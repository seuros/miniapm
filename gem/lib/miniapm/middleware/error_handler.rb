# frozen_string_literal: true

module MiniAPM
  module Middleware
    class ErrorHandler
      def initialize(app)
        @app = app
      end

      def call(env)
        @app.call(env)
      rescue StandardError => e
        report_error(e, env)
        raise
      end

      private

      def report_error(exception, env)
        return unless MiniAPM.enabled?
        return if ignored_exception?(exception)

        MiniAPM.record_error(exception, context: build_context(env))
      end

      def ignored_exception?(exception)
        MiniAPM.configuration.ignored_exceptions.include?(exception.class.name)
      end

      def build_context(env)
        request = ::Rack::Request.new(env) if defined?(::Rack::Request)

        context = {
          request_id: env["action_dispatch.request_id"] || env["HTTP_X_REQUEST_ID"],
          user_id: extract_user_id(env),
          url: build_url(env),
          method: env["REQUEST_METHOD"]
        }

        # Add filtered params
        if request
          context[:params] = filter_params(request.params)
        end

        context.compact
      end

      def extract_user_id(env)
        # Try common patterns for user identification
        # Warden (Devise)
        if env["warden"]
          user = env["warden"].user rescue nil
          return user.id.to_s if user&.respond_to?(:id)
        end

        # Session-based
        if env["rack.session"]
          session = env["rack.session"]
          return session["user_id"].to_s if session["user_id"]
          return session["current_user_id"].to_s if session["current_user_id"]

          # Devise session format
          warden_key = session["warden.user.user.key"]
          if warden_key.is_a?(Array) && warden_key.first.is_a?(Array)
            return warden_key.first.first.to_s
          end
        end

        nil
      rescue StandardError
        nil
      end

      def filter_params(params)
        return nil unless params.is_a?(Hash)
        return nil if params.empty?

        filter_keys = MiniAPM.configuration.filter_parameters

        deep_filter(params, filter_keys)
      end

      def deep_filter(hash, filter_keys)
        hash.each_with_object({}) do |(key, value), result|
          if filter_keys.any? { |f| key_matches?(key, f) }
            result[key] = "[FILTERED]"
          elsif value.is_a?(Hash)
            result[key] = deep_filter(value, filter_keys)
          elsif value.is_a?(Array)
            result[key] = value.map { |v| v.is_a?(Hash) ? deep_filter(v, filter_keys) : v }
          else
            # Truncate long values
            result[key] = truncate_value(value)
          end
        end
      end

      def key_matches?(key, filter)
        case filter
        when Regexp
          key.to_s.match?(filter)
        else
          key.to_s.downcase.include?(filter.to_s.downcase)
        end
      end

      def truncate_value(value)
        str = value.to_s
        str.length > 500 ? str[0, 500] + "..." : str
      end

      def build_url(env)
        scheme = env["rack.url_scheme"] || "http"
        host = env["HTTP_HOST"] || "#{env['SERVER_NAME']}:#{env['SERVER_PORT']}"
        path = env["PATH_INFO"]
        "#{scheme}://#{host}#{path}"
      end
    end
  end
end
