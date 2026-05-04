#!/usr/bin/env node

import { spawn, spawnSync } from "child_process";
import fs from "fs";
import { fileURLToPath } from "url";
import path from "path";
import os from "os";

const root = path.dirname(fileURLToPath(import.meta.url));
const isWindows = process.platform === "win32";

function pauseOnExit(code) {
  if (isWindows && code !== 0) {
    console.error("\n[Velín] Spuštění selhalo. Stiskněte libovolnou klávesu pro zavření okna...");
    try {
      spawnSync("cmd", ["/c", "pause"], { stdio: "inherit" });
    } catch {}
  }
  process.exit(code);
}

process.on("uncaughtException", (err) => {
  console.error("[Velín] Chyba:", err && err.message ? err.message : err);
  pauseOnExit(1);
});

if (!fs.existsSync(path.join(root, "node_modules"))) {
  console.log("[Velín] Instaluji závislosti (může trvat několik minut)...");
  const npmCmd = isWindows ? "npm.cmd" : "npm";
  const install = spawnSync(npmCmd, ["install"], {
    cwd: root,
    stdio: "inherit",
    shell: isWindows,
  });
  if (install.status !== 0) {
    console.error("[Velín] npm install selhal. Zkontrolujte, že máte nainstalovaný Node.js (https://nodejs.org).");
    pauseOnExit(install.status || 1);
  }
}

console.log("[Velín] Spouštím vývojový server...");

const npxCmd = isWindows ? "npx.cmd" : "npx";
const vite = spawn(npxCmd, ["vite", "--host", "127.0.0.1"], {
  cwd: root,
  stdio: ["inherit", "pipe", "pipe"],
  shell: isWindows,
  env: { ...process.env, BROWSER: "none" },
});

let opened = false;
// ANSI escape kódy odstraníme před hledáním URL (Vite obarvuje port)
const ansiRegex = /\x1B\[[0-?]*[ -/]*[@-~]/g;
// Port je povinný — bez něj prohlížeč otevře port 80 a dostane ERR_CONNECTION_REFUSED
const urlRegex = /(https?:\/\/(?:localhost|127\.0\.0\.1):\d+\/?)/i;

function openInBrowser(url) {
  if (opened) return;
  opened = true;
  console.log(`[Velín] Otevírám prohlížeč: ${url}`);
  try {
    if (isWindows) {
      spawn("cmd", ["/c", "start", "", url], { detached: true, stdio: "ignore" }).unref();
    } else if (process.platform === "darwin") {
      spawn("open", [url], { detached: true, stdio: "ignore" }).unref();
    } else {
      spawn("xdg-open", [url], { detached: true, stdio: "ignore" }).unref();
    }
  } catch (e) {
    console.error("[Velín] Nepodařilo se otevřít prohlížeč automaticky. Otevřete prosím ručně:", url);
  }
}

let buffer = "";
function handleStream(stream, isErr) {
  stream.on("data", (chunk) => {
    const text = chunk.toString();
    (isErr ? process.stderr : process.stdout).write(text);
    if (!opened) {
      buffer = (buffer + text).slice(-4096);
      const clean = buffer.replace(ansiRegex, "");
      const m = clean.match(urlRegex);
      if (m) {
        // Počkáme, ať Vite stihne začít poslouchat
        setTimeout(() => openInBrowser(m[1]), 800);
      }
    }
  });
}

handleStream(vite.stdout, false);
handleStream(vite.stderr, true);

vite.on("error", (err) => {
  console.error("[Velín] Nepodařilo se spustit Vite:", err.message);
  console.error("[Velín] Ověřte, že je nainstalován Node.js 18+ (https://nodejs.org).");
  pauseOnExit(1);
});

vite.on("close", (code) => pauseOnExit(code ?? 0));
