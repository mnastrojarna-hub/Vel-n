-- 2026-09-27: kiosk_alerts — poplach „dveře otevřeny bez kódu“ (FORCED_OPEN) pro Velín v reálném čase.
-- Jednotka FORCED_OPEN zapisuje přes kiosk_log_open do branch_door_events (detail.event = 'FORCED_OPEN'); tabulka
-- není v realtime publikaci a Velín ji jen polluje. Trigger níže z takové události založí řádek kiosk_alerts
-- (realtime → Dashboard, badge Pobočky, zvonek, řádek pobočky, tab Samoobsluha) a při následném DOOR_CLOSED téže
-- zóny doplní closed_at. Poplach zmizí až ručním potvrzením (acknowledged_at) — rozhodnutí 2026-09-27.
-- Funguje i pro starší software jednotky (žádná změna na jednotce není potřeba). Idempotentní.

CREATE TABLE IF NOT EXISTS public.kiosk_alerts (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id       uuid REFERENCES public.branches(id) ON DELETE CASCADE,
  device_id       uuid REFERENCES public.kiosk_devices(id) ON DELETE SET NULL,
  door_id         uuid REFERENCES public.branch_doors(id) ON DELETE SET NULL,
  event_id        uuid REFERENCES public.branch_door_events(id) ON DELETE SET NULL,
  zone            int,
  box_number      int,
  kind            text NOT NULL DEFAULT 'forced_open' CHECK (kind IN ('forced_open')),
  title           text NOT NULL,
  detail          jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at      timestamptz NOT NULL DEFAULT now(),
  closed_at       timestamptz,          -- dveře po poplachu znovu zavřeny (DOOR_CLOSED téže zóny)
  acknowledged_at timestamptz,          -- ruční potvrzení ve Velíně (NULL = otevřený poplach)
  acknowledged_by uuid
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_kiosk_alerts_event ON public.kiosk_alerts(event_id) WHERE event_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_kiosk_alerts_open ON public.kiosk_alerts(created_at DESC) WHERE acknowledged_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_kiosk_alerts_branch ON public.kiosk_alerts(branch_id, created_at DESC);
COMMENT ON TABLE public.kiosk_alerts IS
  'Poplachy samoobsluhy pro Velín (2026-09-27): forced_open = dveře otevřeny bez kódu. Zakládá trigger z branch_door_events, potvrzuje admin.';

ALTER TABLE public.kiosk_alerts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS kiosk_alerts_admin_select ON public.kiosk_alerts;
CREATE POLICY kiosk_alerts_admin_select ON public.kiosk_alerts FOR SELECT USING (public.is_admin());
DROP POLICY IF EXISTS kiosk_alerts_admin_update ON public.kiosk_alerts;
CREATE POLICY kiosk_alerts_admin_update ON public.kiosk_alerts FOR UPDATE USING (public.is_admin()) WITH CHECK (public.is_admin());
GRANT SELECT, UPDATE ON public.kiosk_alerts TO authenticated, service_role;

-- Trigger: FORCED_OPEN → nový poplach; DOOR_CLOSED téže zóny → closed_at. Chyba tu NIKDY nesmí shodit audit otevření.
CREATE OR REPLACE FUNCTION public.kiosk_alert_from_door_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_event text; v_zone int; v_box int; v_title text;
  v_label text; v_door_box int; v_door_kind text;
BEGIN
  v_event := NEW.detail->>'event';
  IF v_event = 'FORCED_OPEN' THEN
    v_zone := NULLIF(NEW.detail->>'zone', '')::int;
    v_box  := NULLIF(NEW.detail->>'box_number', '')::int;
    SELECT d.label, d.box_number, d.door_kind INTO v_label, v_door_box, v_door_kind
      FROM public.branch_doors d WHERE d.id = NEW.door_id;
    v_box := coalesce(v_door_box, v_box);
    v_title := coalesce(NULLIF(v_label, ''),
                 CASE WHEN v_door_kind = 'accessories' THEN 'Šatna'
                      WHEN v_box IS NOT NULL THEN 'Kóje ' || v_box
                      WHEN v_zone IS NOT NULL THEN 'Zóna ' || v_zone
                      ELSE 'Dveře' END) || ': dveře otevřeny bez kódu';
    INSERT INTO public.kiosk_alerts(branch_id, device_id, door_id, event_id, zone, box_number, kind, title, detail)
    VALUES (NEW.branch_id, NEW.device_id, NEW.door_id, NEW.id, v_zone, v_box, 'forced_open', v_title, coalesce(NEW.detail, '{}'::jsonb))
    ON CONFLICT DO NOTHING;
  ELSIF v_event = 'DOOR_CLOSED' THEN
    v_zone := NULLIF(NEW.detail->>'zone', '')::int;
    UPDATE public.kiosk_alerts a SET closed_at = NEW.created_at
     WHERE a.closed_at IS NULL AND a.kind = 'forced_open'
       AND ((NEW.device_id IS NOT NULL AND a.device_id = NEW.device_id) OR (NEW.device_id IS NULL AND a.branch_id = NEW.branch_id))
       AND ((v_zone IS NOT NULL AND a.zone = v_zone) OR (v_zone IS NULL AND NEW.door_id IS NOT NULL AND a.door_id = NEW.door_id));
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'kiosk_alert_from_door_event: %', SQLERRM;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_kiosk_alert_from_door_event ON public.branch_door_events;
CREATE TRIGGER trg_kiosk_alert_from_door_event
  AFTER INSERT ON public.branch_door_events
  FOR EACH ROW EXECUTE FUNCTION public.kiosk_alert_from_door_event();

-- Realtime: Velín odebírá INSERT/UPDATE (badge, Dashboard, zvonek, pobočka).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'kiosk_alerts'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.kiosk_alerts;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ALTER PUBLICATION supabase_realtime ADD kiosk_alerts selhalo: %', SQLERRM;
END $$;
