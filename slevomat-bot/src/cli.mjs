#!/usr/bin/env node
// Vstupní bod CLI: login | run | status | record | serve
import { spawn } from 'node:child_process';
import { loadEnv, loadConfig } from './config.mjs';
import { makeDb } from './db.mjs';
import { interactiveLogin } from './login.mjs';
import { runOnce, runWatch } from './run.mjs';
import { startServer } from './server.mjs';
import { log } from './logger.mjs';

const cmd = (process.argv[2] || 'run').toLowerCase();
const flags = new Set(process.argv.slice(3));

async function main() {
  switch (cmd) {
    case 'login': {
      await interactiveLogin(loadConfig());
      break;
    }
    case 'run': {
      await runOnce({ dryRun: flags.has('--dry-run') });
      break;
    }
    case 'watch': {
      await runWatch();
      break;
    }
    case 'status': {
      const db = makeDb(loadEnv());
      const s = await db.summary();
      log.info(`Slevomat fronta — čeká: ${s.pending}, vyřízeno: ${s.applied}, chyby: ${s.failed}.`);
      break;
    }
    case 'record': {
      // Pomocník na zjištění selektorů: otevře Playwright codegen.
      const cfg = loadConfig();
      log.info('Spouštím Playwright codegen — proklikej login a uplatnění, kód se generuje do okna.');
      const child = spawn('npx', ['playwright', 'codegen', cfg.loginUrl], { stdio: 'inherit', shell: true });
      await new Promise((res) => child.on('exit', res));
      break;
    }
    case 'serve': {
      await startServer();
      break;
    }
    default:
      log.info('Použití: slevomat-bot <login|run [--dry-run]|watch|status|record|serve>');
  }
}

main().catch((e) => {
  log.error(e.message || String(e));
  process.exit(1);
});
