# Citewise

Rails 8.1 app (Ruby 4.0.7) on Postgres 17 + pgvector. Hotwire, Tailwind, importmap, Solid Cache/Queue/Cable, Minitest.

## Development environment

Everything runs in the devcontainer, driven from the terminal with the Dev Containers CLI (not VS Code):

```sh
devcontainer up --workspace-folder .                              # build/start; runs bin/setup --skip-server
devcontainer up --workspace-folder . --remove-existing-container  # full rebuild (Dockerfile/features/.env changes)
devcontainer exec --workspace-folder . bash                       # shell in /workspaces/citewise
devcontainer exec --workspace-folder . bin/rails test             # one-off command
devcontainer exec --workspace-folder . bin/dev                    # run the app (Procfile.dev: rails server + tailwindcss:watch)
```

- Plain `docker compose -f .devcontainer/compose.yaml up` skips `devcontainer.json` (features, `postCreateCommand`), so gems aren't installed and Ruby isn't on PATH for `docker exec`. Use the CLI.
- The CLI ignores `forwardPorts`, so port 3000 isn't reachable from the host browser unless `ports:` is added to `compose.yaml`.
- Compose project is `citewise`; DB data lives in the `citewise_postgres-data` volume.
- There's no `.ruby-version`. The Ruby version is the `RUBY_VERSION` build arg in both `.devcontainer/Dockerfile` and `Dockerfile`; change both together.

## Database

- Image `pgvector/pgvector:pg17`. `.devcontainer/init-scripts/01-init.sql` enables `vector` in `citewise_development` on first start of an empty volume.
- The `EnablePgvector` migration keeps `enable_extension "vector"` in `db/schema.rb` so `citewise_test` gets it too.
- Credentials: user `postgres`, password `devpassword`. These must stay consistent across `compose.yaml`, `devcontainer.json` (`DB_*`), and `config/database.yml`.
- Vector search uses the `neighbor` gem (`has_neighbors`).

## Secrets

- Local secrets go in `.env` at the repo root (git- and docker-ignored; template in `.env.example`). It's loaded via `env_file` in `compose.yaml`, only when the container is created, so rebuild after editing.
- Never commit secrets or add them to `devcontainer.json` `containerEnv`, which would also override `.env`.
- `.dockerignore` keeps `.env*` and `config/master.key` out of the production image (`Dockerfile` does `COPY . .`).

## LLM

- RubyLLM is configured in `config/initializers/ruby_llm.rb`, Anthropic only (`ANTHROPIC_API_KEY`, falling back to `credentials.anthropic.api_key`).
- Anthropic has no embeddings API. Storing embeddings needs another RubyLLM provider.
- Smoke test: `bin/rails runner 'puts RubyLLM.chat(model: "claude-haiku-4-5").ask("Reply with exactly: citewise ok").content'`

## Checks

`bin/ci` runs setup, `bin/rubocop`, `bin/bundler-audit`, `bin/importmap audit`, `bin/brakeman`, `bin/rails test`, and the seed replant. Style is `rubocop-rails-omakase` via `.rubocop.yml`.
