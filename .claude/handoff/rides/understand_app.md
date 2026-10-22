# understand:app — ride-recording client (both trees), stats, nonsense cases, geolocator 14 vs 10

Read-only map, 2026-10-22, branch `claude/moto-go-mobile-conversion-gqg5qo` @ 0bfabd41 (contains PR #2208 = d166e684 + 04f8d090).
A = `Motogo-app-main/motogo-app-flutter` (Android, 4.2.0+117), I = `Motogo-app-main/motogo-app-flutter-ios` (iOS, 4.1.3+116).

## 0. Parity / file facts

| file (lib/features/routes/…) | A vs I | size | note |
|---|---|---|---|
| ride_recorder.dart | IDENTICAL | 30 KB (~7.5k tok, already over 5k rule) | state machine — put new logic in NEW files |
| ride_location.dart | IDENTICAL | 9 KB | settings, `ridePointFromFix`, `RideKeepAlive`, `RideForeignStreams`, `rideLog` |
| ride_recorder_watcher.dart | IDENTICAL | 5 KB | rental auto start/stop + lifecycle |
| ride_provider.dart | IDENTICAL | 8.6 KB | RPC wrappers |
| ride_model.dart | IDENTICAL | 12 KB | `UserRide`, `_splitOnGaps`, getters |
| ride_start_feedback.dart, ride_booking_section.dart, route_nav_status.dart, active_ride_provider.dart, my_experiences_provider.dart, route_nav_loop.dart | IDENTICAL | | active_ride_provider = NAVIGATION progress (not GPS recording) |
| ride_card.dart, ride_detail_screen.dart (27 KB), ride_share.dart, ride_point_sheet.dart, my_experiences_screen.dart (45 KB) | DIFF = only v2 seams (`MgV2.on` → *V2 views) | | iOS copies have no v2 imports |
| ride_map.dart, route_navigation_screen.dart | DIFF = userAgentPackageName (+ v2 nav skin in A) | | |
| ride_actions.dart | ANDROID ONLY (`toggleManualRide`, v2 helper per CLAUDE.md rule 6) | | iOS has the same body as `_MyExperiencesScreenState._toggleManualRide` (my_experiences_screen.dart:634) |
| community_submit.dart | own `_toggleManualRide` (both trees) | | "Přidat" menu: start/stop manual ride |

- Watcher mounted in both `lib/main.dart` (A:482, I:458) inside the app shell.
- `test/ride_location_test.dart` exists only in A (8 tests). I has NO `test/` dir (tests must be copied into the rsync copy).
- `core/cache_cleanup_service.dart` (identical in both trees) runs `CacheCleanupService.run()` on EVERY `paused`/`detached` lifecycle (main.dart:309-315) and deletes every SharedPreferences key not in `_preserveKeys`. Recorder keys preserved today: `mg_ride_autorecord`, `mg_ride_rec_id`, `mg_ride_rec_buf`, `mg_ride_rec_manual` (+ `mg_active_ride`, `mg_ride_history`). **Any new recorder pref (pause state, trip id, local stats, server-capability flag) MUST be added to `_preserveKeys` in BOTH trees, otherwise it is wiped the first time the app goes to background.**
- i18n: used ext numbers A = 1–45, 50–58 (58 = `ext_58_v2_fix_a/b`, taken), I = 1–45. Free in both: 46–49, 59+. Shared (old-UI) ride keys → e.g. `translations_ext_59_rides*.dart` in both trees; v2-only → `ext_59_..._v2` / 60 in A only. Existing ride keys live in `translations_ext_18_rides.dart` (`rideNotifTitle/Text`, `rideStat*`, `rideGapNotice`, `rideManual*`) and v2 in `ext_56/57`.
- Released 4.1.3 (commit 70a94933, 2026-10-10, both stores) is BEFORE PR #2208 → its recorder is the OLD one (see §9).

## 1. ride_recorder.dart — state machine

State `RideRecorderState{enabled, recording, rideId, bookingId, points, manual, gpsLost}` (no paused field, no live km/time). `RideStartResult{ok, notSignedIn, locationOff, noPermission, imprecise, failed}`.

Prefs: `mg_ride_autorecord` (bool, default true), `mg_ride_rec_id`, `mg_ride_rec_buf` (JSON list of points), `mg_ride_rec_manual`.
Constants: flush every 20 points or `Timer.periodic(90 s)`; stop retry 2 min; stale buffer 1 h; re-attach if no fix > 2 min on resume; log `fix_gap` if > 3 min between fixes.

Lifecycle:
1. `_restore()` (ctor): loads enabled/id/manual/buffer. **Only MANUAL rides are re-attached here** (`_attachStream('restore')`, recording=true, `_needsServerRide` stays false → points go to the stored id). Auto rides wait for the watcher. `points` is NOT restored (starts at 0).
2. `ensureRecording(bookingId)` (watcher, auto) → `_start(bookingId)`; `startManualResult()` (UI) → permission checks via `GpsService.status()` → `_start(null, manual:true)`.
3. `_start`: iOS precise-accuracy request (`requestTemporaryFullAccuracy(purposeKey:'rideTracking')`); resets `_lastKept/_sentFirst/_attaches/_noFixRetries/_continuation`; `_needsServerRide=true`; **attaches the stream FIRST (foreground, needed for Android 12+ FGS)**, recording=true, then `_ensureServerRide()`. Manual start failing server-side → detach, drop this attempt's points, recording=false, `failed`.
4. `_createServerRideOnce`: `startUserRide(bookingId)` WITHOUT lat/lng. If `_continuation && !resumed && booking_id==null` → `finishUserRide` + `_forgetRide()` (rental over). If not resumed → drop buffer points older than now−1 h, recompute local max. Store id/manual, `_needsServerRide=false`, log `ride_start`, `flush()`.
5. `_attachStream(reason)`: cancel old sub, `_ownStream = !RideForeignStreams.any || (hadSub && _ownStream)`, `Geolocator.getPositionStream(rideLocationSettings(lang))`, restart 90 s timer, `_watchService()` (service status stream → gpsLost / re-attach `service_on`), `RideKeepAlive.set(_ownStream)`, log `stream_attach`. Reasons: start, restore, service_on, foreign_closed, resume_no_stream/resume_error/resume_no_fix, no_fix.
6. `_detachStream()`: cancel sub + timer + service sub, `RideKeepAlive.set(false)`.
7. `_onPosition`: clears gpsLost; logs `fix_gap`; `ridePointFromFix(pos, _lastKept, now, notBefore: attachedAt−30 s)`; append to buffer, local max, `points+1`, persist buffer; first point after server confirm or ≥20 buffered → `flush()`. **Every accepted fix becomes a point — there is no notion of stationary/walking/paused.**
8. `onAppResumed()` (watcher): unless stopping, re-attach if no sub / stream error / no fix for 2 min (so a stationary phone gets re-attached on every app resume); retry server ride; flush.
9. `_tick()` (90 s): retry server ride; in FOREGROUND only, up to 2× re-attach if no fix 60 s after attach (`no_fix`); flush.
10. `flush()` single-flight (`_flushing` future); skipped while stopping (unless offline-created ride). `_flushOnce`: `appendRideTrack(id, batch, maxSpeedKmh: local max)` →
    - `retry` → keep points;
    - `finished` (`ride_finished`/`ride_not_found`) → log `ride_closed_by_server`; **AUTO ride with bookingId: `_continuation=true`, `_needsServerRide=true`, `_ensureServerRide()` → NEW server ride (the split)**; **MANUAL: `_forgetRide(keepBuffer:true)` → recording silently stops (stream detached, UI back to idle, no message)**;
    - ok → remove sent count from buffer, persist.
11. `stop()`: signed out → forget everything. Detach stream; if offline-created ride → create it first (fail → recording=false, id kept, return null); await running flush; `finishUserRide(id, points: buffer)` → closed? kept = !discarded. Not closed → id kept, recording=false, `_lastStopFail`, return null (watcher retries via `canRetryStop` every 2 min). Closed → log `ride_stop`, clear state/buffer/prefs, invalidate `myRidesProvider`. Return true(kept)/false(<1 km discarded)/null(not closed).
12. `setEnabled(false)` (auto switch) → `stop()` unless manual. This is today the ONLY way to end/stop an auto (rental) ride from the UI.
13. `_forgetRide({keepBuffer})`: detach, clear, recording=false, points=0, clearRide, remove prefs.

Pause-design gotchas found in the code:
- Watcher calls `ensureRecording()` on every build while a rental is active and `state.recording==false` → a pause implemented as `recording=false` would be undone immediately. Pause needs its own flag; the watcher stop branch (`!manual && (recording || rideId!=null)` when no active booking) must still finalize a paused rental ride.
- `onAppResumed` and `_tick(no_fix)` re-attach a stream that has had no fix for 1–2 min — exactly the stationary/paused situation. Harmless in foreground, but pause logic must not treat a re-attach as "resumed riding", and `notBefore`/`_lastKept` reset on attach.
- `_lastKept` is reset only on start/forget/stop, kept across re-attach (good: 20 m filter continuity).
- `points` counter: reset to 0 by restore, not reset on server-side continuation, not decreased when stale buffer points are dropped.

## 2. ride_location.dart

- `rideLocationSettings(lang)`:
  - Android: `AndroidSettings(accuracy: high → PRIORITY_HIGH_ACCURACY, distanceFilter: 20, intervalDuration: 5 s (both setIntervalMillis and setMinUpdateIntervalMillis), foregroundNotificationConfig(title 'rideNotifTitle', text 'rideNotifText', channel 'MotoGo24', enableWakeLock: true (PARTIAL_WAKE_LOCK all the time), setOngoing: true))`.
  - iOS: `AppleSettings(accuracy: high → kCLLocationAccuracyNearestTenMeters, distanceFilter: 20, activityType: automotiveNavigation, allowBackgroundLocationUpdates: true, pauseLocationUpdatesAutomatically: false, showBackgroundLocationIndicator: true)`.
- `ridePointFromFix(pos, last, {now, notBefore})` → `[lat5, lng5, ts(epoch s, ROUNDED to whole second), kmh(1 dec, pos.speed*3.6), alt(1 dec, only if finite && != 0)]` or null:
  - drop if accuracy > 500 m, or accuracy > 50 m AND kmh < 3;
  - kmh > 300 → 0 (point kept);
  - fix age < −2 min or > 30 days → ts = receipt time; age > 6 h → drop (cache); first point older than notBefore → drop;
  - with `last`: drop if ts < last.ts (out of order) or < 20 m from last (own distance filter, because the stream may be the navigation's 4 m stream).
  - NO speed sanity vs previous point, NO jump filter, NO walking filter.
- `rideDistanceM` haversine (same as server).
- `RideKeepAlive.set(on)` → MethodChannel `cz.motogo24/ride` `keepAlive` (Android only); handles `reattached` → `Stripe.instance.markNeedsSettings()` + log `engine_reattached`.
- `RideForeignStreams` counter (navigation `opened()`/`closed()`; `onAllClosed` → recorder re-attaches if it was riding the nav stream).
- `rideLog(action, detail, data)` → `app_debug_logs` category `ride` (Velín `rideDiag.js` maps actions: app lifecycle, stream_attach/error/done, fix_gap, ride_start, server_start_failed, ride_closed_by_server, ride_continue_no_booking, ride_stop, engine_reattached, keep_alive_failed — new actions (pause/resume/auto-pause) need labels there).

## 3. ride_recorder_watcher.dart (rental auto start/stop)

- Lifecycle observer: paused/inactive → `flush()`; resumed → `onAppResumed()`.
- `_activeBookingId`: first reservation with `inRentalTerm`, `returnedAt == null`, and (`issuedAt != null` OR status active and now ≥ planned pickup time (`pickup_time`, legacy 00:01 → 23:59)).
- build (only when `reservationsProvider.hasValue`, realtime-backed) → postFrame: booking → `ensureRecording(id)`; manual ride with id but not recording (failed stop) → `stop()` retry; auto ride/id but no active booking → `stop()` (rental ended).
- Runs only when Flutter builds frames (app visible). With screen off / window closed (parked engine) NO watcher decisions happen — everything that must work overnight has to live in the notifier (stream callbacks + timer), not in widgets/post-frame callbacks.

## 4. ride_provider.dart (RPC wrappers, all catch → null/retry)

- `myRidesProvider` = `get_my_rides()` (server default limit 100, max 300) — no auto refresh during recording (invalidated only on stop/forget/manual refresh).
- `bookingRidesProvider(id)` = `get_booking_rides(p_booking_id)`.
- `startUserRide({bookingId, lat, lng})` → `start_user_ride(p_booking_id, p_lat, p_lng)`; reads `success, id, resumed, booking_id`.
- `appendRideTrack(id, points, {maxSpeedKmh})` → `append_ride_track(p_ride_id, p_points, p_max_speed_kmh)`; empty list → returns ok WITHOUT calling; `error in (ride_finished, ride_not_found)` → finished; else retry.
- `finishUserRide(id, {points, name})` → `finish_user_ride(p_ride_id, p_points, p_name)`; `ride_not_found` → treated as closed+discarded.
- `createManualRide`, `updateUserRide(p_id,p_name,p_description,p_visibility,p_cover_image)`, `deleteUserRide`, `saveRidePoint`, `deleteRidePoint`, `uploadRidePhotos` (media/rides/<uid>/…).
- Missing RPC (new name on old server) currently surfaces only as a caught exception → null/false. New wrappers must distinguish PostgREST `PGRST202` (function not in schema cache, HTTP 404) from offline to fall back gracefully.

## 5. Android native (A only)

- `MainActivity.kt`: `provideFlutterEngine` → `RideEngineKeeper.obtain` (reuses parked engine, then `onStart` invokes `reattached`); `createFlutterFragment` → `KeepEngineFlutterFragment` (`shouldDestroyEngineWithHost=false`); `onDestroy` → `RideEngineKeeper.release(engine)`; `configureFlutterEngine` → `register` channel.
- `RideEngineKeeper.release`: parks the engine only if Dart said keepAlive AND geolocator's `GeolocatorLocationService` is running in foreground (checked via `getRunningServices`). keepAlive=false while parked → destroy after 15 s.
- ⇒ If a pause DETACHES the stream: FGS stops, `RideKeepAlive.set(false)` → a window closed during the pause destroys the engine → Dart (timers, auto-resume) dies.
- Manifest: FINE/COARSE, FOREGROUND_SERVICE(+_LOCATION), POST_NOTIFICATIONS, WAKE_LOCK; NO ACCESS_BACKGROUND_LOCATION (deliberate).
- geolocator FGS notification: id 75415, channel `geolocator_channel_01` (display name from config 'MotoGo24'); no action buttons possible via plugin.

## 6. iOS Info.plist (I)

`UIBackgroundModes: [remote-notification, location]`; `NSLocationWhenInUseUsageDescription` (mentions recording while locked); `NSLocationTemporaryUsageDescriptionDictionary.rideTracking`; `NSLocationAlwaysAndWhenInUseUsageDescription` (SOS only — Always is never requested). No `NSMotionUsageDescription`, no motion/activity package → walking/riding detection must be GPS-only (speed, displacement, accuracy). Same holds for Android (no activity-recognition package/permission; no new packages allowed).

## 7. UI — where recording is controlled / shown

Old UI (both trees):
- `my_experiences_screen.dart` `_ridesSection` (A:531, I:~484): "🛰️ Záznam jízd" card with "⏺ Nahrávám" chip + auto switch (`setEnabled`); `RideGpsLostBanner`; `_manualRideCard` (start/stop manual, HIDDEN during auto ride); list of `RideCard`.
- `community_submit.dart` `showCommunityAddMenu` ("Přidat" sheet): start/stop manual (hidden during auto); also used by v2 with `CommunityMenuRowV2`.
- `ride_start_feedback.dart`: `showRideStartResult` snackbars; `RideGpsLostBanner`.
- Old navigation screen: NO recording indicator/control at all.
- Android ongoing notification text = only out-of-app surface.
v2 (A only):
- `home/v2/home_record_row_v2.dart`: start manual / tap→recorder when live / confirm-stop.
- `routes/v2/record_dock_v2.dart` `TrasyRecordDockV2` (+ `trasyConfirmStopRide`): live bar (Stop only if manual), idle CTA, selection mode disc; used in routes_screen, routes_list_parts_v2, moje_view_v2, all_pois_screen.
- `routes/v2/rides/recorder_screen_v2.dart` + `recorder_parts_v2.dart`: full screen; start (MgCta) / stop (manual) / back (auto); `RecorderLiveCardV2` chips: mode, "N bodů" (`rec.points`), GPS ok/lost; auto switch.
- `routes/v2/route_nav_skin_v2.dart` `NavRecChipV2`: "● REC" display only.
- `routes/v2/rides/moje_tabs_v2.dart` record row (ping when recording).
- `home/v2/home_ticket_checklist.dart` (NOT ours) shows auto-recording status; `home/v2/home_experiences_band_v2.dart` (NOT ours) sums km.
- No control anywhere can PAUSE; a rental (auto) ride can be ended only via the auto switch.

## 8. Every stat: where computed, formula, where shown

### 8.1 Server (source of truth; app only displays)
- `_ride_stats(segment)` (20261015b): for consecutive points, d = haversine; dt = ts−prev_ts (null if missing); `bad_time` = dt<0 or ≥86400 → segment ignored entirely; v = d/dt; **GAP** = dt>180 s AND d>0.3 km → only `gap_sec += dt` (no km, no climb); else: km += d unless jump (v ≥ 300 or dt=0 & d ≥ 0.5 km); time: v ≥ 3 km/h → `moving_sec`, else `idle_sec`; **km is added for idle segments too**; max = max(fix kmh < 300, v for dt ≤ 60 s & v < 300); climb += Δalt if Δalt ≥ 5 m (consecutive points, no hysteresis).
- `append_ride_track`: drops points with ts < started_at − 1 h; segment = last stored point + batch; accumulates km/moving/idle/gap/climb; `avg = km / moving` (cap 200, null if moving=0); `duration_min = last_fix − started_at` (phone fix time − server start time); `last_fix_at` = last point ts (sanity: > now+1 h or < now−30 d → now()); `max = greatest(stored, client p_max, segment max, avg)`; track capped to 4000 points (`_ride_track_cap`, keeps gap edges).
- `_ride_finalize(end)`: no-op if already finished; km fallback from whole track only for time-less tracks; **km < 1 → DELETE**; `dur = max(1, end−start, ceil((move+idle+gap)/60))`; `idle = dur*60 − move − gap` if larger (everything unaccounted becomes STÁNÍ); avg = km/move or km/(dur−gap); max ≥ avg; name fallback `DD.MM.YYYY`; inserts start/end points.
- `finish_user_ride`: end = now(), capped at `bookings.returned_at` (if earlier); `close_stale_user_rides` (cron */15): closes recording rides with greatest(last_fix, started, updated_at) older than 3 h, OR started > 36 h ago, OR booking ended/completed/cancelled — end = last activity; `start_user_ride` closes a stale (>3 h) recording ride and creates a new one; manual start without booking id gets **today's reserved/active booking assigned by date**.
- `_ride_json`: distance rounded to 1 dec; all fields above.

### 8.2 App model (`ride_model.dart`, both trees)
- `movingMin/idleMin/gapMin` = round(sec/60); `totalMin = durationMin ?? round((move+idle+gap)/60)`; `avgOverallKmh = km / ((totalMin − gapMin)/60)` (fallback only when server avg null; null if ≥ 200); `hasGaps = gapSec>0 || segments>1`; `photoCount`, `stops`; `longestSegment` (for sharing).
- `_splitOnGaps(track, times)`: gap if dt>180 && **dt<86400** && km>0.3 (server treats dt ≥ 86400 as bad time instead → a >24 h stop is drawn as a SOLID line in the app).

### 8.3 Display
- Old `RideCard` (list, booking section): date(start) · km · total (`totalMin>0`) · moving · avg(`avgSpeedKmh ?? avgOverallKmh`) · stops · photos · moto.
- Old `RideDetailScreen._statsCard`: km, total, moving, idle, avg, max, climb, stops, photos; if gap: gap time, `track.length` ("body" — capped 4000), breaks = segments with gapBefore; amber `rideGapNotice`; "start → end" datetimes; moto.
- `ride_share.dart` text: km, `durationMin` (TOTAL incl. stops), date.
- `ride_map.dart`: segments solid, gaps dotted grey.
- v2 `RideCardV2`, `RideDetailPartsV2` stats grid (same set as old), `ride_track_sketch_v2` (segments), `moje_summary_v2`: total km = Σ distance over `get_my_rides` (≤100 rides), split MotoGo (bookingId≠null) vs private, ride count pill; `home_experiences_band_v2` (not ours): Σ km and counts.
- Live during recording: NO km/time/speed anywhere. v2 recorder card shows `rec.points`; everything else is the server row of the recording ride as of the last `myRidesProvider` load (stale).
- Formatting: `rideDuration` only "X h Y min" (7 days → "167 h 20 min"); `rideDate` only the start date; `rideKm` 1 dec < 10 km; `rideSpeed` 0 dec, ≤0 → "—".
- Velín (not app, for reference): TrasyJizdy list + totals (Σkm, Σmoving), TrasyJizdaModal stats grid, `isStuck` = recording && last fix > 3 h (would flag every paused overnight ride), BookingLiveMap last-fix age, `rideTrack.js` STILL_KM split.

## 9. Old client 4.1.3 (must keep working against new SQL)
- Start: `start_user_ride(p_booking_id, p_lat, p_lng)` with last-known position if fresh (server stamps first point with server now()); stream attached AFTER server start.
- Points `[lat,lng,ts,kmh,alt]` with ts = RECEIPT time (`DateTime.now()`), so batches delivered after wake share one second (server dt=0 rules exist for that).
- Append errors `ride_finished`/`ride_not_found` → `_forgetRide(keepBuffer)`; auto ride restarted by the watcher only when app visible (no in-process continuation). Uses only `success,id,resumed` from start and `success,discarded,distance_km,error` from finish.
- Never pauses; relies on cron 3 h / 36 h closing to avoid zombie rides (`uq_user_rides_recording`).

## 10. Nonsense catalogue (today, current server + current app)

1. **Walking counted as riding** — no walking filter; 4–6 km/h ≥ 3 km/h threshold → MOVING. 40 min town walk ≈ +3 km "ujeto", +40 min "čas jízdy", avg falls (e.g. 200 km/4 h=50 → 203 km/4 h40 = 43 km/h), zigzag on map, climb from stairs/alt noise. Also walking bike→restaurant→bike at every lunch/fuel stop.
2. **Parked drift adds km** — indoor fixes with accuracy ≤ 50 m that jump > 20 m pass the filter; server adds km in IDLE segments (only gaps/jumps excluded) → phantom km and phantom climb (lunch, hotel night). Each drift fix also bumps `last_fix_at/updated_at` → keeps the ride "alive" for the 3 h cron.
3. **Elevation overcount** — consecutive-point Δalt ≥ 5 m summed without hysteresis; GPS altitude noise ±5–15 m (Android ellipsoidal, fused) → nastoupáno typically 1.5–3× real; drift/walking points add more.
4. **Max speed artefacts** — server max includes v computed from segments with dt ≤ 60 s; ts rounded to whole seconds and coords to 5 decimals → on iOS (fix ~1 s, filter 20 m) a 2 s segment can round to 1 s → v doubled (50 km/h road → "100 km/h"); GPS jumps < 300 km/h accepted (400 m in 10 s = 144 km/h + 0.8 km); finalize raises max to ≥ avg (nonsense avg → nonsense max).
5. **Avg speed** = km/moving: walking lowers it, idle drift km raises it; with moving=0 falls back to km/(total−gap).
6. **Day ride with lunch + fuel**: fuel 5 min → idle ok; lunch 1 h → idle ok but walking + drift as above; **lunch/stop > 3 h without fixes → cron closes ride** → rental: split into 2 rides; manual: after lunch first flush gets `ride_finished` → **recording silently stops**, rest of day lost, UI just flips to idle.
7. **Overnight stop**: (a) no fixes → cron closes at last fix after 3 h → rental: morning = new ride (split per night); manual: morning recording silently dies after first flush (day 2+ lost) and the morning points stay in the buffer (may leak into the next manual ride if within 1 h). (b) drift keeps the ride alive → night = 10 h "čas stání" + phantom km/climb; then **36 h hard cap closes it mid-ride on day 2** (manual stops silently; rental splits mid-ride). (c) If rider parked > 300 m from where the phone spent the night (no fixes inside), morning segment = GAP → night shown as "📵 bez signálu 10 h" + "přerušení" + notice blaming weak signal/old app → wrong explanation. (d) Android keeps HIGH_ACCURACY GPS + partial wake lock + "MotoGo24 zaznamenává jízdu" notification all night; iOS GPS + blue indicator all night (battery).
8. **7-day trip**: never one record. Rental: ≥ 1 ride per night + per >3 h stop + every 36 h (each named by date). Manual: dies every night (must be restarted by hand daily) or every 36 h. No trip grouping, no merge; `rideDuration` would show "167 h"; only start date shown; ride count in summaries inflated; `get_my_rides` limit 100 → Σ km in summaries truncates sooner.
9. **3-day rental**: same splitting (3–6 rides); booking section lists cards without a rental total. After return: car km to home can enter until cron (≤15 min) + flush (≤90 s) closes it (close_stale ends at last fix, not at returned_at; finish caps only the END TIME at returned_at, not km).
10. **Manual ride on a rental day** gets booking_id/moto_name by server date-matching (`p_booking_id null` + reserved/active + today in range, even before pickup) → own-bike ride labelled with the rental bike, counted as "MotoGo km", visible in Velín live map.
11. **App killed by OS overnight** (Android OEM killer, iOS memory pressure; iOS never relaunches a When-In-Use app): nothing recorded until the rider opens the app. Then rental → old ride closed (stale) + new ride (split, km of the unrecorded ride missing); manual → `_restore` re-attaches to old id → first flush `ride_finished` (cron closed it) → silently stops. If < 3 h: resumes with a GAP (km not counted).
12. **GPS jumps**: only accuracy-based client filter (>500 m always, >50 m when slow); fast-looking jumps with good accuracy pass; server only rejects ≥300 km/h or dt=0 & ≥500 m.
13. **Clock skew**: phone clock behind > 1 h → server drops all points (`ts < started_at − 1 h`) → ride < 1 km → "příliš krátká" after a real ride. Phone clock ahead > 6 h while fixes carry true GPS time → client drops every fix as "stale cache" (silently, no gpsLost). Moderate skew shifts `duration_min` (= phone last fix − server start) and finalize pads the difference into idle. ts rounding ±1 s (see 4).
14. **Live/stale numbers**: v2 "N bodů" resets to 0 after app restart, keeps counting across server-split rides, includes stale points dropped later; list/detail of a recording ride show numbers from the last list load.
15. **Track points stat** = stored track length (capped 4000) — "4000 bodů" for a long trip.
16. **Split rule mismatch**: app `_splitOnGaps` ignores dt ≥ 86400 (draws solid line) whereas server ignores such segment entirely.

## 11. geolocator 14 (A) vs 10 (I) — runtime-change relevant API

Resolved: A = geolocator 14.1.1 / android 5.1.1+1 / apple 2.3.15 / platform_interface 4.4.0; I = geolocator 10.1.1 / android 4.6.2 / apple 2.3.14 / platform_interface 4.3.0.

- `geolocator.dart` public static API (getPositionStream, getServiceStatusStream, checkPermission, isLocationServiceEnabled, getLocationAccuracy, requestTemporaryFullAccuracy, getLastKnownPosition, getCurrentPosition, openAppSettings/openLocationSettings…) — IDENTICAL signatures.
- `AndroidSettings` — IDENTICAL fields: accuracy, distanceFilter, forceLocationManager, intervalDuration, timeLimit, foregroundNotificationConfig, useMSLAltitude. Android native 4.6.2 vs 5.1.1 differ only in FusedLocationClient/LocationMapper (vertical speed)/NMEA — irrelevant for the iOS-tree build.
- `ForegroundNotificationConfig` — IDENTICAL fields: notificationTitle, notificationText, notificationChannelName, notificationIcon(AndroidResource), enableWifiLock, enableWakeLock, setOngoing, color (5.x uses `toARGB32` internally only).
- `AppleSettings` — IDENTICAL (2.3.14 vs 2.3.15 differ only by CRLF/SPM flag): accuracy, distanceFilter, timeLimit, pauseLocationUpdatesAutomatically, activityType (ActivityType.automotiveNavigation/fitness/otherNavigation/other/airborne), showBackgroundLocationIndicator, allowBackgroundLocationUpdates.
- `Position` — 4.4.0 ADDS `verticalSpeed`, `verticalSpeedAccuracy`, `hasVerticalSpeed`, `hasVerticalSpeedAccuracy` → **must not be used in shared code**. Both have speed, speedAccuracy, hasSpeed, hasSpeedAccuracy, accuracy/hasAccuracy, heading, altitude(+Accuracy), isMocked, floor; constructor required params identical (tests portable).
- iOS accuracy mapping: lowest→3 km, low→1 km, medium→100 m, high→NearestTenMeters, best→Best, bestForNavigation→BestForNavigation; reduced auth → kCLLocationAccuracyReduced.
- **No version can change settings of a running stream.** Plugins cache ONE broadcast position stream per app (`_positionStream`); settings are applied only when it is created; while any other subscriber (navigation, 4 m, no FGS) holds it, re-listening just re-joins the old stream. Changing accuracy/distanceFilter/interval/notification text = cancel ALL subscribers + listen again.
- Android re-listen: `onCancel` → `stopLocationService` + `disableBackgroundMode` (stopForeground, wake lock released, notification removed); `onListen` → `startLocationService` + `enableBackgroundMode` → `startForeground`. From BACKGROUND this is not allowed on Android 12+ (FGS start restriction; plugin does not catch `ForegroundServiceStartNotAllowedException`), Android 11+ while-in-use rule denies location to an FGS started from background (we have no ACCESS_BACKGROUND_LOCATION), Android 14 requires FGS-type-location eligibility. ⇒ On Android the recording stream/FGS can only be (re)started while the app is visible; auto-pause/auto-resume while backgrounded must keep the ORIGINAL subscription alive (same HIGH_ACCURACY 5 s/20 m request + wake lock → no real GPS battery saving possible in background; only Dart/network work can be cut). Notification text cannot be updated via the plugin without re-listen (possible only natively by re-posting id 75415 on channel `geolocator_channel_01` from our MainActivity — hacky).
- iOS re-listen: same CLLocationManager; cancel → `stopUpdatingLocation`, listen → set desiredAccuracy/distanceFilter/activityType/pauses/allowsBackground/showsIndicator + `startUpdatingLocation`. With When-In-Use only, stopping updates in background ends the background location session (app becomes suspendable) and starting updates from background is not permitted/reliable → auto-pause in background must not stop or re-listen; reduced-power re-listen is only safe in foreground. `pauseLocationUpdatesAutomatically: true` would let iOS power down when stationary, but iOS will NOT auto-resume a When-In-Use app in background (resume needs the app in foreground) → would lose the next morning unless the rider opens the app.
- Background indicator: iOS `showBackgroundLocationIndicator` (blue pill, required for When-In-Use background); Android = the FGS notification.
- Timers: Android FGS + partial wake lock keep Dart timers running (also with parked engine). iOS: Dart runs in background only while the location session keeps the app awake; with a stationary phone and distanceFilter 20 m there are no callbacks — do pause/resume decisions on fix arrival and with timestamps (elapsed since last fix), not by precise timers.
- Testing: `GeolocatorPlatform.instance = FakeGeo()` where `FakeGeo extends GeolocatorPlatform` passes the token check in both versions (no extra package); `SharedPreferences.setMockInitialValues`. The notifier hard-depends on `MotoGoSupabase.currentUser` and top-level RPC functions → inject a server-API seam (or keep detection in a pure class) for unit tests with synthetic traces.

## 12. Implications for R1–R6 (facts, not decisions)
- Pause needs a new state field + persisted pref (+ `_preserveKeys` in both trees) and must survive restore (`_restore` re-attaches only manual rides; auto restored by watcher → `_start`).
- Manual pause (user in foreground) MAY detach the stream (resume is a foreground tap) — but then keepAlive=false and a closed window kills Dart; auto-pause MUST keep the subscription (Android FGS + iOS session) and just stop adding points/time.
- Stationary signal: with 20 m filter a still phone delivers no fixes ("no kept point for N min"); walking = sustained 3–8 km/h with small radius; riding = ≥ ~15–20 km/h or displacement ≥ ~300 m quickly. Traffic jams at walking pace are the false-positive risk; filtering retroactively (hold back slow points until classified) avoids losing data.
- Against the CURRENT server: cron closes after 3 h without `last_fix/updated_at` change and after 36 h total; an empty append does NOT bump `updated_at` (client doesn't even call it), a duplicate last point with a new ts does (adds idle). So without new SQL an overnight auto-pause cannot keep one ride open → fallback = today's split (continuation for rentals) plus, for manual rides, re-creating a ride instead of silently stopping.
- Server stats need pause awareness (paused time out of idle/total, no km across pause, night ≠ "bez signálu"), multi-day display (days/etapy), trip grouping/merge — server-side work; app must read new fields defensively (old `get_my_rides` lacks them).
