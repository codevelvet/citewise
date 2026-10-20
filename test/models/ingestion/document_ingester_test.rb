require "test_helper"

class Ingestion::DocumentIngesterTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include FakeEmbedder::TestHelper
  include StubHelper

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
    assert_equal ids.sort, @document.chunks.ids.sort
    assert_operator @document.reload.ingested_at, :>, ingested_at
  end

  test "enqueues embedding after an ingestion that changed the chunks" do
    assert_enqueued_with(job: EmbedDocumentJob, args: [ @document, { strategy: "raw" } ]) { @ingester.call(@document) }
    # Run the embed job so the next ingestion isn't coalesced into it.
    with_fake_embedder { perform_enqueued_jobs }

    attach(@document, "# Changed\n\nNew body.\n")
    assert_enqueued_with(job: EmbedDocumentJob, args: [ @document, { strategy: "raw" } ]) { @ingester.call(@document) }
  end

  test "ingesting twice before embedding runs queues one embed job" do
    assert_enqueued_jobs 1, only: EmbedDocumentJob do
      @ingester.call(@document)
      attach(@document, "# Changed\n\nNew body.\n")
      @ingester.call(@document)
    end
  end

  test "re-chunks an ingested document whose chunker fingerprint is outdated, without force" do
    @ingester.call(@document)
    @document.update_column(:chunker_fingerprint, "0:000000000000")
    ingested_at = @document.reload.ingested_at

    @ingester.call(@document)

    @document.reload
    assert_equal @ingester.fingerprint, @document.chunker_fingerprint
    assert_operator @document.ingested_at, :>, ingested_at
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
    chunks = @document.chunks.order(:position).pluck(:id, :position, :content, :heading_path, :updated_at)

    stub(Chunk, :upsert_all, ->(*) { raise ActiveRecord::Deadlocked, "deadlock detected" }) do
      assert_raises(ActiveRecord::Deadlocked) { @ingester.call(@document, force: true) }
    end

    @document.reload
    assert_not @document.failed?
    assert_nil @document.ingestion_error
    assert_equal chunks, @document.chunks.order(:position).pluck(:id, :position, :content, :heading_path, :updated_at)
  end

  test "a transient error while inserting edited chunks restores the original chunks and embeddings" do
    ingest(chunk("Alpha."), chunk("Beta."), chunk("Gamma."))
    embed
    chunks = @document.chunks.order(:position).pluck(:id, :position, :content, :heading_path, :updated_at)
    embeddings = ChunkEmbedding.where(chunk: @document.chunks).order(:id).pluck(:id, :chunk_id, :input_hash)

    # Fails after the edited chunk's row is deleted and the kept rows are renumbered.
    stub(Chunk, :insert_all!, ->(*) { raise ActiveRecord::Deadlocked, "deadlock detected" }) do
      assert_raises(ActiveRecord::Deadlocked) { ingest(chunk("Alpha."), chunk("Beta, edited."), chunk("Gamma.")) }
    end

    assert_equal chunks, @document.chunks.order(:position).pluck(:id, :position, :content, :heading_path, :updated_at)
    assert_equal embeddings, ChunkEmbedding.where(chunk: @document.chunks).order(:id).pluck(:id, :chunk_id, :input_hash)
    assert_not @document.reload.failed?
    assert_nil @document.ingestion_error
  end

  test "an edit keeps the unchanged chunks and their embeddings" do
    ingest(chunk("Alpha."), chunk("Beta."), chunk("Gamma."))
    embed
    alpha, beta, gamma = @document.chunks.order(:position).to_a
    embeddings = ChunkEmbedding.where(chunk: [ alpha, gamma ]).order(:id).pluck(:id, :chunk_id, :updated_at)

    ingest(chunk("Alpha."), chunk("Beta, edited."), chunk("Gamma."))

    chunks = @document.chunks.order(:position).to_a
    assert_equal [ alpha.id, gamma.id ], [ chunks.first.id, chunks.last.id ]
    assert_not_includes chunks.map(&:id), beta.id
    assert_equal embeddings, ChunkEmbedding.where(chunk: [ alpha, gamma ]).order(:id).pluck(:id, :chunk_id, :updated_at)
    assert_equal [ "Beta, edited." ], document_embedder.pending(@document, :raw).map { it.chunk.content }
  end

  test "reordered chunks keep their ids and take the new positions" do
    ingest(chunk("Alpha."), chunk("Beta."), chunk("Gamma."))
    ids = @document.chunks.pluck(:content, :id).to_h

    ingest(chunk("Gamma."), chunk("Delta."), chunk("Alpha."), chunk("Beta."))

    saved = @document.chunks.order(:position).pluck(:position, :content, :id)
    assert_equal [ [ 0, "Gamma." ], [ 1, "Delta." ], [ 2, "Alpha." ], [ 3, "Beta." ] ], saved.map { it.first(2) }
    assert_equal ids.values_at("Gamma.", "Alpha.", "Beta."), saved.values_at(0, 2, 3).map(&:last)
  end

  test "pairs repeated content with the saved chunks in order" do
    ingest(chunk("Same.", heading_path: [ "A" ]), chunk("Same.", heading_path: [ "B" ]))
    first, second = @document.chunks.order(:position).ids

    ingest(chunk("New."), chunk("Same.", heading_path: [ "A" ]), chunk("Same.", heading_path: [ "B" ]))

    same = @document.chunks.where(content: "Same.").order(:position)
    assert_equal [ [ first, [ "A" ] ], [ second, [ "B" ] ] ], same.pluck(:id, :heading_path)
  end

  test "a renamed heading keeps the chunk and makes its embedding stale" do
    ingest(chunk("Alpha.", heading_path: [ "Old" ]))
    embed
    id = @document.chunks.sole.id

    ingest(chunk("Alpha.", heading_path: [ "New" ]))

    assert_equal [ id, [ "New" ] ], @document.chunks.pick(:id, :heading_path)
    assert_equal [ id ], document_embedder.pending(@document, :raw).map { it.chunk.id }
  end

  private
    class StaticChunker
      attr_accessor :chunks

      def call(*, **)
        chunks
      end

      def fingerprint
        "0:111111111111"
      end
    end

    class FailingChunker
      def call(*, **)
        raise "chunker broke"
      end

      def fingerprint
        "0:000000000000"
      end
    end

    def chunk(content, heading_path: [ "Doc" ])
      Chunking::Chunk.new(content: content, heading_path: heading_path, position: nil, token_count: 1, content_hash: Digest::SHA256.hexdigest(content))
    end

    # Ingests the chunks in this order, as if the chunker returned them.
    def ingest(*chunks)
      chunker = StaticChunker.new
      chunker.chunks = chunks.each_with_index.map { |chunk, position| chunk.with(position: position) }
      Ingestion::DocumentIngester.new(chunker: chunker).call(@document, force: true)
    end

    def embed
      document_embedder.call(@document, strategy: :raw)
    end

    def document_embedder
      unlimited = Embeddings::RateLimiter.new(requests_per_minute: Float::INFINITY, tokens_per_minute: Float::INFINITY)
      Embeddings::DocumentEmbedder.new(embedder: FakeEmbedder.new, limiter: unlimited)
    end

    def attach(document, markdown)
      document.file.attach(io: StringIO.new(markdown), filename: "doc.md", content_type: "text/markdown")
    end
end
