# frozen_string_literal: true

module MiniAPM
  module Instrumentations
    module Redis
      class Redis
        class << self
          def install!
            return if @installed
            return unless defined?(::Redis)
            # Skip if redis-client is present (it's the modern replacement)
            return if defined?(::RedisClient)

            @installed = true
            ::Redis::Client.prepend(Patch)

            MiniAPM.logger.debug { "MiniAPM: redis gem instrumentation installed" }
          end

          def installed?
            @installed || false
          end
        end

        module Patch
          def call(command)
            return super unless MiniAPM.enabled?
            return super unless MiniAPM::Context.current_trace

            operation = command.first.to_s.upcase
            conn_info = extract_connection_info

            span = MiniAPM::Span.new(
              name: "REDIS #{operation}",
              category: :cache,
              trace_id: MiniAPM::Context.current_trace_id,
              parent_span_id: MiniAPM::Context.current_span&.span_id,
              attributes: {
                "db.system" => "redis",
                "db.operation" => operation,
                "db.redis.database_index" => conn_info[:db],
                "net.peer.name" => conn_info[:host],
                "net.peer.port" => conn_info[:port]
              }.compact
            )

            # Add key info for common operations
            if command.length > 1 && %w[GET SET DEL INCR DECR EXPIRE TTL EXISTS HGET HSET LPUSH RPUSH].include?(operation)
              key = command[1].to_s
              span.add_attribute("db.redis.key", truncate_key(key))
            end

            MiniAPM::Context.with_span(span) do
              begin
                result = super
                span.set_ok
                result
              rescue StandardError => e
                span.record_exception(e)
                raise
              ensure
                span.finish
                MiniAPM.record_span(span)
              end
            end
          end

          def call_pipeline(pipeline)
            return super unless MiniAPM.enabled?
            return super unless MiniAPM::Context.current_trace

            commands = pipeline.commands
            operations = commands.map { |c| c.first.to_s.upcase }.uniq.join(", ")
            conn_info = extract_connection_info

            span = MiniAPM::Span.new(
              name: "REDIS PIPELINE (#{commands.size} commands)",
              category: :cache,
              trace_id: MiniAPM::Context.current_trace_id,
              parent_span_id: MiniAPM::Context.current_span&.span_id,
              attributes: {
                "db.system" => "redis",
                "db.operation" => "PIPELINE",
                "db.redis.database_index" => conn_info[:db],
                "db.redis.pipeline_length" => commands.size,
                "db.redis.operations" => operations,
                "net.peer.name" => conn_info[:host],
                "net.peer.port" => conn_info[:port]
              }.compact
            )

            MiniAPM::Context.with_span(span) do
              begin
                result = super
                span.set_ok
                result
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

          def extract_connection_info
            # Redis::Client in older redis gem versions has different APIs
            # Try various methods to get connection info safely
            {
              host: (respond_to?(:host) ? host : options[:host]) rescue nil,
              port: (respond_to?(:port) ? port : options[:port]) rescue nil,
              db: (respond_to?(:db) ? db : options[:db]) rescue nil
            }
          end

          def truncate_key(key)
            key.length > 100 ? key[0...100] + "..." : key
          end
        end
      end
    end
  end
end

# Auto-install when loaded
MiniAPM::Instrumentations::Redis::Redis.install!
