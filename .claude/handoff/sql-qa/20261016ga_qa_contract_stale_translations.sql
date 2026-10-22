-- =============================================================================
-- 20261016ga_qa_contract_stale_translations.sql — NÁVRH ke schválení (QA brána 2026-10-16), neaplikováno
-- document_templates type='rental_contract': content_translations de/en/es/fr/nl/pl jsou starý překlad
-- („Pronajímatel nevyžaduje, aby byl předmět nájmu vrácen ve stavu čistoty …“ = mytí nikdy není potřeba —
-- v rozporu s pravidlem: na samoobslužné pobočce Velké Němčice se motorka vrací umytá).
-- Nezobrazují se (translation_src bez platného otisku → web, appka, generate-document i AI berou závaznou
-- češtinu), ale zůstávají v DB. Smaže se jen překlad, který (a) NEMÁ platný otisk aktuální české verze
-- (sha1 content_html = stejná kontrola jako get_document_translation) a (b) obsahuje starou větu o čistotě.
-- Čerstvý překlad (platný otisk) se nikdy nemaže. Nezávisí na 20261016g: bez něj jen uklidí skryté
-- překlady, po něm (nová verze → všechny otisky zastaralé) uklidí i ty, které by vznikly mezitím.
-- Velín → Dokumenty → „Přeložit chybějící a zastaralé“ pak vytvoří překlady z aktuální češtiny.
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
