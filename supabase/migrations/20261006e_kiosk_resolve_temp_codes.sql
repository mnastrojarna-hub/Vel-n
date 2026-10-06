-- 2026-10-06 (zadání majitele D1+D4): kiosk_resolve_code — krátkodobé kódy z Velína + začátek posledního dne pro
-- dokončení vrácení. Převzato 1:1 z 20261005j, přidáno jen:
--  (1) zákaznický kód (ani alias) nenalezen → krátkodobý kód pobočky (branch_temp_codes, 20261006d): nezrušený,
--      v platnosti, na AKTIVNÍCH dveřích téže pobočky → úspěch ve tvaru zákaznického kódu, ale `temp: true`,
--      `temp_code_id`, `booking_id` NULL, kind = druh dveří, BEZ release_at / protocol / odo / return_final_from
--      (jen dané dveře — žádné km, protokol, šatna-první, hradlo 12:00); use_count + last_used_at (chyba nevadí).
--  (2) neplatný kód: krátkodobý kód pobočky prošlý za posledních 24 h → reason 'expired', zrušený za posledních 24 h
--      → 'revoked' (jednotka ≥ 1.2.5 hláška, NEpočítá do lockoutu); starší = holé invalid_code. Důvody zákaznických
--      kódů mají přednost (beze změny).
--  (3) úspěch kódu s rezervací navíc `return_final_from` = _door_code_valid_from(end_date) = pražská půlnoc začátku
--      POSLEDNÍHO dne pronájmu; jednotka ≥ 1.2.8 podle něj offline pozná finální vrácení (return_gate.py). NULL
--      (bez hradla) u SOS náhrady / vozíku / testu — ty server automaticky nedokončuje. Starší jednotka pole
--      ignoruje. Idempotentní (CREATE OR REPLACE).

CREATE OR REPLACE FUNCTION "public"."kiosk_resolve_code"("p_device_id" "uuid", "p_device_token" "uuid", "p_code" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_bid uuid; v_branch public.branches%ROWTYPE; v_cfg public.branch_kiosk_config%ROWTYPE;
  v_door public.branch_doors%ROWTYPE; v_dc public.branch_door_codes%ROWTYPE; v_svc public.branch_service_codes%ROWTYPE;
  v_box integer; v_doors jsonb; v_code text := btrim(coalesce(p_code,''));
  v_release timestamptz; v_moto uuid;
  v_found boolean; v_n integer := 0; v_x public.branch_door_codes%ROWTYPE; v_reason text;
  v_no_gear boolean := false;
  v_temp_id uuid;   -- 2026-10-06: krátkodobý kód (branch_temp_codes)
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
  v_found := FOUND;
  IF NOT v_found THEN
    -- 2026-10-05 (4): dřívější AUTOMATICKY nahrazený kód živé rezervace = alias jejího aktuálního kódu (zákazník
    -- nemusí mít poslední SMS). Jen jednoznačný (číslo nemá jiná živá rezervace ani aktivní kód této pobočky).
    SELECT count(DISTINCT o.booking_id) INTO v_n
      FROM public.branch_door_codes o
      JOIN public.bookings b ON b.id = o.booking_id AND b.status IN ('reserved','active') AND b.is_test IS NOT TRUE
     WHERE o.door_code = v_code AND o.is_active = false AND o.sent_to_customer = true AND o.superseded_by_regen;
    IF v_n = 1 AND NOT EXISTS (SELECT 1 FROM public.branch_door_codes x
                                WHERE x.branch_id = v_bid AND x.door_code = v_code AND x.is_active) THEN
      SELECT n.* INTO v_dc
        FROM public.branch_door_codes o
        JOIN public.bookings b ON b.id = o.booking_id AND b.status IN ('reserved','active') AND b.is_test IS NOT TRUE
        JOIN public.branch_door_codes n ON n.booking_id = o.booking_id AND n.code_type = o.code_type
             AND n.branch_id = v_bid AND n.is_active AND n.sent_to_customer
             AND (n.valid_from IS NULL OR n.valid_from <= now()) AND (n.valid_until IS NULL OR n.valid_until >= now())
       WHERE o.door_code = v_code AND o.is_active = false AND o.sent_to_customer = true AND o.superseded_by_regen
       ORDER BY n.updated_at DESC LIMIT 1;
      v_found := FOUND;
      IF v_found THEN
        BEGIN
          INSERT INTO public.debug_log(source, action, status, request_data)
          VALUES ('kiosk_resolve_code', 'door_code_alias', 'info', jsonb_build_object(
            'booking_id', v_dc.booking_id, 'code_type', v_dc.code_type, 'current_code_id', v_dc.id, 'branch_id', v_bid));
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
      END IF;
    END IF;
  END IF;
  IF NOT v_found THEN
    -- 2026-10-06 (D4): krátkodobý kód z Velína (branch_temp_codes) — až po zákaznických kódech (shodné číslo živé
    -- rezervace má přednost; vydání kolize vylučuje). Nejnovější nezrušený v platnosti, jen AKTIVNÍ dveře pobočky.
    SELECT t.id INTO v_temp_id
      FROM public.branch_temp_codes t
      JOIN public.branch_doors d ON d.id = t.door_id AND d.branch_id = v_bid AND d.is_active
     WHERE t.branch_id = v_bid AND t.code = v_code AND t.revoked_at IS NULL
       AND t.valid_from <= now() AND t.valid_until >= now()
     ORDER BY t.created_at DESC LIMIT 1;
    IF v_temp_id IS NOT NULL THEN
      SELECT d.* INTO v_door FROM public.branch_temp_codes t JOIN public.branch_doors d ON d.id = t.door_id
       WHERE t.id = v_temp_id;
      -- počítadlo použití pro Velín — best-effort, nikdy nečeká na zámek (anon má statement_timeout 3 s)
      BEGIN
        UPDATE public.branch_temp_codes SET use_count = use_count + 1, last_used_at = now()
         WHERE id IN (SELECT id FROM public.branch_temp_codes WHERE id = v_temp_id FOR UPDATE SKIP LOCKED);
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
      -- tvar jako úspěch zákaznického kódu, ale bez rezervace a hradel: jednotka otevře JEN tyto dveře
      RETURN jsonb_build_object('ok',true,'kind',v_door.door_kind,'branch_id',v_bid,'branch_name',v_branch.name,
        'booking_id',NULL,'box_number',v_door.box_number,
        'music_on_url',v_cfg.music_on_url,'music_off_url',v_cfg.music_off_url,'music_seconds',COALESCE(v_cfg.music_seconds,90),
        'door_open_seconds',COALESCE(v_cfg.door_open_seconds,8),'light_seconds',COALESCE(v_cfg.light_seconds,120),
        'door',jsonb_build_object('id',v_door.id,'door_kind',v_door.door_kind,
          'box_number',v_door.box_number,'label',v_door.label,'relay_url',v_door.relay_url,'light_url',v_door.light_url),
        'door_configured',true,
        'release_at',NULL,'protocol',NULL,'odo',NULL,'return_final_from',NULL,
        'temp',true,'temp_code_id',v_temp_id);
    END IF;
  END IF;
  IF NOT v_found THEN
    -- 2026-10-05: kód, který už nic neotevře (nahrazený, zneplatněný, prošlý) nebo začne platit do 24 h → `reason`
    -- (jednotka ≥ 1.2.5: hláška, NEpočítá se do lockoutu). Zadržený, vzdáleně budoucí kód a kód jiné pobočky = holé
    -- invalid_code (počítá se) — jinak by displej bez trestu prozrazoval kódy, které jednou otevřou (hádání).
    SELECT * INTO v_x FROM public.branch_door_codes c
     WHERE c.branch_id = v_bid AND c.door_code = v_code AND c.is_active ORDER BY c.updated_at DESC LIMIT 1;
    IF NOT FOUND AND v_n = 1 THEN
      -- alias, jehož aktuální kód teď neplatí → důvod podle aktuálního kódu té rezervace
      SELECT n.* INTO v_x FROM public.branch_door_codes o
        JOIN public.branch_door_codes n ON n.booking_id = o.booking_id AND n.code_type = o.code_type AND n.is_active
       WHERE o.door_code = v_code AND o.is_active = false AND o.sent_to_customer = true AND o.superseded_by_regen
       ORDER BY (n.branch_id = v_bid) DESC, n.updated_at DESC LIMIT 1;
      IF NOT FOUND THEN v_reason := 'revoked'; END IF;
    END IF;
    IF v_x.id IS NOT NULL THEN
      IF v_x.branch_id <> v_bid OR NOT coalesce(v_x.sent_to_customer, false) THEN v_reason := NULL;
      ELSIF v_x.valid_from IS NOT NULL AND v_x.valid_from > now() THEN
        v_reason := CASE WHEN v_x.valid_from <= now() + interval '24 hours' THEN 'not_yet_valid' END;
      ELSIF v_x.valid_until IS NOT NULL AND v_x.valid_until < now() THEN v_reason := 'expired';
      END IF;
    ELSIF v_reason IS NULL THEN
      IF EXISTS (SELECT 1 FROM public.branch_door_codes o
                   JOIN public.bookings b ON b.id = o.booking_id
                  WHERE o.door_code = v_code AND o.is_active = false AND o.sent_to_customer = true
                    AND b.status IN ('reserved','active') AND b.is_test IS NOT TRUE
                    AND EXISTS (SELECT 1 FROM public.branch_door_codes n
                                 WHERE n.booking_id = o.booking_id AND n.code_type = o.code_type AND n.id <> o.id
                                   AND n.is_active AND n.sent_to_customer)) THEN
        v_reason := 'replaced';
      ELSIF EXISTS (SELECT 1 FROM public.branch_door_codes o
                     WHERE o.door_code = v_code AND o.is_active = false AND o.sent_to_customer = true
                       AND (o.branch_id = v_bid OR EXISTS (SELECT 1 FROM public.bookings b
                                                             WHERE b.id = o.booking_id AND b.status IN ('reserved','active')))) THEN
        v_reason := 'revoked';
      END IF;
    END IF;
    -- 2026-10-05: kód šatny stažený, protože rezervace nemá vybranou výbavu (_booking_needs_locker) → no_gear
    -- (jednotka ≥ 1.2.7: „Rezervace nemá zapůjčenou výbavu — zadejte kód k motorce“; starší = hláška revoked)
    IF v_reason = 'revoked' THEN
      v_no_gear := EXISTS (SELECT 1 FROM public.branch_door_codes o
                             JOIN public.bookings b ON b.id = o.booking_id
                            WHERE o.door_code = v_code AND o.code_type = 'accessories' AND o.is_active = false
                              AND o.sent_to_customer = true
                              AND b.status IN ('reserved','active') AND b.is_test IS NOT TRUE
                              AND NOT public._booking_needs_locker(b.id)
                              AND NOT EXISTS (SELECT 1 FROM public.branch_door_codes a
                                               WHERE a.booking_id = b.id AND a.code_type = 'accessories' AND a.is_active)
                              AND EXISTS (SELECT 1 FROM public.branch_door_codes m
                                           WHERE m.booking_id = b.id AND m.code_type = 'motorcycle' AND m.is_active));
    END IF;
    -- 2026-10-06 (D4): krátkodobý kód pobočky prošlý / zrušený za posledních 24 h → expired / revoked (hláška, bez
    -- lockoutu); starší = holé invalid_code. Důvod zákaznického kódu (výše) má přednost.
    IF v_reason IS NULL THEN
      SELECT CASE WHEN t.revoked_at IS NOT NULL THEN 'revoked' ELSE 'expired' END INTO v_reason
        FROM public.branch_temp_codes t
       WHERE t.branch_id = v_bid AND t.code = v_code
         AND ((t.revoked_at IS NOT NULL AND t.revoked_at >= now() - interval '24 hours')
           OR (t.revoked_at IS NULL AND t.valid_until < now() AND t.valid_until >= now() - interval '24 hours'))
       ORDER BY t.created_at DESC LIMIT 1;
    END IF;
    RETURN jsonb_build_object('ok',false,'error','invalid_code')
      || CASE WHEN v_reason IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('reason', v_reason) END
      || CASE WHEN v_reason = 'replaced' THEN jsonb_build_object('replaced', true) ELSE '{}'::jsonb END
      || CASE WHEN v_no_gear THEN jsonb_build_object('no_gear', true) ELSE '{}'::jsonb END;
  END IF;

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
               THEN public._kiosk_odometer(v_dc.booking_id, v_bid) END,
    -- 5) `return_final_from` (2026-10-06, D1): pražská půlnoc začátku POSLEDNÍHO dne pronájmu — zavření kóje po
    --    vrácení od tohoto okamžiku je finální (offline hradlo jednotky ≥ 1.2.8); NULL = bez hradla — i u SOS
    --    náhrady / vozíku / testu, které server automaticky nedokončí (kiosk_process_returns → skipped)
    'return_final_from',CASE WHEN v_dc.booking_id IS NOT NULL
               THEN (SELECT public._door_code_valid_from(b.end_date) FROM public.bookings b WHERE b.id = v_dc.booking_id
                        AND NOT COALESCE(b.sos_replacement, false) AND b.trailer_moto_id IS NULL AND b.is_test IS NOT TRUE) END);
END; $$;

ALTER FUNCTION public.kiosk_resolve_code(uuid, uuid, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.kiosk_resolve_code(uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.kiosk_resolve_code(uuid, uuid, text) TO anon, authenticated, service_role;
