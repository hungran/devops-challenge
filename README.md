# 99Tech DevOps Challenge — Solutions

Each problem has its own `SOLUTION.md`. Diagrams are Mermaid, so they render directly on GitHub; no files to download or unzip.

| # | Problem | Type | Start here | What's inside |
|---|---|---|---|---|
| 1 | Building Castle In The Cloud | Architecture | [src/problem1/SOLUTION.md](src/problem1/SOLUTION.md) | AWS spot-trading platform for 500 RPS / p99 < 100 ms: architecture + order-flow diagrams, latency budget, service-by-service rationale with alternatives, HA failure matrix, cost estimate, 4-stage scaling plan |
| 2 | Diagnose Me Doctor | Troubleshooting | [src/problem2/SOLUTION.md](src/problem2/SOLUTION.md) | Runbook for an NGINX LB VM stuck at 99% disk: first-5-minutes triage, decision tree, 9 root causes with confirm / impact / recovery / prevention, plus a tested **read-only** [`disk-triage.sh`](src/problem2/disk-triage.sh) |
| 3 | Debugging issues within system | Hands-on | [src/problem3/SOLUTION.md](src/problem3/SOLUTION.md) | Reproduced and fixed the Docker Compose stack: wrong upstream port, process crash on DB restart, connection-pool leak, Redis on the critical path, missing healthchecks/restarts, stale DNS in nginx, and more. Before/after evidence, monitoring and prevention |
| 4 | Ship It Twice | Hands-on | [src/problem4/SOLUTION.md](src/problem4/SOLUTION.md) | Production GitHub Actions pipelines: backend → EC2 (S3 bundle + CodeDeploy), frontend → S3 + CloudFront. OIDC, build-once-promote, approval gate, smoke tests, automatic rollback, SHA-pinned actions. Sample apps with tests; workflows pass actionlint |
| 5 | Fortify The Castle | Security architecture | [src/problem5/SOLUTION.md](src/problem5/SOLUTION.md) | Problem 1's design with security built in: 20 marked changes (added / changed), accepted risks, launch blockers vs. deferred items, missing facts and assumptions |

## Quick checks a reviewer can run

```bash
# Problem 3 — the fixed stack
cd src/problem3 && docker compose up --build -d && curl localhost:8080/api/users

# Problem 4 — apps and pipelines
cd src/problem4/backend  && npm ci && npm run lint && npm test
cd src/problem4/frontend && npm ci && npm run lint && npm test && npm run build
actionlint   # run from src/problem4 (treated as the repo root for the workflows)

# Problem 2 — read-only triage on any Ubuntu host
sudo src/problem2/disk-triage.sh
```

Assumptions and anything I couldn't execute (e.g., real AWS deployments) are stated explicitly in each solution.
