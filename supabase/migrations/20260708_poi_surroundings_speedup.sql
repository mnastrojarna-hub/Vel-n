-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — Zrychlení cronu popisu okolí (backfill-poi-surroundings)
--
-- Původní `20260707_poi_surroundings_cron.sql` volal edge fn s malou dávkou
-- (limit 8, concurrency 2) každou minutu → ~8 bodů/min = katalog (37 tis.)
-- na ~3 dny. Edge fn nově umí běžet s časovým rozpočtem (jeden běh zpracuje
-- víc dávek po sobě) a s vyšší souběžností + retry na 429. Přeplánujeme cron
-- na **každé 4 min** (interval > rozpočet 220 s → běhy se NEPŘEKRÝVAJÍ, žádná
-- dvojitá práce) a pošleme větší dávku. Pořadí ponecháno: katalog first.
-- Idempotentní; jen přepíše trigger fn a přeplánuje job.
-- ════════════════════════════════════════════════════════════════════

create or replace function public.trigger_poi_surroundings_backfill()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text;
  v_key text;
  v_missing int;
begin
  select
    (select count(*) from public.points_of_interest where surroundings is null and is_active = true)
  + (select count(*) from public.route_pois where surroundings is null)
  into v_missing;

  if coalesce(v_missing, 0) = 0 then
    begin
      perform cron.unschedule('backfill-poi-surroundings');
    exception when others then null;
    end;
    return;
  end if;

  select value #>> '{}' into v_url from public.app_settings where key = 'supabase_url';
  select value #>> '{}' into v_key from public.app_settings where key = 'service_role_key';
  if v_url is null or v_url = '' or v_key is null or v_key = '' then
    raise warning 'trigger_poi_surroundings_backfill: app_settings supabase_url/service_role_key chybí';
    return;
  end if;

  -- Edge fn odpoví hned 202 a poběží na pozadí (EdgeRuntime.waitUntil) až
  -- budget_ms; větší limit = víc řádků na dávku uvnitř smyčky, vyšší souběžnost.
  perform net.http_post(
    url := v_url || '/functions/v1/backfill-poi-surroundings',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_key
    ),
    body := jsonb_build_object('scope', 'all', 'limit', 16, 'concurrency', 6, 'budget_ms', 220000)
  );
end $$;

grant execute on function public.trigger_poi_surroundings_backfill() to service_role;

-- Přeplánuj cron na každé 4 minuty (interval > budget 220 s = bez překryvu).
do $$
begin
  begin
    perform cron.unschedule('backfill-poi-surroundings');
  exception when others then null;
  end;
  perform cron.schedule(
    'backfill-poi-surroundings',
    '*/4 * * * *',
    $cron$ select public.trigger_poi_surroundings_backfill(); $cron$
  );
exception when others then
  raise warning 'cron.schedule selhalo (pg_cron nedostupné?): %', sqlerrm;
end $$;
