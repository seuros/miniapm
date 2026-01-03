# frozen_string_literal: true

require "rails/railtie"

module MiniAPM
  module Instrumentations
    module Rails
      class Railtie < ::Rails::Railtie
        initializer "miniapm.configure_rails_initialization" do |app|
          # Insert middleware at the beginning of the stack
          app.middleware.insert(0, MiniAPM::Middleware::Rack)
          app.middleware.insert(1, MiniAPM::Middleware::ErrorHandler)
        end

        config.after_initialize do
          # Auto-detect Rails version
          MiniAPM.configuration.rails_version ||= ::Rails::VERSION::STRING

          # Auto-detect environment
          MiniAPM.configuration.environment = ::Rails.env.to_s

          # Disable in test by default unless explicitly enabled
          if ::Rails.env.test? && ENV["MINI_APM_ENABLED_IN_TEST"].nil?
            MiniAPM.configuration.enabled = false
          end

          # Use Rails logger if available
          if ::Rails.logger && MiniAPM.configuration.auto_start
            MiniAPM.logger = ::Rails.logger
          end

          # Start MiniAPM if auto_start is enabled
          MiniAPM.start! if MiniAPM.configuration.auto_start
        end
      end
    end
  end
end

# Require middleware
require_relative "../../middleware/rack"
require_relative "../../middleware/error_handler"
