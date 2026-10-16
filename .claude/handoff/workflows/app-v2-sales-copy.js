export const meta = {
  name: 'app-v2-sales-copy',
  description: 'Sales-minded microcopy pass for the Android v2 app: find every selling moment, rewrite benefit-led honest Czech copy (the "dessert" principle), native adaptation to 7 languages, fit/honesty/tone checks; fix loop',
  phases: [
    { title: 'Map', detail: 'selling moments + facts' },
    { title: 'Write', detail: 'Czech copy, then 7 languages' },
    { title: 'Verify', detail: 'honesty, fit in UI, tone, translations' },
    { title: 'Fix', detail: 'fix confirmed issues' },
  ],
}
const S = '/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad'
const A = '/home/user/Vel-n/Motogo-app-main/motogo-app-flutter'
const C = S + '/copy'
const OWNER = 'OWNER (verbatim, 2026-10-16): "když vidím třeba trasy v okolích Velké Němčice, tak bylo by tam spíš lepší něco, nevíte kam vyrazit? Využijte našich tras v okolí. A podobně. ... když ... v restauraci ... se zeptám, a dáte si ještě desert, no tak mi uživatel řekne ne. Ale když se zeptám správně a řekne, vaříme vynikající desert. Z jablíček ..., domácí těsto a úžasná skořice ... Mohu vám dva přinést? Tak uživatel spíš řekne ano. Tak v tomhle duchu potřebuju každou službu dobře jako naplánovat a prodat. V té aplikaci jako prodat je asi to správný slovo." Earlier owner priorities still apply: simple, clear, intuitive, premium; conversion matters; customers are existing customers with ranks; nothing pushy or fake.'
const CTX = [
  'NO FUNCTIONAL CHANGES (owner, verbatim 2026-10-16): "ale pozor jinak nic co se týká funkčnosti nic neměň, to bylo celkem odladěný, tak ne že to rozbiješ" -> change ONLY look, layout, disclosure and copy. Never change logic, providers, services, data flows, validation, navigation semantics or backend calls. If you find a functional bug, REPORT it (severity + evidence) instead of fixing it, unless it is a v2-UI wiring defect (the v2 screen not calling the same action as the old screen) - then make the v2 screen call exactly what the old one called.',

  'DISCLOSURE RULE (owner, verbatim 2026-10-16): "všechny klíčové informace, co zákazník bude pro třeba v rezervačním flow pro rezervaci a pro přehled ... vždycky to, co klíčový zákazník potřebuje vidět, musí být vidět vždycky na první dobrou, nesmí to být schovaný. A naopak doplňky nebo nějaké věci můžou být defaultně zabalený ... klíčový prodej je vždycky rozbalený, klíčové věci, co musí vždycky vyplnit, a naopak navíc věci ... by měly být asi pro jednoduchost spíš zabalený." -> key information (dates, bike, branch + type + address, price/total, what to do next, codes on pickup day, required inputs and blockers) and the key sales offer are ALWAYS visible and expanded at first glance; optional extras, secondary details, long texts are collapsed by default (one tap to expand). Check and fix every screen against this rule.',

  'CONTEXT: the new v2 UI lives in the ANDROID Flutter tree ' + A + ' (lib/core/v2/**, lib/features/*/v2/**, booking_v2_*, texts in lib/core/i18n/translations_ext_5X_*.dart). iOS is untouched on purpose. Czech is tykání. 8 languages: cs, en, de, es, fr, nl, pl, uk.',
  OWNER,
  'COPY PRINCIPLES ("the dessert"): lead with the customer benefit and a concrete, sensory, true detail; make yes easy (one clear action, pre-filled choice where the app already supports it); ask, do not command; short enough for the UI (headings <= ~6 words, sublines <= ~14 words, buttons 1-3 words); warm, confident, premium, never pushy, never guilt or fake scarcity; never invent facts - use only real data (route names/km/photos, branch facts incl. self-service vs staffed, rank benefits/discounts, gear included, no deposit, nonstop, prices from the engine, owner facts in supabase/functions/_shared/agent-knowledge/owner-facts.ts and SUPABASE_BACKEND_STATE docs). Legal/binding texts (contracts, VOP, consents, procedure steps procStep*/gateCodeHint, payment/error explanations) are NOT sales copy - keep them exact.',
  'RULES: no git write commands; never write the live DB; edit only the v2 translation ext files (and add new keys there if a moment needs a subline) plus the minimal v2 widget changes to show a new subline/variant; do not touch level-up overlay, payment logic, iOS tree; Flutter ' + S + '/sdk/flutter/bin/flutter analyze (no new issues) and all tests must pass (incl. the 8-language render tests - texts must fit at 320 and 360 px).',
].join('\n')
const ISSUES = { type: 'object', properties: { issues: { type: 'array', items: { type: 'object', properties: {
  severity: { type: 'string', enum: ['blocker', 'major', 'minor'] }, lang: { type: 'string' }, key: { type: 'string' }, problem: { type: 'string' }, fix: { type: 'string' } }, required: ['severity', 'key', 'problem'] } }, summary: { type: 'string' } }, required: ['issues', 'summary'] }

phase('Map')
const map = await agent(CTX + `\n\nTASK map (read-only + ${C}/moments.md). Walk every v2 screen and list every SELLING MOMENT: section headings and sublines, empty states, CTAs and secondary actions, upsells and cross-sells (passenger gear, boots, trailer, delivery from Mezná, longer rental / weekday prices, late-pickup half-day, extend rental, calculator, vouchers/gift, shop, AI assistant, record a ride, routes near the customer's branch, places, community routes, rank progress and benefits, reviews "Napiš nám recenzi", Home funnel without a booking, branch pages self-service vs staffed). For each: screen, i18n key(s), current Czech text, what the customer gains, which REAL facts can make it irresistible (cite source), and the risk of sounding pushy. Exclude legal/procedure/payment-error texts. Return the list.`, { label: 'map', phase: 'Map' })

phase('Write')
const cs = await agent(CTX + '\n\nMOMENTS:\n' + map + `\n\nTASK write:cs. Rewrite the Czech copy of every selling moment following the dessert principle (example: "Trasy v okolí Velkých Němčic" -> heading "Nevíš, kam vyrazit?" + subline "Projeď naše oblíbené trasy kolem Velkých Němčic - Pálava, vinné sklepy, zatáčky jak na dráze" only if those facts are true for the listed routes). Keep it short and premium; one action per moment. Edit the cs values in the v2 ext files (add sublines/keys where needed and wire them minimally). Write ${C}/cs_changes.md (key: before -> after, facts used + source). Run analyze + tests. Return the change list.`, { label: 'write:cs', phase: 'Write' })
const tr = await agent(CTX + '\n\nCZECH CHANGES:\n' + cs + `\n\nTASK write:translations. Adapt every changed/new key natively into en, de, es, fr, nl, pl, uk (transcreation, not literal: same benefit, same facts, natural idiom, the register each language's app texts already use, same brevity so it fits). Write ${C}/translations.md. Run analyze + the 8-language render tests. Return the change list.`, { label: 'write:translations', phase: 'Write' })

const VER = [
  { key: 'honesty', p: 'TASK verify:honesty (adversarial). Every claim in the new copy (all 8 languages) must be true: check against real data (routes and their places/km, branch facts, rank benefits, prices/discounts, gear, delivery only from Mezná, self-service rules, owner facts). Flag invented details, overpromises, fake urgency, anything that could mislead (consumer law) or contradicts the app elsewhere.' },
  { key: 'craft', p: 'TASK verify:craft (adversarial copy chief). Does each moment follow the dessert principle (benefit + concrete detail + easy yes) without being pushy; is it short and clear enough for the UI; consistent voice and terminology across screens; Czech grammar and tykání; native quality of each translation (en, de, es, fr, nl, pl, uk) - no literal calques; texts fit at 320/360 px (run the render tests and look at goldens). Give concrete better wording where weak.' },
]
let active = VER.slice()
const rounds = []
for (let r = 1; r <= 3 && active.length; r++) {
  phase('Verify')
  const res = await parallel(active.map(v => () => agent(CTX + '\n\nCZECH:\n' + cs + '\n\nTRANSLATIONS:\n' + tr + '\n\n' + v.p + '\nReturn issues with key, lang and fix.', { label: 'verify:' + v.key + ':r' + r, phase: 'Verify', schema: ISSUES })))
  const issues = []
  res.forEach((x, i) => { if (x) for (const it of x.issues || []) issues.push({ ...it, verifier: active[i].key }) })
  const act = issues.filter(x => x.severity !== 'minor' || r === 1)
  log('round ' + r + ': ' + issues.length + ' issues, ' + act.length + ' actionable')
  rounds.push({ r, issues, summaries: res.map((x, i) => active[i].key + ': ' + (x ? x.summary : 'failed')) })
  if (!act.length) break
  phase('Fix')
  const fx = await agent(CTX + '\n\nTASK fix. Re-check each issue, fix the copy in all affected languages, run analyze + render tests, report fixed/rejected.\nISSUES:\n' + JSON.stringify(act, null, 1), { label: 'fix:r' + r, phase: 'Fix' })
  rounds[rounds.length - 1].fix = fx
  active = VER.filter(v => act.some(x => x.verifier === v.key))
}
return { map, cs, tr, rounds }
