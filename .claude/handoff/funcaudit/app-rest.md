# Functional-diff audit — area app-rest (BASE 70a94933 → HEAD, Android tree)

Scope: lib/features/{auth,branches,catalog,home,loyalty,messages,profile} (non-v2 files), lib/main.dart,
lib/core/i18n (existing keys only), pubspec.yaml, android/**, assets.
Method: `git diff 70a94933 HEAD` per file, every hunk read. Commit origin checked per file
(MAIN = commit already in origin/main, merged earlier by another session; BR = only on this branch).
Tree parity: `diff -rq` of both lib/ trees prints exactly the 20 allowed lines (verified).
Assets: no changes. pubspec.yaml: only version 4.1.3+116 → 4.2.0+117 (no dependency change).

Classes: COS = cosmetic (text/style/layout/refactor without behaviour change), FUNC = functional.
"v2 branch" = code that only runs when MgV2.on/peek is true (kill-switch on); old look unaffected.

## Android native / config

| # | File / hunk | Class | Request | Risk (old look / customer paths) | Test |
|---|---|---|---|---|---|
| N1 | MainActivity.kt: provideFlutterEngine/createFlutterFragment/onStart/onDestroy/cleanUpFlutterEngine + RideEngineKeeper.kt (new) + KeepEngineFlutterFragment.java (new) + proguard keep rule (commits d166e684, 04f8d090, BR) | FUNC | UNSURE (Q6-adjacent: ride recording keeps running after the window is closed; not in the Q6 list) | Every Android launch now gets its engine from custom code (new FlutterEngine + custom fragment that never destroys the engine itself; MainActivity.onDestroy destroys it unless a ride is recording). A mistake here breaks app start / back / deep links for all Android customers, independent of the kill-switch. Code reviewed: mirrors the default FlutterFragmentActivity builder (flutterShellArgs omitted — debug only). | none (native, no test) |
| N2 | pubspec.yaml version bump | COS | release | none | — |

## lib/main.dart

| # | Hunk | Class | Request | Risk | Test |
|---|---|---|---|---|---|
| M1 | ErrorWidget.builder: Back/Home buttons, translated texts, v2 CrashViewV2 | FUNC | Q3 (way back) + Q5 | low | navigation_back_test (partly) |
| M2 | Supabase `httpClient: TimeoutClient(...)` — per-request limits (20 s REST/auth, 30 s RPC/edge default, 45–90 s some edge fns, 120 s storage, 30 s body idle) | FUNC | Q3 (nothing hangs) | Global: any request that used to succeed slowly now fails at the limit (large storage uploads on weak LTE, slow edge fns). process-payment is called via its own http client, not affected. | error_states_other_test (limits + timeout unit only) |
| M3 | Money.init default lang falls back to `mg_locale` | FUNC | UNREQUESTED (i18n, MAIN 87bef6c2) | very low | none |
| M4 | AppV2UiNotifier.preload, MgV2Gate around router child, MgV2Scope around onboarding overlays, IntroV2 when v2 | FUNC | Q5 (kill-switch) | gate decides look for whole app | test/v2 (gate tests) |
| M5 | EngagementService.start/onLifecycle/onUserPointer (insert into web_engagement once a day) | FUNC | UNREQUESTED (Velín App funnel, MAIN 8d29aa87) | low: all errors swallowed, debug builds disabled | none |
| M6 | OfflineGuard.onBackOnline → recoverFailedProviders + PaidChangeQueue.drain | FUNC | Q3 + Q4 (D6) | low | paid_change_queue_test(s) |
| M7 | NotificationHandler.initialize moved before PushService.initialize (cold-start tap) | FUNC | UNSURE (bug fix) | low | none |
| M8 | On resume: PushService.initialize, recoverFailedProviders, PaidChangeQueue.drain | FUNC | push: UNSURE; others Q3/Q4 | push init is idempotent and never re-requests permission (verified in push_service.dart) | none for push |
| M9 | signedOut(sessionExpired)/tokenRefreshed null → ForcedSignOut.pending (login explains why) | FUNC | Q3 | low | none |
| M10 | signedIn → PushService.initialize | FUNC | UNSURE (push token fix) | low | none |
| M11 | after permission overlay → PushService.initialize + reportToProfile | FUNC | UNSURE (push token fix) | low | none |
| M12 | routerConfig: mgSafeRouterConfig (Stripe 3DS return link) | FUNC | Q4 | low | navigation_back_test (custom-scheme group) |
| M13 | HandoverPromptWatcher removed (app no longer opens the handover protocol) | FUNC | UNSURE — MAIN 3e872afe "protokol jen na displeji (kiosk 1.2.11)"; kiosk/edge side already live | removal matches live kiosk; reverting would bring back a deleted screen | none |
| M14 | PermissionOverlay onBack → back to language choice (Android only; iOS keeps App-Store variant) | FUNC | Q3 | low | none |
| M15 | Listener.onPointerDown also EngagementService | FUNC | see M5 | — | — |

## features/auth

| # | File / hunk | Class | Request | Risk | Test |
|---|---|---|---|---|---|
| A1 | auth_error_mapper: sign-in variants of network/rate/server bodies; raw exception text no longer shown (logged instead) | FUNC | Q3 | low | refix3_states_test |
| A2 | auth_error_mapper cs/other strings reworded (vykání→tykání, wording) | COS (text) | UNREQUESTED tone change (see T2) | none functional | — |
| A3 | _t falls back to shared translations | FUNC | Q3 support | none | refix3_states_test |
| A4 | AuthService._tr falls back to English for non-cs | FUNC | UNREQUESTED i18n | very low | none |
| A5 | signin_failed log adds detail for unknown errors | FUNC | Q3 | none | none |
| A6 | registration: language normalised (normalizeAppLang); CHECK violation on 'uk' → retry with 'en' (RPC and fallback update) | FUNC | UNREQUESTED i18n (MAIN 87bef6c2) | registration path; only changes value written to profiles.language; failure never blocks registration | none |
| A7 | resetPassword: language from mg_language; error texts via FriendlyError | FUNC | Q3 (+i18n) | low | none |
| A8 | recoveryInProgress flag; router does not redirect /reset-password during recovery (step 3 "new password" now reachable) | FUNC | Q3 (flow fix) | login/password path; flag reset in dispose and after success; router exception untested | none |
| A9 | verifyOtp/updatePassword: friendly messages (PasswordFlowErrors, new file) | FUNC | Q3 | low | none |
| A10 | bioRestoreSession returns ok/offline/invalid; offline keeps biometric data | FUNC | Q3 | low | none |
| A11 | biometric_service.authenticateResult: lockedOut/notEnrolled/unavailable | FUNC | Q3 | low | none |
| A12 | login_screen: ForcedSignOut toast; bio messages per reason; v2 branches | FUNC | Q3 / Q5 | low | asm_auth_test (v2) |
| A13 | login ↔ register carry e-mail (`?email=`), initialEmail params | FUNC | Q5 (never fill twice) — applies also in old look | low | shared_carry_test |
| A14 | register_screen: system back = step back; leaving dirty step 1 asks confirmDiscard; PopScope + BackButtonListener | FUNC | Q3 | registration path: back interception; no test of the old-look back on step 1 | navigation_back_test (confirmDiscard dialog only) |
| A15 | register_screen v2 field errors (_invalid), welcome overlay v2 | FUNC (v2 branch) | Q5 | none for old look (v1 shows the same toasts) | asm_auth_test |
| A16 | reset_password_screen: system back = step back; v2 field errors; error titles | FUNC | Q3 / Q5 | low | asm_auth_test |
| A17 | login_buttons/header/footer, register_name_row: FittedBox/Wrap, name fields stack when label does not fit | COS | — | — | auth_fit_test |
| A18 | login_footer web link per app language | FUNC | UNREQUESTED i18n | none | none |
| A19 | toast_helper: v2 toast | FUNC (v2 branch) | Q5 | none | asm_auth_test |

## features/branches

| # | Hunk | Class | Request | Risk | Test |
|---|---|---|---|---|---|
| B1 | branch_detail/branches_info/motos/photos: v2 views; handlers extracted unchanged | FUNC (v2 branch) | Q5 | none old look | res_profile_more_test, fix_shared_test |
| B2 | branchesInfoDefaults: return/fuel text (staffed: no wash/fuel, reserve light; self-service: washed, reserve off, no full tank) | text | Q1 (identical to live web pobocky.php) | none | — |
| B3 | branchesInfoDefaults: helmet sizes S–3XL text | text | UNSURE (MAIN 3e872afe gear limits, live) | none | — |
| B4 | branchesInfoProvider: missing translation → English before Czech | FUNC | UNREQUESTED i18n | none | none |
| B5 | branchesBack helper + MgBackTap | COS | Q3 | none | navigation_back_test |

## features/catalog

| # | Hunk | Class | Request | Risk | Test |
|---|---|---|---|---|---|
| C1 | bookedDatesProvider 15 s timeout; checkMotoAvailabilityTri (free/busy/unknown) + bool wrapper unchanged semantics | FUNC | Q3 | low | none direct |
| C2 | moto_detail_page: moto gone / loading (15 s retry) / error states with back | FUNC | Q3 | low | refix3_states_test |
| C3 | moto_detail_page: detailStartDates/_followDraftDates/_pickRange share dates (v2 only; old look = filter dates as before) | FUNC (v2 branch) | Q5 (2026-10-22 no double filling) | none old look | catalog_carry_test, home_carry_test |
| C4 | REZERVOVAT → startBookingFromSelection (old look body identical; additionally writes bookingDraftOwnerProvider) | FUNC | Q5 | booking entry path; old-look body verified equal | booking_prefill_flow_test |
| C5 | moto_detail_screen / gallery / video / calendar / manual / validation banner v2 branches | FUNC (v2 branch) | Q5 (+Q7 swipe in detail) | none old look | catalog_* tests, cb_catalog tests |
| C6 | moto_search_screen: back arrow → Home; loading/error states | FUNC | Q3 | none | none |
| C7 | moto_filter_panel: refactor to shared option lists/range models + embedded v2 sheet | COS (old look) / v2 | Q5 | refactor of old filter panel; behaviour verified equal by reading | cb_catalog_test, lookonly_core_test |
| C8 | specList/day labels translated (moto_model, pricing_table), validation banner lang | FUNC | UNREQUESTED i18n | none for cs | catalog_fit_matrix_test |
| C9 | catalog_screen.dart deleted (was imported but never used in BASE router) | COS | — | none | compile |

## features/home

| # | Hunk | Class | Request | Risk | Test |
|---|---|---|---|---|---|
| H1 | home_actions.dart: refreshHome/warmUpRoutes extracted unchanged | COS | — | none | — |
| H2 | home_screen error → MgErrorView with retry | FUNC | Q3 | none | none |
| H3 | nickname dialog: Cancel button added, "Reset" label translated, v2 dialog | FUNC | Q3 / Q5 | none | none |
| H4 | home_reservation_card: dead comparison with 'PŘIPRAVENO' removed (BASE label was 'NADCHÁZEJÍCÍ', never matched) | COS | — | none | — |

## features/loyalty

| # | Hunk | Class | Request | Risk | Test |
|---|---|---|---|---|---|
| Y1 | rank names localised (rank_names.dart; rank card, ranks screen, level-up overlay) | FUNC | UNREQUESTED i18n (MAIN 87bef6c2); cs unchanged | none for cs; touches level-up overlay text only | none |
| Y2 | ranks screen loading/error with back + retry | FUNC | Q3 | none | wiring_test |
| Y3 | leaderboard v2; rules sheet close row | FUNC (v2) / Q3 | Q5 / Q3 | none | test/v2 |

## features/messages

| # | Hunk | Class | Request | Risk | Test |
|---|---|---|---|---|---|
| G1 | threads/admin streams via resilientRealtime | FUNC | Q3 | low | none |
| G2 | timestamps written as UTC (last_message_at, read_at) | FUNC | UNSURE (bug fix: local time without zone stored 1–2 h off) | low | none |
| G3 | AdminMessage title/message_translations (columns do not exist yet; falls back to title/message) | FUNC | UNREQUESTED i18n | none | none |
| G4 | sendMessage returns error object; toast with reason, text kept | FUNC | Q3 | none | none |
| G5 | createThread errors surfaced + retry (_createAndOpen) | FUNC | Q3 | retry after lost response could create a second thread | none |
| G6 | thread_detail: future cached; loading/error/gone states; texts translated | FUNC | Q3 | low | none |
| G7 | messages_screen loading/error states; v2 view; sheet close row | FUNC | Q3 / Q5 | none | profile_sub_test |
| G8 | ai_agent: retry same message+photos, "still thinking" after 20 s, error kinds, SOS hint on error, lang normalised, photo-pick error reason | FUNC | Q3 | low | profile_sub_test |

## features/profile

| # | Hunk | Class | Request | Risk | Test |
|---|---|---|---|---|---|
| P1 | save: set_my_license_group failure now shown (not "Uloženo") | FUNC | Q3 | none | none |
| P2 | menu visible during loading/error; personal form only when loaded | FUNC | Q3 | none | profile_hub_test |
| P3 | back arrow in old header → Home | FUNC | Q3 | none | none |
| P4 | DOB dropdown last year = now−18 (was −15), saved younger year kept | FUNC | UNSURE (18+ doc gate, MAIN bf49a28b/fc55561f, live) | none | none |
| P5 | delete-account error reason; v2 destructive dialog | FUNC | Q3 / Q5 | none | none |
| P6 | consent sheet: load timeout/error/retry, save error in sheet, save disabled while loading | FUNC | Q3 | none | profile_more_test |
| P7 | change-password sheet: errors in sheet, busy state, sheet stays open on error | FUNC | Q3 | none | profile_more_test |
| P8 | language/currency sheets v2 + close row; currency label CZK (CNB) outside cs | FUNC | Q5 / i18n | none | profile_more_test |
| P9 | requestAllPermissionsAndReport (perm_result.dart): real result instead of "re-requested" | FUNC | Q3 | none | none |
| P10 | permissions_screen / branches_sheet v2 | FUNC (v2 branch) | Q5 | none | test/v2 |

## lib/core/i18n — existing keys whose text changed (BASE vs HEAD, evaluated by dumping the merged `translations` map of both versions)

No key removed; 64 existing keys changed:
- T1 (feature alignment with live backend, MAIN): codesStillWithheld, docPhotoSavedNoOcr (doc gate 18+/front+back, bf49a28b); protocolFirst ("on the branch display", 3e872afe); hpMotoGearNote (dd696c27; key not used anywhere in lib).
- T2 (Czech vykání → tykání, no meaning change, 668651c9 Q3 round): aiCommError, changesSaved, checkEmail, deleteAccountFailed, docRemoved, doorCodesUnavailable, errCameraGeneric, errCameraPermission, errImagePrep, errNetwork, errNoFieldsHint, errOcrEmpty, errServerConfig, errServerGeneric, errServerUpstream, errTimeout, errUnknown, extrasBaselineFailed, gpsErrorManual, gpsUnavailableManual, locationSharedMsg, moveErrCustomerOverlap, moveOccupiedRange, noMotoSelected, notLoggedIn, offlineDesc, refundSettleManual, saveWarning, selectDatesFirst, sessionExpired (also reworded), shopProductUnavailable, sosNoMotos, swap.err.alreadySplit, tryAgainOrSkip, tryAgainPlease, writeFirstMessage.
- T3 (Q1 return rule): procStepImportant (all langs: washed + reserve light off, no full tank).
- T4 (Q4 precise error text): cardSaveFailed (all langs).
- T5 (translations synced to existing Czech meaning, cs unchanged): bookingOverlapError (pl,en), cardSavedInApp, cardsSecuredByStripe, endRideTowDesc, priceVatNote, homeFilterLicenseAM, gateNotice/procStep1Code/procStep1NoCode (en wording), codeCorrect (nl).
- T6 (uk: Kč → CZK): amountMin, cartFab, currentlyRefund, deliveryFeeExplain, deliveryFrom, deliveryPrice, deliveryPriceInfo, faultPaidInfo, pricingCurrencyPerDay, replacementPaidDesc, shippingPostInfo, theftSecuredInfo.

## Counts
Files in area with changes: 58 (4 android files, pubspec.yaml, lib/main.dart, 52 feature files) plus 91 changed i18n files (existing-key check only: 64 existing keys changed, 0 removed).
Functional hunks (FUNC rows above, v2-only branches included): 64. Requested: 47. Unrequested: 9 (M3, M5, A4, A6, A18, B4, C8, Y1, G3 — all i18n or analytics) plus text-only T2 (tykání) and T6 (uk CZK). Unsure: 8 (N1, M7, M8 push part, M10, M11, M13, G2, P4) plus text-only B3 and T1.
Requested-but-risky: M2 (global timeout), A8 (password-reset router exception), A14 (register back interception), C4 (booking entry), G5 (thread retry duplicate).
