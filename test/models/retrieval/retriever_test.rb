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

  test "binds the query vector and keeps the index predicate literal" do
    sql, binds = query_of(@retriever.relation(@query, 8))

    assert_includes sql, "ORDER BY chunk_embeddings.embedding::vector(1024) <=> $2 :: vector(1024)"
    assert_includes sql, "chunk_embeddings.model = 'voyage-4-lite' AND chunk_embeddings.strategy = 'raw'"
    assert_no_match(/\[[-\d.,e]+\]/, sql)
    assert_equal [ "query_embedding", "query_embedding", "LIMIT" ], binds
  end

  test "uses the partial HNSW index, including under a generic prepared-statement plan" do
    relation = @retriever.relation(@query, 8)
    connection = ChunkEmbedding.connection
    connection.execute("SET LOCAL enable_seqscan = off")

    assert_includes relation.explain.inspect, "Index Scan using index_chunk_embeddings_on_voyage_4_lite_raw_embedding"

    # Rails prepares statements, and Postgres may switch to a generic plan after
    # five runs. A generic plan can only use the partial index if its predicate is literal.
    sql, _binds = query_of(relation)
    vector = connection.quote("[#{@query.join(",")}]")
    connection.execute("SET LOCAL plan_cache_mode = force_generic_plan")
    # Prepared statements outlive the test's rolled-back transaction, so deallocate it.
    connection.execute("PREPARE retriever_test_query AS #{sql}")
    begin
      plan = connection.select_values("EXPLAIN EXECUTE retriever_test_query(#{vector}, #{vector}, 8)").join("\n")
    ensure
      connection.execute("DEALLOCATE retriever_test_query")
    end
    assert_includes plan, "Index Scan using index_chunk_embeddings_on_voyage_4_lite_raw_embedding"
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
