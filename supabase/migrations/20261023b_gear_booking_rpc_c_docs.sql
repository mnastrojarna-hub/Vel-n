-- =============================================================================
-- 2026-10-23 (b/3b): Výpůjčka výbavy — doklady = JEN totožnost + 18+
-- Rozhodnutí majitele: výpůjčka výbavy nepotřebuje řidičský průkaz.
--  • booking_docs_gate (stejný podpis i návratový tvar): gear → _gear_docs_checklist.
--  • check_booking_docs_status (uživatel + konec): motorková rezervace téhož dne
--    má přednost; je-li jedinou shodou výpůjčka výbavy → pravidlo výbavy.
--  • NOVÉ check_booking_docs_status_for(booking) = totéž API pro konkrétní rezervaci
--    (edge volající pro gear: webhook, fio-sync, send-booking-email).
--  • get_docs_gate_checklist(p_booking_id): gear → checklist výbavy (+ gear_only).
-- Těla ze živého snapshotu, změny označené „gear 2026-10-23“. Idempotentní.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.booking_docs_gate(p_booking_id uuid)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_b record;
BEGIN
  SELECT user_id, moto_id, start_date, end_date, booking_kind INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN RETURN 'Rezervace nenalezena'; END IF;
  -- gear 2026-10-23: výpůjčka výbavy = jen doklad totožnosti + 18+
  IF v_b.booking_kind = 'gear' THEN
    RETURN public._gear_docs_checklist(v_b.user_id,
             (v_b.start_date AT TIME ZONE 'Europe/Prague')::date,
             (v_b.end_date AT TIME ZONE 'Europe/Prague')::date)->>'reason';
  END IF;
  RETURN public._docs_gate_checklist(v_b.user_id,
           (v_b.start_date AT TIME ZONE 'Europe/Prague')::date,
           (v_b.end_date AT TIME ZONE 'Europe/Prague')::date,
           v_b.moto_id)->>'reason';
END;
$$;

CREATE OR REPLACE FUNCTION public.check_booking_docs_status(p_user_id uuid, p_end_date date, p_moto_id uuid DEFAULT NULL)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_start date;
  v_moto uuid;
  v_kind text;
BEGIN
  IF p_user_id IS NULL THEN RETURN 'Chybí uživatel'; END IF;
  -- Cizí stav dokladů jen admin (dřív šel zjistit u kohokoli)
  IF v_uid IS NOT NULL AND v_uid <> p_user_id AND NOT public.is_admin() THEN
    RETURN 'Doklady nelze ověřit';
  END IF;
  SELECT (b.start_date AT TIME ZONE 'Europe/Prague')::date, b.moto_id, b.booking_kind
    INTO v_start, v_moto, v_kind
    FROM bookings b
   WHERE b.user_id = p_user_id
     AND (p_moto_id IS NULL OR b.moto_id = p_moto_id)
     AND p_end_date IS NOT NULL
     AND (b.end_date::date = p_end_date OR (b.end_date AT TIME ZONE 'Europe/Prague')::date = p_end_date)
   -- gear 2026-10-23: motorková rezervace téhož dne má přednost před výpůjčkou výbavy
   ORDER BY (b.booking_kind = 'gear'), (b.status IN ('pending', 'reserved', 'active')) DESC, b.created_at DESC
   LIMIT 1;
  -- gear 2026-10-23: jediná shoda je výpůjčka výbavy → pravidlo výbavy (totožnost + 18+)
  IF v_kind = 'gear' AND p_moto_id IS NULL THEN
    RETURN public._gear_docs_checklist(p_user_id, v_start, p_end_date)->>'reason';
  END IF;
  RETURN public._docs_gate_checklist(p_user_id, v_start, p_end_date, COALESCE(p_moto_id, v_moto))->>'reason';
END;
$$;

-- NOVÉ: stav dokladů KONKRÉTNÍ rezervace (NULL = OK) — stejné API jako
-- check_booking_docs_status, bez nejednoznačnosti „uživatel + konec“ (gear i motorka).
CREATE OR REPLACE FUNCTION public.check_booking_docs_status_for(p_booking_id uuid)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_user uuid;
BEGIN
  SELECT user_id INTO v_user FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN RETURN 'Rezervace nenalezena'; END IF;
  IF v_user IS NULL THEN RETURN 'Chybí uživatel'; END IF;
  IF v_uid IS NOT NULL AND v_uid <> v_user AND NOT public.is_admin() THEN
    RETURN 'Doklady nelze ověřit';
  END IF;
  RETURN public.booking_docs_gate(p_booking_id);
END;
$$;
REVOKE ALL ON FUNCTION public.check_booking_docs_status_for(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_booking_docs_status_for(uuid) TO authenticated, service_role;
COMMENT ON FUNCTION public.check_booking_docs_status_for(uuid) IS
  'Stav dokladů pro vydání kódů KONKRÉTNÍ rezervace (NULL = OK). Motorka = _docs_gate_checklist, výpůjčka výbavy = jen totožnost + 18+. Cizí rezervace jen admin/service. 2026-10-23.';

CREATE OR REPLACE FUNCTION public.get_docs_gate_checklist(p_user_id uuid DEFAULT NULL, p_booking_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_b record;
  v_user uuid := p_user_id;
BEGIN
  IF p_booking_id IS NOT NULL THEN
    SELECT user_id, moto_id, start_date, end_date, booking_kind INTO v_b FROM bookings WHERE id = p_booking_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF v_b.user_id IS NULL THEN RETURN jsonb_build_object('error', 'no_user'); END IF;
    v_user := v_b.user_id;
  END IF;
  IF v_user IS NULL THEN v_user := v_uid; END IF;
  IF v_user IS NULL OR (v_uid IS DISTINCT FROM v_user AND NOT public.is_admin()) THEN
    RETURN jsonb_build_object('error', 'forbidden');
  END IF;
  IF p_booking_id IS NOT NULL THEN
    -- gear 2026-10-23: výpůjčka výbavy = checklist jen totožnost + 18+
    IF v_b.booking_kind = 'gear' THEN
      RETURN public._gear_docs_checklist(v_user,
               (v_b.start_date AT TIME ZONE 'Europe/Prague')::date,
               (v_b.end_date AT TIME ZONE 'Europe/Prague')::date)
             || jsonb_build_object('booking_id', p_booking_id);
    END IF;
    RETURN public._docs_gate_checklist(v_user,
             (v_b.start_date AT TIME ZONE 'Europe/Prague')::date,
             (v_b.end_date AT TIME ZONE 'Europe/Prague')::date, v_b.moto_id)
           || jsonb_build_object('booking_id', p_booking_id);
  END IF;
  RETURN public._docs_gate_checklist(v_user, NULL, NULL, NULL);
END;
$$;
