# Záznam jízd — SQL balíček: přehled pro majitele

Stav 22. 10. 2026. Jsou to jen **návrhy** ve složce `scratchpad/rides/sql/`. Nic není v gitu, v `supabase/migrations` ani na živé databázi. Do `main` jdou až po tvém schválení a spolu s Velínem.

## Co to přinese (jednou větou)

Server přestane dělit cestu přes noc, pozná pauzu a chůzi, spočítá rozumné statistiky po dnech (etapách) a umí sloučit víc jízd do jedné cesty. Starší appka 4.1.3 přitom funguje beze změny.

## Soubory

| Pořadí | Soubor | Název při commitu |
|---|---|---|
| 1 | `01_rides_columns.sql` | `20261023_user_rides_pause_a.sql` |
| 2 | `02_rides_stats_core.sql` | `…_pause_b.sql` |
| 3 | `03a_rides_append.sql` | `…_pause_c.sql` |
| 4 | `03b_rides_finish.sql` | `…_pause_d.sql` |
| 5 | `04_rides_start_cron.sql` | `…_pause_e.sql` |
| 6 | `05_rides_trip_group.sql` | `…_pause_f.sql` |
| 7 | `06_rides_backfill.sql` | `…_pause_g.sql` — **volitelné, rozhoduješ ty** |

- Datum v názvu musí řadit za všechno, co už je v `main`. Dnes je poslední `20261022b_live_viewers.sql`.
- Každý soubor jde do databáze v jedné transakci. Když selže, nezapíše se nic.
- Druhé spuštění téhož souboru nic nezmění (soubory jsou idempotentní).
- Původně měl být soubor 03 jeden. Rozdělil jsem ho na `03a` a `03b`, aby nepřesáhl limit ~5 000 tokenů na soubor.

---

### 1) `01_rides_columns.sql` — nové sloupce a příznak
**Co dělá**
- Do tabulky jízd přidá sloupce:
  - `pause_sec`: čas pauz;
  - `pause_aware`: jízdu vede nová appka, která pauzuje sama;
  - `stats_state`: interní mezivýpočet;
  - `stages`: etapy, tedy dny;
  - `trip_id` a `trip_name`: sloučená cesta.
- Přidá omezení: název cesty má nejvýš 120 znaků.
- Přidá index a české popisky sloupců.
- Založí příznak `ride_autopause`: zapnuto, prahy 5 min stání, 3 min chůze, rozjezd 20 km/h.

**Riziko:** minimální. Jen přidává, nic nemaže. Přidání sloupců s výchozí hodnotou je v Postgresu okamžité. Pokud příznak už existuje, nepřepíše se.

**Staré appky:** nové sloupce nečtou, takže se pro ně nic nemění.

### 2) `02_rides_stats_core.sql` — nový výpočet statistik
**Co dělá:** přidá interní funkce `_ride_stats_v2`, `_ride_prague_night` a `_ride_stage_days`. Výpočet:

| Údaj | Jak se nově počítá |
|---|---|
| Pauza | bod se značkou od appky; nebo ticho ≥ 5 min, kterým se neprojelo (noc, jezero) |
| Bez signálu | jen ticho, kterým se projelo ≥ 15 km/h |
| Jízda | jen s rychlostí z GPS (Doppler) ≥ 7 km/h; chůze ani „bloudění“ polohy v pokoji nepřidají km ani čas |
| Maximum | jen z GPS rychlosti s kontrolou věrohodnosti |
| Nastoupáno | vyhlazené: šum na rovině se nepřičítá a pozvolné stoupání se neztrácí |
| Etapy | den = pauza ≥ 6 h nebo ≥ 30 min přes 00:00–05:00 (Praha); nejvýš 60 etap |
| Stará appka | stání nebo chůze ≥ 5 min se zpětně změní v pauzu a body uvnitř zmizí z mapy |

- `_ride_stats` (původní podpis) teď počítá přes nový výpočet.
- `_ride_track_cap` (prořídnutí stopy) nově ředí rovnoměrně podle vzdálenosti. Značky pauz a okraje mezer vždy zůstanou. Na 12 000 bodů trvá ~40 ms.

**Riziko:** nízké. Funkce jsou interní a klient je nevolá. Hlavní riziko je jiné chování statistik, viz testy níže.

**Staré appky:** dostanou rozumnější čísla. Chůze se do km nepočítá, noc je pauza, ne „stání“.

### 3) `03a_rides_append.sql` — příjem bodů
**Co dělá:** `append_ride_track` má stejný podpis i odpovědi a žádný nový chybový kód. Navíc:
- **Opakovaná dávka** (telefon nedostal odpověď a pošle ji znovu) se nezapočítá dvakrát. Dřív se km zdvojily.
- **Body po vrácení výpůjčky** (nová appka +30 s, stará +2 min rezerva na hodiny) se nepřijmou. Pokud dávka obsahuje jen takové body, jízda se uzavře k času vrácení. Tím zmizí km autem po vrácení i prázdné jízdy navíc.
- **„Připraveno“:** výpůjčka i ruční záznam začnou až rozjezdem, ne v okamžiku podpisu nebo klepnutí.
- Strop stopy roste s počtem dní: 4 000 bodů + 2 000 za každý další den, nejvýš 12 000.
- Rychlost, kterou posílá appka sama, se ignoruje. Maximum se počítá z bodů.

**Riziko:** střední, je to hlavní cesta dat.
- Pokryto testy včetně opakování dávky a stavu po vrácení.
- Uložení dávky trvá ~3 ms při 4 000 bodech a ~17 ms při 12 000 bodech (dřív ~3 ms).

**Staré appky:**
- Volání i kódy beze změny. Po vrácení dostanou `ride_finished`, kterému rozumějí („zapomeň“).
- Známé omezení: když si někdo na telefonu se 4.1.3 vrátí hodiny dozadu, body starší než poslední uložený se zahodí, dokud hodiny „nedoženou“. Je to vzácné.

### 4) `03b_rides_finish.sql` — ukončení a čtení jízd
**Co dělá**
- `finish_user_ride` a `_ride_finalize`:
  - jízda končí nejpozději 2 min po posledním bodu, takže Stop zmáčknutý o 2,5 h později už nepřidá 2,5 h stání;
  - `duration_min` je **na cestě bez pauz**;
  - zastávky jsou vždy zbytek;
  - vícedenní jízda dostane název s rozsahem dat (`14.10.–16.10.2026`);
  - odpověď má navíc `pause_sec` a `days`.
- U staré appky se odřízne ocas chůze na konci, pokud trval ≥ 5 min.
- Výpis jízd (`_ride_json`) má navíc `pause_sec`, `pause_aware`, `trip_id`, `trip_name` a `stages`.

**Riziko:** nízké až střední.
- „Na cestě“ teď znamená něco jiného. Jinak je to stejné jako dřív, včetně mazání jízd pod 1 km.
- Vícedenní cesta s 12 000 body znamená ~0,5 MB dat ve výpisu „Moje jízdy“ (dřív max ~0,2 MB na jízdu).

**Staré appky:** dostanou stejné klíče. „Celkový čas“ jim ukáže čas bez pauz, takže už žádných „167 h“.

### 5) `04_rides_start_cron.sql` — start, obnova, úklid
**Co dělá**
- **Nové RPC `start_user_trip`**, jen pro novou appku:
  - založí nebo převezme jízdu;
  - pro výpůjčku jen převzatou a nevrácenou, jinak `booking_inactive` a nic nevznikne;
  - ruční jízda se už nepáruje s výpůjčkou podle data;
  - vrací serverový čas, aby appka srovnala hodiny telefonu;
  - když se dva starty potkají naráz, oba skončí u stejné jízdy (otestováno).
- **`start_user_ride`** (4.1.3) má stejný podpis. Mění se jen obnova rozjeté jízdy:
  - výpůjčka se obnoví v jakémkoli stáří;
  - vlastní cesta nové appky do 72 h;
  - jinak 3 h jako dřív.
- **Úklid `close_stale_user_rides`** (každých 15 min), kdy uzavře jízdu:
  - **výpůjčka:** jen koncem výpůjčky (vrácení +10 min, storno nebo dokončení, 2 dny po konci, 60 dní), a to k času vrácení;
  - **vlastní cesta nové appky:** po 72 h bez jízdy nebo po 30 dnech;
  - **vlastní jízda 4.1.3:** beze změny po 3 h nebo 36 h.
- **Velín „Mapa a poloha“** dostane `is_standing`: motorka stojí 15+ min a výpůjčka běží. Velín pak napíše „stojí od …“ místo „Záznam visí“.

**Riziko:** střední, je to změna pravidel uzavírání.
- Výpůjčka zůstane otevřená přes noc. To je cíl. Uzavře se nejpozději 2 dny po konci výpůjčky.
- Ruční jízda ze 4.1.3 v den výpůjčky se páruje s výpůjčkou podle data, a to beze změny. Nově ale proto zůstane otevřená do konce výpůjčky, ne jen 3 h.
- **Velín je potřeba nasadit současně**, jinak pozastavená výpůjčka po 3 h ukáže „Záznam visí“.

**Staré appky:**
- 4.1.3 při výpůjčce už nedostane novou jízdu každé ráno. Jede dál do jedné.
- Vlastní jízdy 4.1.3 se uzavírají jako dosud.

### 6) `05_rides_trip_group.sql` — slučování jízd do cesty
**Co dělá**
- Nové RPC `set_user_rides_trip` jen zapisuje k vlastním jízdám skupinu `trip_id` a název `trip_name`.
- Sloučení, rozdělení, přejmenování i „Zpět“ skládá appka.
- Na jízdy, body, fotky ani statistiky nesahá.
- Cizí nebo neexistující jízdy přeskočí a vrátí, kolik jízd opravdu upravilo.

**Riziko:** minimální. Mění jen dva sloupce a jen u vlastních jízd volajícího.

**Staré appky:** RPC nevolají. Sloučení nevidí, jízdy dál ukazují samostatně.

### 7) `06_rides_backfill.sql` — přepočet starých jízd (VOLITELNÉ)
**Co dělá**
- U uzavřených jízd ze starých appek přesune noci a dlouhá stání (ticho ≥ 5 min bez projetí) z „celkového času“ a „stání“ do pauz.
- Km, čas jízdy, maximum ani stoupání nemění. Nic nemaže.
- Ticho, které staré statistiky braly jako „bez signálu“ (posun > 300 m, ale < 15 km/h), převede na pauzu jen u stopy, která nikdy nebyla prořídnutá (< 2 000 bodů). U prořídnuté stopy to bezpečně odlišit nejde.
- Pauza nikdy nepřesáhne čas, který nepokrývá jízda a mezery.

**Riziko:** nízké.
- Je jednorázový a idempotentní: přepočtená jízda dostane značku a podruhé se nepočítá.
- Sahá jen na `pause_sec`, `gap_sec`, `idle_sec` a `duration_min` uzavřených starých jízd.
- Mění `updated_at` těchto jízd.

**Staré appky:** uvidí u starých jízd menší „celkový čas“, protože bez nocí.

---

## Jak jsem to ověřil (čísla)

Lokální PostgreSQL 16 se živým schématem (snapshot `df555c93`). Pokaždé čistý cluster, nic se nespouštělo proti živé databázi.

**SQL testy** (`test_rides.sql`, spouští `run_tests.sh`)
- Všech 7 souborů aplikováno **2×** bez chyby (~0,3 s).
- Testy proběhly **2× za sebou: 168/168 kontrol OK** (každý běh ~4 s). Zahrnují:
  - 15 výpočetních vektorů ze zadání + strop 60 etap;
  - vlastní jízdu (připraveno, opakovaná dávka, značka pauzy = 3 600 s, pozdní Stop = konec +120 s, „na cestě“ 6 min);
  - 3denní cestu s nočním úklidem (= 1 jízda, 3 etapy, 3 dny, název `14.10.–16.10.2026`);
  - výpůjčku (body po vrácení → uzavřeno k času vrácení, žádná nová jízda);
  - appku 4.1.3 (chůze 576 s = pauza, km bez chůze, ocas chůze odříznut, jen staré chybové kódy, rezerva 2 min);
  - úklid (6 případů + kontrolní hraniční případy);
  - převzetí, 72 h, 20 h výpůjčka u 4.1.3;
  - slučování (sloučit / zpět / rozdělit / cizí jízda / 6 špatných vstupů / bez přihlášení);
  - prořídnutí: 30 000 bodů → ≤ 12 000, všechny značky i okraje mezer zůstaly, starší dny rovnoměrně; 12 000 bodů za 37–40 ms;
  - práva: anon nic, authenticated nevolá interní funkce;
  - přepočet historie (noc 10 h → pauza, skutečná mezera beze změny, otevřené a nové jízdy nedotčené).
- Souběžné dva starty: druhý dostal tutéž jízdu (`resumed`), otevřená je 1.
- Podpisy všech existujících funkcí jízd **beze změny**. Přibylo jen 6 nových názvů a **0 přetížení**.

**Přehrávky reálných scénářů:** simulovaný jezdec s GPS šumem, nocemi v hotelu, chůzí a autem přes skutečné RPC. Výsledek **56 ze 57 cílů**.

| Scénář | Dnes | Nově |
|---|---|---|
| Den s přestávkami (331,7 km) | na cestě 412 min, z toho 116 min „stání“ | 331,0 km · na cestě 313 min · pauzy 96 min zvlášť · v sedle 294 min · stání 19 min |
| 2 dny vlastní, noc bez signálu (588,3 km) | 385,8 km, 2. den ztracen | 587,5 km · 1 jízda · 2 etapy · noc = pauza |
| Totéž, poloha v pokoji „bloudí“ | 795 min stání + fantomové km | 586,3 km · stání 25 min · 0 fantomových km |
| 7denní cesta (2 537 km) | 334 km | 2 532,5 km · 1 jízda · 7 etap / 7 dní; s „bloudící“ polohou 2 523 / 2 528 km |
| Výpůjčka 2 a 3 dny | 2–3 jízdy | 1 jízda |
| Appka zabitá přes noc | rozdělená cesta | 1 jízda, noc = pauza |
| Vrácení a hned autem (201,7 km) | 218,4 km, max 104 autem | 201,3 km, max 97,3 |
| 40 min pěšky | Ø 59,4 | Ø 76,4 (pravda 78,1); km 150,7 / 151,0 |
| 3,5 h u jezera | odpoledne ztraceno | 235,0 / 235,3 km · 1 pauza 216 min |
| Stop o 2,5 h později | +154 min stání | konec = příjezd + 2 min |

**Appka 4.1.3 proti novému serveru**
- Chůze vyloučena: 369,5 km / 370,1 km.
- Výpůjčka 2 dny = **1 jízda** (dřív 2). Ráno se nahrálo i to, co dřív chybělo, protože jízdu už nezavírá noční úklid.
- 3 noci s „bloudící“ polohou = 1 jízda, 836,5 / 837,8 km, bez fantomových km.
- Vlastní jízda přes noc se uzavírá stejně jako dnes (regresní test S11).

**Nová appka proti starému serveru** (před nasazením SQL)
- Noc se dál dělí na 2 jízdy, ale záznam nikdy tiše neskončí: součet 588,2 / 588,3 km.
- Chybné hodiny telefonu −2 h i +7 h: uloženo správně (331,0 km).

**Jediný nesplněný cíl: nastoupáno u dne s krátkými vlnkami terénu**
- Výsledek je 82 % skutečnosti, cíl byl 85 %. Dnes je to 34 %.
- U vícedenních cest vychází 85 %.
- Důvod: práh 6 m schválně ignoruje vlnky do ±8 m, protože jinak by se na rovině přičítal šum GPS.
- Citlivější nastavení (vyhlazení 0,3) dá ~87 %, ale na rovině by šum přičetl až ~300 m na 100 km místo dnešních ~190 m. Nechal jsem hodnoty ze zadání (0,25 / 6 m). Změnit to je tvoje volba.

## Co rozhoduješ ty
1. **Přepočet historie (`06`, název `_g`)**: ano nebo ne.
2. **Prahy** (5 min stání, 3 min chůze, 20 km/h, uzavření vlastní cesty po 72 h). Prahy pro telefon jdou měnit i později bez vydání appky (příznak `ride_autopause`).
3. **„Na cestě“ = čas bez pauz** v appce i ve Velínu.
4. **Nasazení:** SQL a Velín musí jít do `main` spolu.

## Odchylky od zadání (`SPEC.md`), které jsem zvolil
- **Rezerva po vrácení:** pro novou appku je 30 s místo 120 s. Při 120 s se do jízdy dostala 1 km jízdy autem a max 104 km/h. Pro 4.1.3 zůstává 120 s kvůli nesrovnaným hodinám.
- **Stará appka:**
  - do běhu stání se počítá i ticho bez projetí (3–5 min i ≥ 5 min), takže noc je jedna pauza, ne několik kousků;
  - GPS skok běh stání nepřeruší.
- **Vyhlazení výšky** začíná od výšky předchozího bodu. Vektor V15 tak dá 54 m podle zadání.
- **„Připraveno“** posune start jen tehdy, když část dávky před značkou má < 60 s jízdy a < 0,2 km. Skutečnou jízdu tak nikdy nezahodí.
- **Jízda rozjetá před nasazením** dostane dosavadní část jako 1. etapu.
- **`start_user_trip`** u už převzaté jízdy neposouvá `updated_at`. Jinak by každé otevření appky oddálilo uzavření po 72 h.
- **`finish_user_ride` u uzavřené jízdy** dál umí přejmenovat, stejně jako dnes.
- **Nové pomocné funkce:** `_ride_stage_days` (počet dní), `_ride_stats` je nyní STABLE SECURITY DEFINER.

## Soubory k použití dál
- **Pro appku (T2):** `stats_vectors.json`, 16 vektorů se spočtenými hodnotami pro test parity.
- **Pro dokumentaci (STATE):** `../STATE_PATCH.md` s přesnými úpravami STATE_1–6, použij v commitu s SQL.
- **Testy:**
  - `run_tests.sh` + `test_rides.sql`;
  - přehrávky `../pg/sim/replay_new.py` (+ `client2.py`, `../pg/make_old_db.sh`);
  - výstupy ve složce `out/`.
- **Testovací cluster:** `/var/tmp/pg-rides` (~1,2 GB). Až nebude potřeba, smazat.
