-- =============================================================================
-- Pobočka Velké Němčice: město „Brno - Velké Němčice“ + výpis zbylých „Pohořelic…“
-- Migrace: 20260923b_branch_velke_nemcice_city.sql (DATOVÁ, bez změn schématu)
--   (navazuje na 20260923_branch_brno_velke_nemcice.sql)
--
-- NÁLEZ 2026-09-23: log deploye 20260923 (Actions run 35879524330) ukázal
-- skutečná živá data přejmenované pobočky: name „MotoGo24 Pohořelice“,
-- address „Pohořelice“, zip „639 00“, city „Brno - Pohořelice“. Zákazník tedy
-- viděl „Brno - Pohořelice“ z pole city — odtud zadání „Brno Pohořelice →
-- Brno Velké Němčice“. Migrace 20260923 nastavila city jen „Velké Němčice“,
-- takže „Brno“ z toho, co zákazník vidí, zmizelo.
--
-- OPRAVA: city = „Brno - Velké Němčice“ (stejný vzor jako dřív) u řádku, který
-- 20260923 přejmenovala (address 'Boudky' + city 'Velké Němčice'). Název
-- „MotoGo24 Velké Němčice“ zůstává (dřív „MotoGo24 Pohořelice“, bez „Brno“).
--
-- DIAGNOSTIKA (jen čtení): do logu deploye vypíše zbývající výskyty
-- „Pohořelic…“ ve volných textech (poznámky pobočky, FAQ, CMS, šablony, e-maily,
-- motorky, trasy) k ruční opravě ve Velíně — české skloňování se automaticky
-- nepřepisuje. Chyba jednotlivého dotazu diagnostiky se jen zaloguje.
--
-- Idempotentní: druhý běh už nic nezmění (city je nastavené), výpis se zopakuje.
-- =============================================================================

DO $$
DECLARE
  n_cnt integer;
BEGIN
  UPDATE public.branches
  SET city = 'Brno - Velké Němčice',
      updated_at = now()
  WHERE city = 'Velké Němčice' AND address = 'Boudky';
  GET DIAGNOSTICS n_cnt = ROW_COUNT;
  RAISE NOTICE 'branches city → „Brno - Velké Němčice“: % row(s)', n_cnt;
END $$;

DO $$
DECLARE
  t     text;
  c     record;
  n     bigint;
  ctx   text;
  total integer := 0;
BEGIN
  FOREACH t IN ARRAY ARRAY['branches','faq_items','cms_pages','cms_variables',
      'document_templates','custom_documents','email_templates','motorcycles',
      'app_settings','routes','kiosk_devices','branch_kiosk_config'] LOOP
    IF to_regclass('public.' || t) IS NULL THEN CONTINUE; END IF;
    FOR c IN
      SELECT column_name FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = t
        AND data_type IN ('text', 'character varying', 'jsonb', 'json')
    LOOP
      BEGIN
        EXECUTE format('SELECT count(*) FROM public.%I WHERE %I::text ~* %L',
                       t, c.column_name, 'poho[řr]elic') INTO n;
        IF n > 0 THEN
          EXECUTE format(
            'SELECT substr(x, greatest(1, strpos(lower(x), %L) - 60), 160)
               FROM (SELECT %I::text AS x FROM public.%I WHERE %I::text ~* %L LIMIT 1) s',
            'pohořelic', c.column_name, t, c.column_name, 'poho[řr]elic') INTO ctx;
          RAISE NOTICE 'POHOŘELICE zůstává: %.% — % řádek/ů, např.: %', t, c.column_name, n, ctx;
          total := total + 1;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'diagnostika %.% přeskočena: %', t, c.column_name, SQLERRM;
      END;
    END LOOP;
  END LOOP;
  RAISE NOTICE 'diagnostika hotová: % sloupců s „Pohořelic…“', total;
END $$;
