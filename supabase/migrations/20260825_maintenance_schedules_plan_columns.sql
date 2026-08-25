-- Servisní plány: chybějící sloupce na maintenance_schedules.
-- Formulář „Pravidelný servis / kontrola" (Velín → Servis → Naplánovat servis)
-- posílá při KAŽDÉM insertu plánu sloupec preferred_days (a u typu
-- „po X rezervacích" navíc interval_reservations). Sloupce v živé DB chyběly,
-- takže každé vytvoření plánu spadlo na 42703 (column does not exist) a chyba
-- se v UI nezobrazila — motorky proto nemohly mít další (dílčí) servisní plány.
-- Idempotentní; žádná data se nemění.

ALTER TABLE public.maintenance_schedules
  ADD COLUMN IF NOT EXISTS preferred_days integer[] DEFAULT NULL;

COMMENT ON COLUMN public.maintenance_schedules.preferred_days IS
  'Preferované dny v týdnu pro naplánování servisu (0=Po … 6=Ne), z formuláře Pravidelný servis';

ALTER TABLE public.maintenance_schedules
  ADD COLUMN IF NOT EXISTS interval_reservations integer DEFAULT NULL;

COMMENT ON COLUMN public.maintenance_schedules.interval_reservations IS
  'Interval plánu v počtu rezervací (schedule_type=reservation_interval)';
