# frozen_string_literal: true

module MiniAPM
  module Instrumentations
    module Search
      class Searchkick < Base
        class << self
          def install!
            return if installed?
            return unless defined?(::Searchkick)

            mark_installed!

            # Searchkick uses ActiveSupport::Notifications
            subscribe("search.searchkick") do |event|
              handle_search(event)
            end

            subscribe("request.searchkick") do |event|
              handle_request(event)
            end

            subscribe("reindex.searchkick") do |event|
              handle_reindex(event)
            end

            MiniAPM.logger.debug { "MiniAPM: Searchkick instrumentation installed" }
          end

          private

          def handle_search(event)
            return unless MiniAPM.enabled?
            return unless Context.current_trace

            payload = event.payload
            model_name = payload[:name] || "unknown"

            attributes = {
              "db.system" => "elasticsearch",
              "db.operation" => "search",
              "searchkick.model" => model_name
            }

            # Add query info (truncated for privacy)
            if payload[:query]
              query_str = payload[:query].to_s
              attributes["searchkick.query"] = query_str.length > 500 ? query_str[0...500] + "..." : query_str
            end

            # Add body for debugging
            if payload[:body]
              body_str = payload[:body].is_a?(String) ? payload[:body] : payload[:body].to_json
              attributes["db.statement"] = body_str.length > 1000 ? body_str[0...1000] + "..." : body_str
            end

            span = create_span_from_event(
              event,
              name: "searchkick #{model_name}",
              category: :search,
              attributes: attributes
            )

            record_span(span)
          end

          def handle_request(event)
            # Lower-level ES/OS requests from Searchkick
            return unless MiniAPM.enabled?
            return unless Context.current_trace

            payload = event.payload

            attributes = {
              "db.system" => "elasticsearch",
              "http.method" => payload[:method]&.to_s&.upcase,
              "http.url" => payload[:path]
            }

            span = create_span_from_event(
              event,
              name: "searchkick #{payload[:method]} #{payload[:path]}",
              category: :search,
              attributes: attributes
            )

            record_span(span)
          end

          def handle_reindex(event)
            return unless MiniAPM.enabled?
            return unless Context.current_trace

            payload = event.payload
            model_name = payload[:name] || "unknown"

            attributes = {
              "db.system" => "elasticsearch",
              "db.operation" => "reindex",
              "searchkick.model" => model_name
            }

            span = create_span_from_event(
              event,
              name: "searchkick reindex #{model_name}",
              category: :search,
              attributes: attributes
            )

            record_span(span)
          end
        end
      end
    end
  end
end

# Auto-install when loaded
MiniAPM::Instrumentations::Search::Searchkick.install!
