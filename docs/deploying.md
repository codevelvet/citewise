# Deploying Citewise to Render

Citewise runs on [Render](https://render.com) from [`render.yaml`](../render.yaml):

| Resource          | What it runs                                                     | Plan          |
|-------------------|------------------------------------------------------------------|---------------|
| `citewise-web`    | The production `Dockerfile`: Thruster in front of Puma, port 10000 | `starter`     |
| `citewise-worker` | The same image, running `bin/jobs` (Solid Queue)                 | `starter`     |
| `citewise-db`     | Postgres 17: `citewise_production` plus `_cache`, `_queue`, and `_cable` databases | `basic-256mb` |

Everything runs in `oregon`. Uploaded documents are stored in a Cloudflare R2 bucket.

Deploys are manual. Nothing deploys on push or merge (`autoDeployTrigger: off`), and there are no preview environments. Each deploy is a commit on `main` tagged with a [semver](https://semver.org) version:

- **patch** (`v1.0.1`): fixes;
- **minor** (`v1.1.0`): features;
- **major** (`v2.0.0`): changes that need data or operations work.

## What needs a paid plan

These were checked from memory, not against Render's current docs. Confirm them, and the prices, at <https://render.com/pricing> before creating the Blueprint.

- **Background workers** have no free tier.
- **Pre-deploy commands** (`preDeployCommand`, which runs migrations) need a paid compute plan.
- **The service shell** (used below for `citewise:create_user` and the corpus import) needs a paid compute plan.
- **Postgres backups and point-in-time recovery** need a paid database. Free databases also expire.

`starter` and `basic-256mb` are paid plans, so everything below works on them.

## First deploy

### 1. Create the R2 bucket

In the Cloudflare dashboard:

1. Create an R2 bucket, for example `citewise-production`, and keep it private.
2. Create an R2 API token with **Object Read & Write** on that bucket only.
3. Note four values:
   - the account ID;
   - the access key ID;
   - the secret access key;
   - the bucket name.

### 2. Create the Blueprint

In Render, go to **New → Blueprint**, pick this repository, and select `render.yaml`. Render asks for every `sync: false` variable. Enter each one for **both** services:

| Variable               | Value                                                       |
|------------------------|-------------------------------------------------------------|
| `RAILS_MASTER_KEY`     | The contents of `config/master.key`                         |
| `ANTHROPIC_API_KEY`    | The production Anthropic key                                |
| `VOYAGE_API_KEY`       | The Voyage key. An `al-…` key works with the configured MongoDB Atlas endpoint (`config.x.embeddings[:base_url]`). A `pa-…` key needs `https://api.voyageai.com/v1` instead. |
| `R2_ACCOUNT_ID`        | From step 1                                                 |
| `R2_ACCESS_KEY_ID`     | From step 1                                                 |
| `R2_SECRET_ACCESS_KEY` | From step 1                                                 |
| `R2_BUCKET`            | From step 1                                                 |

Render only asks for these at creation. Later Blueprint syncs never change them, so all later changes happen in each service's **Environment** page.

Leave `CITEWISE_ASK_PAGE_ENABLED` unset. The ask page stays off (its routes return 404) until step 7.

### 3. Deploy `v1.0.0`

On the Mac, with the commit you want on `main`:

```sh
git switch main && git pull
git tag -a v1.0.0 -m "First production deploy"
git push origin v1.0.0
git rev-parse 'v1.0.0^{commit}'      # the commit to deploy
```

For **`citewise-web`**, then **`citewise-worker`**, go to **Manual Deploy → Deploy a specific commit** and choose that commit.

The web service's pre-deploy command runs `bin/rails db:prepare`:
- On the first deploy, it creates `citewise_production_cache`, `_queue`, and `_cable`.
- It loads every schema, including `enable_extension "vector"`.

If it fails, the deploy stops before any traffic switches. Read its log. A permissions error on `CREATE DATABASE` or `CREATE EXTENSION` means the database user lacks that right, so contact Render support.

Both services log `Citewise revision <first 7 characters of the commit>` when they boot.

### 4. Create the first user

Open **`citewise-web` → Shell** and run:

```sh
bin/rails citewise:create_user
```

It prompts for the email and password and never echoes the password.

### 5. Import and embed the corpus

The corpus isn't in the repository, so it travels through the R2 bucket:

1. On the Mac, run `tar -czf corpus.tar.gz -C <corpus directory> .`.
2. In the Cloudflare dashboard, upload the file to the bucket as `imports/corpus.tar.gz`.
3. In the `citewise-web` shell, download and extract it:

   ```sh
   bin/rails runner 'ActiveStorage::Blob.service.bucket.object("imports/corpus.tar.gz").download_file("/tmp/corpus.tar.gz")'
   mkdir -p /tmp/corpus && tar -xzf /tmp/corpus.tar.gz -C /tmp/corpus
   bin/rails "citewise:import:directory[/tmp/corpus,<collection>]"
   ```

   The import attaches each file to R2 and queues ingestion. The worker chunks the documents. Watch its logs until ingestion settles.

4. Check what embedding will cost before anything calls Voyage:

   ```sh
   bin/rails "citewise:embed[raw,dry_run]"
   ```

   This prints the documents, chunks, estimated tokens, requests, and minutes. **Stop here and review the numbers.** Voyage's limits on this key are 3 requests and 10,000 tokens per minute. The worker's single embeddings thread waits between requests to stay under them, so the minutes figure is the real wall-clock time.

5. Start embedding:

   ```sh
   bin/rails citewise:embed
   ```

   Progress shows in the worker's logs as `Voyage embed …` lines. The task is safe to rerun: chunks that are already up to date are skipped.

6. Delete `imports/corpus.tar.gz` from the bucket, and run `rm -rf /tmp/corpus /tmp/corpus.tar.gz` in the shell.

### 6. Confirm the deploy

The host is the service's `onrender.com` name, such as `citewise-web.onrender.com`.

- **HTTPS.** `curl -sI http://<host>/session/new` should redirect to `https://`. That redirect comes from Render's edge: the app treats every request as HTTPS (`assume_ssl`), so it never redirects by itself. `curl -sI https://<host>/session/new` should return `200` with a `strict-transport-security` header.
- **Secure cookie.** In that same response, `set-cookie: _citewise_session=…` must include `secure`. After you sign in, the `session_id` cookie in the browser's developer tools must show **Secure** too.
- **Host check.** Render routes by Host, so test this from the web shell: `curl -sI -H "Host: evil.example" http://localhost:10000/session/new` should return `403`. `curl -sI http://localhost:10000/up` should return `200`.
- **Client IP.** The sign-in rate limit (10 tries per 3 minutes) is keyed by `request.remote_ip`. To check it:
  1. Run `curl https://ifconfig.me` on the Mac.
  2. Sign in from the Mac.
  3. In `citewise-web`'s logs, find `Started POST "/session" for <ip>`. That IP must match the Mac's.
  4. `bin/rails runner 'puts Session.last.ip_address'` in the shell should show the same.
  5. Repeat from a phone on cellular. It should show the phone's address, not the Mac's.

  If both show the same address, or it's a `10.x`, `172.16–31.x`, or Render-owned address, every visitor shares one rate-limit bucket. Don't turn the page on until that's fixed.
- **Backups.** On `citewise-db`'s **Recovery** page, check that point-in-time recovery is available and that a backup exists.
- **Version.** Signed in, `https://<host>/session/new` shows `Version <commit>` in the footer. While the ask page is off, `/` returns 404.

### 7. Turn on the ask page

On **`citewise-web` → Environment**, add `CITEWISE_ASK_PAGE_ENABLED` = `true`. Choose **Save and deploy**, which deploys the existing build, not a newer commit.

Only the web service serves the page's routes, so the worker doesn't need the variable. The daily cap (`CITEWISE_MAX_QUESTIONS_PER_DAY`, default 20) protects the API budget. Sign in and ask one question to confirm that answers stream in.

## Routine deploys

1. Merge to `main`, and run `bin/ci` if CI hasn't already.
2. Tag the merge commit with the next version, then push the tag:

   ```sh
   git switch main && git pull
   git tag -a v1.2.0 -m "…"
   git push origin v1.2.0
   git rev-parse 'v1.2.0^{commit}'
   ```

3. Deploy that commit to `citewise-web`, then `citewise-worker` (**Manual Deploy → Deploy a specific commit**). The web pre-deploy step runs any new migrations once.
4. Check each service's boot log for `Citewise revision <commit>`.

## Rollback

Redeploy the previous tag's commit (`git rev-parse 'v1.1.0^{commit}'`) to both services. If an earlier deploy in a service's **Events** shows a **Rollback** option, that does the same without rebuilding.

Migrations are **not** reversed. The older code runs against the newer schema, so keep migrations backward compatible (add first, remove in a later release). If a migration has to be undone, run `bin/rails db:rollback` in the web shell **before** redeploying the older code. Do that only when you know what it drops.

## Rotating secrets

Change each secret in the **Environment** page of **both** services, then choose **Save and deploy** (existing build) on each. Revoke the old value only after both services run with the new one.

- **`ANTHROPIC_API_KEY`**: create a key in the Anthropic console, set it, deploy, then delete the old key.
- **`VOYAGE_API_KEY`**: create a key with the same provider (an `al-…` or `pa-…` key must match `base_url`), set it, deploy, then revoke the old one.
- **`R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY`**: create a new R2 API token scoped to the bucket, set both values, deploy, then delete the old token. `R2_ACCOUNT_ID` and `R2_BUCKET` only change if the bucket moves.
- **`RAILS_MASTER_KEY`**:
  1. On the Mac, run `bin/rails credentials:show > /tmp/credentials.yml` (don't commit it).
  2. Delete `config/master.key` and `config/credentials.yml.enc`.
  3. Run `bin/rails credentials:edit`, paste the old contents back in, and save. This writes a new key and file.
  4. Delete `/tmp/credentials.yml`.
  5. Commit `config/credentials.yml.enc` and tag a release.
  6. Set the new `RAILS_MASTER_KEY` on both services, then deploy the tag.

  Changing `secret_key_base` inside the credentials as well signs everyone out.
- **Database password**: Render manages it, and `DATABASE_URL` is read from the database (`fromDatabase`). Use the credential options on `citewise-db`'s page in the dashboard (confirm what your plan offers), then run a Blueprint sync, which refreshes `DATABASE_URL`, and redeploy both services.

## Not covered yet

- **A custom domain** must be added to `config.hosts` in `config/environments/production.rb`, which only allows `RENDER_EXTERNAL_HOSTNAME` today.
- **Cloudflare's proxy** (the orange cloud) in front of Render would make every visitor's IP read as a Cloudflare address until Cloudflare's ranges are trusted proxies.
