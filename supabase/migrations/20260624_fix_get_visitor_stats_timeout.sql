-- 20260624_fix_get_visitor_stats_timeout.sql
-- =============================================================================
-- FIX: Velín → Analýza → Návštěvnost padá na
--      "canceling statement due to statement timeout".
--
-- Root cause: RPC get_visitor_stats agregovala nad rostoucí tabulkou visitor_log
--   (insert-only log z motogo-web-php/visitor_traffic.php) a byla zabíjena
--   statement_timeoutem role `authenticated` (Supabase default ~8 s), který je
--   kratší než frontend watchdog (20 s, Navstevnost.jsx). CTE `base` navíc
--   tahala `select *` — i široké nepoužité sloupce (user_agent, ip_hash,
--   lang, utm_*) → zbytečně velká materializace pro 9 agregačních průchodů.
--
-- Oprava:
--   1) Index (host, ts) pro drill-down dle domény.
--   2) SET statement_timeout = '20s' na funkci (přebije limit role, zarovnáno
--      s frontend watchdogem) + CTE čte jen 9 reálně použitých sloupců.
--   Výstupní JSON je 1:1 stejný — žádná změna sémantiky ani signatury.
--
-- APLIKOVÁNO + OVĚŘENO uživatelem v Supabase (2026-06-24).
-- =============================================================================

-- 1) Index pro filtr dle domény + času
CREATE INDEX IF NOT EXISTS idx_visitor_log_host_ts
  ON public.visitor_log (host, "ts" DESC);

-- 2) Optimalizovaná funkce (vyšší timeout + štíhlejší CTE)
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
           path, referrer, device, country
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
        from base group by 1 order by 1) t)
  ) into v_result;

  return v_result;
end;
$$;
