# frozen_string_literal: true

require "bundler/setup"
require "miniapm"
require "webmock/rspec"
require "vcr"
require "timecop"
require "rack"
require "rack/test"
require "json"

# VCR configuration
VCR.configure do |config|
  config.cassette_library_dir = "spec/cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Allow real connections when recording
  config.allow_http_connections_when_no_cassette = ENV["VCR_RECORD"] == "all"

  # Filter sensitive data
  config.filter_sensitive_data("<API_KEY>") { ENV["MINI_APM_API_KEY"] || "test_api_key" }

  # Record mode for new cassettes
  config.default_cassette_options = {
    record: ENV["VCR_RECORD"] == "all" ? :all : :new_episodes,
    match_requests_on: [:method, :uri]
  }
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.warnings = true

  config.order = :random
  Kernel.srand config.seed

  # Reset MiniAPM state before each test
  config.before(:each) do
    MiniAPM.instance_variable_set(:@configuration, nil)
    MiniAPM.instance_variable_set(:@started, false)
    MiniAPM::Context.clear!
  end

  config.after(:each) do
    MiniAPM.stop! if MiniAPM.started?
  end

  # Include Rack::Test helpers for middleware tests
  config.include Rack::Test::Methods, type: :middleware
end

# Test helpers
module MiniAPMTestHelpers
  def build_test_config(overrides = {})
    MiniAPM.configure do |config|
      config.endpoint = "http://localhost:3000"
      config.api_key = ENV["MINI_APM_API_KEY"] || "test_api_key"
      config.service_name = "test-app"
      config.environment = "test"
      config.auto_start = false
      config.enabled = true
      config.sample_rate = 1.0
      overrides.each { |k, v| config.send("#{k}=", v) }
    end
  end

  def create_test_span(name: "test_span", category: :internal, attributes: {})
    MiniAPM::Span.new(
      name: name,
      category: category,
      attributes: attributes
    )
  end

  def with_test_trace
    trace = MiniAPM::Trace.new
    MiniAPM::Context.current_trace = trace
    yield trace
  ensure
    MiniAPM::Context.clear!
  end

  def capture_spans
    spans = []
    original_record = MiniAPM.method(:record_span)
    MiniAPM.define_singleton_method(:record_span) do |span|
      spans << span
    end
    yield
    spans
  ensure
    MiniAPM.define_singleton_method(:record_span, original_record)
  end
end

RSpec.configure do |config|
  config.include MiniAPMTestHelpers
end
