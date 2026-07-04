# Analýza tras a bodů zájmu — proč to na mapě vypadá bizárně

> Analýza 2026-07-04 · 30 seed souborů (`20260701_seed_recommended_routes_1/2.sql` + `20260703_seed_routes_*.sql`) · **384 tras · 2 196 bodů zájmu**.
> Kód mapy v appce (`route_map.dart`) je v pořádku — markery jsou centrované kruhy, polyline se kreslí správně. **Všechny problémy jsou v datech seedů + v logice startu u zahraničních tras.**

## Jak appka mapu staví (podstata problému)

Appka kreslí zelenou čáru **jen z `routes.waypoints`** (routing Mapy.com přes tyto body, `geometry` je cache). Body zájmu (`route_pois`) do routingu **nevstupují** — jsou to jen markery. Když tedy waypointy nevedou kolem bodů zájmu, markery „plavou" daleko od čáry. Přesně to je vidět na screenshotu trasy **Papuk a Slavonie**.

## Rozbor screenshotu: Papuk a Slavonie (HR)

| Problém | Detail |
|---|---|
| Čára ≠ popis | Waypointy jsou jen **4**: Požega → Velika → Kutjevo → Požega. Vzdušně 49 km (po silnici ~70 km), ale karta tvrdí **190 km / 4 h**. Nakreslený trojúhelník vůbec nevede „lesnatým pohořím Papuk". |
| POI mimo trasu | 3 z 5 bodů (Geopark Papuk, Ružica grad, Jezero Jankovac) leží **7–13 km severně od čáry** v horách, kudy waypointy nevedou. |
| Slité markery | Geopark Papuk (45.53, 17.68) a Jezero Jankovac (45.53, 17.69) jsou od sebe **780 m** → na mapě markery 1+5 přes sebe (na fotce hrbol „4/5"). |
| Špatná souřadnice | „Zřícenina Ružica grad" je seedovaná na (45.52, 17.72) = prostředek lesa; reálně stojí u Orahovice (~45.524, 17.851) — **~10 km vedle**. |
| Start: MotoGo24 Mezná | Chorvatská trasa má `branch_id` = Mezná (viz níže) → detail ukazuje „Start: MotoGo24 Mezná" a navigace/export plánuje trasu **z Vysočiny do Slavonie a zpět (~1 500 km)**. |

## Systémové nálezy (celý dataset)

### 1) Trasy nakreslené „do trojúhelníku" — deklarované km nesedí s waypointy
**92 tras** má deklarovanou `distance_km` větší než 2,2× vzdušnou délku waypointů (reálný silniční faktor je ~1,3×). Nejhorší: Veliko Tarnovo (BG) 16,6×, Rilský klášter (BG) 13×, Velehrad a Buchlovské kopce 12×, Biokovo (HR) 9×, Slapy 7,4×, Kokořínsko 6,3×, Brno a Veveří 5×, **Papuk 3,9×**. U 5 tras je to naopak (waypointy delší než deklarace — Kurská kosa, Silvretta, Žďárské vrchy, 2× Portugalsko).

Rozdíl mezi dávkami je zásadní:

| Dávka | Tras | POI | ≤3 unikátní waypointy | km >2,2× vzdušné délky | POI >5 km od čáry | POI dvojice <300 m |
|---|---|---|---|---|---|---|
| 20260701 (původních 105) | 105 | 893 | **0** | 14 | 5 (max 26 km) | 68 |
| 20260703 (nové státní seedy) | 279 | 1 303 | **64** | **73** | **53 (max 49 km)** | 75 |

Původní dávka vedla waypointy přes všechny POI (5–7 wp). Nové státní seedy mají šablonovitě **start + 2 zastávky + návrat**, zatímco POI je 5 — proto se to rozpadá.

### 2) POI daleko od nakreslené trasy — 36 bodů >8 km (výběr nejhorších)
```
49 km  [dk] Divoké západní pobřeží Jutska → Bovbjerg Fyr
41 km  [dk] Skagen a špička Jutska → Maják Rubjerg Knude
27 km  [bg] Sozopol a jižní Černomoří → Nesebar
26 km  [hr] Chorvatské Zagorje a hrady → Marija Bistrica (46.0, 16.11 — navíc zaokrouhlená souřadnice, reálně 45.94)
26 km  [SE, dávka 1] Vildmarksvägen → Restaurace Marsfjäll Mountain Lodge
24 km  [RO, dávka 1] Transfăgărășan → Bistro Subcarpați (Curtea de Argeș)
16 km  [hr] Lika a hrad Sokolac → Hrad Sokolac (45.0, 15.13 — hrad, podle kterého se trasa jmenuje, je mimo čáru)
12 km  [cz_stredni_cechy] Brdy a Příbramsko → Zámek Mníšek pod Brdy
11 km  [cz_stredni_cechy] Kokořínsko → Zámek Mělník a soutok
10 km  [cz_jizni_morava] Slavkovské bojiště → Ždánický les
10 km  [cz_stredni_cechy] Křivoklátské lesy → Zbiroh – zámek
```
Kompletní seznam: skript `analyze_routes.py` (viz konec dokumentu).

### 3) Markery přes sebe — 277 dvojic <1,2 km, z toho ~70 <100 m
- **Legitimní část:** restaurace u památky (Telč zámek × Gril u Osla apod.) — datově OK, ale na mapě se markery slijí; chtělo by to v appce mírný offset/spiderfy překrývajících se pinů.
- **Datové duplicity (stejné souřadnice, 0 m):** „Hradby Stonu" × „Solné pánve Ston"; „Skanzen Strážnice" × „Zámek Strážnice" × „Baťův kanál" (3 body na 1 souřadnici!); „Slunj" × „Zřícenina Frankopanského hradu"; „Kaňon Tary" × „Most Đurđevića"; „Solina přehrada" × „Zapora Solina"; „Trigrad" × „Ďáblovo hrdlo"; „Palác Balčik" × „Botanická zahrada Balčik" ad. — tady je vždy aspoň jedna souřadnice špatně (objekty reálně stejné místo nesdílejí).

### 4) Hrubé/zaokrouhlené souřadnice — 104 POI s ≤2 desetinnými místy (±0,5–1 km)
Nejvíc: HR 26, dávka 1+2 24, BG 13, DK 12, jižní Morava 12. Podezřelé „kulaté" hodnoty typu `45.0`, `46.0`, `42.66` = AI odhad, ne reálná souřadnice. Právě tyhle body sedí v lese/na poli místo na památce.

### 5) Zahraniční trasy mají branch = Mezná → nesmyslný start
Všechny seedy přiřazují `branch_id` nejbližší pobočce k Mezné. Důsledky v appce:
- Detail chorvatské trasy ukazuje **„Start: MotoGo24 Mezná"** (`routeStartsAt` + `branch.name`).
- `orderedRoutePoints()` předřadí GPS pobočky a u okruhu ji přidá i na konec → **„ZVOLIT TRASU – NAVIGOVAT" na zahraniční trase plánuje stovky km z Mezné a zpět**; totéž export GPX.
- Marker startu (vlaječka) leží u Mezné → auto-fit mapy u zahraniční trasy roztáhne výřez přes půl Evropy (dokud není `geometry` cache jen z waypointů).

## Doporučený postup opravy (bez zásahu do UX)

1. **Data (hlavní):** u 92 tras z bodu 1 doplnit waypointy tak, aby vedly přes všechny body zájmu (ideálně waypoints = start + POI v pořadí `sort_order` + návrat). Tím se srovná čára, kilometry i „plavající" markery najednou. Pak ve Velíně přegenerovat `geometry` cache.
2. **Souřadnice:** opravit 36 POI >8 km od trasy + 104 hrubých souřadnic (dohledat přesné, např. Ružica grad 45.524, 17.851; Marija Bistrica 45.941, 16.110). Duplicitní souřadnice z bodu 3 rozklíčovat.
3. **Appka — zahraniční trasy:** pokud je trasa dál než ~50 km od pobočky, neukazovat „Start: pobočka", neroutovat od pobočky a nenavigovat přes ni (start = první waypoint). Jde o malou úpravu v `routes_provider.dart` (`orderedRoutePoints`/`navPointsFrom`) + podmínku v `route_detail_screen.dart`.
4. **Appka — kosmetika:** drobný offset překrývajících se markerů (68+75 dvojic <300 m), jinak zůstanou „hrbolky" jako na screenshotu i po opravě dat.

Analytický skript s kompletními seznamy: session scratchpad `analyze_routes.py` + `report.txt` (A: 36 POI mimo trasu, B: 277 překryvů, C: 92 poměrů km, D: 104 hrubých souřadnic). Před opravami v DB nutno SQL odsouhlasit v chatu (pravidlo repa) — tento dokument žádná data nemění.
