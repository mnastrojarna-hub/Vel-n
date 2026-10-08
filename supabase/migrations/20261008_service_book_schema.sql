-- 2026-10-08 (A) — Servisní knížka motorek: schéma (zadání majitele: „dotáhnout servisní systém,
-- aby existovala autonomní servisní knížka každé motorky a nic se nepodcenilo“).
-- Tři migrace 20261008 a/b/c (každá vlastní transakce deploy-sql, všechny idempotentní):
--   (A) tento soubor — tabulky a sloupce + katalog úkonů,
--   (B) 20261008b — triggery (auto km / technik dle loginu / klíče úkonů), hlídání intervalů (RPC), backfill,
--   (C) 20261008c — výrobcem předepsané intervaly pro modely flotily + založení plánů všem motorkám.
--
-- (A1) service_task_catalog — katalog servisních úkonů (klíč = id z velin/src/components/fleet/serviceCatalog.js,
--      seed generuje velin/scripts/gen-service-catalog-sql.mjs). Štítek (label) = text v maintenance_log.items,
--      aliases = historické štítky; `tracked` = základní standard hlídaný u každé motorky; `implies` = sada brzd
--      splní i destičky + kotouč; `only_for` = jen chain/shaft/belt/liquid/hours; `moto_interval` = interval
--      z karty motorky (oil/tire/full).
-- (A2) maintenance_log — `technician_report` (zpráva technika: co udělal / zjistil / vyměnil — vedle `description`
--      = zadání / popis závady), `technician_admin_id` (technik = účet Velína dle loginu), `completed_by`,
--      `updated_by/updated_at`, `km_auto` (km doplnil systém ze stavu tachometru), `invoiced_amount` (součet
--      nahraných faktur). CHECK service_type nově povoluje i `inspection` (Velín ho už dřív posílal a INSERT
--      tiše padal — zevrubná inspekce z „Naplánovat servis“ se nikdy neuložila).
-- (A3) maintenance_schedules — `task_key` (vazba plánu na úkon z katalogu → plán se posune sám, když technik
--      úkon odškrtne), `source` (manual/default/preset), `baseline_source` (log/acquisition/manual/unknown —
--      odkud je „naposledy provedeno“), `notes`, `updated_at`; CHECK schedule_type doplněn o hodnoty, které
--      formulář „Pravidelný servis“ posílal (km_interval/time_interval/reservation_interval — INSERT dřív padal,
--      proto byla tabulka v živé DB prázdná); unikát (moto_id, task_key) pro aktivní plány.
-- (A4) service_interval_presets — intervaly dle výrobce pro konkrétní modely (brand/model ILIKE vzor, rok).
-- (A5) maintenance_invoices — faktury / daňové doklady nahrané k servisnímu záznamu (externí servis nahraje
--      PDF/fotku → bucket invoices-received, řádek invoices type=received + financial_events expense → Finance).
-- (A6) service_provider_profiles — fakturační hlavička technika / externího servisu (IČO…) pro předvyplnění
--      dodavatele při nahrání faktury.
-- (A7) storage: bucket `invoices-received` — politiky pro admina (dosud do něj zapisovala jen edge fn
--      receive-invoice přes service_role; Velín potřebuje upload / signed URL z prohlížeče).
-- (A8) realtime publikace pro maintenance_log + maintenance_schedules (guard přes pg_publication_tables).

-- ==========================================================================
-- (A1) Katalog úkonů
-- ==========================================================================
CREATE TABLE IF NOT EXISTS public.service_task_catalog (
  key                     text PRIMARY KEY,
  label                   text NOT NULL,
  group_key               text NOT NULL,
  group_label             text NOT NULL,
  sort_order              integer NOT NULL DEFAULT 0,
  kind                    text NOT NULL DEFAULT 'other' CHECK (kind IN ('replace','check','adjust','repair','other')),
  default_interval_km     integer,
  default_interval_months integer,
  tracked                 boolean NOT NULL DEFAULT false,
  only_for                text CHECK (only_for IS NULL OR only_for IN ('chain','shaft','belt','liquid','hydraulic','hours')),
  moto_interval           text CHECK (moto_interval IS NULL OR moto_interval IN ('oil','tire','full')),
  implies                 text[] NOT NULL DEFAULT '{}',
  aliases                 text[] NOT NULL DEFAULT '{}',
  active                  boolean NOT NULL DEFAULT true,
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.service_task_catalog IS
  'Katalog servisních úkonů (2026-10-08). Zdroj pravdy = velin/src/components/fleet/serviceCatalog.js (seed přes velin/scripts/gen-service-catalog-sql.mjs). label = štítek v maintenance_log.items, aliases = historické štítky, tracked = základní standard hlídaný u každé motorky (maintenance_schedules.task_key), implies = odškrtnutí splní i tyto úkony.';

ALTER TABLE public.service_task_catalog ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS service_task_catalog_public_read ON public.service_task_catalog;
CREATE POLICY service_task_catalog_public_read ON public.service_task_catalog FOR SELECT USING (true);
DROP POLICY IF EXISTS service_task_catalog_admin_write ON public.service_task_catalog;
CREATE POLICY service_task_catalog_admin_write ON public.service_task_catalog FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
GRANT SELECT ON public.service_task_catalog TO anon, authenticated;
GRANT ALL ON public.service_task_catalog TO service_role;

INSERT INTO public.service_task_catalog
  (key, label, group_key, group_label, sort_order, kind, default_interval_km, default_interval_months, tracked, only_for, moto_interval, implies, aliases)
VALUES
  ('oil_change', 'Výměna oleje', 'engine', 'Motor & olej', 10, 'replace', 10000, 12, true, NULL, 'oil', '{}'::text[], ARRAY['Výměna motorového oleje','Olejový servis']::text[]),
  ('oil_filter', 'Výměna olejového filtru', 'engine', 'Motor & olej', 20, 'replace', 10000, 12, true, NULL, 'oil', '{}'::text[], '{}'::text[]),
  ('air_filter', 'Výměna vzduchového filtru', 'engine', 'Motor & olej', 30, 'replace', 20000, 24, true, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('air_filter_clean', 'Čištění vzduchového filtru', 'engine', 'Motor & olej', 40, 'check', 5000, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('spark_plugs', 'Výměna svíček', 'engine', 'Motor & olej', 50, 'replace', 20000, 24, true, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('valve_clearance', 'Kontrola / seřízení ventilových vůlí', 'engine', 'Motor & olej', 60, 'check', 24000, NULL, true, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('timing_check', 'Kontrola / dopnutí rozvodů', 'engine', 'Motor & olej', 70, 'check', 24000, NULL, true, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('throttle_sync', 'Synchronizace škrticích klapek / karburátorů', 'engine', 'Motor & olej', 80, 'adjust', 24000, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('fuel_filter', 'Výměna palivového filtru', 'engine', 'Motor & olej', 90, 'replace', 40000, 48, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('fuel_system', 'Oprava palivové soustavy (čerpadlo, vstřikování, karburátor)', 'engine', 'Motor & olej', 100, 'repair', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('engine_noise', 'Neobvyklý zvuk motoru', 'engine', 'Motor & olej', 110, 'repair', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('oil_leak', 'Únik oleje — diagnostika / oprava', 'engine', 'Motor & olej', 120, 'repair', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('exhaust', 'Oprava / výměna výfuku', 'engine', 'Motor & olej', 130, 'repair', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('gearbox_oil', 'Výměna převodového oleje (skútr / dvoutakt)', 'engine', 'Motor & olej', 140, 'replace', 10000, 24, true, 'belt', NULL, '{}'::text[], '{}'::text[]),
  ('coolant_change', 'Výměna chladicí kapaliny', 'cooling', 'Chlazení', 150, 'replace', 40000, 36, true, 'liquid', NULL, ARRAY['coolant_check']::text[], ARRAY['Kontrola / výměna chladicí kapaliny']::text[]),
  ('coolant_check', 'Kontrola hladiny a stavu chladicí kapaliny', 'cooling', 'Chlazení', 160, 'check', 6000, NULL, false, 'liquid', NULL, '{}'::text[], '{}'::text[]),
  ('radiator', 'Čištění chladiče / kontrola ventilátoru', 'cooling', 'Chlazení', 170, 'check', NULL, 12, false, 'liquid', NULL, '{}'::text[], '{}'::text[]),
  ('cooling_repair', 'Oprava chlazení (termostat, čerpadlo, hadice)', 'cooling', 'Chlazení', 180, 'repair', NULL, NULL, false, 'liquid', NULL, '{}'::text[], '{}'::text[]),
  ('brake_pads_check', 'Kontrola brzdových destiček', 'brakes', 'Brzdy', 190, 'check', 5000, 6, true, NULL, NULL, '{}'::text[], ARRAY['Brzdy (vizuálně)','Kontrola brzd']::text[]),
  ('brake_pads_front', 'Brzdové destičky přední', 'brakes', 'Brzdy', 200, 'replace', NULL, NULL, false, NULL, NULL, ARRAY['brake_pads_check']::text[], ARRAY['Výměna brzdových destiček přední']::text[]),
  ('brake_pads_rear', 'Brzdové destičky zadní', 'brakes', 'Brzdy', 210, 'replace', NULL, NULL, false, NULL, NULL, ARRAY['brake_pads_check']::text[], ARRAY['Výměna brzdových destiček zadní']::text[]),
  ('brake_discs', 'Kontrola brzdových kotoučů', 'brakes', 'Brzdy', 220, 'check', 10000, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('brake_disc_front', 'Výměna brzdového kotouče přední', 'brakes', 'Brzdy', 230, 'replace', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('brake_disc_rear', 'Výměna brzdového kotouče zadní', 'brakes', 'Brzdy', 240, 'replace', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('brake_set_front', 'Výměna brzdové sady přední (destičky + kotouč)', 'brakes', 'Brzdy', 250, 'replace', NULL, NULL, false, NULL, NULL, ARRAY['brake_pads_front','brake_disc_front']::text[], '{}'::text[]),
  ('brake_set_rear', 'Výměna brzdové sady zadní (destičky + kotouč)', 'brakes', 'Brzdy', 260, 'replace', NULL, NULL, false, NULL, NULL, ARRAY['brake_pads_rear','brake_disc_rear']::text[], '{}'::text[]),
  ('brake_fluid', 'Výměna brzdové kapaliny', 'brakes', 'Brzdy', 270, 'replace', NULL, 24, true, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('brake_lines', 'Výměna brzdových hadic', 'brakes', 'Brzdy', 280, 'replace', NULL, 48, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('brake_caliper', 'Servis brzdového třmenu (pístky, čištění)', 'brakes', 'Brzdy', 290, 'repair', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('abs_check', 'Kontrola / diagnostika ABS', 'brakes', 'Brzdy', 300, 'check', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('suspension_check', 'Kontrola tlumičů / pružin', 'chassis', 'Podvozek & řízení', 310, 'check', NULL, 12, true, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('fork_oil', 'Výměna oleje v přední vidlici', 'chassis', 'Podvozek & řízení', 320, 'replace', 30000, 36, true, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('fork_seals', 'Přetěsnění přední vidlice (simerinky)', 'chassis', 'Podvozek & řízení', 330, 'repair', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('shock_service', 'Servis / přetěsnění zadního tlumiče', 'chassis', 'Podvozek & řízení', 340, 'repair', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('shock_replace', 'Výměna zadního tlumiče', 'chassis', 'Podvozek & řízení', 350, 'replace', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('steering_bearings', 'Kontrola / výměna ložisek řízení', 'chassis', 'Podvozek & řízení', 360, 'check', 24000, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('swingarm_bearings', 'Kontrola / mazání ložisek kyvné vidlice', 'chassis', 'Podvozek & řízení', 370, 'check', 24000, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('linkage_lube', 'Mazání čepů zadního odpružení', 'chassis', 'Podvozek & řízení', 380, 'adjust', 12000, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('wheel_bearings', 'Kontrola ložisek kol', 'chassis', 'Podvozek & řízení', 390, 'check', 20000, NULL, false, NULL, NULL, '{}'::text[], ARRAY['Kontrola / výměna ložisek kol']::text[]),
  ('wheel_bearings_replace', 'Výměna ložisek kol', 'chassis', 'Podvozek & řízení', 400, 'replace', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('side_stand', 'Kontrola / mazání stojánku', 'chassis', 'Podvozek & řízení', 410, 'check', NULL, 12, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('tire_check', 'Kontrola stavu / dezénu pneumatik', 'tires', 'Pneumatiky & kola', 420, 'check', 3000, NULL, false, NULL, NULL, '{}'::text[], ARRAY['Stav pneumatik']::text[]),
  ('tire_pressure', 'Kontrola tlaku pneumatik', 'tires', 'Pneumatiky & kola', 430, 'check', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('tire_front', 'Výměna přední pneumatiky', 'tires', 'Pneumatiky & kola', 440, 'replace', NULL, NULL, true, NULL, 'tire', '{}'::text[], '{}'::text[]),
  ('tire_rear', 'Výměna zadní pneumatiky', 'tires', 'Pneumatiky & kola', 450, 'replace', NULL, NULL, true, NULL, 'tire', '{}'::text[], '{}'::text[]),
  ('wheel_balance', 'Vyvážení kol', 'tires', 'Pneumatiky & kola', 460, 'adjust', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('wheel_spokes', 'Kontrola / dotažení drátů kol', 'tires', 'Pneumatiky & kola', 470, 'check', 10000, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('valve_stems', 'Výměna ventilků', 'tires', 'Pneumatiky & kola', 480, 'replace', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('chain_adjust', 'Seřízení řetězu', 'drive', 'Řetěz / kardan / řemen', 490, 'adjust', 1000, NULL, false, 'chain', NULL, '{}'::text[], ARRAY['Dopnutí / seřízení řetězu','Dopnutí řetězu','Řetěz — napnutí, mazání']::text[]),
  ('chain_lube', 'Promazání řetězu', 'drive', 'Řetěz / kardan / řemen', 500, 'adjust', NULL, NULL, false, 'chain', NULL, '{}'::text[], '{}'::text[]),
  ('chain_clean', 'Čištění řetězu', 'drive', 'Řetěz / kardan / řemen', 510, 'adjust', NULL, NULL, false, 'chain', NULL, '{}'::text[], '{}'::text[]),
  ('chain_check', 'Kontrola opotřebení řetězu a rozet', 'drive', 'Řetěz / kardan / řemen', 520, 'check', 5000, NULL, false, 'chain', NULL, '{}'::text[], '{}'::text[]),
  ('chain_kit', 'Výměna řetězu + rozet', 'drive', 'Řetěz / kardan / řemen', 530, 'replace', 25000, NULL, true, 'chain', NULL, ARRAY['chain_adjust','chain_check']::text[], ARRAY['Výměna řetězové sady']::text[]),
  ('final_drive_oil', 'Výměna oleje v kardanu / rozvodovce', 'drive', 'Řetěz / kardan / řemen', 540, 'replace', 20000, 24, true, 'shaft', NULL, '{}'::text[], ARRAY['Výměna oleje v kardanu']::text[]),
  ('final_drive_check', 'Kontrola kardanu (vůle, únik oleje)', 'drive', 'Řetěz / kardan / řemen', 550, 'check', 10000, NULL, false, 'shaft', NULL, '{}'::text[], '{}'::text[]),
  ('belt_check', 'Kontrola / napnutí řemenu', 'drive', 'Řetěz / kardan / řemen', 560, 'check', 10000, NULL, false, 'belt', NULL, '{}'::text[], '{}'::text[]),
  ('belt_replace', 'Výměna hnacího řemenu (CVT / rozvodový)', 'drive', 'Řetěz / kardan / řemen', 570, 'replace', 24000, 48, true, 'belt', NULL, '{}'::text[], '{}'::text[]),
  ('cvt_service', 'Servis variátoru (válečky, spojka)', 'drive', 'Řetěz / kardan / řemen', 580, 'repair', 12000, NULL, false, 'belt', NULL, '{}'::text[], '{}'::text[]),
  ('clutch', 'Kontrola / seřízení spojky', 'clutch', 'Spojka & převodovka', 590, 'check', 6000, 12, true, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('clutch_cable', 'Výměna lanka spojky', 'clutch', 'Spojka & převodovka', 600, 'replace', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('clutch_plates', 'Výměna spojkových lamel', 'clutch', 'Spojka & převodovka', 610, 'replace', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('clutch_fluid', 'Výměna kapaliny hydraulické spojky', 'clutch', 'Spojka & převodovka', 620, 'replace', NULL, 24, false, 'hydraulic', NULL, '{}'::text[], '{}'::text[]),
  ('gearbox_issue', 'Problém s řazením — diagnostika / oprava', 'clutch', 'Spojka & převodovka', 630, 'repair', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('battery', 'Kontrola / výměna baterie', 'electrics', 'Elektrika & světla', 640, 'check', NULL, 6, true, NULL, NULL, '{}'::text[], ARRAY['Kontrola / dobití baterie']::text[]),
  ('battery_replace', 'Výměna baterie', 'electrics', 'Elektrika & světla', 650, 'replace', NULL, 36, false, NULL, NULL, ARRAY['battery']::text[], '{}'::text[]),
  ('charging', 'Kontrola dobíjení (alternátor, regulátor)', 'electrics', 'Elektrika & světla', 660, 'check', NULL, 12, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('lights', 'Kontrola světel', 'electrics', 'Elektrika & světla', 670, 'check', NULL, NULL, false, NULL, NULL, '{}'::text[], ARRAY['Světla a blinkry']::text[]),
  ('bulb', 'Výměna žárovky / LED', 'electrics', 'Elektrika & světla', 680, 'replace', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('fuses', 'Kontrola pojistek', 'electrics', 'Elektrika & světla', 690, 'check', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('starter', 'Problém se startérem', 'electrics', 'Elektrika & světla', 700, 'repair', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('wiring', 'Oprava elektroinstalace / konektorů', 'electrics', 'Elektrika & světla', 710, 'repair', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('horn', 'Kontrola klaksonu', 'electrics', 'Elektrika & světla', 720, 'check', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('diagnostics', 'Diagnostika řídicí jednotky (čtení chyb)', 'electrics', 'Elektrika & světla', 730, 'check', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('software_update', 'Aktualizace softwaru řídicí jednotky', 'electrics', 'Elektrika & světla', 740, 'other', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('windscreen', 'Výměna plexi / větrného štítu', 'body', 'Karoserie & ovládání', 750, 'replace', NULL, NULL, false, NULL, NULL, '{}'::text[], ARRAY['Výměna prasklého plexi']::text[]),
  ('plastics', 'Oprava / výměna plastů a kapotáže', 'body', 'Karoserie & ovládání', 760, 'repair', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('mirrors', 'Výměna / seřízení zrcátek', 'body', 'Karoserie & ovládání', 770, 'repair', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('levers', 'Výměna páček (brzda / spojka)', 'body', 'Karoserie & ovládání', 780, 'replace', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('handlebar', 'Výměna / seřízení řídítek', 'body', 'Karoserie & ovládání', 790, 'repair', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('grips', 'Výměna gripů / rukojetí', 'body', 'Karoserie & ovládání', 800, 'replace', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('footpegs', 'Výměna stupaček / řadicí páky', 'body', 'Karoserie & ovládání', 810, 'replace', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('seat', 'Oprava / výměna sedla', 'body', 'Karoserie & ovládání', 820, 'repair', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('luggage', 'Oprava / montáž kufrů a nosičů', 'body', 'Karoserie & ovládání', 830, 'repair', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('cables_lube', 'Mazání lanek a čepů', 'body', 'Karoserie & ovládání', 840, 'adjust', NULL, 6, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('key_lock', 'Zámky / klíče / imobilizér', 'body', 'Karoserie & ovládání', 850, 'repair', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('cosmetic', 'Kosmetická oprava (lak, plasty)', 'body', 'Karoserie & ovládání', 860, 'repair', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('accident_repair', 'Oprava po nehodě', 'body', 'Karoserie & ovládání', 870, 'repair', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('full_service', 'Kompletní servis / velká prohlídka', 'other', 'Kontroly & ostatní', 880, 'check', 20000, 24, true, NULL, 'full', ARRAY['oil_change','oil_filter','general_inspection','brake_pads_check','clutch','suspension_check','battery','chain_adjust','coolant_check','tire_check','tire_pressure','lights']::text[], '{}'::text[]),
  ('general_inspection', 'Celková kontrola stroje (před / po sezóně)', 'other', 'Kontroly & ostatní', 890, 'check', NULL, 6, true, NULL, NULL, ARRAY['brake_pads_check','tire_check','tire_pressure','lights','battery','suspension_check','chain_adjust']::text[], ARRAY['Vizuální stav motorky','Zevrubná inspekce']::text[]),
  ('stk', 'Příprava na STK', 'other', 'Kontroly & ostatní', 900, 'other', NULL, NULL, false, NULL, NULL, ARRAY['lights','tire_check','brake_pads_check']::text[], '{}'::text[]),
  ('winter_storage', 'Zazimování / odzimování', 'other', 'Kontroly & ostatní', 910, 'other', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('test_ride', 'Zkušební jízda', 'other', 'Kontroly & ostatní', 920, 'check', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('wash', 'Mytí a konzervace', 'other', 'Kontroly & ostatní', 930, 'other', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('recall', 'Svolávací akce výrobce', 'other', 'Kontroly & ostatní', 940, 'other', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[]),
  ('other_repair', 'Jiná oprava', 'other', 'Kontroly & ostatní', 950, 'repair', NULL, NULL, false, NULL, NULL, '{}'::text[], '{}'::text[])
ON CONFLICT (key) DO UPDATE SET
  label = EXCLUDED.label, group_key = EXCLUDED.group_key, group_label = EXCLUDED.group_label,
  sort_order = EXCLUDED.sort_order, kind = EXCLUDED.kind,
  default_interval_km = EXCLUDED.default_interval_km, default_interval_months = EXCLUDED.default_interval_months,
  tracked = EXCLUDED.tracked, only_for = EXCLUDED.only_for, moto_interval = EXCLUDED.moto_interval,
  implies = EXCLUDED.implies, aliases = EXCLUDED.aliases, updated_at = now();

-- ==========================================================================
-- (A2) maintenance_log — zpráva technika, technik dle loginu, auto km
-- ==========================================================================
ALTER TABLE public.maintenance_log
  ADD COLUMN IF NOT EXISTS technician_report   text,
  ADD COLUMN IF NOT EXISTS technician_admin_id uuid REFERENCES public.admin_users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS completed_by        uuid,
  ADD COLUMN IF NOT EXISTS updated_by          uuid,
  ADD COLUMN IF NOT EXISTS updated_at          timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS km_auto             boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS invoiced_amount     numeric(12,2) NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.maintenance_log.description IS 'Zadání servisu / popis závady (co je potřeba) — píše zadavatel.';
COMMENT ON COLUMN public.maintenance_log.technician_report IS 'Zpráva technika: co udělal, co zjistil, co vyměnil (2026-10-08).';
COMMENT ON COLUMN public.maintenance_log.technician_admin_id IS 'Technik = účet Velína (admin_users); doplní se automaticky z loginu při založení / dokončení, lze přepsat.';
COMMENT ON COLUMN public.maintenance_log.performed_by IS 'Jméno technika (text) — automaticky jméno přihlášeného účtu Velína, nebo externí technik ručně.';
COMMENT ON COLUMN public.maintenance_log.km_auto IS 'true = km_at_service doplnil systém ze stavu tachometru motorky (při založení i při dokončení); ručně zadané km = false.';
COMMENT ON COLUMN public.maintenance_log.invoiced_amount IS 'Součet částek faktur nahraných k záznamu (maintenance_invoices) — udržuje trigger.';

ALTER TABLE public.maintenance_log DROP CONSTRAINT IF EXISTS maintenance_log_service_type_check;
ALTER TABLE public.maintenance_log ADD CONSTRAINT maintenance_log_service_type_check
  CHECK (service_type = ANY (ARRAY['regular','extraordinary','repair','inspection']));

CREATE INDEX IF NOT EXISTS idx_maintenance_log_technician_admin ON public.maintenance_log(technician_admin_id) WHERE technician_admin_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_maintenance_log_open ON public.maintenance_log(moto_id) WHERE completed_date IS NULL;

-- ==========================================================================
-- (A3) maintenance_schedules — vazba na úkon, původ intervalu i baseline
-- ==========================================================================
ALTER TABLE public.maintenance_schedules
  ADD COLUMN IF NOT EXISTS task_key        text REFERENCES public.service_task_catalog(key) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS source          text NOT NULL DEFAULT 'manual',
  ADD COLUMN IF NOT EXISTS baseline_source text,
  ADD COLUMN IF NOT EXISTS notes           text,
  ADD COLUMN IF NOT EXISTS updated_at      timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.maintenance_schedules DROP CONSTRAINT IF EXISTS maintenance_schedules_source_check;
ALTER TABLE public.maintenance_schedules ADD CONSTRAINT maintenance_schedules_source_check
  CHECK (source IN ('manual','default','preset'));
ALTER TABLE public.maintenance_schedules DROP CONSTRAINT IF EXISTS maintenance_schedules_baseline_source_check;
ALTER TABLE public.maintenance_schedules ADD CONSTRAINT maintenance_schedules_baseline_source_check
  CHECK (baseline_source IS NULL OR baseline_source IN ('log','acquisition','manual','unknown'));
ALTER TABLE public.maintenance_schedules DROP CONSTRAINT IF EXISTS maintenance_schedules_schedule_type_check;
ALTER TABLE public.maintenance_schedules ADD CONSTRAINT maintenance_schedules_schedule_type_check
  CHECK (schedule_type = ANY (ARRAY['mileage','time','both','km_interval','time_interval','reservation_interval']));

CREATE UNIQUE INDEX IF NOT EXISTS maintenance_schedules_moto_task_active
  ON public.maintenance_schedules(moto_id, task_key) WHERE active = true AND task_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_maintenance_schedules_moto_active ON public.maintenance_schedules(moto_id) WHERE active = true;

COMMENT ON COLUMN public.maintenance_schedules.task_key IS 'Úkon z service_task_catalog — dokončený servis s odškrtnutým úkonem posune last_service_km/date tohoto plánu (trigger update_moto_after_service).';
COMMENT ON COLUMN public.maintenance_schedules.source IS 'manual = zadal admin; default = základní standard z katalogu; preset = interval dle výrobce (service_interval_presets).';
COMMENT ON COLUMN public.maintenance_schedules.baseline_source IS 'Odkud je „naposledy provedeno“: log (dokončený servisní záznam), acquisition (km/datum pořízení — neověřeno), manual (zadal admin), unknown.';
COMMENT ON COLUMN public.maintenance_schedules.next_due IS 'Ručně naplánované datum servisu (volitelné). Odhad termínu z km/dní počítá get_service_due.';

-- ==========================================================================
-- (A4) Intervaly dle výrobce pro konkrétní modely
-- ==========================================================================
CREATE TABLE IF NOT EXISTS public.service_interval_presets (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  brand_pattern   text,
  model_pattern   text NOT NULL,
  year_from       integer,
  year_to         integer,
  task_key        text NOT NULL REFERENCES public.service_task_catalog(key) ON DELETE CASCADE,
  interval_km     integer,
  interval_months integer,
  note            text,
  source_url      text,
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS service_interval_presets_unique
  ON public.service_interval_presets(model_pattern, task_key, COALESCE(year_from, 0), COALESCE(year_to, 9999));
COMMENT ON TABLE public.service_interval_presets IS
  'Servisní intervaly předepsané výrobcem pro modely flotily (2026-10-08). model_pattern/brand_pattern = ILIKE vzor na motorcycles.model/brand; interval_km je v jednotce motorky (km nebo motohodiny). Aplikuje service_plan_apply_presets.';
ALTER TABLE public.service_interval_presets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS service_interval_presets_public_read ON public.service_interval_presets;
CREATE POLICY service_interval_presets_public_read ON public.service_interval_presets FOR SELECT USING (true);
DROP POLICY IF EXISTS service_interval_presets_admin_write ON public.service_interval_presets;
CREATE POLICY service_interval_presets_admin_write ON public.service_interval_presets FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
GRANT SELECT ON public.service_interval_presets TO anon, authenticated;
GRANT ALL ON public.service_interval_presets TO service_role;

-- ==========================================================================
-- (A5) Faktury k servisu
-- ==========================================================================
CREATE TABLE IF NOT EXISTS public.maintenance_invoices (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  maintenance_log_id  uuid NOT NULL REFERENCES public.maintenance_log(id) ON DELETE CASCADE,
  moto_id             uuid REFERENCES public.motorcycles(id) ON DELETE SET NULL,
  invoice_id          uuid REFERENCES public.invoices(id) ON DELETE SET NULL,
  financial_event_id  uuid REFERENCES public.financial_events(id) ON DELETE SET NULL,
  storage_bucket      text NOT NULL DEFAULT 'invoices-received',
  storage_path        text NOT NULL,
  file_name           text,
  mime_type           text,
  file_size           integer,
  invoice_number      text,
  supplier_name       text,
  supplier_ico        text,
  amount              numeric(12,2),
  issue_date          date,
  due_date            date,
  ocr_status          text NOT NULL DEFAULT 'none' CHECK (ocr_status IN ('none','pending','done','failed')),
  note                text,
  uploaded_by         uuid,
  uploaded_by_name    text,
  created_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_maintenance_invoices_log ON public.maintenance_invoices(maintenance_log_id);
CREATE INDEX IF NOT EXISTS idx_maintenance_invoices_invoice ON public.maintenance_invoices(invoice_id) WHERE invoice_id IS NOT NULL;
COMMENT ON TABLE public.maintenance_invoices IS
  'Faktury / daňové doklady nahrané k servisnímu záznamu (2026-10-08): soubor v bucketu invoices-received (servis/<log_id>/…), vazba na invoices (type=received, source=service) a financial_events (expense) → Finance → Přijaté faktury. Součet amount udržuje maintenance_log.invoiced_amount.';
ALTER TABLE public.maintenance_invoices ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS maintenance_invoices_admin_all ON public.maintenance_invoices;
CREATE POLICY maintenance_invoices_admin_all ON public.maintenance_invoices FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
GRANT ALL ON public.maintenance_invoices TO authenticated, service_role;

-- ==========================================================================
-- (A6) Fakturační hlavička technika / externího servisu
-- ==========================================================================
CREATE TABLE IF NOT EXISTS public.service_provider_profiles (
  admin_id      uuid PRIMARY KEY REFERENCES public.admin_users(id) ON DELETE CASCADE,
  company_name  text,
  ico           text,
  dic           text,
  address       text,
  email         text,
  phone         text,
  bank_account  text,
  supplier_id   uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
  updated_at    timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.service_provider_profiles IS
  'Fakturační údaje (hlavička, IČO…) účtu Velína, který servisuje — externí servis si je vyplní v Servisu → „Moje fakturační údaje“; předvyplní dodavatele při nahrání faktury k servisu (2026-10-08).';
ALTER TABLE public.service_provider_profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS service_provider_profiles_admin_all ON public.service_provider_profiles;
DROP POLICY IF EXISTS service_provider_profiles_own ON public.service_provider_profiles;
-- vlastní řádek (technik) nebo superadmin (Finance / správa účtů)
CREATE POLICY service_provider_profiles_own ON public.service_provider_profiles
  FOR ALL USING (public.is_admin() AND (admin_id = auth.uid() OR public.is_superadmin()))
  WITH CHECK (public.is_admin() AND (admin_id = auth.uid() OR public.is_superadmin()));
GRANT ALL ON public.service_provider_profiles TO authenticated, service_role;

-- ==========================================================================
-- (A7) Storage — bucket invoices-received: admin z Velína (upload / čtení / mazání)
-- ==========================================================================
DO $$
BEGIN
  INSERT INTO storage.buckets (id, name, public) VALUES ('invoices-received', 'invoices-received', false)
  ON CONFLICT (id) DO NOTHING;
  DROP POLICY IF EXISTS invoices_received_admin_select ON storage.objects;
  CREATE POLICY invoices_received_admin_select ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'invoices-received' AND public.is_admin());
  DROP POLICY IF EXISTS invoices_received_admin_insert ON storage.objects;
  CREATE POLICY invoices_received_admin_insert ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'invoices-received' AND public.is_admin());
  DROP POLICY IF EXISTS invoices_received_admin_update ON storage.objects;
  CREATE POLICY invoices_received_admin_update ON storage.objects FOR UPDATE TO authenticated
    USING (bucket_id = 'invoices-received' AND public.is_admin()) WITH CHECK (bucket_id = 'invoices-received' AND public.is_admin());
  DROP POLICY IF EXISTS invoices_received_admin_delete ON storage.objects;
  CREATE POLICY invoices_received_admin_delete ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'invoices-received' AND public.is_admin());
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'invoices-received storage policies: % (doplňte ručně v Dashboardu → Storage → Policies)', SQLERRM;
END $$;

-- ==========================================================================
-- (A8) Realtime — Velín (servisní knížka, Sidebar) poslouchá maintenance_log i maintenance_schedules
-- ==========================================================================
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['maintenance_log', 'maintenance_schedules'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    END IF;
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ALTER PUBLICATION supabase_realtime (maintenance_*) selhalo: %', SQLERRM;
END $$;
