#!/usr/bin/env node

import { execSync, spawn } from "child_process";
import fs from "fs";
import { fileURLToPath } from "url";
import path from "path";

const root = path.dirname(fileURLToPath(import.meta.url));

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
