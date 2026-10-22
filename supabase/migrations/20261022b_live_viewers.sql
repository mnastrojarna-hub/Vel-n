-- =============================================================================
-- 2026-10-22: Počet lidí, kteří si právě prohlížejí web / motorku (sociální důkaz)
-- Zdroj = visitor_log (jen reální lidé, bez botů — viz motogo-web-php/visitor_traffic.php;
-- visitor_hash rotuje denně). ŽÁDNÁ vymyšlená čísla: web zobrazí počet jen, když
-- je skutečně nenulový (bez sebe sama). Agregát bez osobních údajů → anon smí volat.
--   site_now   = různí návštěvníci webu za posledních 10 min
--   moto_hour  = různí návštěvníci detailu motorky (/katalog/<id>, i lokalizované
--                /catalog/<id> …) za poslední hodinu
--   moto_today = totéž od půlnoci (Praha)
-- Index idx_visitor_log_ts (ts DESC) drží dotaz na malém okně řádků.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_live_viewers(p_moto_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public SET statement_timeout = '3s' AS $$
  WITH w AS (
    SELECT visitor_hash, ts, path FROM visitor_log
     WHERE ts > LEAST(now() - interval '1 hour',
                      ((now() AT TIME ZONE 'Europe/Prague')::date)::timestamp AT TIME ZONE 'Europe/Prague')
       AND visitor_hash IS NOT NULL
  )
  SELECT jsonb_build_object(
    'site_now', (SELECT count(DISTINCT visitor_hash) FROM w WHERE ts > now() - interval '10 minutes'),
    'moto_hour', CASE WHEN p_moto_id IS NULL THEN 0 ELSE
      (SELECT count(DISTINCT visitor_hash) FROM w WHERE ts > now() - interval '1 hour' AND right(path, 36) = p_moto_id::text) END,
    'moto_today', CASE WHEN p_moto_id IS NULL THEN 0 ELSE
      (SELECT count(DISTINCT visitor_hash) FROM w
        WHERE ts >= ((now() AT TIME ZONE 'Europe/Prague')::date)::timestamp AT TIME ZONE 'Europe/Prague'
          AND right(path, 36) = p_moto_id::text) END
  );
$$;
REVOKE ALL ON FUNCTION public.get_live_viewers(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_live_viewers(uuid) TO anon, authenticated, service_role;
