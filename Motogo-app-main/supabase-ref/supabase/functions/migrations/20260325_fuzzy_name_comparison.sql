-- =============================================================================
-- MIGRACE: Fuzzy porovnání jmen ve verify_customer_docs
-- Datum: 2026-03-25
-- Problém: Mindee OCR vrací jména bez diakritiky (SEMORADOVA místo Semorádová)
-- Řešení: unaccent + case-insensitive porovnání
-- =============================================================================

-- Potřebujeme unaccent extension pro odstranění diakritiky
CREATE EXTENSION IF NOT EXISTS unaccent;

-- Helper: normalize text for comparison (no diacritics, lowercase, trimmed)
CREATE OR REPLACE FUNCTION _normalize_for_compare(t text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $$
  SELECT lower(trim(unaccent(coalesce(t, ''))))
$$;

-- Update verify_customer_docs with fuzzy name comparison
CREATE OR REPLACE FUNCTION verify_customer_docs(
  p_ocr_name text DEFAULT NULL,
  p_ocr_dob text DEFAULT NULL,
  p_ocr_id_number text DEFAULT NULL,
  p_ocr_license_number text DEFAULT NULL,
  p_ocr_license_category text DEFAULT NULL,
  p_ocr_license_expiry text DEFAULT NULL,
  p_rental_end text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_profile record;
  v_mismatches jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_status text := 'verified';
  v_uid uuid;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT * INTO v_profile FROM profiles WHERE id = v_uid;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Profile not found');
  END IF;

  -- Cross-check: jméno (fuzzy — bez diakritiky)
  IF p_ocr_name IS NOT NULL AND p_ocr_name != '' THEN
    IF v_profile.full_name IS NOT NULL AND v_profile.full_name != '' THEN
      IF _normalize_for_compare(p_ocr_name) != _normalize_for_compare(v_profile.full_name) THEN
        -- Check reversed name order (OCR may return "NOVAK JAN" vs profile "Jan Novák")
        DECLARE
          v_ocr_parts text[];
          v_ocr_reversed text;
        BEGIN
          v_ocr_parts := string_to_array(_normalize_for_compare(p_ocr_name), ' ');
          IF array_length(v_ocr_parts, 1) = 2 THEN
            v_ocr_reversed := v_ocr_parts[2] || ' ' || v_ocr_parts[1];
            IF v_ocr_reversed = _normalize_for_compare(v_profile.full_name) THEN
              -- Reversed order — OK, not a mismatch
              NULL;
            ELSE
              v_mismatches := v_mismatches || jsonb_build_array(jsonb_build_object(
                'field', 'name', 'label', 'Jméno',
                'ocr', p_ocr_name, 'profile', v_profile.full_name
              ));
              v_status := 'mismatch';
            END IF;
          ELSE
            v_mismatches := v_mismatches || jsonb_build_array(jsonb_build_object(
              'field', 'name', 'label', 'Jméno',
              'ocr', p_ocr_name, 'profile', v_profile.full_name
            ));
            v_status := 'mismatch';
          END IF;
        END;
      END IF;
    END IF;
  END IF;

  -- Cross-check: datum narození
  IF p_ocr_dob IS NOT NULL AND p_ocr_dob != '' THEN
    IF v_profile.date_of_birth IS NOT NULL THEN
      BEGIN
        IF p_ocr_dob::date != v_profile.date_of_birth THEN
          v_mismatches := v_mismatches || jsonb_build_array(jsonb_build_object(
            'field', 'dob', 'label', 'Datum narození',
            'ocr', p_ocr_dob, 'profile', v_profile.date_of_birth::text
          ));
          v_status := 'mismatch';
        END IF;
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
    END IF;
  END IF;

  -- Cross-check: číslo ŘP (normalize — spaces, dashes)
  IF p_ocr_license_number IS NOT NULL AND p_ocr_license_number != '' THEN
    IF v_profile.license_number IS NOT NULL AND v_profile.license_number != '' THEN
      IF _normalize_for_compare(regexp_replace(p_ocr_license_number, '[\s\-]', '', 'g'))
        != _normalize_for_compare(regexp_replace(v_profile.license_number, '[\s\-]', '', 'g')) THEN
        v_mismatches := v_mismatches || jsonb_build_array(jsonb_build_object(
          'field', 'license_number', 'label', 'Číslo ŘP',
          'ocr', p_ocr_license_number, 'profile', v_profile.license_number
        ));
        v_status := 'mismatch';
      END IF;
    END IF;
  END IF;

  -- Kontrola platnosti ŘP
  IF p_ocr_license_expiry IS NOT NULL AND p_ocr_license_expiry != '' THEN
    BEGIN
      IF p_ocr_license_expiry::date < CURRENT_DATE THEN
        v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
          'type', 'license_expired',
          'label', 'Řidičský průkaz je neplatný (expiroval ' || p_ocr_license_expiry || ')'
        ));
        v_status := 'mismatch';
      END IF;
      IF p_rental_end IS NOT NULL AND p_rental_end != '' THEN
        IF p_ocr_license_expiry::date < p_rental_end::date THEN
          v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
            'type', 'license_expires_before_rental_end',
            'label', 'ŘP vyprší (' || p_ocr_license_expiry || ') před koncem rezervace (' || p_rental_end || ')'
          ));
          v_status := 'mismatch';
        END IF;
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;

  -- Kontrola skupin ŘP
  IF p_ocr_license_category IS NOT NULL AND p_ocr_license_category != '' THEN
    DECLARE
      v_cats text[];
      v_has_moto boolean := false;
    BEGIN
      v_cats := string_to_array(regexp_replace(p_ocr_license_category, '\s+', ',', 'g'), ',');
      v_cats := array_remove(v_cats, '');
      FOR i IN 1..coalesce(array_length(v_cats, 1), 0) LOOP
        IF upper(trim(v_cats[i])) IN ('A', 'A1', 'A2', 'AM') THEN
          v_has_moto := true;
        END IF;
      END LOOP;
      IF NOT v_has_moto THEN
        v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
          'type', 'no_motorcycle_license',
          'label', 'ŘP neobsahuje skupinu pro motorky (A/A2/A1/AM). Nalezeno: ' || p_ocr_license_category
        ));
      END IF;
    END;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'status', v_status,
    'mismatches', v_mismatches,
    'warnings', v_warnings
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;
