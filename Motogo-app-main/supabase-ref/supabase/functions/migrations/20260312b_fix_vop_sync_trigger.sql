-- Oprava sync triggeru: správné mapování VOP typu
-- Dříve VOP padalo do ELSE větve jako 'contract' + 'Dokument.pdf'

CREATE OR REPLACE FUNCTION sync_generated_doc_to_documents()
RETURNS TRIGGER AS $$
DECLARE
  v_user_id uuid;
  v_template_type text;
  v_doc_type text;
  v_file_name text;
BEGIN
  SELECT user_id INTO v_user_id
  FROM bookings WHERE id = NEW.booking_id;
  IF v_user_id IS NULL THEN
    v_user_id := NEW.customer_id;
  END IF;
  IF v_user_id IS NULL THEN RETURN NEW; END IF;

  IF NEW.template_id IS NOT NULL THEN
    SELECT type INTO v_template_type
    FROM document_templates WHERE id = NEW.template_id;
  END IF;

  IF v_template_type = 'rental_contract' OR v_template_type ILIKE '%contract%' THEN
    v_doc_type := 'contract';
    v_file_name := 'Smlouva o pronájmu.pdf';
  ELSIF v_template_type = 'handover_protocol' OR v_template_type ILIKE '%protocol%' THEN
    v_doc_type := 'protocol';
    v_file_name := 'Předávací protokol.pdf';
  ELSIF v_template_type = 'vop' THEN
    v_doc_type := 'vop';
    v_file_name := 'Všeobecné obchodní podmínky.pdf';
  ELSE
    v_doc_type := 'contract';
    v_file_name := 'Dokument.pdf';
  END IF;

  INSERT INTO documents (booking_id, user_id, type, file_name, file_path)
  SELECT NEW.booking_id, v_user_id, v_doc_type, v_file_name,
    COALESCE(NEW.pdf_path, 'generated/' || NEW.id || '.html')
  WHERE NOT EXISTS (
    SELECT 1 FROM documents
    WHERE booking_id = NEW.booking_id
      AND user_id = v_user_id
      AND type = v_doc_type
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
