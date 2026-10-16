# understand:trasy — the TRASY tab: complete inventory and a clearer IA

Scope: the Android master tree `Motogo-app-main/motogo-app-flutter/lib`.
- `features/routes/` has 46 files and 22 784 lines.
- The iOS tree is identical apart from `userAgentPackageName`, which differs in 7 map files. This was checked with `diff`.

Texts: the Czech strings are quoted from `core/i18n/translations_ext_11_routes.dart`, `_18_rides.dart`, `_20_routes_map.dart` and `_36_ride_feedback.dart`. A full Czech dump is in `scratchpad/trasy_cs.txt`.

Live data was read anonymously on 2026-10-15. Raw samples:
- `scratchpad/trasy_vn_routes.json`
- `scratchpad/trasy_mezna_routes.json`
- `scratchpad/trasy_vn_pois.json`

Paths below are relative to `lib/features/routes/` unless they say otherwise.

---

## 0. TL;DR

### Key facts

**1. The tab is not "Trasy" today; it is "Místa".**
- The bottom nav label is **TRASY** (`navRoutes`), but `/routes` renders `AllPoisScreen(asTab: true)`, the places catalogue. This was switched on 2026-09-16.
- The route list moved to `/routes-list`.
- Three tiles are pinned under the header:
  - 🗺️ Trasy
  - 🧭 Mapa míst (on Místa) or 🗺️ Mapa tras (on Trasy)
  - 🏍️ Moje zážitky
- The tiles shrink into compact pills as you scroll. A horizontal swipe rotates their order, which is hard to discover.
- On the Trasy list, the first tile is 📍 Místa.

**2. Five places, all one or two taps deep:**

| Place | Path | Inside the shell? |
|---|---|---|
| Místa | `/routes` | yes |
| Trasy | `/routes-list` | yes |
| Mapa míst | `/places-map` | yes |
| Mapa tras | `/routes-map` | yes |
| Moje zážitky | `/my-experiences` | **no, the bottom nav disappears** |

Fullscreen flows outside the shell:
- `/routes/:id` (route detail; this one is in the shell)
- `/route-nav/:id` and `/route-nav-custom` (navigation)
- `/route-build` (route builder)
- `/pois` (pick mode)
- `/ride/:id` (ride detail)
- `RouteSubmitScreen` and `PoiSubmitScreen` (`MaterialPageRoute`)

**3. Naming in Moje zážitky is confusing. This is the biggest UX problem.** Its three tabs are:

| Tab | What it holds |
|---|---|
| 🗺️ **Vytvořené trasy** | The "Vytvořit novou trasu" CTA, plus the **ride recording toggle** ("🛰️ Záznam jízdy"), plus "Zaznamenat vlastní jízdu", plus **every recorded ride (`user_rides`)**, plus the saved routes (`user_saved_routes`) |
| 📍 **Moje místa** | Places discovered during navigation (`user_visited_places`) |
| 🕘 **Moje trasy** | The **local navigation history** (`activeRideProvider`, SharedPreferences, max 30), with "Pokračovat v trase" and "Jet znovu" |

So the label "Moje trasy" points at the navigation history, rides are hidden under "Vytvořené trasy", and the header stats count only places and routes, not rides or km.

**4. The owner's "my rides with MotoGo" and "my private rides" already exist as data.** `UserRide.bookingId != null` means a ride recorded automatically during a rental; `null` means a manual recording on the customer's own bike. The UI never separates them. The only place that splits them is reservation detail ("🏍️ PROJETÉ JÍZDY" per booking).

**5. "+" menu.**
- It is a FAB at the **bottom-right**, on the Trasy list only. Items:
  - "Zaznamenat vlastní jízdu" / "Ukončit záznam jízdy"
  - "Navrhnout trasu"
  - "Přidat místo"
- Places can also be added by long-pressing the map, or with the 📍+ button on Mapa míst.
- **This collides with the planned AI FAB at bottom-right.** The "+" has to move into the header.

**6. Live data.**
- 1 174 approved routes, all `route_type=loop` in the samples, `geometry` NULL on all of them.
- About 49 926 catalogue POIs and 8 456 `route_pois`.
- 0 approved community POIs.
- 2 route reviews (5★, "Fajn vyjížďka.🤘").

**7. Truth bugs worth fixing in the redesign:**
- The Trasy header claims "Přes **1 370** tras a 49 000 zajímavých míst 🏍️". `_fmtCount(routeCount, floor 1370)` hard-codes a minimum that is **above** the live 1 174. The web says "1 000+ tras s navigací · 50 000 zajímavých míst".
- The route card prints the route's `branch_id` name ("🏁 MotoGo24 Mezná") on all 384 routes that have a `branch_id`, all of which are Mezná. That includes routes around Brno ("Rajhrad a Židlochovicko") and abroad ("Algarve – hory Monchique a Silves"). Route detail already guards this with `startIsNearRoute`; the card does not.

### Proposed IA (details in §7)

- **TRASY** gets one root with a dark collapsing header:
  - title
  - shared search
  - a segmented control **📍 Místa · 🛣️ Trasy · 🏍️ Moje** (web `.km-sw` style, sliding neon thumb with a rank-coloured glow)
  - a map icon that is aware of the segment
  - a "+" action
- **Live strip** above the content, shown only when relevant:
  - "🧭 Pokračovat v trase · {název} ✕"
  - "⏺ Nahrávám jízdu"
- **Moje** becomes a segment, so the nav stays. It is reorganised into:
  - a hero with stats (rank accent)
  - two CTAs
  - sub-chips **Jízdy (Vše · S MotoGo · Soukromé) · Uložené trasy · Objevená místa · Rozjeté navigace**
- Every current function is kept. The mapping is in §8.

---

## 1. Navigation map today

### 1.1 Routes (`core/router.dart`)

| Path | Screen | Shell / bottom nav | Notes |
|---|---|---|---|
| `/routes` | `AllPoisScreen(asTab:true)` ("Místa") | yes, `NoTransitionPage` | Root of the 4th tab |
| `/routes-list` | `RoutesScreen` ("Trasy") | yes, `NoTransitionPage` | Secondary |
| `/places-map` | `PlacesMapScreen` | yes | Fullscreen map, but nav visible |
| `/routes-map` | `RoutesMapScreen` | yes | Fullscreen map, but nav visible |
| `/routes/:id` | `RouteDetailScreen(siblingIds via extra)` | yes | Swipe between siblings |
| `/route-nav/:id` | `RouteNavigationScreen` | **no** | Fullscreen navigator |
| `/route-nav-custom` | `RouteNavigationScreen.custom(CustomNavArgs or RouteItem)` | **no** | Custom route |
| `/route-build` | `RouteBuilderScreen(RouteItem or RouteBuilderArgs)` | **no** | Editor |
| `/pois` | `AllPoisScreen(initialSelected)` | **no** | Legacy, not opened from the UI. The builder pushes `AllPoisScreen(pickMode:true)` through `MaterialPageRoute` |
| `/my-experiences` | `MyExperiencesScreen` | **no** | The nav disappears |
| `/ride/:id` | `RideDetailScreen(siblingIds)` | **no** | |
| (push) | `RouteSubmitScreen`, `PoiSubmitScreen` | **no** | `MaterialPageRoute` from the add menu or a map long-press |

**Tab highlight (`core/app_shell.dart:39`):** `/routes*`, `/places-map`, `/pois` select tab 3. `/my-experiences` and `/ride/*` are outside the shell, so there is no nav at all.

### 1.2 Entry points from outside the tab

| From | Destination |
|---|---|
| Home (`home_screen.dart:44`) | Nothing visible. It only prefetches `routesDataProvider` and `catalogPoisProvider` |
| Reservation detail | `BookingRidesSection` ("🏍️ PROJETÉ JÍZDY" + `RideCard`s) → `/ride/:id` (`reservations/widgets/res_detail_tab_content.dart`) |
| Global shell: route FAB | "🧭 Pokračovat v trase · {name}" + red ✕ (`app_shell.dart:654`). Visible on every shell screen while navigation is running; hidden on payment, login, register, docScan, success. Tap → `openRide` → `/route-nav/:id` or `/route-nav-custom`. ✕ → `endRide()` |
| Global watcher | `RideRecorderWatcher` (`main.dart:401`) starts automatic recording during a running rental. Android shows a persistent notification: "MotoGo24 zaznamenává jízdu" / "Trasa se ukládá do Mých zážitků. Vypnout jde v appce." |
| Completed reservation | `res_rating_card.dart` ("Jak se ti jelo?" → "Napiš nám recenzi" / "Napiš nám přímo, co máme zlepšit"). Lives in Reservations, not in Trasy |

### 1.3 Back fallbacks (`backOr`)

| Screen | Back goes to |
|---|---|
| Místa (non-tab) | `/routes` |
| Trasy | `/routes`, only when it can pop |
| Route detail | `/routes` |
| Navigation | `/routes/{id}` or `/routes` |
| Builder | `/routes` |
| Moje zážitky | `/routes` |
| Ride detail | `/my-experiences` |
| Mapa míst | `/routes` |
| Mapa tras | `/routes-list` |

Mapa míst ⇄ Mapa tras switch with `pushReplacement`.

---

## 2. Screen-by-screen inventory

### 2.1 MÍSTA: `AllPoisScreen(asTab:true)` at `/routes` (`all_pois_screen.dart`, 2 016 lines)

Layout, top to bottom (a `CustomScrollView` of slivers):

**1. Collapsing header** (`collapsing_header.dart`). Pinned; the subtitle and search collapse on scroll.
- Leading "📍".
- Title "Místa" (`poiBrowseAll`).
- Subtitle "Objevuj zajímavá místa a sestav si z nich vlastní vyjížďku" (`poiBrowseSub`).
- Search pill "Hledat místo…" (`poiSearch`):
  - 280 ms debounce.
  - ✕ clear.
  - **The query is shared with Trasy** (`placesSearchProvider`).
- When collapsed, a 🔍 appears in the title row; tapping it scrolls to the top.
- No back button while in tab mode.

**2. Quick links** (`routes_quick_links.dart`, pinned).
- Three tiles:

  | Tile | Subtitle | Opens |
  |---|---|---|
  | 🗺️ "Trasy" | "Hotové vyjížďky od zkušených motorkářů" | `/routes-list` |
  | 🧭 "Mapa míst" | "Prohlédni si všechna místa na mapě" | `/places-map` |
  | 🏍️ "Moje zážitky" (dark tile) | "Tvoje uložené trasy a objevená místa" | `/my-experiences` |

- They morph from full cards (emoji, title, subtitle, arrow) into compact pills as you scroll.
- A horizontal swipe cycles their order with a 420 ms animation.

**3. Location prompt.** Shown only without a location fix. Green-pale card:
- Text "Zapni polohu a seřadíme místa od nejbližších" (`poiLocationPrompt`).
- Button "POVOLIT" → `ensureLocation`.
- On open, `requestLocationQuietly` is called; it never opens the system settings.

**4. Map preview, 160 px** (`PlacesMapView`). It shows exactly the filtered places.
- Gestures:
  - Tap a place → toggle its selection.
  - Long-press or double-tap a place → place detail.
  - Tap empty map → `/places-map`.
  - Long-press empty map → `PoiSubmitScreen(initialPoint)`.
  - Drag is disabled.
- Top-right white ⤢ button → `/places-map`.
- From 2 selected places, the on-road route through them is drawn (`selectionRoadRouteProvider`).
- Hint below: "Klepni na mapu pro zvětšení · podrž místo pro detail" (`placesMapOpenHint`).

**5. Filter row**, collapsed by default.
- Chip "⚙ Filtry a řazení" / "Skrýt filtry" with a count badge, plus a red "✕ Zrušit" when anything is active.
- Expanding it (`AnimatedSize` 220 ms) shows:
  - a horizontal row:
    - "↕ Od mé polohy / Od zvolené trasy / Náhodně" → tools sheet
    - "📡 V okolí 25 km" toggle; when on, 5 / 10 / 25 / 50 km chips
    - "🛣 Trasa ▾" → route picker sheet
  - a Wrap of **category chips with counts**: 🍽️ Jídlo a pití · 🏰 Hrady a zámky · 🗼 Rozhledny a vrcholy · 🌊 Voda · ⛲ Studánky a prameny · ⛪ Památky · 🌳 Příroda · 🪖 Vojenství · ✈️ Letectví · 🏭 Technika · 🏁 Motorismus · 📍 Ostatní
- Scrolling more than 140 px down collapses the panel again.

**6. "Našli jsme i trasy · {n}" banner.** Shown when the query also matches routes; tap → `/routes-list`.

**7. Place list.** Cards, white, r16, 84 px thumbnail.
- Name.
- Second line:
  - for a catalogue place: category emoji + category label
  - for a route POI: 🛣 + route name
  - for a community place: 👥 "Komunitní místo"
- Rating "★ 4.5 (12)".
- Distance "↗ 12.4 km · 15m". This is the straight-line distance × 1.3 at 60 km/h.
- Right: a ⊕ / ✓ circle that adds the place to, or removes it from, the custom ride.
- Tap the card → detail. Long-press → add or remove.
- Thumbnails are precached (first 18).
- **Default sort:** by distance from my position; without a location, a stable random order (seed per app run).
- Near-duplicate places across routes and the catalogue are merged (`dedupPlaces`) unless a single route is filtered.

**8. Selection bar** (`bottomSheet`, sticky) once at least one place is selected:
- "{n} vybráno ✕" clears the selection.
- Green "🧭 Pokračovat" → `buildCustomRoute` in tap order → `/route-build`.

**9. States:**
- Spinner until the catalogue and community sources are loaded.
- Empty: "🗺️ Zatím žádná místa" (`poiEmpty`).

Sheets on this screen:

- **Tools sheet** "Řadit a filtrovat" (`poiToolsTitle`):
  - Header link "✕ Zrušit".
  - Search.
  - **Řadit**: Od mé polohy · Od zvolené trasy (enabled only after a route has been opened) · Náhodně.
  - **Kategorie** chips.
  - **Země**: CZ / SK / AT / HU / IT / HR / SI flags first, then "▼ Další státy ({n})", which expands to full names.
  - "▼ Minimální hodnocení" (collapsed): Vše · ★3+ · ★4+ · ★4.5+.
  - Sticky button "Zobrazit ({live count})".
- **Route picker sheet** "Vyber trasu" (`poiRoutePickTitle`):
  - Search "Hledat trasu…" searches the name, towns on the way and POIs.
  - "Všechny trasy {count}", then every route with POIs, with a count badge and ✓ on the active one.
  - The list is lazy (`ListView.builder`).

**Pick mode** (`AllPoisScreen(pickMode:true)` from the builder's "Přidat z bodů zájmu"):
- The same screen without the quick links, location prompt or map preview.
- It has a back arrow and a local filter.
- The bottom button reads "+ Přidat do trasy" (`poiAddToRoute`) and returns the selected POIs.

### 2.2 Place detail sheet: `showRoutePoiSheet` (`route_poi_sheet.dart`)

A `DraggableScrollableSheet`: 85 % initially, between 50 % and 97 %.

- **Swipe sideways** between siblings. That is the filtered list, the route's POIs, or "Moje místa". A slide + fade transition (220 ms) is used, and a "3 / 12" counter sits top-left.
- 250 px hero photo with a ⤢ hint; tap → fullscreen viewer.
- Thumbnail strip (66×96) for the rest of the gallery.
- Number badge (a route stop only).
- Name: H1 / 900.
- Category pill (emoji + label).
- Spinner while the full detail is fetched: `get_poi_detail` for catalogue places, `get_route_poi_detail` for route POIs.
- **Description**: full text.
- **Okolí** (`poiSurroundings`): an AI-generated surroundings text.
- Divider, then the **star rating bar** `PoiRatingBar`:
  - average + count
  - "Tvé hodnocení" / "Klepni na hvězdy a ohodnoť" / "Zatím bez hodnocení"
  - tap a star → `rate_poi`
  - snackbars: "Hodnocení uloženo ⭐" / "Hodnocení se nepodařilo uložit — zkus to znovu" / "Přihlas se a ohodnoť"
- **Recenze** `PoiReviewsSection`:
  - header "Recenze", "4.5 · 3 recenzí"
  - "Napsat recenzi" / "Upravit recenzi", "Smazat recenzi"
  - empty: "Zatím žádné recenze. Buď první!"
  - Editor: stars (required, "Vyber počet hvězd"), text "Napiš pár slov o trase (volitelně)" (the wording says "trasa" even for a place), "Přidat fotky ({n})", "Odeslat recenzi"
  - Snackbars: "Děkujeme za recenzi!" / "Recenzi se nepodařilo uložit"
  - The author shows as "Tvá recenze" for your own, otherwise the author name or "Motorkář". A hidden review gets a red background (owner only).
- **Sticky "📍+ Přidat do mé cesty" / "✓ Odebrat z mé cesty"**, only where places can be composed: Místa list, Mapa míst, Mapa tras.
- **There is no "Navigovat sem" button in the place detail.** Navigating to a single place is possible only from Moje místa (the 🧭 circle) or through selection → builder → Navigovat.

**Fullscreen image viewer** `openPoiImageViewer`:
- `PageView`, pinch-zoom up to 5×.
- ✕ close.
- "{n} foto" counter.
- An almost invisible ©, bottom-left. It opens a credit sheet: "Fotografie pochází z Wikimedia Commons — autora a licenci najdeš na stránce zdroje." and "Zobrazit zdroj".

### 2.3 MAPA MÍST: `PlacesMapScreen` at `/places-map`

Fullscreen `PlacesMapView`:
- Viewport culling plus grid clustering; a cluster marker shows the count, and tapping it zooms in.
- Same filter and selection as the list.
- Location is requested on open.
- Selected places show as green with ✓.

Dark header:
- ← back.
- 🧭 "Mapa míst".
- Status line, one of:
  - "Načítám místa…"
  - "Míst na mapě · {n}"
  - "Klepni na další místa v pořadí, jak chceš jet"
  - "Počítám trasu po silnici…"
  - "Trasa přes vybraná místa · {km} km · {čas}"
  - "Trasu po silnici se nepodařilo spočítat"
- Active-filter summary chips: „query", CZ / SK, category emojis, 25 km, ★4+, 🗺️, ↕.
- Pill "🛣 Mapa tras" (replaces the screen).
- Filter-off icon (clears the filter and query).

Gestures:
- Tap a place → select it.
- Long-press a place → detail.
- Long-press empty map → `PoiSubmitScreen(initialPoint)`.

Round buttons, right side:
- ◎ "my location" (asks for permission if needed).
- **📍+ "Přidat místo"** (primary). Without a location fix, the snackbar says "Podrž prst na mapě, kam chceš místo přidat".

Selection bar: "{n} vybráno ✕" + "🧭 Pokračovat" → builder.

The draft route from the editor ("Tvoje trasa") is drawn.

### 2.4 TRASY: `RoutesScreen` at `/routes-list` (`routes_screen.dart`, 1 526 lines)

- **Collapsing header:**
  - `AnimatedRouteIcon`: a wavy road with stops; a light dot rides along and pauses 0.5 s at each stop.
  - Title "Trasy".
  - Subtitle "Přes {routes} tras a {pois} zajímavých míst 🏍️" (`routesDiscoverStats`), with the floor bug from §0. The fallback is "Doporučené vyjížďky od našich poboček".
  - Search "Hledat trasu, místo, město…" (`routesSearch`). It searches the name, description, towns on the way and route POIs; it is shared with Místa.
- **Quick links:** 📍 Místa ("Objevuj zajímavá místa…") · 🗺️ Mapa tras ("Body tras na mapě — klepni na bod a ukáže se trasa") · 🏍️ Moje zážitky.
- **Pill row** (horizontal scroll):
  - "⚙ Filtry (n)"
  - "↕ Řadit: Od mé polohy" (default)
  - a light-green "🗺 Mapa tras" pill
  - "✕ Zrušit" when anything is active
- **Filter sheet** "Filtrovat trasy" (`routesFilterTitle`):
  - Header link "✕ Zrušit", which resets and closes the sheet.
  - **Země**: flags first, then "Další státy ({n})". **Shared with Místa.**
  - **Délka (km)**: `RangeSlider` "Délka (km) · 40–249 km".
  - **Čas jízdy**: `RangeSlider` "1h–5h 55m". The two sliders are **linked** through the median speed in the data.
  - Hint "Délka a čas se dopočítávají navzájem (orientačně)."
  - Chip "🏍️ Počítat i cestu od mé polohy". It adds the approach there and back to both ranges.
  - Sticky "Zobrazit ({n})".
  - Type and difficulty filters were **removed on 2026-09-16**; the DB columns stay.
- **Sort sheet:** 🔀 Náhodně · 📏 Délka · 🕑 Čas · ◎ Od mé polohy (disabled without a location) · 🛣 Od zvolené trasy (disabled until a route has been opened).
- **Route card** (`_RouteCard`, `StaggeredReveal` on the first 6 with 60 ms + i×90 ms):
  - 16:9 cover with a gradient, or 🛣️ on pale green.
  - Top-left green pill "🔄 Okruh" / "📍 Za místy".
  - At the bottom of the image: name (H2, white, 2 lines) and "🏁 {branch name}" (the bug from §0).
  - Meta row: 📏 "{km} km", 🕑 "{h} h {m} min", 📍 "{n} míst", ↗ "Od tebe: ~{km} km · ~{čas}", ★ "4.5 (2)" or ☆ "(0)", › arrow.
  - **Tapping the stars opens the reviews sheet without opening the detail.** That sheet can write a review too.
  - Tapping the card → `/routes/{id}` with the sibling ids of the filtered list.
- **FAB "+"** (green, bottom-right) → **add menu** (§2.11).
- Pull to refresh.
- States:
  - Spinner.
  - Error: ☁ "Trasy se nepodařilo načíst" + "Zkusit znovu".
  - Empty: 🗺️ "Zatím žádné trasy" / "Brzy sem přibydou doporučené okruhy a vyjížďky za body zájmu."
  - Filter empty: 🔍 "Žádná trasa neodpovídá filtru" + "Zrušit".

### 2.5 MAPA TRAS: `RoutesMapScreen` at `/routes-map` + `routes_map_picker.dart`

- Only places that lie on a route are drawn, in green. The toggle "+ ostatní místa" / "Jen body tras" shows the rest in white.
- Tapping a point draws **all routes through that point on the road**, each in its own colour, with a name label on the line.
- Bottom panel "Trasy přes vybraný bod · {n}", hint "Klepni na trasu, kterou pojedeš":
  - One horizontal card per route, in the route's colour: name, km, time, difficulty.
  - "Detail ›" opens `/routes/:id`.
  - Tapping a card highlights and fits that route.
- Header:
  - ← back.
  - 🗺️ "Mapa tras".
  - Status "Bodů na trasách · {n}" or "Počítám trasu po silnici…".
  - Pill "🧭 Mapa" (switches to Mapa míst).
  - Mini buttons "⤳ Další trasa" and "+ ostatní místa" / "Jen body tras".
  - Hint "Klepni na bod = trasa".
- Chip "🧭 Tvoje trasa · {km} km ✕": the draft from the editor.
- ◎ my location.
- Selection bar "{n} vybráno ✕ / Pokračovat" → builder.
- Errors: "Trasu po silnici se nepodařilo spočítat".

### 2.6 ROUTE DETAIL: `RouteDetailScreen` at `/routes/:id` (`route_detail_screen.dart`)

- **Map, 188 px** (`RouteMapView`):
  - The polyline comes from live Mapy.com routing. Until that finishes, straight segments through the waypoints are drawn, with the chip "⟳ Počítám nejrychlejší trasu bez dálnic…".
  - Start flag (branch, only if it is near the route).
  - Numbered POI pins. For a loop, **numbering starts at the POI nearest to me** (`rotateLoopPoisForPosition`).
  - Tap a pin → POI sheet.
  - ← back (white, r12).
  - "⛶ Zobrazit na mapě" → fullscreen map (✕ close; the pins open the POI sheet).
- **Title block:**
  - Name (hero size).
  - "🏁 Start: MotoGo24 Mezná" (only if the start is near the route).
  - Chips:
    - 🔄 Okruh / 📍 Za místy
    - 📏 {real road km}. Initially the DB value; then `routeRealLengthKmProvider`.
    - ⏱️ {čas}
    - 🧭 "Od tebe: ~38 km · ~45 min". `~` means an estimate; it is exact once routed.
    - ⛰️ Lehká / Střední / Náročná
    - ⭐ 4.5 (2)
- **Description** (localised `descFor`).
- **"Místa na trase"**: horizontal carousel of 240×196 cards (108 px photo, number badge, name, 2-line description). The active one has a green border. Tap → POI sheet with the route's siblings.
- **"Galerie"**: 170×120 thumbnails → fullscreen viewer with credit.
- **Recenze** `RouteReviewsSection`: the same component set as the POI reviews (§2.2); `submit_route_review` / `delete_route_review`, photos in `media/route-reviews/`.
- **Sticky bottom bar:**
  - Primary (green, `ShimmerSweep`): "🧭 ZVOLIT TRASU – NAVIGOVAT" (`routeNavigate`) → `/route-nav/{id}`.
  - Secondary (pale outline):
    - "✎ Upravit / přidat body" (`routeCustomize`) → `/route-build`, shown when the route has POIs or waypoints.
    - "↗ Otevřít v jiné aplikaci" (`routeNavExternal`) → sheet "Otevřít v jiné aplikaci" with 🧭 Mapy.com, 🗺️ Google Maps and 🍎 Apple Maps, using loop-rotated points. Failure: "Nepodařilo se otevřít navigaci". With fewer than 2 points: "Trasa nemá dostatek bodů pro navigaci".
- Swiping sideways moves between siblings (the list order, or the history).
- Missing route: "Trasa nenalezena" + "Zkusit znovu".

### 2.7 NAVIGATION: `RouteNavigationScreen` (`route_navigation_screen.dart`, 1 753 lines, plus `route_nav_widgets.dart`, `route_nav_loop.dart`, `route_nav_motion.dart`)

A fullscreen in-app navigator: Mapy.com outdoor tiles, wakelock, no bottom nav.

**Top bar** (dark gradient):
- ← back. This leaves the ride **running**; the shell then shows the "Pokračovat v trase" FAB.
- Route name.
- Status line: "Hledám polohu…" / "Počítám nejrychlejší trasu bez dálnic…" / "Přepočítávám trasu…" / "Mimo trasu — přepočítávám…" / "Navigace".
- "☑ {reached}/{total}" → stops sheet.
- **Red ✕** → dialog "Ukončit trasu?" / "Navigace se zavře a jízda se přesune do historie (Moje zážitky). Pokračovat v ní můžeš kdykoli později." with "Zrušit" and a red "Ukončit".

**Map:**
- The ridden part is grey (alpha .5). The part ahead is green with a dark underlay, **drawn only up to the next stop**.
- Branch flag marker.
- Numbered POI pins; visited ones change state.
- Rider arrow `NavMeMarker`, predicted and smoothed at 60 fps between GPS fixes.
- Behaviour:
  - Heading-up rotation above 5 km/h.
  - Adaptive zoom by speed.
  - Off-route (more than 70 m for 2 fixes, or riding the wrong way) → reroute with an 8 s cooldown.
  - At most 15 routing stops per window.
  - **"Never the same road twice"** loop post-processing (`route_nav_loop.dart`).

**Controls:**
- Compass (when rotated; tap = north up).
- "+" and "−" zoom.
- Recenter mini-FAB (green while following).

**Bottom HUD** `NavHud` (white):
- Progress bar.
- Big speed "{n} km/h".
- 2×2 stats: 🏁 "Zbývá", 🕑 "Čas", ⏰ "Příjezd", ⛰ "Výška".
- Shows "Jsi v cíli 🏁" when arrived.

**Context card above the HUD**, by priority:
1. `StopReachedCard`. Fired at 150 m and **never auto-confirmed**:
   - 🎉 "Dojel jsi na místo" + name.
   - "✨ Místo objeveno! · celkem {n}" (first visit, written through `mark_place_visited`) or "✅ Navštíveno".
   - Primary "🧭 Další: {name}" or "Jsi v cíli 🏁".
   - ★ (rate the POI → POI sheet).
   - ☑ (stops sheet).
   - ✕ closes without confirming.
2. `RouteDoneCard`: 🏁 "Trasa dokončena!" with "★ Ohodnotit trasu" (DB route → reviews sheet) or "🔖 Uložit do Mých tras" (custom route → name dialog "Uložit do Mých tras" / "Název trasy" / "Uložit" → `save_user_route`; snackbars "Uloženo do Mých zážitků ✅" / "Uložení se nepovedlo" / "Přihlas se pro uložení trasy").
3. `NavForkHint`: "Křižovatka — kam dál?" with a left and a right side, each with a stop name and "Příští" / "jiný směr".
4. `NavNextStopPill`: "Příští: {name} · 1.2 km · 3/8" → stops sheet.

**Stops sheet** "Body na trasě":
- Hint "Klepnutím na bod se naviguješ rovnou k němu — dřívější nedojeté body se přeskočí."
- Rows: ✓ reached, "Příští" badge, "Navigovat" button.
- A last, initially inactive row **"MotoGo24 · {pobočka}"**: return to the branch, which is added as the final stop. For a custom route the nearest branch is used.

**Other:**
- Location denied → banner "📍 Pro navigaci povol přístup k poloze v nastavení telefonu."
- **Persistence:**
  - `activeRideProvider` (SharedPreferences) keeps the active ride (reached indices, total, done, profile, custom payload) plus a history of at most 30.
  - It survives an app kill.
  - Reopening the same route restores the reached stops.

### 2.8 ROUTE BUILDER: `RouteBuilderScreen` at `/route-build` (`route_builder_screen.dart`, plus `poi_suggest.dart`)

Opened from:
- route detail ("Upravit / přidat body")
- the Místa or map selection ("Pokračovat")
- Moje ("Vytvořit novou trasu", saved route tap or "Upravit", a history item for a custom route)

Layout:
- **Map, 260 px.**
  - Tap → add a stop.
  - Numbered pins.
  - Road polyline (Mapy.com routing, debounced).
  - ← back.
  - Spinner chip while computing.
  - Hint pill "👆 Klikni do mapy = přidat zastávku · tahem změníš pořadí".
- **Stats bar:**
  - "📏 {km} km", "🕑 {čas}" (estimated at 55 km/h, or 75 for Nejrychlejší).
  - "{n} × zastávka".
  - Profile chips: **Doporučené · Nejrychlejší · Nejkratší**.
- **`NearbyPoiPanel`** (collapsible): "Body zájmu v okolí trasy" + count.
  - Expanded: radius chips 5 / 10 / 25 / 50 km plus category chips with counts.
  - Horizontal 76 px cards (photo, name, "↗ 2.3 km"). Tap → add as the next stop.
  - Empty: "V tomto okruhu už žádný další bod není — zvětši okruh."
- **"Místa na trase"** list, reorderable by dragging:
  - Each row: number, name or "Zastávka N", coordinates "49.0906, 16.6100" (shown to the user!), a red 🗑, and a ⠿ drag handle.
  - Header button "📍+ Přidat z bodů zájmu" → Místa in pick mode.
  - Empty: "Přidej aspoň 2 zastávky".
- **Bottom bar:**
  - 🔖 (save for myself, from 2 stops): sheet "Uložit do Mých tras".
    - Hint "Trasa se uloží jen tobě do Mých zážitků — kdykoli ji znovu otevřeš a naviguješ."
    - Fields "Název trasy" and "Poznámka (jen pro tebe)".
    - Button "Uložit".
  - "✉ Navrhnout" (from 2 stops): sheet "Navrhnout trasu ostatním" with "Název" and "Popis trasy (volitelně)" → `routes` insert with `status=pending`.
  - Green "🧭 Navigovat" (from 1 stop) → `/route-nav-custom` with the chosen profile.
- `draftRouteProvider` keeps "Tvoje trasa" visible on both maps after going back.

### 2.9 MOJE ZÁŽITKY: `MyExperiencesScreen` at `/my-experiences` (`my_experiences_screen.dart`, 1 133 lines)

Outside the shell, so there is **no bottom nav**.

- **Dark header** (`MotoGoColors.dark`, bottom radius):
  - ← back.
  - "🏍️ Moje zážitky".
  - "Tvé trasy a objevená místa s MotoGo24".
  - Two tappable stat tiles that switch the tab: "📍 {n} objevených míst ›" and "🗺️ {n} vytvořených tras ›".
- **Tab pills** (swipe works too; `PageView`, 320 ms): 🗺️ Vytvořené trasy · 📍 Moje místa · 🕘 Moje trasy. They use `FittedBox`, so long labels shrink.
- **Tab 0, "Vytvořené trasy"**. Requires login; otherwise 🔑 "Přihlas se a sbírej objevená místa i vlastní trasy" + the login button. Pull to refresh.
  1. **Green CTA card** "📍+ Vytvořit novou trasu" / "Klepni do mapy, přidej zastávky či body zájmu a trasu si ulož" → empty builder.
  2. **"🛰️ Záznam jízdy"** card with a **Switch** and a "⏺ Nahrávám" badge. Hint: "Když máš povolenou polohu, trasa z tvé výpůjčky se ukládá sama — i s motorkou, kterou jsi jel. Nahrává se i na pozadí se zamčeným telefonem a po dobu výpůjčky vidí tvoji polohu i půjčovna. Kdykoli to vypneš tímhle přepínačem."
  3. **Manual ride card** (hidden while an automatic recording runs):
     - Idle: ⏺ "Zaznamenat vlastní jízdu" / "Nemáš půjčenou motorku? Spusť si záznam trasy ručně — uloží se ti mezi projeté jízdy."
     - Running (red): ⏹ "Ukončit záznam jízdy" / "Nahrávám tvou vlastní jízdu — klepnutím záznam ukončíš."
     - Snackbars: "Záznam jízdy běží 🛰️", "Jízda uložena mezi projeté jízdy", "Jízda byla kratší než 1 km — neuložila se", "Jízdu se nepodařilo uložit (bez připojení). Zkusím to znovu, jakmile bude signál.", "Záznam se nepodařilo spustit — přihlas se a povol polohu".
  4. **Ride cards** (`RideCard`) for every `user_ride`, with MotoGo and private **mixed together**.
  5. **Saved route cards** (`user_saved_routes`):
     - Name.
     - 🗑 → "Smazat tuto trasu?" / "Zrušit" / "Smazat".
     - Meta: 📏 km, 🕑 time, 📍 "{n}× zastávka", 📅 date.
     - Description (2 lines).
     - Buttons "🧭 Navigovat" → `/route-nav-custom` and "✎ Upravit" → builder.
     - Card tap → builder.
  - Empty: 🗺️ "Zatím žádné uložené trasy" / "Začni zeleným tlačítkem „Vytvořit novou trasu" nahoře — nebo si otevři kteroukoli doporučenou trasu, uprav ji a ulož záložkou 🔖."
- **Tab 1, "Moje místa"** (login required):
  - Cards with a 92 px photo.
  - "✅ {name}".
  - "🗺️ {route name}".
  - "{first visit date} · navštíveno {n}×".
  - 🧭 circle → navigate to that single place.
  - Card tap → POI sheet (swipe between my places).
  - Empty: 📍 "Zatím žádná objevená místa" / "Naviguj se na bod zájmu — po dojezdu se místo objeví tady automaticky."
- **Tab 2, "Moje trasy"** = the local history. It works without login.
  - Cards: name, a chip "Aktivní" (neon) or "Dokončeno", 🗑 (an active ride → end it; otherwise remove from history), 📅 date, 📍 "{reached}/{total}".
  - Primary "🧭 Pokračovat v trase" or "↻ Jet znovu" (done).
  - Tap → route detail (DB route) or builder (custom route).
  - Empty: 🕘 "Zatím žádné jízdy" / "Spusť navigaci na trase — tady pak najdeš historii jízd s tlačítkem Pokračovat v trase."

### 2.10 Ride card and ride detail (`ride_card.dart`, `ride_detail_screen.dart`, `ride_point_sheet.dart`, `ride_share.dart`, `ride_map.dart`)

**`RideCard`:**
- Track map preview: GPS track, start / end / stop markers. Gaps are drawn as grey dotted segments.
- Badges "⏺ Nahrávám" and "🌍 Sdíleno".
- Name or "Projetá jízda".
- Meta:
  - 📅 "16. 9. 2026 8:23"
  - 📏 km (one decimal under 10)
  - 🕑 total
  - 🏍 moving time
  - Ø speed
  - 📍 stops
  - 📷 photos
  - 🏍 **moto name** (for a rental)
- Description (2 lines).
- Tap → `/ride/:id` with the siblings.

**`/ride/:id`:**
- Dark header:
  - ←.
  - Name with ✎. Tap → dialog "Upravit jízdu" with "Název jízdy", "Popis zážitku", "Zrušit" and "Uložit".
  - "{date} · {moto}".
  - **⇪ share** → sheet "Sdílet jízdu".
  - 🗑 → "Smazat jízdu?".
- **Map, 260 px**, interactive. Tap the map → **new stop**. Tap a stop → edit it.
- **Stats card**, 3×3:
  - 📏 vzdálenost · ⏱️ celkový čas · 🏍️ čas jízdy
  - ⏸️ čas stání · 📊 Ø rychlost · 🚀 max. rychlost
  - ⛰️ nastoupáno · 📍 zastávek · 📷 fotek
  - Plus, when there are gaps: 📵 bez signálu · 🛰️ bodů stopy · ✂️ přerušení.
  - Amber notice `rideGapNotice`.
  - "🕘 start {dt} → konec {dt}".
  - "🏍️ {moto}".
  - Description.
- **"Sdílet ostatním"** switch: "Jízdu vidí i ostatní motorkáři." / "Jízda je jen tvoje — nikdo jiný ji nevidí." Default private; `visibility` is public or private.
- **"Zastávky a body zájmu"** + hint "Klepni do mapy a přidej zastávku — doplň fotky a popisek. Klepnutím na zastávku ji upravíš nebo smažeš."
- Point cards: 🏁 Start / 🏆 Cíl / 📍 Zastávka, name, note, a photo strip (110×84).
- **Point sheet:**
  - "Nová zastávka" / "Upravit zastávku".
  - "Název" with placeholder "Např. Rozhledna Babylon".
  - "Popisek" with placeholder "Co tu stálo za to?".
  - "Fotky", up to 8.
  - 🗑 delete.
  - "Uložit".
- **Share sheet:**
  - Lead: "Pošle se popis jízdy a odkaz na mapu s tvou trasou. Sdílíš jen to, co sám odešleš."
  - Tiles: 💬 WhatsApp · 📘 Facebook · ✖️ X · ✈️ Telegram · ✉️ E-mail · 📋 Kopírovat.
  - The text is: "🏍️ {name}", "{km} km · {čas} · {datum}", description, a Mapy.com link (12 or fewer points), and "Projeto s MotoGo24 🏍️".
  - Snackbars: "Zkopírováno do schránky" / "Sdílení se nepodařilo".
- `get_public_rides` (anonymous public rides) **exists on the backend but is not used anywhere** in the app, the web or Velín. A "community rides" feed would therefore need no new SQL, but it is out of scope unless the owner wants it.

### 2.11 Add menu and community submissions (`community_submit.dart`, `route_submit_screen.dart`, `submit_common.dart`)

**Add menu sheet** (from "+" on Trasy):
- ⏺ "Zaznamenat vlastní jízdu" (subtitle `rideManualHint`), or ⏹ "Ukončit záznam jízdy" (red) while one is running. Hidden during an automatic recording.
- 🛣 "Navrhnout trasu".
- 📍+ "Přidat místo".
- Not logged in → "Přihlas se a ohodnoť". That wording is odd for submitting.

**`RouteSubmitScreen`** "Navrhnout trasu":
- Intro banner: "Návrh zkontroluje náš tým — po schválení se objeví v aplikaci všem jezdcům."
- "Název".
- **Link** "Odkaz z Mapy.com nebo Google Maps", placeholder "mapy.com/s/… · maps.app.goo.gl/… · plná URL", button "Načíst body z odkazu" / "Načítám…". Result "{n} bodů trasy načteno" or "Odkaz se nepodařilo načíst". Short links are resolved by the edge fn `resolve-mapy-route`.
- Help box "Kde odkaz vzít (fungují jen tyto formáty):":
  - "• Mapy.com: naplánuj trasu → Sdílet → zkrácený odkaz nebo QR kód."
  - "• Google Maps: přepni na Trasu → Sdílet / zkopíruj odkaz z adresního řádku."
- Map: tap to add a point, reorder by dragging. Hint "Klikni do mapy = přidat bod · tahem změníš pořadí".
- Stops list.
- "Popis trasy (volitelně)".
- **Fotky** "Přidej až 6 fotek z vyjížďky — první je titulní."
- Button "Odeslat ke schválení" → `routes` insert with `status=pending`.

**`PoiSubmitScreen`** "Navrhnout bod zájmu":
- Intro banner.
- 220 px map with a fixed centre pin (move the map to place it).
- "◎ Moje poloha".
- "Název", pre-filled by reverse geocoding from Mapy.com.
- "Popis (volitelně)".
- Photos, hint "Návrhy s fotkou schvalujeme rychleji." Only the first photo is stored as `image_url`.
- "Odeslat ke schválení" → `user_pois` with `status=pending`.

**Success dialog:** "Díky! Návrh odeslán" / "Po schválení se objeví v aplikaci všem jezdcům." / "Hotovo".

Errors: "Vyplň název", "Odeslání se nepovedlo", "Přidej aspoň 2 body (odkazem nebo klikem do mapy)."

### 2.12 Background services that touch the tab

- **`RideRecorder`:**
  - Automatic recording only when all of these hold: logged in, a running rental, location already granted (it never asks), and the toggle on.
  - Manual recording asks for location.
  - Android uses a foreground service with a notification; iOS uses background location.
  - Fixes are batched every 20 m to `append_ride_track`.
  - A ride under 1 km is dropped.
  - On iOS, approximate location triggers a request for temporary full accuracy.
  - Recordings survive an app kill.
- **Caches:**
  - `routes_cache_v1.json` and `pois_catalog_cache_v1.json`, with a TTL and a background refresh, so they work offline.
  - Wikimedia images are resized with `?width=` and carry the required User-Agent.

---

## 3. Data and backend

**Tables** (STATE_1):

| Table | Holds |
|---|---|
| `routes` | name, description, `route_type` loop/poi, `distance_km`, `duration_min`, difficulty, `waypoints` jsonb (with labels), `geometry` (**NULL everywhere**), `mapy_url`, `cover_image`, `images[]`, `image_alts[]`, `translations`, `countries[]`, `status` pending/approved, `branch_id` (384 routes, all Mezná) |
| `route_pois` | 8 456 rows |
| `points_of_interest` | about 49 926; category from the 12 keys, `surroundings`, `translations` |
| `user_pois` | 0 approved |
| `route_reviews` | 2 |
| `poi_ratings` | |
| poi reviews | through RPC |
| `user_saved_routes` | max 200 per user |
| `user_visited_places` | |
| `user_rides` | stats computed on the server |
| `user_ride_points` | max 200 per ride |

**RPCs used by the tab:** `get_route_detail`, `get_route_poi_detail`, `get_poi_detail` (authenticated), `get_user_pois`, `rate_poi`, `poi_rating_summary`, `get_poi_reviews`, `submit_poi_review`, `delete_poi_review`, `get_route_reviews`, `submit_route_review`, `delete_route_review`, `get_my_saved_routes`, `save_user_route`, `delete_user_route`, `get_my_places`, `mark_place_visited`, `get_my_rides`, `get_booking_rides`, `start_user_ride`, `append_ride_track`, `finish_user_ride`, `create_manual_ride`, `update_user_ride`, `delete_user_ride`, `save_ride_point`, `delete_ride_point`.

**Direct writes:** `routes` insert (pending), `user_pois` insert (pending).

**Storage:** `media` with the prefixes `route-reviews/`, `rides/<uid>/` and submissions.

**External APIs:** Mapy.com routing, rgeocode and outdoor tiles.

**Not needed by the redesign:** any new backend. The only optional new things are i18n keys for new labels; there is no SQL.

---

## 4. Live sample content for mockups (real, anonymous read on 2026-10-15)

### 4.1 Near Velké Němčice

The sample customer's branch is VN. The nearest route starts 10.6 km away. A route's `branch_id` says Mezná, so filter by distance from the branch, not by `branch_id`.

| Route | Type | km | čas | Obtížnost | Míst | Cover |
|---|---|---|---|---|---|---|
| Rajhrad a Židlochovicko | Okruh | 40 | 55 min | Lehká | 5 | `media/routes-mirror/5955e514a6557713724037e3172adc708f0e4d41.jpg` |
| To nejlepší v okolí: Špilberk | Okruh | 66 | 1 h 34 min | Lehká | 8 | `…/84dc07a1e5cddc004eb54932e42d5eac6d14254f.jpg` |
| Za historií: Synagoga v Dolních Kounicích a okolí | Okruh | 122 | 2 h 54 min | Lehká | 7 | `…/57abf096e4807ec0cd48ec3bc8429cf7242df8f8.jpg` |
| Vodní krásy: Věstonická nádrž a okolí | Okruh | 170 | 4 h 50 min | Střední | 7 | `…/88cf0867c83db0b88ec60112c86feb4bd01ed3d2.jpg` |
| Vyhlídková jízda: Stará radnice v Brně a okolí | Okruh | 249 | 5 h 55 min | Střední | 7 | `…/adbce609ce2f3a2402425eb357a0aec42f33ae2a.jpg` |

URL base: `https://vnwnqteskbykeucanlhk.supabase.co/storage/v1/object/public/media/routes-mirror/`.

**Rajhrad a Židlochovicko:**
- Description: "Okruh úrodnou krajinou jižně od Brna mezi klášterem a zámky. Benediktinský klášter Rajhrad, lovecký zámek Židlochovice a vinařské obce nabízí historii a pohodovou jízdu. Nejlepší od jara do podzimu; pozor na provoz u Brna."
- POIs: Klášter Rajhrad, Blučina, Výhon u Židlochovic, Nosislav – vinné sklepy, Zámek Židlochovice.
- Waypoints, labelled: Start: Rajhrad (49.0906, 16.61) → Blučina → Výhon u Židlochovic → Nosislav – vinné sklepy → … (use them for the sketch).

**Vodní krásy: Věstonická nádrž a okolí** POIs: Věstonická nádrž, Mahenovo jezero, Stará Dyje, zdymadlo Rohatec, Kobylské jezero, Vodní dílo Nové Mlýny.

**Places near VN** (category, name, photo id under the same base):

| Category | Place | Photo id |
|---|---|---|
| 🏰 | Zámek Velké Němčice | `f1784715bd8d779befffbcb72651acdeeeeffe44.jpg` |
| 🏭 | vodní mlýn Velké Němčice | `3283571cd9fd7c3b96fa35b5fcd6d4972ab0c0fb.jpg` |
| 🌊 | Vodní dílo Nové Mlýny | `f7576a3851fb1fe428870d41b602a3b5fb5851a1.jpg` |
| 🗼 | Hustopeče (rozhledna) | `897a1c5934c0421f2d73e3689fcd8cf1c86384f9.jpg` |
| 🗼 | rozhledna Slunečná | `42e2c3f31cae5d03d4d7c1a7f0333576a3a7d917.jpg` |
| 🪖 | Římská vojenská pevnost u Mušova | `dace9fb063966cc3710c4e4556cab758434230d2.jpg` |
| 🏰 | Zámek Pouzdřany | `a4b810daadc750dcff259f88365214cc821b5831.jpg` |

**Place detail sample, Zámek Velké Němčice:**
- Description: "Kulturní památka České republiky v obci Velké Němčice. Hrad či zámek v Česku — historická zastávka, která stojí za odbočku."
- Okolí: "Zámek Velké Němčice leží v jižní Moravě v relativně nízkohraté krajině s postupným členěním terénu. Okolí objektu charakterizují zemědělské plochy a typická jihomoravská krajina s rozptýlenou zástavbou. Místo je přirozenou zastávkou na motoristických trasách středojižní Moravy…"

### 4.2 From Mezná

| Route | km | čas | Obtížnost | Míst |
|---|---|---|---|---|
| UNESCO trojúhelník – Telč, Třebíč, Zelená hora | 242 | 5 h 45 min | Střední | 8 |
| Husitské Táborsko a Chýnovská jeskyně | 142 | 3 h 35 min | Střední | 7 |
| Přehrady, voda a klášter Vysočiny | 118 | 2 h 45 min | Lehká | 5 |
| Rozhledny a zámek Přibyslav | 195 | 4 h 20 min | Střední | 8 |
| Mohelenská hadcová step a údolí Oslavy | 215 | 4 h 45 min | Střední | 9 |

Details:
- UNESCO trojúhelník: description "Okružní vyjížďka po třech památkách UNESCO na Vysočině vede výhradně po scénických silnicích II. a III. třídy – dálnicím a rychlostním silnicím se zcela vyhýbá. Z Mezné u Pelhřimova zamíříte na jih k renesanční Telči…". Cover `66dd69af5ffb8d784daf82f4ec722f67007449af.jpg`.
- Husitské Táborsko: cover `62ef780cb6263bc4a5393dd75283c71385bf79ba.jpg`.
- Přehrady, voda a klášter Vysočiny: POIs Vodní nádrž Trnávka, Klášter Želiv, Vodní nádrž Švihov (Želivka), Vodní nádrž Sedlice, Restaurace: Mahler Penzion (Kaliště).

### 4.3 Reviews and personal mock data

- **Real reviews:** "Za historií: Rychlebský hrad a okolí" ★5 (no text); "Vodní krásy: Gösselsdorfer See a okolí" ★5 "Fajn vyjížďka.🤘".
- **Personal data cannot be read anonymously.** For the sample customer, mock:
  - a MotoGo ride "Husqvarna 701 SM" (it belongs to the upcoming 16.–18. 10. booking, so past rides must come from an earlier rental)
  - a private ride
  - saved routes
  - visited places

  Label all of these as `[mock]` in the board.

---

## 5. Problems found (inputs for the redesign; nothing to drop)

1. **IA:**
   - The tab label is TRASY but the root is Místa.
   - Routes, both maps and Moje are reachable only through the rotating quick-link tiles. The swipe-to-cycle gesture is undiscoverable.
   - Moje zážitky and ride detail drop the bottom nav.
2. **Moje naming:** "Moje trasy" = navigation history; "Vytvořené trasy" = create CTA + recording toggle + manual recording + all rides + saved routes. Rides with MotoGo and private rides are not separated. The header stats ignore rides and kilometres.
3. **Bottom-right collisions:** "+" FAB (Trasy), the round 📍+ and ◎ (maps), the navigation zoom and recenter, the shell FABs (route FAB, booking, docs, cart, SOS), and the selection bars. The AI FAB move has to be planned per screen: hidden in fullscreen flows (navigation, builder, maps) and raised above sticky bars.
4. **Truth:**
   - The "1 370 tras" floor (§0).
   - The branch flag on every card.
   - The POI review hint says "o trase" for a place.
   - A not-logged-in submit shows "Přihlas se a ohodnoť".
5. **Missing shortcut:** there is no "Navigovat sem" in the place detail; it exists only in Moje místa.
6. **Filters hidden:**
   - Místa: the category chips (the most used filter) sit behind "Filtry a řazení".
   - Trasy: type and difficulty filters were removed, but difficulty still shows on detail and on the map cards.
7. **Builder** shows raw coordinates per stop. Show "Zastávka N" + a reverse-geocoded place name, or nothing.
8. **`geometry` is NULL** on every route. Sketches have to be drawn from `waypoints` (7–9 points); the road line comes from live Mapy.com in detail only. Spec C16 says `routes.geometry`; it has to fall back to `waypoints`.
9. **Unused i18n keys** (dead in the UI): `routesAllBranches`, `routesFilterType`, `routesFilterDifficulty`, `routesFilterAbroad`, `routeOpenIn`, `routeNavInApp`, `routeNavToFinish`, `routeNavSpeed`, `navRatePoi`, `placesMapRoutes`, `poiNavigateThrough`, `routeBuilderTitle`, `poiSubmitRoute`, `poiAddMenu`, `poiSubmitUrl`, `poiSubmitLocation`, `poiPickOnMap`, `poiSubmitThanks`, `poiAddPhoto`, `routeSubmitThanks`, `poiAllPoints`, `poiCatalog`, `poiCommunity`, `routeSubmitPoints`, `routesDiscoverCount`, `routesFilterFromMe`, `poiFilterTitle`, `poiFilterOnlyPhoto`, `poiFilterClear`. They are useful for new labels; for example `placesMapRoutes` = "Trasy s vybranými místy" and `poiNavigateThrough` = "Navigovat přes vybrané".
10. **Ride feedback:** "Jak se ti jelo?" + "Napiš nám recenzi" / "Napiš nám přímo, co máme zlepšit" lives only on the completed reservation. A MotoGo ride card or detail could link to it (same booking); this is optional.

---

## 6. Web v2 reference for TRASY

The web has **no routes or places pages**. The only reference is the landing section "Trasy a záznam jízdy" (`motogo-web-php/landing-routes.php`, `css/landing-routes.css`, copy in `data/landing-trust.php`).

**Copy:**
- Eyebrow "Aplikace MotoGo24 zdarma".
- H2 "Kam vyrazit? A kudy jsi jel?".
- Lead "Nevíš, kam vyjet? Vyber si z přes 1 000 tras s navigací. A po jízdě uvidíš, kudy jsi jel, kolik km a jak dlouho."
- Stat tiles: **"1 000+ tras s navigací · 50 000 zajímavých míst · 0 Kč aplikace zdarma"**. These are the truthful numbers to reuse in the app header.
- Items:
  - "Záznam každé jízdy": "Trasa na mapě, km, čas jízdy i stání, průměrná a max. rychlost, nastoupané metry a fotky ze zastávek."
  - "Tipy na trasy": "Přes 1 000 doporučených tras u nás i v zahraničí — s navigací."
  - "Zajímavá místa": "Téměř 50 000 míst: hrady, vyhlídky, jídlo i moto spoty. Objevená místa se ti ukládají."
  - "Vlastní trasy": "Naklikej si trasu v mapě, ulož ji a sdílej jízdu s partou."
- Phone mock:
  - Animated route draw: `stroke-dashoffset` over 6 s, the pin pops at the end.
  - Dark card "Okruh Vysočinou" with chips "186 km · 3 h 42 min · Ø 58 km/h · ↑ 1 240 m".
  - **Reuse it as the ride-stat card style in Moje.**

**Reusable v2 UI patterns:**
- The `.km` dark segmented switch: `.km-top` radial `#24563B → #0E2A1C → #0A1F14` with a neon scan line (`lpScan` 3.6 s); `.km-sw` 2-col pill with `rgba(116,251,113,.22)` borders. Use it for the TRASY segments.
- Bottom-sheet filters (`landing-catalog-sheet.js`) with a live count on the apply button. The app already does "Zobrazit (n)".
- `.lp-rt-stats` white stat tiles (900 weight value + small label). Use them for the Moje hero stats.
- `prefers-reduced-motion` guards. The web pauses the draw animation; mirror that.

---

## 7. Proposed clearer IA for TRASY (omits nothing)

### 7.1 Shell and header

- `/routes` stays the tab root and stays in the shell.
- Every list and map lives inside the shell.
- Focused flows hide the nav and use the push motion: navigation, builder, submit screens, fullscreen image viewer, ride detail.

**Dark collapsing header** (`gDark`, bottom r24, rank accent on the segment glow and the title underline):

**Row 1:**
- Title "Trasy" (`routesTitle`), with the `AnimatedRouteIcon` (static under reduced motion).
- Right side, 44 px icon buttons: **🗺 map** and **＋ add**.
  - The map button is segment-aware: Místa → Mapa míst; Trasy → Mapa tras; Moje → Mapa míst filtered to my places.
  - "+" replaces the FAB and frees the bottom-right for the AI FAB.
  - "+" menu:
    - ⏺ "Zaznamenat vlastní jízdu" / ⏹ "Ukončit záznam jízdy"
    - 📍+ "Vytvořit novou trasu" (new entry; the builder)
    - 🛣 "Navrhnout trasu"
    - 📍 "Přidat místo"

**Row 2:** the search pill, shared between Místa and Trasy. Placeholder per segment: "Hledat místo…" / "Hledat trasu, místo, město…". It collapses on scroll; 🔍 in the title restores it.

**Row 3:** the segmented control **📍 Místa · 🛣️ Trasy · 🏍️ Moje**.
- Sliding neon thumb, 240 ms; cross-fade under reduced motion.
- Default Místa, the 16. 9. decision. Remember the last choice.
- `?seg=` deep links. `/routes-list` → `seg=trasy`; `/my-experiences` → `seg=moje`.

**Labels in all 8 languages**, from existing keys:

| Lang | Místa | Trasy | Moje |
|---|---|---|---|
| cs | Místa | Trasy | Moje |
| en | Places | Routes | Mine |
| de | Orte | Routen | Meine |
| es | Lugares | Rutas | Mías |
| fr | Lieux | Itinéraires | Les miennes |
| nl | Plekken | Routes | Mijn |
| pl | Miejsca | Trasy | Moje |
| uk | Місця | Маршрути | Мої |

- "Moje" needs a **new key** (`routesSegMine`). The full `myExpTitle` ("Mes expériences", "Meine Erlebnisse", 15–16 chars) is too wide for a third of 358 dp at 13 px / 800.
- The longest string is fr "Itinéraires" / "Les miennes", about 11 chars, which fits 110 dp at 13 px. Verify with the nav measuring harness (`scratchpad/navmeasure`). Icon + label, no `FittedBox` shrinking.

**Live strip** under the header, sticky and conditional:
- (a) Active navigation: "🧭 Pokračovat v trase · {name} · {reached}/{total}" + ✕. It replaces the shell route FAB on this tab; the FAB stays on other tabs.
- (b) Recording: "⏺ Nahrávám jízdu · {km}" (automatic, with the moto name; or manual with an "Ukončit" link). Tap → Moje › Jízdy.

### 7.2 Segment MÍSTA: visible vs behind a tap

**Visible:**
- The location prompt (only without location).
- The map preview, 160–180 px, with the hint and ⤢.
- A **filter toolbar:**
  - "⚙ Filtry a řazení (n)"
  - "📡 V okolí 25 km" quick toggle
  - "✕ Zrušit"
  - removable active-filter chips (`PlacesFilter.summary()` → real chips)
- **Category chips** as a single horizontal scrolling row with counts. They are visible now instead of hidden, and are the main filter.
- The banner "Našli jsme i trasy · {n} ›". It now **switches to the Trasy segment** with the same query.
- The place list: card tap = detail, ⊕ = add, long-press = add.

**Behind a tap:**
- Tools sheet: search, Řadit, Kategorie, Země + "Další státy", "Minimální hodnocení".
- Route picker sheet.
- Radius chips (after turning on "V okolí").
- The place detail sheet. Everything in §2.2 stays, **plus a new secondary "🧭 Navigovat sem"** (reuses `_navigateToPlace`).

**Sticky:** "{n} vybráno ✕ · 🧭 Vlastní vyjížďka ›" (`poiCustomRouteTitle`) → builder. While the bar shows, the AI FAB rises above it.

### 7.3 Segment TRASY

**Visible:**
- Truthful stat line, e.g. "1 174 tras · 49 900 míst" or "1 000+ tras s navigací · 50 000 míst". Use real counts rounded **down**; never a floor above the actual count.
- Toolbar: "⚙ Filtry (n)" · "↕ Řadit: Od mé polohy" · "🗺 Mapa tras" · "✕ Zrušit".
- **Route cards:**
  - Cover photo with the sketch overlay from `waypoints` (draw-in once; static under reduced motion).
  - Type pill.
  - Name.
  - **Start flag only when the start is near a branch** (reuse `startIsNearRoute`).
  - Meta: km · čas · počet míst · "Od tebe ~{km} km" · ★ (tap → reviews sheet).
  - Difficulty chip, colour-coded as in the spec: Lehká `#E8FCE8/#0D6E0D` · Střední `#FFF4E0/#8A4B00` · Náročná `#FDECEC/#B42318`.

**Behind a tap:** the filter sheet (Země, linked Délka / Čas sliders, "Počítat i cestu od mé polohy"), the sort sheet, the reviews sheet, and the route detail.

**Route detail** keeps everything in §2.6. It reorganises it as:
- Map hero (draw-in 1.6 s, POI pins pop with a 70 ms stagger).
- 4 stat tiles: km · čas · obtížnost · míst. Plus a "Od tebe" chip and rating.
- Description (3 lines + "Více").
- "Místa na trase" carousel.
- Galerie.
- Recenze.
- **Sticky primary "🧭 ZVOLIT TRASU – NAVIGOVAT"** with the rank glow.
- Secondary links: "Upravit / přidat body", "Otevřít v jiné aplikaci".
- The optional ghost link "Půjč si motorku na tuhle trasu", from the spec.
- Swipe between siblings.

### 7.4 Segment MOJE (the "Sultan" diary; replaces `/my-experiences` and keeps the nav)

**Hero card** (`gDark` + rank ring colour, web `.lp-rt` dark card style):
- "🏍️ Moje zážitky" + the subtitle.
- **4 stat tiles**, all computed on the client from data already loaded:
  - objevených míst (`get_my_places`)
  - uložených tras (`get_my_saved_routes`)
  - **jízd** (`get_my_rides` length)
  - **najeto km** (sum of `distance_km`)
- Tiles are tappable and jump to their sub-section.

**CTA row:**
- Green "📍+ Vytvořit novou trasu".
- Outline "⏺ Zaznamenat vlastní jízdu". In the running state it turns red: "⏹ Ukončit záznam jízdy".

**Sub-chips** (horizontal, remembered). The labels are clearer; the content is unchanged.

1. **Jízdy.** Default when any ride exists.
   - Filter chips **Vše · S MotoGo · Soukromé**, split on `bookingId != null`.
   - The "🛰️ Záznam jízdy" switch card (with the full hint) sits at the top as a compact settings row; tap ⓘ to expand the hint.
   - `RideCard` list → ride detail (everything in §2.10).
2. **Uložené trasy:** the saved-route cards with "Navigovat" / "Upravit" / 🗑. Empty text as today; adjust the copy to "Vytvořit novou trasu".
3. **Objevená místa:** today's "Moje místa", with 🧭 navigate and the POI sheet.
4. **Rozjeté navigace:** today's "Moje trasy" local history, with "Pokračovat v trase" / "Jet znovu" / 🗑 and the "Aktivní" / "Dokončeno" chips. It works without login.

**Labels:**
- New keys for: Jízdy, Uložené trasy, Objevená místa, Rozjeté navigace, S MotoGo, Soukromé.
- Existing keys to reuse: `myExpPlacesTab` "Moje místa" (it can stay as "Objevená místa"), `rideBookingSection`.

**Not logged in:** the hero shows the 🔑 prompt "Přihlas se a sbírej objevená místa i vlastní trasy" + "Přihlásit se". Rozjeté navigace stays available.

### 7.5 Global and fullscreen pieces (unchanged in function, restyled)

- **Navigation:**
  - Full §2.7. It hides the AI FAB and the bottom nav.
  - Stop-reached celebration: "✨ Místo objeveno!" with a short neon burst, rank-coloured; static under reduced motion.
  - The done card: "Trasa dokončena!".
- **Builder** (§2.8):
  - Restyle in the dark-on-light premium language.
  - Hide raw coordinates.
  - Keep the 3 profiles, nearby POIs, reordering, save, suggest and navigate.
- **Mapa míst / Mapa tras:** fullscreen inside the shell (or a focused flow). Header with status + summary chips, round controls right, selection bar. The AI FAB is hidden on fullscreen maps (they already have a right-side control column).
- **Submit screens:** RouteSubmit and PoiSubmit unchanged, with an add-login copy fix.
- **Reservation detail** keeps "PROJETÉ JÍZDY".
- **Home (Sultan)** links into Moje › Jízdy (S MotoGo / Soukromé) and Trasy (routes near the pickup branch, chosen by distance and not by `branch_id`; spec §5 personal).

### 7.6 Motion and rank (where the rank shows up in TRASY)

**Motion:**
- Segment thumb: slide + neon glow in the rank `color_hex`, with an outer glow at 30 % opacity. Contrast is guaranteed by keeping the label dark on the neon thumb.
- Card reveal: keep `StaggeredReveal` on the first 6.
- Route sketch draw-in: 900 ms on cards, 1.6 s in detail.
- POI pin pop: 70 ms stagger.
- "Místo objeveno" burst.
- Hero stat count-up on the Moje tiles: 600 ms, run once per session.
- Pull-to-refresh: brand spinner.
- **Under reduced motion**, all of these collapse to fades or nothing.

**Rank:**
- The ring colour in the Moje hero.
- The primary CTA glow (NAVIGOVAT, Vlastní vyjížďka, Vytvořit novou trasu).
- No pink or purple: follow the new rank palette.
- The **level-up overlay is untouched** (a global watcher over all screens, including TRASY).

---

## 8. Completeness checklist: today → proposed home

| Function / information today | Proposed location |
|---|---|
| Místa catalogue, search, location prompt, map preview, gesture hint | TRASY › Místa |
| Categories with counts, V okolí 5–50 km, route filter, sort, countries, min rating, Zrušit | Místa toolbar (categories visible) + tools sheet + route sheet |
| "Našli jsme i trasy" | Místa banner → switches segment |
| Place card: distance + time, rating, category / route / community label, ⊕ / long-press | Místa list (same) |
| Place detail: photos, viewer, credit, category, description, Okolí, rating, reviews (+photos), swipe siblings, add to trip | Sheet (same) + new "Navigovat sem" |
| Selection → custom route → builder | Sticky "Vlastní vyjížďka" bar (Místa, Mapa míst, Mapa tras) |
| Mapa míst: clusters, status, summary chips, filter-off, ◎, 📍+ add, long-press add, selection road route, draft chip | Header map button (Místa / Moje) |
| Trasy list: stat line, search, filters (země, délka ⇄ čas, approach), sort ×5, cards, star → reviews sheet, pull-to-refresh, empty / error / filter-empty | TRASY › Trasy |
| Mapa tras: route points, other places toggle, routes through a point (colours, labels, cards, Detail, Další trasa), draft chip, ◎ | Header map button (Trasy) |
| Route detail: map + fullscreen, computing chip, chips (type, real km, time, Od tebe, difficulty, rating), description, POI carousel, gallery, reviews, NAVIGOVAT, Upravit / přidat body, external apps (Mapy.com / Google / Apple), swipe siblings | Route detail (reordered) |
| Navigation: everything in §2.7 (HUD, reroute, loop logic, stop cards, discovery, fork hint, stops sheet, branch return, end dialog, save custom, rate route, denied banner, compass / zoom / recenter, persistence) | Unchanged fullscreen |
| Route FAB "Pokračovat v trase" + ✕ | Live strip on TRASY + shell FAB elsewhere |
| Builder: map tap, profiles, km / time, nearby POIs (radius, categories), add from catalogue (pick mode), reorder, delete, save for me, Navrhnout, Navigovat, draft persistence | Unchanged focused flow (coordinates hidden) |
| Add menu: manual ride, Navrhnout trasu, Přidat místo | Header "+" (+ "Vytvořit novou trasu") |
| RouteSubmit (link decode Mapy / Google, help, map, points, description, 6 photos, moderation) / PoiSubmit (centre pin, my location, reverse-geocoded name, description, photo) / success dialog | Unchanged (from "+", map long-press, 📍+) |
| Moje header stats (places, routes) | Moje hero (+ rides, km) |
| Vytvořit novou trasu CTA | Moje CTA row + "+" menu |
| Záznam jízdy switch + hint + Nahrávám badge | Moje › Jízdy settings row + live strip |
| Manual ride start / stop + snackbars | Moje CTA row + "+" menu + live strip |
| Ride cards (MotoGo + private) | Moje › Jízdy (Vše / S MotoGo / Soukromé) |
| Saved routes (Navigovat / Upravit / Smazat, meta, description) | Moje › Uložené trasy |
| Moje místa (visit count, route, date, navigate, detail swipe) | Moje › Objevená místa |
| Local history (Aktivní / Dokončeno, Pokračovat / Jet znovu, delete, open detail / builder) | Moje › Rozjeté navigace |
| Ride detail: edit name / description, share sheet (6 targets), delete, interactive map add / edit stops, 3×3 (+gap) stats, gap notice, start → end, moto, visibility switch, stop cards, point sheet (name, note, 8 photos, delete) | Unchanged focused flow |
| Reservation detail "PROJETÉ JÍZDY" | Unchanged |
| Login prompts (Moje, reviews, ratings, save, submit) | Kept (copy fix for submit) |
| Offline caches, background recording notification | Unchanged |
