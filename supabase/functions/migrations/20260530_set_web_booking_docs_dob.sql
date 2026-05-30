-- =============================================================================
-- MIGRACE: set_web_booking_docs — doplnit datum narození (date_of_birth)
-- Datum: 2026-05-30
-- Branch: claude/customer-info-storage-bug-QGk6Y
--
-- Reportováno: U webové rezervace nového (random) zákazníka se do profilu —
--   a tím i do smlouvy a do Velína — neuloží skupina ŘP, platnost ŘP, číslo OP,
--   číslo ŘP, datum narození ani věk. Ukládá se POUZE to, co jde přes
--   `create_web_booking` (jméno, e-mail, telefon, adresa = krok 1). Vše z kroku 2
--   (doklady) mizí. V appce to funguje, protože přihlášený uživatel smí přes RLS
--   zapisovat do vlastního profilu napřímo.
--
-- Root cause:
--   `set_web_booking_docs` (RPC, kterou frontend ve kroku 2 volá) NEBYLA reálně
--   nasazená v produkční DB — migrace `20260525_set_web_booking_docs.sql` byla
--   sice commitnutá, ale SQL se v dashboardu nikdy nespustilo (nebo ho přepsal
--   pozdější redeploy). Volání RPC pak skončí „function does not exist", chybu
--   spolkne `console.warn` a kód spadne do fallbacku
--   `supabase.from('profiles').update(...)`, který je u nepřihlášeného nového
--   web zákazníka zablokovaný RLS → čísla se ztratí. (Příznak: krok 1 = uloženo,
--   krok 2 = prázdné.)
--
-- Fix:
--   1) Znovu (a spolehlivě) vytvořit `set_web_booking_docs` jako SECURITY DEFINER
--      RPC klíčovanou přes booking_id (obchází RLS).
--   2) Doplnit `p_date_of_birth` — datum narození z OCR skenu, aby se uložilo i
--      bez přihlášení (manuální DOB z kroku 1 jde přes `create_web_booking`, toto
--      je navíc záchyt z OCR). Věk se ve Velíně dopočítá z `date_of_birth`.
--
--   Přidání parametru mění signaturu (5 → 6 arg) → nejdřív DROP staré verze,
--   pak CREATE. PostgREST volá podle jmen parametrů.
--
-- POZN. (door codes): záměrně NEnastavujeme `id_verified_at` /
--   `license_verified_at` / `passport_verified_at`. Ručně/OCR zadaná čísla nesmí
--   uvolnit přístupové kódy ke dveřím — to dál vyžaduje fotku NEBO reálné Mindee
--   OCR ověření (viz auto_generate_door_codes / check_booking_docs_status).
-- =============================================================================

DROP FUNCTION IF EXISTS public.set_web_booking_docs(uuid, text, text, text, text);

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

  -- ŘP skupina → enum array (neplatnou hodnotu ignorujeme, nepřepisujeme)
  IF p_license_group IS NOT NULL AND p_license_group <> '' THEN
    BEGIN
      v_lic_group := ARRAY[upper(p_license_group)::license_group];
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
    license_expiry = COALESCE(v_lic_expiry, license_expiry),
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
