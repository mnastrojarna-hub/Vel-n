-- SOS Replacement Order: přidání struktury pro objednávku náhradní motorky
-- Zákazník, který zavinil nehodu a chce náhradní moto, musí vybrat motorku, adresu a zaplatit

-- 1. Přidej replacement_data JSONB na sos_incidents
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sos_incidents' AND column_name = 'replacement_data'
  ) THEN
    ALTER TABLE sos_incidents ADD COLUMN replacement_data jsonb DEFAULT NULL;
    COMMENT ON COLUMN sos_incidents.replacement_data IS
      'Structured replacement order: {replacement_moto_id, replacement_model, delivery_address, delivery_city, delivery_note, payment_status (pending/paid/failed), payment_amount, approved_by_admin (bool), approved_at, customer_confirmed_at}';
  END IF;
END $$;

-- 2. Přidej replacement_status pro sledování stavu objednávky náhradní motorky
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sos_incidents' AND column_name = 'replacement_status'
  ) THEN
    ALTER TABLE sos_incidents ADD COLUMN replacement_status text DEFAULT NULL
      CHECK (replacement_status IN ('selecting', 'pending_payment', 'paid', 'admin_review', 'approved', 'dispatched', 'delivered', 'rejected'));
    COMMENT ON COLUMN sos_incidents.replacement_status IS
      'Status of replacement motorcycle order flow';
  END IF;
END $$;
