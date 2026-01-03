# frozen_string_literal: true

module MiniAPM
  module Instrumentations
    class ActiveRecord < Base
      IGNORED_QUERIES = ["SCHEMA", "CACHE"].freeze
      IGNORED_SQL_PATTERNS = /\A\s*(PRAGMA|EXPLAIN|BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i

      class << self
        def install!
          return if installed?
          mark_installed!

          subscribe("sql.active_record") do |event|
            handle_sql(event)
          end
        end

        private

        def handle_sql(event)
          return unless MiniAPM.enabled?
          return unless Context.current_trace

          payload = event.payload

          # Skip schema queries and internal AR queries
          return if IGNORED_QUERIES.include?(payload[:name])
          return if payload[:sql]&.match?(IGNORED_SQL_PATTERNS)
          return if payload[:cached]

          sql = payload[:sql].to_s
          operation = extract_operation(sql)
          table = extract_table(sql)

          name = [operation, table].compact.join(" ")
          name = operation if name.empty?

          attributes = {
            "db.system" => adapter_name(payload),
            "db.operation" => operation
          }

          attributes["db.sql.table"] = table if table

          # Optionally log SQL (configurable, defaults to off)
          if MiniAPM.configuration.instrumentations.options(:activerecord)[:log_sql]
            attributes["db.statement"] = truncate_sql(sql)
          end

          # Add database name if available
          db_name = database_name(payload)
          attributes["db.name"] = db_name if db_name

          # Add connection info
          if payload[:connection_id]
            attributes["db.connection_id"] = payload[:connection_id]
          end

          span = create_span_from_event(
            event,
            name: name,
            category: :db,
            attributes: attributes
          )

          record_span(span)
        end

        def extract_operation(sql)
          sql.strip.split(/\s+/).first&.upcase || "QUERY"
        end

        def extract_table(sql)
          # Match FROM/INTO/UPDATE/JOIN/DELETE FROM table patterns
          patterns = [
            /\bFROM\s+[`"']?(\w+)[`"']?/i,
            /\bINTO\s+[`"']?(\w+)[`"']?/i,
            /\bUPDATE\s+[`"']?(\w+)[`"']?/i,
            /\bJOIN\s+[`"']?(\w+)[`"']?/i,
            /\bDELETE\s+FROM\s+[`"']?(\w+)[`"']?/i
          ]

          patterns.each do |pattern|
            match = sql.match(pattern)
            return match[1] if match
          end

          nil
        end

        def adapter_name(payload)
          if payload[:connection]
            payload[:connection].adapter_name&.downcase
          elsif payload[:connection_id] && defined?(::ActiveRecord::Base)
            ::ActiveRecord::Base.connection.adapter_name.downcase rescue "unknown"
          else
            "unknown"
          end
        rescue StandardError
          "unknown"
        end

        def database_name(payload)
          if payload[:connection]
            payload[:connection].current_database rescue nil
          elsif defined?(::ActiveRecord::Base)
            ::ActiveRecord::Base.connection.current_database rescue nil
          end
        rescue StandardError
          nil
        end

        def truncate_sql(sql, max_length: 2000)
          sql.length > max_length ? sql[0...max_length] + "..." : sql
        end
      end
    end
  end
end

# Auto-install when loaded
MiniAPM::Instrumentations::ActiveRecord.install!
