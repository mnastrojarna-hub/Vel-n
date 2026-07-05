-- 2026-07-05: QR / bankovní převod jako platební metoda na WEBU (motogo24.cz).
-- Zákazník na kroku 2 rezervace zvolí "Platba QR / převodem na účet" místo Stripe.
-- Systém přidělí ČÍSELNÝ variabilní symbol (bankovní VS = jen číslice, max 10),
-- vystaví ZF s číslem účtu (mBank) a splatností 4 h a upozorní info@motogo24.cz.
-- Rezervace zůstává pending/unpaid; po připsání ji admin ručně potvrdí ve Velíně
-- (PaymentConfirmModal → confirm_payment). Nezaplacené QR se ruší stávajícím
-- cronem auto_cancel_expired_pending() (web = 4 h) — BEZE ZMĚNY.
-- POUZE WEB (booking_source='web'), NE aplikace.

-- 1) Rozlišení platebního kanálu + číselný VS na rezervaci.
ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS pay_channel text,   -- 'qr' = QR/převod; NULL/'stripe' = karta
  ADD COLUMN IF NOT EXISTS payment_vs  text;   -- číselný VS pro QR/převod

-- 2) Sekvence pro VS (8místný a výš, unikátní, čitelný).
CREATE SEQUENCE IF NOT EXISTS booking_vs_seq START WITH 10000001 INCREMENT BY 1;

-- 3) RPC: zákazník zvolí QR platbu → přidělí VS, označí kanál, potlačí "nedokončená
--    rezervace" mail (dostane ZF s pokyny). Idempotentní (návrat/refresh nepřepíše VS).
CREATE OR REPLACE FUNCTION set_booking_qr_payment(p_booking_id uuid)
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
  IF COALESCE(v_b.booking_source, '') <> 'web' THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_web_booking');
  END IF;
  IF v_b.payment_status = 'paid' THEN
    RETURN jsonb_build_object('success', false, 'error', 'already_paid');
  END IF;

  IF v_b.payment_vs IS NULL THEN                 -- VS přidělit jen jednou
    v_vs := nextval('booking_vs_seq')::text;
    UPDATE bookings
       SET payment_vs             = v_vs,
           pay_channel            = 'qr',
           payment_method         = 'bank_transfer',
           abandoned_email_sent_at = COALESCE(abandoned_email_sent_at, now()), -- potlač abandoned mail
           updated_at             = now()
     WHERE id = p_booking_id;
  ELSE
    v_vs := v_b.payment_vs;
    UPDATE bookings
       SET pay_channel            = 'qr',
           abandoned_email_sent_at = COALESCE(abandoned_email_sent_at, now())
     WHERE id = p_booking_id;
  END IF;

  RETURN jsonb_build_object(
    'success',   true,
    'booking_id', p_booking_id,
    'vs',        v_vs,
    'amount',    v_b.total_price,
    'due_hours', 4
  );
END;
$$;

GRANT EXECUTE ON FUNCTION set_booking_qr_payment(uuid) TO anon, authenticated, service_role;
