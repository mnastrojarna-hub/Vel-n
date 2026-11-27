-- =============================================================================
-- 20261128b2_seo_motorcycles_fixes_2.sql (část 2/2)
-- 2026-11-28, schváleno majitelem 2026-11-27. Části 1–2 vznikly rozdělením jednoho souboru po celých sekcích
-- (každá sekce mění jiné sloupce). Tato část: 3) popisy (description).
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
-- 3) Popisy (description, HTML) — věta jen když je v popisu právě jednou
-- ─────────────────────────────────────────────────────────────────────────────
-- Jawa RVM 500 Adventure — místo: motorka stojí na pobočce Velké Němčice u Brna (branch_id 22222222-…), ne u Pelhřimova;
-- Vídeň je odtud ~100 minut jízdy (OSRM, data/landing-trust.php), tam i zpět tedy bezpečně v dojezdu přes 500 km
UPDATE public.motorcycles m
   SET description = replace(m.description, x.old, x.new)
  FROM (VALUES ($old$z Pelhřimova klidně do Vídně bez zastávek u pumpy$old$,
               $new$z Velkých Němčic do Vídně a zase zpátky bez zastávky u pumpy$new$)) AS x(old, new)
 WHERE m.id = 'a0000001-0000-0000-0000-000000000002'
   AND length(m.description) - length(replace(m.description, x.old, '')) = length(x.old);

-- Triumph Tiger 1200 Explorer — „dlouhý cesty“ → „dlouhé cesty“
UPDATE public.motorcycles m
   SET description = replace(m.description, x.old, x.new)
  FROM (VALUES ($old$<strong>dlouhý cesty</strong>$old$,
               $new$<strong>dlouhé cesty</strong>$new$)) AS x(old, new)
 WHERE m.id = 'a0000001-0000-0000-0000-000000000014'
   AND length(m.description) - length(replace(m.description, x.old, '')) = length(x.old);

-- Triumph Tiger 1200 Explorer — „transeuropské“ → „transevropské“
UPDATE public.motorcycles m
   SET description = replace(m.description, x.old, x.new)
  FROM (VALUES ($old$transeuropské tahy$old$,
               $new$transevropské tahy$new$)) AS x(old, new)
 WHERE m.id = 'a0000001-0000-0000-0000-000000000014'
   AND length(m.description) - length(replace(m.description, x.old, '')) = length(x.old);

-- Benelli TRK 702 X — „mezi cestovkou a pravým enduro“ → „… pravým endurem“
UPDATE public.motorcycles m
   SET description = replace(m.description, x.old, x.new)
  FROM (VALUES ($old$pravým enduro</span>$old$,
               $new$pravým endurem</span>$new$)) AS x(old, new)
 WHERE m.id = 'a0000001-0000-0000-0000-000000000003'
   AND length(m.description) - length(replace(m.description, x.old, '')) = length(x.old);

-- Benelli TRK 702 X — „vkuse“ → „v kuse“
UPDATE public.motorcycles m
   SET description = replace(m.description, x.old, x.new)
  FROM (VALUES ($old$přes stovky km vkuse$old$,
               $new$přes stovky km v kuse$new$)) AS x(old, new)
 WHERE m.id = 'a0000001-0000-0000-0000-000000000003'
   AND length(m.description) - length(replace(m.description, x.old, '')) = length(x.old);

-- Suzuki DL 650 V-strom — velké „Ti“ uprostřed věty
UPDATE public.motorcycles m
   SET description = replace(m.description, x.old, x.new)
  FROM (VALUES ($old$anatomické sedlo Ti zase šetří$old$,
               $new$anatomické sedlo ti zase šetří$new$)) AS x(old, new)
 WHERE m.id = '8f554a38-c3b3-4337-9d6a-899ea8e54b37'
   AND length(m.description) - length(replace(m.description, x.old, '')) = length(x.old);

-- Husqvarna TC 65 — shoda: „tvoji ratolesti naučí …, co potřebují“ → „tvoji ratolest naučí …, co potřebuje“ (dál v textu „děcko, které sní“)
UPDATE public.motorcycles m
   SET description = replace(m.description, x.old, x.new)
  FROM (VALUES ($old$který tvoji ratolesti naučí všechno, co potřebují vědět$old$,
               $new$který tvoji ratolest naučí všechno, co potřebuje vědět$new$)) AS x(old, new)
 WHERE m.id = '780e13b3-f07c-4da4-98ab-878e7b6f4775'
   AND length(m.description) - length(replace(m.description, x.old, '')) = length(x.old);

-- Husqvarna TC 65 — chybějící „jako“
UPDATE public.motorcycles m
   SET description = replace(m.description, x.old, x.new)
  FROM (VALUES ($old$že bude jednou jezdit skuteční závodníci$old$,
               $new$že bude jednou jezdit jako skuteční závodníci$new$)) AS x(old, new)
 WHERE m.id = '780e13b3-f07c-4da4-98ab-878e7b6f4775'
   AND length(m.description) - length(replace(m.description, x.old, '')) = length(x.old);

-- Aprilia SR GT 125 — shoda: „s delším projížďkou“ → „s delší projížďkou“
UPDATE public.motorcycles m
   SET description = replace(m.description, x.old, x.new)
  FROM (VALUES ($old$i s delším projížďkou$old$,
               $new$i s delší projížďkou$new$)) AS x(old, new)
 WHERE m.id = 'edabe801-841f-457e-9fc8-944370ec4002'
   AND length(m.description) - length(replace(m.description, x.old, '')) = length(x.old);

-- Kawasaki Z 900 — spojovníky místo pomlček (stejná věta v ostatních popisech má „—“)
UPDATE public.motorcycles m
   SET description = replace(m.description, x.old, x.new)
  FROM (VALUES ($old$patří do zatáček </span>- víkendové výjezdy a horské serpentiny - to je její.$old$,
               $new$patří do zatáček </span>— víkendové výjezdy a horské serpentiny — to je její.$new$)) AS x(old, new)
 WHERE m.id = 'a0000001-0000-0000-0000-000000000007'
   AND length(m.description) - length(replace(m.description, x.old, '')) = length(x.old);
