-- ============================================================================
-- PLATNOST ŘP SE BERE Z ÚDAJE OD ZÁKAZNÍKA, NE Z OCR (zadání uživatele 2026-09-20)
--
-- „Platnost se musí brát z toho, co zákazník vyplňuje, ne z OCR — OCR je jen
--  záznam pro úřady."
--
-- Stav PŘED: `check_booking_docs_status()` (brána pro vydání a uvolnění
-- přístupových kódů) porovnávala konec pronájmu VÝHRADNĚ s
-- `profiles.license_verified_until`, což plní OCR skenu ŘP. Když OCR přečetlo
-- datum špatně (nebo jiný formát), držel systém zákazníkovi kódy s hláškou
-- „ŘP propadlý …", i když měl v profilu vyplněnou správnou platnost. Naopak
-- appka při rezervaci už dnes validuje podle `license_expiry` (údaj od
-- zákazníka) — brány si tedy odporovaly.
--
-- Nově: rozhoduje `profiles.license_expiry` (vyplňuje zákazník při registraci
-- a v profilu, ukládá se jako ISO 'YYYY-MM-DD'); `license_verified_until` z OCR
-- slouží už jen jako ZÁLOHA pro případ, že zákazník platnost nevyplnil vůbec,
-- a jinak zůstává v profilu jako doklad pro úřady (tiskne se do smlouvy).
-- Formát se parsuje tolerantně (ISO i české 'DD.MM.YYYY'); nečitelná hodnota
-- se chová jako nevyplněná, tj. platnost se nekontroluje (parita s dneškem,
-- kdy `license_verified_until` bez OCR bylo NULL).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.check_booking_docs_status(
  p_user_id uuid,
  p_end_date date,
  p_moto_id uuid DEFAULT NULL::uuid
)
RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_license_required text;
  v_has_id_doc boolean := false;
  v_has_dl_doc boolean := false;
  v_id_verified timestamptz;
  v_pp_verified timestamptz;
  v_lic_verified timestamptz;
  v_lic_until date;          -- z OCR (záloha)
  v_lic_customer text;       -- vyplnil zákazník (rozhoduje)
  v_lic_effective date;
BEGIN
  IF p_user_id IS NULL THEN RETURN 'Chybí uživatel'; END IF;

  -- Dětská motorka → doklady nepotřeba
  IF p_moto_id IS NOT NULL THEN
    SELECT license_required INTO v_license_required FROM motorcycles WHERE id = p_moto_id;
    IF v_license_required = 'N' THEN RETURN NULL; END IF;
  END IF;

  SELECT id_verified_at, passport_verified_at, license_verified_at, license_verified_until, license_expiry
    INTO v_id_verified, v_pp_verified, v_lic_verified, v_lic_until, v_lic_customer
  FROM profiles WHERE id = p_user_id;

  -- Doklad totožnosti: fotka (i při neúspěšném OCR) NEBO reálné OCR. Holé číslo NESTAČÍ (jen do smlouvy).
  v_has_id_doc :=
       EXISTS (SELECT 1 FROM documents WHERE user_id = p_user_id AND type IN ('id_card','id_photo','passport'))
    OR v_id_verified IS NOT NULL
    OR v_pp_verified IS NOT NULL;

  -- ŘP: fotka NEBO reálné OCR. Holé číslo NESTAČÍ.
  v_has_dl_doc :=
       EXISTS (SELECT 1 FROM documents WHERE user_id = p_user_id AND type IN ('drivers_license','license_photo'))
    OR v_lic_verified IS NOT NULL;

  IF NOT v_has_id_doc AND NOT v_has_dl_doc THEN RETURN 'Chybí doklady (OP/pas/ŘP)'; END IF;
  IF NOT v_has_id_doc THEN RETURN 'Chybí doklad totožnosti (OP/pas)'; END IF;
  IF NOT v_has_dl_doc THEN RETURN 'Chybí ŘP'; END IF;

  -- PLATNOST ŘP: rozhoduje údaj od zákazníka (`license_expiry`), OCR jen když
  -- zákazník nevyplnil nic. Parsuje se tolerantně, nečitelné = nekontroluje se.
  v_lic_customer := NULLIF(btrim(COALESCE(v_lic_customer, '')), '');
  IF v_lic_customer IS NOT NULL THEN
    BEGIN
      IF v_lic_customer ~ '^\d{4}-\d{2}-\d{2}' THEN
        v_lic_effective := left(v_lic_customer, 10)::date;
      ELSIF v_lic_customer ~ '^\d{1,2}\.\s*\d{1,2}\.\s*\d{4}$' THEN
        v_lic_effective := to_date(regexp_replace(v_lic_customer, '\s', '', 'g'), 'DD.MM.YYYY');
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_lic_effective := NULL;   -- nečitelný zápis platnost neblokuje
    END;
  END IF;
  IF v_lic_effective IS NULL AND v_lic_customer IS NULL THEN
    v_lic_effective := v_lic_until;   -- záloha z OCR jen při nevyplněném údaji
  END IF;

  IF v_lic_effective IS NOT NULL AND p_end_date IS NOT NULL AND v_lic_effective < p_end_date THEN
    RETURN 'ŘP propadlý ' || TO_CHAR(v_lic_effective, 'DD.MM.YYYY');
  END IF;

  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.check_booking_docs_status(uuid, date, uuid) IS
  'Stav dokladů pro vydání přístupových kódů. Platnost ŘP se bere z profiles.license_expiry (vyplňuje zákazník); license_verified_until z OCR je jen záloha, když zákazník platnost nevyplnil (2026-09-20).';
