-- ════════════════════════════════════════════════════════════════════════
--  Přečíslování sort_order VŠECH bodů zájmu (route_pois) podle pořadí na trase
--  ─────────────────────────────────────────────────────────────────────────
--  Problém (hlášeno uživatelem): body zájmu 1–x jsou na mapě „na přeskáčku",
--  nejdou po směru trasy. Appka čísluje markery i+1 dle pořadí, v jakém body
--  vrací RPC get_branch_routes → to řadí `order by p.sort_order`. Když sort_order
--  neodpovídá směru jízdy, markery vypadají chaoticky.
--
--  Řešení: pro každou trasu s použitelnou čárou (waypoints ≥ 2 body) promítni
--  každý bod zájmu na čáru trasy (nejbližší segment) a přečísluj sort_order
--  (0-based) podle vzdálenosti podél čáry. Tím jdou markery 1,2,3,… po směru jízdy.
--
--  Projekce je stejná ekvirektangulární matematika jako v tools/fill_route_poi_gaps.py
--  (project()), jen provedená celá v DB (živá DB je ze sandboxu nedosažitelná).
--  Idempotentní: opakované spuštění nic nezmění (guard sort_order is distinct from).
--  Trasy bez použitelných waypointů zůstanou nedotčené.
-- ════════════════════════════════════════════════════════════════════════

begin;

-- Pomocná funkce: pozice bodu (lat,lng) podél čáry `wps` (jsonb [{lat,lng,…}]).
-- Vrací vzdálenost podél čáry v km k patě kolmice na NEJBLIŽŠÍ segment,
-- nebo NULL, pokud čára nemá ani jeden platný segment.
create or replace function public._poi_route_pos(
  p_lat double precision, p_lng double precision, wps jsonb
) returns double precision
language plpgsql immutable as $fn$
declare
  m        int;
  i        int;
  alat     double precision; alng double precision;
  blat     double precision; blng double precision;
  ky       double precision := 111.0;
  kx       double precision;
  ax       double precision; ay double precision;
  bx       double precision; byv double precision;
  px       double precision; py double precision;
  dx       double precision; dy double precision;
  l2       double precision; t double precision;
  seglen   double precision;
  projx    double precision; projy double precision;
  d        double precision;
  cum      double precision := 0;      -- kumulativní délka k začátku segmentu (a)
  best_d   double precision;
  best_pos double precision;
  found    boolean := false;
begin
  if p_lat is null or p_lng is null
     or wps is null or jsonb_typeof(wps) <> 'array' then
    return null;
  end if;
  m := jsonb_array_length(wps);
  if m < 2 then
    return null;
  end if;

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
    dx := bx-ax;   dy := byv-ay;
    l2 := dx*dx + dy*dy;
    seglen := sqrt(l2);

    if l2 = 0 then
      t := 0;
    else
      t := ((px-ax)*dx + (py-ay)*dy) / l2;
      if t < 0 then t := 0; elsif t > 1 then t := 1; end if;
    end if;

    projx := ax + t*dx;  projy := ay + t*dy;
    d := sqrt((px-projx)*(px-projx) + (py-projy)*(py-projy));

    if not found or d < best_d then
      best_d   := d;
      best_pos := cum + t*seglen;
      found    := true;
    end if;

    cum := cum + seglen;
  end loop;

  if not found then
    return null;
  end if;
  return best_pos;
end
$fn$;

-- Přečíslování sort_order (0-based) dle pozice na trase.
-- Bere jen trasy, kde má alespoň 2 body platnou pozici na čáře (jinak by pořadí
-- nedávalo smysl a hrozilo by náhodné promíchání). Body bez souřadnic (pos NULL)
-- se řadí až za pozicované.
with pos as (
  select rp.id,
         rp.route_id,
         rp.sort_order as old_order,
         public._poi_route_pos(rp.lat, rp.lng, r.waypoints) as pos
  from public.route_pois rp
  join public.routes r on r.id = rp.route_id
  where jsonb_typeof(r.waypoints) = 'array'
    and jsonb_array_length(r.waypoints) >= 2
),
ranked as (
  select id, route_id, old_order,
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

-- Pomocná funkce už není potřeba.
drop function if exists public._poi_route_pos(double precision, double precision, jsonb);

-- Geometry cache není potřeba nulovat: čára (waypoints) se nemění, mění se jen
-- pořadí markerů (sort_order). Appka i tak čte body přes RPC seřazené sort_order.

commit;
