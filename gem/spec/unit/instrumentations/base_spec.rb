# frozen_string_literal: true

require "spec_helper"

# Stub ActiveSupport::Notifications for testing
module ActiveSupport
  module Notifications
    class Event
      attr_reader :name, :time, :end, :payload

      def initialize(name, start, ending, _id, payload)
        @name = name
        @time = start
        @end = ending
        @payload = payload
      end

      def duration
        (@end - @time) * 1000
      end
    end

    class << self
      def subscribe(name, &block)
        subscriptions[name] ||= []
        subscriptions[name] << block
      end

      def subscriptions
        @subscriptions ||= {}
      end

      def clear!
        @subscriptions = {}
      end

      def trigger(name, start_time, end_time, id, payload)
        return unless subscriptions[name]

        subscriptions[name].each do |block|
          block.call(name, start_time, end_time, id, payload)
        end
      end
    end
  end
end unless defined?(ActiveSupport::Notifications)

RSpec.describe MiniAPM::Instrumentations::Base do
  before do
    build_test_config
    ActiveSupport::Notifications.clear! if ActiveSupport::Notifications.respond_to?(:clear!)
  end

  describe ".install!" do
    it "raises NotImplementedError" do
      expect { described_class.install! }.to raise_error(NotImplementedError)
    end
  end

  describe ".installed?" do
    it "returns false by default" do
      expect(described_class.installed?).to be false
    end
  end

  describe ".create_span_from_event" do
    let(:test_class) do
      Class.new(described_class) do
        class << self
          def test_create_span(event, name:, category:, attributes: {})
            create_span_from_event(event, name: name, category: category, attributes: attributes)
          end
        end
      end
    end

    before do
      MiniAPM.start!
      @trace = MiniAPM::Trace.new
      MiniAPM::Context.current_trace = @trace
    end

    after do
      MiniAPM::Context.clear!
      MiniAPM.stop!
    end

    it "creates a span with provided attributes" do
      start_time = Time.now - 0.1
      end_time = Time.now

      event = ActiveSupport::Notifications::Event.new(
        "test.event",
        start_time,
        end_time,
        "id",
        {}
      )

      span = test_class.test_create_span(
        event,
        name: "test span",
        category: :db,
        attributes: { "db.system" => "postgresql" }
      )

      expect(span.name).to eq("test span")
      expect(span.category).to eq(:db)
      expect(span.attributes["db.system"]).to eq("postgresql")
      expect(span.trace_id).to eq(@trace.trace_id)
    end

    it "returns nil when MiniAPM is disabled" do
      MiniAPM.configuration.enabled = false

      event = ActiveSupport::Notifications::Event.new("test", Time.now, Time.now, "id", {})

      span = test_class.test_create_span(event, name: "test", category: :internal)

      expect(span).to be_nil
    end

    it "returns nil when no current trace" do
      MiniAPM::Context.clear!

      event = ActiveSupport::Notifications::Event.new("test", Time.now, Time.now, "id", {})

      span = test_class.test_create_span(event, name: "test", category: :internal)

      expect(span).to be_nil
    end

    it "sets parent_span_id when parent span exists" do
      parent_span = MiniAPM::Span.new(name: "parent", category: :http_server, trace_id: @trace.trace_id)
      MiniAPM::Context.push_span(parent_span)

      event = ActiveSupport::Notifications::Event.new("test", Time.now, Time.now, "id", {})

      span = test_class.test_create_span(event, name: "child", category: :db)

      expect(span.parent_span_id).to eq(parent_span.span_id)
    end
  end
end
