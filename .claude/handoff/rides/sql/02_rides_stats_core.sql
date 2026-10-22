-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — „Moje jízdy": pauza, auto-pauza, vícedenní cesty (2/7)
-- Jádro statistik v2 (interní, klient je nevolá):
--   _ride_prague_night(od, do) — pauza zasahuje do 00:00–05:00 Praha?
--   _ride_stage_days(stages)   — počet dní cesty z etap
--   _ride_stats_v2(úsek, stav, etapy) — klasifikace dvojic bodů:
--       bod s kmh < 0 = PAUZA (appka), ticho > 3 min: projeto ≥ 15 km/h
--       = bez signálu, jinak ≥ 5 min = pauza; JÍZDA jen s Dopplerem ≥ 7 km/h
--       (bez Doppleru odvozeně ≥ 15 km/h) → chůze ani „bloudění" polohy
--       nepřidají km; max jen z Doppleru s kontrolou věrohodnosti;
--       nastoupáno vyhlazené (EMA 0,25 + práh 6 m); etapy po dnech;
--       u starých appek (legacy) se běh stání/chůze ≥ 5 min mění v pauzu
--       a body uvnitř se ze stopy vyjmou (trims).
--   _ride_stats(stopa) — stejný podpis i klíče jako dřív, počítá přes v2.
--   _ride_track_cap(stopa, max) — stejný podpis; nové prořídnutí podle
--       vzdálenosti (rozestup 20 m · 2^k), drží okraje mezer a značky pauz.
-- Idempotentní (create or replace se stejnými podpisy).
-- ════════════════════════════════════════════════════════════════════

create or replace function public._ride_prague_night(p_from double precision, p_to double precision)
returns boolean language sql stable set search_path = public as $$
  select case
    when p_from is null or p_to is null or p_to < p_from then false
    else (to_timestamp(p_to) at time zone 'Europe/Prague')::date
           > (to_timestamp(p_from) at time zone 'Europe/Prague')::date
      or (to_timestamp(p_from) at time zone 'Europe/Prague')::time < time '05:00'
  end
$$;

create or replace function public._ride_stage_days(p_stages jsonb)
returns integer language sql stable set search_path = public as $$
  select greatest(1, count(distinct d)::int)
  from (
    select (to_timestamp((s->>'f')::double precision) at time zone 'Europe/Prague')::date as d
      from jsonb_array_elements(case when jsonb_typeof(p_stages) = 'array' then p_stages else '[]'::jsonb end) s
     where jsonb_typeof(s) = 'object' and coalesce((s->>'mv')::numeric, 0) >= 300
    union
    select (to_timestamp((s->>'t')::double precision) at time zone 'Europe/Prague')::date
      from jsonb_array_elements(case when jsonb_typeof(p_stages) = 'array' then p_stages else '[]'::jsonb end) s
     where jsonb_typeof(s) = 'object' and coalesce((s->>'mv')::numeric, 0) >= 300
  ) x
$$;

create or replace function public._ride_stats_v2(p_seg jsonb, p_state jsonb, p_stages jsonb)
returns jsonb language plpgsql stable set search_path = public as $$
declare
  c_gap_dt constant float8 := 180;     c_gap_v constant float8 := 15;      c_still_km constant float8 := 0.3;
  c_pause_min constant float8 := 300;  c_bad_dt constant float8 := 2592000;
  c_jump_v constant float8 := 250;     c_jump0_km constant float8 := 0.5;
  c_move_v constant float8 := 3;       c_move_dop constant float8 := 7;
  c_move_nodop_v constant float8 := 15; c_move_nodop_dt constant float8 := 3;
  c_max_dop constant float8 := 250;    c_max_rel constant float8 := 1.5;
  c_max_abs constant float8 := 20;     c_max_rel_dt constant float8 := 4;   c_nodop_max_dt constant float8 := 30;
  c_ema constant float8 := 0.25;       c_hyst constant float8 := 6;
  c_spike_rel constant float8 := 0.25; c_spike_abs constant float8 := 10;
  c_stage_long constant float8 := 21600; c_stage_night_min constant float8 := 1800; c_stage_max constant int := 60;
  st jsonb := coalesce(case when jsonb_typeof(p_state) = 'object' then p_state end, '{}'::jsonb);
  v_legacy boolean := coalesce((st->>'legacy')::boolean, false);
  v_ema float8 := (st->>'ema')::float8;  v_ref float8 := (st->>'ref')::float8;  v_palt float8 := (st->>'palt')::float8;
  v_sf float8 := (st->>'still_from')::float8;
  v_sla float8 := (st->'still_pt'->>0)::float8;  v_slo float8 := (st->'still_pt'->>1)::float8;
  v_has_dop boolean := coalesce((st->>'has_dop')::boolean, false);
  v_nodop float8 := coalesce((st->>'nodop_max')::float8, 0);
  v_gr float8 := coalesce((st->>'gr')::float8, 0);
  v_done jsonb := '[]'::jsonb;  v_n int := 0;          -- uzavřené etapy, počet etap vč. běžící
  s_f float8; s_t float8; s_km float8; s_mv float8; s_gap float8; s_ps float8; s_gain float8; s_max float8;
  s_ala float8; s_alo float8; s_bla float8; s_blo float8;
  v_pt jsonb; la float8; lo float8; ts float8; kmh float8; alt float8; n int;
  v_prev boolean := false; v_xla float8; v_xlo float8;  -- předchozí platný bod (i bez času)
  p_ts float8; p_la float8; p_lo float8; p_kmh float8; p_alt float8;  -- předchozí bod s časem
  v_dseg float8 := 0; d_step float8; d float8; dt float8; v float8; dp float8; dq float8; dop float8;
  v_rule text; v_close boolean; v_pf float8; v_pt2 float8; v_dur float8; v_bla float8; v_blo float8; v_bound boolean;
  v_dist float8 := 0; v_move float8 := 0; v_gap float8 := 0; v_pause float8 := 0; v_idle float8 := 0;
  v_gain float8 := 0; v_max float8 := 0; v_nodop_b float8 := 0; v_trims jsonb := '[]'::jsonb; v_gi float8;
begin
  if jsonb_typeof(p_stages) = 'array' and jsonb_array_length(p_stages) > 0 then
    v_n := jsonb_array_length(p_stages);
    v_done := p_stages - (v_n - 1);
    v_pt := p_stages -> (v_n - 1);
    s_f := (v_pt->>'f')::float8; s_t := (v_pt->>'t')::float8; s_km := coalesce((v_pt->>'km')::float8, 0);
    s_mv := coalesce((v_pt->>'mv')::float8, 0); s_gap := coalesce((v_pt->>'gap')::float8, 0);
    s_ps := coalesce((v_pt->>'ps')::float8, 0); s_gain := coalesce((v_pt->>'gain')::float8, 0);
    s_max := coalesce((v_pt->>'max')::float8, 0);
    s_ala := (v_pt->'a'->>0)::float8; s_alo := (v_pt->'a'->>1)::float8;
    s_bla := (v_pt->'b'->>0)::float8; s_blo := (v_pt->'b'->>1)::float8;
  end if;

  for v_pt in select e from jsonb_array_elements(case when jsonb_typeof(p_seg) = 'array' then p_seg else '[]'::jsonb end) e loop
    if jsonb_typeof(v_pt) <> 'array' then continue; end if;
    n := jsonb_array_length(v_pt);
    if n < 2 or jsonb_typeof(v_pt->0) <> 'number' or jsonb_typeof(v_pt->1) <> 'number' then continue; end if;
    la := (v_pt->>0)::float8; lo := (v_pt->>1)::float8;
    ts := case when n > 2 and (v_pt->>2) ~ '^[0-9]+(\.[0-9]+)?$' then (v_pt->>2)::float8 end;
    kmh := case when n > 3 and jsonb_typeof(v_pt->3) = 'number' then (v_pt->>3)::float8 end;
    alt := case when n > 4 and jsonb_typeof(v_pt->4) = 'number' then (v_pt->>4)::float8 end;
    if kmh > 0 and kmh < c_max_dop then v_has_dop := true; end if;

    if not v_prev then                                   -- první bod úseku
      v_prev := true; v_xla := la; v_xlo := lo;
      if ts is not null then
        p_ts := ts; p_la := la; p_lo := lo; p_kmh := kmh; p_alt := alt; v_dseg := 0;
        if v_n = 0 then v_n := 1; s_f := ts; s_t := ts; s_km := 0; s_mv := 0; s_gap := 0; s_ps := 0; s_gain := 0; s_max := 0;
          s_ala := la; s_alo := lo; s_bla := la; s_blo := lo; end if;
      end if;
      continue;
    end if;

    d_step := 6371 * 2 * asin(least(1, sqrt(power(sin(radians(la - v_xla) / 2), 2)
              + cos(radians(v_xla)) * cos(radians(la)) * power(sin(radians(lo - v_xlo) / 2), 2))));
    v_dseg := v_dseg + d_step;
    v_xla := la; v_xlo := lo;

    if ts is null or p_ts is null then                  -- pravidlo 1: bez času (prastaré stopy)
      v_dist := v_dist + d_step;
      if ts is not null then
        p_ts := ts; p_la := la; p_lo := lo; p_kmh := kmh; p_alt := alt; v_dseg := 0;
        if v_n = 0 then v_n := 1; s_f := ts; s_t := ts; s_km := 0; s_mv := 0; s_gap := 0; s_ps := 0; s_gain := 0; s_max := 0;
          s_ala := la; s_alo := lo; s_bla := la; s_blo := lo; end if;
      end if;
      continue;
    end if;

    dt := ts - p_ts; d := v_dseg;
    v := case when dt > 0 then d / dt * 3600 end;
    dp := case when p_kmh > 0 and p_kmh < c_max_dop then p_kmh else 0 end;
    dq := case when kmh > 0 and kmh < c_max_dop then kmh else 0 end;
    dop := greatest(dp, dq);
    v_rule := case
      when dt < 0 or dt >= c_bad_dt then 'bad'
      when kmh < 0 then 'pause'
      when dt > c_gap_dt then case when v >= c_gap_v and d > c_still_km then 'gap'
                                   when dt >= c_pause_min then 'ipause' else 'stop' end
      when coalesce(v >= c_jump_v, false) or (dt = 0 and d >= c_jump0_km) then 'jump'
      when dt = 0 and dop >= c_move_dop then 'zero'
      when v >= c_move_v and (dop >= c_move_dop
           or (dp = 0 and dq = 0 and dt >= c_move_nodop_dt and v >= c_move_nodop_v)) then 'move'
      else 'still' end;

    -- Stará appka (legacy): stání / chůze / ticho bez projetí je „běh stání";
    -- uzavře ho jízda, mezera, značka pauzy nebo nesmyslný čas.
    v_close := false;
    if v_legacy then
      if v_rule in ('still', 'stop', 'ipause') then
        if v_sf is null then v_sf := p_ts; v_sla := p_la; v_slo := p_lo; end if;
        if v_rule = 'ipause' then v_rule := 'still'; end if;
      elsif v_rule <> 'jump' and v_sf is not null then
        v_close := true;
      end if;
    end if;

    -- Až 2 pauzy na dvojici: uzavřený běh stání [still_from, p] a pak pauza [p, q].
    for i in 1..2 loop
      v_bound := null;
      if i = 1 and v_close then
        v_dur := p_ts - v_sf;
        if v_dur >= c_pause_min then
          v_pf := v_sf; v_pt2 := p_ts; v_bla := v_sla; v_blo := v_slo; v_bound := false;
          v_trims := v_trims || jsonb_build_array(jsonb_build_array(round(v_sf::numeric, 1), round(p_ts::numeric, 1)));
        end if;
        v_sf := null; v_sla := null; v_slo := null;
      elsif i = 2 and v_rule in ('pause', 'ipause') then
        v_dur := dt; v_pf := p_ts; v_pt2 := ts; v_bla := p_la; v_blo := p_lo; v_bound := false;
      end if;
      if v_bound is not null then
        v_pause := v_pause + v_dur;
        v_ema := null; v_ref := null; v_palt := null;
        v_bound := v_n < c_stage_max and (v_dur >= c_stage_long
                   or (v_dur >= c_stage_night_min and _ride_prague_night(v_pf, v_pt2)));
        if v_bound then
          v_done := v_done || jsonb_build_array(jsonb_build_object(
            'f', round(s_f::numeric, 1), 't', round(v_pf::numeric, 1), 'km', round(s_km::numeric, 3),
            'mv', round(s_mv)::int, 'gap', round(s_gap)::int, 'ps', round(s_ps)::int, 'gain', round(s_gain)::int,
            'max', nullif(round(s_max::numeric, 1), 0),
            'a', jsonb_build_array(s_ala, s_alo), 'b', jsonb_build_array(v_bla, v_blo)));
          v_n := v_n + 1;
          s_f := v_pt2; s_t := v_pt2; s_km := 0; s_mv := 0; s_gap := 0; s_ps := 0; s_gain := 0; s_max := 0;
          if i = 1 then s_ala := p_la; s_alo := p_lo; else s_ala := la; s_alo := lo; end if;
          s_bla := s_ala; s_blo := s_alo;
        else
          s_ps := s_ps + v_dur;
        end if;
      end if;
    end loop;

    if v_rule = 'bad' then
      v_ema := null; v_ref := null; v_palt := null;
    else
      s_t := greatest(s_t, ts); s_bla := la; s_blo := lo;
      if v_rule = 'gap' then
        v_gap := v_gap + dt; s_gap := s_gap + dt;
        v_ema := null; v_ref := null; v_palt := null;
      elsif v_rule in ('stop', 'still', 'jump') then
        v_idle := v_idle + greatest(dt, 0);
      elsif v_rule = 'zero' then
        v_dist := v_dist + d; s_km := s_km + d;
      elsif v_rule = 'move' then
        v_dist := v_dist + d; v_move := v_move + dt; s_km := s_km + d; s_mv := s_mv + dt;
        if dq > 0 and (dt < c_max_rel_dt or dq <= c_max_rel * v + c_max_abs) then
          v_max := greatest(v_max, dq); s_max := greatest(s_max, dq);
        end if;
        if dp = 0 and dq = 0 and dt >= c_nodop_max_dt then v_nodop_b := greatest(v_nodop_b, v); end if;
        if alt is not null then
          -- Po resetu se vyhlazování rozbíhá od výšky předchozího bodu (je-li).
          if (v_palt is null or v_ema is null or v_ref is null) and p_alt is not null then
            v_ema := p_alt; v_ref := p_alt; v_palt := p_alt;
          end if;
          if v_palt is null or v_ema is null or v_ref is null then
            v_ema := alt; v_ref := alt; v_palt := alt;
          elsif abs(alt - v_palt) <= c_spike_rel * d * 1000 + c_spike_abs then
            v_ema := v_ema + c_ema * (alt - v_ema); v_palt := alt;
            if v_ema - v_ref >= c_hyst then
              v_gain := v_gain + (v_ema - v_ref); s_gain := s_gain + (v_ema - v_ref); v_ref := v_ema;
            elsif v_ema < v_ref then
              v_ref := v_ema;
            end if;
          end if;
        end if;
      end if;
    end if;

    p_ts := ts; p_la := la; p_lo := lo; p_kmh := kmh; p_alt := alt; v_dseg := 0;
  end loop;

  v_nodop := greatest(v_nodop, v_nodop_b);
  v_gi := round(v_gr + v_gain);
  v_gr := v_gr + v_gain - v_gi;
  if v_n > 0 then
    v_done := v_done || jsonb_build_array(jsonb_build_object(
      'f', round(s_f::numeric, 1), 't', round(s_t::numeric, 1), 'km', round(s_km::numeric, 3),
      'mv', round(s_mv)::int, 'gap', round(s_gap)::int, 'ps', round(s_ps)::int, 'gain', round(s_gain)::int,
      'max', nullif(round(s_max::numeric, 1), 0),
      'a', jsonb_build_array(s_ala, s_alo), 'b', jsonb_build_array(s_bla, s_blo)));
  end if;

  return jsonb_build_object(
    'dist_km', round(v_dist::numeric, 3), 'moving_sec', round(v_move)::int, 'gap_sec', round(v_gap)::int,
    'pause_sec', round(v_pause)::int, 'idle_sec', round(v_idle)::int, 'gain_m', v_gi::int,
    'max_kmh', round(v_max::numeric, 1), 'nodop_max_kmh', round(v_nodop_b::numeric, 1),
    'trims', v_trims, 'stages', v_done,
    'state', jsonb_build_object('legacy', v_legacy, 'ema', v_ema, 'ref', v_ref, 'palt', v_palt,
      'still_from', v_sf, 'still_pt', case when v_sf is not null then jsonb_build_array(v_sla, v_slo) end,
      'has_dop', v_has_dop, 'nodop_max', round(v_nodop::numeric, 1), 'gr', round(v_gr::numeric, 3)));
end;
$$;

-- Dosavadní podpis a klíče (dist_km, moving_sec, idle_sec, gap_sec, gain_m,
-- max_kmh); nikdo z appek ho nevolá. SECURITY DEFINER jen kvůli volání
-- interní _ride_stats_v2 (čistý výpočet, žádná data).
create or replace function public._ride_stats(p_track jsonb)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s jsonb := _ride_stats_v2(p_track, '{"legacy": true}'::jsonb, '[]'::jsonb);
begin
  return jsonb_build_object('dist_km', s->'dist_km', 'moving_sec', s->'moving_sec',
    'idle_sec', s->'idle_sec', 'gap_sec', s->'gap_sec', 'gain_m', s->'gain_m',
    'max_kmh', greatest((s->>'max_kmh')::numeric,
                        case when not (s->'state'->>'has_dop')::boolean
                             then (s->'state'->>'nodop_max')::numeric else 0 end));
end;
$$;

create or replace function public._ride_track_cap(p_track jsonb, p_max integer default 4000)
returns jsonb language plpgsql immutable set search_path = public as $$
declare
  n int; v_len float8; v_d float8; v_acc float8 := 0; i int; v_k int;
  v_ord int[]; v_step float8[]; v_edge boolean[]; v_keep int[] := '{}'; v_kedge boolean[] := '{}';
begin
  if jsonb_typeof(p_track) is distinct from 'array' then return '[]'::jsonb; end if;
  n := jsonb_array_length(p_track);
  if p_max is null or p_max < 2 or n <= p_max then return p_track; end if;
  -- Jeden průchod: krok (rovinná aproximace stačí na rozestup), okraje
  -- časových skoků > 180 s a značky pauzy (kmh < 0) i s předchůdcem.
  with x as materialized (
    select e.ord::int ord, (e.pt->>0)::float8 la, (e.pt->>1)::float8 lo,
           case when jsonb_typeof(e.pt->2) = 'number' then (e.pt->>2)::float8 end ts,
           coalesce((e.pt->>3) like '-%', false) neg
      from jsonb_array_elements(p_track) with ordinality e(pt, ord)
     where jsonb_typeof(e.pt) = 'array'),
  y as (
    select x.ord, x.la - lag(x.la) over w dla, (x.lo - lag(x.lo) over w) * cos(radians(x.la)) dlo,
           lag(x.ord) over w is null or lead(x.ord) over w is null
             or coalesce(x.ts - lag(x.ts) over w > 180, false) or coalesce(lead(x.ts) over w - x.ts > 180, false)
             or x.neg or coalesce(lead(x.neg) over w, false) edge
      from x window w as (order by x.ord)),
  z as (select y.ord, y.edge, coalesce(111.195 * sqrt(y.dla * y.dla + y.dlo * y.dlo), 0) step from y)
  select array_agg(z.ord order by z.ord), array_agg(z.step order by z.ord), array_agg(z.edge order by z.ord), sum(z.step)
    into v_ord, v_step, v_edge, v_len from z;
  n := coalesce(array_length(v_ord, 1), 0);
  if n = 0 then return '[]'::jsonb; end if;
  -- Rozestup 20 m · 2^k: opakované prořídnutí pak bere rovnoměrně každý 2. bod.
  v_d := 0.02 * power(2, greatest(0, ceil(log(2, greatest(v_len / (0.85 * p_max) / 0.02, 1)::numeric))));
  for i in 1..n loop
    v_acc := v_acc + v_step[i];
    if v_edge[i] or v_acc >= v_d then
      v_keep := array_append(v_keep, v_ord[i]); v_kedge := array_append(v_kedge, v_edge[i]); v_acc := 0;
    end if;
  end loop;
  n := array_length(v_keep, 1);
  if n > p_max then                                      -- nouzově každý k-tý, okraje vždy
    v_k := ceil(n::numeric / p_max)::int;
    select array_agg(k.o order by k.i) into v_keep from unnest(v_keep, v_kedge) with ordinality k(o, e, i)
     where (k.i - 1) % v_k = 0 or k.e;
  end if;
  return coalesce((select jsonb_agg(p_track -> (k.o - 1) order by k.o) from unnest(v_keep) k(o)), '[]'::jsonb);
end;
$$;

revoke all on function public._ride_prague_night(double precision, double precision) from public, anon, authenticated;
revoke all on function public._ride_stage_days(jsonb) from public, anon, authenticated;
revoke all on function public._ride_stats_v2(jsonb, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public._ride_prague_night(double precision, double precision) to service_role;
grant execute on function public._ride_stage_days(jsonb) to service_role;
grant execute on function public._ride_stats_v2(jsonb, jsonb, jsonb) to service_role;

notify pgrst, 'reload schema';
