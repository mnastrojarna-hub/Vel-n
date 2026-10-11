export const meta = {
  name: 'owner-answers-finish',
  description: 'Finish owner answers: final DB text SQL (for owner approval), repo leftovers, mobile overflow, completeness sweep, adversarial verify + fix loop',
  phases: [
    { title: 'Build', detail: 'SQL finalize, repo leftovers, mobile overflow, 3 completeness sweeps' },
    { title: 'Extend', detail: 'apply sweep findings to repo, then to SQL' },
    { title: 'Verify', detail: 'SQL replay, language QA, build/smoke, layout' },
    { title: 'Fix', detail: 'fix verified issues, re-verify affected areas' },
  ],
}

const S = '/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad'
const CTX = [
  'CONTEXT. Repo: /home/user/Vel-n (branch claude/moto-go-mobile-conversion-gqg5qo, already merged with origin/main; origin/main = base before the owner-answer work). Scratchpad S=' + S + '.',
  'HARD RULES:',
  '- Do NOT run any git command that writes (commit, stash, checkout, reset, restore, merge, rebase, worktree add, clean, apply). Read-only git (status, diff, show, log, archive into S) is fine. The orchestrator commits.',
  '- NEVER write to the live Supabase DB. Live reads only via anon REST: bash ' + S + '/q.sh "<table>?select=...&limit=1000&offset=N" (max 1000 rows per request, paginate). RPC: POST to /rest/v1/rpc/<fn> with the anon key from ' + S + '/anon.key.',
  '- No new files in the repo root. Working files go under ' + S + '/<your-own-dir>.',
  '- Several agents work in the same working tree at the same time. Touch ONLY files your task names; if something else needs changing, put it in your report instead.',
  '- The two Flutter trees (Motogo-app-main/motogo-app-flutter and motogo-app-flutter-ios) must stay identical except the CLAUDE.md whitelist.',
  '- Do not change UX/UI/flow beyond what the task says. Keep files under ~5000 tokens where technically possible.',
  'OWNER RULE (verbatim, 2026-10-11): "Mytí ani tankování není třeba na obslužné pobočce. Na samoobsluze není potřeba tankovat. To důležité je pouze, aby motorka byla umytá a nesvítila rezerva."',
  'Applied as: staffed branch Mezná u Pelhřimova (also returns at another agreed place = delivery/collection service run from Mezná) -> no washing and no refuelling. Self-service branch Velké Němčice u Brna -> no refuelling / full tank not needed, BUT the bike must be returned washed and the fuel-reserve warning light must not be on. Never state a generic "no washing" or a generic "reserve light must be off" without the branch distinction. (Whether the reserve light also matters at Mezná is an open owner question - texts must not claim it does.)',
  'Other owner answers to keep consistent: the MotoGo24 app is on Google Play (Android) AND the App Store (iPhone) - say both wherever app download is mentioned; home "step 3" (pick-up) must mention both branches incl. self-service Velké Němčice; the app header banner (app_settings.header_banner) is shown on top of every web page in all languages.',
  'Languages: cs, en, de, es, fr, nl, pl, uk. Czech register: keep what the surrounding text uses (web mostly tykání; documents, branch guides and some pages vykání).',
  'TOOLS: PHP dev server: PHP_CLI_SERVER_WORKERS=4 php -S 127.0.0.1:<PORT> -t /home/user/Vel-n/motogo-web-php ' + S + '/router.php (router.php hardcodes $root = repo web dir; for a base copy make your own router with another $root). Append ?nc=<n> to bypass the 10-min page cache. Base copy of the web: git archive origin/main motogo-web-php | tar -x -C ' + S + '/<dir>. Playwright + Chromium are preinstalled (PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers; example scripts in ' + S + ' such as ovf.js, shot.js). Postgres 16: /usr/lib/postgresql/16/bin (init clusters under /var/tmp/<name>, never under /tmp/claude-0 - postgres cannot read it). Flutter: ' + S + '/sdk/flutter/bin/flutter. Deno: ' + S + '/denobin/deno with DENO_DIR=' + S + '/denocache. Velín build: copy velin/src into ' + S + '/velin-build/src and run npm run build there. Kiosk venv: /var/tmp/kvenv.',
].join('\n')

const FINDINGS = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          kind: { type: 'string', enum: ['repo', 'db'] },
          location: { type: 'string', description: 'file:line or table/key/id' },
          lang: { type: 'string' },
          current: { type: 'string' },
          problem: { type: 'string' },
          proposed: { type: 'string' },
          severity: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
        required: ['kind', 'location', 'problem', 'severity'],
      },
    },
    notes: { type: 'string' },
  },
  required: ['findings'],
}

const ISSUES = {
  type: 'object',
  properties: {
    issues: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          severity: { type: 'string', enum: ['blocker', 'major', 'minor'] },
          area: { type: 'string', enum: ['sql', 'repo'] },
          location: { type: 'string' },
          problem: { type: 'string' },
          fix: { type: 'string' },
        },
        required: ['severity', 'area', 'location', 'problem'],
      },
    },
    summary: { type: 'string' },
  },
  required: ['issues', 'summary'],
}

const SQL_PROMPT = CTX + `

TASK sql-final: turn the drafted DB-text SQL into final, deployable migration files. They must NOT go into the repo yet (the owner approves SQL as text first) - write them to ${S}/sql/final/.
Inputs (read first): ${S}/sql/m3a_owner_texts.sql (4 independent DO blocks: cms_variables, faq_items, app_settings pages_overlay, header_banner translations), its generator ${S}/dbsql/tools/ (spec.py, gen.py, template.sql, leafdiff.py), notes ${S}/notes/owner-dbsql.md; ${S}/sql/owner_return_rule_pobocky_steps.sql and ${S}/sql/owner_return_rule_email_templates.sql with notes ${S}/notes/owner-ai-app-mail.md.
Known gaps to fix:
1. pages_overlay jak_pujcit_postup / pl / process.steps.11.text still has the old "oddaj go umytego". Every overlay value must equal the CURRENT string in motogo-web-php/lang/pages_<lang>.php - regenerate against the current tree.
2. Check every new value for typos (the earlier report quoted "ke stažein").
3. cms_variables web.jak_pujcit_dokumenty.handover.items.0 ("Převzetí probíhá v Pelhřimově (Mezná 9) nebo využij přistavení.") omits the self-service branch Velké Němčice. Update the CMS row (cs + all translations) AND the PHP fallbacks holding that string (motogo-web-php/data/*.php, lang/pages_<lang>.php, lang/v2/* - you may edit exactly that key in those files) AND the matching pages_overlay leaves; keep the page's register.
4. Re-download ALL live rows the SQL touches (cms_variables paginated, faq_items, app_settings) into ${S}/sql/final/live/ and compare with ${S}/dbsql/live/. Migration 20261011_i18n_customer_language was deployed today 09:33 UTC; if any row changed, regenerate. Every guard must match today's live text.
5. web.pobocky.branches.{0,1}.steps: new text byte-equal to motogo-web-php/data/pobocky.php and to features/branches/branches_info_provider.dart (both app trees). Check how web and app read translations of these keys; if translations are absent today, keep absent but report.
6. Also make sure supabase/functions/translate-pages-master/master_cs.ts values for every changed page key equal the current PHP strings (Velín "Přeložit vše naráz" regenerates overlays from it) - you may edit only those values.
Output: split into self-contained migrations each about 5000 tokens max (~15 kB), named to sort after the newest file in supabase/migrations (now 20261011f_...), e.g. 20261011g_owner_texts_cms.sql, 20261011h_owner_texts_faq.sql, 20261011i_owner_texts_overlay[_x].sql, 20261011j_owner_texts_banner.sql, 20261011k_owner_texts_pobocky_steps.sql, 20261011l_owner_texts_email_templates.sql. Each file: runs inside deploy-sql.yml's single transaction with ON_ERROR_STOP (no BEGIN/COMMIT/VACUUM/CONCURRENTLY), idempotent (2nd run changes nothing), changes only rows whose text still equals the verified live wording (else RAISE NOTICE and skip), never touches other keys/leaves, starts with a Czech header comment (what/why, owner rule quote, date 2026-10-11, "datová migrace").
Test: local PG16 cluster (reuse /var/tmp/pg-dbsql port 55447 or init a new one); tables with the real column types/triggers (real DDL in ${S}/schema_public_snap.sql or ${S}/schema_public.sql); load the fresh live rows; apply all files in LC_ALL=C order exactly like psql --single-transaction -v ON_ERROR_STOP=1 -f <file>, twice. Leaf diff must show exactly the intended leaves; run 2 = 0 changes; negative test (row edited in Velín) skipped.
Write ${S}/sql/final/PREHLED.md in Czech for the owner: per file, every changed text before -> after (cs + en), row counts, what is intentionally not changed, open questions (from the notes), and the VOP čl. 5 l) / rental contract wording proposals from owner-dbsql.md marked as NOT applied (binding documents need explicit owner approval; changing content_html invalidates translation_src translations until re-translated).
Report: files + sizes, test results, unresolved items, list of repo files you edited.`

const REPO_PROMPT = CTX + `

TASK repo-fixes (verify each item first, fix minimal):
1. velin/src/pages/cms/webTextsPobocky.js drifted from motogo-web-php/data/pobocky.php (the 2 new return-rule sentences in branch steps). Sync the Velín defaults with data/pobocky.php exactly. Velín build must pass.
2. motogo-web-php/.well-known/agent.json and any llms.txt / ai-plugin / OpenAPI / agent descriptions under motogo-web-php or supabase/functions that state the return rule generically ("no refuel, no wash") - make them branch-specific per the owner rule (keep each file's language).
3. supabase/functions/mcp-server: the English branch "mode" text lacks the return rule while "mode_cs" has it - add it consistently with facts.ts. deno check must not add errors (compare with origin/main counts).
4. Docs: SUPABASE_BACKEND_STATE_5.md (section for app_settings header_banner; grep where header_banner is described in STATE_1..6): document the new keys translations {lang: text} and translations_src (sha1 hex of the UTF-8 text, same convention as document translation_src), the Velín flow (DashboardBannerEditor.jsx -> bannerI18n.js -> carrier row cms_variables key app.header_banner.text, category general, translated via translate-content; only superadmin/manager may write cms_variables, others save Czech only), the web renderer motogo-web-php/layout-banner.php (top of every page, fresh translation only, contrast guarantee) and the app banner_provider.dart (app language). Add a STATE_6 changelog row "2026-10-11 (E)" summarising: banner on web + translations; return-rule texts (web, app, AI, booking e-mail); FAQ app stores; home step 3 both branches; header edit-reservation button; DB text SQL "čeká na schválení majitele". Follow the existing table format.
5. motogo-web-php/pages/blog_fallback.php (around line 52) and any other PHP fallback stating a generic return rule outside a clear Mezná context - make it branch-specific.
Do NOT edit lang/pages_*.php, data/*-content-*.php or master_cs.ts (owned by the SQL agent this round). Report every change before -> after.`

const LAYOUT_PROMPT = CTX + `

TASK mobile-overflow (use ports 8131 = current tree, 8132 = base copy of origin/main). Earlier QA reported horizontal page overflow: at 320-360 px on uk/de/nl pages because the header top bar (header-tools incl. the new animated "Správa rezervace / Upravit rezervaci" button: css/header-editrez.css + layout.php) is too wide (uk ~61 px at 320); de home .lp-cat; uk/de /pobocky comparison table TH and .pb-badge; ?landing=v1 at 768 px en/uk/de .gbox; and a ~36 px header layout shift at 768 px from header-tools/header-editrez.
1. Measure current vs base for 8 languages x pages (home, catalog list, one catalog detail, /pobocky, both branch detail pages, kontakt, rezervace, the edit-reservation page, jak-pujcit pages, poukazy, faq) x widths 320, 360, 390, 414, 768, 1024, 1366: documentElement.scrollWidth > innerWidth and the offending elements; header CLS.
2. Fix every overflow and the header shift with minimal CSS in the affected components' CSS files (and layout.php markup only if unavoidable). The edit-reservation button must stay clearly visible, labelled and animated on mobile and desktop (explicit owner request) - you may compact it (smaller padding, label wrapping, shorter label variant) only if in all 8 languages it stays obvious what it is. No other content/UX changes.
3. Re-measure: 0 overflow on all combinations (document anything impossible). Save before/after screenshots of the header at 320/390/1366 in cs/de/uk to ${S}/ovf/shots/.
Report files changed and before -> after metrics.`

const SWEEPS = [
  { key: 'repo-text', prompt: CTX + `

TASK sweep repo-text (READ-ONLY, change nothing). Find every remaining statement in the repo that contradicts or omits the owner answers: (a) the return rule (look in all 8 languages: tank/tankovat/nádrž/plná nádrž/umyt/umýt/mytí/nemyj/rezerv/kontrolka; refuel/full tank/wash/reserve light; tanken/Tank/waschen/Reserve; repostar/depósito/lleno/lavar/reserva; plein/réservoir/laver/réserve; tanken/volle tank/wassen/reservelampje; tankować/bak/umyć/rezerwa; заправ/бак/мити/помити/резерв); (b) app download mentions without App Store/iPhone; (c) pick-up/branch statements that present Pelhřimov/Mezná as the only pick-up place where the self-service branch Velké Němčice should be mentioned (home step 3 equivalents, "kde si motorku vyzvednu" FAQs, AI facts). Scope: motogo-web-php (all PHP/JS/JSON/txt), both Flutter trees lib/, supabase/functions (all), raspberry/motogo-box (ui texts, i18n), velin customer-facing defaults (e-mail/document/web text defaults), .well-known, llms.txt. Skip node_modules, dist, build outputs, migrations history. Report ONLY real contradictions/omissions with exact file:line, lang, current text, a precise proposed replacement in that language and register.` },
  { key: 'db', prompt: CTX + `

TASK sweep db (READ-ONLY). Scan the live DB (anon REST) for texts contradicting the owner answers (return rule, app stores, both pick-up branches): cms_variables (ALL rows, paginate; value + translations in all languages), faq_items (all langs), app_settings (all keys incl. pages_overlay.*, site.*, header_banner, any AI/agent config), branches (notes, descriptions, translations, opening texts), blog/article tables (find names in SUPABASE_BACKEND_STATE_1.md), motorcycles text columns + translations, routes descriptions if they mention return, message/notification templates readable by anon, document templates via RPC get_document_translation for each document type and language if anon can call it, ai_public_agent_config. Then compare with the drafts ${S}/sql/m3a_owner_texts.sql, ${S}/sql/owner_return_rule_pobocky_steps.sql, ${S}/sql/owner_return_rule_email_templates.sql and report ONLY what those drafts do NOT already cover, with exact table/key/id/lang, current text, proposed replacement (same language/register). Binding legal documents (VOP, contracts): report but mark "owner approval needed".` },
  { key: 'flows', prompt: CTX + `

TASK sweep flows (READ-ONLY; PHP server on port 8121). Walk through what a customer actually sees in each of the 8 languages about (1) returning the bike (washing/fuel/reserve per branch), (2) where to get the app (Android + iPhone), (3) where the bike can be picked up (Mezná + self-service Velké Němčice + delivery): rendered web pages (home v2 and ?landing=v1, půjčovna, pobočky + both branch pages, all jak-pujcit pages, faq, kontakt, katalog detail, rezervace and its confirmation/payment-result texts, poukazy), booking e-mails (render supabase/functions/send-booking-email templates for every type), AI knowledge (supabase/functions/_shared/agent-knowledge, ai-moto-agent booking context, mcp-server facts), the app (both trees: branches info, help/FAQ, booking success, onboarding, reservation detail), kiosk UI texts (raspberry/motogo-box ui). Report every place where the info is wrong, missing where a customer would clearly need it, or inconsistent across languages/channels; give exact location + proposed text. Distinguish repo (kind=repo) from DB-sourced text (kind=db; find the cms key/table).` },
]

const VERIFY = [
  { key: 'sql', prompt: CTX + `

TASK verify:sql (adversarial - try hard to find real defects; report only with evidence). Independently replay the final migrations in ${S}/sql/final/*.sql: own PG16 cluster /var/tmp/pg-vsql (port 55461); fetch live rows fresh (paginate); tables with the real DDL from ${S}/schema_public_snap.sql incl. triggers for the touched tables; apply in LC_ALL=C order with psql --single-transaction -v ON_ERROR_STOP=1 -f, twice; diff leaves. Check: each file ~5000 tokens max, Czech header, no BEGIN/COMMIT, guards correct and skip with NOTICE, idempotent, JSON structure preserved (lists not replaced wholesale, value types kept), no other keys touched; banner translations_src = sha1 hex of the exact UTF-8 text; overlay values byte-equal to current lang/pages_<lang>.php strings and master_cs.ts values equal to current Czech PHP strings; filenames sort after the newest repo migration and do not collide; what DB triggers on cms_variables/faq_items/app_settings/email_templates do when these run (see SUPABASE_BACKEND_STATE_4.md) and whether that is OK on deploy; every new text obeys the owner rule and other answers in all 8 languages; PREHLED.md is accurate and complete. Return issues (area sql unless the defect is in a repo file).` },
  { key: 'lang', prompt: CTX + `

TASK verify:lang (adversarial native-level QA). Review every customer-facing text changed on this branch vs origin/main (git diff origin/main plus uncommitted working-tree changes in motogo-web-php, supabase/functions, Motogo-app-main, velin, raspberry) AND every new value in ${S}/sql/final/*.sql, in all 8 languages: grammar, spelling, natural phrasing, register consistent with neighbouring text, correct branch attribution per the owner rule, consistent terminology (reserve light), no ambiguity (e.g. Spanish "depósito" also means deposit), no untranslated Czech except proper names, same meaning across languages. Report each issue with exact file/key/lang and the corrected text (area repo or sql).` },
  { key: 'build', prompt: CTX + `

TASK verify:build (adversarial engineering check; port 8141). For git diff origin/main plus the working tree: php -l every changed PHP file; PHP smoke for 8 languages x key pages (home, ?landing=v1, katalog, a katalog detail, pobocky, both branch pages, kontakt, rezervace, edit-reservation page, jak-pujcit pages, poukazy, faq) -> HTTP 200, no PHP warnings/notices in the server log, exactly one top banner, header edit-reservation button present; flutter analyze both trees (baseline Android 193 issues / iOS 184 issues, 0 errors - nothing new) and diff -rq of the two lib/ dirs shows only CLAUDE.md-whitelisted files; deno check every changed edge function vs origin/main counts; Velín build passes; raspberry untouched (else run pytest in /var/tmp/kvenv). Read the whole diff for unintended changes, debug leftovers, broken HTML/JSON, files that grew past ~5000 tokens, secrets. Return issues (area repo).` },
  { key: 'layout', prompt: CTX + `

TASK verify:layout (adversarial; ports 8151 current, 8152 base copy of origin/main). Playwright at 320, 360, 390, 414, 768, 1024, 1366 x 8 languages x key pages (home, catalog, catalog detail, pobocky, both branch pages, kontakt, rezervace, edit-reservation page, jak-pujcit pages, faq): horizontal overflow, top banner + header incl. the animated edit-reservation button (visible, labelled, not clipped, animation present, keyboard focusable), overlapping/clipped text, header CLS. Compare with base to separate pre-existing from new problems; report new ones and any remaining pre-existing overflow at >= 320 px. Return issues (area repo) with element selectors and measurements.` },
]

phase('Build')
const built = await parallel([
  () => agent(SQL_PROMPT, { label: 'build:sql-final', phase: 'Build' }),
  () => agent(REPO_PROMPT, { label: 'build:repo-fixes', phase: 'Build' }),
  () => agent(LAYOUT_PROMPT, { label: 'build:mobile-overflow', phase: 'Build' }),
  ...SWEEPS.map(s => () => agent(s.prompt, { label: 'sweep:' + s.key, phase: 'Build', schema: FINDINGS })),
])
const [sqlRep, repoRep, layoutRep] = built
const sweepRes = built.slice(3)
const seen = new Set()
const findings = []
sweepRes.forEach((r, i) => {
  if (!r) { log('sweep ' + SWEEPS[i].key + ' returned nothing'); return }
  for (const f of r.findings || []) {
    const k = (f.kind + '|' + f.location + '|' + (f.lang || '')).toLowerCase()
    if (seen.has(k)) continue
    seen.add(k)
    findings.push({ ...f, sweep: SWEEPS[i].key })
  }
})
const repoF = findings.filter(f => f.kind === 'repo')
const dbF = findings.filter(f => f.kind === 'db')
log('sweeps: ' + findings.length + ' unique findings (' + repoF.length + ' repo, ' + dbF.length + ' db)')

phase('Extend')
let repoFixRep = 'no repo findings'
if (repoF.length) {
  repoFixRep = await agent(CTX + `

TASK extend:repo. Completeness sweeps found these repo findings (JSON below). Other agents may already have fixed some. For each: re-check the current file, decide if it is real, and apply a minimal fix in every affected language (keep register; keep both app trees identical; you MAY now edit lang/pages_*.php, data/*.php and master_cs.ts). Run the relevant checks (php -l; flutter analyze both trees if Dart changed - baseline Android 193 / iOS 184 issues, 0 errors; deno check vs origin/main counts; Velín build if velin changed). Do not touch ${S}/sql/final. In your report list applied/rejected (with reason) per finding, and a section "SQL MUST MIRROR" listing every string you changed that also lives in the DB (cms_variables key, pages_overlay leaf, faq) or in master_cs.ts.
FINDINGS:
` + JSON.stringify(repoF, null, 1), { label: 'extend:repo', phase: 'Extend' })
}
const sqlExtRep = await agent(CTX + `

TASK extend:sql. The final SQL set is in ${S}/sql/final/ (built by the sql-final agent; its report below). Extend/regenerate it so it also covers (a) every DB finding below that you confirm against fresh live data (reject false positives with a reason; binding VOP/contract texts are NOT changed - add them to PREHLED.md as proposals only), and (b) every string listed under "SQL MUST MIRROR" in the repo-fix report (overlay leaves and CMS values must equal the current PHP strings; master_cs.ts values must equal the current Czech PHP strings - you may edit only those values in master_cs.ts). Keep the same file rules (about 5000 tokens per file, guarded, idempotent, single-transaction safe, Czech header). Re-run the full local test (two runs, leaf diff, negative test) and update PREHLED.md. Report what changed.
SQL-FINAL REPORT:
` + String(sqlRep) + `
REPO-FIX REPORT:
` + String(repoFixRep) + `
DB FINDINGS:
` + JSON.stringify(dbF, null, 1), { label: 'extend:sql', phase: 'Extend' })

let active = VERIFY.slice()
const rounds = []
for (let round = 1; round <= 3 && active.length; round++) {
  phase('Verify')
  const prev = rounds.length ? '\n\nThis is re-verification round ' + round + '. Previous round issues and the fixer report:\n' + JSON.stringify(rounds[rounds.length - 1].issues, null, 1) + '\nFIXER REPORT:\n' + rounds[rounds.length - 1].fix : ''
  const res = await parallel(active.map(v => () => agent(v.prompt + prev, { label: 'verify:' + v.key + ':r' + round, phase: 'Verify', schema: ISSUES })))
  const issues = []
  res.forEach((r, i) => { if (r) for (const x of r.issues || []) issues.push({ ...x, verifier: active[i].key }) })
  const summaries = res.map((r, i) => ({ verifier: active[i].key, summary: r ? r.summary : 'agent failed' }))
  const actionable = issues.filter(x => x.severity !== 'minor' || round === 1)
  log('round ' + round + ': ' + issues.length + ' issues, ' + actionable.length + ' actionable')
  if (!actionable.length) { rounds.push({ round, issues, summaries, fix: 'nothing to fix' }); break }
  phase('Fix')
  const repoIssues = actionable.filter(x => x.area === 'repo')
  const sqlIssues = actionable.filter(x => x.area === 'sql')
  let fixRep = ''
  if (repoIssues.length) {
    fixRep += await agent(CTX + `

TASK fix:repo. Verifiers reported these issues (JSON). For each: re-check that it is real (verifiers can be wrong), then fix minimally and run the relevant checks (php -l, PHP smoke of the touched pages, flutter analyze both trees + diff -rq, deno check, Velín build, Playwright overflow re-measure for layout issues). List fixed/rejected with reasons, plus "SQL MUST MIRROR" for any changed string that also lives in the DB or master_cs.ts.
ISSUES:
` + JSON.stringify(repoIssues, null, 1), { label: 'fix:repo:r' + round, phase: 'Fix' })
  }
  if (sqlIssues.length || /SQL MUST MIRROR[\s\S]*\S/.test(fixRep)) {
    fixRep += '\n\n' + await agent(CTX + `

TASK fix:sql. Fix these issues in ${S}/sql/final/ (re-check each first; reject with reason if wrong) and mirror any changed repo strings listed below; re-run the full local test (two runs, leaf diff, negative test) and update PREHLED.md. Report fixed/rejected.
ISSUES:
` + JSON.stringify(sqlIssues, null, 1) + `
REPO FIX REPORT (for SQL MUST MIRROR):
` + fixRep, { label: 'fix:sql:r' + round, phase: 'Fix' })
  }
  rounds.push({ round, issues: actionable, summaries, fix: fixRep })
  const touched = new Set(actionable.map(x => x.verifier))
  active = VERIFY.filter(v => touched.has(v.key))
}

return { sqlRep, repoRep, layoutRep, findings, repoFixRep, sqlExtRep, rounds }