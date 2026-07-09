-- 20260709_visitor_stats_hourly_dow.sql
-- =============================================================================
-- FEATURE: Velín → Analýza → Návštěvnost — vytíženost webu po HODINÁCH a DNECH
--          v týdnu (napříč všemi dny zvoleného rozsahu).
--
-- Cíl: vidět, KDY chodí na web nejvíc lidí — v jakou hodinu (napříč všemi dny),
--      v jaký den v týdnu (po–ne) a heatmapu den×hodina (např. „neděle ve 20 h").
--
-- Řešení: rozšíření existující RPC `get_visitor_stats` o 3 nové agregáty:
--   - `by_hour`     : [{hour 0–23, views, visitors}]  — napříč všemi dny
--   - `by_dow`      : [{dow 1–7 (po–ne), views, visitors}]
--   - `by_dow_hour` : [{dow 1–7, hour 0–23, views}]   — heatmapa den × hodina
--
-- Hodina i den se počítají v LOKÁLNÍM čase Europe/Prague (`ts AT TIME ZONE …`),
-- aby „hodina" odpovídala nástěnným hodinám návštěvníka, ne UTC. DOW je
-- přemapován z Postgres ISODOW (1=Po … 7=Ne) pro přímé české řazení po–ne.
--
-- Výstupní JSON je zpětně kompatibilní — jen PŘIBYLY klíče, nic se nemění.
-- Signatura, timeout (20s) i security beze změny.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_visitor_stats(
  p_from timestamptz,
  p_to   timestamptz,
  p_host text DEFAULT NULL,
  p_granularity text DEFAULT 'day'
) RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  SET statement_timeout TO '20s'
AS $$
declare
  v_result jsonb;
  v_trunc  text;
  v_tz     constant text := 'Europe/Prague';
begin
  if not is_admin() then
    raise exception 'Access denied';
  end if;

  v_trunc := case lower(coalesce(p_granularity, 'day'))
    when 'week'  then 'week'
    when 'month' then 'month'
    when 'year'  then 'year'
    else 'day'
  end;

  with base as (
    -- jen sloupce, které agregace níže reálně potřebují (ne select *)
    select ts, host, visitor_hash, referrer_type, referrer_domain,
           path, referrer, device, country,
           -- lokální (Europe/Prague) hodina 0–23 a den v týdnu 1=Po … 7=Ne
           extract(hour  from ts at time zone v_tz)::int  as loc_hour,
           extract(isodow from ts at time zone v_tz)::int as loc_dow
    from visitor_log
    where ts >= p_from and ts < p_to
      and (p_host is null or host = p_host)
  )
  select jsonb_build_object(
    'total_views',     (select count(*) from base),
    'unique_visitors', (select count(distinct visitor_hash) from base),

    'by_host', (select coalesce(jsonb_object_agg(h, c), '{}'::jsonb) from (
        select coalesce(nullif(host, ''), '(neznámá)') h, count(*) c
        from base group by 1 order by c desc limit 50) t),

    'by_referrer_type', (select coalesce(jsonb_object_agg(rt, c), '{}'::jsonb) from (
        select coalesce(nullif(referrer_type, ''), 'direct') rt, count(*) c
        from base group by 1) t),

    'by_referrer_domain', (select coalesce(jsonb_agg(jsonb_build_object('name', d, 'count', c) order by c desc), '[]'::jsonb) from (
        select coalesce(nullif(referrer_domain, ''), '(přímý vstup)') d, count(*) c
        from base
        where coalesce(referrer_type, 'direct') <> 'internal'
        group by 1 order by c desc limit 30) t),

    'top_paths', (select coalesce(jsonb_agg(jsonb_build_object('path', p, 'count', c) order by c desc), '[]'::jsonb) from (
        select coalesce(path, '/') p, count(*) c
        from base group by 1 order by c desc limit 30) t),

    'top_referrers', (select coalesce(jsonb_agg(jsonb_build_object('referrer', r, 'count', c) order by c desc), '[]'::jsonb) from (
        select referrer r, count(*) c
        from base where referrer is not null and referrer <> ''
        group by 1 order by c desc limit 30) t),

    'by_device', (select coalesce(jsonb_object_agg(dev, c), '{}'::jsonb) from (
        select coalesce(nullif(device, ''), 'unknown') dev, count(*) c
        from base group by 1) t),

    'by_country', (select coalesce(jsonb_agg(jsonb_build_object('name', co, 'count', c) order by c desc), '[]'::jsonb) from (
        select country co, count(*) c
        from base where country is not null and country <> ''
        group by 1 order by c desc limit 30) t),

    'timeline', (select coalesce(jsonb_agg(jsonb_build_object('bucket', b, 'views', v, 'visitors', uv) order by b), '[]'::jsonb) from (
        select date_trunc(v_trunc, ts) b, count(*) v, count(distinct visitor_hash) uv
        from base group by 1 order by 1) t),

    -- NOVÉ: vytíženost po hodinách (napříč všemi dny rozsahu), lokální čas
    'by_hour', (select coalesce(jsonb_agg(jsonb_build_object('hour', h, 'views', v, 'visitors', uv) order by h), '[]'::jsonb) from (
        select loc_hour h, count(*) v, count(distinct visitor_hash) uv
        from base group by 1 order by 1) t),

    -- NOVÉ: vytíženost po dnech v týdnu (1=Po … 7=Ne)
    'by_dow', (select coalesce(jsonb_agg(jsonb_build_object('dow', d, 'views', v, 'visitors', uv) order by d), '[]'::jsonb) from (
        select loc_dow d, count(*) v, count(distinct visitor_hash) uv
        from base group by 1 order by 1) t),

    -- NOVÉ: heatmapa den × hodina (jen buňky s daty; nuly dopočte frontend)
    'by_dow_hour', (select coalesce(jsonb_agg(jsonb_build_object('dow', d, 'hour', h, 'views', v) order by d, h), '[]'::jsonb) from (
        select loc_dow d, loc_hour h, count(*) v
        from base group by 1, 2 order by 1, 2) t)
  ) into v_result;

  return v_result;
end;
$$;
