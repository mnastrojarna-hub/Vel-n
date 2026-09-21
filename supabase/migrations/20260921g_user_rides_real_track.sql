-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — „Moje jízdy": REÁLNÁ trasa místo rovných čar přes kraj.
--
-- PROBLÉM (nahlášeno 2026-09-21, doloženo jízdou 67.9 km z 11 bodů):
--   Appka sbírala GPS bez foreground service / background módu, takže po
--   přechodu na pozadí fixy přestaly chodit. Mezi dvěma body tak byly i
--   hodiny a desítky kilometrů. Server tuhle mezeru bral jako NORMÁLNÍ
--   úsek jízdy:
--     • vzdálenost = vzdušná čára mezi body  → mapa kreslila rovné čáry,
--     • celá mezera se počítala jako ČAS JÍZDY → 15 h 59 min „v sedle",
--     • Ø rychlost z toho vyšla 4 km/h a MAX 3 km/h (max < průměr!),
--     • jízda se nikdy neukončila (is_recording=true 2 dny), a protože
--       `uq_user_rides_recording` pouští jen JEDNU rozjetou nahrávku na
--       uživatele, zákazníkovi už žádná další jízda nevznikla.
--
-- CO TAHLE MIGRACE DĚLÁ:
--   1. `_ride_stats` rozlišuje MEZERU (bez signálu) od stání i od jízdy.
--      Vzdálenost přes mezeru se NEPŘIČÍTÁ (neznámou trasu nevymýšlíme),
--      čas jde do nového sloupce `gap_sec`. Stání na místě (bez fixů, ale
--      i bez posunu) zůstává správně STÁNÍM.
--   2. Maximální rychlost se dopočítá i z KRÁTKÝCH úseků → max už nikdy
--      nevyjde menší než průměr.
--   3. Nové sloupce `gap_sec` (čas bez signálu) a `last_fix_at` (kdy
--      naposledy dorazil GPS bod — Velín z něj pozná „živou" polohu).
--   4. `_ride_finalize` = jedno společné uzavření jízdy; používá ho jak
--      `finish_user_ride`, tak nový cron `close_stale_user_rides()`,
--      který zatuhlé nahrávky uzavře i když zákazník appku už neotevře.
--   5. `start_user_ride` zatuhlou nahrávku neobnoví, ale uzavře a založí
--      novou; první bod stopy nově nese i časovou značku.
--   6. `admin_booking_live_ride` = ŽIVÁ POLOHA zákazníka pro Velín
--      (detail rezervace → mapa během aktivní výpůjčky).
--   7. Jednorázová oprava historických dat (uzavřít + přepočítat).
--
-- Idempotentní (create or replace / add column if not exists / guard).
-- ════════════════════════════════════════════════════════════════════

-- ══ 0) NOVÉ SLOUPCE ═════════════════════════════════════════════════
alter table public.user_rides
  add column if not exists gap_sec int not null default 0,
  add column if not exists last_fix_at timestamptz;

comment on column public.user_rides.gap_sec is
  'Čas bez GPS signálu (appka na pozadí / ztráta fixu). Vzdálenost přes tyto mezery se do distance_km NEPOČÍTÁ a mapa je nespojuje plnou čarou.';
comment on column public.user_rides.last_fix_at is
  'Kdy naposledy dorazil GPS bod. Velín z něj počítá stáří „živé" polohy u aktivní rezervace.';

create index if not exists idx_user_rides_recording_fix
  on public.user_rides (last_fix_at desc) where is_recording;

-- ══ 1) STATISTIKY ÚSEKU — nově s rozlišením MEZERY ══════════════════
-- Tři druhy úseku mezi dvěma po sobě jdoucími body:
--   JÍZDA   – dt <= 180 s a dopočtená rychlost >= 3 km/h
--   STÁNÍ   – dt <= 180 s a rychlost < 3 km/h, NEBO dlouhé dt s posunem
--             pod 50 m (motorkář prostě stál a nový fix nepřišel)
--   MEZERA  – dlouhé dt a velký posun: appka spala / nebyl signál.
--             Trasu neznáme → vzdálenost se NEPŘIČÍTÁ, čas jde do gap_sec.
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
      v_bad_time := v_dt is not null and (v_dt <= 0 or v_dt >= 86400);
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

-- ══ 2) TVAR JÍZDY PRO ČTECÍ RPC — doplněné nové sloupce ═════════════
create or replace function public._ride_json(p_ride public.user_rides)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'id', p_ride.id, 'booking_id', p_ride.booking_id, 'moto_id', p_ride.moto_id,
    'moto_name', p_ride.moto_name, 'name', p_ride.name, 'description', p_ride.description,
    'source', p_ride.source, 'track', p_ride.track,
    'start_lat', p_ride.start_lat, 'start_lng', p_ride.start_lng,
    'end_lat', p_ride.end_lat, 'end_lng', p_ride.end_lng,
    'started_at', p_ride.started_at, 'ended_at', p_ride.ended_at,
    'distance_km', round(p_ride.distance_km, 1),
    'duration_min', p_ride.duration_min,
    'moving_sec', p_ride.moving_sec, 'idle_sec', p_ride.idle_sec,
    'gap_sec', p_ride.gap_sec, 'last_fix_at', p_ride.last_fix_at,
    'avg_speed_kmh', p_ride.avg_speed_kmh, 'max_speed_kmh', p_ride.max_speed_kmh,
    'elevation_gain_m', p_ride.elevation_gain_m,
    'is_recording', p_ride.is_recording,
    'visibility', p_ride.visibility, 'status', p_ride.status,
    'cover_image', p_ride.cover_image, 'created_at', p_ride.created_at,
    'points', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', pt.id, 'kind', pt.kind, 'name', pt.name, 'note', pt.note,
        'lat', pt.lat, 'lng', pt.lng, 'photos', to_jsonb(pt.photos),
        'route_poi_id', pt.route_poi_id, 'user_poi_id', pt.user_poi_id, 'poi_id', pt.poi_id,
        'happened_at', pt.happened_at, 'sort_order', pt.sort_order
      ) order by pt.sort_order, pt.created_at), '[]'::jsonb)
      from public.user_ride_points pt where pt.ride_id = p_ride.id)
  );
$$;

-- ══ 3) SPOLEČNÉ UZAVŘENÍ JÍZDY ══════════════════════════════════════
-- Dopočte celkový čas, dorovná stání, založí body start/cíl a krátkou
-- jízdu zahodí. Volá ho `finish_user_ride` i nový úklid zatuhlých
-- nahrávek — ať se logika nerozjede do dvou různých verzí.
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

-- `_ride_finalize` MAŽE jízdy (krátká = zahodit), takže nesmí zůstat na
-- výchozím EXECUTE pro PUBLIC — jinak by si ji kdokoli přihlášený mohl
-- zavolat na cizí ride_id. Volá se výhradně zevnitř SECURITY DEFINER RPC
-- a z cronu (vlastník funkce), kterým revoke nevadí.
revoke all on function public._ride_finalize(uuid, timestamptz) from public;
revoke all on function public._ride_finalize(uuid, timestamptz) from anon, authenticated;

-- ══ 4) START NAHRÁVÁNÍ — zatuhlou nahrávku uzavře, neobnoví ═════════
create or replace function public.start_user_ride(
  p_booking_id uuid default null,
  p_lat double precision default null,
  p_lng double precision default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_id uuid; v_booking uuid; v_moto uuid; v_moto_name text; v_track jsonb := '[]'::jsonb;
  v_stale timestamptz;
begin
  if auth.uid() is null then return jsonb_build_object('success', false, 'error', 'not_authenticated'); end if;

  -- Už něco běží? Rozjetou nahrávku obnovíme (idempotentní start po
  -- restartu appky) — ALE jen když je čerstvá. Nahrávka, do které už
  -- hodiny nic nepřiteklo, patří k dávno skončené vyjížďce; kdybychom ji
  -- vrátili, unikátní index `uq_user_rides_recording` by zákazníkovi
  -- zablokoval každou další jízdu.
  select id, coalesce(last_fix_at, updated_at, started_at) into v_id, v_stale
    from user_rides where user_id = auth.uid() and is_recording limit 1;
  if v_id is not null then
    if v_stale > now() - interval '3 hours' then
      return jsonb_build_object('success', true, 'id', v_id, 'resumed', true);
    end if;
    perform _ride_finalize(v_id, v_stale);   -- dojetá / zapomenutá → uzavřít
    v_id := null;
  end if;

  select b.id, b.moto_id into v_booking, v_moto
  from bookings b
  where b.user_id = auth.uid()
    and (p_booking_id is null or b.id = p_booking_id)
    and b.status in ('reserved','active')
    and b.start_date::date <= current_date and b.end_date::date >= current_date
  order by b.start_date desc limit 1;

  if v_moto is not null then
    select nullif(trim(coalesce(m.brand,'') || ' ' || coalesce(m.model,'')), '')
      into v_moto_name from motorcycles m where m.id = v_moto;
  end if;

  -- První bod nese i ČAS — bez něj by se úsek k dalšímu bodu nedal
  -- posoudit (jízda × stání × mezera) a rovnou by se počítal jako jízda.
  if p_lat is not null and p_lng is not null then
    v_track := jsonb_build_array(jsonb_build_array(
      p_lat, p_lng, round(extract(epoch from now()))));
  end if;

  -- `end_*` = POSLEDNÍ známá poloha; na startu je to ten první bod. Velín
  -- z něj kreslí živou polohu, takže nesmí zůstat prázdná do první dávky.
  insert into user_rides (user_id, booking_id, moto_id, moto_name, source,
                          track, start_lat, start_lng, end_lat, end_lng,
                          is_recording, last_fix_at)
  values (auth.uid(), v_booking, v_moto, v_moto_name, 'auto',
          v_track, p_lat, p_lng, p_lat, p_lng, true,
          case when p_lat is not null then now() end)
  returning id into v_id;

  return jsonb_build_object('success', true, 'id', v_id, 'resumed', false,
                            'booking_id', v_booking, 'moto_name', v_moto_name);
end;
$$;
grant execute on function public.start_user_ride(uuid, double precision, double precision) to authenticated;

-- ══ 5) PŘIDÁNÍ GPS BODŮ — mezery do gap_sec, živá poloha do last_fix_at
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
grant execute on function public.append_ride_track(uuid, jsonb, numeric) to authenticated;

-- ══ 6) UKONČENÍ JÍZDY — poslední dávka + společné uzavření ══════════
create or replace function public.finish_user_ride(
  p_ride_id uuid, p_points jsonb default null, p_name text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_r user_rides;
begin
  if auth.uid() is null then return jsonb_build_object('success', false, 'error', 'not_authenticated'); end if;

  select * into v_r from user_rides where id = p_ride_id and user_id = auth.uid();
  if v_r.id is null then return jsonb_build_object('success', false, 'error', 'ride_not_found'); end if;

  -- Poslední dávka bodů projde stejnou cestou jako každá jiná (statistiky
  -- i mezery se tak počítají na JEDNOM místě).
  if jsonb_typeof(p_points) = 'array' and jsonb_array_length(p_points) > 0 then
    perform append_ride_track(p_ride_id, p_points, null);
  end if;

  if coalesce(trim(p_name), '') <> '' then
    update user_rides set name = left(trim(p_name), 120) where id = p_ride_id;
  end if;

  return _ride_finalize(p_ride_id, now());
end;
$$;
grant execute on function public.finish_user_ride(uuid, jsonb, text) to authenticated;

-- ══ 7) ÚKLID ZATUHLÝCH NAHRÁVEK (cron) ══════════════════════════════
-- Zákazník po vyjížďce appku otevřít nemusí, takže se na klienta spolehnout
-- nedá. Uzavřeme nahrávku, do které dlouho nic nepřiteklo, i tu, které
-- mezitím skončila výpůjčka.
create or replace function public.close_stale_user_rides()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_at timestamptz; v_res jsonb; v_closed int := 0; v_dropped int := 0;
begin
  for v_id, v_at in
    select r.id, coalesce(r.last_fix_at, r.updated_at, r.started_at)
      from user_rides r
      left join bookings b on b.id = r.booking_id
     where r.is_recording
       and (
         -- 3 h bez jediného GPS bodu = vyjížďka dávno skončila
         coalesce(r.last_fix_at, r.updated_at, r.started_at) < now() - interval '3 hours'
         -- pojistka i pro nahrávku, do které něco kape, ale běží nesmyslně dlouho
         or r.started_at < now() - interval '36 hours'
         -- výpůjčka skončila / byla zrušena
         or (b.id is not null and (b.end_date::date < current_date
                                   or b.status in ('completed','cancelled')))
       )
     order by r.started_at
     limit 500
  loop
    begin
      v_res := _ride_finalize(v_id, v_at);
      if v_res->>'discarded' = 'true' then v_dropped := v_dropped + 1;
      else v_closed := v_closed + 1; end if;
    exception when others then
      -- Jedna vadná jízda nesmí shodit úklid ostatních.
      raise warning 'close_stale_user_rides: jízda % selhala: %', v_id, sqlerrm;
    end;
  end loop;
  return jsonb_build_object('closed', v_closed, 'discarded', v_dropped);
end;
$$;
comment on function public.close_stale_user_rides() is
  'Uzavře nahrávky jízd, do kterých 3 h nic nepřiteklo, běží přes 36 h, nebo jim skončila výpůjčka. Bez toho by uq_user_rides_recording zákazníkovi zablokoval každou další jízdu.';

-- Úklid patří cronu (běží pod vlastníkem funkce), ne klientům.
revoke all on function public.close_stale_user_rides() from public;
revoke all on function public.close_stale_user_rides() from anon, authenticated;

do $$
begin
  begin
    perform cron.unschedule('close-stale-user-rides');
  exception when others then null;
  end;
  perform cron.schedule('close-stale-user-rides', '*/15 * * * *',
    $cron$ SELECT public.close_stale_user_rides(); $cron$);
exception when others then
  raise warning 'cron.schedule close-stale-user-rides selhalo (pg_cron nedostupné?): %', sqlerrm;
end $$;

-- ══ 8) ŽIVÁ POLOHA ZÁKAZNÍKA PRO VELÍN ══════════════════════════════
-- Detail rezervace → mapa. Vrací poslední známou polohu z PRÁVĚ NAHRÁVANÉ
-- jízdy k té rezervaci + dosud projetou stopu. Když zákazník polohu
-- zapnutou nemá, vrátí důvod, ať Velín může napsat, co se děje.
create or replace function public.admin_booking_live_ride(p_booking_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_r user_rides; v_b bookings; v_age int; v_track jsonb; v_app timestamptz;
begin
  if not is_admin() then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;

  select * into v_b from bookings where id = p_booking_id;
  if v_b.id is null then return jsonb_build_object('ok', false, 'error', 'booking_not_found'); end if;

  -- Nejdřív právě nahrávaná jízda, jinak poslední jízda z té výpůjčky.
  select * into v_r from user_rides
   where booking_id = p_booking_id
   order by is_recording desc, coalesce(last_fix_at, started_at) desc
   limit 1;

  select max(last_seen_at) into v_app from app_installations where user_id = v_b.user_id;

  if v_r.id is null then
    return jsonb_build_object(
      'ok', true, 'has_ride', false,
      'reason', case when v_app is null then 'no_app'
                     when v_app < now() - interval '14 days' then 'app_idle'
                     else 'no_location' end,
      'app_last_seen', v_app,
      'booking_status', v_b.status);
  end if;

  v_age := greatest(0, (extract(epoch from (now() - coalesce(v_r.last_fix_at, v_r.started_at))))::int);
  -- Stopu pro náhled zkrátíme — Velín nepotřebuje 4000 bodů na mapce.
  v_track := _ride_track_cap(coalesce(v_r.track, '[]'::jsonb), 1200);

  return jsonb_build_object(
    'ok', true, 'has_ride', true,
    'ride_id', v_r.id,
    'is_recording', v_r.is_recording,
    'is_live', v_r.is_recording and v_age < 900,   -- fix mladší 15 min = živá poloha
    -- Poslední známá poloha: konec stopy, jinak (hned po startu) její začátek.
    'lat', coalesce(v_r.end_lat, v_r.start_lat,
                    (v_track->(jsonb_array_length(v_track)-1)->>0)::double precision),
    'lng', coalesce(v_r.end_lng, v_r.start_lng,
                    (v_track->(jsonb_array_length(v_track)-1)->>1)::double precision),
    'last_fix_at', v_r.last_fix_at,
    'age_sec', v_age,
    'started_at', v_r.started_at, 'ended_at', v_r.ended_at,
    'distance_km', round(coalesce(v_r.distance_km, 0), 1),
    'duration_min', v_r.duration_min,
    'moving_sec', v_r.moving_sec, 'idle_sec', v_r.idle_sec, 'gap_sec', v_r.gap_sec,
    'avg_speed_kmh', v_r.avg_speed_kmh, 'max_speed_kmh', v_r.max_speed_kmh,
    'moto_name', v_r.moto_name, 'name', v_r.name,
    'points', jsonb_array_length(coalesce(v_r.track, '[]'::jsonb)),
    'track', v_track,
    'app_last_seen', v_app,
    'booking_status', v_b.status);
end;
$$;
grant execute on function public.admin_booking_live_ride(uuid) to authenticated;
comment on function public.admin_booking_live_ride(uuid) is
  'Velín → detail rezervace → mapa: živá poloha zákazníka z právě nahrávané jízdy + dosud projetá stopa. Jen pro is_admin().';

-- ══ 8b) VELÍN: UZAVŘENÍ ZASEKNUTÉ NAHRÁVKY ═════════════════════════
-- Velín → Trasy → Jízdy zákazníků: tlačítko „Ukončit záznam". Projde
-- stejným `_ride_finalize` jako appka i cron (žádný ruční UPDATE, který
-- by nechal statistiky v rozporu).
create or replace function public.admin_finish_user_ride(p_ride_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_r user_rides;
begin
  if not is_admin() then return jsonb_build_object('success', false, 'error', 'forbidden'); end if;
  select * into v_r from user_rides where id = p_ride_id;
  if v_r.id is null then return jsonb_build_object('success', false, 'error', 'ride_not_found'); end if;
  -- Uzavíráme časem POSLEDNÍHO FIXU, ne „teď" — jinak by se z ticha mezi
  -- posledním bodem a klepnutím operátora stal několikadenní „celkový čas".
  return _ride_finalize(p_ride_id, coalesce(v_r.last_fix_at, v_r.updated_at));
end;
$$;
grant execute on function public.admin_finish_user_ride(uuid) to authenticated;
comment on function public.admin_finish_user_ride(uuid) is
  'Velín: uzavře zaseknutou nahrávku jízdy (stejnou cestou jako appka). Jen pro is_admin().';

-- ══ 9) JEDNORÁZOVÁ OPRAVA HISTORICKÝCH DAT ══════════════════════════
-- Zatuhlé nahrávky uzavřít, statistiky AUTOMATICKÝCH jízd přepočítat
-- novou (mezery vynechávající) matematikou a jízdy, ze kterých po očištění
-- zbude míň než kilometr, zahodit. Ručně poskládané jízdy (`source='manual'`)
-- se NEPŘEPOČÍTÁVAJÍ — jejich stopa je z principu jen rovná spojnice bodů.
do $$
declare
  v_r record; v_st jsonb; v_km numeric; v_dur int;
  v_move int; v_idle int; v_gap int; v_active int; v_avg numeric;
  v_fix timestamptz; v_last jsonb; v_n int := 0; v_del int := 0;
begin
  if to_regclass('public.user_rides') is null then return; end if;

  for v_r in select * from user_rides where source = 'auto' loop
    v_st := _ride_stats(coalesce(v_r.track, '[]'::jsonb));
    v_km := (v_st->>'dist_km')::numeric;
    v_move := (v_st->>'moving_sec')::int;
    v_idle := (v_st->>'idle_sec')::int;
    v_gap := (v_st->>'gap_sec')::int;

    -- Po odečtení vzdušných čar přes mezery z „jízdy" často nezbude nic.
    if v_km < 1.0 then
      delete from user_rides where id = v_r.id;
      v_del := v_del + 1;
      continue;
    end if;

    v_last := case when jsonb_array_length(coalesce(v_r.track, '[]'::jsonb)) > 0
                   then v_r.track -> (jsonb_array_length(v_r.track) - 1) end;
    v_fix := coalesce(
      case when v_last is not null and jsonb_typeof(v_last) = 'array'
             and jsonb_array_length(v_last) > 2
             and (v_last->>2) ~ '^[0-9]+(\.[0-9]+)?$'
           then to_timestamp((v_last->>2)::double precision) end,
      v_r.ended_at, v_r.updated_at, v_r.started_at);
    if v_fix < v_r.started_at then v_fix := v_r.started_at; end if;

    -- Zatuhlou nahrávku uzavřeme časem posledního fixu, ne „teď" —
    -- jinak by z dvoudenního ticha vznikl dvoudenní „celkový čas".
    v_dur := greatest(1,
               (extract(epoch from (coalesce(v_r.ended_at, v_fix) - v_r.started_at)) / 60)::int,
               ceil((v_move + v_idle + v_gap)::numeric / 60)::int);
    if v_move + v_idle + v_gap < v_dur * 60 then
      v_idle := v_dur * 60 - v_move - v_gap;
    end if;
    if v_idle < 0 then v_idle := 0; end if;
    v_active := greatest(v_dur * 60 - v_gap, 60);
    v_avg := nullif(least(case when v_move > 0
               then round((v_km / (v_move::numeric / 3600)), 1)
               else round((v_km / (v_active::numeric / 3600)), 1) end,
               200.1), 200.1);

    update user_rides set
      is_recording = false,
      ended_at = coalesce(ended_at, v_fix),
      last_fix_at = coalesce(last_fix_at, v_fix),
      distance_km = v_km,
      duration_min = v_dur,
      moving_sec = v_move,
      idle_sec = v_idle,
      gap_sec = v_gap,
      elevation_gain_m = (v_st->>'gain_m')::int,
      avg_speed_kmh = v_avg,
      max_speed_kmh = nullif(greatest(coalesce((v_st->>'max_kmh')::numeric, 0),
                                      coalesce(v_avg, 0)), 0),
      name = case when coalesce(trim(name), '') <> '' then name
                  else to_char(started_at at time zone 'Europe/Prague', 'DD.MM.YYYY') end
    where id = v_r.id;
    v_n := v_n + 1;
  end loop;

  raise notice 'user_rides oprava: přepočítáno %, zahozeno % (příliš řídká stopa)', v_n, v_del;
end $$;
