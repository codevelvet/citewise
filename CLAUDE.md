# Citewise

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

# Project
Rails 8.1 app (Ruby 4.0.9) on Postgres 17 + pgvector. Hotwire, Tailwind, importmap, Solid Cache/Queue/Cable, Minitest.

## Development environment

Everything runs in the devcontainer, driven from the terminal with the Dev Containers CLI (not VS Code):

```sh
devcontainer up --workspace-folder .                              # build/start; runs bin/setup --skip-server
devcontainer up --workspace-folder . --remove-existing-container  # full rebuild (Dockerfile/features/.env changes)
devcontainer exec --workspace-folder . bash                       # shell in /workspaces/citewise
devcontainer exec --workspace-folder . bin/rails test             # one-off command
devcontainer exec --workspace-folder . bin/dev                    # run the app (Procfile.dev: rails server + tailwindcss:watch + Solid Queue worker)
```

- Plain `docker compose -f .devcontainer/compose.yaml up` skips `devcontainer.json` (features, `postCreateCommand`), so gems aren't installed and Ruby isn't on PATH for `docker exec`. Use the CLI.
- The CLI ignores `forwardPorts`, so port 3000 isn't reachable from the host browser unless `ports:` is added to `compose.yaml`.
- Compose project is `citewise`; DB data lives in the `citewise_postgres-data` volume.
- The Ruby version lives in `.ruby-version` (read by CI) and the `RUBY_VERSION` build arg in both `.devcontainer/Dockerfile` and `Dockerfile`; change all three together.

## Database

- Image `pgvector/pgvector:pg17`. `.devcontainer/init-scripts/01-init.sql` enables `vector` in `citewise_development` on first start of an empty volume.
- The `EnablePgvector` migration keeps `enable_extension "vector"` in `db/schema.rb` so `citewise_test` gets it too.
- Credentials: user `postgres`, password `devpassword`. These must stay consistent across `compose.yaml`, `devcontainer.json` (`DB_*`), and `config/database.yml`.
- Vector search uses the `neighbor` gem (`has_neighbors`).

## Secrets

- Local secrets go in `.env` at the repo root (git- and docker-ignored; template in `.env.example`). It's loaded via `env_file` in `compose.yaml`, only when the container is created, so rebuild after editing.
- Never commit secrets or add them to `devcontainer.json` `containerEnv`, which would also override `.env`.
- `.dockerignore` keeps `.env*` and `config/master.key` out of the production image (`Dockerfile` does `COPY . .`).

## API spend

The Anthropic API credit for this project is capped at $20. Claude Code
itself runs on a separate plan; these rules cover calls the app makes.

- Never make real Anthropic or Voyage API calls without asking me first.
  That includes rake tasks, `bin/rails runner`, console sessions, and
  scripts. Dry runs are fine.
- Tests must never touch the network. WebMock blocks real requests; use
  fakes or VCR cassettes. Never re-record a cassette without asking.
- The Claude model comes from app configuration (Haiku by default). Never
  hard-code model names or switch to a larger model.
- Keep prompts lean: send at most 8 chunks as context and always set
  `max_tokens` explicitly.
- Code that calls Claude repeatedly with the same document must use
  prompt caching. Offline work, like generating chunk context during
  ingestion, should use the Message Batches API.
- Log input, output, and cache token counts for every Claude call.
- Before any operation that would make more than about 10 API calls,
  print an estimate of calls and tokens and stop for my confirmation.

## LLM

- RubyLLM is configured in `config/initializers/ruby_llm.rb`, Anthropic only (`ANTHROPIC_API_KEY`, falling back to `credentials.anthropic.api_key`).
- Anthropic has no embeddings API. Storing embeddings needs another RubyLLM provider.
- Smoke test: `bin/rails runner 'puts RubyLLM.chat(model: "claude-haiku-4-5").ask("Reply with exactly: citewise ok").content'`

## Checks

`bin/ci` runs setup, `bin/rubocop`, `bin/bundler-audit`, `bin/importmap audit`, `bin/brakeman`, `bin/rails test`, and the seed replant. Style is `rubocop-rails-omakase` via `.rubocop.yml`.
