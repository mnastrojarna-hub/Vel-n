-- =============================================================================
-- Univerzální texty k dokladům (obě pobočky) v mailech při potvrzení rezervace
-- a v postupech na webu — zadání majitele 2026-10-04:
--   „Pokud je motorka na samoobslužné pobočce, je nezbytně nutné doklady nahrát
--   předem — jinak se dovnitř nedostanete a nepřijde mail s kódy. Na obslužné
--   pobočce o nahrání přesto žádáme; pokud je nenahrajete, zkontrolujeme je na
--   místě. Všechny maily při potvrzení rezervace musí být napsané univerzálně.“
-- Migrace: 20261004g_universal_docs_pickup_texts.sql (DATA — bez změn schématu)
--
-- Šablony z Velína se NEPŘEPISUJÍ — jen se v nich cíleně nahradí JEDNA známá
-- věta (pokyn majitele: „jenom doplň větu nebo proměnnou“). Řádek, ve kterém
-- věta není (majitel text přepsal), zůstane netknutý a vypíše se NOTICE.
--
-- 1) email_templates `booking_reserved` + `web_booking_reserved` (potvrzení
--    rezervace): odstavec „Na místě společně provedeme kontrolu dokladů, předání
--    motocyklu … a podepíšeme Předávací protokol.“ (krátká i dlouhá varianta
--    „(kterou si budete moci vyzkoušet) … Vše vám rádi vysvětlíme – předání je
--    rychlé a zabere jen pár minut.“) platil JEN pro obslužnou pobočku →
--    univerzální odstavec: doklady nahrát předem, kódy až po ověření; samoobsluha
--    = nezbytné (bez dokladů kódy ani vstup), obslužná = žádáme, jinak kontrola
--    při převzetí na místě.
-- 2) email_templates `booking_missing_docs` + `web_booking_missing_docs`
--    (připomínka po platbě): „…doklady bychom pak museli zkontrolovat osobně až
--    na pobočce.“ → univerzální věta (na samoobsluze se bez dokladů dovnitř
--    nedostanete).
-- 3) U změněných šablon se vynuluje cache překladů `body_translations` →
--    send-booking-email si tělo přeloží znovu (jako 20260718).
-- 4) cms_variables (Velín → Web CMS → Texty webu), JEN pokud řádek existuje a
--    obsahuje původní text: krok 1 postupu obou poboček (`web.pobocky.branches.0/1
--    .steps`) + nápověda kroku dokladů v pokladně (`web.layout.confirm.paydocs
--    .step2`). Překlady (`translations`) se nemění — obnoví se při uložení ve
--    Velíně (auto-překlad). Výchozí texty v kódu (web, Velín, appka) a vestavěné
--    fallbacky edge funkce mění tentýž commit.
--
-- Idempotentní: po nahrazení se vzor už nevyskytuje → opakování nic nezmění.
-- =============================================================================

DO $$
DECLARE
  r record;
  v_rx  constant text := 'Na místě společně provedeme kontrolu dokladů, předání motocyklu i případné zapůjčené výbavy( \(kterou si budete moci vyzkoušet\))? a podepíšeme Předávací protokol\.( Vše vám rádi vysvětlíme [–—-] předání je rychlé a zabere jen pár minut\.)?';
  v_new constant text := 'Doklady (občanský průkaz nebo cestovní pas a řidičský průkaz) prosím nahrajte předem v aplikaci nebo na webu — přístupové kódy vám pošleme až po jejich ověření. Na samoobslužné pobočce je nahrání dokladů předem nezbytné: bez ověřených dokladů kódy nevydáme a na pobočku se nedostanete; motorku i výbavu si převezmete sami pomocí kódů a Předávací protokol podepíšete na dotykovém displeji. Na obslužné pobočce vás o nahrání dokladů předem také žádáme — pokud je nenahrajete, zkontrolujeme je při převzetí na místě, kde vám předáme motorku i výbavu a společně podepíšeme Předávací protokol.';
  v_old_missing constant text := 'Bez ověření dokladů vám nemůžeme poslat přístupové kódy předem — doklady bychom pak museli zkontrolovat osobně až na pobočce.';
  v_new_missing constant text := 'Bez ověření dokladů vám přístupové kódy nemůžeme poslat — na samoobslužné pobočce se bez nich dovnitř nedostanete. Na obslužné pobočce bychom je pak museli zkontrolovat při převzetí na místě.';
BEGIN
  -- 1) potvrzení rezervace (app + web šablona)
  FOR r IN SELECT slug, body_html FROM public.email_templates WHERE slug IN ('booking_reserved', 'web_booking_reserved') LOOP
    IF r.body_html ~ v_rx THEN
      UPDATE public.email_templates
         SET body_html = regexp_replace(body_html, v_rx, v_new),
             body_translations = '{}'::jsonb,
             updated_at = now()
       WHERE slug = r.slug;
      RAISE NOTICE '20261004g: % — odstavec o převzetí nahrazen univerzálním', r.slug;
    ELSIF r.body_html LIKE '%' || left(v_new, 60) || '%' THEN
      RAISE NOTICE '20261004g: % — už obsahuje univerzální odstavec', r.slug;
    ELSE
      RAISE NOTICE '20261004g: % — věta „Na místě společně provedeme kontrolu dokladů…“ nenalezena, šablona NEZMĚNĚNA (doplňte větu ve Velínu ručně)', r.slug;
    END IF;
  END LOOP;

  -- 2) připomínka po platbě
  FOR r IN SELECT slug, body_html FROM public.email_templates WHERE slug IN ('booking_missing_docs', 'web_booking_missing_docs') LOOP
    IF position(v_old_missing IN r.body_html) > 0 THEN
      UPDATE public.email_templates
         SET body_html = replace(body_html, v_old_missing, v_new_missing),
             body_translations = '{}'::jsonb,
             updated_at = now()
       WHERE slug = r.slug;
      RAISE NOTICE '20261004g: % — věta o kontrole na pobočce nahrazena univerzální', r.slug;
    END IF;
  END LOOP;
END $$;

-- 4) Web CMS (jen existující řádky s původním textem; value = jsonb string)
DO $$
DECLARE
  v_pairs constant text[][] := ARRAY[
    ['web.pobocky.branches.0.steps',
     '1. Rezervujete a zaplatíte online (web nebo aplikace).<br>2.',
     '1. Rezervujete a zaplatíte online (web nebo aplikace) a nahrajete doklady (OP/pas + ŘP) — žádáme o to i na obslužné pobočce; pokud je nenahrajete, zkontrolujeme je při převzetí na místě.<br>2.'],
    ['web.pobocky.branches.1.steps',
     '1. Rezervujete a zaplatíte online, zvolíte čas vyzvednutí a doplníte doklady. V aplikaci, e-mailu a SMS pak dostanete kódy v pořadí, v jakém je budete zadávat:',
     '1. Rezervujete a zaplatíte online, zvolíte čas vyzvednutí a nahrajete doklady (OP/pas + ŘP) — na samoobslužné pobočce je to nezbytné: bez ověřených dokladů kódy nedostanete a na pobočku se nedostanete. Po ověření dokladů dostanete v aplikaci, e-mailu a SMS kódy v pořadí, v jakém je budete zadávat:'],
    ['web.layout.confirm.paydocs.step2',
     'Nahraj fotky dokladů (OP/pas + ŘP). Foto je dobrovolné — bez ověření ti ale nepošleme přístupové kódy předem a doklady zkontrolujeme až na pobočce.',
     'Nahraj fotky dokladů (OP/pas + ŘP). Bez jejich ověření ti nepošleme přístupové kódy — na samoobslužné pobočce je nahrání nezbytné, bez kódů se dovnitř nedostaneš. Na obslužné pobočce doklady případně zkontrolujeme při převzetí na místě.']
  ];
  i integer;
  v_val text;
BEGIN
  FOR i IN 1..array_length(v_pairs, 1) LOOP
    SELECT value #>> '{}' INTO v_val FROM public.cms_variables
     WHERE key = v_pairs[i][1] AND jsonb_typeof(value) = 'string';
    IF v_val IS NOT NULL AND position(v_pairs[i][2] IN v_val) > 0 THEN
      UPDATE public.cms_variables
         SET value = to_jsonb(replace(v_val, v_pairs[i][2], v_pairs[i][3])),
             updated_at = now()
       WHERE key = v_pairs[i][1];
      RAISE NOTICE '20261004g: cms_variables % — doplněna věta o dokladech', v_pairs[i][1];
    END IF;
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
