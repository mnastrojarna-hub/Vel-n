-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — Automatický dávkový překlad tras a bodů zájmu (cron → edge)
--
-- Přeloží name+description VŠECH routes i route_pois do všech jazyků přes
-- edge funkci `backfill-route-translations` (ta volá `translate-content`).
-- Běží samo: cron každou minutu spustí jednu dávku; když už nic nechybí,
-- job se sám odplánuje. Klíč + URL se čtou z `app_settings` — stejný
-- ověřený vzor jako `send_push_via_edge` (net.http_post).
-- Idempotentní: opětovné nasazení jen přepíše funkci a přeplánuje job.
-- ════════════════════════════════════════════════════════════════════

create or replace function public.trigger_route_translation_backfill()
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
  -- Kolik řádků ještě nemá překlad (proxy: chybí anglický název).
  select
    (select count(*) from public.routes     where translations->'en'->>'name' is null)
  + (select count(*) from public.route_pois where translations->'en'->>'name' is null)
  into v_missing;

  -- Hotovo → odplánuj sebe sama a skonči.
  if coalesce(v_missing, 0) = 0 then
    begin
      perform cron.unschedule('backfill-route-translations');
    exception when others then null; -- job už neexistuje
    end;
    return;
  end if;

  select value #>> '{}' into v_url from public.app_settings where key = 'supabase_url';
  select value #>> '{}' into v_key from public.app_settings where key = 'service_role_key';
  if v_url is null or v_url = '' or v_key is null or v_key = '' then
    raise warning 'trigger_route_translation_backfill: app_settings supabase_url/service_role_key chybí';
    return;
  end if;

  -- Spusť jednu dávku (edge fn si sama vybere řádky bez překladu).
  perform net.http_post(
    url := v_url || '/functions/v1/backfill-route-translations',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_key
    ),
    body := jsonb_build_object('scope', 'all', 'limit', 12, 'concurrency', 3)
  );
end $$;

grant execute on function public.trigger_route_translation_backfill() to service_role;

-- Naplánuj cron (každou minutu). Nejdřív zruš případný starý job.
do $$
begin
  begin
    perform cron.unschedule('backfill-route-translations');
  exception when others then null;
  end;
  perform cron.schedule(
    'backfill-route-translations',
    '* * * * *',
    $cron$ select public.trigger_route_translation_backfill(); $cron$
  );
exception when others then
  raise warning 'cron.schedule selhalo (pg_cron nedostupné?): %', sqlerrm;
end $$;
