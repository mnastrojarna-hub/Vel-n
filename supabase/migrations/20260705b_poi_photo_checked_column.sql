-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — Fix „zaseknutého" backfillu fotek bodů zájmu.
--
-- Původní cron bral `image_url is null` v pevném pořadí (sort_order,id), takže
-- se pořád otíral o VODNÍ BLOK bodů bez dohledatelné fotky na začátku řazení a
-- dál nepostoupil → postup se plazil a nakonec stál. Přidáme marker
-- `photo_checked_at` = „u tohohle bodu se fotka už jednou zkoušela"; edge fn ho
-- nastaví po každém pokusu (i když se nic nenašlo), takže se okno posouvá a
-- backfill monotónně dojede. Hotovo = žádný aktivní bod bez fotky, který ještě
-- nebyl zkoušen → job se sám odplánuje.
-- Idempotentní.
-- ════════════════════════════════════════════════════════════════════

alter table public.points_of_interest
  add column if not exists photo_checked_at timestamptz;

create or replace function public.trigger_poi_photo_backfill()
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
  -- Práce = aktivní body BEZ fotky, u kterých se fotka JEŠTĚ nezkoušela.
  select count(*) into v_missing
  from public.points_of_interest
  where image_url is null and photo_checked_at is null and is_active;

  -- Hotovo → odplánuj sebe sama a skonči.
  if coalesce(v_missing, 0) = 0 then
    begin
      perform cron.unschedule('backfill-poi-photos');
    exception when others then null;
    end;
    return;
  end if;

  select value #>> '{}' into v_url from public.app_settings where key = 'supabase_url';
  select value #>> '{}' into v_key from public.app_settings where key = 'service_role_key';
  if v_url is null or v_url = '' or v_key is null or v_key = '' then
    raise warning 'trigger_poi_photo_backfill: app_settings supabase_url/service_role_key chybí';
    return;
  end if;

  perform net.http_post(
    url := v_url || '/functions/v1/backfill-poi-photos?limit=150',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_key
    ),
    body := '{}'::jsonb
  );
end $$;

grant execute on function public.trigger_poi_photo_backfill() to service_role;

-- Pojistka: pokud job neexistuje (čerstvé prostředí), naplánuj ho.
do $$
begin
  if not exists (select 1 from cron.job where jobname = 'backfill-poi-photos') then
    perform cron.schedule(
      'backfill-poi-photos',
      '*/5 * * * *',
      $cron$ select public.trigger_poi_photo_backfill(); $cron$
    );
  end if;
exception when others then
  raise warning 'cron.schedule selhalo (pg_cron nedostupné?): %', sqlerrm;
end $$;
