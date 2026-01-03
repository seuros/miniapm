# frozen_string_literal: true

require "logger"

require_relative "miniapm/version"
require_relative "miniapm/configuration"
require_relative "miniapm/context"
require_relative "miniapm/span"
require_relative "miniapm/trace"
require_relative "miniapm/error_event"
require_relative "miniapm/transport/http"
require_relative "miniapm/transport/batch_sender"
require_relative "miniapm/exporters/otlp"
require_relative "miniapm/exporters/errors"
require_relative "miniapm/middleware/rack"
require_relative "miniapm/middleware/error_handler"
require_relative "miniapm/instrumentations/base"
require_relative "miniapm/instrumentations/registry"

module MiniAPM
  class Error < StandardError; end
  class ConfigurationError < Error; end

  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
      start! if configuration.auto_start
    end

    def start!
      return if @started

      configuration.validate!

      @started = true
      Instrumentations::Registry.install_all!
      Transport::BatchSender.start!
      logger.info { "MiniAPM started (service: #{configuration.service_name})" }
    end

    def stop!
      return unless @started

      Transport::BatchSender.stop!
      @started = false
      logger.info { "MiniAPM stopped" }
    end

    def started?
      @started || false
    end

    def enabled?
      configuration.enabled && started?
    end

    def logger
      @logger ||= begin
        log = Logger.new($stdout)
        log.level = Logger::INFO
        log.progname = "MiniAPM"
        log
      end
    end

    attr_writer :logger

    # Create a span with automatic context management
    # Sampling is decided once per trace and inherited by all child spans
    def span(name, category: :internal, attributes: {})
      return yield(nil) unless enabled?

      # Check if we're in an existing trace
      current_trace = Context.current_trace
      parent_span = Context.current_span

      if current_trace
        # We're already in a trace - use its sampled state
        return yield(nil) unless current_trace.sampled?

        span = if parent_span
                 parent_span.create_child(name, category: category, attributes: attributes)
               else
                 Span.new(
                   name: name,
                   category: category,
                   trace_id: current_trace.trace_id,
                   attributes: attributes
                 )
               end
      else
        # Create new trace with sampling decision
        span = Span.new_root(name, category: category, attributes: attributes)

        # new_root creates a trace - check if it's sampled
        return yield(nil) unless Context.current_trace&.sampled?
      end

      Context.with_span(span) do
        yield span
      rescue StandardError => e
        span.record_exception(e)
        raise
      ensure
        span.finish
        record_span(span)
      end
    end

    def record_span(span)
      return unless enabled?
      return unless Context.current_trace&.sampled?

      span = begin
        configuration.before_send&.call(span) || span
      rescue StandardError => e
        logger.error { "MiniAPM before_send callback error: #{e.class}: #{e.message}" }
        span # Return original span if callback fails
      end
      return unless span

      Transport::BatchSender.enqueue(:span, span)
    end

    def record_error(exception, context: {})
      return unless enabled?
      return if ignored_exception?(exception)

      error_event = ErrorEvent.from_exception(exception, context)
      Transport::BatchSender.enqueue(:error, error_event)
    end

    def current_trace_id
      Context.current_trace_id
    end

    def current_span_id
      Context.current_span&.span_id
    end

    def current_span
      Context.current_span
    end

    # Force flush all pending data (useful for testing and graceful shutdown)
    def flush!
      Transport::BatchSender.flush!
    end

    # Get stats about enqueued/sent/dropped data
    def stats
      Transport::BatchSender.stats
    end

    # Check if MiniAPM can connect to the server
    def healthy?
      return false unless enabled?

      result = Transport::HTTP.post(
        "#{configuration.endpoint}/health",
        {},
        headers: { "Authorization" => "Bearer #{configuration.api_key}" }
      )
      result[:success]
    rescue StandardError
      false
    end

    private

    def ignored_exception?(exception)
      configuration.ignored_exceptions.include?(exception.class.name)
    end
  end
end

# Load Rails integration if Rails is present
require_relative "miniapm/instrumentations/rails/railtie" if defined?(Rails::Railtie)
