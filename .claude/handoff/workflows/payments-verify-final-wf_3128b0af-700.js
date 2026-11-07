export const meta = {
  name: 'payments-verify-final',
  description: 'Final adversarial money verification of the payments follow-up after the f3 refund fixes (refunds/credit notes, charges/webhooks/idempotency, messages) and fix until clean — nothing goes live before this is clean',
  phases: [
    { title: 'Verify', detail: 'refunds, charges, messages — independent lenses' },
    { title: 'Fix', detail: 'fix verified issues, re-verify' },
  ],
}
const S = '/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad'
const PD = S + '/paydec'
const CTX = [
  'CONTEXT: MotoGo24. Repo /home/user/Vel-n (branch claude/moto-go-mobile-conversion-gqg5qo). Payments work D1-D6 + follow-up (read ' + PD + '/understand.md, ' + PD + '/DESIGN.md, SQL drafts ' + PD + '/sql/*.sql; edge supabase/functions/process-payment/*, process-refund/* (other-intents.ts, credit-note-sync.ts), webhook-receiver, generate-invoice, _shared/{extension-apply*,paid-change-*,booking-intents,refund-recovery,charge-rounding,duplicate-payment}.ts; web motogo-web-php/js/* + pages + lang; app both trees). Rounding: amount <= 1 Kč waived, 1 < amount < 15 Kč charged 15 Kč with an explicit rounding line (card_rounding), active only once the SQL is deployed (feature-detected).',
  'OWNER ANSWERS (2026-10-16): storno refunds the rounding pro rata; the web rounds too; a paid swap to a bike booked meanwhile -> new reservation has priority, "Motorka je mezitím obsazená", automatic refund exactly once, original booking intact, staff record in Velín.',
  'IMPORTANT HISTORY: the owner merged a WIP state of this work to production by mistake on 2026-10-22 16:43; a live bug was found (webhook charge.refunded recovery made a second full refund -> 50 % storno refunded 100 %) and the edge functions were reverted to the pre-merge state by hotfix PR #2213. This code goes live again ONLY after this verification is clean. Earlier rounds and their fixes: ' + PD + '/prev_rounds.json and the journal summaries; the last fix (f3) changed webhook-receiver recovery call (refund-recovery.ts), staffFullBalanceHaleru in other-intents.ts, credit-note-sync.ts, compare-and-set status writes — none of it re-verified yet.',
  'RULES: no git write commands; never write the live DB; SQL only as drafts in ' + PD + '/sql/ (re-test twice on local PG16 /var/tmp/pg-paydec, template = live snapshot DDL from git show origin/supabase-live-snapshot:supabase/_snapshot/schema_public.sql); feature-detect SQL; stay backward compatible with app 4.1.3 and with the CURRENT live edge (old function versions may run for a minute next to new ones during deploy); other workflows concurrently edit app v2 files (lib/core/v2/**, lib/features/*/v2/**) and ride-recording files — do not touch those. Checks: deno check/test (deno ' + S + '/denobin/deno, DENO_DIR=' + S + '/denocache; no new type errors vs baseline), php -l, node web tests in ' + PD + '/*/web, flutter analyze (' + S + '/sdk/flutter/bin/flutter; iOS only in an rsync copy with pub get --offline — never pub get in the repo iOS tree), app payment tests. Delete big temp outputs when done.',
].join('\n')
const ISSUES = { type: 'object', properties: { issues: { type: 'array', items: { type: 'object', properties: {
  severity: { type: 'string', enum: ['blocker', 'major', 'minor'] }, area: { type: 'string', enum: ['backend', 'web', 'app'] }, file: { type: 'string' }, problem: { type: 'string' }, fix: { type: 'string' } }, required: ['severity', 'area', 'file', 'problem'] } }, summary: { type: 'string' } }, required: ['issues', 'summary'] }
const VER = [
  { key: 'refunds', p: 'TASK verify:refunds (adversarial; try to make money go out wrongly). Every refund path end to end with Stripe and webhook ordering variations (webhook before/after the process-refund response, duplicates, replays, pending refunds, partial failures of the second refund): Velín full and partial cancellation (bookingMessageHelpers.js, BookingDetail.jsx confirmCancelledRefund), send-cancellation-email second dispatch, customer shortening / cheaper bike from the app and web, failed paid change auto refund, duplicate payment refund, storno after a failed swap, bookings with 1, 2 and 3 card payments + QR/cash, e-shop part bundled. Assert: never more than the price paid is refunded, never less than due without a staff notice, exactly-once under retries, credit notes == refunded amounts, payment_status correct, the f3 changes (recovery-only webhook call, staffFullBalanceHaleru, credit-note reconcile, compare-and-set) correct and not regressing earlier fixes. Write deno tests that reproduce anything you find.' },
  { key: 'charges', p: 'TASK verify:charges (adversarial). Every charge path: app booking/SOS/extension/swap/shop, web booking/edit/shop/gear rental checkout, webhook confirmations, idempotency, intent guard (payment_in_progress, fully refunded stored intents), amounts 0 / 0.5 / 1 / 1.01 / 14.99 / 15 / vouchers to 0, rounding only after SQL, documented == charged, app 4.1.3 never charged more than shown, behaviour with SQL not deployed identical to the pre-merge production (git show 550ad417:supabase/functions/...) except intended fixes. Run deno tests, PG drafts twice, app payment tests, web node tests.' },
  { key: 'ux', p: 'TASK verify:messages (adversarial, lighter): customer-facing texts and flows for the above in web + app (8 languages): refund/rounding/obsazená motorka messages truthful (promise only what happens), no contact details in error texts, no dead ends. OWNER DECISION 2026-10-22: NO customer e-mail on a failed paid change (it was removed: _shared/paid-change-customer-mail* deleted; only the internal ops e-mail to info@ stays) — check that no web/app text promises the customer an e-mail about it and nothing still references the removed module.' },
]
let active = VER.slice()
const rounds = []
for (let r = 1; r <= 4 && active.length; r++) {
  phase('Verify')
  const res = await parallel(active.map(v => () => agent(CTX + (rounds.length ? '\n\nLATEST FIX REPORT:\n' + rounds[rounds.length - 1].fix : '') + '\n\n' + v.p + '\nReturn issues with file and fix.', { label: 'verify:' + v.key + ':g' + r, phase: 'Verify', schema: ISSUES })))
  const issues = []
  res.forEach((x, i) => { if (x) for (const it of x.issues || []) issues.push({ ...it, verifier: active[i].key }) })
  const act = issues.filter(x => x.severity !== 'minor' || r === 1)
  log('round ' + r + ': ' + issues.length + ' issues, ' + act.length + ' actionable')
  rounds.push({ r, issues, summaries: res.map((x, i) => active[i].key + ': ' + (x ? x.summary : 'failed')) })
  if (!act.length) break
  phase('Fix')
  const fx = await agent(CTX + '\n\nTASK fix:g' + r + '. Re-check each issue against the current code (reject with evidence if not real), fix the real ones with the smallest safe change and a deno/node/app test that fails before and passes after, run all checks, report fixed/rejected per issue.\nISSUES:\n' + JSON.stringify(act, null, 1), { label: 'fix:g' + r, phase: 'Fix' })
  rounds[rounds.length - 1].fix = fx
  active = VER.filter(v => act.some(x => x.verifier === v.key) || v.key === 'refunds')
}
return { rounds: rounds.map(x => ({ r: x.r, n: x.issues.length, open: x.issues.filter(i => i.severity !== 'minor'), minors: x.issues.filter(i => i.severity === 'minor').map(i => i.problem.slice(0, 200)), summaries: x.summaries, fix: x.fix })) }
