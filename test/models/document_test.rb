require "test_helper"

class DocumentTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include FakeEmbedder::TestHelper

  test "fixtures are valid" do
    assert documents(:handbook).valid?
    assert documents(:pending_upload).valid?
  end

  test "requires a title" do
    document = Document.new(source_type: :upload)
    assert_not document.valid?
    assert_includes document.errors[:title], "can't be blank"
  end

  test "rejects unknown source_type and ingestion_status" do
    document = Document.new(title: "Doc", source_type: "fax", ingestion_status: "lost")
    assert_not document.valid?
    assert_includes document.errors[:source_type], "is not included in the list"
    assert_includes document.errors[:ingestion_status], "is not included in the list"
  end

  test "defaults to pending with empty metadata" do
    document = Document.create!(title: "Doc", source_type: :upload)
    assert document.pending?
    assert_equal({}, document.reload.metadata)
  end

  test "attaches a file" do
    document = documents(:pending_upload)
    document.file.attach(io: StringIO.new("# Hello"), filename: "hello.md", content_type: "text/markdown")
    assert document.file.attached?
  end

  test "has many chunks and deletes them with the document" do
    document = documents(:handbook)
    assert_equal [ chunks(:intro), chunks(:leave) ], document.chunks.order(:position).to_a

    assert_difference -> { Chunk.count }, -2 do
      document.destroy
    end
  end

  test "validates source_uri uniqueness per source_type" do
    duplicate = Document.new(title: "Copy", source_type: :filesystem, source_uri: "handbooks/employee.md")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:source_uri], "has already been taken"
  end

  test "enforces source_uri uniqueness per source_type in the database" do
    assert_raises ActiveRecord::RecordNotUnique do
      Document.insert_all!([ { title: "Copy", source_type: "filesystem", source_uri: "handbooks/employee.md" } ])
    end
  end

  test "allows the same source_uri under another source_type" do
    assert Document.create(title: "Copy", source_type: :url, source_uri: "handbooks/employee.md").persisted?
  end

  test "outdated returns documents with an old or missing chunker fingerprint" do
    current = Document.create!(title: "Current", source_type: :upload, chunker_fingerprint: Ingestion::DocumentIngester.new.fingerprint)
    old = Document.create!(title: "Old", source_type: :upload, chunker_fingerprint: "0:000000000000")

    assert_includes Document.outdated, old
    assert_includes Document.outdated, documents(:handbook)
    assert_not_includes Document.outdated, current
  end

  test "enqueue_ingest coalesces repeated calls into one waiting job" do
    document = documents(:handbook)
    3.times { document.enqueue_ingest }

    assert_enqueued_jobs 1, only: IngestDocumentJob
    assert_enqueued_with job: IngestDocumentJob, args: [ document ]
  end

  test "enqueue_ingest after the job starts queues a follow-up" do
    document = documents(:handbook)
    document.enqueue_ingest
    perform_enqueued_jobs
    document.enqueue_ingest

    assert_performed_jobs 1, only: IngestDocumentJob
    assert_enqueued_jobs 1, only: IngestDocumentJob
  end

  test "enqueue_ingest reclaims a stale queued flag" do
    document = documents(:handbook)
    document.update_column(:ingest_queued_at, Document::QUEUED_FLAG_STALE_AFTER.ago - 1.minute)
    document.enqueue_ingest

    assert_enqueued_jobs 1, only: IngestDocumentJob
  end

  test "enqueue_ingest with force always queues" do
    document = documents(:handbook)
    document.update_column(:ingest_queued_at, Time.current)
    document.enqueue_ingest(force: true)

    assert_enqueued_with job: IngestDocumentJob, args: [ document, { force: true } ]
  end

  test "enqueue_embed coalesces repeated calls into one waiting job" do
    document = documents(:handbook)
    3.times { document.enqueue_embed(strategy: "raw") }

    assert_enqueued_jobs 1, only: EmbedDocumentJob
    assert_enqueued_with job: EmbedDocumentJob, args: [ document, { strategy: "raw" } ]
  end

  test "enqueue_embed after the job starts queues a follow-up" do
    document = documents(:handbook)
    document.enqueue_embed
    with_fake_embedder { perform_enqueued_jobs }
    document.enqueue_embed

    assert_performed_jobs 1, only: EmbedDocumentJob
    assert_enqueued_jobs 1, only: EmbedDocumentJob
  end

  test "enqueue_embed reclaims a stale queued flag" do
    document = documents(:handbook)
    document.update_column(:embed_queued_at, Document::QUEUED_FLAG_STALE_AFTER.ago - 1.minute)
    document.enqueue_embed

    assert_enqueued_jobs 1, only: EmbedDocumentJob
  end

  test "allows many documents without a source_uri" do
    Document.insert_all!([
      { title: "One", source_type: "upload" },
      { title: "Two", source_type: "upload" }
    ])
    assert_equal 3, Document.where(source_type: :upload, source_uri: nil).count
  end
end
