# Area app-flagoff — the v2 kill-switch (`feature_flags.app_v2_ui`)

Base for the app: 70a94933 (4.1.3). HEAD 20a4c358. Android tree read; the iOS tree was checked for the same wiring
(`main.dart` v2 lines identical, `feature_flags.dart`, `core/v2/flag/**` and `router.dart` byte-identical).
No code was changed. Targeted tests run: `test/v2/flag_test.dart`, `test/v2/wiring_test.dart`,
`test/v2/ux/fnd_flag_motion_test.dart` = 34 passed, 0 failed.

## 1. What was searched

`grep -rlE "MgV2\.(on|peek|applied)|V2Switch\(|MgV2Gate|appV2UiProvider|mgV2"` over `lib/` minus v2 directories / `*_v2*`
files gives 141 non-v2 files with 328 seam lines (list: scratchpad `seams.txt`, `seamlines.txt`).
Seam shapes found:
- (A) `if (MgV2.on(context)) return V2View(...same state and callbacks...); <old tree>` — the old tree is the code after the `if`.
- (B) `MgV2.on(context) ? v2Widget : oldWidget` inside a tree — style only.
- (C) `MgV2.peek(context)` inside a callback that picks the v2 sheet/dialog/toast and otherwise runs the old dialog; the
  action after the user's choice is shared.
- (D) v2-only extra logic (date carry, range-busy guard) — listed below.
With no `MgV2Scope` above (tests, early frames) or with the flag OFF, `MgV2.on/peek` return false (v2_scope.dart), so every
(A)/(B)/(C) seam runs the code after/under the `if`. Every `peek` seam (30 lines) was opened and read; in all of them the
OFF branch is the previous dialog/toast/sheet and the action after it is the same function in both branches.

## 2. The gate

| File / hunk | Class | Request | Verified behaviour | Risk | Test |
|---|---|---|---|---|---|
| feature_flags.dart `fetchAppV2UiFlag` | FUNCTIONAL | Q5 | Row missing → true; `enabled` null/true → true; false → false; any error or 8 s timeout → null (= keep current). `feature_flags` is public-SELECT (STATE_5), so anon at /login reads it too. | Low | flag_test.dart |
| feature_flags.dart `AppV2UiNotifier.preload/bootValue` | FUNCTIONAL | Q5 | Cold start uses the last stored pref `mg_app_v2_ui`, missing → ON; read before `runApp`. | Low | flag_test.dart ("preload") |
| feature_flags.dart `refresh` | FUNCTIONAL | Q5 | Fresh DB value is written to the pref at once (valid from the next cold start) and kept in `pending`; offline (null) changes nothing. | Low | flag_test.dart |
| feature_flags.dart `applyPendingIfSafe` | FUNCTIONAL | Q5 | Applies only if path ∈ {/, /search, /reservations, /routes, /profile}, no query, and `paymentProcessingProvider` is false. | Low | flag_test.dart ("every tab root", "?edit=personal") |
| v2_gate.dart `_location/_hasPushedPage` | FUNCTIONAL | Q5 | A tab root reached by `push` (ImperativeRouteMatch, also inside the ShellRouteMatch) is NOT a safe point → old booking form's push('/profile') and v2's push('/profile') do not switch. | Low | flag_test.dart ("pushed over another page") |
| v2_gate.dart `_afterColdStart`, `_onRoute`, `didChangeAppLifecycleState` | FUNCTIONAL | Q5 | Apply after the first fetch, on each router change (post-frame) and on each resume (new fetch). | Low/Medium: pageless dialogs and bottom sheets (showDialog/showModalBottomSheet) are not router matches, so a switch can happen while one is open over a tab root (e.g. resume with the date sheet open on /search, nickname dialog on Home). The screen under it is rebuilt in the other look; the sheet stays and its callbacks point at the disposed state. Only when the owner flips the flag. | No test for a modal open at the safe point |
| v2_gate.dart `build` | presentation | Q5 | OFF: `Theme(data: base)` = same theme; `MgV2.markApplied(false)`. | None | wiring_test.dart ("OFF = old UI, app theme untouched") |
| v2_scope.dart | presentation | Q5 | No scope = OFF; `V2Switch` builds exactly one child. | None | flag_test.dart |
| Velín `FeatureFlagsTab.jsx` + DB | FUNCTIONAL (ops) | Q5 | Velín only lists and `update`s EXISTING rows. No file in `supabase/migrations` (nor origin/main) inserts the `app_v2_ui` row; Velín's own text says "Řádek flagu vzniká SQL migrací" and "iOS zatím jen starý vzhled" (stale since 2026-11-05). | HIGH for the kill-switch itself: without the row the owner cannot switch the look off from Velín in an emergency. | none |

## 3. main.dart (v2 hunks; other hunks belong to other areas and are only named)

| Hunk | Class | Request | Note |
|---|---|---|---|
| `AppV2UiNotifier.preload()` before runApp | FUNCTIONAL | Q5 | as above |
| `MgV2Gate(router: router, child: child!)` around the router's navigator | FUNCTIONAL | Q5 | Root navigator (dialogs, sheets, OfflineGuard overlay entries) is inside the scope. Level-up watcher and RideRecorderWatcher are outside the gate and unchanged. |
| Onboarding overlays wrapped in `MgV2Scope(enabled: v2On)`; intro `v2On ? IntroV2 : MotoIntroOverlay` | presentation | Q5 | OFF = old widgets. |
| ErrorWidget.builder: `MgV2.applied ? CrashViewV2 : old` + Back/Home buttons in the old one | FUNCTIONAL | Q3 | OFF = old widget plus two buttons (Q3 "way back everywhere"). |
| `PermissionOverlay(onBack: …)` | FUNCTIONAL | Q3 | back to language choice, both looks. |
| Removal of `HandoverPromptWatcher` (+ `/protocol` route in router) | FUNCTIONAL | none of Q1–Q7 | Commit 3e872afe (2026-10-10, already in origin/main): handover protocol only on the kiosk display (CLAUDE.md §28 flow). Customers on 4.1.3 had the in-app protocol; 4.2.0 drops it in BOTH looks. |
| `TimeoutClient`, `EngagementService`, `PaidChangeQueue.drain`, `recoverFailedProviders`, push init order, `ForcedSignOut`, `mgSafeRouterConfig` | FUNCTIONAL | Q3/Q4 mostly; EngagementService = Velín funnel (8d29aa87, in origin/main, not in Q list) | Not seams — other areas. `mgSafeRouterConfig` is cached per router (Expando), so rebuilding MaterialApp on a flag change does not re-parse the route. |

## 4. router.dart (seams)

| Hunk | Class | Request | OFF path | Risk | Test |
|---|---|---|---|---|---|
| ShellRoute `V2Switch(v1: AppShell, v2: AppShellV2)` | presentation | Q5 | AppShell | None (shell navigator has a GlobalKey, reparents) | wiring_test.dart |
| Tab roots `routerTabPage(… V2Switch(HomeScreen/HomeScreenV2 …))`, `/search`, `/reservations`, `/loyalty` | presentation | Q5 | `NoTransitionPage(child: old screen)` = base | None | wiring_test.dart |
| `/shop` `MgV2.peek ? routerSwipeBackPage : NoTransitionPage` | presentation | Q5 | base | None | — |
| `routerSwipeBackPage` for `/booking`, `/routes-list` | FUNCTIONAL | Q3 (commit 15673b9b, in origin/main) | Android OFF: NoTransitionPage = base. iOS OFF: MaterialPage → left-edge swipe now pops the booking form in the OLD look too. | Low: an accidental edge swipe leaves the form; the draft stays in the provider, but the old look's REZERVOVAT starts a fresh draft, so extras/address/sizes typed so far are lost. | fnd_flag_motion_test (generic pop only) |
| `observers: [MgBarsRouteObserver()]` | presentation | Q7 | `MgBarsScope.read` = getInheritedWidget → null in the old shell → no-op | None | bars tests |
| errorBuilder `RouteErrorPage`, MgBackGuard wrappers, `/route-build`/`/route-nav-custom` without extra → error page | FUNCTIONAL | Q3 | same in both looks | Low | route error tests |
| `/app/...` App Link redirect; reset-password `recoveryInProgress` exception; login/register `?email=` | FUNCTIONAL | not in Q list (App Links) / Q3 / Q5 "never twice" | in origin/main (668651c9) except `?email` | Low | — |
| Dead private `_BookingDebugWrapper` (≈850 lines) removed | cosmetic | — | route used the public `BookingDebugWrapper` already in base | None | — |

## 5. Old shell refactor (app_shell.dart → shell_*.dart) — runs with the flag OFF

| Hunk | Class | Request | Verified | Test |
|---|---|---|---|---|
| `onShellTabTap` (shell_tab_action.dart) | FUNCTIONAL | Q4 (running-payment confirm) + Q5 | OFF: identical go/reset as base (draft, moto, catalog filter reset on Domů); new: running payment → confirm before leaving. v2-only: keeps draft until a booking was paid. | shared_carry_test.dart, home_carry_test.dart, shell_test.dart |
| `ShellFabLayer` (v2=false) | refactor | — | Same visibility conditions and positions as base for cart/booking/SOS/route FABs; docs FAB now uses `docsFabStatusProvider` (docs gate RPC) instead of `docsVerifiedProvider` (commit 3e92168c, in origin/main, not in Q list); same default (hidden while unknown). | none |
| `ShellBookingFab` → `ShellVerifyingFab` when `booking.verifying` | FUNCTIONAL | Q4 | new "payment is being verified" pill instead of "pay again" | payment tests |
| `cancelPendingBookingFlow` | FUNCTIONAL | Q3 | OFF: same AlertDialog; failure now shows reason + retry instead of "cancelError" | none |
| `ShellPaidListener` | FUNCTIONAL | Q4 | NOT in 4.1.3 (comment says "moved unchanged" — it was added on this branch); snackbar after a payment confirmed after restart | paid_change tests |
| `openPendingPayment`, `openPendingSos`, SOS dismiss, route FAB | refactor | — | bodies identical to base `_BookingFab/_SosFab/_RouteFab` | none |
| `MgBackGuard(shell: true, child: child)` | FUNCTIONAL | Q3 | system back without history → parent | mg_back tests |

## 6. Helpers extracted for v2

| Helper | Extracted from (base) | OFF behaviour vs base | Test |
|---|---|---|---|
| home/home_actions.dart `refreshHome`, `warmUpRoutes` | HomeScreen onRefresh / initState | identical bodies | none |
| booking/booking_quote.dart `quoteFor` | (new, v2 only) | Same arguments `priceBreakdownProvider` gives a fresh draft (no extras, no delivery, no discounts, loyalty, pickupTime null). Not imported by any old file. | home_quote_test.dart, late_pickup_info_test.dart |
| booking/booking_entry.dart `startBookingFromSelection` | moto_detail_page REZERVOVAT | OFF branch identical (same draft fields, boots not prefilled, push /booking); extra side effect in both looks: `bookingDraftOwnerProvider = uid` (read only by v2 carry). | booking_prefill_flow_test.dart ("flag OFF: fresh draft") |
| reservations/res_actions.dart `rebookSameMoto` | res_detail_tab_content "Znovu rezervovat" | OFF identical (clears draft, moto, catalog filter; toast) | reservations_r2_test.dart ("old look … unchanged") |
| reservations/res_actions.dart `openBookingDoc` | res_detail_tab_content `_openBookingDoc` | changed in both looks: progress/cancel, offline reason + retry, "not available yet" text (Q3) | doc open tests |
| routes/ride_actions.dart `toggleManualRide` | my_experiences `_toggleManualRide` | Stop branch identical. Start branch is NOT the 4.1.3 body: `startManualResult` + `showRideStartResult` (reason + fix) replace `startManual` + "rideManualFailed" (Q6/Q3). Docstring "PŘESNĚ podle" refers to the pre-extraction branch code, not 4.1.3. | none for the function |
| booking_form_header_widget `bookingFormBack` | header back tap | identical body | none |
| catalog `detailStartDates` | detail initState | OFF returns the catalog filter = base | none |

## 7. Seams with v2-only logic (flag ON runs more than a presentation)

| Seam | What v2 adds | Request | Risk |
|---|---|---|---|
| booking_form_widget `_onDatesSelected` → `bookingFormShareDates` | writes the new dates to catalog filter / entry filter / calculator | Q5 2026-10-22 (never fill twice) | Low |
| booking_form_widget v2: `canProceed: canProceedNow() && !rangeBusy`, calendar forced open | blocks the CTA when the carried range overlaps a day the calendar shows busy | none explicit (Q5 says flows equal) | Low: old look lets the customer reach payment where the DB refuses; v2 stops earlier. Tested: booking_r2_test.dart |
| moto_detail_page v2: `detailRangeBusy` disables REZERVOVAT; `ref.listen(bookingDraftProvider)` follows form dates; `_pickRange/_pickReset` share dates | same | Q5 2026-10-22 / none for the guard | Low |
| shell_tab_action v2: Domů keeps the draft | Q5 2026-10-22 | Low | shared_carry_test.dart |
| res_actions v2: rebook keeps the catalog filter | Q5 2026-10-22 | Low | reservations_r2_test.dart |
| booking_entry v2: `carryBookingDraft` | Q5 2026-10-22 | Medium (carries extras of a previous draft to a new bike) — tested | booking_prefill_flow_test.dart |

## 8. Old-look functional hunks inside seam files (named, owned by other areas)

booking_form_widget: booked-dates error view + CTA locked until the occupancy is known (Q3); self-service gear size ranges (3e872afe, in main); EngagementService.trackCalc (8d29aa87, in main).
booking_ui_helpers: old unused `showAddrDialog` removed; address sheet `quick` options and distance fee only on confirm (Q5 / r2 fix).
onboarding_overlays `_selectLang`: now applies locale and currency immediately (87bef6c2, in main; not in Q list).
nickname_provider: extra "Cancel" button (Q3). home_screen: error view with retry (Q3). home_reservation_card: dead comparison removed (cosmetic).
notification_handler: deep link waits for login (max 2 min) and `pushOrGo` (Q3). login/register/reset: ForcedSignOut notice, biometric reasons, email carried to registration (Q3/Q5).
document_scanner: `_offerDlOnly` plan gate also in the old choice screen (Q7). offline_guard: continue-offline, call/112, captive-portal strip (Q3).

## 9. Counts

Files in this area read hunk by hunk: 25 (feature_flags.dart, v2_scope.dart, v2_gate.dart, main.dart, router.dart,
safe_router_config.dart, app_shell.dart, shell_actions/banner/fab_layer/fabs/fabs_b/paid_listener/tab_action.dart,
home_actions, booking_quote, booking_entry, res_actions, ride_actions, booking_form_header_widget,
booking_form_widget, moto_detail_page, res_detail_tab_content, my_experiences_screen (seam part), FeatureFlagsTab.jsx).
Seam files enumerated: 141 (328 seam lines; all 30 `peek` callback seams opened).
Functional hunks tabulated: 38; requested 29; unrequested 0 clearly; unsure (not in Q list, mostly already in origin/main) 6; requested-but-risky 3.
