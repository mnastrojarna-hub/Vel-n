# Functional-diff audit: app-ios (Motogo-app-main/motogo-app-flutter-ios)

BASE = 70a94933 (app 4.1.3 in the field). HEAD = claude/moto-go-mobile-conversion-gqg5qo. Working tree of the iOS tree is clean (git status prints nothing), so HEAD = what will be built.

## (a) diff -rq of both lib directories
Verified: it prints exactly the 20 expected lines (19 "differ" + "Only in ...-ios/lib/features/payment/widgets: apple_pay_failure.dart"). No other file differs. assets/: the only difference is the iOS-only assets/app_icon.png, unchanged since BASE.

## (b) Platform difference now vs at BASE (diff Android vs iOS at HEAD compared with the same diff at BASE)
| File | Result |
|---|---|
| translations_uk_main.dart | identical platform difference to BASE |
| translations_cs_pl / en_de_nl / es_fr | only the iOS-only key cardsSavedAtCheckout differs between trees (as at BASE). Context lines changed because shared text was edited in both trees identically (cardsSecuredByStripe got a second sentence in all languages); the iOS cs text itself changed from "Kartu uložíte…" to "Kartu uložíš…" (informal-address i18n work already in origin/main). Text only. |
| offline_guard.dart | difference is still only the connectivity_plus 5 API (single ConnectivityResult); now isolated in one helper `_isNone(ConnectivityResult)` instead of two inline comparisons. Same platform difference, refactored. |
| onboarding_overlays.dart | iOS still has the single "Pokračovat" button, no Skip, no Back (App Store 5.1.1(iv)), v2 branch keeps that too (OnboardingPermV2 without onSkip/onBack). Android gained an onBack (back to language picker) that iOS deliberately does not have. Documented platform difference, consistent with BASE intent. |
| update_check_provider.dart | same platform part (App Store URL id6806045151 / _storeUrl). |
| map_picker.dart, places_map, ride_map, route_map, route_navigation_screen | difference = userAgentPackageName only, byte-identical to BASE difference. |
| community_submit, route_builder_screen, route_submit_screen | difference = userAgentPackageName only (line moved by shared edits). |
| payment_error_mapper.dart | difference = `dart:io Platform` import + Google Pay -> Apple Pay substitution in `_t`; same as BASE. All wallet texts (incl. new pdWalletDeclinedBody) are only reached through `_t`, so iOS never shows "Google Pay" (verified by grep of translation keys containing Google Pay and their call sites). |
| payment_methods_screen.dart | iOS still has no manual card entry: old look unchanged in that respect, v2 passes `onAdd: null` and the cardsSavedAtCheckout notes (Android passes `_addNewCard`). Same platform difference. |
| card_payment_sheet.dart | Apple Pay branch (always visible PlatformPayButton, _tapApplePay, _handleApplePayFailure, _WalletGuard.uncertain, `_applePayAmount`) kept; v2 sheet renders the same Apple Pay button under the same condition; iOS-only v2 dialog for the ApplePayFailureAction.stay case. Android uses `_SubmitGuard.submitting`, iOS `_WalletGuard.uncertain` with equivalent set/reset points (begin submit / finish / not completed / stay). Same platform difference, both trees got the same Q4 logic. |
| main.dart | difference = edge-to-edge block (Android only), nav bar black vs transparent, merchant id `merchant.cz.motogo24.rental`, and the PermissionOverlay onSkip/onBack arguments (Android only, App Store rule). v2 wiring (MgV2Gate, MgV2Scope, IntroV2, CrashViewV2, AppV2UiNotifier.preload) is identical in both. |
| apple_pay_failure.dart (iOS only) | unchanged since BASE. |

No drift beyond the documented platform parts was found.

## (c) Non-lib files
- pubspec.yaml: only `version: 4.1.3+116 -> 4.2.0+117` and comment text. No dependency line changed (Android pubspec also has no dependency change). iOS pins intact.
- pubspec.lock, ios/** (Runner, Info.plist, entitlements, Podfile), .dart_tool, codemagic.yaml: no change vs BASE.
- README.md, APPLE_RELEASE_SETUP.md: version text only.
- New native needs: none. Ride recording background location (AppleSettings allowBackgroundLocationUpdates) was already present at BASE (moved from ride_recorder.dart to ride_location.dart); Info.plist already has UIBackgroundModes location and NSLocation* strings. New MethodChannel uses (cz.motogo24/ride, cz.motogo24/pdf) are guarded to Android only.
- flutter analyze --no-pub in the refreshed scratch copy: 137 issues, 0 errors (= baseline). So all new shared Dart code compiles against the pinned iOS packages (connectivity_plus 5, flutter_stripe 11, geolocator 10 …), including the Android test/ directory.
- Targeted tests run in the iOS scratch copy (shell_home_onboarding, ps_sheets, payment_error_states, payments_3ds_decline, payments_paydec, payments_payfix, refix3_states, ride_location): 92 passed, 0 failed. Note: tests run on the Linux host, so `Platform.isIOS` is false; the Apple Pay branches are not executed by any test.

## Hunk table (iOS-relevant files; the ~845 shared byte-identical files are audited in the Android area)
| File | Hunk | Class | Request | Risk (old look / customer paths) | Tests |
|---|---|---|---|---|---|
| translations_* (4) | text edits | cosmetic | Q1/Q4 texts | none | - |
| core/offline_guard.dart | overlay with Retry result, "Pokračovat bez internetu", call MotoGo/112, thin banner, reachability ping, back closes overlay | FUNCTIONAL | Q3 (2026-10-16 nothing hangs) | low; booking/payment still guarded by requireOnline (resets _dismissed) | refix3_states_test, payment_error_states_test (partial) |
| core/offline_guard.dart | onBackOnline hook (recover providers, drain PaidChangeQueue, map tile retry) | FUNCTIONAL | Q3 + Q4 D6 | low | none specific |
| core/offline_guard.dart | `_isNone` helper for connectivity_plus 5 | cosmetic (platform) | rule 3 | none | analyze |
| core/offline_guard.dart | v2 OfflineViewV2 / OfflineStripV2 | cosmetic v2 | Q5 | none with flag off | v2 tests |
| core/overlays/onboarding_overlays.dart | LanguageOverlay applies chosen locale immediately + currency follows language | FUNCTIONAL | UNSURE (origin/main i18n commit 87bef6c2) | first-launch currency display may switch to EUR/PLN; charges stay CZK | shell_home_onboarding_test (v2 only) |
| core/overlays/onboarding_overlays.dart | v2 language/permission boards (iOS keeps single Continue) | cosmetic v2 | Q5 | none | shell_home_onboarding_test |
| core/update_check_provider.dart | force-update dialog: store-open failure text, call MotoGo/112 | FUNCTIONAL | Q3 | none (still blocking) | none |
| core/update_check_provider.dart | v2 dialog | cosmetic v2 | Q5 | none | render cases |
| features/booking/widgets/map_picker.dart | tile error reporting + chip | FUNCTIONAL (state) | Q3 | none | none |
| features/booking/widgets/map_picker.dart | v2 chrome; texts via i18n; MgBackTap | cosmetic / Q5 | Q5 | none | cb_booking_sheets_test |
| features/payment/payment_error_mapper.dart | never show raw Stripe text, needsVerification/uncertain, wallet flag, new codes | FUNCTIONAL | Q4 (precise errors, double-charge) | low; iOS substitution intact | payment_error_states_test, payments_3ds_decline_test, payments_payfix_test |
| features/payment/payment_methods_screen.dart | back fallback to Profile when no history | FUNCTIONAL (nav) | Q3 | none | none |
| features/payment/payment_methods_screen.dart | loading/error views with retry | FUNCTIONAL (state) | Q3 | none | none |
| features/payment/payment_methods_screen.dart | v2 view (onAdd null on iOS) | cosmetic v2 | Q5 | none | ps tests (Android path) |
| features/payment/widgets/card_payment_sheet.dart | onSubmitting marker before charge | FUNCTIONAL | Q4 double-charge | low | payments_paydec_test |
| features/payment/widgets/card_payment_sheet.dart | sheet locked during processing (PopScope, drag absorbed); dismissal while unknown = processing | FUNCTIONAL | Q4 double-charge | medium on iOS: Apple Pay path not covered by tests | ps_sheets_test (card path only) |
| features/payment/widgets/card_payment_sheet.dart | "not completed" note after 3DS/wallet cancel; visible close X | FUNCTIONAL (state/nav) | Q3/Q4 | low | ps_sheets_test |
| features/payment/widgets/card_payment_sheet.dart | `wallet` flag on result | FUNCTIONAL | Q4 | low | payment_error_states_test |
| features/payment/widgets/card_payment_sheet.dart | pay button amount via Money.czk (selected display currency) instead of fixed "Kč" | FUNCTIONAL (displayed amount) | UNSURE (origin/main) | customer with EUR display sees "Zaplatit 52,00 €" while Apple Pay sheet / charge is CZK | none |
| features/payment/widgets/card_payment_sheet.dart | v2 sheet + iOS-only v2 Apple Pay info dialog | cosmetic v2 | Q5 | none flag off | ps_sheets_test (no iOS path) |
| features/routes/* (7 map files) | shared changes (roads routing, GPS gap estimate, etc.) | FUNCTIONAL | Q7 | see Android area | see Android area |
| main.dart | crash screen with Back/Home | FUNCTIONAL | Q3 | none | none |
| main.dart | TimeoutClient on Supabase http (20-120 s per path) | FUNCTIONAL | Q3 | process-payment default 30 s: a slow charge reports timeout; relies on Q4 verification path | timeout tests in Android area |
| main.dart | PaidChangeQueue drain on resume/online | FUNCTIONAL | Q4 D6 | low | Android area |
| main.dart | recoverFailedProviders on resume/online | FUNCTIONAL | Q3 | low | none |
| main.dart | ForcedSignOut.pending on session expiry | FUNCTIONAL | Q3 | low | none |
| main.dart | mgSafeRouterConfig (3DS return deep link) | FUNCTIONAL | Q4 | low | Android area |
| main.dart | EngagementService (Velin app funnel visits) | FUNCTIONAL | UNSURE (origin/main) | extra network writes; low | none |
| main.dart | NotificationHandler before PushService.initialize; push re-init on resume / signedIn / after permission overlay | FUNCTIONAL | UNSURE (origin/main bug fix) | low | none |
| main.dart | Money.init falls back to mg_locale | FUNCTIONAL | UNSURE (origin/main i18n) | display currency only | none |
| main.dart | HandoverPromptWatcher removed (kiosk-forced in-app handover protocol, route /protocol, ProtocolScreen deleted) | FUNCTIONAL | UNSURE: origin/main commit 3e872afe ("protokol jen na displeji", kiosk 1.2.11), not in Q1-Q7 | app 4.2.0 can no longer fill the handover protocol; any self-service flow that still expects the app to sign it would stall | none |
| main.dart | MgV2Gate / MgV2Scope / IntroV2 / CrashViewV2 / preload | cosmetic v2 + kill-switch | Q5 | gate itself is functional (switch only at safe moment) | v2 gate tests (Android area) |
| core/router.dart (iOS-only branch) | routerSwipeBackPage: on iOS MaterialPage (swipe back + slide) even with flag off for /booking, /routes list etc.; BASE used NoTransitionPage | FUNCTIONAL (nav, iOS only, old look) | Q3 (2026-10-16 "back everywhere") | an accidental left-edge swipe leaves the booking form; tests run with Android platform so no test covers the iOS branch | none |
| pubspec.yaml | version 4.2.0+117 | release | release | none | - |

## Counts
Files changed in area: 867 (864 under lib/, of which 19+1 are iOS-specific and audited here; 3 non-lib: pubspec.yaml, README.md, APPLE_RELEASE_SETUP.md). Functional hunks in the iOS-specific files + iOS-only router branch: 34; requested 27; unrequested 0; unsure 7 (all originate from origin/main, not from this branch).
