# frozen_string_literal: true

module MiniAPM
  module Exporters
    class Errors
      class << self
        # Export a single error
        def export(error_event)
          config = MiniAPM.configuration
          return { success: false, error: "No API key" } unless config.api_key

          # Server expects single error payload matching IncomingError struct
          payload = error_event.to_h

          result = Transport::HTTP.post(
            "#{config.endpoint}/ingest/errors",
            payload,
            headers: auth_headers(config)
          )

          if result[:success]
            MiniAPM.logger.debug { "MiniAPM: Reported error" }
          else
            MiniAPM.logger.debug { "MiniAPM: Failed to report error: #{result[:status]}" }
          end

          result
        end

        # Export multiple errors (sends each individually)
        def export_batch(error_events)
          return { success: true } if error_events.empty?

          results = error_events.map { |error| export(error) }

          # Return success if any succeeded
          success_count = results.count { |r| r[:success] }

          {
            success: success_count > 0,
            sent: success_count,
            failed: results.size - success_count,
            status: results.last&.dig(:status)
          }
        end

        private

        def auth_headers(config)
          { "Authorization" => "Bearer #{config.api_key}" }
        end
      end
    end
  end
end
