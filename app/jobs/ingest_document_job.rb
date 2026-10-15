class IngestDocumentJob < ApplicationJob
  queue_as :ingestion

  # Never ingest the same document twice at once; a second job waits for the first.
  limits_concurrency to: 1, key: ->(document, **) { document }

  # Deterministic failures never get here: the ingester marks the document failed.
  retry_on ActiveRecord::ConnectionNotEstablished, ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout,
           ActiveStorage::Error, Timeout::Error, wait: :polynomially_longer, attempts: 5 do |job, error|
    job.arguments.first.update!(ingestion_status: :failed, ingestion_error: "#{error.class}: #{error.message} (gave up after retries)")
  end

  def perform(document, force: false)
    Ingestion::DocumentIngester.new.call(document, force: force)
  end
end
