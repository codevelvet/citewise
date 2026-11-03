source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.4"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Load .env files into ENV in development and test
gem "dotenv-rails", groups: %i[ development test ]
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"
# Nearest neighbor search with pgvector [https://github.com/ankane/neighbor]
gem "neighbor"
# One API for LLM providers [https://rubyllm.com]
gem "ruby_llm"
# CommonMark + GFM parser for structure-aware chunking [https://github.com/gjtorikian/commonmarker]
gem "commonmarker"
# HTTP client for the Voyage embeddings API [https://lostisland.github.io/faraday]
gem "faraday"
# Official Claude API client, for search-result citations [https://github.com/anthropics/anthropic-sdk-ruby]
gem "anthropic", "1.80.0"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 2.2"
gem "ruby-vips", "~> 2.3"
# Active Storage's S3 service, for Cloudflare R2 in production [https://github.com/aws/aws-sdk-ruby]
gem "aws-sdk-s3", "1.233.2", require: false

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  # Drives Chromium and WebKit through the Playwright CLI [https://github.com/YusukeIwaki/capybara-playwright-driver]
  gem "capybara-playwright-driver", "0.5.13"
  # Must match the playwright CLI's version: see .devcontainer/Dockerfile and the system-test CI job
  gem "playwright-ruby-client", "1.64.0"
  # Blocks real HTTP in tests [https://github.com/bblimke/webmock]
  gem "webmock"
  # Replays recorded HTTP interactions [https://github.com/vcr/vcr]
  gem "vcr"
end
