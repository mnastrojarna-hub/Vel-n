-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — „Moje jízdy": přepočet starých jízd (8/8) — VOLITELNÉ (majitel)
-- Uzavřené jízdy ze starých appek (pause_aware = false, stats_state IS NULL):
-- noci a dlouhá stání v uložené stopě (ticho ≥ 5 min bez projetí ≥ 15 km/h)
-- se z „Celkového času" a „Stání" přesunou do pause_sec. duration_min pak
-- = na cestě BEZ pauz, idle_sec = zbytek. Kilometry, čas jízdy, maximum
-- ani nastoupáno se NEMĚNÍ; nic se nemaže.
--   • ticho, které staré statistiky braly jako „stání" (posun < 3 km/h):
--     vždy pauza;
--   • ticho, které bylo „bez signálu" (posun > 300 m, ale < 15 km/h):
--     pauza jen u stopy, která nikdy nebyla prořídnutá (< 2000 bodů) —
--     u prořídnuté stopy nejde odlišit od mezery vzniklé prořídnutím;
--   • pauza nikdy nepřesáhne čas, který nepokrývá jízda a mezery.
-- Idempotentní: zpracovaná jízda dostane stats_state = {"backfill":1,
-- "old":{duration_min, idle_sec, gap_sec}} — původní hodnoty pro návrat:
--   update public.user_rides set duration_min = (stats_state->'old'->>'duration_min')::int,
--     idle_sec = (stats_state->'old'->>'idle_sec')::int, gap_sec = (stats_state->'old'->>'gap_sec')::int,
--     pause_sec = 0, stats_state = null where stats_state ? 'backfill';
-- ════════════════════════════════════════════════════════════════════

with cand as (
  select r.id, r.track, r.started_at, r.ended_at, r.moving_sec, r.gap_sec,
         jsonb_array_length(r.track) as n
    from public.user_rides r
   where not r.is_recording and not r.pause_aware and r.stats_state is null
     and r.ended_at is not null and jsonb_typeof(r.track) = 'array'
),
pts as (
  select c.id, e.ord, (e.pt->>0)::float8 as la, (e.pt->>1)::float8 as lo, (e.pt->>2)::float8 as ts
    from cand c
    cross join lateral jsonb_array_elements(c.track) with ordinality e(pt, ord)
   where case when jsonb_typeof(e.pt) <> 'array' then false
              when jsonb_array_length(e.pt) < 3 then false
              when jsonb_typeof(e.pt->0) <> 'number' or jsonb_typeof(e.pt->1) <> 'number' then false
              else (e.pt->>2) ~ '^[0-9]+(\.[0-9]+)?$' end
),
pairs as (
  select id, ts - lag(ts) over w as dt,
         case when lag(la) over w is null then null
              else 6371 * 2 * asin(least(1::float8, sqrt(power(sin(radians(la - lag(la) over w) / 2), 2)
                     + cos(radians(lag(la) over w)) * cos(radians(la))
                       * power(sin(radians(lo - lag(lo) over w) / 2), 2)))) end as d
    from pts window w as (partition by id order by ord)
),
agg as (
  select c.id, c.moving_sec, c.gap_sec,
         extract(epoch from (c.ended_at - c.started_at))::float8 as elapsed,
         coalesce(sum(p.dt) filter (where p.dt >= 300 and p.dt < 2592000
               and not (p.d / nullif(p.dt, 0) * 3600 >= 15 and p.d > 0.3)
               and (p.dt >= 86400 or p.d / nullif(p.dt, 0) * 3600 < 3 or (p.d > 0.3 and c.n < 2000))), 0) as pause_raw,
         coalesce(sum(p.dt) filter (where p.dt >= 300 and p.dt < 86400
               and not (p.d / nullif(p.dt, 0) * 3600 >= 15) and p.d > 0.3 and c.n < 2000), 0) as gap_moved
    from cand c left join pairs p on p.id = c.id and p.dt is not null
   group by c.id, c.moving_sec, c.gap_sec, c.ended_at, c.started_at
),
calc as (
  select a.id, a.moving_sec, a.elapsed, a.pause_raw,
         greatest(0, a.gap_sec - round(a.gap_moved)::int) as gap_new
    from agg a
),
fin as (
  select c.*, least(c.pause_raw, greatest(0, c.elapsed - c.moving_sec - c.gap_new)) as pause
    from calc c
)
update public.user_rides r set
  pause_sec = case when f.pause > 0 then round(f.pause)::int else r.pause_sec end,
  gap_sec = case when f.pause > 0 then f.gap_new else r.gap_sec end,
  idle_sec = case when f.pause > 0
                  then greatest(0, round(greatest(60, f.elapsed - f.pause) - r.moving_sec - f.gap_new))::int
                  else r.idle_sec end,
  duration_min = case when f.pause > 0 then greatest(1, round(greatest(60, f.elapsed - f.pause) / 60))::int
                      else r.duration_min end,
  stats_state = jsonb_build_object('backfill', 1, 'old', jsonb_build_object(
    'duration_min', r.duration_min, 'idle_sec', r.idle_sec, 'gap_sec', r.gap_sec))
from fin f
where r.id = f.id;

notify pgrst, 'reload schema';
