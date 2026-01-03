# frozen_string_literal: true

module MiniAPM
  # Fiber-safe context for trace propagation
  # Uses Fiber.[] storage (Ruby 3.2+) with Thread.current fallback
  module Context
    TRACE_KEY = :miniapm_trace
    SPAN_STACK_KEY = :miniapm_span_stack

    class << self
      # Ruby 3.2+ has Fiber.[] for fiber-local storage
      # Fall back to Thread.current for older Ruby (not fiber-safe)
      if Fiber.respond_to?(:[])
        def current_trace
          Fiber[TRACE_KEY]
        end

        def current_trace=(trace)
          Fiber[TRACE_KEY] = trace
        end

        def span_stack
          Fiber[SPAN_STACK_KEY] ||= []
        end

        def span_stack=(stack)
          Fiber[SPAN_STACK_KEY] = stack
        end
      else
        # Fallback for Ruby < 3.2 (not fiber-safe, but thread-safe)
        def current_trace
          Thread.current[TRACE_KEY]
        end

        def current_trace=(trace)
          Thread.current[TRACE_KEY] = trace
        end

        def span_stack
          Thread.current[SPAN_STACK_KEY] ||= []
        end

        def span_stack=(stack)
          Thread.current[SPAN_STACK_KEY] = stack
        end
      end

      def current_trace_id
        current_trace&.trace_id
      end

      def current_span
        span_stack.last
      end

      def push_span(span)
        span_stack.push(span)
      end

      def pop_span
        span_stack.pop
      end

      def with_span(span)
        push_span(span)
        yield span
      ensure
        pop_span
      end

      def with_trace(trace)
        old_trace = current_trace
        old_stack = span_stack

        self.current_trace = trace
        self.span_stack = []

        yield trace
      ensure
        self.current_trace = old_trace
        self.span_stack = old_stack
      end

      def clear!
        self.current_trace = nil
        self.span_stack = nil
      end

      def fiber_safe?
        Fiber.respond_to?(:[])
      end

      # Extract trace context from incoming HTTP headers (W3C Trace Context)
      # Format: 00-{trace_id}-{parent_span_id}-{flags}
      # Example: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
      def extract_from_headers(headers)
        traceparent = headers["traceparent"] ||
                      headers["HTTP_TRACEPARENT"] ||
                      headers["Traceparent"]
        return nil unless traceparent

        parts = traceparent.to_s.split("-")
        return nil unless parts.length == 4
        return nil unless parts[0] == "00" # version check

        trace_id = parts[1]
        parent_span_id = parts[2]
        flags = parts[3].to_i(16)

        # Validate format
        return nil unless trace_id.match?(/\A[0-9a-f]{32}\z/)
        return nil unless parent_span_id.match?(/\A[0-9a-f]{16}\z/)

        {
          trace_id: trace_id,
          parent_span_id: parent_span_id,
          sampled: (flags & 0x01) == 1
        }
      end

      # Inject trace context into outgoing HTTP headers (W3C Trace Context)
      def inject_into_headers(headers)
        return headers unless current_span

        flags = current_trace&.sampled? ? "01" : "00"
        traceparent = format(
          "00-%s-%s-%s",
          current_trace_id,
          current_span.span_id,
          flags
        )

        headers["traceparent"] = traceparent
        headers
      end
    end
  end
end
