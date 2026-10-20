class Document < ApplicationRecord
  has_one_attached :file
  has_many :chunks, dependent: :delete_all

  enum :source_type, { upload: "upload", filesystem: "filesystem", url: "url" }, validate: true
  enum :ingestion_status, { pending: "pending", processing: "processing", ingested: "ingested", failed: "failed" }, validate: true

  # Chunked by other code or settings than the current chunker's, or never chunked.
  scope :outdated, -> { where(chunker_fingerprint: nil).or(where.not(chunker_fingerprint: Ingestion::DocumentIngester.new.fingerprint)) }

  # A queued flag this old most likely belongs to a job that died before it started, so it can
  # be claimed again. Reclaiming too early only adds one job that finds nothing to do, because
  # jobs work from the document's current state.
  QUEUED_FLAG_STALE_AFTER = 1.hour

  validates :title, presence: true
  validates :source_uri, uniqueness: { scope: :source_type }, allow_nil: true

  # Queues IngestDocumentJob unless one is already waiting. Returns the job, or false if
  # it queued none. force always queues, for re-chunking content that hasn't changed.
  def enqueue_ingest(force: false)
    return IngestDocumentJob.perform_later(self, force: true) if force

    enqueue_claiming(:ingest_queued_at) { IngestDocumentJob.perform_later(self) }
  end

  # Queues EmbedDocumentJob unless one is already waiting. Returns the job, or false if it queued none.
  # One flag per document, not per strategy, is enough while raw is the only strategy.
  def enqueue_embed(strategy: "raw")
    enqueue_claiming(:embed_queued_at) { EmbedDocumentJob.perform_later(self, strategy: strategy) }
  end

  private
    # Claims the queued flag and queues the job in one transaction, so a failed enqueue
    # (SolidQueue::Job::EnqueueError raised, or perform_later returning false) rolls the
    # claim back instead of leaving a flag set with no job behind it.
    #
    # enqueue_after_transaction_commit must be false for these jobs (false by default in
    # Rails 8.1). If it's true, perform_later only schedules the enqueue for after commit:
    # the flag commits first, and a failed enqueue leaves it set. Pinned by DocumentTest.
    #
    # requires_new makes this a savepoint when called inside another transaction;
    # otherwise ActiveRecord::Rollback would be swallowed without rolling anything back.
    def enqueue_claiming(column)
      Document.transaction(requires_new: true) do
        next false unless claim_queued_flag(column)

        yield || raise(ActiveRecord::Rollback)
      end || false
    end

    # Atomic, so of concurrent callers exactly one claims the flag. The job clears it when it starts.
    def claim_queued_flag(column)
      Document.where(column => nil).or(Document.where(column => ...QUEUED_FLAG_STALE_AFTER.ago))
        .where(id: id)
        .update_all(column => Time.current) == 1
    end
end
