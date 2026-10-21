require "test_helper"
require "rake"

class CitewiseRakeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include FakeAnswerer::TestHelper

  setup do
    # Keep task descriptions, as rails -T does.
    Rake::TaskManager.record_task_metadata = true
    Rails.application.load_tasks if Rake::Task.tasks.none? { |task| task.name == "citewise:reingest" }
    @dir = Pathname(Dir.mktmpdir)
    @dir.join("guides").mkpath
    @dir.join("intro.md").write("# Intro\n\nWelcome.\n")
    @dir.join("guides/setup.md").write("# Setup\n\nInstall it.\n")
  end

  teardown do
    FileUtils.remove_entry(@dir)
  end

  test "import creates a filesystem document per Markdown file and enqueues ingestion" do
    output = nil
    assert_enqueued_jobs(2, only: IngestDocumentJob) { output = import }

    assert_includes output, "Created 2, updated 0, unchanged 0"
    documents = Document.filesystem.where(source_uri: [ "intro.md", "guides/setup.md" ]).order(:source_uri)
    assert_equal [ "guides/setup.md", "intro.md" ], documents.map(&:source_uri)
    documents.each do |document|
      assert_equal "test-collection", document.metadata["collection"]
      assert document.file.attached?
      assert_enqueued_with(job: IngestDocumentJob, args: [ document ])
    end
  end

  test "re-importing the same directory updates rather than duplicates" do
    import
    # Run the ingests: a request while one is still waiting is coalesced into it.
    perform_enqueued_jobs(only: IngestDocumentJob)
    clear_enqueued_jobs

    output = nil
    assert_no_difference(-> { Document.count }) { assert_no_enqueued_jobs(only: IngestDocumentJob) { output = import } }
    assert_includes output, "Created 0, updated 0, unchanged 2"

    @dir.join("intro.md").write("# Intro\n\nWelcome back.\n")
    assert_no_difference(-> { Document.count }) { assert_enqueued_jobs(1, only: IngestDocumentJob) { output = import } }
    assert_includes output, "Created 0, updated 1, unchanged 1"
    assert_equal "# Intro\n\nWelcome back.\n", Document.find_by!(source_uri: "intro.md").file.download
  end

  test "reingest enqueues outdated and failed documents that have a file" do
    current = Ingestion::DocumentIngester.new.fingerprint
    outdated = create_document("outdated", chunker_fingerprint: "0:000000000000", ingestion_status: :ingested)
    failed = create_document("failed", chunker_fingerprint: current, ingestion_status: :failed)
    create_document("current", chunker_fingerprint: current, ingestion_status: :ingested)
    # documents(:pending_upload) has no file: it is outdated, but an upload in progress.

    output = nil
    assert_enqueued_jobs(2, only: IngestDocumentJob) { output = reingest }

    assert_includes output, "Enqueued 2"
    assert_enqueued_with(job: IngestDocumentJob, args: [ outdated ])
    assert_enqueued_with(job: IngestDocumentJob, args: [ failed ])
  end

  test "running reingest twice enqueues one job per document" do
    create_document("outdated", chunker_fingerprint: "0:000000000000", ingestion_status: :ingested)
    create_document("failed", chunker_fingerprint: Ingestion::DocumentIngester.new.fingerprint, ingestion_status: :failed)

    output = nil
    assert_enqueued_jobs(2, only: IngestDocumentJob) { reingest; output = reingest }
    assert_includes output, "Enqueued 0"
  end

  test "re-importing a changed file while its ingest is waiting adds no job" do
    assert_enqueued_jobs 2, only: IngestDocumentJob do
      import
      @dir.join("intro.md").write("# Intro\n\nWelcome back.\n")
      import
    end
  end

  test "running embed twice enqueues one job per document" do
    stale = create_document("stale", ingestion_status: :ingested)
    stale.chunks.create!(position: 0, content: "Body.", token_count: 2, content_hash: "abc")
    embedder = Embeddings::DocumentEmbedder.new(embedder: FakeEmbedder.new, limiter: Embeddings::RateLimiter.new(requests_per_minute: 10, tokens_per_minute: 10_000))
    documents(:handbook, :leave_policy).each { embedder.call(it, strategy: :raw) }

    output = nil
    assert_enqueued_jobs(1, only: EmbedDocumentJob) { embed; output = embed }
    assert_includes output, "Enqueued 0"
  end

  test "reingest all enqueues every document that has a file" do
    current = Ingestion::DocumentIngester.new.fingerprint
    documents = [ create_document("one", chunker_fingerprint: current, ingestion_status: :ingested), create_document("two") ]

    output = nil
    assert_enqueued_jobs(2, only: IngestDocumentJob) { output = reingest("all") }

    assert_includes output, "Enqueued 2"
    documents.each { |document| assert_enqueued_with(job: IngestDocumentJob, args: [ document, { force: true } ]) }
  end

  test "embed dry run prints chunks, estimated tokens, requests, and duration without enqueueing or embedding" do
    embedder = Embeddings::DocumentEmbedder.new(embedder: FakeEmbedder.new)
    tokens = documents(:handbook, :leave_policy).sum { embedder.pending(it, :raw).sum(&:tokens) }

    output = nil
    assert_no_enqueued_jobs { assert_no_difference(-> { ChunkEmbedding.count }) { output = embed("raw", "dry_run") } }

    assert_includes output, "raw with voyage-4-lite: 2 documents, 3 chunks, ~#{tokens} tokens (estimated), 2 requests, ~1 min at 3 requests/min and 10000 tokens/min"
    assert_includes output, "Dry run: nothing enqueued"
  end

  test "embed enqueues only documents with missing or stale chunks" do
    stale = create_document("stale", ingestion_status: :ingested)
    stale.chunks.create!(position: 0, content: "Body.", token_count: 2, content_hash: "abc")
    embedder = Embeddings::DocumentEmbedder.new(embedder: FakeEmbedder.new, limiter: Embeddings::RateLimiter.new(requests_per_minute: 10, tokens_per_minute: 10_000))
    documents(:handbook, :leave_policy).each { embedder.call(it, strategy: :raw) }

    output = nil
    assert_enqueued_jobs(1, only: EmbedDocumentJob) { output = embed }

    assert_enqueued_with(job: EmbedDocumentJob, args: [ stale, { strategy: "raw" } ])
    assert_includes output, "1 document, 1 chunks"
    assert_includes output, "Enqueued 1"
  end

  test "embed rejects strategies that aren't implemented" do
    assert_raises(SystemExit) { embed("contextual") }
  end

  test "embed's description says it is safe to rerun" do
    assert_match(/\AEmbed missing or stale chunks .*safe to rerun/, Rake::Task["citewise:embed"].full_comment)
  end

  test "ask prints the answer, citations, retrieved chunks with similarity, and token usage" do
    output = with_question_embedder { |embedder| with_fake_embedder(embedder) { with_fake_answerer { ask("How much paid leave do I get?") } } }

    question = Question.last
    assert question.answered?
    assert_equal <<~OUTPUT, output
      Full-time employees accrue 20 days of paid leave per year.

      Citations
        [1] Employee Handbook > Benefits > Paid leave
            Full-time employees accrue 20 days of paid leave per year.

      Retrieved
        1. 1.000  Employee Handbook > Benefits > Paid leave
        2. #{format("%.3f", question.retrieval.last["similarity"])}  Employee Handbook > Introduction

      Tokens: input 900, output 40, cache read 0, cache write 0
      Time: retrieval #{question.retrieval_ms} ms, answer #{question.answer_ms} ms (question #{question.id}, claude-haiku-4-5)
    OUTPUT
  end

  test "ask says when there are no citations" do
    output = with_question_embedder do |embedder|
      with_fake_embedder(embedder) { with_fake_answerer(FakeAnswerer.new(text: "The documents don't cover that.", cite: false)) { ask("Parental leave?") } }
    end

    assert_includes output, "The documents don't cover that.\n\nCitations\n  (none)\n"
  end

  {
    "max_tokens" => "max_tokens at 1024 tokens",
    "refusal" => "refusal",
    "something_new" => "something_new"
  }.each do |stop_reason, reason|
    test "ask warns, naming the reason, when the answer stopped with #{stop_reason}" do
      output = with_question_embedder do |embedder|
        with_fake_embedder(embedder) { with_fake_answerer(FakeAnswerer.new(stop_reason: stop_reason)) { ask("How much paid leave do I get?") } }
      end

      assert_includes output, "Full-time employees accrue 20 days of paid leave per year.\n\n" \
        "Warning: stopped early (#{reason}), so this answer may be incomplete.\n\nCitations\n"
    end
  end

  test "ask without embeddings prints the fixed answer and a hint, without calling the answerer" do
    answerer = FakeAnswerer.new
    output = with_fake_embedder { with_fake_answerer(answerer) { ask("How much paid leave do I get?") } }

    assert_empty answerer.calls
    assert_equal "#{Answering::AskService::NO_SOURCES_ANSWER}\n\nNo embeddings found for voyage-4-lite/raw. Run citewise:embed.\n", output
  end

  test "ask rejoins a question that rake split at its commas" do
    answerer = FakeAnswerer.new
    with_question_embedder { |embedder| with_fake_embedder(embedder) { with_fake_answerer(answerer) { ask("How much leave", "roughly?") } } }

    assert_equal "How much leave, roughly?", answerer.calls.first.first
  end

  test "ask aborts with the error when answering fails, leaving a failed question" do
    answerer = FakeAnswerer.new
    answerer.error = Answering::Answerer::TransientError.new("Answering provider 529: Overloaded")

    error = assert_raises(SystemExit) do
      with_question_embedder { |embedder| with_fake_embedder(embedder) { with_fake_answerer(answerer) { ask("How much paid leave do I get?") } } }
    end
    assert_not error.success?
    assert Question.last.failed?
  end

  test "ask aborts without a question" do
    assert_raises(SystemExit) { ask }
  end

  test "ask aborts on a question over the length limit, without embedding or answering it" do
    answerer = FakeAnswerer.new
    error = assert_raises(SystemExit) do
      with_fake_embedder { with_fake_answerer(answerer) { ask("a" * (Question::MAX_TEXT_LENGTH + 1)) } }
    end

    assert_not error.success?
    assert_empty answerer.calls
    assert_equal 0, Question.count
  end

  test "fail_abandoned_questions marks questions pending for over an hour failed" do
    abandoned = Question.create!(text: "Abandoned?", created_at: 2.hours.ago)

    assert_equal "Marked 1 abandoned question failed\n", run_task("citewise:fail_abandoned_questions")
    assert abandoned.reload.failed?
  end

  private
    def ask(*args)
      run_task("citewise:ask", *args)
    end

    # An embedder whose every question lands exactly on the leave chunk.
    def with_question_embedder
      embedder = FakeEmbedder.new
      leave_vector = embedder.vector_for("leave")
      embedder.define_singleton_method(:embed_query) { |_text| leave_vector }
      [ [ chunks(:leave), leave_vector ], [ chunks(:intro), embedder.vector_for("intro") ] ].each do |chunk, vector|
        ChunkEmbedding.create!(chunk: chunk, model: "voyage-4-lite", strategy: :raw, dimensions: 1024, embedding: vector, input_hash: "abc")
      end
      yield embedder
    end

    def embed(*args)
      run_task("citewise:embed", *args)
    end

    def import
      run_task("citewise:import:directory", @dir.to_s, "test-collection")
    end

    def reingest(*args)
      run_task("citewise:reingest", *args)
    end

    def run_task(name, *args)
      task = Rake::Task[name]
      task.reenable
      capture_io { task.invoke(*args) }.first
    end

    def create_document(title, **attributes)
      Document.create!(title: title, source_type: :upload, **attributes).tap do |document|
        document.file.attach(io: StringIO.new("# #{title}\n"), filename: "#{title}.md", content_type: "text/markdown")
      end
    end
end
