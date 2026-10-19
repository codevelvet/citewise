require "test_helper"

class Answering::AskServiceTest < ActiveSupport::TestCase
  include FakeAnswerer::TestHelper

  QUESTION = "How much paid leave do I get?"

  setup do
    @embedder = FakeEmbedder.new
    # The question's vector equals the leave chunk's, so leave ranks first.
    leave_vector = @embedder.vector_for("leave")
    @embedder.define_singleton_method(:embed_query) { |_text| leave_vector }
    embed(chunks(:leave), leave_vector)
    embed(chunks(:intro), @embedder.vector_for("intro"))
  end

  test "records retrieval, citations, model, token usage, and latencies" do
    question = ask

    assert question.answered?
    assert_equal QUESTION, question.text
    assert_equal "Full-time employees accrue 20 days of paid leave per year.", question.answer
    assert_equal "claude-haiku-4-5", question.model

    assert_equal [ chunks(:leave).id, chunks(:intro).id ], question.retrieval.map { it["chunk_id"] }
    assert_equal [ 1, 2 ], question.retrieval.map { it["rank"] }
    assert_in_delta 1.0, question.retrieval.first["similarity"], 1e-6
    assert_equal({ "document_id" => documents(:handbook).id, "document_title" => "Employee Handbook",
                   "source_title" => "Employee Handbook > Benefits > Paid leave", "content" => chunks(:leave).content },
                 question.retrieval.first.slice("document_id", "document_title", "source_title", "content"))

    assert_equal [ { "chunk_id" => chunks(:leave).id, "cited_text" => chunks(:leave).content, "block_start" => 0, "block_end" => 1, "answer_start" => 0, "answer_end" => question.answer.length,
                     "document_id" => documents(:handbook).id, "document_title" => "Employee Handbook",
                     "source_title" => "Employee Handbook > Benefits > Paid leave" } ], question.citations

    assert_equal [ 900, 40, 0, 0 ], question.slice(:input_tokens, :output_tokens, :cache_read_tokens, :cache_write_tokens).values
    assert_operator question.retrieval_ms, :>=, 0
    assert_operator question.answer_ms, :>=, 0
  end

  test "sends the retrieved chunks to the answerer in rank order" do
    answerer = FakeAnswerer.new
    ask(answerer)
    assert_equal [ [ QUESTION, [ chunks(:leave), chunks(:intro) ] ] ], answerer.calls
  end

  test "a stored question keeps its snapshots after its chunks are deleted" do
    question = ask
    documents(:handbook).chunks.delete_all

    question.reload
    assert_equal "Employee Handbook > Benefits > Paid leave", question.citations.first["source_title"]
    assert_equal chunks(:leave).content, question.retrieval.first["content"]
  end

  test "an answer without citations is still answered" do
    question = ask(FakeAnswerer.new(text: "The documents don't cover that.", cite: false))

    assert question.answered?
    assert_equal "The documents don't cover that.", question.answer
    assert_equal [], question.citations
  end

  test "with nothing retrieved, Claude isn't asked and the question gets a fixed answer" do
    ChunkEmbedding.delete_all
    answerer = FakeAnswerer.new
    log = StringIO.new

    question = with_logger(log) { ask(answerer) }

    assert_empty answerer.calls
    assert question.answered?
    assert_equal Answering::AskService::NO_SOURCES_ANSWER, question.answer
    assert_nil question.model
    assert_equal [ [], [] ], [ question.retrieval, question.citations ]
    assert_equal [ 0, 0, 0, 0 ], question.slice(:input_tokens, :output_tokens, :cache_read_tokens, :cache_write_tokens).values
    assert_nil question.answer_ms
    assert_match(/Question #{question.id} retrieved no chunks: no embeddings for voyage-4-lite\/raw/, log.string)
  end

  test "an embedding failure marks the question failed and re-raises" do
    [ Embeddings::Embedder::TransientError.new("Voyage 429: Slow down"), Embeddings::Embedder::PermanentError.new("Voyage 401: Bad key") ].each do |failure|
      @embedder.define_singleton_method(:embed_query) { |_text| raise failure }

      raised = assert_raises(failure.class) { ask }
      question = Question.last
      assert question.failed?
      assert_equal failure.message, question.error
      assert_equal raised, failure
      assert_equal [], question.retrieval
    end
  end

  test "an answering failure marks the question failed, keeping retrieval, and re-raises" do
    [ Answering::Answerer::TransientError.new("Claude 529: Overloaded"), Answering::Answerer::PermanentError.new("Claude 400: Bad request") ].each do |failure|
      answerer = FakeAnswerer.new
      answerer.error = failure

      assert_raises(failure.class) { ask(answerer) }
      question = Question.last
      assert question.failed?
      assert_equal failure.message, question.error
      assert_nil question.answer
      assert_equal 2, question.retrieval.size
    end
  end

  test "an unexpected error marks the question failed and re-raises" do
    @embedder.define_singleton_method(:embed_query) { |_text| raise "boom" }

    assert_raises(RuntimeError) { ask }
    question = Question.last
    assert question.failed?
    assert_equal "boom", question.error
  end

  test "uses the default retriever and answerer" do
    question = with_fake_embedder(@embedder) { with_fake_answerer { Answering::AskService.call(QUESTION) } }

    assert question.answered?
    assert_equal chunks(:leave).id, question.citations.first["chunk_id"]
  end

  private
    def ask(answerer = FakeAnswerer.new)
      Answering::AskService.call(QUESTION, retriever: Retrieval::Retriever.new(embedder: @embedder), answerer: answerer)
    end

    def with_logger(io)
      original = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(io)
      yield
    ensure
      Rails.logger = original
    end

    def embed(chunk, vector)
      ChunkEmbedding.create!(chunk: chunk, model: "voyage-4-lite", strategy: :raw, dimensions: vector.size, embedding: vector, input_hash: "abc")
    end
end
