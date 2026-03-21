-- =====================================================
-- MotoGo24 — Messaging Triggers (SMS + WhatsApp)
-- Prerequisity:
--   - message_templates, message_log (z 20260320_messaging_system.sql)
--   - Edge Function send-message deploynutá
--   - pg_net extension zapnutá
--   - app.settings.supabase_url a app.settings.service_role_key nastavené
-- Idempotentní — bezpečně spustit opakovaně
-- =====================================================

-- ═══════════════════════════════════════════════════════
-- 0. OVĚŘENÍ app.settings
-- ═══════════════════════════════════════════════════════
-- Tyto hodnoty musí admin nastavit v Supabase SQL editoru:
-- ALTER DATABASE postgres SET app.settings.supabase_url = 'https://vnwnqteskbykeucanlhk.supabase.co';
-- ALTER DATABASE postgres SET app.settings.service_role_key = 'eyJ...service_role_key...';

DO $$
BEGIN
  IF coalesce(current_setting('app.settings.supabase_url', true), '') = '' THEN
    RAISE NOTICE 'app.settings.supabase_url not set — messaging triggers will not fire until configured';
  END IF;
  IF coalesce(current_setting('app.settings.service_role_key', true), '') = '' THEN
    RAISE NOTICE 'app.settings.service_role_key not set — messaging triggers will not fire until configured';
  END IF;
END $$;

-- Zapnutí pg_net (měla by být default v Supabase)
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ═══════════════════════════════════════════════════════
-- 1. HELPER FUNKCE: send_message_via_edge
-- Odešle zprávu přes Edge Function send-message.
-- Při jakékoli chybě pouze WARNuje — NIKDY neblokuje hlavní operaci.
-- ═══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION send_message_via_edge(
  p_channel text,
  p_to text,
  p_template_slug text,
  p_template_vars jsonb,
  p_customer_id uuid DEFAULT NULL,
  p_booking_id uuid DEFAULT NULL
) RETURNS void AS $$
DECLARE
  v_url text;
  v_key text;
BEGIN
  -- Načti nastavení
  v_url := coalesce(current_setting('app.settings.supabase_url', true), '');
  v_key := coalesce(current_setting('app.settings.service_role_key', true), '');

  -- Bez nastavení nepošlem nic
  IF v_url = '' OR v_key = '' THEN
    RAISE WARNING 'send_message_via_edge: app.settings not configured, skipping';
    RETURN;
  END IF;

  -- Validace telefonu
  IF p_to IS NULL OR p_to = '' THEN
    RAISE WARNING 'send_message_via_edge: empty phone, skipping (slug=%)', p_template_slug;
    RETURN;
  END IF;

  PERFORM net.http_post(
    url := v_url || '/functions/v1/send-message',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_key,
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object(
      'channel', p_channel,
      'to', p_to,
      'template_slug', p_template_slug,
      'template_vars', p_template_vars,
      'customer_id', p_customer_id,
      'booking_id', p_booking_id
    )
  );
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'send_message_via_edge failed (slug=%, channel=%): %', p_template_slug, p_channel, SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ═══════════════════════════════════════════════════════
-- 1b. HELPER: Pošli SMS + WhatsApp (dvě volání)
-- ═══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION send_sms_and_wa(
  p_to text,
  p_template_slug text,
  p_template_vars jsonb,
  p_customer_id uuid DEFAULT NULL,
  p_booking_id uuid DEFAULT NULL
) RETURNS void AS $$
BEGIN
  -- SMS jako primární kanál
  PERFORM send_message_via_edge('sms', p_to, p_template_slug, p_template_vars, p_customer_id, p_booking_id);
  -- WhatsApp jako sekundární kanál
  PERFORM send_message_via_edge('whatsapp', p_to, p_template_slug, p_template_vars, p_customer_id, p_booking_id);
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'send_sms_and_wa failed (slug=%): %', p_template_slug, SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ═══════════════════════════════════════════════════════
-- 2. TRIGGER: notify_booking_confirmed
-- Při potvrzení rezervace (status → 'reserved')
-- posílá SMS + WA s template_slug 'booking_confirmed'
-- ═══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION trg_notify_booking_confirmed() RETURNS trigger AS $$
DECLARE
  v_phone text;
  v_moto_model text;
  v_already_sent boolean;
BEGIN
  -- Kontrola: status se právě změnil na 'reserved'
  IF NEW.status != 'reserved' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = 'reserved' THEN RETURN NEW; END IF;

  -- Dedup: už jsme pro tento booking poslali booking_confirmed?
  SELECT EXISTS(
    SELECT 1 FROM message_log
    WHERE booking_id = NEW.id AND template_slug = 'booking_confirmed' AND status = 'sent'
    LIMIT 1
  ) INTO v_already_sent;
  IF v_already_sent THEN RETURN NEW; END IF;

  -- Načti telefon zákazníka
  SELECT phone INTO v_phone FROM profiles WHERE id = NEW.user_id;
  IF v_phone IS NULL OR v_phone = '' THEN RETURN NEW; END IF;

  -- Načti model motorky
  SELECT model INTO v_moto_model FROM motorcycles WHERE id = NEW.moto_id;

  -- Odešli SMS + WA
  PERFORM send_sms_and_wa(
    v_phone,
    'booking_confirmed',
    jsonb_build_object(
      'booking_number', upper(left(NEW.id::text, 8)),
      'motorcycle', coalesce(v_moto_model, ''),
      'start_date', coalesce(to_char(NEW.start_date, 'DD.MM.YYYY'), ''),
      'end_date', coalesce(to_char(NEW.end_date, 'DD.MM.YYYY'), '')
    ),
    NEW.user_id,
    NEW.id
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_notify_booking_confirmed failed: %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_booking_confirmed ON bookings;
CREATE TRIGGER trg_notify_booking_confirmed
  AFTER INSERT OR UPDATE OF status ON bookings
  FOR EACH ROW
  WHEN (NEW.status = 'reserved')
  EXECUTE FUNCTION trg_notify_booking_confirmed();


-- ═══════════════════════════════════════════════════════
-- 3. TRIGGER: notify_door_codes
-- Při vložení nového přístupového kódu typu 'motorcycle'
-- načte oba kódy (motorcycle + accessories) a pošle zákazníkovi
-- ═══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION trg_notify_door_codes() RETURNS trigger AS $$
DECLARE
  v_phone text;
  v_user_id uuid;
  v_code_moto text;
  v_code_gear text;
  v_already_sent boolean;
BEGIN
  -- Posíláme jen jednou — při insertu kódu typu 'motorcycle'
  IF NEW.code_type != 'motorcycle' THEN RETURN NEW; END IF;

  -- Dedup: už jsme pro tento booking poslali door_codes?
  SELECT EXISTS(
    SELECT 1 FROM message_log
    WHERE booking_id = NEW.booking_id AND template_slug = 'door_codes' AND status = 'sent'
    LIMIT 1
  ) INTO v_already_sent;
  IF v_already_sent THEN RETURN NEW; END IF;

  -- Načti user_id z bookingu
  SELECT user_id INTO v_user_id FROM bookings WHERE id = NEW.booking_id;
  IF v_user_id IS NULL THEN RETURN NEW; END IF;

  -- Načti telefon zákazníka
  SELECT phone INTO v_phone FROM profiles WHERE id = v_user_id;
  IF v_phone IS NULL OR v_phone = '' THEN RETURN NEW; END IF;

  -- Kód motorky je z aktuálního řádku
  v_code_moto := NEW.door_code;

  -- Načti kód pro příslušenství (accessories)
  SELECT door_code INTO v_code_gear
  FROM branch_door_codes
  WHERE booking_id = NEW.booking_id AND code_type = 'accessories'
  LIMIT 1;

  -- Odešli SMS + WA
  PERFORM send_sms_and_wa(
    v_phone,
    'door_codes',
    jsonb_build_object(
      'booking_number', upper(left(NEW.booking_id::text, 8)),
      'door_code_moto', coalesce(v_code_moto, '—'),
      'door_code_gear', coalesce(v_code_gear, '—')
    ),
    v_user_id,
    NEW.booking_id
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_notify_door_codes failed: %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_door_codes ON branch_door_codes;
CREATE TRIGGER trg_notify_door_codes
  AFTER INSERT ON branch_door_codes
  FOR EACH ROW
  WHEN (NEW.code_type = 'motorcycle')
  EXECUTE FUNCTION trg_notify_door_codes();


-- ═══════════════════════════════════════════════════════
-- 4. TRIGGER: notify_booking_cancelled
-- Při zrušení rezervace (status → 'cancelled')
-- posílá SMS + WA s template_slug 'booking_cancelled'
-- ═══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION trg_notify_booking_cancelled() RETURNS trigger AS $$
DECLARE
  v_phone text;
  v_already_sent boolean;
BEGIN
  -- Dedup
  SELECT EXISTS(
    SELECT 1 FROM message_log
    WHERE booking_id = NEW.id AND template_slug = 'booking_cancelled' AND status = 'sent'
    LIMIT 1
  ) INTO v_already_sent;
  IF v_already_sent THEN RETURN NEW; END IF;

  -- Načti telefon zákazníka
  SELECT phone INTO v_phone FROM profiles WHERE id = NEW.user_id;
  IF v_phone IS NULL OR v_phone = '' THEN RETURN NEW; END IF;

  -- Odešli SMS + WA
  PERFORM send_sms_and_wa(
    v_phone,
    'booking_cancelled',
    jsonb_build_object(
      'booking_number', upper(left(NEW.id::text, 8))
    ),
    NEW.user_id,
    NEW.id
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_notify_booking_cancelled failed: %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_booking_cancelled ON bookings;
CREATE TRIGGER trg_notify_booking_cancelled
  AFTER UPDATE OF status ON bookings
  FOR EACH ROW
  WHEN (NEW.status = 'cancelled' AND OLD.status IS DISTINCT FROM 'cancelled')
  EXECUTE FUNCTION trg_notify_booking_cancelled();


-- ═══════════════════════════════════════════════════════
-- 5. TRIGGER: notify_ride_completed
-- Při dokončení jízdy (status → 'completed')
-- posílá SMS + WA s template_slug 'ride_completed'
-- ═══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION trg_notify_ride_completed() RETURNS trigger AS $$
DECLARE
  v_phone text;
  v_moto_model text;
  v_already_sent boolean;
BEGIN
  -- Dedup
  SELECT EXISTS(
    SELECT 1 FROM message_log
    WHERE booking_id = NEW.id AND template_slug = 'ride_completed' AND status = 'sent'
    LIMIT 1
  ) INTO v_already_sent;
  IF v_already_sent THEN RETURN NEW; END IF;

  -- Načti telefon zákazníka
  SELECT phone INTO v_phone FROM profiles WHERE id = NEW.user_id;
  IF v_phone IS NULL OR v_phone = '' THEN RETURN NEW; END IF;

  -- Načti model motorky
  SELECT model INTO v_moto_model FROM motorcycles WHERE id = NEW.moto_id;

  -- Odešli SMS + WA
  PERFORM send_sms_and_wa(
    v_phone,
    'ride_completed',
    jsonb_build_object(
      'motorcycle', coalesce(v_moto_model, ''),
      'booking_number', upper(left(NEW.id::text, 8)),
      'review_link', 'https://motogo24.cz/hodnoceni/' || NEW.id::text
    ),
    NEW.user_id,
    NEW.id
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_notify_ride_completed failed: %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_ride_completed ON bookings;
CREATE TRIGGER trg_notify_ride_completed
  AFTER UPDATE OF status ON bookings
  FOR EACH ROW
  WHEN (NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed')
  EXECUTE FUNCTION trg_notify_ride_completed();


-- ═══════════════════════════════════════════════════════
-- 6. TRIGGER: notify_voucher_purchased
-- Při vytvoření nového aktivního voucheru
-- posílá SMS s template_slug 'voucher_purchased'
-- ═══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION trg_notify_voucher_purchased() RETURNS trigger AS $$
DECLARE
  v_phone text;
  v_buyer_id uuid;
  v_already_sent boolean;
BEGIN
  -- Pouze aktivní vouchery
  IF NEW.status != 'active' THEN RETURN NEW; END IF;

  -- Dedup: už jsme pro tento voucher poslali?
  SELECT EXISTS(
    SELECT 1 FROM message_log
    WHERE template_slug = 'voucher_purchased'
      AND metadata->>'voucher_id' = NEW.id::text
      AND status = 'sent'
    LIMIT 1
  ) INTO v_already_sent;
  IF v_already_sent THEN RETURN NEW; END IF;

  -- Najdi kupujícího — buyer_id odkazuje na profiles
  v_buyer_id := NEW.buyer_id;
  IF v_buyer_id IS NULL THEN RETURN NEW; END IF;

  -- Načti telefon
  SELECT phone INTO v_phone FROM profiles WHERE id = v_buyer_id;
  IF v_phone IS NULL OR v_phone = '' THEN RETURN NEW; END IF;

  -- Odešli jen SMS (voucher = jednoduché sdělení, bez WA)
  PERFORM send_message_via_edge(
    'sms',
    v_phone,
    'voucher_purchased',
    jsonb_build_object(
      'voucher_code', coalesce(NEW.code, ''),
      'voucher_amount', coalesce(NEW.amount::text, '0'),
      'expiry_date', coalesce(to_char(NEW.valid_until, 'DD.MM.YYYY'), '')
    ),
    v_buyer_id,
    NULL
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_notify_voucher_purchased failed: %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_voucher_purchased ON vouchers;
CREATE TRIGGER trg_notify_voucher_purchased
  AFTER INSERT ON vouchers
  FOR EACH ROW
  WHEN (NEW.status = 'active')
  EXECUTE FUNCTION trg_notify_voucher_purchased();


-- ═══════════════════════════════════════════════════════
-- 7. KOMENTÁŘE A GRANTY
-- ═══════════════════════════════════════════════════════

COMMENT ON FUNCTION send_message_via_edge IS 'Odešle zprávu přes Edge Function send-message. Nikdy neblokuje hlavní operaci.';
COMMENT ON FUNCTION send_sms_and_wa IS 'Odešle SMS (primární) + WhatsApp (sekundární) přes send_message_via_edge.';
COMMENT ON FUNCTION trg_notify_booking_confirmed IS 'Trigger: potvrzení rezervace → SMS + WA zákazníkovi';
COMMENT ON FUNCTION trg_notify_door_codes IS 'Trigger: vygenerování přístupových kódů → SMS + WA zákazníkovi';
COMMENT ON FUNCTION trg_notify_booking_cancelled IS 'Trigger: storno rezervace → SMS + WA zákazníkovi';
COMMENT ON FUNCTION trg_notify_ride_completed IS 'Trigger: dokončení jízdy → SMS + WA zákazníkovi';
COMMENT ON FUNCTION trg_notify_voucher_purchased IS 'Trigger: zakoupení voucheru → SMS zákazníkovi';

-- Granty pro service_role (pg_net potřebuje)
GRANT USAGE ON SCHEMA net TO postgres;
GRANT EXECUTE ON FUNCTION net.http_post TO postgres;
