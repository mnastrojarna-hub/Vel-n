-- ============================================================================
-- POBOČKA REZERVACE = KDE ZÁKAZNÍK SKUTEČNĚ BYL (zadání majitele 2026-10-10)
--
-- „Velín ukazuje rezervace, které byly reálně v Mezné, pod Velkými Němčicemi,
--  protože jsem přesunul motorky — bere jen aktuální stav motorky.“
--
-- Stav PŘED: sloupec `bookings.branch_id` (FK→branches) existoval, ale nic ho
-- neplnilo (appka, web, Velín, RPC ani triggery) → Velín i AI Copilot
-- přiřazovaly rezervaci k pobočce podle AKTUÁLNÍ pobočky motorky
-- (`motorcycles.branch_id`) a přesun motorky „přestěhoval“ i celou její
-- historii. `snapshot_daily_stats` četl `bookings.branch_id` → vždy 0.
--
-- Nově (pravidlo):
--   * INSERT: pobočka motorky (navazující rezervace `extends_booking_id`
--     a SOS náhrada `replacement_for_booking_id` dědí pobočku původní rezervace);
--   * dokud rezervace NENÍ vyzvednutá (pending/reserved a `picked_up_at` NULL)
--     pobočka následuje motorku — změna motorky i přesun motorky na jinou
--     pobočku (vyzvedává se tam, kde motorka stojí; kódy dveří to dělají stejně);
--   * v okamžiku vyzvednutí / storna / dokončení se pobočka ZMRAZÍ a pozdější
--     přesun motorky ji už nezmění;
--   * zákaznický JWT `branch_id` měnit nesmí (jako `_protect_handover_columns`);
--     admin (Velín) / service role ho ručně opravit smí.
-- Jednorázový backfill historie (jen NULL řádky) — pořadí zdrojů:
--   1. první úspěšná událost dveří kiosku k rezervaci (samoobsluha = fyzické převzetí),
--   2. předávací protokol (`generated_documents`, kiosk `_device_id` → pobočka
--      zařízení; Velín `pickup_location` = adresa pobočky),
--   3. zalogovaný přesun motorky (`admin_audit_log` motorcycle_migrated /
--      `moto_odometer_readings` transfer) BĚHEM pronájmu → pobočka před přesunem,
--   4. poslední řádek `branch_door_codes` rezervace (kódy následují motorku jen
--      do dokončení / storna → pobočka v okamžiku konce),
--   5. první zalogovaný přesun PO vyzvednutí → pobočka před ním,
--   6. záloha: aktuální pobočka motorky.
-- Backfill nebumpne `updated_at` (feed úprav na Dashboardu) ani nezapíše
-- debug_log z `trg_booking_modified_email` (oba triggery vypnuté jen po dobu
-- backfillu v této transakci). Idempotentní (opakované spuštění = no-op).
-- ============================================================================

-- 1) BEFORE trigger na bookings ------------------------------------------------
CREATE OR REPLACE FUNCTION public._booking_set_branch()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_parent    uuid := COALESCE(NEW.extends_booking_id,
                               CASE WHEN NEW.sos_replacement IS TRUE THEN NEW.replacement_for_booking_id END);
  v_priv      boolean := auth.uid() IS NULL OR public.is_admin();
  v_moto_br   uuid;
  v_parent_br uuid;
  v_live_new  boolean := NEW.status IN ('pending', 'reserved') AND NEW.picked_up_at IS NULL;
  v_live_old  boolean;
BEGIN
  SELECT m.branch_id INTO v_moto_br FROM motorcycles m WHERE m.id = NEW.moto_id;
  IF v_parent IS NOT NULL AND v_parent IS DISTINCT FROM NEW.id THEN
    SELECT b.branch_id INTO v_parent_br FROM bookings b WHERE b.id = v_parent;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.branch_id := COALESCE(v_parent_br, v_moto_br, CASE WHEN v_priv THEN NEW.branch_id END);
    RETURN NEW;
  END IF;

  -- Ruční oprava z Velína / service role (backfill) — ponech.
  IF v_priv AND NEW.branch_id IS DISTINCT FROM OLD.branch_id THEN RETURN NEW; END IF;

  NEW.branch_id := OLD.branch_id;   -- zákaznický JWT ani vedlejší změny pobočku nemění
  IF v_parent IS NOT NULL THEN
    NEW.branch_id := COALESCE(OLD.branch_id, v_parent_br, v_moto_br);
    RETURN NEW;
  END IF;

  v_live_old := OLD.status IN ('pending', 'reserved') AND OLD.picked_up_at IS NULL;
  -- Před vyzvednutím + okamžik vyzvednutí / storna: pobočka motorky (pak zmrazená).
  IF v_live_new OR v_live_old THEN
    NEW.branch_id := COALESCE(v_moto_br, OLD.branch_id);
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '_booking_set_branch booking %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public._booking_set_branch() FROM PUBLIC, anon, authenticated;

-- Jméno řadí trigger ZA trg_detect_consecutive_booking (nastaví extends_booking_id)
-- a trg_gate_obsluzna_activation (vrací předčasné →active) — BEFORE triggery
-- běží v abecedním pořadí.
DROP TRIGGER IF EXISTS trg_set_booking_branch ON public.bookings;
CREATE TRIGGER trg_set_booking_branch
  BEFORE INSERT OR UPDATE OF moto_id, status, picked_up_at, branch_id
  ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public._booking_set_branch();

-- 2) Přesun motorky → nevyzvednuté rezervace jdou s ní ------------------------
CREATE OR REPLACE FUNCTION public._booking_branch_follow_moto()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.branch_id IS NULL THEN RETURN NULL; END IF;   -- motorka mimo pobočku: rezervace drží poslední
  UPDATE bookings b
     SET branch_id = NEW.branch_id
   WHERE b.moto_id = NEW.id
     AND b.status IN ('pending', 'reserved')
     AND b.picked_up_at IS NULL
     AND b.extends_booking_id IS NULL
     AND b.sos_replacement IS NOT TRUE
     AND b.branch_id IS DISTINCT FROM NEW.branch_id;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '_booking_branch_follow_moto moto %: %', NEW.id, SQLERRM;
  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public._booking_branch_follow_moto() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_booking_branch_follow_moto ON public.motorcycles;
CREATE TRIGGER trg_booking_branch_follow_moto
  AFTER UPDATE OF branch_id ON public.motorcycles
  FOR EACH ROW WHEN (OLD.branch_id IS DISTINCT FROM NEW.branch_id)
  EXECUTE FUNCTION public._booking_branch_follow_moto();

CREATE INDEX IF NOT EXISTS idx_bookings_branch_id ON public.bookings (branch_id);

-- 3) Backfill historie (jen NULL) --------------------------------------------
ALTER TABLE public.bookings DISABLE TRIGGER bookings_updated_at;
ALTER TABLE public.bookings DISABLE TRIGGER trg_booking_modified_email;

CREATE TEMP TABLE _bb_src ON COMMIT DROP AS
WITH b AS (
  SELECT bk.id, bk.moto_id,
         (bk.status IN ('pending', 'reserved') AND bk.picked_up_at IS NULL) AS live,
         COALESCE(bk.picked_up_at, bk.handover_protocol_filled_at,
                  CASE WHEN bk.status = 'cancelled' THEN LEAST(bk.cancelled_at, bk.start_date) END,
                  bk.start_date) AS t_pick,
         COALESCE(bk.returned_at, bk.actual_return_date, bk.end_date + interval '1 day') AS t_end
    FROM public.bookings bk
   WHERE bk.branch_id IS NULL
     AND bk.extends_booking_id IS NULL
     AND bk.sos_replacement IS NOT TRUE
),
mv AS (   -- zalogované přesuny motorek (komplet od 2026-09-29)
  SELECT a.entity_id AS moto_id, a.created_at AS at,
         NULLIF(a.old_data->>'branch_id', '')::uuid AS from_branch
    FROM public.admin_audit_log a
   WHERE a.action = 'motorcycle_migrated' AND a.old_data ? 'branch_id'
  UNION ALL
  SELECT r.moto_id, r.recorded_at, r.branch_id
    FROM public.moto_odometer_readings r
   WHERE r.kind = 'transfer' AND r.branch_id IS NOT NULL
     AND r.branch_id IS DISTINCT FROM r.to_branch_id
),
p1 AS (   -- první úspěšné otevření dveří kioskem (samoobsluha)
  SELECT DISTINCT ON (e.booking_id) e.booking_id, e.branch_id
    FROM public.branch_door_events e
    JOIN b ON b.id = e.booking_id
   WHERE e.success IS TRUE AND e.branch_id IS NOT NULL
     AND e.kind IN ('motorcycle', 'accessories')
   ORDER BY e.booking_id, e.created_at
),
p2 AS (   -- předávací protokol
  SELECT DISTINCT ON (g.booking_id) g.booking_id, COALESCE(kd.branch_id, ba.id) AS branch_id
    FROM public.generated_documents g
    JOIN b ON b.id = g.booking_id
    LEFT JOIN public.kiosk_devices kd ON kd.id::text = g.filled_data->>'_device_id'
    LEFT JOIN LATERAL (
      SELECT br.id FROM public.branches br
       WHERE NULLIF(btrim(g.filled_data->>'pickup_location'), '') IS NOT NULL
         AND g.filled_data->>'pickup_location' =
             concat_ws(', ', NULLIF(br.address, ''),
                       NULLIF(concat_ws(' ', NULLIF(br.zip, ''), NULLIF(br.city, '')), ''))
       LIMIT 1) ba ON true
   WHERE g.filled_data->>'_doc_type' = 'handover_protocol'
     AND COALESCE(kd.branch_id, ba.id) IS NOT NULL
   ORDER BY g.booking_id, g.created_at
),
p3 AS (   -- první zalogovaný přesun motorky po vyzvednutí
  SELECT b.id AS booking_id, x.from_branch, x.at
    FROM b
    CROSS JOIN LATERAL (
      SELECT mv.from_branch, mv.at FROM mv
       WHERE mv.moto_id = b.moto_id AND mv.at > b.t_pick AND mv.from_branch IS NOT NULL
       ORDER BY mv.at LIMIT 1) x
),
p4 AS (   -- kódy dveří: pobočka v okamžiku dokončení / storna
  SELECT DISTINCT ON (c.booking_id) c.booking_id, c.branch_id
    FROM public.branch_door_codes c
    JOIN b ON b.id = c.booking_id
   WHERE c.branch_id IS NOT NULL
   ORDER BY c.booking_id, c.is_active DESC, c.superseded_by_regen NULLS FIRST, c.created_at DESC
)
SELECT b.id,
       CASE WHEN b.live THEN m.branch_id
            ELSE COALESCE(p1.branch_id, p2.branch_id,
                          CASE WHEN p3.at < b.t_end THEN p3.from_branch END,
                          p4.branch_id, p3.from_branch, m.branch_id) END AS branch_id
  FROM b
  LEFT JOIN public.motorcycles m ON m.id = b.moto_id
  LEFT JOIN p1 ON p1.booking_id = b.id
  LEFT JOIN p2 ON p2.booking_id = b.id
  LEFT JOIN p3 ON p3.booking_id = b.id
  LEFT JOIN p4 ON p4.booking_id = b.id;

UPDATE public.bookings bk
   SET branch_id = s.branch_id
  FROM _bb_src s
 WHERE bk.id = s.id AND bk.branch_id IS NULL AND s.branch_id IS NOT NULL
   AND EXISTS (SELECT 1 FROM public.branches br WHERE br.id = s.branch_id);

-- Navazující rezervace a SOS náhrady dědí pobočku původní (řetězy → 3 průchody).
DO $$
BEGIN
  FOR i IN 1..3 LOOP
    UPDATE public.bookings c
       SET branch_id = p.branch_id
      FROM public.bookings p
     WHERE c.branch_id IS NULL AND p.branch_id IS NOT NULL
       AND p.id = COALESCE(c.extends_booking_id,
                           CASE WHEN c.sos_replacement IS TRUE THEN c.replacement_for_booking_id END);
    EXIT WHEN NOT FOUND;
  END LOOP;
END $$;

-- Zbytek (bez zdroje): aktuální pobočka motorky.
UPDATE public.bookings c
   SET branch_id = m.branch_id
  FROM public.motorcycles m
 WHERE c.branch_id IS NULL AND m.id = c.moto_id AND m.branch_id IS NOT NULL;

ALTER TABLE public.bookings ENABLE TRIGGER trg_booking_modified_email;
ALTER TABLE public.bookings ENABLE TRIGGER bookings_updated_at;

COMMENT ON COLUMN public.bookings.branch_id IS
  'Pobočka rezervace = kde zákazník motorku skutečně převzal. Do vyzvednutí následuje motorku (trg_set_booking_branch + trg_booking_branch_follow_moto), od vyzvednutí / storna / dokončení zmrazená. Backfill historie 2026-10-10 (20261010b). Velín filtruje a sčítá rezervace podle tohoto sloupce, NE podle aktuální pobočky motorky.';
