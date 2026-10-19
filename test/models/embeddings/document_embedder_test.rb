require "test_helper"

class Embeddings::DocumentEmbedderTest < ActiveSupport::TestCase
  class RecordingLimiter
    attr_reader :acquired

    def initialize
      @acquired = []
    end

    def acquire(tokens)
      @acquired << tokens
    end
  end

  setup do
    @document = documents(:handbook)
    @fake = FakeEmbedder.new
    @limiter = RecordingLimiter.new
  end

  test "embeds every chunk with the raw input, model, dimensions, and input hash" do
    embedder.call(@document, strategy: :raw)

    @document.chunks.each do |chunk|
      embedding = chunk.embeddings.sole
      assert_equal [ "voyage-4-lite", "raw", 1024 ], [ embedding.model, embedding.strategy, embedding.dimensions ]
      assert_equal chunk.embedding_input_hash(:raw), embedding.input_hash
      assert_in_delta 0, (embedding.embedding.zip(@fake.vector_for(chunk.embedding_input(:raw))).sum { (_1 - _2).abs }), 1e-4
    end
    assert_equal [ @document.chunks.order(:position).map { it.embedding_input(:raw) } ], @fake.batches
  end

  test "skips chunks whose embedding has a matching input hash" do
    embedder.call(@document, strategy: :raw)
    @fake.batches.clear

    embedder.call(@document, strategy: :raw)
    assert_empty @fake.batches
  end

  test "re-embeds only the chunk whose input changed, replacing its stale embedding" do
    embedder.call(@document, strategy: :raw)
    leave = chunks(:leave)
    stale = leave.embeddings.sole
    untouched = chunks(:intro).embeddings.sole
    @fake.batches.clear

    leave.update!(content: "Full-time employees accrue 25 days of paid leave per year.")
    embedder.call(@document, strategy: :raw)

    assert_equal [ [ leave.embedding_input(:raw) ] ], @fake.batches
    fresh = leave.embeddings.sole
    assert_equal stale.id, fresh.id
    assert_equal leave.embedding_input_hash(:raw), fresh.input_hash
    assert_not_equal stale.input_hash, fresh.input_hash
    assert_not_equal stale.embedding, fresh.embedding
    assert_equal untouched.updated_at, untouched.reload.updated_at
  end

  test "treats an embedding from another model as missing" do
    ChunkEmbedding.create!(chunk: chunks(:intro), model: "other-model", strategy: :raw, dimensions: 1024, embedding: @fake.vector_for("x"), input_hash: chunks(:intro).embedding_input_hash(:raw))

    assert_equal 2, embedder.pending(@document, :raw).size
  end

  test "batches by size" do
    add_chunks(5, words: 10)
    embedder(batch_size: 3).call(@document, strategy: :raw)

    assert_equal [ 3, 3, 1 ], @fake.batches.map(&:size)
    assert_equal 3, @limiter.acquired.size
  end

  test "batches by estimated tokens, sending an oversized input alone" do
    add_chunks(3, words: 100) # ~150 tokens each
    inputs = embedder.pending(@document, :raw)
    tokens = inputs.map(&:tokens)

    batches = embedder(max_batch_tokens: tokens.last(3).sum - 1).batches(inputs)
    assert_equal [ 4, 1 ], batches.map(&:size)
    assert batches.all? { |batch| batch.size == 1 || batch.sum(&:tokens) < tokens.last(3).sum }

    assert_equal [ [ inputs.first ], [ inputs.second ] ], embedder(max_batch_tokens: 1).batches(inputs.first(2))
  end

  test "acquires the rate limiter with each batch's estimated tokens before sending it" do
    add_chunks(2, words: 10)
    inputs = embedder.pending(@document, :raw)
    embedder(batch_size: 2).call(@document, strategy: :raw)

    assert_equal inputs.each_slice(2).map { it.sum(&:tokens) }, @limiter.acquired
  end

  test "keeps the batches saved before a failure" do
    add_chunks(2, words: 10)
    failing = embedder(batch_size: 2)
    calls = 0
    @fake.define_singleton_method(:embed_documents) do |texts|
      raise Embeddings::Embedder::TransientError, "rate limited" if (calls += 1) == 2
      super(texts)
    end

    assert_raises(Embeddings::Embedder::TransientError) { failing.call(@document, strategy: :raw) }
    assert_equal 2, ChunkEmbedding.count
    assert_equal 2, failing.pending(@document, :raw).size
  end

  test "raises a permanent error when the embedder returns fewer vectors than inputs" do
    @fake.define_singleton_method(:embed_documents) { |texts| super(texts).drop(1) }

    error = assert_raises(Embeddings::Embedder::PermanentError) { embedder.call(@document, strategy: :raw) }
    assert_equal "Embedder returned 1 vectors for 2 inputs", error.message
    assert_equal 0, ChunkEmbedding.count
  end

  test "raises a permanent error when a vector has the wrong dimensions" do
    @fake.define_singleton_method(:embed_documents) { |texts| super(texts).tap { it[1] = it[1].first(512) } }

    error = assert_raises(Embeddings::Embedder::PermanentError) { embedder.call(@document, strategy: :raw) }
    assert_equal "Embedder returned a 512-dimension vector, expected 1024", error.message
    assert_equal 0, ChunkEmbedding.count
  end

  test "estimates chunks, tokens, and requests" do
    add_chunks(3, words: 10)
    inputs = embedder.pending(@document, :raw)

    assert_equal({ chunks: 5, tokens: inputs.sum(&:tokens), requests: 2 }, embedder(batch_size: 4).estimate(inputs))
  end

  private
    def embedder(batch_size: 128, max_batch_tokens: 8_000)
      Embeddings::DocumentEmbedder.new(embedder: @fake, limiter: @limiter, batch_size: batch_size, max_batch_tokens: max_batch_tokens)
    end

    def add_chunks(count, words:)
      start = @document.chunks.maximum(:position) + 1
      count.times do |i|
        @document.chunks.create!(position: start + i, content: ([ "word#{i}" ] * words).join(" "), heading_path: [ "Employee Handbook" ], token_count: words, content_hash: "hash-#{i}")
      end
    end
end
