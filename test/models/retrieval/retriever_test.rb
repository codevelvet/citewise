require "test_helper"

class Retrieval::RetrieverTest < ActiveSupport::TestCase
  setup do
    @query = axis(0)
    query = @query
    @embedder = FakeEmbedder.new
    @embedder.define_singleton_method(:embed_query) { |_text| query }
    @retriever = Retrieval::Retriever.new(embedder: @embedder)

    @document = documents(:pending_upload)
    @nearest = embed(chunk_at(0), blend(0, 1, 0.1))
    @middle = embed(chunk_at(1), blend(0, 1, 0.5))
    @farthest = embed(chunk_at(2), axis(1))
  end

  test "k and strategy come from app configuration" do
    retriever = Retrieval::Retriever.new(embedder: @embedder)
    assert_equal [ 8, "raw" ], [ retriever.k, retriever.strategy ]
  end

  test "returns chunks nearest first, with rank and cosine similarity" do
    results = @retriever.call("How much paid leave do I get?")

    assert_equal [ @nearest, @middle, @farthest ], results.map(&:chunk)
    assert_equal [ 1, 2, 3 ], results.map(&:rank)
    assert_in_delta 1 / Math.sqrt(1.01), results[0].similarity, 1e-6
    assert_in_delta 1 / Math.sqrt(1.25), results[1].similarity, 1e-6
    assert_in_delta 0.0, results[2].similarity, 1e-6
    assert_equal @document.title, results.first.chunk.document.title
  end

  test "only searches embeddings for the embedder's model and the configured strategy" do
    # Exact matches for the query, which the model and strategy filter must exclude
    other = chunk_at(3)
    embed(other, @query, strategy: :contextual)
    embed(other, @query, model: "voyage-4")

    assert_equal [ @nearest, @middle, @farthest ], @retriever.call("question").map(&:chunk)
  end

  test "k limits the results" do
    assert_equal [ @nearest, @middle ], @retriever.call("question", k: 2).map(&:chunk)
    assert_equal [ @nearest ], Retrieval::Retriever.new(embedder: @embedder, k: 1).call("question").map(&:chunk)
  end

  test "skips chunks deleted after the nearest-neighbor query" do
    # Re-ingesting a document between the kNN query and the chunk load deletes its chunks.
    middle = @middle
    @retriever.define_singleton_method(:relation) { |vector, k| super(vector, k).load.tap { middle.destroy! } }

    results = @retriever.call("question")

    assert_equal [ @nearest, @farthest ], results.map(&:chunk)
    assert_equal [ 1, 2 ], results.map(&:rank)
  end

  test "finds every live chunk even after many deleted embeddings" do
    # Deleted rows near the query, like a re-ingest or rolled-back tests leave
    # behind. An approximate index scan could miss live rows past them.
    ChunkEmbedding.transaction(requires_new: true) do
      200.times { |i| embed(chunk_at(100 + i), i.even? ? blend(0, 1, 0.1) : blend(0, 1, 0.5)) }
      raise ActiveRecord::Rollback
    end

    assert_equal [ @nearest, @middle, @farthest ], @retriever.call("question").map(&:chunk)
  end

  test "binds the query vector" do
    sql, binds = query_of(@retriever.relation(@query, 8))

    assert_includes sql, "ORDER BY \"chunk_embeddings\".\"embedding\" <=> $"
    assert_no_match(/\[[-\d.,e]+\]/, sql)
    assert_equal [ "query_embedding", "model", "strategy", "query_embedding", "LIMIT" ], binds
  end

  private
    # The SQL and bind names Rails sends when the relation runs.
    def query_of(relation)
      payload = nil
      callback = ->(event) { payload = event.payload if event.payload[:name] == "ChunkEmbedding Load" }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { relation.load }
      [ payload[:sql], payload[:binds].map(&:name) ]
    end

    def chunk_at(position)
      @document.chunks.create!(position: position, content: "Chunk #{position}", token_count: 2, content_hash: "hash-#{position}")
    end

    def embed(chunk, vector, model: "voyage-4-lite", strategy: :raw)
      ChunkEmbedding.create!(chunk: chunk, model: model, strategy: strategy, dimensions: vector.size, embedding: vector, input_hash: "abc")
      chunk
    end

    def axis(index, size: 1024)
      Array.new(size, 0.0).tap { |vector| vector[index] = 1.0 }
    end

    def blend(primary, secondary, weight)
      axis(primary).zip(axis(secondary)).map { |a, b| a + weight * b }
    end
end
