-- =====================================================
-- MotoGo24 — Automatická obnova poukazů při zrušení rezervace
-- Pokud je rezervace zrušena (např. pro nezaplacení),
-- poukazy které byly uplatněny se automaticky obnoví.
-- =====================================================

-- Trigger funkce: obnov voucher při zrušení bookingu
CREATE OR REPLACE FUNCTION restore_vouchers_on_cancel()
RETURNS trigger AS $$
DECLARE
  v_code text;
  v_codes text[];
BEGIN
  -- Pouze pokud se status mění na 'cancelled'
  IF NEW.status = 'cancelled' AND OLD.status != 'cancelled' THEN
    -- Pokud byl uplatněn slevový kód (může být víc oddělených čárkou)
    IF NEW.discount_code IS NOT NULL AND NEW.discount_code != '' THEN
      v_codes := string_to_array(NEW.discount_code, ',');
      FOREACH v_code IN ARRAY v_codes LOOP
        v_code := trim(v_code);
        IF v_code != '' THEN
          -- Obnov voucher na 'active' pokud byl uplatněn
          UPDATE vouchers
            SET status = 'active',
                redeemed_at = NULL,
                redeemed_by = NULL,
                booking_id = NULL,
                updated_at = now()
            WHERE code = v_code AND status = 'redeemed';
        END IF;
      END LOOP;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Připoj trigger na bookings tabulku (idempotentní)
DROP TRIGGER IF EXISTS trg_restore_vouchers_on_cancel ON bookings;
CREATE TRIGGER trg_restore_vouchers_on_cancel
  AFTER UPDATE ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION restore_vouchers_on_cancel();
