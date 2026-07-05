-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — Cron pro AI generaci popisu okolí bodů zájmu (backend-only)
--
-- Každou minutu spustí jednu dávku edge fn `backfill-poi-surroundings`, která
-- vygeneruje KONKRÉTNÍ `surroundings` (a případně doplní `description`) u
-- katalogových `points_of_interest` i bodů na trase `route_pois` a hned to
-- přeloží do všech jazyků. Když už žádný bod nechybí, job se sám odplánuje.
-- Klíč + URL z `app_settings` (stejný vzor jako backfill-route-translations).
-- Idempotentní — opětovné nasazení jen přepíše funkci a přeplánuje job.
-- BEZ lokálního spouštění: vše běží na backendu přes pg_cron + pg_net.
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

  perform net.http_post(
    url := v_url || '/functions/v1/backfill-poi-surroundings',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_key
    ),
    body := jsonb_build_object('scope', 'all', 'limit', 8, 'concurrency', 2)
  );
end $$;

grant execute on function public.trigger_poi_surroundings_backfill() to service_role;

-- Naplánuj cron (každou minutu). Nejdřív zruš případný starý job.
do $$
begin
  begin
    perform cron.unschedule('backfill-poi-surroundings');
  exception when others then null;
  end;
  perform cron.schedule(
    'backfill-poi-surroundings',
    '* * * * *',
    $cron$ select public.trigger_poi_surroundings_backfill(); $cron$
  );
exception when others then
  raise warning 'cron.schedule selhalo (pg_cron nedostupné?): %', sqlerrm;
end $$;
