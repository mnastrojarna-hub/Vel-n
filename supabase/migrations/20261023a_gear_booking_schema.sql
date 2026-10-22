-- =============================================================================
-- 2026-10-23 (a): Výpůjčka JEN výbavy jako běžná rezervace — základ schématu
-- Zadání majitele: výpůjčka oblečení/výbavy bez motorky se má chovat jako
-- rezervace (seznam rezervací ve Velínu, stejné stavy, kódy šatna + brána na
-- samoobsluze, protokol s velikostmi, e-maily ze šablon Velínu).
-- Řádek `bookings` s booking_kind='gear': moto_id NULL, pobočka v branch_id,
-- naceněné řádky v gear_lines (tvar = _gear_rental_quote().lines), cena/den
-- v gear_per_day, velikosti v helmet/jacket/pants/gloves/boots_size.
-- `moto_id IS NULL` samo o sobě gear NEZNAMENÁ (FK ON DELETE SET NULL).
-- Zákazník (JWT, ne admin) mění gear řádky JEN přes RPC (GUC motogo.gear_rpc);
-- přímý SELECT/UPDATE/INSERT/DELETE gear řádků zákazníkem blokuje RESTRICTIVE
-- RLS — stará appka je nevidí, dokud Velín nezapne gear_rental.app_visible.
-- Navazují: 20261023b (RPC/sklad/doklady), c (kódy/kiosek), d (šablony/doklady),
-- e (vratky při zkrácení). Idempotentní.
-- =============================================================================

-- ---- 1) Sloupce + tvar gear řádku -------------------------------------------
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS booking_kind text NOT NULL DEFAULT 'moto';
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS gear_lines jsonb;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS gear_per_day numeric(10,2);
COMMENT ON COLUMN public.bookings.booking_kind IS 'moto = rezervace motorky (výchozí), gear = výpůjčka jen výbavy bez motorky (2026-10-23).';
COMMENT ON COLUMN public.bookings.gear_lines IS 'Jen booking_kind=gear: naceněné řádky [{key,kind,label,includes,sizes,price_per_day,total}] (_gear_rental_quote × dny).';
COMMENT ON COLUMN public.bookings.gear_per_day IS 'Jen booking_kind=gear: cena výbavy za den (Kč) v okamžiku objednání/poslední změny.';

DO $$ BEGIN
  ALTER TABLE public.bookings ADD CONSTRAINT bookings_booking_kind_check CHECK (booking_kind IN ('moto', 'gear'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE public.bookings ADD CONSTRAINT bookings_gear_shape CHECK (
    booking_kind <> 'gear' OR (
      moto_id IS NULL AND trailer_moto_id IS NULL AND own_gear IS NOT TRUE
      AND sos_replacement IS NOT TRUE
      AND COALESCE(pickup_method, 'store') <> 'delivery' AND COALESCE(return_method, 'store') <> 'delivery'
      AND jsonb_typeof(gear_lines) = 'array' AND gear_per_day IS NOT NULL
    ));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_bookings_gear_branch_dates
  ON public.bookings (branch_id, start_date, end_date) WHERE booking_kind = 'gear';

-- ---- 2) Pomocné funkce --------------------------------------------------------
CREATE OR REPLACE FUNCTION public._booking_is_gear(p_booking_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT booking_kind = 'gear' FROM bookings WHERE id = p_booking_id), false);
$$;

-- Pobočka rezervace: gear = bookings.branch_id, motorka = pobočka motorky
-- (zachovává dosavadní chování funkcí, které braly m.branch_id).
CREATE OR REPLACE FUNCTION public.booking_effective_branch(p_booking_id uuid)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE WHEN b.booking_kind = 'gear' THEN b.branch_id ELSE m.branch_id END
    FROM bookings b LEFT JOIN motorcycles m ON m.id = b.moto_id
   WHERE b.id = p_booking_id;
$$;

-- Vidí zákazník (JWT) své gear rezervace přímým SELECTem? Až appka umí gear.
CREATE OR REPLACE FUNCTION public._gear_customer_visible()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT (value->>'app_visible')::boolean FROM app_settings WHERE key = 'gear_rental'), false);
$$;

REVOKE ALL ON FUNCTION public._booking_is_gear(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.booking_effective_branch(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._gear_customer_visible() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._booking_is_gear(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.booking_effective_branch(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._gear_customer_visible() TO anon, authenticated, service_role;

-- ---- 3) Strážce gear řádku (BEFORE, jméno řadí na konec → po _booking_set_branch) --
CREATE OR REPLACE FUNCTION public._gear_booking_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  -- zákazník = přihlášený JWT, ne admin, a změna nejde přes gear RPC
  v_cust boolean := auth.uid() IS NOT NULL AND NOT public.is_admin()
                    AND COALESCE(current_setting('motogo.gear_rpc', true), '') <> '1';
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.booking_kind IS DISTINCT FROM OLD.booking_kind THEN
    RAISE EXCEPTION 'booking_kind_immutable' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.booking_kind IS DISTINCT FROM 'gear' THEN RETURN NEW; END IF;

  IF TG_OP = 'INSERT' AND v_cust THEN
    RAISE EXCEPTION 'gear_booking_rpc_only' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NEW.branch_id IS NULL THEN
    RAISE EXCEPTION 'gear_booking_branch_required' USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'UPDATE' AND v_cust AND (
       NEW.start_date IS DISTINCT FROM OLD.start_date OR NEW.end_date IS DISTINCT FROM OLD.end_date
    OR NEW.total_price IS DISTINCT FROM OLD.total_price OR NEW.extras_price IS DISTINCT FROM OLD.extras_price
    OR NEW.gear_lines IS DISTINCT FROM OLD.gear_lines OR NEW.gear_per_day IS DISTINCT FROM OLD.gear_per_day
    OR NEW.branch_id IS DISTINCT FROM OLD.branch_id OR NEW.moto_id IS DISTINCT FROM OLD.moto_id
    OR NEW.helmet_size IS DISTINCT FROM OLD.helmet_size OR NEW.jacket_size IS DISTINCT FROM OLD.jacket_size
    OR NEW.pants_size IS DISTINCT FROM OLD.pants_size OR NEW.gloves_size IS DISTINCT FROM OLD.gloves_size
    OR NEW.boots_size IS DISTINCT FROM OLD.boots_size OR NEW.discount_amount IS DISTINCT FROM OLD.discount_amount) THEN
    RAISE EXCEPTION 'gear_booking_rpc_only' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- výpůjčka výbavy musí mít aspoň jeden kus (jinak by zanikl kód šatny)
  IF COALESCE(NEW.helmet_size, NEW.jacket_size, NEW.pants_size, NEW.gloves_size, NEW.boots_size) IS NULL THEN
    RAISE EXCEPTION 'gear_booking_needs_item' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public._gear_booking_guard() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_zz_gear_booking_guard ON public.bookings;
CREATE TRIGGER trg_zz_gear_booking_guard BEFORE INSERT OR UPDATE ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public._gear_booking_guard();

-- ---- 4) RLS: gear řádky jen přes RPC (zákazník) / plně pro admina -----------
-- RESTRICTIVE = AND se stávajícími permisivními politikami. service_role a
-- SECURITY DEFINER funkce (vlastník tabulky) RLS obcházejí.
DROP POLICY IF EXISTS bookings_gear_customer_select ON public.bookings;
CREATE POLICY bookings_gear_customer_select ON public.bookings AS RESTRICTIVE FOR SELECT
  USING (booking_kind <> 'gear' OR public.is_admin() OR public._gear_customer_visible());
DROP POLICY IF EXISTS bookings_gear_admin_insert ON public.bookings;
CREATE POLICY bookings_gear_admin_insert ON public.bookings AS RESTRICTIVE FOR INSERT
  WITH CHECK (booking_kind <> 'gear' OR public.is_admin());
DROP POLICY IF EXISTS bookings_gear_admin_update ON public.bookings;
CREATE POLICY bookings_gear_admin_update ON public.bookings AS RESTRICTIVE FOR UPDATE
  USING (booking_kind <> 'gear' OR public.is_admin()) WITH CHECK (booking_kind <> 'gear' OR public.is_admin());
DROP POLICY IF EXISTS bookings_gear_admin_delete ON public.bookings;
CREATE POLICY bookings_gear_admin_delete ON public.bookings AS RESTRICTIVE FOR DELETE
  USING (booking_kind <> 'gear' OR public.is_admin());

-- ---- 5) Nastavení (Velín) -----------------------------------------------------
-- gear_rental.app_visible: zobrazovat gear rezervace přímo v appce (až po vydání podpory).
INSERT INTO public.app_settings (key, value)
VALUES ('gear_rental', '{"enabled": true, "max_days": 30, "max_ahead_days": 400, "app_visible": false}'::jsonb)
ON CONFLICT (key) DO UPDATE SET value = public.app_settings.value || '{"app_visible": false}'::jsonb
  WHERE NOT (public.app_settings.value ? 'app_visible');

-- Kontrola skladu výbavy (Logistika zboží): gear_rental = blokovat výpůjčku výbavy
-- bez volného kusu; moto_booking = rezervace motorek (zatím jen hlídání); keep_free =
-- kusy držené pro zákazníky s motorkou.
INSERT INTO public.app_settings (key, value)
VALUES ('gear_stock_check', '{"gear_rental": false, "moto_booking": false, "keep_free": 0}'::jsonb)
ON CONFLICT (key) DO NOTHING;

NOTIFY pgrst, 'reload schema';
