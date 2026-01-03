# frozen_string_literal: true

require "spec_helper"

RSpec.describe MiniAPM::Trace do
  describe "#initialize" do
    it "generates a trace_id if not provided" do
      trace = described_class.new

      expect(trace.trace_id).to match(/\A[0-9a-f]{32}\z/)
    end

    it "uses provided trace_id" do
      trace = described_class.new(trace_id: "a" * 32)

      expect(trace.trace_id).to eq("a" * 32)
    end

    it "samples by default based on sample_rate" do
      build_test_config(sample_rate: 1.0)
      trace = described_class.new

      expect(trace.sampled?).to be true
    end

    it "respects explicit sampled value" do
      trace = described_class.new(sampled: false)

      expect(trace.sampled?).to be false
    end
  end

  describe "#sampled?" do
    it "returns true when sampled" do
      trace = described_class.new(sampled: true)

      expect(trace.sampled?).to be true
    end

    it "returns false when not sampled" do
      trace = described_class.new(sampled: false)

      expect(trace.sampled?).to be false
    end
  end

  context "with 0% sample rate" do
    before do
      build_test_config(sample_rate: 0.0)
    end

    it "never samples" do
      traces = 10.times.map { described_class.new }

      expect(traces.count(&:sampled?)).to eq(0)
    end
  end

  context "with 100% sample rate" do
    before do
      build_test_config(sample_rate: 1.0)
    end

    it "always samples" do
      traces = 10.times.map { described_class.new }

      expect(traces.count(&:sampled?)).to eq(10)
    end
  end
end
