-- 2026-09-27: zrcadlení obrazovky kiosku ve Velíně (+ vzdálený tap) — CONTRACT §29.
-- Jednotka (raspberry/motogo-box/screen_mirror.py) během relace spuštěné z Velína snímá obrazovku Chromia přes
-- Chrome DevTools Protocol (jen 127.0.0.1:9222) a posílá JPEG snímky (base64, ≤ 1 fps, 960×540, jen při změně)
-- RPC `kiosk_push_screen_frame` do JEDNOHO řádku na zařízení (`kiosk_screen_frames`, realtime → Velín <img>).
-- Relaci (`kiosk_screen_sessions`) zakládá a udržuje (keepalive `expires_at`) admin ve Velíně; jednotka ji ukončí
-- sama, když RPC vrátí active:false, po TTL, nebo když se 60 s nedaří odeslat. `control` = admin smí klepat
-- (příkaz `screen_input`). Kiosk během relace nic nezobrazuje (rozhodnutí majitele 2026-09-27). Idempotentní.

CREATE TABLE IF NOT EXISTS public.kiosk_screen_sessions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id     uuid NOT NULL REFERENCES public.kiosk_devices(id) ON DELETE CASCADE,
  branch_id     uuid REFERENCES public.branches(id) ON DELETE SET NULL,
  created_by    uuid,
  control       boolean NOT NULL DEFAULT false,      -- admin smí klepat (screen_input)
  max_fps       numeric NOT NULL DEFAULT 1,
  quality       int NOT NULL DEFAULT 45,
  max_width     int NOT NULL DEFAULT 960,
  created_at    timestamptz NOT NULL DEFAULT now(),
  expires_at    timestamptz NOT NULL DEFAULT now() + interval '90 seconds',   -- Velín prodlužuje á 30 s
  ended_at      timestamptz,
  frames_total  int NOT NULL DEFAULT 0,
  bytes_total   bigint NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_kiosk_screen_sessions_active ON public.kiosk_screen_sessions(device_id) WHERE ended_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_kiosk_screen_sessions_device ON public.kiosk_screen_sessions(device_id, created_at DESC);
ALTER TABLE public.kiosk_screen_sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS kiosk_screen_sessions_admin ON public.kiosk_screen_sessions;
CREATE POLICY kiosk_screen_sessions_admin ON public.kiosk_screen_sessions FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.kiosk_screen_sessions TO authenticated, service_role;
COMMENT ON TABLE public.kiosk_screen_sessions IS 'Relace zrcadlení obrazovky kiosku z Velína (2026-09-27, CONTRACT §29). Jedna aktivní na zařízení.';

CREATE TABLE IF NOT EXISTS public.kiosk_screen_frames (
  device_id     uuid PRIMARY KEY REFERENCES public.kiosk_devices(id) ON DELETE CASCADE,
  session_id    uuid,
  seq           bigint NOT NULL DEFAULT 0,
  frame         text,                                  -- base64 JPEG (NULL po konci relace)
  width         int,
  height        int,
  captured_at   timestamptz,
  meta          jsonb NOT NULL DEFAULT '{}'::jsonb,   -- {dialog:{type,message}} = nativní dialog v Chromiu (screencast ho nevidí)
  updated_at    timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.kiosk_screen_frames ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS kiosk_screen_frames_admin_select ON public.kiosk_screen_frames;
CREATE POLICY kiosk_screen_frames_admin_select ON public.kiosk_screen_frames FOR SELECT USING (public.is_admin());
GRANT SELECT ON public.kiosk_screen_frames TO authenticated, service_role;
COMMENT ON TABLE public.kiosk_screen_frames IS 'Poslední snímek obrazovky kiosku (1 řádek / zařízení). Zapisuje jen RPC kiosk_push_screen_frame; Velín čte realtime.';

-- Konec relace (ended_at) → snímek se smaže, ať v DB neleží obrazovka se zadávaným kódem / protokolem.
CREATE OR REPLACE FUNCTION public.kiosk_screen_session_ended()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.ended_at IS NOT NULL AND (OLD.ended_at IS NULL) THEN
    UPDATE public.kiosk_screen_frames SET frame = NULL, meta = jsonb_build_object('ended', true), updated_at = now()
     WHERE device_id = NEW.device_id AND session_id = NEW.id;
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_kiosk_screen_session_ended ON public.kiosk_screen_sessions;
CREATE TRIGGER trg_kiosk_screen_session_ended AFTER UPDATE OF ended_at ON public.kiosk_screen_sessions
  FOR EACH ROW EXECUTE FUNCTION public.kiosk_screen_session_ended();

-- RPC: jednotka posílá snímek (nebo jen ping s p_frame NULL) a dozví se, zda relace trvá a zda je povolené ovládání.
CREATE OR REPLACE FUNCTION public.kiosk_push_screen_frame(
  p_device_id uuid, p_device_token uuid, p_session_id uuid, p_seq bigint,
  p_frame text DEFAULT NULL, p_width int DEFAULT NULL, p_height int DEFAULT NULL, p_meta jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_bid uuid; v_sess public.kiosk_screen_sessions%ROWTYPE; v_last timestamptz;
BEGIN
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, false);
  IF v_bid IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'unauthorized'); END IF;
  SELECT * INTO v_sess FROM public.kiosk_screen_sessions WHERE id = p_session_id AND device_id = p_device_id;
  IF NOT FOUND OR v_sess.ended_at IS NOT NULL OR v_sess.expires_at < now() THEN
    IF FOUND AND v_sess.ended_at IS NULL THEN
      UPDATE public.kiosk_screen_sessions SET ended_at = now() WHERE id = v_sess.id;   -- vypršela bez keepalive → trigger smaže snímek
    ELSE
      UPDATE public.kiosk_screen_frames SET frame = NULL, meta = jsonb_build_object('ended', true), updated_at = now()
       WHERE device_id = p_device_id AND session_id = p_session_id AND frame IS NOT NULL;
    END IF;
    RETURN jsonb_build_object('ok', true, 'active', false);
  END IF;
  IF p_frame IS NOT NULL THEN
    IF pg_column_size(p_frame) > 262144 THEN
      RETURN jsonb_build_object('ok', false, 'active', true, 'error', 'too_large', 'control', v_sess.control, 'expires_at', v_sess.expires_at);
    END IF;
    SELECT updated_at INTO v_last FROM public.kiosk_screen_frames WHERE device_id = p_device_id AND session_id = p_session_id;
    IF v_last IS NOT NULL AND v_last > now() - interval '200 milliseconds' THEN
      RETURN jsonb_build_object('ok', false, 'active', true, 'error', 'rate_limited', 'control', v_sess.control, 'expires_at', v_sess.expires_at);
    END IF;
    INSERT INTO public.kiosk_screen_frames(device_id, session_id, seq, frame, width, height, captured_at, meta, updated_at)
    VALUES (p_device_id, p_session_id, coalesce(p_seq, 0), p_frame, p_width, p_height, now(), coalesce(p_meta, '{}'::jsonb), now())
    ON CONFLICT (device_id) DO UPDATE SET session_id = EXCLUDED.session_id, seq = EXCLUDED.seq, frame = EXCLUDED.frame,
      width = EXCLUDED.width, height = EXCLUDED.height, captured_at = now(), meta = EXCLUDED.meta, updated_at = now();
    UPDATE public.kiosk_screen_sessions SET frames_total = frames_total + 1, bytes_total = bytes_total + length(p_frame)
     WHERE id = v_sess.id;
  ELSIF p_meta IS NOT NULL AND p_meta <> '{}'::jsonb THEN
    UPDATE public.kiosk_screen_frames SET meta = p_meta, updated_at = now()
     WHERE device_id = p_device_id AND session_id = p_session_id;
  END IF;
  RETURN jsonb_build_object('ok', true, 'active', true, 'control', v_sess.control, 'expires_at', v_sess.expires_at,
                            'max_fps', v_sess.max_fps, 'quality', v_sess.quality, 'max_width', v_sess.max_width);
END; $$;
REVOKE ALL ON FUNCTION public.kiosk_push_screen_frame(uuid, uuid, uuid, bigint, text, int, int, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.kiosk_push_screen_frame(uuid, uuid, uuid, bigint, text, int, int, jsonb) TO anon, authenticated, service_role;
COMMENT ON FUNCTION public.kiosk_push_screen_frame(uuid, uuid, uuid, bigint, text, int, int, jsonb) IS
  'Snímek obrazovky kiosku (base64 JPEG ≤ 256 KiB, max 5/s) nebo ping (p_frame NULL) do kiosk_screen_frames; vrací {ok, active, control, expires_at}. Auth device_id+token.';

-- Realtime: Velín odebírá změny řádku snímku.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'kiosk_screen_frames'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.kiosk_screen_frames;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ALTER PUBLICATION supabase_realtime ADD kiosk_screen_frames selhalo: %', SQLERRM;
END $$;

-- Nové vzdálené příkazy: screen_mirror {session_id, on, control, max_fps?, quality?, max_width?, ttl_s?},
-- screen_input {session_id, kind: tap|dialog, x, y, text, sent_at}. Vždy DROP + ADD (CLAUDE.md).
ALTER TABLE public.kiosk_commands DROP CONSTRAINT IF EXISTS kiosk_commands_command_check;
ALTER TABLE public.kiosk_commands ADD CONSTRAINT kiosk_commands_command_check
  CHECK (command IN (
    'open_door','music_on','music_off','identify','reload','camera_control','http_get','restart',
    'light_on','light_off','set_signal','zone_test','audio_test','all_off','reboot','sync_config','update_software',
    'diagnostics','update_system','shell_unlock','protocol_signed',
    'contact_test','lte_mode',
    'screen_mirror','screen_input'
  ));
