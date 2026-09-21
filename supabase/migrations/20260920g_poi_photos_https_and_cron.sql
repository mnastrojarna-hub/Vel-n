-- MotoGo24 — fotky míst: https adresy + oživení backfillu
-- ---------------------------------------------------------------------------
-- Zadání uživatele (2026-09-20): „bez fotek … všude kde to chybí doplň fotky".
-- Audit našel dvě příčiny, obě mimo appku:
--
-- 1) VŠECH 34 305 nasazených adres fotek je `http://commons.wikimedia.org/…`
--    (0 https). Velín běží na https, takže prohlížeč obrázek zablokuje jako
--    mixed content → sloupec „Foto" je prázdný i u míst, která fotku MAJÍ.
--    Appka obrázek dostane, ale přes tři přesměrování na každý náhled.
--
-- 2) Cron `backfill-poi-photos` se SÁM ODPLÁNOVAL: jakmile jednou obešel
--    všechny řádky, `trigger_poi_photo_backfill()` zavolal
--    `cron.unschedule('backfill-poi-photos')`. V živém výpisu cron.job
--    (STATE_5 §13, sesouhlaseno 2026-09-17) job skutečně není — 1 168 hor
--    bez fotky přidaných 19. 9. se tedy nikdy nezkusilo doplnit.
--    Navíc volal edge funkci bez `?wait=1`, což je na tomto projektu ověřeně
--    nefunkční vzorec (viz 20260709_poi_surroundings_sync.sql: worker je po
--    odpovědi 202 zabit a zapíše 0 řádků).
--
-- Idempotentní.

-- 1) http → https ------------------------------------------------------------
update public.points_of_interest
   set image_url = 'https://' || substring(image_url from 8), updated_at = now()
 where image_url like 'http://%'
   and (image_url like '%wikimedia.org%' or image_url like '%wikipedia.org%');

update public.points_of_interest p
   set images = (select array_agg(
                   case when u like 'http://%'
                         and (u like '%wikimedia.org%' or u like '%wikipedia.org%')
                        then 'https://' || substring(u from 8) else u end
                   order by ord)
                 from unnest(p.images) with ordinality as t(u, ord)),
       updated_at = now()
 where exists (select 1 from unnest(p.images) as u
                where u like 'http://%'
                  and (u like '%wikimedia.org%' or u like '%wikipedia.org%'));

update public.route_pois
   set image_url = 'https://' || substring(image_url from 8), updated_at = now()
 where image_url like 'http://%'
   and (image_url like '%wikimedia.org%' or image_url like '%wikipedia.org%');

update public.route_pois p
   set images = (select array_agg(
                   case when u like 'http://%'
                         and (u like '%wikimedia.org%' or u like '%wikipedia.org%')
                        then 'https://' || substring(u from 8) else u end
                   order by ord)
                 from unnest(p.images) with ordinality as t(u, ord)),
       updated_at = now()
 where exists (select 1 from unnest(p.images) as u
                where u like 'http://%'
                  and (u like '%wikimedia.org%' or u like '%wikipedia.org%'));

-- 2) Identita bodu ve Wikidatech --------------------------------------------
-- Bez QID se fotka hledala „co je do 600 m a jmenuje se podobně", což u
-- bezejmenných vrcholů nenajde nic (měřeno 0/20) a občas přilepí fotku úplně
-- jiného místa. S QID se dá sáhnout přímo na P18 / Commons kategorii.
alter table public.points_of_interest
  add column if not exists wikidata_id text;
create index if not exists idx_poi_catalog_wikidata
  on public.points_of_interest(wikidata_id) where wikidata_id is not null;

-- 3) Oživení cronu -----------------------------------------------------------
-- Rychlé dohledání práce (bez toho je to seq scan přes celý katalog každou minutu).
create index if not exists idx_poi_photo_todo
  on public.points_of_interest(sort_order, id)
  where image_url is null and photo_checked_at is null and is_active;

create or replace function public.trigger_poi_photo_backfill()
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_url text;
  v_key text;
begin
  -- Práce = aktivní body BEZ fotky, u kterých se fotka ještě nezkoušela.
  -- POZOR: dřív se job při nule SÁM ODPLÁNOVAL (`cron.unschedule`), takže po
  -- prvním dojetí zmizel a další dávka nových míst už se nikdy nezkusila.
  -- Teď jen tiše skončí a příští minutu se podívá znovu — díky
  -- idx_poi_photo_todo je to jeden levný dotaz.
  if not exists (
    select 1 from public.points_of_interest
     where image_url is null and photo_checked_at is null and is_active
     limit 1
  ) then
    return;
  end if;

  select value #>> '{}' into v_url from public.app_settings where key = 'supabase_url';
  select value #>> '{}' into v_key from public.app_settings where key = 'service_role_key';
  if v_url is null or v_url = '' or v_key is null or v_key = '' then
    raise warning 'trigger_poi_photo_backfill: app_settings supabase_url/service_role_key chybí';
    return;
  end if;

  -- SYNCHRONNĚ (`?wait=1`) + krátký rozpočet, stejně jako u popisu okolí:
  -- s odpovědí 202 Supabase workera zabije a dávka zapíše 0 řádků.
  perform net.http_post(
    url := v_url || '/functions/v1/backfill-poi-photos?wait=1&limit=40&budget_ms=20000',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_key
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 28000
  );
end $fn$;

grant execute on function public.trigger_poi_photo_backfill() to service_role;

do $do$
begin
  begin
    perform cron.unschedule('backfill-poi-photos');
  exception when others then null;
  end;
  perform cron.schedule(
    'backfill-poi-photos',
    '* * * * *',
    $cron$ select public.trigger_poi_photo_backfill(); $cron$
  );
exception when others then
  raise warning 'cron.schedule selhalo (pg_cron nedostupné?): %', sqlerrm;
end $do$;
