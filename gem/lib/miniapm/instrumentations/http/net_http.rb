# frozen_string_literal: true

module MiniAPM
  module Instrumentations
    module HTTP
      class NetHTTP
        class << self
          def install!
            return if @installed
            return unless defined?(::Net::HTTP)

            @installed = true
            ::Net::HTTP.prepend(Patch)

            MiniAPM.logger.debug { "MiniAPM: Net::HTTP instrumentation installed" }
          end

          def installed?
            @installed || false
          end
        end

        module Patch
          def request(req, body = nil, &block)
            return super unless MiniAPM.enabled?
            return super unless MiniAPM::Context.current_trace

            # Skip if this is MiniAPM's own request
            return super if req["User-Agent"]&.include?("miniapm-ruby")

            uri = build_uri(req)

            # Inject trace context into outgoing request
            MiniAPM::Context.inject_into_headers(req)

            span = MiniAPM::Span.new(
              name: "#{req.method} #{uri.host}#{uri.path}",
              category: :http_client,
              trace_id: MiniAPM::Context.current_trace_id,
              parent_span_id: MiniAPM::Context.current_span&.span_id,
              attributes: {
                "http.method" => req.method,
                "http.url" => sanitize_url(uri),
                "http.host" => uri.host,
                "net.peer.name" => uri.host,
                "net.peer.port" => uri.port
              }
            )

            MiniAPM::Context.with_span(span) do
              begin
                response = super

                span.add_attribute("http.status_code", response.code.to_i)
                span.add_attribute("http.response_content_length", response["content-length"].to_i) if response["content-length"]

                if response.code.to_i >= 400
                  span.set_error("HTTP #{response.code}")
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

          def build_uri(req)
            scheme = use_ssl? ? "https" : "http"
            host = address
            port_str = (use_ssl? && port == 443) || (!use_ssl? && port == 80) ? "" : ":#{port}"

            path = req.path || "/"
            path = "/" + path unless path.start_with?("/")

            URI.parse("#{scheme}://#{host}#{port_str}#{path}")
          rescue StandardError
            URI.parse("http://#{address}:#{port}#{req.path}")
          end

          def sanitize_url(uri)
            # Remove query params for privacy
            "#{uri.scheme}://#{uri.host}:#{uri.port}#{uri.path}"
          end
        end
      end
    end
  end
end

# Installation is handled by the registry, not auto-install
