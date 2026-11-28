-- =============================================================================
-- 20261129c_operator_cms_texts.sql
-- Změna provozovatele (3/9): texty webu, které žijí jen v databázi (stránka Kontakt, vizitka).
--
-- Zadání majitele 2026-11-27: provozovatel MotoGo24 s.r.o., IČO 29909864, sídlo Mezná 9, 393 01 Mezná,
-- zápis C 36876 u Krajského soudu v Českých Budějovicích, datová schránka 2xfihrd. Kontakty beze změny.
--
-- Co se mění (jen data, žádné schéma):
--   A) cms_variables – blok „Fakturační údaje“ a dlaždice „Datová schránka“ na /kontakt (česky):
--      web.kontakt.place.billing_name / billing_ico / billing_address / billing_note, web.kontakt.quick.2.value;
--   B) cms_variables – staré „ploché“ klíče, které web už nečte, ale drží dosavadního provozovatele:
--      web.kontakt.company / ico / vat / reg / billing.addr / ds (česká hodnota i 6 překladů) – přepsány
--      na nové údaje (nemažou se);
--   C) app_settings pages_overlay.kontakt.{en,de,es,fr,nl,pl} – cizojazyčná stránka Kontakt:
--      place.billing_name / billing_ico / billing_address / billing_vat / billing_note a quick[2].value;
--   D) app_settings business_card_html (dnes nepoužívaná vizitka v e-mailech).
-- Záměrně se NEMĚNÍ: web.kontakt.place.billing_vat („Nejsme plátci DPH.“ + překlady „We are not VAT
-- payers.“ … – množné číslo, na společnost sedí a na webu má přednost před overlayem), adresa
-- provozovny (web.kontakt.place.address = Mezná 9, 393 01 Pelhřimov – kontaktní adresa pobočky).
--
-- Bezpečnost: každá hodnota se změní jen tehdy, když má PŘESNĚ dosavadní znění ověřené proti živé DB
-- 2026-11-27; co mezitím někdo upravil ve Velínu, se přeskočí s NOTICE. Idempotentní (2. běh nic
-- nezmění). Bez BEGIN/COMMIT – deploy-sql.yml pouští soubor v jedné transakci (ON_ERROR_STOP).
-- Po nasazení: web drží texty i company_info v cache až 30 minut – vyprázdní ji uložení kteréhokoli
-- textu webu ve Velínu (Texty webu → Uložit), jinak se srovná sama.
-- =============================================================================
-- Schváleno majitelem 2026-11-27.

DO $$
DECLARE
  r      record;
  l      text;
  n      integer;
  v_cur  text;
  n_upd  integer := 0;
  n_done integer := 0;
  n_skip integer := 0;
  c_name constant text := 'MotoGo24 s.r.o.';
  c_ico  constant text := '29909864';
  c_seat constant text := 'Mezná 9, 393 01 Mezná';
  c_ds   constant text := '2xfihrd';
  c_reg  constant text := 'Společnost je zapsána v obchodním rejstříku vedeném Krajským soudem v Českých Budějovicích, oddíl C, vložka 36876.';
  c_vat  constant text := 'Nejsme plátci DPH.';
  -- cizojazyčné znění (shodné s motogo-web-php/lang/pages_<lang>.php)
  c_regs constant jsonb := jsonb_build_object(
    'en', 'The company is registered in the Commercial Register kept by the Regional Court in České Budějovice, Section C, File 36876.',
    'de', 'Die Gesellschaft ist im Handelsregister beim Kreisgericht in České Budějovice eingetragen, Abteilung C, Einlage 36876.',
    'es', 'La sociedad está inscrita en el Registro Mercantil del Tribunal Regional de České Budějovice, sección C, inscripción 36876.',
    'fr', 'La société est immatriculée au registre du commerce tenu par le tribunal régional de České Budějovice, section C, dossier 36876.',
    'nl', 'De vennootschap is ingeschreven in het handelsregister van de regionale rechtbank in České Budějovice, afdeling C, dossier 36876.',
    'pl', 'Spółka jest wpisana do rejestru handlowego prowadzonego przez Sąd Okręgowy w Czeskich Budziejowicach, dział C, pozycja 36876.');
  c_vats constant jsonb := jsonb_build_object(
    'en', 'The company is not a VAT payer.',
    'de', 'Die Gesellschaft ist nicht umsatzsteuerpflichtig.',
    'es', 'La sociedad no es contribuyente del IVA.',
    'fr', 'La société n''est pas assujettie à la TVA.',
    'nl', 'De vennootschap is niet btw-plichtig.',
    'pl', 'Spółka nie jest płatnikiem VAT.');
  c_old_name constant text := 'Bc. Petra Semorádová';
  c_old_ico  constant text := '21874263';
  c_old_seat constant text := 'Mezná 9, 393 01 Pelhřimov';
  c_old_ds   constant text := 'iuw3vnb';
  c_old_reg  constant text := 'Společnost byla zapsána dne 31. 7. 2024 u Městského úřadu v Pelhřimově.';
BEGIN
  -- ── A + B) cms_variables: klíč, dosavadní české znění, nové znění, co s překlady
  --    tr: 'keep' = překlady beze změny (klíč žádné nemá) · 'same' = všechny jazyky = nová hodnota ·
  --        'reg' / 'vat' = věta o zápisu / o DPH v jazyce překladu
  FOR r IN
    SELECT * FROM (VALUES
      (1,  'web.kontakt.place.billing_name',    c_old_name, c_name, 'keep'),
      (2,  'web.kontakt.place.billing_ico',     c_old_ico,  c_ico,  'keep'),
      (3,  'web.kontakt.place.billing_address', c_old_seat, c_seat, 'keep'),
      (4,  'web.kontakt.place.billing_note',    c_old_reg,  c_reg,  'keep'),
      (5,  'web.kontakt.quick.2.value',         c_old_ds,   c_ds,   'keep'),
      (6,  'web.kontakt.company',               c_old_name, c_name, 'same'),
      (7,  'web.kontakt.ico',                   c_old_ico,  c_ico,  'same'),
      (8,  'web.kontakt.billing.addr',          c_old_seat, c_seat, 'same'),
      (9,  'web.kontakt.ds',                    c_old_ds,   c_ds,   'same'),
      (10, 'web.kontakt.reg',                   c_old_reg,  c_reg,  'reg'),
      (11, 'web.kontakt.vat',                   'Nejsem plátce DPH', c_vat, 'vat')
    ) AS x(ord, key, old, new, tr)
    ORDER BY ord
  LOOP
    UPDATE public.cms_variables v
       SET value = to_jsonb(r.new),
           translations = CASE r.tr
             WHEN 'keep' THEN v.translations
             ELSE coalesce((
               SELECT jsonb_object_agg(t.lang,
                        CASE WHEN jsonb_typeof(t.val) = 'object'
                             THEN t.val || jsonb_build_object('value',
                                    CASE r.tr WHEN 'reg' THEN coalesce(c_regs ->> t.lang, r.new)
                                              WHEN 'vat' THEN coalesce(c_vats ->> t.lang, r.new)
                                              ELSE r.new END)
                             ELSE t.val END)
                 FROM jsonb_each(v.translations) AS t(lang, val)), '{}'::jsonb)
           END,
           updated_at = now()
     WHERE v.key = r.key AND jsonb_typeof(v.value) = 'string' AND v.value #>> '{}' = r.old;
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n > 0 THEN
      n_upd := n_upd + n;
    ELSE
      SELECT value #>> '{}' INTO v_cur FROM public.cms_variables WHERE key = r.key;
      IF NOT FOUND THEN
        n_skip := n_skip + 1;
        RAISE NOTICE 'cms: klíč % v databázi není – přeskočeno (web použije výchozí text z kódu)', r.key;
      ELSIF v_cur = r.new THEN
        n_done := n_done + 1;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'cms: klíč % má jiné znění než 2026-11-27 („%“) – ponecháno beze změny', r.key, left(v_cur, 80);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'cms_variables (kontakt): změněno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;

  -- ── C) cizojazyčná stránka Kontakt (app_settings pages_overlay.kontakt.<jazyk>)
  n_upd := 0; n_done := 0; n_skip := 0;
  FOREACH l IN ARRAY ARRAY['en', 'de', 'es', 'fr', 'nl', 'pl'] LOOP
    UPDATE public.app_settings s
       SET value = jsonb_set(
             CASE WHEN s.value #>> '{quick,2,value}' = c_old_ds
                  THEN jsonb_set(s.value, '{quick,2,value}', to_jsonb(c_ds)) ELSE s.value END,
             '{place}',
             (s.value -> 'place') || jsonb_build_object(
               'billing_name',    c_name,
               'billing_ico',     c_ico,
               'billing_address', c_seat,
               'billing_vat',     c_vats ->> l,
               'billing_note',    c_regs ->> l)),
           updated_at = now()
     WHERE s.key = 'pages_overlay.kontakt.' || l
       AND jsonb_typeof(s.value -> 'place') = 'object'
       AND s.value #>> '{place,billing_ico}' = c_old_ico
       AND s.value #>> '{place,billing_name}' = c_old_name;
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n > 0 THEN
      n_upd := n_upd + n;
    ELSIF EXISTS (SELECT 1 FROM public.app_settings WHERE key = 'pages_overlay.kontakt.' || l AND value #>> '{place,billing_ico}' = c_ico) THEN
      n_done := n_done + 1;
    ELSE
      n_skip := n_skip + 1;
      RAISE NOTICE 'overlay kontakt.%: řádek chybí nebo nemá dosavadní fakturační údaje – přeskočeno', l;
    END IF;
    -- dlaždice datové schránky samostatně (kdyby fakturační blok už někdo upravil ručně)
    UPDATE public.app_settings s
       SET value = jsonb_set(s.value, '{quick,2,value}', to_jsonb(c_ds)), updated_at = now()
     WHERE s.key = 'pages_overlay.kontakt.' || l AND s.value #>> '{quick,2,value}' = c_old_ds;
  END LOOP;
  RAISE NOTICE 'pages_overlay.kontakt (6 jazyků): změněno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;

  -- ── D) vizitka v e-mailech (dnes se nevkládá – {{business_card}} se z šablon maže), jen řádek s provozovatelem
  UPDATE public.app_settings
     SET value = to_jsonb(replace(value #>> '{}', c_old_name || ', IČO: ' || c_old_ico, c_name || ', IČO: ' || c_ico)),
         updated_at = now()
   WHERE key = 'business_card_html' AND jsonb_typeof(value) = 'string'
     AND strpos(value #>> '{}', c_old_name || ', IČO: ' || c_old_ico) > 0;
  GET DIAGNOSTICS n = ROW_COUNT;
  RAISE NOTICE 'business_card_html: změněno %', n;
END $$;
