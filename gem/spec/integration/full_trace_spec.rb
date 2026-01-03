# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Full Trace Integration", :vcr do
  before do
    build_test_config(
      endpoint: "http://localhost:3000",
      service_name: "miniapm-gem-test",
      environment: "test"
    )
    MiniAPM.start!
  end

  after do
    MiniAPM.stop!
  end

  describe "complete request trace" do
    it "captures a full Rails-like request trace", vcr: { cassette_name: "traces/full_request" } do
      trace = MiniAPM::Trace.new
      MiniAPM::Context.current_trace = trace
      all_spans = []

      # 1. HTTP Server span (root)
      root_span = MiniAPM::Span.new(
        name: "GET /api/users/123",
        category: :http_server,
        trace_id: trace.trace_id,
        attributes: {
          "http.method" => "GET",
          "http.url" => "http://localhost:3000/api/users/123",
          "http.host" => "localhost",
          "http.scheme" => "http",
          "http.target" => "/api/users/123"
        }
      )
      MiniAPM::Context.push_span(root_span)

      # 2. Controller action
      controller_span = root_span.create_child(
        "UsersController#show",
        category: :internal,
        attributes: {
          "code.namespace" => "UsersController",
          "code.function" => "show"
        }
      )
      MiniAPM::Context.push_span(controller_span)

      # 3. Database query
      db_span = controller_span.create_child(
        "SELECT users.*",
        category: :db,
        attributes: {
          "db.system" => "postgresql",
          "db.name" => "myapp_production",
          "db.statement" => "SELECT * FROM users WHERE id = $1"
        }
      )
      db_span.finish
      all_spans << db_span

      # 4. Cache lookup
      cache_span = controller_span.create_child(
        "cache_read user:123:profile",
        category: :cache,
        attributes: {
          "cache.key" => "user:123:profile",
          "cache.hit" => true
        }
      )
      cache_span.finish
      all_spans << cache_span

      # 5. External HTTP call
      http_span = controller_span.create_child(
        "GET api.gravatar.com/avatar",
        category: :http_client,
        attributes: {
          "http.method" => "GET",
          "http.url" => "https://api.gravatar.com/avatar/abc123",
          "http.status_code" => 200
        }
      )
      http_span.set_ok
      http_span.finish
      all_spans << http_span

      # 6. View rendering
      view_span = controller_span.create_child(
        "render users/show.html.erb",
        category: :view,
        attributes: {
          "template" => "users/show.html.erb",
          "layout" => "application"
        }
      )

      # 7. Partial rendering inside view
      partial_span = view_span.create_child(
        "render users/_profile.html.erb",
        category: :view,
        attributes: {
          "template" => "users/_profile.html.erb"
        }
      )
      partial_span.finish
      all_spans << partial_span

      view_span.finish
      all_spans << view_span

      # Finish controller and root spans
      controller_span.finish
      all_spans << controller_span
      MiniAPM::Context.pop_span

      root_span.add_attribute("http.status_code", 200)
      root_span.finish
      all_spans << root_span
      MiniAPM::Context.pop_span

      # Export all spans
      result = MiniAPM::Exporters::OTLP.export(all_spans)

      expect(result[:success]).to be true

      # Verify span relationships
      expect(db_span.trace_id).to eq(root_span.trace_id)
      expect(db_span.parent_span_id).to eq(controller_span.span_id)
      expect(controller_span.parent_span_id).to eq(root_span.span_id)
      expect(partial_span.parent_span_id).to eq(view_span.span_id)
    end

    it "captures background job processing", vcr: { cassette_name: "traces/background_job" } do
      trace = MiniAPM::Trace.new
      MiniAPM::Context.current_trace = trace
      all_spans = []

      # 1. Job processing span (root)
      job_span = MiniAPM::Span.new(
        name: "SendWelcomeEmailJob",
        category: :job,
        trace_id: trace.trace_id,
        attributes: {
          "messaging.system" => "sidekiq",
          "messaging.operation" => "process",
          "job.class" => "SendWelcomeEmailJob",
          "job.queue" => "mailers",
          "job.id" => "jid-abc123"
        }
      )
      MiniAPM::Context.push_span(job_span)

      # 2. Database query
      db_span = job_span.create_child(
        "SELECT users.*",
        category: :db,
        attributes: {
          "db.system" => "postgresql",
          "db.statement" => "SELECT * FROM users WHERE id = $1"
        }
      )
      db_span.finish
      all_spans << db_span

      # 3. External API call (email service)
      api_span = job_span.create_child(
        "POST api.sendgrid.com/v3/mail/send",
        category: :http_client,
        attributes: {
          "http.method" => "POST",
          "http.url" => "https://api.sendgrid.com/v3/mail/send",
          "http.status_code" => 202
        }
      )
      api_span.set_ok
      api_span.finish
      all_spans << api_span

      # Finish job span
      job_span.finish
      all_spans << job_span

      result = MiniAPM::Exporters::OTLP.export(all_spans)

      expect(result[:success]).to be true
    end

    it "handles error during request", vcr: { cassette_name: "traces/request_with_error" } do
      trace = MiniAPM::Trace.new
      MiniAPM::Context.current_trace = trace
      all_spans = []

      # 1. HTTP Server span
      root_span = MiniAPM::Span.new(
        name: "POST /api/orders",
        category: :http_server,
        trace_id: trace.trace_id,
        attributes: {
          "http.method" => "POST",
          "http.target" => "/api/orders"
        }
      )
      MiniAPM::Context.push_span(root_span)

      # 2. Database query
      db_span = root_span.create_child(
        "INSERT INTO orders",
        category: :db,
        attributes: {
          "db.system" => "postgresql",
          "db.statement" => "INSERT INTO orders (user_id, total) VALUES ($1, $2)"
        }
      )
      db_span.finish
      all_spans << db_span

      # 3. Payment processing that fails
      payment_span = root_span.create_child(
        "POST api.stripe.com/v1/charges",
        category: :http_client,
        attributes: {
          "http.method" => "POST",
          "http.url" => "https://api.stripe.com/v1/charges"
        }
      )

      # Simulate error
      error = RuntimeError.new("Card declined")
      error.set_backtrace(["app/services/payment_processor.rb:42"])
      payment_span.record_exception(error)
      payment_span.add_attribute("http.status_code", 402)
      payment_span.finish
      all_spans << payment_span

      # Root span also gets error
      root_span.set_error("Payment failed")
      root_span.add_attribute("http.status_code", 422)
      root_span.finish
      all_spans << root_span

      result = MiniAPM::Exporters::OTLP.export(all_spans)

      expect(result[:success]).to be true
      expect(payment_span.error?).to be true
      expect(root_span.error?).to be true
    end
  end

  describe "distributed tracing" do
    it "propagates trace context across services", vcr: { cassette_name: "traces/distributed" } do
      # Service A: Create initial trace
      trace_a = MiniAPM::Trace.new
      MiniAPM::Context.current_trace = trace_a

      span_a = MiniAPM::Span.new(
        name: "GET /api/products/123",
        category: :http_server,
        trace_id: trace_a.trace_id
      )
      MiniAPM::Context.push_span(span_a)

      # Service A makes outgoing request to Service B
      # This would inject traceparent header
      headers = {}
      MiniAPM::Context.inject_into_headers(headers)

      expect(headers["traceparent"]).to match(/^00-#{trace_a.trace_id}-#{span_a.span_id}-01$/)

      # Simulate Service B receiving the request
      incoming = MiniAPM::Context.extract_from_headers(headers)

      expect(incoming[:trace_id]).to eq(trace_a.trace_id)
      expect(incoming[:parent_span_id]).to eq(span_a.span_id)
      expect(incoming[:sampled]).to be true

      # Service B creates its own spans with same trace_id
      span_b = MiniAPM::Span.new(
        name: "GET /internal/inventory",
        category: :http_server,
        trace_id: incoming[:trace_id],
        parent_span_id: incoming[:parent_span_id]
      )
      span_b.finish

      span_a.finish

      # Both services export their spans
      result = MiniAPM::Exporters::OTLP.export([span_a, span_b])

      expect(result[:success]).to be true
      expect(span_a.trace_id).to eq(span_b.trace_id)
      expect(span_b.parent_span_id).to eq(span_a.span_id)
    end
  end
end
