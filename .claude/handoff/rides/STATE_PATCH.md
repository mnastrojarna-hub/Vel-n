# STATE_PATCH — záznam jízd: pauza, auto-pauza, vícedenní cesty, slučování

Kdy se to použije: až majitel schválí SQL. Úpravy patří do STEJNÉHO commitu jako migrace (a Velín).
Pravidla:
- Nic se nepřepisuje. Každá úprava je buď **APPEND** (text se přidá na konec existujícího řádku/odrážky, před koncové ` |`), nebo **INSERT** (nový řádek tabulky / nová sekce na udané místo).
- Kotva = přesný úsek textu, který v souboru je (ověřeno 2026-10-22 na větvi `claude/moto-go-mobile-conversion-gqg5qo`).
- Názvy migrací v textu níže počítají s datem `20261023`. Pokud se commituje později, nahraď ve všech blocích `20261023` datem commitu. Prefix musí řadit ZA vše v `main` (dnes poslední `20261022b_live_viewers.sql`).

Mapování draftů → názvy při commitu:

| Draft (`scratchpad/rides/sql/`) | Migrace |
|---|---|
| `01_rides_columns.sql` | `20261023_user_rides_pause_a.sql` |
| `02_rides_stats_core.sql` | `20261023_user_rides_pause_b.sql` |
| `03a_rides_append.sql` | `20261023_user_rides_pause_c.sql` |
| `03b_rides_finish.sql` | `20261023_user_rides_pause_d.sql` |
| `04_rides_start_cron.sql` | `20261023_user_rides_pause_e.sql` |
| `05_rides_trip_group.sql` | `20261023_user_rides_pause_f.sql` |
| `06_rides_backfill.sql` (VOLITELNÉ, jen se souhlasem majitele) | `20261023_user_rides_pause_g.sql` |

Pokud majitel přepočet starých jízd (`_g`) neschválí, vynech v blocích níže všechny věty označené **[jen s _g]**.

---

## STATE_1 (Tabulky)

### 1a — APPEND do řádku `user_rides`
Kotva (konec řádku): `Diagnostika záznamu z appky jde do `app_debug_logs` (kategorie `ride`), Velín ji ukazuje v detailu jízdy. |`
Vlož PŘED koncové ` |`:

```
 **UPDATE 2026-10-23 (`20261023_user_rides_pause_a…f.sql`, APLIKUJE AUTO-DEPLOY po merge) — pauza, auto-pauza, vícedenní cesty, slučování:** nové sloupce `pause_sec` int NOT NULL DEFAULT 0 (čas pauz: bod s `kmh = -1` od appky = pauza od předchozího bodu, ticho ≥ 5 min bez projetí ≥ 15 km/h, u starých appek běh stání/chůze ≥ 5 min; NEpatří do `idle_sec`/`gap_sec`/`moving_sec`/`duration_min`), `pause_aware` bool NOT NULL DEFAULT false (jízdu vede nová appka přes `start_user_trip` — pauzuje sama), `stats_state` jsonb (interní mezistav výpočtu mezi dávkami), `stages` jsonb NOT NULL DEFAULT '[]' (etapy/dny `[{f,t,km,mv,gap,ps,gain,max,a,b}]`, hranice = pauza ≥ 6 h nebo ≥ 30 min přes 00:00–05:00 Praha, max 60), `trip_id` uuid (bez FK; NULL = výchozí seskupení podle `booking_id`, = `id` = záměrně samostatná, jiná hodnota = člen sloučené cesty) + `trip_name` text (CHECK `user_rides_trip_name_len` ≤ 120), index `idx_user_rides_trip (user_id, trip_id) where trip_id is not null`. **Změna významu:** `duration_min` = NA CESTĚ BEZ PAUZ (start → konec minus `pause_sec`; u jízdy bez pauz stejné jako dřív), `idle_sec` = vždy ZBYTEK (na cestě − jízda − bez signálu), `moving_sec`/`distance_km` jen z úseků s Dopplerem ≥ 7 km/h (bez Doppleru odvozeně ≥ 15 km/h) → chůze ani „bloudění“ polohy v pokoji km nepřidají, `max_speed_kmh` jen z Dopplerovy rychlosti s kontrolou věrohodnosti (`p_max_speed_kmh` klienta se ignoruje; dál platí „max ≥ Ø“), `elevation_gain_m` vyhlazené (EMA 0,25 + práh 6 m). Strop stopy `4000 + 2000 × (etapy − 1)`, max 12 000 bodů; prořídnutí rovnoměrně podle vzdálenosti (rozestup 20 m · 2^k), drží okraje časových skoků > 180 s a značky pauz. Výpůjčka se už NEDĚLÍ přes noc u žádné verze appky (uzavře ji až konec výpůjčky); vlastní cesta nové appky se uzavře po 72 h bez jízdy / 30 dnech; vlastní jízda 4.1.3 beze změny (3 h / 36 h). Body > 30 s (nová appka) / > 2 min (4.1.3) po `bookings.returned_at` se nepřijmou a jízdu uzavřou k času vrácení (žádné km autem po vrácení). Slučování jízd do cest jen přes RPC `set_user_rides_trip` (appka skládá logiku). **[jen s _g]** `20261023_user_rides_pause_g.sql`: uzavřeným jízdám starých appek přesunuty noci a dlouhá stání z `duration_min`/`idle_sec` do `pause_sec` (km, čas jízdy, max ani stoupání beze změny; značka `stats_state = {"backfill":1}`).
```

### 1b — APPEND do řádku `feature_flags`
Kotva: ``| `feature_flags` | Feature flags (mj. `eshop_visible` — e-shop v menu webu/appky, default vypnuto od 2026-10-01; `self_service_delivery`, `reservation_upsell`, `loyalty_leaderboard`, `inventory_v2`) |``
Nahraď celý řádek tímto (jen přidán `ride_autopause`):

```
| `feature_flags` | Feature flags (mj. `eshop_visible` — e-shop v menu webu/appky, default vypnuto od 2026-10-01; `self_service_delivery`, `reservation_upsell`, `loyalty_leaderboard`, `inventory_v2`, `ride_autopause` — automatická pauza záznamu jízdy v appce, default zapnuto od 2026-10-23, prahy v `conditions`) |
```

---

## STATE_2 (Klíčové sloupce)

### 2a — INSERT nové sekce
Kotva: řádek `### sent_emails`. Vlož PŘED něj (s prázdným řádkem za blokem):

```
### user_rides — pauzy, etapy, cesty (NEW 2026-10-23 — `20261023_user_rides_pause_a.sql`)
- **pause_sec** int NOT NULL DEFAULT 0 — čas pauz (s). Zdroje: bod s `kmh < 0` (appka posílá `-1` na PRVNÍM bodu po pauze ≥ 60 s → interval od předchozího bodu je pauza), ticho > 3 min bez projetí ≥ 15 km/h a ≥ 5 min (noc bez fixu, jezero), u `pause_aware = false` běh stání/chůze ≥ 5 min (body uvnitř se ze stopy vyjmou). Do `idle_sec`, `gap_sec`, `moving_sec` ani `duration_min` NEpatří.
- **pause_aware** bool NOT NULL DEFAULT false — `true` = jízdu založila/převzala nová appka (`start_user_trip`). Řídí uzavírání (vlastní cesta 72 h bez jízdy / 30 dní místo 3 h / 36 h) a vypíná odvozování pauz z „běhu stání“ (nová appka pauzy posílá sama).
- **stats_state** jsonb NULL — interní mezistav přírůstkových statistik mezi dávkami (`legacy, ema, ref, palt, still_from, still_pt, has_dop, nodop_max, gr`). Nikde se nezobrazuje. `{"backfill":1}` = jízda přepočtená migrací `_g`.
- **stages** jsonb NOT NULL DEFAULT '[]' — etapy (dny) jedné jízdy: `{f, t}` epoch s, `km`, `mv` (s v pohybu), `gap`, `ps` (pauzy), `gain` (m), `max` (km/h), `a`/`b` `[lat,lng]`. Hranice = pauza ≥ 6 h, nebo ≥ 30 min zasahující do 00:00–05:00 Europe/Prague; max 60 etap (další se slučují do poslední). Počet dní = různá pražská data `f`/`t` etap s ≥ 5 min pohybu (`_ride_stage_days`).
- **trip_id** uuid NULL (bez FK) + **trip_name** text NULL (≤ 120, CHECK `user_rides_trip_name_len`) — sloučení jízd do cesty (jen zobrazení): NULL = výchozí seskupení podle `booking_id`, `= id` = záměrně samostatná, jiná hodnota = člen cesty s tímto klíčem; `trip_name` stejné u všech členů. Zapisuje JEN `set_user_rides_trip`.
- **Změna významu existujících sloupců:** `duration_min` = na cestě BEZ pauz; `idle_sec` = zbytek (`duration − moving − gap`), nikdy součet; `max_speed_kmh` z Dopplera (+ „max ≥ Ø“); `elevation_gain_m` vyhlazené EMA + 6 m.
```

---

## STATE_3 (RPC funkce)

### 3a — APPEND do řádku `start_user_ride(p_booking_id, p_lat, p_lng)`
Kotva (konec řádku): `bez `booking_id` (výpůjčka už neběží) ji hned uzavře a záznam ukončí. |`
Vlož PŘED koncové ` |`:

```
 **UPDATE 2026-10-23 (`20261023_user_rides_pause_e.sql`, APLIKUJE AUTO-DEPLOY po merge):** podpis, klíče i tvorba jízdy beze změny (4.1.3 funguje dál). Mění se jen obnova rozjeté jízdy: s výpůjčkou, která běží (`reserved/active`, `returned_at IS NULL`), a `p_booking_id` NULL nebo stejným → obnoví se v JAKÉMKOLI stáří (výpůjčka se přes noc už nedělí ani u 4.1.3); vlastní jízda nové appky (`pause_aware`, bez výpůjčky) do 72 h; jinak dál 3 h. Uzavírání neobnovené jízdy: u vrácené výpůjčky nejpozději k `returned_at`.
```

### 3b — APPEND do řádku `append_ride_track(p_ride_id, p_points jsonb, p_max_speed_kmh)`
Kotva (konec řádku): `Prořídnutí přes nový `_ride_track_cap` (viz níže). |`
Vlož PŘED koncové ` |`:

```
 **PŘEPSÁNO 2026-10-23 (`20261023_user_rides_pause_c.sql`, APLIKUJE AUTO-DEPLOY po merge):** stejný podpis, žádný nový chybový kód (`not_authenticated`, `points_required`, `ride_not_found`, `ride_finished`). Tělo deleguje na `_ride_append_core`: dávka se filtruje (body bez lat/lng, starší než start − 1 h `dropped_stale`, DUPLICITY po ztracené odpovědi — `ts` menší než poslední uložený / stejný bod → statistiky se nezapočítají dvakrát, body po `returned_at` + 30 s nová appka / + 2 min 4.1.3); dávka jen z bodů po vrácení (a server už > 2 min po vrácení) jízdu uzavře k času vrácení a vrátí `{success:false, error:'ride_finished', finished:true, reason:'booking_ended'}` (4.1.3 to bere jako „zapomeň“ → žádné km autem, žádné prázdné jízdy). Statistiky v2 (`_ride_stats_v2`), `p_max_speed_kmh` se IGNORUJE. „Připraveno“ (jen `pause_aware`, < 60 s jízdy a < 0,2 km): první bod se značkou pauzy posune `started_at` na skutečný rozjezd a zahodí bod P0. Odpověď navíc `pause_sec`, `stages_n`, `dropped`, `now` (epoch serveru — appka z něj srovná hodiny).
```

### 3c — APPEND do řádku `finish_user_ride(p_ride_id, p_points jsonb, p_name)`
Kotva (konec řádku): `hlídač zavolá finish a `now()` by přičetlo hodiny stání po vrácení. |`
Vlož PŘED koncové ` |`:

```
 **UPDATE 2026-10-23 (`20261023_user_rides_pause_d.sql`, APLIKUJE AUTO-DEPLOY po merge):** stejný podpis a klíče; poslední dávka jde přes `_ride_append_core` (s `FOR UPDATE`), konec = `now()`, u vrácené výpůjčky `greatest(returned_at, started_at)`, a `_ride_finalize` ho navíc stáhne na nejvýš 2 min po posledním bodu → Stop zmáčknutý doma o hodiny později už nepřidá stání. Odpověď navíc `pause_sec`, `days`.
```

### 3d — APPEND do řádku `get_my_rides(p_limit int default 100)`
Kotva (konec řádku): `Appka → Moje zážitky → Vytvořené trasy (sekce projetých jízd) + detail jízdy. |`
Vlož PŘED koncové ` |`:

```
 **UPDATE 2026-10-23:** přes `_ride_json` navíc klíče `pause_sec`, `pause_aware`, `trip_id`, `trip_name`, `stages` (totéž `get_booking_rides`, `get_public_rides`); `duration_min` = na cestě bez pauz. Těla funkcí beze změny.
```

### 3e — APPEND do řádku `_ride_finalize(p_ride_id uuid, p_ended_at timestamptz default null)`
Kotva (konec řádku): `Zbytek funkce beze změny, práva (REVOKE) zachována. |`
Vlož PŘED koncové ` |`:

```
 **PŘEPSÁNO 2026-10-23 (`20261023_user_rides_pause_d.sql`, APLIKUJE AUTO-DEPLOY po merge):** stejný podpis, REVOKE zachován. Konec = `coalesce(p_ended_at, last_fix_at, updated_at, now())`, ale nejvýš `last_fix_at + 2 min`; u staré appky (`pause_aware = false`) s rozběhnutým stáním/chůzí ≥ 5 min na konci se konec posune na jeho začátek a body za ním se ze stopy vyjmou. `duration_min = max(1, round((konec − start − pause_sec)/60))` (na cestě bez pauz), `idle_sec` = zbytek po jízdě a mezerách, Ø z času jízdy (≥ 60 s), jinak z času na cestě bez mezer, `max ≥ Ø`; poslední etapa se uzavře koncem; název bez zadání = datum, u vícedenní `DD.MM.–DD.MM.YYYY` (přes rok `DD.MM.YYYY–DD.MM.YYYY`); stopa prořídnutá stropem dle etap. < 1 km se dál maže. Odpověď (i `already_finished`) navíc `pause_sec`; nové uzavření i `days`.
```

### 3f — APPEND do řádku `close_stale_user_rides()`
Kotva (konec řádku): `cron jinak uzavřel i živě nahrávanou jízdu z telefonu s hodinami pozadu. |`
Vlož PŘED koncové ` |`:

```
 **PŘEPSÁNO 2026-10-23 (`20261023_user_rides_pause_e.sql`, APLIKUJE AUTO-DEPLOY po merge) — cesta se už nedělí přes noc:** (1) jízda s výpůjčkou (jakákoli appka) se uzavře JEN koncem výpůjčky — rezervace chybí, `status in (completed, cancelled)`, `returned_at` starší 10 min, `end_date` (datum) < dnešek Praha − 1 den, nebo jízda starší 60 dní — a to k `least(poslední život, returned_at)`; (2) vlastní cesta nové appky (`pause_aware`) po 72 h bez jízdy nebo 30 dnech; (3) vlastní jízda staré appky beze změny 3 h bez bodu / 36 h. `_ride_finalize` konec dál stáhne na ≤ poslední bod + 2 min. Dávka 500, výjimka po jízdě, návrat `{closed, discarded}` beze změny.
```

### 3g — APPEND do řádku `admin_booking_live_ride(p_booking_id uuid)`
Kotva (konec řádku): `Guard `is_admin()` → jinak `{ok:false, error:'forbidden'}`. plpgsql STABLE SECURITY DEFINER. GRANT authenticated. |`
Vlož PŘED koncové ` |`:

```
 **UPDATE 2026-10-23 (`20261023_user_rides_pause_e.sql`):** navíc `pause_aware`, `pause_sec` a `is_standing` = nahrávka běží, 15+ min bez bodu a výpůjčka běží (`reserved/active`, nevrácená) — nová appka mezi zastávkami nic neposílá, Velín pak píše „Motorka stojí od …“ místo „Záznam visí“. `is_live` beze změny; stopa prořídnutá na 1200 bodů novým `_ride_track_cap`.
```

### 3h — APPEND do řádku helperů `_ride_track_km` / `_ride_stats` / `_ride_track_cap` / `_ride_json`
Kotva (konec řádku): `by shodil migraci i `_ride_finalize`. |`
Vlož PŘED koncové ` |`:

```
 **UPDATE 2026-10-23 (`20261023_user_rides_pause_b.sql` + `_d`):** `_ride_stats` = obal nad `_ride_stats_v2` se stavem `legacy` (stejný podpis i klíče `dist_km, moving_sec, idle_sec, gap_sec, gain_m, max_kmh`; `idle_sec` = součet dt stání/ne-jízdy/skoků), STABLE SECURITY DEFINER (smí volat interní v2); appky ho nevolají. `_ride_track_cap` (stejný podpis) = nové prořídnutí: do `p_max` beze změny, nad ním rovnoměrně podle vzdálenosti s rozestupem `20 m · 2^k` (nejmenší k s délkou/rozestup ≤ 0,85 · p_max → opakované prořídnutí bere každý 2. bod a starší dny zůstanou rovnoměrné), vždy první/poslední bod, oba okraje časového skoku > 180 s, každý bod s `kmh < 0` i jeho předchůdce; ne-pole se zahodí; nouzově každý k-tý s okraji. ~40 ms na 12 000 bodů (PG16). `_ride_json` navíc `pause_sec, pause_aware, trip_id, trip_name, stages`.
```

### 3i — INSERT nových řádků
Kotva: řádek začínající ``| `get_route_reviews(p_route_id uuid)` |``. Vlož PŘED něj tyto řádky:

```
| `start_user_trip(p_booking_id uuid)` | **NEW 2026-10-23 (`20261023_user_rides_pause_e.sql`, APLIKUJE AUTO-DEPLOY po merge):** start / převzetí záznamu pro NOVOU appku (bez DEFAULT, žádné přetížení — `start_user_ride` zůstává pro 4.1.3). S `p_booking_id`: jen vlastní rezervace `reserved/active` a NEvrácená, jinak `{success:false, error:'booking_inactive', now}` a NIC nevznikne. Rozjetá jízda se stejnou rezervací (výpůjčka v jakémkoli stáří; vlastní do 72 h) se převezme: `pause_aware = true`, rozběhnuté stání starého výpočtu se zahodí, `updated_at` se u už převzaté jízdy neposouvá. Jiná rozjetá jízda se uzavře (`_ride_finalize`, u vrácené výpůjčky k `returned_at`). Nová jízda: `pause_aware = true`, `source = auto`, prázdná stopa (první bod P0 pošle appka), BEZ párování podle data (ruční jízda v den výpůjčky už není výpůjčka). Souběh (dva starty naráz) → `unique_violation` se zachytí a vrátí vzniklou jízdu jako `resumed`. Vrací `{success, id, resumed, booking_id, moto_name, pause_aware, started_at, distance_km, moving_sec, pause_sec, stages_n, now}` (`now` = epoch serveru pro srovnání hodin telefonu). plpgsql SECURITY DEFINER. REVOKE public/anon, GRANT authenticated + service_role. |
| `set_user_rides_trip(p_items jsonb)` | **NEW 2026-10-23 (`20261023_user_rides_pause_f.sql`, APLIKUJE AUTO-DEPLOY po merge):** zapisovač `trip_id` / `trip_name` u VLASTNÍCH jízd volajícího (sloučení do cesty, rozdělení, přejmenování, vyjmutí i „Zpět“ skládá appka). `p_items = [{id, trip_id|null, trip_name|null}]`, 1–300 položek; špatný tvar / neplatné uuid → `{success:false, error:'bad_items'}`; název `trim`, max 120, prázdný = NULL; duplicitní id = vyhraje poslední. Cizí/neexistující id se tiše přeskočí → `{success:true, updated:n}` (appka porovná s počtem). Jízdy, body, fotky ani statistiky se nemění. plpgsql SECURITY DEFINER. REVOKE public/anon, GRANT authenticated + service_role. |
| `_ride_stats_v2(p_seg jsonb, p_state jsonb, p_stages jsonb)` | **NEW 2026-10-23 (`20261023_user_rides_pause_b.sql`):** jádro statistik (interní). Dvojice bodů (p = předchozí bod s časem, u první dvojice dávky poslední uložený bod): bez času → km; dt < 0 nebo ≥ 30 dní → nic; `kmh < 0` → PAUZA [p, q]; dt > 180 s: ≥ 15 km/h a > 0,3 km → BEZ SIGNÁLU, jinak dt ≥ 300 s → PAUZA, jinak stání; ≥ 250 km/h (nebo dt = 0 a ≥ 0,5 km) → skok; dt = 0 s Dopplerem ≥ 7 → jen km; ≥ 3 km/h a (Doppler ≥ 7 km/h nebo bez Doppleru ≥ 15 km/h při dt ≥ 3 s) → JÍZDA (km, čas, max = Doppler ≤ 1,5·v + 20 při dt ≥ 4 s, stoupání EMA 0,25 + práh 6 m, filtr skoků výšky 0,25·d + 10 m; vyhlazení startuje od výšky předchozího bodu); jinak ne-jízda (chůze, „bloudění“). Stav `legacy` (stará appka): běh ne-jízdy/stání/ticha bez projetí ≥ 5 min se při další jízdě/mezeře/značce uzavře jako PAUZA a body uvnitř jdou do `trims` (skok běh nepřeruší). Etapy dle STATE_2. Vrací `{dist_km, moving_sec, gap_sec, pause_sec, idle_sec, gain_m, max_kmh, nodop_max_kmh, trims, stages, state}`. plpgsql STABLE. REVOKE public/anon/authenticated, GRANT service_role. |
| `_ride_append_core(p_ride_id uuid, p_points jsonb)` | **NEW 2026-10-23 (`20261023_user_rides_pause_c.sql`):** společné jádro `append_ride_track` a `finish_user_ride` (volající drží `FOR UPDATE`): filtr dávky, „připraveno“, statistiky v2, vyjmutí `trims`, strop stopy dle etap, součty a odvozené hodnoty (zastávky = zbytek). Dávka jen po vrácení výpůjčky → uzavře jízdu a vrátí `{booking_ended:true, finalize:{…}}`. plpgsql SECURITY DEFINER. REVOKE public/anon/authenticated, GRANT service_role. |
| `_ride_prague_night(p_from float8, p_to float8)` / `_ride_stage_days(p_stages jsonb)` | **NEW 2026-10-23 (`20261023_user_rides_pause_b.sql`):** pomocné (interní): zasahuje interval (epoch s) do 00:00–05:00 Europe/Prague? / počet dní cesty z etap (různá pražská data `f`/`t` etap s ≥ 300 s pohybu, min. 1). sql STABLE. REVOKE public/anon/authenticated, GRANT service_role. |
```

---

## STATE_5 (RLS, Realtime, Edge, Storage, Secrets, Cron, FK)

### 5a — APPEND do odrážky „Moje jízdy — vlastník + admin“
Kotva (konec odrážky): `Appka jede výhradně přes SECURITY DEFINER RPC (`start_user_ride`, `append_ride_track`, `finish_user_ride`, `save_ride_point`, …).`
Vlož ZA ni (stejný řádek):

```
 **UPDATE 2026-10-23:** RLS beze změny; nové sloupce (`pause_sec`, `pause_aware`, `stats_state`, `stages`, `trip_id`, `trip_name`) kryjí stávající politiky. Nová appka startuje přes `start_user_trip`, sloučení cest zapisuje JEN `set_user_rides_trip` (obě authenticated, ne anon); interní `_ride_stats_v2`, `_ride_append_core`, `_ride_prague_night`, `_ride_stage_days` (+ dál `_ride_finalize`) nemá authenticated ani anon.
```

### 5b — INSERT odrážky feature flagu
Kotva: odrážka začínající `- **Feature flag `loyalty_leaderboard`**`. Vlož PŘED ni:

```
- **Feature flag `ride_autopause`** (**NEW 2026-10-23, `20261023_user_rides_pause_a.sql`, APLIKUJE AUTO-DEPLOY po merge**; řádek v `feature_flags`, default **true**, `ON CONFLICT DO NOTHING` — ruční změna se migrací nepřepíše): automatická pauza záznamu jízdy v appce. `conditions` = `{"stop_min":5,"walk_min":3,"resume_kmh":20,"home_h":3,"long_h":20}` (stání / chůze do pauzy v min, rozjezd km/h, hlídač „doma“ a „dlouhá pauza“ v h; `long_h = 0` vypne). Vypnuto = appka nahrává bez auto-pauzy (bez „připraveno“), ruční pauza, nedělení cest, slučování i statistiky zůstávají. Prahy jdou měnit bez vydání appky.
```

### 5c — APPEND do řádku cronu `close-stale-user-rides`
Kotva: řádek začínající ``| `close-stale-user-rides` | každých 15 min`` (jediný; končí `… (EXCEPTION → WARNING). |` — stejná koncovka je i u jiných cronů, proto hledej podle začátku řádku).
Vlož PŘED koncové ` |` TOHOTO řádku:

```
 **UPDATE 2026-10-23 (`20261023_user_rides_pause_e.sql`, job beze změny `*/15`, mění se jen funkce):** výpůjčka se uzavře až koncem výpůjčky (vrácení +10 min / storno / dokončení / 2 dny po `end_date` / 60 dní) k času vrácení; vlastní cesta nové appky (`pause_aware`) po 72 h bez jízdy nebo 30 dnech; vlastní jízda appky 4.1.3 dál po 3 h bez bodu / 36 h.
```

---

## STATE_6 (Changelog)

### 6a — INSERT nového řádku na začátek tabulky
Kotva: řádek `|-------|-------|` (hned pod hlavičkou `| Datum | Změna |`). Vlož ZA něj:

```
| 2026-10-23 (záznam jízd: pauza, auto-pauza, vícedenní cesty, slučování, statistiky — zadání majitele 2026-10-22 „chybí pauza… nesmyslné statistiky… mělo by to samo pauznout… nedělit cestu… sloučit více tras do jednoho tripu“; **SQL `20261023_user_rides_pause_a…f.sql` [+ volitelně `_g` přepočet historie], APLIKUJE AUTO-DEPLOY po merge; ověřeno na lokálním PG16 se živým schématem (snapshot df555c93): čistý cluster, 2× aplikace bez chyby, 168/168 kontrol 2× (vektory V1–V15 + cap 60 etap, vlastní/výpůjčka/4.1.3, cron, převzetí, souběh startů, slučování, prořídnutí 30 000 bodů, práva), podpisy existujících RPC beze změny, 0 přetížení; 57 cílů přehrávek reálných scénářů splněno 56** (výjimka: nastoupáno 82 % pravdy u dne s 8m vlnkami terénu, cíl 85 %)) | **FEAT+FIX.** **SERVER:** nové sloupce `user_rides.pause_sec`, `pause_aware`, `stats_state`, `stages`, `trip_id`, `trip_name` (STATE_2); statistiky v2 (`_ride_stats_v2`): pauza = značka od appky / ticho ≥ 5 min bez projetí / u 4.1.3 běh stání nebo chůze ≥ 5 min (vyjmut ze stopy), jízda jen s Dopplerem ≥ 7 km/h → chůze a „bloudění“ v pokoji nepřidají km ani čas, max jen z Dopplera, stoupání vyhlazené, zastávky = zbytek, `duration_min` = na cestě BEZ pauz, etapy po dnech; nové RPC `start_user_trip` (nová appka, „připraveno“ = start jízdy až rozjezdem, oprava hodin telefonu z `now`) a `set_user_rides_trip` (sloučení/rozdělení cest + Zpět); výpůjčka se přes noc NEDĚLÍ u žádné appky (cron i `start_user_ride`), vlastní cesta nové appky do 72 h bez jízdy, 4.1.3 vlastní beze změny 3 h / 36 h; body po vrácení výpůjčky (+30 s / 4.1.3 +2 min) jízdu uzavřou k času vrácení (konec km autem a prázdných jízd); opakovaná dávka po ztracené odpovědi se nezapočítá dvakrát; pozdní Stop/úklid končí ≤ 2 min po posledním bodu; strop stopy až 12 000 bodů s rovnoměrným prořídnutím (značky pauz a okraje mezer zůstávají); Velín „Mapa a poloha“ dostává `is_standing`, `pause_aware`, `pause_sec`; příznak `ride_autopause` (prahy v `conditions`). **[jen s _g]** Přepočet uzavřených jízd starých appek: noci/dlouhá stání → `pause_sec` (km, čas jízdy, max, stoupání beze změny). **Kompatibilita:** 4.1.3 i vývojová verze PR #2208 beze změny volání a kódů (přehrávky: výpůjčka 2 dny = 1 jízda místo 2, chůze 40 min se nezapočte, 3 drift noci = 1 jízda bez fantomových km); nová appka funguje i proti starému serveru (fallback, noc se tam dál dělí, ale záznam nikdy tiše nekončí). **Přehrávky (truth → uloženo):** den 331,7 km → 331,0 km, 1 jízda, pauzy 96 min zvlášť, na cestě 313 min (dřív 412 min s 116 min „stání“); 2 dny vlastní 588,3 → 587,5 km, 1 jízda, 2 etapy, noc = pauza (dřív 385,8 km — 2. den ztracen); 7denní cesta 2 537 → 2 533 km, 1 jízda, 7 etap/7 dní (dřív 334 km); výpůjčka + auto po vrácení 201,7 → 201,3 km, max 97,3 (dřív 218,4 km, max 104 autem); 40 min pěšky: Ø 76,4 (pravda 78,1, dřív 59,4); Stop o 2,5 h později: konec ≤ příjezd + 2 min (dřív +154 min stání). Prořídnutí 12 000 bodů ~40 ms, append při 12 000 bodech ~17 ms. **Nasadit spolu s Velínem** (jinak pozastavená výpůjčka po 3 h ukáže „Záznam visí“). |
```

---

## Kontrola po aplikaci patche
- `grep -n "start_user_trip\|set_user_rides_trip\|ride_autopause\|pause_aware" SUPABASE_BACKEND_STATE_*.md` → výskyt ve STATE_1, 2, 3, 5, 6.
- Žádná existující věta se nemaže; jen 1b nahrazuje řádek `feature_flags` jeho rozšířenou verzí.
