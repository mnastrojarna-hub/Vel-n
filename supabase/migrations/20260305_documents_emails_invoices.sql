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
  slug text NOT NULL UNIQUE,
  name text NOT NULL,
  type text NOT NULL DEFAULT 'contract'
    CHECK (type IN ('contract', 'protocol', 'terms', 'invoice', 'damage_protocol')),
  content text,
  pdf_template_path text,
  variables text[] DEFAULT '{}',
  description text,
  active boolean NOT NULL DEFAULT true,
  version integer NOT NULL DEFAULT 1,
  updated_by uuid REFERENCES admin_users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_document_templates_slug ON document_templates(slug);

ALTER TABLE document_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS document_templates_admin ON document_templates;
CREATE POLICY document_templates_admin ON document_templates
  FOR ALL USING (is_admin());

DROP TRIGGER IF EXISTS trg_document_templates_updated ON document_templates;
CREATE TRIGGER trg_document_templates_updated
  BEFORE UPDATE ON document_templates
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Doplnění sloupců pokud tabulka už existovala
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name = 'document_templates' AND column_name = 'pdf_template_path'
  ) THEN
    ALTER TABLE document_templates ADD COLUMN pdf_template_path text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name = 'document_templates' AND column_name = 'version'
  ) THEN
    ALTER TABLE document_templates ADD COLUMN version integer NOT NULL DEFAULT 1;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name = 'document_templates' AND column_name = 'updated_by'
  ) THEN
    ALTER TABLE document_templates ADD COLUMN updated_by uuid REFERENCES admin_users(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name = 'document_templates' AND column_name = 'variables'
  ) THEN
    ALTER TABLE document_templates ADD COLUMN variables text[] DEFAULT '{}';
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════
-- 3. GENERATED_DOCUMENTS
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS generated_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid REFERENCES bookings(id) ON DELETE SET NULL,
  customer_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  template_id uuid REFERENCES document_templates(id) ON DELETE SET NULL,
  name text NOT NULL,
  type text NOT NULL,
  file_path text,
  content_html text,
  metadata jsonb NOT NULL DEFAULT '{}',
  signed boolean NOT NULL DEFAULT false,
  signature_data text,
  signed_at timestamptz,
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
CREATE SEQUENCE IF NOT EXISTS invoice_number_seq START WITH 20260001;

CREATE TABLE IF NOT EXISTS invoices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_number text NOT NULL UNIQUE
    DEFAULT ('MG-' || nextval('invoice_number_seq')::text),
  type text NOT NULL DEFAULT 'proforma'
    CHECK (type IN ('proforma', 'final', 'shop_proforma', 'shop_final')),
  booking_id uuid REFERENCES bookings(id) ON DELETE SET NULL,
  order_id uuid,
  customer_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  subtotal numeric(10,2) NOT NULL DEFAULT 0,
  discount numeric(10,2) NOT NULL DEFAULT 0,
  total numeric(10,2) NOT NULL DEFAULT 0,
  currency text NOT NULL DEFAULT 'CZK',
  status text NOT NULL DEFAULT 'issued'
    CHECK (status IN ('draft', 'issued', 'paid', 'cancelled', 'refunded')),
  paid_at timestamptz,
  seller_info jsonb NOT NULL DEFAULT '{}',
  buyer_info jsonb NOT NULL DEFAULT '{}',
  items jsonb NOT NULL DEFAULT '[]',
  file_path text,
  content_html text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_invoices_booking ON invoices(booking_id);
CREATE INDEX IF NOT EXISTS idx_invoices_customer ON invoices(customer_id);
CREATE INDEX IF NOT EXISTS idx_invoices_type ON invoices(type);
CREATE INDEX IF NOT EXISTS idx_invoices_status ON invoices(status);
CREATE INDEX IF NOT EXISTS idx_invoices_number ON invoices(invoice_number);

ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS invoices_admin ON invoices;
CREATE POLICY invoices_admin ON invoices
  FOR ALL USING (is_admin());

DROP POLICY IF EXISTS invoices_customer_select ON invoices;
CREATE POLICY invoices_customer_select ON invoices
  FOR SELECT USING (customer_id = auth.uid());

DROP TRIGGER IF EXISTS trg_invoices_updated ON invoices;
CREATE TRIGGER trg_invoices_updated
  BEFORE UPDATE ON invoices
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

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
  customer_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  subject text,
  unread_count integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_message_threads_customer ON message_threads(customer_id);

ALTER TABLE message_threads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS message_threads_admin ON message_threads;
CREATE POLICY message_threads_admin ON message_threads
  FOR ALL USING (is_admin());

DROP POLICY IF EXISTS message_threads_customer_select ON message_threads;
CREATE POLICY message_threads_customer_select ON message_threads
  FOR SELECT USING (customer_id = auth.uid());

DROP TRIGGER IF EXISTS trg_message_threads_updated ON message_threads;
CREATE TRIGGER trg_message_threads_updated
  BEFORE UPDATE ON message_threads
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ═══════════════════════════════════════════════════════
-- 7. MESSAGES
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id uuid NOT NULL REFERENCES message_threads(id) ON DELETE CASCADE,
  sender_id uuid,
  content text NOT NULL,
  channel text NOT NULL DEFAULT 'system'
    CHECK (channel IN ('system', 'admin', 'customer')),
  read boolean NOT NULL DEFAULT false,
  metadata jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_messages_thread ON messages(thread_id);
CREATE INDEX IF NOT EXISTS idx_messages_read ON messages(read) WHERE read = false;

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
    channel = 'customer'
    AND thread_id IN (SELECT id FROM message_threads WHERE customer_id = auth.uid())
  );

-- Trigger: inkrementace unread_count při nové nepřečtené zprávě
CREATE OR REPLACE FUNCTION increment_unread_count()
RETURNS trigger AS $$
BEGIN
  IF NEW.read = false AND NEW.channel IN ('system', 'admin') THEN
    UPDATE message_threads
    SET unread_count = unread_count + 1,
        updated_at = now()
    WHERE id = NEW.thread_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_messages_unread ON messages;
CREATE TRIGGER trg_messages_unread
  AFTER INSERT ON messages
  FOR EACH ROW EXECUTE FUNCTION increment_unread_count();

-- ═══════════════════════════════════════════════════════
-- 8. MESSAGE_TEMPLATES
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS message_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  content text NOT NULL,
  category text NOT NULL DEFAULT 'general',
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
INSERT INTO document_templates (slug, name, type, description, variables, content) VALUES
  (
    'rental_contract',
    'Smlouva o pronájmu motocyklu',
    'contract',
    'Generována automaticky při potvrzení rezervace. PDF se nahraje přes admin.',
    ARRAY['customer_name','customer_email','customer_phone','customer_address','moto_model','moto_spz','start_date','end_date','total_price','deposit','pickup_location','booking_number','contract_date','company_name','company_ico'],
    NULL
  ),
  (
    'handover_protocol',
    'Předávací protokol',
    'protocol',
    'Generován při předání motorky zákazníkovi. Obsahuje stav motorky, foto, km.',
    ARRAY['customer_name','moto_model','moto_spz','start_date','km_start','fuel_level','damage_notes','booking_number','handover_date'],
    NULL
  ),
  (
    'vop',
    'Obchodní podmínky',
    'terms',
    'Všeobecné obchodní podmínky pronájmu motorek MotoGo24.',
    ARRAY['company_name','company_ico','company_address'],
    NULL
  ),
  (
    'damage_protocol',
    'Protokol o zjištěném poškození při vrácení',
    'damage_protocol',
    'Generován při vrácení motorky pokud je zjištěno poškození.',
    ARRAY['customer_name','moto_model','moto_spz','booking_number','return_date','km_end','damage_description','estimated_cost'],
    NULL
  ),
  (
    'invoice_template',
    'Šablona faktury',
    'invoice',
    'HTML šablona pro generování faktur (zálohových i konečných).',
    ARRAY['invoice_number','invoice_date','due_date','seller_name','seller_ico','seller_address','seller_bank','buyer_name','buyer_address','buyer_ico','items','subtotal','discount','total','currency','notes'],
    NULL
  )
ON CONFLICT (slug) DO NOTHING;

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
