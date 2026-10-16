// Runtime configuration is fetched from /config.json, which the deploy job
// writes per environment. This keeps the build artifact identical across
// staging and production ("build once, promote the same bytes").

export function validateConfig(raw) {
  if (!raw || typeof raw !== "object") throw new Error("config must be an object");
  const { apiBaseUrl, environment } = raw;
  if (typeof apiBaseUrl !== "string" || !/^https?:\/\/[^\s]+$/.test(apiBaseUrl)) {
    throw new Error("config.apiBaseUrl must be an http(s) URL");
  }
  if (!["local", "staging", "production"].includes(environment)) {
    throw new Error("config.environment must be local, staging or production");
  }
  return { apiBaseUrl: apiBaseUrl.replace(/\/+$/, ""), environment };
}

export async function loadConfig(fetchImpl = fetch) {
  const res = await fetchImpl("/config.json", { cache: "no-store" });
  if (!res.ok) throw new Error(`config.json returned ${res.status}`);
  return validateConfig(await res.json());
}
