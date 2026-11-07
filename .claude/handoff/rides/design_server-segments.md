# Design: server-segments — pauses, auto-pause, never-split trips, merge, sane stats

Date: 2026-10-22. Design only: no repo, git, or live-DB changes.
Inputs:
- `understand_app.md`, `understand_server.md`, `understand_platform.md`
- live function bodies from snapshot `df555c93` (`pg/snap/schema_public.sql`)
- elevation simulation `design_tools/elev.py` (results in §3.6)

Requirements covered: R1–R6 from the task (manual pause, auto-pause, sane stats, never split, merge, rental same rules).

Philosophy:
- The server knows pauses explicitly and stores them per ride.
- A recording ride is one record across nights, ended only by the rider, the rental end or abandonment.
- A separate `user_trips` entity groups rides non-destructively, for merge with undo and automatic rental grouping.
- The client does motion detection, so walking and drift never reach the server. The server also infers pauses for clients that cannot send them (4.1.3).

---

## 0. Shrnutí pro majitele (CZ)

**Pauza**
- U záznamu jsou vedle sebe tlačítka **Pozastavit / Pokračovat** a **Ukončit**. Najdeš je v Mých zážitcích, v nabídce „Přidat“, v novém vzhledu (záznamník, lišta, domovská karta) i v navigaci.
- Ruční pauza vypne GPS, takže nežere baterii. Pokračuje se zase ručně.
- U výpůjčky se jízda ukončí sama při vrácení motorky, takže tam je jen pauza.

**Automatická pauza**
- Záznam se sám pozastaví, když:
  - motorka stojí déle než **5 minut**, nebo
  - po zastavení jdeš **3 minuty pěšky**.
- Sám pokračuje, jakmile jedeš **2× po sobě přes 20 km/h**. Pěšky se to nestane.
- Chůze po benzínce, k jezeru nebo po hotelu se do jízdy nepočítá. Kus prošlý pěšky se ze stopy odřízne.
- Večer nic nemačkáš. Ráno vyjedeš a záznam sám pokračuje ve **stejné jízdě**.

**Vícedenní cesta = jeden záznam**
- Server přestane jízdy dělit po 3 h a 36 h.
- Jízda zůstane jedna, dokud ji neukončíš ty, nebo dokud nevrátíš výpůjčku.
- V detailu uvidíš **etapy po dnech**: kilometry, čas jízdy, průměr a maximum za každý den.
- Pauzy a noci se nepočítají do „stání“ ani do času na cestě.

**Slučování do cesty**
- Libovolné jízdy můžeš **sloučit do jedné cesty** se součty a etapami. Jízdy se přitom nemažou, jen se seskupí.
- Funguje **„Zpět“** i pozdější **„Rozdělit cestu“**.
- Výpůjčka, která se přesto rozpadla na víc jízd, se do cesty seskupí sama. Stává se to třeba u staré verze appky.

**Smysluplné statistiky**

| Co | Jak se počítá |
|---|---|
| ujeto | jen jízda |
| čas jízdy / v sedle | jen jízda |
| na cestě | bez pauz |
| zastávky | krátké stání do 5 min |
| pauzy | delší stání a noci |
| Ø | z času jízdy |
| max | rychlost měřená GPS, ne dopočtená ze skoků polohy |
| nastoupáno | vyhlazené, šum GPS se nepřičítá |
| dny / etapy | počet dní a etap cesty |

- Chůze ani „vlnění“ polohy v pokoji se do km nepočítají.
- Cesta autem po vrácení motorky se do jízdy už nezapíše.

**Baterie**
- Přes noc zůstává GPS zapnuté. Je to jediný způsob, jak ráno samo poznat, že jedeš. Odhad je **5–15 % baterie za noc**.
- Stojí-li záznam v pauze déle než **20 h** (zapomenutá cesta, odpočinkový den), appka GPS vypne. Na Androidu ukáže upozornění „Až vyrazíš, klepni sem“.
- Hodnoty 5 min, 3 min a 20 h jdou měnit z Velína bez vydání verze (feature flag `ride_autopause`).

**Stará appka 4.1.3**
- Funguje dál beze změny.
- Na novém serveru se jí výpůjčka už nedělí na dny a statistiky jsou rozumné.
- Tlačítko pauzy nemá.

**Nová appka na starém serveru**
- Pauza i automatická pauza fungují v telefonu.
- Přes noc se jízda ale dál rozdělí, jako dnes. Nic se přitom neztratí.
- Slučování je skryté, dokud se nenasadí SQL.

---

## 1. Principles and non-goals

1. **One stream for the whole recording (riding, armed, auto-pause)**, with the same geolocator settings as today. Only a manual or deep pause cancels the stream. Resume after a cancelled stream only happens with the app in the foreground (Android FGS rule, iOS when-in-use rule).
2. **The client decides motion; the server decides time accounting.**
   - Points the client uploads are riding points only.
   - Pause boundaries travel as explicit events.
   - The server never trusts the client's stats. It computes everything from points and events.
3. **Never split.** No server rule ends a protocol-2 ride because of silence or age. Only these end it:
   - the rider (finish),
   - the rental end,
   - 7 days without any contact,
   - a 30-day safety cap,
   - an admin.
4. **Non-destructive merge.** Trips group rides. Tracks and stats stay on the rides, so undo is trivial and the 4000-point problem never applies to merges.
5. **Old clients are first-class.**
   - Existing RPC names keep their signatures and their return keys.
   - `append_ride_track` never returns a new error code.
   - Server-side inference gives 4.1.3 sane stats and no rental split.
6. **No new packages and no new permissions.** Detection uses GPS only (Doppler speed, displacement, accuracy).

Non-goals in this iteration:
- activity recognition (taxi, bus, ferry or bicycle will auto-resume — known limitation);
- editing or cutting part of a track;
- a low-power GPS mode switched in the background;
- iOS local notifications (no package — §9.5);
- recomputing historic rides.

---

## 2. Data model

### 2.1 `user_rides` — new columns (all `ADD COLUMN IF NOT EXISTS`)

| Column | Type / default | Meaning |
|---|---|---|
| `proto` | `smallint not null default 1` | 1 = ride driven by old RPC names (4.1.3, 4.2.0-dev). 2 = pause-aware client (`ride_*_v2`). `ride_append_v2` upgrades 1→2. Decides the cron and resume rules (§6). |
| `paused_at` | `timestamptz null` | Start of the **open** pause (= ts of the last riding point, the bike position). `null` = not paused. |
| `pause_kind` | `text null`, CHECK in (`armed`,`auto`,`manual`) | `armed` = recording opened but nothing ridden yet. Deep pause is `auto` + `calc->>'deep'`. |
| `paused_sec` | `integer not null default 0` | Sum of **closed** pauses ≥ 60 s (explicit + inferred). The open pause is not included until it closes. |
| `pauses` | `jsonb not null default '[]'` | Closed pauses `[{f,t,k,lat,lng}]` (epoch s; k = `auto`/`manual`/`inferred`), ≥ 60 s only, max 500 (oldest dropped from the list; `paused_sec` keeps the sum). |
| `stages` | `jsonb not null default '[]'` | Per-stage (≈ day) incremental stats (§2.3). |
| `last_seen_at` | `timestamptz null` | Last contact from any client (server `now()` on every append/ping/pause/start of this ride). Separates "phone alive and paused" from "phone dead". |
| `calc` | `jsonb not null default '{}'` | Internal incremental state: `ema`, `ref` (elevation), `still_from` (proto-1 stationary run start ts), `deep` (bool), `v` = 2 once any batch used stats v2. Not shown anywhere. |
| `trip_id` | `uuid null` FK → `user_trips(id)` `on delete set null` | Trip membership. |
| `no_auto_trip` | `boolean not null default false` | Rider ungrouped an automatic rental trip, so never auto-group this ride again. |

Indexes:
- `idx_user_rides_trip (trip_id) where trip_id is not null`
- `idx_user_rides_open_proto (proto, last_seen_at) where is_recording` (for the cron)

`uq_user_rides_recording` stays. One open ride per user is still correct, because a paused trip is the open ride.

Column comments (Czech) are added for every new column (STATE_1/2 text in `STATE_PATCH.md` at implementation).

### 2.2 New table `user_trips`

```sql
create table if not exists public.user_trips (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  booking_id uuid null references public.bookings(id) on delete set null,
  kind text not null default 'merged' check (kind in ('merged','rental')),
  name text not null default '',            -- '' = app composes a localized default
  description text,
  cover_image text,
  visibility text not null default 'private' check (visibility in ('private','public')),
  status text not null default 'approved' check (status in ('approved','hidden')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now());
```

- Indexes:
  - `(user_id, created_at desc)`
  - unique partial `(booking_id) where kind = 'rental'` — one automatic trip per rental.
- Trigger: `set_updated_at`.
- RLS on:
  - `user_trips_owner` FOR ALL `using (user_id = auth.uid()) with check (user_id = auth.uid())`
  - `user_trips_admin` FOR ALL `using (is_admin())`
- The app writes only via RPC. Velín reads the table directly (admin policy).

### 2.3 JSON shapes

Point (unchanged layout, both protocols): `[lat, lng, ts, kmh, alt?]`.

Changes in what the v2 client puts in it:
- `ts` = fix time in epoch seconds with **one decimal** (the existing regex `^[0-9]+(\.[0-9]+)?$` already accepts it).
- `kmh` = Doppler only when valid (§8.1), else `0`.
- `alt` only when `!hasAltitudeAccuracy || altitudeAccuracy ≤ 20 m`.

Event (v2 only, `p_events` array):

```json
{"t":"pause","ts":1792000000.0,"k":"auto|manual","r":"stopped|walking|signal|manual|stop"}
{"t":"resume","ts":1792003600.0,"k":"auto|manual"}
{"t":"ping","ts":1792001800.0,"s":"armed|paused|deep|riding","lat":49.1,"lng":16.6}
```

- `pause.ts` = ts of the **last riding point** (the anchor, already in the batch or stored).
- `resume.ts` = ts of the **first riding point after the pause** (first pre-roll point).
- `ping.lat/lng` only while `armed` (live position at the branch for Velín).

Stage element (`stages[i]`, epoch seconds):

```json
{"f":start_ts,"t":last_riding_ts,"km":12.345,"mv":2710,"gap":0,"ps":900,
 "gain":214,"max":118.4,"a":[lat,lng],"b":[lat,lng]}
```

- `ps` = pauses inside the stage that did not start a new stage.
- Stage idle (derived) = `(t−f) − mv − gap − ps`, clamped to ≥ 0.

### 2.4 Trip cleanup trigger

`trg_user_rides_trip_cleanup` AFTER UPDATE OF trip_id OR DELETE ON user_rides:
- For `OLD.trip_id`, if fewer than 2 rides remain:
  - set the remaining ride's `trip_id = null`,
  - delete the trip.
- Guard with `pg_trigger_depth() < 2`.

This keeps "a trip has ≥ 2 rides" true without any RPC having to remember it (covers `delete_user_ride` and discarded < 1 km rides).

---

## 3. Stats v2 (exact definitions) — `_ride_stats2` inside `_ride_ingest`

Constants:

| Name | Value | Note |
|---|---|---|
| `c_move_dopp` | 7 km/h | walk→run transition is 7.2 km/h; walking 4–6 never counts |
| `c_move_derived` | 20 km/h with dt ≥ 10 s | only when **both** ends have kmh = 0 (no Doppler); rejects Wi-Fi drift (≤ 12 km/h at 60 s spacing) |
| `c_gap_dt` | 180 s | silence threshold (as today) |
| `c_gap_v` | 15 km/h with d > 0.3 km | "rode through" a silence |
| `c_pause_min` | 300 s | inferred pause (silence, or proto-1 stationary run) |
| `c_jump_v` | 250 km/h | GPS jump (was 300) |
| `c_jump0_km` | 0.5 km | as today |
| `c_max_ok` | 250 km/h, and if pair dt ≥ 4 s: kmh ≤ 1.5·v_derived + 20 | Doppler plausibility |
| `c_ema` | α = 0.25 | elevation smoothing |
| `c_hyst` | 6 m | elevation hysteresis |
| `c_spike` | \|Δalt\| > 0.25·d_m + 10 m | altitude spike → ignore that alt |
| `c_pause_rec` | 60 s | shorter closed pauses are dropped (they become idle) |

### 3.1 Pair classification

`p` = previous kept point, `q` = next point; `dt = q.ts − p.ts`; `d` = haversine; `v = d/dt`.

The pair is classified by the first matching rule:

0. **Explicit pause connector**: an explicit pause closed between `p` and `q`. Nothing is counted (the pause duration is already in `paused_sec`).
1. **Bad time**: `dt < 0`. Nothing. (`dt ≥ 86400` is **no longer** bad time; it falls to rule 2.)
2. **Silence**: `dt > 180`.
   - `v ≥ 15` and `d > 0.3` → **GAP**: `gap_sec += dt`. No km. Reset the elevation reference.
   - else if `dt ≥ 300` → **INFERRED PAUSE** `[p.ts, q.ts]`:
     - `paused_sec += dt`;
     - append to `pauses` with `k:'inferred'` and lat/lng = p;
     - stage-boundary check (§3.4);
     - reset the elevation reference.
   - else → **STOP** (time goes to idle by remainder). No km.
3. **Jump**: `v ≥ 250` or (`dt = 0` and `d ≥ 0.5`). Nothing.
4. **Moving**: `p.kmh ≥ 7 or q.kmh ≥ 7`, or (`p.kmh = 0 and q.kmh = 0 and dt ≥ 10 and v ≥ 20`).
   - `km += d`, `moving_sec += dt`;
   - max candidate `q.kmh` (§3.5);
   - elevation step (§3.6).
5. **Non-moving** (slow, walking, drift, jam crawl < 7 km/h). No km and no moving time; the time goes to idle by remainder.
   - Proto 1 only: if `calc.still_from` is null, set `calc.still_from := p.ts`.
   - Proto 1 only: on the next **moving** pair, if `p.ts − still_from ≥ 300`, then:
     - record an inferred pause `[still_from, p.ts]`;
     - remove stored track points strictly inside it (drift squiggles);
     - set `still_from := null`.

For proto 2 the still-run inference is **off**: the client already pauses on stationarity and walking, so a 10-min jam crawl stays "riding".

Points without ts (very old clients) behave exactly as today: km is counted and no time.

### 3.2 Ride-level values (after every batch and at finalize)

- `end_ts` = `paused_at` if paused, else `last riding point ts` (finalize: §5.5).
- `elapsed_sec = end_ts − started_at`
- `active_sec = max(0, elapsed_sec − paused_sec)`
- `distance_km` = Σ km of moving pairs. Incremental, never recomputed from the track.
- `moving_sec` = Σ moving dt.
- `gap_sec` = Σ gap dt.
- **`idle_sec = max(0, active_sec − moving_sec − gap_sec)`** — always the remainder, so it is consistent by construction. Trimmed walking tails and late Stop can never inflate it.
- **`duration_min = round(active_sec / 60)`** — semantic change: "na cestě bez pauz". For rides without pauses this is identical to today. Old apps and Velín showing "celkový čas" automatically get a sane value.
- `avg_speed_kmh = distance_km / (moving_sec/3600)` when `moving_sec ≥ 60`, else null; cap 200.
  - The finalize fallback `km/active` is kept only for rides without any timestamps.
- `max_speed_kmh` = max over plausible Doppler (§3.5).
  - For proto 2 the client's `p_max_speed_kmh` is ignored; in the v1 path it is still accepted but clamped by `c_max_ok` against the batch.
  - The "max ≥ avg" floor is kept (mathematically true and harmless now).
- `elevation_gain_m` = Σ hysteresis gain (§3.6).
- Display-only derived values (computed in app/Velín from columns):
  - `days` = number of distinct Europe/Prague dates of stage starts/ends with stage `mv ≥ 300`;
  - `pause_count` = `jsonb_array_length(pauses)`.

### 3.3 Stats per surface

| Surface | Shows |
|---|---|
| Ride card (old + v2) | date or date range (`5.–11. 10.`); **km**; **v sedle** (`moving_sec`); **Ø**; chip `N dní` if days ≥ 2; photos; moto; badge `● Nahrává se` / `⏸ Pozastaveno` |
| Ride detail grid | ujeto, čas jízdy (moving), na cestě (`duration_min`), zastávky (idle), pauzy (`N× · h min`), Ø, max, nastoupáno, bez signálu (only if > 0), dny, start → konec (date + time). The "body stopy" stat is removed (meaningless after thinning). |
| Ride detail "Etapy" | if `stages ≥ 2`: one row per stage — `Den 2 · út 6. 10. · 412 km · 5 h 02 min · Ø 82 · max 131 · ⛰ 1 840 m`; tap zooms the map to the stage |
| Live recorder (card, dock, home row, nav chip, Android notification) | phase; **km**; **v sedle**; Ø (after ≥ 5 min moving); `den N`; while paused "stojíš od 18:42" |
| Moje zážitky summary | Σ km, Σ v sedle, number of **jízd a cest** (a trip counts as 1), **dny v sedle** (distinct dates), MotoGo vs vlastní km. From the new server summary RPC (§5.7), not from the ≤100 loaded rides. |
| Trip card / detail | Σ of members (§5.6) + days + date range + members list + concatenated etapy |
| Share text | name, date range, `N dní`, km, v sedle (not total time) |
| Velín | §14 |

### 3.4 Stages

- A stage starts at the first riding point (stage 1) and at each **stage-boundary pause**.
- **Stage-boundary pause** (checked when a pause closes, explicit or inferred):
  - the pause overlaps the Prague night window 00:00–05:00 and lasts ≥ 30 min, **or**
  - the pause lasts ≥ 6 h.
- Otherwise the pause adds to the current stage's `ps`.
- Every moving/gap pair adds its deltas to the **last** stage (km, mv, gap, gain, max, `t`, `b`).
- A night ride across midnight without a pause stays one stage.

### 3.5 Max speed

The candidate is `q.kmh` from a **moving** pair, accepted when:
- `q.kmh < 250`, and
- if `dt ≥ 4 s`: `q.kmh ≤ 1.5·v + 20`.

The second rule rejects isolated Doppler spikes while short-dt pairs (iOS 1 Hz) cannot contradict.

Derived speed never feeds max, with one exception: rides whose points never carry Doppler (every kmh = 0). For those, max = max derived v over pairs with dt ≥ 30 s.

### 3.6 Elevation (EMA + hysteresis), with simulation

Applied only on moving pairs where `q` has alt:
1. If `|q.alt − p.alt| > 0.25·d_m + 10` (spike) → skip this alt.
2. `ema := ema + 0.25·(alt − ema)`; on the first alt, or after a gap or pause reset, `ema := alt`, `ref := alt`.
3. If `ema − ref ≥ 6`: `gain += ema − ref` and `ref := ema`.
4. Else if `ema < ref`: `ref := ema`.

State lives in `calc.ema` and `calc.ref`. It is reset on gap and pause and carried across batches.

Simulation (`design_tools/elev.py`, Android spacing max(20 m, v·5 s), 5 reps). Results in metres:

| Case | Truth | Today (≥5 m per step) | **α 0.25 / H 6** |
|---|---|---|---|
| climb 5 % at 80 km/h, σ3 | 300 | 265 | **280** |
| climb 3.5 % at 80 km/h | 300 | 245 | **286** |
| climb 5 % at 40 km/h | 300 | 255 | **288** |
| hairpins 8 % at 30 km/h | 300 | 248 | **286** |
| flat 100 km, σ3 white | 0 | 794 | **10** |
| flat 100 km, σ6 white | 0 | 2 546 | **199** |
| flat 100 km, AR σ4 | 0 | 124 | **120** |
| hills 3–7 % at 60, AR σ4 | 2 650 | 1 676 | **2 358** |
| hills 3–7 % at 90, AR σ4 | 2 610 | 2 175 | **2 182** |

Target accepted by the test plan: climbs within 85–100 % of truth, and flat noise below 250 m per 100 km at σ6. The server replay with the real `world.py` noise must confirm this before release.

---

## 4. Server processing core — `_ride_ingest(p_ride user_rides, p_points jsonb, p_events jsonb, p_proto smallint) returns jsonb`

`_ride_ingest` is an internal SECURITY DEFINER function, REVOKEd from public/anon/authenticated. It is called by `append_ride_track`, `finish_user_ride`, `ride_append_v2` and `ride_finish_v2` with the row already locked `FOR UPDATE`.

1. **Build items.**
   - Points: drop non-arrays and NULL lat/lng.
   - Events: drop unknown `t` values. Clamp `ts` to `[started_at − 1 h, now() + 1 h]`, else ignore.
   - Sort by `(ts, rank)` with rank `resume 0 < point 1 < pause 2 < ping 3`.
   - Cap: 1000 points and 100 events per call. Excess is ignored, and the response says `truncated:true`. The v2 client sends ≤ 500 points.
2. **Load state.**
   - `prev` = last stored track point.
   - `paused` = `paused_at is not null`.
   - `ret` = `bookings.returned_at` of `booking_id`, if set.
3. **Loop over items.**
   - **Point `q`:**
     - Skip (counted in `dropped`) when any of these holds:
       - `q.ts ≤ prev.ts` — dedup and retry safety; fixes today's double counting on a lost append response;
       - `q.ts < started_at − 1 h` — stale, as today;
       - `ret` is set and `q.ts > ret + 120 s` — after the return; set flag `booking_ended`.
     - If `paused`:
       - proto 2 → skip (a point inside an open pause without a resume);
       - proto 1 path (old RPC on a paused proto-2 ride, i.e. a second device) → implicit `resume` at `q.ts`.
     - Classify the pair `(prev, q)` per §3.1. Append `q` to the track. `prev := q`.
     - Update `last_fix_at = to_timestamp(q.ts)` with today's sanity clamp, plus `end_lat/lng`.
     - If no stage exists yet → create stage 1 (`f = q.ts`).
   - **Pause** (`ts`, `k`):
     - If already paused:
       - `k='manual'` over `auto`/`armed` → set `pause_kind='manual'`;
       - `k='auto'` over `manual` → set `pause_kind='auto'` (manual "Pokračovat" = now waiting for motion).
       - Nothing else changes.
     - Else:
       - If `ts < prev.ts`: trim stored track points with `ts > pause.ts` (walking tail already uploaded). Their stats are not reverted — they were non-moving by §3.1, so km and moving are unaffected and idle is a remainder anyway. `prev` := last remaining point.
       - `paused_at := to_timestamp(greatest(ts, prev.ts))`, `pause_kind := k`.
       - `end_lat/lng := prev` (the bike).
       - `calc.still_from := null`.
   - **Resume** (`ts`, `k`):
     - If not paused → ignore.
     - If `pause_kind='armed'` and the ride has no moving time yet:
       - `started_at := to_timestamp(ts)` (the ride starts at departure);
       - clear the track;
       - the armed period is not a pause.
     - Else:
       - `dur = ts − paused_at`.
       - If `dur ≥ 60`:
         - append to `pauses`, `paused_sec += dur`;
         - stage-boundary check → close the current stage at `paused_at` and open a new stage at `ts`, or add `dur` to the stage's `ps`;
         - mark a connector so the pair `(prev, next point)` is rule 0.
       - If `dur < 60` → no entry (it becomes idle).
     - `paused_at := null`, `pause_kind := null`. Reset `calc.ema/ref`.
   - **Ping:**
     - `last_seen_at := now()`.
     - If `s='armed'` and lat/lng are present → `end_lat/lng`, `last_fix_at := to_timestamp(ts)`.
     - If `s='deep'` → `calc.deep := true`. Any later point or resume sets `deep := false`.
4. **Track.**
   - `track := _ride_track_thin(track, cap)` with `cap = least(12000, 4000 + 2000·(stages−1))`.
   - Thinning only when length > cap, down to 0.85·cap.
5. **Derived values** per §3.2. Set `last_seen_at := now()` and `calc.v := 2`.
6. **Booking end.** If `booking_ended`, call `_ride_finalize(id, ret)` and report `finished:true, reason:'booking_ended'`. This fixes N9 (car drive after the return) and N10 (junk continuation rides).

`_ride_track_thin(track, cap)` is an IMMUTABLE, distance-uniform decimation that replaces `_ride_track_cap` in all write paths:
- Compute the path length L (skipping time jumps > 180 s). `step = L / (0.85·cap)`.
- Keep:
  - the first and last point;
  - every point where the accumulated path distance since the last kept point ≥ step;
  - both edges of every time jump > 180 s (pause and gap edges).
- It is idempotent-ish: repeated application does **not** thin old days exponentially, which is what today's "every k-th point" does on a multi-day track.
- `_ride_track_cap` stays unchanged for `admin_booking_live_ride` previews.

---

## 5. RPCs

All new RPCs have **new names and no DEFAULT parameters**, and are granted to `authenticated` only. Existing names keep **identical signatures** (CREATE OR REPLACE) and identical response keys. No overloads (checked in §19).

### 5.1 `ride_start_v2(p_booking_id uuid) returns jsonb` — new
- `p_booking_id` = null → own-bike recording. The client passes the booking id **only if the watcher considers it picked up and not returned**, so the server's date matching (N10/#9) is gone for v2.
- If the booking id is given and it is not the user's, or not `reserved/active`, or `returned_at` is set → `{success:false, error:'booking_not_active'}`.
- If an open ride exists:
  - same booking (any proto, any age) → **resume**;
  - own and `p_booking_id` null → **resume**. The client only calls start for a "new" ride after the rider chose "Ukončit" in the reconcile sheet (§7.5), so an open own ride here means continuation.
  - otherwise (rental start while an own trip is open, or a different booking) → `_ride_finalize` of the other ride at its `paused_at`/`last_fix_at`, then create.
- Create:
  - `proto=2, source='auto', is_recording=true`;
  - `paused_at=now(), pause_kind='armed'`;
  - `last_seen_at=now()`, empty track, booking/moto as today.
  - Then `_ride_autotrip(booking)` (§5.6).
- Returns:

  ```json
  {"success":true,"id":"…","resumed":false,"booking_id":"…","moto_name":"…","proto":2,
   "phase":"armed|riding|paused","paused_at":"…","pause_kind":"…","started_at":"…",
   "stats":{"km":…,"moving_sec":…,"idle_sec":…,"gap_sec":…,"paused_sec":…,
            "gain_m":…,"max_kmh":…,"stages":n,"duration_min":…}}
  ```

### 5.2 `ride_append_v2(p_ride_id uuid, p_points jsonb, p_events jsonb) returns jsonb` — new
- Locks the row and checks the owner.
- If the ride is closed → `{success:false, error:'ride_finished', finished:true, reason:'closed'|'booking_ended'|'admin', saved:{id,km}}`.
- Sets `proto := 2`.
- Runs `_ride_ingest`.
- Returns `{success:true, points:n, dropped:n, state:{phase, paused_at, pause_kind, ...stats}}` — the same `stats` object as 5.1.
- Errors: `not_authenticated`, `ride_not_found`, `points_required` (points or events not arrays).

### 5.3 `ride_finish_v2(p_ride_id uuid, p_points jsonb, p_events jsonb, p_name text) returns jsonb` — new
1. Ingest the batch, then set the name (≤ 120 characters) when non-empty.
2. End time:
   - if paused → `paused_at`;
   - else → the last riding point ts;
   - rental → `least(that, returned_at)` when `returned_at` is set;
   - never later than `now()`.
3. `_ride_finalize(id, end)`.
4. Returns the finalize JSON (`success, discarded, id, distance_km, duration_min, moving_sec, idle_sec, gap_sec, paused_sec, days`).
5. A ride that is already closed returns its stored values (`already_finished:true`) — the same idempotency as today.

### 5.4 `ride_current_v2() returns jsonb` — new
- Returns the user's open ride (any proto) as `{id, booking_id, proto, phase, paused_at, pause_kind, started_at, last_fix_at, last_seen_at, deep, stats}`, or `{id:null}`.
- Used on restore and on app resume to reconcile (N3: the morning "recording" lie, admin closes, a second device).

### 5.5 Changed bodies of existing names (same signatures, same keys)

| Function | Change |
|---|---|
| `append_ride_track(p_ride_id, p_points, p_max_speed_kmh)` | Body = lock → closed? `ride_finished` (as today) → `_ride_ingest(..., '[]', proto)` with `proto` = the ride's stored proto (1 for old rides) → same return keys `success, points, distance_km, moving_sec, idle_sec, gap_sec` (+ `dropped_stale` when everything was stale). A booking-ended batch returns **`ride_finished`** (already handled by 4.1.3 as "forget"; no new code). Points after `returned_at + 120 s` are dropped. Dedup `ts ≤ last`. |
| `start_user_ride(p_booking_id, p_lat, p_lng)` | Open-ride rule: proto 2 → resume (never finalize for staleness); proto 1 **with an active booking equal to the requested or date-matched one → resume at any age** (one rental = one ride for 4.1.3); otherwise today's 3 h rule. Creation unchanged (proto 1, first point when coords are given). Calls `_ride_autotrip`. |
| `finish_user_ride(p_ride_id, p_points, p_name)` | Ingest as above. End = paused → `paused_at`; proto 1 with fixes → `least(now(), last_fix_at + 120 s)` (N8 late Stop); rental → `least(..., returned_at)`, as today. Same return keys. |
| `_ride_finalize(p_ride_id, p_ended_at)` | Idempotent as today. Clamp `end ≤ paused_at` if paused. For proto 1 with `calc.still_from` and `end − still_from ≥ 300` → `end := still_from` (trailing stationary period trimmed). Close the last stage at `end`. Values per §3.2 (`duration_min` = active, idle = remainder). Name fallback: single day `DD.MM.YYYY` (as today), multi-day `DD.MM.–DD.MM.YYYY` (Prague dates). < 1 km → delete (as today; the trip trigger cleans up). Same return keys + `paused_sec`, `days`. Keeps the REVOKE. |
| `close_stale_user_rides()` | §6 rules. Same name, same cron job (`*/15`). |
| `_ride_json(user_rides)` | **Adds** keys `proto, paused_at, pause_kind, paused_sec, pauses, stages, last_seen_at, trip_id, deep` (= `calc->'deep'`), `elapsed_min`. Old apps ignore unknown keys (verified: `UserRide.fromJson` reads named keys only). |
| `admin_booking_live_ride(p_booking_id)` | Adds `is_paused, paused_at, pause_kind, last_seen_at, deep`; `is_live = is_recording and paused_at is null and fix age < 900`. |
| `admin_finish_user_ride(p_ride_id)` | Unchanged body; `_ride_finalize` handles paused rides. |
| `get_my_rides`, `get_booking_rides`, `get_public_rides` | Unchanged bodies; they inherit the new keys via `_ride_json`. |

### 5.6 Trips — new RPCs (all `authenticated`, owner-checked; error codes in brackets)

| RPC | Semantics |
|---|---|
| `trip_merge_v2(p_ride_ids uuid[], p_name text)` | All rides are the user's [`not_found`]; together with already-existing trips of those rides there must be ≥ 2 rides [`too_few`]; ≤ 100 [`too_many`]. Rides already in trips → those trips are dissolved into the new one. `booking_id` = the common booking if all members share one, else null. `kind='merged'`. Members get `no_auto_trip=false`. Returns `{success, trip_id, ride_ids, dissolved_trip_ids}` (enough for undo). |
| `trip_add_v2(p_trip_id uuid, p_ride_ids uuid[])` | Adds rides; rides that are in another trip are moved. |
| `trip_remove_v2(p_trip_id uuid, p_ride_id uuid)` | `trip_id := null`; for a `rental` trip also `no_auto_trip := true`. The trigger deletes the trip if < 2 members. Returns `{success, trip_deleted}`. |
| `trip_ungroup_v2(p_trip_id uuid)` | **Undo / Rozdělit cestu**: members `trip_id := null` (rental → `no_auto_trip := true`), delete the trip. Returns `{success, ride_ids}`. |
| `trip_update_v2(p_trip_id uuid, p_name text, p_description text, p_visibility text, p_cover_image text)` | Null = keep (as `update_user_ride`). Visibility **cascades to members** (the public feed stays ride-based). |
| `trip_delete_v2(p_trip_id uuid, p_delete_rides boolean)` | false = ungroup; true = delete the member rides (cascade points), then the trip. |
| `get_my_trips_v2()` | `[_trip_json]` of the user's trips (≤ 200, newest first). |
| `ride_summary_v2()` | `{rides, trips, units (rides outside trips + trips), km, moving_sec, days, motogo_km, own_km, recording_id}` over **all** the user's rides (fixes N14 truncation). |

`_trip_json(trip)`:
- `{id, kind, name, description, cover_image, visibility, booking_id, created_at, ride_ids[] (by started_at)}`
- `started_at` = min, `ended_at` = max (null if any member is recording), `is_recording` = any
- `distance_km` Σ, `moving_sec` Σ, `idle_sec` Σ, `gap_sec` Σ
- `paused_sec` = Σ + Σ **inter-ride intervals** (between consecutive members)
- `duration_min` = Σ (active), `elevation_gain_m` Σ, `max_speed_kmh` max, `avg` = Σkm/Σmoving
- `days` = distinct Prague dates over the members' stages (rides without stages: start and end dates when `moving_sec ≥ 300`)
- `stages` = concatenation of `{ride_id, …stage}` (a ride without stages = one synthetic stage from its totals)

`_ride_autotrip(p_booking_id)` (internal):
- When a booking has ≥ 2 rides with `no_auto_trip = false`, ensure the `rental` trip exists (insert … on conflict on the unique booking index) and set its `trip_id` on those rides that have none.
- Called from both start RPCs and from the optional backfill (§18).

### 5.7 Grants

- `grant execute on function … to authenticated` for every new RPC.
- `revoke all … from public, anon` for every new RPC.
- Internal helpers (`_ride_ingest`, `_ride_track_thin`, `_ride_autotrip`, `_ride_stage_close`) are revoked from public, anon and authenticated.

---

## 6. Cron `close_stale_user_rides()` — new rules

Evaluated for open rides, in this order:

| # | Ride | Condition | End time |
|---|---|---|---|
| C1 | any with booking | booking `returned_at` not null, or status `completed`/`cancelled`, or `end_date::date < current_date` (Prague) | `least(greatest(last_fix_at, started_at), coalesce(returned_at, ∞))`, or `paused_at` if paused |
| C2 | proto 1, no booking | no contact (`greatest(last_fix_at, updated_at, last_seen_at)`) for **20 h** (was 3 h) | last activity → finalize trims the trailing still-run |
| C3 | proto 1, booking still active | no contact for **72 h** (app gone mid-rental) | last activity |
| C4 | proto 2, any | no contact (`last_seen_at`) for **7 days** | `paused_at` if paused, else `last_fix_at` |
| C5 | any | `started_at < now() − 30 days` (replaces the 36 h cap) | as C4 |

Unchanged: batch of 500, an exception block per ride, the return `{closed, discarded}`.

Why 20 h for 4.1.3 own-bike rides:
- 4.1.3 keeps its FGS overnight. A next-morning batch then continues the same ride (today: silent loss of day 2).
- An explicit 4.1.3 restart after > 3 h still creates a new ride (start rule unchanged).

---

## 7. Client state machine (shared Dart, both trees)

### 7.1 Phases (`RidePhase`)

| Phase | Meaning |
|---|---|
| `idle` | no open ride |
| `armed` | ride open, stream on, waiting for the first riding |
| `riding` | normal recording |
| `stopPending` | slow; points held back (≤ 5 min) |
| `signalLost` | silence after ≥ 30 km/h; decided at the next fix |
| `pausedAuto` | stream on, nothing uploaded, waiting for motion |
| `pausedManual` | stream **cancelled**; resume only by tap |
| `pausedDeep` | stream **cancelled** after 20 h of auto-pause; resume on app open (rental) or by choice (own) |

`RideRecorderState` keeps every existing field.
- `recording` now means **session open**: true in every phase except `idle`. This keeps the watcher from re-starting a paused ride.
- New fields:
  - `phase`, `pausedAt`, `pauseKind`, `proto` (1|2);
  - `live` (`RideLive{km, movingSec, pausedSec, stage, since}`);
  - `serverV2` (bool?).
- Getters `isPaused` and `isLive`.

Consumers outside this work (`home_ticket_checklist.dart`) still read `recording` = "auto-recording active", which remains truthful.

### 7.2 Transitions

| From | Trigger | To | Server items queued | Stream |
|---|---|---|---|---|
| idle | tap "Zaznamenat jízdu" / watcher (rental active) | armed | `ride_start_v2` (creates the armed pause); first good fix → `ping{s:armed,lat,lng}` | attach (foreground) |
| armed | resume rule (§8.4) | riding | `resume{k:auto, ts=pre-roll start}` + pre-roll points | keep |
| riding | fix with valid Doppler < 10 km/h (or no Doppler and derived < 10 over ≥ 10 s) | stopPending (anchor = last point with Doppler ≥ 8) | — (hold) | keep |
| riding | tick: silence ≥ 3 min after last Doppler < 30 | stopPending (anchor = last point) | — | keep |
| riding | tick: silence ≥ 3 min after last Doppler ≥ 30 | signalLost | — | keep |
| stopPending | 2 consecutive valid Doppler ≥ 10 km/h | riding | held points released | keep |
| stopPending | stationary 5 min since anchor | pausedAuto | `pause{k:auto,r:stopped,ts=anchor.ts}`; held dropped | keep |
| stopPending | walking evidence 3 min | pausedAuto | `pause{k:auto,r:walking,ts=anchor.ts}`; held → tail | keep |
| signalLost | next fix, v ≥ 15 km/h | riding | point (server: gap) | keep |
| signalLost | next fix, d ≤ max(R_STILL, 150 m), dt ≥ 5 min | pausedAuto | `pause{r:signal, ts=last.ts}` | keep |
| signalLost | next fix, otherwise | pausedAuto | `pause{r:walking, ts=last.ts}` | keep |
| pausedAuto | resume rule | riding | `resume{k:auto}` + pre-roll (+ tail restore §8.5) | keep |
| pausedAuto / armed | continuous ≥ `deepPauseH` (20 h) | pausedDeep | `ping{s:deep}` then flush | **cancel** after flush; Android notice §9.4 |
| armed / riding / stopPending / signalLost / pausedAuto | tap "Pozastavit" | pausedManual | `pause{k:manual, ts=anchor or last kept}` | **cancel** |
| pausedManual | tap "Pokračovat" (foreground) | pausedAuto (waiting) | `pause{k:auto}` (kind switch only) | attach |
| pausedDeep | app foreground + rental active | pausedAuto | `ping{s:paused}` | attach |
| pausedDeep (own) | rider chooses "Pokračovat v cestě" | pausedAuto | `ping{s:paused}` | attach |
| any open | tap "Ukončit" / rental ended / `booking_ended` | idle | `ride_finish_v2` (stopPending → pause at the anchor first; held dropped) | cancel |
| any open | append → `ride_finished` `reason:closed\|admin` | rental with an active booking → **armed** in a new ride (continuation); own → idle + info snackbar (no silent stop) | — | rental keep / own cancel |
| any open | append → `ride_finished` `reason:booking_ended` | idle (no continuation, N10) | — | cancel |

Watcher additions (`ride_recorder_watcher.dart`, foreground only):
- Rental active and the open session is an **own** ride in `armed`/`paused*`:
  - `finishOwnForRental()` (ends it at its pause) and start the rental ride;
  - snackbar `ridePOwnSavedForRental`.
- Rental active and `pausedDeep` and not manual → `n.wakeFromDeep()` (attach, `pausedAuto`).
- `pausedManual` → never auto-attach (Strava convention). The "Pokračovat" banner is shown.
- The stop branch (rental ended) works in every phase.

### 7.3 Persistence (SharedPreferences; add **all** keys to `_preserveKeys` in `core/cache_cleanup_service.dart` in BOTH trees)

| Key | Content |
|---|---|
| `mg_ride_session` | JSON v1: `{phase, rideId, bookingId, manual, proto, pausedAt, pauseKind, anchor:[lat,lng,ts], lastFixTs, lastKept, live, deepSince}` |
| `mg_ride_evq` | queued events (JSON list), sent with the next flush |
| `mg_ride_srv_caps` | `{v2:bool, at:epoch}` |
| `mg_ride_flags` | cached `ride_autopause` flag + conditions |
| existing `mg_ride_rec_id`, `mg_ride_rec_buf`, `mg_ride_rec_manual`, `mg_ride_autorecord` | unchanged |

Held points (stopPending) and the pre-roll ring are **not** persisted: at most 5 min, and losing them on a kill is acceptable.

### 7.4 Restore and resume

- `_restore()` reads `mg_ride_session`.
  - `riding`, `stopPending` or `signalLost` → restored as **signalLost**, so the next fix decides retroactively (§8.6).
  - `armed` and `pausedAuto` restore as they are.
  - `pausedManual` and `pausedDeep` → **no attach**.
  - Manual rides attach as today; rental rides wait for the watcher. `_start` for an open v2 ride gets `resumed:true` plus the server phase. The client adopts the server phase when it is "more paused" than local; otherwise it keeps local.
- `onAppResumed()` (foreground) and `_restore()` call `ride_current_v2()` (throttled to 1 per 5 min):
  - server has no open ride, or a different id → handled as `ride_finished` per §7.2, plus snackbar `ridePSavedMeanwhile`;
  - server has an open ride but the local session is `idle` (reinstall, second device):
    - own → reconcile sheet (§13.1 F);
    - rental → adopt.
- Re-attach rules from PR #2208 (`resume_no_fix` etc.) stay, but are skipped in `pausedManual`/`pausedDeep`. A re-attach never counts as motion: the detector ignores the first fix after any attach when `pos.timestamp < attachedAt − 30 s` (existing `notBefore`).

### 7.5 Starting a manual ride when the server already has an open own ride

The start button calls `ride_current_v2` first. If an open own ride exists, the sheet "Máš rozjetou cestu z {date} ({km} km)" offers:
- **Pokračovat v cestě** → adopt and attach, `pausedAuto`;
- **Ukončit ji a začít novou** → `ride_finish_v2`, then `ride_start_v2(null)`.

---

## 8. Detection algorithm (pure Dart class `RideMotionDetector`, file `ride_motion.dart`)

Inputs: every raw `Position`, converted to `RideFix{ts, lat, lng, acc?, kmh?, kmhValid, alt?}`. This happens **before** `ridePointFromFix`, because the 20 m filter would hide slow movement. A `tick(now)` comes from the existing 90 s timer, plus a 30 s timer only while `stopPending`.

Outputs: decisions `keep(point)`, `hold(point)`, `release()`, `pause(anchor, reason)`, `resume(fromTs, prerollPoints, restoreTail)`, `signalLost`.

All constants live in `RideMotionConfig`. The defaults are below; `feature_flags.ride_autopause.conditions` can override `stop_min`, `walk_min`, `deep_h`, `resume_kmh`.

### 8.1 Fix quality
- **Good fix:** `hasAccuracy && acc ≤ 25 m`, and fix age at receipt ≤ 30 s.
- **Usable fix:** `acc ≤ 50 m`.
- **Valid Doppler:** `(hasSpeed || speed > 0) && (!hasSpeedAccuracy || speedAccuracy ≤ 2.5 m/s)`. Never use `verticalSpeed` (Android-only API).
- The first fix after attach that is older than `attachedAt − 30 s` is ignored (iOS cache).

### 8.2 Thresholds

| Name | Value |
|---|---|
| `V_STILL` | < 3 km/h |
| `V_WALK_MAX` | ≤ 8 km/h |
| `V_SLOW_RIDE` | ≥ 10 km/h on 2 consecutive valid fixes (leaves stopPending) |
| `V_RESUME` | ≥ 20 km/h on 2 consecutive valid fixes ≤ 15 s apart, the second ≥ 100 m from the anchor |
| `RESUME_NO_DOPPLER` | two good fixes ≥ 300 m apart within ≤ 60 s, the later one ≥ 300 m from the anchor |
| `R_STILL` | clamp(1.5 × median acc of the last 5 usable fixes, 40 m, 100 m) |
| `T_STOP` | 5 min (stationary inside R_STILL, or silence after slow) |
| `T_WALK` | 3 min of walking evidence: ≥ 3 valid Doppler fixes in 3–8 km/h and none ≥ 10; **or** ≥ 150 m from the anchor on usable fixes at implied ≤ 8 km/h |
| `T_SILENCE` | 3 min without a fix |
| `V_TUNNEL` | last valid Doppler ≥ 30 km/h before silence → signalLost (never a timed pause) |
| Pre-roll ring | ≤ 120 s and ≤ 40 fixes |
| `DEEP_PAUSE` | 20 h continuous armed/pausedAuto |

### 8.3 Hold-back (no tail ever reaches the server in the normal case)

- In `stopPending`, points that pass `ridePointFromFix` go to `_held`, not `_buffer`.
  - On `release()` they move to `_buffer` in order.
  - On `pause` they are dropped (stationary) or moved to `_tail` (walking, kept until resume).
- `stop()` while `stopPending` → `pause` at the anchor is queued, held points are dropped, then finish runs. The end point is the bike, not the hotel room.

### 8.4 Resume and pre-roll
- In `armed`/`pausedAuto` every fix goes to the ring and is checked against the resume rule.
- On resume, `fromTs` = ts of the earliest fix of the contiguous run (backwards from the trigger) with valid Doppler ≥ 8 km/h, or the trigger's first fix if there is none.
- Ring fixes with `ts ≥ fromTs` → `ridePointFromFix(fix, last: anchorPoint)` → `_buffer`.
- `resume.ts = fromTs`. The server drops anything strictly between pause and resume.

### 8.5 Tail restore (slow crawl, not a walk)
- Applies only when the pause reason was `walking`.
- Condition: the first riding fix is ≤ 100 m from the tail's last point **and** ≥ 150 m from the anchor.
- Then queue `resume{ts = tail[0].ts}` instead. The pause shrinks to seconds and is dropped server-side (< 60 s). Upload `_tail` followed by the pre-roll.

### 8.6 Silence (retroactive, works even if no timer fired)

At any fix with `dt = fix.ts − last.ts > 180 s`, compute `d` and `v`:
- `v ≥ 15 km/h` → riding through (server: gap);
- `d ≤ max(R_STILL, 150 m)` → stationary: pause at `last.ts` if `dt ≥ 5 min`, else stopPending;
- else → pause (walking) at the last riding point.

If this fix also satisfies the resume rule (needs the 2nd fix), both the pause and the resume are queued.

### 8.7 Unit-test scenarios (synthetic traces; `FakeGeo extends GeolocatorPlatform`; `has*` flags set)

1. 60 km/h → 90 s red light → ride: no pause.
2. Ride → stop → silence 12 h → 2 × 25 km/h: one pause at the stop; pre-roll; one ride.
3. Ride → stop → walk 4–6 km/h for 10 min/600 m → back → ride: walk-pause at ~3 min; tail discarded; resume at the anchor.
4. Ride → crawl 6 km/h for 5 min → ride on from the crawl end: tail restored, pause < 60 s.
5. 90 km/h → silence 4 min → fix 6 km ahead: signalLost → riding; no pause.
6. Indoor jitter: acc 40–80 m, no Doppler, 30–60 m jumps: stays paused.
7. A single 25 km/h Doppler spike while walking: no resume.
8. Two no-speed Wi-Fi fixes 350 m apart within 40 s (twice): fallback resume.
9. Manual pause → stream cancelled; restore and watcher do not attach; "Pokračovat" attaches into pausedAuto.
10. iOS cached first fix after re-attach: ignored.
11. Armed at the kiosk: walk 3 min, ride: `started_at` = departure, no pre-ride points.
12. 20 h pause → deep: flush then cancel; rental + foreground → wake; own → sheet.
13. Kill while riding → restore → stationary fixes → pause at the restore-time last point.
14. Stop while walking → end = anchor.
15. Navigation open (4 m stream shared): same decisions.

---

## 9. Battery and platform settings

### 9.1 Stream settings — **unchanged**, identical API in geolocator 14.1.1 and 10.1.1

- **Android:** `AndroidSettings(accuracy: high, distanceFilter: 20, intervalDuration: 5 s, foregroundNotificationConfig(title: rideNotifTitle, text: rideNotifText, channelName: 'MotoGo24', enableWakeLock: true, setOngoing: true))`.
- **iOS:** `AppleSettings(accuracy: high, distanceFilter: 20, activityType: automotiveNavigation, allowBackgroundLocationUpdates: true, pauseLocationUpdatesAutomatically: false, showBackgroundLocationIndicator: true)`.
- No settings switch at runtime (not possible in the background on either platform, see the research).

### 9.2 Per phase

| Phase | GPS | CPU / wake lock | Network | Cost [estimate] |
|---|---|---|---|---|
| riding | on, 5 s / 20 m | Android wake lock | batch of 20 points / 90 s | 2–5 %/h |
| armed, pausedAuto | **on** (needed for auto-resume) | wake lock (Android); iOS session | first ping, then **1 ping / 60 min**; no points | ≈ 0.5–1.5 %/h → 5–15 % per night |
| pausedManual, pausedDeep | **off** (stream cancelled → FGS stops / iOS updates stop, blue pill disappears) | none; Android engine may be destroyed (state is persisted) | none | 0 |

A stop or cancel is allowed from the background on both platforms; only a restart needs the foreground. Deep pause is therefore safe from the background, while wake-up needs the app opened (rental) or a choice (own).

### 9.3 Android notification texts per phase (native re-post)

- New method on the existing channel `cz.motogo24/ride`: `notify {title, text}`.
- `MainActivity`/`RideEngineKeeper` posts it only if `GeolocatorLocationService` runs in the foreground (reuse the keeper's check).
- The notification:
  - is rebuilt on channel `geolocator_channel_01` with id **75415** (the same FGS notification, so this is an update, not a second notification);
  - uses the same small icon (`ic_launcher` mipmap), `setOngoing(true)`, `setOnlyAlertOnce(true)`, `setSilent(true)`;
  - has contentIntent = the launch intent.
- Errors are caught and logged (`notif_failed`).
- Dart calls it on a phase change, and at most every 60 s while riding (only when the text changed).

| Phase | Title (cs) | Text (cs) |
|---|---|---|
| armed | Záznam připravený | Začne sám, jakmile se rozjedeš. |
| riding | Nahrávám jízdu | {km} km · {moving} v sedle |
| stopPending | Nahrávám jízdu | {km} km · stojíš |
| signalLost | Nahrávám jízdu | Slabý signál GPS — trasu doplním, až se chytí. |
| pausedAuto | Jízda pozastavená | Stojíš od {HH:MM}. Až vyjedeš, záznam sám pokračuje. |
| GPS service off (existing `gpsLost`) | Záznam čeká na GPS | Zapni polohu, ať se jízda nahrává dál. |

The initial text before the first re-post stays `rideNotifTitle`/`rideNotifText`, unchanged.

### 9.4 Deep-pause notice (Android only, native, id 75416, channel `MotoGo24`)

- Title: **"Záznam cesty spí kvůli baterii"**.
- Text: "Stál přes 20 h, tak jsem vypnul GPS. Až vyrazíš, klepni sem — pokračuju."
- Tapping it opens the app. The notification-tap exemption allows the FGS start; the watcher or rider then wakes the ride.
- It is cancelled on wake, finish or app open.

### 9.5 iOS limits (documented, accepted)

- There is no local-notification package, so deep pause shows only the in-app banner.
- If the OS terminates the app at night, nothing records until the app is opened.
  - The trip stays open; the server infers the pause or gap.
  - For a rental, the watcher re-adopts the ride on open.
- Optional later step (not in this iteration): a server push at 08:00 Prague for deep-paused rides via the existing FCM pipeline.

### 9.6 Measuring

- New `battery` method on the ride channel (Android `BatteryManager`: pct, charging).
- Logged in `rideLog('battery')` on every phase change and hourly ping.
- Velín diagnostics then show the real overnight cost, so the owner can tune `deep_h`.

---

## 10. Point and event pipeline (client)

- **`_buffer`** (points, persisted as today) and **`_evq`** (events, persisted) are flushed together.
  - v2 → one `ride_append_v2(id, points≤500, events)` call.
  - On success, remove what was sent from both.
- `ride_finished` handling per §7.2. Network errors → retry (as today). PGRST202 / 42883 → fallback (§11).
- Pings are only queued when the queue has no ping newer than 50 min.
- The first `ping{armed}` is sent immediately after start (Velín position at pickup), replacing today's "first point sent immediately".
- `ridePointFromFix` changes (shared, both trees):
  - ts to 0.1 s;
  - `kmh = 0` when Doppler is invalid (speedAccuracy > 2.5 m/s);
  - alt dropped when `hasAltitudeAccuracy && altitudeAccuracy > 20`.
  - Everything else is unchanged; existing tests are updated.

---

## 11. Server-capability detection and fallback (new app × old server)

`ride_server_v2.dart` wraps every v2 RPC. It classifies errors as:

| Error | Classification |
|---|---|
| `PostgrestException.code == 'PGRST202'` or `'42883'`, or HTTP 404 on rpc | **missing** → `mg_ride_srv_caps = {v2:false, at}` |
| socket, timeout or client exception | **offline** → retry, caps unchanged |
| anything else | **error** → retry with backoff and log |

Fallback with `v2:false`:
- **Start:** `start_user_ride(p_booking_id)`, as in PR #2208. `proto=1` is stored in the session.
- **Append:** `append_ride_track` with points only. Events are kept local; nothing is uploaded while paused.
  - Manual and auto pause still stop recording locally.
  - Local live stats work: the old append returns `distance_km` and `moving_sec`.
- **`ride_finished`:**
  - rental with an active booking → continuation (as today);
  - **own → continuation too** (new `start_user_ride(null)`), no longer a silent stop.
  - Result: on the old server a night still splits the ride (3 h cron), but nothing is lost.
- **Finish:** `finish_user_ride`.
- **Trips UI:** hidden. Merge entry points are not rendered; trip cards never appear because `get_my_trips_v2` is missing.
- **Re-probe** `ride_start_v2` (or `ride_current_v2`) when the cache is older than 30 min, on app resume or ride start.
  - If it is now available, an ongoing proto-1 ride upgrades on its next flush through `ride_append_v2` (server sets `proto=2`), and queued events go along.
  - Events queued while v2 was missing that are older than the last uploaded point are dropped (they cannot be ordered meaningfully anymore).

---

## 12. Trip UX

**Merge flow (old UI, both trees; v2 Android with the same steps and v2 look)**

1. On a ride card: menu "⋯" or long-press → **"Sloučit s dalšími jízdami…"**.
2. Selection mode: checkboxes on cards. A bottom bar shows **"Vybráno {n}"**, **[Sloučit do cesty]** (disabled below 2) and **[Zrušit]**.
3. The sheet **"Sloučit do jedné cesty"** opens. Body: "Jízdy zůstanou, jak jsou — jen se zobrazí jako jedna cesta se součtem kilometrů a etapami. Kdykoli ji zase rozdělíš."
   - Field **"Název cesty"**, hint "Např. Alpy 2026" (empty = automatic name).
   - CTA **"Sloučit {n} jízd"**.
4. Success snackbar **"Cesta vytvořena · {n} jízd, {km} km"** with action **"Zpět"**. "Zpět" calls `trip_ungroup_v2`, and for dissolved trips re-merges them with `trip_merge_v2`.
5. Errors (meaningful, Czech):
   - `too_few` → "Vyber aspoň dvě jízdy."
   - `not_found` → "Některá jízda už neexistuje nebo není tvoje. Obnov seznam a zkus to znovu."
   - offline → "Sloučení se nepovedlo — nejsi připojený. Zkus to znovu, až bude signál."
   - other → "Sloučení se nepovedlo. Zkus to prosím znovu."

**List**

- Trip card replaces its member rides in the main list:
  - title `🧳 {name || "Cesta {range}"}`;
  - line `{n} jízd · {days} dní · {km} km · {moving} v sedle`.
- Rental trip: `🏍️ {name || "Výpůjčka {moto} · {range}"}`.

**Trip detail** (new screen `trip_detail_screen.dart` + v2 view)

- Header: name (edit) and date range.
- Stats grid: same as the ride detail, aggregated.
- Map: all member tracks, each ride in alternating tone, pauses as "P" dots.
- **Etapy:** concatenated stages.
- **Jízdy v cestě:** cards → ride detail.
- Actions:
  - **Přejmenovat**;
  - **Sdílet**: text `🧳 {name}\n{range} · {days} dní · {km} km · {moving} v sedle\nProjeto s MotoGo24 🏍️`;
  - **Viditelnost**: "Cestu vidí i ostatní" / "Cesta je jen tvoje" (cascades);
  - **Přidat jízdu** (picker);
  - **Rozdělit cestu**: confirm "Rozdělit cestu? Jízdy zůstanou uložené jednotlivě." [Rozdělit] [Nechat];
  - **Smazat cestu**: choice sheet "Jen zrušit seskupení" / "Smazat i všechny jízdy". The second asks to confirm "Smazat {n} jízd včetně fotek? Nejde to vrátit."

**Ride detail**

- Link **"Patří do cesty: {name} ›"**.
- Menu: **"Přidat do cesty…"** / **"Vyjmout z cesty"**, with undo snackbar "Jízda vyjmuta z cesty · Zpět".

**Booking section** (`ride_booking_section.dart`): if the booking has a trip or ≥ 2 rides → header line **"Celkem za výpůjčku: {n} jízd · {km} km"** + trip link.

---

## 13. UI per screen

Old-UI keys are shared (both trees); v2 keys are Android only. Copy is in Czech with *tykání*; all 8 languages are added in the new ext files.

### 13.1 Old UI (both trees)

**A. `my_experiences_screen.dart` → "🛰️ Záznam jízd" card**

The existing card keeps its structure. The status chip is replaced by a phase chip:

| Phase | Chip |
|---|---|
| riding | `⏺ Nahrávám` (existing `rideRecording`) |
| armed | `⏳ Čekám na rozjezd` |
| pausedAuto | `⏸ Stojíš od {HH:MM}` |
| pausedManual | `⏸ Pozastaveno` |
| pausedDeep | `⏸ Pozastaveno · GPS spí` |
| signalLost | `🛰️ Hledám signál` |

- New live row: `{km} km · {moving} v sedle · den {n}`.
- New control row `RideRecorderControls` (new file `ride_recorder_controls.dart`), 44 px targets, semantics labels:
  - open and not paused: **[⏸ Pozastavit]** + (manual) **[⏹ Ukončit jízdu]**;
  - paused: **[▶ Pokračovat]** + (manual) **[⏹ Ukončit jízdu]**;
  - rental: no Stop; note "Záznam výpůjčky se ukončí sám při vrácení motorky."
- One-line explainer under the controls (collapsible "Jak funguje automatická pauza?"): "Když zastavíš na víc než 5 minut nebo půjdeš pěšky, záznam se sám pozastaví. Jakmile se rozjedeš, pokračuje — přes noc nic nemačkáš a vícedenní cesta zůstane jedna."

**B. Manual card**

- Start → `armed` + snackbar "Záznam je připravený — začne, jakmile se rozjedeš."
- The reconcile sheet from §7.5.

**C. Ride list**

- Trip cards.
- Selection mode for merge.
- `RideCard` shows the date range and the `N dní` chip, and swaps the total for "v sedle".

**D. `ride_detail_screen.dart`**

- Grid per §3.3.
- New widget `ride_stage_list.dart` (Etapy).
- Pause markers on `ride_map.dart` (P dot + tooltip "Pauza {HH:MM}–{HH:MM}" / "Noc {date}").
- `_splitOnGaps` also splits at `pauses` and drops the `dt < 86400` condition (N16). A pause connector is not drawn unless d > 0.3 km (dotted).
- New text for `rideGapNotice` (the night is no longer blamed): "Část trasy neznáme — telefon chvílemi neposílal polohu (slabý signál nebo vypnutá appka). Šedé tečkované úseky jsou jen spojnice a do kilometrů se nepočítají. Pauzy a noci se tu nepočítají."

**E. `community_submit.dart` "Přidat" sheet**

- Manual open → rows "Pozastavit záznam" / "Pokračovat v záznamu" + "Ukončit záznam jízdy".
- Rental open → only Pause/Resume.

**F. Reconcile and deep sheets** (new `ride_session_sheets.dart`)

- Deep (own): title "Tvoje cesta je pozastavená od {date time}", body "Stála přes {h} h, tak jsem kvůli baterii vypnul GPS.", buttons **[Pokračovat v cestě] [Ukončit a uložit]**.
- Open-on-server: "Máš rozjetou cestu z {date} ({km} km)", buttons **[Pokračovat v cestě] [Ukončit ji a začít novou]**.

**G. `ride_start_feedback.dart` snackbars**

| Event | Text |
|---|---|
| Pozastaveno ručně | "Jízda pozastavena. GPS je vypnuté, baterie se šetří — pokračuj tlačítkem Pokračovat." |
| Pokračovat | "Pokračuju — jakmile se rozjedeš, nahrávám dál." |
| Saved meanwhile | "Záznam z {date} už je uložený ({km} km). Další jízda se nahraje jako nová." |
| Own trip saved because a rental started | "Tvoje cesta z {date} je uložená — teď se nahrává výpůjčka." |

Resume errors reuse the existing permission and location texts (`showRideStartResult`).

**H. Old navigation screen**

- Today it has no recording UI. Add a compact chip in the existing top status area (new widget, in `route_nav_status.dart`'s file family): `● REC {km} km` / `⏸ PAUZA`.
- Tapping it opens a mini sheet with [Pozastavit/Pokračovat] (+ Ukončit for manual).

**I. `ride_share.dart`**

Text uses the date range, days, km and v sedle.

**J. `ride_booking_section.dart`**

Rental total line + trip link.

### 13.2 v2 (Android only)

| File | Change |
|---|---|
| `home/v2/home_record_row_v2.dart` | Live row shows the phase chip + `{km} km`. A trailing 44 px icon button Pause/Resume; Stop confirm stays for manual. |
| `routes/v2/record_dock_v2.dart` (`_LiveBar`) | Phase label + km; trailing **Pause/Resume** button (always) + `_StopButton` (manual); paused bar tone = neutral (not red ping); `trasyConfirmStopRide` body adds "Pozastavené cesty se ukončí na místě, kde jsi naposledy zastavil." |
| `routes/v2/rides/recorder_parts_v2.dart` (`RecorderLiveCardV2`) | The "N bodů" chip is replaced by a live grid: **ujeto · v sedle · Ø · den**; status text per phase (`NAHRÁVÁM`, `POZASTAVENO`, `ČEKÁM NA ROZJEZD`, `GPS SPÍ`); reduced motion → no ping. |
| `routes/v2/rides/recorder_screen_v2.dart` | Primary CTA toggles **Pozastavit/Pokračovat**; secondary **Ukončit jízdu** (manual); rental hint; auto-pause explainer row with an info icon. |
| `routes/v2/route_nav_skin_v2.dart` (`NavRecChipV2`) | `● REC` / `⏸ PAUZA`; tap → the same mini sheet as 13.1 H (v2 style). |
| `routes/v2/rides/moje_tabs_v2.dart` | Ping only in riding; pause glyph when paused. |
| `routes/v2/rides/moje_summary_v2.dart` | From `ride_summary_v2` when available: Σ km, Σ v sedle, `jízd a cest`, `dny v sedle`, MotoGo/vlastní split; fallback = today's sums. |
| `routes/v2/rides/moje_cards_v2.dart`, `ride_card_v2.dart` | Trip card variant; date range + `N dní` chip; v sedle. |
| `routes/v2/rides/moje_lists_v2.dart` | Long-press selection → dock CTA "Sloučit do cesty ({n})" → `ride_merge_sheet_v2.dart` (new). |
| `routes/v2/rides/ride_detail_parts_v2.dart`, `ride_detail_view_v2.dart`, `ride_track_sketch_v2.dart` | Stats grid per §3.3, Etapy block (`ride_stages_v2.dart` new), pause dots in the sketch, trip link and menu items. |
| new `routes/v2/rides/trip_detail_view_v2.dart` | v2 trip detail (seam from `trip_detail_screen.dart` via `MgV2.on`). |

---

## 14. Velín (React, `velin/src`)

| File | Change |
|---|---|
| `pages/TrasyJizdy.jsx` | `RIDE_LIST_COLS` adds `proto, paused_at, pause_kind, paused_sec, last_seen_at, trip_id` (legacy fallback on 42703 stays). Status badges: `● Nahrává se` (not paused, contact < 15 min); `⏸ Pozastaveno od {čas}` (auto/manual; `· GPS uspáno` if `calc.deep`); `⏳ Čeká na rozjezd` (armed); `Bez spojení od {čas}` (not paused, contact 15 min–threshold); **`Záznam visí`** only when not paused and no contact > **3 h (proto 1) / 24 h (proto 2)**. New column "Cesta" (trip name, loaded by ids from `user_trips`). Filter "Nahrávané" includes paused; new sub-filter "Pozastavené". |
| `pages/TrasyJizdaModal.jsx` (+ new `TrasyJizdaEtapy.jsx` to keep the size) | Grid labels: Ujeto · Čas jízdy (v sedle) · **Na cestě bez pauz** (`duration_min`) · Zastávky (idle) · **Pauzy** (`paused_sec`, n×) · Bez signálu · Ø · Max · Nastoupáno · **Rozpětí** (start → end) · **Dny**. Etapy table. The stuck banner follows the same rule as the list; the paused box "Jízda je pozastavená od … (motorka stojí na {lat,lng}); appka naposledy ozvala {last_seen_at}." Button "Ukončit záznam" stays for both (ends at the pause). |
| `pages/TrasyJizdaMapa.jsx` + `lib/rideTrack.js` | `splitTrackOnGaps` also splits at `pauses[]` intervals: P markers with tooltip; connector dotted only if > 300 m. |
| `lib/rideDiag.js` | Labels for the new `ride` actions: `phase` (from → to, reason), `auto_pause`, `auto_resume` (pre-roll n, pause dur), `manual_pause`, `manual_resume`, `deep_pause`, `deep_wake`, `tail_restored`, `signal_lost`, `srv_caps` (v2 yes/no), `ride_reconciled`, `ride_end_booking`, `own_saved_for_rental`, `notif_failed`, `battery`. |
| `pages/booking/BookingLiveMap.jsx` | When `is_paused`: "⏸ Pozastaveno od {čas} — motorka stojí tady", plus "Appka naposledy v kontaktu {last_seen_at}"; not "živě". |

---

## 15. i18n

- Number ranges: Android uses 1–45 and 50–58; iOS 1–45; **46–49 are free in both**.
  - Shared ride keys → `translations_ext_46_rides_pause_a.dart` (cs, en, de, es) + `_b.dart` (fr, nl, pl, uk) in **both trees**.
  - v2-only keys → `translations_ext_47_v2_rides_pause.dart` (Android only).
- Each file is registered with **one minimal Edit line** in `translations.dart` (concurrent workflow).
- Re-check free numbers at implementation time.

Shared key families:
- `rideP` + phase chips: Armed, StandingSince, Paused, PausedDeep, SignalSearch
- buttons: Pause, Resume, End
- `ridePRentalEndsAtReturn`, explainer, snackbars (§13.1 G), sheets (§13.1 F)
- stat labels: `ridePStatOnRoad`, `ridePStatPauses`, `ridePStatDays`, `ridePStatSpan`, `ridePStages`, `ridePStageRow`
- `ridePDays`
- notification titles and texts (§9.3, §9.4)
- trip UX strings (§12), new `rideGapNotice2`

v2: dock and recorder labels, `v2RidePauseCta`, `v2RideResumeCta`, `v2RideStatusPaused`, …

Wording: natural, with *tykání* in Czech. Every error tells what happened, why, and what to do.

---

## 16. Files

**Shared (identical in both trees), new:**
- `ride_motion.dart` — detector + config
- `ride_session.dart` — phase, persisted session, event queue
- `ride_stats_local.dart` — moving/km rule for unsent delta + live formatting
- `ride_server_v2.dart` — RPC wrappers + caps
- `ride_flags.dart` — `ride_autopause` read + cache
- `ride_notification.dart` — notify bridge + texts; Android-only call
- `ride_recorder_pause.dart` — collaborator `RidePauseEngine` holding detector/session/queue; keeps `ride_recorder.dart` edits to hook points
- `ride_trip_model.dart`, `ride_trip_provider.dart`
- `trip_detail_screen.dart`, `ride_merge_sheet.dart`, `ride_recorder_controls.dart`, `ride_stage_list.dart`, `ride_session_sheets.dart`, `ride_nav_rec_chip.dart`
- tests

**Shared, changed (hook points only):**
- `ride_recorder.dart` (`_onPosition`, `_tick`, `_start`, `_flushOnce`, `stop`, `_restore`, `onAppResumed`)
- `ride_location.dart` (`ridePointFromFix` tweaks)
- `ride_recorder_watcher.dart`, `ride_model.dart` (new fields + `_splitOnGaps`), `ride_provider.dart` (re-export v2)
- old-UI parts of `my_experiences_screen.dart` (iOS: its own `_toggleManualRide`), `ride_card.dart`, `ride_detail_screen.dart`, `ride_map.dart`, `ride_share.dart`, `ride_booking_section.dart`, `community_submit.dart`, `ride_start_feedback.dart`
- `core/cache_cleanup_service.dart` (`_preserveKeys` — one-line, outside the owned file set; coordinate)

**Android only:**
- v2 files of §13.2
- `ride_actions.dart` (pause/resume helpers)
- `RideEngineKeeper.kt`/`MainActivity.kt` (`notify`, `battery`, deep notice)
- `translations_ext_47_*`

**iOS:** shared files only. No pubspec change. API is limited to geolocator 10 (`Position.has*`, no `verticalSpeed`; `getCurrentPosition` only via `GpsService`).

---

## 17. Compatibility matrix

| | **Current server** | **New SQL** |
|---|---|---|
| **4.1.3 (old recorder)** | Today's behaviour. | Same RPCs, keys and error codes. **Rental never splits while active** (resume by booking at any age; no 3 h/36 h). Own ride survives nights ≤ 20 h of silence. Inferred pauses (silence ≥ 5 min, stationary/drift runs ≥ 5 min) → nights and lunch are not stání. Walking and drift no longer add km or moving. Doppler max; smoothed climb. Car km after return dropped (append → `ride_finished`, which 4.1.3 treats as "forget"). Late Stop trimmed to the last fix + 2 min. `duration_min` = time without pauses. No pause buttons. |
| **4.2.0-dev (PR #2208, v1 RPCs)** | Today. | As 4.1.3. Its continuation on `ride_finished` now happens only at the real booking end (then it creates and discards an empty ride, as today; harmless). |
| **New app** | v2 RPCs missing → **fallback** (§11). Pause/auto-pause/deep work locally; nothing uploaded while paused. Server 3 h/36 h split still happens; own rides continue in a new ride instead of a silent stop. Live stats work. Trips hidden. Stats partly improved (no walking or drift uploaded). | **Full:** explicit pauses, never split, stages, trips, merge/undo, summary, booking-ended finish, reconcile. |
| **Mixed during deploy** | — | A ride started on the v1 path continues and is upgraded to proto 2 on the first v2 flush. A second device on old RPCs appending to a proto-2 ride → implicit resume. |

Velín before SQL: the legacy column fallback (42703) already exists; new badges render only when the columns exist.

---

## 18. Rollout and kill-switch

1. **Velín** changes, tolerant of missing columns. Can merge first.
2. **SQL drafts** in `scratchpad/rides/sql/`:
   - `01_rides_trips_schema.sql`
   - `02_rides_stats_core.sql` (`_ride_stats2` logic inside `_ride_ingest`, `_ride_track_thin`)
   - `03_rides_v1_compat.sql` (append/start/finish/finalize/json/admin_live/cron)
   - `04_rides_v2_rpc.sql`
   - `05_trips_rpc.sql` (+ summary)
   - `06_rides_flags_backfill.sql`, which:
     - inserts `feature_flags` `ride_autopause` `{enabled:true, conditions:{stop_min:5, walk_min:3, deep_h:20, resume_kmh:20}}` on conflict do nothing;
     - **optionally** backfills rental trips for past bookings with ≥ 2 rides via `_ride_autotrip`. This is the owner's choice and non-destructive (undo = ungroup).
   - Each draft is idempotent, one transaction, CREATE OR REPLACE / IF NOT EXISTS.
3. **Owner approves** → the drafts become migrations (`2026102x_user_rides_pause_*.sql`) + STATE_1/2/3/5/6 patch (`STATE_PATCH.md`).
4. **App:** Android 4.2.x first (contains the v2 client; detects the SQL). The iOS tree gets the same shared logic and old-UI changes in the same commit (rule 1); the iOS release date is the owner's choice.
5. **Kill-switch** `feature_flags.ride_autopause.enabled=false`:
   - The client stops auto-pause and auto-resume detection: it stays `riding` and uploads every point as today; armed → riding immediately.
   - Manual pause and never-split stay.
   - Thresholds come from `conditions` without a release.
6. **Monitoring:** Velín ride diagnostics (new actions), `battery` logs, Velín "Pozastavené" filter.

---

## 19. Test plan

### SQL — PG16 cluster `/var/tmp/pg-rides:5499` (`pg/setup.sh`)

Apply drafts twice. Extend `t_shim()` to `trip` names.

**Signatures and overloads.**
- `pg_get_function_identity_arguments` of every existing ride RPC is unchanged.
- `select proname from pg_proc join pg_namespace n on n.oid=pronamespace where nspname='public' and (proname like 'ride\_%' or proname like 'trip\_%' or proname like '%ride%') group by proname having count(*)>1` returns 0 rows.

**Replays** — extend `client.py` with a NewClientV2 that emits pause/resume/ping and runs the detector rules. Targets:

| Scenario | Target |
|---|---|
| S1 own day + stops | 1 ride; km ±1 % of truth; lunch/coffee ≥ 5 min in `paused_sec`; idle ≤ sum of < 5 min stops + 2 min; climb 85–100 % |
| S2 / S2d own, night (no fix / drift) | **1 ride**; km ±2 %; night in `paused_sec`; 2 stages; idle < 30 min; phantom km < 0.5 |
| S2r / S2rd / S3 / S9 rental multi-day | **1 ride per rental** (S3: night = inferred pause/gap, no new ride) |
| S4a / S4b / S4c 7-day own | 1 ride; km ±2 % of 2 537; 7 stages; days = 7; no 36 h close |
| S5 / S5b return + car | car km = 0; max ≤ bike max; no junk rides created |
| S6 walk 40 min | Ø ≈ 78 ±3 km/h; walk km 0 |
| S8 lake 3.5 h | 1 ride, 1 pause ≈ 3.5 h |
| S10 late Stop | `ended_at` ≤ arrival + 2 min; idle ≈ real stops |
| 4.1.3 (OldClient) S7a / S7b + new S11 (4.1.3 own, FGS alive overnight) + S12 (4.1.3 rental, killed, reopened) | Every response has the expected keys; append never returns a code other than `ride_finished`/`ride_not_found`; S7b and S12 one ride; S11 one ride |

**Elevation unit** (`elev_check.sql` → new function): the §3.6 targets.

**Idempotency:**
- Re-sending the same batch → stats unchanged.
- Duplicate pause/resume → ignored.
- Resume without pause → ignored.
- Armed → resume moves `started_at` and clears pre-ride points.

**Cron:**
- Proto 2 own paused 30 h → open.
- No contact for 8 days → closed at `paused_at`.
- Rental returned → closed at `returned_at`.
- Proto 1 own 21 h silent → closed; 19 h → open.
- Proto 1 rental 10 h silent while active → open.

**Trips:**
- merge / add / remove / ungroup / delete (with and without rides);
- the trigger deletes trips with < 2 members (also after `delete_user_ride` and < 1 km discard);
- RLS: user B cannot read or modify A's trips or merge A's rides;
- `_trip_json` sums equal the member sums;
- auto rental trip with `no_auto_trip` respected.

**Velín admin functions:** `admin_booking_live_ride` paused flags; `admin_finish_user_ride` on a paused ride ends at `paused_at`.

### App — `flutter test` both trees (iOS via the rsync copy, tests copied in)

- Detector scenarios §8.7 (15).
- Session JSON round-trip.
- Every new pref key is in `_preserveKeys` (test reads the set).
- Caps classifier: PGRST202 / 42883 → missing; SocketException → offline.
- Local stats parity: a JSON fixture exported from the SQL tests gives the same km and moving in Dart.
- Recorder integration with `FakeGeo` + an injectable server seam:
  - 7-day own → 1 ride id, 6 pause/resume pairs, no continuation;
  - rental `booking_ended` → finish, no new ride;
  - fallback: old server 3 h close → continuation for own.
- Widget tests: controls per phase (old + v2), 8 languages × 2 widths, no overflow, semantics labels present, reduced-motion (no ping).
- `flutter analyze`: Android ≤ 147 issues / 0 errors, iOS ≤ 143 / 0. `diff -rq lib` shows only the intended platform files + v2.

### Velín

`npm run build`; manual fixtures (paused/armed/deep/stuck proto 1 and 2/trip) render the correct badges, etapy and P markers.

### Device checklist for the owner

1. Ride → park for the night (no touch) → morning ride: one ride, 2 etapy, night in pauses.
2. Android notification text changes (armed → riding → paused).
3. Battery % per night (diagnostics).
4. Walk 10 min at a fuel stop → not in km.
5. Manual pause → notification gone → Pokračovat.
6. Merge 3 old rides → Zpět.
7. iOS blue pill disappears in manual pause.
8. Kill the app at night → reopen → same ride.

---

## 20. Risks and owner decisions

| # | Risk / decision | Default chosen |
|---|---|---|
| D1 | Battery: GPS stays on during auto-pause (5–15 %/night est.) | accepted; deep pause after **20 h**; tunable via flag; measured via `battery` log |
| D2 | Rest day > 20 h → next morning not recorded until the app is opened (iOS: no notice) | Android notice; iOS banner; consider a server push later |
| D3 | Taxi / bus / ferry / bicycle ≥ 20 km/h auto-resumes | known limitation (no activity recognition); later "odstranit úsek" |
| D4 | Jam crawl < 7 km/h not counted as km/moving (≤ a few hundred m) | accepted (walking exclusion is worth more) |
| D5 | Rental has no manual "Ukončit" (ends at return); the auto switch remains the off-switch | kept as today |
| D6 | Backfill rental trips for past rentals | proposed yes (undoable); owner confirms |
| D7 | Trip visibility cascades to member rides; the public feed stays per ride | yes |
| D8 | `duration_min` redefined as time without pauses (old apps show it as "celkový čas") | yes (only affects new appends) |
| D9 | Track payload: up to 12 000 points per multi-day ride in `get_my_rides` (≤ 100 rides) | acceptable now; later a list RPC with a thinned track |
| D10 | Already-uploaded points after a late `returned_at` (staff sets return hours later) stay in km | rare; documented |
| D11 | Manual start while a rental is picked up → labelled with the rental (client passes the booking) | yes; before pickup → own ride |
| D12 | Pickup while an own trip is paused → the own trip is saved automatically, then the rental recording starts | yes |
