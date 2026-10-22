# LOGIC_API — záznam jízd: pauza, auto-pauza, relace, cesty (impl:logic, 2026-10-22)

Public contract for the UI tasks (old look in both trees, v2 Android only). Code against THIS file; everything else in the recorder is private.
Spec: `SPEC.md` §5–§8, §10, §13. Implemented in BOTH trees, **byte-identical** (no geolocator 14 vs 10 differences were needed — only APIs present in geolocator 10.1.1 / platform_interface 4.3.0 are used: `hasSpeed`, `hasSpeedAccuracy`, `hasAccuracy`, `hasAltitudeAccuracy`; no `verticalSpeed*`).

## 0. Files (lib/features/routes/, both trees identical)

| File | What | Size |
|---|---|---|
| `ride_motion.dart` (new) | `RideFix`, `RideMotionConfig` (+`withFlag`), `RideMotionDetector` (isSlow / released / evalPending / resumeTrigger / preRollStart), `ridePointFromRideFix`, `rideClassifyPair` + `RidePairKind` (mirror of server §3.2), `rideIsMovingPair`, `rideDistM`, `ridePathLenM`, `rideMedian` | 14 KB |
| `ride_pause_engine.dart` (new) | `RidePauseEngine` (pure state machine §6.3), `RideEngineStep`, `RideEngineLog` | 17 KB |
| `ride_session.dart` (new) | `RidePhase`, `RidePauseReason`, `RideSessionMeta` (`mg_ride_session` v1), `RideServerCaps` (`mg_ride_caps`) | 7 KB |
| `ride_server_api.dart` (new) | `classifyRideRpcError`, `RideAppendOutcome`/`RideAppendResult {ok,retry,closed,gone}`, `startUserTrip` → `RideTripStart`, `probeRideServerV2`, `setUserRidesTrip` → `RideTripSetResult`, `RideTripItem`, `rideClockOffset` | 8 KB |
| `ride_server_seam.dart` (new) | `RideServerSeam` + `rideServerSeamProvider` (test seam) | 1 KB |
| `ride_flags.dart` (new) | `RideAutoPauseFlag` + `fetchRideAutoPauseFlag()` (flag `ride_autopause`, missing row = ON) | 3 KB |
| `ride_live_stats.dart` (new) | `rideLiveDelta`, `rideLiveKm`, `rideLiveDuration`, `rideClock`, `rideShortDate`, `rideEpochToLocal`, `ridePluralForm`, `rideDaysLabel`, `rideRidesLabel`, `rideIsStageBoundary` | 4 KB |
| `ride_recorder_state.dart` (new, exported by `ride_recorder.dart`) | `RideRecorderState` (new fields + getters), `RideStartResult` | 5 KB |
| `ride_recorder.dart` (rewritten; library with 3 `part`s) | `RideRecorderNotifier`, `rideRecorderProvider`, keys, public API | 18 KB |
| `ride_recorder_stream.dart` / `_server.dart` / `_pause.dart` (new `part of`) | stream & lifecycle / server, flush, continuation, caps, flag, stop / pauses, session, live, notification | 6 / 13 / 12 KB |
| `ride_recorder_watcher.dart` (changed) | active-booking feed, own→rental switch, notice snackbar, failed-stop retry first | 7 KB |
| `ride_location.dart` (changed) | `rideFixFromPosition`, `rideDopplerKmh`, `ridePointFromFix` (wrapper, old tests), `rideTrOr`, `rideTrOpt`, `RideKeepAlive.notify/notifyIdle/cancelIdle/battery`, `rideLogTestSink` | 12 KB |
| `ride_provider.dart` (changed) | `appendRideTrack` → `RideAppendOutcome` (old enum `finished` split into `closed`/`gone`) | 8 KB |
| `ride_model.dart` (changed) | `UserRide` new fields/getters, `_splitOnGaps` mirrors server §3.2, `RideGap.kind` | 15 KB |
| `ride_stage.dart` (new, exported by `ride_model.dart`) | `RideStage`, `rideDaysOfStages`, `rideCalendarDays` | 3 KB |
| `ride_trip.dart` (new) | `rideTripKey`, `RideListItem` (sealed) / `RideListItemRide` / `RideListItemTrip`, `groupRides`, `RideTrip` (+`aggregate`), `rideTripsAvailable`, `myRideItemsProvider`, `rideDateRange`, `rideTripDefaultName` | 9 KB |
| `ride_trip_api.dart` (new) | merge/split/rename/add/remove/undo plans, `rideTripApply`, `rideTripSetVisibility`, `rideTripDeleteAll`, `RideTripOp`, `RideTripOpResult`, `rideTripResultKey` | 6 KB |

Outside routes: `core/cache_cleanup_service.dart` (both trees) — `'mg_ride_session'`, `'mg_ride_caps'` added to `_preserveKeys`.
Android only: `android/.../RideEngineKeeper.kt` (`register(engine, context)` + methods below), `MainActivity.kt` (`RideEngineKeeper.register(flutterEngine, this)`).

## 1. Recorder contract (`import 'ride_recorder.dart'` — re-exports state, `RidePhase`, `RidePauseReason`)

### 1.1 `RideRecorderState` (new fields; `copyWith(clearRide)` resets them)

```dart
final RidePhase phase;               // riding | autoPaused | manualPaused (meaningful only when recording)
final RidePauseReason? pauseReason;  // start | stop | walk | silence | manual | home | long; null while riding
final DateTime? pausedSince;         // LOCAL time of the anchor (where/when the bike stopped, or "ready since")
final double liveKm;                 // server total from the last append + unsent buffer (same rule as server)
final int liveMovingSec;             // time in the saddle (s)
final int liveStages;                // days/stages: server stages_n (new server) else local estimate (≥ 1)
final DateTime? tripStartedAt;
final String? notice;                // one-shot i18n key — the WATCHER shows it (snackbar 6 s) and consumes it
final Map<String, String>? noticeArgs;
final bool autoPauseOn;              // flag ride_autopause as applied to this session

bool get isPaused;        // recording && phase != riding   (auto + manual + armed)
bool get isArmed;         // recording && autoPaused && reason == start  ("Čeká na rozjezd")
bool get isManualPaused;  // recording && manualPaused   (GPS off)
bool get needsDecision;   // manualPaused because of a guard: reason home | long → offer [rpResumeTrip] [rpEndSave]
bool get canStop;         // recording && manual   (a rental ends at return / auto switch)
bool get isRidingLive;    // recording && riding && !gpsLost   (only then animate/ping)
```

`recording` stays true in EVERY phase ("trip is running"). `points` is diagnostics only — show `liveKm`/`liveMovingSec` instead (`rideLiveKm`, `rideLiveDuration`).

### 1.2 `RideRecorderNotifier` methods

| Method | Semantics |
|---|---|
| `Future<void> pause()` | Manual pause (own AND rental). Local, cannot fail. Pending slow points → only the anchor is sent; flush; GPS stream cancelled (Android FGS + notification gone, iOS blue pill gone); phase `manualPaused/manual`; session saved (survives kill — restore does NOT re-attach GPS). No-op when not recording / already manually paused. |
| `Future<RideStartResult> resume()` | Foreground only (call from a tap). Same checks as manual start: `notSignedIn`, `locationOff`, `noPermission`, `imprecise` (iOS) → show with the existing `showRideStartResult`. `ok` → GPS re-attached, phase `autoPaused/start` (armed — recording starts at departure; the first point after the pause carries the −1 marker). With the kill-switch off it goes straight to `riding`. Returns `ok` if not manually paused; `failed` if not recording. Used for `needsDecision` "Pokračovat v cestě" too. |
| `Future<bool?> stop()` | Unchanged semantics; works in every phase. true = saved, false = < 1 km discarded, null = not closed (offline; retried by the watcher). While paused nothing extra is sent — the server ends the ride at the last point (+ ≤ 2 min). Use only when `canStop` (own ride) or for `needsDecision` "Ukončit a uložit" (own trips only — guards never fire for rentals). |
| `Future<void> discardCurrent()` | Detach + forget WITHOUT finish. Call it BEFORE `deleteUserRide` of the currently recording ride. Auto-start is suppressed 30 s so the watcher doesn't resume the ride being deleted; for an active rental a fresh armed ride starts afterwards (say so in the confirm text: `rpDeleteRecordingRentalQ`). |
| `void consumeNotice()` | Called by the watcher after showing `notice`. UI normally does nothing. |
| `void setActiveBooking(String?)` | Called by the watcher every build (manual start during a picked-up rental is attributed to it). |
| `Future<void> finishOwnForRental(String bookingId)` | Called by the watcher (own trip paused + rental picked up). UI does nothing. |
| unchanged | `startManual()`, `startManualResult()` (now attributes to the active rental), `ensureRecording()` (no-op while paused — `recording` is true), `setEnabled()` (switch off ends a rental in any phase), `onAppResumed()`, `flush()`, `canRetryStop`, `hasLocationPermission()` |
| test only | `debugTick()`, top-level `rideRecorderClock`, `rideLogTestSink` (ride_location.dart), `rideServerSeamProvider.overrideWithValue(fake)` |

### 1.3 UI phase mapping (both looks)

| Condition | Text key | Chip |
|---|---|---|
| `isRidingLive` | `rpPhaseRiding` | `rpChipRec` |
| `isArmed` | `rpPhaseArmed` | `rpChipArmed` |
| `phase == autoPaused` (stop/walk/silence) | `rpPhaseAuto` + `rpSince{time: rideClock(pausedSince!)}` | `rpChipPaused` |
| `isManualPaused && pauseReason == manual` | `rpPhaseManual` + `rpSince` | `rpChipPaused` |
| `needsDecision && pauseReason == home` | `rpPhaseHome` + `rpHintHome{h}` (h = 3, or flag `home_h`) | `rpChipPaused` |
| `needsDecision && pauseReason == long` | `rpPhaseLong{date}` + `rpHintLong{h}` (h = 20, or flag `long_h`) | `rpChipPaused` |
| `gpsLost` | existing `RideGpsLostBanner` | — |

Pause/resume button: show `pause()` when `recording && !isManualPaused` (also while auto-paused/armed — it then turns GPS off), `resume()` when `isManualPaused`. Live line: `rpLiveLine{km: rideLiveKm(liveKm, lang), time: rideLiveDuration(liveMovingSec)}`; append `rpDayN{n: liveStages}` when `liveStages ≥ 2`; Ø = `liveKm / (liveMovingSec/3600)` only when `liveMovingSec ≥ 300`.

## 2. Live/format helpers (`ride_live_stats.dart`)

`rideLiveKm(km, [lang])` → "12,3" (dot for `en`, no decimals ≥ 100); `rideLiveDuration(sec)` → "45 min" / "1 h 20 min" / "2 d 3 h"; `rideClock(DateTime)` → "20:14"; `rideShortDate(DateTime)` → "6. 10. 2026"; `ridePluralForm(n, lang)` → `One|Few|Many` (cs/sk 1/2–4/else; pl, uk last-digit with 12–14 = Many; fr 0–1 = One; others One/Many); `rideDaysLabel(n, tr)` → `rpDays{One|Few|Many}{n}`; `rideRidesLabel(n, tr)` → `rpRides{…}{n}`; `rideIsStageBoundary(fromTs, toTs)`.

## 3. Model (`ride_model.dart` + `ride_stage.dart`)

`UserRide` new: `pauseSec`, `pauseAware`, `tripId`, `tripName`, `stages` (`List<RideStage>`), `serverV2` (row contains `pause_aware` = new server); getters `pauseMin`, `pauseCount` (segments whose `gapBefore.kind == pause`), `activeMin` (= `totalMin`; `durationMin` now = on the road WITHOUT pauses on the new server), `days` (stages, else calendar days when `movingSec ≥ 300`), `inExplicitTrip`. `hasGaps` now = real gaps only (`gapSec > 0` or a `gap` segment) — pauses/nights no longer trigger the gap notice.
`RideGap.kind` (`RideGapKind.gap | pause`, `isPause`). Segments split exactly like the server: marker −1 → pause; silence > 180 s ridden through (≥ 15 km/h and > 300 m) → gap; otherwise silence ≥ 300 s → pause (even if the phone moved — ferry/trailer → draw dashed only when `km > 0.3`); ≥ 30 days → bad time (no split). UI (T3/T4) must draw `kind == pause` differently from gaps (SPEC §9.1 ride_map).
`RideStage {from, to, km, movingSec, gapSec, pauseSec, gain, max, a, b}` + `idleSec` (remainder), `avgKmh`. `rideDaysOfStages(stages)`, `rideCalendarDays(a, b)`.

## 4. Trips (`ride_trip.dart`, `ride_trip_api.dart`)

```dart
String rideTripKey(UserRide r);                 // 't:<trip_id>' > 'b:<booking_id>' > 'r:<id>'  (trip_id == id ⇒ standalone)
List<RideListItem> groupRides(List<UserRide>);  // groups ≥ 2 → RideListItemTrip; newest first
final myRideItemsProvider;                      // Provider<AsyncValue<List<RideListItem>>> from myRidesProvider
bool rideTripsAvailable(rides, [items]);        // show "Sloučit jízdy" only when true (new server && ≥ 2 items)
class RideTrip { key; rides (oldest first); leader; explicitTripId; name; commonBookingId; isRental; isRecording; isPublic; from; to; days; aggregate }
String rideDateRange(DateTime a, DateTime b);   // "6. 10. 2026" | "6.–11. 10. 2026" | "28. 9. – 3. 10. 2026" | full both
String rideTripDefaultName(RideTrip, AppTranslations); // name ?? rpTripRental{moto} ?? rpTripDefault{dates}
```
`aggregate` is a `UserRide` (render it with the existing detail/map/stat widgets): id = leader id; Σ km/moving/idle/gap/elevation/durationMin; `pauseSec` = Σ + time between consecutive rides; max = max; avg = Σkm/Σmoving; track/segments concatenated (member boundary = pause or gap by the silence rule); only the first `start` and last `end` RidePoints; stages concatenated; `bookingId` only when common; `isRecording` any; visibility public only if all public.
⚠ `rideDateRange` lives in `ride_trip.dart` — do NOT define another `rideDateRange` in `ride_card.dart` (ambiguous import); import/re-export it.

Operations (each captures the undo map BEFORE the call):
```dart
RideTripPlan rideTripMergePlan(List<RideListItem> selected, String? name); // key = oldest selected explicit trip, else oldest ride id; empty name → null (default name)
RideTripPlan rideTripSplitPlan(RideTrip t);        // every member → (own id, null)  (also dissolves an implicit rental group)
RideTripPlan rideTripRenamePlan(RideTrip t, String name);
RideTripPlan rideTripAddPlan(RideTrip t, UserRide ride);  // implicit group: all members get the explicit key
RideTripPlan rideTripRemovePlan(UserRide ride);    // → (own id, null)
RideTripPlan rideTripUndoPlan(RideTripUndo undo);  // "Zpět"
Future<RideTripOp> rideTripApply(WidgetRef ref, RideTripPlan plan, {Iterable<String?> bookingIds}); // set_user_rides_trip + invalidate myRidesProvider (+ bookingRidesProvider(ids))
Future<RideTripOpResult> rideTripSetVisibility(WidgetRef ref, RideTrip t, bool public); // per member update_user_ride
Future<RideTripOpResult> rideTripDeleteAll(WidgetRef ref, RideTrip t); // discardCurrent() for the recording member, then delete each
String? rideTripResultKey(RideTripOpResult r);    // ok → null; partial → rpTripPartial; unavailable (old server) → rpTripUnavailable; failed (offline/error) → rpTripFailed
```
Typical merge flow: `final op = await rideTripApply(ref, rideTripMergePlan(sel, name), bookingIds: …); if (op.ok) snackbar(rpMergeDone, action rpUndo → rideTripApply(ref, rideTripUndoPlan(op.undo))) else snackbar(tr(op.messageKey!))`.

## 5. Server capability & fallback (what the UI can rely on)

- New server: `start_user_trip` (one ride per trip/rental, never split, stages, `now` → clock offset), `set_user_rides_trip`.
- Old server (SQL not deployed): `start_user_trip` → `PGRST202/42883/42703/404` = `missing` → `start_user_ride` (as PR #2208). Pause, auto-pause and markers still work locally (nothing uploaded while paused). A night can still be split by the old 3 h cron — the recorder then continues with a NEW ride and sets `notice = rpTripContinuedNewOld` (own) — never a silent stop. Rows lack `pause_aware` → `serverV2 == false` → `rideTripsAvailable` false (hide merge); a merge attempt returns `unavailable`.
- Offline is NEVER treated as an old server (retry like today). Probe (`user_rides.pause_aware`) at most once per 30 min on app resume; when the server gets upgraded mid-trip the legacy ride is adopted (`start_user_trip`, log `caps/upgrade`).
- Flag `ride_autopause` (missing row = ON; `conditions` stop_min/walk_min/resume_kmh/home_h/long_h) refreshed at start/resume/app resume (≤ 1×/30 min); switching it off mid-trip releases held points / ends the auto-pause.

## 6. i18n keys the LOGIC uses (UI agent must add them; missing key ⇒ logic falls back silently)

⚠ ext numbers: `translations_ext_46_booking_prefill.dart` (both trees) and `translations_ext_59_v2_late_info.dart` (Android) are TAKEN by other workflows → use **ext_47** (`translations_ext_47_rides_pause_a..d`, both trees; free 47–49) for shared `rp*` keys and **ext_60** for v2 keys. Re-check before creating.

| Key | Placeholders | Used by |
|---|---|---|
| `rpNotifTitle`, `rpNotifDefault` | — | static FGS notification (fallback `rideNotifTitle`/`rideNotifText`) |
| `rpNotifRidingTitle`, `rpNotifRiding` | `{km}`, `{time}` | Android notification while riding (≤ 1×/5 min) |
| `rpNotifArmedTitle`, `rpNotifArmed` | — | armed |
| `rpNotifPausedTitle`, `rpNotifPaused` | `{time}` | auto-paused |
| `rpNotifIdleTitle`, `rpNotifIdleText` | — | home/long guard (`notifyIdle`, auto-cancel) |
| `rpTripContinuedNew`, `rpTripContinuedNewOld` | — | notice (own trip continued as a new ride, new/old server) |
| `rpOwnSavedForRental` | `{date}` | notice (own trip saved because a rental was picked up) |
| `rpDaysOne/Few/Many`, `rpRidesOne/Few/Many` | `{n}` | `rideDaysLabel`, `rideRidesLabel` |
| `rpTripRental` / `rpTripDefault` | `{moto}` / `{dates}` | `rideTripDefaultName` |
| `rpTripPartial`, `rpTripUnavailable`, `rpTripFailed` | — | `rideTripResultKey` |

## 7. Diagnostics (`app_debug_logs`, category `ride`) — labels for Velín `rideDiag.js` (T5)

New: `phase {from,to,reason,battery?}`, `pause` (detail stop|walk|silence|manual; `{reason,since,m,held}`), `resume` (detail auto|manual; `{mode,from,pause_sec,m,preroll,flagged,kill_gap?}`), `tail_restore {n,m}`, `home_pause {since,h}`, `long_pause {since,h}`, `trip_continue {old,reason,ride}`, `caps {trips}` (detail `upgrade` when a legacy ride was adopted), `clock_offset {sec}`, `notif_failed`, `own_saved_for_rental {kept,booking}`, `flag {on,cond}`, `ride_discard {ride,phase}`. Extended: `ride_start` (+`proto`), `server_start_failed` (detail offline|error|notAuthenticated|booking_inactive), `ride_closed_by_server` (+`result`, `booking_ended`), `ride_stop` (+`phase`), `stream_attach`/`fix_gap` (+`phase`).

## 8. Android native (`cz.motogo24/ride`)

`notify {title,text}` → bool (re-posts geolocator FGS notification id 75415, channel `geolocator_channel_01`, only while `GeolocatorLocationService` runs in foreground, SDK ≥ 26); `notifyIdle {title,text}` (id 75416, auto-cancel, opens app); `cancelIdle`; `battery` → `{pct, charging}`; `keepAlive(false)` additionally cancels 75415 when the service is not running. Not compiled here (no Android SDK) — review-only.

## 9. Behaviour summary (for owner texts)

- Start (manual or rental): armed — P0 sent at once (Velín sees position), recording starts at departure (2 Doppler readings ≥ 20 km/h ≥ 100 m from the bike, or ≥ 300 m in 60 s without Doppler, or slow start median ≥ 12 km/h over 60 s ≥ 300 m away).
- While riding, ≤ 12 km/h holds points: stationary 5 min (radius 40–100 m) → pause "stop"; walking 3 min (Doppler median 2–8 km/h, path ≥ 50 m) → pause "walk" (walking never uploaded); slow ride (2 min, ≥ 300 m, Doppler median > 8) → points released; 10 min undecided → pause. Silence > 3 min after slow riding → stop; tunnel (last Doppler ≥ 30) never times out.
- Resume: pre-roll from the first ≥ 8 km/h fix; slow crawl before a walk-pause is restored to the track; first point after ≥ 60 s pause carries `kmh = −1` (server: pause, no km, no "na cestě").
- Guards (own trips only): paused ≥ 3 h within 500 m of the trip start after ≥ 10 km → GPS off (`home`); paused ≥ 20 h anywhere → GPS off (`long`); both ask "Pokračovat v cestě / Ukončit a uložit".
- Manual pause: GPS off immediately, survives app kill; resume only by tap.

## 10. Tests (Android `test/rides/`; iOS = same files run in `scratchpad/rides/ios_copy/logic`)

`ride_pause_engine_test.dart` (D1–D17 + traffic light, jam, fuel 4/6 min, tunnel, GPS jumps, flag switch, flag thresholds — 24), `ride_motion_test.dart` (7), `ride_live_stats_test.dart` (parity with `fixtures/stats_vectors.json` V1–V10 + plurals, stages, formatting), `ride_session_test.dart`, `ride_cache_keys_test.dart` (source check — never run `CacheCleanupService.run()` in tests: it wipes the system temp dir), `ride_server_api_test.dart`, `ride_point_test.dart`, `ride_trip_test.dart` (10), `ride_recorder_test.dart` (fake server + FakeGeo: 7-day own trip = 1 ride / 6 pauses / 7 markers / 0 continuations, rental `booking_ended` → stop no new ride, old server fallback + continuation notice, offline ≠ fallback, manual pause survives restart without re-attach + resume marker, ensureRecording no-op while paused, discardCurrent + gone, manual start on a server-closed rental → own ride, own trip paused + rental picked up → own saved + rental recorded + notice, server upgrade adoption, Android notification per phase). `fixtures/stats_vectors.json` is a T2 stub computed from SPEC §3.7 — T1 may replace it with SQL-computed values (same format).
Results: Android full `flutter test` → 5117 passed, 0 failed (ride tests incl. 11 recorder integration tests); iOS copy `test/rides + ride_location_test` → 91 passed. Analyze: Android 147 / 0 errors, iOS 143 / 0 errors (baselines).

## 11. Deliberate deviations from SPEC §6 (robustness, all covered by tests)

1. `isSlow` without Doppler uses USABLE fixes (acc ≤ 50 m), not only good ones — indoor phones without speed would otherwise upload drift as riding.
2. Slow-ride release uses the Doppler median when any Doppler exists; path/time only without Doppler (a single GPS jump inflated path/time and released held points at a red light).
3. "Stationary" tolerates max(1, 10 %) good fixes outside `rStill` (single GPS jump no longer delays the 5-min stop pause to the 10-min timeout).
4. Resume rule (b) ignores fixes whose Doppler says < 12 km/h and requires derived speed < 250 km/h (a stationary multipath jump must not resume).
5. The cached-fix guard applies after EVERY (re)attach (first fix older than attach − 30 s), not only before the first fix.
6. Manual start attributed to an active rental that the server already closed (`booking_inactive`) falls back to an own ride instead of failing.
7. `onAppResumed` in `manualPaused` additionally runs the throttled flag refresh / server probe (no GPS attach).
8. No-fix re-attach (`_tick`, foreground) is skipped while auto-paused with an anchor (a parked bike sends no fixes — not a dead stream).
