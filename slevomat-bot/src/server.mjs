// Volitelný lokální trigger server pro tlačítko ve Velínu.
// Běží na 127.0.0.1:<TRIGGER_PORT>. Velín spuštěný lokálně (http://localhost)
// na něj může volat GET /status a POST /run. (Pozn.: Velín z Vercelu přes HTTPS
// na http://localhost kvůli mixed-content nedosáhne — to je jen pro lokální běh.)
import http from 'node:http';
import { loadEnv } from './config.mjs';
import { makeDb } from './db.mjs';
import { runOnce } from './run.mjs';
import { log } from './logger.mjs';

let running = false;
let lastResult = null;

function send(res, code, body) {
  res.writeHead(code, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  });
  res.end(JSON.stringify(body));
}

export async function startServer() {
  const env = loadEnv();
  const db = makeDb(env);

  const server = http.createServer(async (req, res) => {
    if (req.method === 'OPTIONS') return send(res, 204, {});

    if (req.method === 'GET' && req.url === '/status') {
      const s = await db.summary().catch((e) => ({ error: e.message }));
      return send(res, 200, { running, queue: s, lastResult });
    }

    if (req.method === 'POST' && req.url === '/run') {
      if (running) return send(res, 409, { error: 'Běh už probíhá.' });
      running = true;
      log.info('Trigger /run přijat.');
      // Spustíme na pozadí, odpovíme hned (běh může trvat minuty).
      runOnce({})
        .then((r) => {
          lastResult = { at: new Date().toISOString(), ...r };
          log.ok(`Trigger běh hotov: vyřízeno ${r.applied}, chyb ${r.failed}.`);
        })
        .catch((e) => {
          lastResult = { at: new Date().toISOString(), error: e.message };
          log.error('Trigger běh selhal:', e.message);
        })
        .finally(() => {
          running = false;
        });
      return send(res, 202, { accepted: true });
    }

    send(res, 404, { error: 'not found' });
  });

  server.listen(env.triggerPort, '127.0.0.1', () => {
    log.ok(`Trigger server běží na http://127.0.0.1:${env.triggerPort} (GET /status, POST /run).`);
  });
}
