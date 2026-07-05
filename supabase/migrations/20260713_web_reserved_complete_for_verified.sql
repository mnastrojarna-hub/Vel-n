-- =============================================================================
-- MIGRACE 2026-07-13: Web flow — přihlášený s doklady dostane KOMPLETNÍ reserved
-- =============================================================================
-- Fix (report z testu): přihlášený zákazník s ověřenými doklady dostal místo
-- kompletního `web_booking_reserved` (ZF+DP+VOP+smlouva+kódy) jen prázdnou
-- fakturační šablonu. Příčiny + opravy:
--  1) `web_booking_reserved` přílohy se v 20260710 ořezaly na [Smlouva,VOP] →
--     VRÁCENO na [ZF,DP,Smlouva,VOP] (kompletní jako dřív). Webhook nově rozhoduje:
--     doklady OK → booking_reserved (komplet), doklady chybí → invoice_payment_receipt (web_ šablona, ZF+DP).
--  2) Reserved cron gate rozšířen: reserved pošli když `docs_completed_at IS NOT NULL`
--     (nový zákazník dokončil čísla) NEBO `check_booking_docs_status IS NULL` (přihlášený
--     s ověřenými doklady) — jinak by přihlášenému reserved nikdy nedorazil (krok dokladů
--     přeskočil, docs_completed_at zůstalo NULL).
--  3) QR trigger posílá invoice_payment_receipt přes editovatelnou šablonu web_invoice_payment_receipt (ne prázdnou
--     `invoice_payment_receipt` (prázdné placeholdery).
-- POUZE WEB. APP beze změny.
-- =============================================================================

-- 1) web_booking_reserved přílohy zpět na KOMPLET (ZF+DP+Smlouva+VOP). base booking_reserved
--    zůstává jak byl (app). invoice_payment_receipt necháváme pro send-invoice-email (ruční).
DO $$
DECLARE v_type text;
BEGIN
  SELECT data_type INTO v_type FROM information_schema.columns
   WHERE table_schema='public' AND table_name='email_templates' AND column_name='attachments';
  IF v_type = 'ARRAY' THEN
    UPDATE public.email_templates SET attachments = ARRAY['ZF','DP','Smlouva','VOP']::text[] WHERE slug = 'web_booking_reserved';
  ELSE
    UPDATE public.email_templates SET attachments = '["ZF","DP","Smlouva","VOP"]'::jsonb WHERE slug = 'web_booking_reserved';
  END IF;
END $$;

-- 2) reserved cron: reserved když dokončený krok dokladů (docs_completed_at) NEBO doklady
--    už ověřené (check_booking_docs_status IS NULL). APP beze změny.
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
           b.booking_source, b.docs_completed_at,
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

    -- WEB: reserved až když dokončený krok dokladů (čísla) NEBO doklady už ověřené.
    IF COALESCE(v_row.booking_source, 'web') = 'web' AND v_row.docs_completed_at IS NULL THEN
      v_docs := NULL;
      BEGIN
        v_docs := check_booking_docs_status(v_row.user_id, v_row.end_date::date, v_row.moto_id);
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'send_missing_booking_reserved_emails: docs check failed for %: %', v_row.id, SQLERRM;
        CONTINUE;
      END;
      IF v_docs IS NOT NULL THEN CONTINUE; END IF;  -- ani nedokončené, ani ověřené → ještě ne
    END IF;

    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-booking-email',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
        body    := jsonb_build_object(
          'type','booking_reserved','source',COALESCE(v_row.booking_source,'web'),
          'booking_id',v_row.id,'customer_email',v_row.customer_email,
          'customer_name',COALESCE(v_row.customer_name,''),'motorcycle',COALESCE(v_row.motorcycle_model,''),
          'start_date',v_row.start_date,'end_date',v_row.end_date,'total_price',v_row.total_price,
          'manual_url',COALESCE(v_row.manual_url,''),'language',COALESCE(v_row.customer_language,'cs')
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

-- 3) QR trigger: po ručním potvrzení QR/převodu pošli invoice_payment_receipt (web_ šablona, ZF+DP),
--    ne fakturační invoice_payment_receipt (prázdné placeholdery).
CREATE OR REPLACE FUNCTION trg_send_qr_payment_receipt()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_url text; v_key text; v_email text; v_name text; v_model text; v_lang text;
BEGIN
  IF EXISTS (
    SELECT 1 FROM message_log ml
     WHERE ml.booking_id = NEW.id AND ml.channel = 'email'
       AND ml.template_slug IN ('invoice_payment_receipt','web_invoice_payment_receipt','booking_reserved','web_booking_reserved')
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

-- 4) Editovatelná Velín šablona pro potvrzení platby (ZF+DP) v novém flow.
--    send-booking-email posílá type='invoice_payment_receipt' source='web' →
--    resolveSlug preferuje `web_invoice_payment_receipt`. Přílohy [ZF,DP] řídí tento
--    sloupec. Placeholdery plní send-booking-email. Idempotentní (neuvádí ruční text zpět).
INSERT INTO email_templates (slug, name, subject, body_html, active, attachments)
VALUES (
  'web_invoice_payment_receipt',
  'Web — potvrzení platby (ZF + DP, nahrajte doklady)',
  'Platba přijata — rezervace #{{booking_number}}, nahrajte doklady — MotoGo24',
  '<p>Dobrý den,</p>' ||
  '<p>vaše platba za rezervaci č. <strong>#{{booking_number}}</strong> motocyklu <strong>{{motorcycle}}</strong> na <strong>{{start_date}} – {{end_date}}</strong> byla úspěšně přijata — děkujeme!</p>' ||
  '<p>V příloze najdete <strong>zálohovou fakturu</strong> a <strong>doklad o přijaté platbě</strong> (celkem {{total_price}}).</p>' ||
  '<p>Ještě jeden krok: nahrajte prosím doklady (občanku/pas + řidičák) — teprve pak vám pošleme <strong>nájemní smlouvu a přístupové kódy</strong> k motorce a výbavě.</p>' ||
  '<div style="text-align:center;margin:24px 0"><a href="{{docs_url}}" style="display:inline-block;background:#74FB71;color:#1a2e22;padding:14px 28px;border-radius:25px;text-decoration:none;font-weight:800;font-size:15px">Nahrát doklady</a></div>' ||
  '<p>Tým MotoGo24</p>',
  true,
  '["ZF","DP"]'::jsonb
)
ON CONFLICT (slug) DO NOTHING;

NOTIFY pgrst, 'reload schema';
