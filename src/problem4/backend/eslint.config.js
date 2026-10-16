"use strict";

const js = require("@eslint/js");
const globals = require("globals");

module.exports = [
  { ignores: ["node_modules/**", "dist/**", "coverage/**"] },
  js.configs.recommended,
  {
    languageOptions: { sourceType: "commonjs", globals: { ...globals.node } },
    rules: { "no-unused-vars": ["error", { argsIgnorePattern: "^_" }] },
  },
];
