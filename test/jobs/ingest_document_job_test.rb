require "test_helper"

class IngestDocumentJobTest < ActiveJob::TestCase
  include TestData

  setup do
    @document = Document.create!(title: "Doc", source_type: :upload)
    @document.file.attach(io: StringIO.new("# Doc\n\nBody.\n"), filename: "doc.md", content_type: "text/markdown")
  end

  test "ingests the document" do
    IngestDocumentJob.perform_now(@document)

    assert @document.reload.ingested?
    assert_equal [ "Body." ], @document.chunks.pluck(:content)
  end

  test "runs on the ingestion queue" do
    assert_equal "ingestion", IngestDocumentJob.new(@document).queue_name
  end

  test "retries transient errors instead of failing the document" do
    Chunk.define_singleton_method(:insert_all!) { |*| raise ActiveRecord::Deadlocked, "deadlock detected" }

    assert_enqueued_with(job: IngestDocumentJob, args: [ @document, { force: true } ]) do
      IngestDocumentJob.perform_now(@document, force: true)
    end
    assert_not @document.reload.failed?
  ensure
    Chunk.singleton_class.remove_method(:insert_all!)
  end

  test "allows one job per document at a time" do
    other = documents(:pending_upload)
    first, second, unrelated = IngestDocumentJob.new(@document), IngestDocumentJob.new(@document, force: true), IngestDocumentJob.new(other)

    [ first, second, unrelated ].each { |job| SolidQueue::Job.enqueue(job) }

    assert_equal [ first.job_id, unrelated.job_id ].sort, SolidQueue::ReadyExecution.includes(:job).map { it.job.active_job_id }.sort
    assert_equal [ second.job_id ], SolidQueue::BlockedExecution.includes(:job).map { it.job.active_job_id }
  end

  test "an embed job for the same document waits for an ingest" do
    ingest, embed, other = IngestDocumentJob.new(@document), EmbedDocumentJob.new(@document), EmbedDocumentJob.new(documents(:handbook))

    [ ingest, embed, other ].each { |job| SolidQueue::Job.enqueue(job) }

    assert_equal [ ingest.job_id, other.job_id ].sort, SolidQueue::ReadyExecution.includes(:job).map { it.job.active_job_id }.sort
    assert_equal [ embed.job_id ], SolidQueue::BlockedExecution.includes(:job).map { it.job.active_job_id }
  end

  test "the lock covers queue wait plus a long embed" do
    freeze_time do
      job = IngestDocumentJob.new(@document)
      SolidQueue::Job.enqueue(job)

      assert_equal DocumentSerialized::LOCK_DURATION.from_now, SolidQueue::Semaphore.find_by!(key: job.concurrency_key).expires_at
    end
  end

  test "a request made while the job is running queues one follow-up" do
    @document.enqueue_ingest
    chunker = RequestingChunker.new(@document)

    with_ingester(Ingestion::DocumentIngester.new(chunker: chunker)) do
      assert_enqueued_jobs(1, only: IngestDocumentJob) { IngestDocumentJob.perform_now(@document) }
    end
    assert chunker.called
  end

  private
    def with_ingester(ingester)
      Ingestion::DocumentIngester.define_singleton_method(:new) { |*| ingester }
      yield
    ensure
      Ingestion::DocumentIngester.singleton_class.remove_method(:new)
    end

    # Asks for another ingest mid-run, as an upload or import would.
    class RequestingChunker
      attr_reader :called

      def initialize(document)
        @document = document
      end

      def call(*, **)
        @called = true
        @document.enqueue_ingest
        []
      end

      def fingerprint
        "0:111111111111"
      end
    end
end
