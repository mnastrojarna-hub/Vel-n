-- =============================================================================
-- 2026-11-30c: lhůta QR platby rezervace se počítá od ZVOLENÍ QR + storno e-mail po vypršení
--
-- Dnes: web slibuje „uhraďte do 4 hodin“, ale cron auto_cancel_expired_pending ruší webovou
-- rezervaci 4 h od ZALOŽENÍ (created_at). Zákazník, který zvolí QR 3 h po založení rezervace,
-- má na platbu jen hodinu — a o zrušení se nedozví (web rezervace storno mail nedostávají a
-- QR volba potlačila i mail „nedokončená rezervace“). Platí pro motorky i výpůjčku JEN výbavy.
-- Rozhodnutí majitele 2026-11-27: lhůta 4 hodiny zůstává, počítá se od zvolení QR, po vypršení
-- storno e-mail.
--
--   1) bookings.qr_requested_at = okamžik PRVNÍ volby QR (set_booking_qr_payment); opakovaná
--      volba lhůtu neprodlužuje. RPC nově vrací i expires_at (web ukáže přesný čas; edge qr-payment
--      podle něj pozná, že je tato změna nasazená).
--   2) auto_cancel_expired_pending: QR rezervace se ruší 4 h od qr_requested_at (jinak beze změny);
--      zrušená QR rezervace dostane storno e-mail (stejný, jaký dostává appka).
-- Obě funkce = AKTUÁLNÍ živá těla (pg_get_functiondef po migracích do 20261128e3) + jen řádky
-- označené „QR“. Ověřeno fndiff.sh proti živému schématu.
-- Idempotentní. STATE soubory: 2 (sloupec), 3 (RPC), 5 (cron — popis), 6.
-- =============================================================================

ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS qr_requested_at timestamptz;
COMMENT ON COLUMN public.bookings.qr_requested_at IS
  'Okamžik první volby platby QR / převodem na webu (set_booking_qr_payment). Od něj běží 4h lhůta auto_cancel_expired_pending.';

CREATE OR REPLACE FUNCTION public.set_booking_qr_payment(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_b  bookings%ROWTYPE;
  v_vs text;
  v_at timestamptz;
BEGIN
  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  IF COALESCE(v_b.booking_source, '') <> 'web' THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_web_booking');
  END IF;
  IF v_b.payment_status = 'paid' THEN
    RETURN jsonb_build_object('success', false, 'error', 'already_paid');
  END IF;

  v_at := COALESCE(v_b.qr_requested_at, now());            -- QR: lhůta od PRVNÍ volby QR

  IF v_b.payment_vs IS NULL THEN                 -- VS přidělit jen jednou
    v_vs := nextval('booking_vs_seq')::text;
    UPDATE bookings
       SET payment_vs             = v_vs,
           pay_channel            = 'qr',
           payment_method         = 'bank_transfer',
           qr_requested_at        = v_at,
           abandoned_email_sent_at = COALESCE(abandoned_email_sent_at, now()), -- potlač abandoned mail
           updated_at             = now()
     WHERE id = p_booking_id;
  ELSE
    v_vs := v_b.payment_vs;
    UPDATE bookings
       SET pay_channel            = 'qr',
           qr_requested_at        = v_at,
           abandoned_email_sent_at = COALESCE(abandoned_email_sent_at, now())
     WHERE id = p_booking_id;
  END IF;

  RETURN jsonb_build_object(
    'success',   true,
    'booking_id', p_booking_id,
    'vs',        v_vs,
    'amount',    v_b.total_price,
    'due_hours', 4,
    'expires_at', v_at + interval '4 hours'
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.set_booking_qr_payment(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_booking_qr_payment(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.auto_cancel_expired_pending()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
          WHEN booking_source = 'app' OR restored_by_source = 'app'                 -- D3
            THEN 'Automaticky zrušeno — nezaplaceno do 30 minut'
          ELSE  'Automaticky zrušeno — nezaplaceno do 4 hodin'
        END,
        cancelled_at         = now(),
        cancelled_by_source  = 'auto'
      WHERE status = 'pending'
        AND payment_status = 'unpaid'
        AND (                                                                       -- D3
          -- běžné (neobnovené) rezervace jako dosud
          (restored_at IS NULL AND (
            (booking_source = 'app' AND created_at < now() - interval '30 minutes')
            -- QR: u platby převodem běží 4 h od zvolení QR (qr_requested_at), jinak od založení
            OR (booking_source = 'web'
                AND GREATEST(created_at, COALESCE(qr_requested_at, created_at)) < now() - interval '4 hours')
          ))
          -- obnovené zákazníkem v appce: 30 min od obnovení
          OR (restored_by_source = 'app' AND restored_at < now() - interval '30 minutes')
          -- obnovené ve Velínu (restored_by_source NULL) cron neruší — řeší admin
        )
        -- D3: probíhající platba (process-payment zapsal checkout_started_at při
        -- vytvoření PaymentIntentu) → 10 min navíc, nejvýš 60 min od začátku okna
        AND NOT (checkout_started_at IS NOT NULL
                 AND checkout_started_at > now() - interval '10 minutes'
                 AND COALESCE(restored_at, created_at) > now() - interval '60 minutes')
      RETURNING id, user_id, moto_id, start_date, end_date,
                booking_source, cancellation_reason, pay_channel
    )
    SELECT c.id, c.user_id, c.moto_id, c.start_date, c.end_date,
           c.booking_source, c.cancellation_reason, c.pay_channel,
           p.email AS customer_email, p.full_name AS customer_name,
           m.model AS motorcycle_model
      FROM cancelled c
      LEFT JOIN profiles p     ON p.id = c.user_id
      LEFT JOIN motorcycles m  ON m.id = c.moto_id
  LOOP
    -- Web rezervace už dostaly "Nedokončená rezervace" mail z
    -- send_abandoned_booking_emails() po 15 min — neposílej druhý "Storno" mail.
    -- QR: výjimka = rezervace čekající na převod (volba QR mail „nedokončená“ potlačila) →
    -- storno mail dostane, aby zákazník neplatil rezervaci, která už neplatí.
    IF v_row.booking_source = 'web' AND COALESCE(v_row.pay_channel, '') <> 'qr' THEN
      CONTINUE;
    END IF;

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
$function$;
REVOKE ALL ON FUNCTION public.auto_cancel_expired_pending() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.auto_cancel_expired_pending() TO service_role;
