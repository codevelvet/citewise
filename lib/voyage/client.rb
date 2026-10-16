module Voyage
  # POSTs to Voyage's /embeddings endpoint.
  #
  #   client = Voyage::Client.new(api_key: key, base_url: "https://ai.mongodb.com/v1")
  #   client.embed([ "text" ], model: "voyage-4-lite", input_type: "document", output_dimension: 1024)
  #   # => { vectors: [ [ 0.01, ... ] ], total_tokens: 2 }
  #
  # Raises Voyage::TransientError for 429, 5xx, and timeouts, and
  # Voyage::PermanentError for any other unsuccessful response.
  class Client
    def initialize(api_key:, base_url:, timeout: 60)
      @connection = Faraday.new(url: base_url, request: { timeout: timeout }) do |faraday|
        faraday.request :authorization, "Bearer", api_key
        faraday.request :json
        faraday.response :json
      end
    end

    def embed(texts, model:, input_type:, output_dimension:)
      body = post("embeddings", input: texts, model: model, input_type: input_type, output_dimension: output_dimension)
      vectors = body.fetch("data").sort_by { it.fetch("index") }.map { it.fetch("embedding") }
      { vectors: vectors, total_tokens: body.dig("usage", "total_tokens") }
    end

    private
      def post(path, payload)
        response = @connection.post(path, payload)
        raise error_for(response) unless response.success?
        response.body
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => error
        raise TransientError, "Voyage #{error.class}: #{error.message}"
      end

      def error_for(response)
        detail = response.body.is_a?(Hash) ? response.body["detail"] : response.body
        message = "Voyage #{response.status}: #{detail}"

        if response.status == 429 || response.status >= 500
          TransientError.new(message, retry_after: retry_after(response.headers["retry-after"]))
        else
          PermanentError.new(message)
        end
      end

      # Retry-After is either a number of seconds or an HTTP date.
      def retry_after(value)
        return if value.blank?

        Float(value, exception: false) || [ Time.httpdate(value) - Time.now, 0 ].max
      rescue ArgumentError
        nil
      end
  end
end
