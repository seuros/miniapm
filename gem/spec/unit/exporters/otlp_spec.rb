# frozen_string_literal: true

require "spec_helper"

RSpec.describe MiniAPM::Exporters::OTLP do
  before do
    build_test_config(
      service_name: "test-service",
      environment: "test",
      service_version: "1.0.0",
      host: "test-host"
    )
  end

  describe ".export" do
    it "sends spans to OTLP endpoint" do
      stub_request(:post, "http://localhost:3000/ingest/v1/traces")
        .to_return(status: 200)

      span = create_test_span
      span.finish

      result = described_class.export([span])

      expect(result[:success]).to be true
      expect(WebMock).to have_requested(:post, "http://localhost:3000/ingest/v1/traces")
    end

    it "does nothing with empty spans array" do
      result = described_class.export([])

      expect(result).to be_nil
      expect(WebMock).not_to have_requested(:post, //)
    end

    it "does nothing without API key" do
      MiniAPM.configuration.api_key = nil

      span = create_test_span
      span.finish

      result = described_class.export([span])

      expect(result).to be_nil
    end

    it "includes Authorization header" do
      stub_request(:post, "http://localhost:3000/ingest/v1/traces")
        .with(headers: { "Authorization" => "Bearer test_api_key" })
        .to_return(status: 200)

      span = create_test_span
      span.finish

      described_class.export([span])

      expect(WebMock).to have_requested(:post, "http://localhost:3000/ingest/v1/traces")
        .with(headers: { "Authorization" => "Bearer test_api_key" })
    end

    it "builds valid OTLP payload structure" do
      payload = nil

      stub_request(:post, "http://localhost:3000/ingest/v1/traces")
        .with { |request| payload = JSON.parse(request.body) }
        .to_return(status: 200)

      span = create_test_span(name: "test-operation", category: :http_server)
      span.finish

      described_class.export([span])

      expect(payload).to have_key("resourceSpans")
      expect(payload["resourceSpans"]).to be_an(Array)
      expect(payload["resourceSpans"].first).to have_key("resource")
      expect(payload["resourceSpans"].first).to have_key("scopeSpans")
    end

    it "includes resource attributes" do
      payload = nil

      stub_request(:post, "http://localhost:3000/ingest/v1/traces")
        .with { |request| payload = JSON.parse(request.body) }
        .to_return(status: 200)

      span = create_test_span
      span.finish

      described_class.export([span])

      attrs = payload["resourceSpans"].first["resource"]["attributes"]
      attr_keys = attrs.map { |a| a["key"] }

      expect(attr_keys).to include("service.name")
      expect(attr_keys).to include("deployment.environment")
      expect(attr_keys).to include("telemetry.sdk.name")
    end

    it "includes scope information" do
      payload = nil

      stub_request(:post, "http://localhost:3000/ingest/v1/traces")
        .with { |request| payload = JSON.parse(request.body) }
        .to_return(status: 200)

      span = create_test_span
      span.finish

      described_class.export([span])

      scope = payload["resourceSpans"].first["scopeSpans"].first["scope"]

      expect(scope["name"]).to eq("miniapm-ruby")
      expect(scope["version"]).to eq(MiniAPM::VERSION)
    end

    it "converts all spans to OTLP format" do
      payload = nil

      stub_request(:post, "http://localhost:3000/ingest/v1/traces")
        .with { |request| payload = JSON.parse(request.body) }
        .to_return(status: 200)

      spans = 3.times.map do |i|
        span = create_test_span(name: "span-#{i}")
        span.finish
        span
      end

      described_class.export(spans)

      otlp_spans = payload["resourceSpans"].first["scopeSpans"].first["spans"]

      expect(otlp_spans.length).to eq(3)
      expect(otlp_spans.map { |s| s["name"] }).to contain_exactly("span-0", "span-1", "span-2")
    end

    it "handles HTTP errors gracefully" do
      stub_request(:post, "http://localhost:3000/ingest/v1/traces")
        .to_return(status: 500)

      span = create_test_span
      span.finish

      result = described_class.export([span])

      expect(result[:success]).to be false
      expect(result[:status]).to eq(500)
    end

    it "handles network errors gracefully" do
      stub_request(:post, "http://localhost:3000/ingest/v1/traces")
        .to_timeout

      span = create_test_span
      span.finish

      result = described_class.export([span])

      expect(result[:success]).to be false
    end
  end
end
