-- =============================================================================
-- MIGRACE: Předávací protokol z kiosku — hradlo kódu motorky, real-time (návrh v2 §2b)
-- Datum: 2026-09-25 (b) — navazuje JEN na 20260925a (sloupce, _booking_needs_locker).
-- Branch: claude/waveshare-doors-8-analysis-11h9zs
--
-- Tok (rozhodnutí majitele §0): šatna → zavření dveří → protokol na displeji
-- (podpis prstem + kód motorky jako identita) → kóje motorky. Nikdo nedostane
-- motorku bez podepsaného protokolu; zákazník s vlastní výbavou podepisuje po
-- zadání kódu motorky, PŘED otevřením. Hradlo vynucuje řídicí jednotka
-- (raspberry/motogo-box) — DB jí dává stav protokolu v obou RPC:
--
--   1) kiosk_commands: nový příkaz `protocol_signed {booking_id}`.
--   2) _kiosk_protocol(uuid) = JEDINÝ tvar objektu `protocol` (resolve i sync):
--      {booking_id, required, filled_at, needs_locker, gear_collected_at,
--       prompted_at, is_child, data:{customer_name (zkráceně), moto_model,
--       moto_spz, start_date, end_date, mileage, gear:[{key, who, field, size}]}}
--   3) kiosk_resolve_code v3: zákaznický kód navíc `protocol`.
--      kiosk_sync_config v3: navíc `protocols[]` (jen nepodepsané, s kódem v
--      codes[], valid_from ≤ now()+1 den — minimum osobních údajů v cache) a
--      `gear_sizes {adult, child}` z accessory_types.
--   4) trg_handover_from_door_event (branch_door_events): zavření šatny →
--      gear_collected_at; zavření šatny / PROTOCOL_SHOWN → started_at,
--      prompted_at + push (throttle 10 min).
--   5) trg_handover_signed_notify_kiosk (bookings.handover_protocol_filled_at
--      NULL→hodnota): příkaz protocol_signed všem jednotkám pobočky + sync.
--   6) get_handover_protocol_state: can_fill bez 1h okna (started_at NEBO den
--      začátku termínu), deadline NULL, + needs_locker/gear_collected_at/
--      prompted_at/start_date; start_handover_protocol_window jen čte.
--   7) ZRUŠEN autofill po 1 h (cron autofill-handover-protocols + funkce).
--   8) Pojistka duplicit ELEKTRONICKÉHO protokolu ze samoobsluhy (unikátní
--      částečný index jen na dokumenty z edge fn, `_self_service=true`; Velín
--      na obslužné pobočce protokoly vkládá opakovaně — ty index nehlídá)
--      + publikace realtime bookings / branch_door_codes (appka streamuje obojí).
-- Idempotentní; těla stávajících funkcí PŘEVZATA z živé DB (snapshot
-- 2026-09-25, kiosk_sync_config vč. bloku music). Nové funkce mají REVOKE.
-- Starý software kiosku pole `protocol`/`protocols` ignoruje (NEhradluje) a
-- příkaz protocol_signed hlásí unknown_command — do aktualizace z Velína.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────
-- 1) Příkaz protocol_signed (CHECK = 20 stávajících z 20260920c + nový)
-- ─────────────────────────────────────────────────────────────────────────
ALTER TABLE public.kiosk_commands DROP CONSTRAINT IF EXISTS kiosk_commands_command_check;
ALTER TABLE public.kiosk_commands ADD CONSTRAINT kiosk_commands_command_check
  CHECK (command IN (
    'open_door','music_on','music_off','identify','reload','camera_control','http_get','restart',
    'light_on','light_off','set_signal','zone_test','audio_test','all_off','reboot','sync_config','update_software',
    'diagnostics','update_system','shell_unlock','protocol_signed'
  ));

-- ─────────────────────────────────────────────────────────────────────────
-- 2) Stav protokolu pro kiosk (jediný tvar pro obě RPC)
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._kiosk_protocol(p_booking_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record;
  v_parts text[];
  v_name text;
  v_gear jsonb;
BEGIN
  SELECT b.id, b.handover_protocol_filled_at, b.gear_collected_at, b.handover_protocol_prompted_at,
         b.start_date, b.end_date,
         b.helmet_size, b.jacket_size, b.pants_size, b.boots_size, b.gloves_size,
         b.passenger_helmet_size, b.passenger_jacket_size, b.passenger_pants_size,
         b.passenger_boots_size, b.passenger_gloves_size,
         p.full_name, p.email, m.model, m.spz, m.mileage,
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
      'mileage',       r.mileage,
      'gear',          v_gear));
EXCEPTION WHEN OTHERS THEN
  -- Fail-open (§0): NULL = stav neznámý → jednotka otevírá; chyba jednoho
  -- protokolu nesmí shodit resolve kódu ani celý sync_config pobočky.
  RAISE WARNING '_kiosk_protocol failed for booking %: %', p_booking_id, SQLERRM;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public._kiosk_protocol(uuid) FROM PUBLIC, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 3) kiosk_resolve_code v3 — zákaznický kód navíc vrací `protocol`
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.kiosk_resolve_code(p_device_id uuid, p_device_token uuid, p_code text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
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
  RETURN jsonb_build_object('ok',true,'kind',v_dc.code_type,'branch_id',v_bid,'branch_name',v_branch.name,
    'booking_id',v_dc.booking_id,'box_number',coalesce(v_door.box_number,v_box),
    'music_on_url',v_cfg.music_on_url,'music_off_url',v_cfg.music_off_url,'music_seconds',COALESCE(v_cfg.music_seconds,90),
    'door_open_seconds',COALESCE(v_cfg.door_open_seconds,8),'light_seconds',COALESCE(v_cfg.light_seconds,120),
    'door',CASE WHEN v_door.id IS NULL THEN NULL ELSE jsonb_build_object('id',v_door.id,'door_kind',v_door.door_kind,
      'box_number',v_door.box_number,'label',v_door.label,'relay_url',v_door.relay_url,'light_url',v_door.light_url) END,
    'door_configured',(v_door.id IS NOT NULL),
    'protocol',CASE WHEN v_dc.booking_id IS NULL THEN NULL ELSE public._kiosk_protocol(v_dc.booking_id) END);
END; $$;
REVOKE ALL ON FUNCTION public.kiosk_resolve_code(uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.kiosk_resolve_code(uuid, uuid, text) TO anon, authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────
-- 4) kiosk_sync_config v3 — navíc protocols[] a gear_sizes (blok music zachován)
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.kiosk_sync_config(p_device_id uuid, p_device_token uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
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
    'box_number', CASE WHEN bdc.code_type = 'motorcycle' THEN coalesce(d.box_number, m.box_number) ELSE d.box_number END)
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
REVOKE ALL ON FUNCTION public.kiosk_sync_config(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.kiosk_sync_config(uuid, uuid) TO anon, authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────
-- 5) Zavření šatny / zobrazení protokolu na displeji → stav rezervace + push
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._handover_from_door_event()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event  text := COALESCE(NEW.detail->>'event', '');
  v_closed boolean;
  v_b      record;
BEGIN
  IF NEW.booking_id IS NULL OR NEW.success IS NOT TRUE THEN RETURN NULL; END IF;
  v_closed := (NEW.kind = 'accessories' AND v_event = 'DOOR_CLOSED');
  IF NOT v_closed AND v_event <> 'PROTOCOL_SHOWN' THEN RETURN NULL; END IF;

  -- (a) první zavření šatny = výbava vyzvednuta (i když je protokol už podepsaný)
  IF v_closed THEN
    UPDATE bookings SET gear_collected_at = now()
     WHERE id = NEW.booking_id AND gear_collected_at IS NULL;
  END IF;

  -- (b) výzva k podpisu: started_at jednou (historie), prompted_at při každé
  --     výzvě (appka na ni reaguje), push nejvýš jednou za 10 minut
  SELECT user_id, status, handover_protocol_filled_at, handover_protocol_prompted_at
    INTO v_b FROM bookings WHERE id = NEW.booking_id;
  IF NOT FOUND OR v_b.handover_protocol_filled_at IS NOT NULL
     OR v_b.status NOT IN ('reserved', 'active') THEN
    RETURN NULL;
  END IF;

  UPDATE bookings
     SET handover_protocol_started_at  = COALESCE(handover_protocol_started_at, now()),
         handover_protocol_prompted_at = now()
   WHERE id = NEW.booking_id;

  IF v_b.user_id IS NOT NULL
     AND (v_b.handover_protocol_prompted_at IS NULL
          OR v_b.handover_protocol_prompted_at < now() - interval '10 minutes') THEN
    PERFORM send_push_via_edge(
      v_b.user_id,
      'Předávací protokol',
      'Podepište prosím předávací protokol — v aplikaci nebo na displeji pobočky.',
      jsonb_build_object('type', 'handover_protocol', 'id', NEW.booking_id::text)
    );
  END IF;

  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  -- Audit dveří se NIKDY nesmí kvůli protokolu nezapsat (outbox jednotky by
  -- se pokoušel donekonečna) — chybu jen zalogujeme.
  RAISE WARNING '_handover_from_door_event failed for booking %: %', NEW.booking_id, SQLERRM;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public._handover_from_door_event() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_handover_from_door_event ON public.branch_door_events;
CREATE TRIGGER trg_handover_from_door_event
  AFTER INSERT ON public.branch_door_events
  FOR EACH ROW EXECUTE FUNCTION public._handover_from_door_event();

-- ─────────────────────────────────────────────────────────────────────────
-- 6) Podpis (appka / Velín / kiosk) → jednotky pobočky: protocol_signed + sync
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._handover_signed_notify_kiosk()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_branch uuid;
  d record;
BEGIN
  -- Jen samoobsluha a živá rezervace (obslužné pobočky nastavuje Velín,
  -- auto_complete završuje nevyzvednuté — jednotka nic nečeká)
  IF NEW.status NOT IN ('reserved', 'active') THEN RETURN NULL; END IF;
  IF NOT _is_self_service_booking(NEW.id) THEN RETURN NULL; END IF;
  SELECT m.branch_id INTO v_branch FROM motorcycles m WHERE m.id = NEW.moto_id;
  IF v_branch IS NULL THEN RETURN NULL; END IF;

  -- Příkaz = urychlení (broadcast ~1 s, po 10 min expiruje); zdroj pravdy je
  -- protocols[] v kiosk_sync_config (sync_config níže + pravidelný sync).
  FOR d IN SELECT id FROM kiosk_devices WHERE branch_id = v_branch AND is_active LOOP
    INSERT INTO kiosk_commands (device_id, branch_id, command, params)
    VALUES (d.id, v_branch, 'protocol_signed', jsonb_build_object('booking_id', NEW.id));
  END LOOP;
  PERFORM kiosk_request_sync(v_branch);
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '_handover_signed_notify_kiosk failed for booking %: %', NEW.id, SQLERRM;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public._handover_signed_notify_kiosk() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_handover_signed_notify_kiosk ON public.bookings;
CREATE TRIGGER trg_handover_signed_notify_kiosk
  AFTER UPDATE OF handover_protocol_filled_at ON public.bookings
  FOR EACH ROW
  WHEN (OLD.handover_protocol_filled_at IS NULL AND NEW.handover_protocol_filled_at IS NOT NULL)
  EXECUTE FUNCTION public._handover_signed_notify_kiosk();

-- ─────────────────────────────────────────────────────────────────────────
-- 7) Stav protokolu pro appku — bez 1h okna; start_* jen čte (staré appky)
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_handover_protocol_state(p_booking_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_b   bookings%ROWTYPE;
  v_self boolean;
  v_today date := (now() AT TIME ZONE 'Europe/Prague')::date;
BEGIN
  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
  IF v_b.user_id <> v_uid AND NOT is_admin() THEN
    RETURN jsonb_build_object('error', 'forbidden');
  END IF;
  v_self := _is_self_service_booking(p_booking_id);

  RETURN jsonb_build_object(
    'is_self_service', v_self,
    'started_at',  v_b.handover_protocol_started_at,
    'deadline',    NULL::timestamptz,   -- 2026-09-25: 1h okno + autofill zrušeny
    'filled_at',   v_b.handover_protocol_filled_at,
    'autofilled',  v_b.handover_protocol_autofilled,
    'locked',      (v_b.handover_protocol_filled_at IS NOT NULL),
    -- podepsat lze po výzvě z kiosku NEBO ode dne začátku termínu (Praha) —
    -- ne týdny předem (protokol = stav km/výbavy v den předání)
    'can_fill',    (v_self
                    AND v_b.status IN ('reserved','active')
                    AND v_b.handover_protocol_filled_at IS NULL
                    AND (v_b.handover_protocol_started_at IS NOT NULL
                         OR (v_b.start_date AT TIME ZONE 'Europe/Prague')::date <= v_today)),
    'needs_locker',      public._booking_needs_locker(p_booking_id),
    'gear_collected_at', v_b.gear_collected_at,
    'prompted_at',       v_b.handover_protocol_prompted_at,
    'start_date',        v_b.start_date
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.start_handover_protocol_window(p_booking_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_b   bookings%ROWTYPE;
BEGIN
  -- 2026-09-25: ponecháno kvůli starým appkám, ale JEN ČTE — okno spouští
  -- kiosk (trg_handover_from_door_event); žádný UPDATE ani push.
  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'not_found'); END IF;
  IF v_b.user_id <> v_uid AND NOT is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
  END IF;
  IF v_b.status NOT IN ('reserved', 'active') THEN
    RETURN jsonb_build_object('success', false, 'error', 'wrong_status');
  END IF;
  IF NOT _is_self_service_booking(p_booking_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_self_service');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'started_at', v_b.handover_protocol_started_at,
    'deadline',   NULL::timestamptz,
    'filled_at',  v_b.handover_protocol_filled_at,
    'autofilled', v_b.handover_protocol_autofilled
  );
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- 8) Zrušení automatického vyplnění po 1 h (rozhodnutí §0.4)
-- ─────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'autofill-handover-protocols') THEN
    PERFORM cron.unschedule('autofill-handover-protocols');
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'cron.unschedule(autofill-handover-protocols) selhalo: %', SQLERRM;
END $$;
DROP FUNCTION IF EXISTS public.autofill_overdue_handover_protocols();

-- ─────────────────────────────────────────────────────────────────────────
-- 9) Pojistka: nejvýš jeden ELEKTRONICKÝ protokol ze samoobsluhy na rezervaci
--    (souběh appka × kiosk řeší atomický claim v edge fn; index je poslední
--    záchrana — edge 23505 → already_filled). Predikát JEN na dokumenty z edge
--    `submit-handover-protocol` (`_self_service = true`): Velín na OBSLUŽNÉ
--    pobočce (ElectronicProtocolModal) vkládá `_doc_type='handover_protocol'`
--    bez `_self_service` a smí protokol vygenerovat opakovaně (oprava podpisu,
--    opakované odbavení) — ten index nehlídá. DROP + CREATE = predikát je vždy
--    tento (žádný starší tvar indexu). Existující duplicity by CREATE shodily
--    → jen varování, migrace projde; ověření viz STATE_1 (generated_documents).
-- ─────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  EXECUTE 'DROP INDEX IF EXISTS public.generated_documents_handover_once';
  EXECUTE 'CREATE UNIQUE INDEX generated_documents_handover_once
             ON public.generated_documents (booking_id)
             WHERE (filled_data->>''_doc_type'') = ''handover_protocol''
               AND (filled_data->>''_self_service'') = ''true''';
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'generated_documents_handover_once: index nevytvořen (duplicitní samoobslužné protokoly?): %', SQLERRM;
END $$;

-- ─────────────────────────────────────────────────────────────────────────
-- 10) Realtime: appka streamuje bookings (stav protokolu) i branch_door_codes
-- ─────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'bookings'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.bookings;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ALTER PUBLICATION supabase_realtime ADD bookings selhalo: %', SQLERRM;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'branch_door_codes'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.branch_door_codes;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ALTER PUBLICATION supabase_realtime ADD branch_door_codes selhalo: %', SQLERRM;
END $$;

NOTIFY pgrst, 'reload schema';
