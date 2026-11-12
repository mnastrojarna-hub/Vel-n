# Functional-diff audit — area app-core

Scope: `Motogo-app-main/motogo-app-flutter/lib/core` without `lib/core/v2` and `lib/core/i18n`, plus `lib/main.dart`. Android tree.
Base: `70a94933` ("Appka: verze 4.1.3", 2026-10-10). Head: `7dfea18c` on `claude/moto-go-mobile-conversion-gqg5qo` (the last three commits changed only the handoff notes; the code of this area is the same as at `6ffc247c`).
Method: `git diff --stat` / `--numstat` for the list of files, then every hunk read. `router.dart` and `app_shell.dart` were compared as whole files (the base file next to the new file and the new `shell_*.dart` files). No code in the repository was edited. Three probes and sixteen existing test files were run in a private copy of the Android tree in the scratchpad.

## Summary

- 62 files changed: 25 added, 1 deleted, 36 modified; 6624 lines added, 2375 removed.
- 96 functional hunks, 19 v2 look seams, 10 cosmetic hunks.
- Of the 96 functional hunks, 69 serve a request Q1–Q7, 23 come from other owner topics that are not in the Q1–Q7 list (UNSURE), and 4 are small corrections without a named request (UNREQUESTED).
- Classes in the table: C = cosmetic (text, layout, moved code, dead code), V = v2 look seam (`MgV2.on(context) ? v2 view : old tree`, the same handlers go to both), F = functional.
- The iOS tree holds the same code. `diff -rq` of both `lib/core` trees without `i18n` and `v2` prints only the three allowed platform files (`offline_guard.dart`, `overlays/onboarding_overlays.dart`, `update_check_provider.dart`); `main.dart` differs in 20 lines. Every file named in the findings below is byte-identical in both trees, or (for `main.dart` and `onboarding_overlays.dart`) contains the same lines.

### Where the hunks outside Q1–Q7 come from

All of these commits are ancestors of `origin/main`; none of them is in the released 4.1.3. The pull request is the first merge on the first-parent line of `origin/main` that contains the commit.

| commit | date | subject | pull request |
|---|---|---|---|
| `3e872afe` | 2026-10-10 | Samoobsluha: velikosti výbavy dle pobočky, protokol jen na displeji (kiosk 1.2.11) | #2182 |
| `a6e40b80`, `3e92168c` | 2026-10-10 | drobné opravy z review brány dokladů | #2192 |
| `87bef6c2`, `cf824b36` | 2026-10-11 | i18n: jazyk smluv / e-mailů / AI, appka (oba stromy) | #2194 |
| `8d29aa87` | 2026-10-15 | App funnel: návštěvy vs. zahájeno + spočítaná cena | #2206 |
| `d166e684` | 2026-10-15 | Záznam jízdy: robustní GPS, diagnostika ve Velínu | #2208 |
| `668651c9`, `15673b9b` | 2026-10-16 | chybové a výsledkové stavy, navigace zpět (the Q3 round) — also carries the push-notification fixes, which Q3 does not name | #2212 |

## Findings that need a decision

The same list is returned in the structured result. Proposal KEEP = requested, keep it, but the named defect or missing test must be handled before the release; ASK = deliberate change that I cannot tie to Q1–Q7.

| id | what | proposal |
|---|---|---|
| app-core-1 | Address carry between delivery and collection: when both sides are "on address" with the same address, editing EITHER side rewrites BOTH (address and fee). A customer cannot book delivery to one address and collection from another; 4.1.3 allowed it. Both looks, both trees. Proven by a probe. | KEEP the request, fix before release, add the missing test |
| app-core-2 | The app's own cleanup (`CacheCleanupService`, runs at every start and every time the app goes to the background) erases the new local records of this branch: the "payment sent" marker, the queue of paid swaps / edits, the stored kill-switch value and the analytics day token. Only the three ride keys were added to the keep-list. Proven by a probe. | KEEP the requests, fix before release (add the keys), add the missing test |
| app-core-3 | The 2026-10-22 "never fill twice" changes are active in the OLD look too (kill-switch off): address carry and quick options, passenger sizes prefilled from the profile, a chosen sized extra opens its sheet with "Odebrat" instead of being removed by the tap, own voucher chips in the promo dialog, "naposledy" tag on boots, e-mail carried between login and registration. | ASK |
| app-core-4 | The booking CTA is disabled until the bike's booked dates are loaded (`datesKnown`). Requested (Q3), no test for the old look. | KEEP, add the test |
| app-core-5 | Kiosk 1.2.11: the in-app handover protocol is gone (route `/protocol`, `HandoverPromptWatcher`). | ASK |
| app-core-6 | Kiosk 1.2.11: narrower gear size rows for bikes at the self-service branch. | ASK |
| app-core-7 | i18n: the welcome-overlay language is applied at once, the display currency follows the language (also for existing installs through the legacy key `mg_locale`), web links per language. | ASK |
| app-core-8 | i18n: the built-in Czech summary of the terms / privacy text (offline fallback) is deleted. | ASK |
| app-core-9 | App funnel analytics (`EngagementService`: `visit` and `calc` rows in `web_engagement`). | ASK |
| app-core-10 | Push notification fixes (token registered after the permission, after sign-in and on resume; a tap on a cold start is delivered; `pushOrGo`). | ASK |
| app-core-11 | Old-look "Nahrajte doklady" pill follows the documents gate (`docsFabStatusProvider`). | ASK |
| app-core-12 | The "Dokončit rezervaci" pill is shown only for bookings with `booking_source = app`. | ASK |
| app-core-13 | Global request time limits (`TimeoutClient`). Requested (Q3); a slow upload on a weak signal now ends with an error after 60 s (documents) or 120 s (photos). | KEEP, add the test |
| app-core-14 | Promo dialog: Enter now refuses a code that is already applied. | ASK |
| app-core-15 | `DateDropdownField`: a stored year outside the range stays in the list. | ASK |
| app-core-16 | `MotoSuccessHero` / `StaggeredReveal`: no animation when the phone asks for reduced motion. | ASK |
| app-core-17 | Old-look tab pages now carry a page key. | ASK |
| app-core-18 | New log category `ride`. | ASK |

### Probe for app-core-1 (address carry)

File `lib/core/booking_address_carry.dart`, function `handoverSaveAddress` (line 76), called from `openAddress` in `booking_form_pickup_section.dart` and `booking_form_return_section.dart`. Every way of saving an address (typed, suggestion, quick option, map) ends in this function, because the address sheet has one `onSave` callback.

The probe calls exactly what the two sections call: the sheet reports the routed price to the fee provider of its side and then saves. Output:

```
A1 delivery set: pickup=delivery:Jihlava/Masarykovo náměstí 1 return=store:null/null fees p=1200.0 r=0.0
A2 collection -> on address: pickup=delivery:Jihlava/Masarykovo náměstí 1 return=delivery:Jihlava/Masarykovo náměstí 1 fees p=1200.0 r=1200.0
A3 collection changed to Brno: pickup=delivery:Brno/Husova 5 return=delivery:Brno/Husova 5 fees p=3000.0 r=3000.0
A4 delivery set back to Jihlava: pickup=delivery:Jihlava/Masarykovo náměstí 1 return=delivery:Jihlava/Masarykovo náměstí 1 fees p=1200.0 r=1200.0
A5 collection changed to Brno again: pickup=delivery:Brno/Husova 5 return=delivery:Brno/Husova 5 fees p=3000.0 r=3000.0
B1 collection set: pickup=store:null/null return=delivery:Brno/Husova 5 fees p=0.0 r=3000.0
B2 delivery -> on address: pickup=delivery:Brno/Husova 5 return=delivery:Brno/Husova 5 fees p=3000.0 r=3000.0
B3 delivery changed to Jihlava: pickup=delivery:Jihlava/Masarykovo náměstí 1 return=delivery:Jihlava/Masarykovo náměstí 1 fees p=1200.0 r=1200.0
C1 collection changed to Praha: pickup=delivery:Jihlava/Masarykovo náměstí 1 return=delivery:Praha/Na Příkopě 1 fees p=0.0 r=5000.0
D1 delivery edited twice, collection at branch: pickup=delivery:Brno/Husova 5 return=store:null/null fees p=3000.0 r=0.0
```

Step A3 shows the delivery address and its fee silently replaced by the collection address. Steps A4 and A5 show that the customer cannot get out of it: each edit moves both sides. Sequence B shows the same trap when the collection address is entered first. Sequence C shows that two addresses that already differ stay independent, and D that a single side behaves as in 4.1.3.

The existing test (`test/v2/screens/booking_prefill_logic_test.dart`, "pickup address change: a linked return follows, a different one stays") edits only the delivery side and creates the "different" collection address by writing the draft directly, which the form cannot do.

### Probe for app-core-2 (records erased by the cleanup)

`CacheCleanupService.run()` is called in `lib/main.dart` at line 219 (every start, before `Money.init` and before `AppV2UiNotifier.preload()`) and at line 336 (every `paused` / `detached` state). Its part `_clearTransientPrefs` removes every SharedPreferences key that is not in `_preserveKeys` (lines 28–47 of `lib/core/cache_cleanup_service.dart`) and does not start with `supabase`, `sb-` or `mg_loyalty_`. This behaviour is the same as in 4.1.3; the repo already documents two incidents caused by it (the comments at `mg_ride_rec_manual` and `mg_loyalty_`).

Keys used in `lib/` and what the cleanup does with them (script over the source, keys new since 4.1.3 are marked):

```
WIPED mg_app_v2_ui              NEW  (lib/core/feature_flags.dart — stored kill-switch value)
WIPED mg_payment_submitted_v2   NEW  (lib/core/payment_pending_marker.dart)
WIPED mg_paid_change_queue_v1   NEW  (lib/core/paid_change_queue.dart)
WIPED mg_engage_token, mg_engage_sent   NEW  (lib/core/engagement_service.dart)
WIPED mg_v2_ai_coach_seen, mg_v2_home_review_hidden_*   NEW  (v2 files outside this area)
KEPT  mg_ride_session, mg_ride_caps, mg_ride_stop_req   NEW  (added to the keep-list)
WIPED mg_currency, mg_intro_shown, mg_device_id, mg_fx_rates, mg_draft_route_v1, ...   (already so in 4.1.3)
```

The probe ran only the SharedPreferences part of the cleanup (the same private method, exposed in the private copy; `run()` itself must never run on a development machine because it deletes the system temp directory). Output:

```
BEFORE: marker pending=true queue=1 keys=[mg_app_v2_ui, mg_engage_token, mg_language, mg_paid_change_queue_v1, mg_payment_submitted_v2, mg_ride_session]
AFTER : marker pending=false queue=0 v2 bootValue=true keys=[mg_language, mg_ride_session]
```

Consequences that follow from the code:

- Kill-switch (Q5): the value `false` stored by `AppV2UiNotifier.refresh()` is erased at the next start before `preload()` reads it, so every cold start begins in the v2 look. The old look comes only after the flag is fetched again and the customer is on a tab root (`MgV2Gate`). Without a connection at start the whole session stays in v2 although the owner switched it off. The comment in `main.dart` ("poslední známá hodnota z prefu platí od prvního snímku") is therefore not true in the field.
- Double-charge protection (Q4): the marker "payment sent, result unknown" is erased as soon as the app goes to the background (for example when the customer switches to the banking app to approve the payment, or locks the phone) and again at every start. After that `pendingBookingFabProvider` reports `verifying = false`, the pill offers "Dokončit rezervaci" again, the restart notice (`paidAfterRestartProvider`) finds no marker, and in the path where a new booking collides with the customer's own unpaid draft (`payment_screen.dart` line 483) the draft is no longer recognised as "payment running" and is cancelled and replaced. The server guard `payment_in_progress` in `process-payment` still exists; I did not audit it in this task.
- Swap / edit completion with retry (Q4, D6): the queue entry written after a paid surcharge is erased at the first pause. `PaidChangeQueue.drain` on resume, on reconnect and at start then finds nothing. The server webhook still completes the change itself; what is lost is the part only the app knows (gear sizes, own gear, `booking_extras` rows, the old client path) and the stored failure that the booking detail shows once.
- App funnel: the day token is erased too, so every cold start can write a new `visit` row for the same person and day.
- Currency: `mg_currency` was already erased at every start in 4.1.3, so a manual currency choice never survived a restart. With the i18n change (app-core-7) the language therefore decides the display currency at every start.

The unit tests of these features (`test/v2/flag_test.dart`, `test/refix_states_test.dart`, `test/paid_change_queue_test.dart`, `test/payments_restart_taken_test.dart`) use mock SharedPreferences without the cleanup, so they pass. `test/rides/ride_cache_keys_test.dart` shows the kind of test that is missing for the other keys.

## Table of all hunks

Risk column: "old look" = behaviour with `feature_flags.app_v2_ui = false`. Customer paths checked for every functional hunk: login, booking, payment, documents, pickup codes, SOS, ride recording.

### lib/main.dart

| # | file | hunk | class | request | risk | test |
|---|---|---|---|---|---|---|
| M1 | `main.dart` | `ErrorWidget.builder`: the crash card has a localized text and the buttons Zpět / Domů (v2: `CrashViewV2`). | F | Q3 (way back everywhere); the v2 view is Q5 | Low. The buttons use `rootNavigatorKey`; the fixed Czech text "Restartujte aplikaci" is gone. | v2 view: `test/v2/ux/shell_home_onboarding_test.dart`; old-look card: none |
| M2 | `main.dart` | `Supabase.initialize(httpClient: TimeoutClient(...))` — every Supabase request gets a time limit. | F | Q3 (nothing hangs) | Low–medium, see app-core-13. | `test/error_states_other_test.dart` (group TimeoutClient) |
| M3 | `main.dart` | `Money.init(defaultLang: mg_language ?? mg_locale)` — the legacy onboarding key now also decides the default display currency. | F | UNSURE — i18n, PR #2194 (2026-10-11) | Low–medium, see app-core-7. | none |
| M4 | `main.dart` | `AppV2UiNotifier.preload()` before `runApp` (last known kill-switch value for the first frame). | F | Q5 kill-switch | Medium: the stored value is erased before it is read, see app-core-2. | `test/v2/flag_test.dart` (the cleanup is not part of the test) |
| M5 | `main.dart` | `EngagementService.start()`, `.onLifecycle()`, `.onUserPointer()`. | F | UNSURE — App funnel, PR #2206 (2026-10-15) | Low, see app-core-9. | none |
| M6 | `main.dart` | `OfflineGuard.onBackOnline` → `recoverFailedProviders(ref)` + `PaidChangeQueue.drain(online)`. | F | Q3; Q4 (swap completion with retry) | Low. | hook: none; queue: `test/paid_change_queue_test.dart` |
| M7 | `main.dart` | `_initPush`: `NotificationHandler.initialize` now runs before `PushService.initialize`. | F | UNSURE — push fix inside the Q3 round (`668651c9`) | Low, see app-core-10. | none |
| M8 | `main.dart` | resume: `PushService.initialize()`. | F | UNSURE — push fix | Low. One permission check and one FCM token read per resume; the token row is written only when the user or the token changed. | none |
| M9 | `main.dart` | resume: `recoverFailedProviders(ref)` + `PaidChangeQueue.drain(resume)`. | F | Q3; Q4 | Low by itself; after a pause the queue is already empty, see app-core-2. | none |
| M10 | `main.dart` | auth listener: `ForcedSignOut.pending = true` on `SignOutReason.sessionExpired` and on a token refresh without session. | F | Q3 (explain the forced sign-out) | Low. | none |
| M11 | `main.dart` | auth listener: `signedIn` → `PushService.initialize()`. | F | UNSURE — push fix | Low. | none |
| M12 | `main.dart` | `_onPermDone` → `PushService.initialize()` + `PermissionService.reportToProfile()`. | F | UNSURE — push fix | Low. | none |
| M13 | `main.dart` | `routerConfig: mgSafeRouterConfig(router)`. | F | Q4 / Q3 (the return from 3-D Secure `motogo24://payment` does not crash) | Low. | `test/navigation_back_test.dart` (group custom-scheme links) |
| M14 | `main.dart` | `MgV2Gate` around the navigator, `MgV2Scope` around the onboarding overlays, `IntroV2` or `MotoIntroOverlay`. | F | Q5 kill-switch | Low. With the flag off the old widgets are built. | `test/v2/wiring_test.dart`, `test/v2/flag_test.dart`, `test/v2/ux/shell_home_onboarding_test.dart` |
| M15 | `main.dart` | `HandoverPromptWatcher` removed from the app stack. | F | UNSURE — kiosk 1.2.11, PR #2182 (2026-10-10) | Medium, see app-core-5. | none |
| M16 | `main.dart` | `PermissionOverlay(onBack: …)`: arrow and system back return to the language overlay. | F | Q3 | Low. | `test/refix_states_test.dart` (MgOverlayBack), `test/v2/ux/shell_home_onboarding_test.dart` |

### lib/core (root files)

| # | file | hunk | class | request | risk | test |
|---|---|---|---|---|---|---|
| A1 | `auth_guard.dart` | `ForcedSignOut` flag; `handleAuthError` sets it when a session existed. | F | Q3 | Low. | none |
| A2 | `auth_guard.dart` | `isAuthError` returns false for `AuthRetryableFetchException` (a network error during token refresh no longer signs the customer out). | F | Q3 | Low. | no direct test of `isAuthError` |
| B1 | `banner_provider.dart` | Banner translations: used only when `translations_src` equals the SHA-1 of the Czech text; `bannerProvider` returns the banner in the app language. | F | Q1 (banner, owner answers 2026-10-11, `e8b63003`) | Low. A wrong fingerprint only falls back to Czech. I compared `bannerFingerprint` with `sha1sum` for four inputs (empty, "abc", a Czech sentence with an emoji, 1000 × "a"); all four matched. | none in the repo |
| BA1 | `booking_address_carry.dart` | `handoverToDelivery`: a side switched to "on address" without an address of its own takes the address, postcode, coordinates and fee of the other side. | F | Q5 2026-10-22 (never fill twice) | Active in both looks. Low by itself. | `test/v2/screens/booking_prefill_logic_test.dart` |
| BA2 | `booking_address_carry.dart` | `handoverSaveAddress`: the other side follows when it has no address or the same address. | F | Q5 2026-10-22 | HIGH in both looks and both trees, see app-core-1. | only the delivery-side edit is tested; the collection-side edit is not |
| BA3 | `booking_address_carry.dart` | `handoverQuickOptions` / `AddrQuick`: the address sheet offers the other side and the profile address. | F | Q5 2026-10-22 | Active in both looks. Low. | `test/v2/screens/booking_prefill_logic_test.dart`, `test/v2/screens/booking_r2_address_test.dart` |
| E1 | `booking_form_extras_section.dart` | `gearSizesFor(..., selfService: selfService)` for the four rider rows and the boots dialog. | F | UNSURE — kiosk 1.2.11, PR #2182 | Low, see app-core-6. | none for the old look |
| E2 | `booking_form_extras_section.dart` | A tap on an already chosen passenger gear / boots row opens its sheet (with "Odebrat") instead of removing the row. | F | Q5 2026-10-22 | Old look changed, see app-core-3. Low. | v2: `test/v2/ux/cb_booking_sheets_test.dart`; old look: none |
| E3 | `booking_form_extras_section.dart` | Labels through `extraLabel` / `extraDescription` / `extraSizeLabel`. | C | texts (i18n) | None. | — |
| E4 | `booking_form_extras_section.dart` | v2 branch (`BookingExtrasV2`, `BookingExtraRowV2`). | V | Q5 | — | `test/v2/ux/cb_booking_express_test.dart` |
| E5 | `booking_form_extras_section.dart` | Handlers hoisted out of the widget tree (own gear, sizes, trailer tile). | C | — | None; the bodies are unchanged. | — |
| H1 | `booking_form_header_widget.dart` | `bookingFormBack` extracted; the arrow is wrapped in `MgBackTap` (48 px hit area, screen-reader label). | C | Q3 | None. | `test/navigation_back_test.dart` (MgBackTap) |
| L1 | `booking_form_locked_option.dart` | v2 branch. | V | Q5 | — | — |
| P1 | `booking_form_pickup_section.dart` | "On address" → `handoverToDelivery`; save → `handoverSaveAddress`; `quick:` options from the other side and the profile. | F | Q5 2026-10-22 | Active in both looks; see BA2 / app-core-1. | `test/v2/screens/booking_prefill_sections_test.dart` (v2) |
| P2 | `booking_form_pickup_section.dart` | v2 branch (`BookingHandoverV2`). | V | Q5 | — | — |
| P3 | `booking_form_return_section.dart` | The same three changes for the collection side. | F | Q5 2026-10-22 | Active in both looks; see BA2 / app-core-1. | as P1 |
| P4 | `booking_form_return_section.dart` | v2 branch. | V | Q5 | — | — |
| PR1 | `booking_form_price_section.dart` | v2 branch (`BookingPriceV2`). | V | Q5 | — | — |
| PR2 | `booking_form_price_section.dart` | Localized rank name; `Money.czk(0)` instead of the fixed "0 Kč". | C | texts (i18n) | None. | — |
| PM1 | `booking_form_promo_section.dart` | One `apply()` for the button, Enter and a chip: the Enter path now also refuses a code that is already applied. | F | UNREQUESTED — correction that came with the 2026-10-22 refactor (`565986fa`) | Low, see app-core-14. | `test/v2/ux/cb_booking_sheets_test.dart` (v2 sheet) |
| PM2 | `booking_form_promo_section.dart` | The dialog lists the customer's own unused gift vouchers as chips (`myVouchersProvider`); the dialog scrolls. | F | Q5 2026-10-22 | Active in the old dialog too, see app-core-3. One extra read of the vouchers when the dialog opens. Low. | `test/v2/screens/booking_prefill_flow_test.dart`, `test/v2/ux/cb_booking_sheets_test.dart` |
| PM3 | `booking_form_promo_section.dart` | v2 branch (sheet, express chips). | V | Q5 | — | `test/v2/ux/cb_booking_sheets_test.dart` |
| T1 | `booking_form_time_section.dart` | v2 branch. | V | Q5 | — | `test/v2/ux/lookonly_areas_cb_test.dart` |
| W1 | `booking_form_widget.dart` | Handlers hoisted (note, calendar, times, consents). | C | — | None. | — |
| W2 | `booking_form_widget.dart` | `_onDatesSelected`: in v2 the new dates are shared with the list, Home and the calculator (`MgV2.peek`). | F | Q5 2026-10-22 | v2 only. | `test/v2/screens/booking_prefill_flow_test.dart` |
| W3 | `booking_form_widget.dart` | `_missingGearSizes` and `offList` use the self-service size rows. | F | UNSURE — kiosk 1.2.11 | Low, see app-core-6. | none |
| W4 | `booking_form_widget.dart` | The calendar shows an error card with "Zkusit znovu" when the booked dates did not load (before: all days looked free). | F | Q3 | Low. | none for the old look |
| W5 | `booking_form_widget.dart` | CTA rule `datesKnown` + a red row with "Zkusit znovu" when the booked dates failed. | F | Q3 (date collision) | Medium, see app-core-4. | none |
| W6 | `booking_form_widget.dart` | No bike selected: a visible back arrow (v2: `BookingNoMotoV2`). | F | Q3 | Low. | v2: `test/v2/screens/booking_logic_test.dart`; old look: none |
| W7 | `booking_form_widget.dart` | `EngagementService.trackCalc()` when the form shows a price. | F | UNSURE — App funnel | Low, see app-core-9. | none |
| W8 | `booking_form_widget.dart` | v2 branch (`BookingFormV2View`, with the `rangeBusy` lock). | V | Q5 | — | `test/v2/screens/booking_*`, `test/v2/ux/cb_booking_*` |
| S1 | `booking_size_dialogs.dart` | Passenger sizes follow `selfService` (`_passengerGearSizes`). | F | UNSURE — kiosk 1.2.11 | Low, see app-core-6. | none |
| S2 | `booking_size_dialogs.dart` | Passenger sheet: prefilled from the chosen gear or from `profiles.gear_sizes.passenger`, note "from last booking", button "Odebrat". | F | Q5 2026-10-22 | Active in the old look, see app-core-3. The sizes are always confirmed by the button. Low. | v2: `test/v2/ux/cb_booking_sheets_test.dart`; old look: none |
| S3 | `booking_size_dialogs.dart` | Boots dialog: the chosen size is highlighted, the last size carries a tag, button "Odebrat". | F | Q5 2026-10-22 | Active in the old look. The size is still chosen only by a tap. Low. | as S2 |
| S4 | `booking_size_dialogs.dart` | v2 sheets; localized labels; scrollable content; 44 px chips; `MgSheetHandle` with ✕. | V | Q5, Q3 | — | `test/v2/ux/cb_booking_sheets_test.dart` |
| CC1 | `cache_cleanup_service.dart` | The keys `mg_ride_session`, `mg_ride_caps`, `mg_ride_stop_req` survive the cleanup. | F | Q6 | Low. The other new keys of this branch were not added, see app-core-2. | `test/rides/ride_cache_keys_test.dart` |
| CU1 | `currency.dart` | `CurrencyNotifier.followLanguage`. | F | UNSURE — i18n, PR #2194 | Low, see app-core-7. | none |
| LT1 | `data/legal_texts.dart` | File deleted (built-in Czech summary of VOP / GDPR used when the download failed). | F | UNSURE — i18n (`87bef6c2`) | Low, see app-core-8. | none |
| DL1 | `debug_logger.dart` | New value `LogCategory.ride`. | F | UNSURE — ride diagnostics, PR #2208 (2026-10-15) | Low, see app-core-18. | none |
| EN1 | `engagement_service.dart` | New file: `visit` and `calc` rows in `web_engagement`. | F | UNSURE — App funnel | Low, see app-core-9. | none |
| FF1 | `feature_flags.dart` | `fetchAppV2UiFlag`, `AppV2UiNotifier`, `appV2UiProvider`. | F | Q5 kill-switch | Medium because of the erased pref, see app-core-2. | `test/v2/flag_test.dart`, `test/v2/wiring_test.dart` |
| FE1 | `friendly_error.dart` | New file: maps an exception to what / why / how texts. | F | Q3; Q4 (texts without contact) | Low. | `test/error_states_other_test.dart` |
| IU1 | `in_app_update_service.dart` | v2 dialog; handlers hoisted. | V | Q5 | — | — |
| PA1 | `paid_after_restart.dart` | New file: result of a payment sent before the app was killed. | F | Q4 (double charge, swap taken meanwhile) | Medium: it reads markers that do not survive a restart, see app-core-2. | `test/payments_restart_taken_test.dart` |
| PC1 | `paid_change_queue.dart`, `paid_change_entry.dart` | New files: persistent queue of paid swaps / edits. | F | Q4 (swap completion with retry) | Medium: the queue does not survive a pause, see app-core-2. | `test/paid_change_queue_test.dart`, `test/paid_change_queue_fix_test.dart` |
| PC2 | `paid_change_apply.dart` | New file: one completion attempt (server, gear sizes, extras). | F | Q4 | Low. | `test/paid_change_queue_test.dart`, `test/paid_change_queue_fix_test.dart` |
| PMk | `payment_pending_marker.dart` | New file: local record "payment sent, result unknown". | F | Q4 (double charge) | Medium: the record does not survive a pause, see app-core-2. | `test/refix_states_test.dart`, `test/refix2_states_test.dart` |
| PB1 | `pending_booking_fab_provider.dart` | `paymentProcessingProvider`, `paymentLeaveActionProvider`. | F | Q4 | Low. | `test/v2/ux/ps_sheets_test.dart` (the confirmation) |
| PB2 | `pending_booking_fab_provider.dart` | `PendingBooking.verifying` (marker, or an expired PaymentIntent that is still running). | F | Q4 | Low by itself; depends on the marker, see app-core-2. | marker tests above |
| PB3 | `pending_booking_fab_provider.dart` | `restored_at` selected; `pendingWindowStart`. | F | Q4 (restore-and-pay) | Low. | `test/payments_paydec_test.dart` ("payment window counts from the restore") |
| PB4 | `pending_booking_fab_provider.dart` | Filter `.eq('booking_source', 'app')`. | F | UNSURE — serves Q4 (double charge) but removes an ability | Low–medium, see app-core-12. | none |
| PB5 | `pending_booking_fab_provider.dart` | Timeouts 10 s / 15 s; `cancelPendingBooking(reason:)`. | F | Q3; Q4 | Low. The stream keeps the last booking on a network error. | none |
| RC1 | `provider_recovery.dart` | New file: shared providers left in error are reloaded. | F | Q3 | Low. | none |
| RR1 | `realtime_resilience.dart` | New file: realtime subscription that retries after a channel error. | F | Q3 | Low. | none |
| SR1 | `safe_router_config.dart` | New file: ignores links with a custom scheme. | F | Q4 / Q3 | Low. | `test/navigation_back_test.dart` |
| UC1 | `update_check_provider.dart` | Forced-update dialog: text when the store cannot be opened, buttons to call MotoGo24 / 112. | F | Q3 | Low. The dialog still blocks. | none for the old look |
| UC2 | `update_check_provider.dart` | v2 dialog (`UpdateForceDialogV2`). | V | Q5 | — | `test/v2/ux/shell_home_states_test.dart` |
| WL1 | `web_links.dart` | Ukrainian → `motogo24.com?lang=uk`; unknown language → `.com` (before `.cz`). | F | UNSURE — i18n | Low, see app-core-7. | none |

### lib/core/router.dart (old file compared with the new file route by route)

| # | file | hunk | class | request | risk | test |
|---|---|---|---|---|---|---|
| R1 | `router.dart` | Private `_BookingDebugWrapper` (about 860 lines) removed. In the base file it was only defined; the route used `BookingDebugWrapper` from `booking_form_widget.dart`. | C | dead code | None. | `test/compile_smoke_test.dart` |
| R2 | `router.dart` | Route `/protocol`, `Routes.protocol` and its entry in `_authRequired` removed. | F | UNSURE — kiosk 1.2.11 | Medium, see app-core-5. | none |
| R3 | `router.dart` | `errorBuilder: RouteErrorPage`. | F | Q3 | Low. | the page: `test/v2/flag_off_test.dart` |
| R4 | `router.dart` | Redirect strips the App Link prefix `/app/...`. | F | Q3 | Low. No route of the app starts with `/app`. | none for the redirect (`test/navigation_back_test.dart` only checks that such an https link is not treated as a foreign scheme) |
| R5 | `router.dart` | A signed-in customer may stay on `/reset-password` while `AuthService.recoveryInProgress`. | F | Q3 (the password reset reaches its last step) | Low. The flag is cleared in `reset_password_screen.dart`. | none |
| R6 | `router.dart` | `LoginScreen(initialEmail)` and `RegisterScreen(initialEmail)` from the query. | F | Q5 2026-10-22 | Low. Active in both looks (the e-mail typed on one screen is carried to the other). | `test/v2/ux/asm_auth_test.dart` |
| R7 | `router.dart` | `MgBackGuard` around the routes outside the shell. | F | Q3 (system back) | Low. Android back on a screen without history now goes to its parent instead of closing the app. | `test/navigation_back_test.dart`, `test/error_states_other_test.dart` (mgBackParent) |
| R8 | `router.dart` | `/route-build`, `/route-nav-custom`: a wrong `extra` shows `RouteErrorPage` instead of a cast error. | F | Q3 | Low. | none |
| R9 | `router.dart` | `ShellRoute`: `V2Switch(AppShell / AppShellV2)`, observer `MgBarsRouteObserver`. | V | Q5, Q7 (bars hide on scroll) | Old look: no change. | `test/v2/shell_test.dart`, `test/v2/wiring_test.dart` |
| R10 | `router.dart` | Tab pages go through `routerTabPage`: in the old look still `NoTransitionPage`, now with `key: state.pageKey` (before: no key). | F | UNREQUESTED for the old look (came with the v2 tab transition) | Low, see app-core-17. | none with the old shell and the real router |
| R11 | `router.dart` | `/booking` and `/routes-list` use `routerSwipeBackPage`: `MaterialPage` on iPhone in the old look (swipe back), on both platforms in v2. | F | Q3 (way back on iPhone, round of 2026-10-16) | Low. Android old look is unchanged. | none for the old look |
| R12 | `router.dart` | Shop page and loyalty: v2 variants. | V | Q5 | — | — |
| R13 | `router.dart` | `pushOrGo`. | F | Q3 | Low. | `test/refix_states_test.dart` |

### lib/core/app_shell.dart and shell_*.dart (old shell compared with the split files)

| # | file | hunk | class | request | risk | test |
|---|---|---|---|---|---|---|
| SH1 | `app_shell.dart`, `shell_banner.dart`, `shell_fab_layer.dart`, `shell_fabs.dart`, `shell_fabs_b.dart`, `shell_actions.dart` | The shell is split into several files. I compared the conditions, positions, texts and handlers of every pill with the base file; apart from the rows below they are the same. | C | Q5 (shared with the v2 shell) | None. | no test of the old shell with the real router |
| SH2 | `shell_paid_listener.dart` | One notice after a restart about a payment sent before the app was killed. | F | Q4 | Low; depends on the marker, see app-core-2. | `test/payments_restart_taken_test.dart` |
| SH3 | `app_shell.dart` | `MgBackGuard(shell: true)` around the shell content. | F | Q3 | Low. Home still closes the app. | `test/navigation_back_test.dart` |
| SH4 | `shell_tab_action.dart` | `onShellTabTap`: a running payment can be left by a tab only after a confirmation. | F | Q4 (double charge) | Low. | dialog: `test/v2/ux/ps_sheets_test.dart`; the tab handler with a running payment: none |
| SH5 | `shell_tab_action.dart` | `_resetOnHome`: v2 keeps the draft; the old look resets draft, bike and filter exactly as before (I followed the path with `v2 == false`). | F | Q5 2026-10-22 | Old look unchanged. | `test/v2/shell_test.dart`, `test/v2/screens/home_carry_test.dart`, `test/v2/screens/booking_prefill_flow_test.dart` (flag OFF case) |
| SH6 | `shell_fab_layer.dart` | Documents pill: completeness from `docsFabStatusProvider` (documents gate) instead of `docsVerifiedProvider`. | F | UNSURE — documents gate, PR #2192 (2026-10-10) | Low–medium, see app-core-11. | v2 strip: `test/v2/ux/shell_home_strips_test.dart`; old pill: none |
| SH7 | `shell_fabs.dart` | `ShellVerifyingFab` ("Platba se ověřuje") instead of offering a second payment. | F | Q4 | Low by itself; depends on the marker, see app-core-2. | v2 strip: `test/v2/ux/shell_home_strips_test.dart`; old pill: none |
| SH8 | `shell_fabs.dart` | Cancelling the unpaid booking: error toast with "Zkusit znovu". | F | Q3 | Low. | none |
| SH9 | `shell_fab_layer.dart` | v2 strips (`_v2Strips`). | V | Q5 | — | `test/v2/ux/shell_home_strips_test.dart` |

### lib/core/native, net, overlays, push

| # | file | hunk | class | request | risk | test |
|---|---|---|---|---|---|---|
| G1 | `native/gps_service.dart` | `ensurePermission` never opens Settings by itself; new `status()`, `locate()`, `GpsStatus`. | F | Q3 | Low. No caller uses `ensurePermission` any more; all callers use `status()` / `locate()`. | `test/refix2_states_test.dart` (location explanation) |
| PS1 | `native/permission_service.dart` | `requestAll` → `PushService.initialize()`. | F | UNSURE — push fix | Low. | none |
| PS2 | `native/permission_service.dart` | `missingTitles()`. | F | Q3 (result of the permission request) | Low. | none |
| TC1 | `net/timeout_client.dart` | New file: limits per path (REST and auth 20 s, RPC and other functions 30 s, invoice / document / refund 45 s, scan and save document 60 s, AI 90 s, storage 120 s), 30 s between body chunks. | F | Q3 | Low–medium, see app-core-13. | `test/error_states_other_test.dart` |
| O1 | `offline_guard.dart` | The overlay can be left ("Pokračovat bez internetu", system back), offers calls to MotoGo24 / 112, "Zkusit znovu" shows the result. | F | Q3 (2026-10-16) | Low. | v2 view: `test/v2/ux/shell_home_states_test.dart`; logic: none |
| O2 | `offline_guard.dart` | Check at start, reachability ping of Supabase, thin strip "no internet". | F | Q3 | Low. Two slow answers of `HEAD /rest/v1/` in a row show the strip although the connection works. | none |
| O3 | `offline_guard.dart` | `onBackOnline`, `offlineNow`, `overlayVisible`. | F | Q3 | Low. | none |
| OV1 | `overlays/onboarding_overlays.dart` | The language chosen in the welcome overlay is applied at once (`localeProvider.setLocale`) and the currency follows. | F | UNSURE — i18n, PR #2194 | Low for new installs, see app-core-7. | `test/v2/ux/shell_home_onboarding_test.dart` (v2) |
| OV2 | `overlays/onboarding_overlays.dart` | `PermissionOverlay`: back arrow and system back (`MgOverlayBack`). | F | Q3 | Low. | `test/refix_states_test.dart` |
| OV3 | `overlays/onboarding_overlays.dart` | v2 branches (`OnboardingLangV2`, `OnboardingPermV2`). | V | Q5 | — | `test/v2/ux/shell_home_onboarding_test.dart` |
| N1 | `push/notification_handler.dart` | v2 banner; the label "Zobrazit" is localized. | V | Q5, texts | — | — |
| N2 | `push/notification_handler.dart` | A tap on a notification waits until the customer is past the login screens (up to 2 minutes) and opens the target with `pushOrGo`. | F | UNSURE — push fix | Low, see app-core-10. | `pushOrGo`: `test/refix_states_test.dart`; delivery: none |
| PU1 | `push/push_service.dart` | `initialize` can be called repeatedly; a tap is kept until a handler exists; the token is written once per user and token. | F | UNSURE — push fix | Low, see app-core-10. | none |

### lib/core/widgets

| # | file | hunk | class | request | risk | test |
|---|---|---|---|---|---|---|
| AA1 | `widgets/address_autocomplete_field.dart` | Optional `onChanged` callback (used by the SOS address in v2). | F | Q5 | Old look unchanged (nobody passes the callback there). | `test/v2/sos_address_test.dart` |
| AA2 | `widgets/address_autocomplete_field.dart` | v2 border and hint colour. | V | Q5 | — | `test/v2/fix_shared_r3_test.dart` |
| DD1 | `widgets/date_dropdown_field.dart` | A stored year outside `[firstYear, lastYear]` stays in the year list. | F | UNREQUESTED — fix from the v2 date field work (`2805e32b`, 2026-11-05) | Low, see app-core-15. | `test/fix_dates_test.dart` |
| DD2 | `widgets/date_dropdown_field.dart` | v2 row (`DateFieldRowV2`), caps label. | V | Q5 | — | `test/fix_dates_test.dart` |
| EF1 | `widgets/error_feedback.dart` | New file: `showErrorSnack`, `showErrorDialog`, `explainLocation`, `confirmDiscard`, `MgProgress`, `callMotoGo`, `call112`. | F | Q3; Q4 | Low. | `test/refix2_states_test.dart`, `test/refix3_states_test.dart` (MgProgress), `test/v2/flag_off_test.dart`, `test/navigation_back_test.dart` |
| LH1 | `widgets/logo_header.dart` | Subtitle localized. | C | texts (i18n) | None. | — |
| MT1 | `widgets/map_tile_errors.dart` | New file: chip "map tiles did not load" with retry. | F | Q3 | Low. | `test/v2/ux/fix_r2_core_test.dart` |
| MB1 | `widgets/mg_back.dart` | New file: `mgBackParent`, `MgBackGuard`, `mgIsTopmost`, `MgOverlayBack`. | F | Q3 | Low. | `test/navigation_back_test.dart`, `test/error_states_other_test.dart`, `test/refix_states_test.dart` |
| MN1 | `widgets/mg_nav_controls.dart` | New file: `MgBackTap`, `MgHitSlop`, `MgSheetClose`, `MgSheetHandle`, `MgSheetTitleRow`. | F | Q3 (visible, easy to hit back / close) | Low. | `test/navigation_back_test.dart` |
| MF1 | `widgets/moto_fx.dart` | `MotoSuccessHero` and `StaggeredReveal` show the final state at once when the system asks for reduced motion. | F | UNREQUESTED for the old look (`bb2ff4b3`, 2026-10-30, v2 motion work) | Low, see app-core-16. | `test/v2/fix_shared_r3_test.dart` |
| MF2 | `widgets/moto_fx.dart` | Intro subtitle localized. | C | texts (i18n) | None. | — |
| NI1 | `widgets/net_image.dart` | `fadeIn` and `alignment` parameters (defaults equal the old values). | C | Q5 | None. | — |
| PL1 | `widgets/pickup_location_link.dart` | 10 s timeouts on the two queries. | F | Q3 | Low. | none |
| RE1 | `widgets/route_error_page.dart` | New file. | F | Q3 | Low. | `test/v2/flag_off_test.dart` |
| SV1 | `widgets/state_views.dart` | New file: `MgBackArrow`, `MgStateScaffold`, `MgLoadingView`, `MgErrorView`, `MgStaleNote`. | F | Q3 | Low. | `test/error_states_other_test.dart`, `test/v2/states_test.dart`, `test/v2/flag_off_test.dart` |
| TD1 | `widgets/time_dropdown_field.dart` | v2 field (`TimeFieldV2`). | V | Q5 | Old look unchanged. | `test/v2/ux/cb_time_calendar_test.dart` |

## What I checked for the customer paths

- Login: the redirect is the same except for the App Link prefix and the password-reset exception; a network error during token refresh no longer signs the customer out; auth requests have a 20 s limit; the forced sign-out sets a flag that the login screen reads.
- Booking: the old-look tab handler resets draft, bike and filter exactly as before; `gearSizesFor` without `selfService` returns the same lists as in 4.1.3; findings app-core-1, -3, -4, -6.
- Payment: `process-payment` is called through plain `http.post` with its own 30 s limit, so `TimeoutClient` does not touch it; the return link `motogo24://payment` is ignored by the router; findings app-core-2, -12.
- Documents: `scan-document` and `save-verification-document` go through the Supabase client (60 s limit); the photo is resized to 1600 px, JPEG quality 80, before it is sent; finding app-core-13.
- Pickup codes: the push token is now registered on a new install without a restart; the documents pill follows the gate; the handover protocol is no longer in the app; findings app-core-5, -10, -11.
- SOS: `GpsService` never opens Settings by itself and all callers use `status()` / `locate()`; the offline overlay and the forced-update dialog offer calls to MotoGo24 and 112.
- Ride recording: the three new recorder keys are in the keep-list of the cleanup; `LogCategory.ride` has no CHECK in the database (`SUPABASE_BACKEND_STATE_1.md`, table `app_debug_logs`).

## Checks done for this audit

- Read-only look at the backend state files: `feature_flags` has public SELECT (the kill-switch can be read before sign-in); `web_engagement` accepts INSERT from `anon` and `authenticated` with the columns the app sends; `bookings.booking_source` has default `app` and 4.1.3 already wrote `app`; web bookings can wait for a bank transfer (`pay_channel = qr`).
- go_router 13.2.5 source: `popRoute` returns false without calling `maybePop` when no navigator can pop (this is why `MgBackGuard` uses a `BackButtonListener`); the page key of a `go` match is the matched path.
- flutter_riverpod 2.6.1 source: `ref.watch` has no build-phase assertion, so the `ref.watch(bookedDatesProvider)` calls inside the `Builder` callbacks of the booking form are legal.
- Probes in a private copy of the Android tree (`funcaudit/work_appcore2/probe` in the scratchpad): address carry, cleanup of SharedPreferences, SHA-1 of the banner text against `sha1sum`, web links per language. The repository trees were not touched.
- Existing tests run in the same private copy, all passed (154 tests in 16 files): `navigation_back_test`, `error_states_other_test`, `refix_states_test`, `refix2_states_test`, `refix3_states_test`, `paid_change_queue_test`, `paid_change_queue_fix_test`, `payments_restart_taken_test`, `payments_paydec_test`, `fix_dates_test`, `v2/flag_test`, `v2/flag_off_test`, `v2/wiring_test`, `v2/screens/booking_prefill_logic_test`, `v2/shell_test`, `rides/ride_cache_keys_test`.
- I did not run the full suite or `flutter analyze` in this task.
