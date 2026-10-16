"use strict";

const fs = require("node:fs");
const path = require("node:path");
const express = require("express");

// build-info.json is written by CI into the release bundle; absent in local dev.
function loadBuildInfo() {
  try {
    return JSON.parse(fs.readFileSync(path.join(__dirname, "..", "build-info.json"), "utf8"));
  } catch {
    return { version: process.env.APP_VERSION || "dev" };
  }
}

function createApp({ buildInfo = loadBuildInfo() } = {}) {
  const app = express();
  app.disable("x-powered-by");

  // Liveness: used by CodeDeploy ValidateService and the ALB target group.
  app.get("/healthz", (req, res) => res.json({ status: "ok" }));

  // Which build is live? Used by the pipeline smoke test and for rollback.
  app.get("/version", (req, res) => res.json(buildInfo));

  app.get("/api/hello", (req, res) => {
    const name = String(req.query.name || "world").slice(0, 50);
    res.json({ message: `Hello, ${name}!` });
  });

  app.use((req, res) => res.status(404).json({ error: "not found" }));
  return app;
}

module.exports = { createApp, loadBuildInfo };
