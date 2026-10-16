class EmbedDocumentJob < ApplicationJob
  ATTEMPTS = 5

  # Its own queue, served by a single thread so Embeddings::RateLimiter holds.
  queue_as :embeddings

  # Never embed the same document twice at once, so duplicate jobs don't pay for the same chunks.
  # The key covers the document, not the strategy; that's fine while raw is the only strategy.
  limits_concurrency to: 1, key: ->(document, **) { document }

  # Rate limits, server errors, and timeouts retry, after Retry-After when the provider sent one.
  # retry_on can't do that: its wait proc sees the attempt count but not the error.
  # Permanent errors (bad key, invalid request) aren't rescued, so the job fails at once.
  rescue_from Embeddings::Embedder::TransientError do |error|
    raise error if executions >= ATTEMPTS

    retry_job wait: error.retry_after || backoff
  end

  def perform(document, strategy: "raw")
    Embeddings::DocumentEmbedder.new.call(document, strategy: strategy)
  end

  private
    # Like retry_on's :polynomially_longer, with its default 15% jitter.
    def backoff
      delay = executions**4 + 2
      delay + delay * 0.15 * rand
    end
end
