-- 2026-10-08 (B) — Servisní knížka motorek: automatika (navazuje na 20261008_service_book_schema.sql).
--  (B1) service_task_key_for_label / _service_items_with_keys / _service_done_task_keys — párování štítků úkonů
--       v maintenance_log.items na katalog (klíč `key`, historické aliasy). PROVEDENÉ úkony = JEN odškrtnuté
--       (done=true) + `implies` (tranzitivně); legacy `type` a popis „výměna oleje“ se berou POUZE u záznamů bez
--       checklistu (bez položek s key/done) — zadání v `description` nikdy neznamená „provedeno“.
--  (B2) trigger maintenance_log_autofill (BEFORE INSERT/UPDATE): km_at_service ze stavu tachometru (při založení
--       i při dokončení, pokud je technik nezadal ručně → km_auto; km zadané = aktuální stav se bere také jako auto;
--       zpětně datované záznamy (> 1 den) km nedostanou), created_by/updated_by/completed_by = auth.uid(), technik
--       (technician_admin_id + performed_by) = jméno přihlášeného účtu při DOKONČENÍ, items vždy pole s klíči.
--  (B3) update_moto_after_service — NAHRAZENO (živé tělo ze snapshotu 2026-10-08 zachováno: bump tachometru,
--       last_service_date): plány posune JEN pro úkony NOVĚ provedené tímto zápisem (ne při pouhé editaci starého
--       dokončeného záznamu); next_due (ruční termín) se po provedení vynuluje.
--  (B3b) trigger maintenance_schedules_defaults (BEFORE INSERT): ruční plán bez baseline dostane „naposledy“ z
--       posledního dokončeného servisu s úkonem, jinak start = dnešní stav tachometru / dnes (plán z formuláře
--       „Pravidelný servis“ už není po termínu v okamžiku založení).
--  (B4) maintenance_invoices → maintenance_log.invoiced_amount (trigger).
--  (B5) service_plan_apply_presets(p_moto_id, p_reset) — plány „základního standardu“: interval = výrobce
--       (service_interval_presets) > karta motorky (oil/tire/full) > katalog (u motohodin bez katalogových km);
--       baseline = poslední dokončený servis s úkonem, jinak pořízení; vyřazený plán (active=false) se znovu
--       nezakládá (jen p_reset). Volá cron `cron-daily` (auto_schedule_services — přepsána) a Velín.
--  (B6) get_service_due(p_moto_id) / get_service_due_count() / get_last_service_per_moto() — hlídání: zbývá km/dní,
--       odhad termínu z Ø denního nájezdu, km baseline dopočtená z data (km_estimated), stav overdue/due_soon/ok/
--       unknown/no_interval (kontroly s baseline „od pořízení“ = unknown, ne falešné „po termínu“), open_log_id.
--  (B7) backfill: klíče do historických items; dokončené záznamy ze staré verze bez jediného odškrtnutí = provedené
--       (done_legacy); km_auto u otevřených; plány všem motorkám.
-- Idempotentní (CREATE OR REPLACE / DROP IF EXISTS).

-- ==========================================================================
-- (B1) Párování úkonů
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.service_task_key_for_label(p_label text) RETURNS text
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  SELECT c.key FROM service_task_catalog c
   WHERE c.label = btrim(COALESCE(p_label, '')) OR btrim(COALESCE(p_label, '')) = ANY (c.aliases)
   ORDER BY (c.label = btrim(COALESCE(p_label, ''))) DESC
   LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public._service_items_with_keys(p_items jsonb) RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  SELECT COALESCE(jsonb_agg(
    CASE WHEN jsonb_typeof(t.e) = 'object'
          AND NULLIF(t.e->>'key', '') IS NULL
          AND COALESCE((t.e->>'custom')::boolean, false) = false
          AND public.service_task_key_for_label(t.e->>'label') IS NOT NULL
         THEN t.e || jsonb_build_object('key', public.service_task_key_for_label(t.e->>'label'))
         ELSE t.e END ORDER BY t.ord), '[]'::jsonb)
  FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_items) = 'array' THEN p_items ELSE '[]'::jsonb END)
       WITH ORDINALITY AS t(e, ord);
$$;

-- Klíče úkonů PROVEDENÝCH v záznamu: odškrtnuté (done=true) + implies (tranzitivně). Legacy `type` a popis
-- „výměna (motorového) oleje“ jen u záznamů BEZ checklistu (žádná položka s key / done) — popis je zadání.
CREATE OR REPLACE FUNCTION public._service_done_task_keys(p_items jsonb, p_type text, p_description text) RETURNS text[]
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  WITH RECURSIVE items AS (
    SELECT e FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_items) = 'array' THEN p_items ELSE '[]'::jsonb END) e
  ), evidence AS (
    SELECT EXISTS (SELECT 1 FROM items WHERE NULLIF(e->>'key', '') IS NOT NULL OR (e ? 'done')) AS has_checklist
  ), done AS (
    SELECT COALESCE(NULLIF(e->>'key', ''), public.service_task_key_for_label(e->>'label')) AS k
      FROM items WHERE COALESCE((e->>'done')::boolean, false)
  ), typed AS (
    SELECT unnest(CASE p_type
                    WHEN 'oil_change'   THEN ARRAY['oil_change','oil_filter']
                    WHEN 'tire_change'  THEN ARRAY['tire_front','tire_rear']
                    WHEN 'full_service' THEN ARRAY['full_service']
                    ELSE '{}'::text[] END) AS k
     WHERE NOT (SELECT has_checklist FROM evidence)
  ), described AS (
    SELECT 'oil_change'::text AS k
     WHERE NOT (SELECT has_checklist FROM evidence)
       AND COALESCE(p_description, '') ~* 'v[yý]m[eě]n\w*\s+(motorov\w+\s+)?olej'
       AND COALESCE(p_description, '') !~* 'olej\w*\s+(v|ve|do)\s+(kardan|rozvodov|vidlic|p[rř]evodov|tlumi[cč])'
       AND COALESCE(p_description, '') !~* '(nen[ií]\s|zda\s|jestli\s|zkontrol|kontrol)'
  ), allk AS (
    SELECT k FROM done WHERE k IS NOT NULL UNION SELECT k FROM typed UNION SELECT k FROM described
  ), expanded AS (
    SELECT k FROM allk
    UNION
    SELECT unnest(c.implies) FROM expanded x JOIN service_task_catalog c ON c.key = x.k
  )
  SELECT COALESCE(array_agg(DISTINCT k), '{}'::text[]) FROM expanded WHERE k IS NOT NULL;
$$;

-- ==========================================================================
-- (B2) Automatické doplnění záznamu: km, technik dle loginu, klíče úkonů
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.maintenance_log_autofill() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_admin_name text;
  v_mileage    integer;
  v_completing boolean;
  v_current    boolean;   -- záznam se týká současnosti (ne zpětně datovaný) → km ze stavu tachometru
BEGIN
  IF v_uid IS NOT NULL THEN
    SELECT COALESCE(NULLIF(btrim(a.name), ''), a.email) INTO v_admin_name
      FROM admin_users a WHERE a.id = v_uid AND a.active;
  END IF;
  IF NEW.moto_id IS NOT NULL THEN
    SELECT m.mileage INTO v_mileage FROM motorcycles m WHERE m.id = NEW.moto_id;
  END IF;
  v_current := NEW.completed_date IS NULL OR NEW.completed_date::date >= CURRENT_DATE - 1;

  NEW.updated_at := now();
  IF v_uid IS NOT NULL THEN NEW.updated_by := v_uid; END IF;
  NEW.items := public._service_items_with_keys(NEW.items);

  IF TG_OP = 'INSERT' THEN
    NEW.created_by := COALESCE(NEW.created_by, v_uid);
    IF COALESCE(v_mileage, 0) > 0 THEN
      IF NEW.km_at_service IS NULL AND v_current THEN
        NEW.km_at_service := v_mileage; NEW.km_auto := true;
      ELSIF NEW.km_at_service = v_mileage THEN
        NEW.km_auto := true;   -- starší formuláře posílají aktuální stav = žádná nová informace
      END IF;
    END IF;
  ELSIF NEW.km_at_service IS DISTINCT FROM OLD.km_at_service THEN
    NEW.km_auto := false;      -- stav zadaný ručně (technik / admin) má přednost
  END IF;

  v_completing := (COALESCE(NEW.status, '') = 'completed' OR NEW.completed_date IS NOT NULL)
                  AND (TG_OP = 'INSERT' OR (COALESCE(OLD.status, '') <> 'completed' AND OLD.completed_date IS NULL));
  IF v_completing THEN
    NEW.completed_date := COALESCE(NEW.completed_date, CURRENT_DATE);
    NEW.completed_by := COALESCE(NEW.completed_by, v_uid);
    -- km při dokončení = aktuální stav tachometru, pokud technik km nezadal ručně a servis se dokončuje teď
    IF TG_OP = 'UPDATE' AND NEW.km_at_service IS NOT DISTINCT FROM OLD.km_at_service
       AND (OLD.km_auto OR OLD.km_at_service IS NULL) AND COALESCE(v_mileage, 0) > 0
       AND NEW.completed_date::date >= CURRENT_DATE - 1 THEN
      NEW.km_at_service := GREATEST(COALESCE(NEW.km_at_service, 0), v_mileage);
      NEW.km_auto := true;
    END IF;
    -- technik = kdo servis dokončil (přihlášený účet Velína), pokud nebyl zadán jiný
    IF v_admin_name IS NOT NULL THEN
      IF NEW.technician_admin_id IS NULL THEN NEW.technician_admin_id := v_uid; END IF;
      IF NULLIF(btrim(COALESCE(NEW.performed_by, '')), '') IS NULL THEN NEW.performed_by := v_admin_name; END IF;
    END IF;
  END IF;
  -- technik zvolený účtem Velína bez jména → doplnit jméno z admin_users
  IF NEW.technician_admin_id IS NOT NULL AND NULLIF(btrim(COALESCE(NEW.performed_by, '')), '') IS NULL THEN
    SELECT COALESCE(NULLIF(btrim(a.name), ''), a.email) INTO NEW.performed_by FROM admin_users a WHERE a.id = NEW.technician_admin_id;
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'maintenance_log_autofill failed for log %: %', NEW.id, SQLERRM;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_maintenance_log_autofill ON public.maintenance_log;
CREATE TRIGGER trg_maintenance_log_autofill
  BEFORE INSERT OR UPDATE ON public.maintenance_log
  FOR EACH ROW EXECUTE FUNCTION public.maintenance_log_autofill();

-- ==========================================================================
-- (B3) update_moto_after_service — plány posune jen NOVĚ provedený úkon
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.update_moto_after_service() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_keys text[];
  v_old  text[] := '{}';
  v_new  text[];
  v_date date;
BEGIN
  IF NEW.moto_id IS NULL THEN RETURN NEW; END IF;

  -- Bump odometru ze servisního čtení (nikdy nesnižovat).
  IF NEW.km_at_service IS NOT NULL AND NEW.km_at_service > 0 THEN
    UPDATE motorcycles
       SET mileage = GREATEST(COALESCE(mileage, 0), NEW.km_at_service)
     WHERE id = NEW.moto_id
       AND COALESCE(mileage, 0) < NEW.km_at_service;
  END IF;

  IF COALESCE(NEW.status, '') = 'completed' AND NEW.is_test IS NOT TRUE THEN
    v_date := COALESCE(NEW.completed_date::date, CURRENT_DATE);
    UPDATE motorcycles
       SET last_service_date = v_date
     WHERE id = NEW.moto_id AND (last_service_date IS NULL OR last_service_date < v_date);

    v_keys := public._service_done_task_keys(NEW.items, NEW.type, NEW.description);
    IF TG_OP = 'UPDATE' AND COALESCE(OLD.status, '') = 'completed' THEN
      v_old := public._service_done_task_keys(OLD.items, OLD.type, OLD.description);   -- editace starého záznamu
    END IF;
    v_new := ARRAY(SELECT unnest(v_keys) EXCEPT SELECT unnest(v_old));
    IF COALESCE(array_length(v_new, 1), 0) > 0 THEN
      UPDATE maintenance_schedules s
         SET last_service_km   = CASE WHEN NEW.km_at_service IS NOT NULL THEN GREATEST(COALESCE(s.last_service_km, 0), NEW.km_at_service) ELSE s.last_service_km END,
             last_service_date = GREATEST(COALESCE(s.last_service_date, v_date), v_date),
             last_performed    = GREATEST(COALESCE(s.last_performed, v_date), v_date),
             next_due          = NULL,
             baseline_source   = 'log',
             updated_at        = now()
       WHERE s.moto_id = NEW.moto_id AND s.active = true
         AND (s.task_key = ANY (v_new)
              OR (s.task_key IS NULL AND s.description IS NOT NULL AND EXISTS (
                    SELECT 1 FROM unnest(v_new) k JOIN service_task_catalog c ON c.key = k
                     WHERE lower(btrim(s.description)) = lower(c.label) OR lower(btrim(s.description)) = ANY (SELECT lower(x) FROM unnest(c.aliases) x))));
    END IF;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('update_moto_after_service', 'failed', 'error', SQLERRM,
            jsonb_build_object('log_id', NEW.id, 'moto_id', NEW.moto_id));
  EXCEPTION WHEN OTHERS THEN NULL; END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS maintenance_log_after_update ON public.maintenance_log;
CREATE TRIGGER maintenance_log_after_update
  AFTER UPDATE OF km_at_service, status, completed_date, items ON public.maintenance_log
  FOR EACH ROW EXECUTE FUNCTION public.update_moto_after_service();

-- ==========================================================================
-- (B3b) Ruční plán: baseline = poslední servis s úkonem, jinak start = teď
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.maintenance_schedules_defaults() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE v_km integer; v_date date;
BEGIN
  NEW.updated_at := now();
  IF TG_OP = 'INSERT' AND NEW.baseline_source IS NULL THEN
    IF NEW.task_key IS NOT NULL THEN
      SELECT ml.km_at_service, ml.completed_date::date INTO v_km, v_date
        FROM maintenance_log ml
       WHERE ml.moto_id = NEW.moto_id AND ml.completed_date IS NOT NULL AND ml.is_test IS NOT TRUE
         AND NEW.task_key = ANY (public._service_done_task_keys(ml.items, ml.type, ml.description))
       ORDER BY ml.completed_date DESC, ml.km_at_service DESC NULLS LAST
       LIMIT 1;
      IF FOUND THEN
        NEW.last_service_km := COALESCE(NULLIF(NEW.last_service_km, 0), v_km);
        NEW.last_service_date := COALESCE(NEW.last_service_date, v_date);
        NEW.last_performed := COALESCE(NEW.last_performed, v_date);
        NEW.baseline_source := 'log';
        RETURN NEW;
      END IF;
    END IF;
    -- start plánu = teď (formulář „Pravidelný servis“ posílá start v next_due → je to začátek, ne termín)
    IF NEW.last_service_date IS NULL THEN
      NEW.last_service_date := COALESCE(NEW.next_due, CURRENT_DATE);
      NEW.last_performed := COALESCE(NEW.last_performed, NEW.last_service_date);
      NEW.next_due := NULL;
    END IF;
    IF NULLIF(NEW.last_service_km, 0) IS NULL THEN
      SELECT m.mileage INTO NEW.last_service_km FROM motorcycles m WHERE m.id = NEW.moto_id;
    END IF;
    NEW.baseline_source := 'manual';
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'maintenance_schedules_defaults failed: %', SQLERRM;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_maintenance_schedules_defaults ON public.maintenance_schedules;
CREATE TRIGGER trg_maintenance_schedules_defaults
  BEFORE INSERT OR UPDATE ON public.maintenance_schedules
  FOR EACH ROW EXECUTE FUNCTION public.maintenance_schedules_defaults();

-- ==========================================================================
-- (B4) Součet faktur k záznamu
-- ==========================================================================
CREATE OR REPLACE FUNCTION public._maintenance_invoices_sum() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE v_ids uuid[];
BEGIN
  v_ids := ARRAY(SELECT DISTINCT x FROM unnest(ARRAY[CASE WHEN TG_OP <> 'DELETE' THEN NEW.maintenance_log_id END,
                                                     CASE WHEN TG_OP <> 'INSERT' THEN OLD.maintenance_log_id END]) x WHERE x IS NOT NULL);
  UPDATE maintenance_log ml
     SET invoiced_amount = COALESCE((SELECT sum(mi.amount) FROM maintenance_invoices mi WHERE mi.maintenance_log_id = ml.id), 0)
   WHERE ml.id = ANY (v_ids);
  RETURN COALESCE(NEW, OLD);
END $$;

DROP TRIGGER IF EXISTS trg_maintenance_invoices_sum ON public.maintenance_invoices;
CREATE TRIGGER trg_maintenance_invoices_sum
  AFTER INSERT OR UPDATE OF amount, maintenance_log_id OR DELETE ON public.maintenance_invoices
  FOR EACH ROW EXECUTE FUNCTION public._maintenance_invoices_sum();

-- ==========================================================================
-- (B5) Plány základního standardu pro každou motorku
-- ==========================================================================
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
  v_created int := 0; v_updated int := 0; v_motos int := 0;
  v_applies boolean;
  v_source  text;
  v_mh      boolean;
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
    FOR c IN SELECT * FROM service_task_catalog ct WHERE ct.active AND ct.tracked ORDER BY ct.sort_order LOOP
      v_applies := CASE
        WHEN c.only_for IS NULL THEN true
        WHEN c.only_for IN ('chain', 'shaft', 'belt') THEN COALESCE(m.drivetrain, 'chain') = c.only_for
        WHEN c.only_for = 'liquid' THEN COALESCE(m.engine_type, '') !~* '(vzduch|air)'
        WHEN c.only_for = 'hours' THEN v_mh
        ELSE false END;
      IF NOT v_applies THEN CONTINUE; END IF;

      -- 1) interval dle výrobce (nejdelší = nejkonkrétnější vzor modelu)
      SELECT p.interval_km, p.interval_months, p.note INTO v_p_km, v_p_months, v_p_note
        FROM service_interval_presets p
       WHERE p.task_key = c.key
         AND m.model ILIKE p.model_pattern
         AND (p.brand_pattern IS NULL OR COALESCE(m.brand, '') ILIKE p.brand_pattern)
         AND (p.year_from IS NULL OR m.year IS NULL OR m.year >= p.year_from)
         AND (p.year_to IS NULL OR m.year IS NULL OR m.year <= p.year_to)
       ORDER BY length(p.model_pattern) DESC, (p.brand_pattern IS NOT NULL) DESC
       LIMIT 1;
      v_has_preset := FOUND;
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
        ELSIF v_sched.source <> 'manual' AND (p_reset OR v_sched.source <> v_source
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

  RETURN jsonb_build_object('ok', true, 'motos', v_motos, 'created', v_created, 'updated', v_updated);
END $$;

COMMENT ON FUNCTION public.service_plan_apply_presets(uuid, boolean) IS
  'Založí/aktualizuje plány základního standardu (service_task_catalog.tracked) pro motorky: interval = výrobce (service_interval_presets) > karta motorky > katalog (mh bez katalogových km); baseline = poslední dokončený servis s úkonem, jinak pořízení. Ruční plány (source=manual) nemění, vyřazené (active=false) znovu nezakládá (jen p_reset). Volá cron-daily (auto_schedule_services) a Velín.';

-- cron-daily: původní auto_schedule_services (mimo migrace) nastavovala next_due na +14 dní podle legacy
-- sloupce mileage_at_service a zakládala plán „STK“ — nahrazeno založením plánů standardu novým motorkám.
CREATE OR REPLACE FUNCTION public.auto_schedule_services() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM public.service_plan_apply_presets(NULL, false);
END $$;

-- ==========================================================================
-- (B6) Hlídání intervalů
-- ==========================================================================
DROP FUNCTION IF EXISTS public.get_service_due(uuid);
CREATE OR REPLACE FUNCTION public.get_service_due(p_moto_id uuid DEFAULT NULL)
RETURNS TABLE (
  schedule_id uuid, moto_id uuid, model text, spz text, branch_id uuid, moto_status text, tracking_unit text,
  task_key text, label text, group_label text, kind text, source text, interval_km integer, interval_days integer,
  last_km integer, last_date date, baseline_source text, km_estimated boolean, current_km integer, next_km integer, km_remaining integer,
  next_date date, days_remaining integer, avg_daily_km numeric, est_date date, planned_date date, state text, open_log_id uuid)
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  WITH m AS (
    SELECT mo.id, mo.model, mo.spz, mo.branch_id, mo.status::text AS status, COALESCE(mo.tracking_unit, 'km') AS unit,
           COALESCE(mo.mileage, 0) AS cur, mo.purchase_mileage, mo.acquired_at,
           CASE WHEN mo.purchase_mileage IS NOT NULL AND mo.acquired_at IS NOT NULL
                     AND COALESCE(mo.mileage, 0) > mo.purchase_mileage AND CURRENT_DATE - mo.acquired_at >= 14
                THEN LEAST(CASE WHEN COALESCE(mo.tracking_unit, 'km') = 'mh' THEN 8 ELSE 300 END,
                           GREATEST(CASE WHEN COALESCE(mo.tracking_unit, 'km') = 'mh' THEN 0.1 ELSE 5 END,
                                    (COALESCE(mo.mileage, 0) - mo.purchase_mileage)::numeric / (CURRENT_DATE - mo.acquired_at)))
                ELSE CASE WHEN COALESCE(mo.tracking_unit, 'km') = 'mh' THEN 0.5 ELSE 40 END END AS daily
      FROM motorcycles mo
     WHERE mo.status <> 'retired' AND mo.is_trailer IS NOT TRUE AND (p_moto_id IS NULL OR mo.id = p_moto_id)
  ), open_logs AS (   -- otevřené záznamy s úkonem z katalogu = úkon už naplánován
    SELECT ml.moto_id, e->>'key' AS k, (array_agg(ml.id ORDER BY ml.service_date, ml.created_at))[1] AS log_id
      FROM maintenance_log ml
      CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(ml.items) = 'array' THEN ml.items ELSE '[]'::jsonb END) e
     WHERE ml.completed_date IS NULL AND ml.is_test IS NOT TRUE AND NULLIF(e->>'key', '') IS NOT NULL
       AND (p_moto_id IS NULL OR ml.moto_id = p_moto_id)
     GROUP BY ml.moto_id, e->>'key'
  ), base AS (
    SELECT s.id AS schedule_id, m.id AS moto_id, m.model, m.spz, m.branch_id, m.status, m.unit, s.task_key,
           COALESCE(c.label, s.description) AS label, c.group_label, c.kind, s.source, s.interval_km, s.interval_days,
           s.last_service_date AS last_date, s.baseline_source, m.cur, m.purchase_mileage, m.acquired_at, m.daily, s.next_due AS planned_date,
           s.first_service_km,
           -- km baseline: zapsané km; bez nich u baseline ze záznamu / ručně dopočet z data a Ø nájezdu (km_estimated)
           NULLIF(s.last_service_km, 0) AS last_km_raw,
           CASE WHEN NULLIF(s.last_service_km, 0) IS NULL AND s.last_service_date IS NOT NULL AND s.baseline_source IN ('log', 'manual')
                THEN GREATEST(COALESCE(m.purchase_mileage, 0), m.cur - round(m.daily * (CURRENT_DATE - s.last_service_date)))::int END AS last_km_est
      FROM maintenance_schedules s
      JOIN m ON m.id = s.moto_id
      LEFT JOIN service_task_catalog c ON c.key = s.task_key
     WHERE s.active = true
  ), calc AS (
    SELECT b.*, COALESCE(b.last_km_raw, b.last_km_est) AS last_km, (b.last_km_raw IS NULL AND b.last_km_est IS NOT NULL) AS km_est,
           CASE WHEN COALESCE(b.interval_km, 0) > 0 THEN
                  CASE WHEN COALESCE(b.last_km_raw, b.last_km_est) IS NOT NULL THEN COALESCE(b.last_km_raw, b.last_km_est) + b.interval_km
                       WHEN b.first_service_km IS NOT NULL AND b.purchase_mileage IS NOT NULL THEN b.purchase_mileage + b.first_service_km
                       WHEN b.purchase_mileage IS NOT NULL THEN b.purchase_mileage + b.interval_km END END AS next_km,
           CASE WHEN COALESCE(b.interval_days, 0) > 0 THEN
                  CASE WHEN b.last_date IS NOT NULL THEN b.last_date + b.interval_days
                       WHEN b.acquired_at IS NOT NULL THEN b.acquired_at + b.interval_days END END AS next_date
      FROM base b
  ), st AS (
    SELECT c.*, (c.next_km - c.cur) AS km_rem, (c.next_date - CURRENT_DATE) AS days_rem,
           CASE WHEN c.unit = 'mh' THEN LEAST(10, GREATEST(c.interval_km * 0.2, 2)) ELSE LEAST(1000, GREATEST(c.interval_km * 0.2, 200)) END AS km_soon,
           LEAST(45, GREATEST(c.interval_days * 0.2, 14)) AS days_soon,
           -- kontrola / seřízení s baseline jen „od pořízení“ = neověřeno, ne falešné „po termínu“
           (c.baseline_source = 'acquisition' AND COALESCE(c.kind, '') IN ('check', 'adjust')) AS unverified
      FROM calc c
  )
  SELECT st.schedule_id, st.moto_id, st.model, st.spz, st.branch_id, st.status, st.unit, st.task_key, st.label, st.group_label,
         st.kind, st.source, st.interval_km, st.interval_days, st.last_km, st.last_date, st.baseline_source, st.km_est, st.cur,
         st.next_km, st.km_rem, st.next_date, st.days_rem, round(st.daily, 1),
         CASE WHEN st.next_km IS NOT NULL AND st.km_rem <= 0 THEN CURRENT_DATE
              WHEN st.next_km IS NOT NULL AND st.daily > 0 THEN LEAST(COALESCE(st.next_date, 'infinity'::date), CURRENT_DATE + ceil(st.km_rem / st.daily)::int)
              ELSE st.next_date END AS est_date,
         st.planned_date,
         CASE WHEN COALESCE(st.interval_km, 0) = 0 AND COALESCE(st.interval_days, 0) = 0 THEN 'no_interval'
              WHEN st.unverified THEN 'unknown'
              WHEN (st.next_km IS NOT NULL AND st.km_rem <= 0) OR (st.next_date IS NOT NULL AND st.days_rem <= 0) THEN 'overdue'
              WHEN st.next_km IS NULL AND st.next_date IS NULL THEN 'unknown'
              WHEN (st.next_km IS NOT NULL AND st.km_rem <= st.km_soon) OR (st.next_date IS NOT NULL AND st.days_rem <= st.days_soon) THEN 'due_soon'
              ELSE 'ok' END AS state,
         ol.log_id AS open_log_id
    FROM st
    LEFT JOIN open_logs ol ON ol.moto_id = st.moto_id AND ol.k = st.task_key
   ORDER BY CASE WHEN COALESCE(st.interval_km, 0) = 0 AND COALESCE(st.interval_days, 0) = 0 THEN 4
                 WHEN st.unverified THEN 3
                 WHEN (st.next_km IS NOT NULL AND st.km_rem <= 0) OR (st.next_date IS NOT NULL AND st.days_rem <= 0) THEN 0
                 WHEN (st.next_km IS NOT NULL AND st.km_rem <= st.km_soon) OR (st.next_date IS NOT NULL AND st.days_rem <= st.days_soon) THEN 1
                 WHEN st.next_km IS NULL AND st.next_date IS NULL THEN 3 ELSE 2 END,
            LEAST(COALESCE(st.km_rem, 999999), COALESCE(st.days_rem, 999999) * 40), st.model, st.label;
$$;

COMMENT ON FUNCTION public.get_service_due(uuid) IS
  'Hlídání servisních intervalů (2026-10-08): per aktivní plán zbývající km/dny, odhad termínu z Ø denního nájezdu (od pořízení), km baseline dopočtená z data (km_estimated), stav overdue/due_soon/ok/unknown/no_interval (kontroly s baseline od pořízení = unknown), open_log_id = otevřený záznam s tímto úkonem (už naplánováno). Vozík a vyřazené vynechává.';

CREATE OR REPLACE FUNCTION public.get_service_due_count() RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  SELECT jsonb_build_object(
    'overdue',  count(*) FILTER (WHERE d.state = 'overdue'  AND d.open_log_id IS NULL),
    'due_soon', count(*) FILTER (WHERE d.state = 'due_soon' AND d.open_log_id IS NULL),
    'unknown',  count(*) FILTER (WHERE d.state = 'unknown'),
    'planned',  count(*) FILTER (WHERE d.open_log_id IS NOT NULL),
    'motos_overdue', count(DISTINCT d.moto_id) FILTER (WHERE d.state = 'overdue' AND d.open_log_id IS NULL))
  FROM public.get_service_due(NULL) d
  WHERE d.moto_status IN ('active', 'maintenance', 'unavailable');
$$;

-- Poslední dokončený servis každé motorky (Servis → Servisní knížka — přehled bez stahování celého logu)
CREATE OR REPLACE FUNCTION public.get_last_service_per_moto()
RETURNS TABLE (moto_id uuid, log_id uuid, completed_date date, km_at_service integer, performed_by text)
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  SELECT DISTINCT ON (ml.moto_id) ml.moto_id, ml.id, ml.completed_date::date, ml.km_at_service, ml.performed_by
    FROM maintenance_log ml
   WHERE ml.completed_date IS NOT NULL AND ml.is_test IS NOT TRUE AND ml.moto_id IS NOT NULL
   ORDER BY ml.moto_id, ml.completed_date DESC, ml.created_at DESC;
$$;

-- Práva: jen přihlášený Velín / server (anon má v projektu default EXECUTE na nové funkce → výslovně odebrat)
REVOKE ALL ON FUNCTION public.service_plan_apply_presets(uuid, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.auto_schedule_services() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_service_due(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_service_due_count() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_last_service_per_moto() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.service_plan_apply_presets(uuid, boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.auto_schedule_services() TO service_role;
GRANT EXECUTE ON FUNCTION public.get_service_due(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_service_due_count() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_last_service_per_moto() TO authenticated, service_role;

-- ==========================================================================
-- (B7) Backfill
-- ==========================================================================
UPDATE public.maintenance_log
   SET items = public._service_items_with_keys(items)
 WHERE jsonb_typeof(items) = 'array'
   AND EXISTS (SELECT 1 FROM jsonb_array_elements(items) e
                WHERE NULLIF(e->>'key', '') IS NULL AND COALESCE((e->>'custom')::boolean, false) = false
                  AND public.service_task_key_for_label(e->>'label') IS NOT NULL);

-- Stará verze Velína při hromadném uzavření („Vrátit do provozu“) úkony neodškrtávala: dokončený záznam, kde
-- není odškrtnut ani jeden úkon, bereme jako provedený (done_legacy — v knížce označeno „historicky“).
UPDATE public.maintenance_log
   SET items = (SELECT jsonb_agg(CASE WHEN jsonb_typeof(e) = 'object' THEN e || '{"done": true, "done_legacy": true}'::jsonb ELSE e END ORDER BY ord)
                  FROM jsonb_array_elements(items) WITH ORDINALITY t(e, ord))
 WHERE completed_date IS NOT NULL AND created_at < '2026-10-09'
   AND jsonb_typeof(items) = 'array' AND jsonb_array_length(items) > 0
   AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(items) e WHERE COALESCE((e->>'done')::boolean, false) OR (e ? 'done_legacy'));

UPDATE public.maintenance_log SET km_auto = true
 WHERE completed_date IS NULL AND km_at_service IS NOT NULL AND km_auto = false;

-- seřízení řetězu (1 000 km) se jako plán nehlídá (jen úkon v checklistu) — případné automatické plány vyřadit
UPDATE public.maintenance_schedules SET active = false, updated_at = now()
 WHERE task_key = 'chain_adjust' AND source <> 'manual' AND active = true;

SELECT public.service_plan_apply_presets(NULL, false);
