-- =====================================================================
-- 20260816b_admin_create_customer_gen_salt_fix.sql
-- FIX: admin_create_customer padala na živé DB na `function gen_salt(unknown)
-- does not exist` — pgcrypto je na Supabase ve schématu `extensions`, ale
-- funkce měla pevné `SET search_path = public`, takže crypt()/gen_salt()
-- nenašla (lokální validace prošla, protože tam bylo pgcrypto v public).
-- Jediná změna: `SET search_path = public, extensions`. Tělo funkce 1:1
-- z 20260816_admin_create_customer.sql. Idempotentní (CREATE OR REPLACE).
-- =====================================================================

CREATE OR REPLACE FUNCTION admin_create_customer(
  p_full_name text,
  p_email     text DEFAULT NULL,
  p_phone     text DEFAULT NULL,
  p_street    text DEFAULT NULL,
  p_city      text DEFAULT NULL,
  p_zip       text DEFAULT NULL,
  p_country   text DEFAULT 'CZ'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id uuid;
  v_email   text;
BEGIN
  IF NOT is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
  END IF;

  IF p_full_name IS NULL OR trim(p_full_name) = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'missing_name');
  END IF;

  v_email := NULLIF(lower(trim(COALESCE(p_email, ''))), '');

  -- Zákazník s tímto emailem už existuje → nevytvářet duplicitní účet
  IF v_email IS NOT NULL THEN
    SELECT u.id INTO v_user_id FROM auth.users u
    WHERE lower(u.email) = v_email
    LIMIT 1;
    IF v_user_id IS NOT NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'email_exists',
                                'user_id', v_user_id);
    END IF;
  END IF;

  v_user_id := gen_random_uuid();

  -- Stejný vzor jako create_web_booking: reálný auth účet s náhodným heslem.
  -- Email potvrzený → zákazník si později může heslo nastavit přes recovery.
  INSERT INTO auth.users (
    id, instance_id, email, encrypted_password,
    email_confirmed_at, aud, role,
    raw_user_meta_data, created_at, updated_at
  ) VALUES (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    v_email,
    crypt(gen_random_uuid()::text, gen_salt('bf')),
    CASE WHEN v_email IS NOT NULL THEN now() ELSE NULL END,
    'authenticated', 'authenticated',
    jsonb_build_object('full_name', trim(p_full_name), 'phone', NULLIF(trim(COALESCE(p_phone,'')), '')),
    now(), now()
  );

  -- handle_new_user() trigger už mohl profil založit → upsert dat z formuláře
  INSERT INTO profiles (id, full_name, email, phone, street, city, zip, country, registration_source)
  VALUES (
    v_user_id,
    trim(p_full_name),
    v_email,
    NULLIF(trim(COALESCE(p_phone,   '')), ''),
    NULLIF(trim(COALESCE(p_street,  '')), ''),
    NULLIF(trim(COALESCE(p_city,    '')), ''),
    NULLIF(trim(COALESCE(p_zip,     '')), ''),
    COALESCE(NULLIF(trim(COALESCE(p_country, '')), ''), 'CZ'),
    'velin'
  )
  ON CONFLICT (id) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    email     = COALESCE(EXCLUDED.email, profiles.email),
    phone     = COALESCE(EXCLUDED.phone, profiles.phone),
    street    = COALESCE(EXCLUDED.street, profiles.street),
    city      = COALESCE(EXCLUDED.city, profiles.city),
    zip       = COALESCE(EXCLUDED.zip, profiles.zip),
    country   = EXCLUDED.country,
    -- 'auth_trigger' = technický placeholder živého handle_new_user (viz 20260728) → přepsat
    registration_source = CASE WHEN profiles.registration_source IS NULL
                                 OR profiles.registration_source = 'auth_trigger'
                          THEN 'velin' ELSE profiles.registration_source END,
    updated_at = now();

  -- Audit správnými sloupci (admin_audit_log NEMÁ sloupec `details`)
  BEGIN
    INSERT INTO admin_audit_log (admin_id, action, entity_type, entity_id, new_data)
    VALUES (auth.uid(), 'customer_created', 'profiles', v_user_id,
            jsonb_build_object('full_name', trim(p_full_name), 'email', v_email));
  EXCEPTION WHEN OTHERS THEN
    NULL; -- audit nesmí shodit vytvoření zákazníka
  END;

  RETURN jsonb_build_object('success', true, 'user_id', v_user_id);
END;
$$;

GRANT EXECUTE ON FUNCTION admin_create_customer(text, text, text, text, text, text, text) TO authenticated;
