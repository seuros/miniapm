# frozen_string_literal: true

module MiniAPM
  module Instrumentations
    module Redis
      class RedisClient
        class << self
          def install!
            return if @installed
            return unless defined?(::RedisClient)

            @installed = true

            # RedisClient supports middleware registration
            ::RedisClient.register(Middleware)

            MiniAPM.logger.debug { "MiniAPM: redis-client instrumentation installed" }
          end

          def installed?
            @installed || false
          end
        end

        module Middleware
          def call(command, config)
            return super unless MiniAPM.enabled?
            return super unless MiniAPM::Context.current_trace

            operation = command.first.to_s.upcase

            span = MiniAPM::Span.new(
              name: "REDIS #{operation}",
              category: :cache,
              trace_id: MiniAPM::Context.current_trace_id,
              parent_span_id: MiniAPM::Context.current_span&.span_id,
              attributes: {
                "db.system" => "redis",
                "db.operation" => operation,
                "db.redis.database_index" => config.db,
                "net.peer.name" => config.host,
                "net.peer.port" => config.port
              }
            )

            # Add key info for common operations (first arg after command)
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

          def call_pipelined(commands, config)
            return super unless MiniAPM.enabled?
            return super unless MiniAPM::Context.current_trace

            operations = commands.map { |c| c.first.to_s.upcase }.uniq.join(", ")

            span = MiniAPM::Span.new(
              name: "REDIS PIPELINE (#{commands.size} commands)",
              category: :cache,
              trace_id: MiniAPM::Context.current_trace_id,
              parent_span_id: MiniAPM::Context.current_span&.span_id,
              attributes: {
                "db.system" => "redis",
                "db.operation" => "PIPELINE",
                "db.redis.database_index" => config.db,
                "db.redis.pipeline_length" => commands.size,
                "db.redis.operations" => operations,
                "net.peer.name" => config.host,
                "net.peer.port" => config.port
              }
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

          def truncate_key(key)
            key.length > 100 ? key[0...100] + "..." : key
          end
        end
      end
    end
  end
end

# Auto-install when loaded
MiniAPM::Instrumentations::Redis::RedisClient.install!
