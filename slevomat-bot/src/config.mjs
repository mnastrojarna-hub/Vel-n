// Načtení a validace konfigurace (.env + config.json).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import dotenv from 'dotenv';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
dotenv.config({ path: path.join(ROOT, '.env') });

export const PATHS = {
  root: ROOT,
  config: path.join(ROOT, 'config.json'),
  configExample: path.join(ROOT, 'config.example.json'),
  session: path.join(ROOT, 'sessions', 'storageState.json'),
  screenshots: path.join(ROOT, 'screenshots'),
};

function num(name, def) {
  const v = process.env[name];
  if (v == null || v === '') return def;
  const n = Number(v);
  return Number.isFinite(n) ? n : def;
}

export function loadEnv() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    throw new Error(
      'Chybí SUPABASE_URL nebo SUPABASE_SERVICE_ROLE_KEY v .env (zkopíruj .env.example → .env a vyplň).'
    );
  }
  return {
    supabaseUrl: url,
    supabaseKey: key,
    batchLimit: num('BATCH_LIMIT', 0),
    delayBetweenMs: num('DELAY_BETWEEN_MS', 1500),
    maxAttempts: num('MAX_ATTEMPTS', 3),
    headful: process.env.HEADFUL === '1',
    triggerPort: num('TRIGGER_PORT', 8787),
    pollIntervalSec: num('POLL_INTERVAL_SEC', 60),
  };
}

export function loadConfig() {
  if (!fs.existsSync(PATHS.config)) {
    throw new Error(
      `Chybí config.json. Zkopíruj config.example.json → config.json a vyplň selektory portálu.`
    );
  }
  const cfg = JSON.parse(fs.readFileSync(PATHS.config, 'utf8'));
  for (const key of ['loginUrl', 'partnerHash', 'dashboardPath', 'selectors', 'outcomes']) {
    if (!cfg[key]) throw new Error(`config.json: chybí povinná sekce "${key}".`);
  }
  for (const sel of ['codeInput', 'verifySubmit', 'loggedInMarker']) {
    if (!cfg.selectors[sel]) {
      throw new Error(`config.json: chybí selektor selectors.${sel} (nutný pro běh).`);
    }
  }
  // Sestav absolutní URL dashboardu z partnerHash + dashboardPath.
  const origin = new URL(cfg.loginUrl).origin;
  cfg.dashboardUrl = origin + cfg.dashboardPath.replace('{hash}', cfg.partnerHash);
  cfg.redeemButtonText = cfg.redeemButtonText || 'Uplatnit';
  cfg.confirmButtonText = cfg.confirmButtonText || 'Potvrdit';
  cfg.timeouts = cfg.timeouts || {};
  cfg.timeouts.navigationMs = cfg.timeouts.navigationMs || 30000;
  cfg.timeouts.actionMs = cfg.timeouts.actionMs || 15000;
  return cfg;
}
