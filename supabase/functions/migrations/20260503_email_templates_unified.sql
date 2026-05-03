-- =============================================================================
-- MIGRACE 2026-05-03: Sjednocení e-mailových šablon + opravy doručování
--
-- Etapa 1/4 z refactoru email šablon. Řeší:
--   1.1) trg_send_booking_completed_email — fix čtení config z app_settings
--        (broken GUC pattern → KF email tiše selhával)
--   1.2) generate_final_invoice_on_complete — automatické vystavení slevového
--        kódu VRACENI-{booking_short} (200 Kč, 1 rok, max_uses=1)
--   1.3) KF assertion na 0 Kč — pokud rozdíl, log do debug_log (warning)
--   1.4) auto_cancel_expired_pending — posílá booking_cancelled email
--   1.5) cancel_booking_tracked — volá send-cancellation-email (refund + dobropis)
--   1.6) trg_send_shop_order_confirmed_email — auto email po Stripe e-shop platbě
--   1.7) email_templates.attachments jsonb — multi-select příloh per šablona
--   1.8) shop_order_created — deaktivace mrtvé šablony
-- =============================================================================

-- =============================================================================
-- 1.1 + 1.2 + 1.3: KF flow + slevový kód + assertion
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
  v_booking_short text;
  v_promo_code text;
BEGIN
  IF OLD.status != 'active' OR NEW.status != 'completed' THEN RETURN NEW; END IF;
  IF EXISTS (SELECT 1 FROM invoices WHERE booking_id = NEW.id AND type = 'final') THEN RETURN NEW; END IF;
  IF NEW.payment_status != 'paid' THEN RETURN NEW; END IF;
  IF NEW.sos_replacement = true THEN
    RAISE NOTICE 'Skipping KF for SOS replacement booking %', NEW.id;
    RETURN NEW;
  END IF;

  SELECT model, spz INTO v_moto_model, v_moto_spz FROM motorcycles WHERE id = NEW.moto_id;

  SELECT COALESCE(MAX(CAST(SUBSTRING(number FROM '-(\d+)$') AS int)), 0) + 1
    INTO v_seq FROM invoices WHERE number LIKE 'KF-' || v_year || '-%';
  v_inv_num := 'KF-' || v_year || '-' || LPAD(v_seq::text, 4, '0');

  v_extras   := COALESCE(NEW.extras_price, 0);
  v_delivery := COALESCE(NEW.delivery_fee, 0);
  v_discount := COALESCE(NEW.discount_amount, 0);
  v_discount_code := COALESCE(NEW.discount_code, '');
  v_base_rental := COALESCE(NEW.total_price, 0) - v_extras - v_delivery + v_discount;

  v_items := jsonb_build_array(jsonb_build_object(
    'description', 'Pronájem ' || COALESCE(v_moto_model, 'motorky') ||
      ' (' || COALESCE(v_moto_spz, '') || ') — ' ||
      TO_CHAR(NEW.start_date, 'DD.MM.YYYY') || ' – ' || TO_CHAR(NEW.end_date, 'DD.MM.YYYY'),
    'qty', 1, 'unit_price', v_base_rental
  ));

  IF v_extras > 0 THEN
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'description', 'Příslušenství a výbava', 'qty', 1, 'unit_price', v_extras));
  END IF;

  IF v_delivery > 0 THEN
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'description', 'Přistavení / odvoz motorky', 'qty', 1, 'unit_price', v_delivery));
  END IF;

  IF v_discount > 0 THEN
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'description', CASE WHEN v_discount_code <> '' THEN 'Sleva (kód: ' || v_discount_code || ')'
                          ELSE 'Sleva / voucher' END,
      'qty', 1, 'unit_price', -v_discount));
  END IF;

  v_items := v_items || COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'description', 'Odpočet dle DP ' || number, 'qty', 1, 'unit_price', -total))
    FROM invoices WHERE booking_id = NEW.id AND type = 'payment_receipt' AND status != 'cancelled'
  ), '[]'::jsonb);

  v_total := (SELECT SUM((item->>'unit_price')::numeric * (item->>'qty')::numeric)
              FROM jsonb_array_elements(v_items) AS item);

  -- BLOK 1.3: KF musí být MATEMATICKY vždy 0 Kč. Pokud ne, log warning pro účetní.
  IF ROUND(v_total::numeric, 2) <> 0 THEN
    INSERT INTO debug_log (source, action, component, status, error_message, request_data)
    VALUES (
      'generate_final_invoice_on_complete', 'kf_total_not_zero', 'KF assertion', 'warning',
      'KF total != 0 (booking: ' || NEW.id || ', total: ' || v_total || ' Kč) — chybí DP/dobropis pro plné pokrytí?',
      jsonb_build_object(
        'booking_id', NEW.id, 'kf_number', v_inv_num, 'computed_total', v_total,
        'base_rental', v_base_rental, 'extras', v_extras, 'delivery', v_delivery,
        'discount', v_discount, 'items', v_items,
        'sum_dp', (SELECT COALESCE(SUM(total),0) FROM invoices
                    WHERE booking_id=NEW.id AND type='payment_receipt' AND status!='cancelled')
      )
    );
    RAISE WARNING 'KF % pro booking % má total=% Kč (očekáváno 0). Zaloggováno do debug_log.',
      v_inv_num, NEW.id, v_total;
  END IF;

  -- BLOK 1.2: Slevový kód VRACENI-{booking_short} (200 Kč / 1 rok / 1× použití)
  v_booking_short := UPPER(RIGHT(REPLACE(NEW.id::text, '-', ''), 8));
  v_promo_code    := 'VRACENI-' || v_booking_short;

  INSERT INTO promo_codes (code, type, discount_value, is_active, valid_to, max_uses, used_count, description)
  VALUES (
    v_promo_code, 'fixed', 200, true,
    (CURRENT_DATE + INTERVAL '1 year')::timestamptz,
    1, 0,
    'Poděkování za rezervaci ' || v_booking_short || ' — 200 Kč na cokoliv'
  )
  ON CONFLICT (code) DO NOTHING;

  INSERT INTO invoices (
    number, type, customer_id, booking_id, items, subtotal, tax_amount, total,
    issue_date, due_date, status, variable_symbol, source
  )
  VALUES (
    v_inv_num, 'final', NEW.user_id, NEW.id, v_items, v_total, 0, v_total,
    CURRENT_DATE, CURRENT_DATE, 'paid', v_inv_num, 'final_summary'
  );

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'generate_final_invoice_on_complete failed for booking %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;


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

  -- BLOK 1.1: Čteme z app_settings tabulky (Supabase managed neumí ALTER DATABASE pro GUC)
  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'trg_send_booking_completed_email: app_settings(supabase_url|service_role_key) chybí';
    RETURN NEW;
  END IF;

  SELECT * INTO v_booking FROM bookings WHERE id = NEW.booking_id;
  IF NOT FOUND OR v_booking.user_id IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_profile FROM profiles WHERE id = v_booking.user_id;
  IF NOT FOUND OR v_profile.email IS NULL OR v_profile.email = '' THEN
    RAISE NOTICE 'trg_send_booking_completed_email: no email for user %', v_booking.user_id;
    RETURN NEW;
  END IF;

  SELECT model INTO v_moto_model FROM motorcycles WHERE id = v_booking.moto_id;
  v_source := COALESCE(v_booking.booking_source, 'app');

  SELECT value #>> '{}' INTO v_google_url   FROM app_settings WHERE key = 'google_review_url';
  SELECT value #>> '{}' INTO v_facebook_url FROM app_settings WHERE key = 'facebook_review_url';

  -- discount_code = nově vystavený VRACENI-* (vznikl v generate_final_invoice_on_complete)
  v_booking_short := UPPER(RIGHT(REPLACE(v_booking.id::text, '-', ''), 8));
  v_promo_code    := 'VRACENI-' || v_booking_short;
  IF NOT EXISTS (SELECT 1 FROM promo_codes WHERE code = v_promo_code) THEN
    v_promo_code := '';
    RAISE WARNING 'trg_send_booking_completed_email: promo_code chybí pro booking %', v_booking.id;
  END IF;

  PERFORM net.http_post(
    url     := v_url || '/functions/v1/send-booking-email',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_key
    ),
    body    := jsonb_build_object(
      'type',                 'booking_completed',
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
    )
  );

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_send_booking_completed_email failed for invoice %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- =============================================================================
-- 1.4: auto_cancel_expired_pending — pošle booking_cancelled email
-- =============================================================================

CREATE OR REPLACE FUNCTION auto_cancel_expired_pending() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_url text;
  v_key text;
  v_row record;
BEGIN
  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';

  FOR v_row IN
    WITH cancelled AS (
      UPDATE bookings SET
        status               = 'cancelled',
        cancellation_reason  = CASE
          WHEN booking_source = 'app'
            THEN 'Automaticky zrušeno — nezaplaceno do 10 minut'
          ELSE  'Automaticky zrušeno — nezaplaceno do 4 hodin'
        END,
        cancelled_at         = now(),
        cancelled_by_source  = 'auto'
      WHERE status = 'pending'
        AND payment_status = 'unpaid'
        AND (
          (booking_source = 'app' AND created_at < now() - interval '10 minutes')
          OR (booking_source = 'web' AND created_at < now() - interval '4 hours')
        )
      RETURNING id, user_id, moto_id, start_date, end_date,
                booking_source, cancellation_reason
    )
    SELECT c.id, c.user_id, c.moto_id, c.start_date, c.end_date,
           c.booking_source, c.cancellation_reason,
           p.email AS customer_email, p.full_name AS customer_name,
           m.model AS motorcycle_model
      FROM cancelled c
      LEFT JOIN profiles p     ON p.id = c.user_id
      LEFT JOIN motorcycles m  ON m.id = c.moto_id
  LOOP
    IF v_row.customer_email IS NULL OR v_row.customer_email = '' THEN CONTINUE; END IF;
    IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
      RAISE WARNING 'auto_cancel_expired_pending: app_settings missing — skipping mail for %', v_row.id;
      CONTINUE;
    END IF;

    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-cancellation-email',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_key
        ),
        body    := jsonb_build_object(
          'booking_id',           v_row.id,
          'customer_email',       v_row.customer_email,
          'customer_name',        COALESCE(v_row.customer_name, ''),
          'motorcycle',           COALESCE(v_row.motorcycle_model, ''),
          'start_date',           v_row.start_date,
          'end_date',             v_row.end_date,
          'cancellation_reason',  v_row.cancellation_reason,
          'cancelled_by_source',  'auto',
          'refund_amount',        0,
          'refund_percent',       0,
          'source',               COALESCE(v_row.booking_source, 'app')
        )
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'auto_cancel_expired_pending: mail call failed for %: %', v_row.id, SQLERRM;
    END;
  END LOOP;
END;
$$;


-- =============================================================================
-- 1.5: cancel_booking_tracked — volá send-cancellation-email (refund + dobropis)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.cancel_booking_tracked(
  p_booking_id uuid,
  p_reason     text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_booking      bookings%ROWTYPE;
  v_profile      profiles%ROWTYPE;
  v_moto_model   text;
  v_uid          uuid;
  v_hours_until  numeric;
  v_refund_pct   integer;
  v_refund_amt   numeric;
  v_was_paid     boolean;
  v_url          text;
  v_key          text;
BEGIN
  v_uid := auth.uid();

  SELECT * INTO v_booking FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Rezervace nenalezena');
  END IF;

  IF v_booking.user_id != v_uid AND NOT is_admin() THEN
    RETURN jsonb_build_object('error', 'Nemáte oprávnění');
  END IF;

  IF v_booking.status = 'cancelled' THEN
    RETURN jsonb_build_object('error', 'Rezervace je již stornována');
  END IF;

  v_was_paid    := (v_booking.payment_status = 'paid');
  v_hours_until := EXTRACT(EPOCH FROM (v_booking.start_date - now())) / 3600;
  IF v_hours_until > 7 * 24 THEN v_refund_pct := 100;
  ELSIF v_hours_until > 48     THEN v_refund_pct := 50;
  ELSE                              v_refund_pct := 0;
  END IF;
  v_refund_amt := ROUND(COALESCE(v_booking.total_price, 0) * v_refund_pct / 100);

  UPDATE bookings SET
    status               = 'cancelled',
    cancelled_at         = now(),
    cancelled_by         = v_uid,
    cancelled_by_source  = CASE WHEN v_uid = v_booking.user_id THEN 'customer' ELSE 'admin' END,
    cancellation_reason  = COALESCE(p_reason, 'Stornováno zákazníkem')
  WHERE id = p_booking_id;

  INSERT INTO booking_cancellations (booking_id, cancelled_by, reason, refund_amount, refund_percent)
  VALUES (p_booking_id, v_uid, p_reason, v_refund_amt, v_refund_pct);

  -- Pošle send-cancellation-email — ta sama zařídí Stripe refund + dobropis + mail
  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';

  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'cancel_booking_tracked: app_settings missing — refund/mail skipped';
  ELSE
    SELECT * INTO v_profile FROM profiles WHERE id = v_booking.user_id;
    SELECT model INTO v_moto_model FROM motorcycles WHERE id = v_booking.moto_id;

    IF v_profile.email IS NOT NULL AND v_profile.email <> '' THEN
      BEGIN
        PERFORM net.http_post(
          url     := v_url || '/functions/v1/send-cancellation-email',
          headers := jsonb_build_object(
            'Content-Type',  'application/json',
            'Authorization', 'Bearer ' || v_key
          ),
          body    := jsonb_build_object(
            'booking_id',           v_booking.id,
            'customer_email',       v_profile.email,
            'customer_name',        COALESCE(v_profile.full_name, ''),
            'motorcycle',           COALESCE(v_moto_model, ''),
            'start_date',           v_booking.start_date,
            'end_date',             v_booking.end_date,
            'cancellation_reason',  COALESCE(p_reason, 'Stornováno zákazníkem'),
            'cancelled_by_source',  CASE WHEN v_uid = v_booking.user_id THEN 'customer' ELSE 'admin' END,
            'refund_amount',        v_refund_amt,
            'refund_percent',       v_refund_pct,
            'source',               COALESCE(v_booking.booking_source, 'app')
          )
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'cancel_booking_tracked: mail call failed for %: %', v_booking.id, SQLERRM;
      END;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success',         true,
    'refund_percent',  v_refund_pct,
    'refund_amount',   v_refund_amt
  );
END;
$$;


-- =============================================================================
-- 1.6: trg_send_shop_order_confirmed_email — auto email po Stripe e-shop platbě
-- =============================================================================

CREATE OR REPLACE FUNCTION trg_send_shop_order_confirmed_email() RETURNS trigger AS $$
DECLARE
  v_url            text;
  v_key            text;
  v_already_sent   boolean;
  v_source         text;
BEGIN
  IF NEW.payment_status != 'paid' OR OLD.payment_status = 'paid' THEN
    RETURN NEW;
  END IF;
  IF NEW.customer_email IS NULL OR NEW.customer_email = '' THEN
    RETURN NEW;
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM message_log
     WHERE template_slug IN ('shop_order_confirmed', 'web_shop_order_confirmed')
       AND recipient_email = NEW.customer_email
       AND content_preview LIKE '%' || NEW.order_number || '%'
       AND status = 'sent'
     LIMIT 1
  ) INTO v_already_sent;
  IF v_already_sent THEN RETURN NEW; END IF;

  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'trg_send_shop_order_confirmed_email: app_settings missing';
    RETURN NEW;
  END IF;

  v_source := CASE WHEN NEW.customer_id IS NULL THEN 'web' ELSE 'app' END;

  BEGIN
    PERFORM net.http_post(
      url     := v_url || '/functions/v1/send-booking-email',
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'Authorization', 'Bearer ' || v_key
      ),
      body    := jsonb_build_object(
        'type',           'shop_order_confirmed',
        'order_id',       NEW.id,
        'order_number',   NEW.order_number,
        'customer_email', NEW.customer_email,
        'customer_name',  COALESCE(NEW.customer_name, ''),
        'total_price',    NEW.total,
        'shipping_cost',  NEW.shipping_cost,
        'source',         v_source
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'trg_send_shop_order_confirmed_email: pg_net failed for %: %', NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_shop_order_confirmed_email ON shop_orders;
CREATE TRIGGER trg_shop_order_confirmed_email
  AFTER UPDATE OF payment_status ON shop_orders
  FOR EACH ROW
  EXECUTE FUNCTION trg_send_shop_order_confirmed_email();


-- =============================================================================
-- 1.7: email_templates.attachments jsonb — multi-select příloh per šablona
-- =============================================================================

ALTER TABLE email_templates
  ADD COLUMN IF NOT EXISTS attachments jsonb NOT NULL DEFAULT '[]'::jsonb;

UPDATE email_templates SET attachments =
  CASE slug
    WHEN 'booking_reserved'      THEN '["ZF","DP","Smlouva","VOP"]'::jsonb
    WHEN 'web_booking_reserved'  THEN '["ZF","DP","Smlouva","VOP"]'::jsonb
    WHEN 'booking_modified'      THEN '["ZF","DP","Smlouva","VOP"]'::jsonb
    WHEN 'booking_completed'     THEN '["KF"]'::jsonb
    WHEN 'web_booking_completed' THEN '["KF"]'::jsonb
    WHEN 'booking_abandoned'     THEN '["ZF"]'::jsonb
    WHEN 'web_booking_abandoned' THEN '["ZF"]'::jsonb
    WHEN 'booking_cancelled'     THEN '["Dobropis"]'::jsonb
    WHEN 'web_booking_cancelled' THEN '["Dobropis"]'::jsonb
    WHEN 'voucher_purchased'     THEN '["ZF","DP","Voucher"]'::jsonb
    WHEN 'web_voucher_purchased' THEN '["ZF","DP","Voucher"]'::jsonb
    WHEN 'shop_order_confirmed'  THEN '["eshop_DP"]'::jsonb
    WHEN 'shop_order_shipped'    THEN '["eshop_KF"]'::jsonb
    WHEN 'invoice_advance'       THEN '["ZF"]'::jsonb
    WHEN 'invoice_final'         THEN '["KF"]'::jsonb
    WHEN 'invoice_payment_receipt' THEN '["DP"]'::jsonb
    WHEN 'invoice_shop_final'    THEN '["eshop_KF"]'::jsonb
    ELSE '[]'::jsonb
  END
WHERE slug IN (
  'booking_reserved','web_booking_reserved','booking_modified','booking_completed','web_booking_completed',
  'booking_abandoned','web_booking_abandoned','booking_cancelled','web_booking_cancelled',
  'voucher_purchased','web_voucher_purchased','shop_order_confirmed','shop_order_shipped',
  'invoice_advance','invoice_final','invoice_payment_receipt','invoice_shop_final'
);


-- =============================================================================
-- 1.8: shop_order_created — deaktivace mrtvé šablony
-- =============================================================================

UPDATE email_templates
   SET active = false,
       description = COALESCE(description, '') || E'\n[DEAKTIVOVÁNO 2026-05-03 — nikdy se neposílá, nahrazeno shop_order_confirmed po platbě]'
 WHERE slug = 'shop_order_created'
   AND active = true;
