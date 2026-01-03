# frozen_string_literal: true

require "spec_helper"

RSpec.describe MiniAPM::Instrumentations::Registry do
  before do
    build_test_config
  end

  describe "INSTRUMENTATIONS" do
    it "includes all expected instrumentations" do
      expected = %i[
        rails activerecord activejob cache
        sidekiq
        net_http httparty faraday
        opensearch elasticsearch searchkick
        redis_client redis
      ]

      expect(described_class::INSTRUMENTATIONS.keys).to match_array(expected)
    end

    it "maps to file paths" do
      described_class::INSTRUMENTATIONS.each do |name, path|
        expect(path).to be_a(String)
        expect(path).to start_with("miniapm/instrumentations/")
      end
    end
  end

  describe ".install_all!" do
    it "attempts to install enabled instrumentations" do
      # Net::HTTP should be available in Ruby stdlib
      expect { described_class.install_all! }.not_to raise_error
    end

    it "skips disabled instrumentations" do
      MiniAPM.configuration.instrument(:net_http, enabled: false)

      # This should not raise even though we're skipping net_http
      expect { described_class.install_all! }.not_to raise_error
    end
  end

  describe "gem detection" do
    # These tests verify the gem detection logic without actually
    # loading the gems

    it "detects Net::HTTP" do
      # Net::HTTP is always available in Ruby
      result = described_class.send(:gem_present?, :net_http)
      expect(result).to be true
    end

    it "returns false for unavailable gems" do
      # Unless explicitly loaded, these should return false
      result = described_class.send(:gem_present?, :sidekiq)
      expect(result).to be(defined?(Sidekiq) ? true : false)
    end

    it "returns false for unknown instrumentations" do
      result = described_class.send(:gem_present?, :unknown_gem)
      expect(result).to be false
    end
  end
end
