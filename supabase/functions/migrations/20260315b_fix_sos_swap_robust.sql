-- =============================================================================
-- 2026-03-15b: Robust SOS swap + KF trigger fix pro SOS bookings
--
-- Problémy:
-- 1. sos_swap_bookings nemůže najít booking pokud byl předtím ukončen
--    (ended_by_sos=true, status=completed) → swap selže → ZF/DP se negenerují
-- 2. generate_final_invoice_on_complete generuje plnou KF i pro SOS-ukončené
--    bookings, které potřebují speciální handling
-- 3. check_user_booking_overlap blokuje SOS replacement INSERT
--
-- Opravy:
-- A) sos_swap_bookings: přidán fallback pro ended_by_sos bookings
-- B) generate_final_invoice_on_complete: SOS-ended = bez plné KF
-- C) check_user_booking_overlap: SOS replacement výjimka
-- =============================================================================

-- ═══════════════════════════════════════════════
-- A) Robustní sos_swap_bookings
-- ═══════════════════════════════════════════════
CREATE OR REPLACE FUNCTION sos_swap_bookings(
  p_incident_id uuid,
  p_replacement_moto_id uuid,
  p_replacement_model text DEFAULT NULL,
  p_delivery_fee numeric DEFAULT 0,
  p_daily_price numeric DEFAULT 0,
  p_is_free boolean DEFAULT true
)
RETURNS jsonb AS $$
DECLARE
  v_incident record;
  v_booking record;
  v_original_end date;
  v_new_booking_id uuid;
  v_remaining_days int;
  v_total_price numeric;
  v_today date := CURRENT_DATE;
  v_already_ended boolean := false;
BEGIN
  SELECT * INTO v_incident FROM sos_incidents WHERE id = p_incident_id;
  IF v_incident IS NULL THEN
    RETURN jsonb_build_object('error', 'Incident not found');
  END IF;

  -- 1. Hledej aktivní booking (standard)
  SELECT * INTO v_booking FROM bookings
    WHERE user_id = v_incident.user_id
      AND status IN ('active', 'pending', 'reserved', 'confirmed')
      AND payment_status = 'paid'
      AND start_date::date <= v_today
      AND end_date::date >= v_today
    ORDER BY start_date DESC
    LIMIT 1;

  -- 2. Fallback: jakýkoliv ne-cancelled booking
  IF v_booking IS NULL THEN
    SELECT * INTO v_booking FROM bookings
      WHERE user_id = v_incident.user_id
        AND status NOT IN ('cancelled', 'completed')
        AND start_date::date <= v_today
        AND end_date::date >= v_today
      ORDER BY start_date DESC
      LIMIT 1;
  END IF;

  -- 3. Fallback: booking_id z incidentu (ne-cancelled/completed)
  IF v_booking IS NULL AND v_incident.booking_id IS NOT NULL THEN
    SELECT * INTO v_booking FROM bookings
      WHERE id = v_incident.booking_id
        AND status NOT IN ('cancelled', 'completed');
  END IF;

  -- 4. NOVÝ FALLBACK: booking již ukončený SOS (_sosEndBooking běžel dříve)
  IF v_booking IS NULL THEN
    SELECT * INTO v_booking FROM bookings
      WHERE user_id = v_incident.user_id
        AND ended_by_sos = true
        AND status = 'completed'
        AND end_date::date >= v_today - 1  -- max 1 den zpět
      ORDER BY end_date DESC, created_at DESC
      LIMIT 1;
    IF v_booking IS NOT NULL THEN
      v_already_ended := true;
    END IF;
  END IF;

  -- 5. Fallback: booking_id z incidentu (i completed+ended_by_sos)
  IF v_booking IS NULL AND v_incident.booking_id IS NOT NULL THEN
    SELECT * INTO v_booking FROM bookings
      WHERE id = v_incident.booking_id
        AND status != 'cancelled';
    IF v_booking IS NOT NULL AND v_booking.status = 'completed' AND v_booking.ended_by_sos = true THEN
      v_already_ended := true;
    END IF;
  END IF;

  IF v_booking IS NULL THEN
    RETURN jsonb_build_object('error', 'No active booking found for user');
  END IF;

  -- Pro již ukončené bookings: použij original_end_date pokud existuje, jinak end_date
  -- (end_date mohl být zkrácen _sosEndBooking na dnešek)
  v_original_end := COALESCE(v_booking.original_end_date, v_booking.end_date)::date;
  -- Pokud original_end je v minulosti, nastavíme alespoň dnešek
  IF v_original_end < v_today THEN
    v_original_end := v_today;
  END IF;
  v_remaining_days := GREATEST(1, (v_original_end - v_today) + 1);
  v_total_price := CASE WHEN p_is_free THEN 0 ELSE (p_daily_price * v_remaining_days + p_delivery_fee) END;

  -- Step 1: Ukonči původní booking (pokud ještě nebyl ukončen)
  IF NOT v_already_ended THEN
    BEGIN
      -- Ulož original_end_date pokud ještě není nastaveno
      UPDATE bookings SET
        original_end_date = CASE WHEN original_end_date IS NULL THEN end_date ELSE original_end_date END,
        end_date = v_today,
        status = 'completed',
        ended_by_sos = true,
        sos_incident_id = p_incident_id,
        notes = COALESCE(notes, '') || E'\n[SOS] Ukončeno ke dni ' || v_today::text || '. Náhradní motorka objednána.'
      WHERE id = v_booking.id;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'sos_swap: original booking update failed (%), trying minimal', SQLERRM;
      BEGIN
        UPDATE bookings SET
          status = 'completed',
          ended_by_sos = true,
          sos_incident_id = p_incident_id
        WHERE id = v_booking.id;
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'sos_swap: even minimal update failed: %', SQLERRM;
      END;
    END;
  ELSE
    -- Booking je již ukončený — jen přidej sos_incident_id pokud chybí
    BEGIN
      UPDATE bookings SET
        sos_incident_id = COALESCE(sos_incident_id, p_incident_id)
      WHERE id = v_booking.id AND sos_incident_id IS NULL;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;

  -- Step 2: Vytvoř náhradní booking
  BEGIN
    INSERT INTO bookings (
      user_id, moto_id, start_date, end_date, pickup_time,
      status, payment_status, total_price, delivery_fee,
      sos_replacement, replacement_for_booking_id, sos_incident_id,
      notes, booking_source, picked_up_at
    ) VALUES (
      v_incident.user_id,
      p_replacement_moto_id,
      v_today,
      v_original_end,
      '09:00',
      'active',
      CASE WHEN p_is_free THEN 'paid' ELSE 'unpaid' END,
      v_total_price,
      CASE WHEN p_is_free THEN 0 ELSE p_delivery_fee END,
      true,
      v_booking.id,
      p_incident_id,
      '[SOS] Náhradní motorka za ' || COALESCE((SELECT model FROM motorcycles WHERE id = v_booking.moto_id), 'původní') || '. Incident: ' || p_incident_id::text,
      'app',
      NOW()  -- SOS replacement je okamžitě "vydaná"
    )
    RETURNING id INTO v_new_booking_id;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'sos_swap: replacement booking INSERT failed: %', SQLERRM;
    UPDATE sos_incidents SET
      original_booking_id = v_booking.id,
      original_moto_id = v_booking.moto_id
    WHERE id = p_incident_id;
    UPDATE motorcycles SET status = 'maintenance' WHERE id = v_booking.moto_id;
    RETURN jsonb_build_object(
      'error', 'Replacement booking failed: ' || SQLERRM,
      'original_booking_id', v_booking.id,
      'partial', true
    );
  END;

  -- Step 3: Update sos_incidents
  UPDATE sos_incidents SET
    original_booking_id = v_booking.id,
    replacement_booking_id = v_new_booking_id,
    original_moto_id = v_booking.moto_id,
    replacement_moto_id = p_replacement_moto_id
  WHERE id = p_incident_id;

  -- Step 4: Původní motorka do servisu
  UPDATE motorcycles SET status = 'maintenance'
  WHERE id = v_booking.moto_id;

  RETURN jsonb_build_object(
    'success', true,
    'original_booking_id', v_booking.id,
    'replacement_booking_id', v_new_booking_id,
    'remaining_days', v_remaining_days,
    'total_price', v_total_price,
    'original_end_date', v_original_end
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ═══════════════════════════════════════════════
-- B) KF trigger: SOS-ended bookings = speciální KF
-- ═══════════════════════════════════════════════
CREATE OR REPLACE FUNCTION generate_final_invoice_on_complete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_inv_num text;
  v_seq int;
  v_year int := EXTRACT(YEAR FROM CURRENT_DATE)::int;
  v_items jsonb;
  v_total numeric;
  v_moto_model text;
  v_moto_spz text;
  v_actual_days int;
BEGIN
  -- Pouze při přechodu z active na completed
  IF OLD.status != 'active' OR NEW.status != 'completed' THEN
    RETURN NEW;
  END IF;

  -- Přeskoč pokud už KF existuje
  IF EXISTS (SELECT 1 FROM invoices WHERE booking_id = NEW.id AND type = 'final') THEN
    RETURN NEW;
  END IF;

  -- Přeskoč pokud nebylo zaplaceno
  IF NEW.payment_status != 'paid' THEN
    RETURN NEW;
  END IF;

  -- Pro SOS-ended bookings: přeskoč KF — bude vyřešena separátně
  -- (SOS booking potřebuje přepočítat cenu za skutečné dny, odečíst zálohy atd.)
  IF NEW.ended_by_sos = true THEN
    RAISE NOTICE 'Skipping KF for SOS-ended booking %', NEW.id;
    RETURN NEW;
  END IF;

  -- Pro SOS replacement bookings: přeskoč — mají vlastní ZF/DP flow
  IF NEW.sos_replacement = true THEN
    RAISE NOTICE 'Skipping KF for SOS replacement booking %', NEW.id;
    RETURN NEW;
  END IF;

  -- Získej data motorky
  SELECT model, spz INTO v_moto_model, v_moto_spz
  FROM motorcycles WHERE id = NEW.moto_id;

  -- Generuj číslo faktury KF-YYYY-NNNN
  SELECT COALESCE(MAX(CAST(SUBSTRING(number FROM '-(\d+)$') AS int)), 0) + 1
  INTO v_seq FROM invoices WHERE number LIKE 'KF-' || v_year || '-%';
  v_inv_num := 'KF-' || v_year || '-' || LPAD(v_seq::text, 4, '0');

  -- Položky faktury
  v_items := jsonb_build_array(jsonb_build_object(
    'description', 'Pronájem ' || COALESCE(v_moto_model, 'motorky') ||
      ' (' || COALESCE(v_moto_spz, '') || ') — ' ||
      TO_CHAR(NEW.start_date, 'DD.MM.YYYY') || ' – ' || TO_CHAR(NEW.end_date, 'DD.MM.YYYY'),
    'qty', 1, 'unit_price', COALESCE(NEW.total_price, 0)
  ));

  -- Odpočet záloh (DP = payment_receipt)
  v_items := v_items || COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'description', 'Odpočet dle DP ' || number,
      'qty', 1, 'unit_price', -total
    )) FROM invoices
    WHERE booking_id = NEW.id AND type = 'payment_receipt' AND status != 'cancelled'
  ), '[]'::jsonb);

  -- Celková částka
  v_total := (SELECT SUM((item->>'unit_price')::numeric * (item->>'qty')::numeric)
              FROM jsonb_array_elements(v_items) AS item);

  -- Vlož fakturu
  INSERT INTO invoices (number, type, customer_id, booking_id, items, subtotal, tax_amount, total,
                        issue_date, due_date, status, variable_symbol, source)
  VALUES (v_inv_num, 'final', NEW.user_id, NEW.id, v_items, v_total, 0, v_total,
          CURRENT_DATE, CURRENT_DATE, 'paid', v_inv_num, 'final_summary');

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'generate_final_invoice_on_complete failed for booking %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

-- ═══════════════════════════════════════════════
-- C) check_user_booking_overlap: SOS replacement výjimka
-- ═══════════════════════════════════════════════
CREATE OR REPLACE FUNCTION check_user_booking_overlap()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- SOS replacement bookings are exempt from overlap check
  IF NEW.sos_replacement = true THEN
    RETURN NEW;
  END IF;

  -- Skip cancelled/completed bookings
  IF NEW.status IN ('cancelled', 'completed') THEN
    RETURN NEW;
  END IF;

  -- Check for overlapping bookings for the same user
  IF EXISTS (
    SELECT 1 FROM bookings
    WHERE user_id = NEW.user_id
      AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
      AND status NOT IN ('cancelled', 'completed')
      AND sos_replacement IS NOT TRUE
      AND start_date::date <= NEW.end_date::date
      AND end_date::date >= NEW.start_date::date
      -- Výjimka: dětské motorky (license_required = 'N')
      AND moto_id NOT IN (SELECT id FROM motorcycles WHERE license_required = 'N')
  ) THEN
    RAISE EXCEPTION 'Zákazník má překrývající se rezervaci v tomto období';
  END IF;

  RETURN NEW;
END;
$$;
