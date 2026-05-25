-- =============================================================================
-- MIGRACE: set_web_booking_docs RPC
-- Datum: 2026-05-25
-- Reportováno: U webové rezervace random zákazníka se do smlouvy NEvyplní
--   „Číslo OP/pasu" ani „Číslo ŘP", přestože je web flow vynucuje. U testovacího
--   účtu (existující profil) čísla naskočí správně.
--
-- Root cause:
--   Frontend (`pages-rezervace-scan.js` → `MG._rezPersistDocs`) ve kroku 2 volá
--   RPC `set_web_booking_docs`, která ale NIKDY NEEXISTOVALA. Volání tiše spadne
--   (jen console.warn) a kód se spolehne na fallback přímý
--   `supabase.from('profiles').update(...)`. Ten je vázán na RLS — u nového,
--   ještě nepřihlášeného web zákazníka (auto sign-in po vytvoření účtu nemusí
--   projít) RLS update zablokuje → id_number / license_number se do profilu
--   neuloží → `generate-document` je čte z profilu prázdné → smlouva má prázdná
--   pole. Testovací účet měl profil vyplněný předem, proto u něj čísla byla.
--
-- Fix:
--   Doplnit SECURITY DEFINER RPC `set_web_booking_docs` (stejný vzor jako
--   `set_web_booking_password` / `get_web_booking_resume`), klíčovanou přes
--   booking_id. Obejde RLS a spolehlivě uloží ručně zadaná čísla do profilu
--   majitele rezervace. Frontend ji už dnes volá se shodnými parametry.
--
-- POZN. (door codes): záměrně NEnastavujeme `id_verified_at` /
--   `license_verified_at`. Ručně zadaná čísla nesmí uvolnit přístupové kódy ke
--   dveřím — to dál vyžaduje fotku NEBO reálné Mindee OCR ověření
--   (viz auto_generate_door_codes / check_booking_docs_status). Smlouva ale
--   potřebuje čísla jen vytisknout.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.set_web_booking_docs(
  p_booking_id uuid,
  p_id_number text DEFAULT NULL,
  p_license_number text DEFAULT NULL,
  p_license_expiry text DEFAULT NULL,
  p_license_group text DEFAULT NULL
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

  UPDATE profiles SET
    id_number      = COALESCE(NULLIF(p_id_number, ''), id_number),
    license_number = COALESCE(NULLIF(p_license_number, ''), license_number),
    license_group  = COALESCE(v_lic_group, license_group),
    license_expiry = COALESCE(v_lic_expiry, license_expiry),
    updated_at     = now()
  WHERE id = v_user_id;

  RETURN jsonb_build_object('success', true);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_web_booking_docs(uuid, text, text, text, text) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
