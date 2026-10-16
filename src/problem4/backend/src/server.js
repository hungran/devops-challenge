"use strict";

const { createApp } = require("./app");

const port = Number(process.env.PORT || 8080);
const server = createApp().listen(port, () => console.log(`backend listening on ${port}`));

// systemd sends SIGTERM on stop/restart: drain in-flight requests, then exit.
function shutdown(signal) {
  console.log(`${signal} received, draining`);
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 10000).unref();
}
process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
