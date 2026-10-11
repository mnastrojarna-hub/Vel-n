-- =============================================================================
-- 2026-10-11 BEZPEČNOST: anonymně volatelné webové settery / potvrzení
-- Host bez přihlášení dál projde kroky 1–6, QR PC→mobil, odkazy z mailů i Stripe;
-- nositel UUID (anon i cizí přihlášený) zapisuje jen do ŽIVÉ webové rezervace.
-- Helpery _web_booking_full_access / _is_live: 20261011a. Těla = živá definice,
-- měněno jen označené (2026-10-11). Idempotentní.
-- =============================================================================

-- 1) Firemní údaje: nositel odkazu jen u účtu, který tato rezervace právě
--    založila (jako set_web_booking_password) — ten smí údaje i opravit
--    (návrat do kroku 1 a nové odeslání).
CREATE OR REPLACE FUNCTION public.set_web_booking_company(p_booking_id uuid, p_company_name text DEFAULT NULL::text, p_ico text DEFAULT NULL::text, p_dic text DEFAULT NULL::text, p_company_address text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid;
  v_full boolean;  -- 2026-10-11
BEGIN
  -- Klíčováno přes booking_id, jen web rezervace (vzor set_web_booking_docs)
  SELECT user_id INTO v_user_id
    FROM bookings
   WHERE id = p_booking_id
     AND booking_source = 'web';

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'booking_not_found');
  END IF;

  v_full := public._web_booking_full_access(v_user_id);
  IF NOT v_full AND NOT public._web_booking_created_account(p_booking_id) THEN
    RETURN jsonb_build_object('error', 'login_required');
  END IF;

  -- COALESCE(NULLIF(trim(...))) — prázdné hodnoty nepřepíší existující
  UPDATE profiles SET
    company_name    = COALESCE(NULLIF(trim(p_company_name), ''), company_name),
    ico             = COALESCE(NULLIF(trim(p_ico), ''), ico),
    dic             = COALESCE(NULLIF(trim(p_dic), ''), dic),
    company_address = COALESCE(NULLIF(trim(p_company_address), ''), company_address)
  WHERE id = v_user_id;

  RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$function$;

-- 2) Zařízení (analytika): nositel jen u živé rozpracované (pending) rezervace
CREATE OR REPLACE FUNCTION public.set_web_booking_device(p_booking_id uuid, p_device text, p_phase text DEFAULT 'created'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_source text;
  v_device text;
  v_user uuid;     -- 2026-10-11
  v_status text;   -- 2026-10-11
BEGIN
  IF p_booking_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Booking ID je povinné');
  END IF;

  v_device := CASE lower(COALESCE(p_device, ''))
    WHEN 'pc' THEN 'pc'
    WHEN 'desktop' THEN 'pc'
    WHEN 'mobile' THEN 'mobile'
    WHEN 'phone' THEN 'mobile'
    WHEN 'tablet' THEN 'tablet'
    ELSE NULL
  END;
  IF v_device IS NULL THEN
    RETURN jsonb_build_object('error', 'Neznámé zařízení');
  END IF;

  SELECT booking_source, user_id, status::text INTO v_source, v_user, v_status
    FROM bookings WHERE id = p_booking_id;
  IF v_source IS NULL THEN
    RETURN jsonb_build_object('error', 'Rezervace nenalezena');
  END IF;
  IF v_source IS DISTINCT FROM 'web' THEN
    RETURN jsonb_build_object('error', 'Pouze pro webové rezervace');
  END IF;
  IF NOT public._web_booking_full_access(v_user)
     AND NOT (v_status = 'pending' AND public._web_booking_is_live(p_booking_id)) THEN
    RETURN jsonb_build_object('error', 'login_required');
  END IF;

  IF p_phase = 'completed' THEN
    UPDATE bookings SET completed_device = v_device WHERE id = p_booking_id;
  ELSE
    UPDATE bookings SET created_device = v_device
      WHERE id = p_booking_id AND created_device IS NULL;
  END IF;

  RETURN jsonb_build_object('success', true);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$function$;

-- 3) Zvolená platba: nositel jen u živé rezervace
CREATE OR REPLACE FUNCTION public.set_web_booking_chosen_method(p_booking_id uuid, p_method text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user uuid;  -- 2026-10-11
BEGIN
  SELECT user_id INTO v_user FROM bookings WHERE id = p_booking_id AND booking_source = 'web';
  IF v_user IS NOT NULL AND NOT public._web_booking_full_access(v_user)
     AND NOT public._web_booking_is_live(p_booking_id) THEN
    RETURN jsonb_build_object('error', 'login_required');
  END IF;
  UPDATE bookings
     SET chosen_payment_method = LEFT(COALESCE(p_method, ''), 20),
         pay_channel = CASE WHEN p_method = 'card' THEN NULL ELSE pay_channel END
   WHERE id = p_booking_id
     AND booking_source = 'web'
     AND payment_status <> 'paid';
  RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$function$;

-- 4) Doklady dokončeny: nositel jen u živé rezervace (i odkaz z mailu po platbě)
CREATE OR REPLACE FUNCTION public.set_web_booking_docs_completed(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user uuid;  -- 2026-10-11
BEGIN
  SELECT user_id INTO v_user FROM bookings WHERE id = p_booking_id AND booking_source = 'web';
  IF v_user IS NOT NULL AND NOT public._web_booking_full_access(v_user)
     AND NOT public._web_booking_is_live(p_booking_id) THEN
    RETURN jsonb_build_object('error', 'login_required');
  END IF;
  UPDATE bookings
     SET docs_completed_at = COALESCE(docs_completed_at, now()),
         docs_fill_seconds = COALESCE(
           docs_fill_seconds,
           GREATEST(0, LEAST(604800, EXTRACT(EPOCH FROM (now() - COALESCE(confirmed_at, created_at)))::int))
         )
   WHERE id = p_booking_id
     AND booking_source = 'web';
  RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$function$;

-- 5) Doba vyplnění formuláře (analytika, zápis jednou): nositel jen u čerstvé pending
CREATE OR REPLACE FUNCTION public.set_booking_form_seconds(p_booking_id uuid, p_started_at timestamp with time zone)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  UPDATE public.bookings
     SET form_started_at   = p_started_at,
         form_fill_seconds = GREATEST(0, LEAST(86400, EXTRACT(EPOCH FROM (now() - p_started_at))::int))
   WHERE id = p_booking_id AND booking_source = 'web' AND form_started_at IS NULL
     AND p_started_at IS NOT NULL AND p_started_at <= now() AND p_started_at >= now() - interval '24 hours'
     AND (public._web_booking_full_access(user_id)                                  -- 2026-10-11
          OR (status = 'pending' AND created_at > now() - interval '24 hours'));
$function$;

-- 6) Storno rozpracované rezervace: vlastník / admin jako dosud; nositel jen
--    webovou pending+unpaid založenou před < 24 h (dřív jakoukoli, i z appky).
CREATE OR REPLACE FUNCTION public.cancel_pending_web_booking(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_row bookings%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;

  -- Zrušit jen rozpracovanou (pending) a nezaplacenou web rezervaci
  IF v_row.status = 'pending' AND v_row.payment_status = 'unpaid' THEN
    IF NOT public._web_booking_full_access(v_row.user_id)
       AND NOT COALESCE(v_row.booking_source = 'web' AND v_row.created_at > now() - interval '24 hours', false) THEN
      RETURN jsonb_build_object('success', false, 'error', 'not_cancelable', 'reason', 'login_required');
    END IF;
    UPDATE bookings
       SET status = 'cancelled', updated_at = now()
     WHERE id = p_booking_id;
    RETURN jsonb_build_object('success', true);
  END IF;

  RETURN jsonb_build_object('success', false, 'error', 'not_cancelable');
END;
$function$;

-- 7) Kolize termínu uživatele: jen {overlap}; cizí účet se neprověřuje (bylo
--    orákulum „kdy kdo jede" + UUID cizí rezervace). Web čte jen data.overlap.
CREATE OR REPLACE FUNCTION public.check_web_booking_user_overlap(p_email text, p_start date, p_end date, p_exclude_booking_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_uid uuid;
  v_row record;
BEGIN
  IF p_email IS NULL OR trim(p_email) = '' OR p_start IS NULL OR p_end IS NULL THEN
    RETURN jsonb_build_object('overlap', false);
  END IF;

  SELECT id INTO v_uid FROM auth.users
   WHERE lower(email) = lower(trim(p_email))
   LIMIT 1;

  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('overlap', false);  -- neznámý e-mail → žádná kolize
  END IF;

  -- 2026-10-11: jen vlastník / admin / service, nebo obnova vlastní rozpracované
  -- webové rezervace (jinak create_web_booking vrátí email_exists / email_mismatch)
  IF NOT public._web_booking_full_access(v_uid)
     AND NOT EXISTS (SELECT 1 FROM bookings eb
                      WHERE eb.id = p_exclude_booking_id AND eb.user_id = v_uid
                        AND eb.status = 'pending' AND eb.payment_status = 'unpaid'
                        AND eb.booking_source = 'web') THEN
    RETURN jsonb_build_object('overlap', false);
  END IF;

  SELECT b.id, b.start_date, b.end_date
    INTO v_row
    FROM bookings b
   WHERE b.user_id = v_uid
     AND b.status IN ('pending','reserved','active','completed')
     AND (p_exclude_booking_id IS NULL OR b.id <> p_exclude_booking_id)
     AND daterange(b.start_date::date, b.end_date::date, '[]')
         && daterange(p_start, p_end, '[]')
   ORDER BY b.start_date
   LIMIT 1;

  IF v_row.id IS NULL THEN
    RETURN jsonb_build_object('overlap', false);
  END IF;

  RETURN jsonb_build_object('overlap', true);  -- 2026-10-11: bez booking_id / termínů
END;
$function$;

-- Pokračování (potvrzení, granty, RLS): 20261011b_web_booking_setters_guard_b_confirm.sql

NOTIFY pgrst, 'reload schema';
