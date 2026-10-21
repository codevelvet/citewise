class AskJob < ApplicationJob
  ATTEMPTS = 5

  # Solid Queue takes the lock when the job is dispatched, not when it starts, so the duration
  # covers waiting for a worker thread on the shared default queue plus AskService's worst case
  # of over 32 minutes (see Question::ABANDONED_AFTER). If it expired mid-run, one more ask
  # could start than the limit allows. Dead-process pruning releases it sooner after a crash.
  LOCK_DURATION = 2.hours

  # The default queue, so questions don't wait behind a bulk embedding run.
  queue_as :default

  # One key for every ask, so the limit holds across all worker processes. Asks over the
  # limit wait. Solid Queue keeps a semaphore's limit until its row sits idle for the whole
  # duration, so after raising max_concurrent_asks, delete the "ask/ask" semaphore row.
  limits_concurrency to: Rails.configuration.x.ask_page[:max_concurrent_asks], key: ->(*) { "ask" }, group: "ask",
                     duration: LOCK_DURATION, on_conflict: :block

  # The concurrency limit isn't a rate: asks can still exceed the embedding provider's
  # requests per minute, which EmbedDocumentJob shares from another process. So a transient
  # error on the query embedding retries after Retry-After, like EmbedDocumentJob, and the
  # Question stays pending until the last attempt. It fails before the answerer is called,
  # so a retry costs no answering tokens. Every other error has already failed the Question.
  rescue_from Embeddings::Embedder::TransientError do |error|
    raise error if executions >= ATTEMPTS

    retry_job wait: error.retry_after || backoff
  end

  def perform(question)
    # Answered already, or failed by the abandoned sweep while this job waited.
    return Rails.logger.info("AskJob skipped question #{question.id}: it's #{question.status}") unless question.pending?

    keep_pending = executions < ATTEMPTS ? [ Embeddings::Embedder::TransientError ] : []
    Answering::AskService.answer(question, keep_pending: keep_pending)
  end

  private
    # Like retry_on's :polynomially_longer, with its default 15% jitter.
    def backoff
      delay = executions**4 + 2
      delay + delay * 0.15 * rand
    end
end
