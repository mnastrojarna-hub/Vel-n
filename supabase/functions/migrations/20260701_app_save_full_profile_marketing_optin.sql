-- =============================================================================
-- app_save_full_profile — marketing = OPT-IN (re-issue RPC z 2026-06-13)
-- =============================================================================
-- Původní RPC (registrace v appce, auth_provider.signUp) nastavovala VŠECH 10
-- souhlasů natvrdo na `true` — včetně `marketing_consent`. Marketing tak
-- zákazník získal bez opt-inu (navíc i DB default sloupce byl `true`, takže i
-- řádek vzniklý mimo RPC byl defaultně marketingový).
--
-- Změna:
--   * `marketing_consent` = OPT-IN → RPC ho už nezapíná, respektuje jen
--     explicitní hodnotu poslanou z appky (ta ho zatím neposílá → false).
--   * Povinné souhlasy (VOP/GDPR/zpracování dat) — teď reálně gaceované v UI
--     registrace (krok 3, checkboxy) — respektují poslanou hodnotu, fallback true.
--   * Transakční / servisní kanály (email/sms/push/whatsapp/photo/contract)
--     beze změny (transakční komunikace jde vždy; marketing hlídá marketing_consent).
--   * ALTER defaultu sloupce `profiles.marketing_consent` na false (opt-in i pro
--     řádky vzniklé mimo RPC — web create_web_booking marketing také nesbírá).
-- Migrace: 2026-07-01
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
    -- Povinné souhlasy (gaceované v UI registrace) — respektuj poslanou hodnotu, fallback true
    consent_vop             = COALESCE((p_data->>'consent_vop')::boolean, true),
    consent_gdpr            = COALESCE((p_data->>'consent_gdpr')::boolean, true),
    consent_data_processing = COALESCE((p_data->>'consent_data_processing')::boolean, true),
    -- Transakční / servisní kanály beze změny (transakční komunikace jde vždy)
    consent_email = true, consent_sms = true, consent_push = true,
    consent_whatsapp = true, consent_photo = true, consent_contract = true,
    -- Marketing = OPT-IN: RPC ho už nezapíná; respektuje jen explicitní volbu z appky
    marketing_consent = COALESCE((p_data->>'marketing_consent')::boolean, false),
    updated_at = now()
  WHERE id = v_uid;

  RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.app_save_full_profile(jsonb) TO authenticated;

-- Opt-in i pro řádky vzniklé mimo RPC (handle_new_user trigger, create_web_booking
-- marketing nesbírá → zůstával na defaultu true). Nově default false.
ALTER TABLE public.profiles ALTER COLUMN marketing_consent SET DEFAULT false;
