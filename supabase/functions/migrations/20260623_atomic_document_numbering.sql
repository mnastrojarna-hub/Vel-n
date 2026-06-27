-- =============================================================================
-- MIGRACE 2026-06-23 (#11): Atomické číslování dokladů — konec duplicit
--
-- Kontext (bug report 2026-06-23):
--   Duplicitní číslo dobropisu DB-2026-0001 (2× různé částky). Příčina: číslo
--   se generovalo neatomicky `SELECT MAX(seq)+1` na více místech (process-refund
--   3×, KF trigger, generate-invoice) bez DB-unikátnosti → souběh = duplicita.
--
-- Řešení:
--   1) Tabulka-čítač `document_number_counters` (per prefix+rok).
--   2) Fce `next_document_number(prefix)` — atomicky (row-lock) přidělí další
--      číslo. Při KAŽDÉM volání dorovná čítač na živé MAX faktur té řady, takže
--      nemůže vrátit nižší číslo než stávající `MAX+1` v dosud nepřepsaných edge
--      funkcích (bezpečná koexistence, než se i ony přepíšou na tuto fci).
--   3) UNIQUE index na `invoices.number` jako pojistka proti duplicitám.
--      (Před aplikací byly vyřešeny stávající duplicity — viz report = testovací.)
-- =============================================================================

CREATE TABLE IF NOT EXISTS document_number_counters (
  prefix   text NOT NULL,
  year     int  NOT NULL,
  last_seq int  NOT NULL DEFAULT 0,
  PRIMARY KEY (prefix, year)
);

CREATE OR REPLACE FUNCTION next_document_number(p_prefix text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_year int := EXTRACT(YEAR FROM CURRENT_DATE)::int;
  v_seq int;
  v_live_max int;
BEGIN
  INSERT INTO document_number_counters (prefix, year, last_seq)
  VALUES (p_prefix, v_year, 0)
  ON CONFLICT (prefix, year) DO NOTHING;

  SELECT COALESCE(MAX(CAST(SUBSTRING(number FROM '-(\d+)$') AS int)), 0)
    INTO v_live_max
    FROM invoices WHERE number LIKE p_prefix||'-'||v_year||'-%';

  UPDATE document_number_counters                 -- row-lock serializuje souběh
     SET last_seq = GREATEST(last_seq, v_live_max) + 1
   WHERE prefix = p_prefix AND year = v_year
  RETURNING last_seq INTO v_seq;

  RETURN p_prefix||'-'||v_year||'-'||LPAD(v_seq::text, 4, '0');
END; $$;

GRANT EXECUTE ON FUNCTION next_document_number(text) TO authenticated, service_role;

-- Pojistka proti duplicitám (NULL number je povolen vícekrát — Postgres NULL distinct)
CREATE UNIQUE INDEX IF NOT EXISTS invoices_number_unique ON invoices (number);
