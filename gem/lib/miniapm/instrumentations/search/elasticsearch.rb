# frozen_string_literal: true

module MiniAPM
  module Instrumentations
    module Search
      class Elasticsearch
        class << self
          def install!
            return if @installed
            return unless defined?(::Elasticsearch::Transport::Client)

            @installed = true
            ::Elasticsearch::Transport::Client.prepend(Patch)

            MiniAPM.logger.debug { "MiniAPM: Elasticsearch instrumentation installed" }
          end

          def installed?
            @installed || false
          end
        end

        module Patch
          def perform_request(method, path, params = {}, body = nil, headers = nil, opts = {})
            return super unless MiniAPM.enabled?
            return super unless MiniAPM::Context.current_trace

            operation = extract_operation(method, path)
            index = extract_index(path)

            span = MiniAPM::Span.new(
              name: "ES #{operation}#{index ? " #{index}" : ""}",
              category: :search,
              trace_id: MiniAPM::Context.current_trace_id,
              parent_span_id: MiniAPM::Context.current_span&.span_id,
              attributes: {
                "db.system" => "elasticsearch",
                "db.operation" => operation,
                "http.method" => method.to_s.upcase,
                "http.url" => path
              }
            )

            span.add_attribute("elasticsearch.index", index) if index

            # Add query body for search operations (truncated)
            if body && %w[search msearch].include?(operation)
              span.add_attribute("db.statement", truncate_body(body))
            end

            MiniAPM::Context.with_span(span) do
              begin
                response = super

                if response
                  span.add_attribute("http.status_code", response.status)
                  span.set_error("ES #{response.status}") if response.status >= 400
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

          def extract_operation(method, path)
            case
            when path.include?("_search")
              "search"
            when path.include?("_msearch")
              "msearch"
            when path.include?("_bulk")
              "bulk"
            when path.include?("_count")
              "count"
            when path.include?("_update")
              "update"
            when path.include?("_delete_by_query")
              "delete_by_query"
            when path.include?("_refresh")
              "refresh"
            when method.to_s.upcase == "GET"
              "get"
            when method.to_s.upcase == "PUT"
              "index"
            when method.to_s.upcase == "POST"
              "index"
            when method.to_s.upcase == "DELETE"
              "delete"
            else
              "query"
            end
          end

          def extract_index(path)
            # Extract index name from path like /my_index/_search
            parts = path.to_s.split("/").reject { |p| p.empty? || p.start_with?("_") }
            parts.first
          end

          def truncate_body(body)
            json = body.is_a?(String) ? body : body.to_json
            json.length > 1000 ? json[0...1000] + "..." : json
          rescue StandardError
            body.to_s[0...1000]
          end
        end
      end
    end
  end
end

# Auto-install when loaded
MiniAPM::Instrumentations::Search::Elasticsearch.install!
