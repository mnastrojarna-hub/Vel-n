fix:i5r1 result: all 8 issues reproduced on the current code and none were rejected. 7 are fixed in full. Issue 3 is fixed for service calls; the Velín variant now reports the right total but still refunds the chosen amount on top, because that is open decision P2. The two revive-guard issues (4 and 7) are the same bug and got one fix. No git write commands were run, no SQL was written, and no app or PHP/web files were touched.

**Checks**
- `deno test supabase/functions/_tests`: 224 passed, 0 failed (128 ignored; was 119, plus the 9 new flow tests, which only run through the runner).
- New flow file `_tests/storno_i5_flow_test.ts` (9 tests) is registered in `storno_hotfix_test.ts`, with FLOW_MIN raised by 9. All 9 fail on the pre-fix tree (`git archive HEAD`, run with `STORNO_FN_DIR`) and pass after.
- `deno check` error counts are unchanged from baseline: process-payment 98, webhook-receiver 77, process-refund 0, send-cancellation-email 1, generate-invoice 0, send-booking-email 0, fio-sync 13 (same as before).
- `deno lint` is clean on the new files. `php -l` and the node web tests were not needed (no web files changed, and the scratch web dirs no longer exist).
- Temp files are deleted.

**Per issue**
1. **Blocker V9, failed storno refund leaves its credit note live — fixed.**
   - New `webhook-receiver/failed-refund.ts`. For our in-price refunds it re-reads every payment of the booking from Stripe. It then shrinks the credit note of the whole refund to what is still live: the main refund plus its live remainders.
   - At 0 the note is set to `cancelled` with a note. Accounting entries are adjusted the same way `reconcileCreditNote` does it.
   - New decreasing helper `shrinkCreditNote` sits next to `reconcileCreditNote` in `process-refund/credit-note-sync.ts`.
   - The ops mail now says "dobropis X zrušen / upraven z A na B Kč" and "Chybí vrátit N Kč". It never says "Zrušte dobropis".
   - If the Stripe payments can't be read, nothing is changed and the mail asks staff to check the note.
   - Test B1.
2. **V2, only the remainder fails — fixed by the same shrink.** The note goes down to the main refund (500). Recovery and Velín Potvrdit vrácení then bring the refunds and notes back to 3500 each. Test B2.
3. **V1, orphan remainder — fixed for service calls; the Velín part depends on P2.**
   - New `orphanCancelRemainders` in `cancel-once.ts`. Orphans count in `cancellationRefundedHaleru`, so also in `mg_cancel_total` and `cancel_refunded_total`.
   - New `process-refund/cancel-orphans.ts`: a service call refunds only the part the orphans don't cover. If they cover all of it, no refund is created and the status is repaired.
   - Velín still refunds the chosen amount on top (P2), but now reports the true total. Tests B3 and B3u.
4. **Revive guard keeps a new payment (refunds verifier V6) — fixed; same fix as issue 7.**
   - New `webhook-receiver/cancelled-payment.ts`, called by both webhook paths when `confirmBookingPayment` returns 'skipped'. `payment-confirmers.ts` is unchanged.
   - The payment is left alone if its PI has a live refund, if `late_payment_refunded` is already logged for it, or if it is the stored card payment and was paid before the storno.
   - If the charge was paid after `cancelled_at`, it is refunded automatically through `refundLatePaymentOnCancelled` (idempotent per PI, with an adjusted ops mail).
   - Anything else gets an ops mail "zkontrolujte a vraťte", once per PI.
   - If Stripe or the DB can't be read, the webhook returns 500 so Stripe retries. Test C1.
5. **V3, a stale "failed" event re-opens the booking — fixed.** The booking is re-opened only while the failed refund is still current. It is not current when:
   - the stored refund of the booking is newer; or
   - a newer live refund of ours with the same reason exists; or
   - the same logical refund is already back at its `mg_target`.

   Otherwise it logs `refund_updated_failed_superseded`. Mail dedup per refund stays. Test B4, and B2 also covers a stale remainder event after recovery.
6. **Fio surcharge arriving after the storno — fixed.** Match 2 now selects `status`. For a cancelled booking it sets `needs_review` and sends the ops mail "ZRUŠENÉ … vraťte převodem a vystavte dobropis". It does not call `confirm_booking_surcharge`.
   - I limited this to `cancelled` and not "anything but pending/reserved/active", so a surcharge paid after a `completed` booking is still confirmed as before.
   - The optional SQL to make `cancel_booking_tracked` clear `mod_surcharge_due` is an owner decision and was not drafted.
   - Test F1, which also checks that a live booking is still confirmed.
7. **Same revive-guard bug from the charges verifier (R1) — fixed by the fix in issue 4.** R1 passes: 6000 refunded, one mail per payment. A re-delivered event refunds nothing more.
8. **Adaptive Pricing amounts (R2/R3) — fixed.**
   - `paid-change-failure.ts`: for a non-CZK PI the refund is created with no amount (the whole payment), with the same key `mg-pcf-<pi>`.
   - `late-payment.ts`: a bundled non-CZK payment is not split automatically. The ops mail says "VRAŤTE RUČNĚ" with the booking part in Kč, taken from the session's CZK amount (new `czkReceivedH`, passed from the session path).
   - Tests A1 and A2.

**Not covered by this list:** the verifier's untracked `_tests/storno_i5_verify_flow_test.ts` still has 3 failing tests. I did not register it in the runner or change it.
- **V1 Velín variant:** P2 delta semantics, plus the test cancels the shrunk credit note itself.
- **V4:** a premature 'refunded' while the remainder is still pending.
- **V8:** `modifiedRefundCovered` with mixed time zones.

V4 and V8 were not in this issue list. The f1/3 `nowMs` item was already fixed in an earlier round. The charges scratch R4 (financial_events skipped under Adaptive Pricing) was not in the list either.

Files are in /home/user/Vel-n/supabase/functions:
- New: `webhook-receiver/failed-refund.ts`, `webhook-receiver/cancelled-payment.ts`, `process-refund/cancel-orphans.ts`, `_tests/storno_i5_flow_test.ts`
- Changed: `webhook-receiver/refund-updated.ts`, `webhook-receiver/index.ts`, `webhook-receiver/late-payment.ts`, `process-refund/cancel-once.ts`, `process-refund/credit-note-sync.ts`, `process-refund/index.ts`, `_shared/paid-change-failure.ts`, `fio-sync/index.ts`, `_tests/storno_hotfix_test.ts`