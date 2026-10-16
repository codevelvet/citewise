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

    # Settings for Chunking::MarkdownChunker during ingestion. Changing them makes
    # existing documents Document.outdated; run bin/rails citewise:reingest to re-chunk.
    config.x.chunker = { target_tokens: 400, max_tokens: 512, min_tokens: 100, overlap_tokens: 50, merge_policy: :within_section }

    # Settings for Embeddings::Embedder.default and EmbedDocumentJob. The HNSW index on
    # chunk_embeddings serves voyage-4-lite at 1024 dimensions only.
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
  end
end
