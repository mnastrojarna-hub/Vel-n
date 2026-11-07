# Audit routes_rides — Trasy tab, ride recording, Moje zážitky, navigation skin (v2, flag ON)

Date 2026-11-07 · Android tree `Motogo-app-main/motogo-app-flutter` (iOS byte-identical for every routes/v2 file; the 7 non-identical routes files differ ONLY in `userAgentPackageName`, verified).
Inputs: DESIGN_V22 §1.4/§1.5/§2.4/§4/§5.1/§5.2/§6/§7.8–7.10, DESIGN_V21 §2.3–2.6 (T1–T19, Trasy motion table §2.5), PLAN 2026-10-22 (pause / auto-pause / multi-day / merge), boards TrasyHub / Zazitky / TrasaDetail (+ Stavy group 16).

## Method
- Boards rendered with Playwright (390×2300/2960) — `uxp/rr/b/th_*`, `zz_*`, `td_*` (deleted after composing); comparison sheets kept in `uxp/rr/b/c*.png`, `g*.png`, `dock.png`.
- App rendered with the real harness (`test/v2/render`, MG_VERIFY_SCALE 1.0, Montserrat 400–900 instanced from the web VF, reduced motion, scroll shots): routes + rides matrix cs 360×780 + 320×690 (177 cases, all green), routes extra (POI sheet, filter/sort sheets), spot checks de/fr 320×690. Map tiles / Material-icon fonts are stubbed in tests → map grey + "▯" glyphs in renders are harness artefacts, not findings.
- Findings that cite "board" were checked side by side (app 360 vs board 390).

## LC — coverage (flag ON): every page / sheet / dialog / overlay / state of the area
✓ = v2 look · ◐ = hybrid (v2 frame/theme, old body parts) · ✗ = old look

| # | Surface | Entry | Status | Evidence |
|---|---|---|---|---|
| 1 | Místa (tab root, AllPoisScreen asTab) + location prompt, map preview, chips, cards, selection, loading/error/empty | `/routes` | ✓ | renders routes__places__* |
| 2 | Trasy list (RoutesScreen) + band, filter/sort sheets, empty/error/loading | `/routes-list` push | ✓ (skeleton mismatch F-18) | routes__routes__* , extra filter/sort |
| 3 | Moje zážitky (all 4 sub-tabs, logged-out, recording, empty, error) | `/my-experiences` (outside shell, own v2 nav) | ✓ (fidelity F-12…F-17) | rides__moje__* |
| 4 | "+" add menu sheet | header + | ✓ | routes__places__add-menu |
| 5 | Record dock idle / live / selection / guards | all 3 segments | ✓ (F-05, F-06) | dock.png |
| 6 | Recorder screen (idle, manual, rental, auto-paused, armed, paused, guard home/long, GPS lost) + stop confirm | dock / Moje row | ✓ layout differs from board (F-04) | rides__recorder*__* |
| 7 | Ride detail (S MotoGo / soukromá / výpadek / missing), stats, stages, trip row, sharing switch, stops | `/ride/:id` | ✓ (F-08, F-09) | rides__detail__* |
| 8 | Stop / point sheet (new, edit, error) | ride detail map tap | ✓ | rides__point__* |
| 9 | Ride share sheet, delete + edit dialogs | ride detail | ✓ (brand glyphs F-37) | rides__sheet/dialog |
| 10 | Trips: Moje trip cards, trip detail (multi-day, rental, member, error, gone), merge screen | Moje / ride detail (v2 paths) | ✓ | rides__trips__* |
| 11 | **Trip card + trip detail + merge + trip dialogs reached from Reservation detail "Jízdy z výpůjčky"** (`BookingRidesSection` → `RideTripCard` → `RideTripDetailScreen` / `RideMergeScreen` / `rideTripNameDialog` / `rideConfirm` / `rideTripDeleteSheet`) | Rezervace detail v2 (`res_detail_view_v2.dart:148`) | ✗ | `ride_booking_section.dart:36-70`, `ride_trip_card.dart:33-41` (no seam), `ride_trip_detail_screen.dart:26`, `ride_merge_screen.dart:20`, `ride_trip_ui.dart:12/49/75` |
| 12 | Route detail (ok / no POIs / abroad / missing / error) | `/routes/:id` | ✓ body · ◐ loading = spinner (F-19) | routes__detail__* |
| 13 | **Route reviews**: section in route detail, reviews sheet from route-card ★ and from navigation "Ohodnotit trasu", review editor (stars, text, photos) | detail / list / nav | ✗ | `route_reviews.dart:87,245,396`; used by `route_detail_view_v2.dart:196`, `routes_screen.dart:1517`, `route_navigation_screen.dart:1737` |
| 14 | **POI rating bar + POI reviews section + editor** inside the POI (place) sheet | place sheet | ✗ (sheet frame ✓) | `poi_rating.dart:20`, `poi_reviews.dart:31,82`; `route_poi_sheet.dart:524,528` |
| 15 | Place (POI) sheet frame: counter, close, hero, chips, Okolí, trip button | Místa / maps / detail | ✓ (no ‹ › F-24) | routes__poi_sheet__* |
| 16 | **Fullscreen photo viewer** (route gallery, POI hero/thumbs) | detail / POI sheet | ✗ (black dialog, Material ✕ top-right, "n fotek" text, no dots, no swipe-down) | `route_poi_sheet.dart:593-676` |
| 17 | Photo credit sheet | viewer © | ✓ | `route_poi_sheet.dart:690` (v2 branch) |
| 18 | **Fullscreen route map** ("Zobrazit na mapě") | route detail pill | ✗ (MotoGoColors.bg, white 42 px r-lg box + Material close) | `route_detail_screen.dart:661-700` |
| 19 | **"Otevřít v jiné aplikaci" sheet** (Mapy.com / Google / Apple) + "nemá dost bodů" snack | route detail dock | ✗ | `route_detail_screen.dart:703-760` |
| 20 | Route builder / planner (+ nearby POI panel, stops, save/suggest sheets, name sheet) | `/route-build` | ✓ (F-27, F-28) | routes__builder__* |
| 21 | Place picker (pickMode), from-route | `/pois`, builder | ✓ | routes__places__picker / from-route |
| 22 | Navrhnout trasu / Přidat místo forms (+ link decode, map, photos) | + menu / long-press | ✓ | routes__form__* |
| 23 | **"Odesláno" success sheet** after submit (route, place, builder Navrhnout) | 3 flows | ✗ (white r22 sheet, old check + old button) | `submit_common.dart:262`; callers `community_submit.dart:254`, `route_submit_screen.dart:190`, `route_builder_screen.dart:898` |
| 24 | Mapa míst (header, controls, selection dock, add-place disc) | `/places-map` | ✓ (no AI disc F-30) | routes__map__places-map* |
| 25 | **Mapa tras – point panel** ("Trasy přes vybraný bod", route cards, "Detail ›", Další trasa / + ostatní místa mini buttons, status texts) | `/routes-map` tap point | ✗ (MotoGoColors g100/greenPale cards, Material `alt_route`/`layers`/`chevron_right`, `#8AAB99` hint text = banned meta on dark) | `routes_map_picker.dart:46-300`, `routes_map_screen.dart:255, 340-400` |
| 26 | **Route navigation**: top bar ✓ (back/end discs, REC chip, stops chip); everything else old: map line colours + branch flag marker, HUD (speed + 4 stats), NavNextStopPill, StopReachedCard ("Dojel jsi na místo", DALŠÍ), RouteDoneCard ("Trasa dokončena", OHODNOTIT), NavForkHint, NavStatusBanner (hledám polohu / mimo trasu / přepočítávám / poloha zakázána), compass + zoom + recenter buttons, stops sheet, "Ukončit trasu?" AlertDialog (neon ElevatedButton on white), "Uložit trasu" AlertDialog + login snack, exit/permission scaffold | `/route-nav/:id`, `/route-nav-custom` | ◐ | `route_navigation_screen.dart:1123,1190,1546-1600,1640-1820`; `route_nav_widgets.dart:16,43,111,339,508,628,801`; `route_nav_status.dart:14` |
| 27 | Ride start / stop results (not signed in, location off, no permission, imprecise, failed; saved, too short, save failed offline; paused / resumed) | dock, recorder, Moje, Home row | ◐ (v2 toast skin via theme, but §4.4 prescribes T2 sheets for every failure + the saved success sheet) | `ride_actions.dart:22`, `ride_start_feedback.dart:13-58` |
| 28 | Old `RideGpsLostBanner`, `RideRecControlsCard`, `RideTripRow`, `RideNavRecChip`, `ride_pause_sheet.dart` | old bodies only | n/a (not reachable with flag ON) | — |

Exceptions in this area: none (no native system sheet; the share uses our own sheet; external map apps are the OS).

## Prioritized improvements
Format: **id · P · lens · screen file:line** — now → proposal · why (king / conversion) · risk · shared primitive.

### P1
**F-01 · P1 · LC · Route reviews (section, sheet, editor) `route_reviews.dart:87/245/396`, `route_detail_view_v2.dart:196`, `routes_screen.dart:1517`, `route_navigation_screen.dart:1737`**
Now: old look everywhere a customer rates or reads reviews: Material stars `#F5B301`, plain "Recenze" heading, mint pill "Napsat recenzi" with neon border, grey "Zatím žádné recenze", white r20 sheet, old editor, SnackBars.
Proposal (board TrasaDetail "Detail trasy" + "napsat recenzi", V21 T6): new `features/routes/v2/route_reviews_v2.dart` (+ `review_editor_v2.dart`) as V-seams inside `RouteReviewsSection.build`, `_ReviewsSheet.build`, `_ReviewEditor.build` with the SAME state/RPC/callbacks: `RtSectionV2(icon: star, title: Recenze)`; summary = white card r16 "4,7" 32/900 ink + 5 `MgIcons.starFilled` 18 `MgColors.star` + "3 recenze" meta `#55705F`; review cards white r16 1 px line, stars 14, author 14/800 ink, text 14/600 `#2C4A3A`, photo thumbs 72 r10 (tap → v2 viewer F-03); empty = T3 info banner "Zatím žádné recenze. Buď první!"; action `MgBtnGhostLight` "✎ Napsat recenzi" 48; sheet = `RtSheetV2` (grabber, ✕ 44); editor = light sheet: 5 star buttons 44 (tap = rating, MgPop on select), `MgTextArea` lineInput, "Přidat fotky (n)" ghost, primary `MgBtnInk` "Odeslat recenzi" pinned, busy spinner inside button; success → v2 toast "Uloženo". Errors keep their copy.
Why: reviews are social proof on the page that leads to ZVOLIT TRASU; the old mint pill reads as a different app. Risk: none functional (render-only seams). Shared: none new (RtSheetV2, MgBtnGhostLight, MgStateBanner, F-03 viewer).

**F-02 · P1 · LC · POI rating + reviews in the place sheet `poi_rating.dart:20/123`, `poi_reviews.dart:31/82/116/270`, `route_poi_sheet.dart:524-528`**
Now: old rating bar (Material stars, "Klepni na hvězdy a ohodnoť") and old reviews section/editor inside the otherwise v2 place sheet.
Proposal (board Zazitky "Detail místa · hodnocení"): seams to `poi_rating_v2.dart` / `poi_reviews_v2.dart`: row "Zatím bez hodnocení · Klepni na hvězdy a ohodnoť" 14/800 ink + meta, 5 tappable 44 px `MgIcons.star` (filled `MgColors.star` up to the value; MgPop 300 on tap, haptic selection); "Recenze · 0" section head, empty line, `MgBtnGhostLight` "✎ Napsat recenzi"; editor as F-01. Same callbacks / RPCs.
Why: same as F-01, plus the rating is the one-tap engagement on a discovered place. Risk: none. Shared: reuse F-01 parts (`MgStarRow` local to routes/v2).

**F-03 · P1 · LC+L1 · Fullscreen photo viewer `route_poi_sheet.dart:593-676`** (route gallery `route_detail_view_v2.dart:189`, POI hero/thumbs `route_poi_sheet.dart:317/384`)
Now: black `showDialog`, ✕ = Material close in black@.55 circle at top-RIGHT, counter "7 fotek" (no position), no page dots, no swipe-down-to-close, pinch 1–5× OK, no fade-in placeholder (SizedBox).
Proposal (V22 §6.1 "Viewer ✕ photo style", §6.2 viewer row, board TrasaDetail "fotka na celou obrazovku"): v2 branch building the shared viewer: ✕ `MgV2Back(style: photo, close: true)` at (16, top+8); counter pill "3 / 7" (night@.8 + ring, 12.5/800 tabular) top-right; page dots ≤ 7 (else counter only) bottom-centre; vertical drag > 96 px or fling > 700 px/s = close (existing pop) with the image following the finger and backdrop fading (opacity 1 → 0.4) — only when scale == 1 so pinch/pan inside zoom still works; double-tap = zoom 2.5× toggle (InteractiveViewer controller, MgMotion.thumb 300 easeOutCubic); © credit button kept bottom-left (44 hit area). Reduced motion: close without the follow animation.
Why: photos are the emotional hook of a route/place; a premium viewer is expected (swipe down to close is the platform-standard instinct). Risk: gesture conflict pinch vs swipe-down → enable dismiss only at scale 1; PageView horizontal vs vertical dismiss are orthogonal. Shared: **"MgPhotoViewer" (photo pager + pinch + double-tap + swipe-down-to-close + counter/dots + fade-in)** in core/v2 — the catalog FullscreenGallery and branch photos need the same → one primitive.

**F-04 · P1 · L0 · Recorder screen live card `recorder_parts_v2.dart:23-100`, `recorder_screen_v2.dart:110-214`**
Now: 88 px disc with ping + "NAHRÁVÁM" + one sentence + a wrap of small chips (km, v sedle, Ø, den, mode, GPS). The numbers a rider wants are 12–13 px chip text; nothing big. Board (Zazitky "Záznam jízdy · obrazovka", §4.2 D): status chip "● NAHRÁVÁM", time 48/900 white tabular, then two big tiles: distance 32/900 neon + "vzdálenost", Ø 20/800 + "Ø rychlost"; chips row "GPS přesný" (amber "GPS slabý"), mode chip, "od 8:29 · start".
Proposal (look only, values that already exist): keep the phase disc but shrink to 56 and put it inline left of the status line; under it the **numbers hierarchy**: `liveMovingSec` as "1 h 12 min" (48/900 white tabular; label "v sedle" 12/700 `#9FC4B1`; no seconds — the value updates per batch, ticking seconds would lie) · tile pair (well-on-dark white@.06 r16, 1 px white@.10): `liveKm` 32/900 neon "38,2 km" + "vzdálenost"; Ø (when ≥ 5 min, existing `recAvgV2`) 20/800 white; chips row as now (GPS/mode/day; add "od HH:MM · start" from `tripStartedAt`, existing field). Paused / auto-paused / guard phases keep their sentence + "od HH:MM" above the numbers. No count-up (spec). Same `Semantics(liveRegion)`.
Why: the ride is the customer's moment of pride — the screen must read at arm's length on a tank bag. Risk: none (display of existing state). Shared: none (MgType.display exists).
Note: the board's live trace map card needs the live track points in `RideRecorderState` (not there) → owner decision OD-03.

**F-05 · P1 · L0 · Record dock idle CTA `record_dock_v2.dart:92`**
Now: "ZAZNAMENAT JÍZDU" without the ⏺ glyph. Board + §4.2 A: `[ ⏺ ZAZNAMENAT JÍZDU ]` (icon 20 + gap 8 are inside the fit budget; "green ⏺ while idle, red only while live").
Proposal: `MgCta(leadingIcon: MgIcons.recordDot)` — icon 20 in the label colour, gap 8; same for recorder idle "ZAČÍT ZÁZNAM" (`recorder_screen_v2.dart:66`). Fit check fr "ENREGISTRER LA SORTIE" (253 px incl. icon in 294).
Why: the glyph tells "record" before reading — R3 "nikde jsem nenašel zaznamenat jízdu". Risk: label fit at 320 → MgCta already scales (MgWordFit); test 8 langs × 320. Shared: **MgCta `leadingIcon`** (additive param).

**F-06 · P1 · LC+L3 · Ride start/stop results `ride_actions.dart:22`, `ride_start_feedback.dart:13-40`**
Now: every result is a SnackBar (4–8 s) — "Přihlas se…", "Poloha je vypnutá" (+ action), "Zamítnuto", "Přesná poloha", "Start selhal", and after the ride "Jízda uložena" / "kratší než 1 km" / "uložíme až chytíš signál".
Proposal (§4.4 #2–#7, #14–#17, Stavy 16.2–16.17, §5.1 rule 5 "errors that need action are never a toast"): in v2 show a T2 sheet (`showMgSheet` + `MgStateSheetBody`, tone disc `MgToneDisc`) with the SAME result enum and the SAME actions: not signed in → "Přihlas se a vyraž" + PŘIHLÁSIT SE (`context.push('/login')`, the existing Moje login action) · Zpět; location off → "Poloha v telefonu je vypnutá" + ZAPNOUT POLOHU (`openFixSettings(locationOff)`); permission / imprecise → their titles + OTEVŘÍT NASTAVENÍ (`openFixSettings(permission)`); failed → "Záznam se nespustil" + ZKUSIT ZNOVU (re-calls `toggleManualRide(running:false)`) ; saved → success T2: ✓ tone disc (check path draws 300 + pop + one ring 700 ms, reduced = static) "Jízda je uložená" · "Najdeš ji v Moje zážitky → Jízdy." · HOTOVO (+ "Moje zážitky" btnText → existing `/my-experiences` push) ; too short → ⌁ "Jízda byla kratší než 1 km" · ROZUMÍM ; save offline → ⏳ "Jízdu uložíme, až chytíš signál" · OK. Keep toasts only for started / paused / resumed (non-blocking). Copy = existing keys where they exist (`rideManualSaved`, `rideManualTooShort`, `rideManualStopFailed`, `eoRide*`), [návrh] keys of §4.4 in `translations_ext_60_v2_ux_routes_rides.dart`.
Why: the end of a ride is THE success moment ("král"); today it is a 4 s strip. Errors need a fix path the customer can't miss. Risk: none functional (presentation of the existing result); "ZOBRAZIT JÍZDU" of §4.4 #14 needs the saved ride id → only if `rec.rideId` captured before `stop()` (read-only) — else omit (owner decision OD-07). Shared: `MgStateSheetBody` + `MgToneDisc(MgTone.ok)` (exist; the ok disc already carries the check-draw/pop).

**F-07 · P1 · LC · Navigation screen body `route_navigation_screen.dart:1123-1260, 1546-1820`, `route_nav_widgets.dart`, `route_nav_status.dart`**
Now: only the top-bar controls are v2; HUD, stop/next/fork/done cards, status banners, map buttons, stops sheet, both dialogs and line colours are v1.
Proposal (board TrasaDetail "Navigace ·" 15 states, V21 T11 "restyle only, no decorative motion"): new `features/routes/v2/nav/` views as seams inside each widget's build, same props:
- HUD (`NavHud`) → white r20 card, 1 px line, `MgShadows.card`; progress 5 px `#37CF63` on well; speed 40/900 ink tabular + "km/h"; 2×2 stats with `MgIcons` (flag/clock/alarm/mountain) 16 `#0D6E0D`, value 17/900 ink tabular, label 11.5/700 `#55705F`; arrived = "Jsi v cíli" 20/900 + flag icon.
- `NavNextStopPill` → white pill 40 h r999 line, pin 16, "Příští: Klášter Rajhrad · 3,2 km" 13/800, counter "3/5" well pill.
- `StopReachedCard` → white r20 card: icon tile dark 40 (neon pin-check), eyebrow "DOJEL JSI NA MÍSTO", H 18/900, chip `tintOk` "✓ Místo objeveno! · celkem 13" with a one-shot neon ring (MgMotion.pop 300 + ring 700, reduced static — V21 T11), CTA rank `MgCta(size: compact, loop:false)` "DALŠÍ: BLUČINA", 44 star + 44 list discs, ✕ 44 light.
- `RouteDoneCard` → white card, dark icon tile flag, "Trasa dokončena!", rank CTA "OHODNOTIT TRASU" (→ F-01 sheet), ✕ 44.
- `NavForkHint` → white card with 2 option tiles (well, `#0D6E0D` arrows) — the chosen = `btnInk` tile "Bluč ina · Příští".
- `NavStatusBanner` → T3 banners on the map (locating ⏳ chip, off-route ⌁ chip, GPS lost ⚠ 16.22, location off ⚠ 16.23 with "Zapnout polohu" = existing action, offline ⌁ chip 16.24).
- Compass / zoom / recenter → `MapRoundV2` (white 44, line, shadow; recenter = ink disc with neon locate when following off).
- Stops sheet (`showNavStopsSheet`) → `RtSheetV2` "Body na trase" + hint, rows: reached = ✓ tintOk disc, next = ink number disc + "Příští" chip, future = outline number; "Navigovat" `MgBtnInk` sm 40; branch row "M" disc.
- "Ukončit trasu?" + "Uložit trasu" → `MgDialogFrame` T6 (safe `MgBtnGhostLight` "Pokračovat" / action `MgBtnDestructive` "Ukončit" ; save = `MgTextField` + `MgBtnInk` "Uložit"); login snack → T3/T2 "Přihlas se a ulož trasu" with PŘIHLÁSIT SE.
- Line colours: ahead `#0D6E0D` 4 px on night@.22 6 px casing, ridden `#9DB3A8`@.6; branch flag = `MgIcons.flag` ink on neon disc.
Why: navigation is used for hours; a v1 island inside v2 breaks "one product". Risk: performance — keep no loops/blur on the map; markers as const widgets. Shared: none new (MapRoundV2, RtSheetV2, MgDialogFrame, MgStateBanner).

**F-08 · P1 · L1+L4 · Ride detail sibling swipe has no affordance and no motion `ride_detail_screen.dart:50-77`, header `ride_detail_parts_v2.dart:69-110`**
Now: horizontal swipe changes the ride (setState swap, no transition); nothing on screen says it is possible. Board (Zazitky "Detail jízdy"): pager "‹ 3/7 ›" (two 44 white discs + counter) in the header.
Proposal: pass `(index, total)` + `onPrev/onNext = _swipe(∓1)` into `RideDetailViewV2` → header shows the board pager (like `RouteStatsCardV2` sibling pager); wrap the body in `AnimatedSwitcher` keyed by ride id with a directional slide (offset 0.12 × direction + fade, `MgMotion.tab` 210 ms, `MgMotion.emphasized`; reduced = instant). Same for route detail sibling swipe (`route_detail_screen.dart:93-101`, pager exists) — add the same directional switch so the swipe is felt.
Why: browsing "my rides" like a photo album is the diary feeling; without motion the swap looks like a glitch. Risk: GestureDetector already exists; the transition must not rebuild the map controller (key the content below the map only, or accept map rebuild — it already rebuilds today). Shared: **"directional content switch" (MgSwipeSwitcher: AnimatedSwitcher + direction-aware slide/fade, reduced-motion safe)** — also used by Moje sub-tabs (F-15) and POI sheet.

**F-09 · P1 · L2+L3 · Route detail: fixed 280 px map leaves a letterbox for content `route_detail_view_v2.dart:79, 218-243`**
Now: map hero is fixed (`_mapH 280 + top`), the content ListView starts at mapH−24 and clips under it; with the 2-row dock (~140 px) the scrolling window is ≈ 330 px at 360×780 and ≈ 240 px at 320×690 (fr render: only the title + 2 stats visible). The "Zobrazit na mapě" pill overlaps POI pins.
Proposal (V22 §2.4 TrasaDetail "Map hero + dark stats card overlapping · Sheet canvas"): the content becomes a **sheet over the map**: DraggableScrollableSheet-style with snaps at peek (= mapH−24 from top, as today) and expanded (top + 64, under a 44 back disc that stays pinned, map dimmed to night@.2); grabber 42×5 on the dark card's top edge; drag/fling between snaps `MgMotion.sheet` 300 easeOutCubic; the inner list scrolls only when expanded; dragging down at scroll offset 0 collapses; map stays interactive above the sheet. Reduced motion: snaps jump. Ride detail (`ride_detail_view_v2.dart`, map 260) uses the same primitive.
Why: at 320 px the customer sees the map and the CTA but not WHAT the route is (km, time, difficulty, places) — first-glance hierarchy fails. Risk: gesture conflict map pan vs sheet drag → the sheet owns only its own area; tests with tester.drag on sheet + on map. Shared: **"map sheet" (MgMapSheet: fixed map + draggable content sheet, 2 snaps, pinned back)**.

**F-10 · P1 · LC · Trip card / trip detail / merge reached from Reservation detail `ride_booking_section.dart:36-70`, `ride_trip_card.dart:33-41`**
Now: in Rezervace detail (v2) the "Jízdy z výpůjčky" block uses the old header ("🏍️ JÍZDY…" 10 px g400), old `RideTripCard` (no V-seam) → old `RideTripDetailScreen` + old `RideMergeScreen` + old trip dialogs; ride cards inside are v2 (`RideCard` seam).
Proposal: seam `RideTripCard.build` → `RideTripCardV2` (exists) and its taps → `openTripDetailV2` / `openRideMergeV2` (exist, same `leaderId` / `preselectRideId`); section head → `RtSectionV2(icon: bike, title: rideBookingSection)` + total line 14/700 `#2C4A3A`. (File belongs to routes; the res package only hosts the call.)
Why: a rental's multi-day trip is the most valuable diary entry and it opens in the old look. Risk: none. Shared: none.

**F-11 · P1 · LC · "Odesláno" success sheet `submit_common.dart:262`**
Now: old white sheet with a big tick and old button after every community submit.
Proposal (board TrasaDetail "Odesláno (dialog)", V21 T19, Stavy ✓ tone): v2 branch → T2/T6 success: ✓ tone disc 56 (check-draw 300 + pop + one ring 700, reduced = static), "Díky! Návrh odeslán" 20/800, "Po schválení se objeví v aplikaci všem jezdcům." 14/600, `MgBtnInk` "Hotovo" (same pop). Same return.
Why: contribution = recognition moment ("král" helps the community). Risk: none. Shared: `MgToneDisc(MgTone.ok)` (exists).

**F-12 · P1 · LC · Fullscreen route map + "Otevřít v jiné aplikaci" `route_detail_screen.dart:661-760`**
Now: both old (map page `MotoGoColors.bg`, white 42 box + Material close; export sheet old typography/buttons).
Proposal: map page → `MgStatusBar` + RouteMapView full + ✕ `MgV2Back(style: photo)` at (16, top+8) + recenter `MapRoundV2`; export sheet → `RtSheetV2` "Otevřít v jiné aplikaci" with 3 `MgRow` targets (44 icon tiles light: Mapy.com / Google Maps / Apple Maps) + chevron; "Trasa nemá dostatek bodů" → T3 warn banner in the sheet (16.28 copy) instead of a snack.
Why: these are the last steps before the customer rides. Risk: none. Shared: none.

**F-13 · P1 · LC · Mapa tras point panel `routes_map_picker.dart:46-300`, `routes_map_screen.dart:340-400`**
Now: old route cards (g100 bg, greenPale "Detail ›" pill with Material chevron), mini buttons with Material icons, hint in `#8AAB99` (banned meta).
Proposal (board TrasyHub "Mapa tras"): white sheet r22 "Trasy přes vybraný bod · 3" 17/800 + meta "Klepni na trasu, kterou pojedeš"; horizontal cards 240 w white r16 line, 4 px left bar in the route's map colour, name 15/800 2 lines, "66 km · 1 h 34 min · Lehká" 12.5/700 `#55705F`, `MgBtnText` "Detail ›"; header chips row (Další trasa / + ostatní místa / Klepni na bod = trasa) as `TrasyToolChipV2` dark glass with `MgIcons`. Cards snap (PageScrollPhysics-like `itemExtent` snapping, peek 24 px of the next card).
Why: the map is how riders pick a route visually. Risk: none. Shared: none.

### P2
**F-14 · P2 · L0+L5 · Trasy hub header on every segment `trasy_hub_header_v2.dart:68-130`, `routes_screen.dart:488-503`, `moje_view_v2.dart:174-182`**
Now: title + animated route icon only; no LogoRow (logo ring + level badge) and no stats under the title; Trasy and Moje segments show a back disc (they are pushed routes) while Místa does not → the same header changes shape between segments. Board: identical header on all 3 segments: logo ring with level badge "3" + "Trasy" + "↝ 1 100+ · ⌖ 49 000+".
Proposal: add the compact LogoRow (40 px ring + level badge; existing home `_LogoRow` → promote to core/v2 as `MgLogoRing` with tap → `/loyalty`, the existing action) and the 2 stat bits (moved from the band) to `TrasyHubHeaderV2`; on Trasy / Moje entered by a segment tap hide the ‹ disc (the segment control is the way back; system back / iOS edge swipe = pop, unchanged); keep the disc when the page was entered from elsewhere (deep link, Home "Všechny trasy" → origin chip already handles it).
Why: rank visible on every tab header = recognition; a stable header makes the three segments feel like one place. Risk: R6 "always a visible back" — segments are tab-root faces (V22 §6.2 tab root = no control), system back unchanged. Shared: **MgLogoRing** (promote from home).

**F-15 · P2 · L1 · Moje sub-tabs swipe: no visible follow `moje_view_v2.dart:211-222`, `moje_tabs_v2.dart:52`, `moje_lists_v2.dart:62-70`**
Now: horizontal swipe switches Jízdy ↔ Uložené ↔ Místa ↔ Historie (good), but content just fades in (MgEnter), the chip row does not scroll to the selected chip ("Historie navigace" stays off-screen at 360), no direction.
Proposal: (a) on change `Scrollable.ensureVisible(selectedChipKey, alignment: .5, duration: MgMotion.tab, curve: MgMotion.emphasized)`; (b) content switch via the shared directional switcher (F-08) with the swipe direction; (c) the selected chip uses the board's tab-chip look (dark `#0E2A1C` pill, white label, neon count) — F-16.
Why: the customer must see where the swipe took him. Risk: none (same `_select`). Shared: MgSwipeSwitcher (F-08).

**F-16 · P2 · L0 · Moje chips + filter segments style `moje_tabs_v2.dart:57`, `moje_lists_v2.dart:126-133`**
Now: sub-tab chips use `MgFilterChip` selected = tintOk mint; ride filter = light `MgSegmented` with the count on a second line. Board: sub-tabs selected = dark pill + neon count badge (navigation, not a filter); filter "Vše 7 · S MotoGo 3 · Soukromé 4" = segmented with dark thumb and inline neon count.
Proposal: `MgFilterChip(variant: tab)` (dark selected) for sub-tabs; `MgSegmented(inlineSub: true, darkThumb: true)` for the ride filter (single line, 40 h).
Why: tabs vs filters read differently (clarity); denser first screen. Risk: none. Shared: **MgFilterChip tab variant, MgSegmented inline-count/dark-thumb option** (additive).

**F-17 · P2 · L0+L5 · Moje summary card `moje_summary_v2.dart:95-120, 238-288`**
Now: counts as wrapped pills (2 rows); rank row = rank-gradient-filled disc + "Level 3 z 20 · sleva 3 %", no progress. Board / V22 §2.4 Zazitky: 3 equal square tiles (`well`, icon tile, value 22/900, label) in one row (each = sub-tab jump, existing `onSub`); rank row = dark mini disc with rank ring + ink name "Motorkář · Level 3 / 20" + "Ještě 1 b. do: Stálý jezdec (4 %)" + step bar.
Proposal: `Row` of 3 `MgStatTile` (existing) ≥ 96 w, labels wrap at words (2 lines); rank row from the promoted home `ClubEmblem` + `ClubTierBar` + `RankCopy.nextLine` (§1.4 rank on light = dark disc + ring). Count-up of the 3 values + km once per session (V21 §2.5, 700 ms, reduced = final).
Why: the summary is the "Sultan diary" hero; progress to the next rank motivates the next booking. Risk: de/fr word length → 2-line labels + MgWordFit. Shared: **count-up (MgCountUp)**; promote **ClubEmblem / ClubTierBar** to core/v2/rank.

**F-18 · P2 · L2 · Loading skeletons don't match the final layout `routes_list_parts_v2.dart:50` (PlacesLoadingV2 on Trasy), `moje_lists_v2.dart:76-80`, `moje_view_v2.dart:203` (counts "0" while loading)**
Now: Trasy loading shows place-row skeletons (thumb-left) though cards are photo-top 16:9; Moje rides skeletons are image-top while ride cards are thumb-left; Moje summary shows "0 Jízdy" during loading. Board (stavDat Načítání): photo-top skeleton cards on Trasy, thumb-left rows on Moje.
Proposal: `MgSkeletonCard(imageHeight: 180)` ×2 for Trasy; `MgSkeletonRow(thumb: 72)` ×3 for Moje rides; summary counts "—" (as saved/places already do) while `rides.isLoading && !hasValue`; cross-fade skeleton → content `MgMotion.color` 180.
Why: no layout jump, no false "0 rides". Risk: none. Shared: **MgSkeletonRow** (if missing).

**F-19 · P2 · L2 · Route detail loading `route_detail_screen.dart:107`**
Now: spinner on a blank page under a dark band. Board: map placeholder + dark card skeleton (title bar + 4 stat tiles) + section skeletons.
Proposal: v2 loading view = `RouteDetailSkeletonV2` with the exact geometry of the final screen (map 280 well-grey, card r20 night with 4 white@.06 tiles), shimmer `MgMotion.shimmerLoop` (one loop), reduced = static.
Why: perceived speed. Risk: none. Shared: MgSkeleton (exists).

**F-20 · P2 · L4 · Route sketch draw + POI pins pop (V21 §2.5) — route cards `route_card_v2.dart` sketch inset, route detail map, builder**
Now: static. Spec: sketch draws once 900 ms on cards (first 6 in view, session-keyed like MgReveal), 1 600 ms in the detail; pins pop with 70 ms stagger; reduced = static.
Proposal: `MgPathDraw(progress)` painter wrapper (PathMetric extract) for the card sketch and the detail polyline overlay (draw the PolylineLayer points up to t; run once per `sessionKey 'route-{id}'`), MgPop on markers with index × 70 ms.
Why: signature motion of the Trasy board — the route "comes alive". Risk: perf on long polylines → precompute cumulative lengths once; RepaintBoundary. Shared: **MgPathDraw**.

**F-21 · P2 · L2 · Number formatting `ride_card.dart:232` (`rideKm` "1.2 km"), `ride_stats_v2.dart:43` ("1240 m"), `route_card_v2.dart:102` + `route_detail_parts_v2.dart:138` ("4.7 (3)"), `route_builder_screen.dart:429` ("13.6 km"), `moje_cards_v2.dart:63`**
Now: decimal point and no thousands space in cs/de/fr/… (board: "38,2 km", "1 240 m", "4,7").
Proposal: v2 views format with the existing locale helper (`rideLiveKm(km, lang)` / `rtThousands`) or `NumberFormat.decimalPattern(lang)` (intl allowed) — display only, old look untouched.
Why: wrong decimals look foreign/cheap. Risk: none (values unchanged). Shared: **mgNum(value, lang, digits)** helper in core/v2.

**F-22 · P2 · L3 · Stop confirm `ride_pause_actions_v2.dart:50-60`**
Now: "Ukončit záznam? · Jízdu uložíme do Moje zážitky. Jízdy kratší než 1 km neukládáme." · [Ukončit a uložit] above [Pokračovat v jízdě].
Proposal (§4.4 #13): add the ride summary line "38,2 km · 1 h 12 min v sedle" (existing `recLiveBitsV2`) 17/800 ink tabular above the body; order per T6: safe "Pokračovat v jízdě" first/left (ghost), "Ukončit a uložit" (ink) second.
Why: the rider confirms what he is saving; safe action first reduces glove mis-taps. Risk: none. Shared: none.

**F-23 · P2 · L3 · Live bar stop label `rec_live_bar_v2.dart:41-42`**
Now: at 360 dp (cs, scale 1.0) the stop is a 44 px white square with only ■ (label only ≥ 300 dp bar or when stacked at 320) — inconsistent with 320 and the board ("■ Ukončit").
Proposal: keep the label whenever `avail` after a 96 px labelled button ≥ 100 px; otherwise stack (as 320). Pause disc stays icon-only (semantics label).
Why: "Ukončit" must be readable — the destructive action should never be a mystery square. Risk: layout at 412/de; test matrix. Shared: none.

**F-24 · P2 · L1 · Place sheet ‹ › arrows `poi_sheet_v2.dart:16-80`, swipe `route_poi_sheet.dart:136-148`**
Now: counter "1 / 5" + ✕, swipe works (slide), but no visible arrows. Board: "1 / 12" + ‹ › 44 white discs + ✕.
Proposal: `PoiSheetHeadV2` gets prev/next discs (MgIconButton light, disabled at the ends) calling the existing `_go(∓1)`.
Why: discoverability for non-swipers. Risk: none. Shared: none.

**F-25 · P2 · L5 · Place sheet primary + "Navigovat sem" (V21 T4)**
Now: light sheet bottom = ink "Přidat do mé cesty" / ghost "Odebrat z mé cesty". Board: rank CTA in a dark dock inside the sheet ("NAVIGOVAT SEM" on Moje, "PŘIDAT DO MÉ CESTY" on Místa).
Proposal: wrap the trip button in a `MgDock(light:false)` with `MgCta(compact)` when not selected; selected state = `MgBtnGhostLight` "✓ Odebrat z mé cesty". "Navigovat sem" secondary → owner decision OD-05 (new action on that screen).
Why: one obvious next step per sheet. Risk: none. Shared: none.

**F-26 · P2 · L3+L2 · Ride detail stats 2 columns at 360 `ride_stats_v2.dart:187-200`**
Now: 3 columns only when the longest single-line label fits → cs 360 falls to 2 columns (9–12 tiles = 5–6 rows, > 1 screen). Board: 3×3.
Proposal: allow labels to wrap at word boundaries (2 lines, `MgWordFit` per word) and decide 3 columns by the longest WORD, not the whole label; 2 columns only at 320 or text scale ≥ 1.3.
Why: the stats card is the one dark hero; 3 columns keep it glanceable. Risk: fit tests. Shared: none.

**F-27 · P2 · L3 · Planner stop rows show raw coordinates `route_builder_screen.dart:635, 671`**
Now: "Klášter Rajhrad / 49.0906, 16.6100". Board TrasaDetail note #1 + V21 T12 "raw coordinates hidden": row = name + "Zastávka N".
Proposal: v2 tile sub-line = "Zastávka N" (i18n, existing `rideStop`-like key or new) when the stop has a name; unnamed tap-stops keep the coordinates until reverse geocoding is decided (OD-06).
Why: coordinates are noise for a customer. Risk: none. Shared: none.

**F-28 · P2 · L3 · Planner dock icon-only Uložit / Navrhnout `builder_parts_v2.dart:336-338`**
Now: two 48 px icon-only ghost buttons (bookmark, send). V21 T12: "🔖 and ✉ as 48 ghost icon buttons with labels".
Proposal: icon 20 above a 10.5/800 label ("Uložit", "Navrhnout"; fit 8 langs, MgWordFit), tile 56 × 56.
Why: unlabeled icons on a decision dock = guessing. Risk: dock width at 320 → CTA ≥ 160. Shared: none.

**F-29 · P2 · L1+L4 · Segment switching Místa ↔ Trasy ↔ Moje `trasy_hub_header_v2.dart:21-32`, `router.dart:520-524 (_swipeBackPage)`, `moje_view_v2.dart:150-155`**
Now: three different transitions for one control: Místa→Trasy Android = no transition / iOS = push slide; Trasy→Moje = full page push (own nav bar slides in); Moje→Místa/Trasy = `go` (instant). The thumb animates (spring) but the page jumps.
Proposal (no routing change): give `/routes-list` and the segment push to `/my-experiences` a **shared-axis horizontal transition** (CustomTransitionPage: incoming slides 0.15 from the side of the tapped segment + fade, outgoing −0.05 + fade, `MgMotion.tab` 210 ms emphasized; reduced = none) on both platforms; keep iOS edge-back on the pushed pages (CupertinoRoute-compatible transition) — and add a horizontal **fling** (|v| ≥ 600 px/s, outside maps / horizontal lists / the Moje content which already uses swipes for sub-tabs) on the Místa and Trasy list bodies that calls the existing `trasyGoSegment(from, next)`.
Why: the hub must feel like one surface. Risk: gesture conflicts → exclude map preview, chip rails and cards' horizontal lists (only vertical scroll areas); iOS back-swipe must still pop (test). True finger-following segments need one hub route → OD-01. Shared: **"segment transition page" (MgSharedAxisPage)** + **swipeable segments helper**.

**F-30 · P2 · L0 · AI disc missing on focused screens (V22 §6.4) `recorder_screen_v2.dart:121-143`, `builder_parts_v2.dart:20-75`, Mapa míst / Mapa tras headers, ride detail header**
Now: no AI disc on recorder, planner, both maps, ride detail (board shows a 44 disc as the last item of the top bar on all of them).
Proposal: `MgAiDisc(size: 44)` as the last top-bar item (dark style on dark bars; existing AI action).
Why: concierge always one tap away ("král"). Risk: crowding at 320 → title MgWordFit 2 lines. Shared: none.

**F-31 · P2 · L5 · Trasy stats band honesty `routes_screen.dart:332-342, 500-501`**
Now: "1 370+ tras · 37 000+ míst" from hard floors even when live data has 1 174 (V21 T2 "truth fix: floored live counts, never a hard-coded floor"); board shows "1 100+ · 49 000+ · 38 zemí".
Proposal: v2 band computes `floorCount(n)` from the live counts (< 10 000 → hundreds, ≥ 10 000 → thousands, "+"); third tile "zemí" = distinct countries of the loaded routes (display of existing data).
Why: "nothing fake". Risk: none (old look untouched). Shared: none.

**F-32 · P2 · L2 · Moje list builds every card at once `moje_lists_v2.dart:62-70`**
Now: one `SliverList.list` child = a Column with ALL ride/trip/place cards (each with a CustomPaint sketch) → no laziness; 100+ rides = jank on open and on every sub-tab switch.
Proposal: emit each card as its own sliver child (`SliverList.builder` over the item list; headers as separate items); keep MgReveal per index ≤ 6.
Why: smooth scroll on the diary of a loyal (= heavy) customer. Risk: none (layout only). Shared: none.

**F-33 · P2 · L3 · Moje rides list month headers (board)**
Now: flat list. Board: "ŘÍJEN 2026 · 🏍 1 · 96 km" group heads (12/800 caps `#55705F`, right meta).
Proposal: insert month section heads computed from `startedAt` of the shown items (display only).
Why: orientation in a long diary. Risk: none. Shared: none.

### P3
- **F-34 · P3 · L4** Loop budget: `AnimatedRouteIcon` repeats forever (`animated_route_icon.dart:58`) next to the dock CTA loop (+ ping while recording) → run it once per session (or only when no CTA loop), static under reduced motion (V21 §2.5 "loops: primary CTA + one live indicator").
- **F-35 · P3 · L4** Image fade 200 ms is not reduced-motion aware (`route_image.dart:118,132`) → `MgMotion.of(context, MgMotion.color)`; default placeholder `MotoGoColors.greenPale` → v2 `MgColors.well` when MgV2.on.
- **F-36 · P3 · L5** Haptics at key moments (recording started = `mediumImpact`, saved success = `lightImpact` with the ✓ pop); everything else keeps MgPress selectionClick.
- **F-37 · P3 · L0** Share sheet tiles use Material icons; V21 T15 asks for official brand glyphs (WhatsApp, Facebook, X, Telegram) as `MgIcons` paths.
- **F-38 · P3 · L0** Moje "Objevená místa": board's "Na mapě · 12 míst ›" shortcut row + visit-count badge "2×" on the photo; history progress bar fill `#37CF63` (verify fill shows on well).
- **F-39 · P3 · L3** Recorder stop confirm as a light bottom sheet (§4.4 #13 "Confirm sheet") instead of a centred dialog — thumb reach with gloves.
- **F-40 · P3 · L0** Planner header eyebrow "UPRAVIT TRASU" when opened from an existing route (board), "PLÁNOVAČ TRASY" for a new one; segmented profile with dark thumb (board).
- **F-41 · P3 · L4** Route detail board hero toggle "Mapa | Fotky n" (board "fotky v záhlaví"): swap the hero between the map and a photo pager of `route.images` (existing data + viewer) — fidelity item, low priority because the gallery exists below.

## Owner decisions (beyond the approved design or functional)
- **OD-01** One in-shell Trasy hub route with a PageView (Místa · Trasy · Moje) so the segment thumb follows the finger — changes routing/back stack (today 3 routes; Moje outside the shell).
- **OD-02** "Půjč si motorku na tuhle trasu" dark CTA card in route detail (board shows it marked "návrh"; V21 T9 optional; spec §2.4 lists it) → strongest conversion hook of the Trasy tab; needs the owner's yes and the target (Motorky filtered by the branch nearest the start).
- **OD-03** Live trace map card on the recorder (board §4.2 D) — needs live track points exposed by the recorder state (new data path).
- **OD-04** Ride detail "Rezervace #[ID] ›" link for MotoGo rides (V21 T14 optional) — new navigation entry.
- **OD-05** "Navigovat sem" secondary in the Místa place sheet (V21 T4) — new action on that screen.
- **OD-06** Reverse-geocoded names for unnamed planner stops (V21 T12; new Mapy.com call in the planner).
- **OD-07** "ZOBRAZIT JÍZDU" in the saved sheet (§4.4 #14) — needs the saved ride id after `stop()`.
- **OD-08** Navigation "● REC" chip exists; the board's AI disc in the navigation top bar (V22 §6.4 lists navigation) vs V21 T11 "No AI FAB" — conflicting specs, owner picks.

## Already excellent (keep)
- Record dock: one dock with priority live → selection → idle, AI docked, idle↔live 300 ms cross-fade, red only while live, fits 8 languages at 320 (`record_dock_v2.dart`, `rec_live_bar_v2.dart`).
- Recorder phases after the 2026-10-22 decisions: armed / riding / auto-pause / manual pause / guards with one honest sentence each, "Jak funguje automatická pauza?" disclosure, confirm-before-stop, rental cannot be stopped by mistake, GPS-lost banner with a working action.
- Moje: white summary + split bar (R5), Tvoje stopy as the one dark hero, live recording card with red border, sub-tab swipe, empty / locked / error states with real next steps, trip cards + merge + multi-day stats, trip error banner.
- Route detail stats card with sibling pager, "Více" disclosure, dock ZVOLIT TRASU – NAVIGOVAT with ghost links; place sheet frame with sibling swipe + slide and drag snap 50–97 %.
- Místa: map preview card, category chips with well counts, selection mode "VLASTNÍ VYJÍŽĎKA (n)" + ✕ + ⏺ disc (§4.2 ②), location prompt, routes banner.
- Image pipeline (`RouteImage`: Wikimedia thumbs, headers, memCacheWidth, precache), MgReveal session keys (no replay), MgWordFit everywhere (no mid-word breaks in the 8-language renders), byte-identical iOS parity.

## Shared core/v2 primitives needed by this area
MgPhotoViewer (F-03) · MgMapSheet (F-09) · MgSwipeSwitcher / directional content switch (F-08, F-15) · MgSharedAxisPage + swipeable segments helper (F-29) · MgCta `leadingIcon` (F-05) · MgCountUp (F-17) · MgPathDraw (F-20) · mgNum locale number helper (F-21) · MgFilterChip tab variant + MgSegmented inline-count/dark-thumb (F-16) · MgLogoRing + ClubEmblem/ClubTierBar promoted to core/v2/rank (F-14, F-17) · MgSkeletonRow (F-18). Existing and sufficient: MgStateSheetBody + MgToneDisc (F-06, F-11), MgStatTile, MgDialogFrame, RtSheetV2, MapRoundV2, MgReveal.
