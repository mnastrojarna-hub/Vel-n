export const meta = {
  name: 'app-v2-android-impl',
  description: 'Implement the approved app redesign (DESIGN_V22) in the ANDROID Flutter tree only, behind a remote kill-switch, keeping every function; 8-language render tests; adversarial verify + fix; release prep',
  phases: [
    { title: 'Plan', detail: 'architect: file-level implementation plan' },
    { title: 'Foundation', detail: 'theme, rank ramp, motion, shared widgets, nav, AI FAB, back button, flag' },
    { title: 'Screens', detail: 'parallel per feature area' },
    { title: 'Integrate', detail: 'router/shell, i18n registration, analyze, tests' },
    { title: 'Verify', detail: 'parity, i18n/layout renders, code, design fidelity' },
    { title: 'Fix', detail: 'fix verified issues, re-verify' },
  ],
}
const S = '/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad'
const D = S + '/appdesign'
const A = '/home/user/Vel-n/Motogo-app-main/motogo-app-flutter'
const IMP = S + '/impl'
const CTX = [
  'CONTEXT: MotoGo24 customer Flutter app. Implement the new UI ONLY in the ANDROID tree ' + A + '. The owner explicitly said (2026-10-16): "iOS počká, ať neposereme vše najednou" - do NOT touch Motogo-app-main/motogo-app-flutter-ios (it will be ported later). The approved design: ' + D + '/DESIGN_V22.md (+ DESIGN_V21.md, DESIGN_V2.md, ' + S + '/appdesign_spec.md for the price engine/content table) and the interactive boards ' + D + '/project/*.dc.html (HTML/CSS/JS mockups - read their markup/CSS for exact spacing, colours, motion; shared tokens in ' + D + '/shared/). Research inventories: ' + D + '/research/*.md (profile, trasy, states, rank ramp, surface balance).',
  'OWNER REQUIREMENTS (non-negotiable): we only change the LOOK - all functionality must stay exactly as it works today ("vše musí být funkční tak jak bylo a to bez chyb ... nic nesmí chybět"); every screen premium, simple, clear, animated (reduced-motion safe); clearly visible back/close on every screen + system back works; every error/result state meaningful (what/why/how to fix + working action), nothing hangs; rank drives the look (20-level ramp, no pink/purple, monotonic prestige, Legenda fiery gold); bottom nav with PROFIL that never overlaps in any of the 8 languages; AI floating button bottom-right never covering bars/CTAs; Home without a booking = booking funnel; standalone calculator like the web; "Zaznamenat jízdu" prominent; calendar range all days uniformly green; light/white surfaces where many elements, dark heroes where photos; review card with "Napiš nám recenzi" (Google) and "Napiš nám přímo, co máme zlepšit"; the existing LEVEL-UP CELEBRATION (features/loyalty/loyalty_levelup_overlay.dart) must NOT be changed at all.',
  'DO NOT CHANGE BEHAVIOUR: providers, services, Supabase calls, booking submit, pricing engine, payment logic (payment platform files keep their logic - only wrap/restyle their UI), routing semantics/deep links, push, offline guard logic, auth, documents logic. Restyle and recompose widgets; when a screen is rebuilt, re-use the same providers/actions. Keep files under ~5000 tokens (split into new widget files). New UI lives under lib/core/v2/ (shared) and lib/features/<area>/v2/ (screens), gated by a kill-switch: provider appV2UiProvider reading feature flag "app_v2_ui" via the existing lib/core/feature_flags.dart (row absent => ON, explicit false => OFF so the owner can instantly revert without a release); the old screens stay intact and are used when the flag is OFF.',
  'i18n: every new user-facing string in all 8 languages (cs, en, de, es, fr, nl, pl, uk), natural wording, Czech tykání; new keys only in NEW translation ext files (translations_ext_5X_<area>.dart) registered in lib/core/i18n/translations.dart by the integration step. RULES: no git write commands (orchestrator commits); never write to the live DB; no new packages unless already in pubspec (check); Flutter SDK ' + S + '/sdk/flutter/bin/flutter (analyze baseline 193 issues, 0 errors - nothing new); there is no Android SDK here (no APK build) - rely on analyze + flutter test; work dirs under ' + IMP + '/<key>.',
].join('\n')
const ISSUES = { type: 'object', properties: { issues: { type: 'array', items: { type: 'object', properties: {
  severity: { type: 'string', enum: ['blocker', 'major', 'minor'] }, area: { type: 'string' }, file: { type: 'string' }, problem: { type: 'string' }, fix: { type: 'string' } }, required: ['severity', 'area', 'file', 'problem'] } }, summary: { type: 'string' } }, required: ['issues', 'summary'] }

phase('Plan')
const plan = await agent(CTX + `

TASK plan (read-only except ${IMP}/PLAN.md). Read the design docs and boards and the whole current app (lib/core, lib/features, router, app_shell, theme). Write ${IMP}/PLAN.md: (1) shared foundation files to create under lib/core/v2/ (tokens: colours incl. light surfaces, typography, radii, shadows; motion + reduced motion; rank theme from loyalty_levels.color_hex with the new ramp + tier effects + on-accent text by contrast; widgets: primary/secondary buttons with rank glow + shine, back/close button standard, cards, sheets, chips, segmented, stat tiles, calendar range day cell, AI FAB with offset rules, bottom nav v2 with 5 tabs + labels per language measured to fit, page scaffold with light/dark surface sections, result/state screen scaffold); (2) per feature AREA the exact screens/routes to re-skin, which existing providers/actions each uses, new file names, and what must be preserved (content-preservation checklist per screen from ${D}/research and appdesign_spec.md section 11); areas: home, catalog (list + detail + standalone calculator), booking (core/booking_form_widget.dart + sections + payment screen UI + success/result states), reservations (list, detail, edit chooser + focused edit screens UI, cancel, SOS entry), profile (profile hub + sub-screens, documents, contracts/invoices, loyalty screens except the level-up overlay, messages + AI entry, settings), routes (Trasy hub, route detail, navigation UI, builder, submit, places + POI), rides (my experiences, rides, ride detail, recorder incl. "Zaznamenat jízdu"); (3) the kill-switch wiring and how old/new screens are selected in router/app_shell; (4) i18n file per area; (5) test plan: widget tests that pump every new screen with fake providers in all 8 languages at 360x780 and 412x915 and fail on overflow/exception, plus golden PNGs saved to ${IMP}/shots for human review; (6) risks and forbidden files. Return a summary.`, { label: 'plan', phase: 'Plan' })

phase('Foundation')
const found = await agent(CTX + '\n\nPLAN SUMMARY:\n' + plan + `

TASK foundation. Implement section (1) and (3) of ${IMP}/PLAN.md in ${A}: lib/core/v2/** shared tokens, rank theme (20-level ramp, tier effects, contrast-based on-accent text; colours read from the existing loyalty provider with the new ramp as fallback), motion utils, all shared widgets, bottom nav v2 (labels fit in all 8 languages - add a widget test that pumps it at 320/360/412 px in every language and asserts no overflow), AI FAB, back button, page/state scaffolds, and appV2UiProvider kill-switch. Write widget tests for the shared widgets. flutter analyze (no new issues) + flutter test must pass. Do not wire screens into the router yet. Report created files and APIs (constructor signatures) other agents must use.`, { label: 'foundation', phase: 'Foundation' })

phase('Screens')
const AREAS = ['home', 'catalog', 'booking', 'reservations', 'profile', 'routes', 'rides']
const screens = await parallel(AREAS.map(a => () => agent(CTX + '\n\nPLAN SUMMARY:\n' + plan + '\n\nFOUNDATION REPORT (use these shared APIs, do not modify lib/core/v2 - report needed changes instead):\n' + found + `

TASK screens:${a}. Implement the v2 screens of area "${a}" exactly per ${IMP}/PLAN.md section (2) and the design (DESIGN_V22.md + the matching boards). Only create/edit files of your area (lib/features/<area>/v2/** and, for booking, new files next to core/booking_form_widget.dart named booking_v2_*.dart) plus your own translation ext file; do NOT edit router.dart, app_shell.dart, translations.dart or other areas' files (list wiring needs in your report). Reuse existing providers/actions unchanged; preserve every piece of information and every action of the old screens (write the checklist mapping old -> new in your report). Add widget tests pumping each new screen with fake/overridden providers in all 8 languages at 360x780 and 412x915 (fail on overflow or exception) and save golden PNGs to ${IMP}/shots/${a}/. flutter analyze (no new issues) and your tests must pass. Return: files, wiring needs (routes, tabs, flag switches), checklist, test results.`, { label: 'screens:' + a, phase: 'Screens' })))

phase('Integrate')
const integ = await agent(CTX + '\n\nFOUNDATION:\n' + found + '\n\nAREA REPORTS:\n' + screens.map((s, i) => '=== ' + AREAS[i] + '\n' + s).join('\n\n') + `

TASK integrate. Wire everything: router.dart / app_shell.dart select v2 screens when appV2UiProvider is ON and the old ones when OFF (deep links, notification routes and back behaviour identical in both modes); register all new translation ext files in translations.dart; resolve cross-area wiring needs; make sure the level-up overlay and payment platform logic are untouched (git diff must show no changes in features/loyalty/loyalty_levelup_overlay.dart and in payment logic); update /home/user/Vel-n/CLAUDE.md "Appka: dva stromy" with a TEMPORARY exception: the v2 UI (lib/core/v2/**, lib/features/*/v2/**, booking_v2_*, translations_ext_5X_*, router/app_shell flag wiring) exists only in the Android tree until the owner approves the iOS port - do not sync it to iOS meanwhile; everything else keeps the sync rule. Bump the Android pubspec version to 4.2.0 (keep the +build number pattern). flutter analyze (no new issues vs 193 baseline) and the full flutter test suite must pass. Report.`, { label: 'integrate', phase: 'Integrate' })

const VERIFY = [
  { key: 'parity', p: 'TASK verify:parity (adversarial). For every screen of the old app (old files unchanged) compare with its v2 counterpart: every information, action, navigation target, state (empty/loading/error/offline) and edge case present and wired to the SAME providers/actions; booking + payment + edit + cancel + SOS + documents + rides flows behave identically (read the code paths end to end); kill-switch OFF restores the old UI completely; deep links/notifications land correctly in both modes; back works everywhere. Report every gap.' },
  { key: 'render', p: 'TASK verify:render (adversarial). Run the full flutter test suite; additionally write/extend tests that pump EVERY v2 screen and sub-state (incl. result/error states, sheets, dialogs) in all 8 languages at 320x690, 360x780 and 412x915 with large text (textScaleFactor 1.3) and reduced motion; fail on any overflow, clipped text, exception or missing translation key; save goldens to ' + IMP + '/shots/verify and inspect a sample montage per language yourself. Report every failure with screen/language/size.' },
  { key: 'code', p: 'TASK verify:code (adversarial engineering review of git diff in ' + A + '): flutter analyze (no new issues), no changes to forbidden files (level-up overlay, payment logic, providers/services semantics, iOS tree untouched), memory/animation leaks (controllers disposed, tickers), performance (no heavy rebuilds, images cached), null-safety, mounted checks, accessibility (semantics labels, 44 px targets, contrast), file sizes, dead code, i18n completeness.' },
  { key: 'design', p: 'TASK verify:design (adversarial). Compare the implemented screens (goldens in ' + IMP + '/shots) with the boards and DESIGN_V22.md: rank ramp correct for levels 1, 6, 10, 13, 17, 19, 20 (no look-alikes, no pink/purple), light/dark surface balance, calendar range uniform green, back buttons visible, AI FAB placement, bottom nav labels, REZERVOVAT prominence, review card wording, funnel Home without booking, calculator, "Zaznamenat jízdu", premium polish. Report deviations with file and fix.' },
]
let active = VERIFY.slice()
const rounds = []
for (let r = 1; r <= 3 && active.length; r++) {
  phase('Verify')
  const res = await parallel(active.map(v => () => agent(CTX + '\n\nINTEGRATION REPORT:\n' + integ + '\n\n' + v.p + '\nReturn issues with file and fix.', { label: 'verify:' + v.key + ':r' + r, phase: 'Verify', schema: ISSUES })))
  const issues = []
  res.forEach((x, i) => { if (x) for (const it of x.issues || []) issues.push({ ...it, verifier: active[i].key }) })
  const act = issues.filter(x => x.severity !== 'minor' || r === 1)
  log('round ' + r + ': ' + issues.length + ' issues, ' + act.length + ' actionable')
  rounds.push({ r, issues, summaries: res.map((x, i) => active[i].key + ': ' + (x ? x.summary : 'failed')) })
  if (!act.length) break
  phase('Fix')
  const byArea = {}
  for (const it of act) { const k = (it.area || 'shared').toLowerCase(); (byArea[k] = byArea[k] || []).push(it) }
  const keys = Object.keys(byArea)
  const shared = keys.filter(k => !AREAS.includes(k))
  const sharedIssues = shared.flatMap(k => byArea[k])
  let fixRep = ''
  if (sharedIssues.length) fixRep += await agent(CTX + '\n\nTASK fix:shared. Re-check and fix these issues (shared/foundation/integration/cross-area), run analyze + full tests, report fixed/rejected.\nISSUES:\n' + JSON.stringify(sharedIssues, null, 1), { label: 'fix:shared:r' + r, phase: 'Fix' })
  const areaKeys = keys.filter(k => AREAS.includes(k))
  const areaRes = await parallel(areaKeys.map(k => () => agent(CTX + '\n\nTASK fix:' + k + '. Re-check and fix these issues in area ' + k + ' only (report needed shared changes instead of making them), run analyze + your tests, report fixed/rejected.\nISSUES:\n' + JSON.stringify(byArea[k], null, 1), { label: 'fix:' + k + ':r' + r, phase: 'Fix' })))
  fixRep += '\n\n' + areaRes.map((x, i) => areaKeys[i] + ': ' + x).join('\n\n')
  rounds[rounds.length - 1].fix = fixRep
  active = VERIFY.filter(v => act.some(x => x.verifier === v.key))
}
return { plan, found, screens, integ, rounds }
