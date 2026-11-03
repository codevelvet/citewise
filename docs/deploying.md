# Deploying Citewise to Render

> **Live plan: free.** `citewise-web` and `citewise-db` run on Render's free plan, and there is no `citewise-worker`. Start with [Free plan](#free-plan), which says what differs from the paid-plan steps below. Those steps are kept because we expect to upgrade before the free database expires or before real users arrive.
>
> **`citewise-db` created:** `<YYYY-MM-DD>` · **expires:** `<YYYY-MM-DD>` (day 30) · **deleted:** `<YYYY-MM-DD>` (day 44)
>
> This line is where the database's expiry is recorded. Read the creation date from `citewise-db`'s page in the Render dashboard, and update the line in a commit whenever the database is upgraded or re-created.

Citewise runs on [Render](https://render.com) from [`render.yaml`](../render.yaml):

| Resource          | What it runs                                                     | Plan          |
|-------------------|------------------------------------------------------------------|---------------|
| `citewise-web`    | The production `Dockerfile`: Thruster in front of Puma, port 10000 | `starter`     |
| `citewise-worker` | The same image, running `bin/jobs` (Solid Queue)                 | `starter`     |
| `citewise-db`     | Postgres 17: `citewise_production` plus `_cache`, `_queue`, and `_cable` databases | `basic-256mb` |

This table is the paid setup. `render.yaml` currently has `plan: free` for `citewise-web` and `citewise-db`, and no `citewise-worker`.

Everything runs in `oregon`. Uploaded documents are stored in a Cloudflare R2 bucket.

Deploys are manual. Nothing deploys on push or merge (`autoDeployTrigger: off`), and there are no preview environments. Render deploys from the `production` branch, never `main`. Each release is a commit on `main` tagged with a [semver](https://semver.org) version, and `production` is moved to that commit (see [Releases](#releases)):

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

## Free plan

This is the live setup. Free services have no pre-deploy command, no background worker, and no shell, so the steps below replace those parts of the paid-plan runbook.

### Migrations

`bin/docker-entrypoint` runs `bin/rails db:prepare` when the web service boots. That creates and migrates the databases on the first deploy and runs new migrations on later ones. It also runs on every restart, and free services can restart at any time.

### Background jobs

`SOLID_QUEUE_IN_PUMA=true` is set on `citewise-web`, so Solid Queue runs inside Puma instead of in a worker. Ingestion and embedding jobs run on the web service, and their progress shows in its logs.

The service spins down after 15 minutes without traffic, and jobs pause with it. During a long embed, keep the site awake, for example by loading `https://<host>/up` every few minutes, or expect the jobs to resume when traffic returns.

### Running production tasks from the Mac

With no shell, one-off production tasks run on the Mac in the production image, never inside the dev container.

1. Build the image from a checkout of the deployed tag:

   ```sh
   git checkout vX.Y.Z && docker build -t citewise-prod .
   ```

2. Keep the secrets in `~/.config/citewise/prod.env`, outside the repository, with mode `600` (`chmod 600 ~/.config/citewise/prod.env`). It sets:
   - `DATABASE_URL`: the database's **external** URL, from `citewise-db`'s page in the Render dashboard;
   - `RAILS_MASTER_KEY`;
   - `ANTHROPIC_API_KEY`;
   - `VOYAGE_API_KEY`;
   - `R2_ACCOUNT_ID`;
   - `R2_ACCESS_KEY_ID`;
   - `R2_SECRET_ACCESS_KEY`;
   - `R2_BUCKET`.

   Never commit the file or paste its values anywhere.

3. In the Render dashboard, temporarily add the Mac's public IP (`curl https://ifconfig.me`) to `citewise-db`'s allow list. Remove it when you're done. A Blueprint sync may reset the list to `render.yaml`'s empty `ipAllowList`, so check it again after a sync.

4. Define this shell function:

   ```sh
   prod() {
     docker run --rm -it --env-file ~/.config/citewise/prod.env -e RAILS_ENV=production \
       -v "$PWD/test/fixtures/files/handbook:/corpus:ro" citewise-prod "$@"
   }
   ```

   It mounts the corpus from `$PWD`, so run it from the root of the checkout.

5. Then, in order:

   ```sh
   prod bin/rails runner 'puts ActiveRecord::Base.connection.select_value("select 1")'
   prod bin/rails citewise:create_user
   prod bin/rails "citewise:import:directory[/corpus,<collection>]"
   prod bin/rails "citewise:embed[raw,dry_run]"
   prod bin/rails "citewise:embed[raw]"
   ```

   - The first command checks the connection and should print `1`.
   - `citewise:create_user` prompts for the email and password and never echoes the password.
   - The import uploads each file straight to R2 from the mounted directory, so no tarball or manual upload is needed. It queues ingestion, which runs on `citewise-web`. Keep the site awake and watch its logs until ingestion settles.
   - The dry run prints the estimate and enqueues nothing. **Stop and check the estimate** before running the real embed (see [step 5](#5-import-and-embed-the-corpus) for how to read it).

The container's entrypoint only runs `db:prepare` for `rails server`, so these commands never migrate the database.

### Limits

- The Postgres database **expires 30 days after creation**. After a 14-day grace period it is **permanently deleted**. Its dates are in the note at the top of this runbook.
- It has **no backups**.
- R2 files survive, but users, documents, chunks, embeddings, and questions do not.

Before day 30, either upgrade the database, or re-create it, then re-import and re-embed. Re-embedding costs Voyage spend and hours of throttled jobs.

### Other differences

- **Both services:** where this runbook says "both services", the free plan has only `citewise-web`. When you rotate a secret, also update `~/.config/citewise/prod.env`.
- **Confirming the deploy:** the shell-based checks in [step 6](#6-confirm-the-deploy) need a substitute. Run `prod bin/rails runner 'puts Session.last.ip_address'` from the Mac for the client-IP check. The `localhost` host check can't be run without a shell, and the backups check doesn't apply.

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

With the commit you want on `main`, follow [Releases](#releases) with `v1.0.0` and the message `First production deploy`. Deploy the latest commit of `production` to **`citewise-web`**, then **`citewise-worker`**.

The web service's pre-deploy command runs `bin/rails db:prepare`:
- On the first deploy, it creates `citewise_production_cache`, `_queue`, and `_cable`.
- It loads every schema, including `enable_extension "vector"`.

If it fails, the deploy stops before any traffic switches. Read its log. A permissions error on `CREATE DATABASE` or `CREATE EXTENSION` means the database user lacks that right, so contact Render support.

On the free plan, `db:prepare` runs when the web service boots instead (see [Migrations](#migrations)).

Both services log `Citewise revision <first 7 characters of the commit>` when they boot.

### 4. Create the first user

Open **`citewise-web` → Shell** and run:

```sh
bin/rails citewise:create_user
```

It prompts for the email and password and never echoes the password. On the free plan, run `prod bin/rails citewise:create_user` from the Mac instead (see [Running production tasks from the Mac](#running-production-tasks-from-the-mac)).

### 5. Import and embed the corpus

The corpus isn't in the repository. On either plan, run these from the Mac as described in [Running production tasks from the Mac](#running-production-tasks-from-the-mac).

1. Import it:

   ```sh
   prod bin/rails "citewise:import:directory[/corpus,<collection>]"
   ```

   The import uploads each file straight to R2 from the mounted directory and queues ingestion. The worker (on the free plan, `citewise-web`) chunks the documents. Watch its logs until ingestion settles.

2. Check what embedding will cost before anything calls Voyage:

   ```sh
   prod bin/rails "citewise:embed[raw,dry_run]"
   ```

   This prints the documents, chunks, estimated tokens, requests, and minutes. **Stop here and review the numbers.** Voyage's limits on this key are 3 requests and 10,000 tokens per minute. The single embeddings thread waits between requests to stay under them, so the minutes figure is the real wall-clock time.

3. Start embedding:

   ```sh
   prod bin/rails "citewise:embed[raw]"
   ```

   Progress shows in the worker's logs (on the free plan, `citewise-web`'s) as `Voyage embed …` lines. The task is safe to rerun: chunks that are already up to date are skipped.

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

On the free plan, see [Other differences](#other-differences) for the checks that need a shell.

### 7. Turn on the ask page

On **`citewise-web` → Environment**, add `CITEWISE_ASK_PAGE_ENABLED` = `true`. Choose **Save and deploy**, which deploys the existing build, not a newer commit.

Only the web service serves the page's routes, so the worker doesn't need the variable. The daily cap (`CITEWISE_MAX_QUESTIONS_PER_DAY`, default 20) protects the API budget. Sign in and ask one question to confirm that answers stream in.

## Releases

Render deploys from the `production` branch, never `main`, and never on its own. To release, tag a commit on `main` and point `production` at it. On the Mac:

```sh
git checkout main && git pull
git tag -a vX.Y.Z -m '<what this release changes>'
git push origin vX.Y.Z
git push origin 'vX.Y.Z^{commit}:refs/heads/production'
git rev-parse 'vX.Y.Z^{commit}'
git ls-remote origin production
```

The last two commands must print the same SHA, which confirms that `production` points at the tagged commit.

- `^{commit}` pushes the commit the annotated tag points to, not the tag object.
- This push only fast-forwards. It's rejected if `production` has commits that the new tag doesn't include.

Then, in Render's dashboard, open the web service (connected to the repository, with the `production` branch selected) and choose **Manual Deploy → Deploy latest commit**. Check that the deploy shows the same SHA. On the paid plan, do the same for `citewise-worker`.

## Routine deploys

1. Merge to `main`, and run `bin/ci` if CI hasn't already.
2. Release the merge commit with the next version (see [Releases](#releases)).
3. Deploy the latest commit of `production` to `citewise-web`, then `citewise-worker`. The web pre-deploy step runs any new migrations once. On the free plan there is only `citewise-web`, and `db:prepare` runs new migrations when it boots.
4. Check each service's boot log for `Citewise revision <commit>`.

## Rollback

Push the previous tag's commit to `production`, with `--force` because this moves the branch backwards:

```sh
git push --force origin 'vPREV^{commit}:refs/heads/production'
git rev-parse 'vPREV^{commit}'
git ls-remote origin production
```

The last two commands must print the same SHA. Then redeploy the same way as a release (**Manual Deploy → Deploy latest commit**). This is the only step in the runbook that needs `--force`.

Migrations are **not** reversed automatically, so a rollback across a migration needs a manual plan. The older code runs against the newer schema, so keep migrations backward compatible (add first, remove in a later release). If a migration has to be undone, run `bin/rails db:rollback` in the web shell (on the free plan, `prod bin/rails db:rollback` from the Mac) **before** redeploying the older code. Do that only when you know what it drops.

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
