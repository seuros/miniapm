# frozen_string_literal: true

module MiniAPM
  module Instrumentations
    module HTTP
      class HTTParty
        class << self
          def install!
            return if @installed
            return unless defined?(::HTTParty)

            @installed = true
            ::HTTParty::Request.prepend(Patch)

            MiniAPM.logger.debug { "MiniAPM: HTTParty instrumentation installed" }
          end

          def installed?
            @installed || false
          end
        end

        module Patch
          def perform(&block)
            return super unless MiniAPM.enabled?
            return super unless MiniAPM::Context.current_trace

            uri = self.uri
            http_method = self.http_method.name.split("::").last.upcase

            # Inject trace context into outgoing request
            MiniAPM::Context.inject_into_headers(options[:headers] ||= {})

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
                "net.peer.port" => uri.port
              }
            )

            MiniAPM::Context.with_span(span) do
              begin
                response = super

                if response
                  span.add_attribute("http.status_code", response.code)

                  if response.code >= 400
                    span.set_error("HTTP #{response.code}")
                  else
                    span.set_ok
                  end
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
            "#{uri.scheme}://#{uri.host}:#{uri.port}#{uri.path}"
          end
        end
      end
    end
  end
end

# Installation is handled by the registry, not auto-install
