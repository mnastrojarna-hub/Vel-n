# Analýza: body zájmu pro cílovku (muži 40–50) v trasách

> Analýza 2026-07-04 · dataset: 384 tras / 8 456 bodů na trasách (`route_pois`) + katalog `points_of_interest` 27 006 bodů (Wikidata import CZ/SK/PL/AT + EU).
> Zadání: v trasách chybí body pro hlavní cílovku — muže 40–50 let (letiště, vojenské areály, technika…). Tento dokument nic v DB nemění.

## 1. Současný stav — čísla

Rozložení bodů na trasách (dle názvu):

| Typ | Počet | Podíl |
|---|---|---|
| Hrady / zámky / zříceniny | 1 260 | 15 % |
| Církevní (kostely, kláštery, poutní) | 835 | 10 % |
| Voda (přehrady, jezera, vodopády) | 550 | 7 % |
| Příroda (NP, skály, jeskyně) | 441 | 5 % |
| Restaurace / gastro | 297 | 4 % |
| Rozhledny / vyhlídky / průsmyky | 248 | 3 % |
| Ostatní (obce, kombinace…) | 4 743 | 56 % |

Témata pro cílovku (název + popis, celý dataset tras):

| Téma | Bodů | Poznámka |
|---|---|---|
| Letiště / letectví | **5** | z toho reálně letecká 2 (Kbely, zámek Police) |
| Vojenská muzea / armáda | **~15** | Lešany, Darkovičky, pár EU |
| Bunkry / čs. opevnění | **~40** | hlavně Stachelberg (7 objektů), Hanička, Dobrošov, Josefov |
| Bojiště / WW2 / tanky | **~20** | většinou EU (Bastogne, Arnhem), CZ skoro nic |
| Závodní okruhy / moto muzea | **~10** | Mugello, Spa, Zandvoort — **žádný český okruh** |
| Studená válka / radary / rakety | **~3** | jen infocentra JE Dukovany/Temelín |
| Technika / doly / železnice | ~60 | Dlouhé Stráně ano, ale roztroušené |

**Dohromady tvrdá témata cílovky < 2 % bodů.** Převažují zámky, kostely a příroda — profil spíš „rodinný výlet / párový víkend" než 45letý chlap na motorce.

## 2. Druhý problém: co existuje, je špatně zařazené

- Katalog `points_of_interest` má jen kategorie `food/castle/lookout/water/sights/nature/other`. **Vojenská/technická/letecká kategorie neexistuje** — generátor `tools/generate_poi_batches.py` tyto Wikidata třídy vůbec nestahuje.
- Wikidata třída „pevnost" (Q57821) spadá do `castle` → bunkry Stachelbergu mají v appce ikonu 🏰 a šablonový popis *„Hrad či zámek v Česku — historická zastávka, která stojí za odbočku."* U pěchotního srubu to působí nedůvěryhodně.
- Appka (`poi_categories.dart`) nemá pro tato témata filtr — i kdyby body přibyly, uživatel je nenajde jinak než fulltextem.

## 3. Co cílovku (muži 40–50, CZ) reálně táhne — a co chybí

Generace, co zažila vojnu, MiGy a Škodovky. Osvědčené motorkářské cíle:

1. **Letectví** — letecká muzea (Kbely, Kunovice, Vyškov, Zruč u Plzně, Deštná, Koněšín); **sportovní letiště s restaurací u ranveje** (Točná, Zbraslavice, Sazená, Podhořany, Skuteč…) = klasické moto zastávky; vyhlídky u aktivních základen (Čáslav — Gripeny, Náměšť — vrtulníky, dny NATO Mošnov); **bývalá sovětská letiště** Ralsko-Hradčany a Milovice-Boží Dar (legendární cíle, veřejně přístupné).
2. **Čs. opevnění a studená válka** — tvrze Bouda, Hanička, Dobrošov, Stachelberg, Hůrka; Darkovičky, Šatov (pár už je, ale schované pod „hrad"); Atom Muzeum Javor 51 (Míšov, Brdy — bývalý sklad jaderných hlavic), radarová věž Ralsko, Muzeum studené války Rokycany, protiatomové kryty.
3. **Vojenská muzea a technika** — VTM Lešany (tanky, top cíl), Armádní muzeum Žižkov, Král. hradecko (Josefov), tankodrom Milovice (zážitkové jízdy).
4. **Bývalé vojenské prostory jako trasy** — Brdy (CHKO 2016, silnice po hranici), Ralsko, Milovice, okraje Doupova a Libavé (Bores?) — „jízda krajinou, kam se 30 let nesmělo" je sama o sobě story trasy.
5. **Motorismus** — Autodrom Most, Masarykův okruh Brno (vyhlídka + muzeum), Sosnová, Vysoké Mýto; moto muzea (Netvořice, Solnice, Šestajovice už v katalogu jsou); slavné moto srazy/motoresty.
6. **Průmysl a hornictví** — doly (Michal Ostrava, Landek, Příbram — Památník Vojna), Dlouhé Stráně (už je a funguje), vodní elektrárny, viadukty, úzkokolejky, JE infocentra (jsou).
7. **Pivovary** — jako prohlídka/nealko zastávka (Plzeň, Velké Popovice…) — v datech jen okrajově; na moto trase komunikovat opatrně (nealko degustace).

Totéž platí pro EU trasy: Normandie, linie Maginot, Overloon, Sinsheim/Speyer, Nürburgring, Red Bull Ring — v seedech téměř chybí.

## 4. Doporučený postup (bez zásahu do UX, jen data + filtr)

1. **Rozšířit kategorie `points_of_interest`** o `military` (🪖 vojenství a opevnění), `aviation` (✈️ letectví), `tech` (🏭 technika a průmysl), `moto` (🏁 motorismus). Dopad: ALTER CHECK constraintu, `poi_categories.dart` + i18n (7 jazyků) v obou Flutter balících, mapa `CAT` ve Velíně (`TrasyKatalogMist.jsx`), heuristická klíčová slova (bunkr/srub/opevnění/letiště/okruh…), reklasifikace existujících ~120 bodů (Stachelberg, Hanička… z `castle`).
2. **Rozšířit Wikidata generátor** o třídy: vojenské muzeum (Q2772772), letecké muzeum (Q2398990), bunkr (Q91122), letiště/aerodrom (Q62447), závodní okruh (Q1777138), důl/hornické muzeum, technická památka — pro CZ/SK/PL/AT/DE a dál.
3. **Kurátorovaná seed dávka** ~60–100 vlajkových bodů CZ/SK z bodu 3 (ověřené GPS + Commons fotky, 8 jazyků) — Wikidata u malých letišť a krytů nestačí.
4. **Zaplést do stávajících tras** — použít hotový mechanismus `tools/fill_route_poi_gaps.py` (katalogové body ≤ 7 km od čáry) po naplnění nových kategorií.
5. **Nové tematické trasy** (~10–15 CZ/SK): „Opevnění Orlických hor" (Bouda–Hanička–Dobrošov), „Sovětská stopa: Ralsko a Milovice", „Studená válka v Brdech" (Javor 51 + Padrťské rybníky), „Za Gripeny a labskou technikou", „Okruhy: Most–Sosnová", „Letecká jižní Morava" (Kunovice–Náměšť–Koněšín)… Generátor `tools/generate_routes_from_pois.py` už existuje.
6. **Marketing**: v popisech tras přidávat „chlapácké" háčky (technika, historie vojny, rychlost) — dnes jsou popisy laděné univerzálně turisticky.

## 5. Omezení a rizika

- **Aktivní vojenské areály a letecké základny NEseedovat jako cíl** — jen veřejné vyhlídky, muzea a dny otevřených dveří (vstup do areálu = trestný čin). U bývalých VVP jen veřejné silnice (části Ralska/Libavé mají režim vstupu).
- Malá letiště: zastávka = restaurace/vyhlídka u plotu, ne pojezdové dráhy.
- Pivovary komunikovat jako prohlídky (0,0 %), ne konzumaci — jsme půjčovna motorek.
- Sezónnost bunkrů/muzeí (často jen víkendy IV–X) — hodí se zmínit v popisu bodu.

## 6. Pracnost (hrubý odhad)

| Krok | Rozsah |
|---|---|
| Kategorie (DB CHECK + appka + Velín + i18n) | 1 menší PR |
| Reklasifikace existujících bodů | 1 SQL (do chatu dle pravidel) |
| Generátor + import Wikidata dávek | 1 PR + spuštění s internetem |
| Kurátorovaná dávka 60–100 bodů | 1 SQL dávka |
| Doplnění do tras + nové tematické trasy | reuse existujících toolů |

Analytický skript: session scratchpad `analyze_target_pois.py`.

---

## PROVEDENO (2026-07-04, větev `claude/target-demographic-analysis-sqbwp9`)

Body 1, 2 a 5 z doporučení realizovány, celoevropsky:

1. **Kategorie** `military` 🪖 / `aviation` ✈️ / `tech` 🏭 / `moto` 🏁 — DB migrace
   `20260706_poi_categories_cilovka.sql` (CHECK + reklasifikace bunkrů z castle),
   appka (oba balíky: chips, heuristika, i18n 7 jazyků), Velín (CAT + zdroj filtru).
2. **+10 214 bodů** z Wikidata pro 24 zemí: aviation 3 717, tech 3 081, military 1 723,
   moto 903, lookout 790 (`20260706_poi_catalog_cilovka*_batch*.sql`; dedup, ověřené
   GPS/fotky/8 jazyků, vyřazeno 295 aktivních vojenských základen). Katalog po nasazení
   ~37 000 bodů.
3. **+200 tras** kotvených na bodech cílovky (military 60, aviation 50, tech 50,
   moto 40; 22 zemí, 25–260 km) — `20260706_routes_from_catalog_cilovka_batch1..4.sql`,
   skryté (`is_active=false`), publikace po kontrole ve Velíně.

Nerealizováno (další vlna): kurátorovaná CZ/SK dávka malých letišť s restauracemi
a krytů studené války (bod 4.3), doplnění bodů do STÁVAJÍCÍCH tras (4.4), ručně
laděné tematické trasy CZ/SK (4.5).
