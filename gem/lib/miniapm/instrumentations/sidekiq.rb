# frozen_string_literal: true

module MiniAPM
  module Instrumentations
    class Sidekiq
      # Keys used to store trace context in job payload
      TRACE_ID_KEY = "_miniapm_trace_id"
      PARENT_SPAN_ID_KEY = "_miniapm_parent_span_id"
      SAMPLED_KEY = "_miniapm_sampled"

      class << self
        def install!
          return if @installed
          return unless defined?(::Sidekiq)

          @installed = true

          ::Sidekiq.configure_server do |config|
            config.server_middleware do |chain|
              chain.add ServerMiddleware
            end
          end

          # Also configure client for enqueue tracking and trace propagation
          ::Sidekiq.configure_client do |config|
            config.client_middleware do |chain|
              chain.add ClientMiddleware
            end
          end

          # For Sidekiq server process, also add client middleware
          # (for jobs that enqueue other jobs)
          ::Sidekiq.configure_server do |config|
            config.client_middleware do |chain|
              chain.add ClientMiddleware
            end
          end

          MiniAPM.logger.debug { "MiniAPM: Sidekiq instrumentation installed" }
        end

        def installed?
          @installed || false
        end
      end

      class ServerMiddleware
        def call(worker, job, queue)
          return yield unless MiniAPM.enabled?

          # Extract trace context from job if present (propagated from enqueue)
          trace_id = job[TRACE_ID_KEY]
          parent_span_id = job[PARENT_SPAN_ID_KEY]
          sampled = job.key?(SAMPLED_KEY) ? job[SAMPLED_KEY] : nil

          # Create trace with propagated context or new trace
          trace = Trace.new(
            trace_id: trace_id,
            sampled: sampled
          )

          # Skip if not sampled
          return yield unless trace.sampled?

          Context.current_trace = trace

          worker_class = worker.class.name
          job_id = job["jid"]

          span = Span.new(
            name: "#{worker_class}.perform",
            category: :job,
            trace_id: trace.trace_id,
            parent_span_id: parent_span_id, # Link to parent if propagated
            attributes: build_attributes(worker_class, job, queue)
          )

          # Add enqueued_at if present
          if job["enqueued_at"]
            span.add_attribute("sidekiq.enqueued_at", job["enqueued_at"])
            # Calculate queue latency
            latency = Time.now.to_f - job["enqueued_at"]
            span.add_attribute("sidekiq.queue_latency_ms", (latency * 1000).round(2))
          end

          # Add wrapped class for ActiveJob
          if job["wrapped"]
            span.add_attribute("sidekiq.wrapped", job["wrapped"])
            span.add_attribute("job.class", job["wrapped"])
          end

          Context.with_span(span) do
            begin
              yield
              span.set_ok
            rescue StandardError => e
              span.record_exception(e)
              MiniAPM.record_error(e, context: {
                job_class: worker_class,
                job_id: job_id,
                queue: queue
              })
              raise
            ensure
              span.finish
              MiniAPM.record_span(span)
            end
          end
        ensure
          Context.clear!
        end

        private

        def build_attributes(worker_class, job, queue)
          {
            "messaging.system" => "sidekiq",
            "messaging.destination.name" => queue,
            "messaging.operation" => "process",
            "sidekiq.job_id" => job["jid"],
            "sidekiq.queue" => queue,
            "sidekiq.retry_count" => job["retry_count"] || 0,
            "sidekiq.created_at" => job["created_at"],
            "job.class" => worker_class
          }
        end
      end

      class ClientMiddleware
        def call(worker_class, job, queue, redis_pool)
          # Always propagate trace context if available
          inject_trace_context(job)

          return yield unless MiniAPM.enabled?
          return yield unless Context.current_trace

          # Create span for enqueue operation
          worker_name = worker_class.is_a?(Class) ? worker_class.name : worker_class.to_s

          span = Span.new(
            name: "#{worker_name}.enqueue",
            category: :job,
            trace_id: Context.current_trace_id,
            parent_span_id: Context.current_span&.span_id,
            attributes: {
              "messaging.system" => "sidekiq",
              "messaging.destination.name" => queue,
              "messaging.operation" => "send",
              "sidekiq.job_id" => job["jid"],
              "job.class" => worker_name
            }
          )

          Context.with_span(span) do
            begin
              result = yield
              span.set_ok
              result
            rescue StandardError => e
              span.record_exception(e)
              raise
            ensure
              span.finish
              MiniAPM.record_span(span)
            end
          end
        end

        private

        def inject_trace_context(job)
          return unless Context.current_trace

          # Store trace context in job payload for propagation
          job[TRACE_ID_KEY] = Context.current_trace_id
          job[PARENT_SPAN_ID_KEY] = Context.current_span&.span_id
          job[SAMPLED_KEY] = Context.current_trace.sampled?
        end
      end
    end
  end
end

# Auto-install when loaded
MiniAPM::Instrumentations::Sidekiq.install!
