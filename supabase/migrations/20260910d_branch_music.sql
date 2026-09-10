-- ============================================================================
-- Samoobslužná pobočka — HUDBA POBOČKY (9 nezávislých zvukových kanálů)
-- Migrace: 20260910d_branch_music.sql  (navazuje na 20260909 + 20260910)
--
-- Zadání 2026-09-10: 7 kójí + šatna + venek = 9 kanálů, každý spouštěný kódem
-- (kóje svým kódem, šatna svým, venek jakýmkoliv). Hudba se nahrává z Velína
-- přetažením souborů a přiřazuje cíli (kóje / šatna / venek / společná).
--
--   * branch_music_tracks              — metadata skladeb (cíl, cesta v bucketu, pořadí, aktivní)
--   * storage bucket `branch-music`    — public read (cesty jsou uuid), zápis jen admin, 200 MB/soubor
--   * RPC kiosk_sync_config            — nový klíč `music` {updated_at, tracks[]} pro řídicí jednotku
--     (tracks[].updated_at = čas souboru v bucketu, aby změna metadat nevyvolala nové stažení)
--
-- Cíl (`target`): 'all' | 'outdoor' | 'door:<uuid branch_doors.id>'.
-- Cesta v bucketu: `<branch_id>/<track_id>.<ext>`; veřejná URL
-- `<supabase.url>/storage/v1/object/public/branch-music/<file_path>`.
-- Režim audia (selector | multi) je součástí HW mapy (branch_kiosk_config.hardware.audio.mode).
-- Idempotentní — lze spustit opakovaně.
-- ============================================================================

-- ─── 1) Tabulka skladeb ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.branch_music_tracks (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id   uuid NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  target      text NOT NULL DEFAULT 'all'
              CHECK (target = 'all' OR target = 'outdoor' OR target ~ '^door:[0-9a-f-]{36}$'),
  title       text NOT NULL,
  file_path   text NOT NULL UNIQUE,            -- cesta v bucketu branch-music
  ext         text NOT NULL,
  mime        text,
  size_bytes  bigint NOT NULL DEFAULT 0,
  duration_s  numeric,
  sort_order  int NOT NULL DEFAULT 0,
  is_active   boolean NOT NULL DEFAULT true,
  created_by  uuid,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_branch_music_tracks_branch
  ON public.branch_music_tracks(branch_id, target, sort_order);
COMMENT ON TABLE public.branch_music_tracks IS
  'Hudba samoobslužné pobočky: skladba → cíl (all | outdoor | door:<uuid>), soubor v bucketu branch-music. Jednotka si soubory stahuje sama.';
COMMENT ON COLUMN public.branch_music_tracks.target IS
  'all = společná (hraje tam, kde cíl nemá vlastní skladby) | outdoor = venek | door:<branch_doors.id> = kóje/šatna';

-- updated_at trigger (vzor trg_*_touch z 20260628; touch_updated_at už existuje)
CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;
DROP TRIGGER IF EXISTS trg_branch_music_tracks_touch ON public.branch_music_tracks;
CREATE TRIGGER trg_branch_music_tracks_touch BEFORE UPDATE ON public.branch_music_tracks
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- RLS: jen admin (Velín); řídicí jednotka čte přes SECURITY DEFINER RPC kiosk_sync_config
ALTER TABLE public.branch_music_tracks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS branch_music_tracks_admin ON public.branch_music_tracks;
CREATE POLICY branch_music_tracks_admin ON public.branch_music_tracks
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());

-- ─── 2) Storage bucket `branch-music` (public read, admin write, 200 MB/soubor) ─
INSERT INTO storage.buckets (id, name, public, file_size_limit)
  VALUES ('branch-music', 'branch-music', true, 209715200)
  ON CONFLICT (id) DO UPDATE SET public = true, file_size_limit = EXCLUDED.file_size_limit;

DROP POLICY IF EXISTS branch_music_admin_insert ON storage.objects;
CREATE POLICY branch_music_admin_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'branch-music' AND public.is_admin());
DROP POLICY IF EXISTS branch_music_admin_update ON storage.objects;
CREATE POLICY branch_music_admin_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'branch-music' AND public.is_admin())
  WITH CHECK (bucket_id = 'branch-music' AND public.is_admin());
DROP POLICY IF EXISTS branch_music_admin_delete ON storage.objects;
CREATE POLICY branch_music_admin_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'branch-music' AND public.is_admin());
DROP POLICY IF EXISTS branch_music_public_select ON storage.objects;
CREATE POLICY branch_music_public_select ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'branch-music');

-- ─── 3) kiosk_sync_config: + klíč `music` (tělo 1:1 z 20260910, nic nevynecháno) ─
CREATE OR REPLACE FUNCTION public.kiosk_sync_config(p_device_id uuid, p_device_token uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_bid uuid; v_branch public.branches%ROWTYPE; v_cfg public.branch_kiosk_config%ROWTYPE;
  v_key bytea; v_doors jsonb; v_services jsonb; v_codes jsonb; v_music jsonb;
BEGIN
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, true);
  IF v_bid IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'unauthorized'); END IF;
  SELECT * INTO v_branch FROM public.branches WHERE id = v_bid;
  SELECT * INTO v_cfg FROM public.branch_kiosk_config WHERE branch_id = v_bid;
  v_key := convert_to(p_device_token::text, 'UTF8');

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', d.id, 'door_kind', d.door_kind, 'box_number', d.box_number, 'label', d.label,
    'hw', coalesce(d.hw, '{}'::jsonb), 'relay_url', d.relay_url, 'light_url', d.light_url,
    'sort_order', d.sort_order)
    ORDER BY d.sort_order, coalesce(d.box_number, 9999), d.created_at), '[]'::jsonb)
  INTO v_doors FROM public.branch_doors d WHERE d.branch_id = v_bid AND d.is_active;

  -- servisní hesla — jen hashe + účel (service | diagnostics) + popisek
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'h', encode(extensions.hmac(convert_to(p_device_id::text || ':' || s.code, 'UTF8'), v_key, 'sha256'), 'hex'),
    'action', coalesce(s.action, 'service'), 'label', s.label)
    ORDER BY s.created_at), '[]'::jsonb)
  INTO v_services FROM public.branch_service_codes s WHERE s.branch_id = v_bid AND s.is_active;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'h', encode(extensions.hmac(convert_to(p_device_id::text || ':' || bdc.door_code, 'UTF8'), v_key, 'sha256'), 'hex'),
    'kind', bdc.code_type, 'booking_id', bdc.booking_id,
    'valid_from', bdc.valid_from, 'valid_until', bdc.valid_until,
    'door_id', d.id,
    'box_number', CASE WHEN bdc.code_type = 'motorcycle' THEN coalesce(d.box_number, m.box_number) ELSE d.box_number END)
    ORDER BY bdc.valid_until DESC NULLS LAST, bdc.updated_at DESC), '[]'::jsonb)
  INTO v_codes
  FROM public.branch_door_codes bdc
  LEFT JOIN public.motorcycles m ON m.id = bdc.moto_id
  LEFT JOIN public.branch_doors d ON d.branch_id = v_bid AND d.is_active AND (
        (bdc.code_type = 'accessories' AND d.door_kind = 'accessories')
     OR (bdc.code_type = 'motorcycle'  AND d.door_kind = 'motorcycle' AND d.box_number = m.box_number))
  WHERE bdc.branch_id = v_bid AND bdc.is_active = true AND bdc.sent_to_customer = true
    AND bdc.door_code IS NOT NULL AND bdc.door_code <> ''
    AND (bdc.valid_until IS NULL OR bdc.valid_until >= now() - interval '1 day');

  -- hudba pobočky — jen aktivní skladby; jednotka si soubory stáhne z public bucketu branch-music.
  -- tracks[].updated_at = čas SOUBORU (storage.objects.updated_at, fallback created_at řádku), NE řádku:
  -- jednotka podle něj stahuje znovu; přejmenování / přesun / ▲▼ pořadí soubor nemění → nic nestahuje.
  -- music.updated_at = max(updated_at) řádků = jakákoli změna metadat (pro Velín / diagnostiku).
  SELECT jsonb_build_object(
    'updated_at', max(t.updated_at),
    'tracks', coalesce(jsonb_agg(jsonb_build_object(
      'id', t.id, 'target', t.target, 'path', t.file_path, 'ext', t.ext,
      'size', t.size_bytes, 'sort_order', t.sort_order,
      'updated_at', coalesce(o.updated_at, t.created_at))
      ORDER BY t.target, t.sort_order, t.created_at), '[]'::jsonb))
  INTO v_music
  FROM public.branch_music_tracks t
  LEFT JOIN storage.objects o ON o.bucket_id = 'branch-music' AND o.name = t.file_path
  WHERE t.branch_id = v_bid AND t.is_active;

  RETURN jsonb_build_object(
    'ok', true, 'synced_at', now(), 'branch_name', v_branch.name,
    'hardware', coalesce(v_cfg.hardware, '{}'::jsonb),
    'timings', jsonb_build_object(
      'door_open_seconds', COALESCE(v_cfg.door_open_seconds, 8),
      'light_seconds',     COALESCE(v_cfg.light_seconds, 120),
      'music_seconds',     COALESCE(v_cfg.music_seconds, 90)),
    'music_on_url', v_cfg.music_on_url, 'music_off_url', v_cfg.music_off_url,
    'power_status_url', v_cfg.power_status_url,
    'power_poll_seconds', COALESCE(v_cfg.power_poll_seconds, 60),
    'doors', v_doors, 'service_codes', v_services, 'codes', v_codes,
    'music', v_music
  );
END; $$;
COMMENT ON FUNCTION public.kiosk_sync_config(uuid, uuid) IS
  'RPi řídicí jednotka: HW mapa pobočky + dveře (hw) + offline cache kódů jako HMAC-SHA256 (klíč = device_token); service_codes {h, action, label}; music {updated_at = max změny metadat, tracks[{id,target,path,ext,size,sort_order,updated_at = čas souboru v bucketu (storage.objects.updated_at, fallback created_at)}]} (jen aktivní, bucket branch-music). Auth device_id+token.';
