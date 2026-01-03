# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OTLP Export Integration", :vcr do
  before do
    build_test_config(
      endpoint: "http://localhost:3000",
      service_name: "miniapm-gem-test",
      environment: "test"
    )
  end

  describe "exporting spans to MiniAPM server" do
    it "successfully exports a single span", vcr: { cassette_name: "otlp/single_span" } do
      span = MiniAPM::Span.new(
        name: "GET /api/users",
        category: :http_server,
        attributes: {
          "http.method" => "GET",
          "http.url" => "http://example.com/api/users",
          "http.status_code" => 200
        }
      )
      span.finish

      result = MiniAPM::Exporters::OTLP.export([span])

      expect(result[:success]).to be true
      expect(result[:status]).to be_between(200, 299)
    end

    it "exports multiple spans in a batch", vcr: { cassette_name: "otlp/batch_spans" } do
      trace = MiniAPM::Trace.new
      MiniAPM::Context.current_trace = trace

      spans = []

      # Root span
      root_span = MiniAPM::Span.new(
        name: "GET /api/orders",
        category: :http_server,
        trace_id: trace.trace_id,
        attributes: { "http.method" => "GET", "http.status_code" => 200 }
      )

      # Child DB span
      db_span = root_span.create_child("SELECT * FROM orders", category: :db, attributes: {
        "db.system" => "postgresql",
        "db.statement" => "SELECT * FROM orders WHERE user_id = ?"
      })
      db_span.finish
      spans << db_span

      # Child cache span
      cache_span = root_span.create_child("cache_read orders:list", category: :cache, attributes: {
        "cache.hit" => false
      })
      cache_span.finish
      spans << cache_span

      root_span.finish
      spans << root_span

      result = MiniAPM::Exporters::OTLP.export(spans)

      expect(result[:success]).to be true
      expect(result[:status]).to be_between(200, 299)
    end

    it "exports span with exception event", vcr: { cassette_name: "otlp/span_with_exception" } do
      span = MiniAPM::Span.new(
        name: "POST /api/create",
        category: :http_server,
        attributes: { "http.method" => "POST" }
      )

      error = StandardError.new("Database connection failed")
      error.set_backtrace(["app/models/user.rb:42", "app/controllers/users_controller.rb:18"])
      span.record_exception(error)
      span.finish

      result = MiniAPM::Exporters::OTLP.export([span])

      expect(result[:success]).to be true
    end

    it "exports span with custom events", vcr: { cassette_name: "otlp/span_with_events" } do
      span = MiniAPM::Span.new(
        name: "process_order",
        category: :internal,
        attributes: { "order.id" => "12345" }
      )

      span.add_event("validation_passed", attributes: { "rules_checked" => 5 })
      span.add_event("payment_processed", attributes: { "gateway" => "stripe", "amount" => 99.99 })
      span.add_event("email_sent", attributes: { "template" => "order_confirmation" })

      span.finish

      result = MiniAPM::Exporters::OTLP.export([span])

      expect(result[:success]).to be true
    end

    it "exports HTTP client spans", vcr: { cassette_name: "otlp/http_client_span" } do
      trace = MiniAPM::Trace.new
      MiniAPM::Context.current_trace = trace

      parent_span = MiniAPM::Span.new(
        name: "GET /api/external",
        category: :http_server,
        trace_id: trace.trace_id
      )

      child_span = parent_span.create_child("GET api.stripe.com/v1/charges", category: :http_client, attributes: {
        "http.method" => "GET",
        "http.url" => "https://api.stripe.com/v1/charges",
        "http.status_code" => 200,
        "http.response_content_length" => 1234
      })
      child_span.set_ok
      child_span.finish

      parent_span.finish

      result = MiniAPM::Exporters::OTLP.export([parent_span, child_span])

      expect(result[:success]).to be true
    end

    it "exports job spans", vcr: { cassette_name: "otlp/job_span" } do
      span = MiniAPM::Span.new(
        name: "SendEmailJob",
        category: :job,
        attributes: {
          "messaging.system" => "sidekiq",
          "messaging.operation" => "process",
          "job.class" => "SendEmailJob",
          "job.queue" => "default",
          "job.id" => "abc123"
        }
      )
      span.finish

      result = MiniAPM::Exporters::OTLP.export([span])

      expect(result[:success]).to be true
    end
  end

  describe "OTLP payload structure" do
    it "builds valid resourceSpans structure", vcr: { cassette_name: "otlp/payload_structure" } do
      payload = nil

      # Stub to capture payload
      allow(MiniAPM::Transport::HTTP).to receive(:post) do |_url, body, **_opts|
        payload = body
        { success: true, status: 200 }
      end

      span = MiniAPM::Span.new(name: "test", category: :internal)
      span.finish

      MiniAPM::Exporters::OTLP.export([span])

      expect(payload).to have_key("resourceSpans")
      expect(payload["resourceSpans"]).to be_an(Array)
      expect(payload["resourceSpans"].first).to have_key("resource")
      expect(payload["resourceSpans"].first).to have_key("scopeSpans")

      resource = payload["resourceSpans"].first["resource"]
      expect(resource).to have_key("attributes")

      scope = payload["resourceSpans"].first["scopeSpans"].first
      expect(scope["scope"]["name"]).to eq("miniapm-ruby")
      expect(scope["spans"]).to be_an(Array)
    end
  end
end
