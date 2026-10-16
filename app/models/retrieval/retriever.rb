module Retrieval
  # Finds the chunks nearest a question by cosine distance between embeddings.
  #
  #   Retrieval::Retriever.new.call("How much paid leave do I get?")
  #   # => [ Result(chunk:, similarity: 0.83, rank: 1), ... ], nearest first
  #
  # Only embeddings from the embedder's model and the configured strategy are
  # searched, matching the partial HNSW index on chunk_embeddings.
  class Retriever
    Result = Data.define(:chunk, :similarity, :rank)

    attr_reader :embedder, :strategy, :k

    def initialize(embedder: Embeddings::Embedder.default, strategy: Rails.configuration.x.retrieval[:strategy], k: Rails.configuration.x.retrieval[:k])
      @embedder = embedder
      @strategy = strategy
      @k = k
    end

    def call(text, k: self.k)
      rows = relation(embedder.embed_query(text), k).map { [ it.chunk_id, it.distance ] }
      chunks = Chunk.includes(:document).where(id: rows.map(&:first)).index_by(&:id)

      rows.each_with_index.map do |(chunk_id, distance), index|
        Result.new(chunk: chunks.fetch(chunk_id), similarity: 1 - distance, rank: index + 1)
      end
    end

    # The nearest-neighbor query. ORDER BY repeats the index expression
    # (embedding::vector(D) <=> query) and WHERE repeats its predicate, so
    # Postgres can use the partial HNSW index. The query vector is a bound
    # parameter, which the SQL log shows as [FILTERED]. Model and strategy are
    # literals, not binds: a generic plan for a prepared statement can't prove
    # a partial index's predicate from parameters.
    def relation(vector, k)
      ChunkEmbedding
        .where(ChunkEmbedding.sanitize_sql_array([ "chunk_embeddings.model = ? AND chunk_embeddings.strategy = ?", embedder.model, strategy.to_s ]))
        .select(:chunk_id, distance_to(vector).as("distance"))
        .order(distance_to(vector))
        .limit(k)
    end

    private
      def distance_to(vector)
        dimensions = Integer(embedder.dimensions)
        query = Arel::Nodes::BindParam.new(ActiveRecord::Relation::QueryAttribute.new("query_embedding", vector, ChunkEmbedding.type_for_attribute(:embedding)))
        Arel::Nodes::InfixOperation.new("<=>",
          Arel.sql("chunk_embeddings.embedding::vector(#{dimensions})"),
          Arel::Nodes::InfixOperation.new("::", query, Arel.sql("vector(#{dimensions})")))
      end
  end
end
