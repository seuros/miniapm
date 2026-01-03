# frozen_string_literal: true

require "spec_helper"

RSpec.describe MiniAPM::Transport::HTTP do
  describe ".post" do
    it "sends POST request with JSON payload" do
      stub_request(:post, "http://localhost:3000/test")
        .with(
          body: { key: "value" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
        .to_return(status: 200, body: "OK")

      result = described_class.post(
        "http://localhost:3000/test",
        { key: "value" }
      )

      expect(result[:success]).to be true
      expect(result[:status]).to eq(200)
      expect(result[:body]).to eq("OK")
    end

    it "accepts string payload" do
      stub_request(:post, "http://localhost:3000/test")
        .with(body: '{"raw":"json"}')
        .to_return(status: 200)

      result = described_class.post(
        "http://localhost:3000/test",
        '{"raw":"json"}'
      )

      expect(result[:success]).to be true
    end

    it "includes custom headers" do
      stub_request(:post, "http://localhost:3000/test")
        .with(headers: { "Authorization" => "Bearer test-token" })
        .to_return(status: 200)

      result = described_class.post(
        "http://localhost:3000/test",
        {},
        headers: { "Authorization" => "Bearer test-token" }
      )

      expect(result[:success]).to be true
    end

    it "includes User-Agent header" do
      stub_request(:post, "http://localhost:3000/test")
        .with(headers: { "User-Agent" => /miniapm-ruby/ })
        .to_return(status: 200)

      result = described_class.post(
        "http://localhost:3000/test",
        {}
      )

      expect(result[:success]).to be true
    end

    it "handles non-success responses" do
      stub_request(:post, "http://localhost:3000/test")
        .to_return(status: 500, body: "Internal Server Error")

      result = described_class.post(
        "http://localhost:3000/test",
        {}
      )

      expect(result[:success]).to be false
      expect(result[:status]).to eq(500)
    end

    it "handles network errors gracefully" do
      stub_request(:post, "http://localhost:3000/test")
        .to_raise(SocketError.new("Connection refused"))

      result = described_class.post(
        "http://localhost:3000/test",
        {}
      )

      expect(result[:success]).to be false
      expect(result[:status]).to eq(0)
      expect(result[:error]).to be_a(SocketError)
    end

    it "handles timeout errors" do
      stub_request(:post, "http://localhost:3000/test")
        .to_timeout

      result = described_class.post(
        "http://localhost:3000/test",
        {}
      )

      expect(result[:success]).to be false
      expect(result[:status]).to eq(0)
    end

    it "uses HTTPS when scheme is https" do
      stub_request(:post, "https://secure.example.com/test")
        .to_return(status: 200)

      result = described_class.post(
        "https://secure.example.com/test",
        {}
      )

      expect(result[:success]).to be true
    end
  end
end
