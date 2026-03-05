-- =====================================================
-- Velín v2.2 — Email templates, Document templates ext,
-- Invoices, Sent emails, Generated documents
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
CREATE POLICY IF NOT EXISTS email_templates_admin ON email_templates
  FOR ALL USING (auth.uid() IN (SELECT id FROM admin_users));

-- Seed šablony
INSERT INTO email_templates (slug, name, subject, description, variables, body_html) VALUES
  ('booking_confirmed', 'Potvrzení rezervace', 'Vaše rezervace #{{booking_number}} byla potvrzena', 'Odesláno zákazníkovi po potvrzení rezervace', ARRAY['booking_number','customer_name','moto_model','start_date','end_date','total_price','pickup_location','business_card'], '<h2>Rezervace potvrzena</h2><p>Dobrý den {{customer_name}},</p><p>Vaše rezervace motorky {{moto_model}} od {{start_date}} do {{end_date}} byla potvrzena.</p><p>Celková cena: {{total_price}}</p><p>Místo vyzvednutí: {{pickup_location}}</p>{{business_card}}'),
  ('booking_abandoned', 'Nedokončená rezervace', 'Dokončete svou rezervaci — {{moto_model}}', 'Odesláno pokud zákazník nedokončí objednávku', ARRAY['customer_name','moto_model','resume_link','business_card'], '<h2>Nedokončená rezervace</h2><p>Dobrý den {{customer_name}},</p><p>Všimli jsme si, že jste nedokončili rezervaci motorky {{moto_model}}.</p><p><a href="{{resume_link}}">Dokončit rezervaci</a></p>{{business_card}}'),
  ('booking_cancelled', 'Storno rezervace', 'Vaše rezervace byla zrušena', 'Odesláno po zrušení rezervace', ARRAY['customer_name','booking_number','moto_model','start_date','end_date','resume_link','business_card'], '<h2>Rezervace zrušena</h2><p>Dobrý den {{customer_name}},</p><p>Vaše rezervace #{{booking_number}} na motorku {{moto_model}} ({{start_date}} – {{end_date}}) byla zrušena.</p><p><a href="{{resume_link}}">Obnovit rezervaci</a></p>{{business_card}}'),
  ('booking_completed', 'Po skončení rezervace', 'Děkujeme za jízdu! Ohodnoťte nás', 'Odesláno po vrácení motorky', ARRAY['customer_name','moto_model','google_review_link','facebook_review_link','discount_code','business_card'], '<h2>Děkujeme!</h2><p>Dobrý den {{customer_name}},</p><p>Děkujeme za pronájem motorky {{moto_model}}. Budeme rádi za vaši recenzi:</p><p><a href="{{google_review_link}}">Google</a> | <a href="{{facebook_review_link}}">Facebook</a></p><p>Jako poděkování: slevový kód <strong>{{discount_code}}</strong> na příští pronájem.</p>{{business_card}}'),
  ('voucher_purchased', 'Nákup poukazu', 'Váš poukaz {{voucher_code}} je připraven', 'Odesláno po nákupu poukazu', ARRAY['customer_name','voucher_code','voucher_amount','voucher_valid_until','business_card'], '<h2>Poukaz připraven</h2><p>Dobrý den {{customer_name}},</p><p>Váš poukaz <strong>{{voucher_code}}</strong> v hodnotě {{voucher_amount}} je platný do {{voucher_valid_until}}.</p>{{business_card}}')
ON CONFLICT (slug) DO NOTHING;

-- ═══════════════════════════════════════════════════════
-- 2. DOCUMENT_TEMPLATES — doplnění sloupců
-- ═══════════════════════════════════════════════════════
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'document_templates' AND column_name = 'pdf_template_path') THEN
    ALTER TABLE document_templates ADD COLUMN pdf_template_path text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'document_templates' AND column_name = 'version') THEN
    ALTER TABLE document_templates ADD COLUMN version integer NOT NULL DEFAULT 1;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'document_templates' AND column_name = 'updated_by') THEN
    ALTER TABLE document_templates ADD COLUMN updated_by uuid REFERENCES admin_users(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'document_templates' AND column_name = 'variables') THEN
    ALTER TABLE document_templates ADD COLUMN variables text[] DEFAULT '{}';
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════
-- 3. GENERATED_DOCUMENTS
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS generated_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid REFERENCES bookings(id) ON DELETE CASCADE,
  customer_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  template_id uuid REFERENCES document_templates(id) ON DELETE SET NULL,
  name text,
  type text,
  file_path text,
  content_html text,
  metadata jsonb,
  signed boolean NOT NULL DEFAULT false,
  signature_data text,
  signed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_generated_documents_booking ON generated_documents(booking_id);
ALTER TABLE generated_documents ENABLE ROW LEVEL SECURITY;
CREATE POLICY IF NOT EXISTS generated_documents_admin ON generated_documents
  FOR ALL USING (auth.uid() IN (SELECT id FROM admin_users));

-- ═══════════════════════════════════════════════════════
-- 4. INVOICES
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS invoices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_number text UNIQUE,
  type text NOT NULL DEFAULT 'proforma'
    CHECK (type IN ('proforma', 'final', 'shop_proforma', 'shop_final')),
  booking_id uuid REFERENCES bookings(id) ON DELETE SET NULL,
  order_id uuid,
  customer_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  subtotal numeric(10,2) NOT NULL DEFAULT 0,
  discount numeric(10,2) NOT NULL DEFAULT 0,
  total numeric(10,2) NOT NULL DEFAULT 0,
  currency text NOT NULL DEFAULT 'CZK',
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'issued', 'paid', 'cancelled', 'refunded')),
  paid_at timestamptz,
  seller_info jsonb,
  buyer_info jsonb,
  items jsonb NOT NULL DEFAULT '[]',
  file_path text,
  content_html text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_invoices_booking ON invoices(booking_id);
CREATE INDEX IF NOT EXISTS idx_invoices_customer ON invoices(customer_id);
CREATE INDEX IF NOT EXISTS idx_invoices_status ON invoices(status);
CREATE INDEX IF NOT EXISTS idx_invoices_number ON invoices(invoice_number);

ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
CREATE POLICY IF NOT EXISTS invoices_admin ON invoices
  FOR ALL USING (auth.uid() IN (SELECT id FROM admin_users));

DROP TRIGGER IF EXISTS trg_invoices_updated ON invoices;
CREATE TRIGGER trg_invoices_updated
  BEFORE UPDATE ON invoices FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ═══════════════════════════════════════════════════════
-- 5. SENT_EMAILS
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS sent_emails (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_slug text,
  recipient_email text NOT NULL,
  recipient_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  booking_id uuid REFERENCES bookings(id) ON DELETE SET NULL,
  subject text,
  body_html text,
  attachments jsonb,
  status text NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'sent', 'failed', 'bounced')),
  error_message text,
  provider_id text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sent_emails_template ON sent_emails(template_slug);
CREATE INDEX IF NOT EXISTS idx_sent_emails_recipient ON sent_emails(recipient_email);
CREATE INDEX IF NOT EXISTS idx_sent_emails_created ON sent_emails(created_at);

ALTER TABLE sent_emails ENABLE ROW LEVEL SECURITY;
CREATE POLICY IF NOT EXISTS sent_emails_admin ON sent_emails
  FOR ALL USING (auth.uid() IN (SELECT id FROM admin_users));

-- ═══════════════════════════════════════════════════════
-- 6. APP_SETTINGS
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS app_settings (
  key text PRIMARY KEY,
  value jsonb NOT NULL DEFAULT '{}',
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY IF NOT EXISTS app_settings_admin ON app_settings
  FOR ALL USING (auth.uid() IN (SELECT id FROM admin_users));

INSERT INTO app_settings (key, value) VALUES
  ('business_card_html', '"<div style=\"border-top:2px solid #74FB71;margin-top:24px;padding-top:16px;\"><strong>MotoGo24 – Půjčovna motorek</strong><br>+420 774 256 271 · info@motogo24.cz</div>"'),
  ('company_info', '{"name":"MotoGo24 s.r.o.","ico":"12345678","dic":"CZ12345678","address":"Mezná 9, 393 01 Mezná"}'),
  ('google_review_link', '"https://g.page/motogo24/review"'),
  ('facebook_review_link', '"https://facebook.com/MotoGo24/reviews"')
ON CONFLICT (key) DO NOTHING;

-- ═══════════════════════════════════════════════════════
-- 7. PROMO_CODES — ensure table + status column exist
-- ═══════════════════════════════════════════════════════
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'promo_codes' AND column_name = 'status') THEN
    ALTER TABLE promo_codes ADD COLUMN status text NOT NULL DEFAULT 'active';
  END IF;
END $$;
