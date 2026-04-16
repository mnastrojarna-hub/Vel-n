-- =============================================================================
-- MIGRACE: Fix KF — správný rozpis položek (pronájem brutto + sleva + DP)
--          + odeslání e-mailu "booking_completed" s KF v příloze a poděkováním
-- Datum: 2026-04-16
--
-- Problém:
-- 1. Konečná faktura (KF) dosud zobrazovala jen jednu položku "Pronájem"
--    s NEW.total_price — po modifikaci rezervace (prodloužení, změna motorky)
--    se ztratil rozpis a hlavně sleva (discount_code + discount_amount).
--    ZF/DP generované edge funkcí rozepisují: brutto pronájem, extras,
--    přistavení, slevu; KF nikoliv → nekonzistentní účetnictví.
-- 2. Po dokončení jízdy se posílá jen SMS+WhatsApp (trg_notify_ride_completed),
--    nikdy se nevolal send-booking-email s type='booking_completed'. Zákazník
--    tak nedostal e-mail s poděkováním a KF v příloze.
--
-- Změny:
-- 1. generate_final_invoice_on_complete() rozepisuje položky stejně jako ZF/DP:
--      - Pronájem (brutto = total_price + discount_amount − extras − delivery)
--      - Příslušenství a výbava (pokud > 0)
--      - Přistavení / odvoz (pokud > 0)
--      - Sleva (kód: …) — záporná položka
--      - Odpočet dle DP — záporné položky pro všechny zaplacené DP
--    Celkem se spočte jako součet — pokud vše sedí, výsledek = 0 Kč.
--
-- 2. Nový trigger trg_send_booking_completed_email na invoices (AFTER INSERT
--    WHEN type='final') — pošle "booking_completed" e-mail přes pg_net volání
--    edge funkce send-booking-email. Ta si KF automaticky přiloží.
-- =============================================================================

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
  v_base_rental numeric;
  v_extras numeric;
  v_delivery numeric;
  v_discount numeric;
  v_discount_code text;
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

  -- SOS replacement má vlastní ZF/DP flow
  IF NEW.sos_replacement = true THEN
    RAISE NOTICE 'Skipping KF for SOS replacement booking %', NEW.id;
    RETURN NEW;
  END IF;

  -- Data motorky
  SELECT model, spz INTO v_moto_model, v_moto_spz
  FROM motorcycles WHERE id = NEW.moto_id;

  -- Číslo faktury KF-YYYY-NNNN
  SELECT COALESCE(MAX(CAST(SUBSTRING(number FROM '-(\d+)$') AS int)), 0) + 1
  INTO v_seq FROM invoices WHERE number LIKE 'KF-' || v_year || '-%';
  v_inv_num := 'KF-' || v_year || '-' || LPAD(v_seq::text, 4, '0');

  -- Rozpis položek (shoda se ZF/DP v generate-invoice edge funkci):
  -- total_price v bookings je NETTO (po slevě). Pro zobrazení pronájmu
  -- musíme rekonstruovat brutto a slevu zobrazit samostatně.
  v_extras   := COALESCE(NEW.extras_price, 0);
  v_delivery := COALESCE(NEW.delivery_fee, 0);
  v_discount := COALESCE(NEW.discount_amount, 0);
  v_discount_code := COALESCE(NEW.discount_code, '');
  v_base_rental := COALESCE(NEW.total_price, 0) - v_extras - v_delivery + v_discount;

  -- 1) Pronájem (brutto, bez slevy)
  v_items := jsonb_build_array(jsonb_build_object(
    'description', 'Pronájem ' || COALESCE(v_moto_model, 'motorky') ||
      ' (' || COALESCE(v_moto_spz, '') || ') — ' ||
      TO_CHAR(NEW.start_date, 'DD.MM.YYYY') || ' – ' || TO_CHAR(NEW.end_date, 'DD.MM.YYYY'),
    'qty', 1, 'unit_price', v_base_rental
  ));

  -- 2) Příslušenství a výbava
  IF v_extras > 0 THEN
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'description', 'Příslušenství a výbava',
      'qty', 1, 'unit_price', v_extras
    ));
  END IF;

  -- 3) Přistavení / odvoz
  IF v_delivery > 0 THEN
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'description', 'Přistavení / odvoz motorky',
      'qty', 1, 'unit_price', v_delivery
    ));
  END IF;

  -- 4) Sleva (záporná položka)
  IF v_discount > 0 THEN
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'description', CASE
        WHEN v_discount_code <> '' THEN 'Sleva (kód: ' || v_discount_code || ')'
        ELSE 'Sleva / voucher'
      END,
      'qty', 1, 'unit_price', -v_discount
    ));
  END IF;

  -- 5) Odpočet všech DP (záloh) — částky v DP jsou kladné, zde zapisujeme
  --    se záporným znaménkem jako odpočet
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

  -- Vlož fakturu (trigger trg_send_booking_completed_email se postará o email)
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


-- ═══════════════════════════════════════════════════════
-- NOVÝ TRIGGER: send_booking_completed_email
-- Při vložení KF (type='final') pošle e-mail s poděkováním a KF v příloze.
-- Vlastní KF si stáhne send-booking-email automaticky (autoGenerateAttachments).
-- ═══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION trg_send_booking_completed_email() RETURNS trigger AS $$
DECLARE
  v_url text;
  v_key text;
  v_booking bookings%ROWTYPE;
  v_profile profiles%ROWTYPE;
  v_moto_model text;
  v_source text;
  v_google_url text;
  v_facebook_url text;
  v_already_sent boolean;
BEGIN
  -- Pouze pro konečné faktury
  IF NEW.type != 'final' OR NEW.booking_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Dedup: pro tento booking jsme e-mail booking_completed už poslali?
  SELECT EXISTS(
    SELECT 1 FROM message_log
    WHERE booking_id = NEW.booking_id
      AND template_slug IN ('booking_completed', 'web_booking_completed')
      AND status = 'sent'
    LIMIT 1
  ) INTO v_already_sent;
  IF v_already_sent THEN RETURN NEW; END IF;

  -- Nastavení pg_net
  v_url := coalesce(current_setting('app.settings.supabase_url', true), '');
  v_key := coalesce(current_setting('app.settings.service_role_key', true), '');
  IF v_url = '' OR v_key = '' THEN
    RAISE WARNING 'trg_send_booking_completed_email: app.settings not configured';
    RETURN NEW;
  END IF;

  -- Data rezervace + zákazníka
  SELECT * INTO v_booking FROM bookings WHERE id = NEW.booking_id;
  IF NOT FOUND OR v_booking.user_id IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_profile FROM profiles WHERE id = v_booking.user_id;
  IF NOT FOUND OR v_profile.email IS NULL OR v_profile.email = '' THEN
    RAISE NOTICE 'trg_send_booking_completed_email: no email for user %', v_booking.user_id;
    RETURN NEW;
  END IF;

  SELECT model INTO v_moto_model FROM motorcycles WHERE id = v_booking.moto_id;
  v_source := COALESCE(v_booking.booking_source, 'app');

  -- URL pro recenze (volitelné — pokud nejsou v app_settings, send-booking-email použije prázdné)
  SELECT value::text INTO v_google_url FROM app_settings WHERE key = 'google_review_url';
  v_google_url := COALESCE(trim(both '"' from v_google_url), '');
  SELECT value::text INTO v_facebook_url FROM app_settings WHERE key = 'facebook_review_url';
  v_facebook_url := COALESCE(trim(both '"' from v_facebook_url), '');

  PERFORM net.http_post(
    url := v_url || '/functions/v1/send-booking-email',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_key,
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object(
      'type', 'booking_completed',
      'booking_id', NEW.booking_id,
      'customer_email', v_profile.email,
      'customer_name', v_profile.full_name,
      'motorcycle', COALESCE(v_moto_model, ''),
      'start_date', v_booking.start_date,
      'end_date', v_booking.end_date,
      'total_price', NEW.total,
      'source', v_source,
      'google_review_url', v_google_url,
      'facebook_review_url', v_facebook_url
    )
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_send_booking_completed_email failed: %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_send_booking_completed_email ON invoices;
CREATE TRIGGER trg_send_booking_completed_email
  AFTER INSERT ON invoices
  FOR EACH ROW
  WHEN (NEW.type = 'final')
  EXECUTE FUNCTION trg_send_booking_completed_email();

COMMENT ON FUNCTION trg_send_booking_completed_email IS
  'Po vložení KF pošle e-mail booking_completed s poděkováním a KF v příloze.';
