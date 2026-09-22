-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — „Moje jízdy": uzavření jízdy je IDEMPOTENTNÍ.
--
-- Navazuje na 20260921g_user_rides_real_track.sql (ta je NASAZENÁ, proto
-- se needituje). Nález z adversariálního review 2026-09-22 (R1, blocker):
-- `_ride_finalize` přepočítal i UŽ UZAVŘENOU jízdu. Cron
-- `close_stale_user_rides` uzavře zatuhlou nahrávku časem posledního fixu;
-- když si ale zákazník otevře appku až po dnech, hlídač zavolá
-- `finish_user_ride` (lokálně pořád drží id jízdy) → `_ride_finalize`
-- proběhl znovu s p_ended_at = now() → duration_min = dny, idle_sec dorovnané
-- na dny. Tj. přesně ta „33 h 18 min", jen jinou cestou.
--
-- Změna: `_ride_finalize` na jízdě s is_recording = false nic nemění a vrátí
-- uložené hodnoty (`already_finished: true`). Platí pro všechny volající:
-- finish_user_ride (appka), close_stale_user_rides (cron),
-- admin_finish_user_ride (Velín), start_user_ride (zatuhlá nahrávka).
-- + 2) _ride_stats: dt = 0 není vadný čas (SQL-5), 3) append_ride_track
--   zahodí body starší než start jízdy (SQL-3).
-- Idempotentní (create or replace, stejná signatura a návratový typ).
-- ════════════════════════════════════════════════════════════════════

create or replace function public._ride_finalize(
  p_ride_id uuid, p_ended_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_r user_rides; v_last jsonb; v_end timestamptz;
  v_km numeric; v_move int; v_idle int; v_gap int; v_dur int; v_active int;
  v_avg numeric;
begin
  select * into v_r from user_rides where id = p_ride_id for update;
  if v_r.id is null then return jsonb_build_object('success', false, 'error', 'ride_not_found'); end if;

  -- UŽ UZAVŘENÁ jízda se NEPŘEPOČÍTÁVÁ. Cron ji uzavřel časem posledního
  -- fixu; když se pak po dnech otevře appka, hlídač zavolá finish_user_ride
  -- (lokálně má pořád id) a bez téhle pojistky by se všechno spočítalo znovu
  -- s p_ended_at = now(): celkový čas = dny, stání dorovnané na dny. Stejná
  -- třída chyby jako „celkový čas 33 h 18 min", jen jinou cestou.
  if not v_r.is_recording then
    return jsonb_build_object('success', true, 'discarded', false, 'already_finished', true,
                              'id', v_r.id, 'distance_km', round(coalesce(v_r.distance_km, 0), 1),
                              'duration_min', v_r.duration_min, 'moving_sec', v_r.moving_sec,
                              'idle_sec', v_r.idle_sec, 'gap_sec', v_r.gap_sec);
  end if;

  v_end := coalesce(p_ended_at, v_r.last_fix_at, v_r.updated_at, now());
  if v_end < v_r.started_at then v_end := v_r.started_at; end if;

  v_km := coalesce(v_r.distance_km, 0);
  v_move := coalesce(v_r.moving_sec, 0);
  v_idle := coalesce(v_r.idle_sec, 0);
  v_gap := coalesce(v_r.gap_sec, 0);

  -- Stopa bez časových značek (starý klient) → km aspoň ze stopy.
  if v_km = 0 then v_km := _ride_track_km(v_r.track); end if;

  -- Jízda kratší než kilometr = parkování, deník se tím neplní.
  -- (Po odečtení mezer sem spadnou i „trasy", které byly jen pár
  -- vzdušných čar mezi náhodnými fixy — přesně to, co se má zahodit.)
  if v_km < 1.0 then
    delete from user_rides where id = p_ride_id;
    return jsonb_build_object('success', true, 'discarded', true,
                              'distance_km', round(v_km, 1));
  end if;

  -- Celkový čas = start → konec, nejméně však doba pokrytá stopou.
  v_dur := greatest(1,
             (extract(epoch from (v_end - v_r.started_at)) / 60)::int,
             ceil((v_move + v_idle + v_gap)::numeric / 60)::int);
  -- Zbytek celkového času, který stopa nepokryla, je STÁNÍ (ne mezera —
  -- mezeru poznáme jen tam, kde po ní zase přišel fix jinde).
  if v_move + v_idle + v_gap < v_dur * 60 then
    v_idle := v_dur * 60 - v_move - v_gap;
  end if;
  if v_idle < 0 then v_idle := 0; end if;

  -- Čas, ve kterém jsme o motorkáři něco věděli (bez slepých mezer).
  v_active := greatest(v_dur * 60 - v_gap, 60);

  v_last := case when jsonb_array_length(coalesce(v_r.track, '[]'::jsonb)) > 0
                 then v_r.track -> (jsonb_array_length(v_r.track) - 1) end;

  -- Průměr z času jízdy; bez časových značek (starý klient) z času, kdy
  -- jsme signál měli. Nesmyslnou hodnotu (přes 200 km/h) nevykazujeme.
  v_avg := nullif(least(case when v_move > 0
             then round((v_km / (v_move::numeric / 3600)), 1)
             else round((v_km / (v_active::numeric / 3600)), 1) end,
             200.1), 200.1);

  update user_rides set
    is_recording = false,
    ended_at = v_end,
    distance_km = v_km,
    duration_min = v_dur,
    moving_sec = v_move,
    idle_sec = v_idle,
    avg_speed_kmh = v_avg,
    -- Maximum nesmí zůstat pod průměrem (viz append_ride_track).
    max_speed_kmh = nullif(greatest(coalesce(max_speed_kmh, 0), coalesce(v_avg, 0)), 0),
    end_lat = coalesce((v_last->>0)::double precision, end_lat),
    end_lng = coalesce((v_last->>1)::double precision, end_lng),
    name = case when coalesce(trim(name), '') <> '' then name
                else to_char(started_at at time zone 'Europe/Prague', 'DD.MM.YYYY') end
  where id = p_ride_id;

  -- start / cíl jako body jízdy (jen když tam ještě nejsou)
  insert into user_ride_points (ride_id, kind, lat, lng, happened_at, sort_order)
  select p_ride_id, 'start', (v_r.track->0->>0)::double precision,
         (v_r.track->0->>1)::double precision, v_r.started_at, 0
  where jsonb_array_length(coalesce(v_r.track, '[]'::jsonb)) > 0
    and (v_r.track->0->>0) is not null
    and not exists (select 1 from user_ride_points where ride_id = p_ride_id and kind = 'start');

  insert into user_ride_points (ride_id, kind, lat, lng, happened_at, sort_order)
  select p_ride_id, 'end', (v_last->>0)::double precision,
         (v_last->>1)::double precision, v_end, 9999
  where v_last is not null and (v_last->>0) is not null
    and not exists (select 1 from user_ride_points where ride_id = p_ride_id and kind = 'end');

  return jsonb_build_object('success', true, 'discarded', false, 'id', p_ride_id,
                            'distance_km', round(v_km, 1), 'duration_min', v_dur,
                            'moving_sec', v_move, 'idle_sec', v_idle, 'gap_sec', v_gap);
end;
$$;

-- ══ 2) _ride_stats: dt = 0 není vadný čas ═══════════════════════════
-- Nález SQL-5: appka posílá čas fixu zaokrouhlený na sekundy; při 100 km/h
-- a 20m filtru přijdou dva fixy v téže sekundě → dt = 0 → dosud „vadný čas"
-- a ÚSEK VČETNĚ KILOMETRŮ se zahodil. Nově se km přičtou, jen rychlost se
-- z nulového času nepočítá.
create or replace function public._ride_stats(p_track jsonb)
returns jsonb language plpgsql immutable as $$
declare
  c_gap_sec   constant double precision := 180;   -- nad tímhle už úsek nepovažujeme za souvislou jízdu
  c_still_km  constant double precision := 0.05;  -- posun do 50 m = stál na místě
  c_max_kmh   constant double precision := 300;   -- nad tím je to GPS skok, ne rychlost
  c_move_kmh  constant double precision := 3;     -- pod tím se počítá STÁNÍ
  c_inst_sec  constant double precision := 60;    -- jen z tak krátkého úseku věříme dopočtené rychlosti
  c_gain_m    constant double precision := 5;     -- menší změna výšky je šum GPS

  v_pt jsonb;
  v_lat double precision; v_lng double precision;
  v_ts double precision; v_alt double precision; v_kmh double precision;
  v_plat double precision; v_plng double precision;
  v_pts double precision; v_palt double precision;
  v_d double precision; v_dt double precision; v_v double precision;
  -- Vzdálenost od POSLEDNÍHO bodu s časovou značkou. U stopy, kde má čas
  -- každý bod (dnešní klient), se rovná `v_d`. Když ale jeden bod uprostřed
  -- čas nemá, `v_dt` pokrývá dva úseky — a porovnávat ho s délkou jen toho
  -- posledního by rychlost podhodnotilo a úsek chybně označilo za stání.
  v_dseg double precision := 0;
  v_dist double precision := 0; v_move double precision := 0;
  v_idle double precision := 0; v_gap double precision := 0;
  v_gain double precision := 0; v_max double precision := 0;
  v_is_gap boolean; v_bad_time boolean;
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
      -- Body přeházené v čase / přenastavené hodiny na telefonu. Takovému
      -- úseku nevěříme ANI vzdálenost — dřív se km přičetly, ale čas ne,
      -- takže průměrná rychlost vyskočila nad maximum.
      -- dt = 0 (dva fixy v téže zaokrouhlené sekundě — při 100 km/h a 20m filtru
      -- běžné) NENÍ vadný čas: kilometry se počítají, jen se z toho nedá
      -- odvodit rychlost. Vadný je jen záporný nebo absurdní skok.
      v_bad_time := v_dt is not null and (v_dt < 0 or v_dt >= 86400);
      if v_bad_time then v_dt := null; end if;

      v_v := case when v_dt is not null and v_dt > 0 then v_dseg / (v_dt / 3600) end;

      -- MEZERA: dlouhá pauza, po které se motorkář objevil jinde.
      v_is_gap := v_dt is not null and v_dt > c_gap_sec and v_dseg > c_still_km;

      if v_bad_time then
        -- Nic nepřičítáme: ani km, ani čas. (Stopa bez časových značek je
        -- něco jiného — tam dt vůbec nevznikne a km se počítají dál.)
        null;
      elsif v_is_gap then
        -- Trasu mezi body NEZNÁME → vzdušnou čáru nezapočítáme ani do km,
        -- ani do času jízdy. Jen si poznamenáme, jak dlouho jsme byli slepí.
        v_gap := v_gap + v_dt;
      else
        -- GPS skok (teleport) se do vzdálenosti nepočítá.
        if v_v is null or v_v < c_max_kmh then
          v_dist := v_dist + v_d;
        end if;

        if v_dt is not null then
          if v_v >= c_move_kmh and v_v < c_max_kmh then
            v_move := v_move + v_dt;
          else
            v_idle := v_idle + v_dt;   -- semafor, foto, pauza i „stál a nepřišel fix"
          end if;
          -- Maximum i z DOPOČTENÉ rychlosti, ale jen z krátkého úseku, kde
          -- odpovídá okamžité rychlosti. (Dřív se počítalo jen když klient
          -- rychlost neposlal — proto mohlo max vyjít menší než průměr.)
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

-- ══ 3) append_ride_track: dávka ze staré jízdy se nepřilepí do nové ═══
-- Nález SQL-3 (viz komentář ve funkci). Zbytek těla beze změny proti g.
create or replace function public.append_ride_track(
  p_ride_id uuid, p_points jsonb,
  p_max_speed_kmh numeric default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_r user_rides; v_track jsonb; v_last jsonb; v_seg jsonb; v_st jsonb;
  v_dist numeric; v_move int; v_idle int; v_gap int; v_fix timestamptz;
  v_avg numeric;
begin
  if auth.uid() is null then return jsonb_build_object('success', false, 'error', 'not_authenticated'); end if;
  if jsonb_typeof(p_points) is distinct from 'array' then
    return jsonb_build_object('success', false, 'error', 'points_required');
  end if;

  select * into v_r from user_rides
   where id = p_ride_id and user_id = auth.uid() for update;
  if v_r.id is null then return jsonb_build_object('success', false, 'error', 'ride_not_found'); end if;

  -- Do UZAVŘENÉ jízdy se už nepřidává. Telefon, který byl při vracení
  -- motorky offline, se ozve klidně druhý den — a dávka ze starého bufferu
  -- by hotové jízdě přepsala statistiky i konec. Klient tenhle stav bere
  -- jako „doručeno" a dávku zahodí (viz `appendRideTrack` v appce).
  if not v_r.is_recording then
    return jsonb_build_object('success', false, 'error', 'ride_finished',
                              'finished', true);
  end if;

  -- Body z PŘEDCHOZÍ jízdy do téhle nepatří. Když vracení proběhlo offline,
  -- appka si nechala neodeslanou dávku; cron starou jízdu uzavřel a další
  -- den vznikla nová — a ta stará dávka by se do ní přilepila jako
  -- „15 h bez signálu" přes noc. Bod s časem starším než start jízdy
  -- (s rezervou 5 min) proto tiše vynecháme; body bez času necháme.
  -- CASE místo OR: SQL nezaručuje zkrácené vyhodnocení a jsonb_array_length
  -- na ne-poli by shodila celou dávku. `with ordinality` drží pořadí bodů.
  select coalesce(jsonb_agg(e.pt order by e.ord), '[]'::jsonb) into p_points
    from jsonb_array_elements(p_points) with ordinality as e(pt, ord)
   where case
           when jsonb_typeof(e.pt) <> 'array' then true
           when jsonb_array_length(e.pt) < 3 then true
           when not ((e.pt->>2) ~ '^[0-9]+(\.[0-9]+)?$') then true
           else to_timestamp((e.pt->>2)::double precision) >= v_r.started_at - interval '5 minutes'
         end;
  if jsonb_array_length(p_points) = 0 then
    -- Celá dávka byla ze staré jízdy: nic k uložení, pro klienta „doručeno".
    return jsonb_build_object('success', true, 'points', jsonb_array_length(coalesce(v_r.track, '[]'::jsonb)),
                              'distance_km', round(coalesce(v_r.distance_km, 0), 1),
                              'moving_sec', v_r.moving_sec, 'idle_sec', v_r.idle_sec, 'gap_sec', v_r.gap_sec,
                              'dropped_stale', true);
  end if;

  -- Statistiky ÚSEKU: nové body + poslední už uložený bod (aby se nezahodil
  -- kousek mezi dávkami). Přičtou se k dosavadním součtům.
  if jsonb_array_length(coalesce(v_r.track, '[]'::jsonb)) > 0 then
    v_seg := jsonb_build_array(v_r.track -> (jsonb_array_length(v_r.track) - 1)) || p_points;
  else
    v_seg := p_points;
  end if;
  v_st := _ride_stats(v_seg);

  v_dist := coalesce(v_r.distance_km, 0) + (v_st->>'dist_km')::numeric;
  v_move := coalesce(v_r.moving_sec, 0) + (v_st->>'moving_sec')::int;
  v_idle := coalesce(v_r.idle_sec, 0) + (v_st->>'idle_sec')::int;
  v_gap  := coalesce(v_r.gap_sec, 0) + (v_st->>'gap_sec')::int;

  v_track := _ride_track_cap(coalesce(v_r.track, '[]'::jsonb) || p_points);
  if jsonb_array_length(v_track) > 0 then
    v_last := v_track -> (jsonb_array_length(v_track) - 1);
  end if;

  -- Čas posledního fixu bereme z bodu; starý klient ho neposílá → now().
  v_fix := case
    when v_last is not null and jsonb_typeof(v_last) = 'array'
      and jsonb_array_length(v_last) > 2
      and (v_last->>2) ~ '^[0-9]+(\.[0-9]+)?$'
    then to_timestamp((v_last->>2)::double precision)
    else now() end;
  if v_fix > now() + interval '1 hour' or v_fix < now() - interval '30 days' then
    v_fix := now();   -- přenastavené hodiny na telefonu
  end if;

  v_avg := case when v_move > 0
                then least(round((v_dist / (v_move::numeric / 3600)), 1), 200.0) end;

  update user_rides set
    track = v_track,
    distance_km = v_dist,
    moving_sec = v_move,
    idle_sec = v_idle,
    gap_sec = v_gap,
    last_fix_at = v_fix,
    avg_speed_kmh = v_avg,
    elevation_gain_m = coalesce(elevation_gain_m, 0) + (v_st->>'gain_m')::int,
    end_lat = coalesce((v_last->>0)::double precision, end_lat),
    end_lng = coalesce((v_last->>1)::double precision, end_lng),
    start_lat = coalesce(start_lat, (v_track->0->>0)::double precision),
    start_lng = coalesce(start_lng, (v_track->0->>1)::double precision),
    -- Celkový čas se počítá k POSLEDNÍMU FIXU, ne k `now()`. Dřív rostl
    -- dál i po tom, co appka přestala posílat body — tak vznikl „celkový
    -- čas 33 h 18 min" u vyjížďky, která dávno skončila.
    duration_min = greatest(0, (extract(epoch from (v_fix - started_at)) / 60)::int),
    -- Kdo má průměr X, musel někde jet aspoň X. Pojistka proti tomu, aby
    -- Velín zase ukázal „Ø 4 km/h · max 3 km/h".
    max_speed_kmh = greatest(coalesce(max_speed_kmh, 0),
                             coalesce(p_max_speed_kmh, 0),
                             coalesce((v_st->>'max_kmh')::numeric, 0),
                             coalesce(v_avg, 0))
  where id = p_ride_id;

  return jsonb_build_object('success', true, 'points', jsonb_array_length(v_track),
                            'distance_km', round(v_dist, 1),
                            'moving_sec', v_move, 'idle_sec', v_idle, 'gap_sec', v_gap);
end;
$$;

-- Stejná ochrana jako v g: helper maže řádky, nesmí být volatelný přímo.
revoke all on function public._ride_finalize(uuid, timestamptz) from public;
revoke all on function public._ride_finalize(uuid, timestamptz) from anon, authenticated;
