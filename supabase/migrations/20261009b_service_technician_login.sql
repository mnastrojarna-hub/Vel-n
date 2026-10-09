-- 20261009b — Servis: technik / autor = VŽDY přihlášený účet. Zadání majitele 2026-10-09: „když se přihlásím do
-- servisu, vše co vyplňuji se musí ukládat pod názvem loginu — Honza Chuděj nikdy nemůže psát za admina“.
--  (1) maintenance_log_autofill (NAHRAZENA, verze z 20261008b + zámek): účet, který NENÍ superadmin, zapisuje
--      servis vždy pod sebou — technician_admin_id = auth.uid(), performed_by = jméno účtu, technician_id = NULL
--      (při založení i při každé úpravě obsahu: úkony, zpráva, stav, dokončení, km, zadání, cena, termíny);
--      DOKONČENÝ servis jiného technika takový účet upravit nemůže (výjimka P0403 — Velín ukáže hlášku).
--      Změna jen faktur (invoiced_amount — trigger součtu) se nepočítá jako zápis technika.
--      Superadmin může technika zvolit (externí servis, zaměstnanec); prázdný technik = on sám při dokončení.
--  (2) maintenance_invoices: uploaded_by / uploaded_by_name = přihlášený účet (BEFORE INSERT).
--  (3) _service_done_task_keys: type winter_service bez checklistu = full_service (shoda s Velínem).
-- Idempotentní (CREATE OR REPLACE / DROP IF EXISTS).

CREATE OR REPLACE FUNCTION public.maintenance_log_autofill() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_admin_name text;
  v_super      boolean := false;
  v_lock       boolean := false;   -- běžný účet (ne superadmin): technik = on sám
  v_touch      boolean := false;   -- úprava obsahu záznamu (ne jen součet faktur)
  v_mileage    integer;
  v_completing boolean;
  v_current    boolean;   -- záznam se týká současnosti (ne zpětně datovaný) → km ze stavu tachometru
BEGIN
  IF v_uid IS NOT NULL THEN
    SELECT COALESCE(NULLIF(btrim(a.name), ''), a.email), COALESCE(a.role = 'superadmin', false)
      INTO v_admin_name, v_super
      FROM admin_users a WHERE a.id = v_uid AND a.active;
  END IF;
  v_lock := v_uid IS NOT NULL AND NOT v_super AND v_admin_name IS NOT NULL;
  IF NEW.moto_id IS NOT NULL THEN
    SELECT m.mileage INTO v_mileage FROM motorcycles m WHERE m.id = NEW.moto_id;
  END IF;
  v_current := NEW.completed_date IS NULL OR NEW.completed_date::date >= CURRENT_DATE - 1;

  IF TG_OP = 'UPDATE' THEN
    v_touch := NEW.items IS DISTINCT FROM OLD.items OR NEW.technician_report IS DISTINCT FROM OLD.technician_report
            OR NEW.description IS DISTINCT FROM OLD.description OR NEW.status IS DISTINCT FROM OLD.status
            OR NEW.completed_date IS DISTINCT FROM OLD.completed_date OR NEW.km_at_service IS DISTINCT FROM OLD.km_at_service
            OR NEW.cost IS DISTINCT FROM OLD.cost OR NEW.labor_hours IS DISTINCT FROM OLD.labor_hours OR NEW.extra_cost IS DISTINCT FROM OLD.extra_cost
            OR NEW.service_date IS DISTINCT FROM OLD.service_date OR NEW.scheduled_date IS DISTINCT FROM OLD.scheduled_date
            OR NEW.performed_by IS DISTINCT FROM OLD.performed_by OR NEW.technician_admin_id IS DISTINCT FROM OLD.technician_admin_id
            OR NEW.technician_id IS DISTINCT FROM OLD.technician_id OR NEW.service_type IS DISTINCT FROM OLD.service_type
            OR NEW.is_urgent IS DISTINCT FROM OLD.is_urgent;
    -- dokončený servis jiného technika běžný účet neupravuje
    IF v_lock AND v_touch AND (COALESCE(OLD.status, '') = 'completed' OR OLD.completed_date IS NOT NULL)
       AND ((OLD.technician_admin_id IS NOT NULL AND OLD.technician_admin_id <> v_uid)
            OR (OLD.technician_admin_id IS NULL AND NULLIF(btrim(COALESCE(OLD.performed_by, '')), '') IS NOT NULL AND OLD.performed_by <> v_admin_name)) THEN
      RAISE EXCEPTION 'Dokončený servis technika „%“ nelze upravit pod účtem „%“ — zapište vlastní servisní záznam.', OLD.performed_by, v_admin_name
        USING ERRCODE = 'P0403';
    END IF;
  END IF;

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

  -- běžný účet zapisuje VŽDY pod sebou (nikdy za admina ani za jiného technika)
  IF v_lock AND (TG_OP = 'INSERT' OR v_touch) THEN
    NEW.technician_admin_id := v_uid;
    NEW.technician_id := NULL;
    NEW.performed_by := v_admin_name;
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
    -- technik = kdo servis dokončil (přihlášený účet Velína), pokud nebyl zadán jiný (jen superadmin může zadat jiného)
    IF v_admin_name IS NOT NULL THEN
      IF NEW.technician_admin_id IS NULL AND NEW.technician_id IS NULL AND NULLIF(btrim(COALESCE(NEW.performed_by, '')), '') IS NULL THEN
        NEW.technician_admin_id := v_uid;
      END IF;
      IF NULLIF(btrim(COALESCE(NEW.performed_by, '')), '') IS NULL AND NEW.technician_id IS NULL THEN NEW.performed_by := v_admin_name; END IF;
    END IF;
  END IF;
  -- technik zvolený účtem Velína bez jména → doplnit jméno z admin_users
  IF NEW.technician_admin_id IS NOT NULL AND NULLIF(btrim(COALESCE(NEW.performed_by, '')), '') IS NULL THEN
    SELECT COALESCE(NULLIF(btrim(a.name), ''), a.email) INTO NEW.performed_by FROM admin_users a WHERE a.id = NEW.technician_admin_id;
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE = 'P0403' THEN RAISE; END IF;   -- zámek technika je záměrná chyba pro Velín
  RAISE WARNING 'maintenance_log_autofill failed for log %: %', NEW.id, SQLERRM;
  RETURN NEW;
END $$;

COMMENT ON FUNCTION public.maintenance_log_autofill() IS
  'BEFORE INSERT/UPDATE maintenance_log (2026-10-08, rev. 2026-10-09b): klíče úkonů, km ze stavu tachometru (km_auto), created/updated/completed_by, technik = přihlášený účet při dokončení. Účet, který není superadmin, zapisuje vždy pod sebou (technician_admin_id/performed_by = login; nikdy za admina) a dokončený servis jiného technika neupraví (P0403). Změna jen invoiced_amount zámek nespouští.';

-- (2) faktura k servisu = nahrál přihlášený účet
CREATE OR REPLACE FUNCTION public.maintenance_invoices_uploader() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE v_uid uuid := auth.uid(); v_name text;
BEGIN
  IF v_uid IS NOT NULL THEN
    SELECT COALESCE(NULLIF(btrim(a.name), ''), a.email) INTO v_name FROM admin_users a WHERE a.id = v_uid AND a.active;
    IF v_name IS NOT NULL THEN
      NEW.uploaded_by := v_uid;
      NEW.uploaded_by_name := v_name;
    END IF;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_maintenance_invoices_uploader ON public.maintenance_invoices;
CREATE TRIGGER trg_maintenance_invoices_uploader
  BEFORE INSERT ON public.maintenance_invoices
  FOR EACH ROW EXECUTE FUNCTION public.maintenance_invoices_uploader();

-- (3) „Velký zimní servis“ (type winter_service) bez checklistu = kompletní servis (olej, filtr, kontroly) — Velín
--     ho tak v knize zobrazuje (TYPE_KEYS), DB ho dosud nepočítala → plány se po zimní prohlídce neposunuly.
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
                    WHEN 'oil_change'      THEN ARRAY['oil_change','oil_filter']
                    WHEN 'tire_change'     THEN ARRAY['tire_front','tire_rear']
                    WHEN 'full_service'    THEN ARRAY['full_service']
                    WHEN 'winter_service'  THEN ARRAY['full_service']
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
