# frozen_string_literal: true

module MiniAPM
  module Instrumentations
    class Registry
      INSTRUMENTATIONS = {
        # Rails core (via ActiveSupport::Notifications)
        rails: "miniapm/instrumentations/rails/controller",
        activerecord: "miniapm/instrumentations/activerecord",
        activejob: "miniapm/instrumentations/activejob",
        cache: "miniapm/instrumentations/cache",

        # Background jobs
        sidekiq: "miniapm/instrumentations/sidekiq",

        # HTTP clients
        net_http: "miniapm/instrumentations/http/net_http",
        httparty: "miniapm/instrumentations/http/httparty",
        faraday: "miniapm/instrumentations/http/faraday",

        # Search
        opensearch: "miniapm/instrumentations/search/opensearch",
        elasticsearch: "miniapm/instrumentations/search/elasticsearch",
        searchkick: "miniapm/instrumentations/search/searchkick",

        # Redis
        redis_client: "miniapm/instrumentations/redis/redis_client",
        redis: "miniapm/instrumentations/redis/redis"
      }.freeze

      class << self
        def install_all!
          INSTRUMENTATIONS.each do |name, path|
            next unless should_install?(name)

            begin
              require_relative path.sub("miniapm/instrumentations/", "")
              MiniAPM.logger.debug { "MiniAPM: Installed #{name} instrumentation" }
            rescue LoadError => e
              MiniAPM.logger.debug { "MiniAPM: Skipped #{name} (dependency not available: #{e.message})" }
            rescue StandardError => e
              MiniAPM.logger.warn { "MiniAPM: Failed to install #{name}: #{e.message}" }
            end
          end
        end

        private

        def should_install?(name)
          MiniAPM.configuration.instrumentations.enabled?(name) && gem_present?(name)
        end

        def gem_present?(name)
          result = case name
          when :rails
            defined?(Rails) && defined?(ActionController)
          when :activerecord
            defined?(ActiveRecord::Base) && defined?(ActiveSupport::Notifications)
          when :activejob
            defined?(ActiveJob::Base) && defined?(ActiveSupport::Notifications)
          when :sidekiq
            defined?(Sidekiq)
          when :cache
            defined?(ActiveSupport::Cache::Store)
          when :net_http
            defined?(Net::HTTP)
          when :httparty
            defined?(HTTParty)
          when :faraday
            defined?(Faraday)
          when :opensearch
            defined?(OpenSearch::Client)
          when :elasticsearch
            defined?(Elasticsearch::Client)
          when :searchkick
            defined?(Searchkick)
          when :redis_client
            defined?(RedisClient)
          when :redis
            defined?(Redis) && !defined?(RedisClient)
          else
            false
          end
          # Convert to boolean (defined? returns string or nil)
          !!result
        end
      end
    end
  end
end
