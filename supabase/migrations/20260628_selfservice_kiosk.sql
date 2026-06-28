-- ============================================================================
-- Samoobslužná pobočka (AlzaBox na motorky) — kiosk backend
-- Migrace: 20260628_selfservice_kiosk.sql
--
-- Přidává:
--   1) branch_kiosk_config   — 1:1 konfigurace kiosku per pobočka (token, hudba, časování)
--   2) branch_doors          — mapování logických dveří → Shelly relé + světlo (LAN)
--   3) branch_service_codes  — servisní hesla (víc/pobočka, měnitelná, otevírají vše)
--   4) branch_door_events    — audit otevření
--   5) RPC kiosk_resolve_code / kiosk_log_open (SECURITY DEFINER, anon-callable přes token)
--
-- Pozn.: fyzické "číslo dveří" motorky = motorcycles.box_number (už existuje).
--        Dveře k oblečení = JEDNY sdílené per pobočka (door_kind='accessories').
-- ============================================================================

-- ─── 1) Konfigurace kiosku per pobočka ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.branch_kiosk_config (
  branch_id        uuid PRIMARY KEY REFERENCES public.branches(id) ON DELETE CASCADE,
  kiosk_token      uuid NOT NULL DEFAULT gen_random_uuid(),  -- tajný token, který drží tablet
  music_on_url     text,        -- HTTP (GET) spuštění hudby na celé pobočce (Shelly/přehrávač)
  music_off_url    text,        -- HTTP (GET) zastavení hudby (volitelné)
  relay_base_url   text,        -- volitelný základ URL pro relé na LAN (jen informativní)
  door_open_seconds  integer NOT NULL DEFAULT 8,    -- jak dlouho držet zámek otevřený (info pro app)
  light_seconds      integer NOT NULL DEFAULT 120,  -- jak dlouho svítit v garáži (info pro app)
  music_seconds      integer NOT NULL DEFAULT 90,   -- jak dlouho hrát hudbu po zadání kódu
  is_active        boolean NOT NULL DEFAULT true,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

-- ─── 2) Mapování dveří → relé/světlo ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.branch_doors (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id   uuid NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  door_kind   text NOT NULL CHECK (door_kind IN ('motorcycle','accessories')),
  box_number  integer,          -- pro door_kind='motorcycle' = motorcycles.box_number; pro accessories NULL
  label       text,             -- volitelný popis ("Garáž 1", "Skříň oblečení")
  relay_url   text,             -- HTTP (GET) otevření zámku (Shelly REST, LAN)
  light_url   text,             -- HTTP (GET) rozsvícení světla v té garáži (LAN)
  is_active   boolean NOT NULL DEFAULT true,
  sort_order  integer NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- Max jedny dveře na motorku (box) na pobočce
CREATE UNIQUE INDEX IF NOT EXISTS uq_branch_doors_moto
  ON public.branch_doors(branch_id, box_number)
  WHERE door_kind = 'motorcycle';
-- Max jedny sdílené dveře na oblečení na pobočce
CREATE UNIQUE INDEX IF NOT EXISTS uq_branch_doors_acc
  ON public.branch_doors(branch_id)
  WHERE door_kind = 'accessories';
CREATE INDEX IF NOT EXISTS idx_branch_doors_branch ON public.branch_doors(branch_id);

-- ─── 3) Servisní hesla ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.branch_service_codes (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id   uuid NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  code        text NOT NULL,        -- servisní heslo (alfanumerické — QWERTY klávesnice)
  label       text,                 -- komu patří ("Technik Petr")
  is_active   boolean NOT NULL DEFAULT true,
  created_by  uuid,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_branch_service_codes
  ON public.branch_service_codes(branch_id, code) WHERE is_active;
CREATE INDEX IF NOT EXISTS idx_branch_service_codes_branch ON public.branch_service_codes(branch_id);

-- ─── 4) Audit otevření ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.branch_door_events (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id   uuid REFERENCES public.branches(id) ON DELETE SET NULL,
  door_id     uuid REFERENCES public.branch_doors(id) ON DELETE SET NULL,
  kind        text,                 -- motorcycle / accessories / service
  booking_id  uuid,
  code_masked text,                 -- zamaskovaný kód (poslední 2 znaky)
  success     boolean NOT NULL DEFAULT true,
  detail      jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_branch_door_events_branch ON public.branch_door_events(branch_id, created_at DESC);

-- ─── updated_at triggery ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS trg_branch_kiosk_config_touch ON public.branch_kiosk_config;
CREATE TRIGGER trg_branch_kiosk_config_touch BEFORE UPDATE ON public.branch_kiosk_config
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
DROP TRIGGER IF EXISTS trg_branch_doors_touch ON public.branch_doors;
CREATE TRIGGER trg_branch_doors_touch BEFORE UPDATE ON public.branch_doors
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
DROP TRIGGER IF EXISTS trg_branch_service_codes_touch ON public.branch_service_codes;
CREATE TRIGGER trg_branch_service_codes_touch BEFORE UPDATE ON public.branch_service_codes
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- ─── RLS ────────────────────────────────────────────────────────────────────
ALTER TABLE public.branch_kiosk_config   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branch_doors          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branch_service_codes  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branch_door_events    ENABLE ROW LEVEL SECURITY;

-- Admin-only (kiosk čte výhradně přes SECURITY DEFINER RPC, NE přímo)
DROP POLICY IF EXISTS branch_kiosk_config_admin ON public.branch_kiosk_config;
CREATE POLICY branch_kiosk_config_admin ON public.branch_kiosk_config
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());
DROP POLICY IF EXISTS branch_doors_admin ON public.branch_doors;
CREATE POLICY branch_doors_admin ON public.branch_doors
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());
DROP POLICY IF EXISTS branch_service_codes_admin ON public.branch_service_codes;
CREATE POLICY branch_service_codes_admin ON public.branch_service_codes
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());
DROP POLICY IF EXISTS branch_door_events_admin ON public.branch_door_events;
CREATE POLICY branch_door_events_admin ON public.branch_door_events
  FOR SELECT USING (is_admin());

-- ─── RPC: ověření kódu na kiosku ────────────────────────────────────────────
-- Vrací jsonb. Kiosk se autorizuje přes (branch_code + kiosk_token).
-- Pořadí: servisní heslo → zákaznický kód (accessories/motorcycle) → invalid.
-- Sám relé NEovládá (relé je na LAN) — vrací URL, které appka zavolá.
CREATE OR REPLACE FUNCTION public.kiosk_resolve_code(
  p_branch_code text,
  p_kiosk_token uuid,
  p_code        text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_branch   public.branches%ROWTYPE;
  v_cfg      public.branch_kiosk_config%ROWTYPE;
  v_door     public.branch_doors%ROWTYPE;
  v_dc       public.branch_door_codes%ROWTYPE;
  v_box      integer;
  v_doors    jsonb;
  v_code     text := btrim(coalesce(p_code, ''));
BEGIN
  IF p_branch_code IS NULL OR p_kiosk_token IS NULL OR v_code = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_inputs');
  END IF;

  SELECT * INTO v_branch FROM public.branches WHERE branch_code = p_branch_code;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'branch_not_found');
  END IF;

  SELECT * INTO v_cfg FROM public.branch_kiosk_config
    WHERE branch_id = v_branch.id;
  IF NOT FOUND OR v_cfg.kiosk_token <> p_kiosk_token OR v_cfg.is_active = false THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unauthorized');
  END IF;

  -- 1) SERVISNÍ HESLO → vrátí seznam VŠECH aktivních dveří (app se zeptá které otevřít)
  IF EXISTS (
    SELECT 1 FROM public.branch_service_codes s
     WHERE s.branch_id = v_branch.id AND s.is_active AND s.code = v_code
  ) THEN
    SELECT coalesce(jsonb_agg(d ORDER BY d.ord), '[]'::jsonb) INTO v_doors
    FROM (
      SELECT bd.id, bd.door_kind, bd.box_number, bd.label, bd.relay_url, bd.light_url,
             coalesce(bd.box_number, 9999) AS ord
        FROM public.branch_doors bd
       WHERE bd.branch_id = v_branch.id AND bd.is_active
    ) d;
    RETURN jsonb_build_object(
      'ok', true, 'kind', 'service',
      'branch_id', v_branch.id, 'branch_name', v_branch.name,
      'music_on_url', v_cfg.music_on_url, 'music_off_url', v_cfg.music_off_url,
      'music_seconds', v_cfg.music_seconds, 'door_open_seconds', v_cfg.door_open_seconds,
      'light_seconds', v_cfg.light_seconds,
      'doors', v_doors
    );
  END IF;

  -- 2) ZÁKAZNICKÝ KÓD (branch_door_codes) — aktivní, vydaný, v platnosti, této pobočky
  SELECT * INTO v_dc FROM public.branch_door_codes bdc
   WHERE bdc.branch_id = v_branch.id
     AND bdc.door_code = v_code
     AND bdc.is_active = true
     AND bdc.sent_to_customer = true
     AND (bdc.valid_from  IS NULL OR bdc.valid_from  <= now())
     AND (bdc.valid_until IS NULL OR bdc.valid_until >= now())
   ORDER BY bdc.updated_at DESC
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_code');
  END IF;

  IF v_dc.code_type = 'accessories' THEN
    SELECT * INTO v_door FROM public.branch_doors
      WHERE branch_id = v_branch.id AND door_kind = 'accessories' AND is_active
      LIMIT 1;
  ELSE
    SELECT box_number INTO v_box FROM public.motorcycles WHERE id = v_dc.moto_id;
    SELECT * INTO v_door FROM public.branch_doors
      WHERE branch_id = v_branch.id AND door_kind = 'motorcycle'
        AND box_number = v_box AND is_active
      LIMIT 1;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'kind', v_dc.code_type,
    'branch_id', v_branch.id, 'branch_name', v_branch.name,
    'booking_id', v_dc.booking_id,
    'box_number', coalesce(v_door.box_number, v_box),
    'music_on_url', v_cfg.music_on_url, 'music_off_url', v_cfg.music_off_url,
    'music_seconds', v_cfg.music_seconds, 'door_open_seconds', v_cfg.door_open_seconds,
    'light_seconds', v_cfg.light_seconds,
    'door', CASE WHEN v_door.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id', v_door.id, 'door_kind', v_door.door_kind, 'box_number', v_door.box_number,
      'label', v_door.label, 'relay_url', v_door.relay_url, 'light_url', v_door.light_url
    ) END,
    'door_configured', (v_door.id IS NOT NULL)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.kiosk_resolve_code(text, uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION public.kiosk_resolve_code(text, uuid, text)
  TO anon, authenticated, service_role;

-- ─── RPC: audit otevření (volá kiosk po pokusu o ovládání HW) ────────────────
CREATE OR REPLACE FUNCTION public.kiosk_log_open(
  p_branch_code text,
  p_kiosk_token uuid,
  p_door_id     uuid,
  p_kind        text,
  p_booking_id  uuid,
  p_success     boolean,
  p_detail      jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_branch public.branches%ROWTYPE;
  v_cfg    public.branch_kiosk_config%ROWTYPE;
BEGIN
  SELECT * INTO v_branch FROM public.branches WHERE branch_code = p_branch_code;
  IF NOT FOUND THEN RETURN; END IF;
  SELECT * INTO v_cfg FROM public.branch_kiosk_config WHERE branch_id = v_branch.id;
  IF NOT FOUND OR v_cfg.kiosk_token <> p_kiosk_token THEN RETURN; END IF;

  INSERT INTO public.branch_door_events(branch_id, door_id, kind, booking_id, success, detail)
  VALUES (v_branch.id, p_door_id, p_kind, p_booking_id, coalesce(p_success, true), coalesce(p_detail, '{}'::jsonb));
END;
$$;

REVOKE ALL ON FUNCTION public.kiosk_log_open(text, uuid, uuid, text, uuid, boolean, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.kiosk_log_open(text, uuid, uuid, text, uuid, boolean, jsonb)
  TO anon, authenticated, service_role;
