# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module MiniAPM
  module Transport
    class HTTP
      DEFAULT_TIMEOUT = 10
      DEFAULT_OPEN_TIMEOUT = 5

      class << self
        def post(url, payload, headers: {})
          uri = URI.parse(url)

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = DEFAULT_OPEN_TIMEOUT
          http.read_timeout = DEFAULT_TIMEOUT
          http.write_timeout = DEFAULT_TIMEOUT if http.respond_to?(:write_timeout=)

          request = Net::HTTP::Post.new(uri.request_uri)
          request["Content-Type"] = "application/json"
          request["User-Agent"] = "miniapm-ruby/#{MiniAPM::VERSION}"

          headers.each { |key, value| request[key] = value }

          request.body = payload.is_a?(String) ? payload : JSON.generate(payload)

          response = http.request(request)

          {
            status: response.code.to_i,
            body: response.body,
            success: response.is_a?(Net::HTTPSuccess)
          }
        rescue StandardError => e
          MiniAPM.logger.warn { "MiniAPM HTTP error: #{e.class}: #{e.message}" }
          { status: 0, body: e.message, success: false, error: e }
        end
      end
    end
  end
end
