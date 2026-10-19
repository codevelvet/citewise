class IngestDocumentJob < ApplicationJob
  queue_as :ingestion

  # Never ingest a document while another ingest or embed job for it runs; this one waits.
  include DocumentSerialized

  # Deterministic failures never get here: the ingester marks the document failed.
  retry_on ActiveRecord::ConnectionNotEstablished, ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout,
           ActiveStorage::Error, Timeout::Error, wait: :polynomially_longer, attempts: 5 do |job, error|
    job.arguments.first.update!(ingestion_status: :failed, ingestion_error: "#{error.class}: #{error.message} (gave up after retries)")
  end

  def perform(document, force: false)
    # Clear the queued flag before reading the file, so a change made during the run queues a follow-up.
    Document.where(id: document.id).update_all(ingest_queued_at: nil)
    Ingestion::DocumentIngester.new.call(document, force: force)
  end
end
