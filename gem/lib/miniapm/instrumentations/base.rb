# frozen_string_literal: true

module MiniAPM
  module Instrumentations
    class Base
      class << self
        def install!
          raise NotImplementedError, "Subclass must implement .install!"
        end

        def installed?
          @installed || false
        end

        protected

        def mark_installed!
          @installed = true
        end

        def subscribe(event_name, &block)
          ActiveSupport::Notifications.subscribe(event_name) do |*args|
            event = ActiveSupport::Notifications::Event.new(*args)
            block.call(event)
          rescue StandardError => e
            MiniAPM.logger.debug { "MiniAPM instrumentation error in #{event_name}: #{e.message}" }
          end
        end

        def create_span_from_event(event, name:, category:, attributes: {})
          return unless MiniAPM.enabled?
          return unless Context.current_trace

          span = Span.new(
            name: name,
            category: category,
            trace_id: Context.current_trace_id,
            parent_span_id: Context.current_span&.span_id,
            attributes: attributes
          )

          # Backfill timing from event
          if event.time && event.end
            span.instance_variable_set(:@start_time, (event.time.to_f * 1_000_000_000).to_i)
            span.instance_variable_set(:@end_time, (event.end.to_f * 1_000_000_000).to_i)
          else
            span.finish
          end

          span
        end

        def record_span(span)
          return unless span

          MiniAPM.record_span(span)
        end
      end
    end
  end
end
