-- =============================================================================
-- 20261016c_qa_translation_fixes.sql — NÁVRH ke schválení (QA brána 2026-10-16), neaplikováno
-- Opravy strojových překladů (jen překlady; čeština beze změny kromě adresy v jedné FAQ):
--   • pokladna: en „Cash register“ → „Checkout“, es „Caja“ → „Pago“ (= lang/en.php, es.php);
--     osobní vyzvednutí es/pl „Pelhřimově“; nl menu „Motorscooter catalogus“ → „Motorcatalogus“;
--   • české pády v překladech: fr „en Vysočině“, nl „op Vysočině“, de „in Vysočině/Pelhřimově“,
--     pl „na Vysočině / na Wysoczinie / w Pelhřimově“, pl kontakt „Siedzimy w Pelhřimově“, „u Urzędu Miasta“;
--   • zkratka „ČR“ v de/nl/pl/uk textech → Tschechien / Tsjechië / Czechy / Чехія;
--   • pl „motorower“ (= moped) místo „motocykl“ (9 textů webu, 1 FAQ, 1 popis motorky);
--   • nl neexistující slovo „motorfietsverhuuring“ → „motorverhuur“ (6 textů);
--   • pl FAQ palivo „koszty wyłączenia paliwa“ → „koszty wypompowania paliwa“;
--   • FAQ „Kde probíhá vyzvednutí a vrácení?“ (e7079920, všech 8 jazyků): „Mezná 9, 393 01 Mezná (u Pelhřimova)“
--     → „Mezná 9, 393 01 Pelhřimov“ (jednotná adresa jako smlouvy, config.php a e-maily).
-- Klíče web.postup.* a web.jak_pujcit_cena.gear.services.* vynechány (přepisuje je 20261016d).
--
-- Bezpečnost: každá náhrada se provede jen když text obsahuje přesně dané znění (režim eq = celý text);
-- co mezitím někdo ve Velínu přepsal, se nezmění (NOTICE „beze změny“). Nová znění neobsahují stará,
-- takže 2. běh nic nezmění. Bez BEGIN/COMMIT (deploy-sql.yml = 1 transakce na soubor).
-- Pořadí: konkrétní náhrady před obecnými (např. „w dowolnym miejscu w ČR“ před „w ČR“).
-- =============================================================================
DO $$
DECLARE
  r record;
  n integer;
  total integer := 0;
  nomatch integer := 0;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    (1, 'cms_variables', $q$web.layout.checkout.title$q$, 'en', 'value', 'eq', $q$Cash register$q$, $q$Checkout$q$),
    (2, 'cms_variables', $q$web.layout.checkout.title$q$, 'es', 'value', 'eq', $q$Caja$q$, $q$Pago$q$),
    (3, 'cms_variables', $q$web.layout.checkout.shipping.pickup$q$, 'es', 'value', 'eq', $q$Recogida personal en Pelhřimově$q$, $q$Recogida personal en Pelhřimov$q$),
    (4, 'cms_variables', $q$web.layout.checkout.shipping.pickup$q$, 'pl', 'value', 'eq', $q$Osobisty odbiór w Pelhřimově$q$, $q$Odbiór osobisty w Pelhřimovie$q$),
    (5, 'cms_variables', $q$web.layout.menu.catalog$q$, 'nl', 'value', 'eq', $q$Motorscooter catalogus$q$, $q$Motorcatalogus$q$),
    (6, 'cms_variables', $q$web.kontakt.seo.description$q$, 'pl', 'value', 'sub', $q$Siedzimy w Pelhřimově$q$, $q$Mamy siedzibę w Mezná koło Pelhřimova$q$),
    (7, 'cms_variables', $q$web.kontakt.reg$q$, 'pl', 'value', 'sub', $q$u Urzędu Miasta w Pelhřimově$q$, $q$w Urzędzie Miasta w Pelhřimovie$q$),
    (8, 'cms_variables', $q$*$q$, 'pl', 'value', 'sub', $q$w Pelhřimově$q$, $q$w Pelhřimovie$q$),
    (9, 'cms_variables', $q$*$q$, 'pl', 'value', 'sub', $q$na Wysoczinie$q$, $q$na Wysoczynie$q$),
    (10, 'cms_variables', $q$*$q$, 'pl', 'value', 'sub', $q$na Vysočině$q$, $q$na Wysoczynie$q$),
    (11, 'cms_variables', $q$*$q$, 'fr', 'value', 'sub', $q$en Vysočině$q$, $q$en Vysočina$q$),
    (12, 'cms_variables', $q$*$q$, 'nl', 'value', 'sub', $q$op Vysočině$q$, $q$in de regio Vysočina$q$),
    (13, 'cms_variables', $q$*$q$, 'de', 'value', 'sub', $q$in Vysočině$q$, $q$in der Region Vysočina$q$),
    (14, 'cms_variables', $q$*$q$, 'de', 'value', 'sub', $q$in Pelhřimově$q$, $q$in Pelhřimov$q$),
    (15, 'cms_variables', $q$*$q$, 'nl', 'value', 'sub', $q$motorfietsverhuuring$q$, $q$motorverhuur$q$),
    (16, 'cms_variables', $q$*$q$, 'es', 'value', 'sub', $q$en Pelhřimově$q$, $q$en Pelhřimov$q$),
    (17, 'cms_variables', $q$*$q$, 'de', 'value', 'sub', $q$überall in der ČR$q$, $q$überall in Tschechien$q$),
    (18, 'cms_variables', $q$*$q$, 'de', 'value', 'sub', $q$in der gesamten ČR$q$, $q$in ganz Tschechien$q$),
    (19, 'cms_variables', $q$*$q$, 'de', 'value', 'sub', $q$innerhalb der ČR$q$, $q$innerhalb Tschechiens$q$),
    (20, 'cms_variables', $q$*$q$, 'de', 'value', 'sub', $q$in der ČR$q$, $q$in Tschechien$q$),
    (21, 'cms_variables', $q$*$q$, 'nl', 'value', 'sub', $q$overal in ČR$q$, $q$overal in Tsjechië$q$),
    (22, 'cms_variables', $q$*$q$, 'nl', 'value', 'sub', $q$in heel de ČR$q$, $q$in heel Tsjechië$q$),
    (23, 'cms_variables', $q$*$q$, 'nl', 'value', 'sub', $q$in de ČR$q$, $q$in Tsjechië$q$),
    (24, 'cms_variables', $q$*$q$, 'pl', 'value', 'sub', $q$w dowolnym miejscu w ČR$q$, $q$w dowolnym miejscu w Czechach$q$),
    (25, 'cms_variables', $q$*$q$, 'pl', 'value', 'sub', $q$w dowolne miejsce w ČR$q$, $q$w dowolne miejsce w Czechach$q$),
    (26, 'cms_variables', $q$*$q$, 'pl', 'value', 'sub', $q$w całej ČR$q$, $q$w całych Czechach$q$),
    (27, 'cms_variables', $q$*$q$, 'pl', 'value', 'sub', $q$gdziekolwiek w ČR$q$, $q$gdziekolwiek w Czechach$q$),
    (28, 'cms_variables', $q$*$q$, 'pl', 'value', 'sub', $q$na terenie całej ČR$q$, $q$na terenie całych Czech$q$),
    (29, 'cms_variables', $q$*$q$, 'pl', 'value', 'sub', $q$na terenie ČR$q$, $q$na terenie Czech$q$),
    (30, 'cms_variables', $q$*$q$, 'pl', 'value', 'sub', $q$Policji ČR$q$, $q$czeskiej policji$q$),
    (31, 'cms_variables', $q$*$q$, 'pl', 'value', 'sub', $q$w ČR$q$, $q$w Czechach$q$),
    (32, 'cms_variables', $q$*$q$, 'pl', 'value', 'sub', $q$po ČR i zagranicą$q$, $q$po Czechach i za granicą$q$),
    (33, 'cms_variables', $q$*$q$, 'uk', 'value', 'sub', $q$по всій ČR$q$, $q$по всій Чехії$q$),
    (34, 'cms_variables', $q$web.jak_pujcit_postup.process.steps.3.text$q$, 'pl', 'value', 'sub', $q$odbierzesz motorower, lub kiedy go dostarczymy$q$, $q$odbierzesz motocykl lub kiedy go dostarczymy$q$),
    (35, 'cms_variables', $q$web.layout.editRez.moto.help$q$, 'pl', 'value', 'sub', $q$Wybierz inną motorower$q$, $q$Wybierz inny motocykl$q$),
    (36, 'cms_variables', $q$web.layout.editRez.moto.intro$q$, 'pl', 'value', 'sub', $q$Wybierz inną motorower$q$, $q$Wybierz inny motocykl$q$),
    (37, 'cms_variables', $q$web.mapa_stranek.outro.body1$q$, 'pl', 'value', 'sub', $q$Jak wynająć motorower$q$, $q$Jak wynająć motocykl$q$),
    (38, 'cms_variables', $q$web.oblasti.region.jihomoravsky_kraj.citiesIntro$q$, 'pl', 'value', 'sub', $q$Możemy dostarczyć motorower$q$, $q$Możemy dostarczyć motocykl$q$),
    (39, 'cms_variables', $q$web.oblasti.region.jihomoravsky_kraj.ctaTitle$q$, 'pl', 'value', 'sub', $q$Zarezerwuj motorower$q$, $q$Zarezerwuj motocykl$q$),
    (40, 'cms_variables', $q$web.oblasti.region.vysocina.ctaText$q$, 'pl', 'value', 'sub', $q$dostarczymy ci motorower$q$, $q$dostarczymy ci motocykl$q$),
    (41, 'cms_variables', $q$web.pujcovna.cta.title$q$, 'pl', 'value', 'sub', $q$Zarezerwuj motorower$q$, $q$Zarezerwuj motocykl$q$),
    (42, 'cms_variables', $q$web.pujcovna.process.steps.4.text$q$, 'pl', 'value', 'sub', $q$Motorower odbierzesz$q$, $q$Motocykl odbierzesz$q$),
    (43, 'faq_items', $q$02b6cfc8-83af-4887-8f5f-a62214f64f2a$q$, 'pl', 'answer', 'sub', $q$koszty wyłączenia paliwa$q$, $q$koszty wypompowania paliwa$q$),
    (44, 'faq_items', $q$b27221f5-dc55-4bf7-b320-c70b267c6a76$q$, 'pl', 'answer', 'sub', $q$uszkodzisz motorower$q$, $q$uszkodzisz motocykl$q$),
    (45, 'faq_items', $q$b27221f5-dc55-4bf7-b320-c70b267c6a76$q$, 'pl', 'answer', 'sub', $q$kradzieży motoroweru$q$, $q$kradzieży motocykla$q$),
    (46, 'faq_items', $q$*$q$, 'de', 'answer', 'sub', $q$in der gesamten ČR$q$, $q$in ganz Tschechien$q$),
    (47, 'faq_items', $q$*$q$, 'de', 'answer', 'sub', $q$innerhalb der ČR$q$, $q$innerhalb Tschechiens$q$),
    (48, 'faq_items', $q$*$q$, 'de', 'answer', 'sub', $q$Polizei ČR anzurufen$q$, $q$Polizei der Tschechischen Republik anzurufen$q$),
    (49, 'faq_items', $q$*$q$, 'de', 'answer', 'sub', $q$in der ČR$q$, $q$in Tschechien$q$),
    (50, 'faq_items', $q$*$q$, 'de', 'question', 'sub', $q$überall in der ČR$q$, $q$überall in Tschechien$q$),
    (51, 'faq_items', $q$*$q$, 'nl', 'answer', 'sub', $q$in heel de ČR$q$, $q$in heel Tsjechië$q$),
    (52, 'faq_items', $q$*$q$, 'pl', 'answer', 'sub', $q$w dowolnym miejscu w ČR$q$, $q$w dowolnym miejscu w Czechach$q$),
    (53, 'faq_items', $q$*$q$, 'pl', 'answer', 'sub', $q$w dowolne miejsce w ČR$q$, $q$w dowolne miejsce w Czechach$q$),
    (54, 'faq_items', $q$*$q$, 'pl', 'answer', 'sub', $q$w całej ČR$q$, $q$w całych Czechach$q$),
    (55, 'faq_items', $q$*$q$, 'pl', 'answer', 'sub', $q$gdziekolwiek w ČR$q$, $q$gdziekolwiek w Czechach$q$),
    (56, 'faq_items', $q$*$q$, 'pl', 'answer', 'sub', $q$na terenie całej ČR$q$, $q$na terenie całych Czech$q$),
    (57, 'faq_items', $q$*$q$, 'pl', 'answer', 'sub', $q$na terenie ČR$q$, $q$na terenie Czech$q$),
    (58, 'faq_items', $q$*$q$, 'pl', 'answer', 'sub', $q$Policji ČR$q$, $q$czeskiej policji$q$),
    (59, 'faq_items', $q$*$q$, 'pl', 'answer', 'sub', $q$w ČR$q$, $q$w Czechach$q$),
    (60, 'faq_items', $q$*$q$, 'pl', 'question', 'sub', $q$gdziekolwiek w ČR$q$, $q$gdziekolwiek w Czechach$q$),
    (61, 'faq_items_cs', $q$e7079920-f08c-4b08-b52a-9b8623909035$q$, 'cs', 'answer', 're', $q$Mezná 9, 393 01 Mezná \([^)]*\)$q$, $q$Mezná 9, 393 01 Pelhřimov$q$),
    (62, 'faq_items', $q$e7079920-f08c-4b08-b52a-9b8623909035$q$, 'en', 'answer', 're', $q$Mezná 9, 393 01 Mezná \([^)]*\)$q$, $q$Mezná 9, 393 01 Pelhřimov$q$),
    (63, 'faq_items', $q$e7079920-f08c-4b08-b52a-9b8623909035$q$, 'de', 'answer', 're', $q$Mezná 9, 393 01 Mezná \([^)]*\)$q$, $q$Mezná 9, 393 01 Pelhřimov$q$),
    (64, 'faq_items', $q$e7079920-f08c-4b08-b52a-9b8623909035$q$, 'es', 'answer', 're', $q$Mezná 9, 393 01 Mezná \([^)]*\)$q$, $q$Mezná 9, 393 01 Pelhřimov$q$),
    (65, 'faq_items', $q$e7079920-f08c-4b08-b52a-9b8623909035$q$, 'fr', 'answer', 're', $q$Mezná 9, 393 01 Mezná \([^)]*\)$q$, $q$Mezná 9, 393 01 Pelhřimov$q$),
    (66, 'faq_items', $q$e7079920-f08c-4b08-b52a-9b8623909035$q$, 'nl', 'answer', 're', $q$Mezná 9, 393 01 Mezná \([^)]*\)$q$, $q$Mezná 9, 393 01 Pelhřimov$q$),
    (67, 'faq_items', $q$e7079920-f08c-4b08-b52a-9b8623909035$q$, 'pl', 'answer', 're', $q$Mezná 9, 393 01 Mezná \([^)]*\)$q$, $q$Mezná 9, 393 01 Pelhřimov$q$),
    (68, 'faq_items', $q$e7079920-f08c-4b08-b52a-9b8623909035$q$, 'uk', 'answer', 're', $q$Mezná 9, 393 01 Mezná \([^)]*\)$q$, $q$Mezná 9, 393 01 Pelhřimov$q$),
    (69, 'cms_pages', $q$12-hlavnich-vyhod-motogo24$q$, 'nl', 'content', 'sub', $q$in heel de ČR$q$, $q$in heel Tsjechië$q$),
    (70, 'cms_pages', $q$12-hlavnich-vyhod-motogo24$q$, 'nl', 'content', 'sub', $q$in de ČR$q$, $q$in Tsjechië$q$),
    (71, 'motorcycles', $q$edabe801-841f-457e-9fc8-944370ec4002$q$, 'pl', 'description', 'sub', $q$prawa jazdy na motorower$q$, $q$prawa jazdy na motocykl$q$)
  ) AS v(ord, tbl, rid, lang, field, mode, old, new) ORDER BY ord LOOP
    n := 0;
    IF r.tbl = 'cms_variables' THEN
      UPDATE public.cms_variables c
         SET translations = jsonb_set(c.translations, ARRAY[r.lang, 'value'], to_jsonb(
               CASE r.mode WHEN 'eq' THEN r.new ELSE replace(c.translations -> r.lang ->> 'value', r.old, r.new) END)),
             updated_at = now()
       WHERE (c.key = r.rid OR (r.rid = '*' AND c.key NOT LIKE 'web.postup.%'
                                AND c.key NOT LIKE 'web.jak_pujcit_cena.gear.services.%'))
         AND jsonb_typeof(c.translations -> r.lang -> 'value') = 'string'
         AND CASE r.mode WHEN 'eq' THEN c.translations -> r.lang ->> 'value' = r.old
                         ELSE strpos(c.translations -> r.lang ->> 'value', r.old) > 0 END;
      GET DIAGNOSTICS n = ROW_COUNT;
    ELSIF r.tbl = 'faq_items' THEN
      UPDATE public.faq_items f
         SET translations = jsonb_set(f.translations, ARRAY[r.lang, r.field], to_jsonb(
               CASE r.mode WHEN 're' THEN regexp_replace(f.translations -> r.lang ->> r.field, r.old, r.new, 'g')
                           ELSE replace(f.translations -> r.lang ->> r.field, r.old, r.new) END))
       WHERE (f.id::text = r.rid OR r.rid = '*')
         AND jsonb_typeof(f.translations -> r.lang -> r.field) = 'string'
         AND CASE r.mode WHEN 're' THEN (f.translations -> r.lang ->> r.field) ~ r.old
                         ELSE strpos(f.translations -> r.lang ->> r.field, r.old) > 0 END;
      GET DIAGNOSTICS n = ROW_COUNT;
    ELSIF r.tbl = 'faq_items_cs' THEN
      UPDATE public.faq_items f SET answer = regexp_replace(f.answer, r.old, r.new, 'g')
       WHERE f.id::text = r.rid AND f.answer ~ r.old;
      GET DIAGNOSTICS n = ROW_COUNT;
    ELSIF r.tbl = 'cms_pages' THEN
      UPDATE public.cms_pages p
         SET translations = jsonb_set(p.translations, ARRAY[r.lang, r.field],
               to_jsonb(replace(p.translations -> r.lang ->> r.field, r.old, r.new)))
       WHERE p.slug = r.rid AND jsonb_typeof(p.translations -> r.lang -> r.field) = 'string'
         AND strpos(p.translations -> r.lang ->> r.field, r.old) > 0;
      GET DIAGNOSTICS n = ROW_COUNT;
    ELSIF r.tbl = 'motorcycles' THEN
      UPDATE public.motorcycles m
         SET translations = jsonb_set(m.translations, ARRAY[r.lang, r.field],
               to_jsonb(replace(m.translations -> r.lang ->> r.field, r.old, r.new)))
       WHERE m.id::text = r.rid AND jsonb_typeof(m.translations -> r.lang -> r.field) = 'string'
         AND strpos(m.translations -> r.lang ->> r.field, r.old) > 0;
      GET DIAGNOSTICS n = ROW_COUNT;
    END IF;
    total := total + n;
    IF n = 0 THEN
      nomatch := nomatch + 1;
      RAISE NOTICE 'qa_translation_fixes: beze změny #% % % % „%“', r.ord, r.tbl, r.rid, r.lang, left(r.old, 60);
    END IF;
  END LOOP;
  RAISE NOTICE 'qa_translation_fixes: upraveno % řádků (náhrad bez shody: %)', total, nomatch;
END $$;
