# Journey rig — click through the NEW look like a customer

The rig boots the **real app router** (`lib/core/router.dart` → `routerProvider`:
real redirects, real routes, real v2 shell via `V2Switch`, `MgV2Gate`) with the
v2 flag ON, Czech, 360×780, text scale 1.0, reduced motion. All data is faked
(no network, no payments, no camera): provider fakes from `test/v2/support`
(`journey_overrides.dart`) and a fake Supabase backend (`journey_backend.dart`)
that answers availability (`check_moto_availability`, `get_moto_booked_dates`),
the documents gate (`get_docs_gate_checklist`) and `profiles`; everything else
answers an empty list. Availability, the Home offer, the catalog filter and the
booking calendar run their REAL code against that backend.

After every step the rig settles and writes `<dir>/<nn>.png` (360×780 px =
logical px, incl. dialogs and sheets) and one line in `<dir>/log.txt`.

## Run

```
cd Motogo-app-main/motogo-app-flutter
MG_JOURNEY=1 MG_JOURNEY_STATE=ready MG_JOURNEY_SCRIPT=/path/steps.json \
MG_JOURNEY_DIR=/path/out flutter test --no-pub test/v2/journey/journey_run_test.dart
```

`MG_JOURNEY_LOOK=old` boots the OLD look (flag off) instead of the new one
(header line `flag=old`). Without `MG_JOURNEY=1` the run test is skipped. Optional `MG_JOURNEY_START=/path`
jumps there right after boot (logged as boot route; it is a jump, not a click).
The always-on smoke test is `journey_smoke_test.dart`. Example script:
`scripts/book_ready.json` (Home → dates → bike → detail → REZERVOVAT → form →
own gear + consents → POKRAČOVAT K PLATBĚ → payment → system back).

## States (`MG_JOURNEY_STATE`)

| id | customer |
|---|---|
| `first_launch` | not logged in → the router lands on `/login` |
| `new_user_no_docs` | logged in, profile = name + e-mail only, no documents, no cards |
| `ready` | full profile, documents verified (gate ok), licence A+B, 1 saved card |
| `licence_low` | as `ready` but licence A2+B (BMW needs A) |
| `unpaid_booking` | BMW booking `pending`/`unpaid`, created 5 min ago (payment strip/FAB) |
| `paid_upcoming` | Husqvarna, self-service Velké Němčice, in 2 days, door codes sent |
| `paid_upcoming_no_docs` | same, but ŘP missing → codes held back (`docs_missing`) |
| `active_rental` | Husqvarna active since yesterday, handed over, codes sent |
| `completed` | BMW completed 4 days ago, not rated |
| `paid_upcoming_ext_free` | Husqvarna paid, in 3–6 days (4 days), pickup 09:00; nothing booked after it → extension allowed (surcharge), shortening (refund), moving, place/time, cancelling |
| `paid_upcoming_ext_taken` | same, but the SAME bike is booked by another customer on days 7–10 (right after) → extension refused |
| `active_rental_ext_free` | Husqvarna active since yesterday until day 2, handed over; nothing after → extension allowed |
| `active_rental_ext_taken` | same, but days 3–6 booked by another customer → extension refused |
| `paid_upcoming_swap` | as `paid_upcoming_ext_free` but licence A2+B; swap candidates: Shotgun booked by another customer on days 4–5 (Obsazeno), Yamaha free, BMW needs A (filtered out by the licence check) |
| `paid_upcoming_surcharge_pending` | as `paid_upcoming_ext_free` plus a surcharge of this booking paid 2 min ago and not yet confirmed (`PaymentPendingMarker`, kind `edit`) → a second surcharge is blocked ("Platba se ověřuje") |

Bikes: BMW R 1200 GS Adventure (Mezná, staffed, A; booked by someone else in
3–5 weeks), Husqvarna 701 SM (Velké Němčice, self-service, A2/A), Royal Enfield
Shotgun 650 (A2, service block for 60 days), Yamaha PW50 (kids).

Other customers' bookings live in `JourneyData.others` and are answered by
the fake backend in `get_moto_booked_dates` and `check_moto_availability`
(which honours `p_exclude_booking_id`, like the server). The refusals are the
app's REAL checks against that data (calendar, availability, licence filter,
pending-payment marker) — nothing in the rig refuses on its own.

### Changing a booking — ready-made scripts (`scripts/`)

| script | state | what it clicks |
|---|---|---|
| `edit_ext_free.json` | `paid_upcoming_ext_free` | Rezervace → Upravit → tap 2 days after the end → "ZAPLATIT DOPLATEK" → surcharge payment page → back |
| `edit_ext_taken.json` | `paid_upcoming_ext_taken` | tap the crossed-out day → "Tento den je obsazený"; tap past it → "Mezi koncem rezervace a vybraným dnem jsou obsazené dny" |
| `edit_active_ext_free.json` / `edit_active_ext_taken.json` | `active_rental_ext_*` | the same for a running rental |
| `edit_shorten.json` | `paid_upcoming_ext_free` | Zkrátit → Zkrátit konec → new last day → refund in the bottom bar → save |
| `edit_move.json` | `paid_upcoming_ext_free` | Posunout termín → new first day → POSUNOUT ZDARMA |
| `edit_place_time.json` | `paid_upcoming_ext_free` | delivery (locked at a self-service branch), pickup time 09:00 → 15:00, save |
| `edit_swap.json` | `paid_upcoming_swap` | Výměna motorky → taken bike / free bike → POTVRDIT VÝMĚNU |
| `edit_surcharge_pending.json` | `paid_upcoming_surcharge_pending` | extension → ZAPLATIT DOPLATEK → blocked sheet |
| `edit_from_detail_cancel.json` | `paid_upcoming_ext_free` | detail → UPRAVIT REZERVACI → back → Zrušit rezervaci (storno terms + refund) |
| `profile.json` | `paid_upcoming` | Profil tab → edit personal data (licence no., expiry, groups) → Moje doklady → Platební metody |

The day taps are coordinates for 360×780 in the new look; they depend on the
month layout, so check the PNG when the calendar month changes.

## 5.0.1 states — fleet, winter, filters, routes (`journey_states_v501.dart`)

All: full profile, documents verified, licence A+B, rank 3. Fleet = 12 real
models (`journey_fleet.dart`) on the two real branches (live ids/names):
MotoGo24 Mezná (staffed) and MotoGo24 Velké Němčice (self-service); BMW has
3 photos + 2 videos, Husqvarna 701 SM 1 photo + 1 video, Z 900 and Africa
Twin 1 video, Shotgun photos only. `availableToday` follows the state's data
(false when a booking or a closed branch covers today).

| id | data | script (`scripts/`) |
|---|---|---|
| `nodates` | nothing set (default Home); Tiger, VTX, Husqvarna booked by others days 0–4 | `v501_nodates.json` — offer without dates, pager, rows under "Aktivní rezervace", tab switch + background = new order, the bike's calendar |
| `fleet12` | 6 bikes booked by others days 0–9; every availability answer takes 2.5 s | `v501_fleet12.json` — "1 / 12", weekend chip → skeleton → "1 / 3+" → real count, Motorky one bike per swipe |
| `winter` | both branches closed day −14…+130 (`branch_closures`) | `v501_winter.json` — "Volná od" day 131, "V tyhle dny máme zavřeno", calendar |
| `booked_out` | every bike booked by others days 0–20 | `v501_booked_out.json` — "V tyhle dny je vše obsazené", "Volná od" day 21 |
| `filters_on` | filter left set: licence A2 + 30–60 kW | `v501_filters_on.json` — loud card on Home and Motorky, chip ✕, "Zrušit vše", heading opens the panel |
| `filters_many` | naked, A2, 35–70 kW, "Jen dnes volné", branch Velké Němčice, days 7–9 | `v501_filters_many.json` — 0 results, chip ✕, "Zrušit vše" keeps dates + branch |
| `filters_slow` | as `filters_on` + days 7–9, availability answers take 3 s; starts on `/search` | `v501_filters_slow.json` — "Hledám…" during the recount |
| `routes_photos` | 20 routes (`journey_routes.dart`: live names, lengths, stops → places), starts on `/routes-list` | `v501_routes_photos.json` — full-screen card, preview page, place photo, swipes, detail, back to the same card |
| `routes_filtered` | as `routes_photos` + country filter CZ | `v501_routes_filtered.json` — loud card, "Zrušit vše" |
| (video) | `nodates` + `MG_JOURNEY_VIDEO=wifi MG_JOURNEY_MOTION=full` | `v501_video.json` — photo 5 s → video, background → photo, detail hero video |
| (video) | `nodates` + `MG_JOURNEY_VIDEO=mobile MG_JOURNEY_MOTION=full` | `v501_video_mobile.json` — no autoplay, "Pustit video" |

Fake backend for these states: `get_motos_availability_status` (POST, no
params) answers `{moto_id, next_available_date}` = the first day from today
without any block; `branch_closures` (GET) answers the rows with
`closed_to >= today`; `get_moto_booked_dates` adds a `branch_closed` range for
a closed branch and `check_moto_availability` answers false inside it. A state's
`availDelayMs` delays both availability RPCs (fake time; waits advance it).
The Home offer order is random per mount (the app's own seed), so which bike
shows first differs per run; counts, banners and pills do not.

## Photos, video, motion (env vars)

| env | effect |
|---|---|
| `MG_SHOT_IMG_DIR=<dir>` | real photos: every CachedNetworkImage (MgImage, RouteImage, precache) gets a local file from `<dir>/moto/*.jpg` / `<dir>/route/*.jpg` through an in-memory cache manager (`test/v2/support/shot_images.dart`). Fixture URLs `…/media/shot/moto/07.jpg` (`shotUrl('moto', 7)`) map to that file, URLs listed in `<dir>/manifest.json` to theirs, any other URL to a stable hash pick (route/place-looking URLs from `route/`). Unset = placeholders as before. Also honoured by the render harness. The photos are NOT in the repo; the 5.0.1 set (14 bike + 14 route photos, ≤ 900 px, live public storage) is in the scratchpad folder `v501/img`. |
| `MG_JOURNEY_VIDEO=wifi\|mobile\|fail` | fake bike video player (`journey_media.dart`): a blue 16:9 frame "TEST VIDEO <file>"; `wifi` = autoplay allowed, `mobile` = play button only, `fail` = every video fails while loading. Unset = the app's own player against mocked channels (no Wi-Fi → play button). |
| `MG_JOURNEY_MOTION=full` | animations on (default: reduced motion). Autoplay never happens under reduced motion. Steps then take longer (looping animations keep `settle` at its 3 s cap). |

The header line of `log.txt` names all three (`photos=real video=wifi
reducedMotion=off`); each step line carries `t=<s>` (fake time since boot).

## Steps (JSON array)

| step | meaning |
|---|---|
| `{"tap":[x,y]}` | tap at logical px (= PNG px) |
| `{"tapText":"…"}` | tap the first visible, tappable text (exact match, then "contains"); `"index":1` = 2nd match |
| `{"type":"…"}` | replace the text of the focused field (tap the field first) |
| `{"scroll":[x,y,dy]}` | slow drag from (x,y), no fling; `dy > 0` reveals content below, `dy < 0` goes back up |
| `{"back":true}` | system back (Android back button) |
| `{"wait":ms}` | let time pass |
| `{"go":"/path"}` | JUMP via `router.go` — not a click; logged as JUMP |
| `{"swipe":[x,y,dy]}` | quick flick over dy px (a snapping list moves one item) |
| `{"tapKey":"motoFltClear"}` | tapText with the Czech text of an i18n key |
| `{"tapType":"MotoFilterCardV2","dy":28}` | tap a widget by class name at its centre x, `dy` px below its top (no `dy` = centre; `index` = n-th) — only built (on-screen) widgets |
| `{"lifecycle":"pause"\|"resume"\|"cycle"}` | app to background (inactive → hidden → paused) / back / both |

Any step may carry `"note":"…"` (copied into the log).

## Log line

`nn | step | what was hit | route=<top page> (pushed over <base>) | modal=yes/no | server=[calls] | note | EXCEPTION`

* `HIT "<semantics label>" <AppWidget>Detector>` (`<TextField>` for an input) — the tap landed on something
  tappable; `MISS (nothing tappable here; under the finger: "…")` — it did not.
* `NOT FOUND` (tapText) — no visible text; scroll first.
* `modal=yes` — a dialog / bottom sheet is on top.
* `server=[…]` — fake backend calls the step caused (e.g. `POST /rest/v1/bookings`).

## Limits (where the rig cannot go)

* **Paying.** `ZAPLATIT` creates the draft booking against the fake backend,
  which refuses it → the app's own error sheet "Rezervaci se nepodařilo
  vytvořit" (+ Zkusit znovu). The Stripe / Google Pay / Apple Pay native sheet
  never opens; the thank-you page (`/success`) and `/payment-result` are not
  reached by clicking — use the render cases (`test/v2/render/cases_ux_pay_shop.dart`)
  or `{"go":…}` with care (they need provider state a jump does not set).
* **Login / registration / password reset.** Forms can be filled and tapped, but
  the auth server is fake → the app's error message. Start logged-in states instead.
* **Debug-only assertion `markNeedsBuild() called during build`.** The
  profile page and the edit page ask for fresh data when they open
  (`ref.invalidate` + read in their first `didChangeDependencies`). That
  refreshes the provider while the page is being built, and Riverpod tells
  the other mounted listeners (in the new look Home's header/bike list kept
  alive by the shell; the booking detail under the edit page). Debug Flutter
  asserts on that; release builds just mark those widgets dirty and rebuild
  them in the same frame. `JourneyRig.guard` catches only this assertion and
  the log prints it as `DEBUG-ASSERT …`; anything else still fails the run.
  (Until 2026-11-13 both pages called `ref.invalidate` in `initState`, which
  in debug builds replaced the page with the error widget — fixed, guarded by
  `journey_open_screens_test.dart` in both looks.)
* **Writes.** The fake backend answers every write with an empty list, so
  e.g. a shortening is "saved" and the refund edge function "fails" (the app's
  own "Úprava je uložená, vratka čeká"); `reschedule_booking_free` and the
  swap dry-run `split_booking_moto_swap` get no proper answer → the app's own
  error messages ("Termín se nepodařilo posunout…", "Výměnu teď nejde
  provést…", no "Cenový rozdíl"). The swap price and the move cannot be
  completed by clicking.
* **Camera / document scanner, photo picker, GPS, share, phone / e-mail,
  external links.** Plugin channels answer `null` (permissions = denied,
  location services off): `/docs/scan` shows its document-choice page, but the
  live camera, the gallery picker and external apps never open (what the
  scanner shows after "scan" was not checked). Map tiles stay blank (HTTP 400
  in tests); the map panel shows its own "map did not load" note.
* **Onboarding overlays** (intro animation, language, permissions) live in
  `main.dart`'s `MotoGoApp`, which the rig does not mount — they are marked done.
* **Push notifications, level-up celebration, ride recorder watcher, update
  checks** (also `MotoGoApp`) are not mounted.
* Emoji glyphs draw as boxes (no emoji font in tests); network images show
  their placeholders unless `MG_SHOT_IMG_DIR` is set. Material icons and
  Montserrat are real.
* With `MG_SHOT_IMG_DIR` a place / route photo is a real route photo but
  not necessarily of THAT place (hash or fixture mapping); bike photos of
  the fleet are the real bike's photo. Map tiles still stay blank.
* `settle` ends after 0.4 s without a scheduled frame: a slow fake server
  (`availDelayMs`) is caught mid-load — add `{"wait":…}` steps.
* A debug-only "markNeedsBuild() called during build" reported through
  `FlutterError.onError` is logged as DEBUG-ASSERT like the zone one (seen
  once from `MgToTopLayer` / `MgShellChrome.scrollIdle` after scrolling
  Motorky and tapping a hidden tab).
* Realtime streams are replaced by fixed values: nothing changes "by itself"
  (codes released, payment confirmed) during a run.
