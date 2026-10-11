-- =============================================================================
-- 2026-10-11 BEZPEČNOST: kontroly volajícího uvnitř RPC (vlastník / admin / server)
-- Doplněk k 20261011d (granty): authenticated EXECUTE u těchto funkcí zůstává,
-- takže tělo samo musí odmítnout cizího zákazníka; anon odmítne i bez grantu
-- (fail closed). Těla = živá definice, měněno jen označené „2026-10-11“.
-- Části: _b SOS náhrada, _c/_d hromadná aktualizace jednotek, _e Logistika,
-- _f poukazy (limit neplatných pokusů). Idempotentní (CREATE OR REPLACE).
-- =============================================================================

-- 0) Helper: volá admin (Velín) nebo server.
--    Pozor: uvnitř SECURITY DEFINER je current_user VŽDY vlastník (postgres) —
--    rozhoduje GUC `role`, který PostgREST nastaví podle JWT a DEFINER ho nemění:
--    anon → ne; authenticated → is_admin(); service_role → ano; přímé DB
--    spojení bez API role (pg_cron, postgres, GitHub Action) → ano.
CREATE OR REPLACE FUNCTION public._rpc_caller_is_staff()
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  SELECT CASE coalesce(nullif(current_setting('role', true), ''), 'none')
           WHEN 'anon'          THEN false
           WHEN 'authenticated' THEN public.is_admin()
           WHEN 'service_role'  THEN true
           ELSE session_user::text <> 'authenticator'
         END
$function$;
REVOKE ALL ON FUNCTION public._rpc_caller_is_staff() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._rpc_caller_is_staff() TO service_role;

-- 1) cancel_booking_tracked: `user_id != auth.uid()` je pro anon / user_id NULL
--    NULL → kontrola procházela (storno + refund cizí rezervace). Fail closed.
CREATE OR REPLACE FUNCTION public.cancel_booking_tracked(p_booking_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
  v_staff        boolean;  -- 2026-10-11
BEGIN
  v_uid := auth.uid();
  v_staff := public._rpc_caller_is_staff();  -- 2026-10-11

  -- 2026-10-11: bez přihlášení (a mimo server) vůbec nehledat
  IF v_uid IS NULL AND NOT v_staff THEN
    RETURN jsonb_build_object('error', 'Nemáte oprávnění');
  END IF;

  SELECT * INTO v_booking FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Rezervace nenalezena');
  END IF;

  -- 2026-10-11: NULL-bezpečně — vlastník, admin nebo server
  IF NOT v_staff AND v_booking.user_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('error', 'Nemáte oprávnění');
  END IF;

  IF v_booking.status = 'cancelled' THEN
    RETURN jsonb_build_object('error', 'Rezervace je již stornována');
  END IF;

  v_was_paid    := (v_booking.payment_status = 'paid');
  v_hours_until := EXTRACT(EPOCH FROM (v_booking.start_date - now())) / 3600;
  -- 2026-08-04: '>=' místo '>' — web i appka slibují 100 % už PŘESNĚ na hranici
  -- 168 h (a 50 % na 48 h); server nesmí na hranici vracet méně, než UI slíbilo.
  IF v_hours_until >= 168 THEN v_refund_pct := 100;
  ELSIF v_hours_until >= 48    THEN v_refund_pct := 50;
  ELSE                              v_refund_pct := 0;
  END IF;
  -- 2026-08-22c: STROP PO POSUNU TERMÍNU — storno tabulka se počítá z
  -- AKTUÁLNÍHO startu, ale posunutá rezervace už nikdy nemá 100% vratku:
  -- posun ≥168 h před PŮVODNÍM (před-posunovým) startem → max 50 %, pozdější
  -- posun → 0 %. Vždy přísnější sazba (LEAST). Viz _storno_cap_after_move.
  v_refund_pct := LEAST(v_refund_pct, public._storno_cap_after_move(
    v_booking.modification_history, v_booking.original_start_date::date, v_booking.start_date::date));
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
$function$;

-- 2) sos_share_location: záznam do časové osy JEN když poloha patří
--    volajícímu incidentu (dřív i anon / cizí incident: falešné GPS dispečinku).
CREATE OR REPLACE FUNCTION public.sos_share_location(p_incident_id uuid, p_lat numeric, p_lng numeric)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    IF auth.uid() IS NULL THEN RETURN false; END IF;  -- 2026-10-11

    UPDATE sos_incidents SET latitude = p_lat, longitude = p_lng, updated_at = NOW()
    WHERE id = p_incident_id AND user_id = auth.uid();
    IF NOT FOUND THEN RETURN false; END IF;  -- 2026-10-11

    INSERT INTO sos_timeline (incident_id, action, performed_by, data)
    VALUES (p_incident_id, 'gps_shared', auth.uid(), jsonb_build_object('lat', p_lat, 'lng', p_lng));

    RETURN true;  -- 2026-10-11 (dřív FOUND z INSERTu = vždy true)
END;
$function$;

-- 3) get_unread_thread_message_count: jen vlastní vlákna (nebo admin / server).
CREATE OR REPLACE FUNCTION public.get_unread_thread_message_count(p_customer_id uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT COALESCE(COUNT(*)::integer, 0)
  FROM messages m
  JOIN message_threads t ON t.id = m.thread_id
  WHERE t.customer_id = p_customer_id
    AND m.direction = 'admin'
    AND m.read_at IS NULL
    -- 2026-10-11: jen vlastní počet (nebo admin / server)
    AND (p_customer_id = auth.uid() OR (SELECT public._rpc_caller_is_staff()));
$function$;

-- 4) next_document_number: číselné řady dokladů jen server (edge generate-invoice
--    / process-refund se service klíčem, cron/postgres) nebo trigger — Velín ji
--    nevolá (čísla počítá sám). KF/DB z generate_final_invoice_on_complete běží
--    i při akci zákazníka (např. SOS výměna) → pg_trigger_depth() > 0; přímé
--    RPC má hloubku 0.
CREATE OR REPLACE FUNCTION public.next_document_number(p_prefix text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_year int := EXTRACT(YEAR FROM CURRENT_DATE)::int;
  v_seq int;
  v_live_max int;
BEGIN
  -- 2026-10-11: zákazník / anon nesmí „pálit“ čísla zákonné řady (jen server / trigger)
  IF NOT (pg_trigger_depth() > 0
          OR (coalesce(nullif(current_setting('role', true), ''), 'none') <> 'authenticated'
              AND public._rpc_caller_is_staff())) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  INSERT INTO document_number_counters (prefix, year, last_seq)
  VALUES (p_prefix, v_year, 0)
  ON CONFLICT (prefix, year) DO NOTHING;

  SELECT COALESCE(MAX(CAST(SUBSTRING(number FROM '-(\d+)$') AS int)), 0)
    INTO v_live_max
    FROM invoices
   WHERE number LIKE p_prefix||'-'||v_year||'-%'
     AND CAST(SUBSTRING(number FROM '-(\d+)$') AS int) < 5000;

  UPDATE document_number_counters                 -- row-lock serializuje souběh
     SET last_seq = GREATEST(last_seq, v_live_max) + 1
   WHERE prefix = p_prefix AND year = v_year
  RETURNING last_seq INTO v_seq;

  RETURN p_prefix||'-'||v_year||'-'||LPAD(v_seq::text, 4, '0');
END; $function$;

-- 5) auto_reply_sos: nikdo ji nevolá; zákazník přes ni posílal „adminské“
--    zprávy (send_admin_message) majiteli libovolného incidentu → jen admin/server.
CREATE OR REPLACE FUNCTION public.auto_reply_sos(p_incident_id uuid, p_reply_type text DEFAULT 'sos_response'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_user_id UUID;
    v_sos_type TEXT;
    v_title TEXT;
    v_message TEXT;
BEGIN
    -- 2026-10-11: jen admin / server (dřív zákazník posílal „adminské“ zprávy do cizích incidentů)
    IF NOT public._rpc_caller_is_staff() THEN
        RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
    END IF;

    SELECT user_id, type::TEXT INTO v_user_id, v_sos_type
    FROM sos_incidents WHERE id = p_incident_id;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Incident nenalezen';
    END IF;

    CASE p_reply_type
        WHEN 'thanks' THEN
            CASE v_sos_type
                WHEN 'accident_minor' THEN
                    v_title := 'Děkujeme za nahlášení';
                    v_message := 'Děkujeme za nahlášení drobné nehody. Šťastnou cestu! Pokud budete potřebovat cokoliv dalšího, neváhejte nás kontaktovat.';
                WHEN 'accident_major' THEN
                    v_title := 'Přijali jsme vaše hlášení';
                    v_message := 'Vaše hlášení vážné nehody bylo přijato. Náš tým se tím okamžitě zabývá. Zůstaňte v bezpečí a čekejte na další instrukce.';
                WHEN 'breakdown_minor' THEN
                    v_title := 'Děkujeme za nahlášení';
                    v_message := 'Děkujeme za nahlášení poruchy. Šťastnou cestu! Závadu prověříme při nejbližším servisu.';
                WHEN 'breakdown_major' THEN
                    v_title := 'Přijali jsme vaše hlášení';
                    v_message := 'Vaše hlášení poruchy bylo přijato. Pracujeme na řešení. Prosím vyčkejte na místě.';
                WHEN 'theft' THEN
                    v_title := 'Hlášení krádeže přijato';
                    v_message := 'Vaše hlášení krádeže bylo přijato. Kontaktovali jsme Policii ČR. Prosím volejte také 158. Ozveme se co nejdříve.';
                ELSE
                    v_title := 'Děkujeme za nahlášení';
                    v_message := 'Vaše hlášení bylo přijato. Děkujeme a šťastnou cestu!';
            END CASE;
        WHEN 'replacement' THEN
            v_title := 'Vezeme vám náhradní motorku';
            v_message := 'Vydržte! Vezeme vám náhradní motorku. Budeme u vás co nejdříve. Sledujte prosím telefon pro další informace.';
        WHEN 'tow' THEN
            v_title := 'Odtahová služba na cestě';
            v_message := 'Zavolali jsme vám odtahovou službu. Prosím vyčkejte na místě. Řidič vás bude kontaktovat telefonicky.';
        ELSE
            v_title := 'Zpráva z MotoGo24';
            v_message := 'Vaše hlášení bylo přijato. Děkujeme za informaci.';
    END CASE;

    RETURN send_admin_message(
        v_user_id, v_title, v_message, p_reply_type, p_incident_id, NULL
    );
END;
$function$;
