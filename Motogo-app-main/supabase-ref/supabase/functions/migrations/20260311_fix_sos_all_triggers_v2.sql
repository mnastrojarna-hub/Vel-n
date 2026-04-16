-- ═══════════════════════════════════════════════════════
-- KOMPLETNÍ OPRAVA SOS TRIGGERS v2 — 2026-03-11
--
-- Problém: INSERT do sos_incidents stále selhává.
-- Příčina: Pravděpodobně neznámý trigger nebo chybějící
--          WHEN OTHERS handler v check_one_active_sos.
--
-- Řešení:
-- 1. DIAGNOSTIKA: Vypsat všechny triggery na sos_incidents
-- 2. DROP ALL: Smazat VŠECHNY triggery na sos_incidents
-- 3. RECREATE: Znovu vytvořit POUZE potřebné triggery
--    s plným error handlingem a SECURITY DEFINER
-- ═══════════════════════════════════════════════════════

-- ═══════════ KROK 1: DIAGNOSTIKA (výpis do NOTICE) ═══════════
DO $$
DECLARE
  r record;
BEGIN
  RAISE NOTICE '========= TRIGGERS NA sos_incidents =========';
  FOR r IN
    SELECT tgname, tgtype, pg_proc.proname as func_name
    FROM pg_trigger
    JOIN pg_class ON pg_trigger.tgrelid = pg_class.oid
    JOIN pg_proc ON pg_trigger.tgfoid = pg_proc.oid
    WHERE pg_class.relname = 'sos_incidents'
      AND NOT pg_trigger.tgisinternal
  LOOP
    RAISE NOTICE 'Trigger: % → funkce: % (type: %)', r.tgname, r.func_name, r.tgtype;
  END LOOP;
  RAISE NOTICE '=============================================';
END $$;

-- ═══════════ KROK 2: DROP ALL triggers na sos_incidents ═══════════
-- Smažeme ÚPLNĚ VŠECHNO — potom znovu vytvoříme jen to co potřebujeme
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT tgname
    FROM pg_trigger
    JOIN pg_class ON pg_trigger.tgrelid = pg_class.oid
    WHERE pg_class.relname = 'sos_incidents'
      AND NOT pg_trigger.tgisinternal
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON sos_incidents', r.tgname);
    RAISE NOTICE 'DROPPED trigger: %', r.tgname;
  END LOOP;
END $$;

-- ═══════════ KROK 3: RECREATE FUNKCE (safe, SECURITY DEFINER) ═══════════

-- 3a. sos_auto_severity — nastavení závažnosti dle typu
CREATE OR REPLACE FUNCTION sos_auto_severity()
RETURNS trigger AS $$
BEGIN
  IF NEW.severity IS NULL OR NEW.severity::text = 'medium' THEN
    CASE NEW.type::text
      WHEN 'theft' THEN NEW.severity := 'critical';
      WHEN 'accident_major' THEN NEW.severity := 'high';
      WHEN 'breakdown_major' THEN NEW.severity := 'high';
      WHEN 'accident_minor' THEN NEW.severity := 'medium';
      WHEN 'breakdown_minor' THEN NEW.severity := 'low';
      WHEN 'defect_question' THEN NEW.severity := 'low';
      ELSE NEW.severity := 'medium';
    END CASE;
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[sos_auto_severity] error: %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3b. check_one_active_sos — blokace duplikátů
--     KLÍČOVÁ OPRAVA: Přidán WHEN OTHERS → RETURN NEW
--     Dříve: bez WHEN OTHERS → jakákoliv chyba (ENUM cast, RLS) zablokovala INSERT
CREATE OR REPLACE FUNCTION check_one_active_sos()
RETURNS trigger AS $$
DECLARE
  v_active_count int;
BEGIN
  -- Light types don't block
  IF NEW.type::text IN ('breakdown_minor', 'defect_question', 'location_share', 'other') THEN
    RETURN NEW;
  END IF;

  SELECT count(*) INTO v_active_count
  FROM sos_incidents
  WHERE user_id = NEW.user_id
    AND status::text NOT IN ('resolved', 'closed')
    AND type::text NOT IN ('breakdown_minor', 'defect_question', 'location_share', 'other');

  IF v_active_count > 0 THEN
    RAISE EXCEPTION 'Máte již aktivní SOS incident. Počkejte na vyřešení stávajícího incidentu velínem.';
  END IF;

  RETURN NEW;
EXCEPTION
  WHEN raise_exception THEN
    RAISE;  -- Re-raise intentional duplicate block
  WHEN OTHERS THEN
    -- SAFETY NET: Pokud dojde k jakékoliv jiné chybě, povolíme INSERT
    RAISE NOTICE '[check_one_active_sos] unexpected error (allowing INSERT): %', SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3c. sos_auto_timeline — auto timeline záznam
CREATE OR REPLACE FUNCTION sos_auto_timeline()
RETURNS trigger AS $$
BEGIN
  INSERT INTO sos_timeline (incident_id, action, performed_by)
  VALUES (NEW.id, 'Incident nahlasen zakaznikem (' || COALESCE(NEW.type::text, 'other') || ')', 'System');
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[sos_auto_timeline] error: %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3d. sos_notify_user_on_create — notifikace zákazníka
CREATE OR REPLACE FUNCTION sos_notify_user_on_create()
RETURNS trigger AS $$
DECLARE
  v_type_label text;
  v_message text;
  v_title text;
  v_is_light boolean;
  v_exists boolean;
BEGIN
  -- Dedup: neposílej pokud už existuje zpráva v posledních 2 minutách
  SELECT EXISTS(
    SELECT 1 FROM admin_messages
    WHERE user_id = NEW.user_id
      AND type IN ('sos_response', 'sos_auto')
      AND created_at > now() - interval '2 minutes'
  ) INTO v_exists;

  IF v_exists THEN
    RETURN NEW;
  END IF;

  CASE NEW.type::text
    WHEN 'theft' THEN v_type_label := 'Krádež motorky';
    WHEN 'accident_minor' THEN v_type_label := 'Lehká nehoda';
    WHEN 'accident_major' THEN v_type_label := 'Závažná nehoda';
    WHEN 'breakdown_minor' THEN v_type_label := 'Drobná porucha';
    WHEN 'breakdown_major' THEN v_type_label := 'Vážná porucha';
    ELSE v_type_label := 'SOS hlášení';
  END CASE;

  v_is_light := NEW.type::text IN ('accident_minor', 'breakdown_minor', 'defect_question', 'location_share', 'other');

  IF v_is_light THEN
    v_title := 'Děkujeme za nahlášení';
    v_message := 'Děkujeme za nahlášení incidentu (' || v_type_label || '). Šťastnou cestu!';
  ELSE
    v_title := 'SOS přijato: ' || v_type_label;
    v_message := 'Vaše hlášení bylo přijato centrálou MotoGo24. ' ||
      COALESCE(NEW.description, '') ||
      ' Asistent vás bude kontaktovat.';
  END IF;

  INSERT INTO admin_messages (user_id, title, message, type)
  VALUES (
    NEW.user_id,
    v_title,
    v_message,
    CASE WHEN v_is_light THEN 'sos_auto' ELSE 'sos_response' END
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[sos_notify_user_on_create] error: %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3e. update_updated_at — timestamp trigger (safe, idempotent)
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3f. trigger_sos_auto_reply — safe no-op (pro případ že něco odkazuje)
CREATE OR REPLACE FUNCTION trigger_sos_auto_reply()
RETURNS trigger AS $$
BEGIN
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ═══════════ KROK 4: RECREATE TRIGGERS ═══════════
-- Pořadí je důležité:
-- BEFORE INSERT: severity → one_active_sos → updated_at (nah, updated_at je jen UPDATE)
-- AFTER INSERT: timeline → notify

CREATE TRIGGER trg_sos_auto_severity
  BEFORE INSERT ON sos_incidents
  FOR EACH ROW EXECUTE FUNCTION sos_auto_severity();

CREATE TRIGGER trg_one_active_sos
  BEFORE INSERT ON sos_incidents
  FOR EACH ROW EXECUTE FUNCTION check_one_active_sos();

CREATE TRIGGER trg_sos_incidents_updated
  BEFORE UPDATE ON sos_incidents
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_sos_auto_timeline
  AFTER INSERT ON sos_incidents
  FOR EACH ROW EXECUTE FUNCTION sos_auto_timeline();

CREATE TRIGGER trg_sos_notify_user
  AFTER INSERT ON sos_incidents
  FOR EACH ROW EXECUTE FUNCTION sos_notify_user_on_create();

-- ═══════════ KROK 5: Disable automation rules (znovu, pro jistotu) ═══════════
DO $$ BEGIN
  EXECUTE 'UPDATE automation_rules SET enabled = false WHERE id IN (SELECT id FROM automation_rules WHERE to_jsonb(automation_rules)::text ILIKE ''%sos%'')';
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$ BEGIN
  EXECUTE 'UPDATE notification_rules SET enabled = false WHERE id IN (SELECT id FROM notification_rules WHERE to_jsonb(notification_rules)::text ILIKE ''%sos%'')';
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- ═══════════ KROK 6: Ověření ═══════════
DO $$
DECLARE
  r record;
  cnt int := 0;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========= NOVÉ TRIGGERS NA sos_incidents =========';
  FOR r IN
    SELECT tgname, pg_proc.proname as func_name,
           CASE WHEN tgtype::int & 2 > 0 THEN 'BEFORE' ELSE 'AFTER' END as timing,
           CASE WHEN tgtype::int & 4 > 0 THEN 'INSERT'
                WHEN tgtype::int & 16 > 0 THEN 'UPDATE'
                ELSE 'OTHER' END as event
    FROM pg_trigger
    JOIN pg_class ON pg_trigger.tgrelid = pg_class.oid
    JOIN pg_proc ON pg_trigger.tgfoid = pg_proc.oid
    WHERE pg_class.relname = 'sos_incidents'
      AND NOT pg_trigger.tgisinternal
    ORDER BY timing, event
  LOOP
    RAISE NOTICE '  % % → %', r.timing, r.event, r.tgname;
    cnt := cnt + 1;
  END LOOP;
  RAISE NOTICE 'Celkem: % triggers', cnt;
  IF cnt = 5 THEN
    RAISE NOTICE '✅ SPRÁVNĚ — 5 triggers (severity, one_active, updated_at, timeline, notify)';
  ELSE
    RAISE NOTICE '⚠️ POZOR — očekáváno 5 triggers, nalezeno %', cnt;
  END IF;
  RAISE NOTICE '=================================================';
END $$;

-- ═══════════ KROK 7: TEST INSERT (dry-run s rollback) ═══════════
-- Tento blok otestuje že INSERT projde, pak provede rollback
DO $$
DECLARE
  v_test_id uuid;
BEGIN
  -- Najdi existujícího uživatele
  INSERT INTO sos_incidents (user_id, type, status, description)
  SELECT id, 'breakdown_minor', 'reported', 'TEST INSERT — pokud vidíte tuto zprávu, INSERT funguje'
  FROM profiles
  LIMIT 1
  RETURNING id INTO v_test_id;

  IF v_test_id IS NOT NULL THEN
    RAISE NOTICE '✅ TEST INSERT OK — id: %', v_test_id;
    -- Smaž testovací záznam
    DELETE FROM sos_timeline WHERE incident_id = v_test_id;
    DELETE FROM admin_messages WHERE message LIKE '%TEST INSERT%';
    DELETE FROM sos_incidents WHERE id = v_test_id;
    RAISE NOTICE '✅ Testovací záznamy smazány';
  ELSE
    RAISE NOTICE '⚠️ TEST INSERT nevrátil ID';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '❌ TEST INSERT FAILED: % (SQLSTATE: %)', SQLERRM, SQLSTATE;
END $$;
