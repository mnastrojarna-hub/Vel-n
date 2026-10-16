export const meta = {
  name: 'app-v2-ux-review',
  description: 'Customer-perspective review of the new Android v2 app: every scenario and tab walked through (flow tests + renders), clarity/simplicity/conversion/info completeness/web parity/no dead ends; fix + re-verify',
  phases: [
    { title: 'Inventory', detail: 'master list of scenarios, tabs, features from old app + web' },
    { title: 'Walkthrough', detail: '6 scenario groups' },
    { title: 'Fix', detail: 'fix confirmed issues' },
    { title: 'Recheck', detail: 're-walk affected groups' },
  ],
}
const S = '/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad'
const A = '/home/user/Vel-n/Motogo-app-main/motogo-app-flutter'
const U = S + '/ux'
const OWNER = [
  'OWNER (verbatim, 2026-10-16): "Prioritou je samozřejmě kvalita, aby to fungovalo, nic se nerozbilo a bylo to vizuálně top. A splňovalo to hlavně kvalitu z pohledu uživatele, to znamená, bylo to jednoduchý, přehledný, mělo to vysokou konverzi, intuitivní a jednoduchý ovládání ... Aby kódy furt byly hezky v detailu, rezervace klidně mohou být duplicitně ve zprávách a všechno musí být a v notifikacích, ... jsou i kódy v pobočce, ale to klíčový prostě musí to být mega přehledný a mega jasný. Intuitivní, protože pokud to nebude jednoduchý a intuitivní, nikdo to nikdy používat nebude."',
  '"... jsou tam i trasy, to znamená naplánovat trasu, vybrat trasu, vytvořit trasu z míst ... Vytvořit vlastní trasu ... Vyčíst veškeré věci, co potřebuji vidět, detailů. Jestli trefím na smlouvy, jestli trefím na VOP. Jestli se nikde nezaseknu, jestli vím, že motorka je v samoobslužný nebo obslužný pobočce vyloženě, kde se nachází ... vím, co mám dělat, vím, co ... každá pobočka po mně chce a nechce ... aby to mělo i to, co má web, kdy nemohu někde se ztratit, zamrznout ... Jestli se mi dobře procházejí filtry, jestli můžu správně vybrat si motorku podle ceny, nebo vejšky sedla, nebo podle pobočky, ... jestli mi děkuje stránka správně, jestli tam děkovací mě odkazuje na správnou pobočku ... ta kontrola musí být uživatelský workflow, uživatelský zážitek a uživatelská přehlednost a jednoduchost. Ale současně i konverze a informace. A musí tam být všechno obsažený ... projít z pohledu uživatele všechny možný scénáře, všechny možný záložky. Nic tam není pro srandu králíku ... všechny ty věci, co tam jsou, mají nějaký smysl a v nějakém scénáři je zákazník bude potřebovat a musí je vždy správně najít."',
  'DISCLOSURE RULE (owner, verbatim 2026-10-16): "všechny klíčové informace, co zákazník bude pro třeba v rezervačním flow pro rezervaci a pro přehled ... vždycky to, co klíčový zákazník potřebuje vidět, musí být vidět vždycky na první dobrou, nesmí to být schovaný. A naopak doplňky nebo nějaké věci můžou být defaultně zabalený ... klíčový prodej je vždycky rozbalený, klíčové věci, co musí vždycky vyplnit, a naopak navíc věci ... by měly být asi pro jednoduchost spíš zabalený." -> key information (dates, bike, branch + type + address, price/total, what to do next, codes on pickup day, required inputs and blockers) and the key sales offer are ALWAYS visible and expanded at first glance; optional extras, secondary details, long texts are collapsed by default (one tap to expand). Check and fix every screen against this rule.',
].join('\n')
const CTX = [
  'NO FUNCTIONAL CHANGES (owner, verbatim 2026-10-16): "ale pozor jinak nic co se týká funkčnosti nic neměň, to bylo celkem odladěný, tak ne že to rozbiješ" -> change ONLY look, layout, disclosure and copy. Never change logic, providers, services, data flows, validation, navigation semantics or backend calls. If you find a functional bug, REPORT it (severity + evidence) instead of fixing it, unless it is a v2-UI wiring defect (the v2 screen not calling the same action as the old screen) - then make the v2 screen call exactly what the old one called.',

  'CONTEXT: the new v2 UI was implemented in the ANDROID Flutter tree ' + A + ' (lib/core/v2/**, lib/features/*/v2/**, booking_v2_*, router/app_shell wiring behind the appV2UiProvider kill-switch). iOS is untouched on purpose (owner: "iOS počká"). Design references: ' + S + '/appdesign/DESIGN_V22.md + boards ' + S + '/appdesign/project/*.dc.html; research inventories ' + S + '/appdesign/research/*.md; implementation notes ' + S + '/impl/. The OLD screens remain in the code (flag OFF) and are the truth for "what must exist". The web v2 (/home/user/Vel-n/motogo-web-php) is the UX reference.',
  OWNER,
  'HOW TO REVIEW: you cannot run a device; walk each scenario through the real code (router, screens, providers) and, wherever practical, write FLOW widget tests in ' + A + '/test/ux/ that pump the app/router with overridden providers and fake data, tap through the scenario and assert the expected screens/texts/actions appear (store screenshots of each step as goldens in ' + U + '/shots/<group>/). Judge as a customer: is the next step obvious, how many taps, is critical info (branch type self-service vs staffed, address/map, what the branch requires, codes, prices, documents/contracts/VOP) findable in <= 2 taps, any dead end/freeze/missing back, anything confusing, anything from the old app or the web missing, does every screen lead naturally toward booking (conversion) without being pushy. Severity: blocker (feature lost/broken, dead end), major (hard to find, confusing, wrong info), minor (polish).',
  'RULES: no git write commands; never write the live DB; Flutter ' + S + '/sdk/flutter/bin/flutter (analyze must stay without new issues; all tests must pass); i18n 8 languages for any text change (Android ext files); do not touch the level-up overlay or payment logic; do not touch the iOS tree.',
].join('\n')
const ISSUES = { type: 'object', properties: { issues: { type: 'array', items: { type: 'object', properties: {
  severity: { type: 'string', enum: ['blocker', 'major', 'minor'] }, area: { type: 'string', enum: ['home', 'catalog', 'booking', 'reservations', 'profile', 'routes', 'rides', 'shared'] }, scenario: { type: 'string' }, file: { type: 'string' }, problem: { type: 'string' }, fix: { type: 'string' } }, required: ['severity', 'area', 'scenario', 'problem'] } }, summary: { type: 'string' } }, required: ['issues', 'summary'] }

phase('Inventory')
const inv = await agent(CTX + `\n\nTASK inventory (read-only + ${U}/scenarios.md). Build the MASTER list of customer scenarios and features from the OLD app code (every route, tab, segment, screen, sheet, action, notification/deep link) plus the web v2 features a customer uses (calculator, filters by price / seat height / branch / licence / category / dates, branch pages with self-service procedure and requirements, FAQ, documents/VOP/contract, thank-you pages per branch). Group them into 6 walkthrough groups: (1) onboarding/auth/profile/settings/documents/contracts/VOP/invoices/messages/AI/notifications/loyalty, (2) discovery: Home (with and without booking), catalogue + every filter and sort, moto detail, calculator, branches info (self-service vs staffed, address, map, requirements), (3) booking + payment + all result/thank-you pages (correct branch info and codes timing), (4) pickup day and rental: codes in reservation detail + messages + notifications + branch screen, procedure guide, navigation, handover, SOS, extend/shorten/swap/cancel, restore-and-pay, (5) return + rating/review + history/invoices, (6) TRASY: browse/filter routes, route detail, plan a route, choose a route, create own route, create route from places, route builder, submit to community, places/POI map/detail/rating/suggest, my experiences, record a ride (start/pause/stop/save), rides with MotoGo vs private, ride detail/share. For each scenario: steps, expected info/actions, old-app location. Return the list (complete, concise).`, { label: 'inventory', phase: 'Inventory' })

const GROUPS = [1, 2, 3, 4, 5, 6]
let active = GROUPS.slice()
const rounds = []
for (let round = 1; round <= 3 && active.length; round++) {
  phase(round === 1 ? 'Walkthrough' : 'Recheck')
  const prev = rounds.length ? '\n\nRE-CHECK round ' + round + '. Previous issues + fixer report:\n' + JSON.stringify(rounds[rounds.length - 1].issues, null, 1) + '\n' + rounds[rounds.length - 1].fix : ''
  const res = await parallel(active.map(g => () => agent(CTX + '\n\nSCENARIO INVENTORY:\n' + inv + `\n\nTASK walkthrough group ${g}: walk EVERY scenario of group ${g} in the v2 UI (flag ON), in Czech plus spot checks in en, de and uk; also confirm the flag-OFF path still works for the group. Report every issue (blocker/major/minor) with area, scenario, file and a concrete fix.` + prev, { label: (round === 1 ? 'walk:' : 'recheck:') + 'g' + g + ':r' + round, phase: round === 1 ? 'Walkthrough' : 'Recheck', schema: ISSUES })))
  const issues = []
  res.forEach((x, i) => { if (x) for (const it of x.issues || []) issues.push({ ...it, group: active[i] }) })
  const act = issues.filter(x => x.severity !== 'minor' || round === 1)
  log('round ' + round + ': ' + issues.length + ' issues, ' + act.length + ' actionable')
  rounds.push({ round, issues, summaries: res.map((x, i) => 'g' + active[i] + ': ' + (x ? x.summary : 'failed')) })
  if (!act.length) break
  phase('Fix')
  const byArea = {}
  for (const it of act) (byArea[it.area] = byArea[it.area] || []).push(it)
  let fx = ''
  if (byArea.shared) fx += await agent(CTX + '\n\nTASK fix:shared. Re-check and fix (shared v2 widgets, router/app_shell wiring, cross-area), analyze + full tests, report fixed/rejected.\nISSUES:\n' + JSON.stringify(byArea.shared, null, 1), { label: 'fix:shared:r' + round, phase: 'Fix' })
  const areas = Object.keys(byArea).filter(k => k !== 'shared')
  const ar = await parallel(areas.map(k => () => agent(CTX + '\n\nTASK fix:' + k + '. Re-check and fix these issues in area ' + k + ' (report shared needs instead of editing shared files), analyze + tests (incl. the ux flow tests), report fixed/rejected.\nISSUES:\n' + JSON.stringify(byArea[k], null, 1), { label: 'fix:' + k + ':r' + round, phase: 'Fix' })))
  fx += '\n\n' + ar.map((x, i) => areas[i] + ': ' + x).join('\n\n')
  rounds[rounds.length - 1].fix = fx
  active = GROUPS.filter(g => act.some(x => x.group === g))
}
return { inv, rounds }
