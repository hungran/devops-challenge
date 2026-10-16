import { defineConfig } from "vite";

export default defineConfig({
  define: {
    __APP_VERSION__: JSON.stringify(process.env.APP_VERSION || "dev"),
  },
  build: {
    outDir: "dist",
    assetsDir: "assets", // content-hashed => safe to cache forever
    sourcemap: true, // uploaded with the artifact; not served publicly (see SOLUTION.md)
  },
});
