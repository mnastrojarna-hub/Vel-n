-- =============================================================================
-- MIGRACE: Automatický lifecycle přístupových kódů (branch_door_codes)
-- Datum: 2026-03-17
--
-- Problém: Kódy se negenerují automaticky při aktivaci rezervace a nedeaktivují
--          se automaticky při dokončení/zrušení. Zákazníci vidí staré kódy.
--
-- Řešení:
-- 1. Trigger auto_generate_door_codes: generuje 2 kódy (motorka + příslušenství)
--    při přechodu bookingu na status 'active'
-- 2. Trigger auto_deactivate_door_codes: deaktivuje kódy při přechodu na
--    'completed' nebo 'cancelled'
-- 3. Jednorázový cleanup: deaktivace kódů u dokončených/zrušených rezervací
-- =============================================================================

-- 1. Trigger funkce: auto-generování kódů při aktivaci bookingu
CREATE OR REPLACE FUNCTION auto_generate_door_codes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_branch_id uuid;
  v_has_docs boolean;
  v_withheld text;
  v_code1 text;
  v_code2 text;
BEGIN
  -- Pouze při přechodu na 'active' (z jakéhokoli jiného stavu)
  IF NEW.status != 'active' THEN
    RETURN NEW;
  END IF;
  IF OLD IS NOT NULL AND OLD.status = 'active' THEN
    RETURN NEW; -- už je active, nepřegenerovávej
  END IF;

  -- Přeskoč pokud kódy pro tento booking už existují
  IF EXISTS (SELECT 1 FROM branch_door_codes WHERE booking_id = NEW.id LIMIT 1) THEN
    RETURN NEW;
  END IF;

  -- Získej branch_id z motorky
  SELECT branch_id INTO v_branch_id FROM motorcycles WHERE id = NEW.moto_id;
  IF v_branch_id IS NULL THEN
    RETURN NEW; -- motorka nemá pobočku
  END IF;

  -- Zkontroluj doklady zákazníka
  v_has_docs := false;
  IF EXISTS (
    SELECT 1 FROM documents WHERE user_id = NEW.user_id AND type IN ('contract','protocol') LIMIT 1
  ) THEN
    v_has_docs := true;
  END IF;
  IF NOT v_has_docs THEN
    IF EXISTS (
      SELECT 1 FROM profiles WHERE id = NEW.user_id AND license_number IS NOT NULL AND license_number != ''
    ) THEN
      v_has_docs := true;
    END IF;
  END IF;

  v_withheld := CASE WHEN v_has_docs THEN NULL ELSE 'Chybí doklady (OP/pas/ŘP)' END;

  -- Generuj 6-místné kódy
  v_code1 := LPAD(FLOOR(100000 + RANDOM() * 900000)::text, 6, '0');
  v_code2 := LPAD(FLOOR(100000 + RANDOM() * 900000)::text, 6, '0');

  -- Vlož 2 kódy: motorka + příslušenství
  INSERT INTO branch_door_codes (branch_id, booking_id, moto_id, code_type, door_code,
    is_active, valid_from, valid_until, sent_to_customer, sent_at, withheld_reason)
  VALUES
    (v_branch_id, NEW.id, NEW.moto_id, 'motorcycle', v_code1,
     true, NEW.start_date, NEW.end_date, v_has_docs,
     CASE WHEN v_has_docs THEN NOW() ELSE NULL END, v_withheld),
    (v_branch_id, NEW.id, NEW.moto_id, 'accessories', v_code2,
     true, NEW.start_date, NEW.end_date, v_has_docs,
     CASE WHEN v_has_docs THEN NOW() ELSE NULL END, v_withheld);

  -- Pokud má zákazník doklady, pošli mu kódy jako in-app zprávu
  IF v_has_docs THEN
    BEGIN
      INSERT INTO admin_messages (user_id, title, content, type)
      VALUES (
        NEW.user_id,
        'Přístupové kódy k pobočce',
        'Kód k motorce: ' || v_code1 || E'\nKód k příslušenství: ' || v_code2 ||
        E'\nKódy jsou platné po dobu trvání pronájmu (' ||
        TO_CHAR(NEW.start_date::date, 'DD.MM.YYYY') || ' – ' ||
        TO_CHAR(NEW.end_date::date, 'DD.MM.YYYY') || ').',
        'info'
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'auto_generate_door_codes: failed to send message for booking %: %', NEW.id, SQLERRM;
    END;
  END IF;

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'auto_generate_door_codes failed for booking %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

-- 2. Trigger funkce: auto-deaktivace kódů při dokončení/zrušení bookingu
CREATE OR REPLACE FUNCTION auto_deactivate_door_codes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Pouze při přechodu na completed nebo cancelled
  IF NEW.status NOT IN ('completed', 'cancelled') THEN
    RETURN NEW;
  END IF;
  -- Pouze pokud se status skutečně změnil
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- Deaktivuj všechny aktivní kódy pro tento booking
  UPDATE branch_door_codes
  SET is_active = false
  WHERE booking_id = NEW.id
    AND is_active = true;

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'auto_deactivate_door_codes failed for booking %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

-- 3. Triggery na bookings tabulce
DROP TRIGGER IF EXISTS trg_auto_generate_door_codes ON bookings;
CREATE TRIGGER trg_auto_generate_door_codes
  AFTER UPDATE OF status ON bookings
  FOR EACH ROW
  WHEN (NEW.status = 'active' AND OLD.status IS DISTINCT FROM 'active')
  EXECUTE FUNCTION auto_generate_door_codes();

-- Trigger i pro INSERT (např. SOS replacement booking se rovnou vytvoří jako active)
DROP TRIGGER IF EXISTS trg_auto_generate_door_codes_insert ON bookings;
CREATE TRIGGER trg_auto_generate_door_codes_insert
  AFTER INSERT ON bookings
  FOR EACH ROW
  WHEN (NEW.status = 'active')
  EXECUTE FUNCTION auto_generate_door_codes();

DROP TRIGGER IF EXISTS trg_auto_deactivate_door_codes ON bookings;
CREATE TRIGGER trg_auto_deactivate_door_codes
  AFTER UPDATE OF status ON bookings
  FOR EACH ROW
  WHEN (NEW.status IN ('completed', 'cancelled') AND OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION auto_deactivate_door_codes();

-- 4. Jednorázový cleanup: deaktivuj kódy u všech dokončených/zrušených rezervací
UPDATE branch_door_codes
SET is_active = false
WHERE is_active = true
  AND booking_id IN (
    SELECT id FROM bookings WHERE status IN ('completed', 'cancelled')
  );
