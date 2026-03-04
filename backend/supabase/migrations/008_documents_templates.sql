-- MotoGo24: Documents & Templates
-- Šablony smluv, protokolů, faktur + generované dokumenty

CREATE TABLE document_templates (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    type TEXT NOT NULL CHECK (type IN ('smlouva', 'faktura', 'protokol', 'vop', 'dobropis', 'gdpr', 'pojistka')),
    name TEXT NOT NULL,
    html_content TEXT NOT NULL,
    variables JSONB DEFAULT '[]',
    version INT DEFAULT 1,
    status TEXT NOT NULL CHECK (status IN ('active', 'draft', 'archived')) DEFAULT 'draft',
    updated_by UUID,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE generated_documents (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    template_id UUID REFERENCES document_templates(id) ON DELETE SET NULL,
    booking_id UUID REFERENCES bookings(id) ON DELETE SET NULL,
    customer_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    filled_data JSONB,
    pdf_path TEXT,
    generated_by UUID,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ===== TRIGGERY =====

CREATE TRIGGER document_templates_updated_at BEFORE UPDATE ON document_templates
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ===== INDEXY =====

CREATE INDEX idx_document_templates_type ON document_templates(type);
CREATE INDEX idx_document_templates_status ON document_templates(status);
CREATE INDEX idx_generated_documents_template ON generated_documents(template_id);
CREATE INDEX idx_generated_documents_booking ON generated_documents(booking_id);
CREATE INDEX idx_generated_documents_customer ON generated_documents(customer_id);
CREATE INDEX idx_generated_documents_created ON generated_documents(created_at DESC);

-- ===== RLS =====

ALTER TABLE document_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE generated_documents ENABLE ROW LEVEL SECURITY;

-- Šablony: veřejné čtení aktivních
CREATE POLICY "Anyone can view active document templates" ON document_templates
    FOR SELECT USING (status = 'active');

-- Generované dokumenty: zákazník vidí své
CREATE POLICY "Users can view own generated documents" ON generated_documents
    FOR SELECT USING (auth.uid() = customer_id);

COMMENT ON TABLE document_templates IS 'Šablony dokumentů — smlouvy, faktury, protokoly, VOP, GDPR';
COMMENT ON TABLE generated_documents IS 'Vygenerované dokumenty z šablon pro konkrétní rezervace';
