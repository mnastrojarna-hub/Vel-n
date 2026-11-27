-- =============================================================================
-- 20261128b1_seo_motorcycles_fixes_1.sql (část 1/2)
-- 2026-11-28, schváleno majitelem 2026-11-27. Části 1–2 vznikly rozdělením jednoho souboru po celých sekcích
-- (každá sekce mění jiné sloupce). Tato část: 1) parametry a 2) výbava a výhody (features).
-- Datová migrace (bez změn schématu): pravopisné a typografické opravy českých textů motorek
-- v tabulce motorcycles (parametry, výbava, popisy).
--
-- Zadání majitele 2026-11-27: zkvalitnění textů pro SEO. Podklad: redakční/SEO revize blogu
-- a motorek z 2026-11-27. Texty se zobrazují v detailu motorky na webu (/katalog/<id>: tabulka
-- parametrů, „Výbava a výhody“, popis, alt texty fotek „model – barva – popisek“, JSON-LD)
-- a v aplikaci. Opravuje se jen to, co je jednoznačná chyba:
--   * pravopis a překlepy („6 ti stupňová“, „ve předu“, „Dva kouče“, „Doutaktní“, „Usb“,
--     „dlouhý cesty“, „transeuropské“, „v městě“, „řidítka“, „posez“, „vkuse“ …);
--   * velká písmena u barev („ČERVENÁ“, „BÍLÁ“, „Bílá“ → malými písmeny, jak už má třetina
--     motorek) a uprostřed hodnoty („+ Olej“, „2 Kotouče“);
--   * místo v popisu Jawy RVM 500 Adventure („z Pelhřimova“ — motorka stojí na pobočce
--     Velké Němčice, branch_id 22222222-…);
--   * nepravdivý superlativ u Royal Enfield Shotgun 650 („nejnižší sedlo v naší flotile“ —
--     Honda VTX 1800 má v katalogu 700 mm).
--
-- Převodovka se sjednocuje na tvar „6stupňová …“ (pravopisně správný, už ho má 12 motorek
-- a nabízí ho i Velín): slovník překladů parametrů na webu (motogo-web-php/lang/moto-specs/*.php,
-- klíč = česká hodnota) tento tvar zná, takže cizojazyčné stránky zůstanou přeložené. Slovní
-- tvar „šestistupňová“ by ve slovníku nebyl a na 7 jazykových verzích by zůstal česky.
--
-- Záměrně NEMĚNÍ: schéma; technická čísla (objem, výkon, hmotnost, výška sedla, nádrž,
-- rychlost, spotřeba), ceny, názvy modelů a značek, VIN, SPZ, označení paliva („Natural“,
-- „Benzín“) — všechny nalezené nesoulady jsou v seznamu otázek pro majitele; překlady (sloupec
-- translations — po nasazení ve Velínu znovu spustit překlad dotčených motorek); motorky,
-- které se v katalogu nezobrazují (status unavailable / retired); sloupce suitable_for
-- a ideal_usage (web ani aplikace je nezobrazují).
--
-- Bezpečnost: každý UPDATE míří na motorku podle id a provede se jen tehdy, když sloupec
-- stále obsahuje přesně opravované znění (hodnota parametru celá, položka výbavy právě jednou
-- v poli, věta v popisu právě jednou). Co mezitím někdo upravil ve Velínu, se přeskočí.
-- Idempotentní — 2. běh nezmění nic. Bez BEGIN/COMMIT: deploy-sql.yml pouští soubor v jedné
-- transakci (ON_ERROR_STOP). Triggery: motorcycles_updated_at nastaví updated_at,
-- trg_sync_moto_to_assets jako při každé úpravě motorky zapíše název/stav do
-- acc_long_term_assets (značka, model, rok ani status se nemění → stejné hodnoty).
-- Web má data motorek v cache 30 minut (změna textu cache nemaže) — projeví se do půl hodiny.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) Parametry (tabulka „Technické parametry“) — jeden UPDATE na sloupec, řádek = motorka
-- ─────────────────────────────────────────────────────────────────────────────
-- Převodovka: „6 ti / 6ti / 6sti stupňová“ → „6stupňová“ (číslice se píše dohromady s příponou).
UPDATE public.motorcycles m
   SET transmission = v.new_val
  FROM (VALUES
         ('a0000001-0000-0000-0000-000000000001'::uuid, '6 ti stupňová manuální', '6stupňová manuální'),  -- BMW R 1200 GS Adventure
         ('8468ca34-efec-486a-ab6f-deea0ad50946'::uuid, '6ti stupňová manuální', '6stupňová manuální'),   -- Benelli TRK 502 X
         ('a0000001-0000-0000-0000-000000000003'::uuid, '6ti stupňová manuální', '6stupňová manuální'),   -- Benelli TRK 702 X
         ('e3123fff-5ecc-486b-9481-fb5eebc11fdf'::uuid, '6ti stupňová manuální', '6stupňová manuální'),   -- Honda CRF 1000 Africa Twin
         ('f772c7f5-6be7-4395-b97b-007552c6e6c4'::uuid, '6ti stupňová', '6stupňová'),                     -- Voge 500 DSX
         ('b850929a-37da-4b87-86a8-9b2fba7b3316'::uuid, '6sti stupňová + QS', '6stupňová + QS')           -- Husqvarna 701 SM
       ) AS v(id, old_val, new_val)
 WHERE m.id = v.id
   AND m.transmission = v.old_val;

-- Brzdy: překlepy „ve předu“ → „vepředu“, „kouče“ → „kotouče“, velké K uprostřed hodnoty.
UPDATE public.motorcycles m
   SET brake_type = v.new_val
  FROM (VALUES
         ('a0000001-0000-0000-0000-000000000008'::uuid, 'Dva kotouče ve předu 1 kotouč vzadu', 'Dva kotouče vepředu 1 kotouč vzadu'),  -- Yamaha MT-09 Street Rally
         ('4570ce0f-a8e1-4981-bf69-20eed8a45323'::uuid, 'Dva kouče vepředu 1 kotouč vzadu', 'Dva kotouče vepředu 1 kotouč vzadu'),     -- XL 1000 VARADERO
         ('e3123fff-5ecc-486b-9481-fb5eebc11fdf'::uuid, '2 Kotouče vepředu 1 kotouč vzadu', '2 kotouče vepředu 1 kotouč vzadu')        -- Honda CRF 1000 Africa Twin
       ) AS v(id, old_val, new_val)
 WHERE m.id = v.id
   AND m.brake_type = v.old_val;

-- Typ motoru: překlep „Doutaktní“ → „Dvoutaktní“.
UPDATE public.motorcycles m
   SET engine_type = v.new_val
  FROM (VALUES
         ('6071c49d-8019-415e-a9d9-ef23c7ec88a6'::uuid, 'Doutaktní jednoválec', 'Dvoutaktní jednoválec')   -- KTM SX 50 Replica
       ) AS v(id, old_val, new_val)
 WHERE m.id = v.id
   AND m.engine_type = v.old_val;

-- Palivo: velké písmeno uprostřed hodnoty („+ Olej“ → „+ olej“). Označení paliva se nemění.
UPDATE public.motorcycles m
   SET fuel_type = v.new_val
  FROM (VALUES
         ('780e13b3-f07c-4da4-98ab-878e7b6f4775'::uuid, 'Natural 95 + Olej 1:50', 'Natural 95 + olej 1:50')   -- Husqvarna TC 65
       ) AS v(id, old_val, new_val)
 WHERE m.id = v.id
   AND m.fuel_type = v.old_val;

-- Barva: malými písmeny (není to věta ani vlastní jméno; „ČERVENÁ“ a „BÍLÁ“ byly verzálkami).
-- Barva je i v alt textech fotek („model – barva – popisek“). 8 motorek už malá písmena má.
UPDATE public.motorcycles m
   SET color = v.new_val
  FROM (VALUES
         ('edabe801-841f-457e-9fc8-944370ec4002'::uuid, 'Černá', 'černá'),                -- Aprilia SR GT 125
         ('a0000001-0000-0000-0000-000000000001'::uuid, 'Bílá', 'bílá'),                  -- BMW R 1200 GS Adventure
         ('8468ca34-efec-486a-ab6f-deea0ad50946'::uuid, 'Bílá', 'bílá'),                  -- Benelli TRK 502 X
         ('a0000001-0000-0000-0000-000000000003'::uuid, 'Zelená', 'zelená'),              -- Benelli TRK 702 X
         ('a0000001-0000-0000-0000-000000000010'::uuid, 'ČERVENÁ', 'červená'),            -- Ducati Multistrada 1260 s
         ('e3123fff-5ecc-486b-9481-fb5eebc11fdf'::uuid, 'BÍLÁ', 'bílá'),                  -- Honda CRF 1000 Africa Twin
         ('6027e245-07db-44f9-9ed2-0841e1ac6e9c'::uuid, 'Šedá', 'šedá'),                  -- Honda VTX 1800
         ('a0000001-0000-0000-0000-000000000002'::uuid, 'Černá', 'černá'),                -- Jawa RVM 500 Adventure
         ('6071c49d-8019-415e-a9d9-ef23c7ec88a6'::uuid, 'Oranžová', 'oranžová'),          -- KTM SX 50 Replica
         ('a0000001-0000-0000-0000-000000000007'::uuid, 'Zelená', 'zelená'),              -- Kawasaki Z 900
         ('a0000001-0000-0000-0000-000000000014'::uuid, 'Bílá', 'bílá'),                  -- Triumph Tiger 1200 Explorer
         ('f772c7f5-6be7-4395-b97b-007552c6e6c4'::uuid, 'Černá', 'černá'),                -- Voge 500 DSX
         ('4570ce0f-a8e1-4981-bf69-20eed8a45323'::uuid, 'Světle modrá', 'světle modrá'),  -- XL 1000 VARADERO
         ('a0000001-0000-0000-0000-000000000008'::uuid, 'Bílá', 'bílá'),                  -- Yamaha MT-09 Street Rally
         ('a0000001-0000-0000-0000-000000000006'::uuid, 'Černá', 'černá'),                -- Yamaha XT660 X
         ('a0000001-0000-0000-0000-000000000009'::uuid, 'Modrá', 'modrá')                 -- Yamaha XTZ 1200 Super Ténéré
       ) AS v(id, old_val, new_val)
 WHERE m.id = v.id
   AND m.color = v.old_val;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) Výbava a výhody (features) — položka pole, jen když je v poli právě jednou
-- ─────────────────────────────────────────────────────────────────────────────
-- Jawa RVM 500 Adventure — zkratka USB velkými písmeny
UPDATE public.motorcycles m
   SET features = array_replace(m.features, x.old, x.new)
  FROM (VALUES ($old$Usb nabíjení$old$,
               $new$USB nabíjení$new$)) AS x(old, new)
 WHERE m.id = 'a0000001-0000-0000-0000-000000000002'
   AND cardinality(array_positions(m.features, x.old)) = 1;

-- Triumph Tiger 1200 Explorer — zkratka USB velkými písmeny
UPDATE public.motorcycles m
   SET features = array_replace(m.features, x.old, x.new)
  FROM (VALUES ($old$Usb nabíjení$old$,
               $new$USB nabíjení$new$)) AS x(old, new)
 WHERE m.id = 'a0000001-0000-0000-0000-000000000014'
   AND cardinality(array_positions(m.features, x.old)) = 1;

-- Triumph Tiger 1200 Explorer — dvojitá mezera
UPDATE public.motorcycles m
   SET features = array_replace(m.features, x.old, x.new)
  FROM (VALUES ($old$Bohatá elektronika —  ABS, kontrola trakce, tempomat$old$,
               $new$Bohatá elektronika — ABS, kontrola trakce, tempomat$new$)) AS x(old, new)
 WHERE m.id = 'a0000001-0000-0000-0000-000000000014'
   AND cardinality(array_positions(m.features, x.old)) = 1;

-- Honda VTX 1800 — „posez“ → „posed“ (jako ve všech ostatních textech)
UPDATE public.motorcycles m
   SET features = array_replace(m.features, x.old, x.new)
  FROM (VALUES ($old$Pohodlný posez pro jezdce i spolujezdce$old$,
               $new$Pohodlný posed pro jezdce i spolujezdce$new$)) AS x(old, new)
 WHERE m.id = '6027e245-07db-44f9-9ed2-0841e1ac6e9c'
   AND cardinality(array_positions(m.features, x.old)) = 1;

-- Kawasaki Z 900 — „v městě“ → „ve městě“
UPDATE public.motorcycles m
   SET features = array_replace(m.features, x.old, x.new)
  FROM (VALUES ($old$Vzpřímený, ale sportovní posed — pohoda i v městě, dynamika v zatáčkách$old$,
               $new$Vzpřímený, ale sportovní posed — pohoda i ve městě, dynamika v zatáčkách$new$)) AS x(old, new)
 WHERE m.id = 'a0000001-0000-0000-0000-000000000007'
   AND cardinality(array_positions(m.features, x.old)) = 1;

-- Yamaha MT-09 Street Rally — „řidítky“ → „řídítky“, „v městě“ → „ve městě“
UPDATE public.motorcycles m
   SET features = array_replace(m.features, x.old, x.new)
  FROM (VALUES ($old$Vzpřímený posed s vyššími řidítky — pohoda i komfort v městě$old$,
               $new$Vzpřímený posed s vyššími řídítky — pohoda i komfort ve městě$new$)) AS x(old, new)
 WHERE m.id = 'a0000001-0000-0000-0000-000000000008'
   AND cardinality(array_positions(m.features, x.old)) = 1;

-- Yamaha MT-09 Street Rally — „řidítka“ → „řídítka“ (popis téže motorky má správně „řídítka“)
UPDATE public.motorcycles m
   SET features = array_replace(m.features, x.old, x.new)
  FROM (VALUES ($old$Rally vzhled „Street Rally" balíčku — vyšší řidítka, maska světla, chrániče$old$,
               $new$Rally vzhled „Street Rally" balíčku — vyšší řídítka, maska světla, chrániče$new$)) AS x(old, new)
 WHERE m.id = 'a0000001-0000-0000-0000-000000000008'
   AND cardinality(array_positions(m.features, x.old)) = 1;

-- Honda CRF 1000 Africa Twin — „řidítka“ → „řídítka“
UPDATE public.motorcycles m
   SET features = array_replace(m.features, x.old, x.new)
  FROM (VALUES ($old$Vzpřímený posed a široká řidítka — pohodlí i kontrola na celý den$old$,
               $new$Vzpřímený posed a široká řídítka — pohodlí i kontrola na celý den$new$)) AS x(old, new)
 WHERE m.id = 'e3123fff-5ecc-486b-9481-fb5eebc11fdf'
   AND cardinality(array_positions(m.features, x.old)) = 1;

-- XL 1000 VARADERO — „řidítky“ → „řídítky“
UPDATE public.motorcycles m
   SET features = array_replace(m.features, x.old, x.new)
  FROM (VALUES ($old$Vzpřímený posed se širokými řidítky — komfort i kontrola$old$,
               $new$Vzpřímený posed se širokými řídítky — komfort i kontrola$new$)) AS x(old, new)
 WHERE m.id = '4570ce0f-a8e1-4981-bf69-20eed8a45323'
   AND cardinality(array_positions(m.features, x.old)) = 1;

-- Aprilia SR GT 125 — spojovník místo pomlčky (ostatní položky mají „—“)
UPDATE public.motorcycles m
   SET features = array_replace(m.features, x.old, x.new)
  FROM (VALUES ($old$Systém CBS - kombinovaný brzdový systém$old$,
               $new$Systém CBS — kombinovaný brzdový systém$new$)) AS x(old, new)
 WHERE m.id = 'edabe801-841f-457e-9fc8-944370ec4002'
   AND cardinality(array_positions(m.features, x.old)) = 1;

-- Royal Enfield Shotgun 650 — věcná oprava: Honda VTX 1800 má v katalogu sedlo 700 mm, Kawasaki Z 900 také 795 mm (číslo 795 mm beze změny)
UPDATE public.motorcycles m
   SET features = array_replace(m.features, x.old, x.new)
  FROM (VALUES ($old$Nízké sedlo 795 mm — nejnižší v naší flotile, doslova pro každého$old$,
               $new$Nízké sedlo 795 mm — jedno z nejnižších v naší flotile, doslova pro každého$new$)) AS x(old, new)
 WHERE m.id = 'c9617cbe-c6d9-441d-9433-1a11e66fa357'
   AND cardinality(array_positions(m.features, x.old)) = 1;
