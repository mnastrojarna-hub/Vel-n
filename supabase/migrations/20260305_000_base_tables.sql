-- =====================================================
-- MotoGo24 Velin — Base migrace (musí běžet PRVNÍ)
-- Vytváří sdílené tabulky a helper funkce
-- Idempotentní — bezpečné spustit opakovaně
-- =====================================================

-- ═══════════════════════════════════════════════════════
-- 0. HELPER FUNKCE
-- ═══════════════════════════════════════════════════════

-- Automatická aktualizace updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ═══════════════════════════════════════════════════════
-- 1. ADMIN_USERS
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS admin_users (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name text NOT NULL DEFAULT '',
  email text NOT NULL DEFAULT '',
  role text NOT NULL DEFAULT 'admin'
    CHECK (role IN ('admin', 'superadmin', 'technician', 'readonly')),
  phone text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Zajistit, že sloupce existují (tabulka mohla být vytvořena dříve bez nich)
DO $$ BEGIN
  ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS name text NOT NULL DEFAULT '';
  ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS email text NOT NULL DEFAULT '';
  ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS role text NOT NULL DEFAULT 'admin';
  ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS phone text;
  ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS active boolean NOT NULL DEFAULT true;
  ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
  ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();
END $$;

CREATE INDEX IF NOT EXISTS idx_admin_users_email ON admin_users(email);
CREATE INDEX IF NOT EXISTS idx_admin_users_role ON admin_users(role);

-- Helper funkce — SECURITY DEFINER obchází RLS na admin_users,
-- takže nedochází k cyklické referenci (tabulka kontrolující sama sebe)
CREATE OR REPLACE FUNCTION is_admin()
RETURNS boolean AS $$
  SELECT EXISTS (
    SELECT 1 FROM admin_users
    WHERE id = auth.uid() AND active = true
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION is_superadmin()
RETURNS boolean AS $$
  SELECT EXISTS (
    SELECT 1 FROM admin_users
    WHERE id = auth.uid() AND role = 'superadmin' AND active = true
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;

-- Všichni admini vidí všechny adminy (potřeba pro audit log, UI apod.)
DROP POLICY IF EXISTS admin_users_self ON admin_users;
DROP POLICY IF EXISTS admin_users_admin_all ON admin_users;

CREATE POLICY admin_users_read ON admin_users
  FOR SELECT USING (is_admin());

-- Pouze superadmin může vytvářet/editovat/mazat adminy
CREATE POLICY admin_users_write ON admin_users
  FOR ALL USING (is_superadmin())
  WITH CHECK (is_superadmin());

-- Trigger updated_at
DROP TRIGGER IF EXISTS trg_admin_users_updated ON admin_users;
CREATE TRIGGER trg_admin_users_updated
  BEFORE UPDATE ON admin_users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ═══════════════════════════════════════════════════════
-- 2. ADMIN_AUDIT_LOG
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS admin_audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id uuid REFERENCES admin_users(id) ON DELETE SET NULL,
  action text NOT NULL,
  details jsonb,
  ip_address inet,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_log_admin ON admin_audit_log(admin_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_action ON admin_audit_log(action);
CREATE INDEX IF NOT EXISTS idx_audit_log_created ON admin_audit_log(created_at DESC);

ALTER TABLE admin_audit_log ENABLE ROW LEVEL SECURITY;

-- Čtení: jen admini
DROP POLICY IF EXISTS audit_log_admin ON admin_audit_log;
DROP POLICY IF EXISTS audit_log_read ON admin_audit_log;
CREATE POLICY audit_log_read ON admin_audit_log
  FOR SELECT USING (is_admin());

-- Zápis: admini insertují přes SECURITY DEFINER funkci,
-- ale i přímý insert musí projít
DROP POLICY IF EXISTS audit_log_insert ON admin_audit_log;
CREATE POLICY audit_log_insert ON admin_audit_log
  FOR INSERT WITH CHECK (is_admin());

-- Update/Delete: jen superadmin (audit log by se neměl mazat)
DROP POLICY IF EXISTS audit_log_modify ON admin_audit_log;
CREATE POLICY audit_log_modify ON admin_audit_log
  FOR UPDATE USING (is_superadmin());

DROP POLICY IF EXISTS audit_log_delete ON admin_audit_log;
CREATE POLICY audit_log_delete ON admin_audit_log
  FOR DELETE USING (is_superadmin());

-- ═══════════════════════════════════════════════════════
-- 3. PROMO_CODES (slevové kódy)
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS promo_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  type text NOT NULL DEFAULT 'percent'
    CHECK (type IN ('percent', 'fixed')),
  value numeric(10,2) NOT NULL DEFAULT 0,
  valid_from date,
  valid_to date,
  max_uses integer,                 -- NULL = neomezeno
  used_count integer NOT NULL DEFAULT 0,
  min_order_amount numeric(10,2),   -- minimální hodnota objednávky
  applicable_motos text,            -- NULL = vše
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_promo_codes_code ON promo_codes(code);
CREATE INDEX IF NOT EXISTS idx_promo_codes_active ON promo_codes(active);
CREATE INDEX IF NOT EXISTS idx_promo_codes_valid ON promo_codes(valid_from, valid_to);

ALTER TABLE promo_codes ENABLE ROW LEVEL SECURITY;

-- Admini: plný přístup
DROP POLICY IF EXISTS promo_codes_admin ON promo_codes;
CREATE POLICY promo_codes_admin ON promo_codes
  FOR ALL USING (
    is_admin()
  );

-- Zákazníci: čtení aktivních kódů (pro validaci na frontendu)
DROP POLICY IF EXISTS promo_codes_public_read ON promo_codes;
CREATE POLICY promo_codes_public_read ON promo_codes
  FOR SELECT USING (active = true);

-- ═══════════════════════════════════════════════════════
-- 4. PROMO_CODE_USAGE (historie použití kódů)
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS promo_code_usage (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  promo_code_id uuid NOT NULL REFERENCES promo_codes(id) ON DELETE CASCADE,
  booking_id uuid REFERENCES bookings(id) ON DELETE SET NULL,
  customer_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  discount_applied numeric(10,2) NOT NULL DEFAULT 0,
  used_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_promo_usage_code ON promo_code_usage(promo_code_id);
CREATE INDEX IF NOT EXISTS idx_promo_usage_booking ON promo_code_usage(booking_id);

ALTER TABLE promo_code_usage ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS promo_usage_admin ON promo_code_usage;
CREATE POLICY promo_usage_admin ON promo_code_usage
  FOR ALL USING (
    is_admin()
  );

-- Automatická inkrementace used_count při insertu do promo_code_usage
CREATE OR REPLACE FUNCTION increment_promo_used_count()
RETURNS trigger AS $$
BEGIN
  UPDATE promo_codes
  SET used_count = used_count + 1
  WHERE id = NEW.promo_code_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_promo_usage_increment ON promo_code_usage;
CREATE TRIGGER trg_promo_usage_increment
  AFTER INSERT ON promo_code_usage
  FOR EACH ROW EXECUTE FUNCTION increment_promo_used_count();
