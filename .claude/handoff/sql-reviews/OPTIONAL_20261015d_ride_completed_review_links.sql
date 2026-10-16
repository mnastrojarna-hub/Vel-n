-- OPTIONAL_20261015d_ride_completed_review_links.sql
-- =============================================================================
-- NÁVRH (čeká na schválení majitelem — CLAUDE.md pravidlo 3). VOLITELNÉ, NE NALÉHAVÉ —
-- dnes se nic špatně neodesílá (app_settings.google_review_url existuje a edge
-- send-booking-email payloadové odkazy ignoruje a bere jen Google). Jde o úklid, aby
-- ani záložní hodnoty v DB neukazovaly mimo Google („odkaz na recenze VŽDY Google“).
--
-- Zdroj: živé definice ze snapshotu origin/supabase-live-snapshot (2026-10-10),
-- schema_public.sql — změněny JEN vyznačené řádky, jinak 1:1.
--   1) trg_notify_ride_completed() (SMS/WhatsApp „ride_completed“; trigger dnes v živé DB
--      NENÍ připojen — STATE_4) — záloha review_link 'https://motogo24.cz' → Google odkaz
--      (stejný jako výchozí hodnota appky i edge `_shared/review-links.ts`).
--   2) notify_booking_completed_email() (duplicitní trigger mailu, STATE_4) —
--      `value::text` (JSON s uvozovkami) → `value #>> '{}'` (čistý text) a pryč natvrdo
--      zadaný `facebook_review_url`.
-- CREATE OR REPLACE zachová vlastníka, granty i navázané triggery. Idempotentní.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.trg_notify_ride_completed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_phone text;
  v_moto_model text;
  v_lang text;
  v_already_sent boolean;
  v_review_link text;
BEGIN
  IF NEW.status != 'completed' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = 'completed' THEN RETURN NEW; END IF;

  SELECT EXISTS(
    SELECT 1 FROM message_log
    WHERE booking_id = NEW.id AND template_slug = 'ride_completed' AND status = 'sent'
    LIMIT 1
  ) INTO v_already_sent;
  IF v_already_sent THEN RETURN NEW; END IF;

  SELECT phone INTO v_phone FROM profiles WHERE id = NEW.user_id;
  IF v_phone IS NULL OR v_phone = '' THEN RETURN NEW; END IF;

  SELECT model INTO v_moto_model FROM motorcycles WHERE id = NEW.moto_id;
  v_lang := detect_customer_language(NEW.user_id, NEW.id, NULL);

  -- Review link z app_settings; záloha = Google recenze (ZMĚNA: dřív web motogo24.cz)
  SELECT value #>> '{}' INTO v_review_link FROM app_settings WHERE key = 'google_review_url';

  PERFORM send_sms_and_wa(
    v_phone,
    'ride_completed',
    jsonb_build_object(
      'motorcycle',   coalesce(v_moto_model, ''),
      'review_link',  coalesce(nullif(v_review_link, ''), 'https://g.page/r/CUmeYvk-sNf6EBM/review')
    ),
    NEW.user_id,
    NEW.id,
    v_lang
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_notify_ride_completed failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_booking_completed_email()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE v_email text; v_name text; v_moto text; v_url text; v_key text; v_google text;
BEGIN
  IF OLD.status != 'active' OR NEW.status != 'completed' THEN RETURN NEW; END IF;
  IF NEW.payment_status != 'paid' THEN RETURN NEW; END IF;
  IF EXISTS (SELECT 1 FROM message_log WHERE booking_id = NEW.id AND template_slug = 'booking_completed' AND channel = 'email' AND status = 'sent') THEN RETURN NEW; END IF;
  SELECT email, full_name INTO v_email, v_name FROM profiles WHERE id = NEW.user_id;
  IF v_email IS NULL THEN RETURN NEW; END IF;
  SELECT model INTO v_moto FROM motorcycles WHERE id = NEW.moto_id;
  -- ZMĚNA: čistý text místo JSON s uvozovkami
  SELECT value #>> '{}' INTO v_google FROM app_settings WHERE key = 'google_review_url';
  v_url := current_setting('supabase.url', true); v_key := current_setting('supabase.service_role_key', true);
  PERFORM net.http_post(url := v_url || '/functions/v1/send-booking-email',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key,'apikey',v_key),
    -- ZMĚNA: bez natvrdo zadaného facebook_review_url (recenze jen Google)
    body := jsonb_build_object('type','booking_completed','booking_id',NEW.id,'customer_email',v_email,'customer_name',COALESCE(v_name,''),'motorcycle',COALESCE(v_moto,''),'start_date',NEW.start_date,'end_date',NEW.end_date,'total_price',NEW.total_price,'source',COALESCE(NEW.booking_source,'app'),'google_review_url',COALESCE(v_google,'')));
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN RAISE WARNING 'notify_booking_completed_email failed: %', SQLERRM; RETURN NEW;
END; $$;

-- STATE po schválení: STATE_3/STATE_4 (poznámka u obou funkcí), STATE_6 (changelog).
