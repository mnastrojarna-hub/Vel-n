-- ============================================================================
-- PŘÍSTUPOVÉ KÓDY JEN S KOMPLETNÍMI DOKLADY — pojistka + RLS (2026-10-10, 3/4)
-- Pravidlo a jádro viz `20261010_docs_gate_core.sql` (`booking_docs_gate`).
--
-- * `trg_zz_door_codes_docs_gate` (BEFORE INSERT / UPDATE OF sent_to_customer,
--   is_active na branch_door_codes): kód se NEVYDÁ (sent_to_customer=true) bez
--   splněné brány dokladů — ať ho vydává kterákoli cesta (trigger, RPC, přímý
--   zápis z Velína „nouzově vygenerovat“, kopie při přesunu motorky / kódu
--   šatny). Výjimky: rezervace už převzatá (`picked_up_at`) — probíhající
--   pronájem se nikdy nezamkne; rezervace, která už vydaný kód MÁ (kopie
--   kódu při přesunu / nový kód šatny; už odeslané kódy dle rozhodnutí
--   majitele 2026-10-10 platí dál); vědomé ruční uvolnění adminem
--   (`admin_release_door_codes` přes GUC `motogo.door_codes_admin_override`).
--   Jméno řadí trigger ZA trg_withhold_swap_next_codes / trg_normalize_*.
-- * `admin_release_door_codes` („Odeslat“ ve Velínu): uvolní i bez dokladů
--   (obsluha je ověřila osobně), ale zapíše `admin_audit_log`
--   (`door_codes_admin_release` + co chybělo) a vrátí `docs_reason`.
-- * RLS „Customer read own codes“: zákazník vidí JEN vydané kódy (dřív REST
--   i realtime vracely i číslo ZADRŽENÉHO kódu — appka ho jen skryla v UI).
--   Stav zadržení (bez čísla) vrací nové RPC `get_my_door_codes`.
-- ============================================================================

CREATE OR REPLACE FUNCTION public._door_codes_docs_guard()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_picked timestamptz;
  v_reason text;
BEGIN
  IF NOT (COALESCE(NEW.sent_to_customer, false) AND COALESCE(NEW.is_active, false)) THEN RETURN NEW; END IF;
  -- Už vydaný a aktivní kód (jiná změna). Reaktivace / vložení neaktivního
  -- „odeslaného“ řádku a jeho zapnutí bránou projde (jinak obchvat pojistky).
  IF TG_OP = 'UPDATE' AND OLD.sent_to_customer IS TRUE AND OLD.is_active IS TRUE THEN RETURN NEW; END IF;
  IF current_setting('motogo.door_codes_admin_override', true) = '1' THEN RETURN NEW; END IF;

  SELECT b.picked_up_at INTO v_picked FROM bookings b WHERE b.id = NEW.booking_id;
  IF NOT FOUND OR v_picked IS NOT NULL THEN RETURN NEW; END IF;
  IF EXISTS (SELECT 1 FROM branch_door_codes c
              WHERE c.booking_id = NEW.booking_id AND c.id IS DISTINCT FROM NEW.id
                AND c.sent_to_customer IS TRUE) THEN
    RETURN NEW;
  END IF;

  v_reason := public.booking_docs_gate(NEW.booking_id);
  IF v_reason IS NOT NULL THEN
    NEW.sent_to_customer := false;
    NEW.sent_at := NULL;
    NEW.withheld_reason := CASE WHEN NEW.withheld_reason IN ('Vraťte nejdřív původní motorku', 'Vlastní výbava')
                                THEN NEW.withheld_reason ELSE v_reason END;
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Brána nejde vyhodnotit → raději zadržet (zákazník / obsluha uvolní znovu)
  RAISE WARNING '_door_codes_docs_guard booking %: %', NEW.booking_id, SQLERRM;
  NEW.sent_to_customer := false;
  NEW.sent_at := NULL;
  NEW.withheld_reason := COALESCE(NULLIF(NEW.withheld_reason, ''), 'Doklady nelze ověřit');
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public._door_codes_docs_guard() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_zz_door_codes_docs_gate ON public.branch_door_codes;
CREATE TRIGGER trg_zz_door_codes_docs_gate
  BEFORE INSERT OR UPDATE OF sent_to_customer, is_active ON public.branch_door_codes
  FOR EACH ROW EXECUTE FUNCTION public._door_codes_docs_guard();

-- admin_release_door_codes: vědomé ruční uvolnění + audit ------------------------
CREATE OR REPLACE FUNCTION public.admin_release_door_codes(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_released integer := 0;
  v_swap integer := 0;
  v_reason text;
BEGIN
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM bookings WHERE id = p_booking_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;

  v_reason := public.booking_docs_gate(p_booking_id);   -- co chybí (NULL = vše OK)
  PERFORM set_config('motogo.door_codes_admin_override', '1', true);
  UPDATE branch_door_codes
     SET sent_to_customer = true, sent_at = now(), withheld_reason = NULL
   WHERE booking_id = p_booking_id AND is_active AND sent_to_customer = false
     AND withheld_reason IS DISTINCT FROM 'Vraťte nejdřív původní motorku';
  GET DIAGNOSTICS v_released = ROW_COUNT;
  PERFORM set_config('motogo.door_codes_admin_override', '', true);
  SELECT count(*) INTO v_swap FROM branch_door_codes
   WHERE booking_id = p_booking_id AND is_active AND sent_to_customer = false;

  IF v_released = 0 THEN
    RETURN jsonb_build_object('success', false, 'released', 0, 'docs_reason', v_reason,
      'error', CASE WHEN v_swap > 0 THEN 'Vraťte nejdřív původní motorku' ELSE 'Žádné zadržené kódy' END);
  END IF;

  BEGIN
    INSERT INTO admin_audit_log (admin_id, action, entity_type, entity_id, old_data, new_data)
    VALUES (auth.uid(), 'door_codes_admin_release', 'bookings', p_booking_id,
            jsonb_build_object('docs_reason', v_reason),
            jsonb_build_object('released', v_released, 'docs_complete', v_reason IS NULL));
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'admin_release_door_codes: audit failed: %', SQLERRM;
  END;

  PERFORM public._door_codes_notify(p_booking_id, 'Přístupové kódy k pobočce', NULL, false);
  RETURN jsonb_build_object('success', true, 'released', v_released, 'swap_withheld', v_swap,
                            'docs_reason', v_reason);
END $function$;

-- RLS: zákazník čte jen VYDANÉ kódy ------------------------------------------
DROP POLICY IF EXISTS "Customer read own codes" ON public.branch_door_codes;
CREATE POLICY "Customer read own codes" ON public.branch_door_codes
  FOR SELECT
  USING (sent_to_customer = true
         AND EXISTS (SELECT 1 FROM public.bookings
                      WHERE bookings.id = branch_door_codes.booking_id
                        AND bookings.user_id = auth.uid()));

-- Stav kódů rezervace pro appku (číslo jen u vydaného kódu) -------------------
CREATE OR REPLACE FUNCTION public.get_my_door_codes(p_booking_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;
  IF NOT EXISTS (SELECT 1 FROM bookings WHERE id = p_booking_id AND user_id = v_uid) THEN
    RETURN '[]'::jsonb;
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
             'id', c.id, 'booking_id', c.booking_id, 'code_type', c.code_type,
             'door_code', CASE WHEN c.sent_to_customer THEN c.door_code END,
             'is_active', c.is_active, 'sent_to_customer', c.sent_to_customer,
             'withheld_reason', c.withheld_reason,
             'valid_from', c.valid_from, 'valid_until', c.valid_until)
           ORDER BY c.created_at)
      FROM branch_door_codes c
     WHERE c.booking_id = p_booking_id AND c.is_active), '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_door_codes(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_door_codes(uuid) TO authenticated, service_role;
