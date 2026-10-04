# VPS applications

Central deployment repository for GeorgeDanicico's VPS applications. Each application remains in its own repository; this repository records its deployed source revision as a Git submodule.

| Submodule | Production setup |
| --- | --- |
| [expense-tracker](https://github.com/GeorgeDanicico/expense-tracker) | Calls `scripts/deploy.sh`; Docker image, production environment file, health check and upstream rollback |
| [llm-wiki](https://github.com/GeorgeDanicico/llm-wiki) | Updates a persistent Markdown/Git checkout on the host |
| [investments-scraper](https://github.com/GeorgeDanicico/investments-scraper) | Builds the JVM image first (native images are never built on the VPS), then calls `deploy.sh`; preserves the log volume |
| [obsy](https://github.com/GeorgeDanicico/obsy) | Uses upstream Compose with a loopback port override, host metrics mounts and the Docker socket group |

## Automatic updates

[The production workflow](.github/workflows/deploy.yml) runs on pushes to this repository's `main`, every five minutes, manual dispatch, and `repository_dispatch` with type `upstream-changed`. The sync job runs on a GitHub-hosted runner. It fetches each submodule's configured `main` branch, commits changed gitlinks, and passes that exact parent commit to the production job. The production job runs on a Linux self-hosted runner on the VPS.

Submodule synchronization is active immediately. **To enable production deployment, set the repository Actions variable `DEPLOY_ENABLED` to `true` after configuring the VPS and runner.** Runner registration is managed separately; the runner registered only with expense-tracker does not automatically accept this repository's jobs.

The production job checks successful deployment fingerprints stored outside the Actions workspace. Only applications whose source revision, adapter, shared orchestration, or host `.sh` configuration changed are redeployed. Failed deployments are retried on the next run, even if their submodule updates have already been committed. Dependencies deploy first, a failed dependency blocks its consumers, and independent apps can still deploy successfully. An investments change also refreshes expense-tracker. Concurrent production runs are serialized.

Polling detects the latest branch head, so several commits within one interval may deploy together. GitHub's scheduler can delay runs, and public repository schedules can be disabled after 60 days without repository activity. These are [GitHub schedule semantics](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule). For immediate notification on every upstream push, optionally install [the notifier workflow](deploy/upstream-notify.yml.example) in each application repository and give it a `VPS_DISPATCH_TOKEN` secret with **Contents: write** access to this repository. Its ordinary `GITHUB_TOKEN` cannot dispatch into a different repository. Notification payloads never select arbitrary commits: the central job fetches the configured upstream branch heads itself.

Sync and deployment are part of the same workflow because [a push made with `GITHUB_TOKEN` does not trigger another push workflow](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow). The sync job needs permission to push to `main`; branch protection must allow this bot operation if you add protection rules.

## VPS configuration

The runner needs Git, Bash, Python 3.9+, curl, Docker daemon access, and Docker Compose 2.24.4+ (`!override` is used to replace ports and mount paths; see [Docker merge rules](https://docs.docker.com/reference/compose-file/merge/)). investments-scraper always uses its JVM image, because GraalVM native compilation needs about 3 GB of RAM. Production is gated by `DEPLOY_ENABLED`; validation of pull requests runs only on GitHub-hosted runners.

Repository Actions variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `DEPLOY_ENABLED` | unset | Set to `true` to start production jobs |
| `VPS_APPS_ROOT` | `/opt/vps-apps/apps` | Persistent application Git checkouts, outside the Actions workspace |
| `VPS_STATE_DIR` | `/var/lib/vps-apps` | Success records and deployment lock |
| `VPS_CONFIG_DIR` | `/etc/vps-apps` | Trusted, host-owned per-app shell configuration |

Create the application and state directories and make them writable by the runner account. Host configuration and credential files must be readable by the relevant runner/container user. To preserve existing checkout paths, set `VPS_APPS_ROOT=/home/r3k1Nu/projects`; directories must be independent Git repositories without uncommitted or divergent local changes. Ignored environment files are preserved. The orchestrator never runs `git clean` or `git reset --hard` on these checkouts.

Copy and edit the relevant [host configuration examples](config/examples) into `$VPS_CONFIG_DIR/<app>.sh`. These files are sourced as trusted Bash and their assignments are exported before the app's deployment command. All environment variables supported by the upstream deployment scripts can be set here. Keep production values and secrets on the VPS.

Required production files:

- **Expense tracker:** `/etc/expense-tracker/.env.production` with the app's existing production settings (`SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `PRICE_SERVICE_URL`, `SITE_URL`). `PRICE_SERVICE_URL` can point to `http://investment:8080` on the shared `expense-network`. The adapter creates that network when needed. Container name defaults to `expense-tracker-web`, matching its original action.
- **Obsy:** `/etc/obsy/apps.json`; start with [the example](config/examples/obsy-apps.json), adjusting container names to your configuration. Its health probes reach expense-tracker and investments through `expense-network`. The Docker socket's group is detected automatically.

Default endpoints: expense tracker `127.0.0.1:3000`, Obsy `127.0.0.1:3001`; investments preserves its upstream `8080:8080` binding. Keep the existing reverse proxy pointed at these endpoints. An existing Obsy Compose deployment must use its existing project name (`docker compose ls`); set `OBSY_PROJECT_NAME` accordingly to avoid creating duplicate stacks.

## Wiki checkout

The persistent wiki is an independent Git checkout with its own `.git` directory. Commit and push any edits made on the host before the next upstream update. Production sync refuses to discard uncommitted changes or divergent/unpublished commits and reports a failed deployment instead.

## Manual operation

```bash
git clone --recurse-submodules https://github.com/GeorgeDanicico/vps-apps.git
cd vps-apps

# Refresh and stage submodule pointers locally. Commit/push them when ready.
bash scripts/sync-submodules.sh

# Inspect the pending production deployments without changing the VPS.
python3 scripts/deploy.py --dry-run

# Deploy pending applications, or force a specific app and its consumers.
python3 scripts/deploy.py
python3 scripts/deploy.py --app expense-tracker --force
```

The same application selector and force option are available under **Actions → Sync applications and deploy production → Run workflow**. Selecting one application includes its dependencies and downstream consumers; unchanged prerequisites are skipped unless they need deployment. Editing a host `<app>.sh` triggers its redeployment on the next check. After changing only an external environment/config file, use `--force` or the manual workflow's force option.

State is written atomically to `$VPS_STATE_DIR/deployed.json` only after an adapter succeeds. The orchestrator retries failures but does not add universal rollback: expense-tracker keeps its upstream container rollback; other applications retain their upstream deployment behavior. Local history rewrites or divergent production commits need manual reconciliation before sync can proceed. Automated synchronization always follows upstream branch heads; it is not a rollback mechanism for pinning an older version.

## Verification

```bash
python3 -m unittest discover -s tests -v
find scripts deploy/adapters config/examples -name '*.sh' -print0 | xargs -0 -n1 bash -n
```

Tests exercise real temporary Git repositories and the actual sync/deploy orchestration: exact revisions, selective deployment, dependencies, failures and retries, adapter/config changes, dry runs, recreated checkouts, and preservation of local modifications and commits. Real production image builds and health checks run on the VPS; they are not part of these local tests.
