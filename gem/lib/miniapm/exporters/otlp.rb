# frozen_string_literal: true

module MiniAPM
  module Exporters
    class OTLP
      class << self
        def export(spans)
          return if spans.empty?

          config = MiniAPM.configuration
          return unless config.api_key

          payload = build_otlp_payload(spans, config)

          result = Transport::HTTP.post(
            "#{config.endpoint}/ingest/v1/traces",
            payload,
            headers: auth_headers(config)
          )

          if result[:success]
            MiniAPM.logger.debug { "MiniAPM: Exported #{spans.size} spans" }
          else
            MiniAPM.logger.debug { "MiniAPM: Failed to export spans: #{result[:status]}" }
          end

          result
        end

        private

        def build_otlp_payload(spans, config)
          {
            "resourceSpans" => [
              {
                "resource" => {
                  "attributes" => resource_attributes(config)
                },
                "scopeSpans" => [
                  {
                    "scope" => {
                      "name" => "miniapm-ruby",
                      "version" => MiniAPM::VERSION
                    },
                    "spans" => spans.map(&:to_otlp)
                  }
                ]
              }
            ]
          }
        end

        def resource_attributes(config)
          attrs = [
            kv("service.name", config.service_name),
            kv("deployment.environment", config.environment)
          ]

          attrs << kv("service.version", config.service_version) if config.service_version
          attrs << kv("host.name", config.host) if config.host
          attrs << kv("telemetry.sdk.name", "miniapm-ruby")
          attrs << kv("telemetry.sdk.version", MiniAPM::VERSION)
          attrs << kv("telemetry.sdk.language", "ruby")

          if config.rails_version
            attrs << kv("rails.version", config.rails_version)
          end

          if config.ruby_version
            attrs << kv("ruby.version", config.ruby_version)
          end

          if config.git_sha
            attrs << kv("git.sha", config.git_sha)
          end

          attrs
        end

        def kv(key, value)
          { "key" => key, "value" => { "stringValue" => value.to_s } }
        end

        def auth_headers(config)
          { "Authorization" => "Bearer #{config.api_key}" }
        end
      end
    end
  end
end
