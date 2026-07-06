-- =============================================================================
-- MIGRACE 2026-07-06: Web platba — striktní rozlišení POVINNÝCH ČÍSEL vs. SCANU
-- =============================================================================
--
-- BUG (test 2026-07-06): Zákazník opustil web rezervaci v kroku 3 (QR platba),
--      pak zaplatil z QR mailu. Po potvrzení platby (Stripe webhook / QR ve
--      Velíně) dostal `web_booking_reserved` se SMLOUVOU + VOP, přestože
--      NEVYPLNIL povinná čísla dokladů ani skupinu ŘP (a nenahrál scan).
--      Nájemní smlouvu ale NELZE vygenerovat bez čísla OP/ŘP a skupiny —
--      měl dostat jen potvrzení platby (ZF + DP) + výzvu k doplnění.
--
-- NÁVRH (potvrzeno uživatelem):
--   • Povinná ČÍSLA (číslo OP/pasu + číslo ŘP + skupina ŘP) = podmínka SMLOUVY.
--     Vyplněná čísla → `web_booking_reserved` (ZF+DP+Smlouva+VOP). Chybí čísla →
--     `web_invoice_payment_receipt` (ZF+DP + výzva doplnit čísla + dobrovolný scan).
--   • SCAN (foto/OCR) = odemyká door codes, NENÍ podmínka smlouvy (na obslužné
--     pobočce nepovinný). Řeší kanonická check_booking_docs_status.
--   • Dvě připomínkové šablony podle stavu:
--       chybí ČÍSLA          → web_invoice_payment_receipt (výzva čísla + scan)
--       čísla OK, chybí SCAN → web_booking_missing_docs   (jen scan)
--
-- Tato migrace:
--   1) NEW check_booking_docs_state(booking_id) → {numbers_ok, scan_ok, scan_reason}
--      — jediný zdroj pravdy pro edge (payment-confirmers.ts) i crony.
--   2) send_abandoned_booking_emails() Path C — reminder větví podle numbers_ok.
--   3) send_missing_booking_reserved_emails() — smlouvu pošle JEN když numbers_ok
--      (jinak by catch-up vzkřísil kontrakt, protože po platbě bez čísel chybí
--      web_booking_reserved v message_log). Jakmile zákazník čísla doplní, cron
--      smlouvu automaticky došle.
-- =============================================================================

-- =============================================================================
-- 1) check_booking_docs_state — kombinovaný stav dokladů rezervace
-- =============================================================================
CREATE OR REPLACE FUNCTION public.check_booking_docs_state(p_booking_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user           uuid;
  v_end            timestamptz;
  v_moto           uuid;
  v_lic_required   text;
  v_id_number      text;
  v_license_number text;
  v_license_group  license_group[];
  v_scan_reason    text;
  v_numbers_ok     boolean;
BEGIN
  SELECT b.user_id, b.end_date, b.moto_id
    INTO v_user, v_end, v_moto
    FROM bookings b
   WHERE b.id = p_booking_id;

  IF v_user IS NULL THEN
    RETURN jsonb_build_object('error', 'not_found');
  END IF;

  SELECT COALESCE(m.license_required, 'A')
    INTO v_lic_required
    FROM motorcycles m
   WHERE m.id = v_moto;

  SELECT p.id_number, p.license_number, p.license_group
    INTO v_id_number, v_license_number, v_license_group
    FROM profiles p
   WHERE p.id = v_user;

  -- SCAN (foto/OCR): kanonická check_booking_docs_status (NULL = OK).
  -- Dětská motorka (license_required='N') → NULL automaticky.
  v_scan_reason := check_booking_docs_status(v_user, v_end::date, v_moto);

  -- POVINNÁ ČÍSLA do smlouvy: číslo OP/pasu + číslo ŘP + skupina ŘP.
  -- Dětská motorka nemá požadavek na doklad → numbers_ok = true.
  IF v_lic_required = 'N' THEN
    v_numbers_ok := true;
  ELSE
    v_numbers_ok := (
          COALESCE(v_id_number, '')      <> ''
      AND COALESCE(v_license_number, '') <> ''
      AND v_license_group IS NOT NULL
      AND array_length(v_license_group, 1) >= 1
    );
  END IF;

  RETURN jsonb_build_object(
    'numbers_ok',  v_numbers_ok,
    'scan_ok',     (v_scan_reason IS NULL),
    'scan_reason', v_scan_reason
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_booking_docs_state(uuid) TO anon, authenticated, service_role;

-- =============================================================================
-- 2) send_abandoned_booking_emails — Path C reminder podle stavu (čísla vs scan)
-- =============================================================================
CREATE OR REPLACE FUNCTION send_abandoned_booking_emails()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_url         text;
  v_key         text;
  v_row         record;
  v_sent_ab     int := 0;
  v_sent_docs   int := 0;
  v_pay_url     text;
  v_docs_url    text;
  v_docs_state  jsonb;
  v_numbers_ok  boolean;
  v_scan_ok     boolean;
  v_mail_type   text;
  v_site_url    text := 'https://www.motogo24.cz';
BEGIN
  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';

  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'send_abandoned_booking_emails: app_settings (supabase_url/service_role_key) missing — abort';
    RETURN jsonb_build_object('error', 'app_settings_missing');
  END IF;

  -- PATH AB: pending + unpaid (web) — 15 min od created_at, jediný mail
  FOR v_row IN
    SELECT b.id, b.user_id, b.moto_id, b.start_date, b.end_date, b.total_price,
           b.stripe_checkout_url, b.checkout_started_at, b.created_at,
           p.email AS customer_email, p.full_name AS customer_name,
           p.language AS customer_language,
           m.model AS motorcycle_model
      FROM bookings b
      LEFT JOIN profiles    p ON p.id = b.user_id
      LEFT JOIN motorcycles m ON m.id = b.moto_id
     WHERE b.booking_source        = 'web'
       AND b.status                = 'pending'
       AND b.payment_status        = 'unpaid'
       AND b.abandoned_email_sent_at IS NULL
       AND b.created_at < now() - interval '15 minutes'
  LOOP
    IF v_row.customer_email IS NULL OR v_row.customer_email = '' THEN CONTINUE; END IF;

    v_pay_url := COALESCE(
      NULLIF(v_row.stripe_checkout_url, ''),
      v_site_url || '/rezervace?resume=' || v_row.id::text
    );

    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-booking-email',
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || v_key
        ),
        body    := jsonb_build_object(
          'type',            'booking_abandoned',
          'source',          'web',
          'booking_id',      v_row.id,
          'customer_email',  v_row.customer_email,
          'customer_name',   COALESCE(v_row.customer_name, ''),
          'motorcycle',      COALESCE(v_row.motorcycle_model, ''),
          'start_date',      v_row.start_date,
          'end_date',        v_row.end_date,
          'total_price',     v_row.total_price,
          'pay_url',         v_pay_url,
          'resume_link',     v_pay_url,
          'language',        COALESCE(v_row.customer_language, 'cs')
        )
      );

      UPDATE bookings SET abandoned_email_sent_at = now() WHERE id = v_row.id;
      v_sent_ab := v_sent_ab + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'send_abandoned_booking_emails AB: mail call failed for %: %', v_row.id, SQLERRM;
    END;
  END LOOP;

  -- PATH C: paid + reserved/active + chybí doklady (5 min od confirmed_at)
  -- POUZE samoobslužné vyzvednutí na pobočce — obslužná pobočka i přistavení
  -- (delivery) ověří doklady osobně přes obsluhu, nahrání předem je dobrovolné.
  -- Reminder se VĚTVÍ podle stavu (viz check_booking_docs_state):
  --   chybí ČÍSLA          → invoice_payment_receipt (výzva doplnit čísla + scan)
  --   čísla OK, chybí SCAN → booking_missing_docs   (jen scan)
  -- Docs-check je izolovaný v BEGIN/EXCEPTION — jeho chyba nikdy nesmí
  -- rollbacknout transakci a tím zabít Path AB (viz bug 2026-05-26).
  FOR v_row IN
    SELECT b.id, b.user_id, b.moto_id, b.start_date, b.end_date, b.confirmed_at,
           p.email AS customer_email, p.full_name AS customer_name,
           p.language AS customer_language,
           m.model AS motorcycle_model
      FROM bookings b
      LEFT JOIN profiles    p  ON p.id  = b.user_id
      LEFT JOIN motorcycles m  ON m.id  = b.moto_id
      LEFT JOIN branches    br ON br.id = m.branch_id
     WHERE b.booking_source             = 'web'
       AND b.status                     IN ('reserved','active')
       AND b.payment_status             = 'paid'
       AND b.docs_reminder_sent_at      IS NULL
       AND b.confirmed_at < now() - interval '5 minutes'
       AND COALESCE(br.type, '')         <> 'obslužná'
       AND COALESCE(b.pickup_method, '') <> 'delivery'
  LOOP
    IF v_row.customer_email IS NULL OR v_row.customer_email = '' THEN CONTINUE; END IF;

    v_docs_state := NULL;
    BEGIN
      v_docs_state := check_booking_docs_state(v_row.id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'send_abandoned_booking_emails C: docs state failed for %: %', v_row.id, SQLERRM;
      CONTINUE;
    END;

    v_numbers_ok := COALESCE((v_docs_state ->> 'numbers_ok')::boolean, true);
    v_scan_ok    := COALESCE((v_docs_state ->> 'scan_ok')::boolean, true);

    -- Obě strany OK (vč. dětské motorky) → žádná připomínka
    IF v_numbers_ok AND v_scan_ok THEN CONTINUE; END IF;

    v_docs_url := v_site_url || '/upravit-rezervaci?id=' || v_row.id::text || '#doklady';

    -- Chybí povinná čísla → výzva doplnit čísla + scan (ZF+DP z platby už přišly).
    -- Jinak (čísla OK, chybí jen scan) → připomínka jen na scan.
    IF NOT v_numbers_ok THEN
      v_mail_type := 'invoice_payment_receipt';
    ELSE
      v_mail_type := 'booking_missing_docs';
    END IF;

    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-booking-email',
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || v_key
        ),
        body    := jsonb_build_object(
          'type',            v_mail_type,
          'source',          'web',
          'booking_id',      v_row.id,
          'customer_email',  v_row.customer_email,
          'customer_name',   COALESCE(v_row.customer_name, ''),
          'motorcycle',      COALESCE(v_row.motorcycle_model, ''),
          'start_date',      v_row.start_date,
          'end_date',        v_row.end_date,
          'docs_url',        v_docs_url,
          'language',        COALESCE(v_row.customer_language, 'cs')
        )
      );

      UPDATE bookings SET docs_reminder_sent_at = now() WHERE id = v_row.id;
      v_sent_docs := v_sent_docs + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'send_abandoned_booking_emails C: mail call failed for %: %', v_row.id, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'sent_abandoned',    v_sent_ab,
    'sent_missing_docs', v_sent_docs
  );
END;
$$;

-- =============================================================================
-- 3) send_missing_booking_reserved_emails — smlouvu jen když numbers_ok
-- =============================================================================
CREATE OR REPLACE FUNCTION send_missing_booking_reserved_emails()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_url         text;
  v_key         text;
  v_row         record;
  v_sent        int := 0;
  v_numbers_ok  boolean;
BEGIN
  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';

  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'send_missing_booking_reserved_emails: app_settings (supabase_url/service_role_key) missing — abort';
    RETURN jsonb_build_object('error', 'app_settings_missing');
  END IF;

  FOR v_row IN
    SELECT b.id, b.user_id, b.moto_id, b.start_date, b.end_date, b.total_price,
           b.booking_source,
           p.email AS customer_email, p.full_name AS customer_name,
           p.language AS customer_language,
           m.model AS motorcycle_model, m.manual_url AS manual_url
      FROM bookings b
      LEFT JOIN profiles    p ON p.id = b.user_id
      LEFT JOIN motorcycles m ON m.id = b.moto_id
     WHERE b.status                 IN ('reserved','active')
       AND b.payment_status         = 'paid'
       AND b.confirmed_at IS NOT NULL
       AND b.confirmed_at           < now() - interval '3 minutes'  -- realtime cestě dej přednost
       AND b.reserved_email_sent_at IS NULL                         -- cron už to nezkoušel
       AND NOT EXISTS (                                             -- realtime mail nedorazil
         SELECT 1 FROM message_log ml
          WHERE ml.booking_id    = b.id
            AND ml.channel       = 'email'
            AND ml.template_slug IN ('web_booking_reserved','booking_reserved')
       )
  LOOP
    IF v_row.customer_email IS NULL OR v_row.customer_email = '' THEN CONTINUE; END IF;

    -- Smlouvu (booking_reserved: ZF+DP+Smlouva+VOP) pošli JEN když jsou vyplněná
    -- povinná čísla dokladů. Dokud chybí, kontrakt negenerujeme (po platbě dorazil
    -- invoice_payment_receipt). Jakmile zákazník čísla doplní, cron ho automaticky
    -- došle. Marker reserved_email_sent_at ZÁMĚRNĚ nesetujeme, když čísla chybí,
    -- aby rezervace zůstala v hledáčku pro pozdější došlání smlouvy.
    BEGIN
      v_numbers_ok := COALESCE((check_booking_docs_state(v_row.id) ->> 'numbers_ok')::boolean, true);
    EXCEPTION WHEN OTHERS THEN
      v_numbers_ok := true;  -- při chybě zachovej původní chování (smlouvu pošli)
    END;
    IF NOT v_numbers_ok THEN CONTINUE; END IF;

    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-booking-email',
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || v_key
        ),
        body    := jsonb_build_object(
          'type',           'booking_reserved',
          'source',         COALESCE(v_row.booking_source, 'web'),
          'booking_id',     v_row.id,
          'customer_email', v_row.customer_email,
          'customer_name',  COALESCE(v_row.customer_name, ''),
          'motorcycle',     COALESCE(v_row.motorcycle_model, ''),
          'start_date',     v_row.start_date,
          'end_date',       v_row.end_date,
          'total_price',    v_row.total_price,
          'manual_url',     COALESCE(v_row.manual_url, ''),
          'language',       COALESCE(v_row.customer_language, 'cs')
        )
      );

      UPDATE bookings SET reserved_email_sent_at = now() WHERE id = v_row.id;
      v_sent := v_sent + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'send_missing_booking_reserved_emails: mail call failed for %: %', v_row.id, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object('sent_reserved', v_sent);
END;
$$;

-- =============================================================================
-- 4) Šablona web_invoice_payment_receipt — ujisti se, že je aktivní a má ZF+DP.
--    (Tělo/předmět edituje admin ve Velíně — viz screen. Zde jen pojistka stavu.)
-- =============================================================================
UPDATE email_templates
   SET active      = true,
       attachments = '["ZF","DP"]'::jsonb
 WHERE slug = 'web_invoice_payment_receipt';
