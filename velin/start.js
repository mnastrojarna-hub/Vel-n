#!/usr/bin/env node

const { execSync, spawn } = require("child_process");
const fs = require("fs");
const path = require("path");

const root = __dirname;

// Install dependencies if node_modules is missing
if (!fs.existsSync(path.join(root, "node_modules"))) {
  console.log("Instaluji závislosti...");
  execSync("npm install", { cwd: root, stdio: "inherit" });
}

console.log("Spouštím Velín...");

// Start Vite dev server with --open to launch browser automatically
const vite = spawn("npx", ["vite", "--open"], {
  cwd: root,
  stdio: "inherit",
  shell: true,
});

vite.on("close", (code) => process.exit(code));
