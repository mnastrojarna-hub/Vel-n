export const meta = {
  name: 'payments-followup',
  description: 'Owner answers: storno refunds rounding pro rata (verify), web also rounds to 15 Kč, failed paid swap -> "motorka je obsazená" + automatic refund; plus a fresh money re-verification of the last fixes',
  phases: [
    { title: 'Implement', detail: 'web rounding, swap conflict refund, storno check' },
    { title: 'Verify', detail: 'money re-verification incl. previous round fixes' },
    { title: 'Fix', detail: 'fix verified issues' },
  ],
}
const S = '/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad'
const PD = S + '/paydec'
const CTX = [
  'CONTEXT: MotoGo24. Repo /home/user/Vel-n. The previous workflow implemented owner decisions D1-D6 (read ' + PD + '/understand.md, ' + PD + '/DESIGN.md and the SQL drafts ' + PD + '/sql/20261016p1..p4*.sql; edge: supabase/functions/process-payment/*, _shared/extension-apply*.ts, webhook-receiver, generate-invoice, process-refund; app both trees Motogo-app-main/motogo-app-flutter{,-ios}). Rounding rule: amount <= 1 Kč waived, 1 < amount < 15 Kč charged 15 Kč with an explicit rounding line (signed column card_rounding, folded into totals), active only once the SQL is deployed (feature-detected).',
  'OWNER ANSWERS (verbatim, 2026-10-16): "1. ano stejně 2 ano i web 3. nová rezervace má přednost tedy hláška motorka je obsazená pokud není signál doběhne to na signálu" -> (1) on cancellation the rounding is refunded pro rata like the rest (confirm the implementation does this; fix if not). (2) The WEB must round too: web booking checkout, web edit surcharges / swaps, web e-shop: <= 1 Kč waived, 1-15 Kč -> 15 Kč, shown transparently as its own line on the payment page and the Stripe Checkout page, same documents as the app. (3) If a PAID swap cannot be committed because the target bike was booked meanwhile, the new reservation has priority: the customer sees a clear message "Motorka je mezitím obsazená" (what happened + that the payment is being refunded automatically + offer another bike/keep the current one), the swap payment is refunded automatically (idempotently, exactly once), the original booking stays intact; staff get a visible record (existing admin log/alert mechanism in Velín). If the device has no signal the app queue completes when signal returns (already implemented - keep).',
  'RULES: the web reservation/shop JS (motogo-web-php/js/*, pages) was largely written by another Claude session - make minimal, well-scoped changes, keep their structure; edge changes deploy live on merge - feature-detect the SQL (no behaviour change until p1-p4 are applied) and stay backward compatible with app 4.1.3 in the field; SQL only as drafts in ' + PD + '/sql/ (update p1-p4 or add p5; tested twice on local PG16 under /var/tmp/pg-payfu with the live snapshot DDL: git show origin/supabase-live-snapshot:supabase/_snapshot/schema_public.sql); no git write commands; never write the live DB. Android tree: another workflow builds v2 UI files (lib/core/v2/**, lib/features/*/v2/**, booking_v2_*, translations_ext_5X_*) - do not edit those; app text changes in both trees via translations_ext_43_payments.dart (8 languages). Checks: deno check/test (no new errors), php -l, node tests for changed web JS, flutter analyze both trees (iOS in a scratch copy), app tests.',
].join('\n')
const ISSUES = { type: 'object', properties: { issues: { type: 'array', items: { type: 'object', properties: {
  severity: { type: 'string', enum: ['blocker', 'major', 'minor'] }, area: { type: 'string', enum: ['backend', 'web', 'app'] }, file: { type: 'string' }, problem: { type: 'string' }, fix: { type: 'string' } }, required: ['severity', 'area', 'file', 'problem'] } }, summary: { type: 'string' } }, required: ['issues', 'summary'] }

phase('Implement')
const imp = await agent(CTX + '\n\nTASK implement (1)-(3) end to end (edge, SQL drafts if needed, web, app both trees), with tests. Report every change, before -> after, and the updated SQL text summary.', { label: 'implement', phase: 'Implement' })

const VER = [
  { key: 'money', p: 'TASK verify:money (adversarial, full re-check of D1-D6 + this follow-up). Try to break: double charges (retries, two devices, app killed, webhook delay/replay, idempotency), wrong amounts (0, 0.5, 1, 1.01, 14.99, 15, vouchers to 0, negative swap net), documented == charged on every document (ZF/DP/edit DP/KF/shop) incl. web, storno pro-rata refund of rounding, swap conflict -> exactly one automatic refund + original booking intact + clear message, old app 4.1.3 never charged more than shown, behaviour unchanged while SQL is not deployed. Run deno tests, local PG with all drafts applied twice, app tests.' },
  { key: 'ux', p: 'TASK verify:messages+web (adversarial). Web and app show the rounding transparently (own line, before paying) in all 8 languages; the swap-conflict message is clear and offers next steps; no contact details in error texts; no dead ends; web Stripe Checkout line items correct; php/JS/Dart checks pass; both app trees identical except whitelist and the v2 files.' },
]
let active = VER.slice()
const rounds = []
for (let r = 1; r <= 3 && active.length; r++) {
  phase('Verify')
  const res = await parallel(active.map(v => () => agent(CTX + '\n\nIMPLEMENTATION REPORT:\n' + imp + '\n\n' + v.p + '\nReturn issues with file and fix.', { label: 'verify:' + v.key + ':r' + r, phase: 'Verify', schema: ISSUES })))
  const issues = []
  res.forEach((x, i) => { if (x) for (const it of x.issues || []) issues.push({ ...it, verifier: active[i].key }) })
  const act = issues.filter(x => x.severity !== 'minor' || r === 1)
  log('round ' + r + ': ' + issues.length + ' issues, ' + act.length + ' actionable')
  rounds.push({ r, issues, summaries: res.map((x, i) => active[i].key + ': ' + (x ? x.summary : 'failed')) })
  if (!act.length) break
  phase('Fix')
  const fx = await agent(CTX + '\n\nTASK fix. Re-check each issue, fix (backend/web/app as needed; SQL drafts re-tested twice), run all checks, report fixed/rejected.\nISSUES:\n' + JSON.stringify(act, null, 1), { label: 'fix:r' + r, phase: 'Fix' })
  rounds[rounds.length - 1].fix = fx
  active = VER.filter(v => act.some(x => x.verifier === v.key))
}
return { imp, rounds }