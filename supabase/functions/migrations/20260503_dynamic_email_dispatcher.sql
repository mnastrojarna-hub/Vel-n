-- =============================================================================
-- MIGRACE 2026-05-03 (D): Dynamic email dispatcher — Etapa 7
--
-- ⚠️ NESPOUŠTĚT dokud nejsou hotové edge fn úpravy (commit ve stejné větvi).
--    Tato migrace je NEDESTRUKTIVNÍ — přidává paralelní dispatch cestu vedle
--    stávajícího hardcoded chování. Existující šablony fungují dál stejně,
--    nové custom šablony fungují jen s touto migrací + deploynutými edge fn.
-- =============================================================================
-- Mechanismus:
--   1. Edge fn / DB triggery při události navíc volají dispatch_email_event(slug)
--   2. RPC najde všechny aktivní šablony co mají daný event v triggers jsonb
--   3. Pro každou pošle send-booking-email s template_slug parametrem
--   4. Edge fn načte body z DB, lokalizuje (body_translations[lang]),
--      přiloží dokumenty (attachments jsonb) a pošle
--   5. Dedup přes message_log (5 min window per booking_id + template_slug)
-- =============================================================================

-- 1) GIN index na triggers jsonb pro rychlý lookup `triggers @> '["event_slug"]'`
CREATE INDEX IF NOT EXISTS idx_email_templates_triggers_gin
  ON email_templates USING gin (triggers jsonb_path_ops);


-- 2) RPC: najde aktivní šablony pro daný event slug
CREATE OR REPLACE FUNCTION find_email_templates_for_event(p_event_slug text)
RETURNS TABLE (
  id              uuid,
  slug            text,
  name            text,
  subject         text,
  body_html       text,
  active          boolean,
  attachments     jsonb,
  triggers        jsonb,
  subject_translations jsonb,
  body_translations    jsonb
)
LANGUAGE sql STABLE SECURITY DEFINER
AS $$
  SELECT t.id, t.slug, t.name, t.subject, t.body_html, t.active,
         t.attachments, t.triggers, t.subject_translations, t.body_translations
    FROM email_templates t
   WHERE t.active = true
     AND t.triggers @> jsonb_build_array(p_event_slug);
$$;
GRANT EXECUTE ON FUNCTION find_email_templates_for_event(text)
  TO anon, authenticated, service_role;


-- 3) Hlavní dispatcher RPC: pro každou matching šablonu volá send-booking-email
--    přes pg_net s template_slug parametrem
CREATE OR REPLACE FUNCTION dispatch_email_event(
  p_event_slug text,
  p_payload    jsonb DEFAULT '{}'::jsonb
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_url text;
  v_key text;
  v_tpl record;
  v_body jsonb;
BEGIN
  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'dispatch_email_event: app_settings missing — skipping event %', p_event_slug;
    RETURN;
  END IF;

  -- Pro každou matching šablonu pošli zvlášť (může být víc šablon na 1 event)
  FOR v_tpl IN
    SELECT id, slug, name FROM email_templates
     WHERE active = true
       AND triggers @> jsonb_build_array(p_event_slug)
     ORDER BY created_at ASC
  LOOP
    -- Sestav body s template_slug — edge fn načte šablonu z DB sama
    v_body := p_payload || jsonb_build_object('template_slug', v_tpl.slug, 'event_slug', p_event_slug);

    BEGIN
      PERFORM net.http_post(
        url := v_url || '/functions/v1/send-booking-email',
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || v_key
        ),
        body := v_body
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'dispatch_email_event: pg_net failed for slug % event %: %',
        v_tpl.slug, p_event_slug, SQLERRM;
    END;
  END LOOP;
END;
$$;
GRANT EXECUTE ON FUNCTION dispatch_email_event(text, jsonb)
  TO anon, authenticated, service_role;


-- =============================================================================
-- 4) Update existujících email triggerů — přidat call dispatch_email_event
--    VEDLE stávajícího hardcoded volání. Pro každý trigger jen JEDEN nový řádek
--    `PERFORM dispatch_email_event(...)`. Stávající chování beze změny.
-- =============================================================================

-- ── trg_send_booking_completed_email ──────────────────────────────────────────
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
  v_booking_short text;
  v_promo_code text;
  v_payload jsonb;
BEGIN
  IF NEW.type != 'final' OR NEW.booking_id IS NULL THEN RETURN NEW; END IF;

  SELECT EXISTS(
    SELECT 1 FROM message_log
    WHERE booking_id = NEW.booking_id
      AND template_slug IN ('booking_completed', 'web_booking_completed')
      AND status = 'sent'
    LIMIT 1
  ) INTO v_already_sent;
  IF v_already_sent THEN RETURN NEW; END IF;

  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'trg_send_booking_completed_email: app_settings missing';
    RETURN NEW;
  END IF;

  SELECT * INTO v_booking FROM bookings WHERE id = NEW.booking_id;
  IF NOT FOUND OR v_booking.user_id IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_profile FROM profiles WHERE id = v_booking.user_id;
  IF NOT FOUND OR v_profile.email IS NULL OR v_profile.email = '' THEN RETURN NEW; END IF;

  SELECT model INTO v_moto_model FROM motorcycles WHERE id = v_booking.moto_id;
  v_source := COALESCE(v_booking.booking_source, 'app');

  SELECT value #>> '{}' INTO v_google_url   FROM app_settings WHERE key = 'google_review_url';
  SELECT value #>> '{}' INTO v_facebook_url FROM app_settings WHERE key = 'facebook_review_url';

  v_booking_short := UPPER(RIGHT(REPLACE(v_booking.id::text, '-', ''), 8));
  v_promo_code    := 'VRACENI-' || v_booking_short;
  IF NOT EXISTS (SELECT 1 FROM promo_codes WHERE code = v_promo_code) THEN
    v_promo_code := '';
  END IF;

  -- Sdílený payload pro hardcoded volání i dispatch_email_event
  v_payload := jsonb_build_object(
    'booking_id',           v_booking.id,
    'customer_email',       v_profile.email,
    'customer_name',        COALESCE(v_profile.full_name, ''),
    'motorcycle',           COALESCE(v_moto_model, ''),
    'start_date',           v_booking.start_date,
    'end_date',             v_booking.end_date,
    'total_price',          v_booking.total_price,
    'source',               v_source,
    'google_review_url',    COALESCE(v_google_url, ''),
    'facebook_review_url',  COALESCE(v_facebook_url, ''),
    'discount_code',        v_promo_code
  );

  -- HARDCODED legacy volání — beze změny chování
  PERFORM net.http_post(
    url     := v_url || '/functions/v1/send-booking-email',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                   'Authorization', 'Bearer ' || v_key),
    body    := v_payload || jsonb_build_object('type', 'booking_completed')
  );

  -- ⚠️ NOVÉ: dispatch custom šablon které admin přiřadil k těmto eventům
  PERFORM dispatch_email_event('kf_invoice_created', v_payload);
  PERFORM dispatch_email_event('booking_status_changed_to_completed', v_payload);
  PERFORM dispatch_email_event('auto_after_kf_created', v_payload);

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_send_booking_completed_email failed for invoice %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ── trg_send_booking_modified_email ───────────────────────────────────────────
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
  v_payload jsonb;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN RETURN NEW; END IF;
  IF NEW.status NOT IN ('reserved','active') THEN RETURN NEW; END IF;

  v_changed :=
       NEW.moto_id        IS DISTINCT FROM OLD.moto_id
    OR NEW.start_date     IS DISTINCT FROM OLD.start_date
    OR NEW.end_date       IS DISTINCT FROM OLD.end_date
    OR NEW.total_price    IS DISTINCT FROM OLD.total_price
    OR NEW.pickup_method  IS DISTINCT FROM OLD.pickup_method
    OR NEW.pickup_address IS DISTINCT FROM OLD.pickup_address
    OR NEW.pickup_time    IS DISTINCT FROM OLD.pickup_time
    OR NEW.return_method  IS DISTINCT FROM OLD.return_method
    OR NEW.return_address IS DISTINCT FROM OLD.return_address
    OR NEW.return_time    IS DISTINCT FROM OLD.return_time;
  IF NOT v_changed THEN RETURN NEW; END IF;

  SELECT EXISTS(
    SELECT 1 FROM message_log
     WHERE booking_id = NEW.id AND template_slug LIKE 'booking_modified%'
       AND status = 'sent' AND created_at > now() - interval '5 minutes' LIMIT 1
  ) INTO v_already_sent;
  IF v_already_sent THEN RETURN NEW; END IF;

  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN RETURN NEW; END IF;

  SELECT * INTO v_profile FROM profiles WHERE id = NEW.user_id;
  IF NOT FOUND OR v_profile.email IS NULL OR v_profile.email = '' THEN RETURN NEW; END IF;

  SELECT model INTO v_moto_old FROM motorcycles WHERE id = OLD.moto_id;
  SELECT model INTO v_moto_new FROM motorcycles WHERE id = NEW.moto_id;

  v_payload := jsonb_build_object(
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
    'pickup_time',             COALESCE(NEW.pickup_time, ''),
    'return_method',           COALESCE(NEW.return_method, ''),
    'return_address',          COALESCE(NEW.return_address, ''),
    'return_time',             COALESCE(NEW.return_time, ''),
    'original_motorcycle',     COALESCE(v_moto_old, ''),
    'original_start_date',     OLD.start_date,
    'original_end_date',       OLD.end_date,
    'original_total_price',    OLD.total_price,
    'original_pickup_method',  COALESCE(OLD.pickup_method, ''),
    'original_pickup_address', COALESCE(OLD.pickup_address, ''),
    'original_pickup_time',    COALESCE(OLD.pickup_time, ''),
    'original_return_method',  COALESCE(OLD.return_method, ''),
    'original_return_address', COALESCE(OLD.return_address, ''),
    'original_return_time',    COALESCE(OLD.return_time, '')
  );

  -- HARDCODED legacy volání — beze změny chování
  PERFORM net.http_post(
    url     := v_url || '/functions/v1/send-booking-email',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                   'Authorization', 'Bearer ' || v_key),
    body    := v_payload || jsonb_build_object('type', 'booking_modified')
  );

  -- ⚠️ NOVÉ: dispatch custom šablon
  PERFORM dispatch_email_event('booking_updated', v_payload);

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_send_booking_modified_email failed for booking %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;


-- ── trg_send_shop_order_confirmed_email ──────────────────────────────────────
CREATE OR REPLACE FUNCTION trg_send_shop_order_confirmed_email() RETURNS trigger AS $$
DECLARE
  v_url            text;
  v_key            text;
  v_already_sent   boolean;
  v_source         text;
  v_payload        jsonb;
BEGIN
  IF NEW.payment_status != 'paid' OR OLD.payment_status = 'paid' THEN RETURN NEW; END IF;
  IF NEW.customer_email IS NULL OR NEW.customer_email = '' THEN RETURN NEW; END IF;

  SELECT EXISTS(
    SELECT 1 FROM message_log
     WHERE template_slug IN ('shop_order_confirmed', 'web_shop_order_confirmed')
       AND recipient_email = NEW.customer_email
       AND content_preview LIKE '%' || NEW.order_number || '%'
       AND status = 'sent' LIMIT 1
  ) INTO v_already_sent;
  IF v_already_sent THEN RETURN NEW; END IF;

  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN RETURN NEW; END IF;

  v_source := CASE WHEN NEW.customer_id IS NULL THEN 'web' ELSE 'app' END;

  v_payload := jsonb_build_object(
    'order_id',       NEW.id,
    'order_number',   NEW.order_number,
    'customer_email', NEW.customer_email,
    'customer_name',  COALESCE(NEW.customer_name, ''),
    'total_price',    NEW.total,
    'shipping_cost',  NEW.shipping_cost,
    'source',         v_source
  );

  -- HARDCODED legacy volání — beze změny chování
  PERFORM net.http_post(
    url     := v_url || '/functions/v1/send-booking-email',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                   'Authorization', 'Bearer ' || v_key),
    body    := v_payload || jsonb_build_object('type', 'shop_order_confirmed')
  );

  -- ⚠️ NOVÉ: dispatch custom šablon
  PERFORM dispatch_email_event('stripe_payment_confirmed_shop', v_payload);
  PERFORM dispatch_email_event('shop_order_status_confirmed', v_payload);

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_send_shop_order_confirmed_email: pg_net failed for %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
