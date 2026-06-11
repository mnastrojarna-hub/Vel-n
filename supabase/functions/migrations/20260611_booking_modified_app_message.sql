-- =============================================================================
-- MIGRACE 2026-06-11 (B): Úprava rezervace → in-app zpráva + push notifikace
--
-- Mail „Úprava rezervace" (booking_modified / web_booking_modified) chodí
-- e-mailem, ale do mobilní appky (sekce Zprávy) ani push notifikací dosud
-- ŽÁDNÁ informace o úpravě nechodila — admin_messages nikdo nevkládal.
--
-- Fix: trg_send_booking_modified_email po odeslání mailu (KROK 3) vloží
-- admin_message typu 'info' se shrnutím změny (termín / motorka / doplatek /
-- vratka). Na INSERT do admin_messages je navěšený trigger
-- trg_push_on_admin_message → FCM push odejde automaticky (vč. consent_push
-- gate v send-push edge fn) a appka zprávu zobrazí v sekci Zprávy.
--
-- Dedup: blok je AŽ ZA 5min dedup checkem mailu (message_log) — druhý UPDATE
-- téže úpravy (idempotentní webhook/klient apply) sem vůbec nedojde, protože
-- buď nezměnil žádné pole (skipped_no_field_change), nebo padne na dedup.
-- Vlastní BEGIN/EXCEPTION — selhání zprávy nikdy nerozbije mail ani UPDATE.
--
-- Zbytek funkce = 1:1 instrumentovaná verze z 20260519.
-- =============================================================================

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

  SELECT * INTO v_profile FROM profiles WHERE id = NEW.user_id;
  IF NOT FOUND OR v_profile.email IS NULL OR v_profile.email = '' THEN
    INSERT INTO debug_log(source, action, status, request_data)
    VALUES ('trg_booking_modified_email','skipped_no_email','info',
            jsonb_build_object('booking_id',NEW.id,'user_id',NEW.user_id));
    RETURN NEW;
  END IF;

  SELECT model INTO v_moto_old FROM motorcycles WHERE id = OLD.moto_id;
  SELECT model INTO v_moto_new FROM motorcycles WHERE id = NEW.moto_id;

  v_payload := jsonb_build_object(
    'booking_id', NEW.id,
    'customer_email', v_profile.email,
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

  -- KROK 3 (NEW 2026-06-11): in-app zpráva → appka Zprávy + FCM push
  -- (trg_push_on_admin_message na INSERT do admin_messages pošle push sám,
  -- send-push respektuje profiles.consent_push).
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
