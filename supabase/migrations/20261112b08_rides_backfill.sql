-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — „Moje jízdy": přepočet starých jízd (8/8)
-- Požadavek majitele 2026-10-22 (pauza, vícedenní cesta, rozumné statistiky);
-- 2026-10-30 majitel rozhodl, že přepočet historie je součástí nasazení
-- (rozumné statistiky i u starých jízd; návrat jedním příkazem níže).
-- Uzavřené jízdy ze starých appek (pause_aware = false, stats_state IS NULL):
-- noci a dlouhá stání v uložené stopě se z „Celkového času" a „Stání"
-- přesunou do pause_sec — stejné pravidlo jako u 4.1.3 po nasazení
-- (běh stání ≥ 5 min = pauza). duration_min pak = na cestě BEZ pauz,
-- idle_sec = zbytek. Kilometry, čas jízdy, maximum ani nastoupáno se
-- NEMĚNÍ; nic se nemaže.
--   • běh stání: souvislá řada úseků, které staré statistiky počítaly jako
--     „stání" (posun < 3 km/h, i ticho bez posunu > 300 m), dlouhá ≥ 5 min
--     → pauza (noc s telefonem, který dál posílal body, i noc bez bodů);
--   • ticho, které bylo „bez signálu" (posun > 300 m, ale < 15 km/h):
--     pauza (a z mezer pryč), když < 3 km/h nebo stopa nikdy nebyla
--     prořídnutá (< 2000 bodů) — jinak nejde odlišit od prořídnutí;
--   • ticho ≥ 24 h (staré statistiky ho nepočítaly nikam) bez projetí: pauza;
--   • čas po posledním bodu (pozdní Stop — stará finish_user_ride končila
--     vlastní jízdu v now(), výpůjčku vrácením): co přesáhne 2 min po
--     posledním bodu (pravidlo nových jízd), je při ≥ 5 min pauza; ended_at
--     se nemění. Hodiny telefonu pozadu ocas nezvětší (nejvýš start → konec
--     minus rozpětí časů bodů);
--   • pauza nikdy nepřesáhne čas, který nepokrývá jízda a mezery.
-- Známá mez: noc, kterou staré statistiky započítaly jako JÍZDU (bloudění
-- polohy v budově ≥ 3 km/h), zůstane v čase jízdy — bez přepočtu km to nejde.
-- Po přepočtu má jízda stats_state → appka i Velín ukážou nové popisky
-- (_ride_json.stats_v2). Jízdy uzavřené později bez nové dávky (stats_state
-- NULL) zůstávají se starými čísly i popisky.
-- Idempotentní: zpracovaná jízda dostane stats_state = {"backfill":1,
-- "old":{duration_min, idle_sec, gap_sec}} — původní hodnoty pro návrat:
--   update public.user_rides set duration_min = (stats_state->'old'->>'duration_min')::int,
--     idle_sec = (stats_state->'old'->>'idle_sec')::int, gap_sec = (stats_state->'old'->>'gap_sec')::int,
--     pause_sec = 0, stats_state = null where stats_state ? 'backfill';
-- Ohraničená práce (velikost user_rides na živé DB neznáme): jízdy se
-- zpracují po dávkách 200 (podle id), nejdéle ~45 s; řádky, které právě
-- drží jiná transakce, se přeskočí (SKIP LOCKED). Co se nestihne, ohlásí
-- WARNING s počtem — dokončí se ručním během deploy-sql.yml (only =
-- 20261112b08, force = true); opakovaný běh zpracuje jen zbytek.
-- Vadná jízda (nečekaný tvar stopy) neshodí nasazení: dávka se zopakuje po
-- jedné jízdě, vadná zůstane se starými čísly a ohlásí se WARNING.
-- Záměrně se nemění: distance_km, moving_sec, max/avg rychlost, nastoupáno,
-- stopa, body, jízdy otevřené nebo vedené novou appkou.
-- ════════════════════════════════════════════════════════════════════

-- Dočasná funkce (pg_temp — zanikne s koncem spojení, v DB nic nezůstane):
-- přepočet jedné dávky jízd, vrací počet upravených.
create or replace function pg_temp._ride_backfill_batch(p_ids uuid[])
returns integer language plpgsql as $fn$
declare v_n int;
begin
  with cand as (
    select r.id, r.track, r.started_at, r.ended_at, r.moving_sec, r.gap_sec,
           jsonb_array_length(r.track) as n
      from public.user_rides r
     where not r.is_recording and not r.pause_aware and r.stats_state is null
       and r.ended_at is not null and jsonb_typeof(r.track) = 'array'
       and r.id = any(p_ids)
       for update of r skip locked
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
  tl as (
    -- ocas po posledním bodu nad 2 min (pozdní Stop); least(): hodiny telefonu pozadu ho nezvětší
    select c.id, least(extract(epoch from c.ended_at)::float8 - max(p.ts),
                       extract(epoch from (c.ended_at - c.started_at))::float8 - (max(p.ts) - min(p.ts))) - 120 as tail
      from cand c join pts p on p.id = c.id
     group by c.id, c.ended_at, c.started_at
  ),
  pairs as (
    select id, ord, ts - lag(ts) over w as dt,
           case when lag(la) over w is null then null
                else 6371 * 2 * asin(least(1::float8, sqrt(power(sin(radians(la - lag(la) over w) / 2), 2)
                       + cos(radians(lag(la) over w)) * cos(radians(la))
                         * power(sin(radians(lo - lag(lo) over w) / 2), 2)))) end as d
      from pts window w as (partition by id order by ord)
  ),
  cls as (
    -- still = úsek, který staré statistiky počítaly jako „stání" (ne jízda, ne mezera, ne vadný čas)
    select p.*, p.d / nullif(p.dt, 0) * 3600 as v,
           p.dt >= 0 and p.dt < 86400 and not (p.dt > 180 and p.d > 0.3)
             and not coalesce(p.d / nullif(p.dt, 0) * 3600 >= 3 and p.d / nullif(p.dt, 0) * 3600 < 300, false) as still
      from pairs p where p.dt is not null
  ),
  runs as (
    select c.*, sum(case when c.still then 0 else 1 end) over (partition by c.id order by c.ord) as run
      from cls c
  ),
  still_runs as (
    select id, sum(dt) as dur from runs where still group by id, run having sum(dt) >= 300
  ),
  run_sum as (
    select id, sum(dur) as dur from still_runs group by id
  ),
  agg as (
    select c.id, c.moving_sec, c.gap_sec,
           extract(epoch from (c.ended_at - c.started_at))::float8 as elapsed,
           coalesce(max(rs.dur), 0)
           + coalesce(sum(p.dt) filter (where p.dt >= 300 and p.dt < 86400 and p.d > 0.3 and p.v < 15
                 and (p.v < 3 or c.n < 2000)), 0)
           + coalesce(sum(p.dt) filter (where p.dt >= 86400 and p.dt < 2592000
                 and not (p.v >= 15 and p.d > 0.3)), 0) as pause_raw,
           coalesce(sum(p.dt) filter (where p.dt >= 300 and p.dt < 86400 and p.d > 0.3 and p.v < 15
                 and (p.v < 3 or c.n < 2000)), 0) as gap_moved
      from cand c left join cls p on p.id = c.id left join run_sum rs on rs.id = c.id
     group by c.id, c.moving_sec, c.gap_sec, c.ended_at, c.started_at
  ),
  calc as (
    select a.id, a.moving_sec, a.elapsed,
           a.pause_raw + coalesce(case when t.tail >= 300 then t.tail end, 0) as pause_raw,
           greatest(0, a.gap_sec - round(a.gap_moved)::int) as gap_new
      from agg a left join tl t on t.id = a.id
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
  get diagnostics v_n = row_count;
  return v_n;
end;
$fn$;

do $$
declare
  v_t0 timestamptz := clock_timestamp();
  v_ids uuid[]; v_last uuid := '00000000-0000-0000-0000-000000000000';
  v_one uuid; v_done int := 0; v_try int := 0; v_fail int := 0; v_left int; v_err text;
begin
  loop
    select array_agg(s.id order by s.id) into v_ids
      from (select r.id from public.user_rides r
             where r.id > v_last and not r.is_recording and not r.pause_aware
               and r.stats_state is null and r.ended_at is not null
             order by r.id limit 200) s;
    exit when v_ids is null;
    v_last := v_ids[array_length(v_ids, 1)];
    v_try := v_try + array_length(v_ids, 1);
    begin
      v_done := v_done + pg_temp._ride_backfill_batch(v_ids);
    exception when others then
      -- vadná jízda v dávce → po jedné; vadná zůstane beze změny
      foreach v_one in array v_ids loop
        begin
          v_done := v_done + pg_temp._ride_backfill_batch(array[v_one]);
        exception when others then
          get stacked diagnostics v_err = message_text;
          v_fail := v_fail + 1;
          raise warning 'přepočet jízd: jízda % přeskočena (%)', v_one, v_err;
        end;
      end loop;
    end;
    exit when clock_timestamp() - v_t0 > interval '45 seconds';
  end loop;
  -- Selhaly všechny zkoušené jízdy (a ne jen pár) → chyba programu, ne dat.
  if v_fail > 10 and v_fail = v_try then
    raise exception 'přepočet jízd: selhalo všech % jízd (%)', v_fail, v_err;
  end if;
  select count(*) into v_left from public.user_rides r
   where not r.is_recording and not r.pause_aware and r.stats_state is null
     and r.ended_at is not null and jsonb_typeof(r.track) = 'array';
  raise notice 'přepočet jízd: upraveno %, přeskočeno vadných %, zbývá % (% s)',
    v_done, v_fail, v_left, round(extract(epoch from clock_timestamp() - v_t0)::numeric, 1);
  if v_left > v_fail then
    raise warning 'přepočet jízd: nestihl se celý (zbývá % jízd) — spusť deploy-sql.yml ručně (only = 20261112b08, force = true)', v_left;
  end if;
end $$;

drop function if exists pg_temp._ride_backfill_batch(uuid[]);

notify pgrst, 'reload schema';
