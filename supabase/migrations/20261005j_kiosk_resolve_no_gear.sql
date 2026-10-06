-- 2026-10-05: kiosk_resolve_code — kód ŠATNY stažený proto, že rezervace nemá vybranou výbavu (pravidlo
-- 20261005g, úklid 20261005k, přepnutí „Mám vlastní výbavu“ v úpravě): kiosk dřív hlásil „Kód už neplatí —
-- rezervace byla zrušena nebo ukončena…“ (reason revoked) a zákazník se lekl, že nemá rezervaci. Nově navíc
-- příznak `no_gear: true` (zpětně kompatibilní jako `replaced: true` — jednotka < 1.2.7 ho ignoruje a ukáže revoked);
-- jednotka ≥ 1.2.7: „Rezervace nemá zapůjčenou výbavu — šatnu nepotřebujete. Zadejte kód k motorce.“ (bez lockoutu).
-- Zbytek funkce beze změny (20261005b). Idempotentní (CREATE OR REPLACE).

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
               THEN public._kiosk_odometer(v_dc.booking_id, v_bid) END);
END; $$;

ALTER FUNCTION public.kiosk_resolve_code(uuid, uuid, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.kiosk_resolve_code(uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.kiosk_resolve_code(uuid, uuid, text) TO anon, authenticated, service_role;
