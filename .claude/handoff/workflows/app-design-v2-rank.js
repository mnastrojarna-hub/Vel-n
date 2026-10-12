export const meta = {
  name: 'app-design-v2-rank',
  description: 'App design iteration 2: rank-driven styling, always-available AI button, Profil tab in 8 languages, personal "Sultan" home with SOS, decluttered detail; research, concept panel, build boards, adversarial verify + fix',
  phases: [
    { title: 'Understand', detail: 'rank system, personal data, nav/AI/SOS + 8-language labels' },
    { title: 'Concepts', detail: '3 home concepts, 2 judges, synthesis spec + shared snippet' },
    { title: 'Build', detail: 'Home v2, Detail declutter, other boards themed, Rank styles board' },
    { title: 'Verify', detail: 'format/logic, owner feedback, contrast/a11y, data honesty' },
    { title: 'Fix', detail: 'fix verified issues, re-verify' },
  ],
}

const S = '/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad'
const D = S + '/appdesign'
const P = D + '/project'
const R = D + '/research'
const SH = D + '/shared'

const OWNER = [
  'OWNER FEEDBACK on the first app-design canvas (verbatim Czech, then meaning):',
  '"Asi se mi ten vzhled líbí. Obecně by bylo dobrý tam víc customizovat třeba tu záři nebo záři těch tlačítek a vzhled těch tlačítek podle ranku. Víc tam zakomponovat ten rank. Obecně jak do designu, tak na tu domů, stránku domů. AI asistent asi OK, ale obecně bývá spíš jako v tom pravém dolním rohu, nebo obecně bývá k dispozici kdykoliv, protože nahoře v té lavičce by se mohl ztratit. Důležitý, že když dolů přidáš tlačítko profil, tak asi OK. Jenom to musí dávat smysl ve všech jazycích, ale smí se tam překrývat, musí to být dobře. A taky na té stránce domů potom musí se nějakým způsobem vejít jak SOS, tak případně se zaměřit hlavně jako na ty custom věci, to znamená moje trasy, moje zážitky, moje jízdy s MotoGo, moje soukromé jízdy a tak. Prostě, aby ten člověk měl pocit, že když má tu aplikaci, tak prostě celý MotoGo 24 stojí jenom na něm a prostě věnuje se mu tisíc stovky zaměstnanců, který skáčou jenom kolem něj a on je náš Sultán Suleiman. Jinak se mi hodně líbí prohlížení motorek, kdy vlastně ta motorka je celou na celou stránku. To je moc hezký. Kalkulačka může být. Zaměř se potom na ten detail, aby to nebylo nepřehledný. Jinak obecně celkem první výkop asi OK."',
  'Meaning: (1) customise the glow and the look of buttons by the customer rank; weave rank much more into the whole design and into Home. (2) AI assistant must be reachable any time, typically a floating button bottom-right - not hidden in the top bar. (3) A PROFIL tab in the bottom nav is OK, but labels must make sense and fit in all 8 languages (cs, en, de, es, fr, nl, pl, uk) - no overlap/clipping ("smí" in the quote is a speech-to-text slip for "nesmí"). (4) Home must fit SOS and focus on the personal things: my routes, my experiences, my rides with MotoGo, my private rides etc. - the customer must feel the whole company exists only for him, hundreds of staff jumping around him, he is "our Sultan Suleiman" (VIP concierge feeling). (5) Keep the full-screen bike catalogue - he loves it. Calculator stays. (6) Make the moto Detail uncluttered. (7) The rest of the first kick is OK - keep it.',
  'FOLLOW-UP from the owner (verbatim): "V detailu motorky mi přijde málo výrazný tlačítko rezervace nebo rezervovat." Meaning: (8) on the moto Detail the Reserve button is not prominent enough - make REZERVOVAT the unmistakable primary action: large, high-contrast, rank-themed glow, always visible (sticky) with the live price, clear label (e.g. REZERVOVAT · 10 189 Kč), never visually competing with secondary links or the AI button; the same principle for the catalogue card action and the Booking pay button.',
].join('\n')

const CTX = [
  'CONTEXT. MotoGo24 = motorcycle rental (staffed branch Mezná u Pelhřimova, self-service branch Velké Němčice u Brna). Customer Flutter app (two trees: Motogo-app-main/motogo-app-flutter = Android master, motogo-app-flutter-ios). Repo /home/user/Vel-n (read-only for you - do NOT edit repo files and do NOT run git write commands; another workflow is editing the repo right now). Backend docs: /home/user/Vel-n/SUPABASE_BACKEND_STATE_1..6.md. Live DB anon reads: bash ' + S + '/q.sh "<table>?select=...". Never write to the live DB.',
  'The design canvas lives in ' + P + ' (boards: Main.dc.html = Home, MotoKatalog.dc.html, MotoDetail.dc.html, Booking.dc.html, Reservation.dc.html; canvas.json lists them - do not edit canvas.json, the orchestrator does). Earlier spec: ' + S + '/appdesign_spec.md (brand tokens, price engine, rules; read sections 0-2 and 6 at least). Today in mockups = neděle 11. 10. 2026. Sample customer: rank 3 Motorkář, upcoming self-service booking Husqvarna 701 SM 16.-18. 10. at Velké Němčice (12 027 Kč), Czech UI with tykání.',
  'Live rank table loyalty_levels (level = discount %, min_booking_order, name, color_hex = colour of the rank ring around the MG logo in the app): 1 Startér #9CA3AF, 2 Jezdec #86EFAC, 3 Motorkář #4ADE80, 4 Stálý jezdec #22C55E, 5 Věrný zákazník #14B8A6, 6 Bronzový jezdec #CD7F32, 7 Stříbrný jezdec #C0C0C0, 8 Zlatý jezdec #FFD700, 9 Platinový jezdec #E5E4E2, 10 Diamantový jezdec #7DD3FC, 11 Prémiový zákazník #38BDF8, 12 Mistr silnic #3B82F6, 13 Šampion #6366F1, 14 Veterán MotoGo #8B5CF6, 15 Elitní jezdec #A855F7, 16 Ambasador #D946EF, 17 VIP #EF4444, 18 VIP Gold #D4AF37, 19 VIP Platinum #F1F5F9, 20 Legenda MotoGo #FFD700. Rank is earned by app bookings (2 points = 1 rank, see migration 20260917_loyalty_points_rank_floor_leaderboard.sql), discount only for app bookings, passenger gear + boots free from rank 3 (verify).',
  'Brand: neon green #74FB71 / gradient #8DFF86->#37CF63 on dark greens #0A1F14/#0E2A1C/#1A2E22, Montserrat. Rank styling must be an accent layered on the brand, readable (WCAG: button text >= 4.5:1, large/bold >= 3:1), and respect reduced motion.',
].join('\n')

const DCRULES = [
  'DESIGN-CANVAS FILE FORMAT (.dc.html) - follow exactly, study ' + P + '/MotoKatalog.dc.html and ' + P + '/Booking.dc.html as references:',
  '- Skeleton: <!doctype html><html lang="cs"><head><meta charset="utf-8"><title>2-4 word name</title><script src="./support.js"></script></head><body><x-dc><helmet> Google-Fonts link + one <style> </helmet> <div class="{{ rootCls }}" style="width:390px;height:<H>px;position:relative;overflow:hidden;..."> ...board... </div></x-dc><script type="text/x-dc" data-dc-script data-props=\'{...}\'> class Component extends DCLogic { constructor(props){ super(props); this.state = {...}; } renderVals(){ ...; return {...}; } } </script></body></html>',
  '- Holes {{ a.b.c }} are dotted lookups ONLY (no expressions, calls, operators, ternaries, string concat). Compute everything in renderVals. Event handlers: onClick="{{ fn }}", onInput="{{ fn }}" (fn receives the event). style="{{ x.st }}" and class="{{ x.cls }}" are fine.',
  '- Conditionals/loops: <sc-if value="{{ x }}" hint-placeholder-val="{{ true }}">...</sc-if> and <sc-for list="{{ arr }}" as="it" hint-placeholder-count="3">...</sc-for>; CSS must contain sc-if,sc-for{display:contents}.',
  '- data-props JSON: "$preview":{"width":390,"height":<H>} plus props, each {"editor":"int|enum|boolean","default":...,"section":"..."} (int has min/max, enum has options). Every board must have a "rank" int prop 1-20 (default 3) so the owner can flip ranks, plus "reducedMotion" boolean.',
  '- Only inline CSS/JS in the file; images from https://vnwnqteskbykeucanlhk.supabase.co/storage/v1/object/public/media/... (real URLs only). setTimeout ok. Interactions should feel alive (toasts, sheets, animated state changes), one primary CTA per screen.',
  '- No invented business facts: unknown values are drawn as [like this]; example user content (ride names, km) must be plausible and marked as sample where it could be mistaken for real data.',
  '- Validate before finishing: python3 ' + S + '/dclint/lint.py <file> must print LINT OK, and node ' + S + '/dclint/fuzz.js <file> \'<props json>\' must print "fuzz ok" for default props and for rank 1, 6, 10, 17, 19, 20 and reducedMotion true. Do NOT render/screenshot the boards (the runtime is not available locally).',
].join('\n')

const ISSUES = {
  type: 'object',
  properties: {
    issues: { type: 'array', items: { type: 'object', properties: {
      severity: { type: 'string', enum: ['blocker', 'major', 'minor'] },
      board: { type: 'string' },
      problem: { type: 'string' },
      fix: { type: 'string' },
    }, required: ['severity', 'board', 'problem'] } },
    summary: { type: 'string' },
  },
  required: ['issues', 'summary'],
}
const SCORE = {
  type: 'object',
  properties: {
    scores: { type: 'array', items: { type: 'object', properties: {
      concept: { type: 'string' }, total: { type: 'number' }, strengths: { type: 'string' }, weaknesses: { type: 'string' }, steal: { type: 'string' },
    }, required: ['concept', 'total', 'strengths', 'weaknesses'] } },
    winner: { type: 'string' },
    rationale: { type: 'string' },
  },
  required: ['scores', 'winner', 'rationale'],
}

phase('Understand')
const UNDERSTAND = [
  { key: 'rank', file: R + '/rank.md', prompt: `TASK understand:rank. Research the loyalty/rank system end to end: loyalty_levels (live), points and rank mechanics (STATE_3 RPCs, migrations 20260611_loyalty_ranks.sql and 20260917_loyalty_points_rank_floor_leaderboard.sql), leaderboard + monthly winners (feature flag loyalty_leaderboard), level-up overlay, rank card, ranks screen, rank_names.dart, what benefits each rank really has (discount %, free gear from which rank, anything else) and where the app shows rank today. Then propose a rank-driven visual system for the app: tier grouping of the 20 levels (e.g. green starters, metals bronze/silver/gold/platinum, jewels diamond..ambassador, VIP red/gold/platinum, Legend), per-level tokens derived from color_hex (accent, button gradient, glow colour/strength, ring, text-on-accent colour chosen for WCAG contrast - compute the ratios), tier-specific effects (e.g. metallic sheen for metals, sparkle for jewels, aurora/crown/particles for VIP+Legend), all restrained enough to stay on-brand and with reduced-motion fallbacks. Include a compact JS function sketch rankTheme(level) -> tokens and the contrast table.` },
  { key: 'personal', file: R + '/personal.md', prompt: `TASK understand:personal. Inventory everything personal the app can show a customer on Home, with real field names and where it lives: rides (features/routes/ride_model.dart UserRide - rides with a MotoGo booking (booking_id) vs private rides, stats km/time/countries), "Moje zážitky" (my_experiences_screen/provider: created routes, my places, ridden routes + stats), saved/favourite routes, community submissions, POI reviews, reservations (upcoming/active/history), documents status, messages/unread, loyalty points/rank progress/leaderboard, SOS flows (features/sos, routes /sos/*), AI agent (route /ai-agent, where it is reachable today), notifications, shop/vouchers. Check live anon-readable tables for real sample shapes (routes, places) - user-private tables are not readable, just use the schema. Output: what Home can show with existing data/features (and which screen each card opens), what would need new backend (flag clearly), and 10+ concrete "VIP concierge" touches that are backed by real data (e.g. personal greeting by nickname, 'your bike is being prepared', rank-progress nudges, anniversaries of first ride, km milestones, personal route suggestions near the booked branch).` },
  { key: 'nav', file: R + '/nav.md', prompt: `TASK understand:nav. Read the app shell/navigation (lib/core/app_shell.dart or equivalent, router), the bottom-nav tabs and their labels in all 8 languages (lib/core/i18n/translations*), where the AI assistant and SOS are reachable today (top bar? which screens?), and what the redesign canvas boards currently show (${P}/*.dc.html: nav, top bar, AI entry, SOS). Measure with Playwright (Chromium is preinstalled, PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers) the rendered width of candidate tab labels in Montserrat 800 11px uppercase (and 10.5px) for 5 equal tabs on 360 and 390 px wide phones (tab width = width/5 minus 8px padding) in cs, en, de, es, fr, nl, pl, uk - including a PROFIL tab - and propose the shortest natural label set per language that fits without truncation/overlap (existing app translations preferred). Also propose: AI floating button (bottom-right, above the nav, never covering sticky price bars/CTAs - how it moves on screens with sticky bars), and SOS quick access (where, how it avoids accidental taps). Output the label table with measured widths.` },
]
const und = await parallel(UNDERSTAND.map(u => () => agent(CTX + '\n\n' + OWNER + '\n\n' + u.prompt + `\nWrite your full findings to ${u.file} (create ${R} if needed) and return a concise summary (key facts + recommendations).`, { label: 'understand:' + u.key, phase: 'Understand' })))
const undText = UNDERSTAND.map((u, i) => '### ' + u.key + ' (full: ' + u.file + ')\n' + (und[i] || 'FAILED')).join('\n\n')

phase('Concepts')
const ANGLES = [
  { key: 'concierge', text: 'Personal concierge / butler: Home speaks to him like a private team ("Tvůj tým MotoGo"), shows what the staff is doing for him right now (bike prepared, codes ready, route suggestions), very warm and personal.' },
  { key: 'journal', text: 'Rider journal & trophies: Home is his personal riding story - my rides with MotoGo vs private rides, my routes, my places, km/country stats, milestones, rank progress as a trophy path; the company is the stage for his story.' },
  { key: 'club', text: 'Exclusive club & status: Home feels like a members-only VIP lounge whose look literally changes with rank (metal/jewel/VIP themes), status privileges, leaderboard, "only for you" offers, SOS as a white-glove assistance line.' },
]
const concepts = await parallel(ANGLES.map(a => () => agent(CTX + '\n\n' + OWNER + '\n\nRESEARCH SUMMARIES:\n' + undText + `

TASK concept:${a.key}. Write a concrete Home v2 concept from this angle: ${a.text}
It must cover every owner point: rank-driven look (glow + buttons + Home content), AI floating button bottom-right available on every screen, bottom nav with PROFIL in 8 languages, SOS fitting on Home without accidental taps, personal sections (my routes, my experiences, my rides with MotoGo, my private rides, ...), the "Sultan" feeling, keep what already works on the current Main.dc.html (read it). Give: section order top->bottom with approximate heights at 390 px, exact Czech copy (tykání), what each tap opens, which real data backs each block (from the research), animations (one-shot vs the max 2 loops), and how the look changes at rank 1, 6, 10, 17, 20. Max ~1500 words. Write it to ${D}/concepts/${a.key}.md and return it.`, { label: 'concept:' + a.key, phase: 'Concepts' })))
const conceptText = ANGLES.map((a, i) => '=== CONCEPT ' + a.key + ' ===\n' + (concepts[i] || 'FAILED')).join('\n\n')
const judges = await parallel(['owner-fit', 'craft-feasibility'].map(lens => () => agent(CTX + '\n\n' + OWNER + `

TASK judge (${lens} lens). Score the 3 Home concepts below 0-10 on: owner feedback coverage (each of the 7 points), "Sultan" VIP feeling, clarity/simplicity for an existing customer, rank integration, honesty (backed by real data/features), feasibility in Flutter with the existing app, accessibility. ${lens === 'owner-fit' ? 'Weigh owner feedback and emotional effect highest.' : 'Weigh clarity, feasibility, data honesty and accessibility highest.'} Name what to steal from runners-up.

` + conceptText, { label: 'judge:' + lens, phase: 'Concepts', schema: SCORE })))
const spec = await agent(CTX + '\n\n' + OWNER + '\n\nRESEARCH SUMMARIES:\n' + undText + '\n\nCONCEPTS:\n' + conceptText + '\n\nJUDGES:\n' + JSON.stringify(judges, null, 1) + `

TASK synthesis. Write the final design spec for iteration 2 to ${D}/DESIGN_V2.md: Home v2 (winner + grafted best ideas; section order, copy, data, taps, motion), rank theming system (tiers, per-level tokens, effects, contrast table, reduced motion), AI floating button (placement rules per screen incl. screens with sticky bars), bottom nav (5 tabs incl. PROFIL; final label table for 8 languages from the measurements), SOS access, Detail declutter plan (keep full-screen photo hero; reduce visible text/sections to the essentials with progressive disclosure - list exactly what stays visible, what collapses, what moves), and the light-touch changes for MotoKatalog/Booking/Reservation (rank-themed CTA/glow, AI button, nav). Also write the shared code that every board must paste verbatim into ${SH}/: rank-theme.css (CSS custom properties per tier/level via classes like .rk-1..rk-20 or data-driven vars, button/glow/ring styles, effects + reduced motion), rank-theme.js (a plain function rankTheme(level) returning {cls, accent, onAccent, glow, name, tier, ...} for use inside renderVals), nav.html + nav.js (bottom nav with 5 tabs, PROFIL avatar with rank ring, labels for 8 languages selectable by a "jazyk" enum prop), ai-fab.html (floating AI button + its CSS, with bottom offset variable). These snippets must comply with the DC format rules below (holes are dotted lookups only). Return a summary.

` + DCRULES, { label: 'synthesis', phase: 'Concepts' })

phase('Build')
const BUILD = [
  { key: 'Main', prompt: `Rebuild ${P}/Main.dc.html as Home v2 exactly per ${D}/DESIGN_V2.md (read it fully, plus ${SH}/*). Keep the strong parts of the current Main (ticket with codes/state switcher, calendar sheet, banner) where the spec keeps them. Props: rank (1-20), ticketState (keep existing options), jazyk (cs,en,de,es,fr,nl,pl,uk - switches at least the nav labels, AI button label/aria and SOS label), reducedMotion. Choose the board height to fit (report it).` },
  { key: 'MotoDetail', prompt: `Declutter ${P}/MotoDetail.dc.html per the Detail section of ${D}/DESIGN_V2.md: keep the full-screen photo hero and its gallery/video, keep the calculator logic and prices (they are verified: BMW 23.-25. 10. rank 3 = 10 189 Kč), but make the page calm and scannable (progressive disclosure, fewer visible blocks/text). Apply the shared rank theme to the primary CTA/sticky bar/glow and add the AI floating button (offset above the sticky bar). The owner explicitly said the reserve button on the detail is not prominent enough (point 8): the sticky bar must carry one big unmistakable REZERVOVAT primary button with the live price, rank-themed glow, nothing competing with it; the in-page calculator CTA must match it. Props: rank (rename rankLevel->rank, keep loyaltyFailed, photoFit), reducedMotion. Report the new height.` },
  { key: 'Others', prompt: `Light-touch update of ${P}/MotoKatalog.dc.html, ${P}/Booking.dc.html and ${P}/Reservation.dc.html per ${D}/DESIGN_V2.md: paste the shared rank theme (primary buttons, glow, rank chips, accents), the AI floating button (respect sticky bars: Booking summary bar, Reservation nav) and the shared bottom nav with PROFIL (catalog + reservation; booking has no nav). Keep their layouts and logic (the owner loves the full-screen catalogue - do not shrink photos). Add rank prop where missing (Reservation, keep stav), jazyk prop for nav labels where a nav exists. Prices must stay identical (Booking 10 189 Kč at rank 3; catalog BMW 23.-25. 10. = 10 189 Kč).` },
  { key: 'RankStyly', prompt: `Create a new board ${P}/RankStyly.dc.html ("Rank styly"): an overview for the owner of how the app looks per rank - all 20 levels grouped by tier, each showing the rank name, ring around the MG logo, the primary button with its glow, a secondary button, a rank chip and the Home header accent, using the shared ${SH}/rank-theme.* exactly; plus an interactive "try it" area at the top: rank slider/stepper 1-20 that re-themes a mini Home header + CTA + AI button live with the tier effect. Props: rank (default 3), reducedMotion. Width 390; choose height (report it).` },
]
const built = await parallel(BUILD.map(b => () => agent(CTX + '\n\n' + OWNER + '\n\nTASK build:' + b.key + '. ' + b.prompt + '\n\n' + DCRULES + '\nReturn: files written, final board heights, props, what changed, validation output.', { label: 'build:' + b.key, phase: 'Build' })))

const VERIFY = [
  { key: 'format', prompt: `TASK verify:format (adversarial). For every board in ${P}/*.dc.html: run python3 ${S}/dclint/lint.py and node ${S}/dclint/fuzz.js with default props and with rank 1, 3, 6, 8, 10, 13, 17, 18, 19, 20, every jazyk value, reducedMotion true, and the other enum props' values; read each file for DC format violations the linter cannot see (expression holes, missing hint attributes, handlers not functions, props not used, CSS sc-if/sc-for display:contents, absolute positions that ignore the declared height, leftover placeholders that look broken, duplicated ids). Check the shared snippet in ${SH} is pasted consistently (same rank tokens/nav/FAB in every board). Report issues with board + exact fix.` },
  { key: 'owner', prompt: `TASK verify:owner (adversarial product review). Read ${D}/DESIGN_V2.md and all boards in ${P}. For each of the 7 owner points decide with evidence (quote markup/logic) whether the boards deliver it convincingly: rank visibly drives glow + buttons + Home content at different levels; AI button bottom-right reachable on every screen and never covering the nav, sticky price bar, primary CTA or SOS; PROFIL tab + labels that make sense and fit in all 8 languages (check the label strings per language and estimated widths); Home fits SOS (no accidental taps) and puts my routes / my experiences / my rides with MotoGo / my private rides first with the "Sultan" concierge feeling; catalogue still full-screen photos; point 8: on the Detail the REZERVOVAT button is the most prominent element after the photo (size, contrast, glow, sticky, live price) and nothing competes with it; detail clearly less cluttered than before (compare with the previous version in ${D}/MotoDetail.orig.html and git-less copies if present); nothing that already worked got lost. Also flag invented business facts or features without backend. Report issues with the board and a concrete fix.` },
  { key: 'a11y', prompt: `TASK verify:a11y (adversarial). Compute WCAG contrast for every rank level's tokens as used in the boards and ${SH}/rank-theme.*: button text on button background (>= 4.5:1, or >= 3:1 if >= 18.66px bold), rank chip text, ring/accents against their backgrounds (>= 3:1 for UI components), glow not reducing legibility; check light ranks (#F1F5F9, #E5E4E2, #C0C0C0, #FFD700, #9CA3AF) and dark ones (#6366F1, #8B5CF6, #3B82F6, #EF4444). Check reduced-motion handling (prop + @media), animation count limits (max 2 infinite loops per screen), focus-visible styles, aria labels of the AI button/SOS/nav in all 8 languages, tap target sizes >= 44px. Report issues with exact fix values.` },
]

let active = VERIFY.slice()
const rounds = []
for (let round = 1; round <= 3 && active.length; round++) {
  phase('Verify')
  const prev = rounds.length ? '\n\nRe-verification round ' + round + '. Previous issues and fixer report:\n' + JSON.stringify(rounds[rounds.length - 1].issues, null, 1) + '\n' + rounds[rounds.length - 1].fix : ''
  const res = await parallel(active.map(v => () => agent(CTX + '\n\n' + OWNER + '\n\n' + v.prompt + '\n\n' + DCRULES + prev, { label: 'verify:' + v.key + ':r' + round, phase: 'Verify', schema: ISSUES })))
  const issues = []
  res.forEach((r, i) => { if (r) for (const x of r.issues || []) issues.push({ ...x, verifier: active[i].key }) })
  const actionable = issues.filter(x => x.severity !== 'minor' || round === 1)
  log('round ' + round + ': ' + issues.length + ' issues, ' + actionable.length + ' actionable')
  if (!actionable.length) { rounds.push({ round, issues, fix: 'nothing to fix', summaries: res.map(r => r && r.summary) }); break }
  phase('Fix')
  const boards = [...new Set(actionable.map(x => x.board))]
  const fixes = await parallel(boards.map(bd => () => agent(CTX + '\n\n' + OWNER + `

TASK fix:${bd}. Verifiers reported these issues for ${bd} (if the board is "shared"/"all", fix ${SH} and re-paste into every board consistently - only the agent with board "shared" or "all" may touch other boards). Re-check each issue (verifiers can be wrong), fix it, re-run lint + fuzz with all prop combinations, and report fixed/rejected with reasons.
ISSUES:
` + JSON.stringify(actionable.filter(x => x.board === bd), null, 1) + '\n\n' + DCRULES, { label: 'fix:' + bd + ':r' + round, phase: 'Fix' })))
  rounds.push({ round, issues: actionable, fix: fixes.map((f, i) => boards[i] + ': ' + f).join('\n\n') })
  const touched = new Set(actionable.map(x => x.verifier))
  active = VERIFY.filter(v => touched.has(v.key))
}

return { understand: und, concepts, judges, spec, built, rounds }