require "test_helper"

class IngestDocumentJobTest < ActiveJob::TestCase
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
end
