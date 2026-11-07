export const meta = {
  name: 'payments-followup-finish',
  description: 'Finish the payments follow-up (storno pro rata, web 15 Kč rounding, swap taken + automatic refund): fix the last open UX issues, full money re-verification, fix until clean',
  phases: [
    { title: 'Fix', detail: 'last open issues from verify:ux round 3' },
    { title: 'Verify', detail: 'money + messages/web adversarial re-check' },
  ],
}
const S = '/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad'
const PD = S + '/paydec'
const CTX = [
  'CONTEXT: MotoGo24. Repo /home/user/Vel-n (branch claude/moto-go-mobile-conversion-gqg5qo). A previous workflow implemented owner decisions D1-D6 (read ' + PD + '/understand.md, ' + PD + '/DESIGN.md and the SQL drafts ' + PD + '/sql/*.sql; edge: supabase/functions/process-payment/*, _shared/extension-apply*.ts, _shared/paid-change-failure.ts, _shared/booking-intents.ts, webhook-receiver, generate-invoice, process-refund; web motogo-web-php/js/* + pages + lang/*.php; app both trees Motogo-app-main/motogo-app-flutter{,-ios}). Rounding rule: amount <= 1 Kč waived, 1 < amount < 15 Kč charged 15 Kč with an explicit rounding line (signed column card_rounding, folded into totals), active only once the SQL is deployed (feature-detected).',
  'OWNER ANSWERS (verbatim, 2026-10-16): "1. ano stejně 2 ano i web 3. nová rezervace má přednost tedy hláška motorka je obsazená pokud není signál doběhne to na signálu" -> (1) on cancellation the rounding is refunded pro rata like the rest. (2) The WEB rounds too (booking checkout, edit surcharges/swaps, e-shop), shown transparently as its own line before paying and on Stripe Checkout, same documents as the app. (3) A PAID swap that cannot be committed because the target bike was booked meanwhile: the new reservation has priority; the customer sees "Motorka je mezitím obsazená" (what happened + payment refunded automatically + choose another bike / keep the current one), the swap payment is refunded automatically exactly once, the original booking stays intact, staff get a visible record in Velín; offline app queue completes when signal returns.',
  'HISTORY: a disk-full incident interrupted the first run; all earlier verify/fix reports are in ' + PD + '/prev_rounds.json (read them: issues already fixed, rejected, and the open ones). A later run must not re-break what earlier rounds fixed.',
  'RULES: the web reservation/shop JS was largely written by another Claude session — minimal, well-scoped changes, keep their structure; edge changes deploy live on merge — feature-detect the SQL (no behaviour change until the drafts are applied) and stay backward compatible with app 4.1.3 in the field; SQL only as drafts in ' + PD + '/sql/ (tested twice on a local PG16 cluster under /var/tmp/pg-paydec or a fresh one, live snapshot DDL: git show origin/supabase-live-snapshot:supabase/_snapshot/schema_public.sql); no git write commands; never write the live DB. Android tree: other workflows concurrently edit v2 UI files (lib/core/v2/**, lib/features/*/v2/**, booking_v2_*, translations_ext_5X_*) and ride-recording files — do not edit those; app payment texts in both trees via translations_ext_43_payments.dart (8 languages). Checks: deno check/test (DENO: ' + S + '/denobin/deno, DENO_DIR=' + S + '/denocache; no new errors vs baseline), php -l, node tests for changed web JS, flutter analyze both trees (Flutter ' + S + '/sdk/flutter/bin/flutter; Android baseline 147 / 0 errors; iOS ONLY in an rsync copy under ' + PD + '/ioscopy with pub get --offline there — the iOS .dart_tool is tracked in git, never run pub get in the repo iOS tree), app payment tests. Disk is limited — delete big temp outputs when done.',
].join('\n')
const ISSUES = { type: 'object', properties: { issues: { type: 'array', items: { type: 'object', properties: {
  severity: { type: 'string', enum: ['blocker', 'major', 'minor'] }, area: { type: 'string', enum: ['backend', 'web', 'app'] }, file: { type: 'string' }, problem: { type: 'string' }, fix: { type: 'string' } }, required: ['severity', 'area', 'file', 'problem'] } }, summary: { type: 'string' } }, required: ['issues', 'summary'] }

phase('Fix')
const first = await agent(CTX + '\n\nTASK fix:open. In ' + PD + '/prev_rounds.json take the LAST verification (label verify:ux:r3) and any issue of earlier rounds that the fix reports did not close. Re-check each against the current code (reject with evidence if not real), fix the real ones (majors and minors), run all checks, report fixed/rejected per issue.', { label: 'fix:open', phase: 'Fix' })

const VER = [
  { key: 'money', p: 'TASK verify:money (adversarial, full re-check of D1-D6 + this follow-up — the previous money re-check never finished). Try to break: double charges (retries, two devices, app killed, webhook delay/replay, idempotency), wrong amounts (0, 0.5, 1, 1.01, 14.99, 15, vouchers to 0, negative swap net), documented == charged on every document (ZF/DP/edit DP/KF/shop) incl. web, storno pro-rata refund of rounding, storno after a failed swap refunds from the right payment, swap conflict -> exactly one automatic refund + original booking intact (no booking field written on failure — e.g. web guard.js must not write pickup_time/late_pickup_discount_amount when the server reports a failed change) + clear message, old app 4.1.3 never charged more than shown, behaviour unchanged while SQL is not deployed. Run deno tests, local PG with all drafts applied twice, app tests, web node tests.' },
  { key: 'ux', p: 'TASK verify:messages+web (adversarial). Web and app show the rounding transparently (own line, before paying — incl. the web extension/edit preview from guard.js) in all 8 languages; Stripe Checkout line items correct and localised; the swap-conflict message is clear and offers next steps in web and app; refund texts promise only what is actually sent; no contact details in error texts; no dead ends; php/JS/Dart checks pass; both app trees identical except the CLAUDE.md whitelist and v2 files.' },
]
let active = VER.slice()
const rounds = []
for (let r = 1; r <= 3 && active.length; r++) {
  phase('Verify')
  const res = await parallel(active.map(v => () => agent(CTX + '\n\nLATEST FIX REPORT:\n' + (rounds.length ? rounds[rounds.length - 1].fix : first) + '\n\n' + v.p + '\nReturn issues with file and fix.', { label: 'verify:' + v.key + ':f' + r, phase: 'Verify', schema: ISSUES })))
  const issues = []
  res.forEach((x, i) => { if (x) for (const it of x.issues || []) issues.push({ ...it, verifier: active[i].key }) })
  const act = issues.filter(x => x.severity !== 'minor' || r === 1)
  log('round ' + r + ': ' + issues.length + ' issues, ' + act.length + ' actionable')
  rounds.push({ r, issues, summaries: res.map((x, i) => active[i].key + ': ' + (x ? x.summary : 'failed')) })
  if (!act.length) break
  phase('Fix')
  const fx = await agent(CTX + '\n\nTASK fix:f' + r + '. Re-check each issue, fix (backend/web/app as needed; SQL drafts re-tested twice), run all checks, report fixed/rejected per issue.\nISSUES:\n' + JSON.stringify(act, null, 1), { label: 'fix:f' + r, phase: 'Fix' })
  rounds[rounds.length - 1].fix = fx
  active = VER.filter(v => act.some(x => x.verifier === v.key))
}
return { first, rounds: rounds.map(x => ({ r: x.r, n: x.issues.length, open: x.issues.filter(i => i.severity !== 'minor'), summaries: x.summaries, fix: x.fix })) }
