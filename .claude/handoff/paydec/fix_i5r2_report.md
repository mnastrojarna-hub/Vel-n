fix:i5r2: all 5 issues are real on 03a2d1dc and all 5 are fixed; none rejected. Each fix has a test that fails on the pre-fix tree and passes after. I ran no git write commands, wrote no SQL and changed no app files.

**Checks**
- `deno test supabase/functions/_tests`: 224 passed, 0 failed.
  - The runner now includes the new `storno_i5r2_flow_test.ts`; `FLOW_MIN` is raised by 10.
  - All 97 flow tests pass when run directly, including the 24 storno hotfix tests.
- The 10 new tests: 9 fail on the pre-fix tree (`git archive HEAD` with `STORNO_FN_DIR`) and pass now. R1c is a control test that passes on both.
- `deno check` error counts are unchanged: process-payment 98, webhook-receiver 77, process-refund 0, send-cancellation-email 1, generate-invoice 0, send-booking-email 0.
- `node --check` passes on `manualRefundState.js`. `deno lint` on `BookingDetail.jsx` shows the same 6 old style warnings as HEAD.
- No PHP, web JS or SQL changed, so `php -l`, the web node tests, PG and the STATE files were not needed. The `paydec/*/web` directories don't exist anyway.
- Temp copies and test logs are deleted.

**Per issue**
1. **R1, failed-refund.ts — fixed.**
   - The old `current` check is gone. A later refund counts as a retry only if it is ours, live, created later, for the same booking and reason, not a remainder, and asks for the same amount (`mg_target ?? amount` equals `main.mg_target ?? r.amount`).
   - `redone` is kept as it was.
   - **One deviation from the spec in (c):** the cancellation check also requires the newest live main cancellation refund to be newer than the failed one. Without that, a failed top-up from 50 % to 100 % counts as "superseded" by the older 50 % refund, because nothing seems missing. Test R1c fails when I remove this guard.
   - B2, B4, V3 and the i5v R1 test pass.
2. **R2, manualRefundState.js — fixed.**
   - A live booking now always gets `partial_refund`.
   - A cancelled booking is compared with the sum of live payment receipts (new `livePaidDocsCzk`, called from `BookingDetail.jsx`), falling back to `total_price`.
   - With no status the behaviour is unchanged, so the i4 unit tests still pass.
   - In send-cancellation-email, `docsCheck` now counts only credit notes created from `cancelled_at` minus 2 min (the same slack as `refund-split.ts`). The S3b condition still uses all credit notes.
3. **R8, process-refund — fixed.**
   - If `refunds.list` fails for the stored payment, staff and service calls get `otherPaymentsUnavailable` (500, `retry:true`, ops mail). For non-cancellation reasons the mail now gives `STAFF_REFUND_HOWTO`.
   - Customer calls get `customerRefundNeedsStaff` with a specific reason in the mail. I chose this over a 500 because customer modification refunds are never retried automatically, and app 4.1.3 already shows this response.
   - New `replayedFailedRefund` in `retry-key.ts`: if a returned refund was created more than 5 s before the call started, it re-reads the refund and throws `REPLAYED_FAILED` when it is failed or canceled. It is used in `index.ts` and in `other-intents.ts` `refundRemainder`.
   - The harness `advance()` now also ages the stored idempotency snapshots, as real Stripe replays carry the original `created`.
4. **R3, webhook-receiver/index.ts — fixed.**
   - Recovery now uses `const recover = extLatest ? (fullyRefunded && bookingFullyRefunded) : (internalRefund || …)`.
   - `createCreditNoteForExistingRefund` uses "Vrácení platby zákazníkovi" for a live booking.
   - One side effect: if the event for an older refund of ours arrives only after a dashboard refund on the same charge, recovery no longer creates its missing credit note. Staff still get the external-refund mail.
5. **T3, payment-confirmers.ts — fixed.**
   - A read error or exception in the pre-check now returns `'retry'` and `confirm_payment` is not called.
   - `retryNeeded` is set on the checkout and payment-intent paths, and also on the free-verify path, because that path had the same hole.
   - The fallback UPDATE now has `.neq('status','cancelled')`.

**Not in scope:** the verifier's untracked `storno_i5v_flow_test.ts` now passes R1, R2, R3 and R8. Its R4–R7 still fail, as they did before, and I did not register it in the runner. `storno_i5_verify_flow_test.ts` V1, V4/V5 and V8 failed on HEAD before my changes and still fail. Open owner decisions P2, P3 and P4 are not implemented.

Files are in /home/user/Vel-n:
- New: `supabase/functions/_tests/storno_i5r2_flow_test.ts`
- Changed backend: `supabase/functions/webhook-receiver/failed-refund.ts`, `webhook-receiver/index.ts`, `webhook-receiver/payment-confirmers.ts`, `process-refund/index.ts`, `process-refund/retry-key.ts`, `process-refund/other-intents.ts`, `send-cancellation-email/index.ts`
- Changed tests: `supabase/functions/_tests/storno-harness.ts`, `_tests/storno_hotfix_test.ts`
- Changed Velín: `velin/src/pages/booking/manualRefundState.js`, `velin/src/pages/BookingDetail.jsx`