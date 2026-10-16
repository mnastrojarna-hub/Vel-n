# Rank (věrnost) — end-to-end research + v2 rank-driven visual system

Research date 2026-10-15. Sources: live DB via anon REST (`loyalty_levels`, `feature_flags`, `loyalty_monthly_winners`, `accessory_types`), live schema dump `S/schema_public.sql` (snapshot 2026-10-11), migrations `supabase/functions/migrations/20260611_loyalty_ranks.sql` (the original file is in this odd folder, not `supabase/migrations/`), `supabase/migrations/20260917_loyalty_points_rank_floor_leaderboard.sql`, `20260916_gear_free_rank3_update_booking_gear.sql`, `20260806_loyalty_surcharge_and_branch_address.sql`, `20261011_profiles_customer_column_guard.sql`, STATE_1–5, and app code. Both app trees have identical `lib/features/loyalty/` (`diff -rq` clean), and both `main.dart` files wire the watcher the same way.
Token sketch and generator: `S/appdesign/research/rankTheme.js`, tables made by `S/appdesign/research/table.js` (S = scratchpad).

---

## 0. Key facts (TL;DR)

1. **Points:** every completed, non-test booking counts, from the app **and** from the web. 1–6 days = 1 point, 7+ days (inclusive) = 2 points.
2. **Level formula:** `level = min(20, ceil((points + 1) / 2))`, so level L starts at **2L − 2 points**. Startér is 0–1 points and Legenda is 38+. Each level = 1 % more discount.
3. **The discount is app-only.** It is applied only to app bookings (`booking_source='app'`) and enforced server-side by `trg_validate_app_loyalty`.
   - It also applies to the surcharge when an app booking is edited, and to a bike swap.
   - It stacks with promo codes and vouchers.
4. **Free gear from rank 3 (app only):** passenger gear 690 Kč, rider boots 290 Kč and passenger boots 290 Kč, each charged per booking. That's up to 1 270 Kč per booking. Basic rider gear is free for everyone at every rank.
5. **These are the only real benefits.** Anything "VIP" beyond discount + gear is presentation, never a promise.
6. **Rank never drops on its own.** `loyalty_points_floor` holds it ("rank navždy"). It only drops through a manual admin demotion (`loyalty_points_penalty`, 1 rank = 2 points).
7. **Hidden background level-ups.** The `loyalty_leaderboard` flag is **OFF**, so the leaderboard UI is hidden, but the monthly award cron still runs. On 1 Oct 2026 the first winner got **+4 bonus points = +2 ranks** silently in the background. This is exactly the owner's point-11 case.
8. **The level-up overlay already has a decent never-miss base:**
   - a global watcher in `MaterialApp.builder`
   - a server-side "celebrated" baseline
   - persisted only after the dialog
   - re-checked on tap (45 s throttle), resume, a 3-min poll and bookings realtime

   It still misses or misfires in 9 concrete cases (section 4.2).
9. **Display bugs today:**
   - The ladder shows the threshold off by one ("od 3 bodů" for Jezdec; the real threshold is 2 points).
   - A stale rule says "7+ days = 4 points → 2 ranks" in all 8 languages, both trees.
   - The app has no reduced-motion support at all.
10. **v2 proposal:** 5 material tiers drive the CTA fill, glow, ring, chip, header aura and level-up burst:
    - Silnice 1–5
    - Kovy 6–9
    - Drahokamy 10–16
    - VIP 17–19
    - Legenda 20

    Every token is solved for contrast: label ≥ 4.5:1 on every gradient stop, UI marks ≥ 3:1, white text on the header aura ≥ 4.6:1.

---

## 1. Mechanics (verified)

### 1.1 `loyalty_levels` (live, 2026-10-15)

- `level` = `discount_percent` (1–20).
- `min_booking_order` = 2L − 1, meaning "the n-th booking is the first at this level". It is **not** a points threshold.
- `translations` = `{}` for all rows. The app localises names through the `loyaltyRank1..20` keys (8 languages, `translations_ext_35_loyalty_ranks.dart`). If the owner renames a level in Velín, the Czech DB name shows in every language (`rank_names.dart`).

| L | Name | color_hex | Points from | | L | Name | color_hex | Points from |
|---|---|---|---|---|---|---|---|---|
| 1 | Startér | #9CA3AF | 0 | | 11 | Prémiový zákazník | #38BDF8 | 20 |
| 2 | Jezdec | #86EFAC | 2 | | 12 | Mistr silnic | #3B82F6 | 22 |
| 3 | Motorkář | #4ADE80 | 4 | | 13 | Šampion | #6366F1 | 24 |
| 4 | Stálý jezdec | #22C55E | 6 | | 14 | Veterán MotoGo | #8B5CF6 | 26 |
| 5 | Věrný zákazník | #14B8A6 | 8 | | 15 | Elitní jezdec | #A855F7 | 28 |
| 6 | Bronzový jezdec | #CD7F32 | 10 | | 16 | Ambasador | #D946EF | 30 |
| 7 | Stříbrný jezdec | #C0C0C0 | 12 | | 17 | VIP | #EF4444 (= SOS red!) | 32 |
| 8 | Zlatý jezdec | #FFD700 | 14 | | 18 | VIP Gold | #D4AF37 | 34 |
| 9 | Platinový jezdec | #E5E4E2 | 16 | | 19 | VIP Platinum | #F1F5F9 | 36 |
| 10 | Diamantový jezdec | #7DD3FC | 18 | | 20 | Legenda MotoGo | #FFD700 (= rank 8 hex) | 38 |

**Longest localised names** (chips and headers must wrap to 2 lines or scale down to 11 px, never clip):

- es "Maestro de la carretera" (23 chars)
- pl "Diamentowy jeździec"
- de/fr/nl "Meister der Straße" / "Maître de la route" / "Meester van de weg"
- uk "Діамантовий райдер"

### 1.2 Points, level and progress (live definitions)

**Raw points.** `_loyalty_raw_points(uid)` = `SUM(CASE WHEN end−start+1 >= 7 THEN 2 ELSE 1 END)`, counted over `status='completed' AND is_test=false`. App and web bookings both count.

**Qualifying points.** `_loyalty_qualifying_count(uid)` = `GREATEST(0, GREATEST(raw, profiles.loyalty_points_floor) − loyalty_points_penalty)`.

**Effective points.** `_loyalty_effective_count(uid)` = qualifying + `profiles.loyalty_bonus_points`.

The live `get_loyalty_status()` uses the **effective** count (the STATE_3 text still says qualifying; the dump shows effective). It returns:

- `{level, percent, rank_name, color_hex, qualifying_count (= effective points), max_level 20, next_rank_name, next_percent, next_color_hex}`
- `bookings_to_next = 2L − points`. This value is points, not bookings.
- `{leaderboard_opt_in, nickname, bonus_points}`

The server guard `validate_app_loyalty_discount` uses the same effective count.

**Rank never drops on its own.** `trg_loyalty_floor`, which fires when a booking becomes `completed`, raises the floor to the raw points.

**Admin demotion and restore.** `admin_loyalty_adjust_rank(uid, ±ranks, reason)` changes the penalty (2 points per rank) and logs to `loyalty_rank_adjustments` (admin-only RLS).

**One-off top-up.** When the points rule changed on 2026-09-17, a `grandfather-2026-09` adjustment topped up `loyalty_bonus_points` so nobody was demoted.

**Mockup customer.** Rank 3 Motorkář means 4–5 points. Use **5 points**, so "Ještě 1 bod → Stálý jezdec (4 %)". The real consequence: once the Husqvarna booking (16.–18. 10., 3 days = 1 point) is completed, he moves to **Stálý jezdec 4 %**.
- At self-service Velké Němčice that completion happens automatically. `kiosk_process_returns` (pg_cron, every minute) runs after he closes the bay door on the last day.
- It is therefore a textbook background level-up, and he may be standing at the lockers with the app open.

### 1.3 Leaderboard and monthly winner

**Leaderboard.** `get_loyalty_leaderboard(p_limit)` is month-scoped:

- Ranking order: rank gain this month, then km without damage (from handover protocols; `damage_flag` bookings excluded), then level, then days.
- Opt-out: `profiles.loyalty_leaderboard_opt_in` (default true).
- Display name: the nickname, or "Křestní #123" if none is set.
- Returns `{month, entries[{rank_pos,nickname,days,km,rank_gain,level,percent,rank_name,color_hex,is_me}], last_winner}`.

**Monthly winner.**

- The cron `loyalty-monthly-winner` (`10 0 1 * *`) runs `loyalty_award_monthly_winner()`, which adds **+4 bonus points (+2 ranks)** and writes a row to `loyalty_monthly_winners`.
- The first real award was **2026-10-01** for September: "FILIP #730", 6 days, 615 km, rank_gain 1, level before 2.

**Feature flag.** `feature_flags.loyalty_leaderboard = false` live. The app hides `LoyaltyLeaderboardSection` (`core/feature_flags.dart`), but **the award still runs**. The customer therefore gets a +2-rank level-up he cannot explain. The celebration must say why (section 5.8).

**Side finding (low).** `loyalty_monthly_winners` is `Public read` including `user_id` (anon can read the winner's UUID next to the first name).

### 1.4 RPCs and columns the app uses

| What | Where | Notes |
|---|---|---|
| `get_loyalty_status()` | `loyaltyStatusProvider` (`loyalty_provider.dart`) | Fail-safe: keeps the last good status per uid on network error; refresh frozen on `/payment` |
| `loyalty_levels` (public read) | `loyaltyLevelsProvider` | Static fallback copy of the seed in the app |
| `get_loyalty_celebration_motos()` | `fetchLoyaltyCelebrationMotos()` | Returns the last completed bike + `videos[]` for the celebration; `cutout_url` not returned yet |
| `loyalty_get_celebrated()` / `loyalty_advance_celebrated(p_level)` + `profiles.loyalty_celebrated_level` | `LoyaltyLevelUpWatcher` | **Live (in the dump) but missing from STATE_2/STATE_3.** Advance = `GREATEST(old, p_level)` for `auth.uid()`. Protected from direct client writes by `_guard_customer_profile_columns` (20261011) |
| `get_loyalty_leaderboard`, `set_loyalty_nickname`, `set_loyalty_leaderboard_optin` | Leaderboard section, nickname dialog | Leaderboard is behind the flag |
| `admin_loyalty_status`, `admin_loyalty_adjust_rank`, `admin_set_booking_damage`, `get_booking_loyalty_rate` | Velín | — |

### 1.5 What each rank really gives (complete list)

| Benefit | From rank | Where enforced | Notes |
|---|---|---|---|
| Discount L % on **app** bookings | 1 (every registered customer is at least Startér, so their 1st app booking already gets 1 %) | `trg_validate_app_loyalty` (cap = L % of total + discounts − delivery); app `PriceCalculator` (base = rental after late-pickup discount + extras; delivery excluded) | Also on the surcharge when editing an app booking (`_apply_booking_changes_core`, `update_booking_gear`, swap). Stacks with promo codes and vouchers. Web and admin bookings never get it |
| Passenger gear (690 Kč), rider boots (290 Kč), passenger boots (290 Kč) **free** | **3** (`loyaltyFreeGearLevel = 3`) | App `effectiveExtrasProvider` / `freeGearExtraIds {extra-spolujezdec, extra-boty-ridic, extra-boty-spolu}`; RPC `update_booking_gear` (parity since 2026-09-16) | App bookings only, `per_booking` prices. Base rider gear (helmet, jacket, trousers, gloves) is free for everyone, always |
| +2 ranks for the monthly leaderboard winner | any | Cron | Runs even with the flag off |
| Rank kept forever | any | Floor | Except an admin demotion |

There are no priority, SOS, delivery or bike-access perks. Do not draw any.

---

## 2. Where the app shows rank today (both trees identical)

| # | Place | File | What it shows |
|---|---|---|---|
| 1 | MG logo ring in the Home header and the Profil header (`LogoRow`) | `core/widgets/logo_header.dart` | Ring 4–5 px in `color_hex` (Legend uses the gradient `#FFD700→#FF6B00`); glow `color@.55 blur 18`; tap opens `/loyalty`. No ring when loyalty is null |
| 2 | Pilot badge (nickname pill) on Home | `features/home/widgets/home_header.dart` `_PilotBadge` | bg rank@.18, border @.55, glow @.4; tap opens the nickname dialog |
| 3 | Rank card on **Home** (under the header) and in **Profil** | `loyalty_rank_card.dart` | Dark pill with 🏅, rank name, `%`, `GlowPulse` + `ShimmerSweep` loops; progress bar 1–20; "Ještě {n} b. do: {next} ({pct} %)" or "Maximální rank"; "{n} b. · rezervace z appky i webu"; info sheet with rules (`loyaltyRulePoints/Long/Level/AppOnly/Combo`), app-only note |
| 4 | Profil nickname chip | `profile_screen.dart` `_NicknameChip` | Rank-tinted; pull-to-refresh invalidates the status |
| 5 | `/loyalty` ranks screen | `loyalty_ranks_screen.dart` | Ambient floating sparks bg; hero (ring, name, %, progress); leaderboard (flag); ladder 20 → 1 (locked/current/unlocked, "od {n} bodů", % pill, "Výbava spolujezdce i veškerá obuv zdarma" from 3); rules incl. `loyaltyRuleGear`; motivation line |
| 6 | Booking form | `core/booking_form_extras_section.dart`, `booking_form_price_section.dart`, `booking_size_dialogs.dart` | Gear priced "Zdarma" + gear benefit banner from rank 3; row "★ Věrnostní sleva — {rank} ({pct} %)" + "Platí jen pro rezervace vytvořené v aplikaci" |
| 7 | Price summary / payment | `features/booking/widgets/price_summary.dart`, `payment_screen.dart` | Discount row; sends `loyalty_level/percent/discount_amount`; rank frozen during payment |
| 8 | Reservation edit | `reservation_edit_screen.dart`, `reservation_edit_price_calc.dart`, `widgets/reservation_edit_extras_section.dart` | Gear free, discount on surcharge |
| 9 | Leaderboard section (flag OFF) | `loyalty_leaderboard_section.dart` | Month list, km, days, rank gain, last winner, show-me toggle, nickname |
| 10 | Level-up celebration (global) | `loyalty_levelup_overlay.dart` | Described in §4 |

**v2 preservation checklist** (owner point 9: nothing may be lost; collapsing is fine):

- rank name + %
- level L / 20
- points ("b.") and "app + web" note
- next rank + points missing
- max-rank state
- all rules: points, level, app-only, combo with codes, gear from 3 (replace the stale "Long" rule)
- full 20-level ladder with thresholds, % and the gear badge
- gear "Zdarma" in booking/edit
- discount row + app-only note
- leaderboard (behind flag) incl. nickname/opt-out
- celebration texts:
  - `NOVÝ RANK` / `MIMOŘÁDNÝ POSTUP`
  - "Tvoje sleva {pct} % platí napořád"
  - valued note
  - "Tvoje motorka · {bike}"
  - Pokračovat
- the logo ring as the entry to `/loyalty`

---

## 3. Defects found (fix in v2, in both trees)

| ID | Defect | Evidence | Fix |
|---|---|---|---|
| D1 | **Stale rule shown in all 8 languages:** "Rezervace delší než 7 dní = 4 body → postup o 2 ranky najednou". This contradicts `loyaltyRulePoints` (7+ days = 2 points) | `translations_ext_10_loyalty.dart:25` (+7 langs); used by `loyalty_rank_card.dart:209`, `loyalty_ranks_screen.dart:592` | Drop the line, or replace it with "7 a více dní = 2 body = celý rank najednou" (8 languages) |
| D2 | **Ladder threshold off by one:** "od {n} bodů" is fed `min_booking_order` (2L − 1). Jezdec shows "od 3 bodů" but is reached at 2; Startér shows "od 1" but is 0 | `loyalty_ranks_screen.dart:434`, `loyalty_levels_provider.dart` | Show `2L − 2` points (or keep `min_booking_order` with the label "od {n}. rezervace") |
| D3 | Doc comment says ">7 dní = 4 body" | `loyalty_provider.dart` header | Comment only |
| D4 | `profiles.loyalty_celebrated_level`, `loyalty_get_celebrated()`, `loyalty_advance_celebrated()` are undocumented | Live dump lines 12906/13008/22230; STATE_2/3 have no entry | Add to STATE_2/3 with the next SQL change |
| D5 | Monthly award gives +2 ranks while the leaderboard UI is off, so the celebration has no reason to show | Section 1.3 | Reason line in the celebration (§5.8) |
| D6 | No reduced-motion handling anywhere (`disableAnimations` unused). The celebration runs 67 s with infinite pulse, 46–90 particles, beam, video and music at volume 1.0. The app also forces `TextScaler.noScaling` (an a11y concern outside rank scope) | grep; overlay `_BgMusic` | §5.9 |
| D7 | Celebration `fromColor` comes from local prefs, so it is grey on a new device or after reinstall even when the old rank was gold | overlay `_maybeCelebrate` | Use `loyaltyLevelsProvider[baseline].colorHex` |
| D8 | `loyalty_monthly_winners` exposes `user_id` to anon | anon REST | Low; drop `user_id` from public read via a view or column grant (SQL to owner) |
| D9 | Ladder badge numbers and the "TY" chip fail WCAG for 14 of 20 levels (`_onColor` luminance > .5 rule, white text 2.10–4.47:1) | `loyalty_ranks_screen.dart:576` | Use the solved `rankTheme` label/chip tokens (§8) |

---

## 4. Level-up animation today: exact trigger chain

### 4.1 How it works (`loyalty_levelup_overlay.dart` + `loyalty_provider.dart` + `main.dart`)

**Mounting.** `LoyaltyLevelUpWatcher` is mounted once in `MaterialApp.builder`, in the `Stack` next to the navigator (main.dart ~l.398, iOS l.388). That makes it present on every route, including login, payment and success.

**Ways a re-check is triggered:**

- **(a) Any tap.** A global `Listener(onPointerDown)` calls `maybeRefreshLoyalty(ref)`, which runs `ref.invalidate(loyaltyStatusProvider)` with a **45 s throttle**. It skips while a celebration runs (`loyaltyPollPaused`), when logged out, and on `/payment`.
- **(b) App resume.** `didChangeAppLifecycleState(resumed)` does a forced refresh and resets the throttle.
- **(c) Periodic poll.** `Timer.periodic(3 min)` forces a refresh, but only while the app is `resumed`.
- **(d) Bookings realtime.** `ref.listen(reservationsProvider)` fires on any change of the user's bookings, which is a realtime stream on `bookings`, and forces a refresh. When staff (or kiosk auto-return) set `completed`, the check is immediate if the app is open.
- **(e) Profile change.** `profileProvider` changes (login/logout/refresh) cause `loyaltyStatusProvider` to recompute.

**What happens on each new status** (settled data only):

1. `ref.listen(loyaltyStatusProvider)` runs `_maybeCelebrate(status)` post-frame.
2. Latch `_showing`, pause polling.
3. Baseline = `loyalty_get_celebrated()` (server, 5 s timeout) **or**, if that RPC fails, the local `mg_loyalty_last_level_<uid>`.
4. If baseline is null, or the server returns 0, only seed it (no celebration).
5. If `level <= baseline`, store locally and stop.
6. Otherwise `gained = level − baseline`, fetch the celebration bikes (6 s timeout), and open `showGeneralDialog` on the root navigator.
7. **Only after the dialog closes:** persist local level + colour, then `loyalty_advance_celebrated(level)`.
8. Deferred while `onboardingOverlayActiveProvider` or `paymentScreenActiveProvider` is set.
9. If the navigator does not exist yet, retry once after 800 ms.

**The celebration (`LevelUpCelebration`):**

- 67 s master clock, auto-closes at the end.
- Music asset at volume 1.0 with `mixWithOthers`.
- Montage of the bike's videos, then a Ken Burns photo.
- Beam sweep; burst painter with 46 particles (90 + shockwave when "turbo", i.e. gained ≥ 2).
- Emblem: the MG logo ring cross-fades from the old to the new colour at 1.4 s, then "+N".
- Text, in order:
  - `NOVÝ RANK` / `MIMOŘÁDNÝ POSTUP`
  - rank name
  - "Tvoje sleva {pct} % platí napořád"
  - "Základní výhoda navždy — jen pro tebe v aplikaci…"
  - "Tvoje motorka · {bike}"
- The "Pokračovat" button appears at about 3 s.
- Legend (20) uses the gold→orange gradient; every other rank uses its `color_hex`.

### 4.2 When a background level-up is missed or misfires today

| # | Case | Why | Effect |
|---|---|---|---|
| M1 | User had an older app (local-only baseline). The server column is 0. A level-up happens while he is away, then he updates | Server baseline 0 **overrides** a valid local baseline, so the code seeds and returns | **Missed forever** |
| M2 | First app install by a customer who already ranked up on the web (e.g. 2 web rentals → Jezdec), or a reinstall/new device where the server is still 0 | "First observation = seed, never celebrate" | Missed (the owner wants every rank to be seen) |
| M3 | Level-up detected while on `/payment` or under onboarding overlays | `_blockedByOverlay` returns **without re-arming**. Leaving payment does not trigger a check, so it waits for a tap ≥ 45 s after the last poll, or the 3-min timer | Delayed up to 3 min (not lost) |
| M4 | Bonus / admin restore / monthly win while the app is open | `profiles` is **not** in the realtime publication; only `bookings` changes trigger immediately. Taps inside the 45 s throttle window don't check | Delayed up to 45 s–3 min; "tap → animation" is not guaranteed |
| M5 | Level-up detected during an SOS flow, route navigation while riding, the document scanner, handover-protocol signing, typing in the booking form, or **at the kiosk with door codes on screen** (self-service auto-complete fires within a minute of closing the bay door) | Only onboarding and payment block the dialog | A 67 s full-screen video with music covers critical screens. **Safety/UX bug** |
| M6 | Dialog dismissed in < 1 s by Android back | Persisted as celebrated after any pop | Seen for a split second, counted as seen |
| M7 | Two devices; server advance fails (timeout) | Local persisted, server not; no retry | Plays again on the 2nd device (duplicate, not a miss) |
| M8 | Reason never shown | No source info | Monthly win / admin restore feel random (D5) |
| M9 | Theme (ring/glow) changes on the next status fetch, before or without the celebration | The ring reads `status.level` directly | The new look appears silently and weakens the moment |

---

## 5. Never-miss level-up (owner point 11), proposal

### 5.1 Guarantee (acceptance criteria)

1. **Shown exactly once per account per new level.** The server-authoritative baseline uses `GREATEST`, which avoids duplicates across devices.
2. **Shown at the first safe moment after detection.** Detection is:
   - immediate on cold start and on resume
   - immediate on any navigation (route push/pop/tab switch)
   - within ≤ 20 s of any tap
   - immediate via realtime when it happens (with §5.10)
3. **Never shown over** payment, SOS, active route navigation/riding, camera/scanner, signature, door-code view, an open keyboard or system dialogs. It **waits** instead, and is shown on the next safe moment.
4. **Counted as seen only after the reveal.** That means rank name + new ring visible, t ≥ 2.6 s, **or** "Pokračovat" pressed. If the app is killed or backgrounded before that, it replays.
5. **Several level-ups are merged into ONE sequence** (from baseline to current), with every intermediate rank flashed and the reason(s) listed.
6. **The discount and free gear apply immediately.** Prices use `status.level`. Only the **look** waits for the reveal.

### 5.2 State and storage

| Key | Where | Content |
|---|---|---|
| `profiles.loyalty_celebrated_level` | Server (exists) | Highest level whose reveal was seen. Read with `loyalty_get_celebrated()`, write with `loyalty_advance_celebrated(p)` (`GREATEST`) |
| `mg_loyalty_last_level_<uid>` / `_color_<uid>` | SharedPreferences (exist) | Local mirror (offline / RPC failure) |
| `mg_loyalty_last_bonus_<uid>` | SharedPreferences (**new**) | Last seen `bonus_points` (from `get_loyalty_status`). A delta of ≥ 4 means the reason is "výhra měsíce" |
| `mg_loyalty_pending_<uid>` | SharedPreferences (**new**) | `{from, to, reasons[], detectedAt}`. Survives a kill between detection and the safe moment, and drives the theme hold (§5.7) |
| `mg_loyalty_welcomed_<uid>` | SharedPreferences (**new**) | The short "welcome to your rank" intro played once (fixes M2) |

**Baseline rule (fixes M1).** `baseline = max(server > 0 ? server : 0, local ?? 0)`.

- If baseline > server, call `loyalty_advance_celebrated(baseline)` again (self-healing for M7).
- If both are 0/null and `level ≥ 2` and the welcome flag is not set, play the **welcome variant**: Startér grey → current, 6 s, no music, "Vítej v klubu MotoGo24 — jsi {rank}". Then advance.
- If `level == 1`, just seed.

### 5.3 Detection triggers (all feed one `LevelUpGate.check(source)` that dedupes in-flight calls)

| # | Trigger | Today | v2 |
|---|---|---|---|
| T1 | Cold start (first authenticated frame) | Yes (provider listen) | Same |
| T2 | Resume from background | Yes, forced | Same, plus a re-check of the pending queue |
| T3 | **Every route change / tab switch** | No | **New:** GoRouter `routerDelegate.addListener` + `NavigatorObserver` on the shell navigator. Check (RPC if the last fetch is > 10 s old, else the cached status) |
| T4 | Any tap | Yes, 45 s throttle | Throttle **20 s** (`get_loyalty_status` is one STABLE call). Better still, fold `celebrated_level` into the same RPC so one round-trip answers "is there a pending level-up" |
| T5 | Bookings realtime change | Yes, forced | Same (catches staff completion and kiosk auto-return instantly) |
| T6 | Bonus / penalty / monthly win realtime | No | **New, optional backend:** `loyalty_events` realtime (§5.10) |
| T7 | Push "level_up" | No | **New, optional:** push from the same trigger. Tapping it opens the app, which fires T2 |
| T8 | Foreground poll | 3 min | Same |
| T9 | **Blocker cleared** (payment closed, onboarding finished, SOS/navigation/scanner/sign/door-code screen left, keyboard closed) | No | **New:** immediate presentation of the stored pending item (no RPC) |

### 5.4 Presentation gate ("safe moment")

**Allowed:**
- shell tabs (Domů, Motorky, Trasy list, Rezervace, Profil)
- reservation detail when no door code is enlarged
- `/success`
- `/loyalty`
- booking form with the keyboard closed and no sheet open (the celebration then explains the new lower price)

**Blocked (wait, keep pending):**
- `/payment` (existing; price is locked)
- `/sos/*` and any open SOS incident
- `RouteNavigationScreen` / active ride recording with navigation visible (riding safety)
- document scanner / camera
- handover-protocol signature
- full-screen door-code view, and the active-rental ticket while codes are shown in the **15 min after return** (kiosk codes stay valid 15 min after closing the bay or locker, CONTRACT §32)
- keyboard visible
- any modal sheet or dialog with input
- onboarding / language / permission overlays (existing)
- app not `resumed`

Blocked items are re-offered on T3, T4 and T9, so the worst case is "the next screen he opens".

### 5.5 Seen semantics (fixes M6)

- Advance the server + local mirror when `t ≥ 2.6 s` (the reveal finished) or when the user presses Pokračovat.
- Android back before 2.6 s closes the dialog **without** marking it seen. It replays at the next safe moment, but only once more. The second time, back counts as seen, so a user who deliberately dismisses it is not nagged.
- If the advance RPC fails, the local mirror holds and the server is retried on the next check.

### 5.6 Queue and sequence (multi-level)

- One dialog per pending block, `from → to`.
- With `gained ≥ 2`, the emblem ring **steps through every intermediate colour** at 220 ms per step (max 6 steps, then jump), then "+N" and `MIMOŘÁDNÝ POSTUP`.
- **Tier entry** (crossing 5→6, 9→10, 16→17, 19→20) gets a 1.2 s title card before the reveal (new i18n keys, 8 languages):
  - "Vstupuješ do kovové ligy"
  - "Vstupuješ do ligy drahokamů"
  - "Vítej ve VIP klubu"
  - "Jsi Legenda MotoGo"
- A level-up arriving **during** a running celebration is appended: when the dialog closes, the gate re-checks immediately (the latch is released → T9).

### 5.7 Theme hold and morph (fixes M9; makes the moment visible)

- `rankThemeLevel = pending != null ? pending.from : status.level`.
- Glow, CTA fill, ring and chips keep the **old** look until the reveal.
- At t = 1.4 s the `RankTheme` ThemeExtension lerps old → new over 600 ms behind the dialog (`ThemeExtension.lerp`). The user closes the dialog into a re-skinned app.
- Pricing never waits (it reads `status.level`).
- **Demotion** (admin penalty): no celebration, a quiet 300 ms morph down, and the local mirror is lowered. The server `GREATEST` keeps the high-water mark, so a later restore does not re-celebrate.

### 5.8 Reason line (fixes D5/M8, keeps the "for you" feeling)

Derived client-side today, without backend changes:

| Condition | Reason line |
|---|---|
| `bonus_points` grew by ≥ 4 vs `mg_loyalty_last_bonus` | "Vyhrál jsi měsíc {měsíc} — +2 ranky" (month from `loyalty_monthly_winners`, public read) |
| A reservation changed to `completed` since the last check | "Za jízdu na {bike} · {dates}" (from `reservationsProvider`; the bike is also `get_loyalty_celebration_motos().motos[0]`) |
| Otherwise | No reason line (admin restore / grandfather) |

### 5.9 Reduced motion, sound, a11y

`MgMotion.reduced(context)` = `MediaQuery.disableAnimationsOf(context)` OR the app setting "Omezit animace" (spec §2.8).

**Static celebration card when reduced:**
- 200 ms ring cross-fade
- no beam, particles, pulse or video montage (still photo)
- Pokračovat visible immediately
- the same texts

**Sound:**
- music only when not reduced **and** the setting "Zvuk oslav" is on (default on)
- volume .7, 600 ms fade-in
- stops instantly on Pokračovat
- speaker toggle in the corner

**Haptics and screen readers:**
- one `HapticFeedback.heavyImpact()` at the reveal
- `Semantics(liveRegion: true)` announces "Nový rank {name}, sleva {pct} %"

### 5.10 Optional backend for instant and explained level-ups (SQL as **text for the owner**; not applied, CLAUDE.md rule 3)

```sql
-- NÁVRH — loyalty_events: zdroj realtime + důvod povýšení + historie „Tvoje cesta"
CREATE TABLE IF NOT EXISTS loyalty_events (
  id bigserial PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('booking_completed','monthly_win','admin_adjust','other')),
  level_before int NOT NULL, level_after int NOT NULL,
  booking_id uuid, created_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE loyalty_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own read"  ON loyalty_events FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "admin all" ON loyalty_events FOR ALL    USING (is_admin());
ALTER PUBLICATION supabase_realtime ADD TABLE loyalty_events;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS loyalty_last_level int NOT NULL DEFAULT 0;
-- loyalty_sync_level(uid, kind, booking_id): lvl := LEAST(20, CEIL((_loyalty_effective_count(uid)+1)/2.0));
--   IF lvl <> loyalty_last_level THEN INSERT loyalty_events(...); UPDATE profiles SET loyalty_last_level = lvl;
--   IF lvl > old THEN PERFORM send_push_via_edge(uid, 'Nový rank', <rank name>, '{"type":"level_up"}'); END IF;
-- volat z: trg_loyalty_floor_on_complete (kind booking_completed), loyalty_award_monthly_winner (monthly_win),
--          admin_loyalty_adjust_rank (admin_adjust). Přidat 'loyalty_last_level' do _guard_customer_profile_columns.
```

Also fold `loyalty_celebrated_level` into `get_loyalty_status()` (one round-trip per check). If this ships, STATE_1/2/3/4/5/6 must be updated (CLAUDE.md rule 4), including the already-missing D4 entries.

### 5.11 Gate sketch (Dart-like, both trees, file < 5 000 tokens: `features/loyalty/levelup_gate.dart`)

```dart
Future<void> check(Source src) async {            // T1–T9 all land here
  if (_inFlight != null) return _inFlight;
  _inFlight = () async {
    final s = await _status(fresh: src.needsRpc);  // get_loyalty_status (+celebrated when folded in)
    final base = max(await _server() ?? 0, _local() ?? 0);
    if (base == 0) return s.level >= 2 && !_welcomed() ? _queue(1, s.level, [Reason.welcome]) : _seed(s);
    if (s.level > base) _queue(base, s.level, _reasons(s));   // persisted pending, theme hold
    else if (s.level < _local()!) _quietDemote(s);
    await _presentIfSafe();                         // returns if blocked; T3/T4/T9 retry
  }().whenComplete(() => _inFlight = null);
}
```

### 5.12 Test matrix (must pass on Android + iOS)

| # | Scenario |
|---|---|
| 1 | Staff completes a booking while Home is open: shown within 1 s (T5) |
| 2 | Kiosk auto-return while the door code is on screen: not shown; shown when he leaves the screen |
| 3 | Monthly award at 00:10, app closed: shown on next open, with the "Vyhrál jsi měsíc září" line |
| 4 | Admin +1 restore after a demotion to an already celebrated level: no celebration |
| 5 | Two levels at once: one sequence with "+2", tier card if crossing |
| 6 | Kill the app at t = 1 s: replays. At t = 3 s: does not |
| 7 | New device after reinstall: no duplicate if the server says celebrated; welcome variant if the server is 0 |
| 8 | Old app with local baseline, server 0: celebrates (M1 fixed) |
| 9 | Reduced motion: static card, no music |
| 10 | Payment open during a level-up: not shown, price unchanged; shown right after leaving payment (T9) |
| 11 | Riding navigation: never shown |
| 12 | Offline: nothing shown, nothing persisted; shown after reconnect + tap |

---

## 6. Rank-driven visual system (v2)

### 6.1 Principles

1. **Rank is an accent layered on the brand.** It drives exactly these surfaces:
   - the screen's one primary CTA: fill, label, edge, glow and its loop effect
   - the MG logo/avatar ring + progress arc
   - the rank chip
   - the header aura (gDark first stop)
   - the nav active bar
   - progress bars
   - the level-up celebration
   - the static header texture
2. **Rank never touches meaning:**
   - prices (`#0D6E0D` on light / neon on dark)
   - success/checked (neon)
   - warnings (amber)
   - errors
   - **SOS (`#EF4444`)**
   - focus rings (neon)
   - links
   - platform pay buttons (Apple Pay / Google Pay must stay official black/white per HIG/brand rules; only our own "ZAPLATIT" CTA is rank-styled)
3. **Tier comes from the level number; colours come from `color_hex`.** The owner can recolour a level in Velín and every contrast-sensitive token is **solved at runtime**, so it stays WCAG-safe.
4. **Same structure for every rank, different material.** Layout, sizes and copy never change with rank. Only material, light and motion change, so simplicity is preserved.
5. **Motion budget unchanged (spec §0.6):**
   - at most 2 infinite loops per screen
   - the tier effect **replaces** the CTA "shine" in the same loop slot
   - every other rank motion is one-shot
   - `MgMotion.reduced` turns all of it static

### 6.2 Tiers

| Tier | Levels | Material / mood | CTA fill | Label | Ring | Loop fx (CTA slot) | Home ambient (once per session) | Level-up burst |
|---|---|---|---|---|---|---|---|---|
| **Silnice** (road) | 1–5 Startér · Jezdec · Motorkář · Stálý jezdec · Věrný zákazník | Pure brand: neon on dark green; the rank green tints the gradient's low stop | Neon `#8DFF86` → mix(`#37CF63`, rank, .5) | `#08230F` | Solid rank colour, 3 px | `shine` (existing token: 3.2 s, band sweeps in the last 40 %) | none (calm) | Neon + rank-green confetti |
| **Kovy** (metal) | 6–9 Bronz · Stříbro · Zlato · Platina | Brushed metal: 4-stop gradient (highlight, light, base, shade) at 115°, 1 px top highlight edge | Metal stops | Warm ink `#1A1405` (bronze, gold) / cool ink `#0B1512` (silver, platinum) | Conic metallic, 3 px | `sheen`: wide soft specular band (40 % width) glides across in the last 35 % of a 4.8 s cycle | `sheenOnce`: specular sweep across the dark header, 900 ms | Metal sparks + sheen across the emblem |
| **Drahokamy** (jewel) | 10–16 Diamant · Prémiový · Mistr silnic · Šampion · Veterán · Elitní · Ambasador | Cut gem: 2-stop prismatic gradient (base → hue + 24°), 1.5 px bright facet edge | Gem stops (deep gems darkened until white label ≥ 4.5) | Ice gems 10–11: navy `#0A1F33`; deep gems 12–16: white | Faceted conic (12 facets), 3.5 px | `glint`: 3 four-point star sparkles (6–9 px) pop at facet points (scale 0→1→0, 420 ms, stagger 300 ms) in the last 40 % of a 3.6 s cycle | `prismOnce`: prism band with a faint rainbow edge across the header, 1.1 s + 3 glints on the ring | Faceted shards + glints |
| **VIP** | 17 VIP · 18 VIP Gold · 19 VIP Platinum | "Foil card": bright pearl/foil fill, framed 1.5 px foil edge, **crown glyph** before the label. VIP red is used only as glow/edge/ring, **never as a fill** (it is the SOS red) | 17 pearl-rosé `#FFF5F6→#FECDD6`; 18 antique gold foil; 19 pearl-platinum | 17 ruby `#881337`; 18/19 onyx `#14100A` | Double ring (rank + gold) with crown notch, 3.5 px | `edge`: a 24 %-long highlight runs once around the foil border per 4 s; crown glints at the end | `auroraOnce`: slow aurora wash in tier colours over the header aura (2.4 s, alpha ≤ .22); crown pops onto the ring (350 ms) | Crown drops onto the ring + aurora |
| **Legenda** | 20 Legenda MotoGo | Molten gold → orange (extends the app's `legendGradientColors`), laurel glyph | `#FFE27A → #FFD700 → #FF9A1F → #FF6B00` | `#241A06` | Conic gold-orange + laurel wreath, 4 px | `ember`: molten sweep + max 4 warm embers rising 10–16 px and fading, 4.4 s | `auroraEmbersOnce`: aurora + 6 embers from the ring, 2.8 s | Laurel draws around the ring + embers |

**Static header texture by tier** (opacity 4–6 %, zero motion, reduced-motion safe; this gives "uniqueness" for free):

| Tier | Texture |
|---|---|
| Silnice | Topographic contour lines (route feel) |
| Kovy | Brushed hairlines |
| Drahokamy | Low-poly facets |
| VIP | Fine guilloché (banknote/card) |
| Legenda | Guilloché + laurel watermark |

**Glow** (`shGlow`, generalised):
- Colour = rank colour, with these exceptions: Startér uses the brand neon; grey metals (7, 9, 19) are tinted cool `mix(hex,#BFD9FF,.35)` so they never read as a dirty haze; VIP 17 uses rose `#F43F5E` (not SOS red); Legend uses `#FF8C00`.
- Alpha .50 / .55 / .58 / .62 / .66 by tier.
- Blur 22 / 26 / 28 / 30 / 34.
- From metal up, a second soft halo (alpha .12–.24, blur 40–56).
- Pulse ring 0 → 7–10 px over 2.2 s (existing `glow` loop).
- **Deep gems 12–16** have fills that sit 2.2–3.5:1 against the night sticky bar (unavoidable with a white label ≥ 4.5). Their boundary is carried by the 1.5 px facet edge (≥ 3.8:1) + glow, so the button stays the most prominent element (owner point 8).

### 6.3 Where rank shows in v2 (per screen)

| Screen / element | Rank expression | Notes |
|---|---|---|
| **Header (Home, Profil)** | Aura stop + tier texture; MG logo ring + **progress arc** to the next level (track white@.18, arc `ring.progressArc.color`); rank chip "MOTORKÁŘ · −3 %" (solid chip bg so the aura can't break contrast) | Tap ring/chip → `/loyalty` (keep) |
| **Home "Tvůj klub" strip** (replaces the white rank card; same data) | Tier emblem + rank name (accentDark) + "Level 3 z 20 · sleva 3 % na každou jízdu v appce". Segmented progress (2 segments per level = points): "Ještě 1 bod → Stálý jezdec (4 %)". Benefit chips: "Výbava spolujezdce + boty zdarma" (≥ 3) or teaser "Od Motorkáře: výbava spolujezdce + boty zdarma" (1–2). Savings line "Díky ranku jsi zatím ušetřil {sum} Kč", where `sum` = Σ `loyalty_discount_amount` of own bookings (`Reservation.loyaltyDiscountAmount` exists; hide if 0). Rules sit behind ⓘ | Optional "Tvoje cesta" mini-timeline (completed bookings → points → level) once `loyalty_events` exists |
| **Bottom nav (5 tabs incl. PROFIL)** | PROFIL icon = avatar/MG mini with a 2 px rank ring; active tab = 3 px top bar in `uiLight` (≥ 3:1 on white) + pill tint mix(white, rank, .14); labels stay inkDark (never rank-coloured) | Tab switch: `tab` token 210 ms fade-through; the indicator slides 240 ms `Cubic(.2,0,0,1)`; press scale .97 + selectionClick. Reduced → instant |
| **Moto Detail sticky bar** | **REZERVOVAT · 10 189 Kč** = rank CTA (56 px tall, full width minus price block, fill + edge + glow + tier loop); VIP/Legend glyph before the label; secondary links stay text-only; the AI FAB sits above the bar and has **no** glow loop | One primary per screen (spec §0.1) |
| **Katalog card action** | Same rank CTA at 48 px; the loop runs only on the card centred in view (`TickerMode`) | Photos stay full-screen |
| **Booking pay button** | "ZAPLATIT 12 027 Kč" rank CTA; Apple/Google Pay buttons stay official | Theme frozen on `/payment` (as rank refresh is today) |
| **Reservation** | Rank chip in the ticket; the discount row "★ Věrnostní sleva — Motorkář (3 %)" keeps its text, the star takes `accentLight` on light | No CTA re-skin of destructive actions (storno stays neutral) |
| **AI FAB** | Dark glass circle, 1.5 px rank ring, no loop | Must never out-shine the CTA |
| **`/loyalty` ranks screen** | Ladder grouped under **5 tier headers** (Legenda / VIP klub / Drahokamy / Kovy / Silnice), each level tile shows its own material swatch (mini CTA chip) so the customer *sees* what his app will look like next; current tile = live ring + glow; locked = 50 % + lock; thresholds **2L − 2 b.** (D2 fixed); gear badge from 3; rules ⓘ; leaderboard (flag) | All 20 levels and all rules stay visible (no info lost) |
| **Level-up celebration** | Burst per tier; tier-entry title card; ring steps through levels; theme morph behind it (§5.7) | Static card when reduced |

### 6.4 Look at a glance (for the RankStyly board)

| Rank | CTA | Glow | Ring | Feel |
|---|---|---|---|---|
| 1 Startér | Brand neon | Neon, soft | Grey solid (+ progress arc invites) | Clean brand |
| 3 Motorkář (mockup) | Neon → `#41D772` | `#4ADE80` .50 | Green solid | Brand, slightly richer |
| 6 Bronzový | Brushed bronze `#E9C5A3→#B9722D`, warm ink | Bronze .55 + halo | Conic bronze | First "material" step |
| 8 Zlatý | Brushed gold `#FFED8C→#E6C200` | Gold | Conic gold | — |
| 10 Diamantový | Ice prism `#7DD3FC→#7DA0FC`, navy label, facet edge | Ice blue .58 | 12-facet ice | Sparkle |
| 13 Šampion | Indigo→violet `#575AD5→#8757D5`, white label, bright edge | Indigo | Faceted indigo | — |
| 17 VIP | Pearl-rosé foil, ruby label, crown, ruby-gold edge | Rose `#F43F5E` .62 + halo | Red + gold double, crown notch | "Black-tie", but not SOS |
| 18 VIP Gold | Antique gold foil, onyx label, crown | Gold | Gold + champagne double | — |
| 19 VIP Platinum | Pearl-platinum, iridescent edge, crown | Cool white | Platinum + gold double | — |
| 20 Legenda | Molten gold→orange, laurel | `#FF8C00` .66 + halo | Gold-orange conic + laurel | Crown jewel |

### 6.5 Copy (cs, tykání; new strings need all 8 languages)

**Existing keys, keep:**
- `loyaltyLevelUpKicker` NOVÝ RANK
- `loyaltyMegaLevelUpTitle` MIMOŘÁDNÝ POSTUP
- `loyaltyDiscountForever`
- `loyaltyValuedNote`
- `loyaltyYourBike`
- `loyaltyContinue`
- `loyaltyNextRank` "Ještě {n} b. do: {next} ({pct} %)"
- `loyaltyGearBenefit`
- `loyaltyAppOnly`
- `loyaltyRule*` (fix D1)

**New:**
- Tier names: Silnice / Kovová liga / Liga drahokamů / VIP klub / Legenda
- Tier entry lines (§5.6)
- "Vítej v klubu MotoGo24 — jsi {rank}"
- "Vyhrál jsi měsíc {month} — +2 ranky"
- "Za jízdu na {bike}"
- "Díky ranku jsi zatím ušetřil {sum} Kč"
- "Od Motorkáře: výbava spolujezdce + boty zdarma"
- Settings: "Omezit animace", "Zvuk oslav"

**Do not use vocative rank greetings** ("Vítej, Bronzový jezdče"). They are error-prone across 8 languages. Greet by nickname and show the chip.

**Earn promise.** Spec v1 dropped the "+1 bod" earn promise. If the owner wants the "after this ride you'll be Stálý jezdec" nudge back, word it conditionally: "Po dokončení této jízdy: Stálý jezdec (4 %)".

---

## 7. `rankTheme(level, colorHex?)`: JS sketch (runnable; full file `S/appdesign/research/rankTheme.js`)

**Usage in boards:** `const T = rankTheme(P.rank)`, then bind:
- `T.btn.stops` / `T.btn.label` / `T.btn.edge` / `T.glow` / `T.ring` / `T.chip` / `T.aura`
- `T.btn.fx` + `T.ambient` as class names
- with reduced motion, use `T.reduced`

Level 0 = guest or loyalty RPC failure, which gives pure brand (the app today shows no ring then).

```js
// rankTheme(level, colorHex?) -> design tokens for MotoGo24 app v2 (boards + Flutter port).
// Tier is decided by LEVEL (stable); colours come from loyalty_levels.color_hex (live, editable in Velín).
// All contrast-sensitive values are SOLVED (not hand-picked), so a recoloured level stays WCAG-safe.
const B = { neon:'#74FB71', neonHi:'#8DFF86', neonLo:'#37CF63', onNeon:'#08230F', night:'#0A1F14',
  panel:'#0E2A1C', glowStop:'#24563B', inkDark:'#1A2E22', page:'#DFF0EC', card:'#FFFFFF' };
const SEED = ['#9CA3AF','#86EFAC','#4ADE80','#22C55E','#14B8A6','#CD7F32','#C0C0C0','#FFD700','#E5E4E2',
  '#7DD3FC','#38BDF8','#3B82F6','#6366F1','#8B5CF6','#A855F7','#D946EF','#EF4444','#D4AF37','#F1F5F9','#FFD700'];
const TIERS = [ // fx = replaces the CTA "shine" loop (same loop slot; never an extra loop)
  { id:'road',   cs:'Silnice',   from:1,  to:5,  icon:'shield', fx:'shine', ambient:'none',        burst:'confetti' },
  { id:'metal',  cs:'Kovy',      from:6,  to:9,  icon:'medal',  fx:'sheen', ambient:'sheenOnce',   burst:'sparks'   },
  { id:'jewel',  cs:'Drahokamy', from:10, to:16, icon:'gem',    fx:'glint', ambient:'prismOnce',   burst:'prism'    },
  { id:'vip',    cs:'VIP',       from:17, to:19, icon:'crown',  fx:'edge',  ambient:'auroraOnce',  burst:'crown'    },
  { id:'legend', cs:'Legenda',   from:20, to:20, icon:'laurel', fx:'ember', ambient:'auroraEmbersOnce', burst:'laurel' },
];
const LEGEND = ['#FFE27A','#FFD700','#FF9A1F','#FF6B00'];         // extends app legendGradientColors
const INK = { warm:'#1A1405', cool:'#0B1512', legend:'#241A06', navy:'#0A1F33', onyx:'#14100A' };

// ---- colour math (sRGB, WCAG 2.x) ----
const rgb = h => [1,3,5].map(i => parseInt(h.slice(i, i + 2), 16));
const hex = c => '#' + c.map(v => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2,'0')).join('').toUpperCase();
const lin = v => (v /= 255) <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
const lum = h => { const [r,g,b] = rgb(h).map(lin); return 0.2126*r + 0.7152*g + 0.0722*b; };
const cr  = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x,y) + 0.05) / (Math.min(x,y) + 0.05); };
const mix = (a, b, t) => { const A = rgb(a), B2 = rgb(b); return hex(A.map((v,i) => v + (B2[i]-v)*t)); };
const hsl = h => { const [r,g,b] = rgb(h).map(v => v/255), mx = Math.max(r,g,b), mn = Math.min(r,g,b), l = (mx+mn)/2, d = mx-mn;
  if (!d) return [0,0,l]; const s = d / (1 - Math.abs(2*l - 1));
  const H = mx === r ? ((g-b)/d) % 6 : mx === g ? (b-r)/d + 2 : (r-g)/d + 4; return [(H*60 + 360) % 360, s, l]; };
const fromHsl = (H, s, l) => { const c = (1 - Math.abs(2*l - 1)) * s, x = c * (1 - Math.abs((H/60) % 2 - 1)), m = l - c/2;
  const [r,g,b] = H < 60 ? [c,x,0] : H < 120 ? [x,c,0] : H < 180 ? [0,c,x] : H < 240 ? [0,x,c] : H < 300 ? [x,0,c] : [c,0,x];
  return hex([r,g,b].map(v => (v + m) * 255)); };
const spin = (h, deg) => { const [H,s,l] = hsl(h); return fromHsl((H + deg + 360) % 360, s, l); };
// move h toward `to` in 2 % steps until contrast vs every bg >= target
const fit = (h, bgs, target, to) => { bgs = [].concat(bgs);
  for (let t = 0; t <= 1.0001; t += 0.02) { const c = mix(h, to, t); if (bgs.every(bg => cr(c, bg) >= target)) return c; } return to; };
const minCr = (stops, text) => Math.min(...stops.map(s => cr(s, text)));
const solve = (stops, label, to) => { let n = 0; while (minCr(stops, label) < 4.5 && n++ < 50) stops = stops.map(s => mix(s, to, 0.04)); return stops; };

function rankTheme(level, colorHex) {
  const L = Math.max(0, Math.min(20, level | 0));            // 0 = guest / loyalty RPC failed -> pure brand
  const c = (colorHex && /^#[0-9a-f]{6}$/i.test(colorHex)) ? colorHex.toUpperCase() : (SEED[L - 1] || B.neon);
  const ti = L ? TIERS.findIndex(t => L >= t.from && L <= t.to) : 0, tier = TIERS[ti];
  const step = L ? (L - tier.from) / Math.max(1, tier.to - tier.from) : 0;  // 0..1 inside the tier
  const chroma = (Math.max(...rgb(c)) - Math.min(...rgb(c))) / 255, grey = chroma < 0.12;

  // text/icons in the rank colour: on dark (header, hero, sticky, chips) and on light (page #DFF0EC, white cards)
  const accentDark  = fit(c, [B.panel, B.inkDark], 4.5, '#FFFFFF');
  const accentLight = fit(c, [B.page, B.card], 4.55, '#000000');
  const uiLight     = fit(c, [B.card], 3.0, '#000000');      // non-text marks on white (nav indicator, progress)
  const uiDark      = fit(c, [B.panel], 3.0, '#FFFFFF');     // non-text marks on dark (ring, arcs)

  // glow: never a dirty grey haze. Startér keeps the brand neon; grey metals get a cool tint; Legend = molten orange.
  const glowHex = (!L || L === 1) ? B.neon : L === 20 ? '#FF8C00' : grey ? mix(c, '#BFD9FF', 0.35) : (L === 17 ? '#F43F5E' : c);
  const glow = { color: glowHex, alpha: [0.50, 0.55, 0.58, 0.62, 0.66][ti], blur: [22, 26, 28, 30, 34][ti], spread: -8, dy: 8,
    halo: ti ? { alpha: [0, 0.12, 0.16, 0.20, 0.24][ti], blur: [0, 40, 44, 48, 56][ti] } : null,
    pulsePx: [7, 8, 9, 9, 10][ti] };                         // loop `glow`: ring 0 -> pulsePx, alpha .45 -> 0, 2.2 s

  // primary CTA (always on a dark surface: hero card or sticky bar) — label proven >= 4.5:1 on every stop
  let stops, label, edge = null, angle = 135, glyph = null;
  if (!L || tier.id === 'road') {
    label = B.onNeon; stops = solve([B.neonHi, L > 1 ? mix(B.neonLo, c, 0.5) : B.neonLo], label, '#FFFFFF');
  } else if (tier.id === 'metal') {                          // brushed metal: highlight, light, base, shade
    label = grey ? INK.cool : INK.warm; angle = 115;
    stops = solve([mix(c,'#FFFFFF',0.55), mix(c,'#FFFFFF',0.18), c, mix(c,'#000000',0.10)], label, '#FFFFFF');
    edge = { width: 1, stops: [mix(c,'#FFFFFF',0.75), mix(c,'#000000',0.20)] };
  } else if (tier.id === 'jewel') {                          // prismatic: base -> neighbouring hue
    const ice = lum(c) > 0.30; label = ice ? INK.navy : '#FFFFFF';
    stops = solve([c, spin(c, 24)], label, ice ? '#FFFFFF' : '#000000');
    edge = { width: 1.5, stops: [fit(mix(stops[0],'#FFFFFF',0.45), B.night, 3, '#FFFFFF'), fit(mix(stops[1],'#FFFFFF',0.25), B.night, 3, '#FFFFFF')] };
  } else if (tier.id === 'vip') {                            // foil card: bright fill, framed foil edge, crown glyph
    glyph = 'crown';
    if (L === 17)      { label = '#881337'; stops = solve(['#FFF5F6', '#FFE4E8', '#FECDD6'], label, '#FFFFFF');
                         edge = { width: 1.5, stops: ['#FB7185', '#FDE68A', '#E11D48'] }; }
    else if (L === 18) { label = INK.onyx; stops = solve(['#F7E9B8', '#E6C869', c, '#B8932A'], label, '#FFFFFF');
                         edge = { width: 1.5, stops: ['#FFF6D6', '#8C6A12'] }; }
    else               { label = INK.onyx; stops = solve(['#FFFFFF', '#F1F5F9', '#DCE3EC'], label, '#FFFFFF');
                         edge = { width: 1.5, stops: ['#FBCFE8', '#BAE6FD', '#BBF7D0', '#FDE68A'] }; } // iridescent
  } else { label = INK.legend; stops = solve(LEGEND, label, '#FFFFFF'); edge = { width: 1, stops: ['#FFF4D6', '#FFB000'] }; glyph = 'laurel'; }

  // ring around MG logo / avatar / PROFIL tab (drawn on dark; on white add 1 px night keyline)
  const ring = { width: [3, 3, 3.5, 3.5, 4][ti],
    paint: (!L || tier.id === 'road') ? { solid: c }
         : tier.id === 'metal' ? { conic: [mix(c,'#FFFFFF',0.6), c, mix(c,'#000000',0.25), mix(c,'#FFFFFF',0.6)] }
         : tier.id === 'jewel' ? { conic: [c, spin(c, 24), c, spin(c, -18), c], facets: 12 }
         : tier.id === 'vip'   ? { double: [c, L === 18 ? '#FFF1C2' : '#D4AF37'], crownNotch: true }
         : { conic: [...LEGEND, LEGEND[0]], laurel: true },
    progressArc: L && L < 20 ? { color: mix(uiDark, '#FFFFFF', 0.2), track: 'rgba(255,255,255,.18)' } : null };

  const chipBg = mix(B.panel, c, 0.16);                      // solid composite of accent@16 % on panel
  const chipText = fit(c, [chipBg, B.inkDark], 4.5, '#FFFFFF');
  return {
    level: L, tier: tier.id, tierCs: tier.cs, tierIndex: ti, step: +step.toFixed(2), icon: tier.icon, hex: c, grey,
    accentDark, accentLight, uiDark, uiLight,
    chip: { bg: chipBg, border: c, borderAlpha: 0.55, text: chipText, contrast: +cr(chipText, chipBg).toFixed(2) },
    aura: fit(mix(B.glowStop, glowHex, [0.25, 0.32, 0.38, 0.42, 0.50][ti]), '#FFFFFF', 4.6, B.night), // gDark first stop; white text stays >= 4.5 (+margin)
    glow,
    btn: { angle, stops, label, edge, glyph, minContrast: +minCr(stops, label).toFixed(2),
           vsNight: +Math.min(...stops.map(s => cr(s, B.night))).toFixed(2),
           edgeVsNight: edge ? +Math.min(...edge.stops.map(s => cr(s, B.night))).toFixed(2) : null, fx: tier.fx },
    ring, ambient: tier.ambient, burst: tier.burst,
    reduced: { loops: false, fx: 'static', ambient: 'none', ring: 'static', glowAlpha: glow.alpha, celebration: 'staticCard' },
  };
}
if (typeof module !== 'undefined') module.exports = { rankTheme, cr, mix, SEED, B, TIERS };
```

Sample output, rank 3:
- `btn.stops ['#8DFF86','#41D772']`, label `#08230F` (8.9:1)
- `glow #4ADE80 .50/22`
- `ring solid #4ADE80`
- `chip #4ADE80 on #18472C` (6.1:1)
- `aura #2E784C`

Sample output, rank 17:
- pearl-rosé stops, label `#881337` (6.8:1)
- edge `#FB7185→#FDE68A→#E11D48`
- glow `#F43F5E .62/30` + halo
- double ring `#EF4444 + #D4AF37`

---

## 8. Contrast and token tables (computed by `table.js`, WCAG 2.x relative luminance)

**Surfaces:**
- panel `#0E2A1C`
- inkDark `#1A2E22`
- night `#0A1F14` (sticky bar)
- page `#DFF0EC`
- card `#FFFFFF`

**Thresholds:**
- text ≥ 4.5:1 (CTA label 14.5/800 is not "large", so 4.5 applies)
- UI marks (ring, arc, nav bar, edges) ≥ 3:1

### 8.1 Accent text, UI marks and chips

| L | Rank | Tier | color_hex | ring (hex) vs panel | accentDark → vs panel / inkDark | accentLight → vs page / white | uiLight → vs white | chip text → vs chip bg |
|---|---|---|---|---|---|---|---|---|
| 1 | Startér | road | `#9CA3AF` | 6.05 | `#9CA3AF` 6.05 / 5.67 | `#646870` 4.74 / 5.59 | `#8C939E` 3.10 | `#9CA3AF` on `#253D34` 4.61 |
| 2 | Jezdec | road | `#86EFAC` | 10.94 | `#86EFAC` 10.94 / 10.26 | `#407353` 4.69 / 5.53 | `#5BA375` 3.03 | `#86EFAC` on `#214A33` 7.15 |
| 3 | Motorkář | road | `#4ADE80` | 8.82 | `#4ADE80` 8.82 / 8.27 | `#287845` 4.61 / 5.44 | `#37A45F` 3.16 | `#4ADE80` on `#18472C` 6.1 |
| 4 | Stálý jezdec | road | `#22C55E` | 6.74 | `#22C55E` 6.74 / 6.32 | `#157A3A` 4.59 / 5.42 | `#1DA951` 3.07 | `#22C55E` on `#114327` 4.97 |
| 5 | Věrný zákazník | road | `#14B8A6` | 6.17 | `#14B8A6` 6.17 / 5.79 | `#0D766A` 4.67 / 5.50 | `#12A695` 3.04 | `#14B8A6` on `#0F4132` 4.63 |
| 6 | Bronzový jezdec | metal | `#CD7F32` | 4.89 | `#CD7F32` 4.89 / 4.58 | `#945B24` 4.71 / 5.55 | `#CD7F32` 3.14 | `#D38E4B` on `#2D3820` 4.56 |
| 7 | Stříbrný jezdec | metal | `#C0C0C0` | 8.45 | `#C0C0C0` 8.45 / 7.92 | `#686868` 4.73 / 5.57 | `#929292` 3.11 | `#C0C0C0` on `#2A4236` 5.98 |
| 8 | Zlatý jezdec | metal | `#FFD700` | 10.96 | `#FFD700` 10.96 / 10.27 | `#7A6700` 4.73 / 5.57 | `#AD9200` 3.05 | `#FFD700` on `#354618` 7.34 |
| 9 | Platinový jezdec | metal | `#E5E4E2` | 12.09 | `#E5E4E2` 12.09 / 11.34 | `#696968` 4.66 / 5.50 | `#939291` 3.11 | `#E5E4E2` on `#30483C` 7.8 |
| 10 | Diamantový jezdec | jewel | `#7DD3FC` | 9.22 | `#7DD3FC` 9.22 / 8.64 | `#416E83` 4.71 / 5.55 | `#5D9CBA` 3.03 | `#7DD3FC` on `#204540` 6.34 |
| 11 | Prémiový zákazník | jewel | `#38BDF8` | 7.17 | `#38BDF8` 7.17 / 6.72 | `#227195` 4.61 / 5.43 | `#2F9FD0` 3.00 | `#38BDF8` on `#15423F` 5.21 |
| 12 | Mistr silnic | jewel | `#3B82F6` | 4.18 | `#4F8FF7` 4.83 / 4.53 | `#2F68C5` 4.56 / 5.37 | `#3B82F6` 3.68 | `#629BF8` on `#15383F` 4.53 |
| 13 | Šampion | jewel | `#6366F1` | 3.44 | `#8285F4` 4.84 / 4.53 | `#575AD4` 4.66 / 5.50 | `#6366F1` 4.47 | `#8C8EF5` on `#1C343E` 4.54 |
| 14 | Veterán MotoGo | jewel | `#8B5CF6` | 3.63 | `#A079F8` 4.82 / 4.52 | `#784FD4` 4.61 / 5.43 | `#8B5CF6` 4.23 | `#A783F8` on `#22323F` 4.54 |
| 15 | Elitní jezdec | jewel | `#A855F7` | 3.88 | `#B670F8` 4.87 / 4.57 | `#8A46CB` 4.66 / 5.50 | `#A855F7` 3.96 | `#BB7AF9` on `#27313F` 4.55 |
| 16 | Ambasador | jewel | `#D946EF` | 4.44 | `#DC55F0` 4.83 / 4.53 | `#A535B6` 4.71 / 5.55 | `#D946EF` 3.46 | `#DF64F2` on `#2E2E3E` 4.59 |
| 17 | VIP | vip | `#EF4444` | 4.08 | `#F26262` 4.90 / 4.60 | `#BF3636` 4.69 / 5.53 | `#EF4444` 3.76 | `#F26969` on `#322E22` 4.52 |
| 18 | VIP Gold | vip | `#D4AF37` | 7.31 | `#D4AF37` 7.31 / 6.85 | `#7B6520` 4.78 / 5.64 | `#AE902D` 3.08 | `#D4AF37` on `#2E3F20` 5.4 |
| 19 | VIP Platinum | vip | `#F1F5F9` | 14.03 | `#F1F5F9` 14.03 / 13.15 | `#656769` 4.82 / 5.68 | `#919395` 3.08 | `#F1F5F9` on `#324A3F` 8.77 |
| 20 | Legenda MotoGo | legend | `#FFD700` | 10.96 | `#FFD700` 10.96 / 10.27 | `#7A6700` 4.73 / 5.57 | `#AD9200` 3.05 | `#FFD700` on `#354618` 7.34 |

**What the table shows:**
- **Raw `color_hex` on panel** is ≥ 3:1 for all 20 levels, so the ring is OK as a UI mark. As *text* it fails for 12–17 (3.44–4.44). That's why `accentDark` lightens those.
- **Raw hex on white** is only 1.10–4.47 (VIP Platinum 1.10, Platinový 1.27). A ring or mark on a light surface therefore needs a 1 px night keyline, and text uses `accentLight`.
- **Chip:** solid composite bg (`mix(panel, hex, .16)`, opaque, so the header aura can't undercut it) and solved text. Light-surface chip (`accentLight` on white + 14 % tint) is ≥ 4.56 for all levels.
- **Header aura** (radial top-right stop) is solved so white text over it stays ≥ 4.6:1. Without solving, 8/9/10/19 fell to 3.3–4.5.

| L | aura | white on aura |
|---|---|---|
| 1 | `#387F49` | 4.88 |
| 2 | `#3D7C57` | 4.98 |
| 3 | `#2E784C` | 5.37 |
| 4 | `#247244` | 5.89 |
| 5 | `#206F56` | 6.05 |
| 6 | `#5A6338` | 6.41 |
| 7 | `#567B6D` | 4.72 |
| 8 | `#687D28` | 4.61 |
| 9 | `#597C6E` | 4.63 |
| 10 | `#417E7B` | 4.67 |
| 11 | `#2C7D83` | 4.81 |
| 12 | `#2D6782` | 6.22 |
| 13 | `#3C5C80` | 6.92 |
| 14 | `#4B5882` | 6.96 |
| 15 | `#565682` | 6.89 |
| 16 | `#69507F` | 6.87 |
| 17 | `#7B4C4A` | 7.06 |
| 18 | `#6E7B39` | 4.61 |
| 19 | `#5C7B72` | 4.63 |
| 20 | `#8F6F1E` | 4.71 |

### 8.2 Primary CTA, glow, ring, effects

| L | Primary CTA fill (stops, angle) | Label | min label cr (≥4.5) | fill vs night | edge (≥3 vs night) | Glow colour · alpha · blur · halo | Ring paint | fx loop · ambient · burst |
|---|---|---|---|---|---|---|---|---|
| 1 | `#8DFF86` → `#37CF63` · 135° | `#08230F` | 8.16 | 8.42 | — | `#74FB71` · 0.5 · 22 | solid #9CA3AF · 3 px | shine · none · confetti |
| 2 | `#8DFF86` → `#5FDF88` · 135° | `#08230F` | 9.86 | 10.17 | — | `#86EFAC` · 0.5 · 22 | solid #86EFAC · 3 px | shine · none · confetti |
| 3 | `#8DFF86` → `#41D772` · 135° | `#08230F` | 8.9 | 9.18 | — | `#4ADE80` · 0.5 · 22 | solid #4ADE80 · 3 px | shine · none · confetti |
| 4 | `#8DFF86` → `#2DCA61` · 135° | `#08230F` | 7.74 | 7.98 | — | `#22C55E` · 0.5 · 22 | solid #22C55E · 3 px | shine · none · confetti |
| 5 | `#8DFF86` → `#26C485` · 135° | `#08230F` | 7.41 | 7.64 | — | `#14B8A6` · 0.5 · 22 | solid #14B8A6 · 3 px | shine · none · confetti |
| 6 | `#E9C5A3` → `#D69657` → `#CD7F32` → `#B9722D` · 115° | `#1A1405` | 4.81 | 4.52 | 1 px `#F3DFCC`→`#A46628` (3.7) | `#CD7F32` · 0.55 · 26 · halo 0.12/40 | conic #EBCCAD #CD7F32 #9A5F26 #EBCCAD · 3 px | sheen · sheenOnce · sparks |
| 7 | `#E3E3E3` → `#CBCBCB` → `#C0C0C0` → `#ADADAD` · 115° | `#0B1512` | 8.28 | 7.68 | 1 px `#EFEFEF`→`#9A9A9A` (6.12) | `#C0C9D6` · 0.55 · 26 · halo 0.12/40 | conic #E6E6E6 #C0C0C0 #909090 #E6E6E6 · 3 px | sheen · sheenOnce · sparks |
| 8 | `#FFED8C` → `#FFDE2E` → `#FFD700` → `#E6C200` · 115° | `#1A1405` | 10.54 | 9.91 | 1 px `#FFF5BF`→`#CCAC00` (7.77) | `#FFD700` · 0.55 · 26 · halo 0.12/40 | conic #FFEF99 #FFD700 #BFA100 #FFEF99 · 3 px | sheen · sheenOnce · sparks |
| 9 | `#F3F3F2` → `#EAE9E7` → `#E5E4E2` → `#CECDCB` · 115° | `#0B1512` | 11.7 | 10.84 | 1 px `#F9F8F8`→`#B7B6B5` (8.51) | `#D8E0EC` · 0.55 · 26 · halo 0.12/40 | conic #F5F4F3 #E5E4E2 #ACABAA #F5F4F3 · 3 px | sheen · sheenOnce · sparks |
| 10 | `#7DD3FC` → `#7DA0FC` · 135° | `#0A1F33` | 6.61 | 6.81 | 1.5 px `#B8E7FD`→`#9EB8FD` (8.8) | `#7DD3FC` · 0.58 · 28 · halo 0.16/44 | conic #7DD3FC #7DA0FC #7DD3FC #7DF9FC #7DD3FC · 12 facets · 3.5 px | glint · prismOnce · prism |
| 11 | `#4FC5F8` → `#4F80F8` · 135° | `#0A1F33` | 4.6 | 4.74 | 1.5 px `#9EDFFB`→`#7BA0FA` (6.77) | `#38BDF8` · 0.58 · 28 · halo 0.16/44 | conic #38BDF8 #3870F8 #38BDF8 #38F7F8 #38BDF8 · 12 facets · 3.5 px | glint · prismOnce · prism |
| 12 | `#3573DA` → `#3835DA` · 135° | `#FFFFFF` | 4.55 | 2.21 | 1.5 px `#90B2EB`→`#6A68E3` (3.86) | `#3B82F6` · 0.58 · 28 · halo 0.16/44 | conic #3B82F6 #3F3BF6 #3B82F6 #3BBAF6 #3B82F6 · 12 facets · 3.5 px | glint · prismOnce · prism |
| 13 | `#575AD5` → `#8757D5` · 135° | `#FFFFFF` | 4.82 | 3.14 | 1.5 px `#A3A4E8`→`#A581E0` (5.59) | `#6366F1` · 0.58 · 28 · halo 0.16/44 | conic #6366F1 #9963F1 #6366F1 #6391F1 #6366F1 · 12 facets · 3.5 px | glint · prismOnce · prism |
| 14 | `#714BC9` → `#A44BC9` · 135° | `#FFFFFF` | 4.74 | 2.91 | 1.5 px `#B19CE1`→`#BB78D7` (5.56) | `#8B5CF6` · 0.58 · 28 · halo 0.16/44 | conic #8B5CF6 #C95CF6 #8B5CF6 #5D5CF6 #8B5CF6 · 12 facets · 3.5 px | glint · prismOnce · prism |
| 15 | `#8443C2` → `#B643C2` · 135° | `#FFFFFF` | 4.59 | 2.92 | 1.5 px `#BB98DD`→`#C872D1` (5.56) | `#A855F7` · 0.58 · 28 · halo 0.16/44 | conic #A855F7 #E955F7 #A855F7 #7755F7 #A855F7 · 12 facets · 3.5 px | glint · prismOnce · prism |
| 16 | `#B139C3` → `#C3399D` · 135° | `#FFFFFF` | 4.78 | 3.48 | 1.5 px `#D492DE`→`#D26BB6` (5.35) | `#D946EF` · 0.58 · 28 · halo 0.16/44 | conic #D946EF #EF46C1 #D946EF #A646EF #D946EF · 12 facets · 3.5 px | glint · prismOnce · prism |
| 17 | `#FFF5F6` → `#FFE4E8` → `#FECDD6` · 135° · glyph crown | `#881337` | 6.8 | 12.24 | 1.5 px `#FB7185`→`#FDE68A`→`#E11D48` (3.67) | `#F43F5E` · 0.62 · 30 · halo 0.2/48 | double #EF4444 + #D4AF37 · crown notch · 3.5 px | edge · auroraOnce · crown |
| 18 | `#F7E9B8` → `#E6C869` → `#D4AF37` → `#B8932A` · 135° · glyph crown | `#14100A` | 6.54 | 5.94 | 1.5 px `#FFF6D6`→`#8C6A12` (3.43) | `#D4AF37` · 0.62 · 30 · halo 0.2/48 | double #D4AF37 + #FFF1C2 · crown notch · 3.5 px | edge · auroraOnce · crown |
| 19 | `#FFFFFF` → `#F1F5F9` → `#DCE3EC` · 135° · glyph crown | `#14100A` | 14.66 | 13.32 | 1.5 px `#FBCFE8`→`#BAE6FD`→`#BBF7D0`→`#FDE68A` (12.46) | `#E0EBFB` · 0.62 · 30 · halo 0.2/48 | double #F1F5F9 + #D4AF37 · crown notch · 3.5 px | edge · auroraOnce · crown |
| 20 | `#FFE27A` → `#FFD700` → `#FF9A1F` → `#FF6B00` · 135° · glyph laurel | `#241A06` | 6 | 6.03 | 1 px `#FFF4D6`→`#FFB000` (9.4) | `#FF8C00` · 0.66 · 34 · halo 0.24/56 | conic #FFE27A #FFD700 #FF9A1F #FF6B00 #FFE27A · laurel · 4 px | ember · auroraEmbersOnce · laurel |
| 0 (guest / RPC fail) | `#8DFF86` → `#37CF63` | `#08230F` | 8.16 | 8.42 | — | `#74FB71` · 0.5 · 22 | none (plain logo) | shine · none · — |

**Readings:**
- Every label ≥ 4.55:1 on every gradient stop. The tightest are 12 (4.55), 15 (4.59), 11 (4.60), bronze 6 (4.81).
- Fill vs night is ≥ 4.5 everywhere except the deep gems 12–16 (2.21–3.48). Their 1.5 px edge is ≥ 3.86 and the glow carries prominence.
- **Old app helper for comparison:** `_onColor` in `loyalty_ranks_screen.dart` picks ink `#0F1A14` vs white by luminance > .5. It colours the level number in the ladder badge (18 px/900) and the "TY" chip.
  - On raw colours it **fails for 14 of 20 levels**: 1, 4, 5, 6, 11–18, all white text at 2.10–4.47:1. Examples: Startér 2.54, Prémiový 2.14, VIP Gold 2.10.
  - The Legend "TY" chip (white on `#FF8C00`) is 2.33:1.
  - v2 replaces it with the solved tokens (`btn.label` on the tier fill, or `chip.text`).

---

## 9. Flutter mapping (both trees, each file < 5 000 tokens)

**Files:**

| File | Content |
|---|---|
| `lib/core/rank/rank_theme.dart` | `RankTheme extends ThemeExtension<RankTheme>`: the tokens above + `lerp`, for the 600 ms morph. Built from `rankThemeLevelProvider` (theme hold §5.7) + `loyaltyLevelsProvider` hex. Pure functions port `fit/mix/cr` 1:1; unit-test that every level meets the thresholds (golden table = §8) |
| `lib/core/rank/rank_button.dart` | Primary CTA. `DecoratedBox` (gradient + `Border` edge; a `GradientBoxBorder`-style painter for multi-stop edges); `shGlow` + halo `BoxShadow`s; the loop fx in a `RepaintBoundary` with a single `AnimationController` shared by glow pulse + tier fx, so it counts as one loop slot; `TickerMode` off when off-screen or covered |
| `lib/core/rank/rank_fx.dart` | `CustomPainter`s: sheen band, glint stars, edge run (`SweepGradient` rotation), embers (≤ 4 particles, pre-allocated) |
| `lib/core/rank/rank_ring.dart` | Ring + progress arc (`SweepGradient` / solid), crown notch / laurel as small SVG via `LpIcon`. Reuse in the header, the PROFIL tab and the celebration |
| `lib/features/loyalty/levelup_gate.dart` | §5 gate. `loyalty_levelup_overlay.dart` keeps the celebration widget; split it (it is 985 lines today, over the 5 000-token rule) into `levelup_scene.dart` + `levelup_media.dart` + `levelup_burst.dart` |

**Existing widgets to retrofit with `MgMotion.reduced`:** `GlowPulse`, `ShimmerSweep` (moto_fx.dart), the ranks-screen ambient sparks, `LevelUpCelebration`.

**Performance:**
- Glow `BoxShadow` blur ≤ 34 px on one widget is fine.
- Never animate `BoxShadow` blur per frame on lists. Animate an `Opacity`/`Transform` of a pre-blurred layer instead.
- Target 60 fps on mid Android.

---

## 10. Open questions for the owner

1. **VIP 17 is SOS red.** OK to style VIP (17) buttons as pearl + ruby (red only as glow/edge/ring), or should `color_hex` of VIP change in Velín (e.g. ruby `#BE123C`)?
2. **Legenda (20) and Zlatý jezdec (8) share `#FFD700`.** v2 separates them by material (molten gold→orange + laurel). Keep the hex, or recolour Legenda in Velín?
3. **Monthly award** runs with the leaderboard hidden. Keep it (and explain it in the celebration), switch on `loyalty_leaderboard`, or pause the cron until the leaderboard is public?
4. **Approve the optional backend** (`loyalty_events` + push "Nový rank" + `celebrated_level` folded into `get_loyalty_status`) for instant, explained level-ups. Without it the client-only gate still guarantees "never missed", only up to 20 s late for bonus/admin changes.
5. **Celebration music:** default on? (Today it is always on at full volume.) Proposed: on, .7, fade-in, off under reduced motion, setting "Zvuk oslav".
6. **"+1 bod" nudge:** bring it back conditionally ("Po dokončení této jízdy: Stálý jezdec (4 %)")? The v1 spec dropped it.
