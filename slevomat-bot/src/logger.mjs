// Jednoduchý logger s časovými značkami a zápisem do logs/run-<datum>.log.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const LOG_DIR = path.join(ROOT, 'logs');

function ts() {
  return new Date().toISOString().replace('T', ' ').slice(0, 19);
}

function ensureDir() {
  if (!fs.existsSync(LOG_DIR)) fs.mkdirSync(LOG_DIR, { recursive: true });
}

function writeFile(line) {
  try {
    ensureDir();
    const file = path.join(LOG_DIR, `run-${new Date().toISOString().slice(0, 10)}.log`);
    fs.appendFileSync(file, line + '\n');
  } catch {
    /* zápis do souboru je best-effort, nesmí shodit běh */
  }
}

function emit(level, parts) {
  const msg = parts
    .map((p) => (typeof p === 'string' ? p : JSON.stringify(p)))
    .join(' ');
  const line = `[${ts()}] ${level.padEnd(5)} ${msg}`;
  // eslint-disable-next-line no-console
  (level === 'ERROR' ? console.error : console.log)(line);
  writeFile(line);
}

export const log = {
  info: (...a) => emit('INFO', a),
  warn: (...a) => emit('WARN', a),
  error: (...a) => emit('ERROR', a),
  ok: (...a) => emit('OK', a),
};
