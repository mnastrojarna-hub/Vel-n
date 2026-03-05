-- =====================================================
-- MotoGo24 Velín — Kompletní SQL migrace
-- Dokumenty, E-maily, Faktury, Zprávy, Nastavení
-- ZÁVISÍ NA: 20260305_000_base_tables.sql (admin_users, update_updated_at)
-- Spustit v Supabase SQL Editoru — idempotentní
-- =====================================================

-- ═══════════════════════════════════════════════════════
-- 1. EMAIL_TEMPLATES
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS email_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  name text NOT NULL,
  subject text NOT NULL DEFAULT '',
  body_html text NOT NULL DEFAULT '',
  body_text text,
  variables text[] DEFAULT '{}',
  description text,
  active boolean NOT NULL DEFAULT true,
  updated_by uuid REFERENCES admin_users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_email_templates_slug ON email_templates(slug);

ALTER TABLE email_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS email_templates_admin ON email_templates;
CREATE POLICY email_templates_admin ON email_templates
  FOR ALL USING (is_admin());

DROP TRIGGER IF EXISTS trg_email_templates_updated ON email_templates;
CREATE TRIGGER trg_email_templates_updated
  BEFORE UPDATE ON email_templates
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ═══════════════════════════════════════════════════════
-- 2. DOCUMENT_TEMPLATES
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS document_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type text NOT NULL,
  name text NOT NULL,
  html_content text NOT NULL,
  variables jsonb DEFAULT '[]'::jsonb,
  version integer DEFAULT 1,
  status text NOT NULL DEFAULT 'draft',
  updated_by uuid REFERENCES admin_users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE document_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS document_templates_admin ON document_templates;
CREATE POLICY document_templates_admin ON document_templates
  FOR ALL USING (is_admin());

DROP TRIGGER IF EXISTS trg_document_templates_updated ON document_templates;
CREATE TRIGGER trg_document_templates_updated
  BEFORE UPDATE ON document_templates
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Tabulka document_templates již existuje s těmito sloupci:
-- id, type, name, html_content, variables (jsonb), version, status, updated_by, created_at, updated_at

-- ═══════════════════════════════════════════════════════
-- 3. GENERATED_DOCUMENTS
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS generated_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id uuid REFERENCES document_templates(id) ON DELETE SET NULL,
  booking_id uuid REFERENCES bookings(id) ON DELETE SET NULL,
  customer_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  filled_data jsonb,
  pdf_path text,
  generated_by uuid REFERENCES admin_users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_generated_documents_booking ON generated_documents(booking_id);
CREATE INDEX IF NOT EXISTS idx_generated_documents_customer ON generated_documents(customer_id);

ALTER TABLE generated_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS generated_documents_admin ON generated_documents;
CREATE POLICY generated_documents_admin ON generated_documents
  FOR ALL USING (is_admin());

DROP POLICY IF EXISTS generated_documents_customer_select ON generated_documents;
CREATE POLICY generated_documents_customer_select ON generated_documents
  FOR SELECT USING (customer_id = auth.uid());

-- ═══════════════════════════════════════════════════════
-- 4. INVOICES
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS invoices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  number text NOT NULL,
  type text NOT NULL,
  customer_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  supplier_id uuid,
  booking_id uuid REFERENCES bookings(id) ON DELETE SET NULL,
  issue_date date NOT NULL,
  due_date date NOT NULL,
  paid_date date,
  subtotal numeric NOT NULL,
  tax_amount numeric NOT NULL,
  total numeric NOT NULL,
  status text NOT NULL DEFAULT 'draft',
  pdf_path text,
  items jsonb DEFAULT '[]'::jsonb,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_invoices_booking ON invoices(booking_id);
CREATE INDEX IF NOT EXISTS idx_invoices_customer ON invoices(customer_id);
CREATE INDEX IF NOT EXISTS idx_invoices_type ON invoices(type);
CREATE INDEX IF NOT EXISTS idx_invoices_status ON invoices(status);

ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS invoices_admin ON invoices;
CREATE POLICY invoices_admin ON invoices
  FOR ALL USING (is_admin());

DROP POLICY IF EXISTS invoices_customer_select ON invoices;
CREATE POLICY invoices_customer_select ON invoices
  FOR SELECT USING (customer_id = auth.uid());

-- ═══════════════════════════════════════════════════════
-- 5. SENT_EMAILS
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS sent_emails (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_slug text,
  recipient_email text NOT NULL,
  recipient_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  booking_id uuid REFERENCES bookings(id) ON DELETE SET NULL,
  subject text NOT NULL,
  body_html text,
  attachments jsonb NOT NULL DEFAULT '[]',
  status text NOT NULL DEFAULT 'sent'
    CHECK (status IN ('queued', 'sent', 'failed', 'bounced')),
  error_message text,
  provider_id text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sent_emails_recipient ON sent_emails(recipient_id);
CREATE INDEX IF NOT EXISTS idx_sent_emails_booking ON sent_emails(booking_id);
CREATE INDEX IF NOT EXISTS idx_sent_emails_template ON sent_emails(template_slug);
CREATE INDEX IF NOT EXISTS idx_sent_emails_created ON sent_emails(created_at);

ALTER TABLE sent_emails ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS sent_emails_admin ON sent_emails;
CREATE POLICY sent_emails_admin ON sent_emails
  FOR ALL USING (is_admin());

-- ═══════════════════════════════════════════════════════
-- 6. MESSAGE_THREADS
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS message_threads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid REFERENCES profiles(id) ON DELETE CASCADE,
  channel text NOT NULL,
  status text NOT NULL DEFAULT 'open',
  assigned_admin uuid,
  subject text,
  last_message_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_message_threads_customer ON message_threads(customer_id);

ALTER TABLE message_threads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS message_threads_admin ON message_threads;
CREATE POLICY message_threads_admin ON message_threads
  FOR ALL USING (is_admin());

DROP POLICY IF EXISTS message_threads_customer_select ON message_threads;
CREATE POLICY message_threads_customer_select ON message_threads
  FOR SELECT USING (customer_id = auth.uid());

-- ═══════════════════════════════════════════════════════
-- 7. MESSAGES
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id uuid REFERENCES message_threads(id) ON DELETE CASCADE,
  direction text NOT NULL,
  sender_name text,
  content text NOT NULL,
  attachments text[] DEFAULT '{}',
  read_at timestamptz,
  ai_suggested_reply text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_messages_thread ON messages(thread_id);

ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS messages_admin ON messages;
CREATE POLICY messages_admin ON messages
  FOR ALL USING (is_admin());

DROP POLICY IF EXISTS messages_customer_select ON messages;
CREATE POLICY messages_customer_select ON messages
  FOR SELECT USING (
    thread_id IN (SELECT id FROM message_threads WHERE customer_id = auth.uid())
  );

DROP POLICY IF EXISTS messages_customer_insert ON messages;
CREATE POLICY messages_customer_insert ON messages
  FOR INSERT WITH CHECK (
    direction = 'customer'
    AND thread_id IN (SELECT id FROM message_threads WHERE customer_id = auth.uid())
  );

-- ═══════════════════════════════════════════════════════
-- 8. MESSAGE_TEMPLATES
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS message_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  content text NOT NULL,
  category text,
  variables text[] DEFAULT '{}',
  language text DEFAULT 'cs',
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE message_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS message_templates_admin ON message_templates;
CREATE POLICY message_templates_admin ON message_templates
  FOR ALL USING (is_admin());

-- ═══════════════════════════════════════════════════════
-- 9. APP_SETTINGS
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS app_settings (
  key text PRIMARY KEY,
  value jsonb NOT NULL DEFAULT '{}',
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS app_settings_admin ON app_settings;
CREATE POLICY app_settings_admin ON app_settings
  FOR ALL USING (is_admin());

DROP POLICY IF EXISTS app_settings_read ON app_settings;
CREATE POLICY app_settings_read ON app_settings
  FOR SELECT USING (true);

DROP TRIGGER IF EXISTS trg_app_settings_updated ON app_settings;
CREATE TRIGGER trg_app_settings_updated
  BEFORE UPDATE ON app_settings
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ═══════════════════════════════════════════════════════
-- 10. SEED: app_settings
-- ═══════════════════════════════════════════════════════
INSERT INTO app_settings (key, value) VALUES
  ('company_info', '{
    "name": "Bc. Petra Semorádová",
    "ico": "21874263",
    "dic": null,
    "vat_payer": false,
    "address": "Mezná 9, 393 01 Mezná",
    "bank_account": "670100-2225851630/6210",
    "phone": "+420 774 256 271",
    "email": "info@motogo24.cz",
    "web": "https://motogo24.cz",
    "instagram": "moto.go24",
    "facebook": "MotoGo24"
  }'::jsonb),
  ('business_card_html', '"<div style=\"border-top:2px solid #74FB71;margin-top:24px;padding-top:16px;\"><strong>MotoGo24 \u2013 Půjčovna motorek</strong><br>Bc. Petra Semorádová, IČO: 21874263<br>+420 774 256 271 · info@motogo24.cz<br>Instagram: <a href=\"https://instagram.com/moto.go24\">moto.go24</a> · Facebook: <a href=\"https://facebook.com/MotoGo24\">MotoGo24</a></div>"'::jsonb),
  ('google_review_link', '"https://g.page/motogo24/review"'::jsonb),
  ('facebook_review_link', '"https://facebook.com/MotoGo24/reviews"'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- ═══════════════════════════════════════════════════════
-- 11. SEED: email_templates
-- ═══════════════════════════════════════════════════════
INSERT INTO email_templates (slug, name, subject, description, variables, body_html) VALUES
  (
    'booking_confirmed',
    'Potvrzení rezervace',
    'Vaše rezervace č. {{booking_number}} motocyklu u MotoGo24 je potvrzena',
    'Odesláno zákazníkovi po potvrzení rezervace adminem.',
    ARRAY['booking_number','customer_name','moto_model','start_date','end_date','total_price','pickup_location','business_card'],
    '<p>Šablona bude nahrána přes admin rozhraní.</p>'
  ),
  (
    'booking_abandoned',
    'Nedokončená rezervace',
    'Dokončete svou rezervaci č. {{booking_number}} motocyklu u MotoGo24',
    'Odesláno automaticky pokud zákazník nedokončí objednávku do 4 hodin.',
    ARRAY['booking_number','customer_name','moto_model','resume_link','business_card'],
    '<p>Šablona bude nahrána přes admin rozhraní.</p>'
  ),
  (
    'booking_cancelled',
    'Storno rezervace',
    'Vaše rezervace č. {{booking_number}} motocyklu u MotoGo24 byla úspěšně stornována',
    'Odesláno po zrušení rezervace (admin, zákazník, nebo systém).',
    ARRAY['booking_number','customer_name','moto_model','start_date','end_date','cancellation_reason','resume_link','business_card'],
    '<p>Šablona bude nahrána přes admin rozhraní.</p>'
  ),
  (
    'booking_completed',
    'Poděkování po rezervaci',
    'Děkujeme za využití služeb MotoGo24',
    'Odesláno po vrácení motorky — výzva k recenzi + slevový kód.',
    ARRAY['customer_name','moto_model','google_review_link','facebook_review_link','discount_code','business_card'],
    '<p>Šablona bude nahrána přes admin rozhraní.</p>'
  ),
  (
    'voucher_purchased',
    'Dárkový poukaz',
    'Váš dárkový poukaz od MotoGo24',
    'Odesláno po zakoupení dárkového poukazu.',
    ARRAY['customer_name','voucher_code','voucher_amount','voucher_valid_until','business_card'],
    '<p>Šablona bude nahrána přes admin rozhraní.</p>'
  )
ON CONFLICT (slug) DO NOTHING;

-- ═══════════════════════════════════════════════════════
-- 12. SEED: document_templates
-- ═══════════════════════════════════════════════════════
-- document_templates seed — tabulka již existuje, seed přeskočen
-- Šablony se spravují přes admin rozhraní

-- ═══════════════════════════════════════════════════════
-- 13. SEED: message_templates
-- ═══════════════════════════════════════════════════════
INSERT INTO message_templates (name, content, category) VALUES
  (
    'Potvrzení přijetí',
    'Dobrý den, děkujeme za vaši zprávu. Vaši žádost jsme přijali a budeme se jí zabývat v co nejkratší době.',
    'general'
  ),
  (
    'Motorka připravena',
    'Dobrý den, vaše motorka je připravena k vyzvednutí. Těšíme se na vás!',
    'booking'
  ),
  (
    'Upomínka vrácení',
    'Dobrý den, připomínáme, že termín vrácení motorky se blíží. Prosíme o včasné vrácení dle smlouvy.',
    'booking'
  ),
  (
    'SOS odpověď',
    'Dobrý den, vaše hlášení jsme přijali. Technik se s vámi spojí do 15 minut. V případě nouze volejte +420 774 256 271.',
    'sos'
  ),
  (
    'Storno potvrzeno',
    'Dobrý den, vaše rezervace byla úspěšně stornována. Záloha bude vrácena dle storno podmínek.',
    'booking'
  ),
  (
    'Děkujeme za recenzi',
    'Dobrý den, moc děkujeme za vaši recenzi! Vaše zpětná vazba nám pomáhá se zlepšovat.',
    'general'
  )
ON CONFLICT DO NOTHING;
