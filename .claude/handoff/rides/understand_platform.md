# Ride recording — platform research (understand:platform)

Date 2026-10-22. Scope: background GPS on Android 14/15 and iOS, what the
installed geolocator versions allow, how other apps handle pause and multi-day
trips, and concrete auto-pause/auto-resume thresholds. Source code facts were
checked in `~/.pub-cache` and in the repo. Web facts carry a citation number
(list at the end). Anything not documented is marked **[inferred]** or
**[estimate]**.

---

## 0. Shrnutí pro majitele (česky)

* **Pauza:** ruční pauza a automatická pauza se musí lišit.
  * **Automatická pauza** nechává GPS zapnuté. Jen tak appka pozná, že jsi
    zase vyjel, a záznam sama obnoví. Pozastavené body se neukládají.
  * **Ruční pauza** může GPS úplně vypnout (nulová spotřeba). Pak ale
    pokračuješ zase ručně, stejně jako u Stravy.
* **Rozpoznání pěšky / na motorce** je možné bez dalších balíčků. Stačí
  rychlost, kterou měří přímo GPS přijímač (Doppler):
  * Chůze je 4–6 km/h, nejvýš kolem 7 km/h.
  * Za jízdu se považuje 20 km/h a víc, a to ve dvou fixech po sobě.
  * Pauza přijde po 5 minutách stání, nebo po 3 minutách chůze po
    zastavení. Semafor ani kolona ji nespustí.
  * Došlápnuté metry od motorky se ze stopy odříznou.
* **Baterie:** ani Android, ani iOS (s balíčky, které máme) nedovolí
  v pozadí bezpečně přepnout GPS do úsporného režimu tak, aby se záznam
  sám probudil.
  * Přes noc proto zůstane GPS zapnuté. Odhad je 10–30 % baterie za noc,
    a když telefon nabíjíš, tak nic.
  * Úsporný noční režim by znamenal ráno appku otevřít. Nabízím ho jako
    volbu, ne jako výchozí chování.
* **Vícedenní cesta = jeden záznam.** Server dnes jízdu ukončí po 3 h bez
  bodu nebo po 36 h celkem. To se musí změnit, jinak se cesta rozdělí.
  Telefon totiž v noci schválně nic neposílá.
* **Konkurence:**
  * REVER ani Relive slučování jízd neumí.
  * REVER radí ukládat každý den zvlášť.
  * Kurviger umí sloučit omylem rozdělené záznamy.
  * Komoot dělí vícedenní trasu na etapy.
  * Slučování a „cesta s etapami“ by tak pro MotoGo24 byla výhoda.

---

## 1. What the app does today (facts from the code, both trees identical)

`lib/features/routes/ride_location.dart` and `ride_recorder.dart` are the
same file in both trees (`diff` is empty). Ride-relevant behaviour:

| Item | Value / behaviour |
|---|---|
| Stream | `Geolocator.getPositionStream(locationSettings: rideLocationSettings(lang))`. It is opened at start while the app is in the **foreground**, and re-attached only on `onAppResumed` (no fix for 2 min, error, or stream done), on `service_on`, and on `foreign_closed`. |
| Android settings | `AndroidSettings(accuracy: high, distanceFilter: 20, intervalDuration: 5 s, foregroundNotificationConfig(enableWakeLock: true, setOngoing: true, channel 'MotoGo24'))`. Result: geolocator's `GeolocatorLocationService` runs as an FGS of type `location` and holds a **PARTIAL_WAKE_LOCK with no timeout** for the whole recording. |
| iOS settings | `AppleSettings(accuracy: high, distanceFilter: 20, activityType: automotiveNavigation, allowBackgroundLocationUpdates: true, pauseLocationUpdatesAutomatically: false, showBackgroundLocationIndicator: true)`. Info.plist has `UIBackgroundModes: location` and when-in-use text, plus Always text (used for SOS). |
| Fix → point | `ridePointFromFix` drops: accuracy > 500 m always; accuracy > 50 m when speed < 3 km/h; stale/cached fixes; time going backwards; points < 20 m from the last kept point. Point format `[lat,lng,ts,kmh,alt?]`, where kmh is the Doppler speed (0 if missing). |
| Timers | `Timer.periodic(90 s)` handles flush, server-start retry, and the no-fix re-attach (foreground only). Flush also runs at 20 points and on lifecycle pause. |
| Engine keeper (PR #2208) | `RideKeepAlive.set(true)` → `RideEngineKeeper` parks the FlutterEngine when the window closes. It does so **only if geolocator's FGS is in foreground** (`getRunningServices`). If the stream is ever cancelled, `_detachStream` turns keep-alive off. |
| One stream per app | geolocator caches a single broadcast stream. Navigation (`route_navigation_screen.dart`, `LocationSettings(high, distanceFilter 4)`, no FGS) may own it. `RideForeignStreams` tracks this. |
| Server | `close_stale_user_rides` (cron every 15 min) closes a recording ride after **3 h without a fix**, **36 h total**, or when the rental ends. `start_user_ride` resumes only if the last fix is < 3 h old, otherwise it finalizes and creates a new ride. **This is exactly what splits multi-day trips.** `_ride_stats` uses: move ≥ 3 km/h; gap = dt > 180 s with displacement > 300 m; max speed from Doppler **and** from derived speed over dt ≤ 60 s; gain = sum of +Δalt ≥ 5 m. Track cap 4000 points (thinning keeps points around > 180 s time gaps). |

---

## 2. Platform behaviour

### 2.1 Android 14/15 (targetSdk 36) — location FGS started from the foreground

**Starting.** A location FGS needs a while-in-use permission. It must be
created or bound while the app has a visible activity. On Android 14+, a
background attempt throws `SecurityException`, even when a general
background-start exemption applies [A1][A2]. The only while-in-use exemptions
are system components, widgets, **a notification interaction**, a PendingIntent
from a visible app, and a few privileged roles [A1]. The app has no
`ACCESS_BACKGROUND_LOCATION`, so a location FGS **can never be created from the
background**. Today's code respects this: it attaches in the foreground and
re-attaches only from `onAppResumed`.

**How geolocator implements it** (geolocator_android 5.1.1+1, same in 4.6.2):

* `GeolocatorPlugin.onAttachedToEngine` binds `GeolocatorLocationService` with
  `BIND_AUTO_CREATE`. The service is bound, never started.
* `onListen` with `foregroundNotificationConfig` calls
  `startLocationService(...)`, then `enableBackgroundMode()`, which calls
  `startForeground(75415, notif)` and acquires the wakelock.
* `onCancel` calls `disposeListeners(true)`. When `listenerCount == 1` this runs
  `stopLocationService()` and `disableBackgroundMode()`, i.e.
  `stopForeground(REMOVE)` plus wakelock release.

**So cancel + re-listen = stopForeground + startForeground.**
`enableBackgroundMode` skips `startForeground` only if the service is *still*
in foreground mode. That never happens after a cancel. A second `listen` on the
raw EventChannel doesn't help either: Flutter's `EventChannel` calls `onCancel`
before every new `onListen`.

* **Background re-listen kills tracking.** A repeated `startForeground()` after
  `stopForeground()` re-evaluates the app's state **[inferred from AOSP
  `ActiveServices.setServiceForegroundInnerLocked`]**. From the background it
  fails with `ForegroundServiceStartNotAllowedException` or `SecurityException`.
  Flutter's EventChannel catches it as a RuntimeException and returns a stream
  error to Dart. Location updates stop, because a while-in-use app without an
  FGS gets no background location, and `RideEngineKeeper` no longer sees an
  FGS.
* **Rule: never cancel or re-listen the ride stream on Android unless the app
  is RESUMED (visible).** This also means GPS mode cannot be changed in the
  background.

**Overnight with the FGS running:**

* **Doze.** The docs list suspended network, ignored wakelocks, deferred alarms
  and jobs, and no Wi-Fi scans. GPS is not mentioned [A3]. AOSP exempts
  processes at procstate ≤ FOREGROUND_SERVICE from the Doze network and
  wakelock restrictions **[inferred from AOSP; not in the public doc]**.
  Practical effect: fixes, Dart timers (thanks to the wakelock) and HTTP
  uploads keep working. Field data from PR #2208 diagnostics should confirm it
  (`fix_gap` events at night).
* **GNSS stays powered.** FLP with `PRIORITY_HIGH_ACCURACY` "enables GPS, Wi-Fi,
  and cell … may cause significant battery drain" [A4]. The min-distance filter
  only suppresses deliveries. Nothing documents it powering GNSS down when the
  device is still [A4][A5]. **Assume GNSS on all night.**
* **The notification is dismissible on Android 14+** (except on the lock screen
  and for "Clear all") [A6]. The FGS keeps running anyway.
* **No FGS timeout for type `location`.** Android 15's 6 h limit covers only
  `dataSync` and `mediaProcessing` [A7].

**What can still end tracking overnight:**

* **Swipe from recents.** PR #2208 parks the engine and the FGS keeps the
  process alive. Some OEMs (MIUI/HyperOS, Huawei, older Samsung) treat the swipe
  as a force stop [A8].
* **Force stop or Task Manager "Stop".** The process dies and nothing restarts
  it.
* **Phone reboot or Play auto-update at night.** The process dies. A location
  FGS can't be re-created from `BOOT_COMPLETED` or `MY_PACKAGE_REPLACED` without
  background location (the while-in-use rule above) [A1][A7].
* **Battery Saver "location off when screen off"** can starve fixes. This
  produces *silence*, not a stop.
* **After any of these, the trip must survive.** Keep the local id and buffer,
  and keep the server ride open. Resume on the next app open (manual ride:
  `_restore`; rental: watcher). Show the hole as a gap.

**Allowed from the background (FGS running):** extra one-shot requests
(`Geolocator.getCurrentPosition`, which uses a separate location client), timers
and network. **Allowed from a notification tap:** starting the FGS (the
while-in-use notification exemption [A1]). This is useful only if we ever add a
"Pokračovat" action to a deep-pause notification. Today the app has no local
notifications package; the native Android channel could post one.

### 2.2 iOS — when-in-use + `UIBackgroundModes: location`

* **Starting in the foreground keeps the app running.** With
  `allowsBackgroundLocationUpdates = true`, "you start location updates while
  the app is in the foreground, Core Location configures the system to keep the
  app running to receive continuous background location updates … Updates
  continue even if the app subsequently enters the background" [I1]. The app is
  *running*, not suspended, so Dart timers keep firing even when the distance
  filter delivers nothing **[inferred; consistent with I1]**.
* **Suspended or terminated.** A suspended app gets queued updates later. A
  terminated app gets none: "If your app is terminated, the delivery of new
  location events stops altogether" [I2]. A when-in-use app is **not
  relaunched** for standard location updates [I5]. Terminations at night happen
  on user swipe-kill, memory pressure, iOS update or App Store auto-update
  (typically overnight while charging). Same answer as Android: the trip stays
  open and resumes on the next app open.
* **`pausesLocationUpdatesAutomatically` must stay `false`.** Apple: "For apps
  that have in-use authorization, a pause to location updates ends access to
  location changes until the app launches again … consider disabling this
  property and changing location accuracy to kCLLocationAccuracyThreeKilometers
  when your app moves to the background" [I3]. Today's `false` is correct.
* **Changing accuracy at runtime needs stop + start through geolocator.**
  `desiredAccuracy` can be changed on a running manager, and Apple itself
  suggests 3 km in the background [I3][I4]. **geolocator_apple 2.3.14/2.3.15
  cannot do that without stopping.**
  * Its `PositionStreamHandler.onListen` refuses while a stream is active
    (`LOCATION_SUBSCRIPTION_ACTIVE`).
  * `onCancel` calls `stopUpdatingLocation`.
  * A re-listen sets the new `desiredAccuracy` and `distanceFilter` on the
    *same* `CLLocationManager` and calls `startUpdatingLocation`.
  * So a switch is always **stop + start**.
  * For when-in-use, (re)starting from the background is not something Apple
    documents as supported. Forum guidance is that background delivery depends
    on a session started in the foreground. Apple's engineer warns that if
    updates are not active when the app is terminated, it is never launched
    again [I5][I6].
  * **Treat a background stop+start on iOS as unreliable.** At best it works,
    because the process is alive and the session continues. At worst updates
    stop until the next foreground.
* **iOS 17 `CLLocationUpdate.liveUpdates` / `CLBackgroundActivitySession`** has
  built-in stationary handling. Updates stop while stationary, so there is "no
  need to stop the updates" [I6]. It is **not reachable** through geolocator 10.
  Using it would need custom Swift in the iOS tree. Out of scope.
* **Blue indicator.** `showsBackgroundLocationIndicator: true` keeps the blue
  pill visible all night. It is expected and honest; Apple recommends not
  fighting it [I6].

### 2.3 Battery — what costs what

| Cost driver | During a ride | While stationary/auto-paused (stream unchanged) |
|---|---|---|
| GNSS receiver (high accuracy) | on | **still on**: distance filter ≠ power-down [A4]. Indoors it keeps searching. |
| Android partial wakelock (`enableWakeLock: true`) | CPU awake | CPU awake all night |
| CPU wake-ups per fix | every 5 s (Android) / per fix (iOS) | ≈ none (filter suppresses delivery). Jitter > 20 m still wakes it. |
| Radio / uploads | batch of 20 points or 90 s | none if the buffer is empty (`_flushOnce` returns) |

Numbers:

* A modern GNSS chip in continuous tracking draws about 25–70 mW
  (vendor-reported, u-blox [B1]).
* Older measurements put it at 143–166 mW [B2].
* Polarsteps (cell/Wi-Fi "balanced" tracking, not live) reports about 4 % per
  full day [B3].
* Android docs: avoid `PRIORITY_HIGH_ACCURACY` for sustained background work;
  balanced "very rarely uses GPS"; low power "largely relies on cell towers" [A4][A5].

**[estimate]**

* **Stationary night** (high-accuracy GNSS plus wakelock): about 100–250 mW,
  i.e. **≈ 0.5–1.5 %/h → ~5–15 % per 10 h night**. A phone indoors with poor
  sky view can reach ~2–3 %/h because GNSS keeps searching.
* **Riding** with screen off: ≈ 2–5 %/h.

This must be measured on a real device. Suggested tool: an optional
`battery` method on the Android ride channel (BatteryManager in
`MainActivity`/`RideEngineKeeper`), logged with `ride` diagnostics.

Battery levers available without new packages:

1. **Manual pause** = cancel the stream (zero cost). This is safe because
   resume happens in the foreground.
2. Auto-pause = *logical* pause. GPS stays on, CPU work is minimal and nothing
   is uploaded.
3. Optional **deep-night mode** (owner decision, default off): after N hours of
   auto-pause, cancel the stream and tell the rider to open the app. Auto-resume
   is lost until the next foreground.
4. iOS-only experiment: background re-listen at `LocationAccuracy.low`/`lowest`
   with distanceFilter 100–200 m during deep pause. This is the Apple-endorsed
   *idea*, but runs through stop+start, so put it behind a remote flag and test
   on a device first.

**Not recommended:** changing `enableWakeLock`, `intervalDuration` or accuracy
for the whole recording. These regress PR #2208 (uploads with the screen off)
or the track quality.

### 2.4 geolocator API matrix (both trees)

| | Android tree | iOS tree |
|---|---|---|
| geolocator | 14.1.1 | 10.1.1 |
| geolocator_android | 5.1.1+1 | 4.6.2 |
| geolocator_apple | 2.3.15 | 2.3.14 |
| platform_interface | 4.4.0 | 4.3.0 |

* **`AndroidSettings` is identical in 4.6.2 and 5.1.1.**
  * Fields: `accuracy`, `distanceFilter`, `intervalDuration`, `timeLimit`,
    `forceLocationManager`, `foregroundNotificationConfig`, `useMSLAltitude`.
  * `ForegroundNotificationConfig` has the same fields: `notificationTitle`,
    `notificationText`, `notificationChannelName`, `notificationIcon`,
    `enableWifiLock`, `enableWakeLock`, `setOngoing`, `color`. The only
    difference is formatting in `AndroidResource`.
* **`AppleSettings` is identical in 2.3.14 and 2.3.15.**
  * Fields: `accuracy`, `distanceFilter`, `timeLimit`, `activityType`,
    `pauseLocationUpdatesAutomatically`, `showBackgroundLocationIndicator`,
    `allowBackgroundLocationUpdates`.
  * `ActivityType` values: `automotiveNavigation`, `fitness`, `otherNavigation`,
    `airborne`, `other`.
* **Accuracy mapping:**
  * Android (`FusedLocationClient.toPriority`): lowest → PASSIVE,
    low → LOW_POWER, medium → BALANCED, high/best/bestForNavigation →
    HIGH_ACCURACY.
  * Android ≥ 13: `setIntervalMillis` = `setMinUpdateIntervalMillis` =
    interval; `setMinUpdateDistanceMeters` = distanceFilter.
  * Android older: fastest = interval / 2. No `setMaxUpdateDelayMillis`
    (no batching).
  * iOS: lowest → 3 km, low → 1 km, medium → 100 m, high → 10 m, best → Best,
    bestForNavigation → BestForNavigation, reduced → Reduced.
* **`Position` (PI 4.3.0 and 4.4.0):**
  * Fields: `latitude`, `longitude`, `timestamp`, `accuracy`, `altitude`,
    `altitudeAccuracy`, `heading`, `headingAccuracy`, `speed`, `speedAccuracy`,
    `floor`, `isMocked`.
  * Flags **`hasAccuracy`, `hasAltitude`, `hasAltitudeAccuracy`, `hasHeading`,
    `hasHeadingAccuracy`, `hasSpeed`, `hasSpeedAccuracy`** exist in BOTH
    (added in PI 4.3.0).
  * `verticalSpeed*` exists **only in 4.4.0 → do not use** in shared code.
  * Android sends `speed` only if `Location.hasSpeed()`, and `speed_accuracy`
    on API 26+.
  * iOS sends speed only if `speed ≥ 0 && speedAccuracy ≥ 0`. Otherwise
    `hasSpeed = false` and `speed = 0.0`. **Unknown speed ≠ 0 km/h.**
  * The constructor defaults all `has*` to `false`. Test fakes must set
    `hasSpeed: true, hasSpeedAccuracy: true, hasAccuracy: true`. Production
    code should treat a speed as known when `hasSpeed || speed > 0`, which is
    robust for both.
* **Streams:**
  * `getPositionStream` returns the cached broadcast stream if one exists,
    regardless of the new settings.
  * The native cancel happens only when the **last** Dart listener cancels
    (`asBroadcastStream(onCancel: …)` → `_positionStream = null`).
  * Settings therefore change only by: (1) no other listener (no navigation),
    (2) cancel ours, (3) `getPositionStream(newSettings).listen`.
* **`getCurrentPosition`** differs between versions:
  * v10 takes `desiredAccuracy` and has no `locationSettings`.
  * v14 takes `locationSettings`; `desiredAccuracy` is deprecated.
  * Shared code must use `desiredAccuracy` (as `GpsService` does). It is
    already in the analyze baseline as deprecated usage. Better to reuse
    `GpsService.getCurrentPosition()` than add a new call, which would add a
    new analyzer info in the Android tree.
* **`getServiceStatusStream`** is the same in both.

**Runtime switch recipe** (if ever used: foreground only, both platforms):

```dart
// Preconditions: app RESUMED (Android FGS rule; iOS when-in-use start rule),
// !RideForeignStreams.any (otherwise the cached nav stream wins).
await _sub?.cancel();                       // stops FGS (Android) / updates (iOS)
_sub = Geolocator.getPositionStream(locationSettings: newSettings)
    .listen(_onPosition, onError: _onStreamError, onDone: _onStreamDone);
// Android: newSettings must still carry foregroundNotificationConfig, otherwise
// there is no FGS and RideEngineKeeper won't park the engine.
```

Low-power settings that compile in both trees:

```dart
AndroidSettings(accuracy: LocationAccuracy.medium, distanceFilter: 150,
    intervalDuration: const Duration(minutes: 1), foregroundNotificationConfig: …)
AppleSettings(accuracy: LocationAccuracy.medium /* or low */, distanceFilter: 150,
    activityType: ActivityType.automotiveNavigation,
    allowBackgroundLocationUpdates: true,
    pauseLocationUpdatesAutomatically: false,
    showBackgroundLocationIndicator: true)
```

**Conclusion for v1:** keep ONE stream with unchanged settings for the whole
recording, including auto-pause. Only *manual* pause cancels it, and only the
foreground resumes it.

---

## 3. How other apps do it

| App | Pause / auto-pause | Multi-day / merge | Source |
|---|---|---|---|
| **Strava** | Cycling auto-pause is GPS-movement based ("only pause when you're completely stopped"). Running uses the accelerometer. Auto-resume when moving. **A manual pause must be resumed manually, even with auto-pause on.** With auto-pause off, moving and resting time are computed on upload. | Activities are < 1 day in practice. | [S1][S2][S3] |
| **Garmin Edge** | Auto Pause "When Stopped" or "Custom Speed" (pause below a set speed). "History is not recorded while the timer is stopped or paused." | — | [G1] |
| **Garmin zūmo** | Continuous track log, archived when full. A power-off/on splits tracks; users join them in BaseCamp ("Join selected tracks"). | Splits on power cycle; merge only on desktop. | [G2] |
| **REVER** (moto) | "Auto-pause Tracking" toggle. Manual pause → manual resume. A review says it pauses after being stagnant "for more than a minute or so" and resumes when moving. | **"There isn't a feature that allows you to merge multiple rides"** (use BaseCamp). Recommends saving each day separately. Closing the app ends the ride. Asks for "Always" location and battery optimisation off. | [R1][R2] |
| **calimoto** (moto) | Manual "Pause" / "Resume recording" in tour options. No evidence of auto-pause. | Users ask how to split week-long recordings into days. No official answer found. | [C1] |
| **Kurviger** (moto) | 1.9: tracking auto-paused when you stop or end navigation. Settings for recording frequency, min distance, GPS accuracy, **min speed**. | **Merge** recordings that were "accidentally interrupted and split into several separate rides" into one. | [K1][K2] |
| **Komoot** | — | A multi-day plan is split into day stages (Collections). | [M1] |
| **Relive** | — | "Not currently possible to merge multiple activities"; "cannot join multiple days together"; optimised for < 1 day. | [L1] |
| **Polarsteps** | Not live. Low-power travel tracking (~4 %/day; balanced = cell/Wi-Fi). | Whole multi-week trip in one journal. | [B3] |

**Takeaways:**

* Vehicle auto-pause is universally GPS-speed/movement based. A few seconds to
  about a minute is enough for a *timer*. For a *recording* that also controls
  battery and track content, a longer threshold is safer (see §4).
* Manual pause → manual resume is the established convention.
* Moving time is computed separately from elapsed time.
* Merge is missing in REVER and Relive, and Kurviger offers it for accidental
  splits. "One trip with day stages" plus merge/undo is a genuine
  differentiator.

---

## 4. Proposed detection (shared Dart, unit-testable, both trees)

### 4.1 Inputs and quality gates

* **Feed the detector every RAW fix** *before* `ridePointFromFix` filtering
  (the 20 m filter hides slow movement). Also feed a periodic `tick(now)`
  (reuse the 90 s timer; a 30 s tick while paused is fine).
* **Good fix:** `hasAccuracy && accuracy ≤ 25 m` and age at receipt ≤ 30 s.
  *Usable*: ≤ 50 m (matches `kRideMaxAccuracyM`). Above 50 m the fix proves
  only that we are alive, not that we moved.
* **Valid Doppler:** `(hasSpeed || speed > 0) && (!hasSpeedAccuracy ||
  speedAccuracy ≤ 2.5 m/s)`.
  * Smartphone Doppler error is cm/s–dm/s on good fixes [D1]. Ski-slope tests
    show < 1.9 km/h mean speed error [D2].
  * Position-derived speed over 5 s with 10–15 m position error gives ±7–11
    km/h noise, and a 100 m jump reads as 72 km/h.
  * **Decide on Doppler.** Use displacement only over windows ≥ 30 s and
    ≥ 100 m between *good* fixes.
* **First fix after (re)attach:** iOS sends a cached one. Skip it, using the
  existing `notBefore` logic.

### 4.2 States

`ARMED` (recording started, nothing ridden yet) → `RIDING` → `STOP_PENDING` →
`PAUSED_AUTO`. Plus `PAUSED_MANUAL` (stream cancelled) and `SIGNAL_LOST`
(silence after fast movement).

**Armed start for rental auto-start AND manual start.** Today the rental
recorder starts at pickup while the rider walks around the branch or kiosk.
Proposed behaviour:

* Begin in `ARMED`.
* Keep sending the first fix immediately, as today, so Velín "Mapa a poloha"
  still sees the position at once.
* Switch to `RIDING` on the resume rule (§4.3), with pre-roll so no metres are
  lost.

### 4.3 Thresholds

| Name | Value | Why |
|---|---|---|
| `V_STILL` | < 3 km/h (Doppler) | Matches server `c_move_kmh = 3`. Doppler noise at standstill is mostly < 1–2 km/h. |
| `V_WALK_MAX` | ≤ 8 km/h | Preferred walking speed is 1.1–1.65 m/s = 4.0–5.9 km/h (mean 1.4 m/s = 5.0 km/h) [W1]. Walk→run transition ≈ 2.0 m/s = 7.2 km/h [W2]. |
| `V_SLOW_RIDE` | > 12 km/h | Any *valid* sample above this resets walking evidence. Pedestrians don't reach it; jogging rarely sustains it. |
| `V_RESUME` | ≥ 20 km/h on **2 consecutive** valid Doppler fixes ≤ 15 s apart, the second ≥ 100 m from the anchor | Unreachable on foot. Two in a row filters single Doppler spikes. A motorbike passes 20 km/h within seconds of pulling away. |
| Resume fallback (no Doppler) | two good fixes ≥ 300 m apart within ≤ 60 s (≥ 18 km/h), the later ≥ 300 m from the anchor | Some Android/Wi-Fi fixes have no speed. 300 m is above city-canyon jumps. |
| `R_STILL` | clamp(1.5 × median accuracy, 40 m, 100 m) around the anchor | Indoor/urban jitter is 10–60 m. |
| `T_STOP_PAUSE` | **5 min** stationary within `R_STILL`, no valid Doppler > 10 km/h | Traffic lights 0.5–2 min, stop-and-go jams move > 40 m in 5 min. Long level crossings or closures may pause, but resume is automatic and pre-roll loses nothing. Fuel stops (5–15 min) pause, which is wanted: walking around the station is not recorded. |
| `T_WALK_PAUSE` | **3 min** of walking evidence after a stop | Walking evidence: valid Doppler 3–8 km/h, none > 12 km/h, or ≥ 150 m walked at ≤ 8 km/h (≥ 3 good fixes). Parking manoeuvres are < 1 min. |
| Silence after slow | no fix for ≥ 3 min after a fix with Doppler < 10 km/h (or a decelerating pair) counts as stationary from that fix | With `distanceFilter 20`, a still phone delivers *nothing*. Silence after slowing down = standing. |
| `SIGNAL_LOST` | no fix while the last valid Doppler was ≥ 30 km/h | Tunnel, garage, OS throttling or battery saver. **Never pause on a timer here.** Decide retroactively at the next fix (§4.6). After 20 min, show "slabý signál" only. |
| Pre-roll | ring buffer of raw fixes during pause, ≤ 120 s / 40 fixes | On resume, prepend fixes from the first one with valid Doppler ≥ 8 km/h. If none, connect anchor → first riding fix (the bike did not move during the pause). |
| Tail restore | first riding fix ≤ 100 m from the held tail's end **and** ≥ 150 m from the anchor → restore the trimmed tail | It was a slow crawl (jam, rough track), not walking: the bike went along the tail. |
| Stage / day split (display only, never a new record) | stage boundary = pause ≥ 2 h, or a pause containing 00:00–05:00 Europe/Prague. "Dny" = distinct local dates with moving time ≥ 5 min. | Matches Komoot-style stages without splitting the trip. |

### 4.4 Walking tail trimming

* **Anchor:** the start of the "slow run", i.e. the first point after which no
  valid Doppler exceeded 12 km/h. In practice this is where the bike was
  parked.
* **On walk-pause:** move all points after the anchor's timestamp from the
  upload buffer into a held-tail buffer.
  * Those points may already be uploaded, since flush runs every 20 points or
    90 s. A server-side "trim after ts" is then needed, OR delay uploads.
  * Simplest: hold points with Doppler ≤ 12 km/h back from flush for up to
    3 min, so the tail rarely reaches the server. This trades some upload
    latency (Velín live position) during slow movement only.
  * If something was already sent, the new server can drop it via an explicit
    pause marker (see §4.8). The old server keeps it, which is a degrade only.
* **On resume:** discard or restore the held tail per §4.3.
* **On stop while walking** (rider ends the ride from the hotel room): discard
  the tail, so the end point = the bike.

### 4.5 Manual pause semantics (recommendation)

`Pozastavit` = cancel the stream, persist `paused_manual` (+ timestamp), and
set keep-alive off. On Android the FGS notification disappears. On iOS the blue
pill disappears.

* **Resume** happens only in-app (foreground, so FGS creation is allowed).
* **On app open while manually paused:** show "Záznam je pozastavený —
  Pokračovat".
* `_restore()` and the watcher's `ensureRecording()` **must not auto-attach
  while paused_manual.**
* Auto-pause stays separate: GPS on, auto-resume.
* This matches Strava's "manual pause needs manual resume" [S1].

### 4.6 Silence and retroactive decisions

At every fix after a silence with dt > 3 min, compute the displacement `d` from
the last good fix and the implied speed `v = d / dt`:

* `d ≤ max(R_STILL, 150 m)` → it was stationary. Pause interval = [last fix
  + 30 s, this fix], if ≥ 5 min. Stays paused until the resume rule fires.
* `v ≥ 15 km/h` → it rode through the gap (tunnel, throttling). Keep `RIDING`.
  The server marks it as a gap if > 180 s and > 300 m. Not counted as km;
  drawn as a dashed connector.
* Otherwise (walked somewhere, the phone travelled at walking pace) → paused,
  with the tail trimmed from the last good riding fix.

This works even if timers did not fire, e.g. CPU asleep or a delayed iOS
delivery.

### 4.7 Statistics guidance (platform-motivated; the SQL agent decides)

**Problems in today's numbers:**

* **Max speed** is lifted from *derived* speed over dt ≤ 60 s. Short-dt GPS
  jumps give nonsense maxima.
* **"Stání"** includes the whole night: a gap with < 300 m displacement counts
  as idle.
* **Duration** = start → last fix, across nights.
* **Gain:** Δalt ≥ 5 m per step sums GPS altitude noise. Vertical error is
  ~2–3 × horizontal. Android altitude is WGS84-ellipsoidal (CZ geoid ≈ +45 m vs
  iOS MSL); this doesn't matter for gain but does for absolute altitude.
* **Walking** at 3–6 km/h counts as moving.

**Proposed rules:**

* **Max:** Doppler only (point kmh), never derived, except for old clients
  without Doppler and then only over ≥ 30 s windows.
* **Moving time ("čas v sedle"):** the sum of segments with speed ≥ 5 km/h,
  excluding pause intervals.
* **Idle ("zastávky"):** stops ≤ pause threshold inside riding.
* **Paused time:** reported separately (e.g. "pauzy 2 × 11 h").
* **Elapsed:** start → end, informational only.
* **Gain:** hysteresis of 10–15 m, plus `alt` only from fixes with
  `altitudeAccuracy ≤ 15 m` (client can omit alt otherwise; both PI versions
  have `hasAltitudeAccuracy`).
* **Avg:** km / moving time.

### 4.8 Server implications for "never split" (input for the SQL agent)

* **Silence must not close a trip.** A paused trip delivers no fixes for hours.
  An app killed overnight delivers nothing until reopened.
  * `close_stale_user_rides` must not close it on 3 h no-fix / 36 h total.
    Close a rental trip at rental end; close a manual trip only after a long
    inactivity (e.g. ≥ 72 h since last contact) or by the rider.
  * `start_user_ride` must resume a paused trip regardless of age.
  * For old 4.1.3 clients, keep the current rule. Gate it by a flag the new
    client sets via a NEW RPC name, never a new default parameter.
* **Pause boundaries.** Old servers ignore extra point elements (they read
  `->>0..4` only; `_ride_track_cap` keeps arrays as-is). But index 5 needs a
  real alt at index 4, and Dart `List<double>` can't hold null. A separate new
  RPC (`pause/resume` events with ts) is cleaner. Old server = pauses appear as
  idle/gap, which is a degraded but working result.
* **Optional heartbeat** while paused (e.g. every 30–60 min) lets Velín show
  "pozastaveno od 20:14". It is not required for correctness, and Velín's
  `last_fix_at` stays truthful (bike parked at the anchor).
* **Track cap.** At 20 m spacing a 2000 km week is ~100 k points; the 4000 cap
  means ~500 m spacing. Raise the cap for trips or store per-stage tracks.
  Thinning already preserves > 180 s gap edges, i.e. pause edges.

### 4.9 Edge cases → expected behaviour

| Case | Result |
|---|---|
| Red light 30–120 s | RIDING (counts as stop time, not pause) |
| Stop-and-go jam | RIDING (moves > 40 m / 5 min). A long standstill closure → pause, auto-resume. |
| Crawling 5–8 km/h > 3 min (filtering, rough track) | walk-pause, then **tail restored** on resume (§4.3) |
| Fuel stop 8 min, walking to the cashier | pause; walking not recorded; resume on departure |
| Lunch / sightseeing walk 2 km | pause; walk trimmed; resume at the bike |
| Overnight in hotel | pause (~5 min after arrival); GPS on all night; resume in the morning on 2 × ≥ 20 km/h; one trip; new stage |
| Underground garage (signal lost after riding) | SIGNAL_LOST → retroactive: walking out → pause at the garage entrance |
| Long tunnel | SIGNAL_LOST, no pause; next fix far away at ≥ 15 km/h → gap connector |
| Phone killed overnight (OS/app update) | no fixes; the trip stays open; the next app open resumes (`ARMED` → riding); the morning before opening is a gap |
| Rider takes a taxi / bus / ferry | **resumes (known limitation, no activity recognition without new packages)**; future fix: "odstranit úsek" edit |
| Navigation open | stream shared (nav settings, no FGS until nav closes, existing `RideForeignStreams` logic); detection identical; never switch settings while `RideForeignStreams.any` |

### 4.10 Unit-test scenarios (fake `Position` stream, `hasSpeed: true` …)

1. Ride 60 km/h → 90 s light → ride: no pause, stop time ≈ 90 s.
2. Ride → stop → silence 12 h → morning 2 × 25 km/h fixes: one pause, anchor =
   stop, pre-roll applied, a single trip.
3. Ride → stop → walk 4–6 km/h for 10 min/600 m → return walk → ride: walk-pause
   at ~3 min, tail discarded, resume at the anchor.
4. Ride → crawl 6 km/h for 5 min along the road → ride on from the crawl end:
   tail restored.
5. Ride 90 km/h → silence 4 min → fix 6 km ahead at 90 km/h: no pause, gap.
6. Indoor jitter: still, fixes jumping 30–60 m with acc 40–80 m and no Doppler:
   stays paused, no resume.
7. Single Doppler spike of 25 km/h while walking: no resume (needs 2
   consecutive).
8. A Wi-Fi-only fix (no speed) 350 m away followed by another 350 m further
   within 40 s: fallback resume.
9. Manual pause → stream cancelled; restore/watcher don't re-attach while
   `paused_manual`.
10. iOS cached first fix after re-attach: ignored.

---

## Sources

* [A1] Android — Restrictions on starting a FGS from the background (exemptions; while-in-use: "cannot create the service while the app is in the background", SecurityException on Android 14+): https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start
* [A2] Android 12 FGS changes ("must call startForegroundService() or bindService() while your app has a visible activity"; location while-in-use): https://developer.android.com/about/versions/12/foreground-services
* [A3] Android — Optimize for Doze and App Standby: https://developer.android.com/training/monitoring-device-state/doze-standby
* [A4] Android — Optimize location for battery (priorities; "may cause significant battery drain"; interval guidance): https://developer.android.com/develop/sensors-and-location/location/battery
* [A5] Android — Optimize location use for real-world scenarios ("avoid PRIORITY_HIGH_ACCURACY for sustained background work"): https://developer.android.com/develop/sensors-and-location/location/battery/scenarios
* [A6] Android 14 behavior changes — non-dismissible notifications now dismissible: https://developer.android.com/about/versions/14/behavior-changes-all
* [A7] Android 15 behavior changes — FGS timeouts only for dataSync/mediaProcessing; BOOT_COMPLETED restrictions: https://developer.android.com/about/versions/15/behavior-changes-15
* [A8] Don't kill my app — Samsung and others: https://dontkillmyapp.com/samsung
* [I1] Apple — `allowsBackgroundLocationUpdates`: https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates
* [I2] Apple — `startUpdatingLocation()`: https://developer.apple.com/documentation/corelocation/cllocationmanager/startupdatinglocation()
* [I3] Apple — `pausesLocationUpdatesAutomatically` (in-use pause ends access; use 3 km accuracy instead): https://developer.apple.com/documentation/corelocation/cllocationmanager/pauseslocationupdatesautomatically
* [I4] Apple — `desiredAccuracy`: https://developer.apple.com/documentation/corelocation/cllocationmanager/desiredaccuracy
* [I5] Apple — Handling location updates in the background: https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background
* [I6] Apple Developer Forums — stopping/resuming background location with CLLocationUpdate (Apple engineer answer): https://developer.apple.com/forums/thread/810433
* [B1] u-blox — Low power tracking applications white paper: https://content.u-blox.com/sites/default/files/Low-power-tracking-applications_WhitePaper_UBX-21014570(1).pdf
* [B2] Modeling and Improving the Energy Performance of GPS Receivers for Mobile Applications (arXiv 1503.02656): https://ar5iv.arxiv.org/html/1503.02656
* [B3] Polarsteps — How much battery does the app use?: https://support.polarsteps.com/article/81-will-my-battery-survive-the-day
* [S1] Strava — Auto Pause: https://support.strava.com/en-us/articles/15402141-auto-pause
* [S2] Strava — Moving time, speed and pace calculations: https://support.strava.com/en-us/articles/15401804-moving-time-speed-and-pace-calculations
* [S3] Strava — Auto Pause on iOS: https://support.strava.com/en-us/articles/15401970-how-to-use-auto-pause-on-ios
* [G1] Garmin Edge — Using Auto Pause: https://www8.garmin.com/manuals/webhelp/edge520plus/EN-GB/GUID-C5E73CA9-B524-41D7-8D78-1114D9C35274.html
* [G2] Garmin zūmo track log archiving/joining (forum): https://www.ukgser.com/community/threads/how-to-retrieve-your-track-logs-from-your-zumo.100028/
* [R1] REVER FAQ (auto-pause toggle, no merge, save each day, closing ends ride): https://www.rever.co/faqs
* [R2] REVER app review (auto-pause after ~1 min stagnant): https://adventuremotorcycle.com/gear/gear-rever-app-trail-phone-gps
* [C1] calimoto — How do I record a ride?: https://support.calimoto.com/hc/en-us/articles/8235400613532-How-Do-I-Record-a-Ride
* [K1] Kurviger docs — Ride Recording (merge split recordings): https://docs.kurviger.com/app/route_recording
* [K2] Kurviger 1.9 — route recording (auto-paused on stop; min speed setting): https://blog.kurviger.com/en/kurviger-app-1-9-now-with-route-recording/
* [M1] Komoot — planning a long-distance ride (multi-day stages): https://www.komoot.com/adventure-hub/7givr4EV7bXg2vLJbWVXFx/the-5-step-guide-to-planning-a-long-distance-ride-with-komoot
* [L1] Relive — Can I record multiple-day activities?: https://support.relive.com/kb/guide/en/can-i-record-multiple-day-activities-3JYhQFHEKA/Steps/1488294
* [W1] Preferred walking speed (Wikipedia): https://en.wikipedia.org/wiki/Preferred_walking_speed
* [W2] Transition from walking to running (Wikipedia): https://en.wikipedia.org/wiki/Transition_from_walking_to_running
* [D1] Li et al., ISPRS 2022 — Android multi-GNSS Doppler velocity: https://isprs-archives.copernicus.org/articles/XLVI-3-W1-2022/89/2022/
* [D2] Smartphone GNSS position and speed accuracy (ski slopes), PMC: https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12349078/

**Code references** (`~/.pub-cache/hosted/pub.dev`):

* `geolocator_android-5.1.1+1/android/src/main/java/com/baseflow/geolocator/{StreamHandlerImpl,GeolocatorLocationService,GeolocatorPlugin}.java`
* `.../location/{FusedLocationClient,LocationOptions,LocationMapper}.java`
* `geolocator_apple-2.3.14/darwin/geolocator_apple/Sources/geolocator_apple/{Handlers/PositionStreamHandler.m,Handlers/GeolocationHandler.m,Utils/LocationAccuracyMapper.m,Utils/LocationMapper.m}`
* `geolocator_platform_interface-4.3.0|4.4.0/lib/src/models/position.dart`
* Repo: `Motogo-app-main/motogo-app-flutter/lib/features/routes/{ride_location,ride_recorder,ride_recorder_watcher,route_navigation_screen}.dart`
* Repo: `android/app/src/main/java/com/motogo24/app/{RideEngineKeeper.kt,MainActivity.kt}`
* Repo: `supabase/migrations/20261015b_user_rides_stats_jump.sql`, `20260922b_user_rides_gap_threshold.sql`
