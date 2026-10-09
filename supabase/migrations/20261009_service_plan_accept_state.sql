-- 20261009 — Servisní knížka: „Vše v pořádku k dnešku“ — převzetí stavu plánů z externí (papírové) evidence.
-- Zadání majitele 2026-10-09: pravidelné servisy dosud hlídal na papíru, žádný plán nemá být po termínu;
-- v zimě se projde celá motorka a od zimní prohlídky se počítá znovu.
--  (1) service_plan_accept_state(p_moto_id, p_note, p_states): všem AKTIVNÍM plánům motorky (NULL = flotila),
--      které jsou ve stavu po termínu / blíží se / neověřeno (dle get_service_due) a nejsou už v otevřeném
--      servisu, nastaví „naposledy provedeno“ = dnes při aktuálním stavu tachometru (baseline_source = manual,
--      ruční termín zrušen, poznámka s původem). Plány v pořádku se nemění. Zápis do admin_audit_log.
--      Dokončený servisní záznam (zimní prohlídka s odškrtnutými úkony) baseline znovu přepíše (trigger).
--  (2) jednorázové spuštění pro celou flotilu při nasazení.
-- Idempotentní (CREATE OR REPLACE; opakované volání nic dalšího nemění).

CREATE OR REPLACE FUNCTION public.service_plan_accept_state(
  p_moto_id uuid DEFAULT NULL,
  p_note    text DEFAULT NULL,
  p_states  text[] DEFAULT ARRAY['overdue', 'due_soon', 'unknown']
) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  r        record;
  v_note   text;
  v_cnt    int := 0;
  v_motos  uuid[] := '{}';
  v_ids    uuid[] := '{}';
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  v_note := COALESCE(NULLIF(btrim(p_note), ''), 'stav převzat z evidence ' || to_char(CURRENT_DATE, 'DD.MM.YYYY'));

  FOR r IN
    SELECT d.schedule_id, d.moto_id, d.current_km
      FROM public.get_service_due(p_moto_id) d
     WHERE d.state = ANY (p_states) AND d.open_log_id IS NULL
  LOOP
    UPDATE maintenance_schedules s
       SET last_service_km   = CASE WHEN COALESCE(r.current_km, 0) > 0 THEN r.current_km ELSE s.last_service_km END,
           last_service_date = CURRENT_DATE,
           last_performed    = CURRENT_DATE,
           baseline_source   = 'manual',
           next_due          = NULL,
           notes             = CASE WHEN NULLIF(btrim(COALESCE(s.notes, '')), '') IS NULL THEN v_note
                                    WHEN position(v_note IN s.notes) > 0 THEN s.notes
                                    ELSE s.notes || ' · ' || v_note END,
           updated_at        = now()
     WHERE s.id = r.schedule_id AND s.active;
    IF FOUND THEN
      v_cnt := v_cnt + 1;
      v_ids := v_ids || r.schedule_id;
      IF NOT (r.moto_id = ANY (v_motos)) THEN v_motos := v_motos || r.moto_id; END IF;
    END IF;
  END LOOP;

  BEGIN
    INSERT INTO admin_audit_log (admin_id, action, entity_type, entity_id, new_data)
    VALUES (auth.uid(), 'service_plan_accept_state', 'motorcycle', p_moto_id,
            jsonb_build_object('note', v_note, 'states', p_states, 'updated', v_cnt, 'motos', v_motos, 'schedule_ids', v_ids));
  EXCEPTION WHEN OTHERS THEN NULL;   -- audit nesmí shodit akci
  END;

  RETURN jsonb_build_object('ok', true, 'updated', v_cnt, 'motos', COALESCE(array_length(v_motos, 1), 0), 'note', v_note);
END $$;

COMMENT ON FUNCTION public.service_plan_accept_state(uuid, text, text[]) IS
  '„Vše v pořádku k dnešku“ (2026-10-09): aktivním plánům motorky (NULL = flotila) ve stavu overdue/due_soon/unknown (dle get_service_due, ne v otevřeném servisu) nastaví naposledy provedeno = dnes při aktuálním stavu tachometru (baseline manual, next_due NULL, poznámka). Plány v pořádku nemění. Vrací {updated, motos, note}. Audit admin_audit_log. Volá Velín (knížka motorky, Servis → Plánované).';

REVOKE ALL ON FUNCTION public.service_plan_accept_state(uuid, text, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.service_plan_accept_state(uuid, text, text[]) TO authenticated, service_role;

-- (2) jednorázově celá flotila — dosud hlídáno na papíru, odpočet od zimní prohlídky
SELECT public.service_plan_accept_state(NULL, 'stav převzat z papírové evidence ' || to_char(CURRENT_DATE, 'DD.MM.YYYY'));
