-- =============================================================================
-- BEZPEČNOST: confirm_payment smí volat jen server nebo admin Velínu
-- Migrace: 20260923d_confirm_payment_caller_guard.sql
--
-- NÁLEZ 2026-09-23 (analýza incidentu Apple Pay, ověřeno proti živému schématu
-- supabase-live-snapshot 2026-09-23): public.confirm_payment(uuid, text) je
-- SECURITY DEFINER BEZ jakékoli kontroly volajícího a EXECUTE mají anon
-- i authenticated. Kdokoli s veřejným anon klíčem (je v appce i na webu)
-- a UUID rezervace ji mohl označit jako zaplacenou bez platby — přihlášený
-- zákazník svou vlastní nezaplacenou rezervaci; funkce navíc oživuje
-- i stornované rezervace (cancelled → reserved/active).
--
-- LEGITIMNÍ VOLAJÍCÍ (grep celého repa): edge process-payment, webhook-receiver
-- (payment-confirmers.ts), fio-sync, ai-copilot — všechny přes
-- SUPABASE_SERVICE_ROLE_KEY; Velín BookingDetail.jsx + NewIncidentModal.jsx
-- jako přihlášený admin (is_admin() = aktivní řádek v admin_users).
-- Appka ani web ji z klienta NEVOLAJÍ; žádná SQL funkce/trigger ji nevolá.
--
-- OPRAVA:
--   * guard na začátku těla: povolen service_role, admin (is_admin()) a přímé
--     připojení k DB bez JWT (auth.role() IS NULL — SQL editor, psql);
--     jinak {success:false, error:'forbidden'} bez jakékoli změny dat;
--   * REVOKE EXECUTE FROM anon, PUBLIC (authenticated zůstává kvůli Velínu,
--     service_role kvůli edge funkcím).
--   Zbytek těla je 1:1 živá verze (snapshot 2026-09-23), beze změny chování.
--
-- Idempotentní (CREATE OR REPLACE + REVOKE/GRANT lze pouštět opakovaně).
-- =============================================================================

CREATE OR REPLACE FUNCTION "public"."confirm_payment"("p_booking_id" "uuid", "p_method" "text" DEFAULT 'card'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_new_status text;
  v_row_count int;
  v_was_already_paid boolean := false;
  v_revived boolean := false;
BEGIN
  -- Guard 2026-09-23: jen server (service_role) nebo admin Velínu. Přímé
  -- připojení k DB (SQL editor, bez JWT → auth.role() IS NULL) zůstává povolené.
  IF auth.role() IS NOT NULL
     AND auth.role() <> 'service_role'
     AND NOT COALESCE(public.is_admin(), false) THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
  END IF;

  SELECT * INTO v_booking FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Rezervace nenalezena');
  END IF;

  -- Cílový stav: pending NEBO cancelled → reserved/active (podle start_date)
  IF v_booking.status IN ('pending', 'cancelled') THEN
    IF v_booking.start_date::date <= CURRENT_DATE THEN
      v_new_status := 'active';
    ELSE
      v_new_status := 'reserved';
    END IF;
    IF v_booking.status = 'cancelled' THEN
      v_revived := true;
    END IF;
  ELSE
    v_new_status := v_booking.status;
  END IF;

  BEGIN
    UPDATE bookings SET
      payment_status = 'paid',
      payment_method = p_method,
      status = v_new_status::booking_status,
      confirmed_at = CASE
        WHEN v_booking.status IN ('pending','cancelled') AND confirmed_at IS NULL
        THEN now() ELSE confirmed_at END,
      picked_up_at = CASE
        WHEN v_booking.status IN ('pending','cancelled')
          AND v_new_status = 'active'
          AND picked_up_at IS NULL
        THEN now() ELSE picked_up_at END,
      cancelled_at          = CASE WHEN v_revived THEN NULL ELSE cancelled_at END,
      cancelled_by          = CASE WHEN v_revived THEN NULL ELSE cancelled_by END,
      cancelled_by_source   = CASE WHEN v_revived THEN NULL ELSE cancelled_by_source END,
      cancellation_reason   = CASE WHEN v_revived THEN NULL ELSE cancellation_reason END,
      cancellation_notified = CASE WHEN v_revived THEN false ELSE cancellation_notified END
    WHERE id = p_booking_id
      AND payment_status <> 'paid';

    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    v_was_already_paid := (v_row_count = 0);

    IF v_revived AND NOT v_was_already_paid THEN
      BEGIN
        INSERT INTO debug_log (source, action, component, status, request_data)
        VALUES ('confirm_payment', 'cancelled_booking_revived', 'booking', 'ok',
                jsonb_build_object('booking_id', p_booking_id,
                                   'previous_status', v_booking.status,
                                   'new_status', v_new_status,
                                   'previous_cancelled_by_source', v_booking.cancelled_by_source));
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
    END IF;

    RETURN jsonb_build_object(
      'success', true,
      'was_already_paid', v_was_already_paid,
      'revived', v_revived AND NOT v_was_already_paid,
      'new_status', v_new_status,
      'transaction_id', 'TXN-' || substr(p_booking_id::text, 1, 8)
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'confirm_payment failed: %', SQLERRM;
    RETURN jsonb_build_object('success', false, 'error', 'Potvrzení platby selhalo: ' || SQLERRM);
  END;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.confirm_payment(uuid, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.confirm_payment(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.confirm_payment(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_payment(uuid, text) TO service_role;
