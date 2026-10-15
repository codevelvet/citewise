require "test_helper"

class ChunkEmbeddingTest < ActiveSupport::TestCase
  test "is valid with a chunk, model, strategy, and matching dimensions" do
    assert build_embedding.valid?
  end

  test "requires a chunk, model, and embedding" do
    embedding = ChunkEmbedding.new(strategy: :raw, dimensions: 1024)
    assert_not embedding.valid?
    assert_includes embedding.errors[:chunk], "must exist"
    assert_includes embedding.errors[:model], "can't be blank"
    assert_includes embedding.errors[:embedding], "can't be blank"
  end

  test "rejects an unknown strategy" do
    embedding = build_embedding(strategy: "hybrid")
    assert_not embedding.valid?
    assert_includes embedding.errors[:strategy], "is not included in the list"
  end

  test "requires positive dimensions" do
    embedding = build_embedding(dimensions: 0)
    assert_not embedding.valid?
    assert_includes embedding.errors[:dimensions], "must be greater than 0"
  end

  test "requires the embedding size to match dimensions" do
    embedding = build_embedding(dimensions: 512)
    assert_not embedding.valid?
    assert_includes embedding.errors[:embedding], "must have 512 dimensions (has 1024)"
  end

  test "enforces embedding size matching dimensions in the database" do
    error = assert_raises ActiveRecord::StatementInvalid do
      ChunkEmbedding.insert_all!([ { chunk_id: chunks(:intro).id, model: "other-model", strategy: "raw", dimensions: 4, embedding: [ 1, 0, 0 ] } ])
    end
    assert_match "chunk_embeddings_embedding_matches_dimensions", error.message
  end

  test "a chunk holds embeddings for several models and strategies side by side" do
    chunk = chunks(:intro)
    build_embedding(chunk: chunk, strategy: :raw).save!
    build_embedding(chunk: chunk, strategy: :contextual).save!
    build_embedding(chunk: chunk, model: "other-model", dimensions: 3, embedding: [ 1, 0, 0 ]).save!

    assert_equal 3, chunk.embeddings.count
  end

  test "validates uniqueness of model and strategy per chunk" do
    build_embedding.save!
    duplicate = build_embedding
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:model], "has already been taken"
  end

  test "enforces uniqueness of model and strategy per chunk in the database" do
    build_embedding.save!
    assert_raises ActiveRecord::RecordNotUnique do
      ChunkEmbedding.insert_all!([ { chunk_id: chunks(:intro).id, model: "voyage-4-lite", strategy: "raw", dimensions: 1024, embedding: axis(0) } ])
    end
  end

  test "deleting a chunk deletes its embeddings" do
    chunk = chunks(:intro)
    build_embedding(chunk: chunk).save!

    assert_difference -> { ChunkEmbedding.count }, -1 do
      chunk.destroy
    end
  end

  test "nearest neighbors for voyage-4-lite raw embeddings, using the partial HNSW index" do
    document = documents(:pending_upload)
    chunk_at = ->(position) { document.chunks.create!(position: position, content: "Chunk #{position}", token_count: 2, content_hash: "hash-#{position}") }

    query = axis(0)
    nearest = build_embedding(chunk: chunk_at.(0), embedding: blend(0, 1, 0.1)).tap(&:save!)
    middle = build_embedding(chunk: chunk_at.(1), embedding: blend(0, 1, 0.5)).tap(&:save!)
    farthest = build_embedding(chunk: chunk_at.(2), embedding: axis(1)).tap(&:save!)

    # Exact matches for the query that the index predicate must exclude
    build_embedding(chunk: nearest.chunk, strategy: :contextual, embedding: query).save!
    build_embedding(chunk: nearest.chunk, model: "voyage-4", embedding: query).save!

    neighbors = ChunkEmbedding
      .where(model: "voyage-4-lite", strategy: "raw")
      .order(ChunkEmbedding.sanitize_sql_for_order([ Arel.sql("embedding::vector(1024) <=> ?::vector(1024)"), vector_literal(query) ]))
      .limit(5)

    assert_equal [ nearest, middle, farthest ], neighbors.to_a

    ChunkEmbedding.connection.execute("SET LOCAL enable_seqscan = off")
    plan = ChunkEmbedding.connection.select_values("EXPLAIN #{neighbors.to_sql}").join("\n")
    assert_includes plan, "index_chunk_embeddings_on_voyage_4_lite_raw_embedding"
  end

  private
    def build_embedding(chunk: chunks(:intro), model: "voyage-4-lite", strategy: :raw, dimensions: 1024, embedding: axis(0))
      ChunkEmbedding.new(chunk: chunk, model: model, strategy: strategy, dimensions: dimensions, embedding: embedding)
    end

    def axis(index, size: 1024)
      Array.new(size, 0.0).tap { |vector| vector[index] = 1.0 }
    end

    def blend(primary, secondary, weight)
      axis(primary).zip(axis(secondary)).map { |a, b| a + weight * b }
    end

    def vector_literal(vector)
      "[#{vector.join(",")}]"
    end
end
