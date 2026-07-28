-- ════════════════════════════════════════════════════════════════════════
--  SYSTEMATIZACE POŘADÍ WAYPOINTŮ VŠECH TRAS (2026-07-28)
--  ─────────────────────────────────────────────────────────────────────────
--  Problém (hlášeno uživatelem, foto z appky): trasy navádějí nesystematicky —
--  čára trasy se vrací tam a zpátky, kličkuje v kruzích a body zájmu na mapě
--  nejdou očíslované za sebou. Dřívější oprava 20260707 přečíslovala jen
--  sort_order bodů PODLE stávající čáry — ale když samotné pořadí waypointů
--  (z něhož se počítá čára přes Mapy routing) kličkuje, problém zůstal.
--  Analýza repliky DB: 683 z 1374 tras má neoptimální pořadí waypointů,
--  401 tras kličkuje výrazně (>3 % a >3 km navíc; nejhorší o 123 km).
--
--  Řešení: pro každou trasu se přeuspořádají waypointy tak, aby na sebe body
--  navazovaly nejkratší cestou (žádné vracení):
--   • start (1. bod) zůstává VŽDY pevný;
--   • konec zůstává pevný u okruhů (první≈poslední < 1 km) a u tras,
--     jejichž poslední bod má label „Cíl…"; jinak je konec volný;
--   • pořadí prostředních bodů řeší EXAKTNĚ Held-Karp DP (≤13 volných bodů,
--     pokrývá ~99 % tras), pro větší trasy nearest-neighbor + 2-opt + relokace;
--   • nové pořadí se použije jen při zkrácení čáry o > 0.2 km (idempotence);
--   • u změněných tras: mapy_url přegenerován, geometry = null (cache čáry
--     se dopočte živě), distance_km/duration_min přepočteny odhadem
--     (délka čáry × 1.35, ~42 km/h) při odchylce > 15 % — stejné konvence
--     jako 20260704_routes_fix_waypoints_pois.sql.
--  Nakonec se sort_order VŠECH route_pois přečísluje projekcí na (novou)
--  čáru trasy — stejná mechanika jako 20260707_route_pois_reorder_along_route.
--  Komunitní trasy (created_by is not null) se NEMĚNÍ — pořadí jejich bodů
--  je autorovo. Idempotentní: opakované spuštění nic nezmění.
-- ════════════════════════════════════════════════════════════════════════

begin;

-- ── Pomocná funkce: délka čáry v km podle pořadí `o` nad maticí vzdáleností ──
create or replace function public._wp_plen(o int[], d double precision[], n int)
returns double precision language plpgsql immutable as $fn$
declare s double precision := 0; i int;
begin
  for i in 1..(array_length(o,1)-1) loop
    s := s + d[(o[i]-1)*n + o[i+1]];
  end loop;
  return s;
end $fn$;

-- ── Pomocná funkce: optimální pořadí waypointů trasy ─────────────────────
-- Vrací o = nové pořadí (1-based indexy do původního pole) a lnew = novou
-- délku čáry v km; o je NULL, pokud není co měnit (zlepšení ≤ 0.2 km,
-- málo bodů, chybějící souřadnice).
create or replace function public._wp_optimal_order(wps jsonb)
returns table(o int[], lnew double precision)
language plpgsql immutable as $fn$
declare
  n int; m int; i int; j int; k int;
  la double precision[]; lo double precision[];
  xs double precision[]; ys double precision[];
  clat double precision := 0; kx double precision;
  d double precision[];
  closed boolean; fixed_end boolean; ll text;
  mids int[]; ord int[]; cur int[];
  fullm int; mask int; nm int; idx int;
  dp double precision[]; par int[];
  base double precision; cand double precision;
  best double precision; besti int;
  lold double precision; l double precision; lbest double precision;
  freep int[]; seq int[]; tmp int[]; chunk int;
  improved boolean; qmax int;
begin
  o := null; lnew := null;
  if wps is null or jsonb_typeof(wps) <> 'array' then return next; return; end if;
  n := jsonb_array_length(wps);
  if n < 4 then return next; return; end if;

  la := array[]::double precision[]; lo := array[]::double precision[];
  for i in 1..n loop
    if (wps->(i-1)->>'lat') is null or (wps->(i-1)->>'lng') is null then
      return next; return;
    end if;
    la := la || (wps->(i-1)->>'lat')::double precision;
    lo := lo || (wps->(i-1)->>'lng')::double precision;
    clat := clat + la[i];
  end loop;
  clat := clat / n;

  -- ekvirektangulární projekce do km (dostatečná pro rozsah jedné trasy)
  kx := 111.0 * cos(radians(clat));
  xs := array[]::double precision[]; ys := array[]::double precision[];
  for i in 1..n loop
    xs := xs || lo[i]*kx; ys := ys || la[i]*111.0;
  end loop;

  -- matice vzdáleností n×n (flatten: d[(a-1)*n+b])
  d := array_fill(0::double precision, array[n*n]);
  for i in 1..n loop
    for j in 1..n loop
      d[(i-1)*n + j] := sqrt((xs[i]-xs[j])^2 + (ys[i]-ys[j])^2);
    end loop;
  end loop;

  closed := d[(1-1)*n + n] < 1.0;
  ll := lower(coalesce(wps->(n-1)->>'label',''));
  fixed_end := closed or ll like 'cíl%' or ll like 'cil%';

  -- prostřední (volné) body
  mids := array[]::int[];
  for i in 2..(case when fixed_end then n-1 else n end) loop
    mids := mids || i;
  end loop;
  m := coalesce(array_length(mids,1),0);
  if m < 2 then return next; return; end if;

  -- aktuální pořadí + délka
  cur := array[]::int[];
  for i in 1..n loop cur := cur || i; end loop;
  lold := public._wp_plen(cur, d, n);

  if m <= 13 then
    -- ── EXAKTNĚ: Held-Karp DP přes podmnožiny volných bodů ──
    fullm := (1<<m) - 1;
    dp  := array_fill('infinity'::double precision, array[fullm*m]);
    par := array_fill(0, array[fullm*m]);
    for i in 1..m loop
      mask := 1<<(i-1);
      dp[(mask-1)*m + i] := d[(1-1)*n + mids[i]];
    end loop;
    for mask in 1..fullm loop
      for i in 1..m loop
        if (mask & (1<<(i-1))) = 0 then continue; end if;
        base := dp[(mask-1)*m + i];
        if base = 'infinity'::double precision then continue; end if;
        for j in 1..m loop
          if (mask & (1<<(j-1))) > 0 then continue; end if;
          nm := mask | (1<<(j-1));
          cand := base + d[(mids[i]-1)*n + mids[j]];
          idx := (nm-1)*m + j;
          if cand < dp[idx] then
            dp[idx] := cand; par[idx] := i;
          end if;
        end loop;
      end loop;
    end loop;
    -- nejlepší koncový volný bod
    best := 'infinity'::double precision; besti := 0;
    for i in 1..m loop
      cand := dp[(fullm-1)*m + i]
              + case when fixed_end then d[(mids[i]-1)*n + n] else 0 end;
      if cand < best then best := cand; besti := i; end if;
    end loop;
    -- rekonstrukce posloupnosti (pozpátku)
    seq := array[]::int[]; mask := fullm; i := besti;
    while i > 0 loop
      seq := mids[i] || seq;
      j := par[(mask-1)*m + i];
      mask := mask & ~(1<<(i-1));
      i := j;
    end loop;
    ord := 1 || seq;
    if fixed_end then ord := ord || n; end if;
  else
    -- ── HEURISTIKA pro velké trasy: nearest neighbor + 2-opt + relokace ──
    freep := mids; ord := array[1]; k := 1;
    while coalesce(array_length(freep,1),0) > 0 loop
      besti := 1; best := 'infinity'::double precision;
      for i in 1..array_length(freep,1) loop
        if d[(k-1)*n + freep[i]] < best then
          best := d[(k-1)*n + freep[i]]; besti := i;
        end if;
      end loop;
      k := freep[besti];
      ord := ord || k;
      freep := freep[1:besti-1] || freep[besti+1:array_length(freep,1)];
    end loop;
    if fixed_end then ord := ord || n; end if;

    lbest := public._wp_plen(ord, d, n);
    improved := true;
    while improved loop
      improved := false;
      qmax := array_length(ord,1) - case when fixed_end then 1 else 0 end;
      -- 2-opt: reverze úseku i..j
      for i in 2..qmax-1 loop
        for j in i+1..qmax loop
          tmp := ord[1:i-1];
          for k in reverse j..i loop tmp := tmp || ord[k]; end loop;
          tmp := tmp || ord[j+1:array_length(ord,1)];
          l := public._wp_plen(tmp, d, n);
          if l < lbest - 1e-9 then ord := tmp; lbest := l; improved := true; end if;
        end loop;
      end loop;
      -- relokace jednoho bodu na jinou pozici
      for i in 2..qmax loop
        chunk := ord[i];
        tmp := ord[1:i-1] || ord[i+1:array_length(ord,1)];
        for k in 2..(array_length(tmp,1) + case when fixed_end then 0 else 1 end) loop
          exit when fixed_end and k > array_length(tmp,1);
          seq := tmp[1:k-1] || chunk || tmp[k:array_length(tmp,1)];
          l := public._wp_plen(seq, d, n);
          if l < lbest - 1e-9 then ord := seq; lbest := l; improved := true; exit; end if;
        end loop;
        exit when improved;
      end loop;
    end loop;
  end if;

  lnew := public._wp_plen(ord, d, n);
  -- změna jen při reálném zkrácení (zaručuje idempotenci a nulový churn)
  if lnew >= lold - 0.2 then o := null; lnew := null; end if;
  o := case when lnew is null then null else ord end;
  return next;
end $fn$;

-- ── Aplikace: přeuspořádání waypointů, mapy_url, km/min, reset geometry ──
do $$
declare
  r record; res record;
  newwps jsonb; i int;
  org text; dst text; mids text;
  est double precision;
  n_changed int := 0;
begin
  for r in
    select id, name, waypoints, distance_km, duration_min
    from public.routes
    where created_by is null
      and jsonb_typeof(waypoints) = 'array'
      and jsonb_array_length(waypoints) >= 4
  loop
    select * into res from public._wp_optimal_order(r.waypoints);
    if res.o is null then continue; end if;

    newwps := '[]'::jsonb;
    for i in 1..array_length(res.o,1) loop
      newwps := newwps || jsonb_build_array(r.waypoints->(res.o[i]-1));
    end loop;

    org := (newwps->0->>'lat') || ',' || (newwps->0->>'lng');
    dst := (newwps->(jsonb_array_length(newwps)-1)->>'lat') || ',' ||
           (newwps->(jsonb_array_length(newwps)-1)->>'lng');
    select string_agg((e->>'lat') || ',' || (e->>'lng'), '%7C' order by ordn)
      into mids
      from jsonb_array_elements(newwps) with ordinality t(e, ordn)
      where ordn > 1 and ordn < jsonb_array_length(newwps);

    est := res.lnew * 1.35;

    update public.routes set
      waypoints = newwps,
      geometry  = null,
      mapy_url  = 'https://www.google.com/maps/dir/?api=1&origin=' || org
                  || '&destination=' || dst || '&travelmode=driving'
                  || coalesce('&waypoints=' || mids, ''),
      distance_km = case
        when distance_km is null or distance_km = 0
             or abs(est - distance_km) / distance_km > 0.15
        then round(est::numeric)
        else distance_km end,
      duration_min = case
        when distance_km is null or distance_km = 0
             or abs(est - distance_km) / distance_km > 0.15
        then round((est / 42.0 * 60.0)::numeric)::int
        else duration_min end,
      updated_at = now()
    where id = r.id;

    n_changed := n_changed + 1;
  end loop;
  raise notice 'Systematizace waypointů: přeuspořádáno % tras.', n_changed;
end $$;

drop function if exists public._wp_optimal_order(jsonb);
drop function if exists public._wp_plen(int[], double precision[], int);

-- ── Přečíslování sort_order bodů zájmu podle NOVÉ čáry trasy ─────────────
-- (stejná projekce jako 20260707_route_pois_reorder_along_route.sql)
create or replace function public._poi_route_pos(
  p_lat double precision, p_lng double precision, wps jsonb
) returns double precision
language plpgsql immutable as $fn$
declare
  m int; i int;
  alat double precision; alng double precision;
  blat double precision; blng double precision;
  ky double precision := 111.0; kx double precision;
  ax double precision; ay double precision;
  bx double precision; byv double precision;
  px double precision; py double precision;
  dx double precision; dy double precision;
  l2 double precision; t double precision;
  seglen double precision;
  projx double precision; projy double precision;
  d double precision;
  cum double precision := 0;
  best_d double precision; best_pos double precision;
  found boolean := false;
begin
  if p_lat is null or p_lng is null
     or wps is null or jsonb_typeof(wps) <> 'array' then
    return null;
  end if;
  m := jsonb_array_length(wps);
  if m < 2 then return null; end if;
  for i in 1..(m-1) loop
    alat := (wps->(i-1)->>'lat')::double precision;
    alng := (wps->(i-1)->>'lng')::double precision;
    blat := (wps->i->>'lat')::double precision;
    blng := (wps->i->>'lng')::double precision;
    if alat is null or alng is null or blat is null or blng is null then
      continue;
    end if;
    kx := 111.0 * cos(radians(alat));
    ax := alng*kx; ay := alat*ky;
    bx := blng*kx; byv := blat*ky;
    px := p_lng*kx; py := p_lat*ky;
    dx := bx-ax; dy := byv-ay;
    l2 := dx*dx + dy*dy;
    seglen := sqrt(l2);
    if l2 = 0 then t := 0;
    else
      t := ((px-ax)*dx + (py-ay)*dy) / l2;
      if t < 0 then t := 0; elsif t > 1 then t := 1; end if;
    end if;
    projx := ax + t*dx; projy := ay + t*dy;
    d := sqrt((px-projx)*(px-projx) + (py-projy)*(py-projy));
    if not found or d < best_d then
      best_d := d; best_pos := cum + t*seglen; found := true;
    end if;
    cum := cum + seglen;
  end loop;
  if not found then return null; end if;
  return best_pos;
end $fn$;

with pos as (
  select rp.id, rp.route_id,
         public._poi_route_pos(rp.lat, rp.lng, r.waypoints) as pos
  from public.route_pois rp
  join public.routes r on r.id = rp.route_id
  where jsonb_typeof(r.waypoints) = 'array'
    and jsonb_array_length(r.waypoints) >= 2
),
ranked as (
  select id, route_id,
         row_number() over (
           partition by route_id
           order by (pos is null), pos, id
         ) - 1 as new_order,
         count(pos) over (partition by route_id) as positioned_cnt
  from pos
)
update public.route_pois rp
set sort_order = ranked.new_order,
    updated_at = now()
from ranked
where ranked.id = rp.id
  and ranked.positioned_cnt >= 2
  and rp.sort_order is distinct from ranked.new_order;

drop function if exists public._poi_route_pos(double precision, double precision, jsonb);

commit;
