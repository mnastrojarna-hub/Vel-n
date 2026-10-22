export const meta = {
  name: 'storno-refund-hotfix',
  description: 'LIVE bug: Velín storno with partial/no refund can refund per storno table (DB trigger dispatch of send-cancellation-email without amount wins the claim) and cancellation refunds are not exactly-once — reproduce on live code, minimal edge-only hotfix on a branch from main, adversarial verify',
  phases: [
    { title: 'Reproduce', detail: 'map every cancellation path on live code, reproduce over-refunds' },
    { title: 'Fix', detail: 'minimal edge-only fix + tests in the hotfix worktree' },
    { title: 'Verify', detail: 'adversarial money + deploy-window verification, fix until clean' },
  ],
}
const S = '/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad'
const W = S + '/stornofix_wt'
const H = S + '/paydec/vrf'
const CTX = [
  'CONTEXT: MotoGo24 (Supabase edge functions in Deno, Stripe). LIVE production code = branch main; a git worktree of main is at ' + W + ' on branch claude/hotfix-storno-refund-gqg5qo (work ONLY there; do not touch /home/user/Vel-n — other workflows edit it). Merge to main auto-deploys edge functions; SQL is not part of this hotfix (edge-only; propose optional SQL separately as text).',
  'SUSPECTED LIVE BUG (found by an adversarial harness ' + H + ' — README.txt, harness.ts, fakes/, main/ = tests against main, fixtry/ = prototype fixes): DB trigger trg_notify_booking_cancelled_email (live schema: git show origin/supabase-live-snapshot:supabase/_snapshot/schema_public.sql, function notify_booking_cancelled_email) fires pg_net POST send-cancellation-email {booking_id, cancellation_reason, cancelled_by_source, source} on every status->cancelled, WITHOUT refund_amount/refund_percent. send-cancellation-email then computes the refund from the storno table (>=7 d 100 %, 2-7 d 50 %, <48 h 0 %) and calls process-refund for real, and takes claim_email_send first, so Velín\'s own explicit send-cancellation-email (with the admin-chosen amount) is skipped. Reported results on main: Velín storno 50 % -> 100 % refunded; "bez vratky" -> 100 % refunded; second dispatch of the same storno refund is not exactly-once (pending Stripe refund, webhook replay after windows, overlapping dispatches).',
  'RULES: never write to the live DB or call live APIs; no pushes, no PRs (the orchestrator does that after the owner agrees); commit in the worktree only when asked; Deno ' + S + '/denobin/deno with DENO_DIR=' + S + '/denocache; keep deno check error counts equal to main\'s baseline (process-payment 49, webhook-receiver 85, process-refund 0, send-cancellation-email: measure baseline first). Every customer-visible behaviour must stay as today except the bug (customer self-cancellations from app/web must still get exactly the storno-policy refund they get today, the Velín admin choice 0 % / partial / 100 % must be honoured exactly, Stripe portal refunds and cancellation e-mails with credit notes keep working). Consider the deploy window (new send-cancellation-email next to old process-refund and vice versa) and app 4.1.3 clients.',
].join('\n')
const ISSUES = { type: 'object', properties: { issues: { type: 'array', items: { type: 'object', properties: {
  severity: { type: 'string', enum: ['blocker', 'major', 'minor'] }, file: { type: 'string' }, problem: { type: 'string' }, fix: { type: 'string' } }, required: ['severity', 'file', 'problem'] } }, summary: { type: 'string' } }, required: ['issues', 'summary'] }

phase('Reproduce')
const rep = await agent(CTX + '\n\nTASK reproduce (independent check — do not trust the earlier report). Map EVERY path that cancels a booking or refunds a cancellation on main: Velín (velin/src/pages/booking/bookingMessageHelpers.js cancelBookingFromVelin, BookingDetail.jsx confirmCancelledRefund, Bookings list), customer cancellation from the app and web (RPC cancel_booking_tracked and any edge call after it — find exactly who triggers the refund for a customer self-cancellation today), Stripe portal / webhook charge.refunded safety net, admin/AI copilot cancellations, kiosk if any, cron jobs. For each: who calls process-refund with what amount, who calls send-cancellation-email, how claim_email_send and process-refund idempotency interact with the DB trigger dispatch, and timing (pg_net fires after commit, ~0.1-2 s). Using the harness (or your own), reproduce on main code: Velín 50 % storno, Velín 0 % storno, Velín 100 %, customer self-cancel at 10 d / 4 d / 1 d before start, pending Stripe refund, webhook replay; record real refunded amounts. Write ' + W + '/../stornofix/REPRO.md (create the dir) and return a precise summary: which scenarios over/under-refund on live code and the exact mechanism.', { label: 'reproduce', phase: 'Reproduce' })

phase('Fix')
const fix = await agent(CTX + '\n\nREPRODUCTION:\n' + rep + '\n\nTASK fix. Implement the smallest safe edge-only fix in ' + W + ' for every confirmed over-refund on live code. Requirements: (1) the trigger dispatch (no refund_amount and no refund_percent in the body) must never compute its own refund when an explicit dispatch exists or will exist — use the cancellation\'s recorded decision (booking_cancellations row written by cancel_booking_tracked in the same transaction, or by Velín right after the UPDATE — wait/retry briefly for it) and make sure customer self-cancellations still get their refund exactly once; (2) a cancellation refund is executed at most once per booking/cancellation (lock e.g. via the existing RPC claim_email_send with a dedicated slug, plus Stripe-refund-metadata based "already refunded for cancellation" check so retries/replays/pending refunds never add money); (3) the admin choice (0 % / partial / 100 %) and the e-mail text/credit note match what was actually refunded. Add deno tests (in the worktree, e.g. supabase/functions/_tests/storno_hotfix_test.ts with fakes) that FAIL on main and PASS after the fix for every reproduced scenario. Run deno check (no new errors) and the tests. Commit in the worktree with a Czech message (no push). Return what changed and test results.', { label: 'fix', phase: 'Fix' })

const VER = [
  { key: 'money', p: 'TASK verify:money (adversarial). Try to make the fixed code in ' + W + ' refund too much or too little: every cancellation path (Velín 0/partial/100 %, customer self-cancel at each storno tier, QR/bank-paid bookings, bookings with 2 card payments, unpaid bookings, already partially refunded bookings, pending Stripe refunds, webhook replays, overlapping/duplicate dispatches, pg_net retries, the trigger firing before/after Velín\'s calls, missing booking_cancellations row), and the deploy window (old/new function versions mixed). Compare with main (git -C ' + W + ' show origin/main:...) for every scenario: the fix must not change anything except the bug.' },
  { key: 'compat', p: 'TASK verify:compat (adversarial). Review the diff in ' + W + ' (git -C ' + W + ' diff origin/main): correctness, timeouts (edge function wall time when waiting for booking_cancellations), error handling, e-mail still sent exactly once with the right amount and credit note, staff notices, logs, no new type errors, tests meaningful (fail on main, pass on fix), nothing else changed.' },
]
let active = VER.slice()
const rounds = []
let last = fix
for (let r = 1; r <= 3 && active.length; r++) {
  phase('Verify')
  const res = await parallel(active.map(v => () => agent(CTX + '\n\nREPRODUCTION:\n' + rep + '\n\nLATEST FIX REPORT:\n' + last + '\n\n' + v.p + '\nReturn issues with file and fix.', { label: 'verify:' + v.key + ':r' + r, phase: 'Verify', schema: ISSUES })))
  const issues = []
  res.forEach((x, i) => { if (x) for (const it of x.issues || []) issues.push({ ...it, verifier: active[i].key }) })
  const act = issues.filter(x => x.severity !== 'minor' || r === 1)
  log('round ' + r + ': ' + issues.length + ' issues, ' + act.length + ' actionable')
  rounds.push({ r, issues, summaries: res.map((x, i) => active[i].key + ': ' + (x ? x.summary : 'failed')) })
  if (!act.length) break
  phase('Fix')
  last = await agent(CTX + '\n\nTASK fix:r' + r + '. Re-check each issue in ' + W + ' (reject with evidence if not real), fix the real ones with tests, deno check + all tests, amend nothing — add a new commit in the worktree. Report fixed/rejected.\nISSUES:\n' + JSON.stringify(act, null, 1), { label: 'fix:r' + r, phase: 'Fix' })
  rounds[rounds.length - 1].fix = last
  active = VER.slice()
}
return { rep, fix, rounds: rounds.map(x => ({ r: x.r, n: x.issues.length, open: x.issues.filter(i => i.severity !== 'minor'), summaries: x.summaries, fix: x.fix })) }
