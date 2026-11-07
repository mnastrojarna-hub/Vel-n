fix:i6r1: all 6 issues reproduced on 9886c117 and all 6 are fixed; none rejected. I did not implement the open owner decisions (P2–P4), wrote no SQL and touched no app files. Another workflow has already committed all my changes in its WIP commit 7c62fecf, so the working tree for `supabase/` and `velin/` is clean and equal to HEAD.

**Checks**
- `deno test supabase/functions/_tests`: 224 passed, 0 failed.
- Flow tests run directly: 109 passed. That is the previous 97 plus 12 new tests in `_tests/storno_i6r1_flow_test.ts`. The file is registered in `storno_hotfix_test.ts` and `FLOW_MIN` is raised by 12.
- Before/after: on the pre-fix tree, 11 of the 12 new tests fail. N1b is a control test and passes on both.
- `deno check` adds no new errors anywhere:

| function | baseline | now |
|---|---|---|
| process-refund | 0 | 0 |
| send-cancellation-email | 1 | 1 |
| generate-invoice | 0 | 0 |
| send-booking-email | 0 | 0 |
| fio-sync | 13 | 13 |
| webhook-receiver | 77 | 76 |
| process-payment | 98 | 97 |

  The two drops are the same old `start_date on never` error, removed by the N1 change.
- `deno lint`: clean on the new files; only the old warnings remain. `node --check` passes on `manualRefundState.js`.
- `php -l`, the web node tests and the app tests were not needed: no PHP, web or app-contract changes, and the `paydec/*/web` directories don't exist.
- Temp copies and logs are deleted.

**Per issue**
1. **W6, process-refund over-refund — fixed.**
   - New `process-refund/retry-of.ts`. `retriedLogicalRefund` reads the refunds of all payments of the booking. A request counts as a retry of an earlier refund when that refund was ours, for the same booking, reason and amount (`mg_target`), partly failed, and not yet retried.
   - For staff or service calls outside storno, the part of it that already went out is subtracted from the request. If that covers the whole request, the call answers `already_refunded` and repairs the status.
   - Every new refund now carries `mg_price` (the booking price in haléře). A request whose price differs from the newest change refund's `mg_price` is treated as a new change, not a retry. Without this, a legitimate second shortening by the same amount would have been cut and under-refunded (test W1b).
   - The ops mail now says "vraťte jen chybějících N Kč (Velín vratka na N Kč / Stripe dashboard) — celou úpravu NEopakujte…" when part of the refund went out.
2. **W2b, Velín skip — fixed.**
   - New `cancelRefundAlreadyIssued` in `manualRefundState.js` re-reads credit notes and `cancelled_at` from the DB at click time. It skips only for a live note of this storno: created no earlier than `cancelled_at` − 2 min.
   - `send-cancellation-email` now runs `docsCheck` for admin `skip_refund`+`force` calls too.
   - Both attach queries take only notes of this storno (new `stornoCnSinceIso` in `refund-split.ts`).
   - I skipped the optional "point to Stripe dashboard" mail. A dashboard refund next to a still-open storno remainder could be refunded twice by recovery.
3. **W3, stale "Vratka odeslána" — fixed.**
   - New `manualRefundSentLive` re-reads notes, payment receipts and `payment_status`, then writes compare-and-set; `BookingDetail.jsx` uses it.
   - New `process-refund/refunded-check.ts`: an admin storno request with an amount on `refunded` sums what really went back for this storno. That is our refunds on all payments, dashboard refunds made after the storno, and manual notes. If that is short, it returns 409 `refunded_status_mismatch` instead of `already_refunded`, so Velín sends no mail.
4. **W1, `newer` rule in failed-refund.ts — fixed.**
   - process-refund stamps `mg_retry_of` with the id of the refund being retried, or `'none'`. It only stamps when it could read the refunds of all payments.
   - `failedRefundState` treats a refund as superseded only by a stamped retry of the same refund (or its retry chain), and for storno only within the same storno (`mg_cancel_at`).
   - Unstamped refunds from older versions (deploy window) count only with the same amount, and only if created after the first `refund_updated_failed` log row for the failed refund.
5. **N1, payment-confirmers transport error — fixed as specified.**
   - After an RPC error it re-reads the booking. Unreadable or cancelled → `'retry'`. Already `paid` → continue as before.
   - Otherwise the fallback update adds `.neq('payment_status','paid')` and `.select('id')`; zero rows changed → `'retry'`.
6. **T1, cancelled-payment review mail — fixed.**
   - The mail is claimed with `claim_email_send` (`ops_cancelled_payment_review:<pi>`, 1-year window). If the RPC fails, the earliest log row wins.
   - If the mail fails to send, the claim (or my log row) is released and the webhook returns 500, so the redelivered event sends it. Tests T1, T1b and T1c.

**Test harness change you should know about:** `storno-harness.ts` `advance()` now also moves `bookings.cancelled_at`, `booking_cancellations.created_at` and the refunds' `mg_cancel_at` back in time. Before, notes created after a storno looked older than the storno once time was advanced. That broke four existing tests under the new "this storno's notes" windows, and it does not happen in real use. `storno-dispatch.ts` `velinConfirm` now uses the real Velín helper from the tree under test.

**Not covered by this list**
- `_tests/storno_i6v_flow_test.ts` (the refunds verifier's file, committed in that WIP snapshot, not registered in the runner): W1, W2, W2b and W3 now pass. W4 and W5 were not in this list and still fail. W6 fails only on its precondition, which expects the old mail wording ("zopakujte"); its money checks pass.
- The verifier files `storno_i5v_flow_test.ts` (R4–R7) and `storno_i5_verify_flow_test.ts` (V1, V4/V5, V8) fail exactly as before this round.
- The charges verifier's scratch tests N2–N4, T2, T4 and T5 still fail and were not in this list.
- No STATE file update: there was no SQL change, and the i4/i5 rounds did not add rows either.

Files are in /home/user/Vel-n:
- New: `supabase/functions/process-refund/retry-of.ts`, `supabase/functions/process-refund/refunded-check.ts`, `supabase/functions/_tests/storno_i6r1_flow_test.ts`
- Changed backend: `supabase/functions/process-refund/index.ts`, `supabase/functions/webhook-receiver/failed-refund.ts`, `supabase/functions/webhook-receiver/refund-updated.ts`, `supabase/functions/webhook-receiver/payment-confirmers.ts`, `supabase/functions/webhook-receiver/cancelled-payment.ts`, `supabase/functions/send-cancellation-email/index.ts`, `supabase/functions/send-cancellation-email/refund-split.ts`
- Changed tests: `supabase/functions/_tests/storno-harness.ts`, `supabase/functions/_tests/storno-dispatch.ts`, `supabase/functions/_tests/storno_hotfix_test.ts`
- Changed Velín: `velin/src/pages/booking/manualRefundState.js`, `velin/src/pages/BookingDetail.jsx`
