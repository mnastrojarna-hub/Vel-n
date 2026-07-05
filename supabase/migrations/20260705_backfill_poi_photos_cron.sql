-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — Automatické doplnění fotek bodů zájmu (cron → edge)
--
-- Pro body v `points_of_interest` bez fotky zavolá edge fn
-- `backfill-poi-photos`, která najde obrázek s VOLNOU licencí (Wikimedia
-- Commons / Wikipedia, jen při shodě názvu) a doplní `image_url`. Cron
-- `mirror-route-images` (už pokrývá points_of_interest) je pak zrcadlí do
-- bucketu `media`.
--
-- Běží samo: cron každých 5 min spustí jednu dávku (150 bodů); když už žádný
-- bod fotku nepostrádá, job se sám odplánuje. URL + klíč se čtou z
-- `app_settings` — stejný ověřený vzor jako `backfill-route-translations`.
-- Idempotentní: opětovné nasazení jen přepíše funkci a přeplánuje job.
-- ════════════════════════════════════════════════════════════════════

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
  -- Kolik aktivních bodů zájmu ještě nemá fotku.
  select count(*) into v_missing
  from public.points_of_interest
  where image_url is null and is_active;

  -- Hotovo → odplánuj sebe sama a skonči (levný no-op, nebudí edge fn).
  if coalesce(v_missing, 0) = 0 then
    begin
      perform cron.unschedule('backfill-poi-photos');
    exception when others then null; -- job už neexistuje
    end;
    return;
  end if;

  select value #>> '{}' into v_url from public.app_settings where key = 'supabase_url';
  select value #>> '{}' into v_key from public.app_settings where key = 'service_role_key';
  if v_url is null or v_url = '' or v_key is null or v_key = '' then
    raise warning 'trigger_poi_photo_backfill: app_settings supabase_url/service_role_key chybí';
    return;
  end if;

  -- Spusť jednu dávku (edge fn si sama vybere body bez fotky, limit v URL).
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

-- Naplánuj cron (každých 5 min). Nejdřív zruš případný starý job.
do $$
begin
  begin
    perform cron.unschedule('backfill-poi-photos');
  exception when others then null;
  end;
  perform cron.schedule(
    'backfill-poi-photos',
    '*/5 * * * *',
    $cron$ select public.trigger_poi_photo_backfill(); $cron$
  );
exception when others then
  raise warning 'cron.schedule selhalo (pg_cron nedostupné?): %', sqlerrm;
end $$;
