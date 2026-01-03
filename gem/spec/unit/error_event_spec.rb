# frozen_string_literal: true

require "spec_helper"

RSpec.describe MiniAPM::ErrorEvent do
  before do
    build_test_config
  end

  describe "#initialize" do
    it "creates an error event with required attributes" do
      event = described_class.new(
        exception_class: "StandardError",
        message: "Something went wrong",
        backtrace: ["line1", "line2"]
      )

      expect(event.exception_class).to eq("StandardError")
      expect(event.message).to eq("Something went wrong")
      expect(event.backtrace).to eq(["line1", "line2"])
      expect(event.fingerprint).to match(/\A[0-9a-f]{32}\z/)
      expect(event.timestamp).to be_a(Time)
    end

    it "accepts optional attributes" do
      event = described_class.new(
        exception_class: "CustomError",
        message: "Error",
        backtrace: [],
        request_id: "req-123",
        user_id: 456,
        params: { action: "create" },
        context: { custom: "data" }
      )

      expect(event.request_id).to eq("req-123")
      expect(event.user_id).to eq("456")
      expect(event.params).to eq({ action: "create" })
      expect(event.context).to eq({ custom: "data" })
    end

    it "truncates long messages" do
      long_message = "x" * 20_000
      event = described_class.new(
        exception_class: "Error",
        message: long_message,
        backtrace: []
      )

      expect(event.message.length).to be <= 10_003 # 10000 + "..."
      expect(event.message).to end_with("...")
    end

    it "limits backtrace to 50 lines" do
      long_backtrace = 100.times.map { |i| "line #{i}" }
      event = described_class.new(
        exception_class: "Error",
        message: "Error",
        backtrace: long_backtrace
      )

      expect(event.backtrace.length).to eq(50)
    end

    it "handles nil backtrace" do
      event = described_class.new(
        exception_class: "Error",
        message: "Error",
        backtrace: nil
      )

      expect(event.backtrace).to eq([])
    end
  end

  describe ".from_exception" do
    it "creates event from exception object" do
      error = StandardError.new("Test error")
      error.set_backtrace(["app/models/user.rb:10", "app/controllers/users_controller.rb:20"])

      event = described_class.from_exception(error)

      expect(event.exception_class).to eq("StandardError")
      expect(event.message).to eq("Test error")
      expect(event.backtrace).to eq(["app/models/user.rb:10", "app/controllers/users_controller.rb:20"])
    end

    it "accepts context hash" do
      error = RuntimeError.new("Error")
      error.set_backtrace([])

      event = described_class.from_exception(error, {
        request_id: "req-456",
        user_id: 789,
        params: { id: 1 },
        custom_field: "custom_value"
      })

      expect(event.request_id).to eq("req-456")
      expect(event.user_id).to eq("789")
      expect(event.params).to eq({ id: 1 })
      expect(event.context).to eq({ custom_field: "custom_value" })
    end
  end

  describe "#to_h" do
    it "returns hash representation" do
      Timecop.freeze(Time.utc(2024, 1, 15, 12, 0, 0)) do
        event = described_class.new(
          exception_class: "CustomError",
          message: "Error message",
          backtrace: ["line1"],
          request_id: "req-123",
          user_id: 42
        )

        hash = event.to_h

        expect(hash[:exception_class]).to eq("CustomError")
        expect(hash[:message]).to eq("Error message")
        expect(hash[:backtrace]).to eq(["line1"])
        expect(hash[:fingerprint]).to be_a(String)
        expect(hash[:request_id]).to eq("req-123")
        expect(hash[:user_id]).to eq("42")
        expect(hash[:timestamp]).to eq("2024-01-15T12:00:00Z")
      end
    end

    it "excludes nil values" do
      event = described_class.new(
        exception_class: "Error",
        message: "Error",
        backtrace: []
      )

      hash = event.to_h

      expect(hash).not_to have_key(:request_id)
      expect(hash).not_to have_key(:user_id)
      expect(hash).not_to have_key(:params)
    end
  end

  describe "fingerprint generation" do
    it "generates consistent fingerprint for same error" do
      error1 = described_class.new(
        exception_class: "StandardError",
        message: "Connection failed",
        backtrace: ["app/models/user.rb:10"]
      )

      error2 = described_class.new(
        exception_class: "StandardError",
        message: "Connection failed",
        backtrace: ["app/models/user.rb:10"]
      )

      expect(error1.fingerprint).to eq(error2.fingerprint)
    end

    it "normalizes numbers in message" do
      error1 = described_class.new(
        exception_class: "RecordNotFound",
        message: "Couldn't find User with ID=123",
        backtrace: ["app/models/user.rb:10"]
      )

      error2 = described_class.new(
        exception_class: "RecordNotFound",
        message: "Couldn't find User with ID=456",
        backtrace: ["app/models/user.rb:10"]
      )

      expect(error1.fingerprint).to eq(error2.fingerprint)
    end

    it "normalizes UUIDs in message" do
      error1 = described_class.new(
        exception_class: "NotFound",
        message: "Object 550e8400-e29b-41d4-a716-446655440000 not found",
        backtrace: []
      )

      error2 = described_class.new(
        exception_class: "NotFound",
        message: "Object a1b2c3d4-e5f6-7890-abcd-ef1234567890 not found",
        backtrace: []
      )

      expect(error1.fingerprint).to eq(error2.fingerprint)
    end

    it "normalizes quoted strings" do
      error1 = described_class.new(
        exception_class: "ValidationError",
        message: "Invalid value 'foo' for field",
        backtrace: []
      )

      error2 = described_class.new(
        exception_class: "ValidationError",
        message: "Invalid value 'bar' for field",
        backtrace: []
      )

      expect(error1.fingerprint).to eq(error2.fingerprint)
    end

    it "uses first app backtrace line in fingerprint" do
      error1 = described_class.new(
        exception_class: "Error",
        message: "Error",
        backtrace: [
          "/gems/activerecord-7.0.0/lib/active_record/core.rb:100",
          "app/models/user.rb:10",
          "app/controllers/users_controller.rb:20"
        ]
      )

      error2 = described_class.new(
        exception_class: "Error",
        message: "Error",
        backtrace: [
          "/gems/activerecord-7.1.0/lib/active_record/core.rb:105",
          "app/models/user.rb:10",
          "app/controllers/users_controller.rb:25"
        ]
      )

      expect(error1.fingerprint).to eq(error2.fingerprint)
    end
  end

  describe "parameter filtering" do
    it "filters sensitive parameters" do
      event = described_class.new(
        exception_class: "Error",
        message: "Error",
        backtrace: [],
        params: {
          username: "john",
          password: "secret123",
          api_key: "key-abc"
        }
      )

      expect(event.params[:username]).to eq("john")
      expect(event.params[:password]).to eq("[FILTERED]")
      expect(event.params[:api_key]).to eq("[FILTERED]")
    end

    it "filters nested parameters" do
      event = described_class.new(
        exception_class: "Error",
        message: "Error",
        backtrace: [],
        params: {
          user: {
            name: "john",
            password: "secret",
            settings: {
              token: "abc123"
            }
          }
        }
      )

      expect(event.params[:user][:name]).to eq("john")
      expect(event.params[:user][:password]).to eq("[FILTERED]")
      expect(event.params[:user][:settings][:token]).to eq("[FILTERED]")
    end

    it "filters parameters in arrays" do
      event = described_class.new(
        exception_class: "Error",
        message: "Error",
        backtrace: [],
        params: {
          users: [
            { name: "john", password: "secret1" },
            { name: "jane", password: "secret2" }
          ]
        }
      )

      expect(event.params[:users][0][:name]).to eq("john")
      expect(event.params[:users][0][:password]).to eq("[FILTERED]")
      expect(event.params[:users][1][:password]).to eq("[FILTERED]")
    end

    it "handles non-hash params" do
      event = described_class.new(
        exception_class: "Error",
        message: "Error",
        backtrace: [],
        params: "not a hash"
      )

      expect(event.params).to be_nil
    end
  end
end
