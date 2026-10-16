require "test_helper"

class Ingestion::DocumentIngesterTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @markdown = file_fixture("handbook/gitlabengineering.md").read
    @document = Document.create!(title: "gitlabengineering", source_type: :upload)
    attach(@document, @markdown)
    @ingester = Ingestion::DocumentIngester.new
  end

  test "saves the chunker's output and records the fingerprint" do
    @ingester.call(@document)

    expected = @ingester.chunker.call(@markdown, title: "gitlabengineering").map(&:to_h)
    saved = @document.chunks.order(:position).map { |chunk| chunk.slice(:content, :heading_path, :position, :token_count, :content_hash).symbolize_keys }
    assert_not_empty saved
    assert_equal expected, saved

    @document.reload
    assert @document.ingested?
    assert_equal @ingester.fingerprint, @document.chunker_fingerprint
    assert_equal Digest::SHA256.hexdigest(@markdown), @document.content_hash
    assert_not_nil @document.ingested_at
    assert_nil @document.ingestion_error
  end

  test "takes the title from front matter" do
    @ingester.call(@document)
    assert_equal "Engineering", @document.reload.title
  end

  test "reads chunker settings from app configuration" do
    assert_equal Chunking::MarkdownChunker.new(**Rails.configuration.x.chunker).fingerprint, @ingester.fingerprint
  end

  test "skips unchanged content unless forced" do
    @ingester.call(@document)
    ids, ingested_at = @document.chunks.ids, @document.reload.ingested_at

    @ingester.call(@document)
    assert_equal ids, @document.chunks.ids
    assert_equal ingested_at, @document.reload.ingested_at

    @ingester.call(@document, force: true)
    assert_empty ids & @document.chunks.ids
    assert_equal ids.size, @document.chunks.count
  end

  test "enqueues embedding after an ingestion that changed the chunks" do
    assert_enqueued_with(job: EmbedDocumentJob, args: [ @document ]) { @ingester.call(@document) }

    attach(@document, "# Changed\n\nNew body.\n")
    assert_enqueued_with(job: EmbedDocumentJob, args: [ @document ]) { @ingester.call(@document) }
  end

  test "does not enqueue embedding when ingestion is skipped or fails" do
    @ingester.call(@document)
    clear_enqueued_jobs

    assert_no_enqueued_jobs(only: EmbedDocumentJob) { @ingester.call(@document) }
    assert_no_enqueued_jobs(only: EmbedDocumentJob) { Ingestion::DocumentIngester.new(chunker: FailingChunker.new).call(@document, force: true) }
  end

  test "re-chunks changed content without force" do
    @ingester.call(@document)
    ids = @document.chunks.ids

    attach(@document, "# Changed\n\nNew body.\n")
    @ingester.call(@document)

    assert_empty ids & @document.chunks.ids
    assert_equal [ "New body." ], @document.chunks.pluck(:content)
    assert_equal Digest::SHA256.hexdigest("# Changed\n\nNew body.\n"), @document.reload.content_hash
  end

  test "a chunker error marks the document failed and keeps its chunks" do
    @ingester.call(@document)
    chunks = @document.chunks.order(:position).to_a
    content_hash, fingerprint = @document.reload.content_hash, @document.chunker_fingerprint

    attach(@document, "# Changed\n")
    Ingestion::DocumentIngester.new(chunker: FailingChunker.new).call(@document)

    @document.reload
    assert @document.failed?
    assert_equal "RuntimeError: chunker broke", @document.ingestion_error
    assert_equal chunks, @document.chunks.order(:position).to_a
    assert_equal content_hash, @document.content_hash
    assert_equal fingerprint, @document.chunker_fingerprint
  end

  test "a later success clears the error" do
    Ingestion::DocumentIngester.new(chunker: FailingChunker.new).call(@document)
    assert @document.reload.failed?

    @ingester.call(@document)
    assert @document.reload.ingested?
    assert_nil @document.ingestion_error
  end

  test "a missing file marks the document failed" do
    document = documents(:pending_upload)
    @ingester.call(document)

    assert document.reload.failed?
    assert_equal "No file attached", document.ingestion_error
  end

  test "invalid UTF-8 marks the document failed" do
    attach(@document, "# Bad \xFF byte\n".b)
    @ingester.call(@document)

    assert @document.reload.failed?
    assert_equal "File is not valid UTF-8", @document.ingestion_error
  end

  test "a transient error is raised, not recorded" do
    @ingester.call(@document)
    chunks = @document.chunks.order(:position).to_a

    stub(Chunk, :insert_all!, ->(*) { raise ActiveRecord::Deadlocked, "deadlock detected" }) do
      assert_raises(ActiveRecord::Deadlocked) { @ingester.call(@document, force: true) }
    end

    @document.reload
    assert_not @document.failed?
    assert_nil @document.ingestion_error
    assert_equal chunks, @document.chunks.order(:position).to_a
  end

  private
    class FailingChunker
      def call(*, **)
        raise "chunker broke"
      end

      def fingerprint
        "0:000000000000"
      end
    end

    def attach(document, markdown)
      document.file.attach(io: StringIO.new(markdown), filename: "doc.md", content_type: "text/markdown")
    end

    def stub(object, method, implementation)
      object.define_singleton_method(method, &implementation)
      yield
    ensure
      object.singleton_class.remove_method(method)
    end
end
