-- =============================================================================
-- 20261016f_qa_vop_footer_address.sql — NÁVRH ke schválení (QA brána 2026-10-16), neaplikováno
-- VOP (document_templates type='vop', živě v14): patička „Bc. Petra Semorádová · IČO: 21874263 · Mezná 9,
-- 393 01 Mezná · …“ → „Mezná 9, 393 01 Pelhřimov“ (= záhlaví téže VOP, nájemní smlouva, GDPR, e-maily,
-- config.php webu). Jen oprava adresy v patičce – žádná změna podmínek; NEZÁVISÍ na schválení 20261016g
-- (mytí v čl. 5 l). Nová verze šablony (version + 1, jako uložení ve Velínu); překlady VOP dnes nemají
-- platný otisk (translation_src = {}), cizí jazyky tedy už teď zobrazují závaznou češtinu – beze změny.
-- 20261016g (pokud bude schválen) pak už patičku nenajde a změní jen čl. 5 l) (+1 verze).
-- Bezpečnost: mění se jen když je stará adresa v textu PRÁVĚ jednou. Idempotentní. Bez BEGIN/COMMIT.
-- =============================================================================
DO $$
DECLARE
  c_foot_re constant text := $q$Mezná\s+9,\s+393\s+01\s+Mezná(\s*·)$q$;
  n integer;
BEGIN
  UPDATE public.document_templates
     SET content_html = regexp_replace(content_html, c_foot_re, $q$Mezná 9, 393 01 Pelhřimov\1$q$),
         version = coalesce(version, 1) + 1
   WHERE type = 'vop' AND active
     AND (SELECT count(*) FROM regexp_matches(content_html, c_foot_re, 'g')) = 1;
  GET DIAGNOSTICS n = ROW_COUNT;
  RAISE NOTICE 'VOP patička „393 01 Mezná“ → „393 01 Pelhřimov“: upraveno %', n;
END $$;
