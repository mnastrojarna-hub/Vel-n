-- =============================================================================
-- MIGRACE 2026-07-24: Aktivace obslužné rezervace při vzniku PŘEDÁVACÍHO PROTOKOLU
--
-- Report: rezervace AE0439CA (obslužná, zaplacená) zůstala „nadcházející" i po
-- podepsání předávacího protokolu. Příčina: protokol byl podepsán z karty
-- DOKLADY rezervace (`BookingDocumentsTab` → „Vygenerovat předávací protokol"
-- → elektronicky), jejíž `onSaved` jen zavře modal a NEVOLÁ aktivaci
-- (`markPickedUp`). Existují tři cesty podpisu předávacího protokolu a jen dvě
-- rezervaci aktivují:
--   1) Odjezdy a návraty → Odbavit → PickupReadiness → markPickedUp  (aktivuje ✓)
--   2) Odjezdy a návraty → Výměna → SwapModal → swap_handoff_bookings (aktivuje ✓)
--   3) Detail rezervace → Doklady → předávací protokol                (NEAKTIVUJE ✗)
--
-- Oprava (server-side, pokrývá VŠECHNY cesty + je odolná vůči RLS/UI):
-- trigger na INSERT do `generated_documents` — jde-li o elektronický PŘEDÁVACÍ
-- protokol (`filled_data->>'_doc_type' = 'handover_protocol'`) na OBSLUŽNÉ
-- pobočce, nastaví rezervaci `handover_protocol_filled_at` PŘÍMO (projde
-- strážcem trg_gate_obsluzna_activation) a zaplacenou `reserved` překlopí na
-- `active` (+ picked_up_at). Idempotentní (COALESCE), nepřepisuje
-- completed/cancelled, netýká se damage/contract/vop/gdpr ani samoobslužné
-- (ta se aktivuje kódem v appce) / svozu.
--
-- + swap_handoff_bookings: aktivační UPDATE nové rezervace nově přijímá i stav
--   'active' — nový doc-trigger totiž může novou (B) aktivovat už při podpisu
--   protokolu PŘED voláním RPC; RPC pak musí i tak dopsat vazbu řetězu
--   (continues_booking_id). NOVÝ soubor (20260723 už aplikovaná, needituje se).
-- =============================================================================

-- 1) Aktivace obslužné rezervace vznikem předávacího protokolu -----------------
CREATE OR REPLACE FUNCTION _activate_on_handover_protocol_doc()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_obsluzna boolean;
  v_status   text;
  v_pay      text;
BEGIN
  -- Jen elektronický PŘEDÁVACÍ protokol (ne damage/contract/vop/gdpr).
  IF COALESCE(NEW.filled_data->>'_doc_type', '') <> 'handover_protocol' THEN
    RETURN NEW;
  END IF;
  IF NEW.booking_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT b.status::text, b.payment_status::text,
         COALESCE(br.type = 'obslužná', false)
    INTO v_status, v_pay, v_obsluzna
  FROM bookings b
  JOIN motorcycles m ON m.id = b.moto_id
  JOIN branches br   ON br.id = m.branch_id
  WHERE b.id = NEW.booking_id;

  -- Aktivace předáním protokolu se týká OBSLUŽNÉ pobočky (samoobslužná = kód
  -- v appce, svoz/delivery = jinak). Mimo obslužnou neaktivujeme.
  IF NOT COALESCE(v_obsluzna, false) THEN
    RETURN NEW;
  END IF;

  IF v_status = 'reserved'
     AND v_pay IN ('paid', 'partial_refund', 'refund_pending') THEN
    -- Podpis předávacího protokolu = motorka reálně předána → aktivuj.
    -- handover_protocol_filled_at PŘÍMO ve stejném UPDATE → projde strážcem.
    UPDATE bookings SET
      status = 'active',
      picked_up_at = COALESCE(picked_up_at, now()),
      handover_protocol_filled_at = COALESCE(handover_protocol_filled_at, now())
    WHERE id = NEW.booking_id
      AND status = 'reserved';
  ELSE
    -- Mimo aktivaci alespoň zaznamenej podpis protokolu (idempotentně).
    UPDATE bookings SET
      handover_protocol_filled_at = COALESCE(handover_protocol_filled_at, now())
    WHERE id = NEW.booking_id
      AND handover_protocol_filled_at IS NULL;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_activate_on_handover_protocol_doc ON generated_documents;
CREATE TRIGGER trg_activate_on_handover_protocol_doc
  AFTER INSERT ON generated_documents
  FOR EACH ROW
  EXECUTE FUNCTION _activate_on_handover_protocol_doc();

-- 2) swap_handoff_bookings — přijmi i 'active' novou (doc-trigger ji mohl
--    aktivovat už při podpisu protokolu PŘED voláním RPC) ----------------------
CREATE OR REPLACE FUNCTION swap_handoff_bookings(p_prev uuid, p_next uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  a bookings;
  b bookings;
  v_prev_status text;
  v_next_status text;
BEGIN
  IF NOT is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
  END IF;

  SELECT * INTO a FROM bookings WHERE id = p_prev;
  SELECT * INTO b FROM bookings WHERE id = p_next;
  IF a.id IS NULL OR b.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  IF a.user_id IS DISTINCT FROM b.user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'different_customer');
  END IF;
  IF b.payment_status NOT IN ('paid', 'partial_refund', 'refund_pending') THEN
    RETURN jsonb_build_object('success', false, 'error', 'next_not_paid');
  END IF;

  -- Uvolni STAROU (idempotentně): completed + returned_at.
  UPDATE bookings
     SET status = 'completed',
         returned_at = COALESCE(returned_at, now()),
         actual_return_date = COALESCE(actual_return_date, CURRENT_DATE)
   WHERE id = p_prev
     AND status IN ('active', 'reserved');

  -- Aktivuj NOVOU + nastav protokol PŘÍMO + vazbu řetězu. Přijmi i 'active'
  -- (novou mohl doc-trigger aktivovat už při podpisu protokolu PŘED RPC) →
  -- i tak dopíšeme continues_booking_id.
  UPDATE bookings
     SET status = 'active',
         picked_up_at = COALESCE(picked_up_at, now()),
         handover_protocol_filled_at = COALESCE(handover_protocol_filled_at, now()),
         continues_booking_id = p_prev
   WHERE id = p_next
     AND status IN ('reserved', 'pending', 'active');

  SELECT status::text INTO v_prev_status FROM bookings WHERE id = p_prev;
  SELECT status::text INTO v_next_status FROM bookings WHERE id = p_next;

  RETURN jsonb_build_object(
    'success', true, 'prev', p_prev, 'next', p_next,
    'prev_status', v_prev_status, 'next_status', v_next_status,
    'prev_completed', (v_prev_status = 'completed'),
    'next_active', (v_next_status = 'active')
  );
END;
$$;

REVOKE ALL ON FUNCTION swap_handoff_bookings(uuid, uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION swap_handoff_bookings(uuid, uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
