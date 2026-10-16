module Embeddings
  # Embeds with Voyage, using its separate document and query input types.
  class VoyageEmbedder < Embedder
    def initialize(model:, dimensions:, base_url:, api_key: ENV.fetch("VOYAGE_API_KEY") { Rails.application.credentials.dig(:voyage, :api_key) })
      super(model: model, dimensions: dimensions)
      @client = Voyage::Client.new(api_key: api_key, base_url: base_url)
    end

    def embed_documents(texts)
      embed(texts, input_type: "document")
    end

    def embed_query(text)
      embed([ text ], input_type: "query").first
    end

    private
      def embed(texts, input_type:)
        result = @client.embed(texts, model: model, input_type: input_type, output_dimension: dimensions)
        Rails.logger.info "Voyage embed model=#{model} input_type=#{input_type} inputs=#{texts.size} total_tokens=#{result[:total_tokens]}"
        result[:vectors]
      rescue Voyage::TransientError => error
        raise TransientError.new(error.message, retry_after: error.retry_after)
      rescue Voyage::PermanentError => error
        raise PermanentError, error.message
      end
  end
end
