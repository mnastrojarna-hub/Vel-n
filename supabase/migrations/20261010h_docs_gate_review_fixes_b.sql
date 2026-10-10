-- ============================================================================
-- PŘÍSTUPOVÉ KÓDY JEN S KOMPLETNÍMI DOKLADY — opravy ze závěrečného review 2/2 (2026-10-10)
-- `20261010*` a–f už jsou aplikované (auto-deploy) → opravy jdou sem; body 1–2 v `20261010g`.
-- 1) OBCHVAT (ověřeno na kopii živé DB): zákazník si přímým REST zápisem
--    přepnul zaplacenou rezervaci z `reserved` na `pending` a pak `moto_id`
--    (dětská motorka bez dokladů → vydané kódy → zpět dospělá motorka). U
--    `pending` se kódy při změně motorky nepřepočítávají → kiosk otevřel box
--    dospělé motorky bez dokladů. `_guard_customer_booking_status`: zákazník
--    smí do `pending` jen ze zrušené (obnovení v appce), nikdy z reserved/active.
-- 2) `_door_codes_follow_moto`: doklady znovu i při jiné SADĚ skupin ŘP
--    (license_groups, ne jen license_required), přes `booking_docs_gate`;
--    u PŘEVZATÉ rezervace se už vydaný kód nikdy nezamkne; do zprávy jen
--    vydané kódy. Jinak tělo 1:1.
-- 3) `release_my_door_codes`: jen rezervace reserved/active.
-- 4) Pobočka rezervace: navazující rezervace (`extends_booking_id`) jde s
--    motorkou, dokud původní není vyzvednutá (dřív zůstala na staré pobočce).
-- 5) `ai_booking_readiness` (anon, jen číslo rezervace): důvody bez věku a
--    data platnosti ŘP; brána `booking_docs_gate`.
-- ============================================================================

-- 3) ----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.release_my_door_codes(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid;
  v_booking record;
  v_reason text;
  v_code_moto text;
  v_code_gear text;
  v_phone text;
  v_released int := 0;
  v_branch uuid;
  v_gate text;
  v_door integer;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT id, user_id, start_date, end_date, status, moto_id
  INTO v_booking
  FROM bookings
  WHERE id = p_booking_id AND user_id = v_uid;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Booking not found');
  END IF;
  -- 2026-10-10 (20261010g): jen živá rezervace (ne pending / zrušená / dokončená)
  IF v_booking.status NOT IN ('reserved', 'active') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Booking not active');
  END IF;

  -- Kód držený VÝMĚNOU motorky uvolní až vrácení původní motorky — nikdy doklady.
  IF NOT EXISTS (
    SELECT 1 FROM branch_door_codes
    WHERE booking_id = p_booking_id AND is_active = true AND sent_to_customer = false
      AND withheld_reason IS DISTINCT FROM 'Vraťte nejdřív původní motorku'
    LIMIT 1
  ) THEN
    IF EXISTS (SELECT 1 FROM branch_door_codes
                WHERE booking_id = p_booking_id AND is_active = true AND sent_to_customer = false) THEN
      RETURN jsonb_build_object('success', false, 'released', 0, 'error', 'Vraťte nejdřív původní motorku',
                                'withheld_reason', 'Vraťte nejdřív původní motorku');
    END IF;
    RETURN jsonb_build_object('success', true, 'released', 0, 'message', 'No withheld codes');
  END IF;

  -- 2026-10-10: přísná brána rezervace (OP líc+rub / pas, ŘP líc+rub, 18+, platnost, skupina)
  v_reason := public.booking_docs_gate(p_booking_id);
  IF v_reason IS NOT NULL THEN
    UPDATE branch_door_codes SET withheld_reason = v_reason
     WHERE booking_id = p_booking_id AND is_active AND sent_to_customer = false
       AND withheld_reason IS DISTINCT FROM 'Vraťte nejdřív původní motorku'
       AND withheld_reason IS DISTINCT FROM v_reason;
    RETURN jsonb_build_object('success', false, 'error', 'Documents missing', 'withheld_reason', v_reason);
  END IF;

  UPDATE branch_door_codes
  SET sent_to_customer = true, sent_at = NOW(), withheld_reason = NULL
  WHERE booking_id = p_booking_id AND is_active = true AND sent_to_customer = false
    AND withheld_reason IS DISTINCT FROM 'Vraťte nejdřív původní motorku';
  GET DIAGNOSTICS v_released = ROW_COUNT;

  SELECT door_code INTO v_code_moto FROM branch_door_codes
   WHERE booking_id = p_booking_id AND code_type = 'motorcycle' AND is_active AND sent_to_customer LIMIT 1;
  IF v_code_moto IS NULL THEN
    RETURN jsonb_build_object('success', false, 'released', 0, 'error', 'Documents missing',
                              'withheld_reason', public.booking_docs_gate(p_booking_id));
  END IF;
  SELECT door_code INTO v_code_gear FROM branch_door_codes
   WHERE booking_id = p_booking_id AND code_type = 'accessories' AND is_active AND sent_to_customer LIMIT 1;

  -- Brána se schránkou na klíč (Velké Němčice, 2026-10-04)
  SELECT branch_id INTO v_branch FROM motorcycles WHERE id = v_booking.moto_id;
  v_gate := public._booking_gate_code(p_booking_id);   -- NULL u přistavení na adresu
  v_door := CASE WHEN v_gate IS NOT NULL THEN public._branch_locker_door_no(v_branch) END;

  BEGIN
    INSERT INTO admin_messages (user_id, title, message, type)
    VALUES (
      v_uid,
      'Přístupové kódy k pobočce',
      public._door_codes_msg_lines(v_gate, v_door, v_code_gear, v_code_moto) || E'\n' ||
      public._door_codes_msg_valid(v_gate, v_code_gear IS NOT NULL, true) ||
      TO_CHAR(v_booking.start_date::date, 'DD.MM.YYYY') || ' – ' ||
      TO_CHAR(v_booking.end_date::date, 'DD.MM.YYYY') || ').' ||
      public._gate_procedure_msg(v_gate, v_door, v_code_gear IS NOT NULL),
      'door_codes'
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'release_my_door_codes: admin_message insert failed: %', SQLERRM;
  END;

  BEGIN
    SELECT phone INTO v_phone FROM profiles WHERE id = v_uid;
    IF v_phone IS NOT NULL AND v_phone <> '' THEN
      PERFORM send_sms_and_wa(
        v_phone,
        public._door_codes_sms_slug(v_gate, v_code_gear IS NOT NULL),
        jsonb_build_object(
          'booking_number', upper(left(p_booking_id::text, 8)),
          'door_code_moto', v_code_moto,
          'door_code_gear', COALESCE(v_code_gear, '')
        ) || CASE WHEN v_gate IS NOT NULL THEN jsonb_build_object('gate_code', v_gate) ELSE '{}'::jsonb END,
        v_uid, p_booking_id, public._door_codes_sms_lang(v_uid, p_booking_id)
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'release_my_door_codes: SMS/WA failed: %', SQLERRM;
  END;

  PERFORM send_door_codes_email(p_booking_id, v_uid);

  RETURN jsonb_build_object('success', true, 'released', v_released);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$;

-- 4) ----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._booking_set_branch()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_parent    uuid := COALESCE(NEW.extends_booking_id,
                               CASE WHEN NEW.sos_replacement IS TRUE THEN NEW.replacement_for_booking_id END);
  v_priv      boolean := auth.uid() IS NULL OR public.is_admin();
  v_moto_br   uuid;
  v_parent_br uuid;
  v_live_new  boolean := NEW.status IN ('pending', 'reserved') AND NEW.picked_up_at IS NULL;
  v_live_old  boolean;
  v_parent_live boolean := false;
BEGIN
  SELECT m.branch_id INTO v_moto_br FROM motorcycles m WHERE m.id = NEW.moto_id;
  IF v_parent IS NOT NULL AND v_parent IS DISTINCT FROM NEW.id THEN
    SELECT b.branch_id, (b.status IN ('pending', 'reserved') AND b.picked_up_at IS NULL)
      INTO v_parent_br, v_parent_live FROM bookings b WHERE b.id = v_parent;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.branch_id := COALESCE(v_parent_br, v_moto_br, CASE WHEN v_priv THEN NEW.branch_id END);
    RETURN NEW;
  END IF;

  -- Ruční oprava z Velína / service role (backfill) — ponech.
  IF v_priv AND NEW.branch_id IS DISTINCT FROM OLD.branch_id THEN RETURN NEW; END IF;

  NEW.branch_id := OLD.branch_id;   -- zákaznický JWT ani vedlejší změny pobočku nemění
  -- Navazující / SOS dědí pobočku původní — jen když je původní už vyzvednutá;
  -- dokud není, jde rezervace s motorkou jako každá jiná (20261010g).
  IF v_parent IS NOT NULL AND NOT COALESCE(v_parent_live, false) THEN
    NEW.branch_id := COALESCE(OLD.branch_id, v_parent_br, v_moto_br);
    RETURN NEW;
  END IF;

  v_live_old := OLD.status IN ('pending', 'reserved') AND OLD.picked_up_at IS NULL;
  -- Před vyzvednutím + okamžik vyzvednutí / storna: pobočka motorky (pak zmrazená).
  IF v_live_new OR v_live_old THEN
    NEW.branch_id := COALESCE(v_moto_br, OLD.branch_id);
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '_booking_set_branch booking %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public._booking_branch_follow_moto()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.branch_id IS NULL THEN RETURN NULL; END IF;   -- motorka mimo pobočku: rezervace drží poslední
  UPDATE bookings b
     SET branch_id = NEW.branch_id
   WHERE b.moto_id = NEW.id
     AND b.status IN ('pending', 'reserved')
     AND b.picked_up_at IS NULL
     AND (b.extends_booking_id IS NULL
          OR EXISTS (SELECT 1 FROM bookings p WHERE p.id = b.extends_booking_id
                      AND p.status IN ('pending', 'reserved') AND p.picked_up_at IS NULL))
     AND b.sos_replacement IS NOT TRUE
     AND b.branch_id IS DISTINCT FROM NEW.branch_id;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '_booking_branch_follow_moto moto %: %', NEW.id, SQLERRM;
  RETURN NULL;
END;
$function$;

-- Jednorázově: živé navazující rezervace s nevyzvednutou původní → pobočka motorky
ALTER TABLE public.bookings DISABLE TRIGGER bookings_updated_at;
ALTER TABLE public.bookings DISABLE TRIGGER trg_booking_modified_email;
UPDATE public.bookings c
   SET branch_id = m.branch_id
  FROM public.motorcycles m, public.bookings p
 WHERE m.id = c.moto_id AND p.id = c.extends_booking_id
   AND c.status IN ('pending', 'reserved') AND c.picked_up_at IS NULL
   AND p.status IN ('pending', 'reserved') AND p.picked_up_at IS NULL
   AND m.branch_id IS NOT NULL AND c.branch_id IS DISTINCT FROM m.branch_id;
ALTER TABLE public.bookings ENABLE TRIGGER trg_booking_modified_email;
ALTER TABLE public.bookings ENABLE TRIGGER bookings_updated_at;

-- 5) ----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ai_booking_readiness(p_ref text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_raw    text := trim(coalesce(p_ref, ''));
  v_uuid   uuid;
  v_id     uuid;
  v_short  text;
  v_cnt    int;
  v_user   uuid;
  v_end    date;
  v_moto   uuid;
  v_status text;
  v_pay    text;
  v_src    text;
  v_docs_reason text;
  v_codes_active boolean;
  v_codes_sent   boolean;
  v_withheld     text;
BEGIN
  IF length(v_raw) < 6 THEN
    RETURN jsonb_build_object('success', false, 'error', 'missing_inputs');
  END IF;

  BEGIN
    v_uuid := (regexp_match(v_raw, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'))[1]::uuid;
  EXCEPTION WHEN OTHERS THEN
    v_uuid := NULL;
  END;

  IF v_uuid IS NOT NULL THEN
    v_id := v_uuid;
  ELSE
    v_short := upper(regexp_replace(v_raw, '[^0-9a-fA-F]', '', 'g'));
    IF length(v_short) < 8 THEN
      RETURN jsonb_build_object('success', false, 'error', 'bad_ref');
    END IF;
    v_short := right(v_short, 8);
    SELECT count(*) INTO v_cnt FROM bookings b
      WHERE upper(right(replace(b.id::text, '-', ''), 8)) = v_short;
    IF v_cnt > 1 THEN
      RETURN jsonb_build_object('success', false, 'error', 'ambiguous');
    END IF;
    SELECT b.id INTO v_id FROM bookings b
      WHERE upper(right(replace(b.id::text, '-', ''), 8)) = v_short LIMIT 1;
  END IF;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;

  SELECT b.user_id, b.end_date::date, b.moto_id, b.status::text, b.payment_status::text, b.booking_source
  INTO v_user, v_end, v_moto, v_status, v_pay, v_src
  FROM bookings b WHERE b.id = v_id;

  IF v_status IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;

  -- doklady: NULL = OK, jinak konkrétní důvod (chybí OP/ŘP/propadlý…)
  v_docs_reason := public.booking_docs_gate(v_id);

  -- přístupové kódy (NIKDY nevracíme samotný kód, jen stav)
  SELECT EXISTS (SELECT 1 FROM branch_door_codes d WHERE d.booking_id = v_id AND d.is_active = true),
         EXISTS (SELECT 1 FROM branch_door_codes d WHERE d.booking_id = v_id AND d.sent_to_customer = true)
  INTO v_codes_active, v_codes_sent;

  SELECT d.withheld_reason INTO v_withheld
  FROM branch_door_codes d
  WHERE d.booking_id = v_id AND d.withheld_reason IS NOT NULL
  LIMIT 1;

  -- Anonymní volání jen s číslem rezervace: neprozrazovat věk ani datum platnosti ŘP (2026-10-10, 20261010g)
  v_docs_reason := regexp_replace(regexp_replace(v_docs_reason,
                     'Zákazníkovi není 18 let', 'Údaje z dokladů nesplňují podmínky pronájmu — kontaktujte nás', 'g'),
                     'ŘP propadlý [0-9.]+', 'Platnost ŘP nevyhovuje termínu pronájmu', 'g');
  v_withheld := regexp_replace(regexp_replace(v_withheld,
                     'Zákazníkovi není 18 let', 'Údaje z dokladů nesplňují podmínky pronájmu — kontaktujte nás', 'g'),
                     'ŘP propadlý [0-9.]+', 'Platnost ŘP nevyhovuje termínu pronájmu', 'g');

  RETURN jsonb_build_object(
    'success',               true,
    'booking_number',        upper(right(v_id::text, 8)),
    'status',                v_status,
    'payment_status',        v_pay,
    'booking_source',        v_src,
    'docs_ok',               (v_docs_reason IS NULL),
    'docs_missing_reason',   v_docs_reason,                       -- NULL když OK
    'codes_issued',          (v_codes_active AND v_codes_sent),
    'codes_active',          v_codes_active,
    'codes_sent',            v_codes_sent,
    'codes_withheld_reason', v_withheld                           -- typicky „Chybí doklady…"
  );
END;
$function$;
