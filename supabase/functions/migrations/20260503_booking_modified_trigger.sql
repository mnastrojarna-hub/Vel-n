-- =============================================================================
-- MIGRACE 2026-05-03 (B): trg_send_booking_modified_email — Etapa 4/4
--
-- Doplnění předchozí migrace 20260503_email_templates_unified.sql.
-- Pokrývá všechny tři kanály (Velin, web, Flutter app, RPC apply_booking_changes
-- a apply_booking_changes_anon, shorten_booking_with_refund) jediným triggerem
-- na bookings AFTER UPDATE.
--
-- Detekce: změna moto_id / start_date / end_date / total_price / pickup_method /
-- pickup_address / return_method / return_address (alespoň jedno).
-- Status changes (reserved↔active↔completed↔cancelled) NEPOSÍLAJÍ — pro ty
-- existují vlastní triggery (booking_completed, booking_cancelled).
--
-- Dedup: 5min window přes message_log — Velin/app může volat send-booking-email
-- explicitně, druhý mail se skipne.
--
-- Mail obsahuje original_* (z OLD) i nové (z NEW) — frontend v send-booking-email
-- (Etapa 2) z toho vyrobí diff tabulku „Původní vs Nové".
-- =============================================================================

CREATE OR REPLACE FUNCTION trg_send_booking_modified_email() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_url text;
  v_key text;
  v_profile profiles%ROWTYPE;
  v_moto_old text;
  v_moto_new text;
  v_already_sent boolean;
  v_changed boolean;
BEGIN
  -- Status change → handled by other triggers (completed/cancelled)
  IF NEW.status IS DISTINCT FROM OLD.status THEN RETURN NEW; END IF;

  -- Pouze pro reserved/active rezervace
  IF NEW.status NOT IN ('reserved','active') THEN RETURN NEW; END IF;

  -- Detekce změny klíčových polí
  v_changed :=
       NEW.moto_id        IS DISTINCT FROM OLD.moto_id
    OR NEW.start_date     IS DISTINCT FROM OLD.start_date
    OR NEW.end_date       IS DISTINCT FROM OLD.end_date
    OR NEW.total_price    IS DISTINCT FROM OLD.total_price
    OR NEW.pickup_method  IS DISTINCT FROM OLD.pickup_method
    OR NEW.pickup_address IS DISTINCT FROM OLD.pickup_address
    OR NEW.return_method  IS DISTINCT FROM OLD.return_method
    OR NEW.return_address IS DISTINCT FROM OLD.return_address;
  IF NOT v_changed THEN RETURN NEW; END IF;

  -- Dedup 5min window
  SELECT EXISTS(
    SELECT 1 FROM message_log
     WHERE booking_id = NEW.id
       AND template_slug LIKE 'booking_modified%'
       AND status = 'sent'
       AND created_at > now() - interval '5 minutes'
     LIMIT 1
  ) INTO v_already_sent;
  IF v_already_sent THEN RETURN NEW; END IF;

  -- pg_net config
  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'trg_send_booking_modified_email: app_settings missing';
    RETURN NEW;
  END IF;

  SELECT * INTO v_profile FROM profiles WHERE id = NEW.user_id;
  IF NOT FOUND OR v_profile.email IS NULL OR v_profile.email = '' THEN RETURN NEW; END IF;

  SELECT model INTO v_moto_old FROM motorcycles WHERE id = OLD.moto_id;
  SELECT model INTO v_moto_new FROM motorcycles WHERE id = NEW.moto_id;

  PERFORM net.http_post(
    url     := v_url || '/functions/v1/send-booking-email',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_key
    ),
    body    := jsonb_build_object(
      'type',                    'booking_modified',
      'booking_id',              NEW.id,
      'customer_email',          v_profile.email,
      'customer_name',           COALESCE(v_profile.full_name, ''),
      'source',                  COALESCE(NEW.booking_source, 'app'),
      'motorcycle',              COALESCE(v_moto_new, ''),
      'start_date',              NEW.start_date,
      'end_date',                NEW.end_date,
      'total_price',             NEW.total_price,
      'price_difference',        COALESCE(NEW.total_price, 0) - COALESCE(OLD.total_price, 0),
      'pickup_method',           COALESCE(NEW.pickup_method, ''),
      'pickup_address',          COALESCE(NEW.pickup_address, ''),
      'return_method',           COALESCE(NEW.return_method, ''),
      'return_address',          COALESCE(NEW.return_address, ''),
      'original_motorcycle',     COALESCE(v_moto_old, ''),
      'original_start_date',     OLD.start_date,
      'original_end_date',       OLD.end_date,
      'original_total_price',    OLD.total_price,
      'original_pickup_method',  COALESCE(OLD.pickup_method, ''),
      'original_pickup_address', COALESCE(OLD.pickup_address, ''),
      'original_return_method',  COALESCE(OLD.return_method, ''),
      'original_return_address', COALESCE(OLD.return_address, '')
    )
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_send_booking_modified_email failed for booking %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_booking_modified_email ON bookings;
CREATE TRIGGER trg_booking_modified_email
  AFTER UPDATE ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION trg_send_booking_modified_email();
