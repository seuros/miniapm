# frozen_string_literal: true

require "socket"

module MiniAPM
  class Configuration
    # Core settings
    attr_accessor :endpoint          # MiniAPM server URL
    attr_accessor :api_key           # Bearer token for authentication
    attr_accessor :enabled           # Enable/disable the gem
    attr_accessor :auto_start        # Auto-start on Rails boot

    # Service identification
    attr_accessor :service_name      # e.g., "my-rails-app"
    attr_accessor :service_version   # e.g., "1.2.3"
    attr_accessor :environment       # e.g., "production"

    # Metadata
    attr_accessor :host              # Hostname
    attr_accessor :rails_version     # Auto-detected
    attr_accessor :ruby_version      # Auto-detected
    attr_accessor :git_sha           # Git SHA for deploys

    # Batching settings
    attr_accessor :batch_size        # Max spans per batch
    attr_accessor :flush_interval    # Seconds between flushes
    attr_accessor :max_queue_size    # Max queued items before dropping

    # Instrumentation toggles
    attr_reader :instrumentations

    # Sampling
    attr_accessor :sample_rate       # 0.0 to 1.0

    # Error filtering
    attr_accessor :ignored_exceptions

    # Parameter filtering
    attr_accessor :filter_parameters

    # Callbacks
    attr_accessor :before_send       # Proc to modify/filter spans

    def initialize
      @endpoint = ENV.fetch("MINI_APM_URL", "http://localhost:3000")
      @api_key = ENV["MINI_APM_API_KEY"]
      @enabled = true
      @auto_start = true

      @service_name = ENV.fetch("MINI_APM_SERVICE_NAME", "rails-app")
      @service_version = ENV["MINI_APM_SERVICE_VERSION"]
      @environment = ENV.fetch("RAILS_ENV", ENV.fetch("RACK_ENV", "development"))

      @host = Socket.gethostname rescue "unknown"
      @rails_version = defined?(Rails::VERSION::STRING) ? Rails::VERSION::STRING : nil
      @ruby_version = RUBY_VERSION
      @git_sha = ENV["GIT_SHA"] || ENV["HEROKU_SLUG_COMMIT"] || detect_git_sha

      @batch_size = 100
      @flush_interval = 5.0
      @max_queue_size = 10_000

      @instrumentations = InstrumentationConfig.new

      @sample_rate = 1.0

      @ignored_exceptions = [
        "ActionController::RoutingError",
        "ActionController::InvalidAuthenticityToken",
        "ActionController::UnknownFormat",
        "ActiveRecord::RecordNotFound"
      ]

      @filter_parameters = [:password, :password_confirmation, :token, :secret, :api_key, :access_token]

      @before_send = nil
    end

    def instrument(name, enabled: true, **options)
      @instrumentations.configure(name, enabled: enabled, **options)
    end

    # Validate configuration and raise on errors
    def validate!
      errors = []

      # Validate endpoint
      if @endpoint.nil? || @endpoint.empty?
        errors << "endpoint is required"
      else
        begin
          uri = URI.parse(@endpoint)
          unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
            errors << "endpoint must be an HTTP(S) URL"
          end
        rescue URI::InvalidURIError
          errors << "endpoint is not a valid URL"
        end
      end

      # Validate sample_rate
      unless @sample_rate.is_a?(Numeric) && @sample_rate >= 0.0 && @sample_rate <= 1.0
        errors << "sample_rate must be a number between 0.0 and 1.0"
      end

      # Validate batch settings
      errors << "batch_size must be a positive integer" unless @batch_size.is_a?(Integer) && @batch_size > 0
      errors << "flush_interval must be a positive number" unless @flush_interval.is_a?(Numeric) && @flush_interval > 0
      errors << "max_queue_size must be a positive integer" unless @max_queue_size.is_a?(Integer) && @max_queue_size > 0

      # Warn about missing api_key (not an error, as it might be set later)
      if @api_key.nil? || @api_key.empty?
        MiniAPM.logger.warn { "MiniAPM: api_key is not configured - requests will fail" }
      end

      raise ConfigurationError, "Invalid configuration: #{errors.join(', ')}" if errors.any?

      true
    end

    def valid?
      validate!
      true
    rescue ConfigurationError
      false
    end

    private

    def detect_git_sha
      sha = `git rev-parse HEAD 2>/dev/null`.strip
      sha.empty? ? nil : sha
    rescue StandardError
      nil
    end
  end

  class InstrumentationConfig
    DEFAULTS = {
      rails: { enabled: true },
      activerecord: { enabled: true, log_sql: false },
      activejob: { enabled: true },
      sidekiq: { enabled: true },
      cache: { enabled: true },
      net_http: { enabled: true },
      httparty: { enabled: true },
      faraday: { enabled: true },
      opensearch: { enabled: true },
      elasticsearch: { enabled: true },
      searchkick: { enabled: true },
      redis: { enabled: true },
      redis_client: { enabled: true }
    }.freeze

    def initialize
      @config = DEFAULTS.transform_values(&:dup)
    end

    def configure(name, **options)
      @config[name.to_sym] ||= {}
      @config[name.to_sym].merge!(options)
    end

    def [](name)
      @config[name.to_sym] || { enabled: false }
    end

    def enabled?(name)
      self[name][:enabled]
    end

    def options(name)
      self[name]
    end
  end
end
