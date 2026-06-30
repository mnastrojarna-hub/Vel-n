// Playwright vrstva nad Slevomat partner portálem.
// Flow uplatnění je dvoukrokový (dle reálného portálu):
//   1) zadat kód → „Ověřit" (input[name=check])
//   2) u platného voucheru → „Uplatnit" → potvrzovací dialog „Potvrdit"
// Login má reCAPTCHA, proto se přihlašuje jednorázově ručně (`npm run login`)
// a běhy používají uloženou session (sessions/storageState.json).
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';
import { PATHS } from './config.mjs';
import { log } from './logger.mjs';

export class NeedLoginError extends Error {}

function compile(patterns) {
  return (patterns || []).map((p) => new RegExp(p, 'i'));
}

export async function createSession(env, cfg) {
  const hasSession = fs.existsSync(PATHS.session);
  if (!hasSession) {
    throw new NeedLoginError(
      'Chybí uložená session (sessions/storageState.json). Spusť nejdřív `npm run login`.'
    );
  }
  const browser = await chromium.launch({ headless: !env.headful });
  const context = await browser.newContext({ storageState: PATHS.session });
  context.setDefaultNavigationTimeout(cfg.timeouts.navigationMs);
  context.setDefaultTimeout(cfg.timeouts.actionMs);
  const page = await context.newPage();

  const outcomes = {
    alreadyRedeemed: compile(cfg.outcomes.alreadyRedeemed),
    cancelled: compile(cfg.outcomes.cancelled),
    notPaid: compile(cfg.outcomes.notPaid),
    invalid: compile(cfg.outcomes.invalid),
    applied: compile(cfg.outcomes.applied),
  };
  const redeemRe = new RegExp(cfg.redeemButtonText, 'i');

  async function isLoggedIn() {
    try {
      await page.locator(cfg.selectors.loggedInMarker).first().waitFor({
        state: 'visible',
        timeout: 5000,
      });
      return true;
    } catch {
      return false;
    }
  }

  async function ensureLoggedIn() {
    await page.goto(cfg.dashboardUrl, { waitUntil: 'domcontentloaded' });
    if (await isLoggedIn()) return;
    throw new NeedLoginError(
      'Uložená session je neplatná/vypršela. Spusť `npm run login` a přihlas se znovu.'
    );
  }

  async function screenshot(name) {
    try {
      fs.mkdirSync(PATHS.screenshots, { recursive: true });
      const safe = String(name).replace(/[^a-z0-9_-]+/gi, '_').slice(0, 80);
      const file = path.join(PATHS.screenshots, `${Date.now()}-${safe}.png`);
      await page.screenshot({ path: file, fullPage: true });
      return file;
    } catch {
      return null;
    }
  }

  // Vrátí první viditelný lokátor z kandidátů (nebo null).
  async function firstVisible(locators, timeoutMs) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      for (const loc of locators) {
        try {
          const el = loc.first();
          if (await el.isVisible()) return el;
        } catch {
          /* lokátor nepasuje, zkus další */
        }
      }
      await page.waitForTimeout(250);
    }
    return null;
  }

  async function readResult() {
    try {
      const marker = page.locator(cfg.selectors.resultMarker).first();
      await marker.waitFor({ state: 'visible', timeout: cfg.timeouts.actionMs });
      return await marker.innerText();
    } catch {
      return (await page.locator('body').innerText().catch(() => '')) || '';
    }
  }

  function classify(text) {
    const t = (text || '').replace(/\s+/g, ' ').trim();
    // Pořadí záměrně: terminální/chybové stavy dřív než 'applied'
    // (aby „už byl uplatněn" nespadlo omylem do úspěchu).
    if (outcomes.alreadyRedeemed.some((r) => r.test(t))) return { status: 'already_redeemed', message: t };
    if (outcomes.cancelled.some((r) => r.test(t))) return { status: 'cancelled', message: t };
    if (outcomes.notPaid.some((r) => r.test(t))) return { status: 'not_paid', message: t };
    if (outcomes.invalid.some((r) => r.test(t))) return { status: 'invalid', message: t };
    if (outcomes.applied.some((r) => r.test(t))) return { status: 'applied', message: t };
    return { status: 'failed', message: t || 'Neznámý výsledek (prázdná hláška).' };
  }

  /** Uplatní jeden kód. Vrací { status, message, screenshot? }. */
  async function applyVoucher(code) {
    await page.goto(cfg.dashboardUrl, { waitUntil: 'domcontentloaded' });
    if (!(await isLoggedIn())) throw new NeedLoginError('Session vypršela během běhu.');

    // Krok 1 — zadat kód a Ověřit.
    const input = page.locator(cfg.selectors.codeInput).first();
    await input.waitFor({ state: 'visible' });
    await input.fill('');
    await input.fill(code);
    await Promise.all([
      page.waitForLoadState('networkidle').catch(() => {}),
      page.locator(cfg.selectors.verifySubmit).first().click(),
    ]);

    // Krok 2 — pokud se objeví akce „Uplatnit", klikni a potvrď.
    const redeemCandidates = [
      page.getByRole('button', { name: redeemRe }),
      page.getByRole('link', { name: redeemRe }),
      page.locator(`input[type="submit"][value*="${cfg.redeemButtonText}" i]`),
      page.locator(`button:has-text("${cfg.redeemButtonText}"), a:has-text("${cfg.redeemButtonText}")`),
    ];
    const redeem = await firstVisible(redeemCandidates, 4000);
    let redeemClicked = false;
    if (redeem) {
      redeemClicked = true;
      await redeem.click();
      // Potvrzovací dialog (js-confirm-dialog) — pokud se ukáže.
      const confirm = page.locator(cfg.selectors.confirmSubmit).first();
      try {
        await confirm.waitFor({ state: 'visible', timeout: 3000 });
        await Promise.all([
          page.waitForLoadState('networkidle').catch(() => {}),
          confirm.click(),
        ]);
      } catch {
        /* dialog se neobjevil — některé akce potvrzení nevyžadují */
      }
    }

    const result = classify(await readResult());
    // Klikli jsme Uplatnit, ale výsledek je nejednoznačný → uložit screenshot,
    // ať se dá hláška dohledat a doladit outcomes v config.json.
    const needShot = result.status === 'failed' || result.status === 'invalid';
    if (needShot || (redeemClicked && result.status !== 'applied')) {
      result.screenshot = await screenshot(`voucher-${code}-${result.status}`);
    }
    if (!redeem && result.status === 'failed') {
      result.message =
        'Po ověření se neobjevila akce „Uplatnit" ani známá hláška. ' +
        'Zkontroluj screenshot a uprav redeemButtonText/outcomes v config.json. ' +
        result.message;
    }
    return result;
  }

  return {
    page,
    context,
    browser,
    ensureLoggedIn,
    isLoggedIn,
    applyVoucher,
    screenshot,
    close: () => browser.close(),
  };
}
