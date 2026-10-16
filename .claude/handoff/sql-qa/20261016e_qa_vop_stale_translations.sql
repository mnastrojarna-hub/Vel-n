-- =============================================================================
-- 20261016e_qa_vop_stale_translations.sql — NÁVRH ke schválení (QA brána 2026-10-16), neaplikováno
-- document_templates type='vop' (v14): content_translations en/es/fr/nl jsou starý překlad starší verze VOP
-- (čl. 5 f) „předmět nájmu je vždy předán čistý, s plnou nádrží“ – plnou nádrž majitel nikdy neslibuje).
-- Nezobrazují se (translation_src = {} → web, appka, generate-document i AI berou závaznou češtinu),
-- ale zůstávají v DB a mohly by se vrátit cestou, která otisk nekontroluje. Smaže se jen překlad,
-- který (a) nemá platný otisk v translation_src a (b) obsahuje slib plné nádrže. Velín → Dokumenty →
-- „Přeložit chybějící a zastaralé“ pak vytvoří čerstvé překlady z aktuální češtiny.
-- Idempotentní. Bez BEGIN/COMMIT.
-- =============================================================================
DO $$
DECLARE
  l text;
  n integer;
  total integer := 0;
BEGIN
  FOREACH l IN ARRAY ARRAY['en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'] LOOP
    UPDATE public.document_templates
       SET content_translations = content_translations - l
     WHERE type = 'vop'
       AND content_translations ? l
       AND (translation_src ->> l) IS NULL
       AND (content_translations ->> l) ~* '(full tank|depósito lleno|réservoir plein|volle tank|vollem Tank|pełnym bakiem|повним баком)';
    GET DIAGNOSTICS n = ROW_COUNT;
    total := total + n;
    IF n > 0 THEN RAISE NOTICE 'vop: smazán zastaralý překlad %', l; END IF;
  END LOOP;
  RAISE NOTICE 'vop: smazáno % zastaralých překladů', total;
END $$;
