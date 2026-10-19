module Embeddings
  # Embeds a document's chunks that have no up-to-date embedding for the
  # embedder's model and the given strategy.
  #
  #   Embeddings::DocumentEmbedder.new.call(document, strategy: :raw)
  #
  # A chunk is up to date when its stored input_hash matches the hash of
  # Chunk#embedding_input, so rerunning only embeds missing or stale chunks.
  # Each batch is saved as soon as it returns, so a retry after a failed batch
  # skips the batches before it.
  class DocumentEmbedder
    Input = Data.define(:chunk, :text, :input_hash, :tokens)

    attr_reader :embedder

    def initialize(embedder: Embedder.default, limiter: RateLimiter.default, token_counter: Chunking::TokenCounter::Approximate.new,
                   batch_size: Rails.configuration.x.embeddings[:batch_size], max_batch_tokens: Rails.configuration.x.embeddings[:max_batch_tokens])
      @embedder = embedder
      @limiter = limiter
      @token_counter = token_counter
      @batch_size = batch_size
      @max_batch_tokens = max_batch_tokens
    end

    def call(document, strategy:)
      batches(pending(document, strategy)).each do |batch|
        @limiter.acquire(batch.sum(&:tokens))
        vectors = embedder.embed_documents(batch.map(&:text))
        check!(batch, vectors)
        rows = batch.zip(vectors).map do |input, vector|
          { chunk_id: input.chunk.id, model: embedder.model, strategy: strategy.to_s, dimensions: embedder.dimensions, embedding: vector, input_hash: input.input_hash }
        end
        ChunkEmbedding.upsert_all(rows, unique_by: %i[chunk_id model strategy], update_only: %i[dimensions embedding input_hash])
      end
    end

    # Inputs for the chunks whose embedding is missing or stale, in document order.
    def pending(document, strategy)
      current = ChunkEmbedding.where(chunk: document.chunks, model: embedder.model, strategy: strategy.to_s, dimensions: embedder.dimensions)
        .pluck(:chunk_id, :input_hash).to_h

      document.chunks.order(:position).filter_map do |chunk|
        input_hash = chunk.embedding_input_hash(strategy)
        next if current[chunk.id] == input_hash

        text = chunk.embedding_input(strategy)
        Input.new(chunk: chunk, text: text, input_hash: input_hash, tokens: @token_counter.count(text))
      end
    end

    # Packs inputs in order into requests of at most batch_size inputs and
    # max_batch_tokens estimated tokens. An input over the token cap goes alone.
    def batches(inputs)
      inputs.each_with_object([]) do |input, batches|
        batch = batches.last
        if batch.nil? || batch.size >= @batch_size || batch.sum(&:tokens) + input.tokens > @max_batch_tokens
          batches << [ input ]
        else
          batch << input
        end
      end
    end

    def estimate(inputs)
      { chunks: inputs.size, tokens: inputs.sum(&:tokens), requests: batches(inputs).size }
    end

    private
      # upsert_all skips validations, so a short or malformed response would
      # otherwise surface as a database constraint error.
      def check!(batch, vectors)
        if vectors.size != batch.size
          raise Embedder::PermanentError, "Embedder returned #{vectors.size} vectors for #{batch.size} inputs"
        end

        if (wrong = vectors.find { it&.size != embedder.dimensions })
          raise Embedder::PermanentError, "Embedder returned a #{wrong&.size || 0}-dimension vector, expected #{embedder.dimensions}"
        end
      end
  end
end
