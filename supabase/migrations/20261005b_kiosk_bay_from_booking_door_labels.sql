-- 2026-10-05 — kiosk ukázal / otevřel jinou motorku (hlášení majitele, Velké Němčice):
-- „Zákazník měl Hondu CRF 1000 Africa Twin v kóji 5, kiosk řekl ,otevřete kóji 5‘, ale ukázal Yamahu XTZ 1200.“
--
-- (1) DATA: Velín (ensureDoors) zakládal dveře s popisem „Kóje N — <model motorky, která tam v tu chvíli stála>“.
--     Motorky se mezi kójemi přesouvají (prohození šipkami, přečíslování), popis dveří se ale nikdy neměnil →
--     jednotka (Zone.display_name), Velín (log, živý panel protokolu) i upozornění ukazovaly starý model.
--     Popis kóje motorky, který je vygenerovaný („Kóje N — …“, „Garáž #N — …“) nebo obsahuje model některé
--     motorky, se vynuluje (= výchozí „Kóje N“). Šatna se nemění. Dotčeným pobočkám kiosk_request_sync.
-- (2) kiosk_resolve_code + kiosk_sync_config.codes[]: kóje motorky se dosud brala z branch_door_codes.moto_id,
--     protokol z bookings.moto_id — při rozjetí (Velín „Aktivovat“ starého kódu po změně motorky, regen spadlý
--     do WARNING) se otevřela kóje jiné motorky, než ukazoval protokol. Nově obojí z motorky REZERVACE, jen motorka
--     této pobočky s kójí ≥ 1 (jinak se kóje neotevře — „není nastaveno“, nikdy cizí kóje); nesoulad → debug_log.
--     Těla obou funkcí = živý snapshot 2026-10-05 (supabase-live-snapshot) + jen výše popsané řádky.
-- (3) Duplicitní číslo kóje: dvě motorky pobočky se stejným box_number (přesun z jiné pobočky přes
--     admin_move_motorcycle číslo kóje ponechal, nedokončené prohození šipkami) → kiosk otevřel kóji, v níž
--     mohla stát jiná motorka, než ukázal protokol. Resolve i offline cache při konfliktu kóji NEotevřou
--     (debug_log box_conflict); přesun motorky na pobočku, kde je její číslo kóje obsazené, číslo vynuluje
--     (trigger trg_moto_branch_move_free_box — admin kóji přiřadí ve Velíně; Velín duplicity zvýrazňuje).
-- Idempotentní (CREATE OR REPLACE, DROP TRIGGER IF EXISTS, UPDATE jen dosud nevyčištěných popisů).

-- (1) popisy dveří kójí bez modelu motorky
DO $$
DECLARE r record; v_branches uuid[] := '{}'; v_n int := 0;
BEGIN
  FOR r IN
    UPDATE public.branch_doors d SET label = NULL
     WHERE d.door_kind = 'motorcycle' AND nullif(btrim(d.label), '') IS NOT NULL
       AND (d.label ~* '^\s*(k[óo]je|koj[eě]|gar[áa][žz])\s*(č\.\s*)?#?\s*\d+\s*[—–:-]'
            OR EXISTS (SELECT 1 FROM public.motorcycles m
                        WHERE length(btrim(coalesce(m.model, ''))) >= 4
                          AND position(lower(btrim(m.model)) IN lower(d.label)) > 0))
    RETURNING d.id, d.branch_id
  LOOP
    v_n := v_n + 1;
    IF NOT r.branch_id = ANY(v_branches) THEN v_branches := array_append(v_branches, r.branch_id); END IF;
  END LOOP;
  RAISE NOTICE 'branch_doors: vynulováno % popisů kójí s modelem motorky', v_n;
  FOR i IN 1 .. coalesce(array_length(v_branches, 1), 0) LOOP
    PERFORM public.kiosk_request_sync(v_branches[i]);
  END LOOP;
END $$;

-- (2a) kiosk_resolve_code
CREATE OR REPLACE FUNCTION "public"."kiosk_resolve_code"("p_device_id" "uuid", "p_device_token" "uuid", "p_code" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_bid uuid; v_branch public.branches%ROWTYPE; v_cfg public.branch_kiosk_config%ROWTYPE;
  v_door public.branch_doors%ROWTYPE; v_dc public.branch_door_codes%ROWTYPE; v_svc public.branch_service_codes%ROWTYPE;
  v_box integer; v_doors jsonb; v_code text := btrim(coalesce(p_code,''));
  v_release timestamptz; v_moto uuid;
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
    -- 2026-10-05: kóje podle motorky REZERVACE (stejný zdroj jako protokol _kiosk_protocol → bookings.moto_id);
    -- kód bez rezervace podle své motorky. Motorka musí stát na TÉTO pobočce s kójí ≥ 1 — jinak se nic
    -- neotevře (door NULL → jednotka „není nastaveno“), nikdy cizí kóje. Nesoulad kód × rezervace → debug_log.
    v_moto := v_dc.moto_id;
    IF v_dc.booking_id IS NOT NULL THEN
      SELECT coalesce(b.moto_id, v_dc.moto_id) INTO v_moto FROM public.bookings b WHERE b.id = v_dc.booking_id;
      IF v_moto IS DISTINCT FROM v_dc.moto_id THEN
        BEGIN
          INSERT INTO public.debug_log(source, action, status, request_data)
          VALUES ('kiosk_resolve_code', 'door_code_moto_mismatch', 'warning', jsonb_build_object(
            'booking_id', v_dc.booking_id, 'code_id', v_dc.id, 'code_moto_id', v_dc.moto_id,
            'booking_moto_id', v_moto, 'branch_id', v_bid));
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
      END IF;
    END IF;
    SELECT m.box_number INTO v_box FROM public.motorcycles m
     WHERE m.id = v_moto AND m.branch_id = v_bid AND m.box_number >= 1;
    -- dvě (nevyřazené) motorky pobočky se stejným číslem kóje → nevíme, která v kóji stojí → neotevírat
    IF v_box IS NOT NULL AND EXISTS (SELECT 1 FROM public.motorcycles m2
         WHERE m2.branch_id = v_bid AND m2.box_number = v_box AND m2.id <> v_moto
           AND m2.status IS DISTINCT FROM 'retired') THEN
      BEGIN
        INSERT INTO public.debug_log(source, action, status, request_data)
        VALUES ('kiosk_resolve_code', 'box_conflict', 'error', jsonb_build_object(
          'booking_id', v_dc.booking_id, 'moto_id', v_moto, 'box_number', v_box, 'branch_id', v_bid));
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
      v_box := NULL;
    END IF;
    SELECT * INTO v_door FROM public.branch_doors WHERE branch_id=v_bid AND door_kind='motorcycle' AND box_number=v_box AND is_active LIMIT 1;
  END IF;

  -- 2b) VÝDEJ AŽ OD 12:00 (2026-10-01h): rezervace se slevou za pozdní
  --     vyzvednutí (samoobsluha, převzetí na pobočce) se vydává — šatna
  --     i motorka — až od 12:00 Prahy v den začátku. Dřív = srozumitelná
  --     hláška + výzva k úpravě rezervace; do lockoutu se nepočítá.
  IF v_dc.booking_id IS NOT NULL THEN
    v_release := public._kiosk_release_at(v_dc.booking_id);
    IF v_release IS NOT NULL AND now() < v_release THEN
      RETURN jsonb_build_object('ok',false,'error','pickup_too_early','kind',v_dc.code_type,
        'booking_id',v_dc.booking_id,'box_number',coalesce(v_door.box_number,v_box),'release_at',v_release);
    END IF;
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
    'release_at',v_release,
    'protocol',CASE WHEN v_dc.booking_id IS NULL THEN NULL ELSE public._kiosk_protocol(v_dc.booking_id) END,
    'odo',CASE WHEN v_dc.code_type = 'motorcycle' AND v_dc.booking_id IS NOT NULL
               THEN public._kiosk_odometer(v_dc.booking_id, v_bid) END);
END; $$;

-- (2b) kiosk_sync_config
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
    -- release_at (2026-10-01h): výdej až od 12:00 (sleva za pozdní vyzvednutí)
    -- — u každého řádku, aby offline jednotka hradlo vynutila i po delším výpadku
    'release_at', CASE WHEN bdc.booking_id IS NOT NULL THEN public._kiosk_release_at(bdc.booking_id) END,
    'door_id', d.id,
    'box_number', CASE WHEN bdc.code_type = 'motorcycle' THEN coalesce(d.box_number, m.box_number) ELSE d.box_number END,
    -- odo (2026-09-29): jen kód motorky s platností od ≤ 1 dne — offline vrácení (jednotka přepočte days svými hodinami)
    'odo', CASE WHEN bdc.code_type = 'motorcycle' AND bdc.booking_id IS NOT NULL
                 AND (bdc.valid_from IS NULL OR bdc.valid_from <= now() + interval '1 day')
                THEN public._kiosk_odometer(bdc.booking_id, v_bid) END)
    ORDER BY bdc.valid_until DESC NULLS LAST, bdc.updated_at DESC), '[]'::jsonb)
  INTO v_codes
  FROM public.branch_door_codes bdc
  -- 2026-10-05: kóje podle motorky REZERVACE (jako kiosk_resolve_code), jen motorka této pobočky s kójí ≥ 1;
  -- jinak řádek bez door_id/box_number → offline jednotka nic neotevře (nikdy cizí kóje)
  LEFT JOIN public.bookings bk ON bk.id = bdc.booking_id
  LEFT JOIN public.motorcycles m ON m.id = coalesce(bk.moto_id, bdc.moto_id) AND m.branch_id = v_bid AND m.box_number >= 1
        AND NOT EXISTS (SELECT 1 FROM public.motorcycles m2 WHERE m2.branch_id = v_bid AND m2.box_number = m.box_number
                         AND m2.id <> m.id AND m2.status IS DISTINCT FROM 'retired')
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

ALTER FUNCTION public.kiosk_resolve_code(uuid, uuid, text) OWNER TO postgres;
ALTER FUNCTION public.kiosk_sync_config(uuid, uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.kiosk_resolve_code(uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.kiosk_resolve_code(uuid, uuid, text) TO anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.kiosk_sync_config(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.kiosk_sync_config(uuid, uuid) TO anon, authenticated, service_role;

-- (3) přesun motorky na pobočku s obsazeným číslem kóje → bez kóje (nikdy dvě motorky v jedné kóji)
CREATE OR REPLACE FUNCTION public._moto_branch_move_free_box()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.branch_id IS NOT NULL AND NEW.box_number IS NOT NULL AND NEW.box_number >= 1
     AND EXISTS (SELECT 1 FROM public.motorcycles m
                  WHERE m.branch_id = NEW.branch_id AND m.box_number = NEW.box_number AND m.id <> NEW.id
                    AND m.status IS DISTINCT FROM 'retired') THEN
    RAISE NOTICE 'motorka % přesunuta na pobočku %: kóje % je obsazená → bez kóje', NEW.id, NEW.branch_id, NEW.box_number;
    NEW.box_number := NULL;
  END IF;
  RETURN NEW;
END;
$$;
ALTER FUNCTION public._moto_branch_move_free_box() OWNER TO postgres;
REVOKE ALL ON FUNCTION public._moto_branch_move_free_box() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_moto_branch_move_free_box ON public.motorcycles;
CREATE TRIGGER trg_moto_branch_move_free_box BEFORE UPDATE OF branch_id ON public.motorcycles
  FOR EACH ROW WHEN (OLD.branch_id IS DISTINCT FROM NEW.branch_id)
  EXECUTE FUNCTION public._moto_branch_move_free_box();
