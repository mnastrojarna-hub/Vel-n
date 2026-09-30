-- =============================================================================
-- STAV TACHOMETRU (2026-09-29) — 3/6 (merge A): kiosk_sync_config + codes[].odo (offline cache jednotky)
-- Migrace: 20260929e_kiosk_odo_sync.sql — tělo = živá verze (supabase-live-snapshot 2026-09-29) + klíč `odo`
-- v řádku kódu motorky (codes[] jednotka nikdy neukládá do remote_config → starší software ho ignoruje).
-- Závisí na 20260929c (_kiosk_odometer). Idempotentní.
-- =============================================================================

CREATE OR REPLACE FUNCTION "public"."kiosk_sync_config"("p_device_id" "uuid", "p_device_token" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
DECLARE
  v_bid uuid; v_branch public.branches%ROWTYPE; v_cfg public.branch_kiosk_config%ROWTYPE;
  v_key bytea; v_doors jsonb; v_services jsonb; v_codes jsonb; v_music jsonb;
  v_protocols jsonb; v_adult jsonb; v_child jsonb;
BEGIN
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, true);
  IF v_bid IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'unauthorized'); END IF;
  SELECT * INTO v_branch FROM public.branches WHERE id = v_bid;
  SELECT * INTO v_cfg FROM public.branch_kiosk_config WHERE branch_id = v_bid;
  v_key := convert_to(p_device_token::text, 'UTF8');

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', d.id, 'door_kind', d.door_kind, 'box_number', d.box_number, 'label', d.label,
    'hw', coalesce(d.hw, '{}'::jsonb), 'relay_url', d.relay_url, 'light_url', d.light_url,
    'sort_order', d.sort_order)
    ORDER BY d.sort_order, coalesce(d.box_number, 9999), d.created_at), '[]'::jsonb)
  INTO v_doors FROM public.branch_doors d WHERE d.branch_id = v_bid AND d.is_active;

  -- servisní hesla — jen hashe + účel (service | diagnostics) + popisek
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'h', encode(extensions.hmac(convert_to(p_device_id::text || ':' || s.code, 'UTF8'), v_key, 'sha256'), 'hex'),
    'action', coalesce(s.action, 'service'), 'label', s.label)
    ORDER BY s.created_at), '[]'::jsonb)
  INTO v_services FROM public.branch_service_codes s WHERE s.branch_id = v_bid AND s.is_active;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'h', encode(extensions.hmac(convert_to(p_device_id::text || ':' || bdc.door_code, 'UTF8'), v_key, 'sha256'), 'hex'),
    'kind', bdc.code_type, 'booking_id', bdc.booking_id,
    'valid_from', bdc.valid_from, 'valid_until', bdc.valid_until,
    'door_id', d.id,
    'box_number', CASE WHEN bdc.code_type = 'motorcycle' THEN coalesce(d.box_number, m.box_number) ELSE d.box_number END,
    -- odo (2026-09-29): jen kód motorky s platností od ≤ 1 dne — offline vrácení (jednotka přepočte days svými hodinami)
    'odo', CASE WHEN bdc.code_type = 'motorcycle' AND bdc.booking_id IS NOT NULL
                 AND (bdc.valid_from IS NULL OR bdc.valid_from <= now() + interval '1 day')
                THEN public._kiosk_odometer(bdc.booking_id, v_bid) END)
    ORDER BY bdc.valid_until DESC NULLS LAST, bdc.updated_at DESC), '[]'::jsonb)
  INTO v_codes
  FROM public.branch_door_codes bdc
  LEFT JOIN public.motorcycles m ON m.id = bdc.moto_id
  LEFT JOIN public.branch_doors d ON d.branch_id = v_bid AND d.is_active AND (
        (bdc.code_type = 'accessories' AND d.door_kind = 'accessories')
     OR (bdc.code_type = 'motorcycle'  AND d.door_kind = 'motorcycle' AND d.box_number = m.box_number))
  WHERE bdc.branch_id = v_bid AND bdc.is_active = true AND bdc.sent_to_customer = true
    AND bdc.door_code IS NOT NULL AND bdc.door_code <> ''
    AND (bdc.valid_until IS NULL OR bdc.valid_until >= now() - interval '1 day');

  -- hudba pobočky — jen aktivní skladby; jednotka si soubory stáhne z public bucketu branch-music.
  -- tracks[].updated_at = čas SOUBORU (storage.objects.updated_at, fallback created_at řádku), NE řádku:
  -- jednotka podle něj stahuje znovu; přejmenování / přesun / ▲▼ pořadí soubor nemění → nic nestahuje.
  -- music.updated_at = max(updated_at) řádků = jakákoli změna metadat (pro Velín / diagnostiku).
  SELECT jsonb_build_object(
    'updated_at', max(t.updated_at),
    'tracks', coalesce(jsonb_agg(jsonb_build_object(
      'id', t.id, 'target', t.target, 'path', t.file_path, 'ext', t.ext,
      'size', t.size_bytes, 'sort_order', t.sort_order,
      'updated_at', coalesce(o.updated_at, t.created_at))
      ORDER BY t.target, t.sort_order, t.created_at), '[]'::jsonb))
  INTO v_music
  FROM public.branch_music_tracks t
  LEFT JOIN storage.objects o ON o.bucket_id = 'branch-music' AND o.name = t.file_path
  WHERE t.branch_id = v_bid AND t.is_active;

  -- předávací protokoly k podpisu (2026-09-25) — jen rezervace s kódem v codes[],
  -- nepodepsané, reserved/active a s platností kódu do 1 dne (minimum osobních
  -- údajů v offline cache jednotky; podepsané jednotka pozná tím, že tu chybí).
  -- Známé okno (fail-open): jednotka offline > 24 h před začátkem platnosti
  -- kódu položku v cache nemá → motorku vydá bez protokolu.
  -- _kiosk_protocol NULL (chyba) se vynechá — jednotka pak otevírá (fail-open).
  SELECT coalesce(jsonb_agg(p.proto ORDER BY p.start_date, p.id), '[]'::jsonb)
  INTO v_protocols
  FROM (
    SELECT b.id, b.start_date, public._kiosk_protocol(b.id) AS proto
      FROM public.bookings b
     WHERE b.handover_protocol_filled_at IS NULL
       AND b.status IN ('reserved', 'active')
       AND b.is_test IS NOT TRUE
       AND EXISTS (
         SELECT 1 FROM public.branch_door_codes bdc
          WHERE bdc.booking_id = b.id AND bdc.branch_id = v_bid
            AND bdc.is_active = true AND bdc.sent_to_customer = true
            AND bdc.door_code IS NOT NULL AND bdc.door_code <> ''
            AND (bdc.valid_until IS NULL OR bdc.valid_until >= now() - interval '1 day')
            AND (bdc.valid_from  IS NULL OR bdc.valid_from  <= now() + interval '1 day'))
  ) p
  WHERE p.proto IS NOT NULL;

  -- číselník velikostí pro úpravu v protokolu: jen 5 typů výbavy se sloupcem
  -- v bookings; child = adult přepsané dětskými řádky (audience child/both),
  -- aby dětský protokol nikdy neskončil bez velikostí
  SELECT coalesce(jsonb_object_agg(t.key, to_jsonb(t.sizes)), '{}'::jsonb) INTO v_adult
    FROM public.accessory_types t
   WHERE coalesce(t.is_active, true) AND t.key IN ('helmet', 'jacket', 'pants', 'boots', 'gloves')
     AND coalesce(array_length(t.sizes, 1), 0) > 0 AND t.audience IN ('adult', 'both');
  SELECT coalesce(jsonb_object_agg(t.key, to_jsonb(t.sizes)), '{}'::jsonb) INTO v_child
    FROM public.accessory_types t
   WHERE coalesce(t.is_active, true) AND t.key IN ('helmet', 'jacket', 'pants', 'boots', 'gloves')
     AND coalesce(array_length(t.sizes, 1), 0) > 0 AND t.audience IN ('child', 'both');

  RETURN jsonb_build_object(
    'ok', true, 'synced_at', now(), 'branch_name', v_branch.name,
    'branch_is_open', coalesce(v_branch.is_open, false),   -- venek v režimu `branch` svítí, dokud je pobočka otevřená
    'hardware', coalesce(v_cfg.hardware, '{}'::jsonb),
    'timings', jsonb_build_object(
      'door_open_seconds', COALESCE(v_cfg.door_open_seconds, 8),
      'light_seconds',     COALESCE(v_cfg.light_seconds, 120),
      'music_seconds',     COALESCE(v_cfg.music_seconds, 90)),
    'music_on_url', v_cfg.music_on_url, 'music_off_url', v_cfg.music_off_url,
    'power_status_url', v_cfg.power_status_url,
    'power_poll_seconds', COALESCE(v_cfg.power_poll_seconds, 60),
    'doors', v_doors, 'service_codes', v_services, 'codes', v_codes,
    'music', v_music,
    'protocols', v_protocols,
    'gear_sizes', jsonb_build_object('adult', v_adult, 'child', v_adult || v_child)
  );
END; $$;
