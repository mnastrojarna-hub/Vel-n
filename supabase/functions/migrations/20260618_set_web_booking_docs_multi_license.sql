-- =============================================================================
-- MIGRACE: set_web_booking_docs — podpora VÍCE skupin ŘP (multi-select v kroku 2)
-- Datum: 2026-06-18
-- Branch: claude/checkout-reservation-form-bugs-vbc72z
--
-- Reportováno: Na webu v rezervačním formuláři v kroku 2 šlo vybrat jen jednu
--   skupinu ŘP. Zákazník potřebuje vybrat víc skupin najednou — např. při
--   půjčení (dětské) motorky + vozíku potřebuje skupinu B na vozík.
--
-- Frontend (pages-rezervace-steps.js) nově posílá `p_license_group` jako seznam
--   skupin oddělený čárkou, např. "A,B". Stará verze RPC ale castovala jen
--   JEDNU hodnotu: `ARRAY[upper(p_license_group)::license_group]` → cast "A,B"
--   spadl do EXCEPTION → `v_lic_group := NULL` → skupiny se tiše neuložily.
--
-- Fix: parsovat čárkou oddělený seznam → license_group[]. Neplatné/prázdné
--   tokeny ignorujeme; jen platné hodnoty (AM/A1/A2/A/B/N), uppercase, DISTINCT.
--   Když nezbyde nic platného → NULL (COALESCE nepřepíše existující skupinu).
--   Zpětně kompatibilní: jedna skupina ("A") prochází stejně jako dřív.
--
-- POZN.: create_web_booking se NEMĚNÍ — frontend mu posílá jen JEDNU pokrývající
--   skupinu (MG._rezPrimaryLicGroup) kvůli validaci proti motorce; kompletní
--   seznam ukládá tato RPC. Door codes (id_verified_at/license_verified_at)
--   tato RPC záměrně NENASTAVUJE (ruční/OCR čísla nesmí uvolnit kódy ke dveřím).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.set_web_booking_docs(
  p_booking_id uuid,
  p_id_number text DEFAULT NULL,
  p_license_number text DEFAULT NULL,
  p_license_expiry text DEFAULT NULL,
  p_license_group text DEFAULT NULL,
  p_date_of_birth text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_source text;
  v_lic_group license_group[];
  v_lic_expiry date;
  v_dob date;
BEGIN
  IF p_booking_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Booking ID je povinné');
  END IF;

  SELECT user_id, booking_source INTO v_user_id, v_source
    FROM bookings WHERE id = p_booking_id;

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Rezervace nenalezena');
  END IF;
  IF v_source IS DISTINCT FROM 'web' THEN
    RETURN jsonb_build_object('error', 'Pouze pro webové rezervace');
  END IF;

  -- ŘP skupina → enum array. Podporuje VÍCE skupin oddělených čárkou ("A,B").
  -- Neplatné/prázdné tokeny ignorujeme; když nic platného nezbyde → NULL (nepřepíše).
  IF p_license_group IS NOT NULL AND p_license_group <> '' THEN
    BEGIN
      SELECT array_agg(DISTINCT g)
        INTO v_lic_group
        FROM (
          SELECT upper(trim(tok))::license_group AS g
          FROM unnest(string_to_array(p_license_group, ',')) AS tok
          WHERE trim(tok) <> ''
            AND upper(trim(tok)) IN ('AM','A1','A2','A','B','N')
        ) s;
    EXCEPTION WHEN OTHERS THEN
      v_lic_group := NULL;
    END;
  END IF;

  -- platnost ŘP → date (neplatný formát ignorujeme)
  IF p_license_expiry IS NOT NULL AND p_license_expiry <> '' THEN
    BEGIN
      v_lic_expiry := p_license_expiry::date;
    EXCEPTION WHEN OTHERS THEN
      v_lic_expiry := NULL;
    END;
  END IF;

  -- datum narození → date (neplatný formát ignorujeme)
  IF p_date_of_birth IS NOT NULL AND p_date_of_birth <> '' THEN
    BEGIN
      v_dob := p_date_of_birth::date;
    EXCEPTION WHEN OTHERS THEN
      v_dob := NULL;
    END;
  END IF;

  UPDATE profiles SET
    id_number      = COALESCE(NULLIF(p_id_number, ''), id_number),
    license_number = COALESCE(NULLIF(p_license_number, ''), license_number),
    license_group  = COALESCE(v_lic_group, license_group),
    -- POZOR na typy sloupců: license_expiry je v DB TEXT, date_of_birth je DATE.
    license_expiry = COALESCE(v_lic_expiry::text, license_expiry),
    date_of_birth  = COALESCE(v_dob, date_of_birth),
    updated_at     = now()
  WHERE id = v_user_id;

  RETURN jsonb_build_object('success', true);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_web_booking_docs(uuid, text, text, text, text, text) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
