"use strict";

const express = require("express");
const { Pool } = require("pg");
const Redis = require("ioredis");

// ---------------------------------------------------------------------------
// Config (12-factor: everything from env, sane defaults for local compose)
// ---------------------------------------------------------------------------
const cfg = {
  port: Number(process.env.PORT || 3000),
  db: {
    host: process.env.DB_HOST || "postgres",
    port: Number(process.env.DB_PORT || 5432),
    user: process.env.DB_USER || "postgres",
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME || "postgres",
    poolMax: Number(process.env.PG_POOL_MAX || 10),
  },
  redis: {
    host: process.env.REDIS_HOST || "redis",
    port: Number(process.env.REDIS_PORT || 6379),
  },
  shutdownTimeoutMs: Number(process.env.SHUTDOWN_TIMEOUT_MS || 10000),
};

// Minimal structured (JSON) logger so logs are greppable / shippable.
const log = (level, msg, extra = {}) =>
  console.log(JSON.stringify({ ts: new Date().toISOString(), level, msg, ...extra }));

// ---------------------------------------------------------------------------
// PostgreSQL
// ---------------------------------------------------------------------------
const pool = new Pool({
  host: cfg.db.host,
  port: cfg.db.port,
  user: cfg.db.user,
  password: cfg.db.password,
  database: cfg.db.database,
  max: cfg.db.poolMax, // must stay well below Postgres max_connections x replicas
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000, // FIX: never wait forever for a pooled client
  statement_timeout: 5000, // server-side guard
  query_timeout: 5000, // client-side guard
});

// FIX: an idle client dying (Postgres restart / failover / network blip) emits
// 'error' on the pool. Without a listener Node treats it as an unhandled
// 'error' event and the whole process exits.
pool.on("error", (err) => log("warn", "postgres idle client error", { error: err.message }));

// ---------------------------------------------------------------------------
// Redis (best-effort: only stores a "last_call" marker, never on the critical path)
// ---------------------------------------------------------------------------
const redis = new Redis({
  host: cfg.redis.host,
  port: cfg.redis.port,
  connectTimeout: 2000,
  commandTimeout: 500, // FIX: a slow/dead Redis can't stall requests
  maxRetriesPerRequest: 1,
  enableOfflineQueue: false, // FIX: fail fast instead of queueing while disconnected
  retryStrategy: (times) => Math.min(times * 200, 2000), // keep reconnecting
});

let lastRedisError = null;
redis.on("error", (err) => {
  // ioredis emits on every reconnect attempt; only log state changes.
  if (err.message !== lastRedisError) {
    lastRedisError = err.message;
    log("warn", "redis error", { error: err.message });
  }
});
redis.on("ready", () => {
  lastRedisError = null;
  log("info", "redis ready");
});

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------
const app = express();
app.disable("x-powered-by");

app.get("/api/users", async (req, res) => {
  let result;
  try {
    // FIX: pool.query() always releases the client, even when the query throws.
    // The original connect()/release() pair leaked a client on every error,
    // and after PG_POOL_MAX leaks every request hung forever.
    result = await pool.query("SELECT NOW()");
  } catch (err) {
    log("error", "database query failed", { error: err.message, path: req.path });
    return res.status(503).json({ ok: false, error: "database unavailable" });
  }

  // FIX: fire-and-forget. A Redis outage degrades this feature, not the endpoint.
  redis
    .set("last_call", Date.now())
    .catch((err) => log("warn", "redis set failed", { error: err.message }));

  res.json({ ok: true, time: result.rows[0] });
});

// Liveness: the process is up and serving HTTP.
app.get("/status", (req, res) => {
  res.json({ status: "ok" });
});

// Readiness: can we actually serve traffic? (DB required, Redis optional)
app.get("/ready", async (req, res) => {
  const checks = { postgres: "down", redis: redis.status === "ready" ? "up" : "degraded" };
  try {
    await pool.query("SELECT 1");
    checks.postgres = "up";
    res.json({ status: "ready", checks });
  } catch (err) {
    res.status(503).json({ status: "not_ready", checks });
  }
});

const server = app.listen(cfg.port, () => log("info", `API running on ${cfg.port}`));

// ---------------------------------------------------------------------------
// Graceful shutdown: stop accepting, drain in-flight requests, close pools.
// ---------------------------------------------------------------------------
let shuttingDown = false;
function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  log("info", "shutting down", { signal });

  const force = setTimeout(() => {
    log("error", "forced shutdown after timeout");
    process.exit(1);
  }, cfg.shutdownTimeoutMs);
  force.unref();

  server.close(async () => {
    await Promise.allSettled([pool.end(), redis.quit()]);
    log("info", "shutdown complete");
    process.exit(0);
  });
}
process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
process.on("unhandledRejection", (reason) =>
  log("error", "unhandled rejection", { error: String(reason) })
);
