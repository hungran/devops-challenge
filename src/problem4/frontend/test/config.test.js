import { test } from "node:test";
import assert from "node:assert/strict";
import { validateConfig, loadConfig } from "../src/config.js";

test("accepts a valid config and strips trailing slashes", () => {
  assert.deepEqual(validateConfig({ apiBaseUrl: "https://api.example.com/", environment: "staging" }), {
    apiBaseUrl: "https://api.example.com",
    environment: "staging",
  });
});

test("rejects a non-http apiBaseUrl", () => {
  assert.throws(() => validateConfig({ apiBaseUrl: "javascript:alert(1)", environment: "production" }));
});

test("rejects an unknown environment", () => {
  assert.throws(() => validateConfig({ apiBaseUrl: "https://a.b", environment: "dev" }));
});

test("rejects non-objects", () => {
  assert.throws(() => validateConfig(null));
});

test("loadConfig fetches and validates /config.json", async () => {
  const fake = async (url) => {
    assert.equal(url, "/config.json");
    return { ok: true, json: async () => ({ apiBaseUrl: "https://a.b", environment: "local" }) };
  };
  assert.equal((await loadConfig(fake)).apiBaseUrl, "https://a.b");
});

test("loadConfig surfaces HTTP errors", async () => {
  await assert.rejects(loadConfig(async () => ({ ok: false, status: 404 })), /404/);
});
