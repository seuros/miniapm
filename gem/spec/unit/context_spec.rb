# frozen_string_literal: true

require "spec_helper"

RSpec.describe MiniAPM::Context do
  after do
    described_class.clear!
  end

  describe ".current_trace" do
    it "returns nil when no trace is set" do
      expect(described_class.current_trace).to be_nil
    end

    it "returns the current trace when set" do
      trace = MiniAPM::Trace.new
      described_class.current_trace = trace

      expect(described_class.current_trace).to eq(trace)
    end
  end

  describe ".current_trace_id" do
    it "returns nil when no trace is set" do
      expect(described_class.current_trace_id).to be_nil
    end

    it "returns the trace_id of the current trace" do
      trace = MiniAPM::Trace.new(trace_id: "abc123" + "0" * 26)
      described_class.current_trace = trace

      expect(described_class.current_trace_id).to eq("abc123" + "0" * 26)
    end
  end

  describe ".span_stack" do
    it "returns an empty array by default" do
      expect(described_class.span_stack).to eq([])
    end

    it "maintains a stack of spans" do
      span1 = MiniAPM::Span.new(name: "span1", category: :internal)
      span2 = MiniAPM::Span.new(name: "span2", category: :internal)

      described_class.push_span(span1)
      described_class.push_span(span2)

      expect(described_class.span_stack).to eq([span1, span2])
    end
  end

  describe ".current_span" do
    it "returns nil when stack is empty" do
      expect(described_class.current_span).to be_nil
    end

    it "returns the top span on the stack" do
      span1 = MiniAPM::Span.new(name: "span1", category: :internal)
      span2 = MiniAPM::Span.new(name: "span2", category: :internal)

      described_class.push_span(span1)
      described_class.push_span(span2)

      expect(described_class.current_span).to eq(span2)
    end
  end

  describe ".push_span / .pop_span" do
    it "pushes and pops spans correctly" do
      span1 = MiniAPM::Span.new(name: "span1", category: :internal)
      span2 = MiniAPM::Span.new(name: "span2", category: :internal)

      described_class.push_span(span1)
      described_class.push_span(span2)

      expect(described_class.pop_span).to eq(span2)
      expect(described_class.current_span).to eq(span1)

      expect(described_class.pop_span).to eq(span1)
      expect(described_class.current_span).to be_nil
    end
  end

  describe ".with_span" do
    it "pushes span, yields, then pops" do
      span = MiniAPM::Span.new(name: "test", category: :internal)

      result = described_class.with_span(span) do
        expect(described_class.current_span).to eq(span)
        "return_value"
      end

      expect(result).to eq("return_value")
      expect(described_class.current_span).to be_nil
    end

    it "pops span even if block raises" do
      span = MiniAPM::Span.new(name: "test", category: :internal)

      expect {
        described_class.with_span(span) do
          raise "error"
        end
      }.to raise_error("error")

      expect(described_class.current_span).to be_nil
    end
  end

  describe ".with_trace" do
    it "sets trace, yields, then restores previous trace" do
      old_trace = MiniAPM::Trace.new
      new_trace = MiniAPM::Trace.new

      described_class.current_trace = old_trace

      described_class.with_trace(new_trace) do
        expect(described_class.current_trace).to eq(new_trace)
      end

      expect(described_class.current_trace).to eq(old_trace)
    end

    it "clears span stack within the block" do
      span = MiniAPM::Span.new(name: "outer", category: :internal)
      described_class.push_span(span)

      trace = MiniAPM::Trace.new
      described_class.with_trace(trace) do
        expect(described_class.span_stack).to be_empty
      end

      expect(described_class.current_span).to eq(span)
    end
  end

  describe ".clear!" do
    it "clears trace and span stack" do
      trace = MiniAPM::Trace.new
      span = MiniAPM::Span.new(name: "test", category: :internal)

      described_class.current_trace = trace
      described_class.push_span(span)

      described_class.clear!

      expect(described_class.current_trace).to be_nil
      expect(described_class.span_stack).to be_empty
    end
  end

  describe ".extract_from_headers" do
    it "returns nil for missing traceparent" do
      expect(described_class.extract_from_headers({})).to be_nil
    end

    it "parses valid traceparent header" do
      headers = { "traceparent" => "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01" }

      result = described_class.extract_from_headers(headers)

      expect(result[:trace_id]).to eq("4bf92f3577b34da6a3ce929d0e0e4736")
      expect(result[:parent_span_id]).to eq("00f067aa0ba902b7")
      expect(result[:sampled]).to be true
    end

    it "parses unsampled traceparent" do
      headers = { "traceparent" => "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00" }

      result = described_class.extract_from_headers(headers)

      expect(result[:sampled]).to be false
    end

    it "handles HTTP_TRACEPARENT format" do
      headers = { "HTTP_TRACEPARENT" => "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01" }

      result = described_class.extract_from_headers(headers)

      expect(result[:trace_id]).to eq("4bf92f3577b34da6a3ce929d0e0e4736")
    end

    it "returns nil for invalid format" do
      expect(described_class.extract_from_headers({ "traceparent" => "invalid" })).to be_nil
      expect(described_class.extract_from_headers({ "traceparent" => "00-short-id-01" })).to be_nil
      expect(described_class.extract_from_headers({ "traceparent" => "01-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01" })).to be_nil
    end
  end

  describe ".inject_into_headers" do
    it "returns headers unchanged when no current span" do
      headers = { "Content-Type" => "application/json" }

      result = described_class.inject_into_headers(headers)

      expect(result).to eq(headers)
      expect(result).not_to have_key("traceparent")
    end

    it "adds traceparent header when span exists" do
      trace = MiniAPM::Trace.new(sampled: true)
      span = MiniAPM::Span.new(name: "test", category: :internal, trace_id: trace.trace_id)

      described_class.current_trace = trace
      described_class.push_span(span)

      headers = {}
      result = described_class.inject_into_headers(headers)

      expect(result["traceparent"]).to match(/^00-[0-9a-f]{32}-[0-9a-f]{16}-01$/)
    end

    it "sets sampled flag to 00 when not sampled" do
      trace = MiniAPM::Trace.new(sampled: false)
      span = MiniAPM::Span.new(name: "test", category: :internal, trace_id: trace.trace_id)

      described_class.current_trace = trace
      described_class.push_span(span)

      headers = {}
      result = described_class.inject_into_headers(headers)

      expect(result["traceparent"]).to end_with("-00")
    end
  end

  describe "thread safety" do
    it "isolates context between threads" do
      trace1 = MiniAPM::Trace.new
      trace2 = MiniAPM::Trace.new

      thread1_trace_id = nil
      thread2_trace_id = nil

      thread1 = Thread.new do
        described_class.current_trace = trace1
        sleep 0.01
        thread1_trace_id = described_class.current_trace_id
      end

      thread2 = Thread.new do
        described_class.current_trace = trace2
        sleep 0.01
        thread2_trace_id = described_class.current_trace_id
      end

      thread1.join
      thread2.join

      expect(thread1_trace_id).to eq(trace1.trace_id)
      expect(thread2_trace_id).to eq(trace2.trace_id)
      expect(thread1_trace_id).not_to eq(thread2_trace_id)
    end
  end
end
