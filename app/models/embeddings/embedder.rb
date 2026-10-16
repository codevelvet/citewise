module Embeddings
  # What the app needs from an embedding provider. Nothing outside an
  # implementation may call a provider directly, so switching providers means
  # writing one subclass and returning it from Embedder.default.
  #
  #   embedder = Embeddings::Embedder.default
  #   embedder.embed_documents([ "text", ... ]) # => [ [ Float, ... ], ... ], one vector per text, in order
  #   embedder.embed_query("question")         # => [ Float, ... ]
  #
  # Implementations raise TransientError for failures worth retrying and
  # PermanentError for the rest.
  class Embedder
    class Error < StandardError; end

    class TransientError < Error
      # Seconds the provider asked us to wait, if it said.
      attr_reader :retry_after

      def initialize(message = nil, retry_after: nil)
        super(message)
        @retry_after = retry_after
      end
    end

    class PermanentError < Error; end

    def self.default
      config = Rails.configuration.x.embeddings
      VoyageEmbedder.new(model: config[:model], dimensions: config[:dimensions], base_url: config[:base_url])
    end

    # Recorded on every ChunkEmbedding this embedder produces.
    attr_reader :model, :dimensions

    def initialize(model:, dimensions:)
      @model = model
      @dimensions = dimensions
    end

    def embed_documents(texts)
      raise NotImplementedError
    end

    def embed_query(text)
      raise NotImplementedError
    end
  end
end
