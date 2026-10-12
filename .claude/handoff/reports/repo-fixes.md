All five items are done. My earlier edits are already in the orchestrator's WIP commit `9166e359`; only the two STATE docs are still uncommitted.

Checks:
- **Velín build:** passes. A field-by-field compare of `pobocky.php` and the Velín defaults shows 0 differences out of 36 fields.
- **deno check:** `mcp-server` and `public-api` have 0 errors, same as `origin/main`. `ai-moto-agent` and `ai-public-agent` (they import the changed `branch-facts.ts`) each have 1 error, the same one that is already on `origin/main`.
- **Other:** `php -l` passes on `blog_fallback.php`, `agent.json` is valid JSON, and calling the edited function returns the new texts.
- **Live DB:** only one anon read (`site.policies`), no writes.

**1. `velin/src/pages/cms/webTextsPobocky.js`** — now matches `data/pobocky.php` exactly. The app's `branches_info_provider.dart` already had both sentences.
- Mezná, step 4. Before: `…(nebo si ji vyzvedneme na domluvené adrese).` After: `…(nebo si ji vyzvedneme na domluvené adrese) — mýt ani tankovat ji nemusíte.`
- Velké Němčice, step 6. Before: `…poslední den výpůjčky do 24:00. Je-li brána zavřená…` After: `…poslední den výpůjčky do 24:00. Motorku vraťte umytou a bez svítící rezervy (plnou nádrž nepotřebujete). Je-li brána zavřená…`

**2. `motogo-web-php/.well-known/agent.json`** (kept in Czech)
- `policies.fuel`. Before: `Vrácení bez povinnosti dotankovat.` After: `Obslužná pobočka Mezná (i vrácení na jiném sjednaném místě): bez povinnosti tankovat. Samoobslužná pobočka Velké Němčice: plná nádrž není potřeba, ale při vrácení nesmí svítit kontrolka rezervy paliva.`
- `policies.cleaning`. Before: `Vrácení bez povinnosti mýt; nadměrné znečištění individuálně.` After: `Obslužná pobočka Mezná (i vrácení na jiném sjednaném místě): bez povinnosti mýt, nadměrné znečištění individuálně. Samoobslužná pobočka Velké Němčice: motorku je nutné vrátit umytou.`
- `uniqueSellingPoints`. Before: `Bez povinnosti vrátit motorku natankovanou ani umytou.` After: `Vrácení v Mezné (i na jiném sjednaném místě) bez tankování i mytí; na samoobslužné pobočce Velké Němčice plná nádrž netřeba, jen umytá a bez svítící rezervy.`
- `lastUpdated`: `2026-04-26` → `2026-10-11`.
- No change needed in `ai-plugin.json`, `ai.txt`, `pages/llms-txt.php`, `pages/llms-full-txt.php`, the public-api OpenAPI or the `mcp-server` tool descriptions: none of them state a wash or refuel rule. `llms-full` pulls its return text from the `data/*-content-*` files.

**3. MCP English "mode"** — the text lives in `supabase/functions/_shared/agent-knowledge/branch-facts.ts` (`branchPublicFieldsEn`), so the change also reaches the public-api `/branches` endpoint. No code compares these strings.
- Self-service. Before: `self-service (24/7 access code, no staff)` After: `…; return: no refuelling needed (a full tank is not required), but the motorcycle must be returned washed and the fuel reserve warning light must not be on`
- Staffed. Before: `staffed (handover by staff at the booked time, nonstop)` After: `…; return (also at another agreed place): no washing and no refuelling needed`
- The doc comment above the function now mentions the return rule.

**4. Docs**
- `SUPABASE_BACKEND_STATE_5.md`, section `### header_banner`: the JSON example now includes `translations` and `translations_src`. A new "UPDATE 2026-10-11 (E)" block covers:
  - the hash convention, same as document `translation_src`;
  - the Velín flow (`DashboardBannerEditor.jsx` → `bannerI18n.js` → `cms_variables` row `app.header_banner.text` in category `general` → `translate-content`);
  - who can write: the live `cms_variables` policy allows superadmin/manager only, while `app_settings` allows any admin (`is_admin()`), so other admins save Czech only;
  - the web renderer `layout-banner.php` (every page, fresh translation only, WCAG AA contrast guarantee) and the app's `banner_provider.dart` (app language).
- `SUPABASE_BACKEND_STATE_6.md`: new top row `2026-10-11 (E)` in the existing two-column format. It covers the banner, the return-rule texts (web, app, AI, booking e-mail), the FAQ app stores, home step 3, the header edit-reservation button, and the DB text SQL marked "čeká na schválení majitele".

**5. `motogo-web-php/pages/blog_fallback.php`, line 52**
- Before: `Kdykoli během posledního dne výpůjčky. Nemusíte tankovat ani mýt. Podepíšeme předávací protokol a máte hotovo.`
- After: `Kdykoli během posledního dne výpůjčky. Na obslužné pobočce v Mezné (i při vrácení na jiném domluveném místě) nemusíte tankovat ani mýt — podepíšeme předávací protokol a máte hotovo. Na samoobslužné pobočce ve Velkých Němčicích plnou nádrž nepotřebujete, motorku ale vraťte umytou a bez svítící rezervy.`
- I found no other generic wash or reserve-light statement in the PHP or JS fallbacks. The chips "Bez tankování" / "No need to refuel" (`landing-info.php` and `lang/v2/*/info.php`) were left as they are: no refuelling is true at both branches.

Found but not changed, because these files are outside this task:
- `agent.json` and `ai.txt` still list only 7 languages (no `uk`), and `ai.txt` still says "Updated: 2026-04-26".
- The `site.policies` example in `SUPABASE_BACKEND_STATE_5.md` still says `"fuel": "Vracíš jak chceš (i prázdné). Dotankování za nákupní cenu."`. The live `site.policies` has no `fuel` key, so only the doc is stale.
- The CS `web.pobocky.branches.*.steps` rows and the `email_templates` rows in the DB override the code defaults until the pending SQL draft (`sql/owner_return_rule_*.sql` in the scratchpad) is approved and applied.