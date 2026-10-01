-- =============================================================================
-- Samoobsluha: čas vyzvednutí řídí slevu za pozdní vyzvednutí; kiosk vydá
-- takovou rezervaci až od 12:00 (zadání majitele 2026-10-01, ruší 2026-10-01 C)
-- Migrace: 20261001h_selfservice_late_pickup_kiosk_gate.sql
--
-- Zadání: u samoobslužné pobočky si zákazník (web, appka) volí jen čas
-- VYZVEDNUTÍ — řídí slevu 50 % na 1. den (vyzvednutí od 12:00, výpůjčka
-- 2+ dny); čas vrácení se nevolí (23:59 / smlouva do 24:00). Rezervaci se
-- slevou kiosk vydá až od 12:00 v den začátku; kód zadaný dřív = srozumitelná
-- hláška a výzva k úpravě rezervace (dřívější čas = sleva zanikne, doplatek).
--
--  1) `_kiosk_release_at(booking)` — 12:00 Europe/Prague dne začátku, jen pro
--     rezervaci se slevou (`late_pickup_discount_amount > 0` — skutečně
--     přiznané peníze, ne pickup_time, který jde měnit odděleně), samoobslužná
--     pobočka (`_is_self_service_booking`), převzetí na pobočce (ne přistavení),
--     reserved/active, ještě nevyzvednutá (`picked_up_at` NULL), ne SOS náhrada;
--     jinak NULL (bez hradla).
--  2) `kiosk_resolve_code` — kód (šatna i motorka) takové rezervace před
--     release_at → {ok:false, error:'pickup_too_early', kind, booking_id,
--     box_number, release_at} (jednotka ukáže hlášku, do lockoutu se
--     nepočítá); úspěšná odpověď nese `release_at` (informativně).
--  3) `kiosk_sync_config` — každý řádek codes[] nese `release_at` (offline
--     hradlo jednotky).
--  4) `get_handover_protocol_state` — `can_fill` až od release_at + `release_at`
--     v odpovědi (appka nepodepíše protokol před 12:00).
--  5) `trg_booking_kiosk_release_sync` — změna slevy/začátku/převzetí/místa
--     vyzvednutí rezervace s kódy → `kiosk_request_sync` dotčených poboček
--     (offline cache jednotky se srovná hned, ne až do 60 s).
--  6) `_apply_booking_changes_core` — (a) u AKTIVNÍ rezervace nelze změnit čas
--     vyzvednutí (`active_pickup_time_locked`; dřív šlo po převzetí posunout
--     čas na ≥ 12:00 a dostat 50 % 1. dne zpět); (b) získaná late sleva krácená
--     stornem se ukládá jen v přiznané výši (`late_pickup_to` = uložená
--     hodnota). Tělo jinak převzato z 20261001d (živá verze).
-- Signatury beze změny. Idempotentní.
-- =============================================================================

CREATE OR REPLACE FUNCTION public._kiosk_release_at(p_booking_id uuid)
RETURNS timestamptz LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE
    WHEN COALESCE(b.late_pickup_discount_amount, 0) > 0
     AND b.status IN ('reserved', 'active')
     AND b.picked_up_at IS NULL
     AND NOT COALESCE(b.sos_replacement, false)
     AND COALESCE(b.pickup_method, '') <> 'delivery'
     AND public._addr_norm(b.pickup_address) IS NULL
     AND public._is_self_service_booking(b.id)
    THEN (((b.start_date AT TIME ZONE 'Europe/Prague')::date + time '12:00') AT TIME ZONE 'Europe/Prague')
  END
  FROM public.bookings b WHERE b.id = p_booking_id
$$;
REVOKE ALL ON FUNCTION public._kiosk_release_at(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._kiosk_release_at(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.kiosk_resolve_code(p_device_id uuid, p_device_token uuid, p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_bid uuid; v_branch public.branches%ROWTYPE; v_cfg public.branch_kiosk_config%ROWTYPE;
  v_door public.branch_doors%ROWTYPE; v_dc public.branch_door_codes%ROWTYPE; v_svc public.branch_service_codes%ROWTYPE;
  v_box integer; v_doors jsonb; v_code text := btrim(coalesce(p_code,''));
  v_release timestamptz;
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
END; $function$;

CREATE OR REPLACE FUNCTION public.kiosk_sync_config(p_device_id uuid, p_device_token uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
END; $function$;

CREATE OR REPLACE FUNCTION public.get_handover_protocol_state(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_b   bookings%ROWTYPE;
  v_self boolean;
  v_today date := (now() AT TIME ZONE 'Europe/Prague')::date;
  v_unit text;
  v_release timestamptz;
BEGIN
  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
  -- IS DISTINCT FROM (2026-09-29): rezervaci s user_id NULL nesmí číst cizí přihlášený zákazník
  IF v_b.user_id IS DISTINCT FROM v_uid AND NOT is_admin() THEN
    RETURN jsonb_build_object('error', 'forbidden');
  END IF;
  v_self := _is_self_service_booking(p_booking_id);
  v_release := public._kiosk_release_at(p_booking_id);
  SELECT CASE WHEN m.tracking_unit = 'mh' THEN 'mh' ELSE 'km' END INTO v_unit FROM motorcycles m WHERE m.id = v_b.moto_id;

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
                         OR (v_b.start_date AT TIME ZONE 'Europe/Prague')::date <= v_today)
                    -- 2026-10-01h: sleva za pozdní vyzvednutí → podpis až od 12:00
                    AND (v_release IS NULL OR now() >= v_release)),
    'release_at',  v_release,
    'needs_locker',      public._booking_needs_locker(p_booking_id),
    'gear_collected_at', v_b.gear_collected_at,
    'prompted_at',       v_b.handover_protocol_prompted_at,
    'start_date',        v_b.start_date,
    -- 2026-09-29: km do protokolu vyplní systém — appka jen zobrazí, edge zapíše (form.mileage appky ignoruje)
    'mileage',           public._handover_pickup_km(p_booking_id),
    'mileage_unit',      COALESCE(v_unit, 'km')
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.trg_booking_kiosk_release_sync()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record;
BEGIN
  FOR r IN SELECT DISTINCT bdc.branch_id FROM public.branch_door_codes bdc
            WHERE bdc.booking_id = NEW.id AND bdc.is_active AND bdc.branch_id IS NOT NULL LOOP
    BEGIN
      PERFORM public.kiosk_request_sync(r.branch_id);
    EXCEPTION WHEN OTHERS THEN NULL;   -- resync je best-effort, nesmí shodit úpravu rezervace
    END;
  END LOOP;
  RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS trg_booking_kiosk_release_sync ON public.bookings;
CREATE TRIGGER trg_booking_kiosk_release_sync
  AFTER UPDATE OF late_pickup_discount_amount, start_date, picked_up_at, pickup_method, pickup_address, status, moto_id
  ON public.bookings FOR EACH ROW
  WHEN (OLD.late_pickup_discount_amount IS DISTINCT FROM NEW.late_pickup_discount_amount
        OR OLD.start_date IS DISTINCT FROM NEW.start_date
        OR OLD.picked_up_at IS DISTINCT FROM NEW.picked_up_at
        OR OLD.pickup_method IS DISTINCT FROM NEW.pickup_method
        OR OLD.pickup_address IS DISTINCT FROM NEW.pickup_address
        OR OLD.status IS DISTINCT FROM NEW.status
        OR OLD.moto_id IS DISTINCT FROM NEW.moto_id)
  EXECUTE FUNCTION public.trg_booking_kiosk_release_sync();

CREATE OR REPLACE FUNCTION "public"."_apply_booking_changes_core"(
  "p_user_id" "uuid", "p_booking_id" "uuid", "p_new_start" "date", "p_new_end" "date",
  "p_new_moto_id" "uuid", "p_new_pickup_method" "text", "p_new_pickup_address" "text",
  "p_new_pickup_lat" double precision, "p_new_pickup_lng" double precision, "p_new_pickup_fee" numeric,
  "p_new_return_method" "text", "p_new_return_address" "text", "p_new_return_lat" double precision,
  "p_new_return_lng" double precision, "p_new_return_fee" numeric, "p_reason" "text",
  "p_dry_run" boolean, "p_source" "text", "p_new_pickup_time" time DEFAULT NULL) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_b               bookings%ROWTYPE;
  v_old_moto        motorcycles%ROWTYPE;
  v_new_moto        motorcycles%ROWTYPE;
  v_use_moto        motorcycles%ROWTYPE;
  v_fs date := NULL;  v_fe date := NULL;
  v_old_dates_total numeric := 0;
  v_new_dates_total numeric := 0;
  v_dates_diff      numeric := 0;
  v_moto_diff       numeric := 0;
  v_pickup_fee_diff numeric := 0;
  v_return_fee_diff numeric := 0;
  v_gross_diff      numeric := 0;
  v_net_diff        numeric := 0;
  v_refund          numeric := 0;
  v_storno_pct      int := 100;
  v_now             timestamptz := now();
  v_overlap_count   int;
  v_user_lic        text[];
  v_lic_required    text;
  v_d               date;
  v_dow             int;
  v_p_old           numeric;
  v_p_new           numeric;
  v_history_entry   jsonb;
  v_is_active       boolean;
  v_payment_required boolean := false;
  v_changed         boolean := false;
  v_dtype           text;
  v_calc            jsonb;
  v_new_total       numeric;
  v_new_discount    numeric;
  v_url             text;
  v_key             text;
  v_old_late        numeric := 0;
  v_new_late        numeric := 0;
  v_eff_pickup      time;
  v_pickup_changed  boolean := false;
  v_loy_level       int := 0;
  v_loy_pct         numeric := 0;
  v_loy_disc        numeric := 0;
  v_new_on_old_total numeric := 0;   -- nový rozsah oceněný ceníkem STARÉ motorky
  v_new_late_old    numeric := 0;
  v_late_unrefunded numeric := 0;    -- 2026-10-01h: neproplacená část získané late slevy (storno)
  v_late_store      numeric := 0;    -- late sleva, která se ULOŽÍ (= skutečně přiznaná)    -- late sleva nového rozsahu dle STARÉ motorky
  v_moto_swapped    boolean := false;
  v_refund_reason   text;
  -- 2026-10-01: přistavení/odvoz po stranách (incident „vratka −11 Kč")
  v_old_pd          boolean;          -- vyzvednutí BYLO přistavením
  v_old_rd          boolean;          -- vrácení BYLO odvozem z adresy
  v_new_pd          boolean;
  v_new_rd          boolean;
  v_pick_loc_changed boolean := false;
  v_ret_loc_changed  boolean := false;
  v_pick_side_changed boolean := false;
  v_ret_side_changed  boolean := false;
  v_old_fee         numeric := 0;
  v_old_pfee        numeric := 0;
  v_old_rfee        numeric := 0;
  v_new_pfee        numeric := 0;
  v_new_rfee        numeric := 0;
  v_new_delivery_fee numeric;
  v_wp              numeric;
  v_wr              numeric;
  v_hp              numeric;
  v_hr              numeric;
  v_split_est       boolean := false;   -- podíly stran jen odhadnuté
  v_ext_p           numeric := 0;       -- poplatek strany v booking_extras (web)
  v_ext_r           numeric := 0;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;

  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND OR v_b.user_id <> p_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  IF v_b.status NOT IN ('reserved','active') OR v_b.payment_status NOT IN ('paid','partial_refund','refund_pending') THEN
    RETURN jsonb_build_object('success', false, 'error', 'wrong_status');
  END IF;

  v_is_active := (v_b.status = 'active');
  v_eff_pickup := COALESCE(p_new_pickup_time, v_b.pickup_time);
  v_pickup_changed := (p_new_pickup_time IS NOT NULL AND p_new_pickup_time IS DISTINCT FROM v_b.pickup_time);

  v_fs := COALESCE(p_new_start, v_b.start_date);
  v_fe := COALESCE(p_new_end,   v_b.end_date);
  IF v_is_active AND v_fs <> v_b.start_date THEN
    RETURN jsonb_build_object('success', false, 'error', 'active_start_locked');
  END IF;
  IF v_fs > v_fe THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_range');
  END IF;
  -- 2026-10-01h: vyzvednutí už proběhlo → čas vyzvednutí se nemění (jinak by
  -- posun na ≥ 12:00 po převzetí vrátil 50 % 1. dne jako slevu za pozdní
  -- vyzvednutí, které se nekonalo)
  IF v_is_active AND v_pickup_changed THEN
    RETURN jsonb_build_object('success', false, 'error', 'active_pickup_time_locked');
  END IF;

  SELECT * INTO v_old_moto FROM motorcycles WHERE id = v_b.moto_id;
  IF p_new_moto_id IS NOT NULL AND p_new_moto_id <> v_b.moto_id THEN
    IF v_is_active THEN
      RETURN jsonb_build_object('success', false, 'error', 'active_moto_locked');
    END IF;
    -- 2026-09-12: i 'maintenance' (web /upravit-rezervaci i appka je nabízejí —
    -- servisní dny blokuje kontrola maintenance_log níže; dřív server vracel
    -- moto_not_found a web výměnu neprovedl).
    SELECT * INTO v_new_moto FROM motorcycles WHERE id = p_new_moto_id AND status IN ('active','maintenance');
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'moto_not_found');
    END IF;
    -- rev. 2026-09-21: vozík vydává jen OBSLUŽNÁ pobočka, takže rezervace
    -- s přiřazeným vozíkem nesmí přejet na motorku ze samoobslužné.
    -- Umístění je ZÁMĚRNÉ: mezi ranými validacemi, tedy PŘED `IF p_dry_run OR
    -- v_payment_required THEN RETURN` i před jakýmkoli zápisem. Web
    -- (/upravit-rezervaci → „Změna motorky") posílá nejdřív dry-run, pak
    -- zákazníka na Stripe a změnu commituje AŽ PO platbě (a to přímým
    -- UPDATE, který se `_apply_booking_changes_core` ani nedotkne) — kontrola
    -- proto MUSÍ padnout už v dry-runu, jinak by se strhly peníze a změna se
    -- stejně nesměla provést. Stejná úvaha jako u `split_booking_moto_swap`
    -- rev.9 (20260921d) a důvod, proč `20260921c` `moto_id` z triggeru
    -- `trg_check_trailer_overlap` odebralo.
    IF v_b.trailer_moto_id IS NOT NULL AND public.moto_is_self_service(p_new_moto_id) THEN
      RETURN jsonb_build_object('success', false, 'error', 'trailer_staffed_only');
    END IF;
    -- OR-match přes VŠECHNY přijímané skupiny ŘP (license_groups; fallback
    -- [license_required]) — parita s katalogem/appkou.
    DECLARE
      v_groups text[] := (SELECT COALESCE(NULLIF(m.license_groups, '{}'::text[]),
                                          ARRAY[COALESCE(m.license_required::text, 'A')])
                            FROM motorcycles m WHERE m.id = v_new_moto.id);
    BEGIN
      IF NOT ('N' = ANY(COALESCE(v_groups, ARRAY['A']))) THEN
        SELECT license_group INTO v_user_lic FROM profiles WHERE id = p_user_id;
        IF v_user_lic IS NULL OR NOT EXISTS (
          SELECT 1 FROM unnest(COALESCE(v_groups, ARRAY['A'])) g
          WHERE v_user_lic && CASE g
            WHEN 'AM' THEN ARRAY['AM','A1','A2','A','B']
            WHEN 'A1' THEN ARRAY['A1','A2','A']
            WHEN 'A2' THEN ARRAY['A2','A']
            WHEN 'A'  THEN ARRAY['A']
            WHEN 'B'  THEN ARRAY['B']
            ELSE ARRAY[g]
          END
        ) THEN
          RETURN jsonb_build_object('success', false, 'error', 'license_insufficient');
        END IF;
      END IF;
    END;
    v_use_moto := v_new_moto;
    v_moto_swapped := true;
  ELSE
    v_use_moto := v_old_moto;
  END IF;

  IF p_new_start IS NOT NULL OR p_new_end IS NOT NULL OR (p_new_moto_id IS NOT NULL AND p_new_moto_id <> v_b.moto_id) THEN
    SELECT COUNT(*) INTO v_overlap_count FROM bookings b2
      WHERE b2.moto_id = v_use_moto.id
        AND b2.id <> p_booking_id
        AND b2.status IN ('pending','reserved','active')
        AND NOT (b2.end_date < v_fs OR b2.start_date > v_fe);
    IF v_overlap_count > 0 THEN
      RETURN jsonb_build_object('success', false, 'error', 'overlap');
    END IF;
    -- Plánovaný SERVIS blokuje termín i server-side (stejná logika jako
    -- split_booking_moto_swap).
    SELECT COUNT(*) INTO v_overlap_count FROM maintenance_log m
      WHERE m.moto_id = v_use_moto.id
        AND m.service_date IS NOT NULL AND m.completed_date IS NULL
        AND COALESCE(m.status,'') NOT IN ('completed','cancelled')
        AND daterange(m.service_date::date, COALESCE(m.scheduled_date, m.service_date)::date, '[]')
            && daterange(v_fs, v_fe, '[]');
    IF v_overlap_count > 0 THEN
      RETURN jsonb_build_object('success', false, 'error', 'overlap');
    END IF;
  END IF;

  v_d := v_b.start_date;
  WHILE v_d <= v_b.end_date LOOP
    v_dow := EXTRACT(ISODOW FROM v_d)::int;
    v_p_old := CASE v_dow
      WHEN 1 THEN COALESCE(v_old_moto.price_mon, v_old_moto.price_weekday, 0)
      WHEN 2 THEN COALESCE(v_old_moto.price_tue, v_old_moto.price_weekday, 0)
      WHEN 3 THEN COALESCE(v_old_moto.price_wed, v_old_moto.price_weekday, 0)
      WHEN 4 THEN COALESCE(v_old_moto.price_thu, v_old_moto.price_weekday, 0)
      WHEN 5 THEN COALESCE(v_old_moto.price_fri, v_old_moto.price_weekday, 0)
      WHEN 6 THEN COALESCE(v_old_moto.price_sat, v_old_moto.price_weekend, 0)
      WHEN 7 THEN COALESCE(v_old_moto.price_sun, v_old_moto.price_weekend, 0)
    END;
    v_old_dates_total := v_old_dates_total + v_p_old;
    v_d := v_d + 1;
  END LOOP;

  v_d := v_fs;
  WHILE v_d <= v_fe LOOP
    v_dow := EXTRACT(ISODOW FROM v_d)::int;
    v_p_new := CASE v_dow
      WHEN 1 THEN COALESCE(v_use_moto.price_mon, v_use_moto.price_weekday, 0)
      WHEN 2 THEN COALESCE(v_use_moto.price_tue, v_use_moto.price_weekday, 0)
      WHEN 3 THEN COALESCE(v_use_moto.price_wed, v_use_moto.price_weekday, 0)
      WHEN 4 THEN COALESCE(v_use_moto.price_thu, v_use_moto.price_weekday, 0)
      WHEN 5 THEN COALESCE(v_use_moto.price_fri, v_use_moto.price_weekday, 0)
      WHEN 6 THEN COALESCE(v_use_moto.price_sat, v_use_moto.price_weekend, 0)
      WHEN 7 THEN COALESCE(v_use_moto.price_sun, v_use_moto.price_weekend, 0)
    END;
    v_new_dates_total := v_new_dates_total + v_p_new;
    v_d := v_d + 1;
  END LOOP;

  -- Nový rozsah oceněný ceníkem STARÉ motorky — základ rozdílu TERMÍNU
  -- (storno se krátí jen odebrané dny, ne rozdíl ceníku motorek).
  v_d := v_fs;
  WHILE v_d <= v_fe LOOP
    v_dow := EXTRACT(ISODOW FROM v_d)::int;
    v_p_old := CASE v_dow
      WHEN 1 THEN COALESCE(v_old_moto.price_mon, v_old_moto.price_weekday, 0)
      WHEN 2 THEN COALESCE(v_old_moto.price_tue, v_old_moto.price_weekday, 0)
      WHEN 3 THEN COALESCE(v_old_moto.price_wed, v_old_moto.price_weekday, 0)
      WHEN 4 THEN COALESCE(v_old_moto.price_thu, v_old_moto.price_weekday, 0)
      WHEN 5 THEN COALESCE(v_old_moto.price_fri, v_old_moto.price_weekday, 0)
      WHEN 6 THEN COALESCE(v_old_moto.price_sat, v_old_moto.price_weekend, 0)
      WHEN 7 THEN COALESCE(v_old_moto.price_sun, v_old_moto.price_weekend, 0)
    END;
    v_new_on_old_total := v_new_on_old_total + v_p_old;
    v_d := v_d + 1;
  END LOOP;

  -- ── LATE PICKUP ── stará = REÁLNĚ uložená hodnota (ne přepočet — jinak by
  -- legacy rezervace bez late vykázala fantomový rozdíl); nová = přepočet pro
  -- nový obsah + efektivní čas vyzvednutí.
  v_old_late     := COALESCE(v_b.late_pickup_discount_amount, 0);
  v_new_late     := public._late_pickup_discount(v_use_moto.id, v_fs, v_fe, v_eff_pickup);
  v_new_late_old := CASE WHEN v_moto_swapped
                         THEN public._late_pickup_discount(v_old_moto.id, v_fs, v_fe, v_eff_pickup)
                         ELSE v_new_late END;

  -- ── ROZDÍL TERMÍNU (ceník STARÉ motorky) — jen tahle část podléhá stornu ──
  v_dates_diff := (v_new_on_old_total - v_new_late_old) - (v_old_dates_total - v_old_late);
  -- ── ROZDÍL VÝMĚNY MOTORKY na novém rozsahu (nový − starý ceník) — 100 % v
  -- obou směrech, storno se NEvztahuje (2026-09-12, parita split_booking_moto_swap
  -- a Velín; incident C69236EB: levnější motorka <48 h před startem → storno 0 %
  -- → rozdíl 0 Kč → žádný dobropis). ──
  v_moto_diff := CASE WHEN v_moto_swapped
                      THEN (v_new_dates_total - v_new_late) - (v_new_on_old_total - v_new_late_old)
                      ELSE 0 END;
  IF v_dates_diff < 0 THEN
    v_storno_pct := CASE
      WHEN EXTRACT(EPOCH FROM (v_fs::timestamptz - v_now))/3600 >= 168 THEN 100
      WHEN EXTRACT(EPOCH FROM (v_fs::timestamptz - v_now))/3600 >= 48  THEN 50
      ELSE 0
    END;
    -- 2026-08-22c: STROP PO POSUNU TERMÍNU — jakmile byl start rezervace
    -- kdykoli posunut, vratka za odebrané dny už nikdy není 100 %
    -- (viz _storno_cap_after_move; vždy přísnější sazba pro zákazníka).
    v_storno_pct := LEAST(v_storno_pct, public._storno_cap_after_move(
      v_b.modification_history, v_b.original_start_date::date, v_b.start_date::date));
    -- 2026-10-01h: získaná late sleva (pozdější čas vyzvednutí) je ve vratce
    -- krácena stornem → uloží se jen přiznaná část (dřív se uložila celá:
    -- faktura pak ukazovala nafouknutý pronájem a kiosk by čekal do 12:00
    -- kvůli slevě, kterou zákazník nedostal). Neproplacená část = storno
    -- z té části zisku, kterou nevyrovnaly přidané dny.
    v_late_unrefunded := ROUND(LEAST(GREATEST(0, v_new_late_old - v_old_late), -v_dates_diff)
                               * (100 - v_storno_pct) / 100.0);
    v_dates_diff := ROUND(v_dates_diff * v_storno_pct / 100.0);
  END IF;
  v_late_store := GREATEST(0, v_new_late - v_late_unrefunded);

  -- ── PŘISTAVENÍ / ODVOZ — po stranách, server je autoritativní ──────────────
  -- 2026-10-01 (incident: aktivní rezervace, přistavení X, zákaznice přidala
  -- odvoz Y → web poslal p_new_pickup_fee=0 za zamčenou stranu vyzvednutí a
  -- jádro připsalo CELÉ staré delivery_fee vyzvednutí → rozdíl Y−X = −11 Kč
  -- = VRATKA místo doplatku Y, delivery_fee přepsáno na Y). Nově:
  --  • přistavení = metoda 'delivery' NEBO vyplněná adresa (web/AI rezervace
  --    nechávají 'store' + adresu — shodně s generate-document a appkou);
  --    adresa poslaná k pobočkové straně ji dělá přistavením (zpoplatní se);
  --  • NEZMĚNĚNÁ strana si nechává svůj podíl delivery_fee — klientem poslaný
  --    poplatek se u ní ignoruje (0, přepočet trasy, cokoli);
  --  • přesun = `_delivery_place_moved` (stejná definice jako DB pojistka);
  --    přesun NIKDY nevrací peníze (GPS posílá klient, šly by podvrhnout) —
  --    jen doplatek, když je nové místo dražší;
  --  • aktivní rezervace: vyzvednutí už proběhlo → strana vyzvednutí je
  --    neměnná (pokus o změnu = active_pickup_locked, poplatek se ignoruje);
  --  • nově přidaná strana stojí aspoň podlahu _delivery_fee_floor (1000 Kč
  --    + 40 Kč × vzdušná čára od Mezné − 2 km; silniční trasa není kratší);
  --  • odebraná strana vrací svůj podíl; je-li rozdělení obou stran jen
  --    ODHAD, nejvýš podlahu té strany (skutečný poplatek je vždy ≥ podlaha);
  --  • nové delivery_fee = staré + rozdíly změněných stran (zbytek zůstává).
  IF (p_new_pickup_lat IS NOT NULL AND NOT (p_new_pickup_lat BETWEEN -90 AND 90))
     OR (p_new_pickup_lng IS NOT NULL AND NOT (p_new_pickup_lng BETWEEN -180 AND 180))
     OR (p_new_return_lat IS NOT NULL AND NOT (p_new_return_lat BETWEEN -90 AND 90))
     OR (p_new_return_lng IS NOT NULL AND NOT (p_new_return_lng BETWEEN -180 AND 180)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_location');
  END IF;
  v_old_pd := (v_b.pickup_method = 'delivery' OR public._addr_norm(v_b.pickup_address) IS NOT NULL);
  v_old_rd := (v_b.return_method = 'delivery' OR public._addr_norm(v_b.return_address) IS NOT NULL);
  -- Metoda NULL nebo shodná s uloženou = druh se mění jen přidanou adresou
  -- (web posílá u volby „pobočka" uloženou metodu, např. 'store' i u
  -- přistavení přes adresu); jiná metoda rozhoduje sama.
  v_new_pd := CASE WHEN p_new_pickup_method IS NULL OR p_new_pickup_method IS NOT DISTINCT FROM v_b.pickup_method
                   THEN v_old_pd OR public._addr_norm(p_new_pickup_address) IS NOT NULL
                   ELSE p_new_pickup_method = 'delivery' END;
  v_new_rd := CASE WHEN p_new_return_method IS NULL OR p_new_return_method IS NOT DISTINCT FROM v_b.return_method
                   THEN v_old_rd OR public._addr_norm(p_new_return_address) IS NOT NULL
                   ELSE p_new_return_method = 'delivery' END;
  IF v_old_pd AND v_new_pd THEN
    v_pick_loc_changed := public._delivery_place_moved(
      v_b.pickup_address, v_b.pickup_lat, v_b.pickup_lng,
      COALESCE(p_new_pickup_address, v_b.pickup_address), p_new_pickup_lat, p_new_pickup_lng);
  END IF;
  IF v_old_rd AND v_new_rd THEN
    v_ret_loc_changed := public._delivery_place_moved(
      v_b.return_address, v_b.return_lat, v_b.return_lng,
      COALESCE(p_new_return_address, v_b.return_address), p_new_return_lat, p_new_return_lng);
  END IF;
  v_pick_side_changed := (v_new_pd IS DISTINCT FROM v_old_pd) OR v_pick_loc_changed;
  v_ret_side_changed  := (v_new_rd IS DISTINCT FROM v_old_rd) OR v_ret_loc_changed;
  IF v_is_active AND v_pick_side_changed THEN
    RETURN jsonb_build_object('success', false, 'error', 'active_pickup_locked');
  END IF;
  -- Přidaná / přesunutá strana BEZ GPS nejde ocenit: podlaha bez souřadnic je
  -- jen základ 1000 Kč a poplatek od volajícího se nedá ověřit (AI agent GPS
  -- neposílá a cenu odhaduje model) → změnu místa na adresu dělá web/appka,
  -- které počítají trasu. Odebrání strany (→ pobočka) GPS nepotřebuje.
  IF (v_pick_side_changed AND v_new_pd AND (p_new_pickup_lat IS NULL OR p_new_pickup_lng IS NULL))
     OR (v_ret_side_changed AND v_new_rd AND (p_new_return_lat IS NULL OR p_new_return_lng IS NULL)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'location_requires_route',
      'message', 'Přistavení nebo vrácení na novou adresu se počítá podle trasy — změňte ho prosím na webu motogo24.cz (Upravit rezervaci) nebo v aplikaci MotoGo24.');
  END IF;

  -- Podíly starého delivery_fee po stranách (DB drží jen součet). Obě strany
  -- přistavením → přesné rozdělení z poslední úpravy v historii, jinak odhad.
  v_old_fee := GREATEST(COALESCE(v_b.delivery_fee, 0), 0);
  IF v_old_pd AND v_old_rd THEN
    -- Přesný podíl z poslední úpravy (od 2026-10-01 historie nese
    -- pickup_fee_to/return_fee_to + fee_split_exact) — platí, jen když byl
    -- přesný a součet sedí na současné delivery_fee (nikdo ji mezitím nezměnil).
    BEGIN
      SELECT (x.e->>'pickup_fee_to')::numeric, (x.e->>'return_fee_to')::numeric
        INTO v_hp, v_hr
        FROM jsonb_array_elements(CASE WHEN jsonb_typeof(v_b.modification_history) = 'array'
                                       THEN v_b.modification_history ELSE '[]'::jsonb END)
             WITH ORDINALITY AS x(e, i)
       WHERE jsonb_typeof(x.e) = 'object' AND x.e ? 'pickup_fee_to' AND x.e ? 'return_fee_to'
         AND x.e->>'fee_split_exact' = 'true'
       ORDER BY x.i DESC LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
      v_hp := NULL; v_hr := NULL;
    END;
    IF v_hp IS NOT NULL AND v_hr IS NOT NULL AND v_hp >= 0 AND v_hr >= 0 AND v_hp + v_hr = v_old_fee THEN
      v_old_pfee := v_hp;
      v_old_rfee := v_hr;
    ELSE
      -- Odhad v poměru podlah dle uložených GPS, bez nich půl na půl.
      v_split_est := true;
      IF v_b.pickup_lat IS NOT NULL AND v_b.pickup_lng IS NOT NULL
         AND v_b.return_lat IS NOT NULL AND v_b.return_lng IS NOT NULL THEN
        v_wp := public._delivery_fee_floor(v_b.pickup_lat, v_b.pickup_lng, 0);
        v_wr := public._delivery_fee_floor(v_b.return_lat, v_b.return_lng, 0);
      ELSE
        v_wp := 1; v_wr := 1;
      END IF;
      v_old_pfee := ROUND(v_old_fee * v_wp / (v_wp + v_wr));
      v_old_rfee := v_old_fee - v_old_pfee;
      -- Odebírá se právě jedna strana → vrací se nejvýš její podlaha
      -- (skutečná cena strany je vždy ≥ podlaha; přeplatek odhadu ne).
      IF NOT v_new_pd AND v_new_rd THEN
        v_old_pfee := LEAST(v_old_pfee, public._delivery_fee_floor(v_b.pickup_lat, v_b.pickup_lng, 2));
        v_old_rfee := v_old_fee - v_old_pfee;
      ELSIF v_new_pd AND NOT v_new_rd THEN
        v_old_rfee := LEAST(v_old_rfee, public._delivery_fee_floor(v_b.return_lat, v_b.return_lng, 2));
        v_old_pfee := v_old_fee - v_old_rfee;
      END IF;
    END IF;
  ELSIF v_old_pd THEN
    v_old_pfee := v_old_fee;
  ELSIF v_old_rd THEN
    v_old_rfee := v_old_fee;
  END IF;
  -- Web rezervace mají poplatek za přistavení v booking_extras (delivery_fee 0):
  -- u přesunuté strany s nulovým podílem se doplácí jen rozdíl proti němu.
  IF v_pick_loc_changed AND v_old_pfee = 0 THEN
    v_ext_p := public._booking_extras_delivery(v_b.id, 'pickup');
  END IF;
  IF v_ret_loc_changed AND v_old_rfee = 0 THEN
    v_ext_r := public._booking_extras_delivery(v_b.id, 'return');
  END IF;

  v_new_pfee := CASE
    WHEN NOT v_pick_side_changed THEN v_old_pfee
    WHEN NOT v_new_pd THEN 0
    -- přesun: nikdy pod dosavadní cenu strany (podíl + položka webu)
    WHEN v_pick_loc_changed THEN v_old_pfee
         + GREATEST(0, GREATEST(ROUND(COALESCE(p_new_pickup_fee, 0)),
                                public._delivery_fee_floor(p_new_pickup_lat, p_new_pickup_lng, 2))
                       - (v_old_pfee + v_ext_p))
    -- nově přidaná strana: cena klienta, nejméně podlaha
    ELSE GREATEST(ROUND(COALESCE(p_new_pickup_fee, 0)),
                  public._delivery_fee_floor(p_new_pickup_lat, p_new_pickup_lng, 2))
    END;
  v_new_rfee := CASE
    WHEN NOT v_ret_side_changed THEN v_old_rfee
    WHEN NOT v_new_rd THEN 0
    WHEN v_ret_loc_changed THEN v_old_rfee
         + GREATEST(0, GREATEST(ROUND(COALESCE(p_new_return_fee, 0)),
                                public._delivery_fee_floor(p_new_return_lat, p_new_return_lng, 2))
                       - (v_old_rfee + v_ext_r))
    ELSE GREATEST(ROUND(COALESCE(p_new_return_fee, 0)),
                  public._delivery_fee_floor(p_new_return_lat, p_new_return_lng, 2))
    END;
  v_pickup_fee_diff  := v_new_pfee - v_old_pfee;
  v_return_fee_diff  := v_new_rfee - v_old_rfee;
  v_new_delivery_fee := GREATEST(0, COALESCE(v_b.delivery_fee, 0) + v_pickup_fee_diff + v_return_fee_diff);

  -- ── VĚRNOSTNÍ SLEVA (2026-08-06) — JEN app rezervace, JEN kladný rozdíl
  -- pronájmu (doplatek za přidané dny / dražší motorku). Aktuální rank
  -- zákazníka, stejný vzorec jako split_booking_moto_swap. Delivery poplatky
  -- slevě nepodléhají (parita se vznikem rezervace).
  IF COALESCE(v_b.booking_source, 'web') = 'app' AND (v_dates_diff + v_moto_diff) > 0 THEN
    v_loy_level := LEAST(20, CEIL((_loyalty_qualifying_count(v_b.user_id) + 1) / 2.0))::int;
    SELECT COALESCE(discount_percent, 0) INTO v_loy_pct FROM loyalty_levels WHERE level = v_loy_level;
    v_loy_pct := COALESCE(v_loy_pct, 0);
    v_loy_disc := ROUND((v_dates_diff + v_moto_diff) * v_loy_pct / 100.0);
  END IF;

  v_gross_diff := v_dates_diff - v_loy_disc + v_moto_diff + v_pickup_fee_diff + v_return_fee_diff;

  -- typ slevy a multi-rozklad řeší _recalc_booking_discount (krok 3c)
  v_calc  := public._recalc_booking_discount(v_b.id, v_b.total_price, v_b.discount_amount, v_gross_diff, false);
  v_net_diff     := (v_calc->>'net_diff')::numeric;
  v_new_total    := (v_calc->>'new_total')::numeric;
  v_new_discount := (v_calc->>'new_discount')::numeric;

  v_changed := (
    v_fs <> v_b.start_date OR v_fe <> v_b.end_date
    OR (p_new_moto_id IS NOT NULL AND p_new_moto_id <> v_b.moto_id)
    OR v_pickup_changed
    OR v_pick_side_changed OR v_ret_side_changed
    OR (NOT v_is_active AND p_new_pickup_method IS NOT NULL AND p_new_pickup_method IS DISTINCT FROM v_b.pickup_method)
    OR (NOT v_is_active AND p_new_pickup_address IS NOT NULL AND p_new_pickup_address IS DISTINCT FROM v_b.pickup_address)
    OR (p_new_return_method IS NOT NULL AND p_new_return_method IS DISTINCT FROM v_b.return_method)
    OR (p_new_return_address IS NOT NULL AND p_new_return_address IS DISTINCT FROM v_b.return_address)
  );
  IF NOT v_changed THEN
    RETURN jsonb_build_object('success', false, 'error', 'no_change');
  END IF;

  v_payment_required := (v_net_diff > 0);
  v_refund := CASE WHEN v_net_diff < 0 THEN -v_net_diff ELSE 0 END;

  IF p_dry_run OR v_payment_required THEN
    RETURN jsonb_build_object(
      'success', true, 'payment_required', v_payment_required,
      'net_diff', v_net_diff, 'refund_amount', v_refund,
      'new_total', v_new_total, 'new_discount', v_new_discount,
      'new_delivery_fee', CASE WHEN v_pick_side_changed OR v_ret_side_changed THEN v_new_delivery_fee ELSE COALESCE(v_b.delivery_fee, 0) END,
      'location_changed', (v_pick_side_changed OR v_ret_side_changed),
      'loyalty_discount', v_loy_disc, 'loyalty_percent', v_loy_pct, 'loyalty_level', v_loy_level,
      'breakdown', jsonb_build_object(
        'dates_diff', v_dates_diff, 'moto_diff', v_moto_diff,
        'pickup_fee_diff', v_pickup_fee_diff, 'return_fee_diff', v_return_fee_diff,
        'pickup_fee_from', v_old_pfee, 'pickup_fee_to', v_new_pfee,
        'return_fee_from', v_old_rfee, 'return_fee_to', v_new_rfee,
        'fee_split_exact', (NOT v_split_est OR NOT (v_new_pd AND v_new_rd)),
        'gross_diff', v_gross_diff, 'discount_type', v_dtype, 'storno_pct', v_storno_pct,
        'late_pickup_from', v_old_late, 'late_pickup_to', v_late_store,
        'loyalty_discount', v_loy_disc, 'loyalty_percent', v_loy_pct
      )
    );
  END IF;

  v_history_entry := jsonb_build_object(
    'at', v_now,
    'from_start', v_b.start_date, 'from_end', v_b.end_date,
    'to_start', v_fs, 'to_end', v_fe,
    'from_moto', v_b.moto_id, 'to_moto', v_use_moto.id,
    'from_pickup_method', v_b.pickup_method,
    'to_pickup_method', CASE WHEN v_is_active THEN v_b.pickup_method ELSE p_new_pickup_method END,
    'from_pickup_address', v_b.pickup_address,
    'to_pickup_address', CASE WHEN v_is_active THEN v_b.pickup_address ELSE p_new_pickup_address END,
    'from_return_method', v_b.return_method, 'to_return_method', p_new_return_method,
    'from_return_address', v_b.return_address, 'to_return_address', p_new_return_address,
    'from_pickup_time', v_b.pickup_time::text, 'to_pickup_time', v_eff_pickup::text,
    'net_diff', v_net_diff, 'gross_diff', v_gross_diff,
    'dates_diff', v_dates_diff, 'moto_diff', v_moto_diff,
    'refund_amount', v_refund, 'storno_pct', v_storno_pct,
    'discount_type', v_dtype, 'from_discount', v_b.discount_amount, 'to_discount', v_new_discount,
    'from_late_pickup', v_old_late, 'to_late_pickup', v_late_store,
    'loyalty_surcharge_discount', v_loy_disc, 'loyalty_percent', v_loy_pct,
    'price_diff', v_net_diff,
    'from_delivery_fee', v_b.delivery_fee,
    'to_delivery_fee', CASE WHEN v_pick_side_changed OR v_ret_side_changed THEN v_new_delivery_fee ELSE v_b.delivery_fee END,
    'pickup_fee_from', v_old_pfee, 'pickup_fee_to', v_new_pfee,
    'return_fee_from', v_old_rfee, 'return_fee_to', v_new_rfee,
    -- přesné rozdělení = žádný odhad, nebo po změně zbyla nejvýš jedna
    -- strana přistavením (její podíl = celé delivery_fee)
    'fee_split_exact', (NOT v_split_est OR NOT (v_new_pd AND v_new_rd)),
    'reason', p_reason, 'source', COALESCE(p_source, 'web_customer')
  );

  UPDATE bookings SET
    original_start_date = COALESCE(original_start_date, start_date),
    original_end_date   = COALESCE(original_end_date,   end_date),
    start_date          = v_fs,
    end_date            = v_fe,
    moto_id             = v_use_moto.id,
    pickup_time         = COALESCE(p_new_pickup_time, pickup_time),
    -- Aktivní rezervace: vyzvednutí proběhlo → sloupce vyzvednutí se nemění.
    -- Strana na pobočce nemá adresu ani GPS (jinak by ji generate-document,
    -- appka i Velín dál četly jako přistavení). GPS se píší u nové strany, při
    -- přesunu (bez GPS = NULL, staré patřily původní adrese) a k doplnění
    -- chybějících; u nezměněné strany zůstávají uložené (bez driftu špendlíku).
    pickup_method       = CASE WHEN v_is_active THEN pickup_method ELSE COALESCE(p_new_pickup_method, pickup_method) END,
    pickup_address      = CASE WHEN v_is_active THEN pickup_address
                               WHEN NOT v_new_pd THEN NULL
                               ELSE COALESCE(p_new_pickup_address, pickup_address) END,
    pickup_lat          = CASE WHEN v_is_active THEN pickup_lat
                               WHEN NOT v_new_pd THEN NULL
                               WHEN NOT v_old_pd OR v_pick_loc_changed OR pickup_lat IS NULL OR pickup_lng IS NULL THEN p_new_pickup_lat
                               ELSE pickup_lat END,
    pickup_lng          = CASE WHEN v_is_active THEN pickup_lng
                               WHEN NOT v_new_pd THEN NULL
                               WHEN NOT v_old_pd OR v_pick_loc_changed OR pickup_lat IS NULL OR pickup_lng IS NULL THEN p_new_pickup_lng
                               ELSE pickup_lng END,
    return_method       = COALESCE(p_new_return_method, return_method),
    return_address      = CASE WHEN NOT v_new_rd THEN NULL
                               ELSE COALESCE(p_new_return_address, return_address) END,
    return_lat          = CASE WHEN NOT v_new_rd THEN NULL
                               WHEN NOT v_old_rd OR v_ret_loc_changed OR return_lat IS NULL OR return_lng IS NULL THEN p_new_return_lat
                               ELSE return_lat END,
    return_lng          = CASE WHEN NOT v_new_rd THEN NULL
                               WHEN NOT v_old_rd OR v_ret_loc_changed OR return_lat IS NULL OR return_lng IS NULL THEN p_new_return_lng
                               ELSE return_lng END,
    -- delivery_fee počítá VÝHRADNĚ server (staré + rozdíly změněných stran).
    delivery_fee        = CASE WHEN v_pick_side_changed OR v_ret_side_changed
                               THEN v_new_delivery_fee ELSE delivery_fee END,
    total_price         = v_new_total,
    discount_amount     = v_new_discount,
    late_pickup_discount_amount = v_late_store,
    loyalty_discount_amount = CASE WHEN v_loy_disc > 0
                                   THEN COALESCE(loyalty_discount_amount, 0) + v_loy_disc
                                   ELSE loyalty_discount_amount END,
    loyalty_level       = CASE WHEN v_loy_disc > 0 THEN v_loy_level ELSE loyalty_level END,
    loyalty_percent     = CASE WHEN v_loy_disc > 0 THEN v_loy_pct   ELSE loyalty_percent END,
    modification_history = COALESCE(modification_history, '[]'::jsonb) || v_history_entry
  WHERE id = p_booking_id;

  -- Dispatch VŽDY když je co vracet — process-refund si PI dohledá ze
  -- stripe_session_id, a bez Stripe platby vystaví dobropis + 'refund_pending'.
  IF v_refund > 0 THEN
    -- Důvod vratky = kód pro položku dobropisu (process-refund reasonTextFor):
    -- jen výměna motorky → „Výměna motorky", změna termínu → „Zkrácení
    -- rezervace", jinak „Úprava rezervace". p_reason je volný text zákazníka
    -- (web textarea) — do dokladu nepatří, zůstává jen v historii.
    v_refund_reason := CASE
      WHEN v_moto_swapped AND v_fs = v_b.start_date AND v_fe = v_b.end_date THEN 'moto_swap'
      WHEN v_fs <> v_b.start_date OR v_fe <> v_b.end_date THEN 'edit_shortening'
      ELSE 'edit' END;
    BEGIN
      SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
      SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
      IF v_url IS NOT NULL AND v_url <> '' AND v_key IS NOT NULL AND v_key <> '' THEN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/process-refund',
          headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
          body := jsonb_build_object('booking_id', p_booking_id, 'amount', v_refund, 'reason', v_refund_reason, 'source', 'edit')
        );
      ELSE
        INSERT INTO debug_log(source, action, status, error_message, request_data)
        VALUES ('_apply_booking_changes_core','refund_dispatch_skipped_no_settings','error',
                'app_settings supabase_url/service_role_key missing',
                jsonb_build_object('booking_id',p_booking_id,'refund',v_refund));
      END IF;
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO debug_log(source, action, status, error_message, request_data)
      VALUES ('_apply_booking_changes_core','refund_dispatch_failed','error',SQLERRM,
              jsonb_build_object('booking_id',p_booking_id,'refund',v_refund));
    END;
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'payment_required', false,
    'net_diff', v_net_diff, 'refund_amount', v_refund,
    'new_total', v_new_total, 'new_discount', v_new_discount,
    'new_delivery_fee', CASE WHEN v_pick_side_changed OR v_ret_side_changed THEN v_new_delivery_fee ELSE COALESCE(v_b.delivery_fee, 0) END,
    'location_changed', (v_pick_side_changed OR v_ret_side_changed),
    'loyalty_discount', v_loy_disc, 'loyalty_percent', v_loy_pct, 'loyalty_level', v_loy_level,
    'breakdown', jsonb_build_object(
      'dates_diff', v_dates_diff, 'moto_diff', v_moto_diff,
      'pickup_fee_diff', v_pickup_fee_diff, 'return_fee_diff', v_return_fee_diff,
      'pickup_fee_from', v_old_pfee, 'pickup_fee_to', v_new_pfee,
      'return_fee_from', v_old_rfee, 'return_fee_to', v_new_rfee,
      'fee_split_exact', (NOT v_split_est OR NOT (v_new_pd AND v_new_rd)),
      'gross_diff', v_gross_diff, 'discount_type', v_dtype, 'storno_pct', v_storno_pct,
      'late_pickup_from', v_old_late, 'late_pickup_to', v_late_store,
      'loyalty_discount', v_loy_disc, 'loyalty_percent', v_loy_pct
    )
  );
END;
$$;
REVOKE ALL ON FUNCTION "public"."_apply_booking_changes_core"(uuid, uuid, date, date, uuid, text, text, double precision, double precision, numeric, text, text, double precision, double precision, numeric, text, boolean, text, time) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION "public"."_apply_booking_changes_core"(uuid, uuid, date, date, uuid, text, text, double precision, double precision, numeric, text, text, double precision, double precision, numeric, text, boolean, text, time) TO service_role;

NOTIFY pgrst, 'reload schema';
