class EmbedDocumentJob < ApplicationJob
  ATTEMPTS = 5

  # Its own queue, served by a single thread so Embeddings::RateLimiter holds.
  queue_as :embeddings

  # Never embed a document while another embed or ingest job for it runs, so duplicate jobs
  # don't pay for the same chunks and an ingest can't delete chunks mid-batch.
  # The key covers the document, not the strategy; that's fine while raw is the only strategy.
  include DocumentSerialized

  # A re-ingest deleted chunks mid-run and queued a fresh job, which embeds whatever this one didn't.
  discard_on ActiveRecord::InvalidForeignKey do |job, error|
    Rails.logger.warn "EmbedDocumentJob for #{job.arguments.first.to_gid} discarded: #{error.message}"
  end

  # Rate limits, server errors, and timeouts retry, after Retry-After when the provider sent one.
  # retry_on can't do that: its wait proc sees the attempt count but not the error.
  # Permanent errors (bad key, invalid request) aren't rescued, so the job fails at once.
  rescue_from Embeddings::Embedder::TransientError do |error|
    raise error if executions >= ATTEMPTS

    retry_job wait: error.retry_after || backoff
  end

  def perform(document, strategy: "raw")
    # Clear the queued flag before reading the chunks, so a re-ingest during the run queues a follow-up.
    Document.where(id: document.id).update_all(embed_queued_at: nil)
    Embeddings::DocumentEmbedder.new.call(document, strategy: strategy)
  end

  private
    # Like retry_on's :polynomially_longer, with its default 15% jitter.
    def backoff
      delay = executions**4 + 2
      delay + delay * 0.15 * rand
    end
end
