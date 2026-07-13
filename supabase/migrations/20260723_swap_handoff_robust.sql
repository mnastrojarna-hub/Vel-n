-- =============================================================================
-- MIGRACE 2026-07-23: swap_handoff_bookings — odolný switch + diagnostika
--
-- Report: po stisknutí Výměny a podpisu protokolu se stará rezervace nepřesunula
-- na `completed` a nová na `active`. Příčina (nejpravděpodobnější): SwapModal
-- nastavoval `handover_protocol_filled_at` na nové rezervaci SAMOSTATNÝM UPDATE
-- před voláním RPC; když se to neuchytilo (nebo strážce trg_gate_obsluzna_activation
-- srazil aktivaci zpět), guard `handover_protocol_missing` RPC utnul → nic se nepřepnulo.
--
-- Oprava (NOVÝ soubor — 20260720 už je aplikovaná, needituje se):
--   • Aktivační UPDATE nové rezervace nastaví `handover_protocol_filled_at` PŘÍMO
--     (COALESCE) ve stejném příkazu jako status='active' → strážce vidí NEW.… NOT NULL
--     a pustí to. Nezávisí na frontendovém UPDATE ani jeho pořadí.
--   • Zrušen tvrdý guard `handover_protocol_missing` (RPC volá admin po podpisu
--     protokolu ve SwapModalu; protokol si RPC dopíše sama).
--   • Idempotence + nová/pending povolena. VRACÍ výsledné stavy (prev_status/
--     next_status) → frontend ověří, že se switch reálně provedl.
-- =============================================================================

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

  -- Uvolni STAROU (idempotentně): completed + returned_at → get_moto_booked_dates
  -- ji přestane blokovat; KF trigger vygeneruje konečnou fakturu + web_booking_completed.
  UPDATE bookings
     SET status = 'completed',
         returned_at = COALESCE(returned_at, now()),
         actual_return_date = COALESCE(actual_return_date, CURRENT_DATE)
   WHERE id = p_prev
     AND status IN ('active', 'reserved');

  -- Aktivuj NOVOU + nastav protokol PŘÍMO (aby prošla strážcem
  -- trg_gate_obsluzna_activation, který na obslužné vyžaduje handover_protocol_filled_at)
  -- + zapiš vazbu řetězu. Nezávisí na samostatném frontendovém UPDATE.
  UPDATE bookings
     SET status = 'active',
         picked_up_at = COALESCE(picked_up_at, now()),
         handover_protocol_filled_at = COALESCE(handover_protocol_filled_at, now()),
         continues_booking_id = p_prev
   WHERE id = p_next
     AND status IN ('reserved', 'pending');

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
