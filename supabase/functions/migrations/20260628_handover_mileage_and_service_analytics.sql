-- =============================================================================
-- 2026-06-28: Nájezd km z předávacího protokolu -> data model, servis, analytika
-- =============================================================================
-- Produktové rozhodnutí: km eviduje JEN předávací protokol (handover). Vrácení
-- se neřeší — km dalšího předání téže motorky = de facto vrácení předchozího.
-- motorcycles.mileage = GREATEST(stávající, nové) — automaticky NIKDY neklesá.
-- "Najeto za půjčení" se dopočítává z rozdílu po sobě jdoucích předávacích čtení.
--
-- Idempotentní, EXCEPTION-safe. SQL se aplikuje RUČNĚ v Supabase (CLAUDE.md).
-- !!! PŘED APLIKACÍ vydumpni živé tělo update_moto_after_service a ověř, že
--     níže uvedená verze nezahodí žádné extra chování:
--       SELECT pg_get_functiondef('update_moto_after_service'::regproc);
-- =============================================================================

-- ── 1a. Propsání km z protokolu: bookings.mileage_start -> motorcycles.mileage
-- Spustí se JEN když je mileage_start v UPDATE SET listu (column-scoped) — proto
-- neinteraguje s ostatními bookings triggery (booking_modified mail / door codes
-- / účetnictví / vouchery), které sledují status/moto/cenu/místo/payment_status.
CREATE OR REPLACE FUNCTION trg_booking_mileage_to_moto() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  IF NEW.mileage_start IS NULL OR NEW.mileage_start <= 0 THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.mileage_start IS NOT DISTINCT FROM OLD.mileage_start THEN
    RETURN NEW;
  END IF;
  IF NEW.moto_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Nikdy nesnižovat odometr (GREATEST chrání před chybným/staršího pořadí čtením).
  UPDATE motorcycles
     SET mileage = GREATEST(COALESCE(mileage, 0), NEW.mileage_start)
   WHERE id = NEW.moto_id
     AND COALESCE(mileage, 0) < NEW.mileage_start;  -- no-op když neroste

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('trg_booking_mileage_to_moto','bump_failed','error',SQLERRM,
            jsonb_build_object('booking_id',NEW.id,'moto_id',NEW.moto_id,'mileage_start',NEW.mileage_start));
  EXCEPTION WHEN OTHERS THEN NULL; END;
  RETURN NEW;  -- nikdy neshodit UPDATE rezervace
END;
$$;

DROP TRIGGER IF EXISTS trg_booking_mileage_to_moto ON bookings;
CREATE TRIGGER trg_booking_mileage_to_moto
  AFTER INSERT OR UPDATE OF mileage_start ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION trg_booking_mileage_to_moto();


-- ── 1b. Ruční korekce nájezdu (admin) + audit
-- Ruční korekce je autoritativní (smí i dolů kvůli překlepu), ale nikdy pod
-- purchase_mileage (odometr nemůže být nižší než stav při pořízení).
CREATE OR REPLACE FUNCTION correct_motorcycle_mileage(
  p_moto_id uuid, p_km integer, p_note text DEFAULT NULL
) RETURNS motorcycles
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_row motorcycles%ROWTYPE;
  v_admin uuid := auth.uid();
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF p_km IS NULL OR p_km < 0 THEN
    RAISE EXCEPTION 'invalid_km';
  END IF;

  UPDATE motorcycles
     SET mileage = GREATEST(p_km, COALESCE(purchase_mileage, 0))
   WHERE id = p_moto_id
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'moto_not_found';
  END IF;

  BEGIN
    INSERT INTO admin_audit_log(admin_id, action, entity_type, entity_id, new_data)
    VALUES (v_admin, 'motorcycle_mileage_corrected', 'motorcycles', p_moto_id,
            jsonb_build_object('new_km', v_row.mileage, 'requested_km', p_km, 'note', p_note));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN v_row;
END;
$$;
GRANT EXECUTE ON FUNCTION correct_motorcycle_mileage(uuid, integer, text) TO authenticated;


-- ── 1c. Srovnání: purchase_mileage <= mileage
-- Když admin vyplní "Zakoupeno s KM" vyšší než aktuální odometr, zvedne odometr.
CREATE OR REPLACE FUNCTION trg_moto_purchase_mileage_floor() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.purchase_mileage IS NOT NULL
     AND NEW.purchase_mileage > COALESCE(NEW.mileage, 0) THEN
    NEW.mileage := NEW.purchase_mileage;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_moto_purchase_mileage_floor ON motorcycles;
CREATE TRIGGER trg_moto_purchase_mileage_floor
  BEFORE INSERT OR UPDATE OF mileage, purchase_mileage ON motorcycles
  FOR EACH ROW
  EXECUTE FUNCTION trg_moto_purchase_mileage_floor();


-- ── 1d. Dokončení servisu zvedne motorcycles.mileage (GREATEST)
-- CREATE OR REPLACE existující out-of-band funkce. Zachovává status/last_service_date
-- chování (které dnes dělá Velín modal) a přidává bump odometru z km_at_service.
-- !!! Ověř proti živému tělu (viz hlavička) — pokud původní dělalo navíc (např.
--     next_service_date), začleň to sem před aplikací.
CREATE OR REPLACE FUNCTION update_moto_after_service() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  IF NEW.moto_id IS NULL THEN RETURN NEW; END IF;

  -- Bump odometru ze servisního čtení (nikdy nesnižovat).
  IF NEW.km_at_service IS NOT NULL AND NEW.km_at_service > 0 THEN
    UPDATE motorcycles
       SET mileage = GREATEST(COALESCE(mileage, 0), NEW.km_at_service)
     WHERE id = NEW.moto_id
       AND COALESCE(mileage, 0) < NEW.km_at_service;
  END IF;

  -- Při dokončení servisu srovnat baseline plánů.
  IF COALESCE(NEW.status,'') = 'completed' THEN
    UPDATE motorcycles
       SET last_service_date = COALESCE(NEW.completed_date::date, CURRENT_DATE)
     WHERE id = NEW.moto_id;
    UPDATE maintenance_schedules
       SET last_service_km   = GREATEST(COALESCE(last_service_km,0), COALESCE(NEW.km_at_service,0)),
           last_service_date = COALESCE(NEW.completed_date::date, CURRENT_DATE)
     WHERE moto_id = NEW.moto_id AND active = true;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('update_moto_after_service','failed','error',SQLERRM,
            jsonb_build_object('log_id',NEW.id,'moto_id',NEW.moto_id));
  EXCEPTION WHEN OTHERS THEN NULL; END;
  RETURN NEW;
END;
$$;

-- AFTER INSERT trigger (maintenance_log_after_insert) už existuje. Doplnit i edity,
-- které log dodatečně přepnou na completed / doplní km:
DROP TRIGGER IF EXISTS maintenance_log_after_update ON maintenance_log;
CREATE TRIGGER maintenance_log_after_update
  AFTER UPDATE OF km_at_service, status, completed_date ON maintenance_log
  FOR EACH ROW
  EXECUTE FUNCTION update_moto_after_service();


-- ── 1e. Analytika ───────────────────────────────────────────────────────────

-- Per segment: najeto km během rezervace = rozdíl do dalšího předávacího čtení
-- téže motorky (LEAD dle start_date). Poslední otevřený segment má next_reading NULL.
CREATE OR REPLACE FUNCTION analytics_moto_rental_km()
RETURNS TABLE (
  moto_id uuid, booking_id uuid, user_id uuid,
  start_date timestamptz, reading integer, next_reading integer, km_driven integer
)
LANGUAGE sql STABLE
AS $$
  WITH readings AS (
    SELECT b.moto_id, b.id AS booking_id, b.user_id, b.start_date,
           b.mileage_start::int AS reading,
           LEAD(b.mileage_start::int) OVER (PARTITION BY b.moto_id ORDER BY b.start_date) AS next_reading
      FROM bookings b
     WHERE b.mileage_start IS NOT NULL AND b.mileage_start > 0
       AND COALESCE(b.is_test, false) = false
  )
  SELECT moto_id, booking_id, user_id, start_date, reading, next_reading,
         GREATEST(COALESCE(next_reading,0) - reading, 0) AS km_driven
    FROM readings;
$$;
GRANT EXECUTE ON FUNCTION analytics_moto_rental_km() TO authenticated;

-- Per zákazník: Σ najeto na jeho rezervacích (jen uzavřené segmenty).
CREATE OR REPLACE FUNCTION analytics_customer_km()
RETURNS TABLE (user_id uuid, total_km bigint, rentals_with_km bigint, km_per_rental numeric)
LANGUAGE sql STABLE
AS $$
  SELECT user_id,
         COALESCE(SUM(km_driven),0)::bigint AS total_km,
         COUNT(*) FILTER (WHERE km_driven > 0)::bigint AS rentals_with_km,
         ROUND(AVG(NULLIF(km_driven,0)), 0) AS km_per_rental
    FROM analytics_moto_rental_km()
   WHERE next_reading IS NOT NULL AND user_id IS NOT NULL
   GROUP BY user_id;
$$;
GRANT EXECUTE ON FUNCTION analytics_customer_km() TO authenticated;

-- Per motorka: current/purchase/total, km/rezervace, průměr na kalendářní den
-- (od acquired_at) i na půjčovní den.
CREATE OR REPLACE FUNCTION analytics_moto_km()
RETURNS TABLE (
  moto_id uuid, model text, spz text, tracking_unit text,
  current_km integer, purchase_km integer, total_driven integer,
  rentals_with_km bigint, km_per_rental numeric,
  avg_km_per_calendar_day numeric, avg_km_per_rental_day numeric
)
LANGUAGE sql STABLE
AS $$
  WITH rk AS (
    SELECT moto_id,
           COALESCE(SUM(km_driven),0) AS km_from_rentals,
           COUNT(*) FILTER (WHERE km_driven > 0) AS rentals_with_km
      FROM analytics_moto_rental_km()
     WHERE next_reading IS NOT NULL
     GROUP BY moto_id
  ),
  rdays AS (
    SELECT b.moto_id,
           SUM(GREATEST((b.end_date::date - b.start_date::date) + 1, 1)) AS rental_days
      FROM bookings b
     WHERE b.mileage_start IS NOT NULL AND b.mileage_start > 0
       AND COALESCE(b.is_test,false) = false
     GROUP BY b.moto_id
  )
  SELECT m.id, m.model, m.spz, COALESCE(m.tracking_unit,'km'),
         COALESCE(m.mileage,0), COALESCE(m.purchase_mileage,0),
         GREATEST(COALESCE(m.mileage,0) - COALESCE(m.purchase_mileage,0), 0) AS total_driven,
         COALESCE(rk.rentals_with_km,0),
         CASE WHEN COALESCE(rk.rentals_with_km,0) > 0
              THEN ROUND(rk.km_from_rentals::numeric / rk.rentals_with_km, 0) END,
         CASE WHEN m.acquired_at IS NOT NULL
               AND (CURRENT_DATE - m.acquired_at::date) > 0
              THEN ROUND(GREATEST(COALESCE(m.mileage,0)-COALESCE(m.purchase_mileage,0),0)::numeric
                         / (CURRENT_DATE - m.acquired_at::date), 1) END,
         CASE WHEN COALESCE(rd.rental_days,0) > 0
              THEN ROUND(COALESCE(rk.km_from_rentals,0)::numeric / rd.rental_days, 1) END
    FROM motorcycles m
    LEFT JOIN rk    ON rk.moto_id = m.id
    LEFT JOIN rdays rd ON rd.moto_id = m.id;
$$;
GRANT EXECUTE ON FUNCTION analytics_moto_km() TO authenticated;


-- ── 1f. Plánování servisu (per motorka × typ) ───────────────────────────────
-- Zrcadlí koncept serviceScheduleUtils/FleetDetailServiceCard v SQL: interval,
-- current km, km od posledního servisu, zbývá km, due_soon (<=20 %), overdue,
-- odhad data z očekávaného průměru. Bere intervaly z motorcycles.*_interval_*
-- (které jistě existují); bohaté umístění dne (sezóna, Út/St) zůstává v JS.
CREATE OR REPLACE FUNCTION analytics_service_plan(p_default_daily_km numeric DEFAULT 50)
RETURNS TABLE (
  moto_id uuid, model text, spz text, tracking_unit text,
  service_type text, label text,
  interval_km integer, interval_days integer,
  current_km integer, last_service_km integer,
  km_since_last integer, km_remaining integer,
  due_soon boolean, overdue boolean,
  avg_daily_km numeric, estimated_due_date date
)
LANGUAGE sql STABLE
AS $$
  WITH avg_km AS (
    SELECT a.moto_id, a.avg_km_per_calendar_day AS daily FROM analytics_moto_km() a
  ),
  moto_types AS (
    SELECT m.id AS moto_id, m.model, m.spz, COALESCE(m.tracking_unit,'km') AS unit,
           COALESCE(m.mileage,0) AS cur, t.stype, t.lbl, t.ikm, t.idays
      FROM motorcycles m
      CROSS JOIN LATERAL (VALUES
        ('oil_change','Výměna oleje',          m.oil_interval_km,          m.oil_interval_days),
        ('tire_change','Výměna pneumatik',     m.tire_interval_km,         NULL::int),
        ('full_service','Kompletní servis',    m.full_service_interval_km, m.full_service_interval_days)
      ) AS t(stype, lbl, ikm, idays)
     WHERE t.ikm IS NOT NULL AND t.ikm > 0
  ),
  last_km AS (
    SELECT s.moto_id, s.schedule_type AS stype, MAX(s.last_service_km) AS lkm
      FROM maintenance_schedules s
     WHERE s.active = true
     GROUP BY s.moto_id, s.schedule_type
  )
  SELECT mt.moto_id, mt.model, mt.spz, mt.unit,
         mt.stype, mt.lbl, mt.ikm, mt.idays, mt.cur,
         COALESCE(lk.lkm,0),
         GREATEST(mt.cur - COALESCE(lk.lkm,0), 0) AS km_since_last,
         (COALESCE(lk.lkm,0) + mt.ikm) - mt.cur   AS km_remaining,
         ((COALESCE(lk.lkm,0) + mt.ikm) - mt.cur) <= (mt.ikm * 0.20) AS due_soon,
         ((COALESCE(lk.lkm,0) + mt.ikm) - mt.cur) <= 0               AS overdue,
         COALESCE(av.daily, p_default_daily_km) AS avg_daily_km,
         CASE
           WHEN ((COALESCE(lk.lkm,0) + mt.ikm) - mt.cur) <= 0 THEN CURRENT_DATE
           WHEN COALESCE(av.daily, p_default_daily_km) > 0
             THEN CURRENT_DATE + (CEIL(((COALESCE(lk.lkm,0)+mt.ikm) - mt.cur)
                                       / COALESCE(av.daily, p_default_daily_km)))::int
         END AS estimated_due_date
    FROM moto_types mt
    LEFT JOIN last_km lk ON lk.moto_id = mt.moto_id AND lk.stype = mt.stype
    LEFT JOIN avg_km av  ON av.moto_id = mt.moto_id;
$$;
GRANT EXECUTE ON FUNCTION analytics_service_plan(numeric) TO authenticated;

-- Volitelný index (až bookings naroste):
-- CREATE INDEX IF NOT EXISTS idx_bookings_moto_mileage_start
--   ON bookings (moto_id, start_date) WHERE mileage_start IS NOT NULL;
