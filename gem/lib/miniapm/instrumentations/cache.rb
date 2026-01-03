# frozen_string_literal: true

module MiniAPM
  module Instrumentations
    class Cache < Base
      EVENTS = %w[
        cache_read.active_support
        cache_write.active_support
        cache_delete.active_support
        cache_exist?.active_support
        cache_fetch_hit.active_support
        cache_generate.active_support
        cache_increment.active_support
        cache_decrement.active_support
      ].freeze

      # Minimum duration to record (skip very fast operations)
      MIN_DURATION_MS = 0.5

      class << self
        def install!
          return if installed?
          mark_installed!

          EVENTS.each do |event_name|
            subscribe(event_name) do |event|
              handle_cache_event(event)
            end
          end
        end

        private

        def handle_cache_event(event)
          return unless MiniAPM.enabled?
          return unless Context.current_trace

          # Skip very fast cache operations to reduce noise
          return if event.duration && event.duration < MIN_DURATION_MS

          payload = event.payload
          operation = event.name.sub("cache_", "").sub(".active_support", "")
          key = payload[:key]

          attributes = {
            "cache.operation" => operation,
            "cache.key" => truncate_key(key)
          }

          # Add hit/miss info
          if payload.key?(:hit)
            attributes["cache.hit"] = payload[:hit]
          end

          # Add store class if available
          if payload[:store]
            attributes["cache.store"] = payload[:store].to_s
          end

          # Add super_operation for fetch
          if payload[:super_operation]
            attributes["cache.super_operation"] = payload[:super_operation].to_s
          end

          span = create_span_from_event(
            event,
            name: "cache #{operation}",
            category: :cache,
            attributes: attributes
          )

          record_span(span)
        end

        def truncate_key(key)
          key_str = key.to_s
          key_str.length > 200 ? key_str[0, 200] + "..." : key_str
        end
      end
    end
  end
end

# Auto-install when loaded
MiniAPM::Instrumentations::Cache.install!
