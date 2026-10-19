module Ingestion
  # Turns a document's attached Markdown into saved chunks.
  #
  #   Ingestion::DocumentIngester.new.call(document)              # skips unchanged, already ingested content
  #   Ingestion::DocumentIngester.new.call(document, force: true) # always re-chunks
  #
  # Re-chunking keeps each saved chunk whose content is unchanged, with its id
  # and embeddings, and enqueues EmbedDocumentJob for the rest; a skip doesn't.
  #
  # Errors that would recur on retry (no file, invalid UTF-8, anything the
  # chunker raises) mark the document failed. Others, such as a dropped
  # database connection or a storage timeout, propagate so the caller can retry.
  class DocumentIngester
    # A failure that retrying won't fix.
    class Error < StandardError; end

    attr_reader :chunker
    delegate :fingerprint, to: :chunker

    def initialize(chunker: Chunking::MarkdownChunker.new(**Rails.configuration.x.chunker))
      @chunker = chunker
    end

    def call(document, force: false)
      markdown = read(document)
      content_hash = Digest::SHA256.hexdigest(markdown)
      return document if !force && document.ingested? && document.content_hash == content_hash

      document.processing!
      chunks = chunk(markdown, document.title)

      Document.transaction do
        replace_chunks(document, chunks)
        document.update!(
          # The chunker titles every heading path with the front matter title, when there is one.
          title: chunks.first&.heading_path&.first || document.title,
          content_hash: content_hash,
          chunker_fingerprint: fingerprint,
          ingested_at: Time.current,
          ingestion_status: :ingested,
          ingestion_error: nil
        )
      end
      EmbedDocumentJob.perform_later(document) if chunks.any?
      document
    rescue Error => error
      document.update!(ingestion_status: :failed, ingestion_error: error.message)
      document
    end

    private
      def read(document)
        raise Error, "No file attached" unless document.file.attached?

        markdown = document.file.download.force_encoding(Encoding::UTF_8)
        raise Error, "File is not valid UTF-8" unless markdown.valid_encoding?
        markdown
      rescue ActiveStorage::FileNotFoundError => error
        raise Error, "#{error.class}: #{error.message}"
      end

      # Pairs each new chunk with a saved chunk of the same content, in position
      # order, and updates that row in place; deletes unpaired rows and inserts
      # unpaired chunks. A kept chunk whose heading path changed gets a stale
      # embedding, which EmbedDocumentJob replaces.
      def replace_chunks(document, chunks)
        ids = document.chunks.order(:position).pluck(:content_hash, :id).group_by(&:first).transform_values { it.map(&:last) }
        rows = chunks.map { |chunk| chunk.to_h.merge(document_id: document.id, id: ids[chunk.content_hash]&.shift) }
        kept, added = rows.partition { it[:id] }

        document.chunks.where.not(id: kept.pluck(:id)).delete_all
        # Positions are unique per document, so move the kept chunks out of the way before renumbering them.
        document.chunks.update_all("position = -1 - position")
        Chunk.upsert_all(kept) if kept.any?
        Chunk.insert_all!(added.map { it.except(:id) }) if added.any?
        document.chunks.reset
      end

      # The chunker does no IO, so anything it raises will happen again on retry.
      def chunk(markdown, title)
        chunker.call(markdown, title: title)
      rescue StandardError => error
        raise Error, "#{error.class}: #{error.message}"
      end
  end
end
