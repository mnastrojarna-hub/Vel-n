-- =============================================================================
-- 20261129f_operator_email_templates.sql
-- Změna provozovatele (9/9): e-mailové šablony (email_templates) – POJISTKA.
--
-- Obsah živých šablon nejde zvenku přečíst (tabulku vidí jen přihlášená obsluha), proto tento
-- soubor nemění konkrétní věty. Udělá jediné: kdyby některá šablona (česky nebo v uloženém
-- překladu) obsahovala identifikační údaj dosavadního provozovatele, nahradí ho údajem nového:
--     „Bc. Petra Semorádová“ → „MotoGo24 s.r.o.“,   IČO 21874263 → 29909864,
--     účet 670100-2225851630/6210 → 2303580494/2010,   IBAN CZ39 6210 6701 0022 2585 1630 → nový,
--     „mBank“ → „Fio banka“,   datová schránka iuw3vnb → 2xfihrd.
-- V repozitáři žádná šablona tyto údaje nemá (patičku s provozovatelem přidává až kód edge funkcí
-- a platební údaje jdou přes proměnné {{account}} / {{iban}} / {{bank}}) → očekávaný výsledek je
-- „změněno 0“. Které šablony by se změnily, ukazuje kontrolní dotaz (podklady předány majiteli 2026-11-27).
-- Nemění se: nic jiného (texty, proměnné, předměty bez těchto údajů), vypnuté šablony ano (stejná
-- pravidla). Idempotentní. Bez BEGIN/COMMIT.
-- =============================================================================
-- Schváleno majitelem 2026-11-27.

DO $$
DECLARE
  t     record;
  r     record;
  v_s   text;
  v_b   text;
  v_bt  text;
  v_st  text;
  v_tx  text;
  n_ch  integer := 0;
BEGIN
  FOR t IN
    SELECT id, slug, subject, body_html, body_text, subject_translations::text AS st, body_translations::text AS bt
      FROM public.email_templates
     WHERE (coalesce(subject, '') || coalesce(body_html, '') || coalesce(body_text, '')
            || subject_translations::text || body_translations::text)
           ~ 'Bc\. Petra Semorádová|21874263|2225851630|CZ39 ?6210 ?6701 ?0022 ?2585 ?1630|mBank|iuw3vnb'
     FOR UPDATE
  LOOP
    v_s := t.subject; v_b := t.body_html; v_tx := t.body_text; v_st := t.st; v_bt := t.bt;
    FOR r IN
      SELECT * FROM (VALUES
        (1, 'Bc. Petra Semorádová',            'MotoGo24 s.r.o.'),
        (2, '21874263',                         '29909864'),
        (3, '670100-2225851630/6210',           '2303580494/2010'),
        (4, 'CZ3962106701002225851630',         'CZ8320100000002303580494'),
        (5, 'CZ39 6210 6701 0022 2585 1630',    'CZ83 2010 0000 0023 0358 0494'),
        (6, 'mBank',                            'Fio banka'),
        (7, 'iuw3vnb',                          '2xfihrd')
      ) AS x(ord, old, new) ORDER BY ord
    LOOP
      v_s  := replace(v_s,  r.old, r.new);
      v_b  := replace(v_b,  r.old, r.new);
      v_tx := replace(v_tx, r.old, r.new);
      v_st := replace(v_st, r.old, r.new);   -- údaje neobsahují uvozovky ani zpětná lomítka → JSON zůstává platný
      v_bt := replace(v_bt, r.old, r.new);
    END LOOP;
    UPDATE public.email_templates
       SET subject = v_s, body_html = v_b, body_text = v_tx,
           subject_translations = v_st::jsonb, body_translations = v_bt::jsonb, updated_at = now()
     WHERE id = t.id;
    n_ch := n_ch + 1;
    RAISE NOTICE 'email_templates: šablona „%“ obsahovala údaje dosavadního provozovatele – nahrazeny', t.slug;
    IF (v_s || v_b || coalesce(v_tx, '') || v_st || v_bt) ~ '2225851630|Semorádová' THEN
      RAISE WARNING 'email_templates: v šabloně „%“ zůstává dosavadní provozovatel / účet v jiném zápisu – upravte ručně ve Velínu → Dokumenty → E-mailové šablony', t.slug;
    END IF;
  END LOOP;
  RAISE NOTICE 'email_templates: změněno % šablon', n_ch;
END $$;
