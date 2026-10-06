-- 2026-10-06 (zadání majitele D4): KRÁTKODOBÝ KÓD samoobslužné pobočky. Zákazník po vrácení zapomene věc v kóji /
-- šatně, zavolá → obsluha ve Velínu (detail rezervace → „Vydat krátkodobý kód“) vybere dveře, platnost 5–240 min
-- (Velín nabízí 15/30/60/120, výchozí 30) a poznámku; kód (6 číslic) nadiktuje do telefonu. Kód otevře JEN dané
-- dveře, bez km / protokolu / hradel výdeje, rezervaci NEMĚNÍ; funguje online (kiosk_resolve_code, 20261006e) i offline
-- (sync cache kiosk_sync_config, 20261006f). Samostatná tabulka — branch_door_codes nejde: booking_id NOT NULL a
-- triggery (normalizace okna na termín rezervace, SMS, deaktivace při dokončení) by krátké okno přepsaly.
-- Zápis JEN přes RPC níže (admin), audit admin_audit_log. Idempotentní.

CREATE TABLE IF NOT EXISTS public.branch_temp_codes (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id    uuid NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  door_id      uuid NOT NULL REFERENCES public.branch_doors(id) ON DELETE CASCADE,
  booking_id   uuid REFERENCES public.bookings(id) ON DELETE SET NULL,   -- jen reference pro Velín, jednotce se neposílá
  code         text NOT NULL CHECK (code ~ '^[0-9]{6}$'),
  valid_from   timestamptz NOT NULL DEFAULT now(),
  valid_until  timestamptz NOT NULL,
  note         text,
  created_by   uuid,
  created_at   timestamptz NOT NULL DEFAULT now(),
  revoked_at   timestamptz,
  revoked_by   uuid,
  use_count    integer NOT NULL DEFAULT 0,
  last_used_at timestamptz,
  CONSTRAINT branch_temp_codes_window_check CHECK (valid_until > valid_from)
);
CREATE INDEX IF NOT EXISTS idx_branch_temp_codes_branch_code ON public.branch_temp_codes(branch_id, code);
CREATE INDEX IF NOT EXISTS idx_branch_temp_codes_booking ON public.branch_temp_codes(booking_id);
COMMENT ON TABLE public.branch_temp_codes IS
  'Krátkodobé kódy samoobslužné pobočky (2026-10-06, D4): jedny dveře, platnost valid_from–valid_until (5–240 min), bez km/protokolu/hradel, rezervaci nemění. Vydává/ruší jen admin přes admin_issue_temp_door_code / admin_revoke_temp_door_code; kiosk_resolve_code (use_count) + kiosk_sync_config (HMAC, temp:true).';

ALTER TABLE public.branch_temp_codes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS branch_temp_codes_admin_select ON public.branch_temp_codes;
CREATE POLICY branch_temp_codes_admin_select ON public.branch_temp_codes FOR SELECT USING (public.is_admin());
REVOKE ALL ON public.branch_temp_codes FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.branch_temp_codes TO authenticated;
GRANT ALL ON public.branch_temp_codes TO service_role;

-- Změna kódů → jednotkám pobočky `sync_config` (offline cache). Jen sloupce, které mění cache — počítadlo použití
-- (use_count/last_used_at, zapisuje kiosk_resolve_code) sync NEvyvolá. Chyba nikdy neshodí zápis.
CREATE OR REPLACE FUNCTION public._branch_temp_codes_kiosk_sync() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF TG_OP IN ('UPDATE', 'DELETE') THEN PERFORM public.kiosk_request_sync(OLD.branch_id); END IF;
  IF TG_OP IN ('INSERT', 'UPDATE') AND (TG_OP = 'INSERT' OR NEW.branch_id IS DISTINCT FROM OLD.branch_id) THEN
    PERFORM public.kiosk_request_sync(NEW.branch_id);
  END IF;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '_branch_temp_codes_kiosk_sync: %', SQLERRM;
  RETURN NULL;
END $$;
ALTER FUNCTION public._branch_temp_codes_kiosk_sync() OWNER TO postgres;
REVOKE ALL ON FUNCTION public._branch_temp_codes_kiosk_sync() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_branch_temp_codes_kiosk_sync ON public.branch_temp_codes;
CREATE TRIGGER trg_branch_temp_codes_kiosk_sync
  AFTER INSERT OR DELETE OR UPDATE OF branch_id, door_id, code, valid_from, valid_until, revoked_at
  ON public.branch_temp_codes
  FOR EACH ROW EXECUTE FUNCTION public._branch_temp_codes_kiosk_sync();

-- Vydání kódu (Velín). Číslo: kryptograficky náhodné 100000–999999 (jako zákaznické kódy — žádná úvodní nula),
-- unikátní proti všemu, co na displeji pobočky dnes něco otevře nebo hlásí: aktivní kódy rezervací pobočky
-- (platnost do ≥ now − 1 den = i offline cache), dřívější nahrazené kódy živých rezervací (alias v kiosk_resolve_code —
-- jinak by krátkodobý kód otevřel cizí rezervaci), aktivní servisní hesla pobočky a nezrušené krátkodobé kódy pobočky.
CREATE OR REPLACE FUNCTION public.admin_issue_temp_door_code(
  p_door_id uuid, p_minutes integer DEFAULT 30, p_booking_id uuid DEFAULT NULL, p_note text DEFAULT NULL)
RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_door public.branch_doors%ROWTYPE; v_code text; v_try integer := 0; v_id uuid;
  v_from timestamptz := now(); v_until timestamptz;
BEGIN
  IF NOT public.is_admin() THEN RETURN jsonb_build_object('ok', false, 'error', 'forbidden'); END IF;
  SELECT * INTO v_door FROM public.branch_doors WHERE id = p_door_id AND is_active;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'door_not_found'); END IF;
  IF p_minutes IS NULL OR p_minutes < 5 OR p_minutes > 240 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_minutes');
  END IF;
  IF p_booking_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.bookings WHERE id = p_booking_id) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'booking_not_found');
  END IF;
  v_until := v_from + make_interval(mins => p_minutes);

  -- souběžné vydání na téže pobočce nesmí vybrat stejné číslo
  PERFORM pg_advisory_xact_lock(hashtext('branch_temp_codes:' || v_door.branch_id::text));
  LOOP
    v_try := v_try + 1;
    IF v_try > 50 THEN RETURN jsonb_build_object('ok', false, 'error', 'code_generation_failed'); END IF;
    v_code := (100000 + (('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::bigint % 900000))::text;
    CONTINUE WHEN EXISTS (SELECT 1 FROM public.branch_door_codes c
                           WHERE c.door_code = v_code AND (
                                 (c.branch_id = v_door.branch_id AND c.is_active
                                  AND (c.valid_until IS NULL OR c.valid_until >= now() - interval '1 day'))
                              OR (NOT c.is_active AND c.superseded_by_regen
                                  AND EXISTS (SELECT 1 FROM public.bookings b
                                               WHERE b.id = c.booking_id AND b.status IN ('reserved','active')))));
    CONTINUE WHEN EXISTS (SELECT 1 FROM public.branch_service_codes s
                           WHERE s.branch_id = v_door.branch_id AND s.is_active AND s.code = v_code);
    CONTINUE WHEN EXISTS (SELECT 1 FROM public.branch_temp_codes t
                           WHERE t.branch_id = v_door.branch_id AND t.code = v_code AND t.revoked_at IS NULL
                             AND t.valid_until >= now() - interval '1 day');
    EXIT;
  END LOOP;

  INSERT INTO public.branch_temp_codes(branch_id, door_id, booking_id, code, valid_from, valid_until, note, created_by)
  VALUES (v_door.branch_id, v_door.id, p_booking_id, v_code, v_from, v_until, NULLIF(btrim(p_note), ''), auth.uid())
  RETURNING id INTO v_id;

  BEGIN   -- audit (best-effort; číslo kódu do auditu nepatří — je v řádku tabulky)
    INSERT INTO public.admin_audit_log(admin_id, action, entity_type, entity_id, new_data)
    VALUES (auth.uid(), 'temp_door_code_issued', 'branch_temp_codes', v_id, jsonb_build_object(
      'branch_id', v_door.branch_id, 'door_id', v_door.id, 'door_kind', v_door.door_kind, 'box_number', v_door.box_number,
      'booking_id', p_booking_id, 'minutes', p_minutes, 'valid_until', v_until, 'note', NULLIF(btrim(p_note), '')));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('ok', true, 'id', v_id, 'code', v_code, 'valid_from', v_from, 'valid_until', v_until,
    'branch_id', v_door.branch_id, 'door', jsonb_build_object('id', v_door.id, 'door_kind', v_door.door_kind,
      'box_number', v_door.box_number, 'label', v_door.label));
END $$;
ALTER FUNCTION public.admin_issue_temp_door_code(uuid, integer, uuid, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.admin_issue_temp_door_code(uuid, integer, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_issue_temp_door_code(uuid, integer, uuid, text) TO authenticated, service_role;

-- Zrušení kódu (Velín) — idempotentní: už zrušený = ok (revoked_at se nepřepisuje).
CREATE OR REPLACE FUNCTION public.admin_revoke_temp_door_code(p_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_row public.branch_temp_codes%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN RETURN jsonb_build_object('ok', false, 'error', 'forbidden'); END IF;
  UPDATE public.branch_temp_codes SET revoked_at = now(), revoked_by = auth.uid()
   WHERE id = p_id AND revoked_at IS NULL
  RETURNING * INTO v_row;
  IF NOT FOUND THEN
    IF EXISTS (SELECT 1 FROM public.branch_temp_codes WHERE id = p_id) THEN
      RETURN jsonb_build_object('ok', true, 'already_revoked', true);
    END IF;
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;
  BEGIN
    INSERT INTO public.admin_audit_log(admin_id, action, entity_type, entity_id, new_data)
    VALUES (auth.uid(), 'temp_door_code_revoked', 'branch_temp_codes', v_row.id, jsonb_build_object(
      'branch_id', v_row.branch_id, 'door_id', v_row.door_id, 'booking_id', v_row.booking_id,
      'valid_until', v_row.valid_until, 'use_count', v_row.use_count));
  EXCEPTION WHEN OTHERS THEN NULL; END;
  RETURN jsonb_build_object('ok', true);
END $$;
ALTER FUNCTION public.admin_revoke_temp_door_code(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.admin_revoke_temp_door_code(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_revoke_temp_door_code(uuid) TO authenticated, service_role;
