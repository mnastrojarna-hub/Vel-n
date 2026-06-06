-- =============================================================================
-- Fix send_push_via_edge — GUC → app_settings (push se z DB neodesílal)
-- =============================================================================
-- Problém: funkce četla supabase_url + service_role_key z GUC
-- current_setting('app.settings.*'), který je na hostovaném Supabase prázdný
-- (ALTER DATABASE = permission denied) → pg_net.http_post šel "nikam" a FCM push
-- z triggeru trg_push_on_admin_message se nikdy neodeslal.
-- Řešení: čti URL + klíč z tabulky app_settings (key='supabase_url' /
-- 'service_role_key') — stejný ověřený vzor jako send_message_via_edge
-- (mig. 20260503_i18n_customer_comms.sql §5.4a).
-- Signatura beze změny (uuid, text, text, jsonb) — trigger volá dál stejně.
-- =============================================================================

DROP FUNCTION IF EXISTS send_push_via_edge(uuid, text, text, jsonb);

CREATE OR REPLACE FUNCTION send_push_via_edge(
  p_user_id uuid,
  p_title   text,
  p_body    text,
  p_data    jsonb DEFAULT '{}'::jsonb
) RETURNS void AS $$
DECLARE v_url text; v_key text;
BEGIN
  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'send_push_via_edge: app_settings missing';
    RETURN;
  END IF;
  IF p_user_id IS NULL OR p_title IS NULL THEN RETURN; END IF;

  PERFORM net.http_post(
    url := v_url || '/functions/v1/send-push',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_key,
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object(
      'user_id', p_user_id,
      'title',   p_title,
      'body',    COALESCE(p_body, ''),
      'data',    COALESCE(p_data, '{}'::jsonb)
    )
  );
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'send_push_via_edge failed (user=%, title=%): %', p_user_id, p_title, SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION send_push_via_edge(uuid, text, text, jsonb)
  TO authenticated, service_role;
