// Jednorázové ruční přihlášení — otevře viditelný prohlížeč, počká až se
// přihlásíš (zvládne 2FA i captchu) a uloží session do sessions/storageState.json.
import { chromium } from 'playwright';
import fs from 'node:fs';
import path from 'node:path';
import { PATHS } from './config.mjs';
import { log } from './logger.mjs';

export async function interactiveLogin(cfg) {
  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext();
  const page = await context.newPage();

  log.info('Otevírám partner portál — přihlas se v okně prohlížeče (vč. captchy).');
  // Jdeme rovnou na dashboard: nepřihlášeného Slevomat přesměruje na login
  // a po přihlášení zpět, takže marker „Odhlásit" se objeví na správné stránce.
  await page.goto(cfg.dashboardUrl, { waitUntil: 'domcontentloaded' }).catch(() => {});

  // Čekáme až 5 minut, dokud se neobjeví prvek viditelný jen po přihlášení.
  const deadline = Date.now() + 5 * 60 * 1000;
  let loggedIn = false;
  while (Date.now() < deadline) {
    try {
      await page
        .locator(cfg.selectors.loggedInMarker)
        .first()
        .waitFor({ state: 'visible', timeout: 3000 });
      loggedIn = true;
      break;
    } catch {
      /* ještě nepřihlášen, zkoušíme dál */
    }
  }

  if (!loggedIn) {
    await browser.close();
    throw new Error(
      'Přihlášení se nepodařilo detekovat do 5 minut. Zkontroluj selektor selectors.loggedInMarker v config.json.'
    );
  }

  fs.mkdirSync(path.dirname(PATHS.session), { recursive: true });
  await context.storageState({ path: PATHS.session });
  await browser.close();
  log.ok(`Session uložena do ${PATHS.session}. Teď můžeš spouštět \`npm run run\`.`);
}
