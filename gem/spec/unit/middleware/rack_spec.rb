# frozen_string_literal: true

require "spec_helper"

RSpec.describe MiniAPM::Middleware::Rack do
  include Rack::Test::Methods

  let(:inner_app) do
    lambda do |env|
      [200, { "Content-Type" => "text/plain" }, ["OK"]]
    end
  end

  let(:app) { described_class.new(inner_app) }

  before do
    build_test_config
    MiniAPM.start!
    stub_request(:post, "http://localhost:3000/ingest/v1/traces").to_return(status: 200)
  end

  after do
    MiniAPM.stop!
  end

  describe "#call" do
    it "passes request through to app" do
      get "/test"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to eq("OK")
    end

    it "creates a root span for the request" do
      spans = capture_spans do
        get "/test"
      end

      expect(spans.length).to eq(1)
      expect(spans.first.name).to eq("GET /test")
      expect(spans.first.category).to eq(:http_server)
    end

    it "sets span attributes from request" do
      spans = capture_spans do
        get "/users", {}, {
          "HTTP_HOST" => "example.com",
          "HTTP_USER_AGENT" => "TestAgent/1.0"
        }
      end

      span = spans.first
      expect(span.attributes["http.method"]).to eq("GET")
      expect(span.attributes["http.host"]).to eq("example.com")
      expect(span.attributes["http.target"]).to eq("/users")
      expect(span.attributes["http.user_agent"]).to eq("TestAgent/1.0")
    end

    it "records HTTP status code" do
      error_app = lambda { |_env| [500, {}, ["Error"]] }
      app = described_class.new(error_app)
      rack_app = app

      spans = capture_spans do
        request = Rack::MockRequest.new(rack_app)
        request.get("/test")
      end

      span = spans.first
      expect(span.attributes["http.status_code"]).to eq(500)
      expect(span.error?).to be true
    end

    it "records exceptions and re-raises them" do
      error_app = lambda { |_env| raise "Test error" }
      app = described_class.new(error_app)
      rack_app = app

      spans = []
      original_record = MiniAPM.method(:record_span)
      MiniAPM.define_singleton_method(:record_span) do |span|
        spans << span
      end

      begin
        expect {
          request = Rack::MockRequest.new(rack_app)
          request.get("/test")
        }.to raise_error("Test error")
      ensure
        MiniAPM.define_singleton_method(:record_span, original_record)
      end

      span = spans.first
      expect(span).not_to be_nil
      expect(span.error?).to be true
      expect(span.events.first[:name]).to eq("exception")
    end

    it "finishes span after request" do
      spans = capture_spans do
        get "/test"
      end

      span = spans.first
      expect(span.end_time).not_to be_nil
    end

    it "skips when MiniAPM is disabled" do
      MiniAPM.configuration.enabled = false

      spans = capture_spans do
        get "/test"
      end

      expect(spans).to be_empty
    end

    it "extracts trace context from headers" do
      trace_id = "4bf92f3577b34da6a3ce929d0e0e4736"
      parent_span_id = "00f067aa0ba902b7"

      spans = capture_spans do
        get "/test", {}, {
          "HTTP_TRACEPARENT" => "00-#{trace_id}-#{parent_span_id}-01"
        }
      end

      span = spans.first
      expect(span.trace_id).to eq(trace_id)
    end

    it "skips unsampled requests" do
      build_test_config(sample_rate: 0.0)

      spans = capture_spans do
        get "/test"
      end

      expect(spans).to be_empty
    end

    it "extracts query parameter names without values" do
      spans = capture_spans do
        get "/search?q=test&page=1&sort=name"
      end

      span = spans.first
      expect(span.attributes["http.query_params"]).to eq("q,page,sort")
    end

    it "extracts request ID from headers" do
      spans = capture_spans do
        get "/test", {}, { "HTTP_X_REQUEST_ID" => "req-12345" }
      end

      span = spans.first
      expect(span.attributes["http.request_id"]).to eq("req-12345")
    end

    it "extracts client IP from X-Forwarded-For" do
      spans = capture_spans do
        get "/test", {}, { "HTTP_X_FORWARDED_FOR" => "1.2.3.4, 5.6.7.8" }
      end

      span = spans.first
      expect(span.attributes["http.client_ip"]).to eq("1.2.3.4")
    end
  end
end
