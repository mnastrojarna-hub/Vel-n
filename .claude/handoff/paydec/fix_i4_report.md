fix:i4: of the 16 issues, 12 are fixed in code (#6, #7 and #9 partly; parts of each still need an owner decision or a Stripe setting), #10 and #12 have SQL drafts only, and 2 app issues are report-only. None were rejected: every listed issue reproduces on the current branch. No git write commands were run.

**Checks**
- `deno test supabase/functions/_tests`: 224 passed, 0 failed. This includes the flow-test runner with the new `storno_i4_flow_test.ts` (FLOW_MIN raised by 8).
- The 8 new flow tests all fail on the pre-fix tree (`git archive HEAD`, run with `STORNO_FN_DIR`) and pass after.
- The two web behaviour tests in `i4_units_test.ts` also fail on the old JS and pass after.
- `deno check` error counts are unchanged from baseline: process-payment 98, webhook-receiver 77, process-refund 0, send-cancellation-email 1, generate-invoice 0, send-booking-email 0.
- `php -l` passes on all changed PHP and `node --check` on both changed JS files.
- `BookingDetail.jsx` parses (deno lint shows only old style warnings).
- Both SQL drafts were applied twice on each of two fresh PG16 copies of the live schema, with behaviour checks run on both.
- Temp files, the pre-fix copy and the local PG cluster are deleted.

**Per issue**
1. **Blocker, failed refund replayed — fixed.** New `process-refund/retry-key.ts`.
   - Both idempotency keys get a `:f<n>` suffix, where n is the number of failed/canceled refunds on that PI. With no failed refunds the key is identical to the live one, so the deploy window is unaffected.
   - The main key uses the stored PI's refund list (or the retargeted PI's list); the remainder key uses the new `Candidate.failedRefunds` in `_shared/booking-intents.ts`.
   - If Stripe still returns a refund already known as failed, it is treated as an error: no status, credit note or remainder bookkeeping.
2. **Failed refund never re-opens the booking — fixed.**
   - `refundedStatus` and `statusLags` (via new `remainderPending`) return `refund_pending` while a remainder refund is pending.
   - `onRefundUpdated` on failed/canceled for our own in-price refunds does a compare-and-set `refunded`/`partial_refund` → `refund_pending`.
   - The ops mail is sent once per refund, names the credit note to cancel and states the real booking status.
3. **Failed outside-price refund is silent — fixed.**
   - The booking is now also found via `metadata.booking_id`, and the ops mail always goes out, even with no booking found.
   - Outside-price refunds get a "refund manually in the Stripe dashboard" note and never change the booking status.
4. **S10 pending refund repeated twice — fixed.** The fresh-credit-note dedup now runs for every non-cancellation call with an amount, for `paid`, `refund_pending` and `partial_refund`.
5. **S7 mixed card + transfer storno — fixed.**
   - New `velin/src/pages/booking/manualRefundState.js`: the manual credit note shows in Velín next to a card refund, and „Vratka odeslána“ is kept for cancelled bookings in that case.
   - That action now sets the status from all live credit notes.
   - In process-refund, a no_op no longer closes `refund_pending` while a manual credit note is open.
6. **S2 semantics of „Potvrdit vrácení“ — partly fixed; the semantics need your decision.**
   - The amount is still treated as an extra refund (delta), so the hotfix regression test is unchanged.
   - There is no "vraťte ručně" ops mail when nothing more is owed per DP − credit notes.
   - The response gets `cancel_refunded_total`; Velín and the test dispatcher use it for `booking_cancellations` and the customer mail, so the mail matches the money.
7. **S3 unpaid surcharge — partly fixed.**
   - When the request is above what was paid, no shortfall is reported and the status follows reality.
   - send-cancellation-email caps the mail amount to the paid documents.
   - The optional `cancel_booking_tracked` change (percentage of what was paid instead of total_price) needs your decision; I didn't draft it.
8. **S6 failed refund of a second shortening reaches nobody — fixed.**
   - The process-refund catch now sends an ops mail for any caller kind.
   - `modifiedRefundCovered` counts only credit notes created after the newest `modification_history[].at` that has a time zone. App 4.1.3 writes local time without a zone, so for those it falls back to "same amount ±1 Kč or fresh".
9. **Adaptive Pricing — code hardened; the Stripe Dashboard check is still needed before merge.**
   - New `checkoutCzk()` in `_shared/currency.ts` is used in the webhook, `verify-shop-session.ts` and `complete-extension.ts`. A session priced in CZK but paid in EUR is confirmed, with CZK amounts taken from `currency_conversion`.
   - The matching `payment_intent.succeeded` is skipped quietly.
   - Refunds from non-CZK payments are refused (code `foreign_currency_payment` plus ops mail) and are left out of the remainder candidates.
   - Still open: please confirm in Settings → Payments → Adaptive Pricing that it is OFF. Dashboard refunds of EUR payments would still be booked with EUR cents. I did not pass `adaptive_pricing` on session create.
10. **Customer can change price columns of a paid booking (live today) — SQL draft only; needs your decision.**
    - `20261107b_guard_customer_booking_pricing.sql`: a customer JWT update on a non-unpaid booking that extends, shifts or changes the moto/trailer is silently reverted; shortening still passes.
    - Logging is RAISE LOG only, because customers can't insert into `debug_log` under its RLS.
    - Risk before enabling: an app 4.1.3 change too large for the metadata (no_payload) would be lost.
11. **/potvrzeni guesses "refunded" — fixed.**
    - `late-payment.ts` now compare-and-sets `unpaid` → `refunded` after a successful late refund.
    - `confirmBookingPayment` never revives a cancelled booking whose payment is being or has been refunded.
    - The page shows a neutral "platbu ověřujeme" view and keeps polling for about 3 more minutes.
    - A normal storno gets its own text when the new RPC field `late_refund` is false. All new texts exist in 8 languages.
12. **Bundled shop order text — page and texts done, data only via SQL draft.** `20261107a_web_booking_confirmation_late_refund.sql` adds `late_refund`, `late_refund_amount` and `bundled_order_number` to `get_web_booking_confirmation`. The page detects the fields, so it behaves as today until the draft is deployed.
13. **Gear confirmation page — fixed.** `gear-rental-done.js` keeps polling a cancelled + unpaid booking and then shows verify or refund texts (8 languages). The `?resume=` link behaves as before.
14. **Promise of e-mailed credit note — fixed by dropping the promise.** The `refund_needs_staff` text now ends "…vrácenou částku pak uvidíš v detailu rezervace." The ops mails describe the real procedure: Stripe dashboard refund, then credit note in Finance → Dobropisy, then send it to the customer.
15. **App `pdRefundManual` — report only.** In both trees and 8 languages, replace "potvrzení a dobropis přijdou e-mailem" with "vrácenou částku pak uvidíš v detailu rezervace".
16. **App payment polling — report only, still open.** In `stripe_service.dart` and `payment_verify.dart`, keep polling a cancelled + unpaid booking, add a "zrušená – platbu vracíme" outcome, and never return pending for a succeeded payment.

**Not covered by this list:** the verifier's S9 still fails (storno mail amount after a dashboard refund of 1000 Kč on a 0 % storno), and its S7 file hardcodes the old Velín formula, so it fails by design; the new S7 test covers the fix instead. No `SUPABASE_BACKEND_STATE_*.md` files were changed because no SQL was applied.

Files are in /home/user/Vel-n/supabase/functions:
- New: `process-refund/retry-key.ts`, `_tests/storno_i4_flow_test.ts`, `_tests/i4_units_test.ts`
- Changed: `process-refund/index.ts`, `process-refund/other-intents.ts`, `process-refund/cancel-once.ts`, `_shared/booking-intents.ts`, `_shared/currency.ts`, `webhook-receiver/refund-updated.ts`, `webhook-receiver/late-payment.ts`, `webhook-receiver/payment-confirmers.ts`, `webhook-receiver/index.ts`, `process-payment/verify-shop-session.ts`, `process-payment/complete-extension.ts`, `send-booking-email/modified-refund.ts`, `send-booking-email/index.ts`, `send-cancellation-email/index.ts`, `_tests/storno-dispatch.ts`, `_tests/storno_hotfix_test.ts`

Velín (/home/user/Vel-n/velin/src/pages): new `booking/manualRefundState.js`; changed `BookingDetail.jsx`.

Web (/home/user/Vel-n/motogo-web-php): `js/pages-potvrzeni.js`, `js/gear-rental-done.js`, `pages/potvrzeni.php`, `lang/{cs,en,de,nl,es,fr,pl,uk}.php`, `data/gear-rental-flow-texts.php`, `lang/v2/*/gear-flow.php`

SQL drafts:
- /tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad/paydec/sql/20261107a_web_booking_confirmation_late_refund.sql
- /tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad/paydec/sql/20261107b_guard_customer_booking_pricing.sql