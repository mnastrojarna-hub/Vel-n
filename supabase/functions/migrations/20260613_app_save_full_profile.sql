-- =============================================================================
-- app_save_full_profile — uloží CELÝ profil přihlášeného zákazníka jedním
-- voláním (stejný princip jako create_web_booking na webu).
-- =============================================================================
-- Mobilní appka dřív psala profil přímo přes PostgREST a zápis padal na:
--   (a) RLS u INSERT větve `upsert` (uživatel nemá INSERT politiku na profiles),
--   (b) ENUM poli `license_group[]`, které PostgREST z JSON pole neumí
--       přetypovat → CELÝ zápis se zahodil a zůstala jen data z handle_new_user
--       triggeru (jméno/e-mail/telefon); adresa, datum narození, čísla dokladů
--       i skupina ŘP zůstaly prázdné, stát spadl na default.
-- Řešení: SECURITY DEFINER funkce běží server-side → obejde RLS i typové potíže,
-- license_group cast (text→ENUM pole) se udělá v SQL. Píše VÝHRADNĚ vlastní řádek
-- přes auth.uid(). Volá registrace v appce (auth_provider.signUp).
-- Migrace: 2026-06-13
-- =============================================================================

CREATE OR REPLACE FUNCTION public.app_save_full_profile(p_data jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_groups license_group[];
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- skupina ŘP: JSON pole stringů → license_group[] (jen platné hodnoty)
  IF p_data ? 'license_group' AND jsonb_typeof(p_data->'license_group') = 'array' THEN
    SELECT array_agg(DISTINCT upper(g)::license_group)
      INTO v_groups
      FROM jsonb_array_elements_text(p_data->'license_group') AS g
     WHERE upper(g) IN ('AM','A1','A2','A','B','N');
  END IF;

  -- pojistka: pokud řádek ještě neexistuje (trigger ho obvykle vytvoří), dotvoř
  INSERT INTO public.profiles (id, email)
  SELECT v_uid, u.email FROM auth.users u WHERE u.id = v_uid
  ON CONFLICT (id) DO NOTHING;

  UPDATE public.profiles SET
    full_name      = COALESCE(NULLIF(p_data->>'full_name',''), full_name),
    phone          = COALESCE(NULLIF(p_data->>'phone',''), phone),
    date_of_birth  = COALESCE(NULLIF(p_data->>'date_of_birth','')::date, date_of_birth),
    street         = COALESCE(NULLIF(p_data->>'street',''), street),
    city           = COALESCE(NULLIF(p_data->>'city',''), city),
    zip            = COALESCE(NULLIF(p_data->>'zip',''), zip),
    country        = COALESCE(NULLIF(p_data->>'country',''), country),
    id_number      = COALESCE(NULLIF(p_data->>'id_number',''), id_number),
    license_number = COALESCE(NULLIF(p_data->>'license_number',''), license_number),
    license_expiry = COALESCE(NULLIF(p_data->>'license_expiry','')::date, license_expiry),
    license_group  = COALESCE(v_groups, license_group),
    language       = COALESCE(NULLIF(p_data->>'language',''), language),
    registration_source = COALESCE(registration_source, 'app'),
    marketing_consent = true, consent_gdpr = true, consent_vop = true,
    consent_data_processing = true, consent_email = true, consent_sms = true,
    consent_push = true, consent_whatsapp = true, consent_photo = true,
    consent_contract = true,
    updated_at = now()
  WHERE id = v_uid;

  RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.app_save_full_profile(jsonb) TO authenticated;
