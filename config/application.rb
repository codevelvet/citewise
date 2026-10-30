require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Citewise
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # The deployed commit, short. Render sets RENDER_GIT_COMMIT on deploys; nil elsewhere.
    config.x.revision = ENV["RENDER_GIT_COMMIT"].presence&.first(7)

    # Settings for Chunking::MarkdownChunker during ingestion. Changing them makes
    # existing documents Document.outdated; run bin/rails citewise:reingest to re-chunk.
    config.x.chunker = { target_tokens: 400, max_tokens: 512, min_tokens: 100, overlap_tokens: 50, merge_policy: :within_section }

    # Settings for Embeddings::Embedder.default and EmbedDocumentJob.
    config.x.embeddings = {
      model: "voyage-4-lite",
      dimensions: 1024,
      # Inputs per request, and estimated tokens per request (Voyage allows 1M; keep it at most tokens_per_minute).
      batch_size: 128,
      max_batch_tokens: 8_000,
      # The key's rate limits. Embeddings::RateLimiter enforces them in-process only,
      # so the embeddings queue in config/queue.yml must keep one process and one thread.
      requests_per_minute: 3,
      tokens_per_minute: 10_000,
      # Keys only authenticate on the host that issued them (a wrong host returns 403):
      # al-… keys are MongoDB Atlas (https://ai.mongodb.com/v1), pa-… keys are Voyage (https://api.voyageai.com/v1).
      base_url: "https://ai.mongodb.com/v1"
    }

    # Settings for Retrieval::Retriever. The embedding model and dimensions come from
    # config.x.embeddings. k is the number of chunks sent to the answerer; CLAUDE.md caps it at 8.
    config.x.retrieval = { k: 8, strategy: "raw" }

    # Settings for Answering::Answerer.default. Keep the model a Haiku unless CLAUDE.md changes.
    # max_retries is the one retry layer for answering: the Anthropic SDK retries 429s and 5xx errors itself.
    # It stays on even though AskJob answers in a job: AskJob retries only the query embedding's rate limits,
    # which fail before the answerer is called. A job retry after an answering error would re-embed the
    # question and have to reset a failed Question, and the SDK's retries are narrower and already tested.
    config.x.answering = { model: "claude-haiku-4-5", max_tokens: 1024, max_retries: 2 }

    # Settings for the ask page (QuestionsController) and AskJob.
    positive_integer = ->(name, default) do
      value = ENV[name].presence || default
      raise ArgumentError, "#{name} must be a positive integer, got #{value.inspect}" unless value.match?(/\A[1-9]\d*\z/)

      Integer(value, 10)
    end
    config.x.ask_page = {
      # Off in production unless CITEWISE_ASK_PAGE_ENABLED=true; when off, its routes return 404.
      enabled: !Rails.env.production? || ENV["CITEWISE_ASK_PAGE_ENABLED"] == "true",
      # AskJobs running at once, across every worker process. Changing it takes a restart of bin/jobs.
      max_concurrent_asks: positive_integer.("CITEWISE_MAX_CONCURRENT_ASKS", "1"),
      # Questions one signed-in user may ask.
      per_minute: 3,
      per_hour: 30,
      # Questions everyone together may ask in 24 hours. It protects the $20 API budget, so it
      # starts low: 20 questions cost about $0.22 a day at worst. Changing it takes a restart.
      per_day: positive_integer.("CITEWISE_MAX_QUESTIONS_PER_DAY", "20"),
      # Where the per-user counts live; nil means Rails.cache. config/environments/test.rb sets a real store.
      rate_limit_store: nil
    }
  end
end
