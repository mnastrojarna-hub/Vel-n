-- 2026-09-14 — (A) Stav motorky „V servisu" JEN po dobu skutečného servisu
--              (B) Přístupové kódy sledují motorku: přesun na jinou pobočku /
--                  do jiné kóje i výměna motorky = nové kódy + NOVÝ mail
-- ==========================================================================
-- (A) Report uživatele: ve Velíně je 9 motorek „V SERVISU", ačkoli v servisu
--     nejsou — mají servisní záznam ZIMNI-ODSTAVKA-2026-27 (service_date
--     1. 11. 2026, status in_service) → motorka dostala status maintenance
--     už dnes (ServiceLogModal nastavil maintenance podle statusu záznamu bez
--     ohledu na datum; Fleet.jsx přepínal jen pending → in_service při
--     otevření stránky). Nově je zdrojem pravdy DB:
--       * maintenance_log s budoucím service_date je vždy `pending`
--         (BEFORE trigger normalizuje in_service → pending),
--       * `sync_moto_service_status(p_moto_id)`: motorka je `maintenance`
--         právě tehdy, když má OTEVŘENÝ záznam (completed_date IS NULL,
--         status pending/in_service) se service_date <= dnes; takový záznam
--         přepne na in_service (+ service_orders pending → in_service).
--         Motorka `maintenance` BEZ aktuálního servisu, která má jen BUDOUCÍ
--         otevřený záznam → `active` (servis začne až v den service_date).
--         Ruční `maintenance` bez jakéhokoli záznamu se NEMĚNÍ.
--         Nikdy nesahá na unavailable/retired.
--       * AFTER trigger na maintenance_log volá sync pro danou motorku,
--         pg_cron `moto-service-status-sync` denně 00:05 UTC pro všechny
--         (den začátku servisu → maintenance; den po ukončení řeší admin),
--         Velín Fleet volá RPC při načtení (náhrada klientské logiky).
--     Backfill na konci migrace opraví aktuální stav.
-- (B) Zadání: při přesunu motorky na konkrétní pobočku / do konkrétní kóje
--     i při výměně motorky (zákazník v appce/webu, Velín) se MUSÍ všem
--     zákazníkům s rezervací přegenerovat kódy a přijít nový mail — i když
--     kódy už jednou dostali. Dosud: kódy nesly `branch_id` staré pobočky
--     (kiosk nové pobočky je odmítl), `send_door_codes_email` měla dedup
--     „max 1 mail na rezervaci" (druhý mail nikdy nepřišel; regen ho obcházel
--     mazáním message_log).
--       * `regen_door_codes_for_booking(p_booking_id, p_reason)` = společné
--         jádro (deaktivace starých kódů, 2 nové kódy na AKTUÁLNÍ pobočce
--         motorky, in-app zpráva + SMS/WA + mail — jen když jsou kódy vydané;
--         zadržení dle dokladů / „vraťte nejdřív původní" zůstává).
--       * `regen_door_codes_on_moto_change()` (bookings.moto_id) volá jádro.
--       * NOVÝ trigger `trg_regen_codes_on_moto_relocation` na motorcycles
--         (AFTER UPDATE OF branch_id, box_number) → jádro pro každou
--         reserved/active rezervaci motorky (dočasná kóje NULL/-1 při
--         prohazování ve Velíně se přeskakuje → jen jeden mail).
--       * `send_door_codes_email`: dedup nově = „mail s kódy odešel PO
--         vygenerování aktuálních kódů" (message_log.created_at >= max
--         created_at aktivních vydaných kódů) + ochrana proti dvojímu volání
--         v jedné transakci (admin_messages trigger + přímé volání) přes
--         transakční GUC. Nové kódy = nový mail, stejné kódy = žádný duplicit.
-- Idempotentní (CREATE OR REPLACE / DROP IF EXISTS / ON CONFLICT).

-- ==========================================================================
-- (A1) Normalizace: budoucí servis je vždy `pending`
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.normalize_maintenance_log_status() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NEW.completed_date IS NOT NULL AND COALESCE(NEW.status, '') <> 'completed' THEN
    NEW.status := 'completed';
  ELSIF COALESCE(NEW.status, 'pending') = 'in_service'
        AND NEW.completed_date IS NULL
        AND NEW.service_date IS NOT NULL
        AND NEW.service_date::date > CURRENT_DATE THEN
    NEW.status := 'pending';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_normalize_maintenance_log_status ON public.maintenance_log;
CREATE TRIGGER trg_normalize_maintenance_log_status
  BEFORE INSERT OR UPDATE OF service_date, status, completed_date ON public.maintenance_log
  FOR EACH ROW EXECUTE FUNCTION public.normalize_maintenance_log_status();

-- ==========================================================================
-- (A2) sync_moto_service_status — jediný zdroj pravdy pro active ⇄ maintenance
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.sync_moto_service_status(p_moto_id uuid DEFAULT NULL)
RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_to_maint int := 0;
  v_to_active int := 0;
  v_logs int := 0;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  -- 1) budoucí záznamy omylem uložené jako in_service → pending
  UPDATE maintenance_log ml
     SET status = 'pending'
   WHERE ml.completed_date IS NULL
     AND ml.status = 'in_service'
     AND ml.service_date::date > CURRENT_DATE
     AND (p_moto_id IS NULL OR ml.moto_id = p_moto_id);
  GET DIAGNOSTICS v_logs = ROW_COUNT;

  -- 2) servis začal (service_date <= dnes) → záznam in_service + motorka maintenance
  UPDATE maintenance_log ml
     SET status = 'in_service'
   WHERE ml.completed_date IS NULL
     AND ml.status = 'pending'
     AND ml.service_date::date <= CURRENT_DATE
     AND ml.is_test IS NOT TRUE
     AND (p_moto_id IS NULL OR ml.moto_id = p_moto_id)
     AND EXISTS (SELECT 1 FROM motorcycles m WHERE m.id = ml.moto_id AND m.status IN ('active','maintenance'));

  UPDATE service_orders so
     SET status = 'in_service'
   WHERE so.status = 'pending'
     AND so.maintenance_log_id IN (
       SELECT ml.id FROM maintenance_log ml
        WHERE ml.completed_date IS NULL AND ml.status = 'in_service'
          AND (p_moto_id IS NULL OR ml.moto_id = p_moto_id));

  UPDATE motorcycles m
     SET status = 'maintenance'
   WHERE m.status = 'active'
     AND (p_moto_id IS NULL OR m.id = p_moto_id)
     AND EXISTS (
       SELECT 1 FROM maintenance_log ml
        WHERE ml.moto_id = m.id AND ml.completed_date IS NULL
          AND ml.status IN ('pending','in_service')
          AND ml.is_test IS NOT TRUE
          AND ml.service_date::date <= CURRENT_DATE);
  GET DIAGNOSTICS v_to_maint = ROW_COUNT;

  -- 3) maintenance bez aktuálního servisu, jen s BUDOUCÍM záznamem → active
  UPDATE motorcycles m
     SET status = 'active'
   WHERE m.status = 'maintenance'
     AND (p_moto_id IS NULL OR m.id = p_moto_id)
     AND NOT EXISTS (
       SELECT 1 FROM maintenance_log ml
        WHERE ml.moto_id = m.id AND ml.completed_date IS NULL
          AND ml.status IN ('pending','in_service')
          AND ml.is_test IS NOT TRUE
          AND ml.service_date::date <= CURRENT_DATE)
     AND EXISTS (
       SELECT 1 FROM maintenance_log ml
        WHERE ml.moto_id = m.id AND ml.completed_date IS NULL
          AND ml.status IN ('pending','in_service')
          AND ml.is_test IS NOT TRUE
          AND ml.service_date::date > CURRENT_DATE);
  GET DIAGNOSTICS v_to_active = ROW_COUNT;

  RETURN jsonb_build_object('ok', true, 'to_maintenance', v_to_maint,
                            'to_active', v_to_active, 'normalized_logs', v_logs);
END $$;

COMMENT ON FUNCTION public.sync_moto_service_status(uuid) IS
  'Motorka je maintenance právě když má otevřený maintenance_log se service_date <= dnes; budoucí servis = pending + motorka active. Volá trigger na maintenance_log, cron moto-service-status-sync a Velín Fleet. Ruční maintenance bez záznamu se nemění.';

GRANT EXECUTE ON FUNCTION public.sync_moto_service_status(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_moto_service_status(uuid) TO service_role;

-- (A3) AFTER trigger na maintenance_log → okamžitá synchronizace motorky
CREATE OR REPLACE FUNCTION public.trg_sync_moto_service_status() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NEW.moto_id IS NOT NULL THEN
    PERFORM public.sync_moto_service_status(NEW.moto_id);
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_sync_moto_service_status failed for log %: %', NEW.id, SQLERRM;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_sync_moto_service_status ON public.maintenance_log;
CREATE TRIGGER trg_sync_moto_service_status
  AFTER INSERT OR UPDATE OF service_date, status, completed_date, moto_id ON public.maintenance_log
  FOR EACH ROW EXECUTE FUNCTION public.trg_sync_moto_service_status();

-- (A4) pg_cron — denně 00:05 UTC (den začátku servisu → maintenance)
DO $$
BEGIN
  BEGIN
    PERFORM cron.unschedule('moto-service-status-sync');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  PERFORM cron.schedule('moto-service-status-sync', '5 0 * * *',
    $cron$ SELECT public.sync_moto_service_status(); $cron$);
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'cron.schedule moto-service-status-sync selhalo (pg_cron nedostupné?): %', SQLERRM;
END $$;

-- ==========================================================================
-- (B1) send_door_codes_email — dedup podle AKTUÁLNÍCH kódů, ne „1× za rezervaci"
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.send_door_codes_email(p_booking_id uuid, p_user_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_guard text := 'motogo.door_codes_mail_' || replace(p_booking_id::text, '-', '');
  v_codes_at timestamptz;
  v_already_sent boolean;
  v_supabase_url text;
  v_service_key text;
  v_email text;
  v_name text;
  v_moto_model text;
  v_start date;
  v_end date;
  v_source text;
  v_language text;
begin
  -- 0) Ochrana proti dvojímu odeslání v JEDNÉ transakci (trigger na
  --    admin_messages + přímé volání z generátoru kódů).
  IF current_setting(v_guard, true) = '1' THEN RETURN; END IF;

  -- 1) Aktuální vydané kódy (bez nich není co posílat — výzvu k dokladům
  --    nese booking_reserved / release flow).
  SELECT max(created_at) INTO v_codes_at
    FROM branch_door_codes
   WHERE booking_id = p_booking_id AND is_active = true
     AND sent_to_customer = true AND withheld_reason IS NULL;
  IF v_codes_at IS NULL THEN RETURN; END IF;

  -- 2) Dedup: mail s kódy už odešel PO vygenerování těchto kódů → nic.
  --    Nové kódy (výměna motorky, přesun na pobočku / do kóje) = nový mail.
  SELECT EXISTS(
    SELECT 1 FROM message_log
    WHERE booking_id = p_booking_id
      AND template_slug IN ('door_codes', 'web_door_codes')
      AND channel = 'email'
      AND status = 'sent'
      AND created_at >= v_codes_at
    LIMIT 1
  ) INTO v_already_sent;
  IF v_already_sent THEN RETURN; END IF;

  -- Booking + customer
  SELECT p.email, p.full_name, m.model,
         b.start_date::date, b.end_date::date,
         COALESCE(b.booking_source, 'app'),
         COALESCE(b.language, p.language, 'cs')
    INTO v_email, v_name, v_moto_model, v_start, v_end, v_source, v_language
  FROM bookings b
  LEFT JOIN profiles p ON p.id = b.user_id
  LEFT JOIN motorcycles m ON m.id = b.moto_id
  WHERE b.id = p_booking_id;
  IF v_email IS NULL OR v_email = '' THEN
    RAISE WARNING 'send_door_codes_email: no email for booking %', p_booking_id;
    RETURN;
  END IF;

  SELECT value #>> '{}' INTO v_supabase_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_service_key  FROM app_settings WHERE key = 'service_role_key';
  IF v_supabase_url IS NULL OR v_service_key IS NULL THEN
    RAISE WARNING 'send_door_codes_email: supabase_url or service_role_key missing in app_settings';
    RETURN;
  END IF;

  PERFORM set_config(v_guard, '1', true);

  -- Edge fn send-booking-email (type=door_codes) si kódy načte sama,
  -- vyrenderuje šablonu, pošle přes Resend a zaloguje do message_log.
  PERFORM net.http_post(
    url := v_supabase_url || '/functions/v1/send-booking-email',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_service_key,
      'apikey',        v_service_key,
      'Content-Type',  'application/json'
    ),
    body := jsonb_build_object(
      'type',            'door_codes',
      'booking_id',      p_booking_id::text,
      'customer_email',  v_email,
      'customer_name',   COALESCE(v_name, ''),
      'motorcycle',      COALESCE(v_moto_model, ''),
      'start_date',      v_start::text,
      'end_date',        v_end::text,
      'source',          v_source,
      'language',        v_language
    )
  );
exception when others then
  raise warning 'send_door_codes_email failed for booking %: %', p_booking_id, sqlerrm;
end $$;

COMMENT ON FUNCTION public.send_door_codes_email(uuid, uuid) IS
  'Mail s přístupovými kódy přes edge send-booking-email (type=door_codes). Dedup = mail odeslaný po vygenerování aktuálních vydaných kódů (message_log.created_at >= max branch_door_codes.created_at); nové kódy = nový mail. Transakční GUC brání dvojímu volání v jedné transakci.';

-- ==========================================================================
-- (B2) regen_door_codes_for_booking — společné jádro přegenerování
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.regen_door_codes_for_booking(p_booking_id uuid, p_reason text DEFAULT 'moto_change')
RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_b bookings%ROWTYPE;
  v_branch_id uuid;
  v_branch_name text;
  v_box integer;
  v_lic text;
  v_withheld text;
  v_code1 text;
  v_code2 text;
  v_released boolean;
  v_phone text;
  v_lang text;
  v_intro text;
BEGIN
  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND OR v_b.is_test IS TRUE OR v_b.status NOT IN ('active','reserved') THEN
    RETURN false;
  END IF;

  SELECT m.branch_id, m.box_number, m.license_required::text, br.name
    INTO v_branch_id, v_box, v_lic, v_branch_name
    FROM motorcycles m LEFT JOIN branches br ON br.id = m.branch_id
   WHERE m.id = v_b.moto_id;

  -- staré kódy vždy zneplatnit (motorka už není tam, kde byla)
  UPDATE branch_door_codes SET is_active = false
   WHERE booking_id = p_booking_id AND is_active = true;

  IF v_branch_id IS NULL THEN RETURN false; END IF;

  IF v_lic = 'N' THEN
    v_withheld := NULL;
  ELSE
    v_withheld := check_booking_docs_status(v_b.user_id, v_b.end_date::date, v_b.moto_id);
  END IF;

  v_code1 := LPAD(FLOOR(100000 + RANDOM() * 900000)::text, 6, '0');
  v_code2 := LPAD(FLOOR(100000 + RANDOM() * 900000)::text, 6, '0');

  INSERT INTO branch_door_codes (branch_id, booking_id, moto_id, code_type, door_code,
    is_active, valid_from, valid_until, sent_to_customer, sent_at, withheld_reason)
  VALUES
    (v_branch_id, p_booking_id, v_b.moto_id, 'motorcycle', v_code1,
     true, v_b.start_date, v_b.end_date, v_withheld IS NULL,
     CASE WHEN v_withheld IS NULL THEN NOW() ELSE NULL END, v_withheld),
    (v_branch_id, p_booking_id, v_b.moto_id, 'accessories', v_code2,
     true, v_b.start_date, v_b.end_date, v_withheld IS NULL,
     CASE WHEN v_withheld IS NULL THEN NOW() ELSE NULL END, v_withheld);

  -- BEFORE trigger withhold_swap_next_codes mohl kód zadržet → ověř reálný stav
  SELECT bool_and(sent_to_customer) INTO v_released
    FROM branch_door_codes
   WHERE booking_id = p_booking_id AND is_active = true;
  IF NOT COALESCE(v_released, false) THEN RETURN true; END IF;

  v_intro := CASE p_reason
    WHEN 'branch_move' THEN 'Vaše motorka byla přesunuta na pobočku ' || COALESCE(v_branch_name, '') || ' – nové kódy:'
    WHEN 'box_move'    THEN 'Vaše motorka byla přesunuta do jiné kóje' || CASE WHEN v_box IS NOT NULL THEN ' (č. ' || v_box || ')' ELSE '' END || ' – nové kódy:'
    ELSE 'Změnili jste motorku – nové kódy:' END;

  BEGIN
    INSERT INTO admin_messages (user_id, title, message, type)
    VALUES (v_b.user_id, 'Nové přístupové kódy',
      v_intro || E'\n' ||
      'Kód k motorce: ' || v_code1 || E'\n' ||
      'Kód k příslušenství: ' || v_code2 || E'\n' ||
      'Kódy jsou platné (' || TO_CHAR(v_b.start_date::date, 'DD.MM.YYYY') || ' – ' ||
      TO_CHAR(v_b.end_date::date, 'DD.MM.YYYY') || ').' ||
      CASE WHEN v_branch_name IS NOT NULL THEN E'\nPobočka: ' || v_branch_name ELSE '' END ||
      CASE WHEN v_box IS NOT NULL AND v_box > 0 THEN E'\nKóje: ' || v_box ELSE '' END,
      'door_codes');
  EXCEPTION WHEN OTHERS THEN NULL; END;

  BEGIN
    SELECT phone, COALESCE(language, 'cs') INTO v_phone, v_lang FROM profiles WHERE id = v_b.user_id;
    IF v_phone IS NOT NULL AND v_phone <> '' THEN
      PERFORM send_sms_and_wa(v_phone, 'door_codes',
        jsonb_build_object(
          'booking_number', upper(left(p_booking_id::text, 8)),
          'door_code_moto', v_code1,
          'door_code_gear', v_code2
        ), v_b.user_id, p_booking_id, COALESCE(v_b.language, v_lang, 'cs'));
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- mail s novými kódy (dedup dle kódů → vždy odejde; GUC brání dvojímu
  -- odeslání, když ho už spustil trigger na admin_messages)
  PERFORM send_door_codes_email(p_booking_id, v_b.user_id);
  RETURN true;
END $$;

COMMENT ON FUNCTION public.regen_door_codes_for_booking(uuid, text) IS
  'Zneplatní staré kódy rezervace a vydá 2 nové na AKTUÁLNÍ pobočce motorky; při vydání pošle in-app zprávu + SMS/WA + mail (p_reason: moto_change | branch_move | box_move). Volá trigger na bookings.moto_id a trigger na motorcycles.branch_id/box_number.';

REVOKE ALL ON FUNCTION public.regen_door_codes_for_booking(uuid, text) FROM PUBLIC, anon, authenticated;

-- (B3) výměna motorky na rezervaci → jádro
CREATE OR REPLACE FUNCTION public.regen_door_codes_on_moto_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF OLD.moto_id IS NOT DISTINCT FROM NEW.moto_id THEN RETURN NEW; END IF;
  IF NEW.status NOT IN ('active','reserved') THEN RETURN NEW; END IF;
  PERFORM regen_door_codes_for_booking(NEW.id, 'moto_change');
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'regen_door_codes_on_moto_change failed for booking %: %', NEW.id, SQLERRM;
  RETURN NEW;
END $$;

-- (B4) přesun motorky (pobočka / kóje) → nové kódy všem živým rezervacím
CREATE OR REPLACE FUNCTION public.regen_door_codes_on_moto_relocation() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  r record;
  v_reason text;
BEGIN
  IF OLD.branch_id IS NOT DISTINCT FROM NEW.branch_id
     AND OLD.box_number IS NOT DISTINCT FROM NEW.box_number THEN
    RETURN NEW;
  END IF;
  -- dočasná / nepřiřazená kóje (Velín při prohazování ukládá -1) → až finální hodnota
  IF OLD.branch_id IS NOT DISTINCT FROM NEW.branch_id
     AND (NEW.box_number IS NULL OR NEW.box_number < 0) THEN
    RETURN NEW;
  END IF;
  v_reason := CASE WHEN OLD.branch_id IS DISTINCT FROM NEW.branch_id THEN 'branch_move' ELSE 'box_move' END;

  FOR r IN
    SELECT id FROM bookings
     WHERE moto_id = NEW.id AND status IN ('active','reserved') AND is_test IS NOT TRUE
     ORDER BY start_date
  LOOP
    BEGIN
      PERFORM regen_door_codes_for_booking(r.id, v_reason);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'regen_door_codes_on_moto_relocation: booking % failed: %', r.id, SQLERRM;
    END;
  END LOOP;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'regen_door_codes_on_moto_relocation failed for moto %: %', NEW.id, SQLERRM;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_regen_codes_on_moto_relocation ON public.motorcycles;
CREATE TRIGGER trg_regen_codes_on_moto_relocation
  AFTER UPDATE OF branch_id, box_number ON public.motorcycles
  FOR EACH ROW
  WHEN (OLD.branch_id IS DISTINCT FROM NEW.branch_id OR OLD.box_number IS DISTINCT FROM NEW.box_number)
  EXECUTE FUNCTION public.regen_door_codes_on_moto_relocation();

-- ==========================================================================
-- (A5) Backfill: srovnat stav motorek podle skutečného termínu servisu
-- ==========================================================================
DO $$
DECLARE v jsonb;
BEGIN
  v := public.sync_moto_service_status();
  RAISE NOTICE 'sync_moto_service_status backfill: %', v;
END $$;
