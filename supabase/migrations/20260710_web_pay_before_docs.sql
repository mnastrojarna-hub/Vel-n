-- =============================================================================
-- MIGRACE 2026-07-10: Web rezervace — platba PŘED doklady (Část 1b: DB backbone)
-- POUZE WEB (booking_source='web'). APP rezervace se NIJAK nemění.
-- =============================================================================
-- Souvisí s edge změnou (payment-confirmers.ts, send-booking-email/index.ts).
-- Logika mailů:
--   Stripe paid  → invoice_payment_receipt (ZF+DP)         [edge webhook]
--   QR potvrzeno → invoice_payment_receipt (ZF+DP)         [trigger níže]
--   paid + doklady OK → web_booking_reserved (Smlouva+VOP+kódy) [reserved cron + guard]
--   paid + chybí doklady (30 min) → booking_missing_docs (odkaz na poslední krok flow)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) Evidence pro Velín funnel/detail
-- ---------------------------------------------------------------------------
ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS docs_completed_at     timestamptz,   -- kdy zákazník dokončil doklady (po platbě)
  ADD COLUMN IF NOT EXISTS docs_fill_seconds     integer,       -- doba platba → doklady
  ADD COLUMN IF NOT EXISTS chosen_payment_method text;          -- 'card' | 'qr' (volba na kroku 2, i u nezaplacených)

-- ---------------------------------------------------------------------------
-- 2) Přílohy mailů (email_templates.attachments je string[] / jsonb pole tokenů)
--    web_booking_reserved: jen Smlouva + VOP (ZF/DP už přišly v invoice_payment_receipt)
--    invoice_payment_receipt: ZF + DP (čte JEN send-booking-email; ruční fakturace ignoruje)
--    booking_reserved (base) ZŮSTÁVÁ ZF,DP,Smlouva,VOP — používá ji APP, neměnit!
--    POZOR: je-li sloupec text[] místo jsonb, použij ARRAY['Smlouva','VOP'] resp. ARRAY['ZF','DP'].
-- ---------------------------------------------------------------------------
DO $$
DECLARE v_type text;
BEGIN
  SELECT data_type INTO v_type FROM information_schema.columns
   WHERE table_schema='public' AND table_name='email_templates' AND column_name='attachments';
  IF v_type = 'ARRAY' THEN
    UPDATE public.email_templates SET attachments = ARRAY['Smlouva','VOP']::text[] WHERE slug = 'web_booking_reserved';
    UPDATE public.email_templates SET attachments = ARRAY['ZF','DP']::text[]        WHERE slug = 'invoice_payment_receipt';
  ELSE  -- jsonb
    UPDATE public.email_templates SET attachments = '["Smlouva","VOP"]'::jsonb WHERE slug = 'web_booking_reserved';
    UPDATE public.email_templates SET attachments = '["ZF","DP"]'::jsonb        WHERE slug = 'invoice_payment_receipt';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 3) reserved cron: web_booking_reserved (Smlouva+VOP+kódy) až po dokladech
--    Přidán guard: pro WEB posílej reserved JEN když check_booking_docs_status IS NULL
--    (= ověřená fotka/OCR). APP zůstává beze změny. Nastaví i docs_completed_at.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION send_missing_booking_reserved_emails()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_url   text;
  v_key   text;
  v_row   record;
  v_docs  text;
  v_sent  int := 0;
BEGIN
  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';

  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'send_missing_booking_reserved_emails: app_settings missing — abort';
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
       AND b.confirmed_at           < now() - interval '3 minutes'
       AND b.reserved_email_sent_at IS NULL
       AND NOT EXISTS (
         SELECT 1 FROM message_log ml
          WHERE ml.booking_id    = b.id
            AND ml.channel       = 'email'
            AND ml.template_slug IN ('web_booking_reserved','booking_reserved')
       )
  LOOP
    IF v_row.customer_email IS NULL OR v_row.customer_email = '' THEN CONTINUE; END IF;

    -- NOVÝ FLOW: WEB rezervace pošle reserved (Smlouva+VOP+kódy) AŽ když jsou doklady OK.
    -- APP beze změny (reserved = vše najednou hned po platbě).
    IF COALESCE(v_row.booking_source, 'web') = 'web' THEN
      v_docs := NULL;
      BEGIN
        v_docs := check_booking_docs_status(v_row.user_id, v_row.end_date::date, v_row.moto_id);
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'send_missing_booking_reserved_emails: docs check failed for %: %', v_row.id, SQLERRM;
        CONTINUE;
      END;
      IF v_docs IS NOT NULL THEN CONTINUE; END IF;   -- doklady chybí → reserved ještě ne
    END IF;

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

      UPDATE bookings
         SET reserved_email_sent_at = now(),
             docs_completed_at      = CASE WHEN COALESCE(booking_source,'web')='web'
                                           THEN COALESCE(docs_completed_at, now())
                                           ELSE docs_completed_at END
       WHERE id = v_row.id;
      v_sent := v_sent + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'send_missing_booking_reserved_emails: mail call failed for %: %', v_row.id, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object('sent_reserved', v_sent);
END;
$$;

-- ---------------------------------------------------------------------------
-- 4) abandoned cron Path C (booking_missing_docs): práh 5 → 30 min + odkaz na
--    POSLEDNÍ KROK rezervace (/rezervace?resume=<id>) místo /upravit-rezervaci.
--    Path AB (15 min abandoned) beze změny.
-- ---------------------------------------------------------------------------
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
  v_docs_reason text;
  v_site_url    text := 'https://www.motogo24.cz';
BEGIN
  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';

  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'send_abandoned_booking_emails: app_settings missing — abort';
    RETURN jsonb_build_object('error', 'app_settings_missing');
  END IF;

  -- PATH AB: pending + unpaid (web) — 15 min od created_at (BEZE ZMĚNY)
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
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
        body    := jsonb_build_object(
          'type','booking_abandoned','source','web','booking_id',v_row.id,
          'customer_email',v_row.customer_email,'customer_name',COALESCE(v_row.customer_name,''),
          'motorcycle',COALESCE(v_row.motorcycle_model,''),'start_date',v_row.start_date,
          'end_date',v_row.end_date,'total_price',v_row.total_price,
          'pay_url',v_pay_url,'resume_link',v_pay_url,'language',COALESCE(v_row.customer_language,'cs')
        )
      );
      UPDATE bookings SET abandoned_email_sent_at = now() WHERE id = v_row.id;
      v_sent_ab := v_sent_ab + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'send_abandoned_booking_emails AB: mail call failed for %: %', v_row.id, SQLERRM;
    END;
  END LOOP;

  -- PATH C: paid + reserved/active + chybí doklady — NOVĚ 30 min od confirmed_at,
  -- odkaz na poslední krok flow. Jen samoobslužné vyzvednutí (obslužná/delivery skip).
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
       AND b.confirmed_at < now() - interval '30 minutes'          -- 5 → 30 min
       AND COALESCE(br.type, '')         <> 'obslužná'
       AND COALESCE(b.pickup_method, '') <> 'delivery'
  LOOP
    IF v_row.customer_email IS NULL OR v_row.customer_email = '' THEN CONTINUE; END IF;

    v_docs_reason := NULL;
    BEGIN
      v_docs_reason := check_booking_docs_status(v_row.user_id, v_row.end_date::date, v_row.moto_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'send_abandoned_booking_emails C: docs check failed for %: %', v_row.id, SQLERRM;
      CONTINUE;
    END;

    IF v_docs_reason IS NULL THEN CONTINUE; END IF;   -- doklady OK → reserved to řeší, žádná připomínka

    -- NOVĚ: odkaz na poslední krok rezervačního flow (krok dokladů po platbě)
    v_docs_url := v_site_url || '/rezervace?resume=' || v_row.id::text;

    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-booking-email',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
        body    := jsonb_build_object(
          'type','booking_missing_docs','source','web','booking_id',v_row.id,
          'customer_email',v_row.customer_email,'customer_name',COALESCE(v_row.customer_name,''),
          'motorcycle',COALESCE(v_row.motorcycle_model,''),'start_date',v_row.start_date,
          'end_date',v_row.end_date,'docs_url',v_docs_url,'language',COALESCE(v_row.customer_language,'cs')
        )
      );
      UPDATE bookings SET docs_reminder_sent_at = now() WHERE id = v_row.id;
      v_sent_docs := v_sent_docs + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'send_abandoned_booking_emails C: mail call failed for %: %', v_row.id, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object('sent_abandoned', v_sent_ab, 'sent_missing_docs', v_sent_docs);
END;
$$;

-- ---------------------------------------------------------------------------
-- 5) QR/převod: po ručním potvrzení platby ve Velíně (confirm_payment, pay_channel='qr')
--    pošli invoice_payment_receipt (ZF+DP). Stripe jde přes webhook, QR přes tento trigger.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_send_qr_payment_receipt()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_url text; v_key text; v_email text; v_name text; v_model text; v_lang text;
BEGIN
  -- Dedup: kdyby už DP mail byl (message_log), znovu neposílej
  IF EXISTS (
    SELECT 1 FROM message_log ml
     WHERE ml.booking_id = NEW.id AND ml.channel = 'email'
       AND ml.template_slug IN ('invoice_payment_receipt','web_invoice_payment_receipt')
  ) THEN
    RETURN NEW;
  END IF;

  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
  IF v_url IS NULL OR v_key IS NULL THEN RETURN NEW; END IF;

  SELECT p.email, p.full_name, p.language, m.model
    INTO v_email, v_name, v_lang, v_model
    FROM profiles p LEFT JOIN motorcycles m ON m.id = NEW.moto_id
   WHERE p.id = NEW.user_id;
  IF v_email IS NULL OR v_email = '' THEN RETURN NEW; END IF;

  BEGIN
    PERFORM net.http_post(
      url     := v_url || '/functions/v1/send-booking-email',
      headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
      body    := jsonb_build_object(
        'type','invoice_payment_receipt','source','web','booking_id',NEW.id,
        'customer_email',v_email,'customer_name',COALESCE(v_name,''),
        'motorcycle',COALESCE(v_model,''),'start_date',NEW.start_date,'end_date',NEW.end_date,
        'total_price',NEW.total_price,'language',COALESCE(v_lang,'cs')
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'trg_send_qr_payment_receipt: %', SQLERRM;
  END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_qr_payment_receipt ON public.bookings;
CREATE TRIGGER trg_qr_payment_receipt
  AFTER UPDATE OF payment_status ON public.bookings
  FOR EACH ROW
  WHEN (NEW.payment_status = 'paid'
        AND NEW.pay_channel = 'qr'
        AND NEW.booking_source = 'web'
        AND OLD.payment_status IS DISTINCT FROM NEW.payment_status)
  EXECUTE FUNCTION trg_send_qr_payment_receipt();
