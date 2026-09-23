-- =============================================================================
-- Pobočka „Brno Pohořelice“ se přestěhovala → „Brno Velké Němčice“
-- Migrace: 20260923_branch_brno_velke_nemcice.sql (DATOVÁ, bez změn schématu)
--
-- NÁLEZ 2026-09-23 (zadání uživatele): samoobslužné boxy už nestojí
-- v Pohořelicích, ale ve Velkých Němčicích — poloha 49°0'16.821"N,
-- 16°40'19.750"E = 49.0046725, 16.6721528. Web, appka (navigace, seznam
-- poboček) i Velín čtou název, město, adresu a GPS VÝHRADNĚ z tabulky
-- `branches`, takže stačí opravit data — v kódu se název nikde neopisuje.
--
-- PŘÍČINA: starý název/adresa/GPS v `branches` (a jméno řídicí jednotky
-- v `kiosk_devices`) — zákazník by navigoval na starou adresu.
--
-- OPRAVA:
--   * `branches`: řádky s „Pohořelic…“ v názvu nebo městě → název
--     s „Velké Němčice“ místo „Pohořelice“, city, address a GPS nové;
--     každý dotčený řádek se vypíše do logu deploye (RAISE NOTICE).
--   * `kiosk_devices.name`: stejná náhrada (guard na existenci tabulky).
--   * Volné texty (branches.notes/translations, FAQ, CMS, šablony) se
--     NEPŘEPISUJÍ — české skloňování by se rozbilo; jejich výskyty vypíše
--     diagnostický SELECT (komentář na konci tohoto souboru) k ruční
--     opravě ve Velíně.
--
-- Idempotentní: po první aplikaci už nic nevyhoví WHERE → „no branch matched“.
-- Nikdy nesmí spadnout (chyba by zablokovala všechny další migrace).
-- =============================================================================

DO $$
DECLARE
  r     record;
  n_cnt integer := 0;
BEGIN
  -- Log starého stavu — deploy log tak dokumentuje, co se přesně změnilo.
  FOR r IN
    SELECT id, name, city, address, gps_lat, gps_lng
    FROM public.branches
    WHERE name ILIKE '%pohořelic%' OR city ILIKE '%pohořelic%'
  LOOP
    RAISE NOTICE 'branches %: "%" | city "%" | address "%" | gps %,% → Brno Velké Němčice',
      r.id, r.name, r.city, r.address, r.gps_lat, r.gps_lng;
  END LOOP;

  UPDATE public.branches
  SET name       = regexp_replace(name, 'Pohořelice', 'Velké Němčice', 'gi'),
      city       = 'Velké Němčice',
      address    = 'Velké Němčice – samoobslužné boxy (GPS 49.0046725, 16.6721528)',
      gps_lat    = 49.0046725,
      gps_lng    = 16.6721528,
      updated_at = now()
  WHERE name ILIKE '%pohořelic%' OR city ILIKE '%pohořelic%';
  GET DIAGNOSTICS n_cnt = ROW_COUNT;

  IF n_cnt = 0 THEN
    RAISE NOTICE 'no branch matched (Pohořelice → Velké Němčice already applied)';
  ELSE
    RAISE NOTICE 'branches updated: % row(s)', n_cnt;
  END IF;

  -- Jméno řídicí jednotky samoobsluhy (Velín → Samoobsluha) nese název pobočky.
  IF to_regclass('public.kiosk_devices') IS NOT NULL THEN
    UPDATE public.kiosk_devices
    SET name = replace(name, 'Pohořelice', 'Velké Němčice')
    WHERE name ILIKE '%pohořelic%';
    GET DIAGNOSTICS n_cnt = ROW_COUNT;
    RAISE NOTICE 'kiosk_devices renamed: % row(s)', n_cnt;
  END IF;
EXCEPTION WHEN OTHERS THEN
  -- Datová oprava nesmí zablokovat frontu migrací — jen zalogovat.
  RAISE WARNING 'branch rename skipped: % (%)', SQLERRM, SQLSTATE;
END $$;

-- =============================================================================
-- DIAGNOSTIKA (jen ke čtení, NENÍ součástí migrace — spustit ručně v SQL editoru):
-- zbývající výskyty „Pohořelic…“ ve volných textech k ruční opravě ve Velíně.
-- =============================================================================
-- Read-only: zbývající výskyty „Pohořelic…“ ve volných textech (k ruční opravě ve Velíně).
-- Spustit v SQL editoru Supabase; nic nemění. Sloupce podle STATE_1/2.
-- WITH hits AS (
--   SELECT 'branches' AS tbl, id::text AS id, 'notes' AS col, notes AS txt FROM public.branches WHERE notes ILIKE '%pohořelic%'
--   UNION ALL SELECT 'branches', id::text, 'translations', translations::text FROM public.branches WHERE translations::text ILIKE '%pohořelic%'
--   UNION ALL SELECT 'faq_items', id::text, 'question', question FROM public.faq_items WHERE question ILIKE '%pohořelic%'
--   UNION ALL SELECT 'faq_items', id::text, 'answer', answer FROM public.faq_items WHERE answer ILIKE '%pohořelic%'
--   UNION ALL SELECT 'faq_items', id::text, 'translations', translations::text FROM public.faq_items WHERE translations::text ILIKE '%pohořelic%'
--   UNION ALL SELECT 'cms_pages', id::text, 'title', title FROM public.cms_pages WHERE title ILIKE '%pohořelic%'
--   UNION ALL SELECT 'cms_pages', id::text, 'excerpt', excerpt FROM public.cms_pages WHERE excerpt ILIKE '%pohořelic%'
--   UNION ALL SELECT 'cms_pages', id::text, 'content', content FROM public.cms_pages WHERE content ILIKE '%pohořelic%'
--   UNION ALL SELECT 'cms_pages', id::text, 'translations', translations::text FROM public.cms_pages WHERE translations::text ILIKE '%pohořelic%'
--   UNION ALL SELECT 'cms_variables', key, 'value', value FROM public.cms_variables WHERE value ILIKE '%pohořelic%'
--   UNION ALL SELECT 'cms_variables', key, 'translations', translations::text FROM public.cms_variables WHERE translations::text ILIKE '%pohořelic%'
--   UNION ALL SELECT 'document_templates', id::text || ' (' || coalesce(type,'') || ')', 'name', name FROM public.document_templates WHERE name ILIKE '%pohořelic%'
--   UNION ALL SELECT 'document_templates', id::text || ' (' || coalesce(type,'') || ')', 'content_html', content_html FROM public.document_templates WHERE content_html ILIKE '%pohořelic%'
--   UNION ALL SELECT 'document_templates', id::text || ' (' || coalesce(type,'') || ')', 'content_translations', content_translations::text FROM public.document_templates WHERE content_translations::text ILIKE '%pohořelic%'
--   UNION ALL SELECT 'document_templates', id::text || ' (' || coalesce(type,'') || ')', 'name_translations', name_translations::text FROM public.document_templates WHERE name_translations::text ILIKE '%pohořelic%'
--   UNION ALL SELECT 'custom_documents', slug, 'title', title FROM public.custom_documents WHERE title ILIKE '%pohořelic%'
--   UNION ALL SELECT 'custom_documents', slug, 'description', description FROM public.custom_documents WHERE description ILIKE '%pohořelic%'
--   UNION ALL SELECT 'custom_documents', slug, 'content_html', content_html FROM public.custom_documents WHERE content_html ILIKE '%pohořelic%'
--   UNION ALL SELECT 'custom_documents', slug, 'translations', translations::text FROM public.custom_documents WHERE translations::text ILIKE '%pohořelic%'
--   UNION ALL SELECT 'email_templates', slug, 'subject', subject FROM public.email_templates WHERE subject ILIKE '%pohořelic%'
--   UNION ALL SELECT 'email_templates', slug, 'body_html', body_html FROM public.email_templates WHERE body_html ILIKE '%pohořelic%'
--   UNION ALL SELECT 'email_templates', slug, 'body_translations', body_translations::text FROM public.email_templates WHERE body_translations::text ILIKE '%pohořelic%'
--   UNION ALL SELECT 'motorcycles', id::text, 'description', description FROM public.motorcycles WHERE description ILIKE '%pohořelic%'
--   UNION ALL SELECT 'motorcycles', id::text, 'translations', translations::text FROM public.motorcycles WHERE translations::text ILIKE '%pohořelic%'
-- )
-- SELECT tbl, id, col,
--        (length(txt) - length(replace(lower(txt), 'pohořelic', ''))) / length('pohořelic') AS occurrences,
--        substr(txt, greatest(1, position('pohořelic' in lower(txt)) - 60), 160) AS context
-- FROM hits
-- ORDER BY tbl, col, id;
-- Pozn.: pokud některá tabulka/sloupec v živé DB neexistuje (např. cms_pages.excerpt), dotčený řádek UNION ALL smažte — dotaz je jen diagnostika.
