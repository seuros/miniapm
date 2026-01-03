# frozen_string_literal: true

require "spec_helper"
require "miniapm/testing"

RSpec.describe MiniAPM::Testing do
  before do
    build_test_config
  end

  after do
    described_class.disable! if described_class.enabled?
  end

  describe ".enable!" do
    it "enables test mode" do
      described_class.enable!

      expect(described_class.enabled?).to be true
    end

    it "clears previous data" do
      described_class.enable!
      described_class.record_span(create_test_span)
      described_class.enable!

      expect(described_class.spans).to be_empty
    end
  end

  describe ".disable!" do
    it "disables test mode" do
      described_class.enable!
      described_class.disable!

      expect(described_class.enabled?).to be false
    end

    it "clears captured data" do
      described_class.enable!
      described_class.record_span(create_test_span)
      described_class.disable!

      expect(described_class.spans).to be_empty
    end
  end

  describe ".record_span" do
    before { described_class.enable! }

    it "captures spans" do
      span = create_test_span

      described_class.record_span(span)

      expect(described_class.spans).to include(span)
    end

    it "does nothing when disabled" do
      described_class.disable!
      span = create_test_span

      described_class.record_span(span)

      expect(described_class.spans).to be_empty
    end
  end

  describe ".record_error" do
    before { described_class.enable! }

    it "captures errors" do
      error = MiniAPM::ErrorEvent.new(
        exception_class: "TestError",
        message: "Test message",
        backtrace: []
      )

      described_class.record_error(error)

      expect(described_class.errors).to include(error)
    end
  end

  describe ".spans / .recorded_spans" do
    before { described_class.enable! }

    it "returns captured spans" do
      span1 = create_test_span(name: "span1")
      span2 = create_test_span(name: "span2")

      described_class.record_span(span1)
      described_class.record_span(span2)

      expect(described_class.spans.length).to eq(2)
      expect(described_class.recorded_spans).to eq(described_class.spans)
    end

    it "returns a copy of the array" do
      span = create_test_span

      described_class.record_span(span)
      spans = described_class.spans
      spans.clear

      expect(described_class.spans.length).to eq(1)
    end
  end

  describe ".find_spans" do
    before do
      described_class.enable!

      described_class.record_span(create_test_span(name: "GET /users", category: :http_server))
      described_class.record_span(create_test_span(name: "SELECT users", category: :db))
      described_class.record_span(create_test_span(name: "GET /orders", category: :http_server))
    end

    it "finds spans by name regex" do
      spans = described_class.find_spans(name: /users/)

      expect(spans.length).to eq(2)
    end

    it "finds spans by category" do
      spans = described_class.find_spans(category: :db)

      expect(spans.length).to eq(1)
      expect(spans.first.name).to eq("SELECT users")
    end

    it "accepts a block filter" do
      spans = described_class.find_spans { |s| s.name.start_with?("GET") }

      expect(spans.length).to eq(2)
    end
  end

  describe ".span_recorded?" do
    before do
      described_class.enable!
      described_class.record_span(create_test_span(name: "GET /users", category: :http_server))
    end

    it "returns true when matching span exists" do
      expect(described_class.span_recorded?(name: /users/)).to be true
    end

    it "returns false when no matching span exists" do
      expect(described_class.span_recorded?(name: /orders/)).to be false
    end
  end

  describe ".clear!" do
    before { described_class.enable! }

    it "clears all captured data" do
      described_class.record_span(create_test_span)
      described_class.record_error(MiniAPM::ErrorEvent.new(
        exception_class: "Error",
        message: "Test",
        backtrace: []
      ))

      described_class.clear!

      expect(described_class.spans).to be_empty
      expect(described_class.errors).to be_empty
    end
  end

  describe "integration with MiniAPM.record_span" do
    before { described_class.enable! }

    it "intercepts MiniAPM.record_span calls" do
      span = create_test_span
      MiniAPM.record_span(span)

      expect(described_class.spans).to include(span)
    end
  end
end
