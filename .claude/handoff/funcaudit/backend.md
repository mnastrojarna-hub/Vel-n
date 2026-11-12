# Functional-diff audit: backend area (edge functions, Velín, web, repo config)

BASE = origin/main (c254fbe2), HEAD = 20a4c358. The one commit on origin/main after the merge base does not touch this area, so `git diff origin/main HEAD` contains only this branch's changes.

Paths checked: supabase/functions (102 files, of which 43 are in `_tests`), velin/ (21), motogo-web-php/ (21), CLAUDE.md (1). Nothing changed in .github/, codemagic.yaml, raspberry/, slevomat-bot/ or backup/.

Non-test files: 102, with 347 hunks in total. About 55 hunks are cosmetic: the CLAUDE.md text, 49 hunks of web language/CMS text, comment and help text in Velín, and the comment hunk in TrasyMapPicker. About 292 hunks are functional. Of those, about 234 serve Q4 (payments, rounds D1–D6 and i1–i6, P2) and 58 serve Q6/Q7 (rides and routes in Velín). None is clearly unrequested. Two items are UNSURE (B-1 and B-5 below).

Per the task, the money logic of the edge functions was not re-derived. I mapped it from the code comments (each hunk carries a D1–D6 / i1–i6 / f1–f3 / P2 tag) and from the reports fix_i4, fix_i5r1, fix_i5r2 and fix_i6r1.

Important deploy fact: edge functions, Velín (Vercel) and the SQL migrations all go live on merge. The app in the field (4.1.3) talks to the new edge code from that moment, before 4.2.0 is released. Every edge hunk was read with that in mind: 4.1.3 shows the server `error` text word for word.

## 1. Edge functions (supabase/functions)

| File | Hunk(s) | Class | Request | Risk (old app 4.1.3 / customer paths) | Test |
|---|---|---|---|---|---|
| _shared/auth.ts | +trustedCallerKind | functional | Q4 i3 (send-cancellation-email tells Velín apart from the server) | Low. New export; isTrustedCaller is unchanged. | storno_i3_flow_test.ts (V3) |
| _shared/booking-intents.ts (new) | all | functional | Q4 (multi-payment storno, verified rounds f1–f3/i4) | Money logic, not re-derived | storno_multi_test.ts, storno_multi_intent_flow_test.ts |
| _shared/charge-rounding.ts, currency.ts (new) | all | functional | Q4 D1 (15 Kč minimum) + verification round 2026-11-05 (CZK only) + i4 (Adaptive Pricing) | Low: app and web never send a currency other than czk; 4.1.3 sends none | currency_test.ts, gear_rounding_test.ts, payments_test.ts |
| _shared/duplicate-payment.ts (new) | all | functional | Q4 D4 (double-charge protection) | Money logic; mails go only to staff | duplicate_payment_test.ts |
| _shared/extension-apply*.ts (6 new) | all | functional | Q4 D6 (swap/edit completion with retry; code moved here from webhook-receiver) | Money logic | extension_apply_test.ts, complete_extension_kind_test.ts |
| _shared/free-verify.ts (new) | all | functional | Q4 i2 (0 Kč booking whose price changed is not confirmed as free) | Low | f1_payments_test.ts |
| _shared/paid-change-failure.ts, paid-change-guard.ts (new) | all | functional | Q4 D6 + "refund when the swapped bike is taken" + "no customer e-mail when a paid change could not be written". I checked that only the ops e-mail is sent (send-email to OPS_EMAIL). | Money logic | paid_change_guard_test.ts, paid_change_refund_test.ts |
| _shared/refund-recovery.ts (new) | all | functional | Q4 (f3 recovery reason) | Money logic | f3_refund_test.ts |
| fio-sync/index.ts | 2 hunks (select status; cancelled → needs_review + ops mail) | functional | Q4 i5r1 issue 6 (Fio surcharge after storno) | Low. Only `cancelled` is diverted; completed bookings are still confirmed. | storno_i5_flow_test.ts (F1) |
| generate-invoice/index.ts | 9 hunks (rounding line on booking/shop/edit documents, skip ≤ 1 Kč edit DP, itemDiff) | functional | Q4 D1/D2 (rounding as its own document line) | Low. `card_rounding` is read with `|| 0`, so documents are unchanged until SQL 20261112a01 adds the column. | gear_paid_docs_test.ts / gear_documents_test.ts touch generate-invoice; no test is dedicated to the rounding line |
| process-payment/index.ts | 32 hunks | functional | Q4 D1 (minimum/rounding/waiver), D3 (cancelled booking → refusal with restore reason, floor check on app-restored bookings, voucher_unavailable), D4 (one live PI per booking, idempotency keys, payment_in_progress, payment_uncertain, settleMatchingSessions), D5 (refuse() with code + Czech text without contacts, declineMessageCs), D6 (complete_extension action, previous-change completion), i1 (PI metadata on Checkout), i2 (free-verify), CZK guard | See B-1 (overpayment refusal when reservation_upsell is off) and B-2 (app-restored booking floor enforced). Everything else is Q4 design. | pp_charges_flow_test.ts, payments_test.ts, checkout_floor_test.ts, duplicate_payment_test.ts, pp_web_checkout_flow_test.ts, pp_currency_flow_test.ts |
| process-payment/payment-flows.ts | 22 hunks | functional | Q4 D1/D2 (web minimum, rounding item on the Stripe page, waiver ≤ 1 Kč), D4 (settleStoredSession), i1 (server-side amount for web booking and voucher shop), f1 (webBookingMiss reason, free booking + bundled goods), CZK | Low. Web line-item names are now localised (checkout-labels.ts); that is text only. | pp_web_checkout_flow_test.ts, checkout_floor_test.ts |
| process-payment/stripe-customer.ts | 1 hunk (maxNetworkRetries comment/config) | functional | Q4 D4 | Low | – |
| process-payment/ app-change-price, card-minimum, checkout-guard, checkout-labels, complete-extension, declines, due-verify, floor-check, intent-guard, pp-waiver, refusals, stripe-errors, verify-shop-session, web-booking-guards (14 new) | all | functional | Q4 D1–D6, i1–i4. verify-shop-session.ts is the old inline verify_shop_session moved into its own file, plus D2 rounding and i4 Adaptive Pricing. | Money logic, see B-1/B-2/B-3 | payments_test.ts, checkout_floor_test.ts, verify_shop_session_test.ts, i1_units_test.ts, i4_units_test.ts |
| process-refund/index.ts | 43 hunks | functional | Q4 (storno once over all payments, orphans i5, retry-key i4, retry-of i6r1, refunded-check i6r1, doc-owed i3, P2 `cancel_total`, customer refund text without an e-mail promise i4 #14) | Money logic, not re-derived. No REVERT per task. | storno_hotfix_test.ts runner + storno_i1…i6r1 flow tests, f2_customer_refund_test.ts, f3_refund_test.ts |
| process-refund/cancel-once.ts + 9 new modules (cancel-once-pool, cancel-orphans, credit-note-sync, doc-owed, other-intents, refunded-check, retry-key, retry-of) | 7 hunks + all | functional | Q4 | Money logic | same flow tests |
| send-booking-email/index.ts, i18n.ts, modified-refund.ts (new) | 8 + 2 hunks | functional | Q4 i3/i4 (mail for an edit refund without a credit note says "staff finishes it" and does not promise an attachment; ops mail) | Low. It can add a short wait loop before the booking_modified mail of a shortening is sent. | storno_i3_mail_flow_test.ts, i4_units_test.ts |
| send-cancellation-email/index.ts, i18n.ts, refund-split.ts (new) | 19 + 2 hunks | functional | Q4 i1–i6r1 (mail states the actually refunded amount; "deferred" text; card + bank split; attach all credit notes of this storno only; admin call without a refund choice = mail only, never the tier table) | Medium for staff flows, none for app flows. A Velín storno without refund_amount no longer refunds by the tier table. Current Velín always sends refund_amount (bookingMessageHelpers.js), and app/RPC storno comes as a service call, which is unchanged. | storno_i3_flow_test.ts, storno_i3_mail_flow_test.ts, storno_hotfix_once_flow_test.ts (regression line 83) |
| webhook-receiver/index.ts | 17 hunks | functional | Q4 D1 (rounding written after payment), D4 (an extension never revives a cancelled booking via confirm_payment; duplicate payment refunded), D6 (500 → Stripe retry), i1–i5r2 (refund scope, external refund, recovery), CZK guard | Money logic | f3_webhook_cn_test.ts, pp_webhook_charge_flow_test.ts, storno flow tests |
| webhook-receiver/payment-confirmers.ts | 8 hunks | functional | Q4 i1/i5r2/i6r1 (never revive a cancelled booking; retry on read error) | Money logic | storno_i5r2_flow_test.ts, storno_i6r1_flow_test.ts |
| webhook-receiver/ cancel-mail-amount, cancelled-payment, extension-payment, failed-refund, late-payment, refund-scope, refund-updated (7 new) | all | functional | Q4 (late payment on a cancelled booking refunded, i2/i4/i5/i6r1) | Money logic; customer-facing effect = "we refund you" pages (Q4 2026-11-08) | storno_i5_flow_test.ts, storno_i6r1_flow_test.ts, i4_units_test.ts |
| _tests/* (43 files) | all | test-only | – | – | – |

## 2. Velín (velin/)

| File | Hunk(s) | Class | Request | Risk | Test |
|---|---|---|---|---|---|
| pages/booking/bookingMessageHelpers.js | 2 (PAID_FOR_REFUND incl. partial_refund/refund_pending; always send refund_amount/percent, 0 when unpaid) | functional | Q4 i3 | Staff-only. It pairs with the send-cancellation-email "admin without choice = mail only" rule. | storno-dispatch.ts mirrors it (storno_i3_flow_test.ts) |
| pages/Bookings.jsx | 2 | functional | Q4 i3 (cancel modal offers a refund choice for partial_refund/refund_pending) | Staff-only, low | – |
| pages/BookingDetail.jsx | 6 | functional | Q4 P2 (2026-11-08, "Potvrdit vrácení" = total storno amount, capped at what was paid, `cancel_total`), i4/i5r2/i6r1 ("Vratka odeslána" from live DB state) | Staff-only. A new error appears if the refunds so far cannot be read; that is safe. | storno-dispatch.ts velinConfirm uses the real helper; storno_i6r1_flow_test.ts |
| pages/booking/manualRefundState.js (new) | all | functional | Q4 i4/i5r2/i6r1 | Staff-only | i4_units_test.ts, storno_i6r1_flow_test.ts |
| pages/booking/RefundConfirmModal.jsx | 2 | cosmetic (comment + help text for P2) | Q4 P2 | – | – |
| lib/mapyRoute.js | 1 (+fetchRoadLine, Mapy.com routing with an in-memory cache) | functional | Q7 (gaps drawn as an estimated road route; Velín named by the owner) | Admin-only. Up to 25 routing calls per opened ride (API quota); on error nothing is drawn. | none (no Velín unit test) |
| pages/TrasyMapPicker.jsx | 2 (comment; straight dashed fallback line removed) | functional | Q7 (never straight lines between route points, Velín) | Admin-only. Until routing answers, only the points are visible. | none |
| pages/TrasyJizdaMapa.jsx | 10 | functional | Q7 (grey dotted estimated road route + label for GPS gaps) + Q6 (pause segments, paused live marker) | Admin-only | none |
| lib/rideTrack.js | 6 (pause marker kmh −1, gap vs pause rules, trackPauses, pauses count) | functional | Q6 (sane statistics; same rules as server `_ride_stats_v2` and app `_splitOnGaps`) | Admin-only. Old rides are re-split. A silence of 3–5 min that is slower than 15 km/h is no longer a gap, so it is drawn as part of the solid line. | none |
| lib/rideStats.js (new), lib/rideTrip.js (new) | all | functional | Q6 (multi-day trip = one record, merged trips, pause-aware stuck/standing/awaiting states mirroring `close_stale_user_rides`) | Admin-only. It falls back when the new SQL columns are missing. | none |
| lib/rideDiag.js | 4 | functional | Q6 (diagnostic timeline knows pauses, auto-pause, trip continue, flag ride_autopause) | Admin-only, display | none |
| pages/TrasyJizdy.jsx | 10 | functional | Q6 (list: "Stojí" filter, trip badge, pause columns with a 3-step column fallback, booking state fetch) | Admin-only. See B-5. | none |
| pages/TrasyJizdaModal.jsx, TrasyJizdaBody/Cesta/Etapy/Info/Stav (5 new), TrasyJizdaDiag.jsx | 6 + all + 4 | functional (partly refactor: point edit/delete and photo removal moved into TrasyJizdaBody unchanged) | Q6 (trip/stage display) + derived admin safety (confirmRideEnd, RideAwaitBox) | Admin-only. See B-5. | none |
| pages/booking/BookingLiveMap.jsx | 9 | functional | Q6 (live map: "Stojí od …", "Čeká na data", stat tiles from rideCoreStats; confirm before ending a stuck ride) | Admin-only. See B-5. | none |

## 3. Web (motogo-web-php/)

| File | Hunk(s) | Class | Request | Risk | Test |
|---|---|---|---|---|---|
| js/pages-potvrzeni.js (minified one-liner; diffed after splitting on ; and {) | 1 | functional | Q4 2026-11-08 + i2/i4 (payment on a booking cancelled meanwhile → "cancelled, we refund you" / neutral "verifying" view + 3 min background poll; never "waiting"; bundled-order text; ordinary storno text when `late_refund === false`) | Low. Without the SQL fields `late_refund`/`bundled_order_number` it behaves as today. | i4_units_test.ts (web behaviour) |
| js/gear-rental-done.js | 2 | functional | Q4 i4 #13 (gear confirmation page keeps polling a cancelled + unpaid booking, then shows refund/verify text) | Low | i4_units_test.ts |
| js/pages-upravit-rezervaci-guard.js, pages-upravit-rezervaci-gear.js | 3 + 1 | functional (display) | Q4 i1 (refund amounts shown in CZK via MG.fmtCzkExact, which exists on main in card-rounding.js; falls back to MG.formatPrice) | Low | none |
| pages/potvrzeni.php | 1 (new CMS keys) | cosmetic/text wiring | Q4 | – | – |
| lang/{cs,de,en,es,fr,nl,pl,uk}.php | 5 each | cosmetic (text) | Q4 texts. One unasked wording change: refund time "5–7" → "5–10 pracovních dnů" in 4 keys × 8 languages (text only). | – | – |
| lang/v2/*/gear-flow.php, data/gear-rental-flow-texts.php | 1 each | cosmetic (text) | Q4 i4 #13 | – | – |

## 4. Repo files

| File | Hunk | Class | Request | Risk |
|---|---|---|---|---|
| CLAUDE.md | rule 6 rewritten (v2 in both trees; look-only rule; iOS test procedure) | cosmetic (instructions) | Q5 (2026-11-05/-07) | none |

## 5. Items returned to the orchestrator

- **B-1 (UNSURE, ASK)**: process-payment/index.ts, booking/sos branch, `else if (amt > 0 && !order_id && Math.round(amt) > Math.round(payDue) + 1 && !(await upsellEnabled(sbChk)))` → 409 amount_mismatch.
  - When the reservation_upsell flag row is missing or false, a payment higher than the booking price is now refused. Before, it was allowed.
  - DESIGN.md D7 says the opposite: "PP keeps amount higher than due allowed for compatibility".
  - Scenario: 4.1.3 sends `amount` = client breakdown + upsell, while `total_price` was changed afterwards. That happens if a DB trigger caps or adjusts it, or after a client-side discount mismatch. The customer then gets "Cena rezervace je teď X Kč" instead of being charged.
  - This is arguably safer (no overcharge), but it is a deviation from the design.
  - Covered by pp_charges_flow_test.ts line 101.
- **B-2 (requested, risky, KEEP)**: floor-check.ts / due-verify.ts enforcement on bookings restored in the app (`restored_by_source = 'app'`, Q4 D3).
  - A restored booking whose stored price is lower than the price-list floor minus provable discounts is refused with price_outdated ("create a new booking"). If the floor RPC fails, it is refused with 503 validation_unavailable.
  - Realistic break: staff gave a manual price reduction in Velín. That reduction is not in booking_discounts and not a loyalty or late-pickup discount. The booking expires unpaid, the customer taps "Obnovit a zaplatit" in 4.1.3 or 4.2.0, and the payment is refused.
  - checkout_floor_test.ts covers the D3 rule but has no case for a staff-adjusted price.
- **B-3 (requested, risky, KEEP)**: pp-waiver.ts voucherProblem runs on every app booking/sos payment, not only on restore.
  - If the booking's voucher expired or was redeemed by another booking, payment is refused (voucher_unavailable, "create the booking again").
  - Designed (DESIGN §163) and covered in payments_test.ts. The only realistic break is a voucher whose `valid_until` passes between booking creation and payment, or a restored booking.
- **B-4 (requested, risky for staff only, KEEP)**: send-cancellation-email `staffMailOnly`.
  - An admin (Velín) call without refund_amount/refund_percent now sends only the mail and never refunds by the storno table.
  - All current Velín callers send the amount. The risk is a Velín tab opened before the Vercel deploy that cancels a `partial_refund`/`refund_pending` booking: the refund is not made and staff must use "Potvrdit vrácení".
  - Tested in storno_i3_flow_test.ts.
- **B-5 (UNSURE, ASK; admin-only)**: Velín ride-admin additions beyond showing the new ride data.
  - The additions: a "⏸ Stojí" list filter, the "Čeká na data z telefonu" state with RideAwaitBox, a confirm dialog before "Ukončit záznam" (confirmRideEnd), trip grouping badges, auto-close hints and the 3-step column fallback.
  - They follow from Q6 (the server now keeps pause-aware rides open and deletes rides under 1 km on close), but the owner did not ask for Velín features by name.
  - No customer flow is affected. There are no Velín tests for rideStats.js, rideTrip.js or rideTrack.js.
