# frozen_string_literal: true

module MiniAPM
  module Instrumentations
    class ActiveJob < Base
      # Keys for trace context in job metadata
      TRACE_ID_KEY = "_miniapm_trace_id"
      PARENT_SPAN_ID_KEY = "_miniapm_parent_span_id"
      SAMPLED_KEY = "_miniapm_sampled"

      class << self
        def install!
          return if installed?
          mark_installed!

          # Install the job extension for trace propagation
          install_job_extension!

          # Subscribe to notifications for metrics/events
          subscribe("perform.active_job") do |event|
            handle_perform(event)
          end

          subscribe("enqueue.active_job") do |event|
            handle_enqueue(event)
          end

          subscribe("enqueue_at.active_job") do |event|
            handle_enqueue(event)
          end

          subscribe("discard.active_job") do |event|
            handle_discard(event)
          end

          subscribe("retry_stopped.active_job") do |event|
            handle_retry_stopped(event)
          end
        end

        private

        def install_job_extension!
          return unless defined?(::ActiveJob::Base)

          ::ActiveJob::Base.include(JobExtension)
        end

        def handle_perform(event)
          # Performance tracking is handled by JobExtension#perform
          # This is just for additional metadata
        end

        def handle_enqueue(event)
          return unless MiniAPM.enabled?
          return unless Context.current_trace

          job = event.payload[:job]

          span = create_span_from_event(
            event,
            name: "#{job.class.name}.enqueue",
            category: :job,
            attributes: {
              "messaging.system" => queue_adapter_name(job),
              "messaging.destination.name" => job.queue_name,
              "messaging.operation" => "send",
              "job.id" => job.job_id,
              "job.class" => job.class.name
            }
          )

          record_span(span)
        end

        def handle_discard(event)
          return unless MiniAPM.enabled?

          job = event.payload[:job]
          error = event.payload[:error]

          if error
            MiniAPM.record_error(error, context: {
              job_class: job.class.name,
              job_id: job.job_id,
              queue: job.queue_name,
              discarded: true
            })
          end
        end

        def handle_retry_stopped(event)
          return unless MiniAPM.enabled?

          job = event.payload[:job]
          error = event.payload[:error]

          if error
            MiniAPM.record_error(error, context: {
              job_class: job.class.name,
              job_id: job.job_id,
              queue: job.queue_name,
              retry_stopped: true,
              executions: job.executions
            })
          end
        end

        def queue_adapter_name(job)
          adapter = job.class.queue_adapter
          adapter_class = adapter.is_a?(Class) ? adapter : adapter.class

          case adapter_class.name
          when /SolidQueue/
            "solid_queue"
          when /Sidekiq/
            "sidekiq"
          when /Async/
            "async"
          when /Inline/
            "inline"
          when /Delayed/
            "delayed_job"
          when /Resque/
            "resque"
          when /Sneakers/
            "sneakers"
          when /Sucker/
            "sucker_punch"
          when /Test/
            "test"
          else
            adapter_class.name.to_s.split("::").last.to_s.gsub(/Adapter$/, "").downcase
          end
        rescue StandardError
          "unknown"
        end
      end

      # Extension module included in ActiveJob::Base
      module JobExtension
        extend ActiveSupport::Concern

        included do
          # Serialize trace context before enqueueing
          before_enqueue do |job|
            if MiniAPM::Context.current_trace
              job.miniapm_trace_id = MiniAPM::Context.current_trace_id
              job.miniapm_parent_span_id = MiniAPM::Context.current_span&.span_id
              job.miniapm_sampled = MiniAPM::Context.current_trace.sampled?
            end
          end

          # Wrap perform with tracing
          around_perform do |job, block|
            if MiniAPM.enabled?
              job.perform_with_tracing(&block)
            else
              block.call
            end
          end
        end

        # Accessors for trace context stored in job metadata
        def miniapm_trace_id
          @miniapm_trace_id
        end

        def miniapm_trace_id=(value)
          @miniapm_trace_id = value
        end

        def miniapm_parent_span_id
          @miniapm_parent_span_id
        end

        def miniapm_parent_span_id=(value)
          @miniapm_parent_span_id = value
        end

        def miniapm_sampled
          @miniapm_sampled
        end

        def miniapm_sampled=(value)
          @miniapm_sampled = value
        end

        # Override serialize to include trace context
        def serialize
          super.merge(
            TRACE_ID_KEY => miniapm_trace_id,
            PARENT_SPAN_ID_KEY => miniapm_parent_span_id,
            SAMPLED_KEY => miniapm_sampled
          ).compact
        end

        # Override deserialize to restore trace context
        def deserialize(job_data)
          super
          self.miniapm_trace_id = job_data[TRACE_ID_KEY]
          self.miniapm_parent_span_id = job_data[PARENT_SPAN_ID_KEY]
          self.miniapm_sampled = job_data[SAMPLED_KEY]
        end

        def perform_with_tracing
          # Create trace with propagated context or new trace
          trace = MiniAPM::Trace.new(
            trace_id: miniapm_trace_id,
            sampled: miniapm_sampled
          )

          # Skip tracing if not sampled
          return yield unless trace.sampled?

          MiniAPM::Context.current_trace = trace

          span = MiniAPM::Span.new(
            name: "#{self.class.name}.perform",
            category: :job,
            trace_id: trace.trace_id,
            parent_span_id: miniapm_parent_span_id,
            attributes: build_job_attributes
          )

          MiniAPM::Context.with_span(span) do
            begin
              yield
              span.set_ok
            rescue StandardError => e
              span.record_exception(e)
              MiniAPM.record_error(e, context: {
                job_class: self.class.name,
                job_id: job_id,
                queue: queue_name
              })
              raise
            ensure
              span.finish
              MiniAPM.record_span(span)
            end
          end
        ensure
          MiniAPM::Context.clear!
        end

        private

        def build_job_attributes
          attrs = {
            "messaging.system" => MiniAPM::Instrumentations::ActiveJob.send(:queue_adapter_name, self),
            "messaging.destination.name" => queue_name,
            "messaging.operation" => "process",
            "job.id" => job_id,
            "job.class" => self.class.name,
            "job.queue" => queue_name,
            "job.executions" => executions
          }

          attrs["job.priority"] = priority if priority
          attrs["job.scheduled_at"] = scheduled_at.iso8601 if scheduled_at

          attrs
        end
      end
    end
  end
end

# Auto-install when loaded
MiniAPM::Instrumentations::ActiveJob.install!
