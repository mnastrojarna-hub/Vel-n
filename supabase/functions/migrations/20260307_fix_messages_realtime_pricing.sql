-- =====================================================
-- MotoGo24 — Fix messages direction constraint + voucher auto-expire
-- =====================================================

-- 1. FIX messages.direction CHECK constraint
-- The original migration had CHECK (direction IN ('inbound', 'outbound'))
-- but the admin app uses 'admin' and 'customer'. Update to accept both sets.

DO $$ BEGIN
  ALTER TABLE messages DROP CONSTRAINT IF EXISTS messages_direction_check;
EXCEPTION WHEN others THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE messages ADD CONSTRAINT messages_direction_check
    CHECK (direction IN ('inbound', 'outbound', 'admin', 'customer', 'system'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- 2. Sync moto_day_prices -> motorcycles per-day price columns
-- When PricingTab saves to moto_day_prices, we need a trigger to sync
-- the values back to the motorcycles table so enrichMOTOS picks them up.

CREATE OR REPLACE FUNCTION sync_moto_day_prices_to_motorcycles()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE motorcycles SET
    price_mon = NEW.price_monday,
    price_tue = NEW.price_tuesday,
    price_wed = NEW.price_wednesday,
    price_thu = NEW.price_thursday,
    price_fri = NEW.price_friday,
    price_sat = NEW.price_saturday,
    price_sun = NEW.price_sunday,
    price_weekday = ROUND((NEW.price_monday + NEW.price_tuesday + NEW.price_wednesday + NEW.price_thursday + NEW.price_friday) / 5),
    price_weekend = ROUND((NEW.price_saturday + NEW.price_sunday) / 2)
  WHERE id = NEW.moto_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_moto_day_prices ON moto_day_prices;
CREATE TRIGGER trg_sync_moto_day_prices
  AFTER INSERT OR UPDATE ON moto_day_prices
  FOR EACH ROW EXECUTE FUNCTION sync_moto_day_prices_to_motorcycles();

-- 3. Auto-expire vouchers function (can be called by pg_cron or app)
CREATE OR REPLACE FUNCTION expire_vouchers_and_promos()
RETURNS void AS $$
BEGIN
  -- Expire vouchers past valid_until
  UPDATE vouchers SET status = 'expired', updated_at = NOW()
  WHERE status = 'active' AND valid_until < CURRENT_DATE;

  -- Deactivate promo codes past valid_to
  UPDATE promo_codes SET active = false
  WHERE active = true AND valid_to IS NOT NULL AND valid_to < CURRENT_DATE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Enable realtime for key tables (motorcycles, bookings, documents, invoices)
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE motorcycles;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE bookings;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE documents;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE invoices;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE vouchers;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- 5. Extend document_type ENUM (new values for auto-generated docs)
-- NOTE: Must be run SEPARATELY before any usage of new values.
-- Already applied via KROK 1 in Supabase SQL Editor:
--   ALTER TYPE document_type ADD VALUE IF NOT EXISTS 'vop';
--   ALTER TYPE document_type ADD VALUE IF NOT EXISTS 'invoice_advance';
--   ALTER TYPE document_type ADD VALUE IF NOT EXISTS 'invoice_final';
-- No CHECK constraint needed — the ENUM type itself validates allowed values.
