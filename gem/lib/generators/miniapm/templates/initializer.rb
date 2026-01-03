# frozen_string_literal: true

# MiniAPM Configuration
# Documentation: https://miniapm.com/docs
MiniAPM.configure do |config|
  # Required: MiniAPM server endpoint
  config.endpoint = ENV.fetch("MINI_APM_URL", "http://localhost:3000")

  # Required: API key for authentication
  config.api_key = ENV["MINI_APM_API_KEY"]

  # Service identification
  config.service_name = ENV.fetch("MINI_APM_SERVICE_NAME", "<%= Rails.application.class.module_parent_name.underscore.dasherize %>")
  config.environment = Rails.env

  # Optional: Service version for tracking deployments
  # config.service_version = ENV["APP_VERSION"]

  # Optional: Git SHA for deployment tracking
  # config.git_sha = ENV["GIT_SHA"] || ENV["HEROKU_SLUG_COMMIT"]

  # Batching configuration (defaults are usually fine)
  # config.batch_size = 100         # Max spans per batch
  # config.flush_interval = 5.0     # Seconds between flushes
  # config.max_queue_size = 10_000  # Max queued items before dropping

  # Sampling (1.0 = 100%, 0.1 = 10%)
  # Useful for high-traffic applications
  config.sample_rate = Rails.env.production? ? 1.0 : 1.0

  # Enable/disable specific instrumentations
  # config.instrument :activerecord, log_sql: true  # Include SQL in spans
  # config.instrument :redis, enabled: false        # Disable Redis tracing

  # Error tracking configuration
  # Exceptions to ignore (won't be reported)
  config.ignored_exceptions = [
    "ActionController::RoutingError",
    "ActionController::InvalidAuthenticityToken",
    "ActionController::UnknownFormat",
    "ActiveRecord::RecordNotFound"
  ]

  # Parameters to filter from error reports (merged with Rails defaults)
  config.filter_parameters = Rails.application.config.filter_parameters

  # Custom span modification (return false to drop span)
  # config.before_send = ->(span) {
  #   # Add custom attributes
  #   span.add_attribute("custom.attribute", "value")
  #
  #   # Return false to drop this span
  #   # return false if span.name.include?("health_check")
  #
  #   true
  # }

  # Disable in test environment
  config.enabled = !Rails.env.test?
end
