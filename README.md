# Docker Observability Go

A hands-on reference project for running a small Go HTTP service behind Nginx,
with a fully isolated Docker network topology and a complete observability
stack: **Prometheus** (metrics), **Loki + Fluent Bit** (logs), and **Grafana**
(dashboards).

It demonstrates, end to end:

- Multi-network Docker isolation (public, backend, monitoring)
- A Go service (`go-chi` router) with structured JSON logging and Prometheus
  metrics, split into clean, single-responsibility packages
- Log shipping from the app/Nginx into Loki via Fluent Bit
- Metrics scraping from Prometheus and visualization in Grafana
- A single `go.mod`/`go.sum` module living in [app/](/app), built via a
  multi-stage Docker image

## Table of Contents

- [Project Layout](#project-layout)
- [Docker Network Architecture](#docker-network-architecture)
- [What Fluent Bit and Loki Do](#what-fluent-bit-and-loki-do)
- [Getting Started](#getting-started)
- [Using the Makefile](#using-the-makefile)
- [Testing the Complete Flow](#testing-the-complete-flow)
- [End-to-End Example: Request to Logs and Metrics](#end-to-end-example-request-to-logs-and-metrics)
- [API Endpoints](#api-endpoints)
- [Configuration](#configuration)
- [Service Management](#service-management)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)

## Project Layout

```
docker-observability-go/
├── app/                      # Go HTTP service (single Go module)
│   ├── main.go               # Thin entrypoint: wires everything together
│   ├── go.mod / go.sum       # The ONLY go.mod/go.sum in the repo
│   ├── Dockerfile            # Multi-stage build -> Alpine runtime image
│   └── internal/
│       ├── logger/           # Structured JSON logging (stdout + file)
│       ├── metrics/          # Prometheus collectors
│       ├── httpmiddleware/   # Request logging + metrics middleware
│       ├── handlers/         # HTTP handlers (/, /health, /api, ...)
│       └── router/           # chi router wiring
├── nginx/                    # Reverse proxy (Dockerfile + nginx.conf)
├── prometheus/                # Prometheus scrape config
├── loki/                     # Loki storage config
├── fluent-bit/                # Log shipping config (app + nginx -> Loki)
├── grafana/                   # Datasource/dashboard provisioning
├── scripts/                   # Test/helper scripts (bash + PowerShell)
├── compose.yaml               # All services, networks, and volumes
├── Makefile                   # Convenience commands (see below)
└── CHANGELOG.md
```

### Why the Go code is split into packages

`app/main.go` used to be one large file containing logging, metrics,
middleware, handlers, and server setup. It's now a ~50-line entrypoint; each
concern lives in its own package under `internal/`, which keeps every file
short and focused:

| Package | Responsibility |
|---|---|
| [internal/logger](/app/internal/logger/logger.go) | `Logger` type: writes structured JSON log entries to stdout and a daily-rotated file under `/var/log/app` |
| [internal/metrics](/app/internal/metrics/metrics.go) | `Metrics` type: defines and registers the Prometheus counters/histograms |
| [internal/httpmiddleware](/app/internal/httpmiddleware/logging.go) | Request-ID generation, response wrapper, and the logging/metrics middleware |
| [internal/handlers](/app/internal/handlers/handlers.go) | The `/`, `/health`, `/api`, `/frontend`, `/backend` HTTP handlers |
| [internal/router](/app/internal/router/router.go) | Builds the `chi` router and mounts routes, middleware, and `/metrics` |
| [main.go](/app/main.go) | Initializes the logger/metrics, builds the router, starts the HTTP server |

### Single Go module

Previously there was a `go.mod`/`go.sum` pair both at the repo root **and**
inside `app/`, which was confusing and unused at the root (nothing outside
`app/` is a Go file). The root copies have been removed — `app/go.mod` and
`app/go.sum` are now the single source of truth, matching the Dockerfile's
build context (`./app`).

## Docker Network Architecture

Three isolated bridge networks enforce a clear trust boundary between the
public edge, the application tier, and the observability stack:

| Network | Subnet | Members | Purpose |
|---|---|---|---|
| `frontend` | 10.0.1.0/24 | `nginx`, `app` | Request path between the host-published Nginx proxy and the Go app |
| `backend` | 10.0.2.0/24 | `app`, `postgres` | Database isolation; Postgres is never reachable from Nginx |
| `monitoring` | 10.0.3.0/24 | `app`, `prometheus`, `loki`, `grafana`, `fluent-bit` | Observability traffic (metrics scraping, log shipping, dashboards) |

The `app` service straddles all three networks (frontend, backend,
monitoring) because it needs to talk to the database, expose metrics to
Prometheus, and receive proxied requests from Nginx. The app also publishes
host port `8080` for direct local testing; normal browser/API traffic in the
example below enters through Nginx on host port `9080`.

### Traffic flow

```
Host Machine
  │
  ├─ HTTP request :9080 ──▶ Nginx (frontend)
  │                            │ proxy_pass http://app
  │                            ▼
  │                         Go App :8080 ─────▶ Postgres :5432 (backend)
  │                            │
  │                            ├─ response + X-Request-ID ──▶ Nginx ──▶ caller
  │                            ├─ JSON request log ──▶ app-logs volume ──┐
  │                            └─ /metrics ◀──── Prometheus scrapes app:8080
  │                                                                     │
  │              Nginx access/error logs ──▶ nginx-logs volume ──┐     │
  │                                                              ▼     ▼
  ├─ :3100 ───────────────▶ Loki ◀──── Fluent Bit tails both log volumes
  │
  ├─ :9090 ───────────────▶ Prometheus (stores scraped metrics)
  │
  └─ :3000 ───────────────▶ Grafana (queries Prometheus and Loki)
```

The HTTP request does **not** pass through Fluent Bit, Loki, Prometheus, or
Grafana. Those services receive telemetry on separate paths while the request
is being handled or after it completes.

### What Fluent Bit and Loki do

- **Fluent Bit is the log collector and forwarder.** It tails the read-only
  `app-logs` and `nginx-logs` named volumes. It parses the Go application's
  JSON log lines with the `json` parser and Nginx access lines with the
  `nginx` parser, adds service/host labels, and sends batches to Loki's
  `/loki/api/v1/push` endpoint on the Docker monitoring network.
- **Loki stores and indexes logs by labels.** It receives those batches from
  Fluent Bit and makes them searchable with LogQL. In this configuration,
  application entries use `service="go-app"` and Nginx entries use
  `service="nginx"`. The log body remains available as a line; Go's JSON
  fields (including `request_id`) can be extracted at query time with
  `| json`.
- **Grafana is the user interface.** Its provisioned Loki datasource points
  to `http://loki:3100`, which is the Docker service name and port, not the
  host URL. The provisioned Prometheus datasource similarly points to
  `http://prometheus:9090`.

This is file-based collection, not Docker stdout collection: Fluent Bit tails
the files in the named volumes. The app writes each request as JSON to
`/var/log/app/app-YYYY-MM-DD.log`; Nginx writes access/error logs under
`/var/log/nginx`. Compose mounts the same volumes into Fluent Bit as read-only.
Fluent Bit checks for new input periodically and flushes records to Loki, so
allow a few seconds after a request before querying for it.

### Docker DNS resolution

Every container gets automatic service discovery via Docker's embedded DNS
server (`127.0.0.11:53`). A name like `app` or `postgres` only resolves for
containers that share a network with that service — this is what makes the
isolation real rather than cosmetic:

```bash
# From nginx (on frontend network) -> resolves app's frontend-network IP
docker exec docker-observability-nginx nslookup app

# From postgres (on backend network only) -> cannot resolve nginx at all
docker exec docker-observability-db nslookup nginx   # fails: not on same network
```

### Isolation benefits

1. **Security** — Postgres is never reachable from Nginx or the public network.
2. **Least privilege** — each service only joins the network(s) it needs.
3. **Debuggability** — `docker network inspect <network>` shows exactly who can talk to whom.
4. **Separation of concerns** — observability traffic (scraping/shipping) is isolated from user-facing traffic.

## Getting Started

### Prerequisites

- Docker & Docker Compose v2+
- `make` (optional — every target has a `docker compose` equivalent)
- `curl` / `jq` for manual testing

### Setup

```bash
# 1. Clone and enter the repo
cd docker-observability-go

# 2. Create your .env (optional — sensible defaults are baked in)
cp .env.example .env

# 3. Build images
make build

# 4. Start the stack
make up

# 5. Confirm everything is healthy
make health
docker compose ps
```

All containers should report `(healthy)`. If `nginx` or `app` haven't
finished their startup grace period yet, re-run `make health` a few seconds
later.

## Using the Makefile

Run `make help` at any time to see this list from the Makefile itself.

| Command | What it does |
|---|---|
| `make build` | Build all Docker images |
| `make up` | Start the full stack in the background, then run a health check |
| `make down` | Stop all services (keeps volumes) |
| `make restart` | Restart all services |
| `make clean` | Stop services **and remove volumes** (full reset — logs/DB data are lost) |
| `make ps` | Show running containers |
| `make logs` / `logs-app` / `logs-nginx` / `logs-db` / `logs-fluent-bit` | Tail logs for all services or one in particular |
| `make volume-stats` | Show size/line-count statistics for the persistent log volume |
| `make shell-app` / `shell-db` | Open an interactive shell inside the app or database container |
| `make health` | Curl the Nginx and app `/health` endpoints |
| `make test` | Run `test-endpoints` |
| `make test-endpoints` | Curl every public endpoint through Nginx |
| `make test-persistent-logs` | Verify JSON logs persist across container recreation |
| `make test-observability` | Exercise the whole Prometheus/Loki/Grafana/Fluent Bit pipeline |
| `make metrics` | Curl the app's `/metrics` endpoint directly |
| `make logs-loki` | Query Loki for recent `go-app` log lines |
| `make dashboard-urls` | Print every dashboard/service URL and credentials |

On Windows, the `test-*`/`volume-stats` targets automatically
dispatch to the PowerShell scripts in [scripts/](/scripts) instead of their
bash equivalents.

## Testing the Complete Flow

This walks through the whole request → metrics → logs → dashboard pipeline,
so you can confirm the stack is wired correctly end to end.

### 1. Start the stack and check health

```bash
make up
make health
```

### 2. Exercise the public API through Nginx

```bash
curl -s http://localhost:9080/            # root banner
curl -s http://localhost:9080/health | jq
curl -s http://localhost:9080/api | jq
curl -s http://localhost:9080/frontend | jq
curl -s http://localhost:9080/backend | jq
```

Responses from these application endpoints carry an `X-Request-ID` header —
note the value, you'll use it to trace the request through the logs in step 4.
The Prometheus `/metrics` handler is a separate endpoint and does not return
this header.

```bash
curl -s -i http://localhost:9080/api | grep -i x-request-id
```

### 3. Confirm Prometheus is scraping the app

```bash
make metrics   # direct: curl http://localhost:8080/metrics

# Confirm the "app" scrape target is UP:
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {labels, health}'
```

You should see `{"labels": {"instance": "app:8080", "job": "app"}, "health": "up"}`.

### 4. Confirm logs reach Loki (and correlate by request ID)

```bash
# Ship a few requests, then query Loki for them
curl -s http://localhost:9080/api > /dev/null
make logs-loki
```

Or query directly and grep for the request ID captured in step 2:

```bash
curl -s 'http://localhost:3100/loki/api/v1/query_range?query=%7Bservice%3D%22go-app%22%7D&limit=20' | jq
```

Each log line is the same structured JSON the app writes to
`/var/log/app/app-YYYY-MM-DD.log`, so the `request_id` you saw in the
response header will show up in the corresponding log entry.

### 5. Check the dashboards

```bash
make dashboard-urls
```

Open Grafana at <http://localhost:3000> (`admin` / `admin` by default) and
confirm the Prometheus and Loki datasources are provisioned, then open the
HTTP Metrics / Logs / Request Tracing dashboards.

### 6. One-shot automated check

```bash
make test-observability
```

Runs all of the above checks (containers, metrics, Prometheus, Loki,
Grafana, request-ID correlation, Fluent Bit) in one script and prints a
pass/fail summary plus every dashboard URL.

## End-to-End Example: Request to Logs and Metrics

This example follows one `GET /api` request from your machine, through the
Docker networks, and into both log and metric backends.

### 1. Start the containers

From the repository root:

```bash
docker compose up --build -d
docker compose ps
```

Wait until the app and Nginx health checks pass. Confirm the public route:

```bash
curl -i http://localhost:9080/health
```

The host port mapping `9080:80` sends this connection to Nginx's port 80.
Nginx and the app share the `frontend` network, so Nginx resolves the app by
the Compose DNS name `app` and forwards the request to `app:8080`. The app
also joins `backend` and `monitoring`, but Nginx does not join either network.

### 2. Make one request and capture its request ID

```bash
curl -i http://localhost:9080/api
```

The response includes a header similar to:

```text
HTTP/1.1 200 OK
X-Request-ID: 1729960000000000000-1
Content-Type: application/json
```

The response body is similar to:

```json
{"message":"API endpoint is working","request_id":"1729960000000000000-1","service":"backend-api"}
```

The exact ID and JSON key order will vary. Go's HTTP middleware generates the
ID, records the completed request, adds it to the response, and updates the
Prometheus request metrics. The Nginx proxy returns that response to the
caller. Save the actual `X-Request-ID` value from your response for the Loki
query below.

### 3. Follow the log pipeline

After a few seconds, Fluent Bit will have tailed the new records from the
shared volumes and pushed them to Loki. The Go application log is a JSON line
containing the request ID, HTTP method, path, status, and duration. Nginx
also writes its own access log line for the proxied request; its default
access format does not include the Go-generated request ID.

In Grafana, open <http://localhost:3000>, sign in with `admin` and the
configured `GRAFANA_PASSWORD` (default: `admin`), open **Explore**, choose the
**Loki** datasource, and run this LogQL query. Replace the placeholder with
the ID from step 2:

```logql
{service="go-app"} | json | request_id="1729960000000000000-1"
```

To see recent application and Nginx logs without filtering by request ID, run
each query separately:

```logql
{service="go-app"} | json
{service="nginx"}
```

The same data can be queried from Loki's HTTP API, which is published on host
port `3100`. For example, this returns recent Go application log entries:

```bash
curl -G --data-urlencode 'query={service="go-app"} | json' \
  --data-urlencode 'limit=20' \
  http://localhost:3100/loki/api/v1/query_range
```

To confirm collection if a query returns no records, inspect Fluent Bit and
Loki:

```bash
docker compose logs --tail=50 fluent-bit
curl -s http://localhost:3100/ready
```

### 4. Follow the metrics pipeline

Prometheus independently scrapes the app's `/metrics` endpoint every 15
seconds over the `monitoring` network. Check the target at
<http://localhost:9090/targets>; the `app` target should be **UP**. After
making the request and waiting for a scrape, run this PromQL query in
Prometheus or Grafana's **Prometheus** datasource:

```promql
http_requests_total{method="GET", path="/api"}
```

To group the number of `/api` requests by HTTP status:

```promql
sum by (status) (http_requests_total{path="/api"})
```

These metrics are not sent by Fluent Bit and do not go through Loki.
Prometheus scrapes them directly from the Go app; Grafana can query both
Prometheus metrics and Loki logs from its two provisioned datasources.

### 5. Understand which ports are for what

| Host URL | Purpose |
|---|---|
| <http://localhost:9080> | Normal HTTP requests through Nginx to the Go app |
| <http://localhost:8080/metrics> | Direct host-published app port; useful for inspecting metrics |
| <http://localhost:9090> | Prometheus UI and scrape target status |
| <http://localhost:3100> | Loki API (logs are normally explored through Grafana) |
| <http://localhost:3000> | Grafana UI for dashboards, LogQL, and PromQL |

Port `8080` is published for local testing, but it is not needed for the
request path through `localhost:9080`. Inside Docker, services communicate
using Compose DNS names and container ports, not the host-published ports.

## API Endpoints

| Endpoint | Description |
|---|---|
| `GET /` | Plain-text service banner |
| `GET /health` | Liveness/health info (JSON) |
| `GET /api` | Example backend API response |
| `GET /frontend` | Bridge endpoint proving frontend-network connectivity |
| `GET /backend` | Bridge endpoint proving backend-network connectivity |
| `GET /metrics` | Prometheus metrics (not proxied by Nginx — see below) |

All routes are reachable through Nginx on `http://localhost:9080`, except
`/metrics`, which is intentionally **not** proxied by Nginx. It is reachable
directly on `http://localhost:8080/metrics` (the app's own published port)
or internally by Prometheus over the `monitoring` network.

## Configuration

Environment variables (see [.env.example](/.env.example)), all with safe
defaults if `.env` is omitted:

```env
# Database
DB_USER=observability
DB_PASSWORD=observability_pass
DB_NAME=observability_db

# Logging
LOG_LEVEL=info

# Grafana
GRAFANA_PASSWORD=admin

# Service ports
APP_PORT=8080
NGINX_PORT=80
DB_PORT=5432

# Prometheus
PROMETHEUS_RETENTION=15d

ENVIRONMENT=development
```

- Edit `nginx/nginx.conf` for routing/proxy changes.
- Edit `prometheus/prometheus.yml` to add/remove scrape targets.
- Edit `fluent-bit/fluent-bit.conf` to change log parsing/shipping rules.

## Service Management

```bash
make logs               # all services
make logs-app           # app only
make ps                 # running containers
make restart            # restart everything
make down               # stop (keep volumes)
make clean              # stop AND wipe volumes (logs, DB data, dashboards)
```

## Troubleshooting

**Services won't start**
```bash
docker compose logs
docker compose build --no-cache
docker compose down -v && docker compose up -d
```

**Can't reach a service**
```bash
docker compose ps
docker network ls
docker network inspect docker-observability-go_frontend
docker exec docker-observability-nginx wget -O- http://app:8080/health
```

**Database connection issues**
```bash
docker compose logs postgres
docker exec docker-observability-db pg_isready
```

**Port already in use** — override it in `.env` (e.g. `APP_PORT=8081`) or
edit the corresponding `ports:` mapping in `compose.yaml`.

## Security Considerations

1. Change `DB_PASSWORD` and `GRAFANA_PASSWORD` before using this outside a local/dev environment.
2. There is no TLS — add SSL/TLS termination in Nginx for anything beyond local use.
3. Postgres and the observability stack are intentionally kept off the `frontend` network; don't add new services to it unless they truly need to be public.
4. Use Docker secrets or an external secrets manager instead of plain environment variables in production.

## License

MIT License. See [CHANGELOG.md](/CHANGELOG.md) for release history.
