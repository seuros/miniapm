# frozen_string_literal: true

require "spec_helper"
require "miniapm/instrumentations/http/net_http"

RSpec.describe MiniAPM::Instrumentations::HTTP::NetHTTP do
  before do
    build_test_config
    MiniAPM.start!

    stub_request(:any, /httpbin\.org/).to_return(status: 200, body: "OK")
  end

  after do
    MiniAPM.stop!
  end

  describe ".install!" do
    it "prepends Patch module to Net::HTTP" do
      described_class.install!

      expect(Net::HTTP.ancestors).to include(described_class::Patch)
    end

    it "marks as installed" do
      described_class.install!

      expect(described_class.installed?).to be true
    end
  end

  describe "instrumented requests" do
    before do
      described_class.install!
    end

    it "creates spans for HTTP requests" do
      trace = MiniAPM::Trace.new
      MiniAPM::Context.current_trace = trace

      spans = capture_spans do
        uri = URI.parse("http://httpbin.org/get")
        Net::HTTP.get(uri)
      end

      expect(spans.length).to eq(1)
      expect(spans.first.name).to include("GET")
      expect(spans.first.category).to eq(:http_client)
    end

    it "records HTTP attributes" do
      trace = MiniAPM::Trace.new
      MiniAPM::Context.current_trace = trace

      spans = capture_spans do
        uri = URI.parse("http://httpbin.org/post")
        http = Net::HTTP.new(uri.host, uri.port)
        request = Net::HTTP::Post.new(uri.path)
        http.request(request)
      end

      span = spans.first
      expect(span.attributes["http.method"]).to eq("POST")
      expect(span.attributes["http.host"]).to eq("httpbin.org")
      expect(span.attributes["http.status_code"]).to eq(200)
    end

    it "records status code on error responses" do
      stub_request(:get, "http://httpbin.org/error")
        .to_return(status: 500, body: "Error")

      trace = MiniAPM::Trace.new
      MiniAPM::Context.current_trace = trace

      spans = capture_spans do
        uri = URI.parse("http://httpbin.org/error")
        Net::HTTP.get(uri)
      end

      span = spans.first
      expect(span.attributes["http.status_code"]).to eq(500)
      expect(span.error?).to be true
    end

    it "records exceptions" do
      stub_request(:get, "http://httpbin.org/timeout")
        .to_timeout

      trace = MiniAPM::Trace.new
      MiniAPM::Context.current_trace = trace

      spans = []
      original_record = MiniAPM.method(:record_span)
      MiniAPM.define_singleton_method(:record_span) do |span|
        spans << span
      end

      begin
        expect {
          uri = URI.parse("http://httpbin.org/timeout")
          Net::HTTP.get(uri)
        }.to raise_error(Net::OpenTimeout)
      ensure
        MiniAPM.define_singleton_method(:record_span, original_record)
      end

      span = spans.first
      expect(span).not_to be_nil
      expect(span.error?).to be true
      expect(span.events.first[:name]).to eq("exception")
    end

    it "injects trace context headers" do
      trace = MiniAPM::Trace.new
      MiniAPM::Context.current_trace = trace
      parent_span = MiniAPM::Span.new(name: "parent", category: :http_server, trace_id: trace.trace_id)
      MiniAPM::Context.push_span(parent_span)

      captured_headers = {}
      stub_request(:get, "http://httpbin.org/headers")
        .with { |request| captured_headers = request.headers }
        .to_return(status: 200)

      capture_spans do
        uri = URI.parse("http://httpbin.org/headers")
        Net::HTTP.get(uri)
      end

      expect(captured_headers["Traceparent"]).to match(/^00-[0-9a-f]{32}-[0-9a-f]{16}-\d{2}$/)
    end

    it "sets parent span id correctly" do
      trace = MiniAPM::Trace.new
      MiniAPM::Context.current_trace = trace
      parent_span = MiniAPM::Span.new(name: "parent", category: :http_server, trace_id: trace.trace_id)
      MiniAPM::Context.push_span(parent_span)

      spans = capture_spans do
        uri = URI.parse("http://httpbin.org/get")
        Net::HTTP.get(uri)
      end

      span = spans.first
      expect(span.parent_span_id).to eq(parent_span.span_id)
      expect(span.trace_id).to eq(trace.trace_id)
    end

    it "skips when no current trace" do
      MiniAPM::Context.clear!

      spans = capture_spans do
        uri = URI.parse("http://httpbin.org/get")
        Net::HTTP.get(uri)
      end

      expect(spans).to be_empty
    end

    it "skips MiniAPM's own requests" do
      trace = MiniAPM::Trace.new
      MiniAPM::Context.current_trace = trace

      spans = capture_spans do
        uri = URI.parse("http://localhost:3000/ingest/v1/traces")
        http = Net::HTTP.new(uri.host, uri.port)
        request = Net::HTTP::Post.new(uri.path)
        request["User-Agent"] = "miniapm-ruby/#{MiniAPM::VERSION}"
        stub_request(:post, "http://localhost:3000/ingest/v1/traces")
          .to_return(status: 200)
        http.request(request)
      end

      expect(spans).to be_empty
    end

    it "handles HTTPS requests" do
      stub_request(:get, "https://secure.httpbin.org/get")
        .to_return(status: 200, body: "OK")

      trace = MiniAPM::Trace.new
      MiniAPM::Context.current_trace = trace

      spans = capture_spans do
        uri = URI.parse("https://secure.httpbin.org/get")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        request = Net::HTTP::Get.new(uri.path)
        http.request(request)
      end

      span = spans.first
      expect(span.attributes["http.url"]).to start_with("https://")
    end
  end
end
