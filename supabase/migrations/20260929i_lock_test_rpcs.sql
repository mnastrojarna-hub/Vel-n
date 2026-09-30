-- =============================================================================
-- BEZPEČNOST (2026-09-29): testovací RPC jen pro service_role
-- Migrace: 20260929i_lock_test_rpcs.sql — idempotentní
-- Testovací RPC (AI trénink, SECURITY DEFINER, obchází RLS) měly EXECUTE pro anon
-- i authenticated: kdokoli bez přihlášení mohl měnit libovolnou rezervaci
-- (update_test_booking_fields/status), označit reálný profil jako testovací
-- (create_test_customer) a pak ho smazat i z auth.users (cleanup_all_test_data).
-- V repu nemají žádného volajícího → EXECUTE jen service_role.
-- =============================================================================
DO $$
DECLARE f regprocedure;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname IN ('cleanup_all_test_data', 'create_test_booking', 'create_test_customer',
                         'create_test_maintenance_log', 'create_test_service_order', 'create_test_sos_incident',
                         'create_test_sos_timeline', 'update_test_booking_status', 'update_test_profile',
                         'update_test_sos_status', 'update_test_booking_fields')
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f);
  END LOOP;
END $$;
