-- ============================================================================
-- POBOČKA REZERVACE v2 — triggery (2026-10-11; jednorázový přepočet historie
-- je zvlášť v 20261011f_booking_branch_reattribution.sql)
--
-- Majitel: „Ve Velkých Němčicích je reálně dokončená jen jedna rezervace, všechny
-- ostatní byly v Mezné.“ Triggery z 20261010b/h braly „živou“ rezervaci jako
-- reserved bez picked_up_at BEZ ohledu na datum → staré nedokončené (hotovost,
-- obslužná pobočka bez protokolu) dostávaly AKTUÁLNÍ pobočku motorky při každém
-- přesunu motorky i při změně stavu (cron auto_complete_expired_bookings krok 1,
-- Velín „Dokončit“, storno).
--
-- Nová pravidla:
--   * _booking_branch_follows(): rezervace následuje motorku jen když je
--     pending/reserved, bez picked_up_at, bez protokolu a dnes (Praha) <= den
--     začátku termínu. Potom je pobočka zmrazená.
--   * převzetí zapsané TEĎ (picked_up_at / ne-auto protokol v okně now-6 h …
--     now+10 min, nejpozději v poslední den termínu) = pobočka motorky teď
--     (pozdní vyzvednutí na kiosku); auto protokol cronu se nepočítá;
--   * navazující (extends_booking_id) a SOS náhrada dědí pobočku původní
--     (dokud původní následuje motorku, následují s ní obě);
--   * ruční změna branch_id (Velín admin / SQL editor / service role) zůstává a
--     loguje se do admin_audit_log 'booking_branch_set' (old/new); automatiky
--     (vnořené triggery, přepočty s GUC motogo.branch_reattribution) se nelogují.
--   * trigger nově reaguje i na start_date (posun termínu do budoucna = zase
--     následuje) a handover_protocol_filled_at (podpis protokolu).
-- ============================================================================

CREATE OR REPLACE FUNCTION public._booking_branch_follows(
  p_status public.booking_status, p_picked timestamptz, p_handover timestamptz, p_start timestamptz)
RETURNS boolean
LANGUAGE sql STABLE
SET search_path = public
AS $$
  SELECT COALESCE(p_status IN ('pending', 'reserved') AND p_picked IS NULL AND p_handover IS NULL
                  AND (now() AT TIME ZONE 'Europe/Prague')::date <= (p_start AT TIME ZONE 'Europe/Prague')::date, false)
$$;
REVOKE ALL ON FUNCTION public._booking_branch_follows(public.booking_status, timestamptz, timestamptz, timestamptz)
  FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION public._booking_branch_follows(public.booking_status, timestamptz, timestamptz, timestamptz) IS
  'TRUE = pobočka rezervace ještě následuje motorku (pending/reserved, bez převzetí a protokolu, dnes Praha <= den začátku). 20261011e.';

CREATE OR REPLACE FUNCTION public._booking_set_branch()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_parent      uuid := COALESCE(NEW.extends_booking_id,
                                 CASE WHEN NEW.sos_replacement IS TRUE THEN NEW.replacement_for_booking_id END);
  v_priv        boolean := auth.uid() IS NULL OR public.is_admin();
  v_now_win     boolean;
  v_moto_br     uuid;
  v_parent_br   uuid;
  v_parent_live boolean := false;
BEGIN
  SELECT m.branch_id INTO v_moto_br FROM motorcycles m WHERE m.id = NEW.moto_id;
  IF v_parent IS NOT DISTINCT FROM NEW.id THEN v_parent := NULL; END IF;
  IF v_parent IS NOT NULL THEN
    SELECT b.branch_id, public._booking_branch_follows(b.status, b.picked_up_at, b.handover_protocol_filled_at, b.start_date)
      INTO v_parent_br, v_parent_live FROM bookings b WHERE b.id = v_parent;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.branch_id := COALESCE(v_parent_br, v_moto_br, CASE WHEN v_priv THEN NEW.branch_id END);
    RETURN NEW;
  END IF;

  -- Ruční oprava (admin / service role) — ponech; log jen přímého zásahu, ne automatik.
  IF v_priv AND NEW.branch_id IS DISTINCT FROM OLD.branch_id THEN
    IF pg_trigger_depth() = 1 AND COALESCE(current_setting('motogo.branch_reattribution', true), '') = '' THEN
      BEGIN
        INSERT INTO admin_audit_log(admin_id, action, entity_type, entity_id, old_data, new_data)
        VALUES (auth.uid(), 'booking_branch_set', 'bookings', NEW.id,
                jsonb_build_object('branch_id', OLD.branch_id), jsonb_build_object('branch_id', NEW.branch_id));
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;
    RETURN NEW;
  END IF;

  NEW.branch_id := OLD.branch_id;   -- zákaznický JWT ani vedlejší změny pobočku nemění
  -- Navazující / SOS: pobočka původní (dokud původní následuje motorku, platí obecné pravidlo níže);
  -- ručně nastavenou pobočku navazující (booking_branch_set) nepřepisuj.
  IF v_parent IS NOT NULL AND NOT COALESCE(v_parent_live, false) THEN
    IF v_parent_br IS NOT NULL AND v_parent_br IS DISTINCT FROM OLD.branch_id
       AND NOT EXISTS (SELECT 1 FROM admin_audit_log a
                        WHERE a.entity_type = 'bookings' AND a.entity_id = NEW.id AND a.action = 'booking_branch_set') THEN
      NEW.branch_id := v_parent_br;
    END IF;
    NEW.branch_id := COALESCE(NEW.branch_id, v_moto_br);
    RETURN NEW;
  END IF;

  -- Do konce dne začátku (bez převzetí): pobočka motorky; storno/převzetí v té době ji zmrazí.
  IF public._booking_branch_follows(OLD.status, OLD.picked_up_at, OLD.handover_protocol_filled_at, OLD.start_date)
     OR public._booking_branch_follows(NEW.status, NEW.picked_up_at, NEW.handover_protocol_filled_at, NEW.start_date) THEN
    NEW.branch_id := COALESCE(v_moto_br, OLD.branch_id);
    RETURN NEW;
  END IF;

  -- Převzetí zapsané TEĎ (kiosk, Velín odbavení / protokol) nejpozději v poslední den termínu = kde motorka stojí.
  -- Cron (den po konci + auto protokol) ani dodatečné „Dokončit“ (picked_up_at zůstává NULL) pobočku nemění.
  v_now_win := (now() AT TIME ZONE 'Europe/Prague')::date <= (NEW.end_date AT TIME ZONE 'Europe/Prague')::date
               AND NOT (NEW.handover_protocol_autofilled IS TRUE AND OLD.handover_protocol_autofilled IS NOT TRUE)
               AND ((OLD.picked_up_at IS NULL
                     AND NEW.picked_up_at BETWEEN now() - interval '6 hours' AND now() + interval '10 minutes')
                    OR (OLD.handover_protocol_filled_at IS NULL AND NEW.handover_protocol_autofilled IS NOT TRUE
                        AND NEW.handover_protocol_filled_at BETWEEN now() - interval '6 hours' AND now() + interval '10 minutes'));
  IF COALESCE(v_now_win, false) THEN
    NEW.branch_id := COALESCE(v_moto_br, OLD.branch_id);
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '_booking_set_branch booking %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public._booking_set_branch() FROM PUBLIC, anon, authenticated;

-- Jméno řadí trigger ZA trg_detect_consecutive_booking a trg_gate_obsluzna_activation (BEFORE abecedně).
DROP TRIGGER IF EXISTS trg_set_booking_branch ON public.bookings;
CREATE TRIGGER trg_set_booking_branch
  BEFORE INSERT OR UPDATE OF moto_id, status, picked_up_at, branch_id, start_date, handover_protocol_filled_at
  ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public._booking_set_branch();

-- Přesun motorky → s ní jdou jen rezervace, které ještě následují (ne staré nedokončené).
CREATE OR REPLACE FUNCTION public._booking_branch_follow_moto()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.branch_id IS NULL THEN RETURN NULL; END IF;   -- motorka mimo pobočku: rezervace drží poslední
  UPDATE bookings b
     SET branch_id = NEW.branch_id
   WHERE b.moto_id = NEW.id
     AND public._booking_branch_follows(b.status, b.picked_up_at, b.handover_protocol_filled_at, b.start_date)
     AND (b.extends_booking_id IS NULL
          OR EXISTS (SELECT 1 FROM bookings p WHERE p.id = b.extends_booking_id
                      AND public._booking_branch_follows(p.status, p.picked_up_at, p.handover_protocol_filled_at, p.start_date)))
     AND b.sos_replacement IS NOT TRUE
     AND b.branch_id IS DISTINCT FROM NEW.branch_id;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '_booking_branch_follow_moto moto %: %', NEW.id, SQLERRM;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public._booking_branch_follow_moto() FROM PUBLIC, anon, authenticated;

COMMENT ON COLUMN public.bookings.branch_id IS
  'Pobočka rezervace = kde byla motorka v okamžiku převzetí. Do konce dne začátku termínu (bez převzetí a protokolu) následuje motorku (trg_set_booking_branch + trg_booking_branch_follow_moto, _booking_branch_follows); převzetí zapsané v termínu = pobočka motorky v tu chvíli; pak zmrazená (cron, Dokončit, storno ji nemění). Navazující / SOS dědí původní. Ruční změna → admin_audit_log booking_branch_set. Historie: 20261010b, přepočet 20261011f (admin_audit_log booking_branch_reattributed, new_data.migration = branch_v2).';
