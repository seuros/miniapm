# frozen_string_literal: true

require "thread"

module MiniAPM
  module Transport
    class BatchSender
      SHUTDOWN_TIMEOUT = 5 # seconds to wait for flush on shutdown
      MAX_RETRY_ATTEMPTS = 3
      BASE_RETRY_DELAY = 1.0 # seconds
      MAX_CONCURRENT_SENDS = 4

      class << self
        def start!
          @start_mutex ||= Mutex.new

          @start_mutex.synchronize do
            return if @started

            @started = true
            @shutdown = false

            @queues = {
              span: Queue.new,
              error: Queue.new
            }

            @mutex = Mutex.new
            @batches = { span: [], error: [] }
            @last_flush = Time.now

            # Stats for monitoring
            reset_stats!

            # Bounded thread pool for sending
            @send_queue = Queue.new
            @send_threads = MAX_CONCURRENT_SENDS.times.map do |i|
              Thread.new { send_worker_loop(i) }
            end

            start_worker_thread!
            setup_shutdown_hook!

            MiniAPM.logger.debug { "MiniAPM BatchSender started" }
          end
        end

        def stop!
          @start_mutex ||= Mutex.new

          @start_mutex.synchronize do
            return unless @started

            @shutdown = true

            # Drain queues and flush remaining data
            drain_queues_to_batches!
            flush_all!

            # Wait for worker thread
            @worker_thread&.join(SHUTDOWN_TIMEOUT)

            # Signal send threads to stop and wait
            MAX_CONCURRENT_SENDS.times { @send_queue << :shutdown }
            @send_threads&.each { |t| t.join(SHUTDOWN_TIMEOUT) }

            @started = false

            MiniAPM.logger.debug { "MiniAPM BatchSender stopped" }
          end
        end

        def enqueue(type, item)
          return unless @started

          queue = @queues[type]
          return unless queue

          config = MiniAPM.configuration

          # Drop if queue is full (backpressure)
          if queue.size >= config.max_queue_size
            increment_stat(:dropped, type)
            MiniAPM.logger.warn { "MiniAPM: Queue full, dropping #{type}" }
            return
          end

          queue << item
          increment_stat(:enqueued, type)
        end

        def started?
          @started || false
        end

        # Force flush all pending data (useful for testing)
        def flush!
          return unless @started

          # First, drain queues into batches
          drain_queues_to_batches!

          # Then flush all batches
          flush_all!

          # Wait for send queue to drain
          deadline = Time.now + 5 # 5 second timeout
          while @send_queue&.size&.positive? && Time.now < deadline
            sleep 0.1
          end
        end

        # Get current stats
        def stats
          @mutex.synchronize { @stats.dup }
        end

        # Reset stats
        def reset_stats!
          @mutex.synchronize do
            @stats = {
              enqueued: { span: 0, error: 0 },
              sent: { span: 0, error: 0 },
              dropped: { span: 0, error: 0 },
              failed: { span: 0, error: 0 },
              retries: 0
            }
          end
        end

        private

        def drain_queues_to_batches!
          @queues.each do |type, queue|
            @mutex.synchronize do
              while !queue.empty?
                begin
                  item = queue.pop(true) # non-blocking
                  @batches[type] << item
                rescue ThreadError
                  break
                end
              end
            end
          end
        end

        def increment_stat(stat, type = nil)
          @mutex.synchronize do
            if type
              @stats[stat][type] += 1
            else
              @stats[stat] += 1
            end
          end
        end

        def start_worker_thread!
          @worker_thread = Thread.new do
            Thread.current.name = "miniapm-batcher"
            Thread.current.report_on_exception = false

            until @shutdown
              begin
                process_queues
              rescue StandardError => e
                MiniAPM.logger.error { "MiniAPM worker error: #{e.class}: #{e.message}" }
              end

              sleep 0.1 # Small sleep to prevent busy-waiting
            end
          end
        end

        def send_worker_loop(worker_id)
          Thread.current.name = "miniapm-sender-#{worker_id}"
          Thread.current.report_on_exception = false

          loop do
            work = @send_queue.pop
            break if work == :shutdown

            type, items = work
            send_with_retry(type, items)
          end
        end

        def process_queues
          config = MiniAPM.configuration

          @queues.each do |type, queue|
            # Drain queue into batch
            @mutex.synchronize do
              while !queue.empty? && @batches[type].size < config.batch_size
                begin
                  item = queue.pop(true) # non-blocking
                  @batches[type] << item
                rescue ThreadError
                  break
                end
              end
            end

            # Flush if batch is full or timer expired
            flush_type!(type) if should_flush?(type)
          end
        end

        def should_flush?(type)
          @mutex.synchronize do
            batch = @batches[type]
            return false if batch.empty?

            config = MiniAPM.configuration
            batch.size >= config.batch_size ||
              (Time.now - @last_flush) >= config.flush_interval
          end
        end

        def flush_type!(type)
          items = nil

          @mutex.synchronize do
            batch = @batches[type]
            return if batch.empty?

            items = batch.dup
            batch.clear
            @last_flush = Time.now
          end

          return unless items && !items.empty?

          # Queue for sending (bounded by thread pool)
          @send_queue << [type, items]
        end

        def flush_all!
          @queues.each_key { |type| flush_type!(type) }
        end

        def send_with_retry(type, items)
          attempts = 0

          loop do
            attempts += 1
            result = send_batch(type, items)

            if result[:success]
              @mutex.synchronize { @stats[:sent][type] += items.size }
              return true
            end

            # Don't retry on client errors (4xx)
            if result[:status] && result[:status] >= 400 && result[:status] < 500
              MiniAPM.logger.warn { "MiniAPM: Client error #{result[:status]}, not retrying" }
              increment_stat(:failed, type)
              return false
            end

            # Check if we should retry
            if attempts >= MAX_RETRY_ATTEMPTS
              MiniAPM.logger.error { "MiniAPM: Failed to send #{type} after #{attempts} attempts" }
              increment_stat(:failed, type)
              return false
            end

            # Exponential backoff
            delay = BASE_RETRY_DELAY * (2 ** (attempts - 1))
            delay += rand * delay * 0.1 # Add jitter
            increment_stat(:retries)
            MiniAPM.logger.debug { "MiniAPM: Retrying #{type} in #{delay.round(2)}s (attempt #{attempts})" }
            sleep delay
          end
        end

        def send_batch(type, items)
          case type
          when :span
            Exporters::OTLP.export(items)
          when :error
            Exporters::Errors.export_batch(items)
          end
        rescue StandardError => e
          MiniAPM.logger.error { "MiniAPM send error: #{e.class}: #{e.message}" }
          { success: false, error: e }
        end

        def setup_shutdown_hook!
          at_exit { stop! }
        end
      end
    end
  end
end
