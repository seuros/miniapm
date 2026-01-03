# frozen_string_literal: true

module MiniAPM
  module Middleware
    class Rack
      def initialize(app)
        @app = app
      end

      def call(env)
        return @app.call(env) unless MiniAPM.enabled?

        # Extract incoming trace context from headers
        incoming = Context.extract_from_headers(env)

        # Create trace (with incoming context if present)
        trace = Trace.new(
          trace_id: incoming&.dig(:trace_id),
          sampled: incoming&.dig(:sampled)
        )

        return @app.call(env) unless trace.sampled?

        Context.with_trace(trace) do
          request = ::Rack::Request.new(env) if defined?(::Rack::Request)
          request_method = env["REQUEST_METHOD"]
          request_path = env["PATH_INFO"]
          request_url = build_url(env)

          span = Span.new(
            name: "#{request_method} #{request_path}",
            category: :http_server,
            trace_id: trace.trace_id,
            attributes: build_attributes(env, request)
          )

          Context.with_span(span) do
            begin
              status, headers, body = @app.call(env)

              span.add_attribute("http.status_code", status)
              span.set_error("HTTP #{status}") if status >= 500

              [status, headers, body]
            rescue StandardError => e
              span.record_exception(e)
              raise
            ensure
              span.finish
              MiniAPM.record_span(span)
            end
          end
        end
      end

      private

      def build_attributes(env, request)
        attrs = {
          "http.method" => env["REQUEST_METHOD"],
          "http.url" => build_url(env),
          "http.scheme" => env["rack.url_scheme"] || "http",
          "http.host" => env["HTTP_HOST"] || env["SERVER_NAME"],
          "http.target" => env["PATH_INFO"]
        }

        # Add query string if present (without values for privacy)
        if env["QUERY_STRING"] && !env["QUERY_STRING"].empty?
          attrs["http.query_params"] = env["QUERY_STRING"].split("&").map { |p| p.split("=").first }.join(",")
        end

        # Add user agent if present
        if env["HTTP_USER_AGENT"]
          attrs["http.user_agent"] = env["HTTP_USER_AGENT"]
        end

        # Add request ID if present (Rails sets this)
        request_id = env["action_dispatch.request_id"] || env["HTTP_X_REQUEST_ID"]
        if request_id
          attrs["http.request_id"] = request_id
        end

        # Add client IP
        client_ip = env["HTTP_X_FORWARDED_FOR"]&.split(",")&.first&.strip ||
                    env["HTTP_X_REAL_IP"] ||
                    env["REMOTE_ADDR"]
        if client_ip
          attrs["http.client_ip"] = client_ip
        end

        attrs
      end

      def build_url(env)
        scheme = env["rack.url_scheme"] || "http"
        host = env["HTTP_HOST"] || "#{env['SERVER_NAME']}:#{env['SERVER_PORT']}"
        path = env["PATH_INFO"]
        # Omit query string from URL for privacy
        "#{scheme}://#{host}#{path}"
      end
    end
  end
end
