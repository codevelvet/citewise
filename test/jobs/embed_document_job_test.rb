require "test_helper"

class EmbedDocumentJobTest < ActiveJob::TestCase
  include FakeEmbedder::TestHelper

  setup do
    @document = documents(:handbook)
  end

  test "embeds the document's chunks" do
    with_fake_embedder do
      assert_difference(-> { ChunkEmbedding.raw.count }, 2) { EmbedDocumentJob.perform_now(@document) }
    end
  end

  test "runs on the embeddings queue" do
    assert_equal "embeddings", EmbedDocumentJob.new(@document).queue_name
  end

  test "retries a rate-limit error after the Retry-After the provider sent" do
    fake = FakeEmbedder.new
    fake.error = Embeddings::Embedder::TransientError.new("Embedding provider 429: Rate limit exceeded", retry_after: 7)

    freeze_time do
      with_fake_embedder(fake) do
        assert_enqueued_with(job: EmbedDocumentJob, args: [ @document ], at: 7.seconds.from_now) do
          EmbedDocumentJob.perform_now(@document)
        end
      end
    end
  end

  test "retries a transient error without Retry-After with polynomial backoff and jitter" do
    fake = FakeEmbedder.new
    fake.error = Embeddings::Embedder::TransientError.new("Embedding provider 503: Service unavailable")

    freeze_time do
      with_fake_embedder(fake) { EmbedDocumentJob.perform_now(@document) }

      wait = enqueued_jobs.sole[:at] - Time.current.to_f
      assert_in_delta 3 * 1.075, wait, 3 * 0.075 # first execution: 1**4 + 2 seconds, plus up to 15%
    end
  end

  test "gives up on transient errors after #{EmbedDocumentJob::ATTEMPTS} attempts" do
    fake = FakeEmbedder.new
    fake.error = Embeddings::Embedder::TransientError.new("Embedding provider 503: Service unavailable")
    job = EmbedDocumentJob.new(@document)
    job.executions = EmbedDocumentJob::ATTEMPTS - 1

    with_fake_embedder(fake) do
      assert_raises(Embeddings::Embedder::TransientError) { job.perform_now }
    end
    assert_no_enqueued_jobs
  end

  test "fails at once on an authentication error" do
    fake = FakeEmbedder.new
    fake.error = Embeddings::Embedder::PermanentError.new("Embedding provider 401: Provided API key is invalid.")

    with_fake_embedder(fake) do
      error = assert_raises(Embeddings::Embedder::PermanentError) { EmbedDocumentJob.perform_now(@document) }
      assert_equal "Embedding provider 401: Provided API key is invalid.", error.message
    end
    assert_no_enqueued_jobs
  end

  test "allows one job per document at a time" do
    first, second, other = EmbedDocumentJob.new(@document), EmbedDocumentJob.new(@document), EmbedDocumentJob.new(documents(:pending_upload))

    [ first, second, other ].each { |job| SolidQueue::Job.enqueue(job) }

    assert_equal [ first.job_id, other.job_id ].sort, SolidQueue::ReadyExecution.includes(:job).map { it.job.active_job_id }.sort
    assert_equal [ second.job_id ], SolidQueue::BlockedExecution.includes(:job).map { it.job.active_job_id }
  end

  test "an ingest job for the same document waits for an embed" do
    embed, ingest, other = EmbedDocumentJob.new(@document), IngestDocumentJob.new(@document), IngestDocumentJob.new(documents(:pending_upload))

    [ embed, ingest, other ].each { |job| SolidQueue::Job.enqueue(job) }

    assert_equal [ embed.job_id, other.job_id ].sort, SolidQueue::ReadyExecution.includes(:job).map { it.job.active_job_id }.sort
    assert_equal [ ingest.job_id ], SolidQueue::BlockedExecution.includes(:job).map { it.job.active_job_id }
  end

  test "the lock covers queue wait plus a long embed" do
    freeze_time do
      job = EmbedDocumentJob.new(@document)
      SolidQueue::Job.enqueue(job)

      assert_equal DocumentSerialized::LOCK_DURATION.from_now, SolidQueue::Semaphore.find_by!(key: job.concurrency_key).expires_at
    end
  end

  test "discards the job with a warning when a chunk is deleted mid-run" do
    log = StringIO.new
    logger, Rails.logger = Rails.logger, ActiveSupport::Logger.new(log)

    raised = with_fake_embedder(ChunkDeletingEmbedder.new(@document)) do
      EmbedDocumentJob.perform_now(@document)
      nil
    rescue ActiveRecord::InvalidForeignKey => error
      error
    end

    assert_nil raised
    assert_no_enqueued_jobs
    assert_match(/EmbedDocumentJob.*discarded/, log.string)
  ensure
    Rails.logger = logger
  end

  private
    # Deletes one of the document's chunks while its batch is out, as a concurrent re-ingest would.
    class ChunkDeletingEmbedder < FakeEmbedder
      def initialize(document)
        super()
        @document = document
      end

      def embed_documents(texts)
        Chunk.where(id: @document.chunks.order(:position).first.id).delete_all
        super
      end
    end
end
