# 🦀 `Rust API` ⚓ · ☸️ Kubernetes-ready

API written in Rust with Axum, PostgreSQL, Redis, and Kubernetes support.

A ready-to-use template for building RESTful APIs in Rust, with project structure, local development, Docker, Kubernetes, observability, database migrations, and testing already set up.

This project is a template for building a **RESTful API** in Rust without the boilerplate of setting up the project structure and the support for kubernetes.

# 📚 Content
1. [Project Structure](#-project-structure)
2. [Health Checks](#-health-checks)
3. [Configuration and Environment Variables](#-configuration-and-environment-variables)
4. [Justfile Commands](#-justfile-commands)
5. [Postgres Persistence in the Cluster](#-postgres-persistence-in-the-cluster)
6. [Workflow](#-workflow)
7. [Using as a Template](#-using-as-a-template)
8. [Drizzle Gateway](#-drizzle-gateway-httplocalhost4983)
9. [ER Diagram](#-er-diagram-httplocalhost8081)
10. [Metrics and Prometheus](#-metrics-and-prometheus)
11. [Sample Data (Zoo)](#-sample-data-zoo)
12. [Tests with Postgres](#-tests-with-postgres)

## 🏗️ Project Structure
```
.
├── docker
│   └── erd
├── kubernetes
│   ├── base
│   ├── dev
│   └── observability
├── migrations
├── sql
└── src
    ├── monitor
    └── routes
```

## 💓 Health Checks
- `live`: checks that the API is alive.
- `startup`: checks that the API has started successfully.
- `ready`: checks the Postgres and Redis connections.

> [!WARNING]
> `/health/ready` returns `503` if Postgres is unavailable, or `200 (redis degraded)` if Redis is unavailable.

## ⚙️ Configuration and Environment Variables
The project has a `.env.example` present, so you can copy it to `.env` and set the values for your environment.

```bash
cp .env.example .env
```

| Key | Description | Context |
|-----|-------------|---------|
| `POSTGRES_USER`* | Postgres User | Postgres & Drizzle Gateway |
| `POSTGRES_PASSWORD`* | Postgres Password | Postgres & Drizzle Gateway |
| `POSTGRES_DB`* | Postgres Database | Postgres & Drizzle Gateway |
| `MASTERPASS`* | Master Password | Drizzle Gateway |
| `DATABASE_URL` | Database Connection | Postgres & Drizzle Gateway |
| `REDIS_URL` | Redis connection | Redis |
| `BIND_ADDR` | API bind address | API |
| `METRICS_ADDR` | Metrics bind address | API (metrics) |
| `RUST_LOG` | Rust log level | API |

> [!NOTE]
> **\***: Required to start up the app

## 🤖 Justfile commands
This project requires the [`just`](https://github.com/casey/just) and `nu` shell to run the commands.

### 🛠️ Local Commands
| Command | Description |
|---------|-------------|
| `up` | Starts the API and the dependencies (Postgres and Redis) in a local environment with `docker compose`. |
| `down` | Stops the API and the dependencies (Postgres and Redis) in a local environment with `docker compose`. |
| `stop` | Stops the containers without deleting data |
| `doctor` | Checks if the required tools are installed. |
| `run` | Runs the API in local with `cargo pretty run`. Without the `metrics` feature (run `cargo run --features metrics` manually if you want to test it). |
| `test` | Runs the tests. The ones that use Postgres need `just up` and run in temporary databases: they don't touch your database. |
| `build-docker` | Builds the `api:dev` image (always with the `metrics` feature, see `Dockerfile`). |

### ☸️ Kubernetes Commands.
| Command | Description |
|---------|-------------|
| `k8s-cluster` | Creates the kind cluster (1 control-plane + 3 workers). |
| `k8s-up` | Starts up from zero (the cluster MUST do not exist before). |
| `k8s-start` | Resumes a paused cluster, or after restarting Docker or the PC, and waits for the nodes to be Ready. |
| `k8s-stop` | Pauses the cluster (stops the nodes) without deleting anything, to free RAM. |
| `k8s-image` | Builds the image and loads it into the kind nodes. |
| `k8s-redeploy` | Rebuilds the image and restarts the API (development cycle). |
| `k8s-restart` | Restarts the API without rebuilding the image (for example, after changing the secrets with `k8s-secrets`). |
| `k8s-ship` | `k8s-redeploy` + `health`: updates the API and tests it. |
| `k8s-secrets` | Creates or updates the cluster secrets from `.env` (Postgres passwords and `DATABASE_URL`/`REDIS_URL` for the API). |
| `k8s-apply` | Applies everything (base + dev) with Kustomize. |
| `k8s-scale <name> <n>` | Changes the replicas of a Deployment, e.g. `just k8s-scale redis 0`. |
| `k8s-render` | Shows the final YAML that Kustomize generates, without applying anything. |
| `k8s-check` | Validates against the server what would be applied, without changing anything (the namespace must exist). |
| `k8s-metrics` | Installs metrics-server (needed for HPA; not to be confused with the Prometheus metrics of the API). |
| `k8s-namespace` | Creates the `app` namespace and sets it as default. |
| `k8s-clean` ⚠ | Deletes the namespace, leaves the cluster. Postgres data is preserved. |
| `k8s-destroy` ⚠ | Deletes the entire cluster. Postgres data is preserved. |
| `k8s-wipe-data` ⚠ | Deletes the Postgres data. It's the only command that does it. |

### 🔍 Inspection / Debugging Commands
| Command | Description |
|---------|-------------|
| `k8s-status` | Overview of the namespace. |
| `k8s-nodes [app]` | Which node each pod is on (default the API). |
| `k8s-logs [app]` | Live logs of all pods of an app (default the API). |
| `k8s-top` | CPU and memory per pod. |
| `k8s-hpa` | Live HPA. |
| `k9` | Opens k9s in the namespace. |

### 🔭 Observability Commands
| Command | Description |
|---------|-------------|
| `obs-up` | Installs / Updates the `kube-prometheus-stack` via Helm. |
| `obs-down` | Removes Prometheus & Grafana (the data get lost) |
| `obs-grafana` | Tunnel to Grafana. |
| `obs-prometheus` | Tunnel to Prometheus. |
| `obs-status` | Pods of the observability stack. |
| `obs-podmonitor` | Registers the API in Prometheus (`PodMonitor`). Needs `obs-up` and `k8s-apply` done before. |
| `api-metrics` | Tunnel to the raw `/metrics` of an API pod. |

### 🗄️ Data Commands
| Command | Description |
|---------|-------------|
| `db-new <name>` | Creates an empty migration in `migrations/`. Applied by the API on startup. |
| `db-ui` | Starts only Drizzle Gateway, no local Postgres/Redis. Pair with `k8s-pg` to see the cluster. |
| `erd` | Regenerates the ER diagram from `migrations/`, served at `http://localhost:8081`. |
| `db-seed` | Loads `sql/seed.sql`. Schema has to exist already (`just run`). Can't run twice. |
| `db-dump` | Dumps the local compose Postgres to `.data/dump.sql`. |
| `db-restore` ⚠ | Loads `.data/dump.sql` into the cluster Postgres, replaces its tables. Repeatable. |

### 🚇 Tunnel Commands
| Command | Description |
|---------|-------------|
| `k8s-pg` | Cluster Postgres on `localhost:5433`. |
| `k8s-redis` | Cluster Redis on `localhost:6380`. |

### 🧪 Testing Commands
| Command | Description |
|---------|-------------|
| `health` | Hits `/health/ready` through the NodePort, `127.0.0.1:8080`. |
| `load-soft` | `oha`, 300 req/s for 1 minute. |
| `load-hard` | Saturates the CPU, HPA scales to max. |

## 💾 Postgres Persistence in the Cluster
Data lives at `/var/lib/kind-<project>-pg`, inside the Docker VM, mounted on the worker labeled `data=pg` (`kubernetes/kind.config.yaml`). Survives `k8s-clean`, `k8s-destroy`, and recreating the cluster. Only `k8s-wipe-data` touches it.

Cluster from before this setup won't have the mount, the label or the names. Delete it (`kind delete cluster --name axum`) and run `k8s-up` once.

## 🔄 Workflow
Local: API runs with `cargo` against compose. Cluster: API runs in kind.

```bash
cp .env.example .env
just doctor
just up
just k8s-up
```

| Situation | Command |
|-----------|---------|
| Writing the API | `just up` once, then `just run`. |
| Updated the API, want it in the cluster | `just ship`. |
| Same, no test | `just k8s-redeploy`. |
| Changed a manifest | `just k8s-apply`. |
| Preview before applying | `k8s-render` (YAML) or `k8s-check` (dry-run). |
| New table or schema change | `db-new <name>`, write the SQL, restart the API. |
| Move local data to the cluster | `db-dump` then `db-restore`. |
| Something's broken | `status`, `logs [app]`, `k9`. |
| Check the HPA scales | `k8s-hpa` in one terminal, `load-hard` in another. |
| Check Redis is optional | `k8s-scale redis 0`, `health` → 200 degraded. |
| Check Postgres is required | `k8s-scale postgres 0`, `health` → 503. |
| Done for the day | `stop` + `k8s-stop`. |
| Back the next day | `up` + `k8s-start`. |
| Nuke everything | `down` (local data gone) + `k8s-destroy` (cluster data stays). |

## 📋 Using as a Template
1. Rename `name` in `Cargo.toml`, run `cargo check`. Justfile, cluster, compose and data folder follow it.
2. Delete `sql/seed.sql` and the initial schema migration, write your own with `db-new`. ER diagram needs at least one migration.
3. Change the passwords in `.env`, delete `src/routes/example.rs` once you have real routes.
4. Not using Prometheus? Drop `metrics` from `Cargo.toml`, `Dockerfile`, the `metrics` port in `kubernetes/base/deployment.yaml`, delete `kubernetes/observability/`. Leaving it in costs nothing, it's opt-in.

Host port `8080` is fixed (`kubernetes/kind.config.yaml`, justfile `url`). Two clusters from different projects can't run at once.

## 🌳 Drizzle Gateway (`http://localhost:4983`)
Two connections: `local` (compose Postgres) and `cluster` (needs `k8s-pg` running or it won't answer). Tunnel uses `5433` instead of `5432` so both can be up together.

Gateway reads `DATABASE_URL_*` only when it creates its volume. Had the volume from before? `cluster` won't show up. Add it by hand from the UI (`postgresql://<user>:<password>@host.docker.internal:5433/<db>`), or recreate the volume (only holds Gateway config, no Postgres data):

```bash
docker compose -p <project> -f docker/compose.yaml rm -sf postgres-ui
docker volume rm <project>_drizzle-data
just up
```

## 📊 ER Diagram (`http://localhost:8081`)
[Liam ERD](https://liambx.com) reads `migrations/` in order, `erd` compose service serves it (starts with `just up`). Run `just erd` after changing a migration.

## 📈 Metrics and Prometheus
`metrics` Cargo feature, off by default. `build-docker` always compiles it; locally you ask for it: `cargo run --features metrics`.

With it on, `main.rs` opens a second HTTP server on `METRICS_ADDR` (`127.0.0.1:9090` local, `0.0.0.0:9090` in the cluster via configmap), one route:

- `GET /metrics`: `http_requests_total`, `http_request_duration_seconds`, `http_requests_in_flight` from the `routes::metrics::track` middleware, plus `db_pool_connections`/`db_pool_max_connections` from the sqlx pool. `redis_up` and `redis_heartbeat_failures_total` are declared but not wired to `src/monitor/redis.rs` yet.

```bash
just k8s-up          # or k8s-apply if the cluster exists
just obs-up
just obs-podmonitor
just obs-grafana      # http://127.0.0.1:3000, admin/admin
```

## 🦁 Sample Data (Zoo)
Schema comes from the API on startup. Data doesn't, you seed it yourself.

```bash
just up
just run        # Ctrl+C once it's up
just db-seed
```

Seed can't run twice (`duplicate key`, no partial state). Start over: `down`, `up`, `run`, `db-seed`.

## 🧫 Tests with Postgres
`#[sqlx::test]` spins up a temp database per test, runs `migrations/`, drops it (see `src/routes/health.rs`). `just test` points at compose's `postgres` database, yours stays clean.
