# frozen_string_literal: true

require "securerandom"

module MiniAPM
  class Span
    # OTLP SpanKind values
    KINDS = {
      unspecified: 0,
      internal: 1,
      server: 2,
      client: 3,
      producer: 4,
      consumer: 5
    }.freeze

    # MiniAPM categories mapped to OTLP kinds
    CATEGORY_KINDS = {
      http_server: :server,
      http_client: :client,
      db: :client,
      view: :internal,
      search: :client,
      job: :consumer,
      rake: :internal,
      cache: :internal,
      internal: :internal
    }.freeze

    # Status codes
    STATUS_UNSET = 0
    STATUS_OK = 1
    STATUS_ERROR = 2

    # Limits to prevent memory issues
    MAX_NAME_LENGTH = 256
    MAX_ATTRIBUTE_KEY_LENGTH = 128
    MAX_ATTRIBUTE_VALUE_LENGTH = 4096
    MAX_ATTRIBUTES = 128
    MAX_EVENTS = 128
    MAX_EVENT_ATTRIBUTES = 32
    TRACE_ID_LENGTH = 32
    SPAN_ID_LENGTH = 16

    attr_reader :trace_id, :span_id, :parent_span_id
    attr_reader :name, :category, :kind
    attr_reader :start_time, :end_time
    attr_reader :attributes, :events
    attr_accessor :status_code, :status_message

    def initialize(
      name:,
      category: :internal,
      trace_id: nil,
      parent_span_id: nil,
      attributes: {}
    )
      @name = validate_name(name)
      @category = validate_category(category)
      @kind = KINDS[CATEGORY_KINDS[@category] || :internal]

      @trace_id = validate_trace_id(trace_id) || generate_trace_id
      @span_id = generate_span_id
      @parent_span_id = validate_span_id(parent_span_id)

      @start_time = Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond)
      @end_time = nil

      @attributes = {}
      @events = []

      @status_code = STATUS_UNSET
      @status_message = nil

      # Add initial attributes with validation
      attributes.each { |k, v| add_attribute(k, v) }
    end

    def self.new_root(name, category: :http_server, attributes: {})
      trace = Trace.new
      Context.current_trace = trace

      new(
        name: name,
        category: category,
        trace_id: trace.trace_id,
        attributes: attributes
      )
    end

    def create_child(name, category: :internal, attributes: {})
      self.class.new(
        name: name,
        category: category,
        trace_id: @trace_id,
        parent_span_id: @span_id,
        attributes: attributes
      )
    end

    def finish
      @end_time = Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond)
    end

    def duration_ns
      (@end_time || Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond)) - @start_time
    end

    def duration_ms
      duration_ns / 1_000_000.0
    end

    def add_attribute(key, value)
      return if @attributes.size >= MAX_ATTRIBUTES

      key = truncate(key.to_s, MAX_ATTRIBUTE_KEY_LENGTH)
      value = sanitize_attribute_value(value)

      @attributes[key] = value
    end

    def add_event(name, attributes: {})
      return if @events.size >= MAX_EVENTS

      event_attrs = {}
      attributes.first(MAX_EVENT_ATTRIBUTES).each do |k, v|
        key = truncate(k.to_s, MAX_ATTRIBUTE_KEY_LENGTH)
        event_attrs[key] = sanitize_attribute_value(v)
      end

      @events << {
        name: truncate(name, MAX_NAME_LENGTH),
        time_unix_nano: Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond),
        attributes: event_attrs
      }
    end

    def record_exception(exception)
      @status_code = STATUS_ERROR
      @status_message = truncate(exception.message, MAX_ATTRIBUTE_VALUE_LENGTH)

      add_event("exception", attributes: {
        "exception.type" => exception.class.name,
        "exception.message" => exception.message,
        "exception.stacktrace" => exception.backtrace&.first(30)&.join("\n")
      })
    end

    def set_error(message = nil)
      @status_code = STATUS_ERROR
      @status_message = message ? truncate(message, MAX_ATTRIBUTE_VALUE_LENGTH) : nil
    end

    def set_ok
      @status_code = STATUS_OK
    end

    def root?
      @parent_span_id.nil?
    end

    def error?
      @status_code == STATUS_ERROR
    end

    # Convert to OTLP JSON format
    def to_otlp
      span_data = {
        "traceId" => @trace_id,
        "spanId" => @span_id,
        "name" => @name,
        "kind" => @kind,
        "startTimeUnixNano" => @start_time.to_s,
        "endTimeUnixNano" => (@end_time || @start_time).to_s,
        "attributes" => attributes_to_otlp,
        "status" => build_status
      }

      span_data["parentSpanId"] = @parent_span_id if @parent_span_id
      span_data["events"] = events_to_otlp if @events.any?

      span_data
    end

    private

    def validate_name(name)
      truncate(name.to_s, MAX_NAME_LENGTH)
    end

    def validate_category(category)
      cat = category.to_sym
      CATEGORY_KINDS.key?(cat) ? cat : :internal
    end

    def validate_trace_id(trace_id)
      return nil if trace_id.nil?

      str = trace_id.to_s.downcase
      return nil unless str.match?(/\A[0-9a-f]{32}\z/)

      str
    end

    def validate_span_id(span_id)
      return nil if span_id.nil?

      str = span_id.to_s.downcase
      return nil unless str.match?(/\A[0-9a-f]{16}\z/)

      str
    end

    def generate_trace_id
      SecureRandom.hex(16)
    end

    def generate_span_id
      SecureRandom.hex(8)
    end

    def truncate(string, max_length)
      return "" if string.nil?

      str = string.to_s
      str.length > max_length ? str[0, max_length] : str
    end

    def sanitize_attribute_value(value)
      case value
      when String
        truncate(value, MAX_ATTRIBUTE_VALUE_LENGTH)
      when Integer, Float, TrueClass, FalseClass, NilClass
        value
      when Array
        # Limit array size and sanitize each element
        value.first(32).map { |v| sanitize_attribute_value(v) }
      when Hash
        # Convert hash to string representation
        truncate(value.to_s, MAX_ATTRIBUTE_VALUE_LENGTH)
      else
        truncate(value.to_s, MAX_ATTRIBUTE_VALUE_LENGTH)
      end
    end

    def attributes_to_otlp
      @attributes.map do |key, value|
        { "key" => key, "value" => value_to_otlp(value) }
      end
    end

    def events_to_otlp
      @events.map do |event|
        {
          "name" => event[:name],
          "timeUnixNano" => event[:time_unix_nano].to_s,
          "attributes" => event[:attributes].map do |k, v|
            { "key" => k, "value" => value_to_otlp(v) }
          end
        }
      end
    end

    def value_to_otlp(value)
      case value
      when String
        { "stringValue" => value }
      when Integer
        { "intValue" => value.to_s }
      when Float
        { "doubleValue" => value }
      when TrueClass, FalseClass
        { "boolValue" => value }
      when Array
        { "arrayValue" => { "values" => value.map { |v| value_to_otlp(v) } } }
      when nil
        { "stringValue" => "" }
      else
        { "stringValue" => value.to_s }
      end
    end

    def build_status
      status = { "code" => @status_code }
      status["message"] = @status_message if @status_message
      status
    end
  end
end
