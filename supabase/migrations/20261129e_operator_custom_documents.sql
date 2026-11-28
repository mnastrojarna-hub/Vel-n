-- =============================================================================
-- 20261129e_operator_custom_documents.sql
-- Změna provozovatele (8/9): strojové PŘEKLADY tří vlastních dokumentů e-shopu (custom_documents)
--   reklamacni-rad-e-shop-motogo24, obchodni-podminky-pro-e-shop-motogo24, zasady-cookies-motogo24.
--
-- České originály těchto dokumentů jsou NAHRANÉ PDF soubory – ty SQL změnit neumí. Nové PDF
-- (prodávající = MotoGo24 s.r.o., zápis v obchodním rejstříku místo živnostenského, oba formuláře,
-- správce cookies) musí majitel nahrát ve Velínu → Dokumenty → Vlastní dokumenty a dát „Přeložit“.
-- Do té doby web ukazuje dosavadní PDF (ve všech jazycích – překlady nemají platný otisk).
--
-- Tento soubor jen odstraňuje dosavadního provozovatele z uložených překladů (de, en, es, fr, nl,
-- pl), aby v databázi nezůstal a nemohl se vrátit: název a IČO prodávajícího / správce, adresát
-- reklamačního a odstupního formuláře, „zapsán v živnostenském rejstříku“ → zápis v obchodním
-- rejstříku. Jiný text se nemění; verze dokumentu ani otisk překladu (translation_src) se nemění,
-- překlady zůstávají „zastaralé“ = nadále se nezobrazují.
-- Bezpečnost: nahrazuje se jen přesné dosavadní znění; idempotentní. Bez BEGIN/COMMIT.
-- =============================================================================
-- Schváleno majitelem 2026-11-27.

DO $$
DECLARE
  d      record;
  l      text;
  v_old  text;
  v_new  text;
  v_tr   jsonb;
  n_ch   integer := 0;
  n_left integer := 0;
  -- „zapsán(a) v živnostenském rejstříku“ → zápis v obchodním rejstříku (znění = web lang/pages_<jazyk>.php)
  c_reg constant jsonb := jsonb_build_object(
    'en', jsonb_build_array('registered in the Trade Register',
                            'registered in the Commercial Register kept by the Regional Court in České Budějovice, Section C, File 36876'),
    'de', jsonb_build_array('eingetragen im Gewerberegister',
                            'eingetragen im Handelsregister beim Kreisgericht in České Budějovice, Abteilung C, Einlage 36876'),
    'es', jsonb_build_array('inscrita en el Registro de Actividades Comerciales',
                            'inscrita en el Registro Mercantil del Tribunal Regional de České Budějovice, sección C, inscripción 36876'),
    'fr', jsonb_build_array('immatriculée au registre du commerce (živnostenský rejstřík)',
                            'immatriculée au registre du commerce tenu par le tribunal régional de České Budějovice, section C, dossier 36876'),
    'nl', jsonb_build_array('ingeschreven in het handelsregister<br>',
                            'ingeschreven in het handelsregister van de regionale rechtbank in České Budějovice, afdeling C, dossier 36876<br>'),
    'pl', jsonb_build_array('wpisana do rejestru działalności gospodarczej',
                            'wpisana do rejestru handlowego prowadzonego przez Sąd Okręgowy w Czeskich Budziejowicach, dział C, pozycja 36876'));
BEGIN
  FOR d IN
    SELECT id, slug, translations FROM public.custom_documents
     WHERE slug IN ('reklamacni-rad-e-shop-motogo24', 'obchodni-podminky-pro-e-shop-motogo24', 'zasady-cookies-motogo24')
     FOR UPDATE
  LOOP
    v_tr := coalesce(d.translations, '{}'::jsonb);
    FOR l IN SELECT k FROM jsonb_object_keys(v_tr) AS k LOOP
      CONTINUE WHEN jsonb_typeof(v_tr -> l) <> 'object' OR jsonb_typeof(v_tr #> ARRAY[l, 'content_html']) <> 'string';
      v_old := v_tr #>> ARRAY[l, 'content_html'];
      v_new := replace(replace(v_old,
                 'Bc. Petra Semorádová, IČO 21874263', 'MotoGo24 s.r.o., IČO 29909864'),
                 'Bc. Petra Semorádová, Mezná 9, 393 01 Mezná', 'MotoGo24 s.r.o., Mezná 9, 393 01 Mezná');
      IF c_reg ? l AND v_new <> v_old THEN   -- věta o rejstříku jen tam, kde se zároveň měnil prodávající
        v_new := replace(v_new, c_reg -> l ->> 0, c_reg -> l ->> 1);
      END IF;
      IF v_new <> v_old THEN
        v_tr := jsonb_set(v_tr, ARRAY[l, 'content_html'], to_jsonb(v_new));
        n_ch := n_ch + 1;
      END IF;
      IF v_new ~ 'Semorádová|21874263' THEN
        n_left := n_left + 1;
        RAISE WARNING 'custom_documents %/%: v překladu zůstává dosavadní provozovatel v jiném znění – po nahrání nového PDF dejte ve Velínu „Přeložit“', d.slug, l;
      END IF;
    END LOOP;
    IF v_tr IS DISTINCT FROM d.translations THEN   -- jeden zápis na dokument
      UPDATE public.custom_documents SET translations = v_tr WHERE id = d.id;
    END IF;
  END LOOP;
  RAISE NOTICE 'custom_documents: upraveno % překladů, s neopravitelným zbytkem %', n_ch, n_left;
  RAISE NOTICE 'PŘIPOMÍNKA: české originály (PDF) musí majitel nahrát nové – Velín → Dokumenty → Vlastní dokumenty';
END $$;
