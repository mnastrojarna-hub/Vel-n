-- =============================================================================
-- 2026-10-23 (b/9): Velín — úprava výpůjčky výbavy (admin_update_gear_booking)
-- NULL parametr = beze změny. p_dry_run (výchozí true) jen spočítá dopad
-- {old_total, new_total, diff, lines, warnings}. Stejné kusy (klíče) = ceny řádků
-- z uložené objednávky × nové dny (velikosti se jen přepíšou), jiné kusy = aktuální
-- ceník. Dárkový poukaz zůstává (sleva ≤ nová cena). Platbu / vratku rozdílu
-- řeší Velín (diff), funkce peníze nehýbe. Idempotentní.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.admin_update_gear_booking(p_booking_id uuid, p_start date, p_end date, p_items jsonb,
  p_branch_id uuid, p_pickup_time text, p_return_time text, p_dry_run boolean DEFAULT true)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  b record; v_sd date; v_ed date; v_start date; v_end date; v_branch uuid; v_items jsonb; v_p jsonb;
  v_from jsonb; v_to jsonb; v_same_keys boolean; v_lines jsonb; v_per_day numeric; v_sub numeric;
  v_vsum numeric; v_disc numeric; v_new numeric; v_warn jsonb; v_time time; v_rtime text;
BEGIN
  IF NOT public.is_admin() THEN RETURN jsonb_build_object('error', 'forbidden'); END IF;
  SELECT * INTO b FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND OR b.booking_kind IS DISTINCT FROM 'gear' THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
  IF b.status IN ('completed', 'cancelled') THEN RETURN jsonb_build_object('error', 'bad_status', 'status', b.status); END IF;

  v_sd := (b.start_date AT TIME ZONE 'Europe/Prague')::date;
  v_ed := (b.end_date AT TIME ZONE 'Europe/Prague')::date;
  v_start := COALESCE(p_start, v_sd);
  v_end := COALESCE(p_end, v_ed);
  v_branch := COALESCE(p_branch_id, b.branch_id);
  v_from := public._gear_booking_sizes(b.id);
  v_items := COALESCE(p_items, (SELECT jsonb_agg(jsonb_build_object('key', e.key, 'size', e.value))
                                  FROM jsonb_each_text(v_from) e));

  v_p := public._gear_prepare(v_branch, v_start, v_end, v_items, b.id, true, NOT COALESCE(p_dry_run, true));
  IF v_p ? 'error' THEN RETURN v_p; END IF;
  v_to := v_p->'sizes';
  v_warn := v_p->'warnings';

  -- Stejné kusy → ceny řádků z objednávky (ceník se mezitím mohl změnit), jinak nové nacenění
  v_same_keys := (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_from) k)
                 = (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_to) k)
                 AND jsonb_array_length(COALESCE(b.gear_lines, '[]'::jsonb)) > 0;
  IF v_same_keys THEN
    v_lines := public._gear_lines_resize(b.gear_lines, v_to, (v_p->>'days')::int);
    v_per_day := b.gear_per_day;
  ELSE
    v_lines := v_p->'lines';
    v_per_day := (v_p->>'per_day')::numeric;
  END IF;
  v_sub := v_per_day * (v_p->>'days')::int;
  SELECT sum(d.value) INTO v_vsum FROM booking_discounts d WHERE d.booking_id = b.id AND d.kind = 'voucher';
  v_disc := LEAST(COALESCE(v_vsum, b.discount_amount, 0), v_sub);
  v_new := GREATEST(v_sub - v_disc, 0);
  IF b.payment_status IN ('paid', 'partial_refund', 'refund_pending') AND v_new <> COALESCE(b.total_price, 0) THEN
    v_warn := v_warn || '"paid_total_changed"'::jsonb;
  END IF;

  IF COALESCE(p_dry_run, true) THEN
    RETURN jsonb_build_object('success', true, 'dry_run', true, 'old_total', b.total_price, 'new_total', v_new,
      'diff', v_new - COALESCE(b.total_price, 0), 'days', (v_p->>'days')::int, 'per_day', v_per_day,
      'lines', v_lines, 'sizes', v_to, 'discount', v_disc, 'warnings', v_warn, 'stock_short', v_p->'stock_short');
  END IF;

  v_time := public._gear_parse_time(p_pickup_time);
  v_rtime := to_char(public._gear_parse_time(p_return_time), 'HH24:MI');
  PERFORM set_config('motogo.gear_rpc', '1', true);
  UPDATE bookings SET
    start_date = CASE WHEN v_start = v_sd THEN start_date ELSE (v_start::timestamp AT TIME ZONE 'UTC') END,
    end_date   = CASE WHEN v_end = v_ed THEN end_date ELSE (v_end::timestamp AT TIME ZONE 'UTC') END,
    original_start_date = CASE WHEN v_start <> v_sd OR v_end <> v_ed THEN COALESCE(original_start_date, v_sd) ELSE original_start_date END,
    original_end_date   = CASE WHEN v_start <> v_sd OR v_end <> v_ed THEN COALESCE(original_end_date, v_ed) ELSE original_end_date END,
    branch_id = v_branch,
    pickup_time = COALESCE(v_time, pickup_time), return_time = COALESCE(v_rtime, return_time),
    helmet_size = v_to->>'helmet', jacket_size = v_to->>'jacket', pants_size = v_to->>'pants',
    gloves_size = v_to->>'gloves', boots_size = v_to->>'boots',
    gear_lines = v_lines, gear_per_day = v_per_day, total_price = v_new, discount_amount = v_disc,
    modification_history = COALESCE(modification_history, '[]'::jsonb) || jsonb_build_object(
      'at', now(), 'source', 'velin', 'type', 'gear_admin_update', 'by', auth.uid(),
      'from_start', v_sd, 'from_end', v_ed, 'to_start', v_start, 'to_end', v_end,
      'from_branch', b.branch_id, 'to_branch', v_branch, 'from', v_from, 'to', v_to,
      'from_total', b.total_price, 'to_total', v_new)
   WHERE id = b.id;
  PERFORM set_config('motogo.gear_rpc', '', true);

  -- změna kusů / velikostí: e-mail s rozdílem výbavy (termín/cenu pošle trigger úprav; dedup)
  IF v_from IS DISTINCT FROM v_to THEN
    PERFORM public._gear_notify_modified(b.id, jsonb_build_object('gear', jsonb_build_object('from', v_from, 'to', v_to)));
  END IF;
  RETURN jsonb_build_object('success', true, 'dry_run', false, 'old_total', b.total_price, 'new_total', v_new,
    'diff', v_new - COALESCE(b.total_price, 0), 'days', (v_p->>'days')::int, 'per_day', v_per_day,
    'lines', v_lines, 'sizes', v_to, 'discount', v_disc, 'warnings', v_warn, 'stock_short', v_p->'stock_short');
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', 'failed', 'message', SQLERRM);
END $$;

REVOKE ALL ON FUNCTION public._gear_notify_modified(uuid, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._gear_booking_sizes(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._gear_lines_resize(jsonb, jsonb, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._gear_notify_modified(uuid, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public._gear_booking_sizes(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._gear_lines_resize(jsonb, jsonb, integer) TO service_role;
REVOKE ALL ON FUNCTION public.customer_update_gear_sizes(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.customer_update_gear_sizes(uuid, jsonb) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_create_gear_booking(uuid, uuid, date, date, jsonb, text, text, text, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_create_gear_booking(uuid, uuid, date, date, jsonb, text, text, text, boolean, text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_update_gear_booking(uuid, date, date, jsonb, uuid, text, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_gear_booking(uuid, date, date, jsonb, uuid, text, text, boolean) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
