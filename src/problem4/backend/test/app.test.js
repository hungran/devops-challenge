"use strict";

const { test, before, after } = require("node:test");
const assert = require("node:assert/strict");
const { createApp, loadBuildInfo } = require("../src/app");

let server;
let base;

before(async () => {
  server = createApp({ buildInfo: { version: "abc123" } }).listen(0);
  await new Promise((r) => server.once("listening", r));
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => server.close());

test("GET /healthz returns ok", async () => {
  const res = await fetch(`${base}/healthz`);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { status: "ok" });
});

test("GET /version returns the build version", async () => {
  const res = await fetch(`${base}/version`);
  assert.equal((await res.json()).version, "abc123");
});

test("GET /api/hello greets by name and truncates input", async () => {
  const res = await fetch(`${base}/api/hello?name=${"x".repeat(100)}`);
  assert.equal(res.status, 200);
  assert.equal((await res.json()).message, `Hello, ${"x".repeat(50)}!`);
});

test("unknown routes return 404 JSON", async () => {
  const res = await fetch(`${base}/nope`);
  assert.equal(res.status, 404);
});

test("loadBuildInfo falls back to APP_VERSION outside a release bundle", () => {
  process.env.APP_VERSION = "local";
  assert.equal(loadBuildInfo().version, "local");
});
