# design:minimal-change — pauza, auto-pauza, vícedenní cesty, slučování, rozumné statistiky

2026-10-22 · větev `claude/moto-go-mobile-conversion-gqg5qo` @ 0bfabd41 (obsahuje PR #2208).
Podklady: `understand_app.md`, `understand_server.md`, `understand_platform.md` (stejná složka).
Vlastní ověření v této fázi:
- `pg/capcheck*.sql`, `pg/capproto.sql`: kumulativní prořeďování stopy (viz §3.3).
- `elev/elev.py`: algoritmus „nastoupáno“ (viz §8.1).

Filozofie: co nejvíc na klientu.
- Klient: pauza a auto-pauza, značka pauzy v EXISTUJÍCÍM formátu bodu.
- Server: co nejméně nových objektů, jen aby přestal dělit cesty, uměl pauzy ve statistikách a uložil sloučení.
- Maximální znovupoužití existujících RPC i obrazovek.

---

## 0. Shrnutí pro majitele (česky)

**Pauza a auto-pauza**
- Vedle „Ukončit“ přibude **Pozastavit / Pokračovat** všude, kde se záznam ovládá: Moje zážitky, menu „Přidat“, navigace, v2 nahrávač, dok a Domů.
- **Ruční pauza vypne GPS** (nulová spotřeba) a pokračuje se klepnutím, stejně jako u Stravy.
- **Automatická pauza** nastane sama:
  - po 5 minutách stání,
  - po 3 minutách chůze,
  - nebo přes noc.
- Během auto-pauzy se nic nenahrává ani neodesílá. Po rozjezdu (2× nad 20 km/h) záznam sám pokračuje.
- Metry došlapané pěšky od motorky se ze stopy odříznou.

**Jedna cesta = jeden záznam**
- Vlastní vícedenní cesta i celá výpůjčka zůstane **jedním záznamem** přes všechny noci.
- Výpůjčka končí vrácením motorky.
- Vlastní cesta končí tlačítkem „Ukončit“. Server ji sám uloží, jen když se 3 dny nic neděje.
- V detailu jsou **dny a etapy**.
- Když dorazíš zpátky na místo startu a stojíš tam přes 3 h, záznam vypne GPS a v appce se zeptá: „Pokračovat v cestě / Ukončit“. Zapomenutá cesta tak nebude nahrávat cesty autem do práce.

**Slučování jízd**
- Více jízd jde **sloučit do jedné cesty** a kdykoli zase rozdělit.
- Hned po sloučení je k dispozici i tlačítko „Zpět“.
- Starší výpůjčky rozdělené po dnech se v appce zobrazí jako jedna cesta automaticky.

**Statistiky, které dávají smysl**
- Noc ani oběd se nepočítají do „stání“. Jsou zvlášť jako **pauzy**.
- Chůze se nepočítá jako jízda.
- Maximum se nebere z GPS skoků.
- „Nastoupáno“ je počítané správně: na serpentinách dřív 18 % skutečnosti, nově 95–100 %.
- Pozdě zmáčknuté „Ukončit“ nepřidá hodiny.
- Jízda autem po vrácení motorky se do výpůjčky nezapočítá.
- Týdenní cesta má mapu celou. Dnes se z prvních dnů ztratí skoro všechny body.

**Baterie**
- Při auto-pauze zůstává GPS zapnuté. Jinak by appka nepoznala rozjezd: Android ani iOS nedovolí GPS znovu zapnout z pozadí.
- Odhad spotřeby je 5–15 % za noc. Kdo chce nulu, dá ruční pauzu.

**Co schvaluješ**
- SQL balíček (5 souborů, viz §3).
- Pravidlo „doma po 3 h vypnout GPS“ (§5.8).
- Přepínač `ride_autopause` ve Velínu (Feature flags) umí auto-pauzu kdykoli vypnout bez vydání appky.

---

## 1. Rozsah a principy

| Požadavek | Kde se řeší |
|---|---|
| R1 ruční pauza/pokračování | Recorder (`RidePhase.manualPaused`, stream zrušen) + ovládání ve všech UI bodech (§10) |
| R2 auto-pauza/auto-pokračování | Čistý detektor `RideMotionDetector` na klientu (§5), serverová inference dlouhých stání (§3.2) jako záchrana pro staré klienty |
| R3 rozumné statistiky | `_ride_stats_v2` + `_ride_finalize` + `finish_user_ride` + `_ride_track_cap` (§3, §8), klientský živý přehled (§8.2) |
| R4 nikdy nedělit cestu | Cron + `start_user_ride` už nedělí výpůjčky (u žádného klienta). Vlastní cesty nového klienta (`pause_aware`) drží otevřené 72 h ticha / 30 dní. Klient při `ride_finished` naváže, nikdy tiše nekončí (§3.4, §4.6). |
| R5 sloučení + zpět | Sloupce `trip_id`, `trip_name` + jedno RPC `set_user_rides_trip` (merge, split, undo i přejmenování), seskupení v UI (§9) |
| R6 výpůjčka = jedna cesta | Platí pro nového i starého klienta (server) + implicitní seskupení podle `booking_id` pro historii (§9.1) |

Tvrdá pravidla, která se dodržují:
- **4.1.3 beze změny funguje.**
  - Žádný nový chybový kód v `append_ride_track`.
  - Stejné klíče odpovědí.
  - Stejné signatury.
- **Nová appka na starém serveru** degraduje srozumitelně (§12):
  - Pauza a auto-pauza fungují lokálně.
  - Cesty se dělí jako dnes.
  - Slučování je skryté.
- **Žádný nový balíček.**
  - iOS jen API z geolocator 10 / PI 4.3.0 (žádné `verticalSpeed*`).
  - Žádné bumpy.
- **Nic mimo záznam jízd se nemění.** Kiosk, rezervace, platby a v2 mimo jízdy zůstávají, jak jsou.
  - Dvě nutné mini-změny mimo „naše“ soubory jsou vyznačené ⚠ v §13.

---

## 2. Datový model

### 2.1 `user_rides` — nové sloupce (vše `ADD COLUMN IF NOT EXISTS`)

| Sloupec | Typ | Default | Význam |
|---|---|---|---|
| `pause_sec` | integer not null | 0 | Čas pauz (auto/ruční/odvozené dlouhé stání, noci). Není ve `idle_sec` ani `gap_sec`. |
| `pause_aware` | boolean not null | false | Záznam vede klient, který sám pauzuje (nová appka přes `start_user_trip`). Řídí cron (72 h ticha místo 3 h) a vypíná „legacy chůzi“ v statistikách. |
| `stats_state` | jsonb | null | Stav přenášený mezi dávkami: převýšení (`e_ref`, `e_a1`, `e_a2`, `e_ts`). Klient ho nevidí. |
| `trip_id` | uuid | null | Ruční seskupení do cesty. `null` = výchozí seskupení (podle `booking_id`), `= id` = samostatná jízda (rozděleno), jiné = členem cesty. |
| `trip_name` | text | null | Název cesty (stejný na všech členech; ≤ 120 znaků). |

- Žádná nová tabulka.
- RLS beze změny: sloupce jsou na existující tabulce, zápis jen přes SECURITY DEFINER RPC.
- Index není potřeba: seznam je per uživatel a cron jede po `is_recording`.
- `COMMENT ON COLUMN` pro každý sloupec.

### 2.2 Formát bodu (beze změny tvaru)

`[lat, lng, ts, kmh, alt?]`. Dart zůstává `List<double>`. Nové konvence, které jen nový klient posílá:

| Pole | Konvence | Starý server / 4.1.3 / Velín |
|---|---|---|
| `kmh = -1` | **Značka „před tímto bodem byla pauza“.** Bod je první po obnovení záznamu. Jeho skutečná rychlost se obětuje; maximum jde zvlášť přes `p_max_speed_kmh`. | `_ride_stats` bere kmh jen pro maximum (`v_kmh > v_max` → nic). 4.1.3 model i Velín (`rideTrack.js`) index 3 nečtou. Ověřeno grepem. |
| `kmh` | Jen PLATNÁ Dopplerova rychlost (`hasSpeed \|\| speed>0`, a `speedAccuracy ≤ 2,5 m/s` když je k dispozici), jinak 0. Nikdy > 300. | beze změny |
| `alt` | Jen když je konečná, ≠ 0 a (`!hasAltitudeAccuracy \|\| altitudeAccuracy ≤ 20 m`) | volitelné už dnes |
| `ts` | Čas fixu (s) opravený o posun hodin vůči serveru, když je \|posun\| > 120 s (§7) | beze změny |

Proč ne objektový marker ani 6. prvek:
- Oboje vyžaduje změnit typ bufferu a persistence.
- Objekt by `_ride_track_cap` prořídnutím zahodil.
- `-1` projde všemi dnešními cestami beze změny.

### 2.3 Cesta = skupina řádků (jen v UI)

Klíč skupiny řádku `r`:

```
tripKey(r) = r.trip_id != null ? 't:' + r.trip_id
           : r.booking_id != null ? 'b:' + r.booking_id
           : 'r:' + r.id
```

- Skupina s 1 řádkem je obyčejná jízda.
- Skupina se ≥ 2 řádky je **cesta**.
- Jeden řádek přes ≥ 2 dny se zobrazí jako cesta (dny/etapy) se stejnou kartou.
- Agregace se počítá na klientu (§9.2). Server se o skupiny nestará.
- Statistiky se **sčítají z uložených součtů**, nikdy se nepřepočítávají z prořídnuté stopy (N13).

---

## 3. SQL (drafty → `scratchpad/rides/sql/`, NIKDY do `supabase/migrations` bez schválení)

Návrh souborů. Každý je idempotentní a spustitelný dvakrát.
- Workflow `deploy-sql.yml` pouští každý soubor v `--single-transaction`, proto v souborech není BEGIN/COMMIT.
- Každý soubor končí `notify pgrst, 'reload schema';`.
- Každý mezistav je kompatibilní se starým i novým klientem. Nový klient zjišťuje schopnosti serveru podle existence RPC.

| # | Draft | Obsah |
|---|---|---|
| 01 | `01_rides_columns.sql` | Sloupce §2.1 + komentáře. `INSERT INTO feature_flags (key, enabled, description) VALUES ('ride_autopause', true, '…') ON CONFLICT (key) DO NOTHING`. |
| 02 | `02_rides_stats_cap.sql` | `_ride_stats_v2` (nová, interní) + `_ride_stats(jsonb)` jako obal (stejná signatura) + `_ride_track_cap(jsonb,int)` (stejná signatura, nový algoritmus) |
| 03 | `03_rides_append_finish.sql` | `append_ride_track`, `_ride_finalize`, `finish_user_ride`, `_ride_json` (všechny stejné signatury) + jednorázová oprava dat (§3.7) |
| 04 | `04_rides_trip_start_cron.sql` | `start_user_trip` (NOVÁ), `start_user_ride` (stejná signatura), `close_stale_user_rides` (stejná), `admin_booking_live_ride` (stejná, +klíče) |
| 05 | `05_rides_trip_group.sql` | `set_user_rides_trip` (NOVÁ) |

Přejmenování při commitu: `20261023_user_rides_trips_a.sql` … `_e.sql`. Pořadí podle `LC_ALL=C sort`.

Práva:
- Nové veřejné RPC: `revoke all … from public, anon; grant execute … to authenticated, service_role`.
- `_ride_stats_v2`: `revoke all … from public, anon, authenticated` (Supabase default privileges jinak dají EXECUTE všem).
- `CREATE OR REPLACE` se stejnou signaturou práva zachová.

**Žádné přetížení:**
- Žádné existující RPC nedostane nový parametr.
- Nové chování mají jen nová jména `start_user_trip` a `set_user_rides_trip`.
- Test v PG: `select proname, count(*) from pg_proc where proname in (…) group by 1 having count(*)>1` → 0 řádků.

### 3.1 `_ride_stats_v2(p_track jsonb, p_state jsonb) returns jsonb` (nová, interní)

Vrací `{dist_km, moving_sec, idle_sec, gap_sec, pause_sec, gain_m, max_kmh, state}`.

`p_state`:
- `legacy` (bool): pravidlo chůze pro staré klienty.
- `e_ref`, `e_a1`, `e_a2` (num/null).
- `e_ts` (num/null).

Konstanty: `c_gap_sec 180`, `c_still_km 0.3`, `c_pause_sec 300`, `c_bad_sec 2592000` (30 d), `c_max_kmh 300`, `c_move_kmh 3`, `c_walk_kmh 7`, `c_walk_dop 8`, `c_inst_min 10`, `c_inst_max 60`, `c_gain_h 10`, `c_jump0_km 0.5`.

Pro každý bod `b` (předchozí `a`; vzdálenost `d` se kumuluje od posledního bodu s časem jako dnes; `dt = tb - ta`):
- `kmh_b < 0` → **flag** (pauza před b).
- `dop_b = kmh_b` když `0 < kmh_b < 300`, jinak 0.

Maximum: `max = max(max, dop_b)`.

Klasifikace úseku a→b, v tomto pořadí:
1. `dt < 0 or dt ≥ c_bad_sec` → nedůvěryhodný: nic, reset převýšení.
2. `flag` → **PAUZA**: `pause += dt`, žádné km, reset převýšení.
3. `dt > 180 and d > 0.3` → **MEZERA** (`gap += dt`), žádné km, reset převýšení.
   - Dnes se úsek s `dt ≥ 86400` zahazoval celý. Nově je to mezera, aby souhlasil celkový čas.
4. `dt ≥ 300 and d ≤ 0.3` → **PAUZA odvozená**: dlouhé stání bez posunu, typicky noc, oběd nebo starý klient. `pause += dt`, km += 0, reset převýšení.
5. Skok (`v ≥ 300` nebo `dt = 0 and d ≥ 0.5`) → žádné km, `idle += dt`.
6. Jinak `v = d/dt`:
   - `pomalé = v < 3`, a navíc pro `legacy`: `v < 7 and dop_b ≤ 8`.
   - pomalé → `idle += dt`, **km se nepřičítá** (drift v hotelu, chůze starého klienta).
   - jinak `moving += dt`, `km += d`.
   - Body bez času (`dt` null) → `km += d`, bez času (jako dnes).
   - Maximum z odvozené rychlosti jen když `10 ≤ dt ≤ 60`, `dop_a = dop_b = 0` (rychlost neznámá) a `v < 250`.

Převýšení:
- Klouzavý průměr ze 3 posledních surových výšek (`e_a1`, `e_a2`, `alt`).
- Hystereze 10 m:
  - `s > ref + 10` → `gain += s - ref; ref = s`;
  - `s < ref` → `ref = s`.
- Body s `ts ≤ e_ts` se do převýšení nepočítají (překryvový bod z minulé dávky).
- Reset (`ref, a1, a2 := null`) po bodech 1–4.

Výsledek ověřený na syntetickém profilu (`elev/elev.py`, 100 km):

| Profil | Dnes (krok ≥ 5 m) | Nově |
|---|---|---|
| Rovina, šum σ3 | +680 m | 0–63 m |
| Rovina, šum σ6 | +2 600 m | ~500 m |
| Serpentiny 8 % ve 30 km/h | 18 % skutečnosti | 98–100 % |
| Kopce ve 40–80 km/h | 79–186 % skutečnosti (podle šumu) | 82–94 % |

`_ride_stats(p_track jsonb)` (stávající, stejná signatura) = `(_ride_stats_v2(p_track, null) - 'state')`. Kvůli konzistenci a případnému ručnímu použití.

### 3.2 Pauza odvozená = záchrana pro všechny klienty

Bod 4 výše dělá noc nebo dlouhou zastávku pauzou i u 4.1.3 a u nové appky na serveru bez explicitní značky. Explicitní značka (`flag`) navíc pokryje pauzu s posunem: ruční pauza a převoz trajektem/vlakem se počítá jako pauza, ne jako „bez signálu“.

### 3.3 `_ride_track_cap(p_track jsonb, p_max int default 4000)` — stejná signatura, nový algoritmus

Ověřeno v PG (`pg/capcheck.sql`):
- Dnešní „každý k-tý bod“ se při každé dávce nad limitem aplikuje znovu, takže se **starší části prořeďují opakovaně**.
- Simulace 30 000 bodů (týden): 4 starší dny po ~80 bodech na 5 000 surových, tj. rozestup 4–7 km.
- Týdenní mapa by první dny ukázala jako rovné čáry.

Nově (`pg/capproto.sql`, prototyp ověřený):
- Když `n ≤ p_max`, stopa beze změny.
- Jinak se spočte délka cesty `L` (haversine).
- **Rozestup** `D = 0,02 km × 2^k`, nejmenší `k` takové, že `L / D ≤ 0,85 × p_max`.
  - Mocniny dvou dělají opakované prořeďování rovnoměrné: starší úseky se rozestupem D/2 se při dalším zdvojení prořeďují přesně na půl.
- Prochází se body a drží se:
  - první a poslední bod,
  - bod, u něhož kumulovaná vzdálenost od posledního drženého bodu ≥ `D`,
  - oba kraje časového skoku > 180 s,
  - každý bod s `kmh < 0` a jeho předchůdce.
- Nepole se vynechají.
- Když je výsledek stále > `p_max` (patologicky mnoho mezer), použije se starý „každý k-tý“ s drženými kraji.

Výsledek simulace:
- Každý den ~417 bodů (rovnoměrně) + hustý živý konec.
- Vlna 30 000 bodů po 20: 13 s v testovacím PG (1 500 volání), tedy ~9 ms na dávku.

`admin_booking_live_ride` (cap 1 200) to dostane zadarmo. `_ride_finalize` na konci zavolá cap ještě jednou, aby se srovnal hustý konec.

### 3.4 `start_user_trip(p_booking_id uuid default null) returns jsonb` — NOVÁ (jen nový klient)

```
auth.uid() null → {success:false, error:'not_authenticated'}
v_now := now()
if p_booking_id not null:
   booking musí patřit uživateli, status in ('reserved','active'), returned_at is null
   jinak → {success:false, error:'booking_inactive', now: epoch(v_now)}   -- bez založení prázdné jízdy (N10)
otevřená jízda (id, last := greatest(coalesce(last_fix_at, started_at), updated_at), booking_id):
   pokud booking_id IS NOT DISTINCT FROM p_booking_id
      and (booking_id is not null            -- stejná, běžící výpůjčka (ověřeno výše)
           or last > v_now - 72 h):          -- vlastní cesta naživu (i když ji založil starší klient)
        update set pause_aware = true        -- adopce
        → {success:true, id, resumed:true, booking_id, moto_name, pause_aware:true, now}
   jinak _ride_finalize(id, end_rule(r))     -- jiná výpůjčka / mrtvá vlastní cesta
insert … booking_id = p_booking_id (BEZ párování podle data — oprava N10/#10), source 'auto',
       pause_aware true, track '[]', is_recording true
→ {success:true, id, resumed:false, booking_id, moto_name, pause_aware:true, now: epoch(v_now)}
```

- `end_rule(r)` = `least(last, b.returned_at)` (≥ started_at) u výpůjčky, jinak `last`.
- `now` = epoch s (numeric). Klient z něj počítá posun hodin (§7).

### 3.5 `start_user_ride(p_booking_id, p_lat, p_lng)` — stejná signatura (4.1.3 + fallback)

Změna jen ve větvi „otevřená jízda existuje“:

| Otevřená jízda | Dnes | Nově |
|---|---|---|
| s `booking_id`, výpůjčka běží (reserved/active, nevráceno) | obnoví jen do 3 h, jinak uzavře a založí novou | **obnoví vždy** → 4.1.3 už nedělí výpůjčku přes noc (R6) |
| s `booking_id`, výpůjčka skončila | — | uzavře `least(last, returned_at)` a pokračuje jako dnes |
| `pause_aware`, bez booking | — | obnoví, je-li `last > now - 72 h`, jinak uzavře a založí |
| legacy bez booking | 3 h pravidlo | **beze změny** |

Zbytek (párování podle data, první bod s `p_lat/p_lng` a časem serveru, odpověď) je beze změny.

### 3.6 `append_ride_track(p_ride_id, p_points, p_max_speed_kmh)` — stejná signatura, stejné chyby

Změny:
1. **Body po vrácení se zahodí** (oprava N9: auto po vrácení).
   - Jízda s `booking_id`, `returned_at` není null.
   - Body s `ts > returned_at + 2 min` se vyřadí stejně jako dnešní `ts < started_at - 1 h`.
   - Celá dávka vyřazená → `{success:true, …, dropped_after_return:true}`.
   - Žádná nová chyba (4.1.3 by jinak opakoval donekonečna).
2. Statistiky: `v_st := _ride_stats_v2(seg, coalesce(stats_state,'{}') || jsonb_build_object('legacy', not pause_aware))`. Přičte se `pause_sec`, uloží se `stats_state := v_st->'state'`.
3. Odpověď navíc obsahuje `pause_sec` (starý klient ji ignoruje).
4. `p_max_speed_kmh` se ořízne `least(…, 300)`.

Ostatní (dnešní pojistky `last_fix_at`, `duration_min = last_fix − started_at`, `avg = km/moving`, `max ≥ avg`) zůstává.

### 3.7 `_ride_finalize`, `finish_user_ride`, `_ride_json`, oprava dat

**`_ride_finalize(p_ride_id, p_ended_at)`** (stejná signatura)
- `v_dur = max(1, (end−start)/60, ceil((move+idle+gap+pause)/60))`.
- Nepokrytý čas `u = v_dur·60 − move − idle − gap − pause`:
  - `u ≥ 300` → `pause += u`,
  - jinak `idle += max(u,0)`.
  - Dnes šlo vše do stání (N4, N8).
- Průměr bez času jízdy: `km / ((dur·60 − gap − pause)/3600)`.
- Název (je-li prázdný):
  - jeden pražský den → `DD.MM.YYYY`,
  - víc dní → `DD.MM.–DD.MM.YYYY`.
- Na konci `track := _ride_track_cap(track)` (srovná hustý konec).
- Návrat navíc obsahuje `pause_sec`. < 1 km se stále smaže.

**`finish_user_ride(p_ride_id, p_points, p_name)`** (stejná signatura)
- Konec = `now()`. Po připojení poslední dávky platí:
  - když `last_fix_at < now() − 5 min` → konec = `greatest(last_fix_at, started_at)`. Pozdní Stop (N8) ani Stop během pauzy nepřidá hodiny.
  - výpůjčka s `returned_at` → konec = `least(konec, greatest(returned_at, started_at))`.
- Platí i pro 4.1.3 (jen zlepšení).

**`_ride_json(p_ride)`**: přidá `pause_sec`, `pause_aware`, `trip_id`, `trip_name`. 4.1.3 neznámé klíče ignoruje.

**Oprava dat (v 03, idempotentní)**
- Týká se uzavřených jízd s `pause_sec = 0` a stopou s časy.
- `pause_sec := Σ dt` úseků uložené stopy s `300 ≤ dt < 30 d` a posunem ≤ 0,3 km. Kraje > 180 s cap vždy držel, takže je to spolehlivé i na prořídnuté stopě.
- `idle_sec := greatest(0, idle_sec − pause_sec)`.
- km a max se nemění. Opraví „noc = stání“ u dosavadních jízd.

### 3.8 `close_stale_user_rides()` — stejná signatura, nová pravidla

`last := greatest(coalesce(last_fix_at, started_at), updated_at)`. Uzavřít, když:

| Druh | Podmínka | Konec |
|---|---|---|
| výpůjčka (jakýkoli klient) | booking chybí, nebo status completed/cancelled, nebo `returned_at < now() − 10 min`, nebo `end_date::date < current_date`, nebo `started_at < now() − 60 d` | `greatest(started_at, least(last, coalesce(returned_at, last)))` |
| vlastní `pause_aware` | `last < now() − 72 h` nebo `started_at < now() − 30 d` | `last` |
| vlastní legacy | `last < now() − 3 h` nebo `started_at < now() − 36 h` (**beze změny**) | `last` |

- Limit 500 na běh.
- Výjimka na jízdu zůstává.
- Komentář funkce aktualizovat.
- 10 min po vrácení je rezerva na poslední dávku (flush ≤ 90 s), aby se konec výpůjčky neztratil.

### 3.9 `set_user_rides_trip(p_items jsonb) returns jsonb` — NOVÁ (merge / split / undo / přejmenování)

```
auth null → {success:false, error:'not_authenticated'}
p_items musí být pole 1..300 objektů {id uuid, trip_id uuid|null, trip_name text|null}
  (neplatné uuid / tvar → {success:false, error:'bad_items'})
update user_rides set trip_id = i.trip_id,
                      trip_name = nullif(left(trim(i.trip_name),120),'')
 where id = i.id and user_id = auth.uid()
→ {success:true, updated:n}
```

- Cizí id se tiše přeskočí. Klient porovná `updated` s počtem a ohlásí částečný neúspěch.
- Hloupý setter s kontrolou vlastníka. Veškerá logika (které `trip_id`, undo mapa) je v klientu (§9.3).

### 3.10 `admin_booking_live_ride` (stejná signatura)

Přidá klíče:
- `pause_sec`, `pause_aware`,
- `is_standing = is_recording and age_sec ≥ 900 and booking_status in ('reserved','active')`.

`is_live` beze změny.

### 3.11 PG testy (na `/var/tmp/pg-rides`, port 5499)

- Každý draft aplikovat 2×.
- Pak `select public.t_shim()`. Rozšířit filtr shimu o `trip`, aby `start_user_trip` a `set_user_rides_trip` braly falešné hodiny.
- Scénáře §15.2.
- Kontrola přetížení (§3).
- `\df+` práv: anon nesmí nic z nového, authenticated nesmí `_ride_stats_v2`.

---

## 4. Klientský stavový automat

### 4.1 Stav

`RideRecorderState` (sdílený soubor, oba stromy) — přidá:

```dart
enum RidePhase { riding, autoPaused, manualPaused }
enum RidePauseReason { start, stop, walk, silence, manual, home }
final RidePhase phase;            // platí jen když recording == true
final RidePauseReason? pauseReason;
final DateTime? pausedAt;         // začátek pauzy (kotva), pro „od 20:14“
final double? liveKm;             // §8.2
final int? liveMovingSec;
final String? notice;             // jednorázová hláška (i18n klíč) při dalším otevření
```

- `recording` zůstává **„cesta běží“** ve všech třech fázích. Hlídač proto pauzu nikdy „neopraví“ (`ensureRecording` končí na `state.recording`).
- `points` zůstává jen pro diagnostiku. UI místo „N bodů“ ukazuje km.

### 4.2 Přechody

```
idle ──start/ensureRecording──▶ autoPaused(start) ──resume rule──▶ riding
riding ──5 min stání / 3 min chůze / ticho po pomalu──▶ autoPaused(stop|walk|silence)
autoPaused ──resume rule (+pre-roll, příp. obnova pomalého úseku)──▶ riding
riding|autoPaused ──Pozastavit (UI)──▶ manualPaused       [stream ZRUŠEN, GPS off]
autoPaused(stop) u startu ≥ 3 h, vlastní cesta ──▶ manualPaused(home)   [§5.8]
manualPaused ──Pokračovat (UI, jen popředí)──▶ autoPaused(start) ──▶ riding
kterákoli ──Ukončit / vypnutí přepínače / konec výpůjčky (hlídač)──▶ idle
```

Kill-switch `ride_autopause = false`:
- Detektor nikdy neauto-pauzuje a nedrží pomalé body. Chování je jako dnes.
- Start jde rovnou do `riding`.
- Ruční pauza funguje dál.

### 4.3 Persistence (přežije restart i zabití OS)

Jeden nový pref `mg_ride_rec_meta` (JSON):
- `phase`, `reason`, `pausedAt` (epoch s),
- `anchor` (bod), `last` (poslední odeslaný bod),
- `start` (první bod cesty, pro §5.8), `clockOff` (s),
- `live` `{km, mov, at}`, `notice`.

Druhý pref `mg_ride_caps` (JSON):
- `trips` (bool|null), `probedAt`,
- `autopause` (bool, poslední známá hodnota flagu).

**Oba klíče MUSÍ přibýt do `_preserveKeys` v `core/cache_cleanup_service.dart` v OBOU stromech** (⚠, jinak je smaže první přechod do pozadí). Ukládá se při každé změně fáze a po každé odeslané dávce.

### 4.4 Obnova (`_restore`)

| Uloženo | Dnes | Nově |
|---|---|---|
| ruční + `manualPaused` | — | `recording=true, phase=manualPaused`, **stream se nepřipojí**. UI ukáže „Pozastaveno · Pokračovat“. |
| ruční + `riding`/`autoPaused` | připojí stream | připojí stream, detektor **armed** (`autoPaused(start)`) s kotvou `anchor ?? last` a `restored=true` (§5.6) |
| výpůjčka + `manualPaused` | čeká na hlídače | `recording=true, phase=manualPaused`. Hlídač nic nespustí (recording=true); konec výpůjčky ji ukončí. |
| výpůjčka + jiné | hlídač → `_start` | beze změny (hlídač → `_start` → `start_user_trip` resumed). Detektor armed s kotvou z meta. |

### 4.5 Hlídač a lifecycle

Pravidla pro jednotlivé vstupy:
- **`onAppResumed`**:
  - nic, když `phase == manualPaused`.
  - Při `autoPaused` se znovu připojí jen při chybě, chybějícím odběru, nebo když je ticho > 30 min. Krátké ticho je normální stání.
- **`_onForeignStreamsClosed`, `_watchService`, `_tick no_fix`**: nic, když `manualPaused`.
- **Konec výpůjčky během ruční pauzy**: větev hlídače `!manual && (recording||rideId)` → `stop()` beze změny ✓.
- **`setEnabled(false)`**: beze změny (ukončí i pozastavenou výpůjčku).

### 4.6 Odpovědi serveru

`appendRideTrack` vrací `RideAppendOutcome {result, distanceKm?, movingSec?, pauseSec?}`. Výsledek `finished` se rozdělí na `closed` (`ride_finished`) a `gone` (`ride_not_found`).

| Výsledek | Výpůjčka | Vlastní |
|---|---|---|
| `closed` | dnešní navázání (`start_user_trip(booking)`). `booking_inactive` → konec bez prázdné jízdy. Fallback `start_user_ride` (dnešní pojistka). | **Nově navázat novou cestou** (dnes tichý konec). `notice = 'rideTripContinuedNew'`, rideLog `trip_continue`. |
| `gone` (smazáno) | navázat (jako dnes) | konec záznamu (`_forgetRide`) |

Smazání PRÁVĚ nahrávané jízdy z detailu:
- Nejdřív `recorder.discardCurrent()`: odpojit a zapomenout bez finish.
- Pak `delete_user_ride`.
- Potvrzení „Tahle jízda se právě nahrává — smazáním se záznam zastaví.“

### 4.7 Volba RPC a zjištění schopností serveru

| Situace | Postup |
|---|---|
| Start | `start_user_trip(bookingId)` |
| `PostgrestException.code == 'PGRST202'` (nebo `42883`) | `caps.trips=false` na 1 h, pak `start_user_ride(bookingId)` (bez lat/lng jako dnes) |
| Offline (jiná výjimka) | `retry`, NE fallback |

- `bookingId` = aktivní výpůjčka podle hlídače (`_activeBookingId`). Ruční start během převzaté výpůjčky (přepínač vypnutý) ji předá, jinak `null`, tedy vlastní motorka bez párování podle data.
- **Sloučení** se zobrazí, jen když řádky z `get_my_rides` mají klíč `trip_id`. Volání `set_user_rides_trip` s `PGRST202` → hláška `rideTripUnavailable`.

### 4.8 Testovatelnost

- Recorder dostane šev `RideServerApi`: `signedIn`, `startTrip`, `append`, `finish`. Výchozí implementace volá dnešní top-level funkce.
- Provider `rideServerApiProvider` se v testech přepíše.
- GPS se testuje přes `GeolocatorPlatform.instance = FakeGeo()`.

---

## 5. Detekce (čistý Dart `RideMotionDetector`, oba stromy, bez I/O)

### 5.1 Vstupy

- `onFix(Position p, DateTime now)`: každý SUROVÝ fix ještě před `ridePointFromFix`.
- `onTick(DateTime now)`: časovač 90 s, beze změny.
- Výstup jsou události:
  - `emit(List<point>)`: do bufferu,
  - `pause(at, reason)`,
  - `resume(flagged)`,
  - `trim(n, m)`,
  - `restore(n)`.
- Detektor sám volá `ridePointFromFix` (20 m filtr vůči svému poslednímu bodu) a drží si `held`, `pausePath` a `preroll`.
- Fix s časem ≤ poslední zpracovaný se ignoruje (iOS cache po připojení; `notBefore` jako dnes).

Kvalita fixu:
- `good`: `hasAccuracy && accuracy ≤ 25`.
- `usable`: ≤ 50.
- `dop` (km/h) jen když `usable && (hasSpeed || speed > 0) && (!hasSpeedAccuracy || speedAccuracy ≤ 2.5)`, jinak `null`.
- **Neznámá rychlost ≠ 0.**

### 5.2 Prahy (konstanty v `ride_motion.dart`, jedna tabulka)

| Název | Hodnota |
|---|---|
| `kSlowKmh` (začátek pomalého běhu, „reset“ nad) | 12 |
| `kStillKmh` | 3 |
| `kWalkMaxKmh` | 8 |
| `kStopPause` (stání v `R_STILL`) | 5 min |
| `kWalkPause` (důkazy chůze) | 3 min, ≥ 3 good fixy, ≥ 50 m dráhy |
| `kSlowRideRelease` | 2 min a dráha ≥ 300 m a medián `dop` > 8 (nebo dráha/čas > 9 km/h) → uvolnit držené body |
| `R_STILL` | clamp(1,5 × medián přesnosti, 40 m, 100 m) kolem kotvy |
| `kSilenceAfterSlow` (poslední `dop` < 10) | 3 min ticha = stání od toho fixu |
| `kSignalLostKmh` (poslední `dop` ≥ 30) | ticho se NIKDY nečasuje, rozhodne až další fix (§5.5) |
| `kResumeKmh` | 2 po sobě jdoucí `dop` ≥ 20, ≤ 15 s od sebe, druhý ≥ 100 m od kotvy |
| `kResumeNoDop` | 2 good fixy ≥ 300 m od sebe do 60 s, pozdější ≥ 300 m od kotvy |
| `kPrerollWindow` | 120 s / 40 fixů (kruhový buffer během pauzy) |
| `kPrerollStartKmh` | 8 (pre-roll začne prvním fixem s `dop` ≥ 8; když žádný není, první fix obnovy) |
| `kFlagMinPause` | 60 s (kratší „pauza“ se neznačí) |
| `kRestoreNear` / `kRestoreMinPath` | 100 m / 150 m |
| `kPausePathMax` | 1 200 bodů (drží se ZAČÁTEK, tedy pomalý úsek) |
| `kKillGapKm` | 1 km (po obnově ze zabití: dál od kotvy znamená mezeru, ne pauzu) |
| `kHomeRadius` / `kHomeAfter` / `kHomeMinKm` | 500 m / 3 h / 10 km |

### 5.3 RIDING

- `dop > 12` → `held` se vyšle (`emit`), `slowSince = null`.
- Jinak (`dop ≤ 12` nebo neznámá rychlost a malý posun):
  - Když `slowSince == null`: `slowSince = ts`, `anchor = tento bod` (první pomalý fix; kde motorka zastavila).
  - Bod (po 20 m filtru) jde do `held`, **neodesílá se**. Velín vidí polohu se zpožděním ≤ 5 min jen při pomalém pohybu.
- Rozhodnutí (při fixu i `onTick`):
  - **Stání**: `now − slowSince ≥ 5 min` a všechny fixy v `R_STILL` (nebo žádné) → vyslat `anchor`, `held` zahodit, `pause(anchor.ts, stop)`.
  - **Chůze**: okno ≥ 3 min, žádný `dop > 12`, medián `dop` v [2, 8] (nebo dráha/čas ≤ 8 km/h), dráha ≥ 50 m → vyslat `anchor`, `held` (bez kotvy) → `pausePath`, `pause(anchor.ts, walk)`, `trim`.
  - **Pomalá jízda**: pravidlo `kSlowRideRelease` → vyslat `held`, `slowSince = null`.
- Ticho po pomalu (`kSilenceAfterSlow`) se počítá jako stání od posledního fixu (`onTick`).

### 5.4 AUTO-PAUSED

- Každý fix po 20 m filtru jde do `pausePath` (do `kPausePathMax`) a do `preroll` (120 s).
- Nic se neposílá.
- Pravidlo obnovy (`kResumeKmh` nebo `kResumeNoDop`) určí `R` = první bod pre-rollu s `dop ≥ 8` (jinak fix obnovy).
- **Obnova pomalého úseku (jam / hledání parkování)**:
  - `i* =` NEJDŘÍVĚJŠÍ index v `pausePath` s `dist(pausePath[i*], R) ≤ 100 m`.
  - Když dráha `pausePath[0..i*] ≥ 150 m` → vyslat `pausePath[0..i*]`, `restore(i*+1)`. Pauza je pak jen `[ts(i*), ts(R)]`.
  - Procházka tam a zpět ke kotvě dá `i* ≈ 0`, tedy nic se neobnoví ✓.
- Vyslat pre-roll od `R`. První vyslaný bod dostane **`kmh = −1`**, když `ts(R) − začátek pauzy ≥ 60 s`. Výjimka (bez značky = mezera): `restored && dist(R, kotva) > 1 km`, tedy appka byla zabitá a ráno otevřena až za jízdy.
- `resume(flagged)`, fáze `riding`, `pausePath/preroll` vyprázdnit.

### 5.5 Ticho po rychlé jízdě (tunel, garáž, uspaný OS)

Při dalším fixu po tichu > 180 s, `d` = vzdálenost od posledního bodu, `v = d/dt`:

| Podmínka | Výsledek |
|---|---|
| `d ≤ max(R_STILL,150 m)` a `dt ≥ 5 min` | stání: `pause(posledníFix.ts + 30 s, silence)`, tento fix → pre-roll |
| `d ≤ max(R_STILL,150 m)` a `dt < 5 min` | jízda pokračuje (krátká zastávka) |
| `v ≥ 15 km/h` | projel (vyslat normálně; server z toho udělá mezeru bez km) |
| jinak | odešel pěšky (garáž → ven): `pause(posledníFix.ts, walk)`, fix → `pausePath` |

### 5.6 Start, ruční pauza, obnova

- **Start**: `autoPaused(start)`.
  - První `usable` fix (do 2 min) se vyšle hned jako P0. Velín vidí polohu jako dnes.
  - P0 se uloží jako `meta.start`.
  - Kotva = P0.
- **Ruční pauza** (`pause()` z UI):
  - Když jsou `held` body, vyšle se kotva, zbytek se zahodí.
  - `flush()`, `_detachStream()` (FGS zmizí, `RideKeepAlive.set(false)`), fáze `manualPaused`, `pausedAt = now`, kotva = poslední vyslaný bod, persist, rideLog `pause manual`.
- **Pokračovat** (`resume()`, jen popředí):
  - `_ensurePreciseOnIos()`, `_attachStream('resume_manual')`.
  - Detektor `autoPaused(start)` s kotvou a začátkem pauzy z meta. První vyslaný bod bude značený (≥ 60 s).
- **Ukončit během pauzy**: `held` / `pausePath` se zahodí, `finish` (server ukončí k `last_fix`, tedy ke kotvě; konec = motorka).

### 5.7 Kdy se rozhoduje

- Rozhoduje se při fixu a v `onTick` (90 s, Android FGS + wakelock běží i se zaparkovaným enginem).
- Na iOS se spoléháme hlavně na časová razítka. Rozhodnutí doběhne zpětně s dalším fixem, takže nevadí, když timer v pozadí nedoběhne.

### 5.8 „Doma“ — pojistka proti zapomenuté cestě (jen vlastní cesta)

- Platí, když je `autoPaused(stop|walk|silence)` ≥ 3 h, kotva ≤ 500 m od `meta.start` a cesta má ≥ 10 km (`liveKm`).
- Pak se zruší stream (smí i z pozadí, je to stop) a fáze `manualPaused(home)`.
- UI ukáže „Jsi zpátky tam, kde cesta začala — záznam čeká“ s volbami [Pokračovat v cestě] [Ukončit a uložit].
- Zabrání tomu, aby zapomenutá cesta auto-pokračováním nasbírala jízdy autem, a ušetří baterii doma.
- Výpůjčky se netýká (končí vrácením).

### 5.9 Diagnostika (`rideLog`, kategorie `ride`)

Nové akce (Velín `rideDiag.js` + popisky):

| Akce | Data | Popisek ve Velínu |
|---|---|---|
| `pause` | detail `stop\|walk\|silence\|manual\|home`, `{since, m_from_anchor, held}` | Pozastaveno (stání/chůze/ticho/ručně/doma) |
| `resume` | detail `auto\|manual`, `{pause_sec, m, preroll, flagged}` | Pokračuje |
| `tail_trim` | `{n, m}` | Ořízlá chůze |
| `tail_restore` | `{n, m}` | Obnovený pomalý úsek |
| `trip_continue` | `{old, reason}` | Nová cesta po uzavření serverem |
| `caps` | `{trips}` | Server bez podpory cest |
| `clock_offset` | `{sec}` | Posun hodin telefonu |

---

## 6. Baterie a platformy (přesná nastavení)

Stream se **nikdy nemění za běhu**. Zrušení a nové připojení jen při ruční pauze, Pokračovat, startu a dnešních důvodech (popředí).

| Stav | Android (geolocator 14.1.1 / android 5.1.1) | iOS (geolocator 10.1.1 / apple 2.3.14) |
|---|---|---|
| riding + autoPaused (beze změny) | `AndroidSettings(accuracy: high, distanceFilter: 20, intervalDuration: 5 s, foregroundNotificationConfig: (title, text, channelName 'MotoGo24', enableWakeLock: true, setOngoing: true))` | `AppleSettings(accuracy: high, distanceFilter: 20, activityType: automotiveNavigation, allowBackgroundLocationUpdates: true, pauseLocationUpdatesAutomatically: false, showBackgroundLocationIndicator: true)` |
| manualPaused / home | stream zrušen → FGS stop, wakelock pryč, notifikace pryč | stream zrušen → modrý indikátor pryč |

- `getCurrentPosition` se nepoužívá (rozdílné API 10/14).
- `verticalSpeed*` zakázané.
- Odhad spotřeby (změřit na zařízení): auto-pauza přes noc ≈ 0,5–1,5 %/h (5–15 % za 10 h), uvnitř až 2–3 %/h; jízda 2–5 %/h; ruční pauza 0.
- „Hluboká noc“ (po N h auto-pauzy vypnout GPS a ráno chtít otevřít appku) **NENÍ** ve v1. Je to možná volba majitele později (flag).

**Android notifikace podle stavu (bez re-listen)**
- Nová metoda `notify(title, text)` na kanálu `cz.motogo24/ride` (Dart `RideKeepAlive.notify`, jen Android, jinde no-op).
- Nativně (`RideEngineKeeper`, handler s `applicationContext`, funguje i se zaparkovaným enginem):
  - JEN když běží `GeolocatorLocationService` na popředí (dnešní kontrola).
  - Znovu pošle notifikaci **id 75415** na kanálu **`geolocator_channel_01`**:
    - ikona `mipmap/ic_launcher` (výchozí geolocatoru),
    - `setOngoing(true)`, `setOnlyAlertOnce(true)`,
    - content intent = spuštění appky (`FLAG_IMMUTABLE`).
  - Při `keepAlive(false)` a neběžící službě se defenzivně zavolá `cancel(75415)`, aby nezůstala sirotčí notifikace.
  - Bez `POST_NOTIFICATIONS` je to no-op.
- Volá se jen při změně fáze a jen s vlastním streamem (`_ownStream`).

| Stav | Titulek | Text |
|---|---|---|
| výchozí (při listen, statický) | MotoGo24 · záznam jízdy | Nahrávám, jen když jedeš. Při zastávce se záznam sám pozastaví. |
| riding | MotoGo24 nahrává jízdu | Při zastávce se záznam sám pozastaví a po rozjezdu pokračuje. |
| autoPaused(start) | MotoGo24 · připraveno k záznamu | Nahrávat začnu, až se rozjedeš. |
| autoPaused(stop/walk/silence) | MotoGo24 · jízda pozastavena | Stojíš od {time}, nic se nenahrává. Po rozjezdu záznam sám pokračuje. |
| manualPaused / home | — (služba neběží) | — |

---

## 7. Hodiny telefonu

- `start_user_trip` vrací `now`. Klient změří `off = serverNow − (t0+t1)/2` a uloží ho do meta, když \|off\| > 120 s (jinak 0). Loguje se `clock_offset`.
- `ridePointFromFix(…, now: DateTime.now().add(off))` posouvá:
  - kontrolu stáří fixu (oprava #13: hodiny +6 h zahazovaly všechno),
  - záložní čas příjmu.
- GPS čas fixu se bere, když je vůči opravenému „teď“ věrohodný. Hodiny −1 h tak už nevedou k zahození dávek serverem.
- Na starém serveru (bez `now`) je `off = 0`, tedy dnešní chování.

---

## 8. Statistiky

### 8.1 Server (zdroj pravdy)

Viz §3.1 a §3.7. Definice:

| Veličina | Vzorec / pravidlo |
|---|---|
| `distance_km` | Σ d úseků „jízda“. Bez mezer, pauz, skoků a pomalých úseků < 3 km/h (legacy < 7 km/h & Doppler ≤ 8). Mezi dávkami přírůstkově. |
| `moving_sec` (čas jízdy) | Σ dt úseků s v ≥ 3 km/h (legacy: ne chůze) |
| `idle_sec` (čas stání) | krátké zastávky < 5 min (+ nepokrytý zbytek < 5 min) |
| `pause_sec` (pauzy) | značené pauzy + odvozené (dt ≥ 300 s, posun ≤ 300 m) + nepokrytý zbytek ≥ 5 min |
| `gap_sec` (bez záznamu) | dt > 180 s a posun > 300 m |
| `duration_min` (doba cesty) | `ended_at − started_at` (za běhu `last_fix − started_at`) = move+idle+pause+gap (+ zbytky) |
| `avg_speed_kmh` | km / (moving h); bez moving: km / ((dur − gap − pause) h); > 200 → null |
| `max_speed_kmh` | max(platný Doppler bodů < 300, klientské max ≤ 300, odvozená v jen 10–60 s bez Doppleru < 250, avg) |
| `elevation_gain_m` | hystereze 10 m nad klouzavým průměrem 3 výšek; reset přes pauzy, mezery a nedůvěryhodný čas |

### 8.2 Klient

`ride_live_stats.dart` obsahuje Dart port klasifikace úseku (stejné konstanty, testy parity se SQL vektory):
- **Živé**: `liveKm/liveMovingSec` = součty z poslední OK odpovědi `append` + delta z neodeslaného bufferu.
  - Před první odpovědí se vezme z `meta.live`, nebo z řádku nahrávané jízdy v `myRidesProvider`.
  - Na starém serveru chybí `pause_sec`, nevadí.
- **Dny**: počet lokálních dat, kdy je v úsecích „jízda“ ≥ 5 min.
- **Etapy**: hranice = pauza (značená nebo odvozená) ≥ 2 h, nebo pauza přes 00:00–05:00 místního času, nebo hranice řádku ve skupině.
  - Etapa obsahuje: start–konec (čas), km a čas jízdy z polyline.
  - **Přeškálováno** tak, aby Σ etap = serverové součty (prořídnutá stopa podhodnocuje).
- **Segmenty mapy** (`_splitOnGaps`) se srovnají se serverem:
  - `RideGap.kind ∈ {gap, pause}`, pauza = značený bod nebo odvozená.
  - Hranice 86 400 s se ruší (30 d).
  - Pauza s posunem se kreslí přerušovaně modrošedě, mezera šedě tečkovaně (dnes).

### 8.3 Co se kde ukazuje

| Plocha | Obsah |
|---|---|
| Karta jízdy (old `RideCard`, v2 `RideCardV2`) | datum (u víc dní rozsah) · km · **dny** (≥ 2) jinak celkový čas · čas jízdy · Ø · zastávky · fotky · motorka. U cesty čip „🧳 Cesta · 3 dny“. |
| Detail (old grid `RideStatsGrid`, v2 `RideDetailPartsV2`) | vzdálenost · čas jízdy · Ø · max · nastoupáno · čas stání · **pauzy** (čas, „2×“ z trasy) · bez signálu (jen > 0) · **doba cesty** (víc dní „2 dny 4 h“, jinak celkový čas) · **dny** (≥ 2) · fotky · zastávky. „Bodů stopy“ v appce **pryč** (zůstává ve Velínu). |
| Sekce Etapy (detail, ≥ 2 etapy) | „1. den · po 6. 10. · 08:12–18:40 · 312 km · 5 h 10 min jízdy“ |
| Živý záznam (old karta, v2 recorder, dok, Domů v2) | fáze · km · čas jízdy · „{n}. den cesty“ (≥ 2. den) · „od 20:14“ při pauze · GPS stav |
| Moje zážitky souhrn (v2) | Σ km (beze změny, MotoGo/soukromé podle členů) · počet = **karet** (cest + jízd) |
| Sdílení | název · data · km · čas jízdy (ne celkový) · dny (≥ 2) |
| Velín | §11 |

Formát času:
- `rideDuration(min)`: < 24 h „X h Y min“, ≥ 24 h „{dny} {h} h“ (plurál přes `rideDays*`).
- `rideDate` u víc dní „6.–11. 10. 2026“.

---

## 9. Cesty (sloučení, detail, zpět)

### 9.1 Seskupení a výchozí název

- `ride_trip.dart`: `List<RideTrip> groupRides(List<UserRide>)` podle `tripKey` (§2.3).
- Pořadí: nejnovější `startedAt` skupiny.
- Výchozí název:
  - `trip_name`,
  - jinak u `b:` „Výpůjčka {moto}“,
  - jinak název vedoucí (nejstarší) jízdy, když není datový,
  - jinak „Cesta {data}“.
- Agregát `UserRide` (syntetický, `id = vedoucí id`) pro znovupoužití karet a v2 detailu:
  - stopa a segmenty spojené (mezi řádky segment `pause` nebo `gap` podle §8.2),
  - body všech členů,
  - součty `distance/moving/idle/pause/gap/elevation`, `max = max`,
  - `avg = Σkm/Σmoving`,
  - `durationMin = poslední konec − první start`,
  - `bookingId` jen když je společný.

### 9.2 Sloučit (old i v2, sdílená obrazovka `RideMergeScreen`)

1. Vstup:
   - V seznamu jízd řádek „🔗 Sloučit jízdy“, jen když jsou ≥ 2 karty a server umí cesty.
   - V detailu jízdy položka v menu „Přidat k jiné jízdě…“, která otevře merge screen s předvybranou jízdou.
2. Obrazovka:
   - Hlavička „Sloučit jízdy“ + nápověda (`rideTripMergeHint`).
   - Seznam karet (cesta = jedna položka) s checkboxem 44×44, `Semantics(checked)`.
   - Spodní lišta „Sloučit ({n})“, neaktivní pod 2 (`rideTripMinTwo`).
3. Dialog „Pojmenuj cestu“ předvyplněný výchozím názvem. Prázdné jméno → výchozí.
4. `trip_id` výsledku = existující explicitní `trip_id` z vybraných (nejstarší skupiny), jinak id vedoucí jízdy. Všichni členové všech vybraných karet dostanou ho + jméno.
   - Klient si uloží **undo mapu** `{id → (trip_id, trip_name)}` PŘED změnou.
5. `set_user_rides_trip(items)`, pak `invalidate(myRidesProvider)`, pak snackbar „Jízdy jsou sloučené do jedné cesty.“ + **Zpět** (undo mapa → stejné RPC).
6. Chyby:
   - offline/server → `rideTripFailed` (co + zkus znovu),
   - `updated < n` → `rideTripPartial`,
   - `PGRST202` → `rideTripUnavailable`.

### 9.3 Detail cesty (`RideTripDetailScreen`, old look, oba stromy; v Android v2 šev → `RideDetailViewV2` s agregátem)

- **Hlavička**: název, data, čip dnů.
- **Mapa**: `RideMap` z agregátu, pauzy a mezery rozlišené.
- **Statistiky**: `RideStatsGrid`.
- **Etapy**: `RideStagesSection`.
- **Jízdy v cestě**: karty členů → dnešní detail jízdy.
- **Akce**:

| Akce | Postup |
|---|---|
| Přejmenovat cestu | `set_user_rides_trip` se stejným `trip_id` a novým jménem. U implicitní výpůjčky nastaví explicitní `trip_id` = vedoucí id. |
| Sdílet | text §8.3 + odkaz na nejdelší souvislý úsek nejdelší členské jízdy (dnešní mechanika) |
| Veřejná / soukromá | `update_user_ride(visibility)` pro každého člena; částečný neúspěch → `rideTripPartial` |
| Rozdělit cestu | potvrzení `rideTripSplitQ`; všem `trip_id = vlastní id`, `trip_name = null` (i rozpad implicitní výpůjčky). Snackbar + Zpět (undo mapa). |
| Smazat cestu | potvrzení `rideTripDeleteQ` (počet jízd, nevratné, nabídne Rozdělit); `delete_user_ride` pro každého. Nahrávaný člen nejdřív `discardCurrent()`. |

- Detail jednotlivé jízdy, která je členem, ukáže odkaz „Součást cesty {název} →“.
- Výpůjčka v detailu rezervace (`ride_booking_section.dart`): ≥ 2 jízdy → jedna karta cesty (agregát) + členové pod ní.

---

## 10. UI po obrazovkách (česky, tykání; všechny texty v 8 jazycích)

Společné prvky:
- Cíle ≥ 44 px, `Semantics(button, label)`.
- Stav v `liveRegion`.
- Při reduced motion žádná pulzace: ping jen při `riding` a `!reduced`, pauza se ukazuje statickou ikonou ❚❚.

### 10.1 Starý vzhled (OBA stromy)

| Místo | Změna |
|---|---|
| `my_experiences_screen.dart` `_ridesSection` | Čip v hlavičce podle fáze (`RideRecChip`). Volání `_manualRideCard` → `RideRecControlsCard(onStart, onStop)` (nový soubor). Callbacky předá každý strom svým `toggle` (Android `toggleManualRide`, iOS `_toggleManualRide`). `for (r in rides) RideCard` → `...rideTripCards(context, ref, rides)` + řádek „Sloučit jízdy“. |
| `RideRecControlsCard` | **idle**: dnešní karta „Zaznamenat vlastní jízdu“ beze změny. **riding**: „⏺ Nahrávám jízdu“, řádek `{km} km · {čas} jízdy · {n}. den cesty`, tlačítka [❚❚ Pozastavit] [■ Ukončit záznam jízdy] (Ukončit jen ruční). Výpůjčka místo Ukončit: „Záznam skončí s vrácením motorky.“ **autoPaused(start)**: „Připraveno — začnu nahrávat, až se rozjedeš“. **autoPaused**: „⏸ Stojíš — záznam je pozastavený · od 20:14“ + `ridePhaseAutoHint` + [❚❚ Pozastavit a vypnout GPS] [■ Ukončit]. **manualPaused**: „❚❚ Záznam pozastaven · od 20:14“ + `ridePhaseManualHint` + [▶ Pokračovat] [■ Ukončit]. **home**: `rideHomeParked` + [▶ Pokračovat v cestě] [■ Ukončit a uložit]. |
| `community_submit.dart` (menu „Přidat“) | Když se nahrává: řádek „❚❚ Pozastavit záznam“ / „▶ Pokračovat v záznamu“ nad dnešním Start/Stop. Pauza jde i u výpůjčky. |
| Navigace (old) | `RideNavRecChip` (v `route_nav_status.dart`): „● REC“ / „❚❚ PAUZA“. Klepnutí otevře `showRidePauseSheet` (Pozastavit/Pokračovat, u ruční i Ukončit). ⚠ 1řádkové vložení do `route_navigation_screen.dart` (oba stromy). |
| `ride_card.dart` | Čip cesty, dny místo „167 h“, rozsah dat |
| `ride_detail_screen.dart` | `_statsCard` deleguje na `RideStatsGrid`. Vloží `RideStagesSection` (≥ 2 etapy) a odkaz „Součást cesty“. Mazání nahrávané jízdy přes `discardCurrent`. |
| `ride_map.dart` | Pauza s posunem přerušovaně modrošedě. Legenda `ridePauseLegend` jen když taková je. |
| `ride_share.dart` | Čas jízdy místo celkového, dny a rozsah dat, varianta pro cestu |
| `ride_start_feedback.dart` | Snackbary `ridePausedToast`, `rideResumedToast`, `notice` (`rideTripContinuedNew`). Chyba Pokračovat = dnešní `showRideStartResult` (poloha vypnutá/oprávnění/přesnost). |
| `ride_booking_section.dart` | Seskupení výpůjčky (§9.3) |
| `rideGapNotice` → `rideGapNotice2` | „Část trasy neznáme — telefon chvílemi neposílal polohu (appka byla vypnutá, slabý signál nebo vypnutá poloha). Šedé tečkované úseky jsou jen spojnice; tudy jsi jet nemusel a do kilometrů se nepočítají.“ |

### 10.2 v2 (JEN Android)

| Soubor | Změna |
|---|---|
| `v2/rides/recorder_parts_v2.dart` | `RecorderLiveCardV2`: stav podle fáze (NAHRÁVÁM / POZASTAVENO / PŘIPRAVENO). Čipy: režim, **{km} km**, **{čas} jízdy**, GPS. U pauzy „od 20:14“. Ping jen při riding. Nové `RecorderPauseButtonV2` (bílé 56, „❚❚ POZASTAVIT“) a Pokračovat = `MgCta` „▶ POKRAČOVAT“. |
| `v2/rides/recorder_screen_v2.dart` | Řada [POZASTAVIT/POKRAČOVAT] [UKONČIT (ruční)]. **Oprava r1**: nejdřív potvrzení, až pak busy (rozdělit `trasyConfirmStopRide` na confirm + stop). |
| `v2/record_dock_v2.dart` | `_LiveBar`: řádek režimu podle fáze („Pozastaveno · od 20:14“) + ikonové tlačítko ❚❚/▶ 44×44 vedle ■ (ruční) |
| `v2/route_nav_skin_v2.dart` | `NavRecChipV2`: ● REC / ❚❚ PAUZA, klepnutelné (44 px) → `showRidePauseSheet` |
| `home/v2/home_record_row_v2.dart` | Text podle fáze: „Nahrávám · 123 km“ / „Pozastaveno od 20:14“ / idle beze změny. Klepnutí → nahrávač (beze změny). |
| `v2/rides/moje_tabs_v2.dart` | Ping jen při riding, pauza statická ❚❚ |
| `v2/rides/moje_cards_v2.dart`, `moje_lists_v2.dart` | Seskupené karty (`groupRides`), řádek „Sloučit jízdy“ → `RideMergeScreen` |
| `v2/rides/ride_card_v2.dart` | Čip „CESTA · 3 DNY“, dny, rozsah dat |
| `v2/rides/ride_detail_parts_v2.dart`, `ride_detail_view_v2.dart` | Grid s pauzami, dobou cesty a dny. `RideStagesV2` (nový). Trip-mode = agregát + akce cesty. |
| `v2/rides/moje_summary_v2.dart` | Počet = karty |
| `ride_actions.dart` | `pauseRide(context, ref)` / `resumeRide(context, ref)` vedle `toggleManualRide` |

`RideMergeScreen` a `RideTripDetailScreen` mají ve v2 zatím starý vzhled uvnitř v2 rámu, stejně jako platební obrazovky. Výjimka: detail cesty má šev na `RideDetailViewV2` (existující díly, levné). Merge screen v2 skin později (majitel připomínkuje).

### 10.3 Nové i18n klíče (cs; en)

Soubory:
- `translations_ext_59_rides_a.dart` (cs, en, de, es) a `_b.dart` (fr, nl, pl, uk) v OBOU stromech. 59 je volné v obou; při implementaci znovu ověřit.
- Případné v2-only klíče do `translations_ext_60_rides_v2.dart` jen v Android.
- Registrace v `translations.dart` jedním minimálním Editem.
- Plurál dnů: `rideDaysOne/Few/Many` + helper `rideDaysLabel(n, lang)`.
  - cs: den/dny/dní; pl: dzień/dni/dni; uk: день/дні/днів; ostatní one/other.

| Klíč | cs | en |
|---|---|---|
| ridePause | Pozastavit | Pause |
| ridePauseGpsOff | Pozastavit a vypnout GPS | Pause and turn off GPS |
| rideResume | Pokračovat | Resume |
| rideResumeTrip | Pokračovat v cestě | Continue the trip |
| rideEndSave | Ukončit a uložit | End and save |
| ridePhaseRiding | Nahrávám jízdu | Recording your ride |
| ridePhaseArmed | Připraveno — začnu nahrávat, až se rozjedeš | Ready — recording starts when you ride off |
| ridePhaseAuto | Stojíš — záznam je pozastavený | You're stopped — recording is paused |
| ridePhaseManual | Záznam pozastaven | Recording paused |
| ridePausedSince | od {time} | since {time} |
| ridePhaseAutoHint | Při zastávce, procházce nebo přes noc se záznam sám pozastaví a po rozjezdu pokračuje. Celá cesta zůstane jedním záznamem. | Stops, walks and nights pause the recording automatically; it resumes when you ride off. The whole trip stays one record. |
| ridePhaseManualHint | GPS je vypnuté a nic se nenahrává. Až vyrazíš, klepni na Pokračovat. | GPS is off and nothing is recorded. Tap Resume when you set off. |
| rideRentalEndsHint | Záznam skončí s vrácením motorky. | Recording ends when you return the bike. |
| rideHomeParked | Jsi zpátky tam, kde cesta začala — záznam čeká, GPS je vypnuté. | You're back where the trip started — recording is waiting, GPS is off. |
| rideLiveLine | {km} km · {time} jízdy | {km} km · {time} riding |
| rideDayN | {n}. den cesty | Day {n} of the trip |
| ridePausedToast | Záznam pozastaven. GPS je vypnuté. | Recording paused. GPS is off. |
| rideResumedToast | Pokračuju — nahrávat začnu, až se rozjedeš. | Resumed — recording starts when you ride off. |
| rideTripContinuedNew | Předchozí cesta se po 3 dnech bez jízdy uložila. Tahle jízda se nahrává jako nová — obě můžeš později sloučit. | Your previous trip was saved after 3 days without riding. This ride is recorded as a new one — you can merge them later. |
| rideRecordingDeleteQ | Tahle jízda se právě nahrává — smazáním se záznam zastaví. | This ride is being recorded — deleting it stops the recording. |
| rideStatPauses | pauzy | pauses |
| rideStatElapsed | doba cesty | trip duration |
| rideStatDays | dny na cestě | days on the road |
| ridePauseLegend | Modrá přerušovaná čára = přesun během pauzy, do kilometrů se nepočítá. | Blue dashed line = moved while paused, not counted in distance. |
| rideGapNotice2 | (viz §10.1) | Part of the route is unknown — your phone stopped sending its location for a while (app closed, weak signal or location off). Grey dotted parts are just connectors; you may not have ridden there and they aren't counted. |
| rideTripChip | Cesta | Trip |
| rideTripRental | Výpůjčka {moto} | Rental {moto} |
| rideTripDefault | Cesta {dates} | Trip {dates} |
| rideTripMerge | Sloučit jízdy | Merge rides |
| rideTripMergeHint | Vyber jízdy, které patří k jedné cestě. Statistiky se sečtou, jízdy zůstanou zachované a cestu můžeš kdykoli zase rozdělit. | Pick the rides that belong to one trip. Stats are added up, the rides are kept and you can split the trip again any time. |
| rideTripMergeBtn | Sloučit ({n}) | Merge ({n}) |
| rideTripMinTwo | Vyber aspoň dvě jízdy. | Pick at least two rides. |
| rideTripNameTitle | Pojmenuj cestu | Name the trip |
| rideTripMerged | Jízdy jsou sloučené do jedné cesty. | Rides merged into one trip. |
| rideTripUndo | Zpět | Undo |
| rideTripAddTo | Přidat k jiné jízdě… | Add to another ride… |
| rideTripRename | Přejmenovat cestu | Rename trip |
| rideTripSplit | Rozdělit cestu | Split trip |
| rideTripSplitQ | Rozdělit cestu na jednotlivé jízdy? Jízdy, fotky i zastávky zůstanou, jen se zase zobrazí každá zvlášť. | Split the trip into separate rides? Rides, photos and stops stay; they're just shown one by one again. |
| rideTripSplitDone | Cesta je rozdělená na jednotlivé jízdy. | The trip is split into separate rides. |
| rideTripDeleteQ | Smazat celou cestu? Smaže všech {n} jízd včetně fotek a zastávek a nejde to vrátit. Pokud chceš jen zrušit sloučení, zvol Rozdělit cestu. | Delete the whole trip? All {n} rides incl. photos and stops are deleted for good. To just undo the merge, choose Split trip. |
| rideTripStages | Etapy | Stages |
| rideTripStageLine | {day} · {from}–{to} · {km} km · {time} jízdy | {day} · {from}–{to} · {km} km · {time} riding |
| rideTripMembers | Jízdy v cestě | Rides in this trip |
| rideTripPartOf | Součást cesty {name} | Part of the trip {name} |
| rideTripFailed | Sloučení se nepovedlo — zkontroluj připojení a zkus to znovu. | Merging failed — check your connection and try again. |
| rideTripPartial | Některé jízdy se nepodařilo upravit — obnov seznam a zkus to znovu. | Some rides couldn't be updated — refresh the list and try again. |
| rideTripUnavailable | Slučování jízd zatím nejde — server ještě nemá potřebnou aktualizaci. Zkus to později. | Merging isn't available yet — the server hasn't been updated. Try again later. |
| rideNotifDefTitle / Text | MotoGo24 · záznam jízdy / Nahrávám, jen když jedeš. Při zastávce se záznam sám pozastaví. | MotoGo24 · ride recording / Recording only while you ride. Stops pause it automatically. |
| rideNotifRidingTitle / Text | MotoGo24 nahrává jízdu / Při zastávce se záznam sám pozastaví a po rozjezdu pokračuje. | MotoGo24 is recording your ride / Stops pause it automatically; it resumes when you ride off. |
| rideNotifArmedTitle / Text | MotoGo24 · připraveno k záznamu / Nahrávat začnu, až se rozjedeš. | MotoGo24 · ready to record / Recording starts when you ride off. |
| rideNotifPausedTitle / Text | MotoGo24 · jízda pozastavena / Stojíš od {time}, nic se nenahrává. Po rozjezdu záznam sám pokračuje. | MotoGo24 · ride paused / Stopped since {time}, nothing is recorded. It resumes when you ride off. |
| rideA11yPause / Resume | Pozastavit záznam jízdy / Pokračovat v záznamu jízdy | Pause ride recording / Resume ride recording |

Dnešní `rideNotifTitle`/`rideNotifText` zůstávají (4.1.3 je nečte z nového souboru). Nový klient použije `rideNotifDef*`.

---

## 11. Velín (`velin/`, `npm run build`)

| Soubor | Změna |
|---|---|
| `src/lib/rideTrack.js` | Úsek před bodem s `kmh < 0` = pauza. Odvozená pauza (dt ≥ 300, ≤ 0,3 km) není mezera. Hranice 30 d místo 86 400. `rideRecState(r)` → `live` (fix < 15 min) / `standing` / `stuck`. `stuck` u výpůjčky jen když je ukončená (v BookingLiveMap podle `booking_status`); u `pause_aware` vlastní > 72 h; u legacy vlastní > 3 h. Plus `fmtDurLong` (dny). |
| `TrasyJizdy.jsx` | `RIDE_LIST_COLS` + `pause_sec, pause_aware, trip_id, trip_name` (legacy fallback na 42703 už existuje: přidat je i do vyřazení). Odznak „⏸ Stojí od HH:MM“ místo „Záznam visí“ podle `rideRecState`. Sloupec pauzy. Odznak „🧳 {trip_name}“. |
| `TrasyJizdaModal.jsx` | Grid + pauzy, doba cesty (dny), dny/etapy (z `rideTrack.js`). Stav „stojí“ vs „visí“ (tlačítko Ukončit záznam u obou). |
| `TrasyJizdaMapa.jsx` | Pauza s posunem modrošedě přerušovaně, popisek „pauza {čas}“ |
| `booking/BookingLiveMap.jsx` | „Poslední poloha {čas} — motorka od té doby stojí, nebo appka neběží“ místo „visí“, dokud výpůjčka běží. `is_standing`. |
| `src/lib/rideDiag.js` | Popisky akcí z §5.9 |

---

## 12. Kompatibilita

| Klient × server | Start | Noc / dlouhé stání | Více dní | Statistiky | Sloučení |
|---|---|---|---|---|---|
| **4.1.3 × starý SQL** | dnes | dělí 3 h / 36 h | víc jízd | dnes | — |
| **4.1.3 × nový SQL** | `start_user_ride` stejné odpovědi | výpůjčka se **nedělí** (obnoví i po noci), vlastní legacy 3 h jako dnes | výpůjčka = 1 jízda; vlastní dělí jako dnes | noc = pauza (odvozená), chůze/drift bez km, max/převýšení opravené, pozdní Stop ořízne, auto po vrácení se zahodí | v nové appce |
| **nová appka × starý SQL** | `start_user_trip` 404 → `start_user_ride` (`caps.trips=false`, znovu za 1 h) | auto-pauza i ruční pauza lokálně (nic se neposílá). Server po 3 h uzavře → appka **naváže novou jízdou** i u vlastní (žádná ztráta, žádný tichý konec). Značka −1 se ignoruje → noc = stání/mezera (dnes). | víc jízd (výpůjčka se v UI seskupí podle `booking_id`) | dnešní serverové, živé km z odpovědí `append` | skryté (žádný `trip_id` v JSON) |
| **nová appka × nový SQL** | `start_user_trip` (`pause_aware`, `now`) | jedna cesta, pauzy značené | 1 cesta (výpůjčka do vrácení, vlastní do Ukončit / 72 h ticha / domů) | vše §8 | ano |
| Velín starý × nový SQL | — | pozastavená výpůjčka po 3 h „Záznam visí“ (nepravda) → **nasadit Velín se SQL** | | čte jen stará pole | — |
| Velín nový × starý SQL | sloupce chybí → existující fallback 42703 | | | | |

---

## 13. Soubory (vlastnictví, velikost ≤ ~5 000 tokenů)

**Nové sdílené (oba stromy, identické, `lib/features/routes/`)**

| Soubor | Obsah |
|---|---|
| `ride_motion.dart` | detektor + prahy; když přeroste, `ride_motion_rules.dart` |
| `ride_recorder_pause.dart` | `part of 'ride_recorder.dart'`: pause/resume/discardCurrent, meta persistence, notifikace, pravidlo domů, continuation. `part` sdílí privátní stav. |
| `ride_live_stats.dart` | klasifikátor, živé součty, dny/etapy |
| `ride_trip.dart` | `RideTrip`, `groupRides`, agregát, undo mapy |
| `ride_trip_api.dart` | `startUserTrip`, `setUserRidesTrip`, PGRST202, `rideCapsProvider` |
| `ride_rec_controls.dart` | old karta, čip, nav čip; `ride_rec_sheet.dart` (`showRidePauseSheet`) |
| `ride_stats_grid.dart`, `ride_stages_section.dart` | old look |
| `ride_trip_list.dart`, `ride_merge_screen.dart`, `ride_trip_detail_screen.dart` | Android verze s v2 švem, iOS bez něj (záměrný rozdíl podle pravidla 6) |
| `core/i18n/translations_ext_59_rides_a.dart`, `_b.dart` | i18n |

**Upravené sdílené (oba stromy)**
- `ride_recorder.dart`: stav, `part`, háčky detektoru, `RideServerApi`, outcome append.
- `ride_location.dart`: `kmh` jen platný, alt přesnost, offset hodin, `RideKeepAlive.notify`.
- `ride_provider.dart`: append vrací outcome se součty, `closed` vs `gone`.
- `ride_model.dart`: `pauseSec, pauseAware, tripId, tripName`, `RideGap.kind`, hranice 30 d.
- `ride_card.dart`, `ride_detail_screen.dart`, `ride_share.dart`, `ride_map.dart`, `ride_booking_section.dart`, `ride_start_feedback.dart`.
- `my_experiences_screen.dart`: 2 švy.
- `community_submit.dart`.
- `route_nav_status.dart`.
- `ride_recorder_watcher.dart`: jen ochrany fáze, pokud nestačí `recording`.
- ⚠ `core/cache_cleanup_service.dart`: 2 klíče do `_preserveKeys`.
- ⚠ `route_navigation_screen.dart`: 1 řádek, čip.
- `core/i18n/translations.dart`: 1 řádek registrace.

**Jen Android**
- v2 soubory §10.2, `ride_actions.dart`.
- Nové `v2/rides/ride_stages_v2.dart`, `v2/rides/ride_trip_detail_v2.dart`, `v2/rides/recorder_controls_v2.dart`.
- Nativní `RideEngineKeeper.kt` (+`notify`, `cancel`) a `MainActivity.kt` (jen registrace, pokud handler sedí tam).

**Kontrola synchronizace stromů**
- `diff -rq` obou `lib/` smí navíc ukázat jen v2 švy (detail cesty, merge screen, ride_trip_list) a dnešní záměrné rozdíly.
- Logika (`ride_motion`, `ride_live_stats`, `ride_trip`, `ride_recorder*`, `ride_location`, `ride_provider`, `ride_model`) musí být **bajtově stejná**.

---

## 14. Nasazení a rozhodnutí majitele

1. Postup implementace:
   - SQL drafty 01–05 do `scratchpad/rides/sql/` + `STATE_PATCH.md` (přesný text pro STATE_1: sloupce; STATE_3: RPC; STATE_5: cron, flag; STATE_6: changelog).
   - Test na PG 2× + simulace §15.2.
   - Appka (oba stromy) + Velín.
   - Ověření: `flutter analyze` (baseline A 147/0, I 143/0, nic nového), testy, `npm run build`.
2. **Majitel schválí SQL** → commit migrací (autodeploy). Zároveň merge Velínu (Vercel), aby pozastavené výpůjčky nebyly „visí“. Pak STATE dokumenty z `STATE_PATCH.md`.
3. Vydání appky Android (4.2.x, i v2) a iOS (další verze se sdílenou logikou a starým UI). Pořadí SQL × appka je libovolné (§12), doporučeně SQL dřív.
4. Sledování:
   - Velín → jízda → Diagnostika (`pause/resume/tail_*`),
   - poměr `pause_sec` / `moving_sec`,
   - stížnosti.
   - Při problému přepínač `ride_autopause` ve Velínu → Texty webu → Feature flags. Vypnutí vrátí chování „bez auto-pauzy“, ruční pauza zůstane.

Rozhodnutí majitele:
- (a) Pravidla serveru:
  - výpůjčka se nedělí u žádného klienta,
  - vlastní cesta 72 h ticha / 30 dní,
  - konec k poslednímu fixu,
  - body po vrácení pryč,
  - oprava dat „noc → pauza“.
- (b) Pravidlo „doma“ (3 h, 500 m, ≥ 10 km).
- (c) Hluboká noc: zatím ne.
- (d) Prahy 5 min / 3 min. Mění se konstantami, ne SQL.

---

## 15. Testy

### 15.1 Dart (Android `test/`, iOS kopie v rsync kopii; FakeGeo, `SharedPreferences.setMockInitialValues`, `RideServerApi` fake)

**`ride_motion_test.dart`**

Syntetické stopy (`Position` s `hasSpeed/hasSpeedAccuracy/hasAccuracy: true`):
1. 60 km/h → semafor 90 s → jízda: bez pauzy, held vyslán.
2. Stop → ticho 12 h → ráno 2× 25 km/h: jedna pauza od kotvy, pre-roll od ≥ 8 km/h, první bod `kmh = −1`.
3. Stop → chůze 4–6 km/h 10 min/600 m → zpět → jízda: pauza (walk) ~3 min, ocas zahozen, obnova u kotvy, nic obnoveno.
4. Kolona 5 km/h 5 min / 400 m → jízda z konce: `tail_restore` prefixu, pauza jen do konce kolony, bez značky < 60 s.
5. Hledání parkování 150 m pomalu + procházka tam a zpět → obnoven JEN prefix k motorce (nejdřívější index ≤ 100 m).
6. 90 km/h → ticho 4 min → fix 6 km dál v 90 km/h: žádná pauza, mezera.
7. Drift v pokoji (30–60 m, acc 40–80, bez Doppleru): zůstává pauza, žádná obnova, nic se neposílá.
8. Jeden Doppler výkyv 25 km/h při chůzi: žádná obnova.
9. Wi-Fi fixy bez rychlosti 350 m / 40 s: záložní obnova.
10. iOS cache fix po připojení: ignorován.
11. Ticho po 30+ km/h a další fix 100 m v 2 h (garáž): pauza `silence`.
12. Obnova po zabití 50 km od kotvy: bez značky (mezera).
13. Kill-switch vypnuto: nikdy pauza, nic nedrženo.
14. „Doma“: start A, 40 km, stání u A 3 h → `manualPaused(home)`.

**`ride_live_stats_test.dart`**
- Parita klasifikace se SQL vektory (stejná JSON data jako §15.2 `stats_vectors.sql`): pauza značená/odvozená, mezera, skok, drift bez km, legacy chůze, max 10–60 s, převýšení hystereze napříč dávkami.
- Etapy: noc 00–05, pauza ≥ 2 h, hranice řádků.
- Dny.
- Přeškálování na serverové součty.

**`ride_trip_test.dart`**
- `tripKey` (explicitní > výpůjčka > samostatná, `trip_id = id`).
- Agregát (součty, avg, max, doba, společný booking).
- Výchozí názvy.
- Undo mapa merge/split (návrat přesně k předchozímu stavu včetně implicitní výpůjčky).

**`ride_recorder_pause_test.dart`**
- pause → stream zrušen, `RideKeepAlive.set(false)`, meta uložena;
- `_restore` v `manualPaused` nepřipojí;
- `ensureRecording` při pauze nic;
- `onAppResumed`/`foreign_closed`/`service_on` při pauze nic;
- resume → attach + armed + značka;
- `closed` u vlastní → nová cesta + `notice`;
- `gone` u vlastní → stop;
- `booking_inactive` → stop bez finish;
- PGRST202 → fallback `start_user_ride` + `caps`;
- offline ≠ fallback;
- `discardCurrent` před mazáním;
- stop během auto-pauzy pošle buffer bez held.

**Ostatní**
- `ride_point_test.dart`: `kmh` jen platný, alt přesnost, offset hodin (−2 h, +7 h).
- `cache_preserve_test.dart`: `mg_ride_rec_meta`, `mg_ride_caps` přežijí `CacheCleanupService.run()`.

### 15.2 SQL (PG 16, `pg/setup.sh`; drafty 2×; `t_shim()` s filtrem i na `trip`)

- Simulátor (`pg/sim/`): přidat **NewClient2** (pause-aware dle §5: held, pauza bez bodů, značka −1, `start_user_trip`, continuation vlastní).
- Spustit S1–S10 pro OldClient (4.1.3), NewClient (PR #2208) i NewClient2 a nové scénáře:

| Scénář | Očekávání |
|---|---|
| S11 7denní vlastní, NewClient2, noci bez fixu | 1 řádek, km ≈ pravda (±1 %), `pause_sec` ≈ noci, `idle_sec` < 1 h/den, mapa: každý den ≥ 300 bodů |
| S12 3denní výpůjčka, NewClient2 + auto po vrácení | 1 řádek, konec ≤ returned_at, žádné km po vrácení, žádná prázdná jízda |
| S13 3denní výpůjčka, **OldClient** | 1 řádek (nedělí se), noci = pauza |
| S14 vlastní 2 dny, OldClient | rozdělí se jako dnes (legacy 3 h) |
| S15 chůze 40 min, OldClient | km bez chůze (±0,5 km), Ø ≈ 78 |
| S16 pozdní Stop 2,5 h, oba klienti | konec = poslední fix, `idle` + < 5 min |
| S17 hodiny −2 h / +7 h, NewClient2 | nic se nezahodí, jízda uložena |
| S18 `set_user_rides_trip`: merge 3, split, undo, cizí id, špatný tvar | `updated` správně, cizí neovlivněno, `bad_items` |
| S19 převýšení (`elev_check.sql` + sim kopce) | 85–105 % pravdy na stoupáních, rovina σ3 < 100 m/100 km |
| S20 cap 30 000 bodů po dávkách | starší dny rovnoměrně (±25 %), kraje pauz drženy, ≤ 9 ms/dávka |
| S21 cron | výpůjčka nepřeruší po 3 h/36 h, uzavře 10 min po vrácení; vlastní `pause_aware` 72 h; legacy 3 h |
| S22 oprava dat | uzavřené jízdy: `pause_sec` z mezer stání, `idle` sníženo, km beze změny; druhý běh nic |
| S23 přetížení | žádné duplicitní `proname`; práva anon/authenticated |

### 15.3 Velín a appka

- `cd velin && npm run build`.
- Ruční kontrola ve Velínu (seznam/modal/mapa/BookingLiveMap) na datech ze simulace přes `psql` dump → JSON.
- `flutter analyze` obou stromů (iOS v rsync kopii, `pub get --offline`): žádný nový problém.
- `flutter test`.
- `diff -rq` lib/.

---

## 16. Rizika a známé limity

- **Taxi / autobus / trajekt** se po auto-pauze nahraje jako jízda (bez rozpoznání aktivity bez balíčku). Náprava: ruční pauza. Budoucí volba „odstranit úsek“.
- **Kolona pod 12 km/h**: Velín vidí polohu se zpožděním ≤ 5 min. Velmi pomalá kolona < 150 m se může započítat jako pauza.
- **Baterie přes noc** v auto-pauze (5–15 %). Je to vědomé: rozjezd jinak poznat nejde. Ruční pauza / pravidlo domů ji eliminuje.
- **Odhad dnů a etap** z prořídnuté stopy je přeškálovaný na serverové součty (Σ sedí, jednotlivé etapy ± několik %).
- **Android notifikace** podle stavu závisí na tom, že geolocator používá id 75415 a kanál `geolocator_channel_01` (ověřeno ve zdroji 4.6.2 i 5.1.1). Při změně pluginu se notifikace vrátí k statickému textu, funkce se nerozbije.
- **4.1.3 vlastní jízdy** se dál dělí na noc (legacy 3 h). Je to záměr: 4.1.3 nemá auto-pauzu a zapomenutá jízda by jinak nahrávala vše až 30 dní.
