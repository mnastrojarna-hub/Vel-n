-- =============================================================================
-- 20261112u13_web_editrez_h1_terms.sql — jednotný pojem „Upravit rezervaci“ v nadpisu stránky (QA 2026-10-16)
-- Datová migrace (bez změn schématu). Živé cms_variables (web.layout.*) přebíjejí lang/<jazyk>.php a
-- nadpis stránky se liší od tlačítka, které ji otevírá:
--   de  tlačítko „Reservierung bearbeiten“  → nadpis „Buchung bearbeiten“
--   es  tlačítko „Editar reserva“           → nadpis „Modificar reserva“
--   nl  tlačítko „Reservering bewerken“     → nadpis „Reservering wijzigen“
-- Nadpis (web.layout.editRez.h1) dostane stejné znění jako tlačítko (web.layout.menu.editReservation);
-- cs/en/fr/pl už shodné jsou. Stejné znění má i lang/<jazyk>.php (editRez.h1 = menu.editReservation).
-- Bezpečnost: mění JEN překlad, který má přesně ověřené živé znění; jinak NOTICE a nic.
-- Idempotentní. Bez BEGIN/COMMIT – deploy-sql.yml pouští soubor v jedné transakci (ON_ERROR_STOP).
-- =============================================================================
DO $$
DECLARE
  f record;
  cnt integer;
BEGIN
  FOR f IN SELECT * FROM (VALUES
    ('de', 'Buchung bearbeiten',   'Reservierung bearbeiten'),
    ('es', 'Modificar reserva',    'Editar reserva'),
    ('nl', 'Reservering wijzigen', 'Reservering bewerken')
  ) AS x(lang, old, new)
  LOOP
    UPDATE public.cms_variables
       SET translations = jsonb_set(translations, ARRAY[f.lang], (translations -> f.lang) || jsonb_build_object('value', f.new)),
           updated_at = now()
     WHERE key = 'web.layout.editRez.h1'
       AND jsonb_typeof(translations) = 'object'
       AND jsonb_typeof(translations -> f.lang) = 'object'
       AND translations -> f.lang ->> 'value' = f.old;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    IF cnt = 0 THEN
      RAISE NOTICE 'editRez.h1 [%]: beze změny (už „%“, nebo text ve Velínu mezitím upraven)', f.lang, f.new;
    END IF;
  END LOOP;
END $$;
