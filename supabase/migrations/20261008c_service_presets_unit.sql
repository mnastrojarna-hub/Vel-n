-- 20261008c — Servisní knížka: presety výrobce v jednotce motorky (km / motohodiny), „úkon se netýká“,
-- opravy karet motorek pro správné hlídání. Idempotentní.
--  (C1) service_interval_presets.unit ('km' | 'mh'): preset platí jen pro motorky se stejnou jednotkou
--       (hodinové intervaly dětských motorek se nesmí přenést na km-tracked kus a naopak).
--  (C2) service_plan_apply_presets: preset s interval_km i interval_months NULL = výrobce úkon nepředepisuje
--       (olejový filtr u dvoutaktu, baterie u dětské motorky, chladicí kapalina u vzduchem chlazené) → plán se
--       nezakládá a existující AUTOMATICKÝ plán (source <> manual) se vyřadí; totéž pro úkon, který se motorky
--       netýká pohonem / chlazením (po opravě karty motorky). Ruční plány admina se nemění.
--  (C3) karty motorek: Royal Enfield Shotgun 650 a Yamaha PW 50 jsou vzduchem chlazené (plán chladicí kapaliny
--       byl falešný), Aprilia SR GT 125 má řemen variátoru (ne kardan), doplněna značka u Husqvarna TC 65 /
--       KTM 1290 Super Adventure / KTM SX 50 a pohon + motor u KTM 1290.

-- (C1)
ALTER TABLE public.service_interval_presets ADD COLUMN IF NOT EXISTS unit text NOT NULL DEFAULT 'km';
ALTER TABLE public.service_interval_presets DROP CONSTRAINT IF EXISTS service_interval_presets_unit_check;
ALTER TABLE public.service_interval_presets ADD CONSTRAINT service_interval_presets_unit_check CHECK (unit IN ('km', 'mh'));
COMMENT ON COLUMN public.service_interval_presets.unit IS 'Jednotka interval_km: km, nebo mh (motohodiny) — preset se použije jen u motorek se stejnou tracking_unit.';

-- (C2)
CREATE OR REPLACE FUNCTION public.service_plan_apply_presets(p_moto_id uuid DEFAULT NULL, p_reset boolean DEFAULT false) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  m         record;
  c         record;
  v_p_km    integer; v_p_months integer; v_p_note text; v_has_preset boolean;
  v_km      integer; v_days integer;
  v_last_km integer; v_last_date date; v_baseline text;
  v_sched   record;
  v_created int := 0; v_updated int := 0; v_motos int := 0; v_deactivated int := 0; v_cnt int;
  v_applies boolean;
  v_source  text;
  v_mh      boolean;
  v_unit    text;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  FOR m IN SELECT * FROM motorcycles mo
            WHERE mo.status <> 'retired' AND mo.is_trailer IS NOT TRUE
              AND (p_moto_id IS NULL OR mo.id = p_moto_id)
  LOOP
    v_motos := v_motos + 1;
    v_mh := COALESCE(m.tracking_unit, 'km') = 'mh';
    v_unit := CASE WHEN v_mh THEN 'mh' ELSE 'km' END;
    FOR c IN SELECT * FROM service_task_catalog ct WHERE ct.active AND ct.tracked ORDER BY ct.sort_order LOOP
      v_applies := CASE
        WHEN c.only_for IS NULL THEN true
        WHEN c.only_for IN ('chain', 'shaft', 'belt') THEN COALESCE(m.drivetrain, 'chain') = c.only_for
        WHEN c.only_for = 'liquid' THEN COALESCE(m.engine_type, '') !~* '(vzduch|air)'
        WHEN c.only_for = 'hours' THEN v_mh
        ELSE false END;

      -- 1) interval dle výrobce (nejdelší = nejkonkrétnější vzor modelu; jen ve stejné jednotce)
      v_has_preset := false; v_p_km := NULL; v_p_months := NULL; v_p_note := NULL;
      IF v_applies THEN
        SELECT p.interval_km, p.interval_months, p.note INTO v_p_km, v_p_months, v_p_note
          FROM service_interval_presets p
         WHERE p.task_key = c.key AND p.unit = v_unit
           AND m.model ILIKE p.model_pattern
           AND (p.brand_pattern IS NULL OR COALESCE(m.brand, '') ILIKE p.brand_pattern)
           AND (p.year_from IS NULL OR m.year IS NULL OR m.year >= p.year_from)
           AND (p.year_to IS NULL OR m.year IS NULL OR m.year <= p.year_to)
         ORDER BY length(p.model_pattern) DESC, (p.brand_pattern IS NOT NULL) DESC
         LIMIT 1;
        v_has_preset := FOUND;
      END IF;

      -- úkon se motorky netýká (pohon / chlazení) nebo ho výrobce nepředepisuje → automatický plán vyřadit
      IF NOT v_applies OR (v_has_preset AND v_p_km IS NULL AND v_p_months IS NULL) THEN
        UPDATE maintenance_schedules s SET active = false, updated_at = now()
         WHERE s.moto_id = m.id AND s.task_key = c.key AND s.active AND COALESCE(s.source, 'default') <> 'manual';
        GET DIAGNOSTICS v_cnt = ROW_COUNT;
        v_deactivated := v_deactivated + v_cnt;
        CONTINUE;
      END IF;

      IF v_has_preset THEN
        v_km := v_p_km; v_days := CASE WHEN v_p_months IS NOT NULL THEN round(v_p_months * 30.44)::int END; v_source := 'preset';
      ELSE
        v_source := 'default';
        -- 2) interval z karty motorky (oil / tire / full — v jednotce motorky), 3) katalog (km jen u km motorek)
        v_km := CASE c.moto_interval
                  WHEN 'oil'  THEN NULLIF(m.oil_interval_km, 0)
                  WHEN 'tire' THEN NULLIF(m.tire_interval_km, 0)
                  WHEN 'full' THEN NULLIF(m.full_service_interval_km, 0) END;
        IF v_km IS NULL OR v_km > 200000 THEN v_km := CASE WHEN v_mh THEN NULL ELSE c.default_interval_km END; END IF;
        v_days := CASE c.moto_interval
                    WHEN 'oil'  THEN NULLIF(m.oil_interval_days, 0)
                    WHEN 'full' THEN NULLIF(m.full_service_interval_days, 0) END;
        IF v_days IS NULL OR v_days > 3650 THEN v_days := CASE WHEN c.default_interval_months IS NOT NULL THEN round(c.default_interval_months * 30.44)::int END; END IF;
      END IF;
      IF v_km IS NULL AND v_days IS NULL THEN CONTINUE; END IF;

      SELECT s.* INTO v_sched FROM maintenance_schedules s
       WHERE s.moto_id = m.id AND s.task_key = c.key
       ORDER BY s.active DESC, s.updated_at DESC LIMIT 1;

      IF FOUND THEN
        IF NOT v_sched.active THEN
          IF NOT p_reset THEN CONTINUE; END IF;   -- vyřazený plán admin nechce — cron ho znovu nezakládá
          UPDATE maintenance_schedules SET active = true, interval_km = v_km, interval_days = v_days, source = v_source,
                 schedule_type = CASE WHEN v_km IS NOT NULL AND v_days IS NOT NULL THEN 'both' WHEN v_km IS NOT NULL THEN 'mileage' ELSE 'time' END,
                 notes = COALESCE(v_p_note, notes), updated_at = now()
           WHERE id = v_sched.id;
          v_updated := v_updated + 1;
        ELSIF COALESCE(v_sched.source, 'default') <> 'manual' AND (p_reset OR v_sched.source IS DISTINCT FROM v_source
             OR v_sched.interval_km IS DISTINCT FROM v_km OR v_sched.interval_days IS DISTINCT FROM v_days) THEN
          -- ruční plán admina se nemění; automatický se srovná na výrobce / nový default
          UPDATE maintenance_schedules
             SET interval_km = v_km, interval_days = v_days, source = v_source,
                 schedule_type = CASE WHEN v_km IS NOT NULL AND v_days IS NOT NULL THEN 'both' WHEN v_km IS NOT NULL THEN 'mileage' ELSE 'time' END,
                 notes = COALESCE(v_p_note, notes), updated_at = now()
           WHERE id = v_sched.id;
          v_updated := v_updated + 1;
        END IF;
        CONTINUE;
      END IF;

      -- „naposledy provedeno“: poslední dokončený servis s tímto úkonem, jinak pořízení
      SELECT ml.km_at_service, ml.completed_date::date INTO v_last_km, v_last_date
        FROM maintenance_log ml
       WHERE ml.moto_id = m.id AND ml.completed_date IS NOT NULL AND ml.is_test IS NOT TRUE
         AND c.key = ANY (public._service_done_task_keys(ml.items, ml.type, ml.description))
       ORDER BY ml.completed_date DESC, ml.km_at_service DESC NULLS LAST
       LIMIT 1;
      IF FOUND THEN
        v_baseline := 'log';
      ELSE
        v_last_km := m.purchase_mileage; v_last_date := m.acquired_at;
        v_baseline := CASE WHEN v_last_km IS NOT NULL OR v_last_date IS NOT NULL THEN 'acquisition' ELSE 'unknown' END;
      END IF;

      INSERT INTO maintenance_schedules
        (moto_id, schedule_type, interval_km, interval_days, description, active, task_key, source, baseline_source,
         last_service_km, last_service_date, last_performed, notes)
      VALUES
        (m.id, CASE WHEN v_km IS NOT NULL AND v_days IS NOT NULL THEN 'both' WHEN v_km IS NOT NULL THEN 'mileage' ELSE 'time' END,
         v_km, v_days, c.label, true, c.key, v_source, v_baseline,
         v_last_km, v_last_date, CASE WHEN v_baseline = 'log' THEN v_last_date END, v_p_note);
      v_created := v_created + 1;
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'motos', v_motos, 'created', v_created, 'updated', v_updated, 'deactivated', v_deactivated);
END $$;

COMMENT ON FUNCTION public.service_plan_apply_presets(uuid, boolean) IS
  'Plány „základního standardu“ pro motorku (NULL = všechny): interval výrobce (service_interval_presets, stejná jednotka km/mh; NULL/NULL = nepředepisuje → plán se vyřadí) > karta motorky (oil/tire/full) > katalog; úkony mimo pohon/chlazení motorky se vyřadí (jen automatické plány); ruční plány se nemění; vyřazený plán se znovu nezakládá (jen p_reset). Vrací {motos, created, updated, deactivated}. Volá cron (auto_schedule_services) a Velín.';

-- (C3) karty motorek
UPDATE public.motorcycles SET engine_type = 'řadový dvouválec, vzduchem/olejem chlazený'
 WHERE model ILIKE 'Royal Enfield Shotgun 650%' AND COALESCE(engine_type, '') !~* '(vzduch|air)';
UPDATE public.motorcycles SET engine_type = 'dvoutaktní jednoválec, vzduchem chlazený'
 WHERE model ILIKE 'Yamaha PW 50%' AND COALESCE(engine_type, '') !~* '(vzduch|air)';
UPDATE public.motorcycles SET drivetrain = 'belt'
 WHERE model ILIKE 'Aprilia SR GT%' AND drivetrain IS DISTINCT FROM 'belt';
UPDATE public.motorcycles SET brand = 'Husqvarna'
 WHERE model ILIKE 'Husqvarna TC 65%' AND (brand IS NULL OR brand = 'TC 65');
UPDATE public.motorcycles SET brand = COALESCE(NULLIF(brand, ''), 'KTM'), drivetrain = COALESCE(drivetrain, 'chain'),
       engine_type = COALESCE(NULLIF(engine_type, ''), 'vidlicový dvouválec LC8, kapalinou chlazený')
 WHERE model ILIKE 'KTM 1290 Super Adventure%';
UPDATE public.motorcycles SET brand = 'KTM' WHERE model ILIKE 'KTM SX 50%' AND NULLIF(brand, '') IS NULL;
