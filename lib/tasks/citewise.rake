namespace :citewise do
  namespace :import do
    desc "Create or update a Document for each Markdown file under dir, tagged with collection, and enqueue ingestion"
    task :directory, [ :dir, :collection ] => :environment do |_task, args|
      dir = Pathname(args.fetch(:dir)).expand_path
      collection = args.fetch(:collection)
      abort "#{dir} is not a directory" unless dir.directory?

      counts = Hash.new(0)
      Dir.glob("**/*.md", base: dir).sort.each do |relative_path|
        path = dir.join(relative_path)
        document = Document.find_or_initialize_by(source_type: :filesystem, source_uri: relative_path)

        # Active Storage checksums blobs as base64 MD5.
        if document.persisted? && document.file.attached? && document.metadata["collection"] == collection &&
           document.file.checksum == OpenSSL::Digest::MD5.base64digest(path.binread)
          counts[:unchanged] += 1
          next
        end

        counts[document.new_record? ? :created : :updated] += 1
        # A placeholder until ingestion takes the title from front matter.
        document.title ||= path.basename(".md").to_s
        document.metadata = document.metadata.merge("collection" => collection)
        document.file.attach(io: path.open, filename: path.basename.to_s, content_type: "text/markdown")
        document.save!
        IngestDocumentJob.perform_later(document)
      end

      puts "Created #{counts[:created]}, updated #{counts[:updated]}, unchanged #{counts[:unchanged]}"
    end
  end

  desc "Enqueue forced re-ingestion of outdated and failed documents, or of every document with citewise:reingest[all]"
  task :reingest, [ :scope ] => :environment do |_task, args|
    # Documents without a file are uploads still in progress, not failed ingestions.
    documents = Document.where.associated(:file_attachment)
    documents = documents.merge(Document.outdated.or(Document.failed)) unless args[:scope] == "all"

    count = 0
    documents.find_each do |document|
      IngestDocumentJob.perform_later(document, force: true)
      count += 1
    end
    puts "Enqueued #{count}"
  end

  desc "Embed missing or stale chunks of ingested documents (safe to rerun: up-to-date chunks are skipped); citewise:embed[raw,dry_run] only prints counts"
  task :embed, [ :strategy, :dry_run ] => :environment do |_task, args|
    strategy = args[:strategy].presence || "raw"
    abort "Only the raw strategy is implemented (got #{strategy.inspect})" unless strategy == "raw"

    embedder = Embeddings::DocumentEmbedder.new
    totals = Hash.new(0)
    documents = Document.ingested.find_each.select do |document|
      estimate = embedder.estimate(embedder.pending(document, strategy))
      estimate.each { |key, value| totals[key] += value }
      estimate[:chunks].positive?
    end

    # Batches are per document, so every document with pending chunks takes at least one request.
    config = Rails.configuration.x.embeddings
    minutes = [ totals[:requests].fdiv(config[:requests_per_minute]), totals[:tokens].fdiv(config[:tokens_per_minute]) ].max
    puts "#{strategy} with #{embedder.embedder.model}: #{documents.size} #{"document".pluralize(documents.size)}, " \
      "#{totals[:chunks]} chunks, ~#{totals[:tokens]} tokens (estimated), #{totals[:requests]} requests, " \
      "~#{minutes.ceil} min at #{config[:requests_per_minute]} requests/min and #{config[:tokens_per_minute]} tokens/min"

    if args[:dry_run] == "dry_run"
      puts "Dry run: nothing enqueued"
    else
      documents.each { |document| EmbedDocumentJob.perform_later(document, strategy: strategy) }
      puts "Enqueued #{documents.size}"
    end
  end
end
