# frozen_string_literal: true

require "digest"
require "time"

module MiniAPM
  class ErrorEvent
    attr_reader :exception_class, :message, :backtrace, :fingerprint
    attr_reader :request_id, :user_id, :params, :timestamp
    attr_reader :context

    def initialize(
      exception_class:,
      message:,
      backtrace:,
      fingerprint: nil,
      request_id: nil,
      user_id: nil,
      params: nil,
      timestamp: nil,
      context: {}
    )
      @exception_class = exception_class
      @message = truncate(message, 10_000)
      @backtrace = backtrace&.first(50) || []
      @fingerprint = fingerprint || generate_fingerprint
      @request_id = request_id
      @user_id = user_id&.to_s
      @params = filter_params(params)
      @timestamp = timestamp || Time.now.utc
      @context = context
    end

    def self.from_exception(exception, context = {})
      new(
        exception_class: exception.class.name,
        message: exception.message,
        backtrace: exception.backtrace,
        request_id: context[:request_id] || MiniAPM.current_trace_id,
        user_id: context[:user_id],
        params: context[:params],
        context: context.except(:request_id, :user_id, :params)
      )
    end

    def to_h
      {
        exception_class: @exception_class,
        message: @message,
        backtrace: @backtrace,
        fingerprint: @fingerprint,
        request_id: @request_id,
        user_id: @user_id,
        params: @params,
        timestamp: @timestamp.iso8601
      }.compact
    end

    private

    def generate_fingerprint
      # Create a stable fingerprint from exception class, message pattern, and first app backtrace line
      parts = [@exception_class]

      # Normalize message (remove variable parts like IDs, timestamps)
      # Order matters: replace UUIDs first before numbers break the pattern
      normalized_message = @message.to_s
        .gsub(/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i, "UUID")  # Replace UUIDs first
        .gsub(/\b\d+\b/, "N")                    # Replace numbers
        .gsub(/'[^']*'/, "'X'")                  # Replace quoted strings
        .gsub(/"[^"]*"/, '"X"')                  # Replace double-quoted strings
        .slice(0, 200)

      parts << normalized_message

      # Find first application backtrace line (not gem/stdlib)
      app_line = @backtrace.find do |line|
        !line.include?("/gems/") &&
        !line.include?("/ruby/") &&
        !line.include?("/vendor/") &&
        !line.start_with?("<")
      end
      parts << app_line if app_line

      Digest::SHA256.hexdigest(parts.join("\n"))[0, 32]
    end

    MAX_FILTER_DEPTH = 10

    def filter_params(params)
      return nil unless params.is_a?(Hash)

      filter_keys = MiniAPM.configuration.filter_parameters

      deep_filter(params, filter_keys, 0)
    end

    def deep_filter(hash, filter_keys, depth)
      return { "__truncated__" => "max depth exceeded" } if depth >= MAX_FILTER_DEPTH

      hash.each_with_object({}) do |(key, value), result|
        if filter_keys.any? { |f| key_matches?(key, f) }
          result[key] = "[FILTERED]"
        elsif value.is_a?(Hash)
          result[key] = deep_filter(value, filter_keys, depth + 1)
        elsif value.is_a?(Array)
          result[key] = value.first(100).map { |v| v.is_a?(Hash) ? deep_filter(v, filter_keys, depth + 1) : v }
        else
          result[key] = value
        end
      end
    end

    def key_matches?(key, filter)
      case filter
      when Regexp
        key.to_s.match?(filter)
      else
        key.to_s.downcase.include?(filter.to_s.downcase)
      end
    end

    def truncate(string, max_length)
      return nil if string.nil?

      string = string.to_s
      string.length > max_length ? string[0, max_length] + "..." : string
    end
  end
end
