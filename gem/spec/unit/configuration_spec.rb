# frozen_string_literal: true

require "spec_helper"

RSpec.describe MiniAPM::Configuration do
  describe "#initialize" do
    it "sets default values" do
      config = described_class.new

      expect(config.enabled).to be true
      expect(config.auto_start).to be true
      expect(config.batch_size).to eq(100)
      expect(config.flush_interval).to eq(5.0)
      expect(config.max_queue_size).to eq(10_000)
      expect(config.sample_rate).to eq(1.0)
    end

    it "reads endpoint from environment" do
      # Stub specific ENV calls
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:fetch).with("MINI_APM_URL", anything).and_return("http://custom:3000")

      config = described_class.new

      expect(config.endpoint).to eq("http://custom:3000")
    end

    it "sets default ignored exceptions" do
      config = described_class.new

      expect(config.ignored_exceptions).to include("ActionController::RoutingError")
      expect(config.ignored_exceptions).to include("ActiveRecord::RecordNotFound")
    end

    it "sets default filter parameters" do
      config = described_class.new

      expect(config.filter_parameters).to include(:password)
      expect(config.filter_parameters).to include(:api_key)
      expect(config.filter_parameters).to include(:token)
    end

    it "detects Ruby version" do
      config = described_class.new

      expect(config.ruby_version).to eq(RUBY_VERSION)
    end

    it "detects hostname" do
      config = described_class.new

      expect(config.host).not_to be_nil
      expect(config.host).not_to eq("unknown")
    end
  end

  describe "#instrument" do
    it "configures instrumentation settings" do
      config = described_class.new
      config.instrument(:activerecord, enabled: false)

      expect(config.instrumentations.enabled?(:activerecord)).to be false
    end

    it "allows custom options" do
      config = described_class.new
      config.instrument(:activerecord, log_sql: true)

      expect(config.instrumentations[:activerecord][:log_sql]).to be true
    end
  end
end

RSpec.describe MiniAPM::InstrumentationConfig do
  describe "#initialize" do
    it "loads default configuration for all instrumentations" do
      config = described_class.new

      expect(config.enabled?(:rails)).to be true
      expect(config.enabled?(:activerecord)).to be true
      expect(config.enabled?(:net_http)).to be true
    end
  end

  describe "#configure" do
    it "updates existing instrumentation config" do
      config = described_class.new
      config.configure(:activerecord, enabled: false, log_sql: true)

      expect(config.enabled?(:activerecord)).to be false
      expect(config[:activerecord][:log_sql]).to be true
    end

    it "creates new instrumentation config" do
      config = described_class.new
      config.configure(:custom, enabled: true, custom_option: "value")

      expect(config.enabled?(:custom)).to be true
      expect(config[:custom][:custom_option]).to eq("value")
    end

    it "accepts string keys" do
      config = described_class.new
      config.configure("redis", enabled: false)

      expect(config.enabled?(:redis)).to be false
    end
  end

  describe "#[]" do
    it "returns config for known instrumentation" do
      config = described_class.new

      expect(config[:rails]).to eq({ enabled: true })
    end

    it "returns disabled config for unknown instrumentation" do
      config = described_class.new

      expect(config[:unknown]).to eq({ enabled: false })
    end
  end

  describe "#enabled?" do
    it "returns true for enabled instrumentations" do
      config = described_class.new

      expect(config.enabled?(:rails)).to be true
    end

    it "returns false for disabled instrumentations" do
      config = described_class.new
      config.configure(:rails, enabled: false)

      expect(config.enabled?(:rails)).to be false
    end

    it "returns false for unknown instrumentations" do
      config = described_class.new

      expect(config.enabled?(:nonexistent)).to be false
    end
  end

  describe "#options" do
    it "returns all options for instrumentation" do
      config = described_class.new

      expect(config.options(:activerecord)).to eq({ enabled: true, log_sql: false })
    end
  end
end

RSpec.describe "MiniAPM.configure" do
  it "yields configuration block" do
    MiniAPM.configure do |config|
      config.service_name = "test-service"
      config.api_key = "test-key"
    end

    expect(MiniAPM.configuration.service_name).to eq("test-service")
    expect(MiniAPM.configuration.api_key).to eq("test-key")
  end

  it "maintains configuration across calls" do
    MiniAPM.configure do |config|
      config.service_name = "first"
    end

    MiniAPM.configure do |config|
      config.api_key = "second"
    end

    expect(MiniAPM.configuration.service_name).to eq("first")
    expect(MiniAPM.configuration.api_key).to eq("second")
  end
end
