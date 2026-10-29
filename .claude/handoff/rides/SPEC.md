# SPEC — ride recording: pause, auto-pause, never-split trips, merge, sane stats

Final implementation spec, 2026-10-22. Branch `claude/moto-go-mobile-conversion-gqg5qo` (contains PR #2208).
Inputs: `design_server-segments.md` (A), `design_minimal-change.md` (B), `understand_app.md`, `understand_server.md`, `understand_platform.md`, live snapshot `pg/snap/schema_public.sql` (df555c93).
Owner summary: `SPEC_OWNER_CS.md`. This file is binding for every implementation task (T1–T5, §17). Where this spec and a design disagree, this spec wins.

---

## 0. Verdict

Scores 1–5 (5 = best):

| Criterion | A server-segments | B minimal-change |
|---|---|---|
| R1 manual pause | 5 | 5 |
| R2 auto-pause/resume | 5 | 5 |
| R3 sane stats | 5 (silence rule, Doppler moving, EMA climb, server stages) | 3 (slow-displacement nights still "bez signálu", client-side stages from thinned track) |
| R4 never split | 5 | 4 |
| R5 merge + undo | 5 (separate table, 8 RPCs) | 4 (columns + client grouping, implicit rental grouping for history) |
| R6 rental same rules | 5 | 5 |
| Robustness (kills, offline, retries, clock, 2 phones) | 3 (event ordering, open-pause server state, more moving parts) | 4 (marker travels inside the point = retry-safe; clock offset) |
| Battery | 4 (deep pause, but wake needs the app) | 3 (GPS on while paused; home rule only) |
| Backward compatibility (4.1.3) | 3 (4.1.3 own rides kept open up to 30 d with drift) | 5 |
| Simplicity for the rider | 3 (deep/reconcile sheets) | 5 |
| Implementation risk | 2 (new append path, events, trip table, many RPCs, two native notifications) | 4 |
| SQL rule (new names, no overloads, idempotent) | 5 | 5 |

**Base = B (minimal-change).** Kept from B: pause marker `kmh = -1` inside the existing point format; existing `append_ride_track` path for every client; only two new public RPCs (`start_user_trip`, `set_user_rides_trip`); trips as columns `trip_id`/`trip_name` plus client grouping (rentals grouped by `booking_id` automatically, also for history); legacy (4.1.3) own rides keep today's 3 h / 36 h rule; clock-offset correction; "home" guard; power-of-two track thinning.

**Grafted from A:**
- server silence rule (a long slow silence is a pause regardless of displacement; only ≥ 15 km/h counts as gap);
- Doppler-based "moving" rule (walking and drift never add km);
- `idle` as remainder and `duration_min` = time without pauses;
- Doppler-only max with plausibility check;
- EMA + 6 m hysteresis elevation;
- exact server-side `stages` (days);
- armed start (`started_at` moves to the real departure);
- immediate close of a rental ride when a batch arrives after `returned_at`;
- legacy still-run inference (4.1.3 drift/walking runs become pauses);
- long-pause battery guard for own trips with an Android notice;
- per-phase Android notification text;
- stage-scaled track cap (up to 12 000 points).

**Dropped:**
- from A: `user_trips` table and its 8 RPCs, `ride_append_v2`/events, open-pause server columns, pings, `ride_current_v2`, `ride_summary_v2`, reconcile sheet;
- from B: client-side stage estimation.

---

## 1. Invariants and glossary

**Hard invariants**
- Released app 4.1.3 must keep working unchanged against the new SQL:
  - same RPC names, signatures and response keys;
  - `append_ride_track` never returns an error code other than today's (`not_authenticated`, `points_required`, `ride_not_found`, `ride_finished`).
- The new app must work against the CURRENT server (before the SQL is deployed): fallback in §5.4.
- No new Dart packages; no iOS dependency bumps; shared code uses only APIs present in geolocator 10.1.1 / platform_interface 4.3.0. `verticalSpeed*` is forbidden. `Position.hasSpeed`, `hasSpeedAccuracy`, `hasAccuracy` and `hasAltitudeAccuracy` exist in both versions.
- One GPS stream per recording session, settings unchanged (§6.9). Only manual pause and the battery guards cancel it. Re-attach only happens in the foreground.
- Everything else stays as it is today:
  - auto-start during a rental when location is already permitted, plus the auto switch;
  - manual recording;
  - ride points with photos, naming, private/public sharing, delete;
  - Velín live position via `last_fix_at`, Velín diagnostics;
  - navigation integration (`RideForeignStreams`);
  - the `< 1 km` discard;
  - kiosk and booking logic.

**Glossary**

| Term | Meaning |
|---|---|
| point | `[lat, lng, ts, kmh, alt?]` as today. Dart `List<double>`, JSON array. |
| pause marker | `kmh < 0` (the client sends exactly `-1`) on the **first point after a pause ≥ 60 s**. The interval from the previous point to the marked point is a pause. Old server, 4.1.3 and Velín never read index 3 as anything but a speed for `max` (−1 never wins). Verified by grep. |
| pause-aware ride | `user_rides.pause_aware = true`, set by `start_user_trip` (new app on the new server). Otherwise the ride is **legacy** (4.1.3, PR #2208 dev build, new app's fallback). |
| auto-pause | Client phase `autoPaused`: stream on, nothing uploaded, waiting for riding. |
| armed | `autoPaused` with reason `start`: recording opened, nothing ridden yet. |
| manual pause | Client phase `manualPaused`: stream cancelled, resume only by tap in the foreground. |
| stage (etapa) | Server-side day-like section of one ride. A boundary is a pause ≥ 6 h, or a pause ≥ 30 min overlapping 00:00–05:00 Europe/Prague. |
| trip (cesta) | Display group of ≥ 2 rides: explicit `trip_id`, else same `booking_id`. One ride over several days is NOT a trip; it is a ride with ≥ 2 stages. |

---

## 2. Data contract

### 2.1 `user_rides` new columns (draft 01; all `ADD COLUMN IF NOT EXISTS`, Czech `COMMENT ON COLUMN` each)

| Column | Type / default | Meaning |
|---|---|---|
| `pause_sec` | `integer not null default 0` | Time of pauses: explicit marker, inferred silence ≥ 5 min, legacy still-runs ≥ 5 min. Not part of `idle_sec`, `gap_sec`, `moving_sec` or `duration_min`. |
| `pause_aware` | `boolean not null default false` | The ride is driven by a client that pauses itself (set by `start_user_trip`). Drives cron/start rules (§4.6–4.8) and switches off legacy still-run inference. |
| `stats_state` | `jsonb null` | Incremental carry state between batches (§3.6). Never shown. |
| `stages` | `jsonb not null default '[]'` | Per-stage stats (§3.5). |
| `trip_id` | `uuid null` (no FK) | `null` = default grouping (by `booking_id`); `= id` = explicitly standalone; any other value = member of the trip keyed by that uuid. |
| `trip_name` | `text null`, CHECK `trip_name is null or char_length(trip_name) <= 120` (constraint `user_rides_trip_name_len`, added in a DO block if missing) | Trip name, identical on all members. |

Index: `create index if not exists idx_user_rides_trip on public.user_rides (user_id, trip_id) where trip_id is not null;`

RLS is unchanged (owner ALL + admin ALL). The app writes trip fields only via `set_user_rides_trip`.

### 2.2 Point conventions (new client; old clients unchanged)

| Index | New-client rule |
|---|---|
| 0, 1 | lat/lng, 5 decimals (as today) |
| 2 `ts` | Fix time in epoch seconds, **0.1 s precision**, corrected by the clock offset (§5.5). The server regex `^[0-9]+(\.[0-9]+)?$` already accepts decimals. |
| 3 `kmh` | Valid Doppler only (`(hasSpeed \|\| speed > 0) && (!hasSpeedAccuracy \|\| speedAccuracy <= 2.5 m/s)`), ×3.6, 1 decimal, `> 300 → 0`. Otherwise `0`. **`-1` = pause marker.** |
| 4 `alt` | Only if finite, `!= 0`, and `(!hasAltitudeAccuracy \|\| altitudeAccuracy <= 20)`. Otherwise omitted (point length 4). |

### 2.3 `_ride_json` (all ride reads)

Adds keys `pause_sec`, `pause_aware`, `trip_id`, `trip_name`, `stages`. Every existing key stays, with the same meaning, except `duration_min` (= active time without pauses, §3.4). Old apps read named keys only (`UserRide.fromJson`), so the extra keys are ignored.

---

## 3. Stats v2 (server, source of truth)

### 3.1 Constants (`_ride_stats_v2`)

| Name | Value | Meaning |
|---|---|---|
| `c_gap_dt` | 180 s | silence threshold |
| `c_gap_v` | 15 km/h | silence ridden through → gap |
| `c_still_km` | 0.3 km | gap needs more displacement than this |
| `c_pause_min` | 300 s | inferred pause / still-run pause |
| `c_bad_dt` | 2 592 000 s (30 d) | larger dt = bad time (was 86 400) |
| `c_jump_v` | 250 km/h | GPS jump (was 300) |
| `c_jump0_km` | 0.5 km | dt = 0 jump |
| `c_move_v` | 3 km/h | minimal derived speed of a moving pair |
| `c_move_dop` | 7 km/h | Doppler threshold of a moving pair |
| `c_move_nodop_v` | 15 km/h | derived threshold when neither end has Doppler |
| `c_move_nodop_dt` | 3 s | minimal dt for the no-Doppler rule |
| `c_max_dop` | 250 km/h | Doppler max ceiling |
| `c_max_rel`, `c_max_abs`, `c_max_rel_dt` | 1.5, 20 km/h, 4 s | plausibility: if dt ≥ 4 s then `kmh ≤ 1.5·v + 20` |
| `c_nodop_max_dt` | 30 s | derived max only for rides without any Doppler |
| `c_ema`, `c_hyst` | 0.25, 6 m | elevation smoothing, hysteresis |
| `c_spike_rel`, `c_spike_abs` | 0.25, 10 m | altitude spike if `\|Δalt\| > 0.25·d_m + 10` |
| `c_stage_long` | 21 600 s (6 h) | stage boundary |
| `c_stage_night_min` | 1 800 s | stage boundary if the pause overlaps 00:00–05:00 Prague |

### 3.2 Pair classification

`p` = previous point with a timestamp (the stored last point for the first pair of a batch); `q` = current point.
- `d` = haversine km accumulated since `p`; points without ts accumulate, as today.
- `dt = q.ts − p.ts`; `v = d / dt · 3600` when `dt > 0`.
- `dp`, `dq` = valid Doppler of p/q: `kmh` if `0 < kmh < 250`, else 0.
- `dop = max(dp, dq)`.
- `flag = q.kmh < 0`.

The first matching rule wins:

0. No `p` yet → stage init (§3.5), nothing counted.
1. `dt` is null (no timestamps) → `km += d` (today's behaviour), nothing else.
2. `dt < 0` or `dt ≥ c_bad_dt` → bad time: nothing counted, elevation reset.
3. `flag` → **EXPLICIT PAUSE** `[p.ts, q.ts]`:
   - `pause += dt`;
   - stage-boundary check (§3.5);
   - elevation reset;
   - no km, even if `d` is large (ferry, trailer).
4. `dt > c_gap_dt`:
   - `v ≥ 15 and d > 0.3` → **GAP**: `gap += dt`, stage `gap += dt`, elevation reset, no km;
   - else if `dt ≥ 300` → **INFERRED PAUSE** `[p.ts, q.ts]`: as rule 3;
   - else → **STOP**: nothing counted (it becomes idle via the remainder).
5. `v ≥ 250` or (`dt = 0` and `d ≥ 0.5`) → **JUMP**: nothing counted.
6. `dt = 0 and d < 0.5 and dop ≥ 7` → `km += d` (4.1.3 receipt-time batches share one second), no time.
7. `v ≥ 3` and (`dop ≥ 7` or (`dp = 0 and dq = 0 and dt ≥ 3 and v ≥ 15`)) → **MOVING**:
   - `km += d`, `moving += dt`;
   - max candidate (§3.3);
   - elevation step (§3.6);
   - add to the current stage.
8. Otherwise → **NON-MOVING** (walking, drift, crawl < 7 km/h Doppler, light stop): nothing counted.
   - Legacy rides only: if `state.still_from` is null, set it to `p.ts`.

**Legacy still-run** (only when `state.legacy` is true, i.e. `pause_aware = false`). Before applying any rule other than 8 to a pair:
- if `state.still_from` is not null and `p.ts − still_from ≥ 300`:
  - it is a still-run pause `[still_from, p.ts]`: `pause += p.ts − still_from`, stage-boundary check, elevation reset;
  - add `[still_from, p.ts]` to `trims` (stored points strictly inside are removed, §4.2 step 6);
- then `still_from := null`.

For pause-aware rides `still_from` is never set: the client already pauses, so a slow jam stays "stop" time.

Whatever the per-batch result, **idle is always a remainder** (§3.4). It is never summed.

### 3.3 Max speed

- Candidate `dq` from a MOVING pair, accepted when `dq < 250` and (`dt < 4` or `dq ≤ 1.5·v + 20`).
- `state.has_dop := true` when any point has `0 < kmh < 250`.
- `state.nodop_max` = max derived `v` over MOVING pairs with `dp = dq = 0` and `dt ≥ 30`.
- Ride max = `greatest(stored max, batch dop max, case when not has_dop then nodop_max end, avg)`. The "max ≥ avg" floor is kept from today.
- `p_max_speed_kmh` of `append_ride_track` is accepted and **ignored**: every point carries its own kmh, and the client max is unvalidated.

### 3.4 Ride-level values (append and finalize)

```
last_ts      = ts of the last stored point (append) or the finalize end (finalize)
elapsed_sec  = last_ts − epoch(started_at)
active_sec   = greatest(0, elapsed_sec − pause_sec)
idle_sec     = greatest(0, active_sec − moving_sec − gap_sec)
duration_min = round(active_sec / 60)                                     -- "na cestě bez pauz"
avg_speed    = moving_sec ≥ 60 ? least(round(km / (moving_sec/3600), 1), 200)
             : null                                                       -- finalize fallback as today
```

- `duration_min` changes meaning: it now excludes pauses. 4.1.3, Velín and the app show it as the total/"na cestě" time, which automatically becomes sane.
- For a ride without pauses the value equals today's.

### 3.5 Stages (`stages` column)

Element (epoch seconds):

```json
{"f": start_ts, "t": last_ts, "km": 12.345, "mv": 2710, "gap": 0, "ps": 900,
 "gain": 214, "max": 118.4, "a": [lat, lng], "b": [lat, lng]}
```

- **Init:** when `stages = []` and the first point arrives → `{f: q.ts, t: q.ts, a: q, b: q, zeros}`.
- **Every non-pause pair** updates the last stage:
  - `t := q.ts`, `b := q`;
  - MOVING adds `km`, `mv`, `gain`, `max`;
  - GAP adds `gap`.
- **Pause close** (explicit, inferred or still-run) of `[pf, pt]`, duration `D`:
  - boundary when `D ≥ 21600`, or (`D ≥ 1800` and `_ride_prague_night(pf, pt)`);
  - boundary → last stage `t := pf`, `b := p`, then append a new stage `{f: pt, t: pt, a: q, b: q, zeros}`;
  - otherwise → last stage `ps += D`.
- **Helper:** `_ride_prague_night(p_from double precision, p_to double precision) returns boolean` STABLE. True when `[to_timestamp(pf), to_timestamp(pt)]` overlaps any local 00:00–05:00 Europe/Prague window.
- **Cap:** at most 60 stages; beyond that, merge into the last.
- **Derived:**
  - stage idle = `greatest(0, (t − f) − mv − gap − ps)`;
  - `days` = number of distinct Prague dates among `{date(f), date(t)}` of stages with `mv ≥ 300`; 1 when there are no such stages.

### 3.6 Elevation and `stats_state`

`stats_state` keys:
- `legacy` (bool; set per call from `not pause_aware`, not persisted semantics);
- `ema`, `ref`, `palt` (numeric or null);
- `still_from` (epoch or null);
- `has_dop` (bool);
- `nodop_max` (numeric).

On MOVING pairs where `q` has alt:
1. If `palt` is null → `ema := ref := palt := alt`, done.
2. If `|alt − palt| > 0.25·d_m + 10` → skip (spike; `palt` unchanged).
3. `ema := ema + 0.25·(alt − ema)`, `palt := alt`.
4. If `ema − ref ≥ 6` → `gain += ema − ref`, `ref := ema`; else if `ema < ref` → `ref := ema`.

`ema`, `ref` and `palt := null` on gap, pause and bad time.

Expected quality (A's simulation, `design_tools/elev.py`; T1 must confirm with `world.py` noise):
- climbs: 85–100 % of truth;
- flat road 100 km: σ3 m → < 100 m, σ6 m → < 250 m.

### 3.7 Unit vectors (shared by SQL tests and the Dart parity test)

All along the meridian lng 16.6 from lat 49.2. Δlat 0.001° = 0.1111949 km (R = 6371). t0 = 1792000000. Points are `[lat, lng, ts, kmh]`; each case is a fresh state with `legacy = false` unless noted.

Expectations are `_ride_stats_v2` outputs for the vector, not ride-level values: no avg floor, and the first point's kmh is never a max candidate.

| ID | Input | Expected |
|---|---|---|
| V1 | 4 pts, Δlat 0.001, dt 8 s, kmh 50 | dist 0.334 · moving 24 · gap 0 · pause 0 · max 50.0 |
| V2 | 6 pts, Δlat 0.0001 (11.1 m), dt 10 s, kmh 4 (walking) | dist 0 · moving 0 |
| V3 | 6 pts, Δlat 0.0005, dt 60 s, kmh 0 (drift, v 3.3) | dist 0 · moving 0 |
| V4 | 4 pts, Δlat 0.001, dt 10 s, kmh 0 (no Doppler, v 40) | dist 0.334 · moving 30 · max 0 · nodop_max 0 (dt < 30) · state.has_dop false |
| V5 | p t0, q t0+3600 kmh −1 Δlat 0.0001 | pause 3600 · dist 0 |
| V6 | p t0, q t0+7200 Δlat 0.009 (1.0 km, v 0.5) kmh 30 | pause 7200 (inferred, not gap) · dist 0 |
| V7 | p t0, q t0+240 Δlat 0.02 (2.224 km, v 33.4) kmh 60 | gap 240 · dist 0 |
| V8 | p t0, q t0+240 Δlat 0.0005 kmh 0 | all zero (stop) |
| V9a | 3 pts, dt 5 s, Δlat 0.000625 (69.5 m, v 50.0); kmh 50, 50, 120 | moving 10 · max 50.0 (120 > 1.5·50+20 = 95 → rejected) |
| V9b | same with the last kmh 90 | max 90.0 |
| V10 | p, q dt 5 Δlat 0.004 (444.8 m, v 320) kmh 60 | all zero (jump) |
| V11 | legacy=true: m0, m1 (dt 8, Δ0.001, kmh 50); w1..w8 (dt 60, Δ0.0006, kmh 4); m2, m3 (dt 8, Δ0.001, kmh 50) | (m1,w1) is MOVING (dop 50, v 4.0); w-pairs NON-MOVING, `still_from = w1.ts`; at (w8,m2) still-run closes → pause 420 · trims `[[w1.ts, w8.ts]]` · moving 84 · dist 0.400 |
| V12 | moving pairs 21:00–21:30 Prague, explicit pause to 07:00 next day, moving 07:00–07:30 | 2 stages · pause 34 200 · days 2 |
| V13 | moving, explicit pause 12:00–13:00 Prague, moving | 1 stage · stage `ps` 3600 |
| V14 | flat alt alternating 100/110 on 30 moving pairs (Δlat 0.001) | gain 0 (EMA oscillates 104.3–105.7, never ≥ ref + 6) |
| V15 | alt 0, 2, 4 … 60 on 31 points, 30 moving pairs | gain 54 (EMA lag; ±1) |

Exact km values: T1 computes them in SQL and copies them into the Dart fixture `test/rides/fixtures/stats_vectors.json` (`{id, points, legacy, expect:{dist_km, moving_sec, gap_sec, pause_sec}}`) for the parity test (§16.2).

---

## 4. Server functions (T1)

General rules:
- `plpgsql SECURITY DEFINER SET search_path = public`.
- Existing names: `CREATE OR REPLACE` with the **identical** signature and defaults.
- New public RPCs:
  ```sql
  revoke all on function … from public, anon;
  grant execute on function … to authenticated, service_role;
  ```
- New internal helpers: `revoke all … from public, anon, authenticated` (Supabase default privileges grant EXECUTE otherwise).
- No new parameter on any existing name. No overloads.

### 4.1 `_ride_stats_v2(p_seg jsonb, p_state jsonb, p_stages jsonb) returns jsonb` — NEW internal, STABLE

- `p_seg[0]` may be the stored context point. Pairs are processed per §3.2.
- Returns:
  ```json
  {"dist_km": numeric(3 dec), "moving_sec": int, "gap_sec": int, "pause_sec": int,
   "gain_m": int, "max_kmh": numeric(1 dec), "nodop_max_kmh": numeric,
   "trims": [[f, t], ...], "state": {...}, "stages": [...]}
  ```
- `_ride_stats(p_track jsonb)` (existing, same signature) becomes a wrapper with legacy state. It returns today's keys `dist_km, moving_sec, idle_sec, gap_sec, gain_m, max_kmh`, where `idle_sec` = Σ dt of STOP + NON-MOVING + JUMP pairs.

### 4.2 `_ride_append_core(p_ride_id uuid, p_points jsonb) returns jsonb` — NEW internal

The caller holds `FOR UPDATE` on a recording ride.

1. **Context.**
   - `r` = the ride row;
   - `ret` = `bookings.returned_at` when `r.booking_id` is set;
   - `last` = last stored track element; `last_ts` = its ts.
2. **Filter** the points (order kept; `with ordinality`). Drop:
   - non-arrays, or lat/lng null;
   - ts present and `ts < epoch(started_at) − 3600` → `stale++`;
   - ts present and (`ts < max(last_ts, previous kept ts)` or (`ts = last_ts` and lat/lng equal to `last`)) → `dup++` (retry-safe; fixes double counting when a response was lost);
   - `ret` not null and ts `> epoch(ret) + 120` → `after_return++`.
3. **Nothing kept:**
   - `after_return > 0 and now() > ret + 120 s` → `_ride_finalize(r.id, least(greatest(coalesce(r.last_fix_at, r.started_at), r.started_at), ret))`, return `{"booking_ended": true}`;
   - otherwise return the current values plus `dropped_stale: stale > 0` (today's key) and `dropped`.
4. **Armed reset** (only `pause_aware`, `moving_sec < 60` and `distance_km < 0.2`). If a kept point has `kmh < 0`, let `i0` be its index:
   - `started_at := least(now(), to_timestamp(kept[i0].ts))`;
   - `track := '[]'`, `last := null`;
   - `distance_km`, `moving_sec`, `idle_sec`, `gap_sec`, `pause_sec`, `elevation_gain_m` := 0, `max_speed_kmh := null`;
   - `stages := '[]'`, `stats_state := '{}'`;
   - `start_lat/lng := kept[i0]`;
   - `kept := kept[i0..]`.
5. **Stats:**
   ```
   st := _ride_stats_v2((last ? [last] : []) || kept,
                        coalesce(stats_state,'{}') || {"legacy": not pause_aware},
                        stages)
   ```
6. **Track:**
   - `track := track || kept`;
   - remove points with `f < ts < t` for each `st.trims`;
   - `cap := least(12000, 4000 + 2000 * greatest(0, jsonb_array_length(st.stages) − 1))`;
   - `track := _ride_track_cap(track, cap)`.
7. **Update the row:**
   - `distance_km`, `moving_sec`, `gap_sec`, `pause_sec`, `elevation_gain_m` += the batch values;
   - `stats_state := st.state`, `stages := st.stages`;
   - `last_fix_at` = last kept point ts with today's sanity clamp;
   - `end_lat/lng`, `start_lat/lng := coalesce(...)` as today;
   - `idle_sec`, `duration_min`, `avg_speed_kmh` per §3.4; `max_speed_kmh` per §3.3.
8. **Return:**
   ```json
   {"success": true, "points": <track len>, "distance_km": round(km,1), "moving_sec", "idle_sec",
    "gap_sec", "pause_sec", "stages_n", "dropped", "now": epoch(now())}
   ```

### 4.3 `_ride_track_cap(p_track jsonb, p_max int default 4000)` — same signature, new algorithm

Port of `pg/capproto.sql`:
- `n ≤ p_max` → return the track unchanged.
- Otherwise spacing `D = 0.02 km · 2^k`, the smallest k with `L / D ≤ 0.85·p_max` (L = path length).
- Keep:
  - the first and last point;
  - a point whose accumulated distance since the last kept point is ≥ D;
  - both edges of a time jump > 180 s;
  - every point with `kmh < 0` and its predecessor.
- Non-arrays are dropped.
- If the result is still > `p_max` → fallback every-k-th, keeping all edges.
- Must be O(n): build with `jsonb_agg` over a keep-flag, not repeated `||`. **Perf:** ≤ 50 ms per call at 12 000 points on the test PG.
- `admin_booking_live_ride` (1200) inherits it.

### 4.4 `append_ride_track(p_ride_id uuid, p_points jsonb, p_max_speed_kmh numeric default null)` — same signature

1. Auth → `not_authenticated`.
2. Non-array points → `points_required`.
3. Lock → not found → `ride_not_found`.
4. Not recording → `{success:false, error:'ride_finished', finished:true}` (today).
5. `res := _ride_append_core(...)`:
   - `res.booking_ended` → return `{success:false, error:'ride_finished', finished:true, reason:'booking_ended'}`;
   - else return `res`.
6. `p_max_speed_kmh` is ignored (§3.3).

**No new error code.**

### 4.5 `finish_user_ride(p_ride_id uuid, p_points jsonb default null, p_name text default null)` — same signature

1. Auth; lock.
2. Not found → `ride_not_found`.
3. Not recording → return `_ride_finalize` stored values (`already_finished:true`), as today.
4. Non-empty points → `_ride_append_core`. If the result is `booking_ended`, the ride is already closed → return the finalize JSON.
5. Name: `nullif(left(trim(p_name),120),'')` when non-empty.
6. `end := now()`; booking with `returned_at < end` → `end := greatest(returned_at, started_at)` (today).
7. `_ride_finalize(id, end)` and return its JSON.

### 4.6 `_ride_finalize(p_ride_id uuid, p_ended_at timestamptz default null)` — same signature, REVOKE kept

1. Already closed → stored values plus `pause_sec`.
2. `end := coalesce(p_ended_at, last_fix_at, updated_at, now())`.
3. If `last_fix_at` is not null → `end := least(end, last_fix_at + interval '120 seconds')`. This fixes the late Stop and cron closes.
4. Legacy with `stats_state->>'still_from'` not null and `epoch(end) − still_from ≥ 300`:
   - `end := to_timestamp(still_from)`;
   - remove track points with `ts > still_from`.
5. `end := greatest(end, started_at)`.
6. km fallback as today; `km < 1 → DELETE` (as today).
7. Values:
   - `elapsed = end − started_at`;
   - `active = greatest(60, elapsed − pause_sec)`;
   - `idle = greatest(0, active − moving − gap)`;
   - `duration_min = greatest(1, round(active/60))`;
   - `avg` = `km / moving` (moving ≥ 60), else `km / (active − gap)` when > 0; `nullif(least(..., 200.1), 200.1)` as today;
   - `max = greatest(max, avg)`.
8. Close the last stage: `t := least(t, epoch(end))`.
9. Name fallback (Prague dates of `started_at`, `end`):
   - same date → `DD.MM.YYYY`;
   - same year → `DD.MM.–DD.MM.YYYY`;
   - else `DD.MM.YYYY–DD.MM.YYYY`.
10. Final `_ride_track_cap(track, cap)`; start/end `user_ride_points` as today.
11. Return today's keys plus `pause_sec` and `days` (§3.5).

### 4.7 `start_user_trip(p_booking_id uuid) returns jsonb` — NEW public (no DEFAULT; the client always passes the key, possibly null)

```
if auth.uid() is null → {success:false, error:'not_authenticated'}
v_now := now()
if p_booking_id is not null:
   b := bookings where id = p_booking_id and user_id = auth.uid()
   if not found or b.status not in ('reserved','active') or b.returned_at is not null
      → {success:false, error:'booking_inactive', now: epoch(v_now)}       -- no ride created
open := open ride of the user FOR UPDATE; last := greatest(coalesce(last_fix_at, started_at), updated_at)
if open:
   if open.booking_id is not distinct from p_booking_id
      and (p_booking_id is not null or last > v_now - interval '72 hours'):
        update set pause_aware = true            -- adoption (also of a legacy ride)
        → resumed JSON
   else _ride_finalize(open.id, case when open booking returned
                                     then least(last, returned_at) else last end)
insert user_rides(user_id, booking_id = p_booking_id, moto_id/moto_name from the booking, source 'auto',
                  pause_aware true, track '[]', stats_state '{}', stages '[]', is_recording true)
  -- NO date matching (fixes the manual ride on a rental day labelled as rental)
  exception when unique_violation → re-select the open ride → resumed JSON
→ {success:true, id, resumed:false, booking_id, moto_name, pause_aware:true, started_at,
   distance_km:0, moving_sec:0, pause_sec:0, stages_n:0, now: epoch(v_now)}
```

Resumed JSON:

```json
{"success": true, "id": "...", "resumed": true, "booking_id": "...", "moto_name": "...",
 "pause_aware": true, "started_at": "...", "distance_km": ..., "moving_sec": ...,
 "pause_sec": ..., "stages_n": ..., "now": ...}
```

### 4.8 `start_user_ride(p_booking_id uuid default null, p_lat double precision default null, p_lng double precision default null)` — same signature

Only the open-ride branch changes. `last` is computed as today. The open ride is resumed (`{success, id, resumed:true}`) when:

| Open ride | Rule |
|---|---|
| has a booking that is active (`status in (reserved, active)` and `returned_at is null`), and `p_booking_id` is null or equal | resume at **any age** (4.1.3 rental never splits) |
| `pause_aware` and no booking | resume if `last > now − 72 h` |
| otherwise | resume if `last > now − 3 h` (today) |

Not resumed → `_ride_finalize(open, case when booking returned then least(last, returned_at) else last end)`. Creation is unchanged (date matching, first point from `p_lat/p_lng`, keys).

### 4.9 `close_stale_user_rides()` — same name, same cron job `*/15`

`last := greatest(coalesce(last_fix_at, started_at), updated_at)`.

| Ride | Close when | End |
|---|---|---|
| with `booking_id` (any client) | booking missing, or `status in ('completed','cancelled')`, or `returned_at < now() − 10 min`, or `end_date::date < (now() at time zone 'Europe/Prague')::date − 1`, or `started_at < now() − 60 days` | `least(last, coalesce(returned_at, 'infinity'))` |
| own, `pause_aware` | `last < now() − 72 h` or `started_at < now() − 30 days` | `last` |
| own, legacy | `last < now() − 3 h` or `started_at < now() − 36 h` (**unchanged**) | `last` |

Finalize clamps further (§4.6). Kept: batch of 500, per-ride exception block, return `{closed, discarded}`.

### 4.10 `set_user_rides_trip(p_items jsonb) returns jsonb` — NEW public

```
auth null → {success:false, error:'not_authenticated'}
p_items must be an array of 1..300 objects {id uuid, trip_id uuid|null, trip_name text|null}
   (bad shape / invalid uuid → {success:false, error:'bad_items'})
update user_rides set trip_id = i.trip_id, trip_name = nullif(left(trim(i.trip_name),120),'')
 where id = i.id and user_id = auth.uid()
→ {success:true, updated:n}
```

- Foreign or missing ids are skipped silently; the client compares `updated` with the count it sent.
- It is a dumb setter: all grouping logic lives in the client (§8).

### 4.11 `admin_booking_live_ride(p_booking_id uuid)` — same signature

Adds keys:
- `pause_aware`, `pause_sec`;
- `is_standing` = `is_recording and fix age ≥ 900 s and booking status in (reserved, active) and returned_at is null`.

`is_live` is unchanged.

### 4.12 Other functions

- `admin_finish_user_ride`, `get_my_rides`, `get_booking_rides`, `get_public_rides`, `update_user_ride`, `delete_user_ride`: bodies unchanged (they inherit the new keys via `_ride_json`).

**Feature flag (draft 01):**

```sql
insert into public.feature_flags (key, enabled, description, conditions)
values ('ride_autopause', true,
        'Automatická pauza záznamu jízdy (appka). Vypnutí = nahrává se bez auto-pauzy; ruční pauza zůstává.',
        '{"stop_min":5,"walk_min":3,"resume_kmh":20,"home_h":3,"long_h":48}')
on conflict (key) do nothing;
```

### 4.13 Drafts (`scratchpad/rides/sql/`)

No `BEGIN`/`COMMIT`: deploy runs `psql --single-transaction`. Every file ends with `notify pgrst, 'reload schema';` and must apply twice cleanly.

| File | Content |
|---|---|
| `01_rides_columns.sql` | §2.1 columns, constraint, index, comments, feature flag |
| `02_rides_stats_core.sql` | `_ride_prague_night`, `_ride_stats_v2`, `_ride_stats` wrapper, `_ride_track_cap` |
| `03_rides_append_finish.sql` | `_ride_append_core`, `append_ride_track`, `finish_user_ride`, `_ride_finalize`, `_ride_json` |
| `04_rides_start_cron.sql` | `start_user_trip`, `start_user_ride`, `close_stale_user_rides`, `admin_booking_live_ride` |
| `05_rides_trip_group.sql` | `set_user_rides_trip` |
| `06_rides_backfill.sql` | **optional, owner choice** — see below |

`06_rides_backfill.sql` applies to closed rides with `pause_aware = false`, `stats_state is null` and ≥ 2 timed points. From the stored track (pause/gap edges are kept by the cap) it recomputes:
- `pause_sec` = Σ dt of pairs with `dt ≥ 300` and not (`v ≥ 15` and `d > 0.3`), `dt < 30 d`;
- `gap_sec` = Σ dt of pairs with `dt > 180`, `v ≥ 15` and `d > 0.3`;
- `idle_sec`, `duration_min` per §3.4 using `ended_at`.

It leaves km, moving, max and elevation unchanged and sets `stats_state = '{"backfill":1}'` (idempotency marker).

**Commit-time names** (after owner approval, renamed in this order): `<date>_user_rides_pause_a.sql` … `_f.sql`. Pick a date prefix that sorts after every migration in `main` at commit time.

### 4.14 STATE docs

Do not edit `SUPABASE_BACKEND_STATE_*.md`. T1 writes exact patch text into `scratchpad/rides/STATE_PATCH.md`:
- STATE_1: `user_rides` row (new columns, `duration_min` meaning, cap);
- STATE_2: key columns;
- STATE_3: rows for `start_user_trip`, `set_user_rides_trip`, `_ride_stats_v2`, `_ride_append_core`, `_ride_prague_night`, and UPDATE notes for every changed function;
- STATE_5: cron rules, feature flag `ride_autopause`;
- STATE_6: changelog entry.

---

## 5. Client architecture (T2, shared, identical in both trees)

### 5.1 Files (`lib/features/routes/`; each new file ≤ ~5 000 tokens)

| File | Content |
|---|---|
| `ride_motion.dart` (new) | `RideFix`, `RideMotionConfig` (§6.1), pure `RideMotionDetector` (§6), `ridePointFromRideFix`, `rideIsMovingPair` (§3.2 rule 7 mirror) |
| `ride_pause_engine.dart` (new) | `RidePauseEngine`: owns the detector, held/pausePath/ring buffers, anchor, trip start, home/long guards, flagging. No I/O, no Riverpod. Returns `RideEngineStep{emit, phaseChanged, detach, logs}`. |
| `ride_session.dart` (new) | enums `RidePhase {riding, autoPaused, manualPaused}`, `RidePauseReason {start, stop, walk, silence, manual, home, long}`; `RideSessionMeta` (JSON v1, §5.3) + load/save/clear; `RideServerCaps` + load/save |
| `ride_server_api.dart` (new) | `startUserTrip`, `setUserRidesTrip`, `probeRideServerV2`, `classifyRideRpcError`, `RideAppendOutcome` parsing helper |
| `ride_flags.dart` (new) | `RideAutoPauseFlag {enabled, stopMin, walkMin, resumeKmh, homeH, longH}` + `fetchRideAutoPauseFlag()` (8 s timeout) + cache in caps |
| `ride_live_stats.dart` (new) | local delta km/moving of the unsent buffer, live formatting helpers, `rideDaysLabel(n, lang)` plural helper |
| `ride_location.dart` (changed) | `rideFixFromPosition(pos, {now, clockOffset})`; `ridePointFromFix` kept as a wrapper (tests); `rideLocationSettings` uses the new static texts `rpNotifTitle`/`rpNotifDefault`; `RideKeepAlive.notify(title, text)`, `notifyIdle(title, text)`, `cancelIdle()` (Android only, no-op elsewhere) |
| `ride_provider.dart` (changed) | `appendRideTrack` returns `RideAppendOutcome`; `startUserRide` unchanged |
| `ride_recorder.dart` (changed) | state fields + hook points only (§7). Net growth ≤ ~2 KB; everything else goes into the new files. |
| `ride_recorder_watcher.dart` (changed) | §7.6 |
| `core/cache_cleanup_service.dart` ⚠ (outside the owned set) | add `'mg_ride_session'`, `'mg_ride_caps'` to `_preserveKeys` (both trees, one line each) |

### 5.2 Public recorder contract (UI tasks T3/T4 code against this only)

```dart
// RideRecorderState — new fields (copyWith + clearRide reset them)
final RidePhase phase;               // meaningful only when recording; default riding
final RidePauseReason? pauseReason;  // null while riding
final DateTime? pausedSince;         // local time of the anchor (bike stopped / armed since)
final double liveKm;                 // server total from the last append + local delta of the unsent buffer
final int liveMovingSec;
final int liveStages;                // stages_n from the server (≥ 1); fallback 1 + local stage boundaries
final DateTime? tripStartedAt;
final String? notice;                // one-shot i18n key (§12), shown by the watcher, then consumeNotice()
final Map<String, String>? noticeArgs;
final bool autoPauseOn;              // ride_autopause flag as applied to this session

bool get isPaused        => recording && phase != RidePhase.riding;
bool get isArmed         => recording && phase == RidePhase.autoPaused && pauseReason == RidePauseReason.start;
bool get isManualPaused  => recording && phase == RidePhase.manualPaused;
bool get needsDecision   => isManualPaused && (pauseReason == RidePauseReason.home || pauseReason == RidePauseReason.long);
bool get canStop         => recording && manual;   // a rental ride ends at return (or via the auto switch)
bool get isRidingLive    => recording && phase == RidePhase.riding && !gpsLost;

// RideRecorderNotifier — new methods
Future<void> pause();                      // manual pause (own AND rental); local, cannot fail
Future<RideStartResult> resume();          // foreground only; same permission checks as startManualResult
Future<void> discardCurrent();             // detach + forget WITHOUT finish (used before deleting the recording ride)
void consumeNotice();
void setActiveBooking(String? bookingId);  // the watcher feeds the active picked-up rental (manual-start attribution)
Future<void> finishOwnForRental(String bookingId); // §7.6
// existing, unchanged semantics: startManual(), startManualResult(), ensureRecording(), setEnabled(),
// stop() (works in every phase), onAppResumed(), flush(), canRetryStop, points (diagnostics only)
```

UI phase mapping (both looks):

| Condition | Text key | Chip |
|---|---|---|
| `isRidingLive` | `rpPhaseRiding` | `rpChipRec` |
| `isArmed` | `rpPhaseArmed` | `rpChipArmed` |
| `autoPaused` (stop/walk/silence) | `rpPhaseAuto` + `rpSince` | `rpChipPaused` |
| `manualPaused` (manual) | `rpPhaseManual` + `rpSince` | `rpChipPaused` |
| `needsDecision` home | `rpPhaseHome` + `rpHintHome` | `rpChipPaused` |
| `needsDecision` long | `rpPhaseLong` + `rpHintLong` | `rpChipPaused` |
| `gpsLost` | existing `RideGpsLostBanner` | — |

### 5.3 Persistence

`mg_ride_session` (JSON, written on every phase change, after every successful flush, on start; removed on stop/forget):

```json
{"v":1,"ride":"uuid","booking":"uuid|null","manual":true,"proto":"trip|legacy",
 "phase":"riding|autoPaused|manualPaused","reason":"start|stop|walk|silence|manual|home|long",
 "since":1792000000.0,"anchor":[...],"last":[...],"start":[...],"off":0,
 "live":{"km":12.3,"mov":1234,"st":1,"at":1792000000},
 "notice":{"k":"rpTripContinuedNew","a":{"date":"6. 10. 2026"}}}
```

`mg_ride_caps` (JSON):

```json
{"trips":true,"at":1792000000,"ap":{"on":true,"stop":5,"walk":3,"resume":20,"home":3,"long":20},"apAt":1792000000}
```

- Existing keys `mg_ride_autorecord`, `mg_ride_rec_id`, `mg_ride_rec_buf`, `mg_ride_rec_manual` are unchanged. The buffer still holds points; the marker lives in index 3.
- Held points, ring and pausePath are not persisted (≤ minutes; losing them on a kill is acceptable).

### 5.4 Server capability and fallback

- `classifyRideRpcError(e)`:
  - `PostgrestException` with code `PGRST202`, `42883` or `42703`, or HTTP 404 on rpc → `missing`;
  - `SocketException`, `TimeoutException`, `http.ClientException`, `AuthRetryableFetchException` → `offline`;
  - anything else → `error`.
- **Probe:** `probeRideServerV2()` = `from('user_rides').select('pause_aware').limit(1)`.
  - ok → `trips = true`;
  - `missing` → `trips = false`;
  - offline → keep the cached value.
- **When to probe:** at start, at `onAppResumed` and after `start_user_trip` returned `missing`; throttled to once per 30 min.

**Start path:**
1. caps `trips != false` (or older than 30 min) → `startUserTrip(bookingId)`.
2. `missing` → caps `trips = false` → `startUserRide(bookingId: bookingId)` (legacy, as PR #2208, no lat/lng). Session `proto = legacy`.
3. `offline` → today's retry (`_needsServerRide`). **Never fall back on offline.**
4. `booking_inactive` → no ride. During a continuation: deliver the remaining buffer to the old ride id first (`_drainEndedRental`, §21.4), then `_forgetRide()` + log `ride_continue_no_booking` (`late` = points delivered). During a watcher start: nothing (the watcher stops; its Stop sends the buffer with `finish_user_ride`). Retry of an offline start (not the watcher's): same drain when `rideId` is known, then `_forgetRide()`.

**Upgrade:** when a probe flips caps to `trips = true` while the session is `proto = legacy` → call `startUserTrip(state.bookingId)`.
- Same id and resumed → `proto = trip`.
- A different id cannot happen for a live legacy ride except after a server close; handle it as a continuation.

**Fallback behaviour (old server):**
- pause, auto-pause and markers work locally; nothing is uploaded while paused;
- the server's 3 h / 36 h rules still split; continuation (§7.4) prevents loss for own rides too;
- trip UI is hidden because rides lack `pause_aware` (§8.1).

### 5.5 Clock offset

- `start_user_trip` returns `now`. With `t0`/`t1` = local time before/after the call: `off = now − (t0+t1)/2`.
- If `|off| ≤ 120 s` → `off = 0`. Store it in the session; log `clock_offset {sec}` when it is non-zero.
- Append responses (new server) carry `now`. Recompute the offset the same way and replace it when it differs by > 60 s.

`rideFixFromPosition(pos, now, off)`:
- `corrNow = now + off`;
- `t = pos.timestamp`;
- if `off != 0` and `|t − now| < 120 s` → `t = t + off` (the fix time follows the wrong phone clock);
- `age = corrNow − t`;
- existing rules: `age < −2 min or > 30 d` → `t = corrNow`; `age > 6 h` → drop.

On the old server `off = 0`, i.e. today's behaviour.

---

## 6. Detection (T2) — `RideMotionDetector` + `RidePauseEngine`

### 6.1 Constants (`RideMotionConfig`, defaults; ★ = overridable from `ride_autopause.conditions`)

| Name | Value |
|---|---|
| `goodAccM` / `usableAccM` | 25 / 50 m |
| `dopMaxSpeedAccMs` | 2.5 m/s |
| `walkMinKmh` / `walkMaxKmh` | 2 / 8 km/h |
| `slowKmh` | 12 km/h (≤ = slow; release needs 2 consecutive valid Doppler > 12 km/h ≤ `pairGapS` apart) |
| `pairGapS` | 15 s |
| `stopPause` ★ `stop_min` | 5 min |
| `walkPause` ★ `walk_min` | 3 min |
| `walkMinFixes` / `walkMinPathM` | 3 / 50 m |
| `slowRideAfter` / `slowRidePathM` / `slowRideMedianKmh` / `slowRideAvgKmh` | 2 min / 300 m / 8 / 9 km/h |
| `pendingMax` | 10 min |
| `rStill` | clamp(1.5 × median acc of the last 5 usable fixes, 40 m, 100 m) |
| `silenceS` | 180 s |
| `signalLostKmh` | 30 km/h |
| `rideThroughKmh` | 15 km/h |
| `silenceStillM` | 150 m |
| `resumeKmh` ★ `resume_kmh` | 20 km/h; `resumeAnchorM` 100 m |
| `resumeNoDopM` / `resumeNoDopWindowS` | 300 m / 60 s |
| `slowResumeKmh` / `slowResumeWindowS` / `slowResumeMinFixes` / `slowResumeAnchorM` | 12 km/h / 60 s / 4 / 300 m |
| `prerollStartKmh` / `prerollMaxS` / `prerollMaxFixes` | 8 km/h / 180 s / 60 |
| `flagMinPauseS` | 60 s |
| `restoreNearM` / `restoreMinPathM` / `pausePathMax` | 100 m / 150 m / 1200 (keep the start) |
| `killGapM` | 1000 m |
| `homeRadiusM` / `homeAfter` ★ `home_h` / `homeMinKm` | 500 m / 3 h / 10 km (own only; **notice only, GPS stays on**, single-stage trips, once per pause — §20) |
| `longPauseOwn` ★ `long_h` | **48 h** without contact (own only; 0 = off) — §20 |
| `cachedFixSlackS` | **150 s** (30 s + the 120 s band where the clock offset is not applied) — §20 |

`RideFix`: `ts` (corrected), `lat`, `lng`, `acc` (null if `!hasAccuracy`), `kmh` (valid Doppler or null), `alt` (filtered or null).
- good = `acc != null && acc ≤ 25`;
- usable = `acc == null || acc ≤ 50`.

### 6.2 Engine state

| Field | Meaning |
|---|---|
| `mode` | `riding \| pending \| paused` (`pending` is internal; the UI sees `riding`) |
| `anchor` | where the bike stopped: the first held point of the slow run, else `lastEmitted` |
| `lastEmitted` | last point put into the upload buffer (replaces the recorder's `_lastKept`) |
| `held` | `[pt]` |
| `slowSince` | ts |
| `pausePath` | `[pt]` (20 m chained from the anchor) |
| `ring` | `[RideFix]` (≤ 180 s, ≤ 60) |
| `lastFix` | last raw fix |
| `lastDop` | `(ts, kmh)` |
| other | `pausedSince`, `reason`, `restored`, `tripStart` (first emitted point of the session's ride), `own`, `autoPauseOn` |

### 6.3 Algorithm

```
onFix(f):
  if lastFix == null and f.ts < attachedAt − 30 s → ignore (cached fix)
  if lastFix != null and f.ts <= lastFix.ts → ignore
  if !autoPauseOn: p = point(f, lastEmitted); if p != null { if flagNext { flag p if p.ts − pausedSince ≥ flagMinPauseS; flagNext = false }; emit(p) }
                   lastFix = f; return       // kill-switch: today's behaviour (+ marker after a manual pause)
  if mode != paused and lastFix != null and f.ts − lastFix.ts > silenceS → silence(f) (may switch mode)
  switch mode:
   riding:  if isSlow(f) → mode = pending; slowSince = f.ts; held = []; anchor = null; addHeld(f)
            else emit(point(f, lastEmitted))
   pending: addHeld(f); if released(f) → emit(held...); held = []; mode = riding
            else evalPending(f.ts)
   paused:  ring.add(f); addPausePath(f); if resumeRule() → resume()
  lastFix = f; if f.kmh != null → lastDop = (f.ts, f.kmh)

isSlow(f): (f.kmh != null and f.kmh ≤ slowKmh)
        or (f.kmh == null and good(f) and good(lastFix) and dt ≥ 5 s and dist/dt ≤ slowKmh)
released(f): f.kmh > slowKmh and previous raw fix has kmh > slowKmh and ≤ pairGapS apart
addHeld(f): p = point(f, held.last ?? lastEmitted); if p != null: held.add(p); anchor ??= p
evalPending(now):                       // also called from onTick
  a = anchor ?? lastEmitted
  stationary: now − slowSince ≥ stopPause and every good fix since slowSince is within rStill of a  → pause(stop)
  walking:    now − slowSince ≥ walkPause and no valid Doppler > slowKmh since slowSince and path ≥ walkMinPathM
              and (≥ walkMinFixes valid Doppler with median in [walkMinKmh, walkMaxKmh]
                   or (no Doppler and path/time ≤ walkMaxKmh))                                       → pause(walk)
  slow ride:  now − slowSince ≥ slowRideAfter and path ≥ slowRidePathM
              and (median Doppler > slowRideMedianKmh or path/time > slowRideAvgKmh)                 → release
  timeout:    now − slowSince ≥ pendingMax → pause(dist(lastFix, a) ≤ silenceStillM ? stop : walk)
silence(f):  dt = f.ts − lastFix.ts; d = dist(lastFix, f); v = d/dt
  v ≥ rideThroughKmh → (pending → release held); continue as riding         // server: gap
  d ≤ max(rStill, silenceStillM): dt ≥ stopPause → pause(silence); else mode = pending, slowSince ??= lastFix.ts
  else → pause(walk)
pause(r):                                // automatic
  a = anchor ?? lastEmitted; if a is a held point → emit(a)
  r == walk ? pausePath = held minus a : drop held
  mode = paused; reason = r; pausedSince = a.ts; anchor = a; ring = []
onTick(now):                             // existing 90 s timer, + 30 s timer while pending
  riding and lastFix and now − lastFix.ts ≥ silenceS:
      lastDop.kmh < signalLostKmh → mode = pending; slowSince = lastFix.ts; anchor = lastEmitted
      else → nothing (signal lost; decided by silence() at the next fix)
  pending → evalPending(now) (no fix since ≥ silenceS after slow counts as stationary)
  paused and own and reason in {stop, walk, silence}:
      tripStart, dist(anchor, tripStart) ≤ homeRadiusM, now − pausedSince ≥ homeAfter, liveKm ≥ homeMinKm → guard(home)
  paused and own and longPauseOwn > 0 and now − pausedSince ≥ longPauseOwn → guard(long)
guard(r): step.detach = true; phase manualPaused; reason r   // stream cancel is allowed from background
resumeRule():
  (a) last two ring fixes have Doppler ≥ resumeKmh, ≤ pairGapS apart, the second ≥ resumeAnchorM from the anchor
  (b) two good fixes ≥ resumeNoDopM apart within resumeNoDopWindowS, the later ≥ resumeNoDopM from the anchor
  (c) in the last slowResumeWindowS: ≥ slowResumeMinFixes valid Doppler, median ≥ slowResumeKmh,
      last fix ≥ slowResumeAnchorM from the anchor
  (anchor null, i.e. armed before the first fix → the distance conditions are skipped)
resume():
  R = earliest ring fix of the contiguous run ending at the trigger with Doppler ≥ prerollStartKmh,
      else the first trigger fix
  base = anchor
  if reason == walk:
      i* = earliest index in pausePath with dist(pausePath[i*], R) ≤ restoreNearM
      if i* exists and pathLen(anchor → pausePath[0..i*]) ≥ restoreMinPathM:
          emit(pausePath[0..i*]) unflagged; base = pausePath[i*]; log tail_restore
  pts = ring fixes with ts ≥ R.ts → point(·, chained from base)
  flag pts[0] (kmh := -1) if pts[0].ts − base.ts ≥ flagMinPauseS
      and !(restored and dist(R, anchor) > killGapM)
  emit(pts); mode = riding; clear ring/pausePath/held; pausedSince = null; reason = null; restored = false
```

**Manual operations:**
- `pauseManual(now)`:
  - mode pending → emit the anchor if it is held; drop the rest;
  - `anchor = lastEmitted`, `pausedSince = anchor?.ts ?? now`;
  - reason `manual`, phase `manualPaused`, `detach = true`.
- `resumeManual()`: mode paused, reason `start` (armed), anchor and `pausedSince` kept (the pause continues until riding), `restored = false`.
  - With `autoPauseOn = false`: mode `riding` and `flagNext = true` (the first emitted point is flagged when ≥ 60 s after `pausedSince`).

**Starting:**
- `startArmed()` (watcher or manual start): mode paused, reason `start`, anchor null.
  - The first usable fix is emitted at once as **P0** (Velín sees the position) and becomes the anchor, `tripStart` and `pausedSince`.
  - With `autoPauseOn = false` the engine starts in `riding`.

**Stop:**
- `stop()` while pending → emit the anchor, drop held.
- While paused → emit nothing. The server ends at the last point + ≤ 2 min.

**Local max** (old-server `p_max`) uses the real Doppler before flagging.

### 6.4 Known limitations (documented, accepted)

- A taxi, bus, ferry or bicycle at ≥ 20 km/h resumes recording; manual pause avoids it.
- A crawl < 7 km/h Doppler lasting > 3 min pauses. Tail restore usually brings it back; the server does not count < 7 km/h as km.

---

## 7. Recorder integration (T2)

### 7.1 Hooks in `ride_recorder.dart`

| Hook | Change |
|---|---|
| `_onPosition` | Build the `RideFix`; `engine.onFix` → append `step.emit` to `_buffer`; update local max (real Doppler), `points` (diagnostics) and live delta; first emitted point after server confirmation → `flush()` (as today); `step.detach` → §7.3; phase changes → state + session save + notification (§10). |
| `_tick` | `engine.onTick(now)` before the existing logic; plus a 30 s `Timer` only while the engine is in pending. |
| `_start` | Load the flag (cache first, refresh async); create the engine `startArmed()`; server start per §5.4; resumed with the same id as the session → `engine.restore(meta, restored: true)`. |
| `_flushOnce` | Outcome handling §7.4; on ok update `liveKm/liveMovingSec/liveStages` from the response; save the session. |
| `stop()` | `engine.stopFlush()` first (pending → anchor); otherwise unchanged; clears the session. |
| `_restore()` | §7.2 |
| `onAppResumed()` | `manualPaused` → only `flush()`. `autoPaused` → re-attach only when `_sub == null \|\| _streamError != null \|\| quiet > 30 min`. Riding → as today. Then throttled flag refresh, probe/upgrade, `engine.onTick(now)`. |
| `_watchService` / `_onForeignStreamsClosed` / no-fix re-attach | Skipped in `manualPaused`. |
| `_forgetRide` | Also clears the session and the engine. |

### 7.2 Restore table

| Stored session | Action |
|---|---|
| manual + `manualPaused` (any reason) | `recording = true`, phase/reason/since from the session, no attach, keepAlive off |
| manual + `riding`/`autoPaused` | attach (as today); engine paused, reason `start`, anchor = `session.anchor ?? session.last`, `pausedSince` = session value (or anchor ts), `restored = true` |
| rental + `manualPaused` | `recording = true`, phase `manualPaused`, no attach. The watcher does nothing (`recording` is true); a rental end stops it. |
| rental + other | as today (the watcher → `_start` → `start_user_trip` resumed → `engine.restore(restored: true)`) |
| no session but `mg_ride_rec_id` (upgrade from an older build) | today's behaviour; engine starts paused/start with anchor null |

### 7.3 Detach (manual pause, home, long)

1. `flush()`.
2. `_detachStream()` (the FGS stops, `RideKeepAlive.set(false)`, the iOS blue pill disappears).
3. Phase `manualPaused` with the reason; save the session.
4. Log `pause` (manual) or `home_pause` / `long_pause`.
5. home/long on Android → `RideKeepAlive.notifyIdle(rpNotifIdleTitle, rpNotifIdleText)`.

`resume()`:
1. Same checks as `startManualResult()` (signed in, `GpsService.status`, `_ensurePreciseOnIos`); return the matching `RideStartResult`.
2. `_attachStream('resume_manual')`, `engine.resumeManual()`, `cancelIdle()`, phase `autoPaused`/`start`.
3. Log `resume` (manual).

### 7.4 Append outcomes

`RideAppendOutcome {result: ok|retry|closed|gone, distanceKm?, movingSec?, pauseSec?, stagesN?, serverNow?}`:
- `ride_finished` → `closed`;
- `ride_not_found` → `gone`;
- network → `retry`.

The columns are decided by `state.bookingId`, not by `manual`. A manual ride attributed to a picked-up rental behaves like a rental here: it never continues as an own ride after the return.

| Outcome | Booking set (auto or manual) | Own (no booking) |
|---|---|---|
| `closed` | continuation (today): `_continuation = true` → server start with the booking; `booking_inactive` → forget + stop (no junk ride) | **continuation:** new ride (`startUserTrip(null)` / fallback `startUserRide(null)`), engine keeps phase and anchor, notice `rpTripContinuedNew` (new server) or `rpTripContinuedNewOld` (old server), log `trip_continue {old, reason}`. Never a silent stop. |
| `gone` | continuation (as today) | `_forgetRide()` (deleted by the user) |

### 7.5 `discardCurrent()`

Detach, forget local state (buffer, session) **without** finish. Used by the ride detail before `delete_user_ride` on the recording ride. For a rental, the watcher then starts a fresh armed ride (expected, stated in the confirm text).

### 7.6 Watcher (`ride_recorder_watcher.dart`)

- Every build:
  - `n.setActiveBooking(activeBookingId)`;
  - manual start attributes the ride to that booking when present (keeps today's labelling, but only for picked-up rentals).
- `booking != null && rec.recording && rec.manual && rec.bookingId != booking && rec.isPaused` → `n.finishOwnForRental(booking)`. A manual ride already attributed to this rental is left alone.
  - `stop()`; on success `ensureRecording(booking)` + notice `rpOwnSavedForRental{date}`;
  - on failure retry via `canRetryStop`.
- Unchanged: `ensureRecording` (a no-op while `recording`, so a pause is never undone), the rental-ended stop branch (works in every phase), the manual failed-stop retry.
- **Notice display:** `ref.listen(rideRecorderProvider.select((s) => s.notice), …)` → `ScaffoldMessenger.maybeOf(context)?.showSnackBar` with `tr.trArgs(key, args)` (6 s), then `consumeNotice()`.

---

## 8. Trips (T3 implements, T4 consumes; shared, both trees)

### 8.1 Model (`ride_model.dart` changes)

- `UserRide` new fields:
  - `pauseSec`, `pauseAware`, `tripId`, `tripName`, `stages` (`List<RideStage>`);
  - `serverV2` = the json contains the key `pause_aware`;
  - per-point pause flags parsed from index 3 (`< 0`).
- `RideStage {DateTime from, to; double km; int movingSec, gapSec, pauseSec, gain; double? max; LatLng? a, b;}` with getters `idleSec` and `avgKmh`.
- Getters:
  - `days` (§3.5, local time; without stages: number of local dates from `startedAt` to `endedAt ?? lastFixAt` when `movingSec ≥ 300`, else 1);
  - `pauseCount` = segments whose `gapBefore.kind == pause`;
  - `activeMin` = `durationMin`.
- `_splitOnGaps` mirrors §3.2:
  - pair is a **pause** if `flag`, or (`dt > 180`, not (`v ≥ 15` and `km > 0.3`), `dt ≥ 300`);
  - pair is a **gap** if `dt > 180`, `v ≥ 15` and `km > 0.3`;
  - the 86 400 s condition is replaced by 30 days.
- `RideGap` gets `kind` (`gap|pause`).
- `hasGaps` = `gapSec > 0 || segments.any(kind == gap)`.

### 8.2 Grouping (`ride_trip.dart`, new)

```dart
String rideTripKey(UserRide r) => r.tripId != null ? 't:${r.tripId}'
    : (r.bookingId != null ? 'b:${r.bookingId}' : 'r:${r.id}');
sealed class RideListItem;  RideListItemRide(UserRide)  |  RideListItemTrip(RideTrip)
List<RideListItem> groupRides(List<UserRide> rides);   // groups of ≥2 → trip; ordered by newest member startedAt desc
class RideTrip { String key; List<UserRide> rides /*startedAt asc*/; String? explicitTripId; String? name;
  bool isRental /*b: key or common bookingId*/; UserRide aggregate; int days; DateTime from, to; }
String rideTripDefaultName(RideTrip t, AppTranslations tr);
// name || (isRental ? rpTripRental{moto} : rpTripDefault{dates})
```

**Aggregate:**
- id = leader (oldest) id; name = trip name;
- `distanceKm`, `movingSec`, `idleSec`, `gapSec`, `elevationGainM`, `durationMin` = Σ;
- `pauseSec` = Σ + Σ intervals between consecutive members (`endedAt_i` or `lastFixAt_i` → `startedAt_{i+1}`);
- `maxSpeedKmh` = max; `avgSpeedKmh` = Σkm / Σmoving;
- track/segments concatenated (member boundary = gap or pause by the silence rule);
- points concatenated; stages concatenated;
- `bookingId` only when common;
- `isRecording` = any member.

Sums always come from stored stats, never recomputed from thinned tracks.

### 8.3 Operations (`ride_trip_api.dart` → `set_user_rides_trip`)

Every operation captures an **undo map** `{id → (tripId, tripName)}` BEFORE the call. "Zpět" sends the map back.

| Op | Items sent |
|---|---|
| merge(selected items, name) | T = explicit `tripId` of the oldest selected explicit trip, else a NEW random key (`rideTripNewKey()`, UUID v4 from `Random.secure()`, never a ride id — fix:logic:r2); all members → `(T, name-or-null)` |
| split(trip) | every member → `(own id, null)` (also dissolves an implicit rental group) |
| rename(trip, name) | every member → `(explicitTripId ?? newKey, name)` |
| addTo(trip, ride) | ride → `(trip.explicitTripId ?? newKey, trip.name)`; for an implicit trip all members also get the explicit id |
| remove(ride) | ride → `(own id, null)`; when the ride's own id IS its trip key (trips made by dev builds before fix:logic:r2, key = leader id) → `(newKey, null)`, otherwise the ride would stay in the trip |

A trip key must never equal a member's id: `trip_id = own id` means "explicitly standalone", so with key = leader id "Vyjmout z cesty" on the oldest ride was a silent no-op (fix:logic:r2).

**Result:**
- `updated == count` → ok + `invalidate(myRidesProvider)` (+ `bookingRidesProvider`);
- `updated < count` → `rpTripPartial`;
- `missing` → `rpTripUnavailable`;
- offline/other → `rpTripFailed`.

**Visibility** (trip): `updateUserRide(visibility)` per member; any failure → `rpTripPartial`.

**Delete** (trip): a choice sheet:
- "Jen zrušit sloučení" → split;
- "Smazat i všechny jízdy" → confirm `rpTripDeleteQ` → for each member: `recording` → `discardCurrent()` first; then `deleteUserRide`.

**Merge entry is visible only when** `rides.any((r) => r.serverV2)` and there are ≥ 2 list items.

---

## 9. UI

General rules for every new control:
- ≥ 44 px targets; `Semantics(button: true, label: rpA11yPause|rpA11yResume)`;
- phase text in `Semantics(liveRegion: true)`;
- ping/pulse only when `isRidingLive` and not reduced motion (`MediaQuery.disableAnimationsOf` / `MgMotion`); a paused state shows a static ❚❚;
- every error and result has a message with what, why and how to fix (§12).

### 9.1 Old look (T3, BOTH trees; identical except existing v2 seams)

| Place | Change |
|---|---|
| `my_experiences_screen.dart` `_ridesSection` | Header chip by phase (`RideRecChip`). `_manualRideCard(...)` replaced by `RideRecControlsCard(onStartStop: <tree's toggle>)` (Android `toggleManualRide`, iOS `_toggleManualRide`). `for (r in rides) RideCard` → `...rideListWidgets(context, ref, rides)` (RideCard / RideTripCard) + row "🔗 `rpMerge`" when allowed (§8.3). |
| new `ride_rec_controls.dart` | `RideRecChip`, `RideRecControlsCard`, `RideNavRecChip` |
| `RideRecControlsCard`: idle | Today's "Zaznamenat vlastní jízdu" card unchanged (hidden during a rental recording, as today) |
| `RideRecControlsCard`: recording | Phase line + `rpSince`; live line `rpLiveLine` (+ `· rpDayN` when stages ≥ 2; Ø after ≥ 5 min moving) |
| `RideRecControlsCard`: buttons | [❚❚ `rpPause`] or [▶ `rpResume`] for own AND rental; in auto-pause (`rideIsAutoPaused`) the same button reads [`rpPauseGps`] (it also turns GPS off) and the status shows `rpAutoNoAction` (nothing to press); [■ `rideManualStop`] only when `canStop`. Rental: `rpRentalEndsHint` under the buttons. (fix:ui-old r1) |
| `RideRecControlsCard`: `needsDecision` | [▶ `rpResumeTrip`] [■ `rpEndSave`] |
| `RideRecControlsCard`: explainer | Collapsible "ⓘ `rpHowTitle`" → `rpHintAuto` (`rpHintManual` while manually paused) |
| new `ride_pause_actions.dart` | `Future<void> rideTogglePause(BuildContext, WidgetRef)`: pause → snackbar `rpToastPaused`; resume → `showRideStartResult` on failure, `rpToastResumed` on ok. Used by every place below and by v2. |
| `community_submit.dart` "Přidat" sheet (both looks in Android, old in iOS) | When recording: row "❚❚ `rpPauseRow`" / "▶ `rpResumeRow`" (auto-pause: `rpPauseGpsRow`, subtitle phase + `rpAutoNoAction`) above today's rows (also for a rental); Stop row (manual only) subtitle `rpStopRowPaused` while paused. The sheet scrolls in both looks (no overflow at 320×690 ×1.3). (fix:ui-old r1) |
| Old navigation | `RideNavRecChip` (shrink when not recording): "● REC {km}" only while really recording; "⏳ `rpNavArmed`" / "❚❚ `rpChipAuto`" / "❚❚ `rpNavPaused`" / "⚠ `rpChipNoGps`" otherwise (fix:ui-old r1) → tap → `showRidePauseSheet` (new `ride_pause_sheet.dart`: phase text, [Pozastavit/Pokračovat], [Ukončit] when `canStop`) |
| ⚠ `route_navigation_screen.dart` (outside the owned set, 1 line) | Android line ~1626: `if (MgV2.on(context)) const NavRecChipV2() else const RideNavRecChip(),`. iOS line ~1624: insert `const RideNavRecChip(),` before `if (_stops.isNotEmpty)`. |
| `ride_card.dart` | Date or range (`rideDateRange`); km · **v sedle** (`movingMin`, replaces total) · Ø · stops/photos · moto; chip `rpDaysLabel(days)` when days ≥ 2; recording badge by phase for the recording ride (`rideChipKey` + `rideRecTone`: "⏺ `rpChipRec`" / "⏳ `rpChipArmed`" / "❚❚ `rpChipAuto`" / "❚❚ `rpChipPaused`" / "⚠ `rpChipNoGps`"); `RideTripCard` uses the same badge when the trip contains the recording ride (fix:ui-old r1) |
| new `ride_trip_card.dart` (`RideTripCard`) | "🧳 {name}" (rental "🏍️"); line `{rpRides(n)} · {rpDaysLabel} · {km} · {v sedle}`; tap → trip detail |
| `ride_detail_screen.dart` | `_statsCard` → new `ride_stats_grid.dart` (§9.3); new `ride_stage_list.dart` (Etapy, stages ≥ 2); `rideGapNotice` → `rpGapNotice`; new "Cesta" row: member → "🧳 `rpTripPartOf`{name} ›" + text button `rpTripRemove` (undo snackbar); non-member and server supports trips → text button `rpTripAddTo` → merge screen with this ride preselected; deleting the recording ride → confirm `rpDeleteRecordingOwnQ`/`rpDeleteRecordingRentalQ` → `discardCurrent()` → delete |
| `ride_map.dart` | Pause connector: none when `km ≤ 0.3`, dashed blue-grey when moved; gaps stay dotted grey; legend `rpPauseLegend` only when a moved pause exists |
| `ride_share.dart` | Text: name · range · days (≥ 2) · km · v sedle (not total). Trip variant: "🧳 {name}\n{range} · {days} · {km} · {time} v sedle\n" + today's footer. |
| `ride_booking_section.dart` | ≥ 2 rides → header line `rpBookingTotal`; with a group → one RideTripCard + members |
| new `ride_merge_screen.dart` | Header `rpMerge` + `rpMergeHint`; list of items (trip = one item) with 44×44 checkbox, `Semantics(checked)`; bottom bar [`rpMergeBtn`{n}] disabled below 2 (tap → `rpMergeMinTwo`); name dialog `rpMergeNameTitle` (hint `rpMergeNameHint`, empty = default); success snackbar `rpMergeDone` + `rpUndo`. Server without trips (no ride has `pause_aware`): note `rpTripUnavailable`, checkboxes and the button disabled, no preselection (fix:ui-old r1). Button / dialog action labels stay on one line (scale down, `rideFitLabel`). |
| new `ride_trip_detail_screen.dart` | Header name + range + days chip; map of the aggregate; stats grid (aggregate); Etapy (concatenated); `rpTripMembers` → RideCards; actions: `rpTripRename`, share, visibility switch (`rpTripVisibilityOn/Off`), `rpTripSplit` (confirm `rpTripSplitQ`, then `rpTripSplitDone` + Zpět), `rpTripDelete` (choice sheet). Android: `MgV2.on` seam → `TripDetailViewV2` (T4). |
| `ride_start_feedback.dart` | Add `showRidePauseFeedback(msg, tr, {paused})` used by `rideTogglePause` |

Helpers in `ride_card.dart`:
- `rideDateRange(a, b)`: same day `6. 10. 2026`; same month `6.–11. 10. 2026`; same year `28. 9. – 3. 10. 2026`; else full both;
- `rideDuration` unchanged.

### 9.2 v2 (T4, ANDROID ONLY)

| File | Change |
|---|---|
| `home/v2/home_record_row_v2.dart` | Text by phase: "{rpPhaseRiding} · {km}" / "{rpChipPaused} · {rpSince}" / `rpChipArmed`; trailing 44 px icon button pause/resume (`rideTogglePause`); stop confirm stays (manual); idle unchanged |
| `routes/v2/record_dock_v2.dart` | `_LiveBar`: phase label + km; trailing **pause/resume** disc (44 px, every recording) + `_StopButton` (manual); paused tone neutral (no red ping); `_liveLine` by phase. Split `trasyConfirmStopRide` into `trasyConfirmStop(context) → Future<bool>` + stop; the confirm body appends `v2RpStopBody2` while paused. |
| `routes/v2/rides/recorder_parts_v2.dart` | `RecorderLiveCardV2`: status `v2RpStatusRec/Paused/Armed/Home/Long`; the "N bodů" chip is replaced by chips km · `v2RpChipRiding` · `v2RpChipAvg` (after ≥ 5 min) · `v2RpChipDay` (≥ 2) · GPS; "od HH:MM" while paused; new `RecorderPauseButtonV2` (white 56 px, `v2RpPauseCta`/`v2RpResumeCta`) |
| `routes/v2/rides/recorder_screen_v2.dart` | Primary CTA toggles pause/resume; secondary stop (manual); `rpRentalEndsHint`; explainer row (info icon → `rpHintAuto`); `needsDecision` card (`rpResumeTrip`/`rpEndSave`). **r1 fix:** confirm first, then `_run(stop)`; no spinner while the confirm is open. |
| `routes/v2/route_nav_skin_v2.dart` | `NavRecChipV2`: "● `v2RpNavRec`" / "❚❚ `v2RpNavPause`", tappable 44 px → v2 sheet (new `v2/rides/ride_pause_sheet_v2.dart`) |
| `routes/v2/rides/moje_tabs_v2.dart` | `MojeRecordRowV2`: ping only when riding, static pause glyph, phase text |
| `routes/v2/rides/moje_summary_v2.dart` | Ride count = grouped items (`groupRides`); km sums unchanged |
| `routes/v2/rides/moje_cards_v2.dart`, `moje_lists_v2.dart`, `ride_card_v2.dart` | Grouped list; new `ride_trip_card_v2.dart` (`v2RpTripCard`); range + days chip; "v sedle" instead of total; row `v2RpMergeRow` → `RideMergeScreen` (old look inside the v2 frame) |
| `routes/v2/rides/ride_detail_parts_v2.dart`, `ride_detail_view_v2.dart`, `ride_track_sketch_v2.dart` | Stats grid per §9.3; new `ride_stages_v2.dart`; sketch draws pause connectors per §9.1; optional params `tripName`, `onOpenTrip`, `onTripAction` for the trip row. **r1 fix:** below 360 dp move share/edit/delete under the title (or a ⋯ menu); captions 2 lines with scale-down (de/pl). |
| new `routes/v2/rides/trip_detail_view_v2.dart` | v2 trip detail composed of the existing v2 parts (stats grid, sketch, stages, member cards) plus trip actions |

Keep any r1 fix already present in the tree. Do not touch catalog, booking, home (except the record row), profile, reservations, payments or non-recording routes.

### 9.3 Stats per surface

| Surface | Shows |
|---|---|
| Ride card | range · km · v sedle · Ø · days chip · stops/photos · moto |
| Detail grid (old + v2) | `rideStatDistance` · `rideStatMoving` (v sedle) · `rideStatAvg` · `rideStatMax` · `rideStatClimb` · `rpStatOnRoad` (duration_min) · `rideStatIdle` (zastávky) · `rpStatPauses` (`{n}× · {time}`, only when > 0) · `rideStatGap` (only when > 0) · days (≥ 2; value `rpDaysOne/Few/Many` „5 dní", caption `rpStatDaysCap`) · photos · stops · start → end. `rideStatPoints` is removed from the app (it stays in Velín). Old look (fix:ui-old r1): labels never break inside a word nor get „…" (`RideFitText`, `ride_fit_text.dart`: whole label scales down to fit its longest word / 3 lines); the grid uses 3 columns only when every label fits its tile at ≥ 85 % size, otherwise 2 columns (narrow phone, large text, de/nl/pl). Ride / trip detail titles: 2 / 3 lines, word-fit (min 60 %), „…" only for very long rider-given names. Live line keeps number + unit together (NBSP, „km⁠/⁠h" with word joiners). |
| Etapy row | `rpStageDay`{n} · weekday date · km · {time} v sedle · Ø · max · ⛰ gain (v2 without emoji) |
| Live (card, dock, home row, nav chip, notification) | phase · km · v sedle · Ø (≥ 5 min moving) · `rpDayN` (≥ 2) · `rpSince` while paused · GPS state |
| Trip card / detail | aggregate (§8.2), days, range, members, Etapy |
| Share | name · range · days · km · v sedle |

---

## 10. Android native (T2; Android tree only)

`RideEngineKeeper.kt`, channel `cz.motogo24/ride`, new methods:

- **`notify {title, text}`**
  - Only when `GeolocatorLocationService` runs in the foreground (reuse the keeper check) and `SDK_INT ≥ 26`.
  - Build `Notification.Builder(ctx, "geolocator_channel_01")`:
    - small icon `resources.getIdentifier("ic_launcher","mipmap",pkg)`;
    - `setOngoing(true)`, `setOnlyAlertOnce(true)`;
    - contentIntent = launch intent (`FLAG_IMMUTABLE | FLAG_UPDATE_CURRENT`).
  - Post with `notify(75415, …)`, which replaces the geolocator FGS notification.
  - Any exception → `result.error` → Dart logs `notif_failed`.
- **`notifyIdle {title, text}`**: a normal auto-cancel notification, id 75416, same channel, tap opens the app. **`cancelIdle`** cancels 75416.
- **`keepAlive(false)`**: when the service is not running, defensively `cancel(75415)`.
- **Optional `battery` → `{pct, charging}`**: when present, Dart adds it to the `phase` log.

Dart calls `notify` on every phase change, and while riding at most every 5 min when the text changed. Only with `_ownStream`.

| Phase | Title | Text |
|---|---|---|
| static (listen) | `rpNotifTitle` | `rpNotifDefault` |
| riding | `rpNotifRidingTitle` | `rpNotifRiding` {km, time} |
| armed | `rpNotifArmedTitle` | `rpNotifArmed` |
| autoPaused | `rpNotifPausedTitle` | `rpNotifPaused` {time} |
| manualPaused | service stopped | — (home/long: `notifyIdle`) |

iOS: none (the blue pill stays during auto-pause; disappears in manual pause).

---

## 11. Velín (T5; `velin/src`; Czech UI)

| File | Change |
|---|---|
| `lib/rideTrack.js` | `splitTrackOnGaps` mirrors §3.2: `kmh < 0` → pause; silence `dt > 180`: `v ≥ 15` & `d > 0.3` → gap, else `dt ≥ 300` → pause; bad time 30 d. Segments carry `kind`. New `trackPauses(track)` → `{count, sec}`. New `rideRecState(ride, now)` → `live` (fix < 15 min) / `standing` / `stuck`. `stuck` when the last fix is older than 3 h (legacy own / server without pause columns), 24 h (legacy rental), 72 h (pause-aware own); a pause-aware **rental** is never `stuck` from age alone while its booking runs (server closes it only when the booking ends): `rideRecState(ride, now, rentalHoldsRide(booking))` — booking known (Mapa a poloha) → `standing` until the booking is returned (+30 min cron grace) / completed / cancelled / 2 days past `end_date`, then `stuck`; booking unknown (list, modal) → `stuck` only after 7 days (`RENTAL_STUCK_SEC`). Any rental whose booking is over but still recording → `stuck` (hint "při dalším úklidu"). Otherwise `standing`. |
| `pages/TrasyJizdy.jsx` | `RIDE_LIST_COLS` + `pause_sec, pause_aware, trip_id, trip_name` (the legacy fallback list strips them). Badges: `● Nahrává se` (live), `⏸ Stojí od {čas}` (standing), `Záznam visí` (stuck). Labels: "⏱️ Na cestě (bez pauz)" for `duration_min`, "⏸️ Zastávky" for `idle_sec`, new "🛌 Pauzy" `pause_sec`. Badge `🧳 {trip_name}` when set. Filter "Nahrávané" includes standing; sub-filter "Stojí". |
| `pages/TrasyJizdaModal.jsx` + new `TrasyJizdaEtapy.jsx` | Grid: Ujeto · Čas jízdy (v sedle) · Na cestě (bez pauz) · Zastávky · Pauzy (n×, from `trackPauses`) · Bez signálu · Ø · Max · Nastoupáno · Dny · Body stopy · Start → Konec. Load `stages` with the track; Etapy table (Den, datum, km, v sedle, Ø, max, ⛰, pauzy). Standing box: "Záznam je pozastavený — motorka stojí od {čas} (appka nahrává jen při jízdě)." The "Ukončit záznam" button stays for standing and stuck. |
| `pages/TrasyJizdaMapa.jsx` | Pause connector: none (≤ 300 m) or dashed blue-grey with tooltip "pauza {od}–{do}"; gaps unchanged |
| `pages/booking/BookingLiveMap.jsx` | When `is_standing` (or pause-aware with fix ≥ 15 min): "Motorka stojí od {čas} — appka nahrává jen při jízdě; poloha je místo, kde zastavila." No "Záznam visí" while the booking runs (pause-aware ride; booking state from RPC `booking_status` + booking `returned_at`/`end_date` via `rentalHoldsRide`); after the booking ended a still-recording ride is "visí". Labels as in the list. |
| `lib/rideDiag.js` | Labels for actions in §13 |

Velín must tolerate missing columns (42703 fallback) and deploy **together with the SQL** (otherwise paused rentals read as "visí" after 3 h).

---

## 12. i18n

**Shared old-UI keys (both trees).** New files `lib/core/i18n/translations_ext_46_rides_pause_a.dart` (cs, en), `_b.dart` (de, es), `_c.dart` (fr, nl), `_d.dart` (pl, uk). Maps `translationsExt46RidesPauseA..D`. Keys have the `rp` prefix, no `v2` prefix (the v2 i18n test forbids `v2` keys outside `ext_5*`).

**v2 keys (Android only).** `translations_ext_59_v2_rides_pause.dart`, map `translationsExt59V2RidesPause`: `v2` prefix, no emoji, ≤ 18 500 bytes (split `_a/_b` if larger).

Before creating the files, re-check that 46 and 59 are still free. Register each file in `translations.dart` with minimal Edits (one import line + one list line per file; never rewrite the file; another workflow edits it concurrently).

All 8 languages are required: natural wording, Czech *tykání*, informal in de/es/fr/nl/pl/uk (du / tú / tu / je / ty / ти). Plurals via `rpDaysLabel(n, lang)` and `rpRidesLabel(n, lang)`:
- cs: 1 / 2–4 / else (21 → "21 dní");
- pl and uk: last-digit rules (12–14 → many);
- others: one / other (fr: 0 and 1 → one).

### 12.1 Shared keys (cs / en)

**Controls, phases, hints**

| Key | cs | en |
|---|---|---|
| rpPause | Pozastavit | Pause |
| rpResume | Pokračovat | Resume |
| rpPauseRow | Pozastavit záznam jízdy | Pause ride recording |
| rpResumeRow | Pokračovat v záznamu jízdy | Resume ride recording |
| rpResumeTrip | Pokračovat v cestě | Continue the trip |
| rpEndSave | Ukončit a uložit | End and save |
| rpChipRec | Nahrávám | Recording |
| rpChipPaused | Pozastaveno | Paused |
| rpChipArmed | Čeká na rozjezd | Waiting to ride |
| rpChipAuto / rpChipNoGps / rpNavArmed (fix:ui-old r1, `translations_ext_47_rides_uifix.dart`) | Auto-pauza / Bez GPS / Připraveno | Auto-pause / No GPS / Ready |
| rpPhaseGpsLost | Záznam stojí — poloha není dostupná | Recording on hold — location unavailable |
| rpPauseGps / rpPauseGpsRow / rpA11yPauseGps | Vypnout GPS / Vypnout GPS (ruční pauza) / Vypnout GPS a pozastavit záznam ručně | Turn off GPS / … (manual pause) / … |
| rpAutoNoAction | Nic nemačkej — jakmile se rozjedeš, nahrávám dál sám. | No need to tap anything — I’ll carry on as soon as you ride off. |
| rpStopRowPaused | Záznam je pozastavený — klepnutím cestu ukončíš a uložíš. | Recording is paused — tap to end and save the trip. |
| rpPhaseRiding | Nahrávám jízdu | Recording your ride |
| rpPhaseArmed | Připraveno — nahrávat začnu, jakmile se rozjedeš | Ready — recording starts as soon as you ride off |
| rpPhaseAuto | Stojíš — záznam je pozastavený | You've stopped — recording is paused |
| rpPhaseManual | Záznam je pozastavený | Recording is paused |
| rpPhaseHome | Jsi zpátky tam, kde cesta začala | You're back where the trip started |
| rpPhaseLong | Cesta stojí od {date} | Your trip has been paused since {date} |
| rpSince | od {time} | since {time} |
| rpLiveLine | {km} km · {time} v sedle | {km} km · {time} riding |
| rpDayN | {n}. den | Day {n} |
| rpHowTitle | Jak funguje automatická pauza? | How does auto-pause work? |
| rpHintAuto | Když zastavíš na víc než pár minut nebo odejdeš pěšky, záznam se sám pozastaví. Jakmile se rozjedeš, pokračuje. Večer nic nemačkáš a celá cesta zůstane jedním záznamem. | Stop for more than a few minutes or walk away and recording pauses by itself. It carries on as soon as you ride off. Nothing to press in the evening, and the whole trip stays one record. |
| rpHintManual | GPS je vypnuté a nic se nenahrává. Až vyrazíš, klepni na Pokračovat. | GPS is off and nothing is being recorded. Tap Resume when you set off. |
| rpHintHome | Stojíš u startu cesty přes {h} h, tak jsem kvůli baterii vypnul GPS. Pokračuješ, nebo cestu ukončíme a uložíme? | You've been at the trip's starting point for over {h} h, so I turned GPS off to save battery. Carry on, or end and save the trip? |
| rpHintLong | Cesta stojí přes {h} h, tak jsem kvůli baterii vypnul GPS. Pokračuješ, nebo ji ukončíme a uložíme? | Your trip has been still for over {h} h, so I turned GPS off to save battery. Carry on, or end and save it? |
| rpRentalEndsHint | Záznam výpůjčky skončí sám, až motorku vrátíš. | The rental recording ends by itself when you return the bike. |

**Toasts and notices**

| Key | cs | en |
|---|---|---|
| rpToastPaused | Záznam je pozastavený a GPS vypnuté, šetří se baterie. Až vyrazíš, klepni na Pokračovat. | Recording paused and GPS off to save battery. Tap Resume when you set off. |
| rpToastResumed | Pokračuju — nahrávat začnu, jakmile se rozjedeš. | Resumed — recording starts as soon as you ride off. |
| rpToastArmed | Záznam je připravený — začne sám, jakmile se rozjedeš. | Recording is ready — it starts by itself as soon as you ride off. |
| rpTripContinuedNew | Předchozí část cesty je už uložená. Nahrávám dál jako novou jízdu — obě pak můžeš sloučit do jedné cesty. | The earlier part of your trip is already saved. I'm recording on as a new ride — you can merge both into one trip later. |
| rpTripContinuedNewOld | Předchozí část jízdy je už uložená. Nahrávám dál jako novou jízdu. | The earlier part of your ride is already saved. I'm recording on as a new ride. |
| rpOwnSavedForRental | Tvoje cesta z {date} je uložená — teď se nahrává výpůjčka. | Your trip from {date} is saved — now recording the rental. |
| rpDeleteRecordingOwnQ | Tahle jízda se právě nahrává. Smazáním se záznam zastaví a všechno, co je zatím uložené, zmizí. | This ride is being recorded. Deleting it stops the recording and removes everything saved so far. |
| rpDeleteRecordingRentalQ | Tahle jízda se právě nahrává. Smazáním zmizí, co je zatím uložené, a výpůjčka se začne nahrávat znovu od teď. | This ride is being recorded. Deleting it removes what's saved so far, and the rental starts recording again from now. |
| rpA11yPause | Pozastavit záznam jízdy | Pause ride recording |
| rpA11yResume | Pokračovat v záznamu jízdy | Resume ride recording |

**Android notifications**

| Key | cs | en |
|---|---|---|
| rpNotifTitle | MotoGo24 · záznam jízdy | MotoGo24 · ride recording |
| rpNotifDefault | Nahrávám, jen když jedeš. Při zastávce se záznam sám pozastaví. | Recording only while you ride. Stops pause it automatically. |
| rpNotifRidingTitle | MotoGo24 nahrává jízdu | MotoGo24 is recording your ride |
| rpNotifRiding | {km} km · {time} v sedle | {km} km · {time} riding |
| rpNotifArmedTitle | MotoGo24 · připraveno k záznamu | MotoGo24 · ready to record |
| rpNotifArmed | Nahrávat začnu, až se rozjedeš. | Recording starts when you ride off. |
| rpNotifPausedTitle | MotoGo24 · jízda pozastavená | MotoGo24 · ride paused |
| rpNotifPaused | Stojíš od {time}, nic se nenahrává. Po rozjezdu záznam sám pokračuje. | Stopped since {time}, nothing is recorded. It resumes by itself when you ride off. |
| rpNotifIdleTitle | Záznam cesty čeká | Your trip recording is waiting |
| rpNotifIdleText | Kvůli baterii jsem vypnul GPS. Až vyrazíš, otevři appku a klepni na Pokračovat. | GPS is off to save battery. When you set off, open the app and tap Resume. |

**Stats, days, stages**

| Key | cs | en |
|---|---|---|
| rpStatOnRoad | na cestě (bez pauz) | on the road (excl. breaks) |
| rpStatPauses | pauzy | breaks |
| rpStatPausesVal | {n}× · {time} | {n}× · {time} |
| rpStatDays | dny na cestě | days on the road | (no longer shown — the days tile shows `rpDaysOne/Few/Many` as the value + caption `rpStatDaysCap` „trvání cesty" / "trip length", fix:ui-old r1) |
| rpDaysOne / rpDaysFew / rpDaysMany | {n} den / {n} dny / {n} dní | {n} day / {n} days / {n} days |
| rpRidesOne / rpRidesFew / rpRidesMany | {n} jízda / {n} jízdy / {n} jízd | {n} ride / {n} rides / {n} rides |
| rpStages | Etapy | Stages |
| rpStageDay | Den {n} | Day {n} |
| rpGapNotice | Část trasy neznáme — telefon chvílemi neposílal polohu (slabý signál, vypnutá appka nebo poloha). Šedé tečkované úseky jsou jen spojnice: tudy jsi jet nemusel a do kilometrů se nepočítají. Pauzy a noci sem nepatří, ty jsou zvlášť. | Part of the route is unknown — your phone stopped sending its location for a while (weak signal, app or location off). Grey dotted parts are just connectors: you may not have ridden there and they aren't counted. Breaks and nights aren't included here; they're shown separately. |
| rpPauseLegend | Modrošedá čárkovaná čára = přesun během pauzy (trajekt, přívěs…), do kilometrů se nepočítá. | Blue-grey dashed line = moved during a break (ferry, trailer…), not counted in distance. |

**Trips**

| Key | cs | en |
|---|---|---|
| rpTripChip | Cesta | Trip |
| rpTripDefault | Cesta {dates} | Trip {dates} |
| rpTripRental | Výpůjčka {moto} | Rental {moto} |
| rpMerge | Sloučit jízdy | Merge rides |
| rpMergeHint | Vyber jízdy, které patří k jedné cestě. Jízdy zůstanou uložené, jen se zobrazí jako jedna cesta se součty a etapami. Kdykoli ji zase rozdělíš. | Pick the rides that belong to one trip. The rides stay saved; they're just shown as one trip with totals and stages. You can split it again any time. |
| rpMergeBtn | Sloučit ({n}) | Merge ({n}) |
| rpMergeMinTwo | Vyber aspoň dvě jízdy. | Pick at least two rides. |
| rpMergeNameTitle | Pojmenuj cestu | Name the trip |
| rpMergeNameHint | Např. Alpy 2026 (nech prázdné a pojmenuju ji sám) | e.g. Alps 2026 (leave empty and I'll name it) |
| rpMergeDone | Jízdy jsou sloučené do jedné cesty. | Rides merged into one trip. |
| rpUndo | Zpět | Undo |
| rpTripAddTo | Přidat do cesty… | Add to a trip… |
| rpTripRemove | Vyjmout z cesty | Remove from the trip |
| rpTripRemoved | Jízda je vyjmutá z cesty. | Ride removed from the trip. |
| rpTripRename | Přejmenovat cestu | Rename trip |
| rpTripSplit | Rozdělit cestu | Split trip |
| rpTripSplitQ | Rozdělit cestu na jednotlivé jízdy? Jízdy, fotky i zastávky zůstanou, jen se zase zobrazí každá zvlášť. | Split the trip into separate rides? Rides, photos and stops stay; they're just shown one by one again. |
| rpTripSplitDone | Cesta je rozdělená na jednotlivé jízdy. | The trip is split into separate rides. |
| rpTripDelete | Smazat cestu | Delete trip |
| rpTripDeleteOnlyGroup | Jen zrušit sloučení | Only undo the merge |
| rpTripDeleteAll | Smazat i všechny jízdy | Delete all its rides too |
| rpTripDeleteQ | Smazat celou cestu? Smažou se všechny její jízdy ({n}) včetně fotek a zastávek a nejde to vrátit. | Delete the whole trip? All its rides ({n}) incl. photos and stops are deleted for good. | (shown only after the sheet that already offers „Jen zrušit sloučení"; when the trip holds the recording ride, `rpDeleteRecordingRentalQ`/`rpDeleteRecordingOwnQ` is appended — fix:ui-old r1) |
| rpTripMembers | Jízdy v cestě | Rides in this trip |
| rpTripPartOf | Součást cesty {name} | Part of the trip {name} |
| rpTripVisibilityOn | Cestu vidí i ostatní jezdci | Other riders can see this trip |
| rpTripVisibilityOff | Cesta je jen tvoje | Only you can see this trip |
| rpTripFailed | Úprava cesty se nepovedla — zkontroluj připojení a zkus to znovu. | Couldn't update the trip — check your connection and try again. |
| rpTripPartial | Některé jízdy se nepodařilo upravit — obnov seznam a zkus to znovu. | Some rides couldn't be updated — refresh the list and try again. |
| rpTripUnavailable | Slučování jízd zatím nejde — server ještě nemá potřebnou aktualizaci. Zkus to později. | Merging rides isn't available yet — the server hasn't been updated. Try again later. |
| rpBookingTotal | Celkem za výpůjčku: {rides} · {km} · {time} v sedle | Rental total: {rides} · {km} · {time} riding |

### 12.2 v2 keys (cs / en; Android only; no emoji)

| Key | cs | en |
|---|---|---|
| v2RpStatusRec | NAHRÁVÁM | RECORDING |
| v2RpStatusPaused | POZASTAVENO | PAUSED |
| v2RpStatusArmed | ČEKÁM NA ROZJEZD | WAITING TO RIDE |
| v2RpStatusHome | ZPĚT NA STARTU | BACK AT THE START |
| v2RpStatusLong | GPS VYPNUTÉ | GPS OFF |
| v2RpPauseCta | POZASTAVIT | PAUSE |
| v2RpResumeCta | POKRAČOVAT | RESUME |
| v2RpNavRec | REC | REC |
| v2RpNavPause | PAUZA | PAUSED |
| v2RpChipRiding | {time} v sedle | {time} riding |
| v2RpChipAvg | Ø {v} km/h | avg {v} km/h |
| v2RpChipDay | {n}. den | Day {n} |
| v2RpTripCard | CESTA · {days} | TRIP · {days} |
| v2RpMergeRow | Sloučit jízdy do cesty | Merge rides into a trip |
| v2RpStopBody2 | Pozastavená cesta se uloží v místě, kde jsi naposledy zastavil. | A paused trip is saved where you last stopped. |

---

## 13. Diagnostics (`rideLog`, category `ride`)

New actions (Velín `rideDiag.js` labels in Czech):
- `phase {from, to, reason, battery?}` → "Stav záznamu";
- `pause {reason, since, m, held}` → "Pozastaveno (stání/chůze/ticho/ručně)";
- `resume {mode auto|manual, pause_sec, m, preroll, flagged}` → "Pokračuje";
- `tail_restore {n, m}` → "Obnovený pomalý úsek";
- `home_pause` → "Pauza doma (GPS vypnuto)";
- `long_pause` → "Dlouhá pauza (GPS vypnuto)";
- `trip_continue {old, reason}` → "Nová jízda po uzavření serverem";
- `caps {trips}` → "Server: podpora cest";
- `clock_offset {sec}` → "Posun hodin telefonu";
- `notif_failed` → "Notifikace selhala";
- `own_saved_for_rental` → "Vlastní cesta uložena kvůli výpůjčce";
- `flag {on, cond}` → "Auto-pauza (flag)".

---

## 14. Compatibility matrix

| | Current server | New SQL |
|---|---|---|
| **4.1.3** | today | Same RPCs, keys and codes. Rental never splits while active (resume at any age, no 3 h/36 h). Nights and long stops → inferred pause; walking/drift no km; Doppler max; smoothed climb; car km after return dropped (append → `ride_finished`, which 4.1.3 treats as "forget"); late Stop trimmed; `duration_min` without pauses. Own rides keep 3 h/36 h (documented). No pause UI. |
| **PR #2208 dev build** | today | As 4.1.3 (legacy path) |
| **New app** | Fallback (§5.4): pause/auto-pause/markers local; a night still splits (3 h cron) but continuation keeps recording for own rides too; trips hidden; live stats from append responses | Full: one ride per trip, stages, merge/undo, booking-end close, clock offset |
| Mixed during deploy | — | A legacy session upgrades via the probe → `start_user_trip` adoption. A second device appending to the same open ride: points older than the last stored point are dropped (no crash). |

---

## 15. Rollout and kill-switch

1. Owner approves the SQL → migrations a–e (+ f if the backfill is approved) are committed **together with Velín** (Vercel) in one merge. STATE docs from `STATE_PATCH.md` go into the same commit.
2. App: Android 4.2.x (v2 + shared). The iOS tree gets the same shared logic and old-UI changes in the same commit (CLAUDE.md rule 1); the iOS release date is the owner's.
3. Kill-switch `feature_flags.ride_autopause.enabled = false`:
   - no auto-pause, no hold-back, no armed (P0 then everything uploaded);
   - manual pause, never-split, trips and stats stay.
   - Thresholds via `conditions` without a release.
4. Monitoring:
   - Velín → jízda → Diagnostika (phase/pause/resume);
   - Velín "Stojí" filter;
   - ratio `pause_sec / moving_sec`;
   - battery from `phase` logs (if implemented).

---

## 16. Tests

### 16.1 SQL (T1) — PG16 `/var/tmp/pg-rides:5499` via `pg/setup.sh`

- **Apply** every draft twice; then `select public.t_shim()`, with the shim filter extended to names containing `trip`.
- **Signatures** of every existing ride RPC unchanged (`pg_get_function_identity_arguments` before/after diff = ∅).
- **No overloads:**
  ```sql
  select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where nspname = 'public' and (proname like '%ride%' or proname like '%trip%')
  group by 1 having count(*) > 1;
  ```
  returns 0 rows.
- **Grants:** anon cannot execute any new function; authenticated cannot execute `_ride_stats_v2`, `_ride_append_core`, `_ride_prague_night`, `_ride_finalize`.
- **Vectors** V1–V15 (§3.7) exact; write `stats_vectors.json` for T2.

**Append/finish/finalize:**
- re-sending the same batch → stats unchanged;
- marker → pause;
- armed reset moves `started_at` and drops P0;
- the batch after `returned_at` + 2 min → `ride_finished` and the ride is closed at `returned_at`;
- finish 2.5 h after the last fix → `ended_at ≤ last_fix + 2 min`;
- `already_finished` path unchanged;
- 4.1.3 response keys present.

**Cron:**

| Case | Expected |
|---|---|
| pause-aware own silent 30 h | open |
| pause-aware own silent 73 h | closed at last fix |
| legacy own 3 h 5 min | closed (unchanged) |
| legacy rental active, silent 10 h | open |
| rental returned 11 min ago | closed at `returned_at` |
| `end_date` two days ago | closed |

**`start_user_trip`:**
- `booking_inactive`: no row created;
- adoption of a legacy rental ride (`pause_aware` becomes true);
- own resume < 72 h; own > 72 h → old one finalized, new one created;
- `unique_violation` race → resumed.

**`start_user_ride`:** a 4.1.3 rental open 20 h with an active booking → resumed.

**`set_user_rides_trip`:** merge 3 / undo / split, foreign id skipped (`updated` 2 of 3), `bad_items`.

**Cap:** 30 000 points in batches of 20 → older days evenly spaced (±25 %), markers and pause edges kept, ≤ 50 ms per thinning call at 12 000.

**Replays** (`pg/sim`): add `NewClient2`, a truth-based emulation of the new client:
- start via `start_user_trip` with P0;
- uploads only riding points (bike speed ≥ 7 km/h, or a stop shorter than 5 min);
- a stop ≥ 5 min becomes a pause with the first point after it flagged −1;
- walking is never uploaded; points carry 0.1 s ts and clock offset;
- on `ride_finished` it continues like the app.

Truth values are from `understand_server.md` §5:

| Scenario | Target |
|---|---|
| S1 own day | 1 ride; km 331.7 ±1 % ([328.4, 335.0]); climb within 85–105 % of 2 794 m; `idle ≤ Σ(stops < 5 min) + 2 min` |
| S2 own, no-fix night | 1 ride; km 588.3 ±2 %; `pause ≥ 9 h`; 2 stages; days 2 |
| S2d own, drift night | 1 ride; phantom km < 0.5; idle < 30 min; 2 stages |
| S2r / S2rd rental 2 days | 1 ride each |
| S3 rental killed 20:24, opened 08:00 | 1 ride; night = pause; no new ride |
| S4a / S4c 7-day own | 1 ride; km 2 537 ±2 % ([2 486, 2 588]); 7 stages; days 7; no close |
| S5 / S5b return + car | car km 0 (km ≤ bike truth + 0.5); max ≤ bike max; rows created = 1 per rental |
| S6 walk 40 min | km 151.0 ±0.5; Ø 78 ±3 |
| S8 lake 3.5 h | 1 ride; km 235.3 ±1 %; one pause 3.5 h ±10 min |
| S9 rental 3 days, drift | 1 ride; phantom < 1 km; no 36 h close |
| S10 late Stop | `ended_at ≤ arrival + 2 min`; idle ≈ real short stops |
| S7a (OldClient, 4.1.3) | 1 ride; walking excluded (km ≤ 370.1 + 0.5); all response keys; only legacy codes |
| S7b (OldClient rental) | **1 ride** (was 2); the morning before the app is opened is not recorded (4.1.3 limit) |
| S11 OldClient own 2 days | identical to today's behaviour (regression check) |
| S13 NewClient2 on the OLD schema (drafts not loaded) | own 2 days → 2 rides, km sum ±2 % of truth, no silent stop |
| S14 NewClient2 clock −2 h / +7 h | saved; km ±2 % |

### 16.2 Dart (T2/T3/T4)

Android `test/rides/`. iOS: copy the shared tests into `scratchpad/rides/ios_copy/<key>/test/rides/` and run there.

**`ride_motion_test.dart` / `ride_pause_engine_test.dart`.** Synthetic traces: meridian north; fixes every 5 s while moving; `acc` 8; `hasSpeed`, `hasSpeedAccuracy` and `hasAccuracy` set true; no fixes while still unless stated. `GeolocatorPlatform.instance = FakeGeo()` only for recorder-level tests.

| # | Trace | Expect |
|---|---|---|
| D1 | 60 km/h 5 min → decelerate (40, 20, 8) → no fix 90 s → 15, 30, 60 km/h 5 min | 0 pauses; no flag; every point emitted in order |
| D2a | ride 30 min → decelerate → no fixes 12 h (ticks every 90 s) → 25, 25 km/h 5 s apart, 120 m from the anchor → ride | 1 pause, `since` = anchor ts; reason `stop` at slowSince + 5 min; first emitted after resume has kmh −1 and ts = pre-roll start; nothing emitted during the pause |
| D2b | ride at 60 then abrupt silence 12 h, no ticks → first fix 40 m away, then 25, 25 km/h | 1 pause, reason `silence`, anchor = last riding point; flag on the first resumed point |
| D3 | ride → stop → walk 5 km/h 10 min loop 600 m back to the bike → ride | pause reason `walk` 3 min after slowSince (±10 s); no walking point emitted; no tail restore; flag present |
| D4 | ride 60 → crawl 6 km/h 5 min (500 m) → 50 km/h from the crawl end | walk-pause at ~3 min, then tail restored (log `tail_restore`); no flag; emitted points cover the crawl |
| D5 | 90 km/h → no fix 4 min → fix 6 km ahead at 90 | 0 pauses; point emitted |
| D6 | paused; 8 h of fixes acc 40–80, no Doppler, 30–60 m jumps every 60 s | stays paused; 0 emitted |
| D7 | paused; walking 5 km/h with one 25 km/h Doppler spike | no resume |
| D8 | paused; fixes without speed, acc 15: two pairs 350 m apart within 40 s, ≥ 300 m from the anchor | resume (rule b) |
| D9 | `pauseManual()` while pending | anchor emitted, held dropped, `detach` true; `resumeManual()` → armed; the first emitted point is flagged |
| D10 | after attach, a fix with ts = attachedAt − 10 min | ignored |
| D11 | `startArmed()`; P0; walk 3 min; then ride | P0 emitted at once; nothing from the walk; the first riding point is flagged (≥ 60 s) |
| D12 | own; P0 at A; 40 km loop back to A; stop; ticks for 3 h | guard home → detach, reason `home` |
| D13 | own paused 20 h far from the start → guard long; rental paused 20 h | own: detach; rental: no detach |
| D14 | `stop()` while pending with 6 held points | only the anchor emitted |
| D15 | `autoPauseOn = false` | no pending/pause; every point emitted; manual pause works |
| D16 | restore after kill (`restored = true`, anchor A), first fixes 50 km away at 60 km/h | resume; first point NOT flagged |
| D17 | armed; 10–15 km/h for 70 s then ≥ 20 km/h | resume by rule (c) or (a); pre-roll starts at the first fix ≥ 8 km/h within 180 s |

**Other Dart tests:**
- `ride_live_stats_test.dart`: `rideIsMovingPair` parity with `stats_vectors.json` (V1–V10 moving/km).
- `ride_session_test.dart`: JSON round-trip; unknown/older JSON → null session without a crash.
- `ride_cache_keys_test.dart`: `mg_ride_session` and `mg_ride_caps` survive `CacheCleanupService.run()`.
- `ride_server_api_test.dart`: `classifyRideRpcError` (PGRST202/42883/42703 → missing; SocketException/Timeout → offline; other → error).
- `ride_point_test.dart` (update `ride_location_test.dart`): ts to 0.1 s; kmh 0 when `speedAccuracy > 2.5`; alt dropped when `altitudeAccuracy > 20`; clock offset −2 h and +7 h.
- **Recorder integration** (fake server seam `RideServerSeam` injected via provider override, FakeGeo):
  - 7-day own trip → 1 ride id, 6 pause/resume pairs, 0 continuations;
  - rental `booking_ended` → `closed` → `start_user_trip` `booking_inactive` → stopped, no new ride;
  - old server: `start_user_trip` missing → `start_user_ride`; `closed` for own → new ride + notice `rpTripContinuedNewOld`;
  - offline start ≠ fallback;
  - manual pause → `_restore` does not attach;
  - the watcher `ensureRecording` is a no-op while paused;
  - `discardCurrent` then `gone` → no continuation.
- `ride_trip_test.dart`:
  - `rideTripKey` precedence;
  - aggregate sums incl. inter-ride pause;
  - default names;
  - undo maps of merge / split / rename / remove / add restore the exact previous `(tripId, tripName)`, incl. an implicit rental group.
- `rp_i18n_test.dart` (both trees): every `rp*` key exists in 8 languages, non-empty, same placeholders; plural helpers (cs 1/2/5/21, pl 2/5/12/22, uk 1/3/11/21).
- **Widget tests:**
  - old `RideRecControlsCard` and `RideNavRecChip` in every phase × 8 languages × widths 320/411: no overflow; semantics labels; reduced motion → no animation;
  - v2 (Android `test/v2/`): dock live bar, recorder card/screen, home row, nav chip, trip card in the same matrix;
  - existing v2 tests (`file_size_test`, `i18n_v2_test`, …) stay green.

**Analyze:** Android ≤ 147 issues / 0 errors; iOS (rsync copy, `pub get --offline`) ≤ 143 / 0. `diff -rq` of both `lib/` shows only the intentional platform files, the v2 files and the v2 seams.

### 16.3 Velín (T5)

- `cd velin && npm run build`.
- Fixtures (JSON in a scratch file, rendered via a temporary story or a manual check): live / standing / stuck for legacy and pause-aware rides; a ride with stages; a ride with a marker pause and a moved pause; a trip name. Check badges, Etapy, connectors.

---

## 17. Tasks, ownership, order

| Task | Owns (writes) | Depends on |
|---|---|---|
| **T1 SQL** | `scratchpad/rides/sql/01..06_*.sql`, `pg/sim/*` extensions, `scratchpad/rides/STATE_PATCH.md`, `stats_vectors.json` (copied by T2) | — |
| **T2 Recorder + native** (both trees, identical) | `ride_motion.dart`, `ride_pause_engine.dart`, `ride_session.dart`, `ride_server_api.dart`, `ride_flags.dart`, `ride_live_stats.dart`, `ride_location.dart`, `ride_provider.dart`, `ride_recorder.dart`, `ride_recorder_watcher.dart`, ⚠ `core/cache_cleanup_service.dart` (2 lines), Android `RideEngineKeeper.kt` / `MainActivity.kt` ride parts, tests §16.2 (motion, engine, session, cache, server api, point, live stats, recorder integration) | `stats_vectors.json` from T1 for the parity test (may stub, then swap) |
| **T3 Old UI + model + trips** (both trees) | `ride_model.dart`, `ride_trip.dart`, `ride_trip_api.dart`, `ride_rec_controls.dart`, `ride_pause_actions.dart`, `ride_pause_sheet.dart`, `ride_stats_grid.dart`, `ride_stage_list.dart`, `ride_trip_card.dart`, `ride_merge_screen.dart`, `ride_trip_detail_screen.dart`, edits in `my_experiences_screen.dart` (old parts; iOS incl. `_toggleManualRide` call), `ride_card.dart`, `ride_detail_screen.dart`, `ride_map.dart`, `ride_share.dart`, `ride_booking_section.dart`, `ride_start_feedback.dart`, `community_submit.dart`, ⚠ `route_navigation_screen.dart` (1 line), i18n `translations_ext_46_rides_pause_a..d.dart` + registration, tests (trip, i18n, old widgets) | T2's public contract (§5.2). Code against it; T2 lands first or merges in the same integration. |
| **T4 v2 UI** (Android only) | files in §9.2, `translations_ext_59_v2_rides_pause.dart` + registration, v2 tests | T2 contract + T3 `ride_trip.dart`, `ride_pause_actions.dart`, `ride_merge_screen.dart`, `ride_trip_detail_screen.dart` (seam) |
| **T5 Velín** | §11 files | none (columns are optional) |

**Integration gate** (orchestrator):
- both analyzers;
- all tests (iOS in the copy);
- `diff -rq`;
- Velín build;
- SQL drafts applied twice plus replays green;
- `STATE_PATCH.md` present.

No git writes by agents. Disk: work dirs under `scratchpad/rides/<key>`; delete goldens and copies when done.

---

## 18. Owner decisions (defaults chosen; owner may change)

| # | Decision | Default |
|---|---|---|
| D1 | Thresholds: pause after 5 min standing / 3 min walking; resume 2× ≥ 20 km/h | yes (flag-tunable) |
| D2 | GPS stays on during auto-pause (est. 5–15 % battery per night), for rentals AND own trips; stated in the „Jak funguje automatická pauza?“ text | yes; the own-trip guard switches GPS off only after **48 h without contact** (`long_h`, counted from the later of the pause start and the last app open / Pokračovat / stream attach) — §20 |
| D3 | "Home": own single-stage trip paused ≥ 3 h within 500 m of its start after ≥ 10 km → **notification only** (Android), GPS stays on, departure is recorded hands-free | yes — §20 |
| D4 | Own trip auto-saved after 72 h without riding; 30-day cap | yes |
| D5 | 4.1.3 own rides keep 3 h / 36 h; rentals never split for any app | yes |
| D6 | `duration_min` = time without pauses ("Na cestě") in app and Velín | yes |
| D7 | Rental and manual recording start "armed": the ride begins at departure | yes |
| D8 | Backfill historical rides (nights → pauses) — draft 06 | proposed yes |
| D9 | Rental ride closes immediately when points arrive after the return | yes |
| D10 | Trip visibility switch applies to every ride in it; public feed stays per ride | yes |
| D11 | Known limitation: taxi, bus, ferry or bicycle ≥ 20 km/h resumes recording | accepted |
| D12 | Merge and trip detail screens in old look (inside the v2 frame on Android) until the owner comments; v2 trip detail uses v2 parts | yes |

---

## 19. Traceability

| Requirement / nonsense case | Fix |
|---|---|
| R1 pause | §6.3 manual ops, §7.3, §9 |
| R2 auto-pause/resume | §6 |
| R3 stats | §3, §9.3 |
| R4 never split | §4.7–4.9, §7.4 |
| R5 merge + undo | §4.10, §8 |
| R6 rental | armed, §4.8–4.9, §6.3 |
| N walking = riding | client hold-back + server rule 7 (Doppler ≥ 7) |
| N drift km / climb | not uploaded while paused + rules 7/8 + legacy still-run |
| N climb noise | §3.6 |
| N max artefacts | §3.3 + 0.1 s ts + Doppler validity |
| N night splits / silent stop | §4.7–4.9 + continuation §7.4 |
| N night as stání / "bez signálu" | marker + silence rule (§3.2 rules 3–4) |
| N 7-day = many rides | never split + stages + trips (+ implicit rental grouping for history) |
| N car km after return | §4.2 step 2–3 |
| N manual ride labelled as rental before pickup | `start_user_trip` without date match + `setActiveBooking` |
| N OS kill | session restore §7.2; rental adoption at any age |
| N clock skew | §5.5 |
| N "N bodů" / 4000 points | live km/time instead of points; cap §4.3 |
| N solid line over > 24 h | 30-day bad-time threshold in app, server, Velín |
| N battery | auto-pause keeps GPS (platform limit); manual pause and home/long guards cancel it |

---

## 20. Amendments 2026-10-29 (fix:logic:r1 — scenario verification)

These override the sections above where they differ. App code: both trees (shared), v2 texts Android only.

1. **Battery guards never lose a riding day** (§6.3 `onTick`, §7.3).
   - Re-attaching a low-power stream after a guard is NOT possible within the platform: on Android the guard runs in the background, cancelling the stream stops geolocator's location FGS, and Android 12+/14 forbid (re)starting a location FGS from the background (the parked engine is also destroyed 15 s after `keepAlive(false)`); on iOS „při používání“ cannot start location updates from the background. So the guards changed instead:
   - `home` = **notice only** (`RideEngineStep.homeNotice` → Android `notifyIdle(rpNotifHomeTitle, rpNotifHomeText)`, cancelled by `cancelIdle` once riding resumes / Pokračovat / stop). GPS stays on, the phase stays `autoPaused`, departure resumes hands-free. Only for single-stage trips (`liveStages < 2`), once per pause, log `home_notice`. The engine no longer produces `manualPaused + home` (UI keeps handling it for compatibility).
   - `long` = detach as before, but default **48 h** (`long_h`; draft 01 flag default must become `"long_h":48` — SQL owner) and counted from `max(pausedSince, guardFrom)`; `guardFrom` = last `onAttach` (stream attach only happens in the foreground), `noteForeground` (every `onAppResumed`) and `resumeManual(now)`.
   - No guard within 120 s of `guardFrom` (`guardQuietS`), and none while the ring has a fix from the last 120 s with Doppler ≥ 12 km/h or ≥ 100 m from the anchor (`guardMoveM`) — the resume rule decides.
   - `resumeManual(now)` therefore cannot be undone by the next tick (S5: 941 km lost before).
2. **Resume rule (b) without Doppler** (§6.3): needs 3 good fixes A→B→C within 60 s, A–C ≥ 300 m, each step 15–250 km/h, C farther from the anchor than B, C ≥ 300 m from the anchor; and it is **disabled** once the session has seen ≥ 3 fixes with Doppler ≥ 12 km/h (`dopplerSeen`, the phone measures speed — Wi-Fi/network fixes never carry speed). Fixes the hotel-night Wi-Fi flips (E3: 45 false resumes). The server-side out-and-back spike rule for 4.1.3 points (A→B→A′ ≤ 120 s, |AB| ≥ 300 m, |AA′| < 50 m → jump) is an SQL follow-up (`_ride_stats_v2` + Dart mirror together, parity vectors).
3. **Pending decisions use Doppler only with ≥ 3 samples** (`walkMinFixes`): walk = `byDop ? median∈[2,8] : avg ≤ 8`, release = `byDop ? median > 8 : avg > 9`. A single braking sample no longer turns a walk into „slow riding“ (S2-nodop).
4. **Tail restore** (§6.3 `resume`): only when the segment is ride-like (mean speed or Doppler median > 8 km/h) or leads one way away from the anchor (net displacement ≥ 60 % of its path, `restoreOneWay`). An out-and-back walk is never restored; a 6 km/h jam crawl that moves away still is (D4).
5. **Clock offset at start** (§5.5): a new start holds fixes (≤ 20 s, ≤ 300) until the first `start_user_trip`/`start_user_ride` attempt finishes (`_clockQueue`, released in `_createServerRide`'s `finally`, also at stop), then processes them with the measured offset; `_applyClock` re-bases the engine attach time (`rebaseAttach`). `cachedFixSlackS` = 150 s. Fixes C3 +7 h (whole ride discarded) and +40 s GPS time (P0 dropped).
6. **Uploads**: `append_ride_track` in chunks of ≤ 2000 points (loop while ok and points remain, ≤ 100 chunks); the buffer is persisted at most every 30 s / 20 points and always after a flush (also offline), pause/detach, stop. `append_ride_track` and `finish_user_ride` time out after 30 s (`kRideRpcTimeout` → retry / not closed; the server de-duplicates a repeated batch).
7. **Detach order** (§7.3): `_detachStream()` first, then `unawaited(flush())` — a hanging connection never keeps GPS on; a manual-paused cold start (§7.2) calls `flush()` at once.
8. **Watcher** (§7.6): `rideActiveBookingId()` skips `Reservation.isGearOnly` (`booking_kind = 'gear'`, new field `bookingKind` parsed from `select *`) — a clothing rental never starts a recording, never ends a paused own trip (`finishOwnForRental`) and never gets manual starts attributed. 4.1.3 cannot be fixed → keep `gear_rental.app_visible = false` until this app ships and the server backstop (`start_user_trip`/`start_user_ride` → `booking_inactive` for gear) is deployed.
9. **Trips** (§8.2): the time between member rides counts as pause (and as a pause join on the map) only when ≤ 36 h (`kRideTripJoinPauseMaxSec`); a longer gap adds neither time nor count and is drawn as a plain break. `trip.days` (used by every surface) stays the distinct stage/ride days.
10. **Trip I/O** (§8.3): one result mapping `rideTripResultOf`; container-based `rideTripApplyIn(c, plan, {bookingIds, set})`, `rideTripSetVisibilityIn`, `rideTripDeleteAllIn`; the `WidgetRef` wrappers capture `ProviderScope.containerOf(ref.context)` before the first await. v2 `tripApplyV2`/undo use the same function with their seam (`set: tripSetSeamV2`).
11. **Texts**: new `rpNotifHomeTitle`/`rpNotifHomeText` (`translations_ext_60_rides_logic.dart`, registered via `translations_ext_47_rides.dart`, both trees); `rpHintAuto` (both trees) and `v2RpHintAuto` (Android) now say that GPS stays on during auto-pause (battery) and that a bus/car/train above 20 km/h can be recorded — tap Pause before such a transfer (D11; the „not near the bike“ heuristic was rejected: it would cut jam crawls and cold-start departures).
12. **Not changed here (SQL owner)**: own trip offline > 72 h (C5) — preferred fix: `append_ride_track` re-opens an own `pause_aware` trip that the 72 h rule closed (`closed_by = 'stale'`) when the same user sends points newer than its last fix and no other ride is open; the app needs no change for it.


## 21. Amendments 2026-10-29 (fix:sql:r1 — SQL drafts)

These override §1–§4, §14 and §16.1 where they differ. SQL only (drafts in `scratchpad/rides/sql/`).

1. **Files / names.** 8 drafts, each depending only on earlier ones: `01` a, `02` b, `03a` c (`_ride_append_core` only), `03b` d (`_ride_auto_name`, `_ride_close`, `_ride_finalize` wrapper, `_ride_json`, `get_public_rides`), **`03c` e (new: `_ride_append_late`, `append_ride_track`, `finish_user_ride`)**, `04` f (+ gear data fix), `05` g, `06` h (optional). Commit names `20261029_user_rides_pause_a…h.sql` — must sort (LC_ALL=C) after `20261023f_faq_gear_rental.sql`; `20261023_…` would sort before `20261023a_…`.
2. **Close core** (§4.6): `_ride_close(p_ride_id, p_ended_at, p_by text, p_reclose boolean)` holds the old `_ride_finalize` body; `_ride_finalize(id, end)` = `_ride_close(id, end, null, false)` (live `admin_finish_user_ride` keeps calling it). `p_by` → `stats_state.closed_by` (only when `stats_state` is not null — a pre-deploy ride keeps NULL = old stats for Velín and `06`): `user` (finish), `return` (append/finish batch only after the return), `cron` (close_stale), `start` (start_user_trip/start_user_ride closing a stale ride). `p_reclose` = recompute an already closed ride (never deletes; an auto name `DD.MM.YYYY` / range and the `end` point follow the new end).
3. **`_ride_append_core` no longer closes** (§4.2 step 3): all-after-return → `{booking_ended:true, end_at}`; the caller closes with `'return'`.
4. **Late points into a closed rental** (§4.4 step 4, §4.5 step 3): `append_ride_track` / `finish_user_ride` on a closed ride call `_ride_append_late`: only a MOTORCYCLE rental (`booking_kind <> 'gear'`) with `returned_at` set, `closed_by in (return, cron, start)`, `now() ≤ returned_at + 7 d`; points go through `_ride_append_core` (dup ≤ last stored ts, after-return grace 30 s / 120 s, bad) and the ride is re-closed with `_ride_close(id, returned_at, closed_by, true)` (end = min(return, last fix + 2 min)). `append_ride_track` still answers `ride_finished` (+ `reason:'booking_ended'` when ≥ 1 point was stored); `finish_user_ride` answers `already_finished` with the new values. Own rides and rides stopped by the rider never take late points. **App side (fix:logic:r2):** the app uploads in chunks of ≤ 2000 points (§20 item 6), so a long offline day arrives as several appends. `_flushChunk`: a chunk answered `ride_finished` + `booking_ended` was stored into that ride (or was all after the return) → it is dropped from the buffer and the NEXT chunk goes to the SAME ride id; only when the buffer is empty, or a chunk comes back `ride_finished` without `reason` (nothing stored), the recorder runs the continuation (→ `start_user_trip` → `booking_inactive`). In the `booking_inactive` branch (continuation, or an offline start after an app restart with a known `rideId`) the recorder first delivers the whole remaining buffer to `_st.rideId` (`_drainEndedRental`: chunks ≤ 2000, response not evaluated — a chunk of duplicates after a lost answer comes back without `reason`, the next one can still be stored; offline → buffer kept, retried by the timer) and only then `_forgetRide()`. Replays: C6 331.2 / 331.6 km; X16 (last day 4×70 min offline, ~3 100 buffered fixes > 2000) 447.3 / 447.5 km (before: 314.1 — the rest of the buffer was dropped after chunk 1).
5. **Dedup high-water mark** (§4.2 step 2): taken from the last stored ts only when ≤ `now() + 600 s`, advanced only by kept points with ts ≤ `now() + 600 s`; ts > 4 102 444 800 (year 2100) = bad point.
6. **Armed reset** (§4.2 step 4): additionally `gap_sec < 300` and stored track ≤ 3 points (outer), pre-marker part `gap_sec < 300` (inner).
7. **Gear-only bookings** (`booking_kind = 'gear'`) are not motorcycle rentals anywhere: `start_user_trip(gear)` → `booking_inactive`; `start_user_ride` pairs (date and id) only `booking_kind <> 'gear'`, an own gear id → `{success:false, error:'booking_inactive'}`; both start RPCs detach an open ride linked to a gear booking (`booking_id = null`); `close_stale_user_rides`, `_ride_append_core`, `finish_user_ride`, `_ride_append_late` ignore a gear booking (own-ride rules, no return cut-off); `04` detaches every ride linked to a gear booking (idempotent `update … set booking_id = null`).
8. **`get_public_rides`** (same signature): only `not is_recording`, and without `trip_id`, `last_fix_at`, `pause_aware`, `is_recording` (plus `booking_id`, `moto_id` as before).
9. **Text coordinates**: `_ride_track_cap`, `_ride_close`, `_ride_append_core` and `admin_booking_live_ride` read stored lat/lng only when `jsonb_typeof = 'number'`.
10. **Backfill (`06`)**: `stats_state = {"backfill":1, "old":{duration_min, idle_sec, gap_sec}}`; revert snippet in the file header (tested, L6).
11. **Flag default** `ride_autopause.conditions.long_h = 48` (per §20.1).
12. **Not changed (documented)**: track cap 12 000 / list payload (STATE_PATCH 3b/3d); own trip offline > 72 h re-open (§20.12) is still open.
13. **Tests** (§16.1): `test_rides.sql` 215 checks (new P, R, S, GK, Q, H3, L6 + closed_by checks), run 2× on a fresh cluster; `run_tests.sh` also checks the gear data fix on a pre-existing ride; `PGD` / `PGPORT_RIDES` select another cluster.


## 22. Amendments 2026-10-29 (fix:ui-v2:r1 — v2 look, Android only)

These override §9.2 and §12.2 where they differ.

1. **Toast never covers the dock.** `RecorderScreenV2` keeps `MgDock` in `Scaffold.bottomNavigationBar` (the floating toast sits above it). Toasts of `rideTogglePauseV2` get `lift = MgShellChrome.dockHeight` (`rideToastLiftV2`), so on Trasy / Moje the toast floats above the record dock in the page body. `showMgToast` has an optional `lift` (default 0, backwards compatible).
2. **Phase words** (`RecPhaseV2`, one mapping for every v2 surface): auto-pause (`rideIsAutoPaused`) = status `v2RpStatusAuto` „STOJÍŠ · AUTO-PAUZA“, chip `v2RpChipAuto` „Auto-pauza“, `auto = true`, tone stays `paused`; manual pause keeps POZASTAVENO / Pozastaveno. GPS lost = status `v2RpStatusNoGps` „POLOHA NEDOSTUPNÁ“, chip `v2RpChipNoGps` „Bez GPS“, title `v2RpPhaseNoGps` (never „Nahrávám“ — nothing is recorded then; Domů row, dock bar, Moje row and the live badge follow the chip).
3. **Nav chip** (`recNavLabelV2`): REC (riding) · PŘIPRAVENO `v2RpNavArmed` (armed, neon dot) · AUTO-PAUZA (chip upper-case) · PAUZA (manual pause, guards) · BEZ GPS (warn dot).
4. **CTA while auto-paused**: the recorder's white button reads „VYPNOUT GPS“ (`v2RpGpsOffBtn`, a11y `v2RpA11yGpsOff`) and the pause sheet „Vypnout GPS“ — same action as Pozastavit (manual pause, GPS off); armed / riding keep POZASTAVIT. `recHintV2` for auto-pause = `v2RpHintAutoNow` (nothing to press, GPS on for the move-off, Vypnout GPS saves battery overnight, then Pokračovat).
5. **GPS chip of the recorder card** (`recGpsChipKeyV2`): riding „Poloha se zaznamenává“ · armed / auto-pause „GPS zapnuté — čeká na rozjezd“ (`v2RpGpsWaiting`) · manual / guards „GPS vypnuté“ · lost „Bez GPS“.
6. **Trip delete** (v2): when the trip holds the recording ride, the confirm body appends `v2RpTripDeleteRecRental` (rental + auto-record on: recording restarts from now) or `v2RpTripDeleteRecOwn` (recording stops) — same rule as the old look.
7. **Copy**: `v2RpTripDeleteBody` takes `{n}` (number only: „jízdy (3)“); stat tiles show `recDaysV2` / `recRidesV2` as the value („3 dny“, „5 jízd“) with neutral captions `v2RpStatDays` „trvání cesty“ / `v2RpStatRides` „v této cestě“; de merge wording = „zusammenführen / Zusammenführung“ (as the old-look `rp*` keys), never „Zusammenfassung“.
8. New keys: `translations_ext_57_v2_rides_g.dart` (8 languages, registered in `translations.dart`).

## 23. Amendments 2026-10-29 (fix:sql:r2 — long offline, nothing lost)

These override §4.4, §4.5, §4.9, §20.12 and §21.4 / §21.12 where they differ. SQL only (drafts in `scratchpad/rides/sql/`); the app needs no change.

1. **Re-open of an own trip closed by the cron** (C5; §20.12 resolved — the marker is `closed_by = 'cron'`, not `'stale'`). New internal `_ride_reopen(p_ride_id uuid, p_points jsonb) returns boolean` (`03c` → `_e`, REVOKE public/anon/authenticated, GRANT service_role; the caller holds `FOR UPDATE`). It re-opens only when ALL hold: `not is_recording`, `pause_aware`, `stats_state->>'closed_by' = 'cron'`, no motorcycle booking (`booking_id` null or a gear booking), `started_at ≥ now() − 30 days`, the user has no other open ride, and the batch has ≥ 1 valid point (numeric lat/lng/ts) with `ts >` last stored ts (last track point when ≤ now + 600 s, else `last_fix_at`) and `ts ≤ now() + 600 s`. Re-open = `is_recording = true`, `ended_at = null`, `stats_state − 'closed_by'`, automatic name (`_ride_auto_name(start, end)`) → `''` (column is NOT NULL DEFAULT ''); a concurrent start (`unique_violation` on `uq_user_rides_recording`) → `false`, nothing changes.
   - `append_ride_track` on a closed ride: `_ride_reopen` true → `_ride_append_core(...) || {reopened: true}` (normal success keys); else the old path (`_ride_append_late`, `ride_finished`).
   - `finish_user_ride` with points on a closed ride: `_ride_reopen` true → `_ride_append_core`, then the normal Stop close (`closed_by = user`, normal finish JSON); else `_ride_append_late` / `already_finished` as before.
   - `_ride_close` moves an existing `end` point to the new end on every close (before: only on re-close), so a re-opened trip keeps exactly one `end` point at its real end.
   - Never re-opened: Stop (`user`), return / start / admin closes, 4.1.3 rides (not `pause_aware`), rentals (they use `_ride_append_late`), trips started > 30 days ago, batches of only stored / repeated / future points, another user's ride (`ride_not_found` as before).
2. **No deletion while late points can arrive** (`close_stale_user_rides`, `04` → `_f`): closing a ride < 1 km deletes it, which made the buffered offline points land on `ride_not_found`. Now:
   - motorcycle rental with `returned_at` set and `distance_km < 1` → not closed while `returned_at > now() − 7 days` (the `_ride_append_late` window; the 60-day cap still applies); afterwards deleted as before;
   - own `pause_aware` ride with `distance_km < 1` → the 72 h rule does not apply, only the 30-day rule; afterwards deleted as before.
   - With a ride kept open, the late batch is stored by the normal path (before-return points kept, after-return dropped) and the next cron pass / `booking_ended` batch / Stop closes it with the real km (end ≤ `returned_at`).
3. **App** (both trees): no change. On the new server a re-openable trip never answers `closed`, so the continuation and the 1 h buffer cut-off (`_kStaleBufferAge`) are not reached; they remain only where the server would reject those points anyway (`ts < started_at − 3600` in `_ride_append_core`). Against the current live server (before the SQL deploy) nothing changes (§14).
4. **Velín follow-up** (not SQL): `rideAutoCloseHint` says „při dalším úklidu (výpůjčka už skončila…)“ for a returned rental; a returned rental ride < 1 km now stays open up to 7 days (shown as „Záznam visí“ after 30 min) → the hint should say „do 7 dní po vrácení (čeká na body z telefonu bez dat)“ for `distance_km < 1`.
5. **Tests**: `test_rides.sql` 246 checks run 2× on a fresh cluster (new O1–O10b; S5 now expects the re-open; I2/I3 include `_ride_reopen`); `run_tests.sh` adds the re-open race (competing open ride inserted in an open transaction → no re-open, `ride_finished`, 1 open ride; without it the same batch re-opens). Real-recorder scenarios (`sqlr2/and`, current repo `lib`): C5 own 4 days without data 532.3 / 533.1 km in 1 ride (r1 drafts: 79.8 km, 2 rides); C6b rental offline from the pickup 180.7 / 180.9 km, 1 ride ending at the return (r1: ride deleted, 0 km); X19b app killed at night + riding on after 4 days = 1 trip 210.3 km / 2 days (r1: 2 rides); C6 331.2 / 331.6 km, X6, X7, X16 and scen_b S4–S8 unchanged; Python replays (incl. 4.1.3) 56/57 targets as before.
6. **Handoff / commit**: migrations are built ONLY from `scratchpad/rides/sql` (mapping §21.1: 01→`20261029_user_rides_pause_a` … 03c→`_e`, 04→`_f`, 05→`_g`, 06→`_h` only with consent); the repo copy `.claude/handoff/rides/sql/`, `STATE_PATCH.md`, `SPEC.md` and `setup.sh` were re-synced from the scratchpad. Check right before the commit: `git ls-tree --name-only origin/main supabase/migrations/ | LC_ALL=C sort | tail -1` must sort before `20261029_` (2026-10-29: `20261023f_faq_gear_rental.sql`).
