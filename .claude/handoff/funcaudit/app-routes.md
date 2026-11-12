# Functional-diff audit — area app-routes (Android tree)

Scope: `Motogo-app-main/motogo-app-flutter/lib/features/routes/*.dart` excluding `v2/**`.
Base: `70a94933` (app 4.1.3 in the field). Head: working tree of branch `claude/moto-go-mobile-conversion-gqg5qo`.
Method: `git diff --stat/--numstat 70a94933 HEAD`, every hunk of the 35 modified files read; the 36 new files read for structure and for the
customer-facing decisions they take (recorder, pause engine, watcher, server API, road line, navigation status). Code was not edited.

Verified while auditing:
- Targeted tests run in the Android tree: `flutter test --no-pub test/rides test/v2/ux/road_line_test.dart test/ride_location_test.dart test/navigation_back_test.dart` = **304 passed, 0 failed**.
- `GpsService.status()` still requests the OS permission by default (`request = true`), so the replacements of the old `ensurePermission()` keep the
  permission prompt; only the automatic jump into the phone Settings was removed (explanation dialog + "Otevřít nastavení" on tap instead).
- All consumers of `catalogPoisProvider` / `userPoisProvider` outside `all_pois_screen.dart` use `valueOrNull` or `isLoading`, so the new error
  state of these providers cannot crash or blank another screen.
- GPS stream settings of the recorder (`distanceFilter 20 m`, 5 s interval, Android foreground notification, iOS background flags) are unchanged
  versus base (moved to `ride_location.dart`).
- `pushOrGo` (core/router.dart) uses `go()` when the top route is outside the shell; `/my-experiences` is outside the shell, `/routes/:id` inside.

Request key: Q1–Q7 as in the task; "PR #2208" = the ride-recording bug-fix PR the owner merged to `main` on 2026-10-15 (Velín-reported ride of
4. 10. with 2.3 km / Ø 97 km/h); it is in the app diff because 4.1.3 was built before it.

Statistics: **71 files** (35 modified, 36 new). Table rows: 81 (modified files, hunks grouped by purpose) + 20 (new files, grouped).
**Functional rows: 91** (72 in A, 19 in B; 10 rows are cosmetic-only). Requested: **87**. Clearly unrequested: **0**.
Unsure: **4** (rows 20, 33, R4, N1). Requested-but-risky flagged: **4** (rows 36, 42, 61, R2).

## A. Modified files

| # | File | Hunk | Class | Request | Risk (old look / customer paths) | Test |
|---|---|---|---|---|---|---|
| 1 | all_pois_screen.dart | v2 branch (`MgV2.on`) + callbacks extracted into shared closures (`onChanged`, `onClear`, `toggleNearby`, `apply`, `clear`, `pick…`) with unchanged bodies | cosmetic/refactor | Q5 | None for old look: bodies byte-identical, only moved | test/v2/screens/routes_test.dart, routes_cases*.dart |
| 2 | all_pois_screen.dart | Old look: back arrow always shown; tab root (Místa) → `context.go(Routes.home)`; pick mode pops | FUNCTIONAL (navigation) | Q3 visible way back | Low. Tab root gets a new arrow to Home | test/navigation_back_test.dart |
| 3 | all_pois_screen.dart | Error banner + "Zkusit znovu" when catalog POIs fail with no cache or user POIs fail | FUNCTIONAL (error handling) | Q3 | Low | test/v2/ux/rr_routes_test.dart (v2); old-look path no dedicated test |
| 4 | all_pois_screen.dart | `ensureLocation(ref, context:)` (location prompt, nearby filter, near-me sort) explains why location is missing | FUNCTIONAL (permissions UX) | Q3 | Low; still requests permission | none specific |
| 5 | animated_route_icon.dart | `once` parameter (default false) — v2 runs the animation once | cosmetic | Q5 | None (default = old behaviour) | v2 render cases |
| 6 | collapsing_header.dart | Back tap → `MgBackTap` (48 px hit area, screen-reader label) | FUNCTIONAL (minor, hit target) | Q3 | None | test/v2/ux/fold_header_test.dart |
| 7 | community_submit.dart | Add-menu: new row Pozastavit/Pokračovat záznam (own ride and rental) | FUNCTIONAL (flow) | Q6 manual pause | Low; row only while recording | test/rides/ride_rec_ui_test.dart |
| 8 | community_submit.dart | Stop-row subtitle text when paused; menu wrapped in `SingleChildScrollView` | cosmetic | Q6 / layout | None | — |
| 9 | community_submit.dart | Manual start uses `startManualResult()` + `showRideStartResult` (says what is wrong: permission, GPS off, offline); v2 result sheet | FUNCTIONAL (result states) | Q3 + Q6 | Low | test/rides/ride_rec_ui_test.dart |
| 10 | community_submit.dart | POI submit: `_initLocation` uses `GpsService.locate()` + `explainLocation(snack)` instead of silently doing nothing / opening Settings | FUNCTIONAL | Q3 | Low | none |
| 11 | community_submit.dart | POI submit: counts photos not uploaded and says so; error snack with "Zkusit znovu" | FUNCTIONAL | Q3 | Low | none |
| 12 | community_submit.dart | POI submit: `PopScope` + `confirmDiscard` when the form has data | FUNCTIONAL (flow: extra dialog) | Q3 (way back without silent data loss) | Low; adds one dialog on back | test/v2/states_test.dart (confirmDiscard) |
| 13 | community_submit.dart | Map tile error chip | FUNCTIONAL (error state) | Q3 | None | v2 render cases |
| 14 | my_experiences_screen.dart | v2 branch; actions extracted into shared methods (`_refresh`, `_historyDelete`, `_historyGo`, `_openSavedRoute`, `_navSavedRoute`, `_openPlace`, `_createRoute`, `_setAutoRecord`) with unchanged bodies | cosmetic/refactor | Q5 | None | test/v2/screens/rides_test.dart |
| 15 | my_experiences_screen.dart | Manual ride card replaced by `RideRecControlsCard` (start/stop own ride, Pozastavit/Pokračovat for own ride AND rental, phase text) and `toggleManualRide` moved to ride_actions.dart | FUNCTIONAL (flow) | Q6 | Medium: a rental rider can now pause the recording manually (GPS off) and forget to resume — that is what Q6 asked for | test/rides/ride_rec_ui_test.dart, ride_pause_decision_test.dart |
| 16 | my_experiences_screen.dart | Rides list grouped into trips (`groupRides`, `RideTripCard`) + merge row `RideMergeRow` | FUNCTIONAL | Q6 trip/merge | Low; trips only from a server that knows them (`rideTripsAvailable`) | test/rides/ride_trip_test.dart, ride_trip_ui_test.dart |
| 17 | my_experiences_screen.dart | `RideGpsLostBanner` while recording without GPS; `RideRecChip` instead of the fixed "⏺ nahrává" pill | FUNCTIONAL (state) | Q3 + Q6 | Low | test/rides/ride_rec_ui_test.dart |
| 18 | my_experiences_screen.dart | Saved routes / places: error view with reason + retry instead of the empty state | FUNCTIONAL | Q3 | Low | none old-look |
| 19 | my_experiences_screen.dart | Route delete failure is reported (snack) | FUNCTIONAL | Q3 | Low | none |
| 20 | my_experiences_screen.dart | History card → route detail: `context.push` → `context.pushOrGo` (= `go()` here) | FUNCTIONAL (navigation) | **UNSURE** (comes from the Q3 commit 15673b9b; comment: push would double the shell) | Medium: with `go()` the stack is rebuilt, so Back from the route detail lands on the Routes list, not on Moje zážitky (old and new look) | none |
| 21 | my_experiences_screen.dart | Back arrow `MgBackTap`; dialog Cancel label `routesFilterClear` → `cancel` | cosmetic (label bug fix) / Q3 hit target | Q3 | None | — |
| 22 | places_map.dart | `errorTileCallback`/`reset` + `MapTileErrorChip` | FUNCTIONAL (error state) | Q3 | None | test/v2/ux/fix_r2_core_test.dart |
| 23 | places_map_screen.dart | On open `requestLocationQuietly` instead of `ensureLocation` (no Settings jump); "moje poloha" button explains | FUNCTIONAL | Q3 | Low; permission still requested | none |
| 24 | places_map_screen.dart | Tile error strip, back `MgBackTap`, v2 title fit / button width | Q3 / cosmetic | Q3, Q5 | None | v2 render |
| 25 | poi_rating.dart | v2 branch only | cosmetic | Q5 | None | rr_reviews_test.dart |
| 26 | poi_reviews.dart | v2 branches; old-look sheet handle → `MgSheetHandle` (adds a visible ✕) | cosmetic + Q3 close | Q3/Q5 | None | rr_reviews_test.dart |
| 27 | poi_suggest.dart | v2 styling, title wrap, chip row height in v2 | cosmetic | Q5 | None | v2 render |
| 28 | ride_booking_section.dart | Booking detail: sum line for ≥ 2 rides (`rpBookingTotal`), trips grouped (`RideTripCard` + its rides) | FUNCTIONAL (content) | Q6 multi-day trip / statistics | Low; section only renders when rides exist | test/rides/ride_trip_ui_test.dart |
| 29 | ride_card.dart | Badge = live recorder phase (nahrává / čeká / pozastaveno) for the ride being recorded; date range + days (≥ 2); saddle time shown instead of total time (total only when no moving time) | FUNCTIONAL (content) | Q6 sane statistics | Low | test/rides/ride_ui_fix_r1_test.dart, ride_trip_ui_test.dart |
| 30 | ride_detail_screen.dart | Loading and error states with Back + retry (error no longer shown as "Jízda nenalezena") | FUNCTIONAL | Q3 | Low | test/v2/states_test.dart |
| 31 | ride_detail_screen.dart | Visibility / edit / delete results checked; failure snack with retry; delete failure stays on detail | FUNCTIONAL | Q3 | Low | none |
| 32 | ride_detail_screen.dart | Deleting the ride that is being recorded: warning text + `discardCurrent()` before delete | FUNCTIONAL | Q6 (+Q3) | Low–medium; recorder state change on delete | test/rides/ride_recorder_test.dart (discardCurrent) |
| 33 | ride_detail_screen.dart | Old stats card replaced by `RideStatsGrid`: adds pauses, days, "Na cestě" label for stats_v2 rides; **drops the "GPS body" and "Přerušení" cells** and the old gap notice text (`rideGapNotice` → `rideGapEstNotice`) | FUNCTIONAL (content) | Q6 sane statistics; removal of two cells **UNSURE** | Low (informational) | test/v2/screens/rides_pause_fit_test.dart, rides_test.dart |
| 34 | ride_detail_screen.dart | `RideStageList` (≥ 2 stages) + `RideTripRow`; title on 2 lines (`RideFitText`); date range | FUNCTIONAL / cosmetic | Q6 | Low | test/rides/ride_trip_ui_test.dart |
| 35 | ride_detail_screen.dart | v2 pager + swipe animation, v2 dialogs | cosmetic | Q5/Q7 swipe | None | rides_test.dart |
| 36 | ride_map.dart | GPS gap drawn as grey dotted ESTIMATED road route (Mapy routing, ≤ 25 gaps/ride) + label on the big map; nothing drawn until routed | FUNCTIONAL (network + display) | Q7 gaps as estimated road route | Low–medium: every ride map (also small card previews) fires up to 25 routing calls per ride; cached in memory per run | test/v2/ux/road_line_test.dart |
| 37 | ride_map.dart | Pauses no longer drawn as gaps; moved pause (> 300 m, ferry/trailer) dashed blue-grey | FUNCTIONAL | Q6 | Low | road_line_test.dart, ride_trip_ui_test.dart |
| 38 | ride_map.dart | `RideTrackMap` → `ConsumerStatefulWidget`; tile error chip | FUNCTIONAL (infra) / Q3 | Q7, Q3 | None (ProviderScope is app-wide) | — |
| 39 | ride_model.dart | `_splitOnGaps`: pause = marker `kmh < 0` or silence ≥ 5 min without ride-through; gap = silence > 180 s with > 300 m at ≥ 15 km/h; bad dt ≥ 30 days; fractional timestamps kept | FUNCTIONAL (data) | Q6 (same rule as server/Velín) | Medium: changes how every existing ride is split on display | test/rides/ride_r4_fix_test.dart, ride_trip_test.dart |
| 40 | ride_model.dart | New fields `pauseSec`, `pauseAware`, `tripId/tripName`, `stages`, `serverV2`, `statsV2`; `hasGaps` excludes pauses; `days`, `pauseCount` | FUNCTIONAL (data) | Q6 | Low (missing keys → defaults) | ride_trip_test.dart |
| 41 | ride_point_sheet.dart | `enableDrag: false` + visible ✕ + `PopScope`/`confirmDiscard` when dirty | FUNCTIONAL (gesture + flow) | Q3 | Low; old-look drag-to-dismiss removed | none |
| 42 | ride_point_sheet.dart | Save failure keeps the sheet open with reason; partial photo upload reported; re-save edits the created point (`_savedId`) | FUNCTIONAL | Q3 | **Risky**: on partial upload the uploaded photos stay in `_newPhotos` and are already appended to `_photos`, so "Uložit" again uploads them again → duplicate photos (and > 8) | none |
| 43 | ride_point_sheet.dart | Delete failure reported; photo-picker error shown with permission hint | FUNCTIONAL | Q3 | Low | none |
| 44 | ride_provider.dart | `RideStart` carries `bookingId`; append/finish RPC timeout 30 s; `RideAppendOutcome` (ok/retry/closed/gone + live totals) replaces enum | FUNCTIONAL (network) | Q6 + PR #2208 robustness | Low; retries are server-deduplicated | test/rides/ride_server_api_test.dart, ride_late_chunk_test.dart |
| 45 | ride_share.dart | Share text: date range, days, saddle time instead of total duration; trip share text; `rideShareTap` extracted (same body) | FUNCTIONAL (content) | Q6 | Low | ride_trip_ui_test.dart |
| 46 | ride_share.dart | Sheet title row with ✕ (`MgSheetTitleRow`); v2 sheet | Q3 / cosmetic | Q3, Q5 | None | — |
| 47 | ride_recorder.dart (rewrite, + 5 `part` files) | See section B rows R1–R8 | FUNCTIONAL | Q6 + PR #2208 | see B | test/rides/* |
| 48 | route_builder_screen.dart | `_edited` + `PopScope`/`_leave` with confirm before discarding unsaved stops | FUNCTIONAL (flow) | Q3 | Low | test/navigation_back_test.dart |
| 49 | route_builder_screen.dart | Routing failure → no line and no distance (was straight connectors + their length); saved route then has `distance_km` null | FUNCTIONAL (display/data) | Q7 | Low | road_line_test.dart |
| 50 | route_builder_screen.dart | Save / suggest sheets moved to `route_builder_sheets.dart`; prefilled from `RouteNameMemory` (saved route's own name/desc, remembered after first save) | FUNCTIONAL (prefill) | Q5 "never fill twice" (2026-10-22) — applied in old look too | Low | test/v2/screens/route_names_carry_test.dart |
| 51 | route_builder_screen.dart | Tile error chip; back `MgBackTap`; v2 layout/fit padding | Q3 / cosmetic | Q3, Q5 | None | — |
| 52 | route_detail_screen.dart | Loading/error states with Back + retry (error no longer "Trasa nenalezena") | FUNCTIONAL | Q3 | Low | test/v2/states_test.dart |
| 53 | route_detail_screen.dart | Preview line before routing: only stored ROAD geometry, never straight stops | FUNCTIONAL | Q7 | Low; offline = POI pins without line | road_line_test.dart |
| 54 | route_detail_screen.dart | Missing route: explanation + button label "Zpět" (was "Zkusit znovu" that went back) | FUNCTIONAL (text/state) | Q3 | None | — |
| 55 | route_detail_screen.dart | Back `MgBackTap` wrapping `PressableScale`; full-map close `MgBackTap`; v2 views, v2 export sheet | Q3 / cosmetic | Q3, Q5 | None (only one recognizer wins) | navigation_back_test.dart |
| 56 | route_image.dart | v2 placeholder/fade | cosmetic | Q5 | None | — |
| 57 | route_map.dart | Tile errors; v2 draw-once animation | Q3 / cosmetic | Q3, Q5 | None | — |
| 58 | route_nav_widgets.dart | Close buttons on stop/done cards → `MgBackTap`; stops sheet handle with ✕; rest v2 | Q3 / cosmetic | Q3, Q5 | None | v2 render cases_ux_routes_nav.dart |
| 59 | route_navigation_screen.dart | Start: `GpsService.status(request: true)`; denied/serviceOff → `NavStatusBanner` with "Povolit polohu"; re-check on app resume (without re-prompt) | FUNCTIONAL (permissions) | Q3 | Low | none logic-level |
| 60 | route_navigation_screen.dart | GPS stream `onError` → "GPS ztracena" banner; service-status stream (location switched off/on → restart stream) | FUNCTIONAL | Q3 | Low | none |
| 61 | route_navigation_screen.dart | 5 s timer: no fix for > 20 s → "Slabý GPS signál" banner | FUNCTIONAL (timing) | Q3 | **Risky**: stream uses `distanceFilter: 4`, so a rider standing still (lights, fuel, photo stop) gets no fixes and sees a false "weak GPS signal" banner after 20 s | none |
| 62 | route_navigation_screen.dart | Routing failed → `_straightLine` banner ("ukazuji spojnici bodů") + re-route every ~30 s | FUNCTIONAL (network) | Q7 (owner said yes to straight guide line with banner offline) | Low | none |
| 63 | route_navigation_screen.dart | `RideForeignStreams.opened/closed` (recorder can borrow the navigation GPS stream) | FUNCTIONAL | PR #2208 | Low | test/ride_location_test.dart |
| 64 | route_navigation_screen.dart | Data loading/error states with Back + retry; "route not found" view | FUNCTIONAL | Q3 | Low | — |
| 65 | route_navigation_screen.dart | `RideNavRecChip` in the old-look header (tap → pause sheet) | FUNCTIONAL | Q6 | Low | ride_rec_ui_test.dart |
| 66 | route_navigation_screen.dart | Dialog Cancel label fix; tile error chip; v2 HUD/buttons; circle buttons `MgBackTap` | cosmetic / Q3 | Q3, Q5 | None | — |
| 67 | route_poi_sheet.dart | Visible ✕ on POI sheet; photo viewer ✕ darker + `MgBackTap`; photo-credit sheet ✕; zoom hint moved bottom-right | Q3 / cosmetic | Q3 | None | routes_sheets_r2_test.dart |
| 68 | route_reviews.dart | v2 branches; old sheet handle → `MgSheetHandle` (✕) | cosmetic / Q3 | Q3, Q5 | None | rr_reviews_test.dart |
| 69 | route_submit_screen.dart | Routing failure → no line | FUNCTIONAL | Q7 | Low | — |
| 70 | route_submit_screen.dart | Dropped-photos notice; error snack with retry | FUNCTIONAL | Q3 | Low | none |
| 71 | route_submit_screen.dart | `PopScope` + `confirmDiscard` | FUNCTIONAL (flow) | Q3 | Low | — |
| 72 | route_submit_screen.dart | Tile errors, v2 scaffold | Q3 / cosmetic | Q3, Q5 | None | — |
| 73 | routes_map_picker.dart | v2 panel/colour/height helpers (old look returns the old constants) | cosmetic | Q5 | None | — |
| 74 | routes_map_provider.dart | Failed road line retried later (`retryRoadLineLater`, ≤ 3×, 20/40/60 s) | FUNCTIONAL (network) | Q7 | Low | road_line_test.dart |
| 75 | routes_map_screen.dart | Quiet location request at open; explanation on "moje poloha"; tile strip; `MgBackTap`; v2 chrome | FUNCTIONAL / cosmetic | Q3, Q5 | Low | — |
| 76 | routes_model.dart | `isRoadGeometry`: stored geometry with ≤ stops + 2 points is treated as missing → recomputed along roads | FUNCTIONAL (data) | Q7 | Low; a genuine road line has hundreds of points | road_line_test.dart |
| 77 | routes_provider.dart | Catalog POIs: no cache + no network → error (offline vs unavailable) instead of `[]`; user POIs rethrow | FUNCTIONAL (error states) | Q3 | Low (consumers verified) | none |
| 78 | routes_provider.dart | `ensureLocation({context})`: `GpsService.status()` (still requests permission), explain dialog instead of opening Settings | FUNCTIONAL | Q3 | Low | none |
| 79 | routes_provider.dart | `routeDisplayProvider`: routing failure → empty geometry + retry (was straight stops) | FUNCTIONAL | Q7 | Low; navigation has its own fallback (#62) | road_line_test.dart |
| 80 | routes_screen.dart | Old look: back arrow always (`backOr(Routes.routes)`); location explain in filter sheet; v2 branches; callbacks extracted (same bodies) | FUNCTIONAL (nav) / refactor | Q3, Q5 | Low | navigation_back_test.dart, routes_test.dart |
| 81 | submit_common.dart | Photo-picker error → explanation + Settings; v2 intro/success | FUNCTIONAL / cosmetic | Q3, Q5 | None | — |

## B. New files (one row each; recorder rows R1–R8 expand row 47)

| # | File | Content | Class | Request | Risk | Test |
|---|---|---|---|---|---|---|
| R1 | ride_recorder.dart + ride_recorder_stream.dart | Stream attach/re-attach on resume, no-fix re-attach (2 min, 30 min in auto-pause), clock offset hold (20 s), chunked append (2000 points), persistence every 30 s | FUNCTIONAL | Q6 + PR #2208 | Medium (core of auto-recording for every rental with location permission) | ride_recorder_test.dart, ride_recorder_fix_test.dart, ride_late_chunk_test.dart |
| R2 | ride_recorder_server.dart, ride_server_api.dart, ride_server_seam.dart | `start_user_trip` with fallback to `start_user_ride` when the server lacks it (PGRST202/42883/42703/404 = "missing"; offline never = old server); booking_inactive handling, continuation after server close, caps cached 30 min | FUNCTIONAL (network/data) | Q6 | **Risky**: depends on the SQL bundle (task 31) being deployed; on an old server the legacy path runs with auto-pause ON by default (missing `ride_autopause` row = enabled) | ride_server_api_test.dart, ride_offline_start_test.dart |
| R3 | ride_recorder_pause.dart, ride_pause_engine.dart, ride_motion.dart, ride_pause_guards.dart, ride_session.dart | Auto-pause by stop (5 min)/walk (3 min), resume by Doppler ≥ 20 km/h (or slow-resume rules), pause marker `kmh = −1`, preroll, manual pause = GPS off, session restore | FUNCTIONAL | Q6 | Medium; extensive unit tests | ride_pause_engine_test.dart, ride_motion_test.dart, ride_pause_decision_test.dart, ride_pause_guard_test.dart, ride_session_test.dart |
| R4 | ride_pause_guards.dart (guards) | "Home" notice (own trip paused ≥ 3 h near trip start), "trip idle since…" reminder (≥ 20 h), **GPS switched off after 48 h pause without opening the app — also for a rental** | FUNCTIONAL (timing) | **UNSURE** (Q6 asked pause/resume by movement and multi-day trip; these extra guards are design additions, tunable/disable-able via Velín flag `ride_autopause.conditions` long_h/idle_h/home_h = 0) | Medium: a rental rider who leaves the bike ≥ 48 h and then rides without opening the app records nothing until the app is opened | ride_pause_guard_test.dart |
| R5 | ride_flags.dart | Kill-switch `feature_flags.ride_autopause` + thresholds (8 s timeout, cached) | FUNCTIONAL | Q6 | Low | ride_recorder_test.dart |
| R6 | ride_recorder_watcher.dart | Recording window = pickup (`issuedAt`/active + planned time) → return; **gear-only bookings never record**; prefer current rental (two bikes on one account); SOS swap → `switchRental`; own paused trip + new rental → `finishOwnForRental`; flush on background, re-check stream on resume | FUNCTIONAL | PR #2208 (file origin) + Q6 + gear backend (Q8) | Medium | ride_watcher_gear_test.dart, ride_recorder_test.dart |
| R7 | ride_recorder_handoff.dart, ride_recorder_offline.dart | Rental hand-over / SOS swap split of points, carry-over buffer, offline start (ride starts at first point of the session) | FUNCTIONAL | Q6 | Medium | ride_late_chunk_test.dart, ride_offline_start_test.dart, ride_r5_fix_test.dart |
| R8 | ride_recorder_state.dart, ride_rec_phase.dart | State + phase (recording/armed/auto-paused/paused/gps-lost) and chip keys | FUNCTIONAL (state) | Q6 | Low | ride_rec_ui_test.dart |
| N1 | ride_location.dart | Fix time = GPS fix time, stale/cached fix filters, own 20 m filter, `RideKeepAlive`, diagnostics, `RideForeignStreams` | FUNCTIONAL | PR #2208 (UNSURE as a request, see flagged item) + Q6 statistics | Low | test/ride_location_test.dart |
| N2 | ride_live_stats.dart | Live km/time/day labels | FUNCTIONAL (display) | Q6 | Low | ride_live_stats_test.dart |
| N3 | ride_merge_screen.dart, ride_trip.dart, ride_trip_api.dart, ride_trip_card.dart, ride_trip_detail_screen.dart, ride_trip_row.dart, ride_trip_ui.dart | Trips: grouping, merge rides into a trip and split back (`set_user_rides_trip`, unavailable on old server), trip detail/share | FUNCTIONAL | Q6 merge/split | Low | ride_trip_test.dart, ride_trip_ui_test.dart |
| N4 | ride_stage.dart, ride_stage_list.dart | Days/stages of a multi-day ride | FUNCTIONAL | Q6 | Low | ride_trip_test.dart |
| N5 | ride_stats_grid.dart | New statistics grid (see row 33) | FUNCTIONAL | Q6 | Low | rides_pause_fit_test.dart |
| N6 | ride_rec_controls.dart, ride_pause_actions.dart, ride_pause_sheet.dart | Controls card, pause sheet, nav chip, pause/resume/stop actions with feedback | FUNCTIONAL | Q6 | Low | ride_rec_ui_test.dart |
| N7 | ride_start_feedback.dart | Start/pause result texts (what is wrong, how to fix) | FUNCTIONAL (result states) | Q3 + Q6 | Low | ride_rec_ui_test.dart |
| N8 | ride_actions.dart | Shared `toggleManualRide` (same body as old `_toggleManualRide`, `startManualResult` feedback) — also used by v2 Home "Zaznamenat jízdu" | FUNCTIONAL | Q5 exception "Zaznamenat jízdu" + Q6 | Low | ride_rec_ui_test.dart |
| N9 | road_line.dart | `roadLineProvider`, retry ≤ 3×, gap road estimate (≤ 25 per ride), Home sketch | FUNCTIONAL (network) | Q7 | Low–medium (API call volume, see row 36) | road_line_test.dart |
| N10 | route_builder_sheets.dart | Save/suggest sheets (old look identical fields/validation) + `RouteNameMemory` prefill | FUNCTIONAL (prefill) | Q5 | Low | route_names_carry_test.dart |
| N11 | route_nav_status.dart | Navigation status banner (denied, location off, GPS lost, weak GPS, straight line) | FUNCTIONAL | Q3, Q7 | see row 61 | v2 render cases only |
| N12 | ride_fit_text.dart | Text shrink-to-fit helper | cosmetic | Q5/layout | None | rides_pause_fit_test.dart |

## C. Flagged hunks (returned in the structured result)

1. **Row 20** — `pushOrGo` from Moje zážitky history to route detail: Back no longer returns to Moje zážitky (UNSURE → ASK).
2. **Row 61** — false "Slabý GPS signál" banner in navigation when standing still > 20 s (requested Q3, risky → KEEP, fix the condition, add a test).
3. **Row 42** — ride point sheet: re-save after a partial photo upload duplicates photos (requested Q3, risky → KEEP, fix + test).
4. **R4** — pause guards: GPS off after 48 h pause also during a rental, plus home/idle reminders (UNSURE → ASK).
5. **R2** — recorder trip protocol depends on the SQL bundle; legacy fallback runs with auto-pause on (requested Q6, risky → KEEP; verify the SQL ships in the same merge).
6. **Row 33** — two statistics cells removed from the old-look ride detail (UNSURE → ASK).
7. **Row 36 / N9** — gap road estimates on every ride map: routing call volume (requested Q7, risky → KEEP).
8. **N1 / R6 / row 63** — PR #2208 app code (fix time, stream sharing with navigation, watcher) is in the diff because 4.1.3 predates it; owner merged it to main but it is not in Q1–Q7 (ASK, do not revert — Q6 code builds on it).
