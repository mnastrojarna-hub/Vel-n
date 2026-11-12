# Functional diff audit: area app-res (Android tree, non-v2 files)

Scope: `Motogo-app-main/motogo-app-flutter/lib/features/{reservations,documents,sos}` without `*/v2/**`, BASE `70a94933` (app 4.1.3) → HEAD.
66 files: 41 modified, 21 added, 4 deleted. Every hunk was read (diff per file in `funcaudit/appres/*.diff`).

Important context found during the audit: a part of this diff was already merged into `origin/main` BEFORE the owner's Q1–Q7 request list
(10–11 Oct 2026: `64a19faa`, `dd696c27`, `3e872afe` handover protocol / self-service gear sizes, `fc55561f` + `bf49a28b` docs gate,
`87bef6c2` + `cf824b36` i18n of contracts and app). Their backend halves are live; their app halves reach customers for the first time with 4.2.0.
They are not in the Q list, so they are listed below as ASK.

Legend: class C = cosmetic (text, i18n strings, layout, v2 branch `if (MgV2.on(context))` that only delegates to a v2 view with the same callbacks, refactor/hoist without behaviour change); F = functional.

## Table

| # | File | Hunk | Class | Request | Risk (old look / customer paths) | Test |
|---|---|---|---|---|---|---|
| 1 | reservations/reservation_provider.dart | `kGoogleReviewFallbackUrl`, `isGoogleReviewUrl`, provider accepts only https Google URLs | F | Q2 (Google-only review links) | Low. Non-Google DB value silently replaced by fallback. | none (no test references `isGoogleReviewUrl`) |
| 2 | reservation_provider.dart | `_fetchDoorCodes` first calls RPC `get_my_door_codes` (withheld codes without number), falls back to table select | F | none in Q list – docs gate (live backend 2026-10-10, RLS hides withheld codes) | Low; RPC exists live (STATE_3). Without it the withheld state would be invisible to 4.2.0. | none |
| 3 | reservation_provider.dart | door-code fetch errors are rethrown / stream keeps last value (`skipError`) instead of `[]` | F | Q3 | Low; card shows reason + Retry/Messages/Call instead of vanishing. | none |
| 4 | reservation_provider.dart | `filteredReservationsProvider` keeps cached list on refresh error | F | Q3 | Low. | none |
| 5 | reservation_provider.dart | `cancelBooking` → `CancelResult`: parses RPC `{success}`/`{error}` (4.1.3 ignored `{error}` and looked like success), 20 s timeout, on network error re-reads `bookings.status` + `booking_cancellations` | F | Q3 (meaningful result states), Q4 (pro-rata storno shown) | Medium: error mapping matches Czech texts of live `cancel_booking_tracked` (verified in 20261023e); `wrong_status` maps to "failed" and offers a Retry that can never succeed. | none (no test references `cancelBooking`/`CancelResult` logic; `cancelResultDialog` only in v2 sheet test) |
| 6 | reservation_provider.dart | `rated_at` written as UTC | F | Q2 (rating card shows rating date) | Low. | none |
| 7 | reservation_provider.dart | `handoverProtocolStateProvider` removed | F | none – owner commit 3e872afe (protocol only on kiosk display) | see #40 | – |
| 8 | reservation_provider.dart | SOS `typeLabel/statusLabel` → i18n keys | C | – | – | – |
| 9 | reservation_models.dart | `bookingKind` + `isGearOnly` from `booking_kind` | F | Q8-adjacent (gear-only backend is live; app-side guard used by ride recorder) | Low; defaults to 'moto'. | none |
| 10 | reservation_models.dart | `ModDescription` → enum + i18n, start/end shift via `calendarDaysInclusive` (DST) | F (DST) / C (texts) | DST part: none | Low; display only. | none |
| 11 | reservation_models.dart | moto name fallback translated, comments | C | – | – | – |
| 12 | reservation_detail_screen.dart | protocol banner (link to in-app protocol) removed | F | none – 3e872afe | see #40 | – |
| 13 | reservation_detail_screen.dart | 5 s refresh skipped offline; `skipError` + stale bar; loading/error/not-found states with back + Retry | F | Q3 | Low. | navigation_back_test.dart / error_states_other_test.dart do not reference this screen directly; v2 tests only |
| 14 | reservation_detail_screen.dart | `_restoreBooking` → `restoreAndPay` (booking_restore.dart) | F | Q4 (restore-and-pay fix) | see #17 | – |
| 15 | reservation_detail_screen.dart | contract / final invoice open via `runDocOpen` (progress, cancel after 15 s, double-tap guard, offline reason) | F | Q3 | Low. | none |
| 16 | reservation_detail_screen.dart | v2 branch → `ResDetailV2View` | C | Q5 | – | v2 tests |
| 17 | reservations/booking_restore.dart (new) | restore through RPC `customer_restore_booking` (server checks owner, dates, bike, vouchers, new 30-min pay window); refusal sheet per code; `not_cancelled` → re-read and go to payment | F | Q4 | HIGH dependency: RPC comes from `supabase/migrations/20261112a02_customer_restore.sql`, which is untracked (not in HEAD, not in origin/main). Until it is applied every restore shows "pdRestoreUpdating" (4.1.3 restored by direct UPDATE). | payments_paydec_test.dart, payments_payfix_test.dart cover only `restoreRefusalText`; no test of `restoreAndPay` flow |
| 18 | reservations_screen.dart | offline guard on 5 s timer, stale bar, `MgLoadingView`/`MgErrorView`, back arrow on tab root → Home | F | Q3 | Low. | none |
| 19 | reservations_screen.dart | cancel dialog keeps result in the same dialog, cannot be closed while cancelling | F | Q3 | Low. | none |
| 20 | reservations_screen.dart + widgets/reservation_card.dart | list card "Obnovit" → `restoreAndPay` (4.1.3: `context.go(Routes.search)`) | F | Q4 (D3 "obnovit a zaplatit") | Same dependency as #17 – affects the OLD look list too. | none |
| 21 | reservations/res_actions.dart (new) | `openBookingDoc` (as #15); `rebookSameMoto` keeps catalogue filter in v2 only, old look unchanged | F | Q3; Q5 (2026-10-22 no double entry) | Low. | v2/screens/reservations_r2_test.dart |
| 22 | reservations/ride_feedback.dart (new) | "Napiš nám přímo" → own `message_threads` + `messages` with marker `#XXXXXXXX` and stars | F | Q2 | Low; uses existing customer INSERT rights. | none |
| 23 | reservation_edit_screen.dart | first load: 15 s timeout, error screen with back/Retry (`EditStateScaffold`) | F | Q3 | Low. | none |
| 24 | reservation_edit_screen.dart | `?tab=swap` opens swap tab (target of "Vybrat jinou motorku") | F | Q4 (swap retry when bike taken) | Low. | none |
| 25 | reservation_edit_screen.dart | self-service gear size limit check in `_missingGearSizes` (`gearSizeSelfServiceLimit`) | F | none – 3e872afe "zadání majitele 2026-10-10" | Medium: blocks Save at a self-service branch when rider/passenger gear was touched or the bike moved to self-service and a stored size is outside S–3XL / ≤4XL. | none (`selfServiceSizeAllowed` untested) |
| 26 | reservation_edit_screen.dart | free move: 15 s timeout, after network error re-read dates (`_moveAppliedAfterNetError`), uncertain sheet, `showEditFailure` | F | Q3 | Low. | none |
| 27 | reservation_edit_screen.dart | availability tri-state (`checkMotoAvailabilityTri`) – outage ≠ occupied | F | Q3 | Low. | none |
| 28 | reservation_edit_screen.dart | card minimum `cardCharge`, `_card_rounding` in pending changes, `CardRoundingNote`, save label "pdSaveFree" | F | Q4 (D1) | Medium (money): relies on server/webhook adding rounding. | payments_paydec_test.dart (cardCharge) |
| 29 | reservation_edit_screen.dart | `blockIfSurchargePending` before surcharge and before direct save | F | Q4 (double charge protection) | see #33 | refix2_states_test.dart |
| 30 | reservation_edit_screen.dart | direct save: 20 s timeout, network error → `_editAppliedAfterNetError`, uncertain sheet; refund partial → `pdRefundManual`; error text via `showEditFailure` | F | Q3/Q4 (precise texts, no "contact us") | Medium, cross-area: the direct UPDATE path is unchanged from 4.1.3, but untracked SQL `20261112a07_guard_customer_booking_pricing.sql` silently pins an extension+cheaper-bike edit (more days, effDiff ≤ 0); the app then reports "saved" and calls process-refund. Whether process-refund refuses was not verified here. | payments_refund_partial_test.dart (`refundFellShort`) |
| 31 | reservation_edit_screen.dart + reservation_edit_address.dart (new) | address of the booking prefilled in AddressPickerWidget, quick picks (other side, profile) – both looks | F | Q5 (2026-10-22 never fill twice) | Low; unchanged address stays `null` (no fee, no history). Visible change in OLD look. | v2/screens/res_edit_address_test.dart |
| 32 | reservation_edit_screen.dart | sections hoisted into variables, v2 branch `ResEditV2View` | C | Q5 | – | v2 tests |
| 33 | widgets/reservation_edit_states.dart (new) | `EditStateScaffold`, `editFailureText`, `showEditUncertain`, `refundFellShort`, `blockIfSurchargePending` (PaidChangeQueue non-failed entry or 15-min PaymentPendingMarker blocks) | F | Q3/Q4 | Medium: a queue entry that never reaches done/failed keeps blocking edits and swaps of that booking (queue hard max 45 days). | refix2_states_test.dart, payments_refund_partial_test.dart |
| 34 | widgets/paid_change_banner.dart (new) | banner for paid swap/edit still being written; failed → "keep current / pick other" | F | Q4 (D6, swap completion with retry) | Low. | none for banner (queue: paid_change_queue_test.dart) |
| 35 | widgets/cancel_result_dialog.dart (new) | result/error dialog of storno (refund amount, uncertain, retry) | F | Q3/Q4 | Low. | v2/ux/res_profile_sheets_test.dart (v2 only) |
| 36 | widgets/res_cancel_dialog.dart | same as #19 for detail | F | Q3 | Low. | none |
| 37 | widgets/res_access_codes_card.dart | `skipError`, error with reason + Retry / Messages / Call; withheld reason localized | F (errors) / C (i18n) | Q3 | Low. | none |
| 38 | widgets/res_access_codes_card.dart | "protocolFirst" note no longer opens in-app protocol | F | none – 3e872afe | see #40 | – |
| 39 | widgets/res_detail_tab_content.dart | rating card `ResRatingCard` (stars + Google + "co máme zlepšit" for everyone), Google button moved into card, rating badge, `PaidChangeBanner`, `rebookSameMoto`, `openBookingDoc`; shortId double "#" fixed | F | Q2, Q4, Q3 | Low. | none for ResRatingCard |
| 40 | DELETED protocol_screen.dart, protocol_widgets.dart, protocol_gear.dart, handover_prompt_watcher.dart (+ #7, #12, #38) | customer can no longer fill/sign the handover protocol in the app; the kiosk prompt no longer opens it | F | none in Q list (owner commit 3e872afe, 2026-10-10, in origin/main) | Medium: 4.1.3 let a self-service customer sign in the app; with 4.2.0 only the kiosk display or Velín can sign, and the bike bay stays closed without a signed protocol (`protocol_required`). | none |
| 41 | widgets/res_payment_details_tab.dart | row `card_rounding` (+ minimum / − waived) | F | Q4 (D1) | Low; reads column only if present. | none |
| 42 | widgets/res_modification_history.dart | i18n, DST-safe day diffs, v2 colours | F (DST) / C | DST: none | Low. | none |
| 43 | widgets/edit_reservation_calendar.dart | extension end computed by calendar days (DST), v2 texts | F (DST) / C | DST: none | Low-medium: changes the OLD-look extension computation across a DST change (4.1.3 could shift the end by a day). | none |
| 44 | widgets/reservation_edit_extras_section.dart | `selfService` narrows size lists | F | none – 3e872afe | see #25 | none |
| 45 | widgets/reservation_swap_section.dart | `net > 0` (was > 0.5) goes to payment (waive ≤ 1 Kč handled by payment screen), `blockIfSurchargePending`, COMMIT 20 s timeout + dry-run verification after network loss, D5 texts via `PaymentRefusals.swapCodes`, `CardRoundingNote` | F | Q4 (D1, D5, swap completion) | Medium (money): sub-1-Kč swap now passes through payment screen waive path instead of direct commit. | payments_swap_taken_test.dart (swap taken), no test of `_swapCommittedAfterNetError` |
| 46 | widgets/res_rating_card.dart, res_rating_widgets.dart, ride_feedback_sheet.dart (new) | rating card, feedback sheet | F | Q2 | Low. | none |
| 47 | widgets/reservation_edit_confirm_page.dart | visible close button | F | Q3 | Low. | none |
| 48 | widgets/res_detail_button/card/row/location_row/pickup_procedure, reservation_edit_calendar_section, reservation_edit_widgets, reservation_edit_moto_section | v2 delegates, hoisted closures, i18n of hard-coded Czech | C | Q5 | – | v2 tests |
| 49 | documents/document_provider.dart | `scanDocumentWithRetry` progress callback + `retryOnNetwork`; `verifyCustomerDocs` 20 s timeout | F | Q3 | Low. | none |
| 50 | document_provider.dart | `uploadDocPhoto`: marker-row fallback removed, success requires `document_id` | F | none – docs gate (fc55561f) | Medium: in 4.1.3 a failed edge call still inserted a marker and the step passed; now the step fails and the customer retries. Live edge `save-verification-document` returns `document_id` (verified). | none |
| 51 | document_provider.dart, document_models.dart | localized warnings / labels → i18n keys | C | – | – | – |
| 52 | document_scanner_screen.dart | passport steps use `ScanDocType.passport` (was `idCard`) → `documents.type='passport'`, Mindee passport model | F | none – docs gate (fc55561f); related to Q7 | Low: photo is saved even if OCR fails; edge has `modelIdPassport`. | none |
| 53 | document_scanner_screen.dart + doc_scan_plan.dart (new) | modes `missing/missing_id/missing_dl` (only sides the gate lacks), `offerDlOnly` | F | Q5 (2026-10-22 never twice) | Low; on status failure falls back to full document. | v2/screens/docs_scan_plan_test.dart |
| 54 | document_scanner_screen.dart | `_finalize` asks `get_docs_gate_checklist`; honest toast (incomplete / codes still withheld / pending) | F | Q3 + docs gate | Low. | none |
| 55 | document_scanner_screen.dart | camera error view (settings/retry/back), progress text, diagnostics removed from customer text | F | Q3 | Low. | none |
| 56 | document_scanner_screen.dart | v2 choice screen with exact photo list | F (v2) | Q7 | – | v2/ux/scan_choice_text_test.dart, v2/ux/asm_sos_scan_test.dart |
| 57 | documents_screen.dart + docs_gate_provider.dart (new) + docs_gate_widgets.dart (new) | status from gate RPC (fallback profile), "missing" line, `codesReady = gate.ok` | F | none – docs gate | Low. | none (`docsGateMissingLabels` untested) |
| 58 | documents_screen.dart | gallery upload: new doc-kind picker (OP front/back, passport, ŘP front/back) before picking; offline check; progress with cancel; 150 s limit | F | docs gate (picker) / Q3 (rest) | Low-medium: one extra step in the OLD look; fixes 4.1.3 typing every gallery photo as OP without side. | v2/screens/profile_more_test.dart (picker render) |
| 59 | contracts_screen.dart + legal_doc_loader.dart (new) | VOP/GDPR/templates via RPC `get_document_translation` with freshness check; no local LegalTexts fallback (offline → "legalLoadFailed") | F | none – i18n (87bef6c2) | Low; RPC live since 20261011. | none |
| 60 | contracts_screen.dart, invoices_screen.dart | error/loading views, `docDisplayTitle`, list always shows static tiles | F (errors) / C | Q3 | Low. | none |
| 61 | doc_open_runner.dart (new), booking_doc_viewer.dart | global double-tap guard, progress + cancel, transient errors rethrown (not "not ready"); invoice not rendered without customer profile | F | Q3 | Low. | none |
| 62 | doc_webview_screen.dart, pdf_pages_screen.dart | refresh signed URL on retry, main-frame-only errors, error view, open-outside kept | F | Q3 | Low. | none |
| 63 | document_camera_screen.dart | painter colours parameterised, v2 back | C | Q5 | – | – |
| 64 | sos/sos_provider.dart | `SosIncident.motoId` | F | Q3 (replacement excludes own bike) | Low. | v2/fix_shared_r4_test.dart |
| 65 | sos_provider.dart | realtime via `resilientRealtime` | F | Q3 | Low. | none here |
| 66 | sos_provider.dart | `uploadSosPhotos` 40 s budget, per-photo try, partial result | F | Q3 | Low. | none |
| 67 | sos_provider.dart | `sosEndRide`, `sosContinueRide`, `uploadServiceInvoice` throw instead of returning false/null | F | Q3 (never "tow ordered" when not saved) | Low. | none |
| 68 | sos/sos_location.dart (new) + all SOS screens | `sosLocate` = `GpsService.locate()` capped at 20 s replaces `getCurrentPosition()` | F | Q3 (nothing hangs) | Medium: `_acquire` = 15 s high + 15 s low + last-known; the 20 s cap cuts the low-accuracy try and never reaches last-known, so in weak GPS an incident is sent without coordinates where 4.1.3 sent the last known position (customer sees "sent without location"). | none |
| 69 | sos_location.dart | `shareLocationNow`: no fix → explanation, NO `location_share` incident created (4.1.3 created one with null coords and said "shared") | F | Q3 | Medium: staff no longer get an alert row when GPS is off. | none |
| 70 | sos_replacement_motos.dart (new) + sos_replacement_screen.dart | only bikes free until booking end (`motoAvailableForRange`), not own bike, no trailer/maintenance/closed branch; server "taken" → pick other | F | Q3 (SOS replacement only really available) | Low. | v2/fix_shared_r4_test.dart |
| 71 | sos_here_address.dart (new) + sos_replacement_screen.dart | "Kde právě jsi" row: reverse geocode (Mapy.com, Nominatim) prefetched when permission already granted; address sent = field text (+GPS) | F | Q5 (2026-10-22 never fill twice) | Low; visible in OLD look too. | v2/sos_address_test.dart, v2/shared_carry_test.dart |
| 72 | sos_report_screen.dart + sos_report_sheet.dart (new) + sos_feedback.dart (new) | progress dialog, retry dialog, photos best-effort, submit allowed without photo only when camera unusable | F | Q3 | Low. | v2/ux/asm_sos_scan_test.dart (v2) |
| 73 | sos_immobile, sos_breakdown_immobile, sos_service, sos_theft screens | retry dialogs, tow/replacement only confirmed after save, invoice upload reason + Messages | F | Q3 | Low. | none |
| 74 | sos_detail_screen.dart | error → error view (4.1.3 showed the "done" view), continue-ride error dialog, back arrow on done view | F | Q3 | Low. | none |
| 75 | sos_timeline_i18n.dart (new) | localize staff timeline texts | C | – | – | – |
| 76 | all SOS screens | v2 delegates / `mgV1Back` / `mgV1PageColor` | C | Q5 | – | v2 tests |

## Counts
Files 66 (41 modified, 21 added, 4 deleted). Functional rows in the table: 67 (rows group one change across files where noted).
Requested (Q2, Q3, Q4, Q5, Q7): 52. Not in the Q list: 15 rows (#2, #7, #9, #10, #12, #25, #38, #40, #42 DST part, #43 DST part, #44, #50, #52, #57, #59; #58 picker part) - 13 of them come from owner-era commits already in origin/main (3e872afe, fc55561f/bf49a28b, 87bef6c2), 2 are DST bug fixes, 1 is the gear-only guard.
UNREQUESTED with nothing depending on it: none found (every not-listed row is either needed by a live backend change or is a bug fix). UNSURE: 6 grouped candidates. Requested but risky: 6.
Tests: no test was run for this audit; test files named above were located by symbol search only.

## Candidates returned to the orchestrator
See structured result (app-res-1 … app-res-12).

- app-res-1 (ASK): in-app handover protocol removed (#7, #12, #38, #40).
- app-res-2 (ASK): self-service gear size limits in reservation edit (#25, #44).
- app-res-3 (ASK, recommend keep): docs-gate app side (#2, #50, #52, #57, #58 picker, #54).
- app-res-4 (ASK): legal texts via RPC without offline summary (#59).
- app-res-5 (ASK): DST calendar-day fixes (#10, #42, #43).
- app-res-6 (ASK, recommend keep): booking_kind / isGearOnly (#9).
- app-res-7 (KEEP): restore-and-pay depends on untracked SQL 20261112a02 (#17, #20).
- app-res-8 (KEEP): SOS location 20 s cap loses last-known fallback (#68).
- app-res-9 (KEEP): share location without fix creates no incident (#69).
- app-res-10 (KEEP): blockIfSurchargePending can block a booking for long (#29, #33, #45).
- app-res-11 (KEEP): cancelBooking result parsing untested; wrong_status offers useless Retry (#5).
- app-res-12 (KEEP, cross-area): direct edit UPDATE vs new SQL guard a07 (#30).
