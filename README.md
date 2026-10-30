# Citewise

A Rails 8.1 application backed by PostgreSQL 17 with pgvector for vector search and RubyLLM for Claude integration. Development happens entirely inside a devcontainer.

## Tech stack

| Layer            | Technology                                                        |
| ---------------- | ----------------------------------------------------------------- |
| Language         | Ruby 4.0.9                                                        |
| Framework        | Rails 8.1.4                                                       |
| Database         | PostgreSQL 17 with pgvector (`pgvector/pgvector:pg17` image)      |
| Vector search    | [neighbor](https://github.com/ankane/neighbor) gem                |
| LLM              | [RubyLLM](https://rubyllm.com) (Anthropic provider)               |
| Frontend         | Hotwire (Turbo + Stimulus), Tailwind CSS, importmap, Propshaft    |
| Jobs, cache, websockets | Solid Queue, Solid Cache, Solid Cable                      |
| Web server       | Puma, Thruster                                                    |
| Testing          | Minitest, Capybara, Selenium                                      |
| Linting/security | RuboCop (`rubocop-rails-omakase`), Brakeman, bundler-audit        |
| Deployment       | Render (Blueprint in `render.yaml`), Active Storage on Cloudflare R2 |

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) (Docker Desktop, OrbStack, or similar), running
- One of:
  - [VS Code](https://code.visualstudio.com/) with the [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension, or
  - the [Dev Containers CLI](https://github.com/devcontainers/cli): `npm install -g @devcontainers/cli`
- An Anthropic API key, for the LLM features

Ruby, Postgres, and gems don't need to be installed on the host. They all live in the containers.

## Setup

1. Clone the repository:

   ```sh
   git clone git@github.com:codevelvet/citewise.git
   cd citewise
   ```

2. Create your local secrets file from the template and fill in your key:

   ```sh
   cp .env.example .env
   ```

   ```sh
   ANTHROPIC_API_KEY=sk-ant-...
   VOYAGE_API_KEY=al...
   ```

   `.env` is git- and docker-ignored.
   Dotenv reads it each time Rails boots, so restart the server or job worker after changing it.

3. Start the devcontainer (next section). On first creation it runs `bin/setup --skip-server`, which installs gems and creates and migrates the database. 

## Devcontainer

The devcontainer is a Docker Compose project named `citewise` with two services:

- `rails-app`: the Ruby/Rails development container, with the workspace mounted at `/workspaces/citewise`
- `postgres`: PostgreSQL 17 + pgvector. Data persists in the `citewise_postgres-data` volume. The `vector` extension is enabled via a template.

Inside the container the app connects to Postgres at host `postgres`, user `citewise_app`, password `citewise-local-development`.
```
    "DB_HOST": "postgres",
    "DB_USER": "citewise_app",
    "DB_PASSWORD": "citewise-local-development",
    "DB_TEMPLATE": "citewise_vector_template"
```
`citewise_app` is a non-superuser development role with permissions to create databases.

### Prepare Docker resources
Run these commands from a terminal on your host machine, outside the devcontainer.

Create the private database network once:
```
docker network create \
  --driver bridge \
  --internal \
  --opt com.docker.network.bridge.gateway_mode_ipv4=isolated \
  citewise-db-private
```

If Docker does not support isolated gateway mode, update Docker Desktop before continuing.

Create the administrator password file outside the repository:
```
mkdir -p "$HOME/.config/citewise"
chmod 700 "$HOME/.config/citewise"

(
  umask 077
  if [ ! -f "$HOME/.config/citewise/postgres-admin-password" ]; then
    openssl rand -hex 32 \
      > "$HOME/.config/citewise/postgres-admin-password"
  fi
)
```
The password file is mounted only into PostgreSQL. Do not commit it, copy it into the workspace, or expose it to the Rails container.

These resources persist across container rebuilds. Do not regenerate the password file to rotate an existing database password: changing the file alone does not change PostgreSQL’s stored password.

After preparing the host resources, reopen the project in the devcontainer. On an empty database volume, PostgreSQL initialization scripts create the application role, vector template, and development/test databases. The devcontainer then runs bin/setup --skip-server.

Rebuilding a container preserves the database volume and does not rerun PostgreSQL initialization scripts.

To discard all development/test database data and rerun initialization, close the devcontainer and run this from the host at the repository root:
```
docker compose -f .devcontainer/compose.yaml down --volumes
```
Then reopen/rebuild the devcontainer. The external network and host password file remain available.

### Security
PostgreSQL rejects administrator logins over TCP. Trusted administration runs from the host through docker compose exec, using the database container’s local socket.

The devcontainer sets DB_TEMPLATE=citewise_vector_template. Primary development and test databases inherit the preinstalled vector extension from this template. Queue and cable databases use PostgreSQL’s default template.

Do not expose the Docker socket, Docker API credentials, or administrator password to the Rails container.

### Start

**VS Code:** open the repository folder, then run **Dev Containers: Reopen in Container** from the Command Palette.

**CLI:**

```sh
devcontainer up --workspace-folder .
```

### Open a shell or run commands

**VS Code:** use the integrated terminal once the window has reopened in the container.

**CLI:**

```sh
devcontainer exec --workspace-folder . bash              # interactive shell
devcontainer exec --workspace-folder . bin/rails test    # one-off command
```

### Stop

Closing VS Code, or the CLI session, leaves the containers running. To stop them, run this from the host in the repository root:

```sh
docker compose -f .devcontainer/compose.yaml stop
```

Start them again with `devcontainer up` or **Reopen in Container**.

To remove the containers as well (the database volume is kept):

```sh
docker compose -f .devcontainer/compose.yaml down
```

To also delete the database volume and start from an empty database:

```sh
docker compose -f .devcontainer/compose.yaml down --volumes
```

### Rebuild

Rebuild after changing the `Dockerfile` or devcontainer features.

**VS Code:** **Dev Containers: Rebuild Container**.

**CLI:**

```sh
devcontainer up --workspace-folder . --remove-existing-container
```

> Use the devcontainer tooling to start the environment, not plain `docker compose up`. Compose alone skips `devcontainer.json`, so features and `bin/setup` don't run.

## Running the app

Inside the container:

```sh
bin/dev
```

This starts the Rails server and the Tailwind watcher (see `Procfile.dev`). The app listens on port 3000. VS Code forwards it automatically to <http://localhost:3000>. The Dev Containers CLI doesn't forward ports, so with the CLI the app isn't reachable from a host browser unless a `ports:` mapping is added to `.devcontainer/compose.yaml`.

## Running tests and checks

```sh
bin/rails test    # test suite
bin/ci            # full CI: rubocop, bundler-audit, importmap audit, brakeman, tests, seeds
```

## Deployment

Production runs on Render from [`render.yaml`](render.yaml), deployed by hand from a semver tag. See [docs/deploying.md](docs/deploying.md) for the first deploy, routine deploys, rollback, and rotating secrets. The Kamal configuration in `config/deploy.yml` isn't used.

## License

See [LICENSE](LICENSE).
