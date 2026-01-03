# frozen_string_literal: true

require "spec_helper"

RSpec.describe MiniAPM::Span do
  describe "#initialize" do
    it "creates a span with required attributes" do
      span = described_class.new(name: "test_span", category: :internal)

      expect(span.name).to eq("test_span")
      expect(span.category).to eq(:internal)
      expect(span.trace_id).to match(/\A[0-9a-f]{32}\z/)
      expect(span.span_id).to match(/\A[0-9a-f]{16}\z/)
      expect(span.parent_span_id).to be_nil
      expect(span.start_time).to be_a(Integer)
      expect(span.end_time).to be_nil
    end

    it "accepts custom trace_id and parent_span_id" do
      span = described_class.new(
        name: "child_span",
        category: :db,
        trace_id: "a" * 32,
        parent_span_id: "b" * 16
      )

      expect(span.trace_id).to eq("a" * 32)
      expect(span.parent_span_id).to eq("b" * 16)
    end

    it "accepts and stores attributes" do
      span = described_class.new(
        name: "test",
        category: :http_client,
        attributes: { "http.method" => "GET", count: 42 }
      )

      expect(span.attributes).to eq({
        "http.method" => "GET",
        "count" => 42
      })
    end

    it "maps categories to correct OTLP kinds" do
      test_cases = {
        http_server: 2,  # SERVER
        http_client: 3,  # CLIENT
        db: 3,           # CLIENT
        view: 1,         # INTERNAL
        search: 3,       # CLIENT
        job: 5,          # CONSUMER
        cache: 1,        # INTERNAL
        internal: 1      # INTERNAL
      }

      test_cases.each do |category, expected_kind|
        span = described_class.new(name: "test", category: category)
        expect(span.kind).to eq(expected_kind), "Expected #{category} to have kind #{expected_kind}, got #{span.kind}"
      end
    end
  end

  describe ".new_root" do
    it "creates a root span with a new trace" do
      span = described_class.new_root("GET /users", category: :http_server)

      expect(span.name).to eq("GET /users")
      expect(span.category).to eq(:http_server)
      expect(span.root?).to be true
      expect(MiniAPM::Context.current_trace).not_to be_nil
      expect(MiniAPM::Context.current_trace.trace_id).to eq(span.trace_id)
    end
  end

  describe "#create_child" do
    it "creates a child span with same trace_id" do
      parent = described_class.new(name: "parent", category: :http_server)
      child = parent.create_child("child", category: :db)

      expect(child.trace_id).to eq(parent.trace_id)
      expect(child.parent_span_id).to eq(parent.span_id)
      expect(child.root?).to be false
    end

    it "passes attributes to child" do
      parent = described_class.new(name: "parent", category: :http_server)
      child = parent.create_child("child", category: :db, attributes: { "db.system" => "postgresql" })

      expect(child.attributes).to eq({ "db.system" => "postgresql" })
    end
  end

  describe "#finish" do
    it "sets the end_time" do
      span = described_class.new(name: "test", category: :internal)
      expect(span.end_time).to be_nil

      span.finish

      expect(span.end_time).to be_a(Integer)
      expect(span.end_time).to be >= span.start_time
    end
  end

  describe "#duration_ms" do
    it "calculates duration in milliseconds" do
      span = described_class.new(name: "test", category: :internal)
      sleep 0.01 # 10ms
      span.finish

      expect(span.duration_ms).to be >= 10
      expect(span.duration_ms).to be < 100
    end
  end

  describe "#add_attribute" do
    it "adds an attribute to the span" do
      span = described_class.new(name: "test", category: :internal)
      span.add_attribute("custom.key", "custom_value")

      expect(span.attributes["custom.key"]).to eq("custom_value")
    end

    it "converts symbol keys to strings" do
      span = described_class.new(name: "test", category: :internal)
      span.add_attribute(:symbol_key, "value")

      expect(span.attributes["symbol_key"]).to eq("value")
    end
  end

  describe "#add_event" do
    it "adds an event with timestamp" do
      span = described_class.new(name: "test", category: :internal)
      span.add_event("custom_event", attributes: { key: "value" })

      expect(span.events.size).to eq(1)
      expect(span.events.first[:name]).to eq("custom_event")
      expect(span.events.first[:time_unix_nano]).to be_a(Integer)
      expect(span.events.first[:attributes]).to eq({ "key" => "value" })
    end
  end

  describe "#record_exception" do
    it "records an exception as an event" do
      span = described_class.new(name: "test", category: :internal)
      error = StandardError.new("Something went wrong")
      error.set_backtrace(["line1", "line2", "line3"])

      span.record_exception(error)

      expect(span.status_code).to eq(MiniAPM::Span::STATUS_ERROR)
      expect(span.status_message).to eq("Something went wrong")
      expect(span.events.size).to eq(1)
      expect(span.events.first[:name]).to eq("exception")
      expect(span.events.first[:attributes]["exception.type"]).to eq("StandardError")
      expect(span.events.first[:attributes]["exception.message"]).to eq("Something went wrong")
      expect(span.events.first[:attributes]["exception.stacktrace"]).to include("line1")
    end
  end

  describe "#set_error" do
    it "sets the span status to error" do
      span = described_class.new(name: "test", category: :internal)
      span.set_error("HTTP 500")

      expect(span.status_code).to eq(MiniAPM::Span::STATUS_ERROR)
      expect(span.status_message).to eq("HTTP 500")
      expect(span.error?).to be true
    end
  end

  describe "#set_ok" do
    it "sets the span status to OK" do
      span = described_class.new(name: "test", category: :internal)
      span.set_ok

      expect(span.status_code).to eq(MiniAPM::Span::STATUS_OK)
      expect(span.error?).to be false
    end
  end

  describe "#to_otlp" do
    it "produces valid OTLP JSON format" do
      span = described_class.new(
        name: "GET /users",
        category: :http_server,
        attributes: { "http.method" => "GET", "http.status_code" => 200 }
      )
      span.finish

      otlp = span.to_otlp

      expect(otlp["traceId"]).to match(/\A[0-9a-f]{32}\z/)
      expect(otlp["spanId"]).to match(/\A[0-9a-f]{16}\z/)
      expect(otlp["name"]).to eq("GET /users")
      expect(otlp["kind"]).to eq(2) # SERVER
      expect(otlp["startTimeUnixNano"]).to be_a(String)
      expect(otlp["endTimeUnixNano"]).to be_a(String)
      expect(otlp["status"]).to eq({ "code" => 0 })
    end

    it "includes parentSpanId when present" do
      span = described_class.new(
        name: "child",
        category: :db,
        parent_span_id: "abcd1234abcd1234"
      )
      span.finish

      otlp = span.to_otlp

      expect(otlp["parentSpanId"]).to eq("abcd1234abcd1234")
    end

    it "converts attributes to OTLP format" do
      span = described_class.new(
        name: "test",
        category: :internal,
        attributes: {
          "string" => "value",
          "int" => 42,
          "float" => 3.14,
          "bool" => true,
          "array" => ["a", "b"]
        }
      )
      span.finish

      otlp = span.to_otlp

      expect(otlp["attributes"]).to include(
        { "key" => "string", "value" => { "stringValue" => "value" } },
        { "key" => "int", "value" => { "intValue" => "42" } },
        { "key" => "float", "value" => { "doubleValue" => 3.14 } },
        { "key" => "bool", "value" => { "boolValue" => true } }
      )
    end

    it "includes events when present" do
      span = described_class.new(name: "test", category: :internal)
      span.add_event("test_event", attributes: { key: "value" })
      span.finish

      otlp = span.to_otlp

      expect(otlp["events"]).to be_an(Array)
      expect(otlp["events"].first["name"]).to eq("test_event")
    end

    it "includes status message when present" do
      span = described_class.new(name: "test", category: :internal)
      span.set_error("Something went wrong")
      span.finish

      otlp = span.to_otlp

      expect(otlp["status"]["code"]).to eq(2)
      expect(otlp["status"]["message"]).to eq("Something went wrong")
    end
  end
end
