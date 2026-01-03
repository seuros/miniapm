# frozen_string_literal: true

module MiniAPM
  module Instrumentations
    module HTTP
      class Faraday
        class << self
          def install!
            return if @installed
            return unless defined?(::Faraday)

            @installed = true

            # Define the middleware class only when Faraday is available
            define_middleware_class!

            # Register our middleware
            ::Faraday::Middleware.register_middleware(miniapm: middleware_class)

            # Auto-inject into all connections by patching Connection
            ::Faraday::Connection.prepend(ConnectionPatch)

            MiniAPM.logger.debug { "MiniAPM: Faraday instrumentation installed" }
          end

          def installed?
            @installed || false
          end

          def middleware_class
            @middleware_class
          end

          private

          def define_middleware_class!
            @middleware_class = Class.new(::Faraday::Middleware) do
              def call(env)
                return @app.call(env) unless MiniAPM.enabled?
                return @app.call(env) unless MiniAPM::Context.current_trace

                uri = env.url
                http_method = env.method.to_s.upcase

                # Inject trace context
                MiniAPM::Context.inject_into_headers(env.request_headers)

                span = MiniAPM::Span.new(
                  name: "#{http_method} #{uri.host}#{uri.path}",
                  category: :http_client,
                  trace_id: MiniAPM::Context.current_trace_id,
                  parent_span_id: MiniAPM::Context.current_span&.span_id,
                  attributes: {
                    "http.method" => http_method,
                    "http.url" => sanitize_url(uri),
                    "http.host" => uri.host,
                    "net.peer.name" => uri.host,
                    "net.peer.port" => uri.port || (uri.scheme == "https" ? 443 : 80)
                  }
                )

                MiniAPM::Context.with_span(span) do
                  begin
                    response = @app.call(env)

                    span.add_attribute("http.status_code", response.status)

                    if response.status >= 400
                      span.set_error("HTTP #{response.status}")
                    else
                      span.set_ok
                    end

                    response
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

              def sanitize_url(uri)
                port = uri.port || (uri.scheme == "https" ? 443 : 80)
                "#{uri.scheme}://#{uri.host}:#{port}#{uri.path}"
              end
            end
          end
        end

        # Patch to auto-inject middleware
        module ConnectionPatch
          def initialize(url = nil, options = nil, &block)
            super

            middleware_class = MiniAPM::Instrumentations::HTTP::Faraday.middleware_class
            # Add our middleware if not already present
            unless @builder.handlers.any? { |h| h.klass == middleware_class }
              @builder.insert(0, middleware_class)
            end
          end
        end
      end
    end
  end
end

# Installation is handled by the registry, not auto-install
