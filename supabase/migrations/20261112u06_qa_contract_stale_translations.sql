-- =============================================================================
-- 20261112u06_qa_contract_stale_translations.sql — smazání zastaralých překladů nájemní smlouvy (QA 2026-10-16)
-- document_templates type='rental_contract' (v11): content_translations de/en/es/fr/nl/pl jsou strojový
-- překlad bez platného otisku (translation_src = {}); nezobrazují se nikde (web, generate-document, AI agent
-- kontrolují otisk, appka bere u smlouvy jen content_html), ale zůstávají v DB a obsahují starou větu
-- („… nevyžaduje, aby byl předmět nájmu vrácen ve stavu čistoty …“). Smaže se jen překlad, který
-- (a) NEMÁ platný otisk aktuální české verze (sha1 content_html = stejná kontrola jako
-- get_document_translation) a (b) obsahuje tuto starou větu. Čerstvý překlad (platný otisk) se nikdy nemaže.
-- Česká závazná verze (content_html), verze šablony ani podmínky se NEMĚNÍ (úprava mytí ve smlouvě a VOP
-- není součástí bundle – majitel ji neodsouhlasil). Velín → Dokumenty → „Přeložit chybějící a zastaralé“
-- pak vytvoří překlady z aktuální češtiny. Idempotentní. Bez BEGIN/COMMIT.
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
     WHERE type = 'rental_contract'
       AND content_translations ? l
       AND (translation_src ->> l) IS DISTINCT FROM
           encode(extensions.digest(convert_to(content_html, 'UTF8'), 'sha1'), 'hex')
       AND (content_translations ->> l) ~* '(clean condition|gereinigtem Zustand|condiciones de limpieza|état de propreté|schone staat|stanie czystości|стані чистоти|чистому стані)';
    GET DIAGNOSTICS n = ROW_COUNT;
    total := total + n;
    IF n > 0 THEN RAISE NOTICE 'smlouva: smazán zastaralý překlad %', l; END IF;
  END LOOP;
  RAISE NOTICE 'smlouva: smazáno % zastaralých překladů', total;
END $$;
