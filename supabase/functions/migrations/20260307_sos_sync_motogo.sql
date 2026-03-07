-- =====================================================
-- MotoGo24 SOS sync migrace
-- Pridava chybejici sloupce pro synchronizaci MotoGo <-> Velin
-- Bezpecne spustit opakovane (idempotentni)
-- =====================================================

-- 1. moto_id na sos_incidents
--    MotoGo appka posila moto_id pri vytvareni incidentu (api.js:483)
--    Umoznuje primo identifikovat motorku bez nutnosti jit pres booking
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sos_incidents' AND column_name = 'moto_id'
  ) THEN
    ALTER TABLE sos_incidents ADD COLUMN moto_id uuid REFERENCES motorcycles(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_sos_incidents_moto ON sos_incidents(moto_id);

-- 2. data (JSONB) na sos_timeline
--    MotoGo zapisuje GPS souradnice a poznamky do timeline zaznamu:
--    - replacement_requested: {note: 'Zakaznik zada nahradni motorku'}
--    - tow_requested: {note: 'Zakaznik zada odtahovou sluzbu'}
--    - location_shared: {latitude, longitude, note: 'GPS: lat, lng'}
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sos_timeline' AND column_name = 'data'
  ) THEN
    ALTER TABLE sos_timeline ADD COLUMN data jsonb;
  END IF;
END $$;
