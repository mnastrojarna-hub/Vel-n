-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — Oprava detekce chybějících překladů tras a bodů zájmu (2026-07-04)
--
-- Kontrola překladů odhalila dvě díry (detail ANALYZA_TRASY_POI.md):
--  1) Backfill (DB fce i edge `backfill-route-translations`) považoval řádek
--     za přeložený, jakmile měl `translations->'en'->>'name'`. Řádek s padlým
--     jazykem (např. jen en+de) nebo s ručně přepsaným názvem se už nikdy
--     nedopřeložil. Nově se kontroluje VŠECH 7 jazyků, name i description.
--     (Edge fn opravena v témže commitu — NUTNO REDEPLOY.)
--  2) `20260704_routes_postseed_fixes.sql` přepsal názvy 7 přejmenovaných tras
--     jen v en/de/es/fr/nl/pl — ukrajinský název zůstal starý (nebo chybí).
--     Doplňujeme uk názvy ručně (popisy se rename neměnily, ty jsou OK).
-- Na konci se přeplánuje cron — podle nové detekce dopřeloží vše, co chybí
-- (vč. 26 kurátorovaných bodů z 20260705_route_pois_fill_gaps.sql).
-- ════════════════════════════════════════════════════════════════════

begin;

-- ── 1) Robustnější počítadlo nedopřeložených řádků ────────────────────
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
  -- Kolik řádků nemá kompletní překlad (name ve všech jazycích; description
  -- ve všech jazycích, pokud řádek popis má).
  select
    (select count(*) from public.routes r
      where exists (
        select 1 from unnest(array['en','de','es','fr','nl','pl','uk']) as l(lang)
        where r.translations->l.lang->>'name' is null
           or (r.description is not null and r.translations->l.lang->>'description' is null)))
  + (select count(*) from public.route_pois p
      where exists (
        select 1 from unnest(array['en','de','es','fr','nl','pl','uk']) as l(lang)
        where p.translations->l.lang->>'name' is null
           or (p.description is not null and p.translations->l.lang->>'description' is null)))
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

-- ── 2) Ukrajinské názvy 7 přejmenovaných tras (rename přepsal jen 6 jazyků) ──
update public.routes set translations = coalesce(translations,'{}'::jsonb) || jsonb_build_object(
    'uk', coalesce(translations->'uk','{}'::jsonb) || jsonb_build_object('name','Греблі, вода та монастир Височини')
  ) where name = 'Přehrady, voda a klášter Vysočiny';

update public.routes set translations = coalesce(translations,'{}'::jsonb) || jsonb_build_object(
    'uk', coalesce(translations->'uk','{}'::jsonb) || jsonb_build_object('name','Оглядові вежі та замок Камен (Височина)')
  ) where name = 'Rozhledny a hrad Kámen (Vysočina)';

update public.routes set translations = coalesce(translations,'{}'::jsonb) || jsonb_build_object(
    'uk', coalesce(translations->'uk','{}'::jsonb) || jsonb_build_object('name','Оглядові вежі та замок Пржибислав')
  ) where name = 'Rozhledny a zámek Přibyslav';

update public.routes set translations = coalesce(translations,'{}'::jsonb) || jsonb_build_object(
    'uk', coalesce(translations->'uk','{}'::jsonb) || jsonb_build_object('name','Оглядові вежі та замки околиць Тржебіча (Марженка і Бабілон)')
  ) where name = 'Rozhledny a zámky Třebíčska (Mařenka a Babylon)';

update public.routes set translations = coalesce(translations,'{}'::jsonb) || jsonb_build_object(
    'uk', coalesce(translations->'uk','{}'::jsonb) || jsonb_build_object('name','Замки та печери навколо Праги')
  ) where name = 'Hrady a jeskyně kolem Prahy';

update public.routes set translations = coalesce(translations,'{}'::jsonb) || jsonb_build_object(
    'uk', coalesce(translations->'uk','{}'::jsonb) || jsonb_build_object('name','Полабʼя – замки та скансен')
  ) where name = 'Polabí – zámky a skanzen';

update public.routes set translations = coalesce(translations,'{}'::jsonb) || jsonb_build_object(
    'uk', coalesce(translations->'uk','{}'::jsonb) || jsonb_build_object('name','Оглядові вежі та памʼятки Пісецьких гір')
  ) where name = 'Rozhledny a památky Píseckých hor';

-- ── 3) Přeplánuj cron — nová detekce dopřeloží vše, co reálně chybí ────
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

commit;
