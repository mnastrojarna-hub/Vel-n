-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — „Moje jízdy": uzavření jízdy už NEDOPOČÍTÁ km vzdušnou čarou
-- přes mezeru v signálu.
--
-- Nahlášeno 2026-10-15 (Velín, jízda 4. 10. 2026, RE Shotgun 650):
-- „5 bodů na 2,3 km, 45 min bez signálu, čas jízdy —, Ø 97 km/h, max 97".
-- Přehráno na PG16 se stejnými čísly: appka poslala fix na startu a další
-- až po 44,6 min o 2,3 km dál. Přírůstkové statistiky to spočítaly správně
-- (0 km, 2675 s MEZERA), ale `_ride_finalize` měl pojistku pro starého
-- klienta „km = 0 → km = délka celé stopy" — a ta sečetla i úsek PŘES
-- mezeru. Jízda, která se měla jako kratší než 1 km zahodit, se uložila
-- s 2,3 km a Ø 97 km/h (2,3 km / 85 s, které zbyly po odečtení mezery).
--
-- Změna: délka ze stopy se dopočítá JEN u stopy bez časových značek
-- (starý klient — u ní mezery poznat nejde a nic jiného nemáme). Stopa
-- s časy má km z `_ride_stats` a 0 km je u ní skutečná hodnota.
-- Navazuje na 20260922_user_rides_finalize_idempotent.sql (nasazená, needituje
-- se); zbytek funkce beze změny. create or replace = stejná signatura,
-- práva (REVOKE z 20260921g) zůstávají. Oprava uložených dat je až
-- v 20261015b (potřebuje i novou `_ride_stats`).
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

  -- UŽ UZAVŘENÁ jízda se NEPŘEPOČÍTÁVÁ (viz 20260922_…_idempotent).
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

  -- Stopa BEZ časových značek (starý klient) → km aspoň ze stopy. Stopa
  -- s časy má km z přírůstkových statistik — 0 je u ní skutečná hodnota
  -- (všechno, co „ujela", byly mezery bez signálu) a délka celé stopy by
  -- sečetla právě ty vzdušné čáry, které `_ride_stats` záměrně vynechává.
  if v_km = 0 and not exists (
       select 1 from jsonb_array_elements(
         case when jsonb_typeof(v_r.track) = 'array' then v_r.track else '[]'::jsonb end) e
        where jsonb_typeof(e) = 'array' and jsonb_array_length(e) > 2
          and (e->>2) ~ '^[0-9]+(\.[0-9]+)?$') then
    v_km := _ride_track_km(v_r.track);
  end if;

  -- Jízda kratší než kilometr = parkování, deník se tím neplní.
  if v_km < 1.0 then
    delete from user_rides where id = p_ride_id;
    return jsonb_build_object('success', true, 'discarded', true,
                              'distance_km', round(v_km, 1));
  end if;

  -- Celkový čas = start → konec, nejméně však doba pokrytá stopou.
  v_dur := greatest(1,
             (extract(epoch from (v_end - v_r.started_at)) / 60)::int,
             ceil((v_move + v_idle + v_gap)::numeric / 60)::int);
  -- Zbytek celkového času, který stopa nepokryla, je STÁNÍ.
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
    max_speed_kmh = nullif(greatest(coalesce(max_speed_kmh, 0), coalesce(v_avg, 0)), 0),
    end_lat = coalesce((v_last->>0)::double precision, end_lat),
    end_lng = coalesce((v_last->>1)::double precision, end_lng),
    name = case when coalesce(trim(name), '') <> '' then name
                else to_char(started_at at time zone 'Europe/Prague', 'DD.MM.YYYY') end
  where id = p_ride_id;

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
