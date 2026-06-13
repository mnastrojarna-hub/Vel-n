-- =============================================================================
-- set_my_license_group — uloží skupinu ŘP přihlášeného zákazníka.
-- =============================================================================
-- Sloupec `profiles.license_group` je ENUM pole (`license_group[]`). PostgREST
-- ho z prostého JSON pole NEUMÍ přetypovat → přímý UPDATE/UPSERT z appky, který
-- license_group obsahoval, CELÝ padal a uložilo se jen jméno/e-mail/telefon
-- z handle_new_user triggeru (adresa, datum narození, čísla dokladů i skupina ŘP
-- zůstaly prázdné, stát spadl na default). Appka proto license_group z přímého
-- zápisu vyjímá a ukládá ho přes toto RPC, které cast text[] → license_group[]
-- udělá v SQL. SECURITY DEFINER obejde RLS, ale píše VÝHRADNĚ vlastní řádek
-- (auth.uid()). Volá registrace (auth_provider.signUp) i editace profilu
-- (profile_screen._save) v mobilní appce.
-- Migrace: 2026-06-13
-- =============================================================================

CREATE OR REPLACE FUNCTION public.set_my_license_group(p_groups text[])
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

  -- jen platné skupiny (velkými písmeny), cast text → license_group ENUM
  SELECT array_agg(DISTINCT upper(g)::license_group)
    INTO v_groups
    FROM unnest(p_groups) AS g
   WHERE upper(g) IN ('AM','A1','A2','A','B','N');

  UPDATE public.profiles
     SET license_group = v_groups
   WHERE id = v_uid;

  RETURN jsonb_build_object('success', true,
                            'count', COALESCE(array_length(v_groups, 1), 0));
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_my_license_group(text[]) TO authenticated;
