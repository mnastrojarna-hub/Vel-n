# Plán fíčury „TRASY" + přesun E-shopu do menu

> Stav: **PŘÍPRAVA / ANALÝZA** — zatím se nic neimplementuje.
> Větev: `claude/bold-mendel-6n5jpv`
> Datum: 2026-06-21

---

## 1. Zadání (rozpad)

1. **Přesun E-shopu** z dolního panelu (bottom nav) do hamburger menu.
2. **Nové tlačítko „Trasy"** na uvolněné místo v dolním panelu.
3. **Trasy = doporučené motorkářské trasy vedoucí od konkrétní pobočky:**
   - okruhy **nebo** trasy za body zájmu (POI),
   - členění/řazení podle délky v km,
   - **náhled trasy v mapě** (zoom, posun),
   - body zájmu + obrázky + popis.
4. **Velín — správa tras:** admin přidá popis, body zájmu, obrázky → komplet CRUD.
5. **Přenos trasy do aplikace uživatele:** kliknutím „Zvolit" přenést trasu i se zastávkami a POI do Mapy.cz / Google Maps / Waze, **nebo** lépe zobrazit přímo v MotoGo appce přes Mapy.com API.

Referenční trasa: https://mapy.com/s/lerafakubu

---

## 2. Co už v projektu existuje (zjištěno analýzou)

### Flutter app (`Motogo-app-main/motogo-app-flutter/`)
- **Dolní panel** = `lib/core/app_shell.dart`, pole `_tabDefs` (4 taby: Home, Book, Reservations, **Shop**).
  - Index Shopu = 3; metoda `_currentIndex()` mapuje cesty na tab.
- **Hamburger menu** = `lib/features/profile/profile_screen.dart` (hamburger na home → `context.go(Routes.profile)`; menu je profil). Položky = widget `ProfileMenuItem`, členěné do sekcí.
- **Routing** = GoRouter, `lib/core/router.dart`, konstanty ve třídě `Routes`, `ShellRoute` pro taby.
- **State** = Riverpod (`FutureProvider`/`StreamProvider`).
- **Supabase** = `MotoGoSupabase.client` (`lib/core/supabase_client.dart`).
- **Pobočky** = tabulka `branches`, načítané přímo (`branches_sheet.dart`); moto model nese `branchId/branchName/branchCity/branchType`.
- **Mapy:**
  - `flutter_map: ^6.1.0` + `latlong2` (už používáno v `widgets/map_picker.dart`, OSM/CARTO dlaždice).
  - **Mapy.cz API klíč** už hardcoded: `whg1ilj203oYhmsqkBHVtUqpk-tYr0E-HFTx4lGdue0`, hlavička `X-Mapy-Api-Key`. Používá se pro `rgeocode` a routing (`map_launcher.dart`, `price_calculator.dart`).
  - `url_launcher: ^6.2.2` (otevírání externích URL) + `webview_flutter: ^4.10.0`.
- **i18n** = `lib/core/i18n/translations.dart` (mapy `cs/en/de/nl/es/fr/pl`), použití `t(context).tr('key')`.

### Velín (`velin/`)
- **CRUD vzor** = `src/pages/Branches.jsx` (list/insert/update/delete + `admin_audit_log`).
- **Supabase** = `src/lib/supabase.js` (`supabase` klient).
- **Navigace** = `src/components/Sidebar.jsx` (NAV pole) + `src/App.jsx` (lazy `Route`).
- **Upload obrázků** = `src/components/ui/ImageUploader.jsx`, bucket **`media`**, prop `folder`.
- **Modal/formuláře** = `src/components/ui/Modal.jsx`, `FormField` (vzor `BranchModal.jsx`).
- **Překlady obsahu** = `src/lib/autoTranslate.js` (`FIELD_MAP`, sloupec `translations` jsonb) + `TranslateEverythingButton`.

### Backend (Supabase, projekt `vnwnqteskbykeucanlhk`)
- Zatím **žádná** tabulka pro trasy. Nutné nově vytvořit.
- Bucket `media` existuje pro obrázky.

---

## 3. Návrh datového modelu (backend) — SQL až po odsouhlasení

> Dle pravidla CLAUDE.md: SQL se nejdřív dá jako text do chatu, commitne se až po ověření; po změně se aktualizují `SUPABASE_BACKEND_STATE_*.md`.

### Tabulka `routes` (trasy)
| sloupec | typ | popis |
|---|---|---|
| `id` | uuid PK | |
| `branch_id` | uuid FK→branches | pobočka, od které trasa vede |
| `name` | text | název trasy |
| `description` | text | popis (HTML/markdown text) |
| `route_type` | text | `loop` (okruh) / `poi` (za body zájmu) |
| `distance_km` | numeric | délka v km (pro řazení/filtr) |
| `duration_min` | int | odhad času (volitelné) |
| `difficulty` | text | volitelné (easy/medium/hard) |
| `waypoints` | jsonb | `[{lat,lng,order}]` — body pro výpočet trasy |
| `geometry` | jsonb | volitelně předpočítaná geometrie (polyline/GeoJSON) z Mapy.com routing |
| `mapy_url` | text | originální mapy.com share link (záloha/odkaz) |
| `cover_image` | text | hlavní obrázek (URL) |
| `images` | text[] | galerie |
| `image_alts` | text[] | alt texty |
| `translations` | jsonb | `{lang:{name,description}}` |
| `is_active` | bool | publikováno |
| `sort_order` | int | řazení |
| `created_at/updated_at` | timestamptz | |

### Tabulka `route_pois` (body zájmu) — varianta normalizovaná
| sloupec | typ | popis |
|---|---|---|
| `id` | uuid PK | |
| `route_id` | uuid FK→routes ON DELETE CASCADE | |
| `name` | text | název POI |
| `description` | text | popis |
| `lat`/`lng` | numeric | poloha |
| `image_url` | text | obrázek POI |
| `images` | text[] | galerie POI |
| `sort_order` | int | pořadí na trase |
| `translations` | jsonb | překlady |

*(Alternativa: POI držet jen jako `waypoints`/`poi` v jsonb na `routes` — méně tabulek, jednodušší velín, ale hůř se škáluje na obrázky per-POI. Doporučuji samostatnou tabulku `route_pois`.)*

### RLS
- `routes`/`route_pois`: **Public read** (`is_active=true`) pro anon+authenticated; **write** jen admin (`is_admin()`), vzor dle ostatních tabulek.

---

## 4. Mapy.com / Mapy.cz API — jak řešit geometrii a zobrazení

- **Klíč už máme** (`X-Mapy-Api-Key`). Mapy REST API v1 umí: routing (`/v1/routing/route` — geometrie trasy mezi body, profily car/bike/foot), rastrové dlaždice, geocode/rgeocode, statické mapy.
- **Zdroj geometrie trasy** (rozhodnutí níže): nejspolehlivější je nechat admina zadat **waypointy** ve Velíně a geometrii spočítat přes Mapy routing API (uložit do `geometry` pro rychlé vykreslení v appce). Share link `mapy.com/s/...` nelze veřejným API spolehlivě dekódovat → slouží jen jako referenční odkaz/záloha.
- **Náhled v appce:** `flutter_map` (už v projektu) + Mapy.com rastrové dlaždice; polyline z `geometry`, markery POI; nativní zoom/posun.
- **Přenos do cizí app** (`url_launcher`) — ROZHODNUTO: **Apple Maps + Google Maps**:
  - Google Maps (Android i web): `https://www.google.com/maps/dir/?api=1&origin=…&destination=…&waypoints=lat,lng|…&travelmode=driving`.
  - Apple Maps (iOS): `https://maps.apple.com/?saddr=…&daddr=lat,lng+to:lat,lng…&dirflg=d` (víc zastávek přes `daddr` + `to:`).
  - Volba cílové app dle platformy (iOS → nabídnout Apple Maps, Android → Google Maps), případně nabídka obou.

---

## 5. Plán implementace (etapy)

### Etapa A — Backend (SQL, nejdřív do chatu)
1. Migrace `routes` + `route_pois` + RLS (public read / admin write) + indexy (`branch_id`, `is_active`, `sort_order`).
2. (volitelně) RPC `get_branch_routes(branch_id)` pro app — vrátí trasy + POI v jednom volání.
3. Přidat `routes`/`route_pois` do `FIELD_MAP` v `autoTranslate.js`.
4. Aktualizovat `SUPABASE_BACKEND_STATE_1/2/3/5/6.md`.

### Etapa B — Velín (správa tras)
1. `src/pages/Routes.jsx` (CRUD dle `Branches.jsx`): seznam tras, filtr dle pobočky, vytvořit/upravit/smazat.
2. `src/pages/RouteModal.jsx`: pole name/description/type/distance/duration, waypointy (editor bodů — lat/lng nebo výběr na mapě), POI (přidávání s obrázky), galerie přes `ImageUploader` (`folder={`routes/${routeId}`}`), `mapy_url`.
3. (nice-to-have) náhled trasy na mapě ve velíně přes Mapy statickou/rastrovou mapu.
4. Sidebar + App.jsx nový záznam „Trasy".
5. Audit log + `autoTranslateRow` po uložení.

### Etapa C — Flutter app (dolní panel + obrazovky)
1. **app_shell.dart**: nahradit `_TabItem` Shop za `_TabItem(route: Routes.routes, i18nKey:'navRoutes', icon: Icons.route_outlined/map)` a upravit `_currentIndex()`.
2. **profile_screen.dart**: přidat `ProfileMenuItem` „E-shop" → `context.push(Routes.shop)` (např. do nové sekce nebo k „Pomoc a podpora"/„Ostatní").
3. **router.dart**: přidat `Routes.routes = '/routes'`, route na seznam tras + `'/routes/:id'` na detail. Shop routy zůstávají (jen už nejsou v tabu).
4. **Nové feature složky** `lib/features/routes/`:
   - `routes_provider.dart` (Riverpod, načítá trasy dle pobočky),
   - `routes_screen.dart` (výběr pobočky + seznam tras, řazení dle km, karty s cover image),
   - `route_detail_screen.dart` (mapa s polyline + POI, galerie, popis, tlačítka „Zobrazit v appce" / „Zvolit → otevřít v Mapy.cz/Google/Waze"),
   - `route_map.dart` (flutter_map + Mapy dlaždice + polyline + markery),
   - `route_export.dart` (sestavení URL pro externí navigace, url_launcher).
5. **i18n**: nové klíče (`navRoutes`, nadpisy, tlačítka) do všech 7 jazyků v `translations*.dart`.

### Etapa D — Ověření
- Build appky (codemagic) / `flutter analyze`.
- Velín lint/build.
- Ruční ověření CRUD ve velíně + zobrazení v appce.

---

## 6. Rozhodnutí (potvrzeno uživatelem 2026-06-21)
1. **Zdroj geometrie trasy** → ✅ **Waypointy + Mapy routing API** (geometrie se cachuje do `routes.geometry`).
2. **Zobrazení mapy v appce** → ✅ **`flutter_map` + Mapy.com dlaždice** (polyline + markery POI, nativní zoom/posun).
3. **Cílové externí aplikace pro „Zvolit"** → ✅ **Apple Maps + Google Maps** (volba dle platformy; Mapy.cz/Waze vynecháno).
4. **POI model** → ✅ **Samostatná tabulka `route_pois`** (obrázky a překlady per-POI).

---

## 7. Rizika / poznámky
- Mapy API rate-limit a podmínky užití klíče (free tier) — u tras se volá routing per zobrazení; proto **cachovat geometrii** v DB.
- Waze přes URL neumí multi-stop → realisticky jen start+cíl, ČR uživatel ideálně Mapy.cz.
- Pravidlo CLAUDE.md: neměnit UX/flow nad rámec zadání; SQL nejdřív do chatu; po SQL aktualizovat STATE soubory.
</content>
</invoke>
