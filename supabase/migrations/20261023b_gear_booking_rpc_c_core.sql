-- =============================================================================
-- 2026-10-23 (b/3): Výpůjčka výbavy — pobočka, uzavření, překryv
-- Těla převzatá ze živého snapshotu, měněné řádky označené „gear 2026-10-23“:
--  • _booking_set_branch: INSERT gear rezervace si drží zadanou pobočku
--    (RPC ji ověřilo; zákaznický INSERT gear řádku blokuje 20261023a); UPDATE
--    gear řádku přes gear RPC (GUC motogo.gear_rpc) — přepis konceptu z webu —
--    pobočku také drží (jinak by ji zákaznický JWT vrátil na původní).
--  • check_booking_branch_open: gear = bookings.branch_id (+ branch_id ve
--    sloupcích triggeru a v „beze změny“ zkratce jen pro gear).
--  • check_user_booking_overlap / check_web_booking_user_overlap: výpůjčka výbavy
--    se s rezervacemi zákazníka nepřekrývá na žádné straně (rozhodnutí majitele).
--  • doklady (booking_docs_gate …) → 20261023b_gear_booking_rpc_c_docs.sql
-- Idempotentní.
-- =============================================================================

CREATE OR REPLACE FUNCTION public._booking_set_branch()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_parent      uuid := COALESCE(NEW.extends_booking_id,
                                 CASE WHEN NEW.sos_replacement IS TRUE THEN NEW.replacement_for_booking_id END);
  v_priv        boolean := auth.uid() IS NULL OR public.is_admin();
  v_now_win     boolean;
  v_moto_br     uuid;
  v_parent_br   uuid;
  v_parent_live boolean := false;
BEGIN
  SELECT m.branch_id INTO v_moto_br FROM motorcycles m WHERE m.id = NEW.moto_id;
  IF v_parent IS NOT DISTINCT FROM NEW.id THEN v_parent := NULL; END IF;
  IF v_parent IS NOT NULL THEN
    SELECT b.branch_id, public._booking_branch_follows(b.status, b.picked_up_at, b.handover_protocol_filled_at, b.start_date)
      INTO v_parent_br, v_parent_live FROM bookings b WHERE b.id = v_parent;
  END IF;

  IF TG_OP = 'INSERT' THEN
    -- gear 2026-10-23: výpůjčka výbavy nemá motorku → pobočka zadaná RPC / Velínem
    IF NEW.booking_kind = 'gear' THEN
      NEW.branch_id := COALESCE(v_parent_br, NEW.branch_id);
      RETURN NEW;
    END IF;
    NEW.branch_id := COALESCE(v_parent_br, v_moto_br, CASE WHEN v_priv THEN NEW.branch_id END);
    RETURN NEW;
  END IF;

  -- Ruční oprava (admin / service role) — ponech; log jen přímého zásahu, ne automatik.
  IF v_priv AND NEW.branch_id IS DISTINCT FROM OLD.branch_id THEN
    IF pg_trigger_depth() = 1 AND COALESCE(current_setting('motogo.branch_reattribution', true), '') = '' THEN
      BEGIN
        INSERT INTO admin_audit_log(admin_id, action, entity_type, entity_id, old_data, new_data)
        VALUES (auth.uid(), 'booking_branch_set', 'bookings', NEW.id,
                jsonb_build_object('branch_id', OLD.branch_id), jsonb_build_object('branch_id', NEW.branch_id));
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;
    RETURN NEW;
  END IF;

  -- gear 2026-10-23: přepis rozpracované výpůjčky výbavy přes gear RPC (ověřená pobočka) platí
  IF NEW.booking_kind = 'gear' AND COALESCE(current_setting('motogo.gear_rpc', true), '') = '1' THEN
    RETURN NEW;
  END IF;

  NEW.branch_id := OLD.branch_id;   -- zákaznický JWT ani vedlejší změny pobočku nemění
  -- Navazující / SOS: pobočka původní (dokud původní následuje motorku, platí obecné pravidlo níže);
  -- ručně nastavenou pobočku navazující (booking_branch_set) nepřepisuj.
  IF v_parent IS NOT NULL AND NOT COALESCE(v_parent_live, false) THEN
    IF v_parent_br IS NOT NULL AND v_parent_br IS DISTINCT FROM OLD.branch_id
       AND NOT EXISTS (SELECT 1 FROM admin_audit_log a
                        WHERE a.entity_type = 'bookings' AND a.entity_id = NEW.id AND a.action = 'booking_branch_set') THEN
      NEW.branch_id := v_parent_br;
    END IF;
    NEW.branch_id := COALESCE(NEW.branch_id, v_moto_br);
    RETURN NEW;
  END IF;

  -- Do konce dne začátku (bez převzetí): pobočka motorky; storno/převzetí v té době ji zmrazí.
  IF public._booking_branch_follows(OLD.status, OLD.picked_up_at, OLD.handover_protocol_filled_at, OLD.start_date)
     OR public._booking_branch_follows(NEW.status, NEW.picked_up_at, NEW.handover_protocol_filled_at, NEW.start_date) THEN
    NEW.branch_id := COALESCE(v_moto_br, OLD.branch_id);
    RETURN NEW;
  END IF;

  -- Převzetí zapsané TEĎ (kiosk, Velín odbavení / protokol) nejpozději v poslední den termínu = kde motorka stojí.
  -- Cron (den po konci + auto protokol) ani dodatečné „Dokončit“ (picked_up_at zůstává NULL) pobočku nemění.
  v_now_win := (now() AT TIME ZONE 'Europe/Prague')::date <= (NEW.end_date AT TIME ZONE 'Europe/Prague')::date
               AND NOT (NEW.handover_protocol_autofilled IS TRUE AND OLD.handover_protocol_autofilled IS NOT TRUE)
               AND ((OLD.picked_up_at IS NULL
                     AND NEW.picked_up_at BETWEEN now() - interval '6 hours' AND now() + interval '10 minutes')
                    OR (OLD.handover_protocol_filled_at IS NULL AND NEW.handover_protocol_autofilled IS NOT TRUE
                        AND NEW.handover_protocol_filled_at BETWEEN now() - interval '6 hours' AND now() + interval '10 minutes'));
  IF COALESCE(v_now_win, false) THEN
    NEW.branch_id := COALESCE(v_moto_br, OLD.branch_id);
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '_booking_set_branch booking %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.check_booking_branch_open()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_start  date := NEW.start_date::date;
  v_end    date := NEW.end_date::date;
  v_branch uuid;
  v_name   text;
BEGIN
  IF NEW.sos_replacement = true THEN
    RETURN NEW;
  END IF;

  IF NEW.status IN ('cancelled', 'completed') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD.moto_id IS NOT DISTINCT FROM NEW.moto_id
     AND OLD.trailer_moto_id IS NOT DISTINCT FROM NEW.trailer_moto_id
     AND OLD.start_date::date = v_start
     AND OLD.end_date::date   = v_end
     -- gear 2026-10-23: u výpůjčky výbavy rozhoduje i změna pobočky
     AND (NEW.booking_kind IS DISTINCT FROM 'gear' OR OLD.branch_id IS NOT DISTINCT FROM NEW.branch_id)
     AND OLD.status NOT IN ('cancelled', 'completed') THEN
    RETURN NEW;
  END IF;

  -- gear 2026-10-23: výpůjčka výbavy bez motorky = pobočka rezervace
  IF NEW.booking_kind = 'gear' THEN
    IF public.branch_is_closed(NEW.branch_id, v_start, v_end) THEN
      SELECT b.name INTO v_name FROM branches b WHERE b.id = NEW.branch_id;
      RAISE EXCEPTION 'Pobočka % je v termínu % – % zavřená, výbavu nelze půjčit.',
        COALESCE(v_name, 'výpůjčky'), to_char(v_start, 'DD.MM.YYYY'), to_char(v_end, 'DD.MM.YYYY')
        USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
  END IF;

  SELECT m.branch_id INTO v_branch FROM motorcycles m WHERE m.id = NEW.moto_id;
  IF public.branch_is_closed(v_branch, v_start, v_end) THEN
    SELECT b.name INTO v_name FROM branches b WHERE b.id = v_branch;
    RAISE EXCEPTION 'Pobočka % je v termínu % – % zavřená, motorku nelze rezervovat.',
      COALESCE(v_name, 'motorky'), to_char(v_start, 'DD.MM.YYYY'), to_char(v_end, 'DD.MM.YYYY')
      USING ERRCODE = '23514';
  END IF;

  IF NEW.trailer_moto_id IS NOT NULL THEN
    SELECT m.branch_id INTO v_branch FROM motorcycles m WHERE m.id = NEW.trailer_moto_id;
    IF public.branch_is_closed(v_branch, v_start, v_end) THEN
      SELECT b.name INTO v_name FROM branches b WHERE b.id = v_branch;
      RAISE EXCEPTION 'Pobočka % je v termínu % – % zavřená, vozík nelze půjčit.',
        COALESCE(v_name, 'vozíku'), to_char(v_start, 'DD.MM.YYYY'), to_char(v_end, 'DD.MM.YYYY')
        USING ERRCODE = '23514';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- gear 2026-10-23: + branch_id (přesun výpůjčky výbavy na zavřenou pobočku)
DROP TRIGGER IF EXISTS trg_check_booking_branch_open ON public.bookings;
CREATE TRIGGER trg_check_booking_branch_open BEFORE INSERT OR UPDATE OF start_date, end_date, moto_id,
  trailer_moto_id, status, branch_id ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public.check_booking_branch_open();

CREATE OR REPLACE FUNCTION public.check_user_booking_overlap()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- SOS replacement bookings are exempt from overlap check
  IF NEW.sos_replacement = true THEN
    RETURN NEW;
  END IF;

  -- Testovací rezervace (is_test) jsou z kontroly vyjmuté (NEW 2026-08-20):
  -- seed obsazenosti kalendáře = jeden účet, mnoho motorek souběžně.
  IF NEW.is_test IS TRUE THEN
    RETURN NEW;
  END IF;

  -- gear 2026-10-23: výpůjčka výbavy se smí překrývat s čímkoli (rozhodnutí majitele)
  IF NEW.booking_kind = 'gear' THEN
    RETURN NEW;
  END IF;

  -- Skip cancelled/completed bookings
  IF NEW.status IN ('cancelled', 'completed') THEN
    RETURN NEW;
  END IF;

  -- Check for overlapping bookings for the same user
  IF EXISTS (
    SELECT 1 FROM bookings o
    WHERE o.user_id = NEW.user_id
      AND o.id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
      AND o.status NOT IN ('cancelled', 'completed')
      AND o.sos_replacement IS NOT TRUE
      -- Testovací rezervace nikdy neblokují reálné (NEW 2026-08-20)
      AND o.is_test IS NOT TRUE
      -- gear 2026-10-23: existující výpůjčka výbavy neblokuje
      AND o.booking_kind IS DISTINCT FROM 'gear'
      AND o.start_date::date <= NEW.end_date::date
      AND o.end_date::date >= NEW.start_date::date
      -- Výjimka: dětské motorky (license_required = 'N')
      AND o.moto_id NOT IN (SELECT id FROM motorcycles WHERE license_required = 'N')
      -- Výjimka: výměna motorky (switch chain) — dvojice A↔B spojená přes
      -- continues_booking_id se nepovažuje za kolizi ani na sdílený hraniční den.
      AND o.id IS DISTINCT FROM NEW.continues_booking_id
      AND o.continues_booking_id IS DISTINCT FROM NEW.id
  ) THEN
    RAISE EXCEPTION 'Zákazník má překrývající se rezervaci v tomto období';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.check_web_booking_user_overlap(p_email text, p_start date, p_end date,
                                                                 p_exclude_booking_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_uid uuid;
  v_row record;
BEGIN
  IF p_email IS NULL OR trim(p_email) = '' OR p_start IS NULL OR p_end IS NULL THEN
    RETURN jsonb_build_object('overlap', false);
  END IF;

  SELECT id INTO v_uid FROM auth.users
   WHERE lower(email) = lower(trim(p_email))
   LIMIT 1;

  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('overlap', false);  -- neznámý e-mail → žádná kolize
  END IF;

  -- 2026-10-11: jen vlastník / admin / service, nebo obnova vlastní rozpracované
  -- webové rezervace (jinak create_web_booking vrátí email_exists / email_mismatch)
  IF NOT public._web_booking_full_access(v_uid)
     AND NOT EXISTS (SELECT 1 FROM bookings eb
                      WHERE eb.id = p_exclude_booking_id AND eb.user_id = v_uid
                        AND eb.status = 'pending' AND eb.payment_status = 'unpaid'
                        AND eb.booking_source = 'web') THEN
    RETURN jsonb_build_object('overlap', false);
  END IF;

  SELECT b.id, b.start_date, b.end_date
    INTO v_row
    FROM bookings b
   WHERE b.user_id = v_uid
     AND b.status IN ('pending','reserved','active','completed')
     AND b.booking_kind IS DISTINCT FROM 'gear'  -- gear 2026-10-23: výpůjčka výbavy nekoliduje
     AND (p_exclude_booking_id IS NULL OR b.id <> p_exclude_booking_id)
     AND daterange(b.start_date::date, b.end_date::date, '[]')
         && daterange(p_start, p_end, '[]')
   ORDER BY b.start_date
   LIMIT 1;

  IF v_row.id IS NULL THEN
    RETURN jsonb_build_object('overlap', false);
  END IF;

  RETURN jsonb_build_object('overlap', true);  -- 2026-10-11: bez booking_id / termínů
END;
$$;
