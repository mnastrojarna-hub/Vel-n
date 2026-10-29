-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — „Moje jízdy": pauza, auto-pauza, vícedenní cesty (3/8)
-- Příjem bodů — interní jádro (append_ride_track / finish_user_ride ho
-- volají až od souboru 5/8, do té doby běží živé verze beze změny).
--   _ride_append_core (interní) — filtr dávky (stará jízda, duplicita po
--       opakovaném odeslání, body po vrácení výpůjčky: nová appka +30 s,
--       stará +2 min rezerva na hodiny; čas po roce 2100 = vadný bod; bod
--       z budoucnosti (> teď + 10 min, rozhozené hodiny) se uloží, ale
--       neblokuje další body jako „duplicitní"), „připravený" start (start
--       jízdy = skutečný rozjezd; jen u ještě prázdné jízdy — ≤ 3 body, bez
--       mezery), statistiky v2, etapy, stopa (strop 4000 + 2000 za každou
--       další etapu, max 12 000 bodů). Výpůjčka JEN výbavy (booking_kind
--       = 'gear') není vrácení motorky → body po ní se neořezávají.
--   Dávka jen z bodů po vrácení jízdu NEUZAVÍRÁ — vrátí {booking_ended,
--       end_at} a uzavře volající (_ride_close, closed_by = return).
-- Idempotentní (create or replace se stejným podpisem → práva zůstávají).
-- ════════════════════════════════════════════════════════════════════

create or replace function public._ride_append_core(p_ride_id uuid, p_points jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_r user_rides; v_ret timestamptz; v_now timestamptz := now(); v_track jsonb; v_last jsonb;
  v_lts float8; v_lla float8; v_llo float8; v_start float8; v_maxts float8;
  v_now_e float8 := extract(epoch from now());
  v_pt jsonb; v_ts float8; v_kept jsonb[] := '{}'; v_stale int := 0; v_dup int := 0; v_after int := 0; v_bad int := 0;
  v_i0 int; v_pre jsonb; v_state jsonb; v_stages jsonb; v_st jsonb; v_seg jsonb; v_kj jsonb; v_grace float8;
  v_cap int; v_lp jsonb; v_fix timestamptz; v_km numeric; v_move int; v_gap int; v_pause int;
  v_active float8; v_idle int; v_avg numeric; v_max numeric; v_reset boolean := false;
begin
  select * into v_r from user_rides where id = p_ride_id;          -- volající drží FOR UPDATE
  if v_r.id is null then return jsonb_build_object('success', false, 'error', 'ride_not_found'); end if;
  if v_r.booking_id is not null then
    select returned_at into v_ret from bookings where id = v_r.booking_id and booking_kind <> 'gear';
  end if;
  v_track := case when jsonb_typeof(v_r.track) = 'array' then v_r.track else '[]'::jsonb end;
  if jsonb_array_length(v_track) > 0 then
    v_last := v_track -> (jsonb_array_length(v_track) - 1);
    if jsonb_typeof(v_last) = 'array' and jsonb_array_length(v_last) > 2 and (v_last->>2) ~ '^[0-9]+(\.[0-9]+)?$' then
      v_lts := (v_last->>2)::float8;
      v_lla := case when jsonb_typeof(v_last->0) = 'number' then (v_last->>0)::float8 end;
      v_llo := case when jsonb_typeof(v_last->1) = 'number' then (v_last->>1)::float8 end;
    end if;
    if jsonb_typeof(v_last) <> 'array' then v_last := null; end if;
  end if;
  v_start := extract(epoch from v_r.started_at);
  -- Hranice duplicit jen z věrohodného času: jediný bod z budoucnosti
  -- (rozhozené hodiny 4.1.3) by jinak zahodil celý zbytek jízdy.
  v_maxts := case when v_lts <= v_now_e + 600 then v_lts end;
  -- Rezerva na hodiny telefonu: nová appka má čas srovnaný se serverem (30 s),
  -- stará appka razítkuje časem příjmu z nesrovnaných hodin (2 min).
  v_grace := case when v_r.pause_aware then 30 else 120 end;

  -- 1) Filtr dávky (pořadí bodů zachováno).
  for v_pt in select e.pt from jsonb_array_elements(p_points) with ordinality e(pt, ord) order by e.ord loop
    if jsonb_typeof(v_pt) <> 'array' then v_bad := v_bad + 1; continue; end if;
    if jsonb_array_length(v_pt) < 2 or jsonb_typeof(v_pt->0) <> 'number' or jsonb_typeof(v_pt->1) <> 'number' then
      v_bad := v_bad + 1; continue;
    end if;
    v_ts := case when jsonb_array_length(v_pt) > 2 and (v_pt->>2) ~ '^[0-9]+(\.[0-9]+)?$' then (v_pt->>2)::float8 end;
    if v_ts > 4102444800 then v_bad := v_bad + 1; continue; end if;            -- po roce 2100 = nesmysl
    if v_ts is not null then
      if v_ts < v_start - 3600 then v_stale := v_stale + 1; continue; end if;   -- bod z předchozí jízdy
      if v_ts < v_maxts or (v_ts = v_lts and (v_pt->>0)::float8 = v_lla and (v_pt->>1)::float8 = v_llo) then
        v_dup := v_dup + 1; continue;                                           -- už uloženo (opakovaná dávka)
      end if;
      if v_ret is not null and v_ts > extract(epoch from v_ret) + v_grace then
        v_after := v_after + 1; continue;                                       -- po vrácení výpůjčky
      end if;
      if v_ts <= v_now_e + 600 then v_maxts := v_ts; end if;
    end if;
    v_kept := array_append(v_kept, v_pt);
  end loop;

  if coalesce(array_length(v_kept, 1), 0) = 0 then
    if v_after > 0 and v_now > v_ret + interval '120 seconds' then
      -- Uzavře volající (_ride_close … 'return'); u už uzavřené jízdy nic.
      return jsonb_build_object('booking_ended', true,
        'end_at', least(greatest(coalesce(v_r.last_fix_at, v_r.started_at), v_r.started_at), v_ret));
    end if;
    return jsonb_build_object('success', true, 'points', jsonb_array_length(v_track),
      'distance_km', round(coalesce(v_r.distance_km, 0), 1), 'moving_sec', v_r.moving_sec,
      'idle_sec', v_r.idle_sec, 'gap_sec', v_r.gap_sec, 'pause_sec', v_r.pause_sec,
      'stages_n', jsonb_array_length(coalesce(v_r.stages, '[]'::jsonb)),
      'dropped', v_stale + v_dup + v_after + v_bad, 'dropped_stale', v_stale > 0,
      'now', round(extract(epoch from v_now)::numeric, 3));
  end if;

  v_state := coalesce(v_r.stats_state, '{}'::jsonb) || jsonb_build_object('legacy', not v_r.pause_aware);
  v_stages := case when jsonb_typeof(v_r.stages) = 'array' then v_r.stages else '[]'::jsonb end;

  -- 2) „Připraveno": první značka pauzy v ještě prázdné jízdě = skutečný rozjezd.
  --    Prázdná = nejvýš P0 (≤ 3 body), bez jízdy i bez mezery: řídké body
  --    ze škrceného GPS (jen mezery, 0 km) jsou už jízda a nesmí zmizet.
  if v_r.pause_aware and coalesce(v_r.moving_sec, 0) < 60 and coalesce(v_r.distance_km, 0) < 0.2
     and coalesce(v_r.gap_sec, 0) < 300 and jsonb_array_length(v_track) <= 3 then
    select o.i into v_i0 from unnest(v_kept) with ordinality o(pt, i)
     where jsonb_array_length(o.pt) > 3 and jsonb_typeof(o.pt->3) = 'number' and (o.pt->>3)::float8 < 0
       and jsonb_array_length(o.pt) > 2 and (o.pt->>2) ~ '^[0-9]+(\.[0-9]+)?$'
     order by o.i limit 1;
    if v_i0 is not null then
      v_pre := _ride_stats_v2(case when v_last is not null then jsonb_build_array(v_last) else '[]'::jsonb end
                              || coalesce(to_jsonb(v_kept[1:v_i0 - 1]), '[]'::jsonb), v_state, v_stages);
      if coalesce(v_r.moving_sec, 0) + (v_pre->>'moving_sec')::int < 60
         and coalesce(v_r.distance_km, 0) + (v_pre->>'dist_km')::numeric < 0.2
         and coalesce(v_r.gap_sec, 0) + (v_pre->>'gap_sec')::int < 300 then
        v_reset := true;
        v_r.started_at := least(v_now, to_timestamp((v_kept[v_i0]->>2)::float8));
        v_r.distance_km := 0; v_r.moving_sec := 0; v_r.gap_sec := 0; v_r.pause_sec := 0;
        v_r.elevation_gain_m := 0; v_r.max_speed_kmh := null;
        v_r.start_lat := (v_kept[v_i0]->>0)::float8; v_r.start_lng := (v_kept[v_i0]->>1)::float8;
        v_track := '[]'::jsonb; v_last := null; v_state := '{"legacy": false}'::jsonb; v_stages := '[]'::jsonb;
        v_kept := v_kept[v_i0:];
      end if;
    end if;
  end if;

  -- Jízda rozjetá před nasazením (stopa bez etap): dosavadek jako 1. etapa.
  if jsonb_array_length(v_stages) = 0 and v_last is not null and v_lts is not null then
    v_stages := jsonb_build_array(jsonb_build_object('f', round(v_start::numeric, 1), 't', round(v_lts::numeric, 1),
      'km', round(coalesce(v_r.distance_km, 0), 3), 'mv', coalesce(v_r.moving_sec, 0), 'gap', coalesce(v_r.gap_sec, 0),
      'ps', 0, 'gain', coalesce(v_r.elevation_gain_m, 0), 'max', v_r.max_speed_kmh,
      'a', jsonb_build_array(coalesce(v_r.start_lat, v_lla), coalesce(v_r.start_lng, v_llo)),
      'b', jsonb_build_array(v_lla, v_llo)));
  end if;

  -- 3) Statistiky úseku (poslední uložený bod + dávka), přičtou se.
  v_kj := to_jsonb(v_kept);
  v_seg := case when v_last is not null then jsonb_build_array(v_last) else '[]'::jsonb end || v_kj;
  v_st := _ride_stats_v2(v_seg, v_state, v_stages);

  -- 4) Stopa: + dávka, − body uvnitř běhů stání (stará appka), prořídnutí.
  v_track := v_track || v_kj;
  if jsonb_array_length(v_st->'trims') > 0 then
    select coalesce(jsonb_agg(e.pt order by e.ord), '[]'::jsonb) into v_track
      from jsonb_array_elements(v_track) with ordinality e(pt, ord)
     where not exists (select 1 from jsonb_array_elements(v_st->'trims') tr
                        where case when jsonb_typeof(e.pt) <> 'array' then false
                                   when jsonb_array_length(e.pt) < 3 then false
                                   when not ((e.pt->>2) ~ '^[0-9]+(\.[0-9]+)?$') then false
                                   else (e.pt->>2)::float8 > (tr->>0)::float8 and (e.pt->>2)::float8 < (tr->>1)::float8 end);
  end if;
  v_cap := least(12000, 4000 + 2000 * greatest(0, jsonb_array_length(v_st->'stages') - 1));
  v_track := _ride_track_cap(v_track, v_cap);

  -- 5) Součty a odvozené hodnoty (zastávky = zbytek, nikdy součet).
  v_lp := v_track -> (jsonb_array_length(v_track) - 1);
  v_fix := case when v_lp is not null and jsonb_typeof(v_lp) = 'array' and jsonb_array_length(v_lp) > 2
                     and (v_lp->>2) ~ '^[0-9]+(\.[0-9]+)?$'
                then to_timestamp((v_lp->>2)::float8) else v_now end;
  if v_fix > v_now + interval '1 hour' or v_fix < v_now - interval '30 days' then v_fix := v_now; end if;
  v_km := coalesce(v_r.distance_km, 0) + (v_st->>'dist_km')::numeric;
  v_move := coalesce(v_r.moving_sec, 0) + (v_st->>'moving_sec')::int;
  v_gap := coalesce(v_r.gap_sec, 0) + (v_st->>'gap_sec')::int;
  v_pause := coalesce(v_r.pause_sec, 0) + (v_st->>'pause_sec')::int;
  v_active := greatest(0, extract(epoch from (v_fix - v_r.started_at)) - v_pause);
  v_idle := greatest(0, round(v_active - v_move - v_gap))::int;
  v_avg := case when v_move >= 60 then least(round(v_km / (v_move::numeric / 3600), 1), 200.0) end;
  v_max := greatest(coalesce(v_r.max_speed_kmh, 0), coalesce((v_st->>'max_kmh')::numeric, 0),
                    case when not coalesce((v_st->'state'->>'has_dop')::boolean, false)
                         then coalesce((v_st->'state'->>'nodop_max')::numeric, 0) else 0 end,
                    coalesce(v_avg, 0));

  update user_rides set
    track = v_track, started_at = v_r.started_at,
    distance_km = v_km, moving_sec = v_move, idle_sec = v_idle, gap_sec = v_gap, pause_sec = v_pause,
    elevation_gain_m = coalesce(v_r.elevation_gain_m, 0) + (v_st->>'gain_m')::int,
    last_fix_at = v_fix, avg_speed_kmh = v_avg, max_speed_kmh = v_max,
    duration_min = round(v_active / 60)::int,
    end_lat = coalesce((v_lp->>0)::float8, end_lat), end_lng = coalesce((v_lp->>1)::float8, end_lng),
    start_lat = coalesce(v_r.start_lat, case when jsonb_typeof(v_track->0->0) = 'number' then (v_track->0->>0)::float8 end),
    start_lng = coalesce(v_r.start_lng, case when jsonb_typeof(v_track->0->1) = 'number' then (v_track->0->>1)::float8 end),
    stats_state = v_st->'state', stages = v_st->'stages'
  where id = p_ride_id;

  return jsonb_build_object('success', true, 'points', jsonb_array_length(v_track),
    'distance_km', round(v_km, 1), 'moving_sec', v_move, 'idle_sec', v_idle, 'gap_sec', v_gap,
    'pause_sec', v_pause, 'stages_n', jsonb_array_length(v_st->'stages'),
    'dropped', v_stale + v_dup + v_after + v_bad, 'now', round(extract(epoch from v_now)::numeric, 3));
end;
$$;

revoke all on function public._ride_append_core(uuid, jsonb) from public, anon, authenticated;
grant execute on function public._ride_append_core(uuid, jsonb) to service_role;

notify pgrst, 'reload schema';
