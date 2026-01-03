# frozen_string_literal: true

module MiniAPM
  # Testing utilities for capturing and inspecting spans/errors in tests
  #
  # Usage:
  #   require 'miniapm/testing'
  #
  #   RSpec.describe "MyFeature" do
  #     before { MiniAPM::Testing.enable! }
  #     after { MiniAPM::Testing.disable! }
  #
  #     it "tracks spans" do
  #       perform_action
  #       expect(MiniAPM::Testing.spans).to include(
  #         having_attributes(name: /process_action/)
  #       )
  #     end
  #   end
  #
  module Testing
    class << self
      # Enable test mode - captures spans/errors instead of sending them
      def enable!
        @enabled = true
        @spans = []
        @errors = []
        @mutex = Mutex.new

        # Stub the record methods to capture instead of send
        install_test_hooks!
      end

      # Disable test mode and restore normal behavior
      def disable!
        @enabled = false
        clear!
        uninstall_test_hooks!
      end

      # Check if test mode is enabled
      def enabled?
        @enabled || false
      end

      # Get all captured spans
      def spans
        @mutex.synchronize { @spans.dup }
      end

      # Get all captured errors
      def errors
        @mutex.synchronize { @errors.dup }
      end

      # Alias for spans
      def recorded_spans
        spans
      end

      # Alias for errors
      def recorded_errors
        errors
      end

      # Clear all captured data
      def clear!
        @mutex&.synchronize do
          @spans = []
          @errors = []
        end
      end

      # Find spans matching criteria
      def find_spans(name: nil, category: nil, &block)
        result = spans
        result = result.select { |s| s.name.match?(name) } if name
        result = result.select { |s| s.category == category } if category
        result = result.select(&block) if block_given?
        result
      end

      # Find errors matching criteria
      def find_errors(exception_class: nil, message: nil, &block)
        result = errors
        result = result.select { |e| e.exception_class == exception_class } if exception_class
        result = result.select { |e| e.message.match?(message) } if message
        result = result.select(&block) if block_given?
        result
      end

      # Check if any span matches
      def span_recorded?(name: nil, category: nil)
        find_spans(name: name, category: category).any?
      end

      # Check if any error matches
      def error_recorded?(exception_class: nil, message: nil)
        find_errors(exception_class: exception_class, message: message).any?
      end

      # Record a span (called by test hooks)
      def record_span(span)
        return unless enabled?

        @mutex.synchronize { @spans << span }
      end

      # Record an error (called by test hooks)
      def record_error(error)
        return unless enabled?

        @mutex.synchronize { @errors << error }
      end

      private

      def install_test_hooks!
        # Guard against double installation
        return if @hooks_installed

        # Store original methods
        @original_record_span = MiniAPM.method(:record_span)
        @original_record_error = MiniAPM.method(:record_error)

        # Replace with test versions (suppress warnings)
        testing = self
        original_verbose = $VERBOSE
        begin
          $VERBOSE = nil
          MiniAPM.define_singleton_method(:record_span) do |span|
            testing.record_span(span)
          end

          MiniAPM.define_singleton_method(:record_error) do |exception, context: {}|
            error_event = ErrorEvent.from_exception(exception, context)
            testing.record_error(error_event)
          end
        ensure
          $VERBOSE = original_verbose
        end

        @hooks_installed = true
      end

      def uninstall_test_hooks!
        return unless @hooks_installed

        original_verbose = $VERBOSE
        begin
          $VERBOSE = nil
          MiniAPM.define_singleton_method(:record_span, @original_record_span)
          MiniAPM.define_singleton_method(:record_error, @original_record_error)
        ensure
          $VERBOSE = original_verbose
        end

        @original_record_span = nil
        @original_record_error = nil
        @hooks_installed = false
      end
    end
  end
end

# RSpec integration
if defined?(RSpec)
  RSpec.configure do |config|
    config.before(:each, :miniapm) do
      MiniAPM::Testing.enable!
    end

    config.after(:each, :miniapm) do
      MiniAPM::Testing.disable!
    end
  end
end

# Minitest integration
if defined?(Minitest)
  module MiniAPM
    module Testing
      module MinitestHooks
        def before_setup
          super
          MiniAPM::Testing.enable! if self.class.miniapm_enabled?
        end

        def after_teardown
          MiniAPM::Testing.disable! if self.class.miniapm_enabled?
          super
        end
      end

      module MinitestClassMethods
        def miniapm_enabled?
          @miniapm_enabled || false
        end

        def enable_miniapm!
          @miniapm_enabled = true
        end
      end
    end
  end

  Minitest::Test.prepend(MiniAPM::Testing::MinitestHooks)
  Minitest::Test.extend(MiniAPM::Testing::MinitestClassMethods)
end
