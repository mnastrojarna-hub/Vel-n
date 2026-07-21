-- 2026-07-27: DOPLATEK ZA ÚPRAVU REZERVACE VE VELÍNĚ — QR výzva k platbě + odklad
-- „booking_modified" mailu až po potvrzení doplatku.
--
-- Dosud: admin ve Velíně upravil ZAPLACENOU rezervaci s doplatkem („Zákazník
-- doplatí") → trigger trg_booking_modified_email poslal OKAMŽITĚ mail
-- booking_modified / web_booking_modified, jehož součástí je i rozdílový DP
-- (doklad o PŘIJATÉ platbě, source='edit') — přestože zákazník nic nezaplatil
-- a žádná výzva k platbě mu nepřišla.
--
-- Nově: úprava se ZAPLACENOU původní částí + doplatek →
--   1) Velín uloží úpravu a v TÉMŽE UPDATE nastaví `mod_surcharge_due` (dlužný
--      doplatek). Trigger úpravu detekuje, mail NEODEŠLE — payload si odloží do
--      `mod_email_payload` a skončí (deferred).
--   2) Velín zavolá edge fn `qr-payment` v režimu surcharge → RPC
--      `set_booking_mod_surcharge` přidělí číselný VS (booking_vs_seq) a
--      zákazníkovi odejde mail ze šablony `booking_qr_payment` (QR + účet + VS
--      na částku doplatku) + upozornění na info@.
--   3) Po připsání admin v detailu rezervace klikne „Potvrdit doplatek"
--      (PaymentConfirmModal v režimu doplatku) → RPC `confirm_booking_surcharge`
--      označí doplatek jako zaplacený a TEPRVE TEĎ odešle odložený
--      booking_modified mail (send-booking-email si k němu vygeneruje rozdílový
--      DP source='edit' + aktualizovanou smlouvu/VOP) + in-app zprávu.
--
-- NEZASAHUJE do: web self-edit (apply_booking_changes — mod_surcharge_due nikdy
-- nenastaví → mail chodí hned jako dosud), úpravy bez doplatku, úpravy „Zdarma",
-- vratky (refund flow beze změny), potvrzení celé nezaplacené rezervace
-- (confirm_payment beze změny).

-- 1) Sloupce pro evidenci dlužného doplatku za úpravu.
ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS mod_surcharge_due          numeric,     -- dlužný doplatek (NULL/0 = nic)
  ADD COLUMN IF NOT EXISTS mod_surcharge_vs           text,        -- číselný VS pro platbu doplatku
  ADD COLUMN IF NOT EXISTS mod_surcharge_requested_at timestamptz, -- kdy admin doplatek vyžádal
  ADD COLUMN IF NOT EXISTS mod_surcharge_paid_at      timestamptz, -- kdy admin doplatek potvrdil
  ADD COLUMN IF NOT EXISTS mod_email_payload          jsonb;       -- odložený payload booking_modified mailu

-- 1b) E-mailová šablona pro doplatek — sestra `booking_qr_payment` (stejný vzhled
--     a placeholdery), ale text sedí na doplatek ZAPLACENÉ rezervace: bez 4h
--     splatnosti / auto-zrušení a bez zmínky o ZF v příloze (ZF se u úprav
--     neposílá — pravidlo 2026-06-11; rozdílový DP přijde až po potvrzení).
--     Editovatelná ve Velíně (Dokumenty → E-mailové šablony). Idempotentní.
INSERT INTO email_templates (slug, name, subject, body_html, active, attachments)
VALUES (
  'booking_qr_payment_surcharge',
  'Platba QR / převod — doplatek za úpravu rezervace',
  'Doplatek k rezervaci #{{booking_number}} — QR / bankovní převod',
  '<h2 style="margin:0 0 6px;font-size:20px;color:#0f1a14">Doplatek za úpravu rezervace — QR / bankovní převod</h2>' ||
  '<p style="margin:0 0 16px;color:#374151;font-size:14px">{{lead}} <strong>#{{booking_number}}</strong> se váže doplatek. Uhraďte ho prosím bankovním převodem nebo naskenováním QR kódu v mobilní bankovní aplikaci.</p>' ||
  '<div style="text-align:center;margin:0 0 16px"><img src="{{qr_url}}" alt="QR Platba" style="width:240px;height:240px;border:1px solid #e5e7eb;border-radius:12px"></div>' ||
  '<table style="width:100%;border-collapse:collapse;margin:0 0 14px">' ||
  '<tr><td style="padding:8px 0;color:#16a34a;font-weight:600;font-size:13px">Částka</td><td style="padding:8px 0;text-align:right;color:#0f1a14;font-weight:700;font-size:18px;font-variant-numeric:tabular-nums">{{amount}}</td></tr>' ||
  '<tr><td style="padding:8px 0;color:#16a34a;font-weight:600;font-size:13px">Číslo účtu</td><td style="padding:8px 0;text-align:right;color:#0f1a14;font-weight:700;font-size:14px;font-variant-numeric:tabular-nums">{{account}}</td></tr>' ||
  '<tr><td style="padding:8px 0;color:#16a34a;font-weight:600;font-size:13px">IBAN</td><td style="padding:8px 0;text-align:right;color:#0f1a14;font-weight:700;font-size:14px;font-variant-numeric:tabular-nums">{{iban}}</td></tr>' ||
  '<tr><td style="padding:8px 0;color:#16a34a;font-weight:600;font-size:13px">Banka</td><td style="padding:8px 0;text-align:right;color:#0f1a14;font-weight:700;font-size:14px;font-variant-numeric:tabular-nums">{{bank}}</td></tr>' ||
  '<tr><td style="padding:8px 0;color:#16a34a;font-weight:600;font-size:13px">Variabilní symbol</td><td style="padding:8px 0;text-align:right;color:#0f1a14;font-weight:700;font-size:14px;font-variant-numeric:tabular-nums">{{vs}}</td></tr>' ||
  '</table>' ||
  '<p style="margin:0;color:#374151;font-size:13px">Po připsání platby vám úpravu rezervace potvrdíme e-mailem spolu s dokladem o platbě a aktualizovanou smlouvou.{{invoice_suffix}}</p>',
  true,
  '[]'::jsonb
)
ON CONFLICT (slug) DO NOTHING;

-- 2) RPC: přidělení VS pro doplatek (volá edge fn qr-payment v režimu surcharge).
--    Idempotentní — opakované volání nepřepíše existující VS. Sekvence je sdílená
--    s QR platbami rezervací (booking_vs_seq) → VS je unikátní napříč platbami.
CREATE OR REPLACE FUNCTION set_booking_mod_surcharge(p_booking_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_b  bookings%ROWTYPE;
  v_vs text;
BEGIN
  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  IF COALESCE(v_b.mod_surcharge_due, 0) <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'no_surcharge_pending');
  END IF;

  IF v_b.mod_surcharge_vs IS NULL THEN           -- VS přidělit jen jednou
    v_vs := nextval('booking_vs_seq')::text;
    UPDATE bookings SET mod_surcharge_vs = v_vs, updated_at = now()
     WHERE id = p_booking_id;
  ELSE
    v_vs := v_b.mod_surcharge_vs;
  END IF;

  RETURN jsonb_build_object(
    'success',    true,
    'booking_id', p_booking_id,
    'vs',         v_vs,
    'amount',     v_b.mod_surcharge_due
  );
END;
$$;

GRANT EXECUTE ON FUNCTION set_booking_mod_surcharge(uuid) TO authenticated, service_role;

-- 3) RPC: potvrzení doplatku adminem (Velín → detail rezervace → „Potvrdit doplatek").
--    Označí doplatek jako zaplacený a odešle ODLOŽENÝ booking_modified mail
--    (payload uložený triggerem; fallback ho poskládá z aktuálního řádku) +
--    dispatch custom šablon + in-app zprávu (appka Zprávy + FCM push přes
--    trg_push_on_admin_message). Selhání mailu/zprávy NIKDY nerollbackne potvrzení
--    (izolované BEGIN/EXCEPTION — stejný vzor jako trg_send_booking_modified_email).
CREATE OR REPLACE FUNCTION confirm_booking_surcharge(
  p_booking_id      uuid,
  p_method          text DEFAULT 'bank_transfer',
  p_vs              text DEFAULT NULL,
  p_paid_date       date DEFAULT NULL,
  p_transaction_ref text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_b       bookings%ROWTYPE;
  v_due     numeric;
  v_url     text;
  v_key     text;
  v_payload jsonb;
  v_profile profiles%ROWTYPE;
  v_moto    text;
  v_app_msg text;
BEGIN
  IF NOT is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
  END IF;

  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  v_due := COALESCE(v_b.mod_surcharge_due, 0);
  IF v_due <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'no_surcharge_pending');
  END IF;

  -- Potvrzení: vynulovat dluh, zapsat čas platby, payload vyčistit až PO odeslání.
  -- (Tento UPDATE nemění žádné pole sledované trg_booking_modified_email →
  -- trigger se neodpálí znovu.)
  UPDATE bookings
     SET mod_surcharge_due     = NULL,
         mod_surcharge_paid_at = COALESCE(p_paid_date::timestamptz, now()),
         payment_reference     = COALESCE(p_transaction_ref, payment_reference),
         updated_at            = now()
   WHERE id = p_booking_id;

  -- Odložený payload; fallback z aktuálního řádku (kdyby trigger payload neuložil).
  v_payload := v_b.mod_email_payload;
  IF v_payload IS NULL THEN
    SELECT * INTO v_profile FROM profiles WHERE id = v_b.user_id;
    SELECT model INTO v_moto FROM motorcycles WHERE id = v_b.moto_id;
    v_payload := jsonb_build_object(
      'booking_id',           v_b.id,
      'customer_email',       COALESCE(v_profile.email, ''),
      'customer_name',        COALESCE(v_profile.full_name, ''),
      'source',               COALESCE(v_b.booking_source, 'app'),
      'motorcycle',           COALESCE(v_moto, ''),
      'start_date',           v_b.start_date,
      'end_date',             v_b.end_date,
      'total_price',          v_b.total_price,
      'original_total_price', COALESCE(v_b.total_price, 0) - v_due
    );
  END IF;
  -- price_difference = skutečně zaplacený doplatek (rozdílový DP se vystaví na něj).
  v_payload := v_payload || jsonb_build_object('price_difference', v_due);

  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';

  -- KROK 1: odložený booking_modified mail (izolovaně).
  IF v_url IS NOT NULL AND v_url <> '' AND v_key IS NOT NULL AND v_key <> ''
     AND COALESCE(v_payload->>'customer_email', '') <> '' THEN
    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-booking-email',
        headers := jsonb_build_object('Content-Type', 'application/json',
                                      'Authorization', 'Bearer ' || v_key),
        body    := v_payload || jsonb_build_object('type', 'booking_modified')
      );
      INSERT INTO debug_log(source, action, status, request_data)
      VALUES ('confirm_booking_surcharge', 'deferred_modified_mail_queued', 'info',
              jsonb_build_object('booking_id', p_booking_id, 'amount', v_due));
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO debug_log(source, action, status, error_message, request_data)
      VALUES ('confirm_booking_surcharge', 'deferred_modified_mail_failed', 'error', SQLERRM,
              jsonb_build_object('booking_id', p_booking_id));
    END;
  ELSE
    INSERT INTO debug_log(source, action, status, request_data)
    VALUES ('confirm_booking_surcharge', 'deferred_mail_skipped_missing_cfg', 'info',
            jsonb_build_object('booking_id', p_booking_id,
                               'has_url', v_url IS NOT NULL, 'has_key', v_key IS NOT NULL,
                               'has_email', COALESCE(v_payload->>'customer_email', '') <> ''));
  END IF;

  -- KROK 2: dispatch custom šablon (izolovaně).
  BEGIN
    PERFORM dispatch_email_event('booking_updated', v_payload);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('confirm_booking_surcharge', 'dispatch_event_failed', 'error', SQLERRM,
            jsonb_build_object('booking_id', p_booking_id));
  END;

  -- KROK 3: in-app zpráva (appka Zprávy + FCM push) — izolovaně.
  BEGIN
    v_app_msg := 'Vaše rezervace č. ' || UPPER(RIGHT(v_b.id::text, 8))
      || ' byla upravena a doplatek ' || ROUND(v_due)::text
      || ' Kč jsme v pořádku přijali. Detaily a aktualizovanou smlouvu jsme poslali e-mailem.';
    INSERT INTO admin_messages (user_id, title, message, type)
    VALUES (v_b.user_id, 'Rezervace upravena', v_app_msg, 'info');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('confirm_booking_surcharge', 'app_message_failed', 'error', SQLERRM,
            jsonb_build_object('booking_id', p_booking_id));
  END;

  -- Payload už není potřeba.
  UPDATE bookings SET mod_email_payload = NULL WHERE id = p_booking_id;

  RETURN jsonb_build_object('success', true, 'amount', v_due,
                            'vs', COALESCE(p_vs, v_b.mod_surcharge_vs));
END;
$$;

GRANT EXECUTE ON FUNCTION confirm_booking_surcharge(uuid, text, text, date, text) TO authenticated;

-- 4) Trigger fn trg_send_booking_modified_email — 1:1 verze z 20260611 (app zpráva)
--    + NOVÁ větev: čeká-li rezervace na doplatek (mod_surcharge_due > 0), mail se
--    NEODEŠLE hned — payload se odloží do bookings.mod_email_payload a odešle ho
--    až confirm_booking_surcharge po potvrzení platby. Větev je AŽ ZA kontrolou
--    v_changed → interní UPDATE mod_email_payload (žádné sledované pole) se
--    nezacyklí (rekurzivní volání skončí na skipped_no_field_change).
CREATE OR REPLACE FUNCTION public.trg_send_booking_modified_email() RETURNS trigger
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
  v_price_diff numeric;
  v_app_msg text;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO debug_log(source, action, status, request_data)
    VALUES ('trg_booking_modified_email','skipped_status_change','info',
            jsonb_build_object('booking_id',NEW.id,'old_status',OLD.status,'new_status',NEW.status));
    RETURN NEW;
  END IF;

  IF NEW.status NOT IN ('reserved','active') THEN
    INSERT INTO debug_log(source, action, status, request_data)
    VALUES ('trg_booking_modified_email','skipped_status_not_eligible','info',
            jsonb_build_object('booking_id',NEW.id,'status',NEW.status));
    RETURN NEW;
  END IF;

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

  IF NOT v_changed THEN
    INSERT INTO debug_log(source, action, status, request_data)
    VALUES ('trg_booking_modified_email','skipped_no_field_change','info',
            jsonb_build_object(
              'booking_id',NEW.id,
              'old',jsonb_build_object('moto',OLD.moto_id,'start',OLD.start_date,'end',OLD.end_date,'total',OLD.total_price,'pickup_method',OLD.pickup_method,'pickup_time',OLD.pickup_time,'return_method',OLD.return_method,'return_time',OLD.return_time),
              'new',jsonb_build_object('moto',NEW.moto_id,'start',NEW.start_date,'end',NEW.end_date,'total',NEW.total_price,'pickup_method',NEW.pickup_method,'pickup_time',NEW.pickup_time,'return_method',NEW.return_method,'return_time',NEW.return_time)
            ));
    RETURN NEW;
  END IF;

  SELECT model INTO v_moto_old FROM motorcycles WHERE id = OLD.moto_id;
  SELECT model INTO v_moto_new FROM motorcycles WHERE id = NEW.moto_id;

  SELECT * INTO v_profile FROM profiles WHERE id = NEW.user_id;

  v_payload := jsonb_build_object(
    'booking_id', NEW.id,
    'customer_email', COALESCE(v_profile.email,''),
    'customer_name', COALESCE(v_profile.full_name,''),
    'source', COALESCE(NEW.booking_source,'app'),
    'motorcycle', COALESCE(v_moto_new,''),
    'start_date', NEW.start_date,
    'end_date', NEW.end_date,
    'total_price', NEW.total_price,
    'price_difference', COALESCE(NEW.total_price,0) - COALESCE(OLD.total_price,0),
    'pickup_method', COALESCE(NEW.pickup_method,''),
    'pickup_address', COALESCE(NEW.pickup_address,''),
    'pickup_time', COALESCE(NEW.pickup_time::text,''),
    'return_method', COALESCE(NEW.return_method,''),
    'return_address', COALESCE(NEW.return_address,''),
    'return_time', COALESCE(NEW.return_time::text,''),
    'original_motorcycle', COALESCE(v_moto_old,''),
    'original_start_date', OLD.start_date,
    'original_end_date', OLD.end_date,
    'original_total_price', OLD.total_price,
    'original_pickup_method', COALESCE(OLD.pickup_method,''),
    'original_pickup_address', COALESCE(OLD.pickup_address,''),
    'original_pickup_time', COALESCE(OLD.pickup_time::text,''),
    'original_return_method', COALESCE(OLD.return_method,''),
    'original_return_address', COALESCE(OLD.return_address,''),
    'original_return_time', COALESCE(OLD.return_time::text,'')
  );

  -- NOVÉ (2026-07-27): úprava s nezaplaceným doplatkem → mail ODLOŽIT.
  -- Payload se uschová a odešle ho confirm_booking_surcharge po potvrzení platby
  -- (zákazník mezitím dostane výzvu k platbě ze šablony booking_qr_payment přes
  -- edge fn qr-payment v režimu surcharge). Interní UPDATE nemění žádné sledované
  -- pole → rekurze se zastaví na skipped_no_field_change.
  IF COALESCE(NEW.mod_surcharge_due, 0) > 0 THEN
    BEGIN
      UPDATE bookings SET mod_email_payload = v_payload WHERE id = NEW.id;
      INSERT INTO debug_log(source, action, status, request_data)
      VALUES ('trg_booking_modified_email','deferred_surcharge_pending','info',
              jsonb_build_object('booking_id',NEW.id,'surcharge_due',NEW.mod_surcharge_due));
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO debug_log(source, action, status, error_message, request_data)
      VALUES ('trg_booking_modified_email','deferred_payload_store_failed','error',SQLERRM,
              jsonb_build_object('booking_id',NEW.id));
    END;
    RETURN NEW;
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM message_log
     WHERE booking_id = NEW.id AND template_slug LIKE 'booking_modified%'
       AND status = 'sent' AND created_at > now() - interval '5 minutes' LIMIT 1
  ) INTO v_already_sent;
  IF v_already_sent THEN
    INSERT INTO debug_log(source, action, status, request_data)
    VALUES ('trg_booking_modified_email','skipped_dedup_5min','info',
            jsonb_build_object('booking_id',NEW.id));
    RETURN NEW;
  END IF;

  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('trg_booking_modified_email','app_settings_missing','error','supabase_url or service_role_key empty',
            jsonb_build_object('booking_id',NEW.id,'has_url',v_url IS NOT NULL,'has_key',v_key IS NOT NULL));
    RETURN NEW;
  END IF;

  IF v_profile.id IS NULL OR v_profile.email IS NULL OR v_profile.email = '' THEN
    INSERT INTO debug_log(source, action, status, request_data)
    VALUES ('trg_booking_modified_email','skipped_no_email','info',
            jsonb_build_object('booking_id',NEW.id,'user_id',NEW.user_id));
    RETURN NEW;
  END IF;

  -- KROK 1: hardcoded mail — isolated tak, aby selhání KROKU 2 NEROLLBACKLO http_post
  BEGIN
    PERFORM net.http_post(
      url     := v_url || '/functions/v1/send-booking-email',
      headers := jsonb_build_object('Content-Type','application/json',
                                     'Authorization','Bearer '||v_key),
      body    := v_payload || jsonb_build_object('type','booking_modified')
    );
    INSERT INTO debug_log(source, action, status, request_data)
    VALUES ('trg_booking_modified_email','http_post_queued','info',
            jsonb_build_object('booking_id',NEW.id,'recipient',v_profile.email));
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('trg_booking_modified_email','http_post_failed','error',SQLERRM,
            jsonb_build_object('booking_id',NEW.id));
  END;

  -- KROK 2: dispatch custom šablon — isolated v vlastním BEGIN/EXCEPTION
  BEGIN
    PERFORM dispatch_email_event('booking_updated', v_payload);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('trg_booking_modified_email','dispatch_event_failed','error',SQLERRM,
            jsonb_build_object('booking_id',NEW.id));
  END;

  -- KROK 3 (2026-06-11): in-app zpráva → appka Zprávy + FCM push
  BEGIN
    v_price_diff := COALESCE(NEW.total_price,0) - COALESCE(OLD.total_price,0);
    v_app_msg := 'Vaše rezervace č. ' || UPPER(RIGHT(NEW.id::text, 8)) || ' byla upravena.'
      || CASE WHEN NEW.start_date::date <> OLD.start_date::date OR NEW.end_date::date <> OLD.end_date::date
           THEN ' Nový termín: ' || TO_CHAR(NEW.start_date,'DD.MM.YYYY') || ' – ' || TO_CHAR(NEW.end_date,'DD.MM.YYYY') || '.'
           ELSE '' END
      || CASE WHEN NEW.moto_id IS DISTINCT FROM OLD.moto_id
           THEN ' Nová motorka: ' || COALESCE(v_moto_new,'') || '.'
           ELSE '' END
      || CASE WHEN v_price_diff > 0
           THEN ' Doplatek ' || ROUND(v_price_diff)::text || ' Kč — doklad o platbě najdete v e-mailu.'
           WHEN v_price_diff < 0
           THEN ' Vracíme ' || ROUND(ABS(v_price_diff))::text || ' Kč zpět na kartu — dobropis najdete v e-mailu.'
           ELSE '' END
      || ' Detaily a aktualizovanou smlouvu jsme poslali e-mailem.';
    INSERT INTO admin_messages (user_id, title, message, type)
    VALUES (NEW.user_id, 'Rezervace upravena', v_app_msg, 'info');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('trg_booking_modified_email','app_message_failed','error',SQLERRM,
            jsonb_build_object('booking_id',NEW.id));
  END;

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  BEGIN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('trg_booking_modified_email','trigger_outer_exception','error',SQLERRM,
            jsonb_build_object('booking_id',NEW.id));
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  RETURN NEW;
END;
$$;
