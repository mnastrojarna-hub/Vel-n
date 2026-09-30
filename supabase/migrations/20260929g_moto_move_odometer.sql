-- =============================================================================
-- STAV TACHOMETRU (2026-09-29) — 5/6 (merge A): přesun motorky se stavem tachometru (RPC, zatím BEZ strážce)
-- Migrace: 20260929g_moto_move_odometer.sql — idempotentní, aditivní
--  • admin_move_motorcycle(s): obslužná ↔ samoobslužná (i NULL → samoobslužná) jen s p_km; log transfer
--  • correct_motorcycle_mileage: živé tělo + SET search_path + log correction (Velín „Korekce nájezdu“)
-- Strážce přímého UPDATE branch_id přijde až v 20260929h (merge B, spolu s Velínem).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.correct_motorcycle_mileage(p_moto_id uuid, p_km integer, p_note text DEFAULT NULL::text)
RETURNS public.motorcycles
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_row motorcycles%ROWTYPE;
  v_prev integer;
  v_admin uuid := auth.uid();
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF p_km IS NULL OR p_km < 0 THEN
    RAISE EXCEPTION 'invalid_km';
  END IF;

  SELECT mileage INTO v_prev FROM motorcycles WHERE id = p_moto_id FOR UPDATE;
  UPDATE motorcycles
     SET mileage = GREATEST(p_km, COALESCE(purchase_mileage, 0))
   WHERE id = p_moto_id
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'moto_not_found';
  END IF;

  BEGIN
    INSERT INTO admin_audit_log(admin_id, action, entity_type, entity_id, new_data)
    VALUES (v_admin, 'motorcycle_mileage_corrected', 'motorcycles', p_moto_id,
            jsonb_build_object('new_km', v_row.mileage, 'requested_km', p_km, 'prev_km', v_prev, 'note', p_note));
  EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN   -- 2026-09-29: historie stavů tachometru (Velín); nápověda/spodní mez kiosku = motorcycles.mileage
    INSERT INTO moto_odometer_readings(moto_id, km, unit, kind, source, prev_km, branch_id, created_by, note)
    VALUES (p_moto_id, v_row.mileage, CASE WHEN v_row.tracking_unit = 'mh' THEN 'mh' ELSE 'km' END,
            'correction', 'velin', v_prev, v_row.branch_id, v_admin, p_note);
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_move_motorcycle(
  p_moto_id uuid, p_branch_id uuid, p_km integer DEFAULT NULL, p_force boolean DEFAULT false, p_note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_m motorcycles%ROWTYPE; v_unit text; v_last integer; v_jump integer; v_new_km integer;
  v_from_self boolean; v_to_self boolean; v_need boolean;
BEGIN
  IF NOT public.is_admin() THEN RETURN jsonb_build_object('ok', false, 'error', 'forbidden'); END IF;
  IF p_moto_id IS NULL OR p_branch_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'missing_inputs'); END IF;
  IF NOT EXISTS (SELECT 1 FROM branches WHERE id = p_branch_id) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'branch_not_found');
  END IF;
  SELECT * INTO v_m FROM motorcycles WHERE id = p_moto_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'moto_not_found', 'moto_id', p_moto_id); END IF;
  IF v_m.branch_id IS NOT DISTINCT FROM p_branch_id AND p_km IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'changed', false, 'moto_id', p_moto_id, 'to_branch_id', p_branch_id);
  END IF;

  v_unit      := CASE WHEN v_m.tracking_unit = 'mh' THEN 'mh' ELSE 'km' END;
  v_last      := COALESCE(v_m.mileage, 0);
  v_from_self := public.branch_is_self_service(v_m.branch_id);
  v_to_self   := public.branch_is_self_service(p_branch_id);
  v_need      := v_m.branch_id IS DISTINCT FROM p_branch_id AND v_from_self <> v_to_self;

  IF v_need AND p_km IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'km_required', 'moto_id', p_moto_id, 'model', v_m.model, 'spz', v_m.spz,
                              'last', NULLIF(v_last, 0), 'unit', v_unit,
                              'from_self_service', v_from_self, 'to_self_service', v_to_self);
  END IF;
  IF p_km IS NOT NULL THEN
    IF p_km < 0 OR p_km > 9999999 THEN
      RETURN jsonb_build_object('ok', false, 'error', 'invalid_km', 'moto_id', p_moto_id);
    END IF;
    IF p_km < COALESCE(v_m.purchase_mileage, 0) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'km_below_purchase', 'moto_id', p_moto_id,
                                'purchase_km', v_m.purchase_mileage, 'unit', v_unit);
    END IF;
    v_jump := CASE v_unit WHEN 'mh' THEN 500 ELSE 20000 END;
    IF NOT COALESCE(p_force, false) AND p_km < v_last THEN            -- Velín: „Opravdu nižší?“ → p_force
      RETURN jsonb_build_object('ok', false, 'error', 'km_below_last', 'needs_confirm', true, 'moto_id', p_moto_id,
                                'last', v_last, 'unit', v_unit);
    END IF;
    IF NOT COALESCE(p_force, false) AND v_last > 0 AND p_km > v_last + v_jump THEN   -- překlep o řád
      RETURN jsonb_build_object('ok', false, 'error', 'km_jump', 'needs_confirm', true, 'moto_id', p_moto_id,
                                'last', v_last, 'unit', v_unit);
    END IF;
  END IF;

  PERFORM set_config('motogo.moto_move_ok', p_moto_id::text, true);   -- strážce 20260929h pustí jen tuto motorku
  UPDATE motorcycles
     SET branch_id = p_branch_id,
         mileage   = COALESCE(p_km, mileage)
   WHERE id = p_moto_id
  RETURNING mileage INTO v_new_km;
  PERFORM set_config('motogo.moto_move_ok', '', true);

  IF p_km IS NOT NULL THEN
    INSERT INTO moto_odometer_readings(moto_id, km, unit, kind, source, prev_km, branch_id, to_branch_id, created_by, note)
    VALUES (p_moto_id, p_km, v_unit, 'transfer', 'velin', NULLIF(v_last, 0), v_m.branch_id, p_branch_id, auth.uid(), p_note);
  END IF;
  BEGIN
    INSERT INTO admin_audit_log(admin_id, action, entity_type, entity_id, old_data, new_data)
    VALUES (auth.uid(), 'motorcycle_migrated', 'motorcycles', p_moto_id,
            jsonb_build_object('branch_id', v_m.branch_id, 'mileage', v_m.mileage),
            jsonb_build_object('branch_id', p_branch_id, 'mileage', v_new_km, 'km_reading', p_km,
                               'km_required', v_need, 'forced', COALESCE(p_force, false), 'note', p_note));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('ok', true, 'changed', true, 'moto_id', p_moto_id, 'from_branch_id', v_m.branch_id,
                            'to_branch_id', p_branch_id, 'km_required', v_need, 'mileage', v_new_km, 'unit', v_unit);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_move_motorcycle(uuid, uuid, integer, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_move_motorcycle(uuid, uuid, integer, boolean, text) TO authenticated, service_role;
COMMENT ON FUNCTION public.admin_move_motorcycle(uuid, uuid, integer, boolean, text) IS
  'Velín/AI (2026-09-29): přesun motorky. Obslužná↔samoobslužná (i NULL→samoobslužná) povinný p_km → jinak {ok:false,error:km_required,last,unit}. km_below_purchase (tvrdě); km_below_last / km_jump (+20 000 km | +500 MH) → needs_confirm, znovu s p_force. Zapíše branch_id + mileage, moto_odometer_readings (transfer), admin_audit_log. Jen admin (JWT).';

-- Hromadný přesun (FleetBulkActionsModal): p_items = [{moto_id, km?, force?}] — vše, nebo nic
CREATE OR REPLACE FUNCTION public.admin_move_motorcycles(p_branch_id uuid, p_items jsonb, p_note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  it jsonb; r jsonb; v_out jsonb := '[]'::jsonb; v_fail jsonb;
BEGIN
  IF NOT public.is_admin() THEN RETURN jsonb_build_object('ok', false, 'error', 'forbidden'); END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_inputs');
  END IF;
  BEGIN
    FOR it IN SELECT value FROM jsonb_array_elements(p_items) LOOP
      r := public.admin_move_motorcycle(
             CASE WHEN (it->>'moto_id') ~* '^[0-9a-f-]{36}$' THEN (it->>'moto_id')::uuid END,
             p_branch_id,
             CASE WHEN (it->>'km') ~ '^[0-9]{1,7}$' THEN (it->>'km')::integer END,
             lower(COALESCE(it->>'force', 'false')) = 'true',
             p_note);
      IF NOT COALESCE((r->>'ok')::boolean, false) THEN
        v_fail := r || jsonb_build_object('moto_id', it->>'moto_id');
        RAISE EXCEPTION 'bulk_move_failed';
      END IF;
      v_out := v_out || jsonb_build_array(r);
    END LOOP;
  EXCEPTION WHEN raise_exception THEN
    IF v_fail IS NOT NULL THEN      -- savepoint bloku vrátil všechny dosavadní přesuny
      RETURN jsonb_build_object('ok', false, 'error', 'bulk_move_failed', 'failed', v_fail);
    END IF;
    RAISE;
  END;
  RETURN jsonb_build_object('ok', true, 'moved', v_out);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_move_motorcycles(uuid, jsonb, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_move_motorcycles(uuid, jsonb, text) TO authenticated, service_role;
