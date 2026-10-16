import { loadConfig } from "./config.js";

// Injected at build time by vite.config.js (git SHA in CI, "dev" locally).
// eslint-disable-next-line no-undef
const version = __APP_VERSION__;

async function main() {
  document.getElementById("version").textContent = `build ${version}`;
  try {
    const config = await loadConfig();
    const res = await fetch(`${config.apiBaseUrl}/api/hello?name=${config.environment}`);
    const { message } = await res.json();
    document.getElementById("message").textContent = message;
  } catch (err) {
    document.getElementById("message").textContent = "Backend unavailable";
    console.error(err);
  }
}

main();
