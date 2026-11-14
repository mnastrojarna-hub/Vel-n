-- =============================================================================
-- 20261112u04_qa_vop_stale_translations.sql — smazání zastaralých strojových překladů VOP (QA brána 2026-10-16)
-- document_templates type='vop' (v14): content_translations en/es/fr/nl jsou starý překlad starší verze VOP
-- (čl. 5 f) „předmět nájmu je vždy předán čistý, s plnou nádrží“ – plnou nádrž majitel nikdy neslibuje).
-- Web, generate-document a AI agent je nezobrazují (translation_src = {} → bez platného otisku → závazná
-- čeština); appka 4.1.3 (contracts_screen.dart) je ale čte přímo bez kontroly otisku → zákazník s en/es/fr/nl
-- tam dnes vidí starou verzi. Po smazání uvidí závaznou češtinu (jako na webu).
-- Smaže se jen překlad, který (a) nemá otisk v translation_src a (b) obsahuje slib plné nádrže.
-- Česká závazná verze (content_html), verze šablony ani jiné dokumenty se NEMĚNÍ. Velín → Dokumenty →
-- „Přeložit chybějící a zastaralé“ pak vytvoří čerstvé překlady z aktuální češtiny.
-- Idempotentní (2. běh nic nenajde). Bez BEGIN/COMMIT.
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
