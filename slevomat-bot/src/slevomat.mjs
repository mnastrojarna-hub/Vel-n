// Playwright vrstva nad Slevomat partner portálem.
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';
import { PATHS } from './config.mjs';
import { log } from './logger.mjs';

export class NeedLoginError extends Error {}

function compile(patterns) {
  return (patterns || []).map((p) => new RegExp(p, 'i'));
}

export async function createSession(env, cfg, { interactive = false } = {}) {
  const hasSession = fs.existsSync(PATHS.session);
  const browser = await chromium.launch({ headless: interactive ? false : !env.headful });
  const context = await browser.newContext(
    hasSession ? { storageState: PATHS.session } : undefined
  );
  context.setDefaultNavigationTimeout(cfg.timeouts.navigationMs);
  context.setDefaultTimeout(cfg.timeouts.actionMs);
  const page = await context.newPage();

  const outcomes = {
    applied: compile(cfg.outcomes.applied),
    alreadyRedeemed: compile(cfg.outcomes.alreadyRedeemed),
    invalid: compile(cfg.outcomes.invalid),
    notPaid: compile(cfg.outcomes.notPaid),
    cancelled: compile(cfg.outcomes.cancelled),
  };

  async function saveSession() {
    fs.mkdirSync(path.dirname(PATHS.session), { recursive: true });
    await context.storageState({ path: PATHS.session });
  }

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

  // Programatické přihlášení (jen bez 2FA/captcha). Při 2FA použij `npm run login`.
  async function ensureLoggedIn() {
    await page.goto(cfg.redeemUrl, { waitUntil: 'domcontentloaded' });
    if (await isLoggedIn()) return;

    if (!env.slevomatUser || !env.slevomatPass) {
      throw new NeedLoginError(
        'Není platná session a nejsou vyplněné přihlašovací údaje. Spusť `npm run login` a přihlas se ručně (zvládne i 2FA).'
      );
    }
    log.info('Session neplatná → zkouším programatické přihlášení.');
    await page.goto(cfg.loginUrl, { waitUntil: 'domcontentloaded' });
    await page.fill(cfg.selectors.usernameInput, env.slevomatUser);
    await page.fill(cfg.selectors.passwordInput, env.slevomatPass);
    await Promise.all([
      page.waitForLoadState('networkidle').catch(() => {}),
      page.click(cfg.selectors.loginSubmit),
    ]);
    if (!(await isLoggedIn())) {
      await screenshot('login-failed');
      throw new NeedLoginError(
        'Přihlášení selhalo (špatné údaje, 2FA nebo captcha). Spusť `npm run login` a přihlas se ručně.'
      );
    }
    await saveSession();
    log.ok('Přihlášení OK, session uložena.');
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

  function classify(text) {
    const t = (text || '').replace(/\s+/g, ' ').trim();
    if (outcomes.applied.some((r) => r.test(t))) return { status: 'applied', message: t };
    if (outcomes.alreadyRedeemed.some((r) => r.test(t)))
      return { status: 'already_redeemed', message: t };
    if (outcomes.cancelled.some((r) => r.test(t))) return { status: 'cancelled', message: t };
    if (outcomes.notPaid.some((r) => r.test(t))) return { status: 'not_paid', message: t };
    if (outcomes.invalid.some((r) => r.test(t))) return { status: 'invalid', message: t };
    // Neznámou hlášku bereme jako přechodnou chybu (retry) + uložíme screenshot.
    return { status: 'failed', message: t || 'Neznámý výsledek (prázdná hláška).' };
  }

  /** Uplatní jeden kód. Vrací { status, message }. */
  async function applyVoucher(code) {
    await page.goto(cfg.redeemUrl, { waitUntil: 'domcontentloaded' });
    if (!(await isLoggedIn())) throw new NeedLoginError('Session vypršela během běhu.');

    const input = page.locator(cfg.selectors.codeInput).first();
    await input.waitFor({ state: 'visible' });
    await input.fill('');
    await input.fill(code);
    await Promise.all([
      page.waitForLoadState('networkidle').catch(() => {}),
      page.click(cfg.selectors.redeemSubmit),
    ]);

    let text = '';
    try {
      const marker = page.locator(cfg.selectors.resultMarker).first();
      await marker.waitFor({ state: 'visible', timeout: cfg.timeouts.actionMs });
      text = await marker.innerText();
    } catch {
      text = await page.locator('body').innerText().catch(() => '');
    }

    const result = classify(text);
    if (result.status === 'failed' || result.status === 'invalid') {
      result.screenshot = await screenshot(`voucher-${code}-${result.status}`);
    }
    return result;
  }

  return { page, context, browser, ensureLoggedIn, isLoggedIn, applyVoucher, saveSession, screenshot, close: () => browser.close() };
}
