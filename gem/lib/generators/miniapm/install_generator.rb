# frozen_string_literal: true

require "rails/generators"

module Miniapm
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Creates a MiniAPM initializer file at config/initializers/miniapm.rb"

      def create_initializer_file
        template "initializer.rb", "config/initializers/miniapm.rb"
      end

      def show_readme
        readme "README" if behavior == :invoke
      end

      private

      def readme(path)
        say File.read(File.expand_path(path, self.class.source_root))
      end
    end
  end
end
