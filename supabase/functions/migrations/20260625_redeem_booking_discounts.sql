-- =============================================================================
-- MIGRACE 2026-06-25: Krok 5 — uplatnění slev po zaplacení rezervace
--   • voucher → status='redeemed' (+ booking_id), Slevomat voucher navíc nahlásí
--     uplatnění jejich Partner API (edge slevomat-voucher action='apply', pg_net)
--   • promo kód → záznam do promo_code_usage (+ used_count), idempotentně
--   • obnova při zrušení rozšířena na booking_discounts (Slevomat se NEobnovuje —
--     u Slevomatu nelze uplatnění vzít zpět; řeší se vratkou/manuálně)
-- Idempotentní: voucher redeemuje jen 'active', promo usage jen když chybí.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.redeem_booking_discounts_on_paid()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r record; v_src text; v_url text; v_key text;
BEGIN
  -- jen při PŘECHODU na paid
  IF NOT (NEW.payment_status = 'paid' AND OLD.payment_status IS DISTINCT FROM 'paid') THEN
    RETURN NEW;
  END IF;

  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key='supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key='service_role_key';

  FOR r IN SELECT * FROM booking_discounts WHERE booking_id = NEW.id LOOP
    IF r.kind = 'voucher' AND r.voucher_id IS NOT NULL THEN
      v_src := NULL;
      UPDATE vouchers
        SET status='redeemed', redeemed_at=now(), redeemed_by=NEW.user_id,
            booking_id=NEW.id, updated_at=now()
        WHERE id = r.voucher_id AND status='active'
        RETURNING source INTO v_src;
      -- Slevomat voucher → nahlas uplatnění jejich API (fire-and-forget)
      IF v_src = 'slevomat' AND v_url IS NOT NULL AND v_key IS NOT NULL THEN
        BEGIN
          PERFORM net.http_post(
            url := v_url || '/functions/v1/slevomat-voucher',
            headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key),
            body := jsonb_build_object('action','apply','code', r.code));
        EXCEPTION WHEN OTHERS THEN
          INSERT INTO debug_log(source,action,status,error_message,request_data)
          VALUES('redeem_booking_discounts_on_paid','slevomat_apply_failed','error',SQLERRM,
                 jsonb_build_object('booking_id',NEW.id,'code',r.code));
        END;
      END IF;
    ELSIF r.kind = 'promo_code' AND r.promo_code_id IS NOT NULL THEN
      IF NOT EXISTS (SELECT 1 FROM promo_code_usage WHERE promo_code_id=r.promo_code_id AND booking_id=NEW.id) THEN
        INSERT INTO promo_code_usage (promo_code_id, booking_id, customer_id, discount_applied, used_at)
        VALUES (r.promo_code_id, NEW.id, NEW.user_id, r.amount, now());
        UPDATE promo_codes SET used_count = COALESCE(used_count,0) + 1 WHERE id = r.promo_code_id;
      END IF;
    END IF;
  END LOOP;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'redeem_booking_discounts_on_paid failed for %: %', NEW.id, SQLERRM;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS redeem_booking_discounts ON bookings;
CREATE TRIGGER redeem_booking_discounts AFTER UPDATE OF payment_status ON bookings
  FOR EACH ROW EXECUTE FUNCTION public.redeem_booking_discounts_on_paid();

-- ── Obnova při zrušení — rozšířeno na booking_discounts (mimo Slevomat) ───────
CREATE OR REPLACE FUNCTION public.restore_vouchers_on_cancel()
RETURNS trigger AS $$
DECLARE v_code text; v_codes text[];
BEGIN
  IF NEW.status = 'cancelled' AND OLD.status <> 'cancelled' THEN
    -- multi: vouchery z booking_discounts (Slevomat NEobnovovat — nelze vzít zpět)
    UPDATE vouchers v
      SET status='active', redeemed_at=NULL, redeemed_by=NULL, booking_id=NULL, updated_at=now()
      FROM booking_discounts bd
      WHERE bd.booking_id = NEW.id AND bd.kind='voucher' AND bd.voucher_id = v.id
        AND v.status='redeemed' AND v.source IS DISTINCT FROM 'slevomat';
    -- legacy fallback přes discount_code
    IF NEW.discount_code IS NOT NULL AND NEW.discount_code <> '' THEN
      v_codes := string_to_array(NEW.discount_code, ',');
      FOREACH v_code IN ARRAY v_codes LOOP
        v_code := trim(v_code);
        IF v_code <> '' THEN
          UPDATE vouchers SET status='active', redeemed_at=NULL, redeemed_by=NULL, booking_id=NULL, updated_at=now()
            WHERE code = v_code AND status='redeemed' AND source IS DISTINCT FROM 'slevomat';
        END IF;
      END LOOP;
    END IF;
  END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql SECURITY DEFINER;
