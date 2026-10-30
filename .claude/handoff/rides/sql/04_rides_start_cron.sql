-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — „Moje jízdy": pauza, auto-pauza, vícedenní cesty (6/8)
-- Start, obnova a úklid nahrávek — cesta se už nedělí přes noc.
-- Výpůjčka JEN výbavy (bookings.booking_kind = 'gear', od 2026-10-23) NENÍ
-- jízda na motorce: nikde se s ní nepáruje, nedrží jízdu otevřenou ani ji
-- neořezává vrácením; jízdy k ní dřív spárované se odpojí (= vlastní jízda).
-- „Skončená" výpůjčka = _ride_booking_end (vrácení, nebo motorka zaparkovaná
-- v kóji kiosku před posledním dnem — kiosk ji dokončí až den po konci).
--   start_user_trip(p_booking_id) — NOVÉ RPC pro novou appku (bez DEFAULT,
--       žádné přetížení): založí/převezme jízdu s pause_aware = true;
--       výpůjčka jen vlastní, reserved/active a neskončená (převzetí hlídá
--       appka), ne výbava (jinak booking_inactive, nic nevznikne); bez
--       párování podle data (ruční jízda ≠ výpůjčka); vrací i `now`.
--       Motorka znovu vyjela z kóje (zaparkovaná přes noc, state out) →
--       pokračuje TÁŽ jízda (znovu otevřená, + reopened) — nedělí se.
--   start_user_trip_from(p_booking_id, p_first_ts) — NOVÉ RPC (bez DEFAULT):
--       totéž pro relaci, která začala OFFLINE (p_first_ts = první bod
--       relace, epoch s, osa serveru): nová jízda začne tímto časem (nejdál
--       7 dní zpět, u výpůjčky ne dřív než převzetí − 10 min), takže body
--       z doby bez dat se nezahodí jako „stará jízda"; převzatá ještě prázdná
--       jízda se posune na něj. Výpůjčka skončená ≤ 7 dní, ke které jízda
--       ještě NEEXISTUJE a p_first_ts < konec → jízda se založí zpětně
--       (+ retro; body do konce uloží, po něm zahodí, uzavře úklid / Stop).
--       Appka ho volá jen pro relaci bez jízdy na serveru, nikdy při navázání.
--   _ride_start_trip (interní) — společné jádro obou (uživatel z auth.uid()).
--   _ride_reopen_parked (interní) — znovuotevření jízdy výpůjčky po vyjetí
--       z kóje: jen poslední jízda té výpůjčky uzavřená automaticky (return
--       | cron | start), skončená nejpozději při vyjetí (+10 min), ≤ 60 dní.
--   start_user_ride — stejný podpis/klíče; rozjetá jízda s AKTIVNÍ
--       neskončenou výpůjčkou se obnoví v jakémkoli stáří (4.1.3 už výpůjčku
--       nedělí), vlastní jízda nové appky do 72 h, jinak dál 3 h (4.1.3 beze
--       změny); párování podle data jen s neskončenou výpůjčkou motorky; id
--       výbavy nebo zaparkované výpůjčky → booking_inactive (4.1.3 pak
--       nenahrává); po vyjetí z kóje pokračuje táž jízda (resumed).
--   close_stale_user_rides — výpůjčka se uzavře až jejím koncem (vrácení
--       nebo zaparkování v kóji kiosku = _ride_booking_end, zrušení, 2 dny
--       po konci, 60 dní), k času konce; vlastní cesta nové appky po 72 h
--       bez jízdy / 30 dnech; stará appka 3 h / 36 h.
--       Uzavřené značí stats_state.closed_by = cron (start → start).
--       Jízda pod 1 km by se uzavřením SMAZALA — a s ní i body, které telefon
--       bez dat teprve pošle. Proto zůstane otevřená: skončená výpůjčka
--       motorky do 7 dní po konci (okno pozdních bodů), vlastní cesta nové
--       appky do 30 dní od startu (místo 72 h). Pak se smaže jako dřív.
--   admin_booking_live_ride — + pause_aware, pause_sec, is_standing (jen
--       u neskončené výpůjčky — zaparkovaná v kóji už „nestojí").
-- Idempotentní (create or replace; nové funkce bez přetížení; oprava dat
-- jen odpojí booking_id od výbavy — podruhé nic nenajde).
-- ════════════════════════════════════════════════════════════════════

-- Jízdy omylem spárované s výpůjčkou JEN výbavy (4.1.3 páruje podle data
-- od 2026-10-23) se odpojí → dál se chovají jako vlastní jízda.
update public.user_rides r set booking_id = null
  from public.bookings b
 where b.id = r.booking_id and b.booking_kind = 'gear';

create or replace function public._ride_trip_json(p_r public.user_rides, p_resumed boolean, p_now timestamptz)
returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object('success', true, 'id', p_r.id, 'resumed', p_resumed,
    'booking_id', p_r.booking_id, 'moto_name', p_r.moto_name, 'pause_aware', true,
    'started_at', p_r.started_at, 'distance_km', round(coalesce(p_r.distance_km, 0), 1),
    'moving_sec', coalesce(p_r.moving_sec, 0), 'pause_sec', coalesce(p_r.pause_sec, 0),
    'stages_n', jsonb_array_length(case when jsonb_typeof(p_r.stages) = 'array' then p_r.stages else '[]'::jsonb end),
    'now', round(extract(epoch from p_now)::numeric, 3))
$$;

create or replace function public._ride_reopen_parked(p_uid uuid, p_booking_id uuid, p_adopt boolean)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_b bookings; v_out timestamptz; v_r user_rides;
begin
  select * into v_b from bookings where id = p_booking_id and user_id = p_uid;
  if v_b.id is null or v_b.booking_kind = 'gear' or v_b.status not in ('reserved', 'active')
     or _ride_booking_end(v_b.id) is not null then
    return null;
  end if;
  -- Kóje: motorka po zaparkování znovu vyjela (přes noc v kóji, výpůjčka běží dál).
  select k.out_at into v_out from booking_kiosk_returns k
   where k.booking_id = v_b.id and k.state = 'out' and k.out_at is not null;
  if v_out is null then return null; end if;
  select * into v_r from user_rides r
   where r.user_id = p_uid and r.booking_id = v_b.id
   order by r.started_at desc limit 1 for update;
  if v_r.id is null or v_r.is_recording
     or coalesce(v_r.stats_state->>'closed_by', '') not in ('return', 'cron', 'start')
     or v_r.ended_at is null or v_r.ended_at > v_out + interval '10 minutes'
     or v_r.started_at < now() - interval '60 days' then
    return null;                                     -- Stop jezdce / admin / stará / jiná jízda
  end if;
  begin
    update user_rides set is_recording = true, ended_at = null,
           pause_aware = pause_aware or coalesce(p_adopt, false),
           stats_state = case when coalesce(p_adopt, false) and not pause_aware
                              then coalesce(stats_state, '{}'::jsonb) - 'closed_by' - 'still_from' - 'still_pt'
                              else coalesce(stats_state, '{}'::jsonb) - 'closed_by' end,
           -- automatický název (datum / rozsah) se při dalším uzavření sestaví znovu
           name = case when ended_at is not null and name = _ride_auto_name(
                         (started_at at time zone 'Europe/Prague')::date,
                         (ended_at at time zone 'Europe/Prague')::date) then '' else name end
     where id = v_r.id;
  exception when unique_violation then
    return null;                                     -- souběžný start jiné jízdy
  end;
  return v_r.id;
end;
$$;

create or replace function public._ride_start_trip(p_uid uuid, p_booking_id uuid, p_first_ts double precision)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_now timestamptz := now(); v_b bookings; v_o user_rides; v_last timestamptz; v_oend timestamptz;
  v_end timestamptz; v_first timestamptz; v_retro boolean := false; v_moto_name text; v_id uuid;
  v_inactive jsonb := jsonb_build_object('success', false, 'error', 'booking_inactive',
                                         'now', round(extract(epoch from now())::numeric, 3));
begin
  if p_uid is null then return jsonb_build_object('success', false, 'error', 'not_authenticated'); end if;
  -- Začátek relace z telefonu (start offline): jen věrohodný čas, nejvýš 7 dní zpět, ne v budoucnu.
  if p_first_ts between 946684800 and 4102444800 then
    v_first := greatest(least(to_timestamp(p_first_ts), v_now), v_now - interval '7 days');
  end if;
  if p_booking_id is not null then
    select * into v_b from bookings where id = p_booking_id and user_id = p_uid;
    if v_b.id is null or v_b.booking_kind = 'gear' or v_b.status not in ('reserved', 'active', 'completed') then
      return v_inactive;
    end if;
    if v_first is not null then
      v_first := greatest(v_first, coalesce(v_b.picked_up_at, v_b.start_date) - interval '10 minutes');
    end if;
    v_end := _ride_booking_end(v_b.id);
    if v_b.status = 'completed' or v_end is not null then
      -- Skončená výpůjčka: jízdu založí (zpětně) jen telefon, který nahrával offline
      -- už před koncem, a jen když k ní ještě žádná jízda není (≤ 7 dní po konci).
      if v_first is null or v_end is null or v_first >= v_end or v_end < v_now - interval '7 days'
         or exists (select 1 from user_rides where user_id = p_uid and booking_id = v_b.id) then
        return v_inactive;
      end if;
      v_retro := true;
    end if;
  end if;

  -- Rozjetá jízda spárovaná s výbavou = vlastní jízda (samoléčení, obvykle nic).
  update user_rides r set booking_id = null from bookings b
   where r.user_id = p_uid and r.is_recording and b.id = r.booking_id and b.booking_kind = 'gear';
  select * into v_o from user_rides where user_id = p_uid and is_recording limit 1 for update;
  if v_o.id is not null then
    v_last := greatest(coalesce(v_o.last_fix_at, v_o.started_at), v_o.updated_at);
    if not v_retro and v_o.booking_id is not distinct from p_booking_id
       and (p_booking_id is not null or v_last > v_now - interval '72 hours') then
      -- Převzetí jízdy založené starou cestou: rozběhnuté stání se zahodí.
      -- (Už převzatou nepřepisujeme — updated_at se nesmí posunout, jinak
      -- by každé otevření appky oddálilo uzavření po 72 h bez jízdy.)
      if not v_o.pause_aware then
        update user_rides set pause_aware = true,
               stats_state = coalesce(stats_state, '{}'::jsonb) - 'still_from' - 'still_pt'
         where id = v_o.id returning * into v_o;
      end if;
      -- Start offline: ještě prázdná jízda začne prvním bodem relace.
      if v_first < v_o.started_at and jsonb_typeof(v_o.track) = 'array' and jsonb_array_length(v_o.track) = 0 then
        update user_rides set started_at = v_first where id = v_o.id returning * into v_o;
      end if;
      return _ride_trip_json(v_o, true, v_now);
    end if;
    v_oend := _ride_booking_end(v_o.booking_id);
    perform _ride_close(v_o.id, case when v_oend is not null then least(v_last, v_oend) else v_last end, 'start', false);
  end if;

  -- Motorka znovu vyjela z kóje kiosku → pokračuje TÁŽ jízda výpůjčky.
  if p_booking_id is not null and not v_retro then
    v_id := _ride_reopen_parked(p_uid, p_booking_id, true);
    if v_id is not null then
      select * into v_o from user_rides where id = v_id;
      return _ride_trip_json(v_o, true, v_now) || jsonb_build_object('reopened', true);
    end if;
  end if;

  if v_b.moto_id is not null then
    select nullif(trim(coalesce(m.brand, '') || ' ' || coalesce(m.model, '')), '')
      into v_moto_name from motorcycles m where m.id = v_b.moto_id;
  end if;
  begin
    insert into user_rides (user_id, booking_id, moto_id, moto_name, source, pause_aware,
                            track, stats_state, stages, is_recording, started_at)
    values (p_uid, p_booking_id, v_b.moto_id, v_moto_name, 'auto', true,
            '[]'::jsonb, '{}'::jsonb, '[]'::jsonb, true, coalesce(v_first, v_now))
    returning * into v_o;
  exception when unique_violation then
    -- Souběžný start (dva požadavky naráz): vrátí se ta, která vznikla.
    update user_rides set pause_aware = true where user_id = p_uid and is_recording returning * into v_o;
    if v_o.id is null then raise; end if;
    return _ride_trip_json(v_o, true, v_now);
  end;
  return _ride_trip_json(v_o, false, v_now)
      || case when v_retro then jsonb_build_object('retro', true) else '{}'::jsonb end;
end;
$$;

create or replace function public.start_user_trip(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return _ride_start_trip(auth.uid(), p_booking_id, null);
end;
$$;

create or replace function public.start_user_trip_from(p_booking_id uuid, p_first_ts double precision)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return _ride_start_trip(auth.uid(), p_booking_id, p_first_ts);
end;
$$;

comment on function public.start_user_trip_from(uuid, double precision) is
  'Appka: start nahrávky relace, která začala offline (p_first_ts = první bod, epoch s): jízda začne tímto časem (≤ 7 dní zpět, výpůjčka ≥ převzetí − 10 min); skončená výpůjčka bez jízdy (≤ 7 dní) se založí zpětně (+ retro). Jinak jako start_user_trip.';

create or replace function public.start_user_ride(p_booking_id uuid default null::uuid,
  p_lat double precision default null::double precision, p_lng double precision default null::double precision)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_id uuid; v_booking uuid; v_moto uuid; v_moto_name text; v_track jsonb := '[]'::jsonb;
  v_stale timestamptz; v_obk uuid; v_paw boolean; v_bst text; v_bret timestamptz; v_resume boolean;
begin
  if auth.uid() is null then return jsonb_build_object('success', false, 'error', 'not_authenticated'); end if;
  -- Výpůjčka JEN výbavy není jízda na motorce → nic nezaložit (4.1.3: success
  -- false = nenahrává, stejně jako bez výpůjčky).
  if p_booking_id is not null and exists (select 1 from bookings
       where id = p_booking_id and user_id = auth.uid() and booking_kind = 'gear') then
    return jsonb_build_object('success', false, 'error', 'booking_inactive');
  end if;
  update user_rides r set booking_id = null from bookings b
   where r.user_id = auth.uid() and r.is_recording and b.id = r.booking_id and b.booking_kind = 'gear';

  -- Rozjetá nahrávka: výpůjčka s aktivní neskončenou rezervací se obnoví v jakémkoli
  -- stáří (přes noc se nedělí), vlastní cesta nové appky do 72 h, jinak 3 h jako dřív.
  select id, booking_id, pause_aware, greatest(coalesce(last_fix_at, started_at), updated_at)
    into v_id, v_obk, v_paw, v_stale
    from user_rides where user_id = auth.uid() and is_recording limit 1;
  if v_id is not null then
    if v_obk is not null then
      select status into v_bst from bookings where id = v_obk;
      v_bret := _ride_booking_end(v_obk);
    end if;
    v_resume := case
      when v_obk is not null and v_bst in ('reserved', 'active') and v_bret is null
           and (p_booking_id is null or p_booking_id = v_obk) then true
      when v_paw and v_obk is null then v_stale > now() - interval '72 hours'
      else v_stale > now() - interval '3 hours' end;
    if v_resume then
      return jsonb_build_object('success', true, 'id', v_id, 'resumed', true);
    end if;
    perform _ride_close(v_id, case when v_bret is not null then least(v_stale, v_bret) else v_stale end, 'start', false);
    v_id := null;
  end if;

  if p_booking_id is not null then
    -- Motorka zaparkovaná v kóji kiosku (vrácení před posledním dnem, kiosk dokončí
    -- až po konci) → nenahrávat (4.1.3: success false = nenahrává).
    if exists (select 1 from bookings b where b.id = p_booking_id and b.user_id = auth.uid()
                 and b.booking_kind <> 'gear' and b.status in ('reserved', 'active')
                 and _ride_booking_end(b.id) is not null) then
      return jsonb_build_object('success', false, 'error', 'booking_inactive');
    end if;
    -- Motorka znovu vyjela z kóje → pokračuje TÁŽ jízda výpůjčky.
    v_id := _ride_reopen_parked(auth.uid(), p_booking_id, false);
    if v_id is not null then return jsonb_build_object('success', true, 'id', v_id, 'resumed', true); end if;
  end if;

  -- Beze změny: s id rezervace párování podle id, bez id podle dnešního dne
  -- (jen neskončená výpůjčka motorky — výbava ani zaparkovaná se nepáruje).
  select b.id, b.moto_id into v_booking, v_moto
  from bookings b
  where b.user_id = auth.uid()
    and b.status in ('reserved','active')
    and b.booking_kind <> 'gear'
    and (b.id = p_booking_id
         or (p_booking_id is null
             and b.start_date::date <= current_date and b.end_date::date >= current_date))
    and _ride_booking_end(b.id) is null
  order by b.start_date desc limit 1;

  if v_moto is not null then
    select nullif(trim(coalesce(m.brand,'') || ' ' || coalesce(m.model,'')), '')
      into v_moto_name from motorcycles m where m.id = v_moto;
  end if;

  if p_lat is not null and p_lng is not null then
    v_track := jsonb_build_array(jsonb_build_array(p_lat, p_lng, round(extract(epoch from now()))));
  end if;

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

create or replace function public.close_stale_user_rides()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_at timestamptz; v_res jsonb; v_closed int := 0; v_dropped int := 0;
begin
  for v_id, v_at in
    select r.id,
           least(greatest(coalesce(r.last_fix_at, r.started_at), r.updated_at), coalesce(e.v_end, 'infinity'::timestamptz))
      from user_rides r
      left join bookings b on b.id = r.booking_id
      -- konec výpůjčky: vrácení, nebo dřív zaparkování v kóji kiosku (výbava NULL)
      left join lateral (select public._ride_booking_end(b.id) as v_end) e on true
     where r.is_recording
       and case
         -- Výpůjčka motorky (jakákoli appka): jen konec výpůjčky, ne ticho přes noc.
         -- (Spárovaná výbava se uklízí jako vlastní jízda.)
         when r.booking_id is not null and b.booking_kind is distinct from 'gear' then
           case
             -- Skončená, na serveru < 1 km (telefon bez dat od převzetí): smazání
             -- by zahodilo i den, který telefon teprve pošle → čekat 7 dní.
             when e.v_end is not null and coalesce(r.distance_km, 0) < 1
                  and e.v_end > now() - interval '7 days'
                  and r.started_at >= now() - interval '60 days' then false
             else b.id is null or b.status in ('completed', 'cancelled')
               or e.v_end < now() - interval '10 minutes'
               or b.end_date::date < (now() at time zone 'Europe/Prague')::date - 1
               or r.started_at < now() - interval '60 days'
           end
         -- Vlastní cesta nové appky (pauzuje sama): 72 h bez jízdy, max 30 dní;
         -- pod 1 km (offline hned po startu) až po 30 dnech — jinak smazání.
         when r.pause_aware then
              (greatest(coalesce(r.last_fix_at, r.started_at), r.updated_at) < now() - interval '72 hours'
               and coalesce(r.distance_km, 0) >= 1)
           or r.started_at < now() - interval '30 days'
         -- Stará appka (4.1.3): beze změny 3 h bez bodu / 36 h celkem.
         else greatest(coalesce(r.last_fix_at, r.started_at), r.updated_at) < now() - interval '3 hours'
           or r.started_at < now() - interval '36 hours'
       end
     order by r.started_at
     limit 500
  loop
    begin
      v_res := _ride_close(v_id, v_at, 'cron', false);
      if v_res->>'discarded' = 'true' then v_dropped := v_dropped + 1;
      else v_closed := v_closed + 1; end if;
    exception when others then
      raise warning 'close_stale_user_rides: jízda % selhala: %', v_id, sqlerrm;
    end;
  end loop;
  return jsonb_build_object('closed', v_closed, 'discarded', v_dropped);
end;
$$;

comment on function public.close_stale_user_rides() is
  'Uzavře nahrávky jízd: výpůjčka motorky až koncem výpůjčky (vrácení nebo zaparkování v kóji kiosku/zrušení/2 dny po konci/60 dní, k času konce; skončená pod 1 km až 7 dní po konci — pozdní body z telefonu bez dat), vlastní cesta nové appky po 72 h bez jízdy (pod 1 km až po 30 dnech) nebo 30 dnech, stará appka po 3 h bez bodu nebo 36 h (jízda spárovaná s výpůjčkou jen výbavy = vlastní). Značí stats_state.closed_by = cron (vlastní cestu pak nové body znovu otevřou — _ride_reopen). Bez toho by uq_user_rides_recording zablokoval další jízdu.';

create or replace function public.admin_booking_live_ride(p_booking_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_r user_rides; v_b bookings; v_age int; v_track jsonb; v_app timestamptz;
begin
  if not is_admin() then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;

  select * into v_b from bookings where id = p_booking_id;
  if v_b.id is null then return jsonb_build_object('ok', false, 'error', 'booking_not_found'); end if;

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
  v_track := _ride_track_cap(coalesce(v_r.track, '[]'::jsonb), 1200);

  return jsonb_build_object(
    'ok', true, 'has_ride', true,
    'ride_id', v_r.id,
    'is_recording', v_r.is_recording,
    'is_live', v_r.is_recording and v_age < 900,
    -- Stojí: nahrávka běží, ale 15+ min bez bodu u probíhající výpůjčky
    -- (nová appka mezi zastávkami nic neposílá — poloha = kde zastavil).
    'is_standing', v_r.is_recording and v_age >= 900 and v_b.status in ('reserved', 'active')
                   and _ride_booking_end(v_b.id) is null,
    'pause_aware', v_r.pause_aware, 'pause_sec', v_r.pause_sec,
    'lat', coalesce(v_r.end_lat, v_r.start_lat,
                    case when jsonb_typeof(v_track->(jsonb_array_length(v_track)-1)->0) = 'number'
                         then (v_track->(jsonb_array_length(v_track)-1)->>0)::double precision end),
    'lng', coalesce(v_r.end_lng, v_r.start_lng,
                    case when jsonb_typeof(v_track->(jsonb_array_length(v_track)-1)->1) = 'number'
                         then (v_track->(jsonb_array_length(v_track)-1)->>1)::double precision end),
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

revoke all on function public._ride_trip_json(public.user_rides, boolean, timestamptz) from public, anon, authenticated;
grant execute on function public._ride_trip_json(public.user_rides, boolean, timestamptz) to service_role;
revoke all on function public._ride_reopen_parked(uuid, uuid, boolean) from public, anon, authenticated;
grant execute on function public._ride_reopen_parked(uuid, uuid, boolean) to service_role;
revoke all on function public._ride_start_trip(uuid, uuid, double precision) from public, anon, authenticated;
grant execute on function public._ride_start_trip(uuid, uuid, double precision) to service_role;
revoke all on function public.start_user_trip(uuid) from public, anon;
grant execute on function public.start_user_trip(uuid) to authenticated, service_role;
revoke all on function public.start_user_trip_from(uuid, double precision) from public, anon;
grant execute on function public.start_user_trip_from(uuid, double precision) to authenticated, service_role;

notify pgrst, 'reload schema';
