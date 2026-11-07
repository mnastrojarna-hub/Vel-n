# understand:server — záznam jízd (live stav 2026-10-22)

Source of truth: `origin/supabase-live-snapshot` @ `df555c93` (2026-10-22 08:35 UTC). The function
bodies there already contain 20261015 + 20261015b (CASE "track has timestamps", `c_jump0_km`), so
PR #2208's SQL is live. Every number below comes from replaying synthetic tracks through the REAL
live RPCs on a PG16 copy of the live schema (nothing touched the live DB).

## 0. Shrnutí pro majitele (CZ)

- **Proč se cesta dělí / ztrácí:** server uzavře jízdu, když 3 h nepřijde GPS bod (noc, dlouhá
  zastávka u jezera) nebo když běží déle než 36 h. U **výpůjčky** pak appka ráno založí novou jízdu
  → 3denní výpůjčka = 3 jízdy. U **vlastní motorky** (ruční „Zaznamenat") se ráno při prvním
  odeslání bodů záznam **tiše zastaví** — druhý a další den se vůbec nenahraje (7denní trip:
  uloženo 334 z 2 537 km). Appka ráno ještě ukazuje „nahrávám", než to zjistí.
- **Nesmyslné statistiky:** (1) když jízdu přes noc drží naživu „vlnící se" poloha v pokoji,
  noc se počítá do celkového času i do „stání" (21,6 h celkem, 13 h stání) a přibudou fantomové
  km, minuty jízdy a stovky metrů stoupání; (2) chůze 4 km/h se počítá jako jízda (snižuje Ø);
  (3) „nastoupáno" je chybně počítané — stoupání pod 5 m mezi body se zahodí celé (8% serpentiny
  ve 30 km/h = 0 m), šum GPS se naopak přičte (rovina 100 km = až +2 650 m); v simulaci vychází
  30–40 % skutečnosti; (4) Stop zmáčknutý doma až za 2,5 h přidá 2,5 h „stání"; (5) po vrácení
  motorky se do jízdy ještě až 15 min zapisuje cesta autem (max 104 km/h).
- Pauza, etapy/dny, sloučení jízd ani „trip" server vůbec nezná.

## 1. Test rig (reusable)

| What | Where |
|---|---|
| Cluster PG16 | `/var/tmp/pg-rides` (owner `postgres`), port **5499**, socket `/var/tmp/pg-rides/sock`, DB `rides`, TZ UTC |
| Setup | `scratchpad/rides/pg/setup.sh` — init+start, recreate DB from live snapshot (`pg/snap/schema_public.sql`, `triggers.sql`; `SNAP_REFRESH=1` re-fetches), `stubs.sql` (roles, `auth.users`, `auth.uid()` exactly as live, `extensions` uuid-ossp/pgcrypto, `cron.schedule` stub), `timeshim.sql`, `fixtures.sql`. ~2 s. Expected load errors: 2× `privilege "maintain"` (PG17-only GRANT) + duplicate triggers from triggers.sql — harmless. `setup.sh psql`, `setup.sh stop`. |
| Fake clock | `public.t_now()` reads `test.now`; `select t_set(ts, uid)` sets clock + JWT sub. `select public.t_shim()` rewrites `now()`/`current_date` → fake clock in every public function whose name contains `ride` (+`set_updated_at`) and user_rides defaults. **Re-run `t_shim()` after loading any draft**; a new function without `ride` in its name is not shimmed (extend the filter). Test-only, never in a migration. |
| Fixtures | users `a…0a` (rental, new app), `b…0b` (own bike, new app), `c…0c` (4.1.3), `e1…e1`, `e2…e2` (extra), admin `d…0d` (in `admin_users`), motorcycle `e…0e` Honda CB 500 X. Bookings are inserted per scenario with `session_replication_role=replica` (bookings has many side-effect triggers). |
| Simulator | `scratchpad/rides/pg/sim/`: `world.py` (rider world + Android FLP delivery: 5 s interval, 20 m smallestDisplacement; outdoor noise σ3.5 m AR; indoor Wi-Fi positions every ~60 s σ≈17 m with rare 80–200 m jumps, acc 12–90 m; terrain 3–7 % hills; altitude AR noise σ4 m), `client.py` (**NewClient** = PR #2208 recorder incl. `ridePointFromFix`, 20-pt/90-s flush, continuation, watcher, kill/cold-start restore; **OldClient** = 4.1.3 @70a94933: start with last-known ≤5 min coords, receipt-time stamps, no own 20 m filter, no continuation), `engine.py` (event loop, cron `close_stale_user_rides()` every 15 min, closure attribution), `scenarios.py` (S1–S10), `pgpipe.py` (persistent psql pipe — no python driver here). Run: `python3 -I scratchpad/rides/pg/sim/scenarios.py [S1 S2 …]` → console report + `sim/results.json`. `sim/elev_check.sql` = elevation unit check. The OldClient is the 4.1.3 back-compat harness for new drafts. |

## 2. Data model (live)

`user_rides`: `id, user_id, booking_id, moto_id, moto_name, name, description, source (auto|manual),
track jsonb [[lat,lng,ts,kmh,alt]…] (cap 4000), start/end lat/lng, started_at, ended_at,
distance_km numeric(9,3), duration_min, moving_sec, idle_sec, gap_sec, avg_speed_kmh, max_speed_kmh,
elevation_gain_m, is_recording, visibility, status, cover_image, created_at, updated_at, last_fix_at`.
Partial **unique index `uq_user_rides_recording (user_id) WHERE is_recording`** → max ONE open ride per
user. `idx_user_rides_recording_fix (last_fix_at desc) where is_recording`. Only trigger:
`trg_user_rides_updated` (set_updated_at). `user_ride_points` (kind start|end|stop, photos[], POI refs,
FK ride CASCADE). RLS owner+admin, no anon read. **`source` is always `'auto'` for every GPS
recording** (`start_user_ride` hardcodes it — also for own-bike "Zaznamenat"); `'manual'` only for
`create_manual_ride` (drawn routes). Server cannot tell own-bike recording from rental except by
`booking_id` — and a manual start on a rental day gets paired to the rental (date match).
No concept of pause, segment/day, trip or merge anywhere (no columns, no RPC).

## 3. RPC behaviour (live bodies)

- **start_user_ride(p_booking_id, p_lat, p_lng)** — if the user has an open ride: `greatest(coalesce(last_fix_at,started_at), updated_at) > now()-3h` → return it `resumed:true`; else **`_ride_finalize(old, that time)` and create a new one**. Booking = `p_booking_id` if status reserved/active, else (only when p_booking_id null) a reserved/active booking with `start_date::date <= current_date <= end_date::date` (UTC). Inserts `source='auto'`, first point `[lat,lng,server now]` when coords given (4.1.3 does; new app sends none). Returns `{success,id,resumed,booking_id,moto_name}`.
- **append_ride_track(p_ride_id, p_points, p_max_speed_kmh)** — closed ride → `{success:false,error:'ride_finished',finished:true}`; drops points with ts < started_at−1 h (`dropped_stale`); stats of (last stored point + batch) via `_ride_stats`, **added incrementally**; track capped by `_ride_track_cap(4000)` (keeps every k-th point + both edges of >180 s jumps + last); `last_fix_at` = last point ts (sanity-clamped); `duration_min = last_fix − started_at`; `avg = km/moving (≤200)`; `max = greatest(max, client max, stats max, avg)`. **No check against `bookings.returned_at`.**
- **_ride_stats(track)** per neighbour pair: dt<0 or ≥86400 → ignored entirely; **gap** = dt>180 s AND displacement>0.3 km → only `gap_sec` (no km, no elevation); jump (v≥300 km/h or dt=0 & ≥0.5 km) → no km; else km added **regardless of speed**, time → `moving` if v≥3 km/h else `idle`; max from client speed or computed v (dt≤60 s); **elevation = sum of per-step rises ≥5 m** (no hysteresis/smoothing).
- **_ride_finalize(id, p_ended_at)** (revoked from clients) — already closed → returns stored values; `end = coalesce(p_ended_at, last_fix_at, updated_at, now())`; km from track only for timestamp-less tracks; **<1 km → DELETE row** (`discarded`); `duration = max(end−start, covered)`; **`idle := duration − moving − gap`** (all unexplained time becomes "stání"); avg; max ≥ avg; end point; name = `DD.MM.YYYY` of start if empty; inserts `start`/`end` points.
- **finish_user_ride(id, points, name)** — append last batch, then finalize at **`now()`**, clamped to `bookings.returned_at` only when the ride has a booking and returned_at < now.
- **close_stale_user_rides()** (pg_cron `close-stale-user-rides` `*/15`) — closes open rides where (a) `greatest(coalesce(last_fix_at,started_at),updated_at) < now()-3h`, or (b) `started_at < now()-36h`, or (c) booking `end_date::date < current_date` (UTC) or status completed/cancelled; finalize at `greatest(last_fix, updated_at)` (NOT returned_at); <1 km deleted; 500/run; per-ride exception block.
- **admin_finish_user_ride** (Velín button) → finalize at last fix. **admin_booking_live_ride** (Velín "Mapa a poloha") → the booking's open ride first, else latest; `is_live = is_recording AND fix age < 900 s`; track capped 1200.
- **get_my_rides(p_limit default 100, max 300)** / get_booking_rides / get_public_rides (authenticated only since 20261011d) → `_ride_json` (all columns + points). update_user_ride / delete_user_ride / save_ride_point (200/ride) / delete_ride_point / create_manual_ride (500/user).

## 4. Every rule that ENDS or SPLITS a trip

| # | Where | Condition | Effect |
|---|---|---|---|
| R-a | `close_stale_user_rides` | no fix and no update for **3 h** | closed at last fix; next batch → `ride_finished` |
| R-b | `close_stale_user_rides` | **started_at older than 36 h** (even if fixes keep coming) | closed mid-trip (sim: 21:15 / 22:09 on day 2 evening) |
| R-c | `close_stale_user_rides` | booking end date (UTC) passed or status completed/cancelled | closed ≤15 min after return, at last fix |
| R-d | `start_user_ride` | open ride stale >3 h when (re)start is called | old one finalized, new one created |
| R-e | `_ride_finalize` | km < 1.0 | row DELETED (a short split piece vanishes) |
| R-f | `append_ride_track` | points older than started_at−1 h | dropped (protects new ride from old buffer) |
| R-g | unique index | only one `is_recording` per user | a paused/open trip blocks any other recording |
| R-h | new client | `ride_finished` on append: rental (bookingId set, not manual) → `start_user_ride(booking)` = **new ride**; booking no longer active → finish empty ride (deleted) + stop; **manual → `_forgetRide` = recording STOPS** | split (rental) / loss (own bike) |
| R-i | 4.1.3 client | `ride_finished` → forget, **no continuation**; watcher restarts only when the app is opened in foreground (rental only) | loss until app opened |
| R-j | watcher (fg only) | booking returned/ended → `stop()` | finish (clamped to returned_at) |

## 5. Scenario replays (truth vs stored)

Columns: rides stored / created; stored km vs true bike km; per ride: total (duration_min) · jízda
(moving) · stání (idle) · bez signálu (gap) in min; Ø, max km/h; ⛰ stored vs true climb.

| Scn | What | Rides | km stored / true bike | Per ride |
|---|---|---|---|---|
| S1 | 1 day own bike, fuel/coffee/lunch/photo stops, new app | 1/1 | 332.7 / 331.7 | 412 · 296 · 116 · 0; Ø 67.4, max 99.2; ⛰ 952 / **2 794** |
| S2 | own bike, hotel night, **no fix 10 h** | 1/1 | **385.8 / 588.3 (−203 km: day 2 lost)** | closed by cron 23:45; 07:46 first batch → `ride_finished` → recording stopped |
| S2d | same, **indoor drift night** | 1/1 | 593.2 / 587.2 (+5.7 phantom) | **1298 · 503 (+24) · 795 (night as stání) · 0**; ⛰ 2 716 (drift noise) |
| S2r | rental 2 days, no-fix night | 2/2 | 589.1 / 588.3 | split: Mon 13:00–20:39 + Tue 07:46–10:34 |
| S2rd | rental 2 days, drift night | 1/1 | 593.2 / 587.2 | 1294 · 503 · 791 · 0 (night inside) |
| S3 | rental 2 days, app killed 20:24, opened 08:00 | 2/2 | 668.7 / 667.0 | split by cron 21:00 + new ride at open |
| S3b | own bike, app killed mid-ride 65 min | 1/1 | 153.2 / 206.3 | 188 · 117 · 5 · **65 gap** (correctly not counted as km) |
| S4a | **7-day own-bike trip**, Start once, no-fix nights | 1/1 | **334.3 / 2 537 (−2 205 km)** | only day 1; stops at first batch of day 2 |
| S4b | 7 days, rider presses Start each morning when he sees it stopped | 4/4 | 1 504.7 / 2 537 | app still says "recording" in the morning → only every other day survives |
| S4c | 7 days, Start once, drift nights | 1/1 | 711.3 / 2 528 | **36 h cap** closes Tue 21:15 → stopped; ride 2 175 · 635 · **1 540** · 0, ⛰ 4 532 |
| S5 | rental 3 days + return + 45 min car home | 3/4 (1 deleted) | 839.7 / 836.5 | one ride per day; post-return empty ride created+deleted |
| S5b | rental, return, **car immediately** | 1/2 (1 deleted) | **218.4 / 201.7 (+16.7 car)** | ended 14:00 > returned 13:47, **max 104.1 (car)** |
| S6 | own bike, **40 min walk 4 km/h** | 1/1 | 153.5 / 151.0 (+2.7 walk) | 163 · **155 (walk as riding)** · 8; **Ø 59.4** (bike only ≈78) |
| S7a | **4.1.3** day + stops + walk | 1/1 | 373.2 / 370.1 | 481 · 363 · 118; Ø 61.7; ⛰ 988 / 3 130 |
| S7b | **4.1.3** rental 2 days, app opened 12:00 day 2 | 2/2 | 472.3 / 636.6 (−164) | morning 08:00–12:00 lost |
| S8 | own bike, **3.5 h at a lake** (phone outdoors, no fix) | 1/1 | 112.5 / 235.3 (−123) | closed by cron 13:45 → afternoon lost |
| S9 | rental 3 days, drift nights | 2/3 (1 deleted) | 858.4 / 837.8 (+20 phantom) | ride 1 = 36 h (2 169 · 559 · **1 610**), ride 2 starts **22:16 in the hotel** |
| S10 | own bike, home 14:42, **Stop at 17:12** | 1/1 | 124.5 / 124.5 | **252 · 98 · 154** (2.5 h at home = stání) |

Elevation unit check (`sim/elev_check.sql`, `_ride_stats` directly): 5 % at 80 km/h → 300/300 m;
**3.5 % at 80 km/h → 0/299; 5 % at 40 km/h → 0/300; 8 % hairpins at 30 km/h → 0/299; flat 100 km,
white noise σ3 m → +773 m, σ6 m → +2 650 m.**

## 6. Nonsense / unwanted-split catalogue

- **N1 (split/loss, 3 h rule)** — nights and ≥3 h stops end the ride. Rental → one ride per day (S2r, S3, S5). Own bike → recording silently stops next morning (S2 −203 km, S4a −2 205 km, S8 −123 km). 4.1.3 → stopped until the app is opened (S7b −164 km).
- **N2 (36 h cap)** — anything that keeps a ride alive (drift) splits it at start+36 h, typically on the 2nd evening; the continuation ride then starts at night in the hotel (S9 22:16); own bike → stops (S4c).
- **N3 (morning UI lie)** — after a server-side close the app keeps `recording=true` until the next batch (≤90 s / 20 pts) returns `ride_finished`; the rider sees "nahrávám" and rides off.
- **N4 (night = stání/celkový čas)** — when a ride spans a night, `duration_min` and `idle_sec` include the whole night (S2d 21.6 h / 13.3 h stání; S4c 36 h / 25.7 h; S9 36 h / 26.8 h). `_ride_finalize` turns every unexplained second into `idle`.
- **N5 (drift)** — indoor Wi-Fi fixes with accuracy ≤50 m pass the app filter (dropped only if acc>50 AND <3 km/h) and the 20 m filter; server adds km for every non-gap segment regardless of speed and counts v≥3 km/h jumps as moving → per night ≈ +6 km, +24 min jízdy, +~1 000 m ⛰.
- **N6 (walking = riding)** — 4 km/h ≥ 3 km/h threshold: +km, +moving minutes, Ø dragged down (S6, S7a).
- **N7 (elevation)** — per-step ≥5 m rule drops gradual climbs (most real climbs at normal fix spacing) and counts noise; stored ≈ 30–40 % of truth on day rides, noise-inflated on flat/drift.
- **N8 (late Stop)** — `finish_user_ride` ends at `now()` (own bike: no clamp) → time at home becomes stání/celkový čas (S10 +2.5 h). Max 3 h, then cron closes at last fix.
- **N9 (after return)** — append accepts points after `returned_at`; cron closes ≤15 min later at last fix (not returned_at) → car drive home in the rental ride (S5b +16.7 km, max 104 km/h).
- **N10 (junk rows)** — every rental end with the app alive in background creates an empty continuation ride that is immediately finished/deleted (S5, S5b, S9).
- **N11 (gap)** — app killed mid-ride: gap correctly excluded from km, but "Celkový čas" includes it and stops inside it are not stání (S3b). Expected; must not be treated as riding by any auto-pause logic.
- **N12** — name = start date only ("05.10.2026") for a multi-day ride; no days/etapy/pauses anywhere.
- **N13** — 4000-point cap: a 7-day trip (~25–35 k points) is thinned (every ~7th point + gap edges). Stats are incremental so they stay right, **but any merge/recompute from stored tracks under-counts km** — a merge must sum stored stats (and keep `gap`), not rerun `_ride_stats` on the concatenation.
- **N14** — app list `get_my_rides()` default 100 rides; daily splits fill it fast. `Moje` summary just sums km.

## 7. Velín (what it computes/shows)

- `TrasyJizdy.jsx`: direct select of `user_rides` with an explicit column list (`RIDE_LIST_COLS`, falls back to a legacy list on 42703), points from `user_ride_points`; header totals = Σ`distance_km`, Σ`moving_sec` ("v sedle"); per ride km, `duration_min` ("Celkový čas"), moving ("Čas jízdy"), idle ("Čas stání"), avg, max, gap ("bez signálu"), ⛰; badge "● Nahrává se"; **`isStuck` = is_recording and >3 h since last_fix/updated → "Záznam visí"**; filters incl. "Nahrávané".
- `TrasyJizdaModal.jsx`: loads track on open; stats grid (same fields + points count, start/end); `stuck` (3 h) → red box + **"Ukončit záznam"** (`admin_finish_user_ride`); sparse-track warning (`trackQuality`: <10 pts or <5 pts/km with <1000 pts); diagnostics `TrasyJizdaDiag` (app_debug_logs `ride`/`lifecycle` ±15 min, `rideDiag.js`).
- `TrasyJizdaMapa.jsx` + `lib/rideTrack.js`: `splitTrackOnGaps` with the server's thresholds (180 s & 0.3 km) → dashed grey gap segments.
- `booking/BookingLiveMap.jsx` (Rezervace → "Mapa a poloha"): `admin_booking_live_ride`; "živě" if fix <15 min, "Poslední signál před X" otherwise, stuck banner + "Ukončit záznam".
- Consequence for pause/auto-pause: a paused open ride would show "Záznam visí" after 3 h and offer "Ukončit záznam"; live map shows it as stale — both must learn the paused state.

## 8. Facts that constrain the redesign (back-compat)

- **4.1.3 client** (released): `start_user_ride(p_booking_id,p_lat,p_lng)` needs `success,id,resumed`; `append_ride_track` → `success:true` ok, error `ride_finished|ride_not_found` → forget, **any other error → retry forever (buffer persisted, grows)** — never return a new error code to append; `finish_user_ride` needs `success,discarded,distance_km`, `ride_not_found` = closed. 4.1.3 stamps points with receipt time, has no pause, no continuation; after a cold start it re-attaches a manual ride WITHOUT asking the server. It relies on cron R-a to free the unique index.
- If R-a/R-b stop splitting multi-day trips, an old client's ride simply stays open across nights (good for R4/R6) — then the server itself must classify the long no-fix/same-place interval as a **pause, not stání/celkový čas** (N4), because 4.1.3 will never send a pause.
- `start_user_ride` itself finalizes a >3 h stale ride (R-d): a paused overnight trip would be closed by the next `start_user_ride` call (old or new client) unless that rule learns about pause/trips. `uq_user_rides_recording` means a paused trip that stays `is_recording` blocks every other recording; one that doesn't is invisible to resume logic.
- New RPC names only (no new defaulted params on existing names — PostgREST overload ambiguity). New app must detect a missing RPC (PostgREST `PGRST202` / SQLSTATE 42883) and missing JSON keys from `get_my_rides` and degrade.
- Merge must re-parent `user_ride_points` (and drop inner `start`/`end` points), sum incremental stats, recompute derived ones (duration, avg, max), keep `booking_id` semantics (a merged rental + own-bike trip has no single booking), respect the 4000 cap, and be undoable (keep source rows/segments).
- Other read-only consumers (not ride files): `features/home/v2/home_ticket_checklist.dart`, `features/routes/community_submit.dart`. No edge function or web code touches rides.
