-- ============================================================================
-- PŘÍSTUPOVÉ KÓDY JEN S KOMPLETNÍMI DOKLADY (zadání majitele 2026-10-10)
--
-- Incident #5AED3469: zákazník dostal kódy brány / šatny / motorky, i když měl
-- nahraný jen LÍC ŘP a dvě fotky „Občanský průkaz“ bez strany (marker řádky
-- appky bez souboru). Kanonická brána `check_booking_docs_status` brala
-- JAKOUKOLI jednu fotku OP/pasu + JAKOUKOLI jednu fotku ŘP (nebo jen
-- `*_verified_at`, které si zákazník umí zapsat sám), nekontrolovala strany,
-- věk ani skupinu ŘP a prázdná platnost ŘP prošla.
--
-- Nové pravidlo (dospělá motorka; dětská `N` beze změny bez dokladů):
--   * doklad totožnosti: OP LÍC + OP RUB, nebo cestovní pas (jedna datová strana),
--   * řidičský průkaz: LÍC + RUB,
--   * „fotka“ = řádek `documents` se skutečným souborem v bucketu `documents`
--     ve složce zákazníka (marker `mindee_verified/…` ani cizí soubor nestačí),
--     strana z `metadata.side` (záloha: `_front_` / `_back_` v názvu souboru),
--   * datum narození vyplněné a k začátku pronájmu 18+,
--   * platnost ŘP vyplněná (údaj zákazníka `license_expiry`, záloha OCR
--     `license_verified_until`) a ≥ konec pronájmu,
--   * skupina ŘP pokrývá motorku (`license_groups`, záloha `license_required`;
--     matice jako appka / `_apply_booking_changes_core`).
--   OCR `*_verified_at` už fotky NENAHRAZUJE (zákazník ho umí zapsat sám).
-- Tento soubor: jádro (`_docs_gate_checklist`, `booking_docs_gate`),
-- `check_booking_docs_status` (STEJNÁ signatura, jen tělo) a RPC
-- `get_docs_gate_checklist` pro Velín / appku / web. Cesty vydání kódů
-- přepojuje `20261010a`, pojistku na tabulce kódů + RLS `20261010c`.
-- Už odeslané kódy zůstávají v platnosti (rozhodnutí majitele 2026-10-10).
-- ============================================================================

-- 1) Pokrytí skupin ŘP: stačí, aby kterákoli držená skupina pokryla kteroukoli
--    požadovanou (OR). AM ← AM/A1/A2/A/B, A1 ← A1/A2/A, A2 ← A2/A, A ← A, B ← B.
CREATE OR REPLACE FUNCTION public._license_groups_cover(p_held text[], p_required text[])
RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM unnest(COALESCE(p_required, '{}'::text[])) r(g)
     WHERE (SELECT COALESCE(array_agg(upper(btrim(h))), '{}'::text[]) FROM unnest(COALESCE(p_held, '{}'::text[])) h)
           && CASE upper(btrim(r.g))
                WHEN 'AM' THEN ARRAY['AM','A1','A2','A','B']
                WHEN 'A1' THEN ARRAY['A1','A2','A']
                WHEN 'A2' THEN ARRAY['A2','A']
                WHEN 'A'  THEN ARRAY['A']
                WHEN 'B'  THEN ARRAY['B']
                ELSE ARRAY[upper(btrim(r.g))]
              END)
$$;

-- 2) Kontrolní seznam dokladů (jediný zdroj pravdy) ---------------------------
CREATE OR REPLACE FUNCTION public._docs_gate_checklist(
  p_user_id uuid, p_start date, p_end date, p_moto_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req text[];
  v_child boolean := false;
  v_p record;
  v_id_f boolean; v_id_b boolean; v_pass boolean; v_dl_f boolean; v_dl_b boolean;
  v_ref date := COALESCE(p_start, (now() AT TIME ZONE 'Europe/Prague')::date);
  v_age_ok boolean; v_exp date; v_exp_ok boolean; v_grp_ok boolean;
  v_cust text;
  v_miss text[] := '{}';
BEGIN
  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'Chybí uživatel', 'missing', jsonb_build_array('Chybí uživatel'));
  END IF;

  IF p_moto_id IS NOT NULL THEN
    SELECT COALESCE(NULLIF(m.license_groups, '{}'::text[]), ARRAY[COALESCE(m.license_required::text, 'A')]),
           m.license_required::text = 'N' OR 'N' = ANY(COALESCE(m.license_groups, '{}'::text[]))
      INTO v_req, v_child
      FROM motorcycles m WHERE m.id = p_moto_id;
  END IF;
  IF v_child THEN   -- dětská motorka: doklady se nevyžadují (beze změny)
    RETURN jsonb_build_object('ok', true, 'child', true, 'reason', NULL, 'missing', '[]'::jsonb);
  END IF;

  -- Rub se počítá jen jako JINÝ soubor než líc (jedna fotka zapsaná dvakrát
  -- jako líc i rub nestačí). Strana: metadata (oprava ve Velínu) > název souboru.
  WITH d AS (
    SELECT CASE WHEN dd.type IN ('id_card', 'id_photo') THEN 'id'
                WHEN dd.type = 'passport' THEN 'pass' ELSE 'dl' END AS k,
           dd.file_path,
           COALESCE(NULLIF(lower(btrim(dd.metadata->>'side')), ''),
                    CASE WHEN dd.file_path ~ '_front[_.]' THEN 'front'
                         WHEN dd.file_path ~ '_back[_.]'  THEN 'back' END) AS side
      FROM documents dd
     WHERE dd.user_id = p_user_id
       AND dd.type IN ('id_card', 'id_photo', 'passport', 'drivers_license', 'license_photo')
       AND dd.file_path IS NOT NULL
       AND dd.file_path NOT LIKE 'mindee_verified/%'
       AND (dd.file_path LIKE p_user_id::text || '/%' OR dd.file_path LIKE 'user-docs/' || p_user_id::text || '/%')
       AND EXISTS (SELECT 1 FROM storage.objects o WHERE o.bucket_id = 'documents' AND o.name = dd.file_path)
  )
  SELECT EXISTS (SELECT 1 FROM d WHERE k = 'id' AND side = 'front'),
         EXISTS (SELECT 1 FROM d f JOIN d b ON b.k = 'id' AND b.side = 'back' AND b.file_path <> f.file_path
                  WHERE f.k = 'id' AND f.side = 'front')
           OR (NOT EXISTS (SELECT 1 FROM d WHERE k = 'id' AND side = 'front')
               AND EXISTS (SELECT 1 FROM d WHERE k = 'id' AND side = 'back')),
         EXISTS (SELECT 1 FROM d WHERE k = 'pass'),
         EXISTS (SELECT 1 FROM d WHERE k = 'dl' AND side = 'front'),
         EXISTS (SELECT 1 FROM d f JOIN d b ON b.k = 'dl' AND b.side = 'back' AND b.file_path <> f.file_path
                  WHERE f.k = 'dl' AND f.side = 'front')
           OR (NOT EXISTS (SELECT 1 FROM d WHERE k = 'dl' AND side = 'front')
               AND EXISTS (SELECT 1 FROM d WHERE k = 'dl' AND side = 'back'))
    INTO v_id_f, v_id_b, v_pass, v_dl_f, v_dl_b;

  SELECT date_of_birth, license_expiry, license_verified_until, license_group::text[] AS groups
    INTO v_p FROM profiles WHERE id = p_user_id;

  -- Doklad totožnosti
  IF NOT v_pass AND NOT (v_id_f AND v_id_b) THEN
    v_miss := v_miss || CASE WHEN NOT v_id_f AND NOT v_id_b THEN 'Chybí OP (líc a rub) nebo pas'
                             WHEN NOT v_id_b THEN 'Chybí rub OP' ELSE 'Chybí líc OP' END;
  END IF;
  -- Řidičský průkaz
  IF NOT (v_dl_f AND v_dl_b) THEN
    v_miss := v_miss || CASE WHEN NOT v_dl_f AND NOT v_dl_b THEN 'Chybí ŘP (líc a rub)'
                             WHEN NOT v_dl_b THEN 'Chybí rub ŘP' ELSE 'Chybí líc ŘP' END;
  END IF;
  -- Věk 18+ k začátku pronájmu
  v_age_ok := v_p.date_of_birth IS NOT NULL AND v_p.date_of_birth + interval '18 years' <= v_ref;
  IF v_p.date_of_birth IS NULL THEN v_miss := v_miss || 'Chybí datum narození'::text;
  ELSIF NOT v_age_ok THEN v_miss := v_miss || 'Zákazníkovi není 18 let'::text; END IF;
  -- Platnost ŘP: rozhoduje údaj zákazníka, OCR jen když zákazník nevyplnil nic
  v_cust := NULLIF(btrim(COALESCE(v_p.license_expiry, '')), '');
  IF v_cust IS NOT NULL THEN
    BEGIN
      IF v_cust ~ '^\d{4}-\d{2}-\d{2}' THEN v_exp := left(v_cust, 10)::date;
      ELSIF v_cust ~ '^\d{1,2}\.\s*\d{1,2}\.\s*\d{4}$' THEN
        v_exp := to_date(regexp_replace(v_cust, '\s', '', 'g'), 'DD.MM.YYYY');
      END IF;
    EXCEPTION WHEN OTHERS THEN v_exp := NULL;
    END;
  ELSE
    v_exp := v_p.license_verified_until;
  END IF;
  v_exp_ok := v_exp IS NOT NULL AND v_exp >= COALESCE(p_end, v_ref);
  IF v_exp IS NULL THEN v_miss := v_miss || 'Chybí platnost ŘP'::text;
  ELSIF NOT v_exp_ok THEN v_miss := v_miss || ('ŘP propadlý ' || to_char(v_exp, 'DD.MM.YYYY')); END IF;
  -- Skupina ŘP (bez známé motorky stačí jakákoli skupina pro motorky / B)
  v_grp_ok := CASE WHEN v_req IS NOT NULL THEN public._license_groups_cover(v_p.groups, v_req)
                   ELSE public._license_groups_cover(v_p.groups, ARRAY['AM','B']) END;
  IF NOT v_grp_ok THEN
    v_miss := v_miss || CASE WHEN COALESCE(array_length(v_p.groups, 1), 0) = 0 THEN 'Chybí skupina ŘP'
                             ELSE 'Skupina ŘP nestačí (potřeba ' || array_to_string(COALESCE(v_req, ARRAY['A']), '/') || ')' END;
  END IF;

  RETURN jsonb_build_object(
    'ok', cardinality(v_miss) = 0,
    'child', false,
    'id_front', v_id_f, 'id_back', v_id_b, 'passport', v_pass,
    'dl_front', v_dl_f, 'dl_back', v_dl_b,
    'identity_ok', v_pass OR (v_id_f AND v_id_b),
    'license_ok', v_dl_f AND v_dl_b,
    'date_of_birth', v_p.date_of_birth, 'age_ok', v_age_ok,
    'license_expiry', v_exp, 'expiry_ok', v_exp_ok,
    'license_groups', to_jsonb(COALESCE(v_p.groups, '{}'::text[])),
    'required_groups', to_jsonb(v_req), 'groups_ok', v_grp_ok,
    'missing', to_jsonb(v_miss),
    'reason', CASE WHEN cardinality(v_miss) = 0 THEN NULL ELSE array_to_string(v_miss, '; ') END);
END;
$$;

-- 3) Brána pro konkrétní rezervaci (data z rezervace, čas Praha) ---------------
CREATE OR REPLACE FUNCTION public.booking_docs_gate(p_booking_id uuid)
RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_b record;
BEGIN
  SELECT user_id, moto_id, start_date, end_date INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN RETURN 'Rezervace nenalezena'; END IF;
  RETURN public._docs_gate_checklist(v_b.user_id,
           (v_b.start_date AT TIME ZONE 'Europe/Prague')::date,
           (v_b.end_date AT TIME ZONE 'Europe/Prague')::date,
           v_b.moto_id)->>'reason';
END;
$$;

REVOKE ALL ON FUNCTION public._license_groups_cover(text[], text[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._docs_gate_checklist(uuid, date, date, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.booking_docs_gate(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._license_groups_cover(text[], text[]) TO service_role;
GRANT EXECUTE ON FUNCTION public._docs_gate_checklist(uuid, date, date, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.booking_docs_gate(uuid) TO service_role;

-- 4) Kanonická veřejná brána — STEJNÁ signatura (volají ji edge fn, appka,
--    Velín i 9 DB funkcí); začátek pronájmu (věk) a motorku (skupina, dětská)
--    dohledá z rezervace zákazníka se shodným koncem.
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
  v_uid uuid := auth.uid();
  v_start date;
  v_moto uuid;
BEGIN
  IF p_user_id IS NULL THEN RETURN 'Chybí uživatel'; END IF;
  -- Cizí stav dokladů jen admin (dřív šel zjistit u kohokoli)
  IF v_uid IS NOT NULL AND v_uid <> p_user_id AND NOT public.is_admin() THEN
    RETURN 'Doklady nelze ověřit';
  END IF;
  SELECT (b.start_date AT TIME ZONE 'Europe/Prague')::date, b.moto_id
    INTO v_start, v_moto
    FROM bookings b
   WHERE b.user_id = p_user_id
     AND (p_moto_id IS NULL OR b.moto_id = p_moto_id)
     AND p_end_date IS NOT NULL
     AND (b.end_date::date = p_end_date OR (b.end_date AT TIME ZONE 'Europe/Prague')::date = p_end_date)
   ORDER BY (b.status IN ('pending', 'reserved', 'active')) DESC, b.created_at DESC
   LIMIT 1;
  RETURN public._docs_gate_checklist(p_user_id, v_start, p_end_date, COALESCE(p_moto_id, v_moto))->>'reason';
END;
$$;

COMMENT ON FUNCTION public.check_booking_docs_status(uuid, date, uuid) IS
  'Stav dokladů pro vydání přístupových kódů (NULL = OK). Od 2026-10-10 přísně: OP líc+rub nebo pas, ŘP líc+rub (skutečné soubory v bucketu documents), datum narození 18+ k začátku, platnost ŘP ≥ konec, skupina ŘP pokrývá motorku; dětská motorka bez dokladů. Jádro _docs_gate_checklist.';

REVOKE EXECUTE ON FUNCTION public.check_booking_docs_status(uuid, date, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_booking_docs_status(uuid, date, uuid) TO authenticated, service_role;

-- 5) RPC pro UI: co přesně chybí (Velín / appka / web) -------------------------
CREATE OR REPLACE FUNCTION public.get_docs_gate_checklist(p_user_id uuid DEFAULT NULL, p_booking_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_b record;
  v_user uuid := p_user_id;
BEGIN
  IF p_booking_id IS NOT NULL THEN
    SELECT user_id, moto_id, start_date, end_date INTO v_b FROM bookings WHERE id = p_booking_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    v_user := v_b.user_id;
  END IF;
  IF v_user IS NULL THEN v_user := v_uid; END IF;
  IF v_user IS NULL OR (v_uid IS DISTINCT FROM v_user AND NOT public.is_admin()) THEN
    RETURN jsonb_build_object('error', 'forbidden');
  END IF;
  IF p_booking_id IS NOT NULL THEN
    RETURN public._docs_gate_checklist(v_user,
             (v_b.start_date AT TIME ZONE 'Europe/Prague')::date,
             (v_b.end_date AT TIME ZONE 'Europe/Prague')::date, v_b.moto_id)
           || jsonb_build_object('booking_id', p_booking_id);
  END IF;
  RETURN public._docs_gate_checklist(v_user, NULL, NULL, NULL);
END;
$$;

REVOKE ALL ON FUNCTION public.get_docs_gate_checklist(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_docs_gate_checklist(uuid, uuid) TO authenticated, service_role;

-- 6) `apply_profile_license_group(p_user_id, p_group)` (jen v dashboardu, bez
--    volajících v repu i v DB) byla spustitelná anonymně → kdokoli mohl
--    libovolnému profilu přidat skupinu ŘP a obejít kontrolu skupiny.
DO $$
BEGIN
  IF to_regprocedure('public.apply_profile_license_group(uuid, text)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.apply_profile_license_group(uuid, text) FROM PUBLIC, anon, authenticated;
    GRANT EXECUTE ON FUNCTION public.apply_profile_license_group(uuid, text) TO service_role;
  END IF;
END $$;
