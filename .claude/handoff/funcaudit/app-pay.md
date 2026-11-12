# Functional-diff audit — area app-pay

Scope: `Motogo-app-main/motogo-app-flutter/lib/features/payment`, `lib/features/shop`, `lib/features/booking` (without `*/v2/**` and `*_v2*.dart`), Android tree.
Base: `70a94933` (app 4.1.3 in the field). Head: `20a4c358`.
Method: `git diff --numstat/--stat 70a94933 HEAD`; every hunk read; `payment_screen.dart` was read as a whole new file next to the old file (`git show 70a94933:…`) together with its new `part` files (`payment_screen_problems.dart`, `payment_screen_changes.dart`). Callers outside the area were followed where a hunk changes behaviour (reservation edit, FAB resume, restore). No code was edited.

## Summary

- 50 files changed (20 added, 30 modified), about +7 000 / −1 700 lines (non-v2 only).
- 79 functional hunks: 68 serve a named request (mostly Q4 D1–D6 and the Q3 error/result-state round of 2026-10-16), 10 are UNSURE (other owner topics already merged into `main` in their own PRs, or Q5 "never fill twice" logic that is also active in the OLD look), 1 is UNREQUESTED (the payment screen now cancels the booking itself when the 30-minute timer runs out).
- Classes: C = cosmetic (text, i18n label, layout, dead code, moved code), V = v2 seam (`MgV2.on/peek` → v2 view with the same handlers, Q5), F = functional.
- Provenance: the payment commits (`848a3c23`, `0bd1ade4`, `141f77e2`, `491628a3`, `0a46ec80`, `5cd2d77a`, `9c59e50e`, `c83404d6`) are Q4 D1–D6; `ebcdadc0`, `b71105fe`, `668651c9`, `15673b9b` are the Q3 round; `a6efa854` (2026-11-08) is the Q4 cancelled-meanwhile/manual-refund fix; `565986fa`, `e0f68ffe`, `30cd6b00`, `29780c7c` carry the Q5 2026-10-22 "never fill twice" work; `3e872afe` (kiosk 1.2.11) and `87bef6c2` / `cf824b36` / `1a807c5d` (i18n) are other owner topics that are ancestors of `origin/main` but were never released in the app.

### Important dependency verified during the audit

The app code now relies on server behaviour that is NOT live: `git grep` on `origin/main:supabase/functions` finds no `card_min`, `attempt_id` or `complete_extension`. These were deployed once by PR #2212 and then removed again by the hotfix `31cf5293` (2026-10-22, "vrácení edge funkcí plateb do stavu před PR #2212", because of a partial-storno refund bug). On this branch they are back (`supabase/functions/_shared/extension-apply*.ts`, `paid-change-*.ts`, `process-payment/card-minimum.ts`). The app 4.2.0 payment flows are therefore only correct if the branch's edge functions (and the SQL p1–p4 for `card_rounding`) are deployed with the merge and stay deployed. Most visible case: a paid reservation edit is no longer written by the app itself (old code did `bookings.update` + `replaceModeledExtras` after payment); the new app only asks the server (`complete_extension`) through `PaidChangeQueue`. If the edge part is reverted again, paid edits stay "Úprava se dokončuje" until a person intervenes. See app-pay-1.

## Findings that need a decision (also returned in the structured result)

| id | what | proposal |
|---|---|---|
| app-pay-1 | Paid edit / swap is written only by the server (`complete_extension` via `PaidChangeQueue`); the old client-side write after payment was removed. Requires the branch edge functions that were reverted from `main` once. No end-to-end test of the PaymentScreen extension path. | KEEP (Q4), deploy edge + SQL together, add flow test |
| app-pay-2 | Payment timer runs out → the app itself cancels the unpaid booking (`cancelPendingBooking`, reason "Čas na zaplacení v appce vypršel"). Deadline uses the phone clock against the server `created_at`. Old app only showed the "expired" sheet; the cron cancelled. | ASK |
| app-pay-3 | Draft creation that hits the overlap trigger looks up the customer's own unpaid app draft of the same bike and CANCELS it, then creates a new one (`_createDraftWithRecovery`). Requested in spirit (Q3, "dřív neznámá chyba až 30 minut"), no test. | KEEP, add test |
| app-pay-4 | Card sheet cannot be closed while a payment is submitted (PopScope + drag absorbed + close button disabled). If the Stripe call never returns (3DS / Link abandoned outside the app) the customer has no way out of the sheet. No test of `CardPaymentSheet`. | KEEP, add test / timeout |
| app-pay-5 | `InvoiceService.generateBookingDocs`: old call was a no-op (400, `types` param); new code waits 45 s and generates contract + VOP if `generated_documents` does not show them. From the i18n round, not Q1–Q7. Can create a duplicate contract/VOP if `send-booking-email` is slower than 45 s or if the template version became inactive. | ASK |
| app-pay-6 | Address sheet behaviour in BOTH looks: typing clears the prefilled/selected address, the delivery price is applied only on POTVRDIT (not on pick), POTVRDIT waits for a running pick/GPS. Bug fix from v2 review round r2, not a named request. Test exists only under the v2 harness. | ASK |
| app-pay-7 | Q5 2026-10-22 "never fill twice" logic active in the OLD look inside this area: quick address options in the address sheet, own gift-voucher chips (`my_vouchers.dart`), reservation-edit address picker prefilled with the saved address and "same address = unchanged". Same topic as app-core-2. | ASK |
| app-pay-8 | Self-service size limits (`self_service_gear.dart`, `gearSizesFor(selfService:)`) — kiosk 1.2.11 topic (`3e872afe`), outside Q1–Q7. Same topic as app-core-4. | ASK |
| app-pay-9 | i18n round items with behaviour: booking `language` 'uk' → 'en' retry on CHECK violation, `normalizeAppLang` for shop order language, `isPickup` flag instead of comparing the Czech label. Low risk. | ASK |
| app-pay-10 | Shop checkout re-uses the already created unpaid order while cart/codes/shipping/address signature is unchanged. Serves Q4 (no duplicate orders / payments), no test. | KEEP, add test |

## Table of hunks

Columns: file — hunk — class — request — risk (old look with kill-switch off, customer paths) — test.

### booking

| file | hunk | class | request | risk | test |
|---|---|---|---|---|---|
| booking/booking_entry.dart (new) | `startBookingFromSelection`: body of the old REZERVOVAT button moved; old-look branch identical (same draft, same `ctx.push`), plus it records `bookingDraftOwnerProvider`; v2 branch carries the existing draft (`carryBookingDraft`) | F | Q5 (2026-10-22 prefill) | Old look: same result; owner write is harmless | v2/screens/booking_prefill_flow_test.dart |
| booking/booking_models.dart | `gearSizesFor(..., selfService)` narrowing via `selfServiceGearSizes` | F | UNSURE (kiosk 1.2.11) | Fewer sizes offered at self-service branch in reservation edit (both looks) | none |
| booking/booking_models.dart | `extraLabel` / `extraSizeLabel` / `extraDescription` translated labels | C (i18n text) | — | none | v2/screens/booking_r2_test.dart |
| booking/self_service_gear.dart (new) | size rank filter | F | UNSURE (kiosk 1.2.11) | as above | none |
| booking/booking_quote.dart (new) | `quoteFor` / `listQuoteFor` = `PriceCalculator.calculate` with the fresh-draft arguments | F (pure) | Q5 exception (price calculator, offer on Home) | none for old look | v2/home_quote_test.dart, late_pickup_info_test.dart |
| booking/booking_provider.dart | `validateAndApplyCode`: 15 s / 25 s timeouts, specific failure reason (expired, not yet valid, used up, redeemed, Slevomat unverified, offline), Slevomat check skipped once a known code gives a reason | F | Q3 (meaningful error states) | Slevomat is no longer asked when the promo/voucher RPC already explained why the code fails — correct; offline now says "no internet" | payment_error_states_test.dart (promoReasonKey / slevomatReasonKey unit); no test of the whole function |
| booking/booking_provider.dart, booking_validator.dart | validation texts in the app language (`lang`) | C (i18n text) | — | none | v2/screens/booking_r3_test.dart |
| booking/promo_reasons.dart (new) | Czech RPC text / Slevomat code → i18n key | F | Q3 | none | payment_error_states_test.dart |
| booking/booking_ui_helpers.dart | `showAddrDialog` deleted | C (dead code, no caller at base) | — | none | — |
| booking/booking_ui_helpers.dart | address sheet: `_gen` counter, typing clears selection, `_km` only for current address, `onDistCalc` only on POTVRDIT, POTVRDIT waits for running pick (`_busy`), double-tap guard + spinner | F | UNSURE (v2 review r2 fix) — app-pay-6 | Old look changes too: closing the sheet after picking no longer changes the price (was a bug); POTVRDIT can wait up to ~30 s on GPS + routing (all calls have timeouts) | v2/screens/booking_r2_address_test.dart (v2 harness only) |
| booking/booking_ui_helpers.dart | GPS: `GpsService.locate()` with why + settings button (`explainLocation`) | F | Q3 | none | refix2_states_test.dart |
| booking/booking_ui_helpers.dart | quick options (`AddressQuickOptions`) in the sheet, both looks | F | UNSURE (Q5 2026-10-22 in old look) — app-pay-7 | extra buttons in old look | res_edit_address_test.dart, booking_prefill_* tests |
| booking/booking_ui_helpers.dart | v2 sheet frame / `AddrSheetV2View`; texts translated (`enterAddress`, `map`, `confirmAddressBtn`, `applyCode`) | V / C | Q5 / — | none | render tests |
| booking/my_vouchers.dart (new) | own active gift vouchers offered as chips in the promo dialog (both looks via core promo section) | F | UNSURE (Q5 2026-10-22 in old look) — app-pay-7 | read-only query, fails to empty list | booking_prefill_sections_test.dart, cb_booking_sheets_test.dart |
| booking/widgets/address_picker.dart | `isPickup` instead of `label == 'Vyzvednutí'` | F | UNSURE (i18n) — app-pay-9 | fixes wrong title in foreign languages | none |
| booking/widgets/address_picker.dart | `initialAddress` / `currentAddress` / `quick`; confirming the same address reports "unchanged"; fee applied only with confirmed address; method back to branch restores saved address | F | UNSURE (Q5 2026-10-22, active in old-look reservation edit) — app-pay-7 | Paid-change path checked: "unchanged" yields `pickupAddressChanged == false` in `EditPriceCalc`, so no delivery surcharge for the same address | v2/screens/res_edit_address_test.dart |
| booking/widgets/address_picker.dart | prices from `PriceCalculator.deliveryBase/PerKm` (1000 / 40 — same values), `_RadioOption` adaptive layout, v2 row builder | C / V | — / Q5 | none | fix_dates_test.dart |
| booking/widgets/address_quick_options.dart (new) | quick option buttons | F | UNSURE (Q5) — app-pay-7 | — | res_edit_address_test.dart |
| booking/widgets/map_picker.dart | tile error chip (`MapTileErrors`), v2 chrome, `mgV1StatusBar`, translated texts | F (small) / V / C | Q3 (map tile errors) / Q5 | none | render tests |
| booking/widgets/price_summary.dart | translated labels, localized rank name | C | — | none | render tests |

### payment

| file | hunk | class | request | risk | test |
|---|---|---|---|---|---|
| payment/card_minimum.dart (new) | card minimum rule (≤1 Kč waive, <15 Kč → 15 Kč), `kcExact`, `newAttemptId` | F | Q4 D1/D4 | needs branch edge (`card_min`) | payments_paydec_test.dart |
| payment/stripe_service.dart | `_validSession` / `_refreshSession`: refresh expired token before paying; network failure ≠ sign-out | F | Q3/Q4 | none | refix2_states_test.dart |
| payment/stripe_service.dart | 401 → one refresh + one resend (401 is returned before any charge) | F | Q3/Q4 | resend is safe per server comment; with `attempt_id` it is also idempotent | none (flow) |
| payment/stripe_service.dart | `card_min: true` and `attempt_id` in every request | F | Q4 D1/D4 | old edge ignores the extra fields; full effect needs branch edge | payments_paydec_test.dart |
| payment/stripe_service.dart | non-JSON / 5xx / timeout / lost response with a saved card → `uncertain` (verify, never "nothing charged"); DNS/refused → plain retry | F | Q4 (double charge) | none | refix2_states_test.dart, payment_error_states_test.dart |
| payment/stripe_service.dart | `free` answer checked before off-session; carries `waived`, `applied`, `new_booking_id`, `card_rounding` | F | Q4 D1 | — | payments_waiver_unverified_test.dart |
| payment/stripe_service.dart | `offSessionSucceeded` keeps `client_secret`; `offSessionFailed` keeps `error_code` and PI status | F | Q4 D4/D5 | — | payments_3ds_decline_test.dart |
| payment/stripe_service.dart | `PaymentResult.refusal` parses server codes/fields | F | Q4 D5 | — | payment_error_states_test.dart, payments_paydec_test.dart |
| payment/stripe_service.dart | `handleNextActionDetailed`, `outcomeForStatus`, `fetchIntentStatus` (3 × 8 s) | F | Q4 D5 | bounded wait | payments_3ds_decline_test.dart |
| payment/stripe_service.dart | `pollBookingPaymentStatus` no longer stops early on `cancelled`; 8 s per query | F | Q4 (2026-11-08 cancelled-meanwhile) | polling on a cancelled booking takes the full attempts (max 3 × 2 s in the callers) | none |
| payment/stripe_service.dart | `bookingIsCancelled`, `pollBookingTotal` (moved from screen) | F | Q4 | — | refix2_states_test.dart |
| payment/stripe_service.dart | `confirmFreeBooking(type: 'sos')` + attempt id | F | Q4 D1 | SOS flow is not built by any caller today | — |
| payment/stripe_service.dart | debug logs removed | C | — | — | — |
| payment/next_action.dart (new) | outcomes + decline extraction | F | Q4 D5 | — | payments_3ds_decline_test.dart |
| payment/net_error.dart (new) | `isNetworkError`, `requestNeverSent`, `authRefreshNetworkFailure` | F | Q3/Q4 | — | refix2_states_test.dart |
| payment/payment_verify.dart (new) | `verifyPayment`: DB, then PI of the last attempt; succeeded on a cancelled booking → `cancelledRefund`; unknown → pending | F | Q4 (2026-11-08) / Q3 | — | refix2_states_test.dart (marker); no test of `cancelledRefund` |
| payment/paid_change_api.dart (new) | `completeExtension` call + response mapping | F | Q4 (swap completion with retry, refund when bike taken) | needs branch edge — app-pay-1 | payments_paydec_test.dart, payments_restart_taken_test.dart, paid_change_queue_fix_test.dart |
| payment/paid_change_outcomes.dart (new) | outcomes for completing / failed / rounding line | F | Q4 | — | payments_swap_taken_test.dart, payments_reason_closed_test.dart |
| payment/payment_screen.dart | `_recoverPaymentOnResume`: edit via `pollBookingTotal`, skips waived | F | Q4 D1 | — | none |
| payment/payment_screen.dart | `_flow`, `_markerKind`, `_setMarker`, `_expectedEditTotal` (+ rounding) | F | Q4 | — | refix2_states_test.dart |
| payment/payment_screen.dart | `_bookingDue` / `_serverAmount` / `_upsellBundled` / `_amount` | F | Q4 D1 (upsell only when booking ≥ 15 Kč; upsell is disabled anyway, D7) | — | payments_waiver_unverified_test.dart |
| payment/payment_screen.dart | countdown: no expiry while a payment runs; `_expired` locks the pay button | F | Q3 | — | v2/ux/ps_payment_test.dart (v2) |
| payment/payment_screen_problems.dart | `_onTimeout`: non-dismissible sheet "pick again" / "open reservation" | F | Q3 | — | none |
| payment/payment_screen_problems.dart | `_onTimeout`: cancels the unpaid draft itself when no payment marker | F | UNREQUESTED — app-pay-2 | phone clock ahead of server → the app cancels a booking the server would still accept; old app left this to the cron | none |
| payment/payment_screen.dart | `_createDraftWithRecovery`: token refresh + retry; own overlapping unpaid draft → `_goPending` if marker, else cancel + recreate | F | Q3 — app-pay-3 | cancels customer's own unpaid draft; safe guard `.eq('payment_status','unpaid')` | none |
| payment/payment_screen.dart | `_insertBooking` 20 s timeout; 'uk' language CHECK fallback to 'en' | F | UNSURE (i18n) — app-pay-9 | low | none |
| payment/payment_screen.dart | `_DraftKind` classification (Czech trigger texts, auth, network) | F | Q3 | — | none |
| payment/payment_screen.dart | `if (!mounted) return bookingId;` before profile gear write; 15 s timeout on discounts insert | F | Q3 (crash after leaving) | — | none |
| payment/payment_screen.dart | `_doPayment`: guard `_expired/_completed`; free / waive / round routing; `_showDraftFailure` | F | Q4 D1 / Q3 | — | v2/ux/ps_payment_test.dart |
| payment/payment_screen.dart | `_chargeSavedCard`: offline pre-check (`OfflineGuard.isOnline`, 3 s) | F | Q3/Q4 | a false "offline" from connectivity_plus blocks the saved-card charge with "check connection" | none |
| payment/payment_screen.dart | marker set before the saved-card request; attempt id; PI id kept | F | Q4 D4/D6 | — | refix2_states_test.dart |
| payment/payment_screen.dart | 3DS outcome switch (succeeded / processing / unknown → verify / declined with reason / not completed) | F | Q4 D5 | — | payments_3ds_decline_test.dart |
| payment/payment_screen.dart | off-session failed: PI `processing` → wait; no code → verify; else clear marker + reason | F | Q4 | — | payment_error_states_test.dart |
| payment/payment_screen.dart | `_runPaymentSheetFlow`: `onSubmitting` marker + queue entry (90 s delay); cancel clears marker and queue | F | Q4 D6 | — | paid_change_queue_test.dart |
| payment/payment_screen.dart | `_verifyAndComplete`: extension → queue + finish without DB poll; else `_goPending` result screen instead of toast + Reservations | F | Q3/Q4 | — | none (flow) |
| payment/payment_screen.dart | `_awaitProcessingConfirmation` → result screen; swap skips poll | F | Q3/Q4 | — | none |
| payment/payment_screen.dart | `_confirmFree(waived)`, SOS type, PayProblem on missing id | F | Q4 D1 | — | payments_waiver_unverified_test.dart |
| payment/payment_screen.dart | `_onPaymentSuccess`: processing guard, marker clear, restore/fromDraft flags, upsell only if bundled, `_advanceInvoiceBackup` (ZF only after verified paid, never with rounding/haléře/0) | F | Q4 D1 | — | payments_waiver_unverified_test.dart |
| payment/payment_screen.dart | extension success → `_finishPaidChange` (old client `bookings.update` + `replaceModeledExtras` + swap RPC loop removed) | F | Q4 — app-pay-1 | needs branch edge | paid_change_queue_*_test.dart (queue only) |
| payment/payment_screen.dart | SOS / shop / booking outcome: amount = what was charged + rounding line | F | Q4 D1 | — | none |
| payment/payment_screen.dart | build: `BackButtonListener` + `PopScope(canPop: !_processing)`, header back → `_onBack`, server price note, `CardRoundingNote`, pay button `expired/statusLabel/freeLabel`, v2 seam | F / V | Q3 / Q4 D1 / Q5 | back is blocked only while processing; confirm dialog after submit | v2/ux/ps_payment_test.dart |
| payment/payment_screen_problems.dart | `_showProblem` action mapping (priceChanged → pay server total, payMin, reloadEdit, editAddress, signIn = sign out + login, reservations, toCart) | F | Q4 D5 | "Přihlásit" signs the customer out (also on 403 `forbidden`) | payments_paydec_test.dart, payment_error_states_test.dart |
| payment/payment_screen_problems.dart | `_handleSavedCardFailure` rewrite (card gone → other card only, amount_too_small → 15 Kč) | F | Q4 D5/D1 | — | payment_error_states_test.dart |
| payment/payment_screen_problems.dart | `_handleStripeError`, `_resolveAfterSheetError`, `_handleGatewayError(wallet)` | F | Q4 | — | payment_error_states_test.dart |
| payment/payment_screen_problems.dart | `_handleMaxAttempts` non-dismissible, edit → reservation detail | F | Q3 | — | none |
| payment/payment_screen_problems.dart | `_verifyUncertain` (5 × 6 s), `cancelledRefund` sheet, `notPaid` retry | F | Q4 (2026-11-08) | — | none |
| payment/payment_screen_problems.dart | `_goPending` → result screen "Platba se ověřuje" | F | Q3/Q4 | — | none |
| payment/payment_screen_problems.dart | `_onBack` (confirm leave when submitted, marker + Reservations) | F | Q3 | — | none |
| payment/payment_screen_changes.dart (new) | `_paidChangeEntry`, `_enqueuePaidChange`, `_rememberPreviousChange`, `_finishPaidChange`, `_showChangeDone` (mail + ZF + docs only when written), `_applyWaivedChange`, `_commitSwapDirect` (≤ 0,50 Kč during deploy window), `_handleFreeResult` | F | Q4 D1/D6, "no e-mail when the paid change could not be written" | app-pay-1 | paid_change_queue_test.dart, payments_restart_taken_test.dart |
| payment/payment_ui_helpers.dart (new) | `confirmLeaveRunningPayment`, `isTopmostRoute`, `signInAgain`, pending outcomes | F | Q3 | — | none |
| payment/payment_provider.dart | `paymentMethodsProvider` throws instead of empty list (+15 s timeout) | F | Q3 | on payment screen same as before (`defaultCardProvider` → null) | none |
| payment/payment_provider.dart | `attachPaymentMethod` 20 s timeout, verifies attach after lost response | F | Q4 (no double save) | — | none |
| payment/payment_provider.dart | `PaymentContext.isRestore`, `lastConfirmedRestore/FromDraft`, `PaymentOutcome` kinds + verify fields | F | Q4 restore / Q3 | — | none |
| payment/payment_result_screen.dart | pending state with auto-verify every 10 s (max 3 min), "Ověřit znovu", not-paid / late-refund texts, queue events, secondary route, back → close route | F | Q3/Q4 (2026-11-08) | — | refix tests (partial) |
| payment/payment_confirmation_screen.dart | details from DB by booking id (draft only when it belongs), load-fail retry, restored subtitle, back listener, v2 seam | F / V | Q3 / Q4 restore / Q5 | — | none for old look |
| payment/invoice_service.dart | `generateBookingDocs`: wait 45 s, generate missing contract / VOP in booking language; old call was a 400 no-op | F | UNSURE (i18n round) — app-pay-5 | possible duplicate documents | none |
| payment/payment_error_mapper.dart | codes → texts, `uncertain`, wallet variants, no contact | F | Q4 D5 | — | payment_error_states_test.dart, payments_paydec_test.dart |
| payment/payment_error_strings_a/b/c.dart (new) | text tables | C | Q4 D5 texts | — | payments_paydec_test.dart |
| payment/payment_refusals.dart (new) | refusal → PayProblem + action | F | Q4 D5 | — | payment_error_states_test.dart, payments_paydec_test.dart, payments_price_outdated_test.dart |
| payment/payment_methods_screen.dart | loading/error states with retry, back fallback to Profile, card-save errors shown, sheet locked while saving, v2 seams | F / V | Q3 / Q5 | — | none |
| payment/widgets/card_payment_sheet.dart | `onSubmitting` marker, `_SubmitGuard` (closed while submitting → `processing`), sheet locked during payment, cancelled 3DS keeps the sheet with a note, wallet flag, close button, `Money.czk` amount | F / V | Q4 (double charge) / Q3 / Q5 | app-pay-4 | none |
| payment/widgets/card_rounding_note.dart (new) | D1 note before payment | F (display of rule) | Q4 D1 | — | payments_paydec_test.dart |
| payment/widgets/payment_error_sheet.dart | `dismissible`, contact line removed, v2 seam | F / C / V | Q3 / Q4 D5 | — | payments_paydec_test.dart (no contact) |
| payment/widgets/payment_header_widgets.dart | `onBack`, `expired`, `statusLabel/Note`, `freeLabel`, exact Kč under 15 | F | Q3 / Q4 D1 | — | v2/ux/ps_payment_test.dart |
| payment/widgets/saved_card_preview.dart, upsell_section.dart | translated label; v2 seam | C / V | — / Q5 | — | — |

### shop

| file | hunk | class | request | risk | test |
|---|---|---|---|---|---|
| shop/shop_checkout_screen.dart | processing / submitted guard, tab-leave → pending, `_onBack` with confirm, `PopScope` | F | Q3 / Q4 | — | none |
| shop/shop_checkout_screen.dart | re-use of the unpaid order while the signature is unchanged | F | Q4 — app-pay-10 | — | none |
| shop/shop_checkout_screen.dart | card minimum D2 (charge 15 / waive / payMin sheet) | F | Q4 D2 | needs branch edge | payments_paydec_test.dart (rule only) |
| shop/shop_checkout_screen.dart | marker on submit, `_resolveUnclear` by PI status, pending screen clears cart | F | Q4 | cart is cleared also when the later verification says "not paid" (customer adds items again) | none |
| shop/shop_checkout_screen.dart | refusal mapping (`PaymentRefusals.resolve` for shop), `_showOrderError` actions, missing-field list + `reveal()` | F | Q3 / Q4 D5 | — | payment_error_states_test.dart (shop order gone) |
| shop/shop_checkout_screen.dart | `_onSuccess(free/waived)`, `select()` for `card_rounding`, rounding line | F | Q4 D2 | — | none |
| shop/shop_checkout_screen.dart | v2 seam, `MgBackTap` | V | Q5 | — | v2/ux/ps_shop_test.dart |
| shop/shop_provider.dart | create order 20 s timeout, `network`/`failed` errors; `ShopPromoCheck` with reason | F | Q3 | — | none |
| shop/shop_provider.dart | `normalizeAppLang` for order language, log on failure | F | UNSURE (i18n) — app-pay-9 | low | none |
| shop/shop_models.dart | `translations` + `nameFor/descriptionFor/...` (display only; Czech name still goes to the order) | C (i18n content) | — | none | v2 tests |
| shop/product_detail_screen.dart | loading / error / gone states with retry and back; `_addToCart` shared; translated fields | F / C / V | Q3 / — / Q5 | none | v2/ux/ps_shop_test.dart |
| shop/shop_screen.dart | visible back arrow in old look (`backOr(profile)`); translated name; v2 seam | F / C / V | Q3 (visible way back) | none | v2/ux/ps_shop_test.dart |
| shop/voucher_screen.dart | `_buy` shared; 'CZK' suffix outside Czech; v2 seam | C / V | — / Q5 | none | v2/ux/ps_shop_test.dart |
| shop/cart_screen.dart | v2 seam, `MgBackTap` | V | Q5 | none | v2/ux/ps_shop_test.dart |
| shop/widgets/checkout_shipping_section.dart | public state with `reveal()`, header summary listens to fields | F | Q3 | none | v2/ux/ps_shop_test.dart |
| shop/widgets/checkout_payment_card.dart, checkout_summary_section.dart | v2 seams | V | Q5 | none | render tests |

## Details for the decisions

**app-pay-1.** `payment_screen.dart` old lines 1217–1330 (client write of the paid edit, swap commit loop) are gone; `_finishPaidChange` calls `PaidChangeQueue.completeNow(key)` → `completeExtension()` → `process-payment {action:'complete_extension'}`. That action exists only in this branch (`git grep complete_extension origin/main -- supabase/functions` is empty). `CompleteState.clientApply` keeps a fallback when the server answers `client_apply`, but the live (`origin/main`) process-payment has no `complete_extension` branch: the request falls through to the normal payment path and is refused (400, e.g. `invalid_amount`), which `CompleteResponse.fromHttp` maps to `retry`, so the queue retries for up to 7 days. `PaidChangeApply.attempt` has no database fallback (it never checks `total_price`), so even an edit that the live webhook wrote from the Stripe metadata stays "completing" in the app, and extras / gear (not in the metadata, formerly written by the old app itself) are not written at all. Scenario: merge deploys edge, deploy-functions fails or the edge is reverted again as on 2026-10-22 → every paid edit in 4.2.0 shows "Úprava se dokončuje" and is never written, while the money was taken. Missing: a flow test that drives PaymentScreen in the extension flow with a fake `completeExtension` (done / completing / failed / notPaid) in the old look.

**app-pay-2.** `_onTimeout` in `payment_screen_problems.dart`: `if (!edit && bid != null && !await PaymentPendingMarker.isPending(bid)) cancelPendingBooking(bid, reason: 'Čas na zaplacení v appce vypršel')`. The deadline is `bookingCreatedAt + 30 min` measured with the phone clock (`DateTime.now()`); a phone running 5–10 minutes fast cancels the resumed booking early. Old app only displayed "Čas vypršel" and left the cancel to `auto_cancel_expired_pending()`. The new text (`psExpiredBookingBody`) may depend on the cancel; check the text before reverting.

**app-pay-3.** `_ownOverlappingDraft` selects `bookings` of the same user, same `moto_id`, `pending` + `unpaid` + `booking_source='app'`, overlapping dates; if no local marker it cancels that row and inserts a new one. A payment started for the old draft on another device (marker is local) would then land on a cancelled booking (server refunds it — Q4 2026-11-08 path). No test.

**app-pay-4.** `card_payment_sheet.dart`: while `_processing`, `PopScope(canPop:false)`, drag is absorbed and the close icon is disabled. The sheet is unlocked only when `confirmPayment` / `confirmPlatformPayPaymentIntent` returns or throws. If the plugin future never completes (external 3DS or Link page abandoned), the customer sees "Platba se zpracovává" with no exit; old sheet could be dragged away. No test covers `CardPaymentSheet`.

**app-pay-5.** Old `generateBookingDocs` sent `{types:[...]}` which generate-document rejects (400, needs `template_slug`), so it did nothing. New code runs 45 s later and generates `rental_contract` and `vop` when `generated_documents` + `document_templates` (RLS: only `active=true` templates are visible to the customer) do not show them. generate-document deletes older versions only for the same `template_id`, so a duplicate stays when the template version changed or the e-mail generation is still running. Called for new bookings, resumed bookings and written edits.

**app-pay-6 / app-pay-7.** The address sheet (`showAddrBottomSheet`) is used by the booking form in both looks and by the reservation edit (through `AddressPickerWidget`). Quick options and saved-address prefill are passed regardless of the look (`reservation_edit_screen.dart` lines 1465–1490 pass `initialAddress`, `currentAddress`, `quick` without a `MgV2` check). Verified that confirming the unchanged address does not create an address change in `EditPriceCalc` (`_normAddr(pickupAddressNew) == _normAddr(booking.pickupAddress)`), so no wrong delivery surcharge.
