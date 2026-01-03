# frozen_string_literal: true

require "spec_helper"

RSpec.describe MiniAPM::Exporters::Errors do
  before do
    build_test_config
  end

  describe ".export" do
    it "sends error event to errors endpoint" do
      stub_request(:post, "http://localhost:3000/ingest/errors")
        .to_return(status: 200)

      error_event = MiniAPM::ErrorEvent.new(
        exception_class: "StandardError",
        message: "Test error",
        backtrace: ["line1", "line2"]
      )

      result = described_class.export(error_event)

      expect(result[:success]).to be true
      expect(WebMock).to have_requested(:post, "http://localhost:3000/ingest/errors")
    end

    it "does nothing without API key" do
      MiniAPM.configuration.api_key = nil

      error_event = MiniAPM::ErrorEvent.new(
        exception_class: "Error",
        message: "Test",
        backtrace: []
      )

      result = described_class.export(error_event)

      expect(result[:success]).to be false
      expect(result[:error]).to eq("No API key")
      expect(WebMock).not_to have_requested(:post, //)
    end

    it "includes Authorization header" do
      stub_request(:post, "http://localhost:3000/ingest/errors")
        .with(headers: { "Authorization" => "Bearer test_api_key" })
        .to_return(status: 200)

      error_event = MiniAPM::ErrorEvent.new(
        exception_class: "Error",
        message: "Test",
        backtrace: []
      )

      described_class.export(error_event)

      expect(WebMock).to have_requested(:post, "http://localhost:3000/ingest/errors")
        .with(headers: { "Authorization" => "Bearer test_api_key" })
    end

    it "sends error event data as JSON" do
      payload = nil

      stub_request(:post, "http://localhost:3000/ingest/errors")
        .with { |request| payload = JSON.parse(request.body) }
        .to_return(status: 200)

      error_event = MiniAPM::ErrorEvent.new(
        exception_class: "CustomError",
        message: "Something went wrong",
        backtrace: ["app/models/user.rb:10"],
        request_id: "req-123",
        user_id: 456
      )

      described_class.export(error_event)

      # Single error format
      expect(payload["exception_class"]).to eq("CustomError")
      expect(payload["message"]).to eq("Something went wrong")
      expect(payload["backtrace"]).to eq(["app/models/user.rb:10"])
      expect(payload["request_id"]).to eq("req-123")
      expect(payload["user_id"]).to eq("456")
      expect(payload["fingerprint"]).to be_a(String)
      expect(payload["timestamp"]).to be_a(String)
    end

    it "handles HTTP errors gracefully" do
      stub_request(:post, "http://localhost:3000/ingest/errors")
        .to_return(status: 500)

      error_event = MiniAPM::ErrorEvent.new(
        exception_class: "Error",
        message: "Test",
        backtrace: []
      )

      result = described_class.export(error_event)

      expect(result[:success]).to be false
      expect(result[:status]).to eq(500)
    end

    it "handles network errors gracefully" do
      stub_request(:post, "http://localhost:3000/ingest/errors")
        .to_timeout

      error_event = MiniAPM::ErrorEvent.new(
        exception_class: "Error",
        message: "Test",
        backtrace: []
      )

      result = described_class.export(error_event)

      expect(result[:success]).to be false
    end
  end
end
