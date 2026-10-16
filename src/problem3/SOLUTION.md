# Problem 3 — Debugging issues within the system

> Note: the Notion page says "Reference README in Problem 4 repo", and the README in this folder is titled "Problem 4". I treated `src/problem3/` as the system to debug, since that's the only folder containing it.

## TL;DR

The system had **one hard outage** and **three ways to fail "sometimes"**. Each one alone matches "unreliable and sometimes inaccessible":

| # | Problem | Symptom | Severity |
|---|---------|---------|----------|
| 1 | nginx proxies to `api:3001`, the API listens on `3000` | **Every** `/api/*` request returns 502 | Outage |
| 2 | Unhandled `'error'` event on the pg Pool | API **process crashes** whenever Postgres restarts or drops an idle connection. With no restart policy it **stays down** | Intermittent → permanent |
| 3 | Connection leak: `db.release()` is skipped when a query throws, and there's no connect timeout | After 10 query errors (pool size), **every request hangs forever** | Intermittent → permanent |
| 4 | Redis is on the critical path with default ioredis retries | Redis down → every request hangs **~9.6 s** then 500, though Redis only stores a non-critical "last_call" marker | Degradation |
| 5 | No healthchecks; `depends_on` only waits for "started" | Startup races; traffic is routed before dependencies are ready | Reliability |
| 6 | nginx resolves `api` once at startup | API container recreated (new IP) → 502 until nginx restarts | Reliability |
| 7 | Smaller issues | Hardcoded DB password, no Postgres volume (data loss on recreate), image runs as root, `npm install` without a lockfile, 60 s default proxy timeouts, `/status` not reachable through nginx, obsolete `version:` key | Hygiene / latent |
| 8 | Traps in the repo | `postgres/init.sql` (`max_connections = 20`) and an **empty** `nginx/nginx.conf` are both **not mounted**. If someone "fixes" compose by mounting them, nginx won't start and Postgres gets capped at 20 connections | Latent |

## How I diagnosed it

Docker in my sandbox couldn't pull images, so I ran **the exact same code and config natively**: Postgres 16, Redis 7, Node 22 and nginx 1.24, with `api`/`postgres`/`redis` mapped to `127.0.0.1`. Then I injected the failures a production system actually sees.

**1. Traffic path first, outside-in.** `curl /` → 200 (nginx is up). `curl /api/users` → 502. Hitting the API directly on `:3000` → 200. So the problem sits between nginx and the API. The nginx error log says it plainly:

```
connect() failed (111: Connection refused) while connecting to upstream,
upstream: "http://127.0.0.1:3001/api/users"
```
`index.js` listens on 3000. **Issue 1.**

**2. With the port fixed, inject dependency failures.** "Sometimes" usually means "when a dependency blips".

| Test (original code) | Result |
|---|---|
| Stop Redis, call `/api/users` | `500 in 9.56s`. ioredis queues the command offline and retries 20 times before failing |
| Restart Postgres with idle clients in the pool | **API process exits**: `throw er; // Unhandled 'error' event ... error: terminating connection due to administrator command ... Emitted 'error' event on BoundPool`. Nothing listening on :3000 afterwards → nginx 502 |

**3. Code review of the request handler** found the leak. I proved it with a minimal script (`pool max = 3`, three failing queries, then one healthy query):

```
original pattern: next healthy request -> STILL WAITING (hung) after 5002ms | pool total=3 idle=0 waiting=1
fixed pattern   : next healthy request -> OK after 7ms              | pool total=1 idle=1 waiting=0
```
In production, any transient query error (failover, `statement_timeout`, network reset) permanently consumes one of the 10 pooled clients. `pg` has no default `connectionTimeoutMillis`, so once all 10 are leaked, requests wait forever. nginx turns them into 504s after 60 s.

**4. Compose and config review** found the rest: no `restart:`, no healthchecks, no volume, the unmounted files, and the hardcoded secret.

## Fixes applied

| File | Change | Fixes |
|---|---|---|
| `nginx/conf.d/default.conf` | Upstream port `3000` | #1 |
| | `resolver 127.0.0.11` + variable `proxy_pass` → DNS re-resolved every 10 s | #6 |
| | 2 s connect / 10 s read timeouts, single retry for idempotent requests on 502/503/connection error | Fast failure, rides over API restarts |
| | Forwarded headers, `X-Request-ID`, access log with `$request_time`/`$upstream_response_time`/`$upstream_status` | Observability |
| | `/healthz` for nginx's own healthcheck | #5 |
| `api/src/index.js` | `pool.on('error', …)` | #2 |
| | `pool.query()` instead of manual `connect`/`release` (always releases), plus `connectionTimeoutMillis: 2000`, `statement_timeout`/`query_timeout: 5000` | #3 |
| | Redis write is fire-and-forget with `.catch`; `enableOfflineQueue: false`, `commandTimeout: 500`, `maxRetriesPerRequest: 1`, deduplicated error logging | #4 |
| | DB errors return **503** (retryable) without leaking internal error text | Correct semantics |
| | `/status` (liveness) and `/ready` (Postgres required, Redis reported as degraded) | #5 |
| | Graceful SIGTERM: stop accepting, drain, close pools, 10 s hard timeout; JSON logs | Clean deploys |
| `docker-compose.yml` | `restart: unless-stopped` everywhere | #2 recovery |
| | Healthchecks for all four services; `depends_on: condition: service_healthy` | #5 |
| | `pgdata` volume; `max_connections` set explicitly via `command:`; password from `.env` (`${POSTGRES_PASSWORD:?}`) | #7 |
| | `init: true`, `stop_grace_period`, memory limit, Redis `maxmemory` + LRU, removed `version:` | Hygiene |
| `api/Dockerfile` | `package-lock.json` + `npm ci --omit=dev`, `NODE_ENV=production`, `USER node`, `.dockerignore` | #7 |
| removed | `postgres/init.sql`, empty `nginx/nginx.conf` | #8 |

### Verification (same harness, fixed code)

| Scenario | Before | After |
|---|---|---|
| `GET /api/users` | 502 | **200** in 17 ms |
| Redis down | 500 after 9.6 s | **200 in 5 ms**; `/ready` reports `redis: degraded` |
| Postgres restart | API process dies, stays down | API alive, next request **200** |
| Postgres fully down | n/a (already dead) | **503 in 4 ms**; `/ready` = 503; recovers automatically |
| 3 failing queries, pool of 3 | next request hangs forever | next request OK in 7 ms |
| Load: 2,000 requests, 50 concurrent | n/a | **100% 200**, p50 62 ms, p99 129 ms (small shared sandbox, no tuning); DB connections capped at pool size |
| `SIGTERM` | Node as PID 1 ignores it → killed after 10 s | drained and exited in 12 ms |

To run it:
```bash
cd src/problem3
cp .env.example .env   # set POSTGRES_PASSWORD (a local-only default is already provided)
docker compose up --build
curl localhost:8080/api/users
```

## Monitoring and alerts I would add

**Golden signals at the edge** (nginx log already has the fields):

| Alert | Condition | Why |
|---|---|---|
| API 5xx ratio | `5xx / total > 2%` for 5 min (page at 5%) | Catches #1, #2, #3 instantly |
| Upstream latency | p99 `$upstream_response_time` > 500 ms for 10 min | Catches the Redis stall (#4) and pool starvation (#3) before they turn into errors |
| 502/504 count | any sustained 502 or 504 | 502 = API down/unreachable, 504 = API hung. Different runbooks |
| Synthetic probe | external check of `/api/users` every 30 s from outside the host | Detects "nginx up, app broken" |

**Service level:**
- **Container restarts**: `restart_count` increase > 3 in 10 min. A restart policy hides crashes, so restarts must alert.
- **Health status**: any container `unhealthy` for > 1 min.
- **pg pool saturation**: export `totalCount`/`idleCount`/`waitingCount`. Alert on `waitingCount > 0` for 1 min or `idle == 0` at max. This is the direct signal for leak #3.
- **Postgres**: `numbackends / max_connections > 80%`, replication lag, long-running queries.
- **Redis**: `up == 0`, memory > 80% of `maxmemory`, evictions. Warning-level only, because Redis is now non-critical.
- **Log-based**: rate of `"level":"error"` lines; any `Unhandled 'error' event` / process exit message.

**Stack:** Prometheus (nginx-prometheus-exporter or log-derived metrics via Vector/Promtail, postgres_exporter, redis_exporter, cAdvisor, `prom-client` in the API) + Grafana + Alertmanager → Slack/PagerDuty. On AWS, CloudWatch + Container Insights covers the same ground.

## How I would prevent this in production

1. **Catch config drift in CI.** Add a smoke test in the pipeline: `docker compose up --wait` then `curl --fail localhost:8080/api/users`. Issue #1 would never have merged. Also add `nginx -t`, `docker compose config`, hadolint and eslint.
2. **Chaos and failure tests before release.** Restart Postgres, kill Redis, and recreate the API container while a load test runs. Assert no crash, bounded latency, automatic recovery. These are the exact tests that exposed #2, #3, #4 and #6.
3. **Resilience defaults as a library/template.** Every service gets connection and query timeouts, pool `error` handlers, retry with backoff, graceful shutdown, and liveness/readiness endpoints. Code review checklist: "what happens when each dependency is slow or down?"
4. **Classify dependencies as critical vs optional** and design degraded modes (Redis here). Optional dependencies must never block the request path.
5. **Run on an orchestrator, not a single compose host**, for anything real: ECS/EKS with ≥2 API replicas behind an ALB, liveness/readiness probes, rolling deploys, managed Postgres (RDS Multi-AZ) and ElastiCache with RDS Proxy/pgBouncer in front of the DB. Size `pool max × replicas` against `max_connections` explicitly.
6. **Secrets from a secrets manager** (AWS Secrets Manager / SSM), never in compose or the image. Images pinned by digest, built once, scanned (Trivy), run as non-root.
7. **SLOs + error budgets** (e.g., 99.9% of `/api/*` succeed in < 300 ms), with the alerts above derived from them.
8. **Blameless postmortem**, with each root cause turned into a regression test.
