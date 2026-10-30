export const meta = {
  name: 'payments-integrate-verify',
  description: 'Payments in the dev branch: integrate the storno hotfix (#2221) with the branch payment rework (D1–D6, f1–f3) after the gear merge, fix stale tests, then adversarial money verification and fixes until clean',
  phases: [
    { title: 'Integrate', detail: 'merge hotfix branch, reconcile refund/cancellation logic, fix time-dependent tests' },
    { title: 'Verify', detail: 'refunds, charges, messages — independent lenses' },
    { title: 'Fix', detail: 'fix verified issues, re-verify' },
  ],
}
const S = '/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad'
const PD = S + '/paydec'
const R = '/home/user/Vel-n'
const CTX = [
  'CONTEXT: MotoGo24 (Supabase edge functions in Deno, Stripe, PHP web, Flutter app in two trees). Repo ' + R + ', dev branch claude/moto-go-mobile-conversion-gqg5qo (NOT deployed; merge to main = live deploy, only after this work is clean). The dev branch contains a big payments rework not yet live: owner decisions D1–D6 (read ' + PD + '/understand.md, ' + PD + '/DESIGN.md, SQL drafts ' + PD + '/sql/*.sql — card rounding to min 15 Kč with explicit line, restore-and-pay, double-charge protection, precise errors without contacts, swap completion + retry, swap-taken automatic refund, storno refunds rounding pro rata, web rounding) plus fix rounds f1–f3 (refund-recovery.ts, staffFullBalanceHaleru, credit-note-sync.ts, compare-and-set status writes). Customer e-mail on failed paid change was REMOVED by owner decision (only ops e-mail to info@).',
  'NEW SINCE: (1) main gained gear-only bookings (booking_kind gear, migrations 20261023a–f live, process-payment/gear-checkout.ts, process-refund/gear.ts, webhook-receiver/gear-docs.ts, send-cancellation-email/refund-tier.ts = Prague pickup-time tiers) and was merged into the dev branch (conflicts resolved by combining). (2) A LIVE storno hotfix is in PR #2221, branch origin/claude/hotfix-storno-refund-gqg5qo (2 commits on top of main ef0d2f4c: send-cancellation-email/trigger-dispatch.ts — trigger-shaped calls never decide money; process-refund/cancel-once.ts — cancellation refund under claim_email_send lock, mg_cancel_at metadata, already-refunded-for-this-cancellation check, duplicate admin request stop, partial→100 % confirm tops up; webhook safety-net mail with skip_refund; 24 storno flow tests). It may be merged to main any time; the dev branch must contain the SAME protections so that a later main→dev merge is trivial and nothing regresses. (3) Two f1/3 tests in supabase/functions/_tests/f1_payments_test.ts fail since 2026-10-29 because otherRefundableIntents uses Date.now() while the tests use a fixed NOW — make the code take nowMs (or the tests inject time) without changing behaviour.',
  'RULES: no git push, no PRs (the orchestrator commits/pushes); never write the live DB or call live APIs; SQL only as drafts in ' + PD + '/sql/ (re-test twice on local PG16, cluster under /var/tmp/pg-paydec or a fresh one; live schema = git show origin/supabase-live-snapshot:supabase/_snapshot/schema_public.sql plus main migrations up to 20261023f); feature-detect SQL; stay backward compatible with app 4.1.3 and with the edge versions live today (deploy window); other workflows concurrently edit app v2 files (lib/core/v2/**, lib/features/*/v2/**) — do not touch those. Checks: deno check (deno ' + S + '/denobin/deno, DENO_DIR=' + S + '/denocache; no new type errors vs baseline: process-payment 98, webhook-receiver 77, process-refund 0, send-cancellation-email 1, generate-invoice 0), deno test supabase/functions/_tests (all must pass), php -l, node web tests in ' + PD + '/*/web, flutter analyze (' + S + '/sdk/flutter/bin/flutter; Android baseline 147 / 0 errors; iOS only in an rsync copy with pub get --offline — never pub get in the repo iOS tree), app payment tests. Delete big temp outputs when done (disk is limited).',
].join('\n')
const ISSUES = { type: 'object', properties: { issues: { type: 'array', items: { type: 'object', properties: {
  severity: { type: 'string', enum: ['blocker', 'major', 'minor'] }, area: { type: 'string', enum: ['backend', 'web', 'app'] }, file: { type: 'string' }, problem: { type: 'string' }, fix: { type: 'string' } }, required: ['severity', 'area', 'file', 'problem'] } }, summary: { type: 'string' } }, required: ['issues', 'summary'] }

phase('Integrate')
const integ = await agent(CTX + '\n\nTASK integrate. In ' + R + ' (dev branch, working tree): (a) run `git merge --no-commit --no-ff origin/claude/hotfix-storno-refund-gqg5qo` (fetch first) and resolve every conflict so that BOTH the dev-branch payment rework and the hotfix protections hold (where they overlap — e.g. cancellation exactly-once in process-refund, webhook charge.refunded recovery, send-cancellation-email trigger dispatch — produce one coherent design; keep the hotfix 24 storno flow tests passing, adapting fakes if the dev branch changed signatures). Do NOT commit (the orchestrator commits). If the merge cannot be completed cleanly, abort it (git merge --abort) and port the hotfix changes manually with the same effect. (b) Fix the 2 time-dependent f1/3 tests. (c) Run all checks listed in RULES. Report what was merged/reconciled per file, design decisions, and check results.', { label: 'integrate', phase: 'Integrate' })

const VER = [
  { key: 'refunds', p: 'TASK verify:refunds (adversarial; try to make money go out wrongly). Every refund and cancellation path end to end with Stripe/webhook ordering variations (webhook before/after the process-refund response, duplicates, replays after lock windows, pending refunds, partial failures of a second refund, process-refund crash after Stripe refund): Velín full/partial/0 % storno (bookingMessageHelpers.js, BookingDetail.jsx confirmCancelledRefund incl. partial→100 %), the DB trigger dispatch of send-cancellation-email, customer cancel via cancel_booking_tracked, bulk/AI cancel, customer shortening/cheaper bike from app and web, failed paid change auto refund, duplicate payment refund, storno after a failed swap, bookings with 1/2/3 card payments + QR/cash, e-shop part bundled, gear-only bookings. Assert: never more than paid is refunded, never less than due without a staff notice, exactly once under retries, credit notes == refunded, payment_status correct, the hotfix scenarios still pass. Use or extend the existing harnesses (' + S + '/paydec/vrf, ' + S + '/stornofix/repro2) and the deno tests.' },
  { key: 'charges', p: 'TASK verify:charges (adversarial). Every charge path: app booking/SOS/extension/swap/shop, web booking/edit/shop/gear rental checkout, webhook confirmations, idempotency, intent guard (payment_in_progress, fully refunded stored intents), currency (must be CZK server-side, not client-controlled — known open issue), amounts 0 / 0.5 / 1 / 1.01 / 14.99 / 15 / vouchers to 0, rounding only after SQL, documented == charged, app 4.1.3 never charged more than shown, behaviour with SQL not deployed identical to live main except intended fixes (compare git show origin/main:supabase/functions/...). Run deno tests, PG drafts twice, app payment tests, web node tests.' },
  { key: 'ux', p: 'TASK verify:messages (adversarial, lighter): customer-facing texts and flows in web + app (8 languages): refund/rounding/"Motorka je mezitím obsazená" messages truthful (promise only what happens — no customer e-mail about a failed paid change), no contact details in error texts, no dead ends; staff (Velín) sees what happened.' },
]
let active = VER.slice()
const rounds = []
let last = integ
for (let r = 1; r <= 4 && active.length; r++) {
  phase('Verify')
  const res = await parallel(active.map(v => () => agent(CTX + '\n\nLATEST REPORT (integration or fix):\n' + last + '\n\n' + v.p + '\nReturn issues with file and fix.', { label: 'verify:' + v.key + ':i' + r, phase: 'Verify', schema: ISSUES })))
  const issues = []
  res.forEach((x, i) => { if (x) for (const it of x.issues || []) issues.push({ ...it, verifier: active[i].key }) })
  const act = issues.filter(x => x.severity !== 'minor' || r === 1)
  log('round ' + r + ': ' + issues.length + ' issues, ' + act.length + ' actionable')
  rounds.push({ r, issues, summaries: res.map((x, i) => active[i].key + ': ' + (x ? x.summary : 'failed')) })
  if (!act.length) break
  phase('Fix')
  last = await agent(CTX + '\n\nTASK fix:i' + r + '. Re-check each issue against the current code (reject with evidence if not real), fix the real ones with the smallest safe change and a test that fails before and passes after, run all checks, report fixed/rejected per issue.\nISSUES:\n' + JSON.stringify(act, null, 1), { label: 'fix:i' + r, phase: 'Fix' })
  rounds[rounds.length - 1].fix = last
  active = VER.filter(v => act.some(x => x.verifier === v.key) || v.key === 'refunds')
}
return { integ, rounds: rounds.map(x => ({ r: x.r, n: x.issues.length, open: x.issues.filter(i => i.severity !== 'minor'), minors: x.issues.filter(i => i.severity === 'minor').map(i => i.problem.slice(0, 200)), summaries: x.summaries, fix: x.fix })) }
