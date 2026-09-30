-- =============================================================================
-- STAV TACHOMETRU (2026-09-29) — 2/6 (merge A): payload kiosku (protokol + resolve)
-- Migrace: 20260929d_kiosk_odo_resolve.sql — těla = živé verze (supabase-live-snapshot 2026-09-29) + aditivní klíče
--  • _kiosk_protocol: + moto_id, data.mileage = _handover_pickup_km, + data.mileage_unit
--  • kiosk_resolve_code: + `odo` u kódu motorky
-- Starší software jednotky nové klíče ignoruje. Závisí na 20260929c. Idempotentní (CREATE OR REPLACE, granty zůstávají).
-- =============================================================================

CREATE OR REPLACE FUNCTION "public"."_kiosk_protocol"("p_booking_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  r record;
  v_parts text[];
  v_name text;
  v_gear jsonb;
BEGIN
  SELECT b.id, b.moto_id, b.handover_protocol_filled_at, b.gear_collected_at, b.handover_protocol_prompted_at,
         b.start_date, b.end_date,
         b.helmet_size, b.jacket_size, b.pants_size, b.boots_size, b.gloves_size,
         b.passenger_helmet_size, b.passenger_jacket_size, b.passenger_pants_size,
         b.passenger_boots_size, b.passenger_gloves_size,
         p.full_name, p.email, m.model, m.spz, m.tracking_unit,
         (m.license_required::text = 'N') AS is_child
    INTO r
    FROM bookings b
    LEFT JOIN profiles p    ON p.id = b.user_id
    LEFT JOIN motorcycles m ON m.id = b.moto_id
   WHERE b.id = p_booking_id;
  IF NOT FOUND THEN RETURN NULL; END IF;

  -- Jméno na displeji zkráceně (křestní + iniciála), fallback část e-mailu, nikdy NULL;
  -- tituly („Bc.", „Ing.", „Ph.D.") = tokeny končící tečkou se přeskočí
  SELECT coalesce(array_agg(p ORDER BY o), '{}'::text[]) INTO v_parts
    FROM unnest(regexp_split_to_array(btrim(coalesce(r.full_name, '')), '\s+')) WITH ORDINALITY AS u(p, o)
   WHERE p <> '' AND right(p, 1) <> '.';
  IF coalesce(v_parts[1], '') <> '' THEN
    v_name := v_parts[1] || CASE WHEN array_length(v_parts, 1) > 1
                                 THEN ' ' || left(v_parts[array_length(v_parts, 1)], 1) || '.' ELSE '' END;
  ELSE
    v_name := nullif(split_part(coalesce(r.email, ''), '@', 1), '');
  END IF;
  v_name := coalesce(v_name, '—');

  -- Půjčená výbava: jen neprázdné velikosti; field = sloupec bookings (Velín/edge)
  SELECT coalesce(jsonb_agg(jsonb_build_object('key', g.key, 'who', g.who, 'field', g.field, 'size', btrim(g.size))
                            ORDER BY g.ord), '[]'::jsonb)
    INTO v_gear
    FROM (VALUES
      (1,  'helmet', 'rider',     'helmet_size',           r.helmet_size),
      (2,  'jacket', 'rider',     'jacket_size',           r.jacket_size),
      (3,  'pants',  'rider',     'pants_size',            r.pants_size),
      (4,  'boots',  'rider',     'boots_size',            r.boots_size),
      (5,  'gloves', 'rider',     'gloves_size',           r.gloves_size),
      (6,  'helmet', 'passenger', 'passenger_helmet_size', r.passenger_helmet_size),
      (7,  'jacket', 'passenger', 'passenger_jacket_size', r.passenger_jacket_size),
      (8,  'pants',  'passenger', 'passenger_pants_size',  r.passenger_pants_size),
      (9,  'boots',  'passenger', 'passenger_boots_size',  r.passenger_boots_size),
      (10, 'gloves', 'passenger', 'passenger_gloves_size', r.passenger_gloves_size)
    ) AS g(ord, key, who, field, size)
   WHERE nullif(btrim(g.size), '') IS NOT NULL;

  RETURN jsonb_build_object(
    'booking_id',        r.id,
    'moto_id',           r.moto_id,          -- 2026-09-29: jednotka páruje čekající stav vrácení téže motorky
    'required',          (r.handover_protocol_filled_at IS NULL),
    'filled_at',         r.handover_protocol_filled_at,
    'needs_locker',      public._booking_needs_locker(r.id),
    'gear_collected_at', r.gear_collected_at,
    'prompted_at',       r.handover_protocol_prompted_at,
    'is_child',          coalesce(r.is_child, false),
    'data', jsonb_build_object(
      'customer_name', v_name,
      'moto_model',    r.model,
      'moto_spz',      r.spz,
      'start_date',    r.start_date,
      'end_date',      r.end_date,
      -- 2026-09-29: km vyplní systém (zákazník nezadává) = poslední stav (vrácení předchozím zákazníkem)
      'mileage',       public._handover_pickup_km(r.id),
      'mileage_unit',  CASE WHEN r.tracking_unit = 'mh' THEN 'mh' ELSE 'km' END,
      'gear',          v_gear));
EXCEPTION WHEN OTHERS THEN
  -- Fail-open (§0): NULL = stav neznámý → jednotka otevírá; chyba jednoho
  -- protokolu nesmí shodit resolve kódu ani celý sync_config pobočky.
  RAISE WARNING '_kiosk_protocol failed for booking %: %', p_booking_id, SQLERRM;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."kiosk_resolve_code"("p_device_id" "uuid", "p_device_token" "uuid", "p_code" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_bid uuid; v_branch public.branches%ROWTYPE; v_cfg public.branch_kiosk_config%ROWTYPE;
  v_door public.branch_doors%ROWTYPE; v_dc public.branch_door_codes%ROWTYPE; v_svc public.branch_service_codes%ROWTYPE;
  v_box integer; v_doors jsonb; v_code text := btrim(coalesce(p_code,''));
BEGIN
  IF v_code = '' THEN RETURN jsonb_build_object('ok',false,'error','missing_inputs'); END IF;
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, true);
  IF v_bid IS NULL THEN RETURN jsonb_build_object('ok',false,'error','unauthorized'); END IF;
  SELECT * INTO v_branch FROM public.branches WHERE id = v_bid;
  SELECT * INTO v_cfg FROM public.branch_kiosk_config WHERE branch_id = v_bid;

  -- 1) servisní heslo → seznam všech aktivních dveří (app se zeptá které) + účel hesla
  SELECT * INTO v_svc FROM public.branch_service_codes s
   WHERE s.branch_id=v_bid AND s.is_active AND s.code=v_code ORDER BY s.created_at LIMIT 1;
  IF FOUND THEN
    SELECT coalesce(jsonb_agg(d ORDER BY d.ord),'[]'::jsonb) INTO v_doors FROM (
      SELECT bd.id,bd.door_kind,bd.box_number,bd.label,bd.relay_url,bd.light_url,coalesce(bd.box_number,9999) AS ord
        FROM public.branch_doors bd WHERE bd.branch_id=v_bid AND bd.is_active) d;
    RETURN jsonb_build_object('ok',true,'kind','service','action',coalesce(v_svc.action,'service'),'label',v_svc.label,
      'branch_id',v_bid,'branch_name',v_branch.name,
      'music_on_url',v_cfg.music_on_url,'music_off_url',v_cfg.music_off_url,'music_seconds',COALESCE(v_cfg.music_seconds,90),
      'door_open_seconds',COALESCE(v_cfg.door_open_seconds,8),'light_seconds',COALESCE(v_cfg.light_seconds,120),'doors',v_doors);
  END IF;

  -- 2) zákaznický kód (branch_door_codes) — aktivní, vydaný, v platnosti, této pobočky
  --    (kód šatny bez nároku řádek deaktivuje trg_sync_locker_code → invalid_code)
  SELECT * INTO v_dc FROM public.branch_door_codes bdc
   WHERE bdc.branch_id=v_bid AND bdc.door_code=v_code AND bdc.is_active=true AND bdc.sent_to_customer=true
     AND (bdc.valid_from IS NULL OR bdc.valid_from<=now()) AND (bdc.valid_until IS NULL OR bdc.valid_until>=now())
   ORDER BY bdc.updated_at DESC LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','invalid_code'); END IF;

  IF v_dc.code_type='accessories' THEN
    SELECT * INTO v_door FROM public.branch_doors WHERE branch_id=v_bid AND door_kind='accessories' AND is_active LIMIT 1;
  ELSE
    SELECT box_number INTO v_box FROM public.motorcycles WHERE id=v_dc.moto_id;
    SELECT * INTO v_door FROM public.branch_doors WHERE branch_id=v_bid AND door_kind='motorcycle' AND box_number=v_box AND is_active LIMIT 1;
  END IF;

  -- 3) stav předávacího protokolu (2026-09-25) — hradlo kódu motorky vynucuje jednotka;
  --    `protocol` NULL = stav neznámý (jednotka otevírá, fail-open)
  -- 4) `odo` (2026-09-29) — jen kód MOTORKY: nápověda + hranice km a důkazy fáze pro vrácení (_kiosk_odometer);
  --    NULL = neznámo → jednotka se řídí jen lokálním stavem (bez něj km nežádá)
  RETURN jsonb_build_object('ok',true,'kind',v_dc.code_type,'branch_id',v_bid,'branch_name',v_branch.name,
    'booking_id',v_dc.booking_id,'box_number',coalesce(v_door.box_number,v_box),
    'music_on_url',v_cfg.music_on_url,'music_off_url',v_cfg.music_off_url,'music_seconds',COALESCE(v_cfg.music_seconds,90),
    'door_open_seconds',COALESCE(v_cfg.door_open_seconds,8),'light_seconds',COALESCE(v_cfg.light_seconds,120),
    'door',CASE WHEN v_door.id IS NULL THEN NULL ELSE jsonb_build_object('id',v_door.id,'door_kind',v_door.door_kind,
      'box_number',v_door.box_number,'label',v_door.label,'relay_url',v_door.relay_url,'light_url',v_door.light_url) END,
    'door_configured',(v_door.id IS NOT NULL),
    'protocol',CASE WHEN v_dc.booking_id IS NULL THEN NULL ELSE public._kiosk_protocol(v_dc.booking_id) END,
    'odo',CASE WHEN v_dc.code_type = 'motorcycle' AND v_dc.booking_id IS NOT NULL
               THEN public._kiosk_odometer(v_dc.booking_id, v_bid) END);
END; $$;

