-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — „Moje jízdy": skok o kilometry „v téže sekundě" není jízda
-- + oprava uložených jízd s kilometry bez jediné vteřiny jízdy.
-- Navazuje na 20261015_user_rides_finalize_no_gap_km.sql.
--
-- 1) _ride_stats: úsek s dt = 0 (oba body v téže zaokrouhlené sekundě) se
--    do km počítal vždy — i „teleport" o kilometry (poloha z cache + čerstvý
--    fix doručené najednou; appka do 4.1.3 razítkovala bod časem PŘÍJMU, ne
--    fixu). Nově: dt = 0 s posunem od 500 m je GPS skok a do km nejde.
--    Práh je nad největší rozestup skutečných fixů: nový klient má v téže
--    sekundě nejvýš desítky metrů, starý klient při „dávce po probuzení"
--    (fixy po 5 s se stejným časem příjmu) až ~420 m při 300 km/h — ty se
--    počítají dál jako dřív (jen bez času). Jinak beze změny (20260922b).
-- 2) Oprava dat: uzavřené automatické jízdy se stopou s časy, které mají
--    kilometry, ale NULOVÝ čas jízdy (moving_sec = 0) — tj. km vznikly jen
--    pojistkou z finalize (vzdušná čára přes mezeru) nebo skoky s dt = 0.
--    Přepočet z uložené stopy novou funkcí; NIC SE NEMAŽE (i jízda s 0 km
--    zůstane, obsluha ji případně smaže ve Velíně ručně).
-- Idempotentní (create or replace se stejnou signaturou → práva zůstávají;
-- oprava dat podruhé nic nenajde).
-- ════════════════════════════════════════════════════════════════════

create or replace function public._ride_stats(p_track jsonb)
returns jsonb language plpgsql immutable as $$
declare
  c_gap_sec   constant double precision := 180;   -- nad tímhle už úsek nepovažujeme za souvislou jízdu
  c_still_km  constant double precision := 0.3;   -- posun do 300 m = stál na místě (viz 20260922b)
  c_max_kmh   constant double precision := 300;   -- nad tím je to GPS skok, ne rychlost
  c_move_kmh  constant double precision := 3;     -- pod tím se počítá STÁNÍ
  c_inst_sec  constant double precision := 60;    -- jen z tak krátkého úseku věříme dopočtené rychlosti
  c_gain_m    constant double precision := 5;     -- menší změna výšky je šum GPS
  c_jump0_km  constant double precision := 0.5;   -- dt = 0 a posun od 500 m = skok, ne jízda

  v_pt jsonb;
  v_lat double precision; v_lng double precision;
  v_ts double precision; v_alt double precision; v_kmh double precision;
  v_plat double precision; v_plng double precision;
  v_pts double precision; v_palt double precision;
  v_d double precision; v_dt double precision; v_v double precision;
  -- Vzdálenost od POSLEDNÍHO bodu s časovou značkou (viz 20260922b).
  v_dseg double precision := 0;
  v_dist double precision := 0; v_move double precision := 0;
  v_idle double precision := 0; v_gap double precision := 0;
  v_gain double precision := 0; v_max double precision := 0;
  v_is_gap boolean; v_bad_time boolean; v_jump boolean;
begin
  if jsonb_typeof(p_track) is distinct from 'array' then
    return jsonb_build_object('dist_km', 0, 'moving_sec', 0, 'idle_sec', 0,
                              'gap_sec', 0, 'gain_m', 0, 'max_kmh', 0);
  end if;

  for v_pt in select * from jsonb_array_elements(p_track) loop
    if jsonb_typeof(v_pt) <> 'array' or jsonb_array_length(v_pt) < 2 then continue; end if;
    v_lat := (v_pt->>0)::double precision;
    v_lng := (v_pt->>1)::double precision;
    if v_lat is null or v_lng is null then continue; end if;
    v_ts  := case when jsonb_array_length(v_pt) > 2 then (v_pt->>2)::double precision end;
    v_kmh := case when jsonb_array_length(v_pt) > 3 then (v_pt->>3)::double precision end;
    v_alt := case when jsonb_array_length(v_pt) > 4 then (v_pt->>4)::double precision end;
    -- Rychlost změřená přijímačem. 0 = „stál nebo neumí", ne maximum.
    if v_kmh is not null and v_kmh > v_max and v_kmh < c_max_kmh then v_max := v_kmh; end if;

    v_is_gap := false; v_bad_time := false;

    if v_plat is not null then
      v_d := 6371 * 2 * asin(sqrt(
        power(sin(radians(v_lat - v_plat) / 2), 2) +
        cos(radians(v_plat)) * cos(radians(v_lat)) *
        power(sin(radians(v_lng - v_plng) / 2), 2)));
      v_dseg := v_dseg + v_d;

      v_dt := case when v_ts is not null and v_pts is not null then v_ts - v_pts end;
      -- Záporný nebo absurdní skok času = nedůvěryhodný úsek (ani km).
      v_bad_time := v_dt is not null and (v_dt < 0 or v_dt >= 86400);
      if v_bad_time then v_dt := null; end if;

      v_v := case when v_dt is not null and v_dt > 0 then v_dseg / (v_dt / 3600) end;

      -- MEZERA: dlouhá pauza, po které se motorkář objevil jinde.
      v_is_gap := v_dt is not null and v_dt > c_gap_sec and v_dseg > c_still_km;

      -- GPS skok: rychlost přes 300 km/h, nebo dt = 0 s posunem od 500 m
      -- (víc nedají ani fixy po 5 s se stejným časem příjmu ze starého
      -- klienta; „teleport" o kilometry ano).
      -- (coalesce: bod bez času má dt NULL a o skok nejde — km se počítají.)
      v_jump := coalesce(v_v >= c_max_kmh, false)
             or coalesce(v_dt = 0 and v_dseg >= c_jump0_km, false);

      if v_bad_time then
        null;   -- nic nepřičítáme: ani km, ani čas
      elsif v_is_gap then
        -- Trasu mezi body NEZNÁME → do km ani do času jízdy, jen do mezery.
        v_gap := v_gap + v_dt;
      else
        if not v_jump then
          v_dist := v_dist + v_d;
        end if;

        if v_dt is not null then
          if v_v >= c_move_kmh and v_v < c_max_kmh then
            v_move := v_move + v_dt;
          else
            v_idle := v_idle + v_dt;   -- semafor, foto, pauza i „stál a nepřišel fix"
          end if;
          -- Maximum i z DOPOČTENÉ rychlosti, ale jen z krátkého úseku.
          if v_dt <= c_inst_sec and v_v > v_max and v_v < c_max_kmh then
            v_max := v_v;
          end if;
        end if;

        -- Nastoupáno: jen přes souvislý úsek a jen změny nad 5 m.
        if v_alt is not null and v_palt is not null and v_alt - v_palt >= c_gain_m then
          v_gain := v_gain + (v_alt - v_palt);
        end if;
      end if;
    end if;

    v_plat := v_lat; v_plng := v_lng;
    -- Časovou kotvu (a s ní i nasčítanou vzdálenost) posouváme jen na bodu,
    -- který čas opravdu má.
    if v_ts is not null then v_pts := v_ts; v_dseg := 0; end if;
    -- Přes mezeru (ani přes nedůvěryhodný úsek) výšku neporovnáváme.
    if v_is_gap or v_bad_time then v_palt := null;
    elsif v_alt is not null then v_palt := v_alt; end if;
  end loop;

  return jsonb_build_object(
    'dist_km', round(v_dist::numeric, 3),
    'moving_sec', round(v_move)::int,
    'idle_sec', round(v_idle)::int,
    'gap_sec', round(v_gap)::int,
    'gain_m', round(v_gain)::int,
    'max_kmh', round(v_max::numeric, 1));
end;
$$;

-- ══ 2) OPRAVA ULOŽENÝCH JÍZD: km bez jediné vteřiny jízdy ═════════════
-- Jen uzavřené automatické jízdy se stopou s časy (u stopy bez časů je
-- km ze stopy jediný údaj, který máme). Celkový čas, mezera a stání se
-- nemění; přepočítá se vzdálenost, průměr a maximum (maximum bylo jen
-- vytažené na nesmyslný průměr).
do $$
declare v_r record; v_st jsonb; v_km numeric; v_avg numeric; v_max numeric;
        v_active int; v_n int := 0;
begin
  for v_r in
    select r.id, r.track, r.distance_km, r.duration_min, r.gap_sec
      from user_rides r
     where r.source = 'auto' and not r.is_recording
       and coalesce(r.moving_sec, 0) = 0 and coalesce(r.distance_km, 0) > 0
       and jsonb_typeof(r.track) = 'array'
       and exists (select 1 from jsonb_array_elements(r.track) e
                    -- CASE: plánovač by jinak volal jsonb_array_length i na
                    -- prvku, který není pole (chyba → migrace by spadla)
                    where case when jsonb_typeof(e) <> 'array' then false
                               when jsonb_array_length(e) < 3 then false
                               else (e->>2) ~ '^[0-9]+(\.[0-9]+)?$' end)
  loop
    v_st := _ride_stats(v_r.track);
    v_km := (v_st->>'dist_km')::numeric;
    -- Jen tam, kde přepočet km opravdu ubere (drift při stání zůstává).
    if v_km >= v_r.distance_km then continue; end if;
    -- Průměr jako v _ride_finalize: bez času jízdy z času, kdy byl signál.
    v_active := greatest(coalesce(v_r.duration_min, 0) * 60 - coalesce(v_r.gap_sec, 0), 60);
    v_avg := case when v_km > 0
                  then nullif(least(round(v_km / (v_active::numeric / 3600), 1), 200.1), 200.1) end;
    v_max := nullif(greatest(coalesce((v_st->>'max_kmh')::numeric, 0), coalesce(v_avg, 0)), 0);
    update user_rides
       set distance_km = v_km, avg_speed_kmh = v_avg, max_speed_kmh = v_max
     where id = v_r.id;
    v_n := v_n + 1;
  end loop;
  raise notice 'user_rides: opraveno % jízd s km bez času jízdy', v_n;
end $$;
