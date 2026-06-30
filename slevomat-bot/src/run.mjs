// Hlavní orchestrace: vyber poukazy → uplatni → zapiš výsledek.
import { loadEnv, loadConfig } from './config.mjs';
import { makeDb, DONE_STATUSES } from './db.mjs';
import { createSession, NeedLoginError } from './slevomat.mjs';
import { log } from './logger.mjs';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Lidsky čitelné popisky stavů do logu.
const LABEL = {
  applied: 'UPLATNĚNO',
  already_redeemed: 'JIŽ UPLATNĚNO (ber jako hotovo)',
  invalid: 'NEPLATNÝ',
  not_paid: 'NEZAPLACENO',
  cancelled: 'STORNO/REFUND',
  failed: 'CHYBA (přechodná, retry)',
};

/**
 * @param {object} opts
 * @param {boolean} opts.dryRun  Nic se neuplatní ani nezapíše, jen vypíše frontu.
 * @returns {Promise<object>} souhrn běhu
 */
export async function runOnce({ dryRun = false } = {}) {
  const env = loadEnv();
  const cfg = loadConfig();
  const db = makeDb(env);

  const pending = await db.fetchPending(env.batchLimit);
  log.info(`Ke zpracování: ${pending.length} poukaz(ů)${dryRun ? ' (DRY-RUN)' : ''}.`);
  if (pending.length === 0) return { processed: 0, applied: 0, failed: 0, results: [] };

  if (dryRun) {
    for (const v of pending) log.info(`  • ${v.code} (${v.amount} Kč, pokusů: ${v.slevomat_apply_attempts || 0})`);
    return { processed: 0, applied: 0, failed: 0, results: [], dryRun: true };
  }

  const session = await createSession(env, cfg);
  const results = [];
  let applied = 0;
  let failed = 0;

  try {
    await session.ensureLoggedIn();

    for (const v of pending) {
      let outcome;
      try {
        outcome = await applyWithRetry(session, v, env, db);
      } catch (e) {
        if (e instanceof NeedLoginError) {
          log.error('Ztráta přihlášení — přerušuji běh:', e.message);
          break; // zbytek fronty se zpracuje v dalším běhu po `npm run login`
        }
        outcome = { status: 'failed', message: e.message };
      }

      await db.recordResult(v, outcome);
      const done = DONE_STATUSES.has(outcome.status);
      if (done) applied += 1;
      else failed += 1;
      results.push({ code: v.code, ...outcome });
      log[done ? 'ok' : 'warn'](`${v.code}: ${LABEL[outcome.status] || outcome.status}`);

      if (env.delayBetweenMs) await sleep(env.delayBetweenMs);
    }
  } finally {
    await session.close().catch(() => {});
  }

  log.info(`Hotovo. Vyřízeno: ${applied}, k řešení/retry: ${failed}.`);
  return { processed: results.length, applied, failed, results };
}

// Retry jen pro přechodné chyby (status 'failed'); terminální stavy vrací hned.
async function applyWithRetry(session, voucher, env, db) {
  let last;
  for (let attempt = 1; attempt <= env.maxAttempts; attempt += 1) {
    last = await session.applyVoucher(voucher.code);
    if (last.status !== 'failed') return last;
    if (attempt < env.maxAttempts) {
      const backoff = 1000 * 2 ** (attempt - 1); // 1s, 2s, 4s…
      log.warn(`${voucher.code}: přechodná chyba, retry za ${backoff}ms (${attempt}/${env.maxAttempts}).`);
      await sleep(backoff);
    }
  }
  return last;
}
