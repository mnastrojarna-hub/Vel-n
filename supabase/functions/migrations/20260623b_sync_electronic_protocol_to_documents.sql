-- =============================================================================
-- MIGRACE 2026-06-23 (b): Sync ELEKTRONICKÉHO protokolu → documents (appka)
--
-- Elektronický předávací / škodní protokol (ElectronicProtocolModal ve Velíně)
-- se ukládá do `generated_documents` s `template_id = NULL` (není to klasická
-- šablona, HTML se skládá v prohlížeči). Původní `sync_generated_doc_to_documents`
-- odvozoval typ JEN z `document_templates.type` přes `template_id` → u el. protokolu
-- spadl do větve ELSE = `contract`/`Dokument.pdf`, a protože smlouva (type=contract)
-- už existovala, `NOT EXISTS` ho zahodil → el. protokol se zákazníkovi v appce
-- NIKDY nezobrazil.
--
-- Oprava: když `template_id IS NULL`, odvodíme typ z `filled_data->>'_doc_type'`
-- ('handover_protocol' | 'damage_protocol'). Mapování:
--   handover_protocol → documents.type = 'protocol'         (appka už filtruje)
--   damage_protocol   → documents.type = 'protocol_damage'  (appka doplněna)
-- Appka (contractsProvider) zobrazí protokol vedle smlouvy/VOP.
-- =============================================================================

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
  ELSE
    -- El. protokol (bez šablony) → typ z filled_data._doc_type
    v_template_type := NEW.filled_data->>'_doc_type';
  END IF;

  IF v_template_type = 'damage_protocol' THEN
    v_doc_type := 'protocol_damage';
    v_file_name := 'Protokol o poškození.pdf';
  ELSIF v_template_type = 'rental_contract' OR v_template_type ILIKE '%contract%' THEN
    v_doc_type := 'contract';
    v_file_name := 'Smlouva o pronájmu.pdf';
  ELSIF v_template_type = 'handover_protocol' OR v_template_type ILIKE '%protocol%' THEN
    v_doc_type := 'protocol';
    v_file_name := 'Předávací protokol.pdf';
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

-- Trigger zůstává (AFTER INSERT ON generated_documents) — jen těla funkce se mění.
