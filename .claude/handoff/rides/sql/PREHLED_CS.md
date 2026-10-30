# Záznam jízd — SQL balíček: přehled pro majitele

Stav 30. 10. 2026 (kolo 3: vrácení na kiosku před posledním dnem, start bez dat, shodné popisky statistik, přepočet historie součástí balíčku). Soubory jsou připravené ve složce `scratchpad/rides/sql/` (kopie pro předání v `.claude/handoff/rides/sql/`). V `supabase/migrations` ani na živé databázi zatím nic není. Do `main` jdou spolu s Velínem a appkou; zapsání do `supabase/migrations` je zároveň nasazení (autodeploy).

## Co to přinese (jednou větou)

Server přestane dělit cestu přes noc, pozná pauzu a chůzi, spočítá rozumné statistiky po dnech (etapách) a umí sloučit víc jízd do jedné cesty. Výpůjčku jen oblečení nebere jako jízdu na motorce a neztratí poslední den výpůjčky, když byl telefon offline. Neztratí ani vícedenní cestu v cizině bez mobilních dat (roaming vypnutý): cesta pokračuje v jednom záznamu, i když telefon dny neposílal nic. Když zákazník vrátí motorku na kiosku o den dřív (kiosk ji jen „zaparkuje“), cesta autem domů se do jízdy nezapočte; a když motorku přes noc nechá v kóji a ráno pokračuje, zůstane to jedna jízda. Záznam spuštěný bez dat se uloží celý, i kdyby se telefon připojil až po vrácení. Starší appka 4.1.3 přitom funguje beze změny.

## Soubory

| Pořadí | Soubor | Název při commitu |
|---|---|---|
| 1 | `01_rides_columns.sql` | `20261029_user_rides_pause_a.sql` |
| 2 | `02_rides_stats_core.sql` | `…_pause_b.sql` |
| 3 | `03a_rides_append.sql` | `…_pause_c.sql` |
| 4 | `03b_rides_finish.sql` | `…_pause_d.sql` |
| 5 | `03c_rides_append_finish.sql` | `…_pause_e.sql` |
| 6 | `04_rides_start_cron.sql` | `…_pause_f.sql` |
| 7 | `05_rides_trip_group.sql` | `…_pause_g.sql` |
| 8 | `06_rides_backfill.sql` | `…_pause_h.sql` — **součást balíčku** (rozhodnuto 30. 10., vratné jedním příkazem) |

- Datum v názvu musí řadit za všechno, co už je v `main`. Dnes je poslední `20261023f_faq_gear_rental.sql`. Dřívější návrh `20261023_…` by se řadil PŘED něj (podtržítko je v řazení před písmenem), proto `20261029_…`. Těsně před commitem se to ještě jednou ověří.
- Každý soubor jde do databáze v jedné transakci. Když selže, nezapíše se nic. Každý soubor potřebuje jen soubory před sebou, takže při chybě v kterémkoli dalším běží všechno dál po staru.
- Druhé spuštění téhož souboru nic nezmění (soubory jsou idempotentní).
- Soubor 03 je rozdělený na `03a`, `03b` a `03c`, aby nepřesáhl limit ~5 000 tokenů na soubor a aby žádný nezávisel na pozdějším.

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
- `_ride_track_cap` (prořídnutí stopy) nově ředí rovnoměrně podle vzdálenosti. Značky pauz a okraje mezer vždy zůstanou. Na 12 000 bodů trvá ~40 ms. Starý bod, který má místo čísla text, nic neshodí.

**Riziko:** nízké. Funkce jsou interní a klient je nevolá. Hlavní riziko je jiné chování statistik, viz testy níže.

**Staré appky:** dostanou rozumnější čísla. Chůze se do km nepočítá, noc je pauza, ne „stání“.

### 3) `03a_rides_append.sql` + `03c_rides_append_finish.sql` — příjem bodů
**Co dělá:** `append_ride_track` má stejný podpis i odpovědi a žádný nový chybový kód. Navíc:
- **Opakovaná dávka** (telefon nedostal odpověď a pošle ji znovu) se nezapočítá dvakrát. Dřív se km zdvojily.
- **Rozhozené hodiny:** jediný bod s časem z budoucnosti (třeba telefon se 4.1.3 na chvíli o rok napřed) už nezablokuje zbytek jízdy. V předchozím návrhu by se pak všechno další zahodilo jako „duplicita“. Čas po roce 2100 je vadný bod a nic neshodí.
- **Body po vrácení výpůjčky** (nová appka +30 s, stará +2 min rezerva na hodiny) se nepřijmou. Pokud dávka obsahuje jen takové body, jízda se uzavře k času vrácení. Tím zmizí km autem po vrácení i prázdné jízdy navíc. Platí jen pro výpůjčku motorky; vrácení oblečení jízdu neořízne.
- **Vrácení na kiosku před posledním dnem** (nové 30. 10.): kiosk takové vrácení jen „zaparkuje“ a rezervaci dokončí až den po konci (čas vrácení pak zapíše zpětně). Do té doby rezervace běží a appka by nahrávala cestu autem domů. Pro jízdu teď platí zavření kóje jako vrácení: body po něm se nepřijmou a jízda se uzavře. Když motorka z kóje znovu vyjede (zaparkovaná přes noc), vrácení se zruší a jízda pokračuje.
- **Telefon offline v den vrácení:** úklid jízdu po vrácení uzavře (bez bodů z posledního dne). Když se telefon připojí (i za pár hodin, nejvýš do 7 dní), body jízdy až do vrácení se do ní ještě uloží a jízda se přepočte: km, konec, název s rozsahem dat i bod „cíl“. Platí jen pro výpůjčku uzavřenou vrácením nebo úklidem, ne pro jízdu ukončenou tlačítkem Stop ani pro vlastní jízdu. Appka posílá velkou dávku po částech (nejvýš 2 000 bodů). Když server část do uzavřené výpůjčky uloží, appka pošle do téže jízdy i další části. Teprve potom záznam ukončí. Ověřeno s logikou appky: 331,2 km z 331,6 (dřív 150,6, celý druhý den chyběl). Dlouhý poslední den offline (přes 3 000 bodů): 447,3 km z 447,5. Před opravou appky to bylo 314,1 km, zbytek dávky po první části se zahodil.
- **Vlastní cesta bez mobilních dat déle než 72 h** (roaming vypnutý, cizina bez dat): úklid ji po 72 h bez kontaktu uzavře. Když se telefon připojí a pošle body novější než poslední uložený, cesta se **znovu otevře** a body z doby offline se do ní uloží. Appka dostane běžnou odpověď a nahrává dál do téže cesty, takže se nic nerozdělí ani neztratí. Platí jen pro vlastní cestu nové appky, kterou uzavřel úklid (ne Stop), do 30 dní od startu a jen tehdy, když jezdec mezitím nezačal jinou jízdu. Na 4.1.3 se to netýká.
- **„Připraveno“:** výpůjčka i ruční záznam začnou až rozjezdem, ne v okamžiku podpisu nebo klepnutí. Posun startu se týká jen opravdu prázdné jízdy (nejvýš první bod, bez mezer). Řídké body ze „škrceného“ GPS na pozadí se už nikdy nezahodí.
- Strop stopy roste s počtem dní: 4 000 bodů + 2 000 za každý další den, nejvýš 12 000.
- Rychlost, kterou posílá appka sama, se ignoruje. Maximum se počítá z bodů.

**Riziko:** střední, je to hlavní cesta dat.
- Pokryto testy včetně opakování dávky, stavu po vrácení, pozdních bodů, hodin z budoucnosti a řídkých bodů.
- Uložení dávky trvá ~3 ms při 4 000 bodech a ~17 ms při 12 000 bodech (dřív ~3 ms).
- Každá dávka přepisuje celou uloženou stopu. U vícedenní cesty s 8–12 tisíci body to dělá ~140–180 kB zápisu do databázového logu na dávku (dnes nejvýš ~50 kB). Za 7denní cestu je to zhruba 0,2–0,4 GB, v horším případě ~1 GB, tedy 2–3× víc než dnes. Při dnešním počtu jezdců to nevadí. Kdyby jezdců výrazně přibylo, jde snížit strop stopy (např. na 8 000 bodů) bez zásahu do appky.

**Staré appky:**
- Volání i kódy beze změny. Po vrácení dostanou `ride_finished`, kterému rozumějí („zapomeň“).
- Známé omezení: když si někdo na telefonu se 4.1.3 posune hodiny dozadu, body starší než poslední uložený se zahodí jako duplicita, dokud hodiny „nedoženou“. Hodiny napřed už nic neblokují.

### 4) `03b_rides_finish.sql` (+ `finish_user_ride` v `03c`) — ukončení a čtení jízd
**Co dělá**
- `finish_user_ride` a `_ride_finalize` (jádro je nová interní funkce `_ride_close`):
  - jízda končí nejpozději 2 min po posledním bodu, takže Stop zmáčknutý o 2,5 h později už nepřidá 2,5 h stání;
  - `duration_min` je **na cestě bez pauz**;
  - zastávky jsou vždy zbytek;
  - vícedenní jízda dostane název s rozsahem dat (`14.10.–16.10.2026`);
  - odpověď má navíc `pause_sec` a `days`;
  - server si u jízdy pamatuje, kdo ji uzavřel (Stop / vrácení / úklid / nový start). Podle toho pozná, kam ještě smí přijmout pozdní body;
  - Stop po dlouhé době bez dat pošle zbytek bodů i do cesty, kterou mezitím uzavřel úklid. Cesta se znovu otevře, body se uloží a pak se uzavře jako Stop;
  - bod „cíl“ se po znovuotevření posune na skutečný konec.
- U staré appky se odřízne ocas chůze na konci, pokud trval ≥ 5 min.
- **Vrácení zjištěné až po bodech** (nové 30. 10., např. kiosk byl chvíli offline a zavření kóje dorazilo po bodech cesty autem): při uzavření jízdy se body po vrácení ze stopy odstraní a km, čas jízdy, maximum, etapy i cíl se spočítají znovu. Dřív v takovém případě zůstalo 230,7 km (z toho 60 km autem) a maximum 91,5 km/h z auta.
- **„Na cestě“ nikdy kratší než čas v sedle** (pojistka; dřív šlo vidět 146 min na cestě a 182 min jízdy).
- Výpis jízd (`_ride_json`) má navíc `pause_sec`, `pause_aware`, `trip_id`, `trip_name`, `stages` a **`stats_v2`**: jestli čísla jízdy počítal nový výpočet (nahrávaná jízda, nebo jízda s novými statistikami / přepočtená). Appka i Velín podle toho shodně zvolí popisky. Stará jízda, kterou nový výpočet nikdy neviděl, má dál staré popisky („celkový čas“, „stání“), protože její čísla obsahují noci.
- **Veřejné jízdy** (`get_public_rides`) ukazují jen dokončené jízdy. Rozjetá jízda přepnutá na „veřejná“ by jinak prozradila, kde jezdec právě je a kde spí. Navíc se nevrací klíče, podle kterých by šlo spojit jízdy jednoho člověka. Zatím to nic nevolá, takže se nic viditelně nemění.

**Riziko:** nízké až střední.
- „Na cestě“ teď znamená něco jiného. Jinak je to stejné jako dřív, včetně mazání jízd pod 1 km.
- Vícedenní cesta s 12 000 body znamená ~0,5–0,7 MB dat ve výpisu „Moje jízdy“ (dřív max ~0,2 MB na jízdu). Kdo má několik dlouhých cest, stáhne při otevření „Mých jízd“ jednotky MB. Appka bere detail jízdy ze stejného výpisu, takže zmenšit to jde až s novým RPC pro detail.

**Staré appky:** dostanou stejné klíče. „Celkový čas“ jim ukáže čas bez pauz, takže už žádných „167 h“.

### 5) `04_rides_start_cron.sql` — start, obnova, úklid
**Co dělá**
- **Nové RPC `start_user_trip`**, jen pro novou appku:
  - založí nebo převezme jízdu;
  - pro výpůjčku motorky, která běží a není vrácená, jinak `booking_inactive` a nic nevznikne. Převzetí na pobočce hlídá appka, server kontroluje jen stav rezervace;
  - výpůjčka jen oblečení → `booking_inactive`: automatický záznam se nespustí, ruční se nahraje jako vlastní jízda;
  - ruční jízda se už nepáruje s výpůjčkou podle data;
  - vrací serverový čas, aby appka srovnala hodiny telefonu;
  - když se dva starty potkají naráz, oba skončí u stejné jízdy (otestováno).
- **Nové RPC `start_user_trip_from`** (nové 30. 10.), jen pro novou appku: totéž, ale pro záznam, který začal **bez dat** (zahraničí, vypnutý roaming). Appka pošle čas prvního bodu a jízda začne jím (nejvýš 7 dní zpět, u výpůjčky ne dřív než převzetí), takže body z hodin bez signálu se nezahodí jako „stará jízda“. Když se telefon poprvé připojí až po vrácení výpůjčky a jízda k ní ještě neexistuje, založí se zpětně: body do vrácení se uloží, po vrácení zahodí. Starý server funkci nezná a appka pak použije `start_user_trip`.
- **Kiosk:** výpůjčka zaparkovaná v kóji (vrácení před posledním dnem) se pro záznam bere jako vrácená: `start_user_trip` i `start_user_ride` (4.1.3) vrátí `booking_inactive` a nic nenahrávají. Když motorka ráno z kóje vyjede, **pokračuje stejná jízda** (znovu se otevře, noc je pauza). To platí jen pro jízdu, kterou uzavřel server, ne Stop jezdce.
- **`start_user_ride`** (4.1.3) má stejný podpis. Mění se obnova rozjeté jízdy:
  - výpůjčka se obnoví v jakémkoli stáří;
  - vlastní cesta nové appky do 72 h;
  - jinak 3 h jako dřív;
  - ruční jízda se podle data páruje jen s výpůjčkou motorky, nikdy s výpůjčkou oblečení. Dnes živá verze od 23. 10. páruje i s oblečením. Má-li zákazník obojí, dostane jízda motorku, takže ji Velín uvidí v „Mapě a poloze“;
  - 4.1.3 s id výpůjčky oblečení dostane `booking_inactive` a nenahrává, stejně jako bez výpůjčky.
- **Oprava dat:** jízdy, které 4.1.3 od 23. 10. spárovala s výpůjčkou oblečení, se odpojí a dál se chovají jako vlastní jízdy. Nic se nemaže.
- **Úklid `close_stale_user_rides`** (každých 15 min), kdy uzavře jízdu:
  - **výpůjčka motorky:** jen koncem výpůjčky (vrácení nebo zaparkování v kóji kiosku +10 min, storno nebo dokončení, 2 dny po konci, 60 dní), a to k času vrácení. Pozdní body z telefonu se do ní pak ještě přijmou (viz bod 3);
  - **jízda spárovaná s výpůjčkou oblečení:** jako vlastní jízda;
  - **vlastní cesta nové appky:** po 72 h bez jízdy nebo po 30 dnech. Když pak přijdou novější body, cesta se znovu otevře (viz bod 3);
  - **jízda pod 1 km** by se uzavřením smazala, a s ní i body, které telefon bez dat teprve pošle. Úklid ji proto zatím nechá otevřenou. Vrácenou výpůjčku motorky smaže až 7 dní po vrácení, vlastní cestu nové appky až po 30 dnech od startu. Typický případ: výpůjčka na den s vypnutými daty hned od převzetí. Dřív se smazala 10 minut po vrácení a telefon pak celý den neměl kam poslat;
  - **vlastní jízda 4.1.3:** beze změny po 3 h nebo 36 h.
- **Velín „Mapa a poloha“** dostane `is_standing`: motorka stojí 15+ min a výpůjčka běží (ne zaparkovaná v kóji). Velín pak napíše „stojí od …“ místo „Záznam visí“.

**Riziko:** střední, je to změna pravidel uzavírání.
- Výpůjčka zůstane otevřená přes noc. To je cíl. Uzavře se nejpozději 2 dny po konci výpůjčky.
- Ruční jízda ze 4.1.3 v den výpůjčky motorky se páruje s výpůjčkou podle data, a to beze změny. Nově ale proto zůstane otevřená do konce výpůjčky, ne jen 3 h. S výpůjčkou oblečení se už nepáruje vůbec.
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

### 7) `06_rides_backfill.sql` — přepočet starých jízd (SOUČÁST BALÍČKU)
**Rozhodnutí 30. 10.:** jde do commitu. Chceš rozumné statistiky i u starých jízd a schvalovací kolo nebude („udělej to a pak to vypřipomínkujeme“). Kdyby se ti výsledek nelíbil, vrátí se jedním příkazem (je v hlavičce souboru, v testu ověřený).

**Co dělá**
- U uzavřených jízd ze starých appek přesune noci a dlouhá stání z „celkového času“ a „stání“ do pauz. Nově i noc, kdy telefon se 4.1.3 dál posílal body z pokoje (každý „běh stání“ ≥ 5 min, stejné pravidlo jako u 4.1.3 po nasazení), nejen noc bez bodů.
- Km, čas jízdy, maximum ani stoupání nemění. Nic nemaže.
- Ticho, které staré statistiky braly jako „bez signálu“ (posun > 300 m, ale < 15 km/h), převede na pauzu jen u stopy, která nikdy nebyla prořídnutá (< 2 000 bodů). U prořídnuté stopy to bezpečně odlišit nejde.
- Pauza nikdy nepřesáhne čas, který nepokrývá jízda a mezery.

**Riziko:** nízké.
- Je jednorázový a idempotentní: přepočtená jízda dostane značku a podruhé se nepočítá.
- U každé jízdy si uloží původní hodnoty (`duration_min`, `idle_sec`, `gap_sec`). Jde ho tak vrátit jedním příkazem bez obnovy zálohy (příkaz je v hlavičce souboru a v testu ověřený).
- Sahá jen na `pause_sec`, `gap_sec`, `idle_sec` a `duration_min` uzavřených starých jízd.
- Mění `updated_at` těchto jízd.

**Staré appky:** uvidí u starých jízd menší „celkový čas“, protože bez nocí.

**Známá mez:** noc, kterou staré statistiky započítaly jako jízdu (poloha v budově „bloudila“ rychleji než 3 km/h), zůstane v čase jízdy. Opravit by to šlo jen přepočtem km, a ten jsem u historie nechtěl.

---

## Jak jsem to ověřil (čísla)

Lokální PostgreSQL 16 se živým schématem (snapshot `1871eba3` z 29. 10., už s výpůjčkami oblečení 20261023a–f). Pokaždé čistý cluster, nic se nespouštělo proti živé databázi.

**SQL testy** (`test_rides.sql`, spouští `run_tests.sh`)
- Všech 8 souborů aplikováno **2×** bez chyby (~0,4 s).
- Testy proběhly **2× za sebou: 307/307 kontrol OK** (každý běh ~5–8 s). Zahrnují:
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
  - přepočet historie (noc 10 h → pauza, skutečná mezera beze změny, otevřené a nové jízdy nedotčené, návrat na původní hodnoty);
  - telefon offline v den vrácení (pozdní body přes `append` i přes `finish`, opakování nic nepřidá; vlastní jízda a jízda ukončená Stopem pozdní body nepřijmou);
  - výpůjčka oblečení (4.1.3 ruční jízda se nespáruje, zavře se po 3 h, ráno se neobnoví; `start_user_trip` → `booking_inactive`; motorka + oblečení → motorka; Velín bez jízdy; stará spárovaná jízda se vrácením oblečení neořízne a odpojí se);
  - hodiny z budoucnosti a čas po roce 2100, řídká první část jízdy, veřejný výpis, textové souřadnice;
  - vlastní cestu 5 dní, z toho 4 bez dat. Úklid ji po 72 h uzavře. První dávka po připojení ji znovu otevře, druhá se uloží normálně a opakovaná se nezapočítá. Další úklid ji nezavře. Stop dá 1 jízdu se všemi km, název `23.10.–27.10.2026`, 5 dní a jeden bod „cíl“ na skutečném konci;
  - kdy se cesta znovu NEotevře: jezdec mezitím začal jinou jízdu, cestu ukončil Stopem, jde o jízdu ze 4.1.3, start je starší než 30 dní, dávka nese jen staré, opakované nebo budoucí body, nebo jízdu posílá cizí uživatel;
  - Stop s body z doby offline do cesty uzavřené úklidem;
  - **kiosk (kolo 3):** vrácení o den dřív a domů autem 120 km/h → auto se nepřijme, km a max jen z motorky; kiosk offline (auto už uložené) → úklid jízdu uzavře k zavření kóje, auto ořízne, „na cestě“ ≥ čas jízdy, cíl na posledním bodu motorky, Velín ji neukáže jako „stojí“; vrácení bez dokončení (nezaplaceno) + Stop doma → jen motorka; motorka přes noc v kóji a ráno ven → 1 jízda, 2 dny, noc = pauza (nová appka i 4.1.3); po Stopu jezdce se jízda neotevře; telefon offline před zaparkováním → pozdní body motorky se uloží, auto ne; ruční jízda 4.1.3 téhož dne se s zaparkovanou výpůjčkou nespáruje; vlastní jízda s hodinami telefonu napřed se při Stopu neořezává;
  - **start bez dat (kolo 3):** jízda začne prvním bodem (nic se nezahodí; bez nové funkce by se zahodilo 202 bodů), nesmyslné časy (10 dní zpět, NaN, budoucnost, 0) ořízne / ignoruje, ještě prázdnou převzatou jízdu posune, výpůjčka vrácená před prvním spojením se založí zpětně (body do vrácení ano, auto ne, úklid ji uzavře k vrácení, druhá stejná žádost nic nezaloží), ne pro výpůjčku vrácenou před víc než 7 dny ani stornovanou, zaparkovaná v kóji funguje stejně, start nikdy před převzetím;
  - **popisky (kolo 3):** `stats_v2` ve výpisu (přepočtená stará jízda ano, stará bez přepočtu ne, nahrávaná ano); přepočet noci se 600 body z pokoje → pauza 9 h 59 min, „na cestě“ 5 min; krátká zastávka 4 min zůstane zastávkou; kontrola přes všechny testovací jízdy: „na cestě“ ≥ čas jízdy + bez signálu;
  - jízdu pod 1 km. Vlastní cesta po 72 h nezmizí a body dorazí po 10 dnech. Prázdná se smaže po 30 dnech. Výpůjčka s vypnutými daty od převzetí po vrácení nezmizí; když telefon za 3 dny pošle oba dny, úklid ji uzavře se skutečnými km do vrácení. Prázdná výpůjčka se smaže 7 dní po vrácení.
- Oprava dat (odpojení jízd od výpůjček oblečení) ověřena na jízdě založené před aplikací.
- Volání RPC pod rolí `authenticated` (jako z appky) proběhlo bez chyby. Interní funkce jsou pro ni zakázané.
- Souběžné dva starty: druhý dostal tutéž jízdu (`resumed`), otevřená je 1.
- Souběh znovuotevření s jiným startem: dávka do uzavřené cesty počká na zámek a cestu neotevře. Odpověď je `ride_finished`, ne chyba. Otevřená zůstane jen ta nová jízda. Bez souběžné jízdy se stejná dávka cestu znovu otevře.
- Znovuotevření pod rolí `authenticated` (jako z appky) funguje. Interní `_ride_reopen` je pro ni zakázaná.
- Podpisy všech existujících funkcí jízd **beze změny**. Přibylo 15 nových názvů (z toho 12 interních; veřejné jen `start_user_trip`, `start_user_trip_from`, `set_user_rides_trip`) a **0 přetížení**.

**Přehrávky reálných scénářů:** simulovaný jezdec s GPS šumem, nocemi v hotelu, chůzí a autem přes skutečné RPC. Výsledek **56 ze 57 cílů**.

**Přehrávky se skutečnou logikou appky** (testovací sady C a D z ověřování 29. 10.): výpůjčka offline v den vrácení dřív ztratila celý 2. den (150,6 z 331,6 km), teď 331,2 km. Automatický start s výpůjčkou oblečení dřív nahrával „Výpůjčku“, teď nenahraje nic. Ostatní výsledky sad A–E se SQL změnami nezměnily. Zbylé nesplněné body těch sad jsou na straně appky a řeší se zvlášť.

**Kolo 2 (29. 10.), aktuální appka proti SQL před a po opravě:**

| Scénář | Před opravou | Nově |
|---|---|---|
| Vlastní cesta 4 dny bez mobilních dat (roaming) | 79,8 z 533,1 km, 2 jízdy, 453 km ztraceno | 532,3 / 533,1 km, 1 jízda |
| Výpůjčka na den, data vypnutá hned po převzetí, telefon online druhý den | 0 km, jízda smazaná | 180,7 / 180,9 km, 1 jízda, konec při vrácení |
| Appka zabitá v noci, jezdec jede dál po 4 dnech | 2 jízdy (140,2 + 70,1 km) | 1 cesta 210,3 km, 2 dny |
| Výpůjčka, poslední den offline (kontrola) | 331,2 km | 331,2 km beze změny |

- Sady B (7denní cesta, výpůjčka 3 dny, ruční pauza, restarty) a X6, X7, X16 dopadly stejně jako před opravou.
- Přehrávky reálných scénářů (vč. 4.1.3) dál splňují 56 z 57 cílů. Jediný nesplněný cíl je pořád nastoupáno.

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

**Kolo 3 (30. 10.), skutečná logika appky proti SQL:**

| Scénář | Před opravou | Nově |
|---|---|---|
| Vrácení na kiosku o den dřív, domů autem (motorka 170,7 km, auto 60 km) | 230,7 km, max 91,5 (auto), na cestě 146 min < jízda 182 min, Velín ukazuje motorku doma | 170,6 km, max 76,5 (motorka), na cestě ≥ jízda, poloha = kóje |
| Výpůjčka bez dat od převzetí, telefon online večer (výpůjčka běží) | body z doby bez dat zahozené | 187,9 / 188,0 km, 1 jízda |
| Totéž, vrácení na kiosku, online až druhý den | jízda nevznikla, vše ztraceno | 188,3 / 188,0 km, 1 jízda uzavřená při vrácení |

- Sady B (S4–S8), C (C4–C12), X (X6, X7, X15, X16, X18, X19c) a H: viz výsledek ověření v předávce.

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

## Co můžeš po nasazení připomínkovat
1. **Přepočet historie (`06`, název `_h`)**: jde do commitu (rozhodnuto 30. 10.). Je vratný: každá přepočtená jízda si nese původní hodnoty a vrátit to jde jedním příkazem.
2. **Prahy** (5 min stání, 3 min chůze, 20 km/h, uzavření vlastní cesty po 72 h). Prahy pro telefon jdou měnit i později bez vydání appky (příznak `ride_autopause`).
3. **„Na cestě“ = čas bez pauz** v appce i ve Velínu.
4. **Nasazení:** SQL, Velín a appka musí jít do `main` spolu.

## Odchylky od zadání (`SPEC.md`), které jsem zvolil
- **Znovuotevření vlastní cesty** (nové 29. 10., kolo 2): úklid po 72 h dál uzavírá, aby opuštěný záznam nevisel. Když ale pak přijdou novější body, cesta pokračuje jako jeden záznam. Hranice 30 dní od startu je stejná jako nejdelší cesta. Appka kvůli tomu nic měnit nemusí.
- **Jízda pod 1 km se nemaže hned** (nové 29. 10., kolo 2): výpůjčka čeká 7 dní po vrácení, vlastní cesta 30 dní od startu. Ve Velínu proto taková jízda po vrácení chvíli svítí jako „Záznam visí“. Text nápovědy „při dalším úklidu“ tam teď neplatí přesně, upraví se ve Velínu.
- **Pozdní body po uzavření výpůjčky** (nové 29. 10.): přijmou se jen do jízdy výpůjčky motorky uzavřené vrácením, úklidem nebo novým startem, jen do času vrácení (+ rezerva) a jen do 7 dní. Odpověď appce zůstává `ride_finished`.
- **Rezerva po vrácení:** pro novou appku je 30 s místo 120 s. Při 120 s se do jízdy dostala 1 km jízdy autem a max 104 km/h. Pro 4.1.3 zůstává 120 s kvůli nesrovnaným hodinám.
- **Stará appka:**
  - do běhu stání se počítá i ticho bez projetí (3–5 min i ≥ 5 min), takže noc je jedna pauza, ne několik kousků;
  - GPS skok běh stání nepřeruší.
- **Vyhlazení výšky** začíná od výšky předchozího bodu. Vektor V15 tak dá 54 m podle zadání.
- **„Připraveno“** posune start jen tehdy, když část dávky před značkou má < 60 s jízdy a < 0,2 km. Skutečnou jízdu tak nikdy nezahodí.
- **Jízda rozjetá před nasazením** dostane dosavadní část jako 1. etapu.
- **`start_user_trip`** u už převzaté jízdy neposouvá `updated_at`. Jinak by každé otevření appky oddálilo uzavření po 72 h.
- **`finish_user_ride` u uzavřené jízdy** dál umí přejmenovat, stejně jako dnes.
- **Vrácení na kiosku před posledním dnem** (kolo 3): pro jízdu platí zavření kóje jako vrácení, i když rezervace ještě běží. Výjimka: motorka po zaparkování znovu vyjela. Rezervace, kód ani kiosk se tím nemění, jen záznam jízdy.
- **`start_user_trip_from`** (kolo 3): nesmyslný čas prvního bodu se ořízne (7 dní zpět, převzetí − 10 min), neignoruje se celý; převzatá jízda bez jediného bodu se na něj posune (pomůže, když se ztratila odpověď prvního startu); zpětně se výpůjčka založí jen tehdy, když k ní žádná jízda ještě není (jinak by mohla vzniknout dvakrát).
- **Nové pomocné funkce:** `_ride_stage_days` (počet dní), `_ride_close` (jádro uzavření), `_ride_append_late` (pozdní body), `_ride_auto_name` (název z dat), `_ride_booking_end` (konec výpůjčky včetně kiosku), `_ride_start_trip` + `_ride_trip_json` (společné jádro startu), `_ride_reopen_parked` (pokračování po vyjetí z kóje); `_ride_stats` je nyní STABLE SECURITY DEFINER.

## Soubory k použití dál
- **Pro appku (T2):** `stats_vectors.json`, 16 vektorů se spočtenými hodnotami pro test parity.
- **Pro dokumentaci (STATE):** `../STATE_PATCH.md` s přesnými úpravami STATE_1–6, použij v commitu s SQL.
- **Testy:**
  - `run_tests.sh` + `test_rides.sql`;
  - přehrávky `../pg/sim/replay_new.py` (+ `client2.py`, `../pg/make_old_db.sh`);
  - výstupy ve složce `out/`;
  - testy appky proti SQL (`vs/and/test/verify/scen_*_test.dart`) mají v D4 seznam souborů, nově i s `03c`.
- **Testovací cluster:** `/var/tmp/pg-rides` (~1,2 GB; jiný adresář/port přes `PGD=… PGPORT_RIDES=…`). Až nebude potřeba, smazat.
