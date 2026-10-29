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
        document.enqueue_ingest
      end

      puts "Created #{counts[:created]}, updated #{counts[:updated]}, unchanged #{counts[:unchanged]}"
    end
  end

  desc "Enqueue re-ingestion of outdated and failed documents, or forced re-ingestion of every document with citewise:reingest[all]"
  task :reingest, [ :scope ] => :environment do |_task, args|
    # Documents without a file are uploads still in progress, not failed ingestions.
    documents = Document.where.associated(:file_attachment)
    all = args[:scope] == "all"
    documents = documents.merge(Document.outdated.or(Document.failed)) unless all

    count = 0
    documents.find_each do |document|
      count += 1 if document.enqueue_ingest(force: all)
    end
    puts "Enqueued #{count}"
  end

  desc "Answer a question from the embedded chunks, with citations (1 embedding call + 1 answering call)"
  task :ask, [ :question ] => :environment do |_task, args|
    # Rake splits arguments on commas, so put the question back together.
    text = [ args[:question], *args.extras ].compact.join(", ").strip
    abort %(Usage: bin/rails "citewise:ask[How much paid leave do I get?]") if text.empty?
    abort "Question is #{text.length} characters; the limit is #{Question::MAX_TEXT_LENGTH}" if text.length > Question::MAX_TEXT_LENGTH

    begin
      question = Answering::AskService.call(text)
    rescue Embeddings::Embedder::Error, Answering::Answerer::Error => error
      abort "Failed: #{error.message}"
    end

    puts question.answer, ""
    if question.incomplete?
      reason = question.stop_reason
      reason += " at #{Rails.configuration.x.answering[:max_tokens]} tokens" if reason == "max_tokens"
      puts "Warning: stopped early (#{reason}), so this answer may be incomplete.", ""
    end
    if question.retrieval.empty?
      puts "No embeddings found for #{Rails.configuration.x.embeddings[:model]}/#{Rails.configuration.x.retrieval[:strategy]}. Run citewise:embed."
      next
    end

    puts "Citations"
    puts "  (none)" if question.citations.empty?
    question.citations.each.with_index(1) do |citation, number|
      puts "  [#{number}] #{citation["source_title"]}"
      puts "      #{citation["cited_text"].squish}"
    end

    puts "", "Retrieved"
    question.retrieval.each do |result|
      puts format("  %d. %.3f  %s", result["rank"], result["similarity"], result["source_title"])
    end

    puts "", "Tokens: input #{question.input_tokens}, output #{question.output_tokens}, " \
      "cache read #{question.cache_read_tokens}, cache write #{question.cache_write_tokens}"
    puts "Time: retrieval #{question.retrieval_ms} ms, answer #{question.answer_ms} ms (question #{question.id}, #{question.model})"
  end

  desc "Create a user, or set a new password and sign out every session if the email exists (prompts; the password isn't echoed)"
  task create_user: :environment do
    require "io/console"
    # Never fall back to reading the password with echo, or from a pipe.
    abort "citewise:create_user needs an interactive terminal, so it can read the password without echo" unless $stdin.tty?

    print "Email: "
    email_address = $stdin.gets&.strip
    abort "No email address given" if email_address.blank?
    # getpass turns echo off and drops the newline. Both return nil at end of input.
    password = $stdin.getpass("Password: ")
    confirmation = $stdin.getpass("Confirm password: ")
    abort "No password given" if password.blank? || confirmation.nil?
    abort "The passwords don't match" unless password == confirmation

    user = User.find_or_initialize_by(email_address: email_address)
    existing = user.persisted?
    user.assign_attributes(password: password, password_confirmation: confirmation)
    # Validation messages describe the password's length, never its value.
    abort user.errors.full_messages.to_sentence unless user.valid?

    signed_out = 0
    User.transaction do
      user.save!
      # A reset may follow a leaked password, so no browser stays signed in with the old one.
      signed_out = user.sessions.destroy_all.size if existing
    end
    # Open sockets outlive their session row. Once closed, they can't reconnect without one.
    ActionCable.server.remote_connections.where(current_user: user).disconnect if existing

    if existing
      puts "Set a new password for #{user.email_address} and signed out #{signed_out} #{"session".pluralize(signed_out)}"
    else
      puts "Created user #{user.email_address}"
    end
  end

  desc "Mark questions pending for over an hour failed (also runs every 15 minutes in production via config/recurring.yml)"
  task fail_abandoned_questions: :environment do
    count = Question.fail_abandoned
    puts "Marked #{count} abandoned #{"question".pluralize(count)} failed"
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
      # Documents whose embed job is already waiting aren't counted.
      count = documents.count { |document| document.enqueue_embed(strategy: strategy) }
      puts "Enqueued #{count}"
    end
  end
end
