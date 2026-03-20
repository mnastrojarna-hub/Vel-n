-- =====================================================
-- MotoGo24 — Messaging System Migration
-- Přidává: message_channel enum, rozšíření message_templates,
--          message_log, broadcast_campaigns, profily rozšíření
-- Idempotentní — bezpečně spustit opakovaně
-- =====================================================

-- ═══════════════════════════════════════════════════════
-- 1. ENUM message_channel
-- ═══════════════════════════════════════════════════════

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_channel') THEN
    CREATE TYPE message_channel AS ENUM ('sms', 'whatsapp', 'email');
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════
-- 2. TABULKA message_templates (ALTER existující + nové sloupce)
-- ═══════════════════════════════════════════════════════

-- Přidej nové sloupce do existující tabulky
ALTER TABLE message_templates ADD COLUMN IF NOT EXISTS slug text;
ALTER TABLE message_templates ADD COLUMN IF NOT EXISTS channel text DEFAULT 'sms';
ALTER TABLE message_templates ADD COLUMN IF NOT EXISTS subject text;
ALTER TABLE message_templates ADD COLUMN IF NOT EXISTS subject_template text;
ALTER TABLE message_templates ADD COLUMN IF NOT EXISTS body_template text;
ALTER TABLE message_templates ADD COLUMN IF NOT EXISTS wa_template_id text;
ALTER TABLE message_templates ADD COLUMN IF NOT EXISTS is_marketing boolean DEFAULT false;
ALTER TABLE message_templates ADD COLUMN IF NOT EXISTS is_active boolean DEFAULT true;
ALTER TABLE message_templates ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

-- Synchronizuj body_template z content (pro existující řádky)
UPDATE message_templates SET body_template = content WHERE body_template IS NULL AND content IS NOT NULL;

-- Nastav slug z name kde chybí (lower, strip diakritiky, replace spaces)
UPDATE message_templates SET slug = lower(replace(replace(name, ' ', '_'), '-', '_'))
  WHERE slug IS NULL AND name IS NOT NULL;

-- Unique constraint (slug + channel + language) — jen pokud neexistuje
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'message_templates_slug_channel_language_key'
  ) THEN
    -- Nejdřív odstraň duplikáty (ponech nejnovější)
    DELETE FROM message_templates a USING message_templates b
      WHERE a.id < b.id AND a.slug = b.slug AND a.channel = b.channel AND a.language = b.language
      AND a.slug IS NOT NULL;
    ALTER TABLE message_templates ADD CONSTRAINT message_templates_slug_channel_language_key
      UNIQUE (slug, channel, language);
  END IF;
END $$;

-- Updated_at trigger
DROP TRIGGER IF EXISTS trg_message_templates_updated ON message_templates;
CREATE TRIGGER trg_message_templates_updated
  BEFORE UPDATE ON message_templates
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- RLS — rozšíř politiky
DROP POLICY IF EXISTS message_templates_admin ON message_templates;
DROP POLICY IF EXISTS message_templates_read ON message_templates;
DROP POLICY IF EXISTS message_templates_write ON message_templates;

CREATE POLICY message_templates_read ON message_templates
  FOR SELECT USING (true);

CREATE POLICY message_templates_write ON message_templates
  FOR ALL USING (is_admin())
  WITH CHECK (is_admin());

-- ═══════════════════════════════════════════════════════
-- 2b. SEED message_templates — výchozí šablony
-- ═══════════════════════════════════════════════════════

-- SMS šablony (transakční)
INSERT INTO message_templates (slug, channel, language, name, body_template, content, is_marketing, is_active)
VALUES
  ('booking_confirmed', 'sms', 'cs', 'Potvrzení rezervace',
   'Vaše rezervace {{booking_number}} je potvrzena! Motorka: {{motorcycle}}, termín: {{start_date}} – {{end_date}}. MOTO GO 24',
   'Vaše rezervace {{booking_number}} je potvrzena! Motorka: {{motorcycle}}, termín: {{start_date}} – {{end_date}}. MOTO GO 24',
   false, true),
  ('door_codes', 'sms', 'cs', 'Přístupové kódy',
   'Kódy pro rezervaci {{booking_number}}: Motorka: {{door_code_moto}}, Výbava: {{door_code_gear}}. Šťastnou jízdu! MOTO GO 24',
   'Kódy pro rezervaci {{booking_number}}: Motorka: {{door_code_moto}}, Výbava: {{door_code_gear}}. Šťastnou jízdu! MOTO GO 24',
   false, true),
  ('booking_reminder', 'sms', 'cs', 'Připomínka D-1',
   'Zítra začíná Vaše rezervace {{booking_number}}! Motorka {{motorcycle}} na Vás čeká. Nezapomeňte ŘP. MOTO GO 24',
   'Zítra začíná Vaše rezervace {{booking_number}}! Motorka {{motorcycle}} na Vás čeká. Nezapomeňte ŘP. MOTO GO 24',
   false, true),
  ('ride_completed', 'sms', 'cs', 'Jízda dokončena',
   'Děkujeme za jízdu na {{motorcycle}}! Jak se Vám líbilo? Ohodnoťte nás: {{review_link}}. MOTO GO 24',
   'Děkujeme za jízdu na {{motorcycle}}! Jak se Vám líbilo? Ohodnoťte nás: {{review_link}}. MOTO GO 24',
   false, true),
  ('booking_cancelled', 'sms', 'cs', 'Storno rezervace',
   'Rezervace {{booking_number}} byla zrušena. Pokud máte dotazy, kontaktujte nás. MOTO GO 24',
   'Rezervace {{booking_number}} byla zrušena. Pokud máte dotazy, kontaktujte nás. MOTO GO 24',
   false, true),
  ('voucher_purchased', 'sms', 'cs', 'Voucher zakoupen',
   'Váš poukaz {{voucher_code}} v hodnotě {{voucher_amount}} Kč je aktivní! Platí do {{expiry_date}}. MOTO GO 24',
   'Váš poukaz {{voucher_code}} v hodnotě {{voucher_amount}} Kč je aktivní! Platí do {{expiry_date}}. MOTO GO 24',
   false, true),
  ('deposit_returned', 'sms', 'cs', 'Kauce vrácena',
   'Kauce {{deposit_amount}} Kč za rezervaci {{booking_number}} byla vrácena na Váš účet. MOTO GO 24',
   'Kauce {{deposit_amount}} Kč za rezervaci {{booking_number}} byla vrácena na Váš účet. MOTO GO 24',
   false, true),
  ('sos_received', 'sms', 'cs', 'SOS přijato',
   'Přijali jsme Váš SOS požadavek. Kontaktujeme Vás co nejdříve. MOTO GO 24',
   'Přijali jsme Váš SOS požadavek. Kontaktujeme Vás co nejdříve. MOTO GO 24',
   false, true),
  ('season_opening', 'sms', 'cs', 'Zahájení sezóny',
   'Sezóna 2026 je tu! Rezervuj motorku se slevou {{discount}}% na motogo24.cz. MOTO GO 24',
   'Sezóna 2026 je tu! Rezervuj motorku se slevou {{discount}}% na motogo24.cz. MOTO GO 24',
   true, true),
  ('last_minute', 'sms', 'cs', 'Last minute',
   '{{motorcycle}} volná {{date}} za {{price}} Kč! Rezervuj: {{link}}. MOTO GO 24',
   '{{motorcycle}} volná {{date}} za {{price}} Kč! Rezervuj: {{link}}. MOTO GO 24',
   true, true)
ON CONFLICT (slug, channel, language) DO NOTHING;

-- WhatsApp šablony (stejné slugy, channel='whatsapp')
INSERT INTO message_templates (slug, channel, language, name, body_template, content, is_marketing, is_active)
VALUES
  ('booking_confirmed', 'whatsapp', 'cs', 'Potvrzení rezervace',
   'Vaše rezervace {{booking_number}} je potvrzena! Motorka: {{motorcycle}}, termín: {{start_date}} – {{end_date}}. MOTO GO 24',
   'Vaše rezervace {{booking_number}} je potvrzena! Motorka: {{motorcycle}}, termín: {{start_date}} – {{end_date}}. MOTO GO 24',
   false, true),
  ('door_codes', 'whatsapp', 'cs', 'Přístupové kódy',
   'Kódy pro rezervaci {{booking_number}}: Motorka: {{door_code_moto}}, Výbava: {{door_code_gear}}. Šťastnou jízdu! MOTO GO 24',
   'Kódy pro rezervaci {{booking_number}}: Motorka: {{door_code_moto}}, Výbava: {{door_code_gear}}. Šťastnou jízdu! MOTO GO 24',
   false, true),
  ('booking_reminder', 'whatsapp', 'cs', 'Připomínka D-1',
   'Zítra začíná Vaše rezervace {{booking_number}}! Motorka {{motorcycle}} na Vás čeká. Nezapomeňte ŘP. MOTO GO 24',
   'Zítra začíná Vaše rezervace {{booking_number}}! Motorka {{motorcycle}} na Vás čeká. Nezapomeňte ŘP. MOTO GO 24',
   false, true),
  ('ride_completed', 'whatsapp', 'cs', 'Jízda dokončena',
   'Děkujeme za jízdu na {{motorcycle}}! Jak se Vám líbilo? Ohodnoťte nás: {{review_link}}. MOTO GO 24',
   'Děkujeme za jízdu na {{motorcycle}}! Jak se Vám líbilo? Ohodnoťte nás: {{review_link}}. MOTO GO 24',
   false, true),
  ('booking_cancelled', 'whatsapp', 'cs', 'Storno rezervace',
   'Rezervace {{booking_number}} byla zrušena. Pokud máte dotazy, kontaktujte nás. MOTO GO 24',
   'Rezervace {{booking_number}} byla zrušena. Pokud máte dotazy, kontaktujte nás. MOTO GO 24',
   false, true),
  ('voucher_purchased', 'whatsapp', 'cs', 'Voucher zakoupen',
   'Váš poukaz {{voucher_code}} v hodnotě {{voucher_amount}} Kč je aktivní! Platí do {{expiry_date}}. MOTO GO 24',
   'Váš poukaz {{voucher_code}} v hodnotě {{voucher_amount}} Kč je aktivní! Platí do {{expiry_date}}. MOTO GO 24',
   false, true),
  ('deposit_returned', 'whatsapp', 'cs', 'Kauce vrácena',
   'Kauce {{deposit_amount}} Kč za rezervaci {{booking_number}} byla vrácena na Váš účet. MOTO GO 24',
   'Kauce {{deposit_amount}} Kč za rezervaci {{booking_number}} byla vrácena na Váš účet. MOTO GO 24',
   false, true),
  ('sos_received', 'whatsapp', 'cs', 'SOS přijato',
   'Přijali jsme Váš SOS požadavek. Kontaktujeme Vás co nejdříve. MOTO GO 24',
   'Přijali jsme Váš SOS požadavek. Kontaktujeme Vás co nejdříve. MOTO GO 24',
   false, true),
  ('season_opening', 'whatsapp', 'cs', 'Zahájení sezóny',
   'Sezóna 2026 je tu! Rezervuj motorku se slevou {{discount}}% na motogo24.cz. MOTO GO 24',
   'Sezóna 2026 je tu! Rezervuj motorku se slevou {{discount}}% na motogo24.cz. MOTO GO 24',
   true, true),
  ('last_minute', 'whatsapp', 'cs', 'Last minute',
   '{{motorcycle}} volná {{date}} za {{price}} Kč! Rezervuj: {{link}}. MOTO GO 24',
   '{{motorcycle}} volná {{date}} za {{price}} Kč! Rezervuj: {{link}}. MOTO GO 24',
   true, true)
ON CONFLICT (slug, channel, language) DO NOTHING;

-- ═══════════════════════════════════════════════════════
-- 3. TABULKA message_log
-- ═══════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS message_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  channel text NOT NULL DEFAULT 'sms',
  direction text NOT NULL DEFAULT 'outbound'
    CHECK (direction IN ('outbound', 'inbound')),
  recipient_phone text,
  recipient_email text,
  customer_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  booking_id uuid REFERENCES bookings(id) ON DELETE SET NULL,
  template_slug text,
  content_preview text,
  body text,
  external_id text,
  status text NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'sent', 'delivered', 'failed', 'bounced')),
  error_message text,
  cost_amount numeric(8,4),
  metadata jsonb DEFAULT '{}',
  is_marketing boolean DEFAULT false,
  template_vars jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Indexy
CREATE INDEX IF NOT EXISTS idx_message_log_customer_id ON message_log(customer_id);
CREATE INDEX IF NOT EXISTS idx_message_log_booking_id ON message_log(booking_id);
CREATE INDEX IF NOT EXISTS idx_message_log_created_at ON message_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_message_log_channel_status ON message_log(channel, status);
CREATE INDEX IF NOT EXISTS idx_message_log_template_slug ON message_log(template_slug);

-- RLS
ALTER TABLE message_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS message_log_read ON message_log;
DROP POLICY IF EXISTS message_log_write ON message_log;
DROP POLICY IF EXISTS message_log_admin ON message_log;

CREATE POLICY message_log_read ON message_log
  FOR SELECT USING (is_admin());

CREATE POLICY message_log_admin ON message_log
  FOR ALL USING (is_admin())
  WITH CHECK (is_admin());

-- ═══════════════════════════════════════════════════════
-- 4. TABULKA broadcast_campaigns
-- ═══════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS broadcast_campaigns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  channel text NOT NULL DEFAULT 'sms',
  template_id uuid REFERENCES message_templates(id) ON DELETE SET NULL,
  segment text DEFAULT 'all',
  segment_filter jsonb DEFAULT '{}',
  template_vars jsonb DEFAULT '{}',
  scheduled_at timestamptz,
  status text DEFAULT 'draft'
    CHECK (status IN ('draft', 'scheduled', 'sending', 'completed', 'cancelled')),
  total_recipients int DEFAULT 0,
  sent_count int DEFAULT 0,
  failed_count int DEFAULT 0,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_broadcast_campaigns_channel ON broadcast_campaigns(channel);
CREATE INDEX IF NOT EXISTS idx_broadcast_campaigns_status ON broadcast_campaigns(status);
CREATE INDEX IF NOT EXISTS idx_broadcast_campaigns_created_at ON broadcast_campaigns(created_at DESC);

-- RLS
ALTER TABLE broadcast_campaigns ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS broadcast_campaigns_admin ON broadcast_campaigns;

CREATE POLICY broadcast_campaigns_admin ON broadcast_campaigns
  FOR ALL USING (is_admin())
  WITH CHECK (is_admin());

-- ═══════════════════════════════════════════════════════
-- 5. ALTER profiles — přidání sloupců pro messaging
-- ═══════════════════════════════════════════════════════

-- marketing_consent už existuje v profiles, ale přidáme IF NOT EXISTS pro jistotu
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS marketing_consent boolean DEFAULT false;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS marketing_consent_at timestamptz;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS preferred_channel text DEFAULT 'sms';
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS phone_e164 text;

-- ═══════════════════════════════════════════════════════
-- 6. REALTIME — přidej message_log a broadcast_campaigns
-- ═══════════════════════════════════════════════════════

DO $$
BEGIN
  -- message_log
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'message_log'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE message_log;
  END IF;

  -- broadcast_campaigns
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'broadcast_campaigns'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE broadcast_campaigns;
  END IF;
EXCEPTION
  WHEN OTHERS THEN NULL; -- Ignoruj pokud realtime publication neexistuje
END $$;

-- ═══════════════════════════════════════════════════════
-- HOTOVO
-- ═══════════════════════════════════════════════════════
