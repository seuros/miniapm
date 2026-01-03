# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Error Reporting Integration", :vcr do
  before do
    build_test_config(
      endpoint: "http://localhost:3000",
      service_name: "miniapm-gem-test",
      environment: "test"
    )
  end

  describe "reporting errors to MiniAPM server" do
    it "successfully reports a basic error", vcr: { cassette_name: "errors/basic_error" } do
      error_event = MiniAPM::ErrorEvent.new(
        exception_class: "StandardError",
        message: "Something went wrong during processing",
        backtrace: [
          "app/models/user.rb:42:in `save'",
          "app/controllers/users_controller.rb:18:in `create'",
          "actionpack (7.0.0) lib/action_controller/metal.rb:100"
        ],
        request_id: "req-12345",
        user_id: 42
      )

      result = MiniAPM::Exporters::Errors.export(error_event)

      expect(result[:success]).to be true
      expect(result[:status]).to be_between(200, 299)
    end

    it "reports an error created from exception", vcr: { cassette_name: "errors/from_exception" } do
      begin
        raise RuntimeError, "Database connection lost"
      rescue RuntimeError => e
        error_event = MiniAPM::ErrorEvent.from_exception(e, {
          request_id: "req-67890",
          user_id: 123,
          params: { action: "index", controller: "users" }
        })

        result = MiniAPM::Exporters::Errors.export(error_event)

        expect(result[:success]).to be true
      end
    end

    it "reports error with filtered parameters", vcr: { cassette_name: "errors/filtered_params" } do
      error_event = MiniAPM::ErrorEvent.new(
        exception_class: "ValidationError",
        message: "Invalid credentials",
        backtrace: ["app/controllers/sessions_controller.rb:10"],
        params: {
          email: "user@example.com",
          password: "secret123",
          remember_me: true
        }
      )

      # Password should be filtered
      expect(error_event.params[:password]).to eq("[FILTERED]")

      result = MiniAPM::Exporters::Errors.export(error_event)

      expect(result[:success]).to be true
    end

    it "reports error with context", vcr: { cassette_name: "errors/with_context" } do
      error_event = MiniAPM::ErrorEvent.new(
        exception_class: "PaymentError",
        message: "Payment gateway timeout",
        backtrace: [
          "app/services/payment_processor.rb:55",
          "app/controllers/checkout_controller.rb:32"
        ],
        context: {
          gateway: "stripe",
          order_id: "ord_12345",
          amount_cents: 9999,
          currency: "USD"
        }
      )

      result = MiniAPM::Exporters::Errors.export(error_event)

      expect(result[:success]).to be true
    end

    it "reports error with very long backtrace (truncated)", vcr: { cassette_name: "errors/long_backtrace" } do
      long_backtrace = 100.times.map { |i| "app/deep/nested/file_#{i}.rb:#{i * 10}" }

      error_event = MiniAPM::ErrorEvent.new(
        exception_class: "DeepStackError",
        message: "Very deep call stack",
        backtrace: long_backtrace
      )

      # Backtrace should be truncated to 50 lines
      expect(error_event.backtrace.length).to eq(50)

      result = MiniAPM::Exporters::Errors.export(error_event)

      expect(result[:success]).to be true
    end

    it "generates consistent fingerprints for similar errors", vcr: { cassette_name: "errors/fingerprints" } do
      error1 = MiniAPM::ErrorEvent.new(
        exception_class: "RecordNotFound",
        message: "Couldn't find User with ID=123",
        backtrace: ["app/models/user.rb:10"]
      )

      error2 = MiniAPM::ErrorEvent.new(
        exception_class: "RecordNotFound",
        message: "Couldn't find User with ID=456",
        backtrace: ["app/models/user.rb:10"]
      )

      expect(error1.fingerprint).to eq(error2.fingerprint)

      MiniAPM::Exporters::Errors.export(error1)
      result = MiniAPM::Exporters::Errors.export(error2)

      expect(result[:success]).to be true
    end
  end

  describe "error payload structure" do
    it "sends correctly formatted JSON", vcr: { cassette_name: "errors/payload_structure" } do
      payload = nil

      allow(MiniAPM::Transport::HTTP).to receive(:post) do |_url, body, **_opts|
        payload = body
        { success: true, status: 200 }
      end

      Timecop.freeze(Time.utc(2024, 1, 15, 12, 0, 0)) do
        error_event = MiniAPM::ErrorEvent.new(
          exception_class: "TestError",
          message: "Test message",
          backtrace: ["line1", "line2"],
          request_id: "req-test",
          user_id: 99
        )

        MiniAPM::Exporters::Errors.export(error_event)
      end

      expect(payload[:exception_class]).to eq("TestError")
      expect(payload[:message]).to eq("Test message")
      expect(payload[:backtrace]).to eq(["line1", "line2"])
      expect(payload[:fingerprint]).to be_a(String)
      expect(payload[:fingerprint].length).to eq(32)
      expect(payload[:request_id]).to eq("req-test")
      expect(payload[:user_id]).to eq("99")
      expect(payload[:timestamp]).to eq("2024-01-15T12:00:00Z")
    end
  end
end
