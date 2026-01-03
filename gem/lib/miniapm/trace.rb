# frozen_string_literal: true

require "securerandom"

module MiniAPM
  class Trace
    attr_reader :trace_id
    attr_accessor :sampled

    def initialize(trace_id: nil, sampled: nil)
      @trace_id = trace_id || SecureRandom.hex(16)
      @sampled = sampled.nil? ? should_sample? : sampled
      @mutex = Mutex.new
    end

    def sampled?
      @sampled
    end

    private

    def should_sample?
      rand < MiniAPM.configuration.sample_rate
    end
  end
end
