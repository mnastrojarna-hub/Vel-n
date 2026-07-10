-- =============================================================================
-- MIGRACE 2026-07-19: Aktivace rezervace na OBSLUŽNÉ pobočce až předáním protokolu
--
-- Cíl (zadání): na obslužné pobočce (`branches.type='obslužná'`) se rezervace
-- překlopí z `reserved` na `active` AŽ podpisem/uložením předávacího protokolu
-- (elektronicky ve Velíně) nebo potvrzením tištěného protokolu tlačítkem ve Velíně.
-- Tím `picked_up_at` odpovídá reálnému času předání a stav `active` = motorka
-- skutečně předaná. Samoobslužná / svoz / ostatní pobočky beze změny.
--
-- Tři na sebe navázané kusy:
--   1) trg_gate_obsluzna_activation — TVRDÝ strážce: jakýkoli přechod →active na
--      obslužné bez vyplněného protokolu (`handover_protocol_filled_at`) se srazí
--      zpět na `reserved`. Odchytí i `confirm_payment` (same-day platba → dnes by
--      šla rovnou na active) a případné ruční/cron aktivace — BEZ nutnosti
--      přepisovat křehkou `confirm_payment` (revive logika, atomic dedup).
--   2) auto_activate_reserved_bookings() — půlnoční cron NEaktivuje obslužné
--      (ty čekají na předání). Ostatní pobočky beze změny.
--   3) auto_complete_expired_bookings() — dvoukrokově: nejdřív dozvednuté paid
--      rezervace po `end_date` promotuje reserved→active (označí protokol jako
--      auto-vyplněný, aby prošly strážcem), pak active→completed. Tím se KF
--      (konečná faktura) vygeneruje i pro obslužné rezervace, které nikdy neprošly
--      ručním předáním (no-show / obsluha zapomněla potvrdit) — KF trigger totiž
--      střílí JEN na active→completed, přímé reserved→completed by KF minulo.
--
-- Velín (mimo tuto migraci): CheckInModal.markPickedUp a nové tlačítko „Potvrdit
-- tištěný protokol" v PickupReadiness nastaví handover_protocol_filled_at spolu
-- se status='active' → projdou strážcem.
-- =============================================================================

-- 1) Strážce aktivace na obslužné pobočce -------------------------------------
CREATE OR REPLACE FUNCTION _gate_obsluzna_activation()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_obsluzna boolean;
BEGIN
  -- Reaguj jen na přechod DO active z jiného stavu.
  IF NEW.status <> 'active' OR OLD.status = 'active' THEN
    RETURN NEW;
  END IF;

  -- Předávací protokol vyplněn (podpis / uložení / potvrzení tištěného) → pusť.
  -- Nastavuje ho Velín (markPickedUp / tištěný protokol) i auto-complete promote.
  IF NEW.handover_protocol_filled_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- Je rezervace na obslužné pobočce?
  SELECT COALESCE(br.type = 'obslužná', false) INTO v_obsluzna
  FROM motorcycles m
  JOIN branches br ON br.id = m.branch_id
  WHERE m.id = NEW.moto_id;

  IF COALESCE(v_obsluzna, false) THEN
    -- Aktivace až předáním protokolu — držíme reserved a nedáváme picked_up_at.
    NEW.status := 'reserved';
    NEW.picked_up_at := OLD.picked_up_at;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_gate_obsluzna_activation ON bookings;
CREATE TRIGGER trg_gate_obsluzna_activation
  BEFORE UPDATE OF status ON bookings
  FOR EACH ROW
  WHEN (NEW.status = 'active' AND OLD.status <> 'active')
  EXECUTE FUNCTION _gate_obsluzna_activation();

-- 2) Půlnoční auto-aktivace — vynech obslužné pobočky ------------------------
CREATE OR REPLACE FUNCTION auto_activate_reserved_bookings()
RETURNS void AS $$
BEGIN
  UPDATE bookings b SET
    status = 'active',
    picked_up_at = COALESCE(b.picked_up_at, NOW())
  WHERE b.status = 'reserved'
    AND b.payment_status = 'paid'
    AND b.start_date::date <= CURRENT_DATE
    -- Obslužné pobočky se aktivují AŽ předávacím protokolem (viz strážce výše),
    -- nikoli půlnočním cronem.
    AND NOT EXISTS (
      SELECT 1 FROM motorcycles m
      JOIN branches br ON br.id = m.branch_id
      WHERE m.id = b.moto_id AND br.type = 'obslužná'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3) Auto-complete dvoukrokově (promote → complete) → KF i bez ruční aktivace --
CREATE OR REPLACE FUNCTION auto_complete_expired_bookings()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Krok 1: dozvednuté paid rezervace po end_date, které nikdy neprošly přes
  -- active (typicky obslužná bez ručního předání), promotuj reserved→active.
  -- Označ protokol jako auto-vyplněný, aby přechod prošel strážcem
  -- trg_gate_obsluzna_activation. Door kódy už existují z reserved (idempotentní,
  -- žádná nová SMS); vzápětí je deaktivuje přechod na completed.
  UPDATE bookings SET
    status = 'active'::booking_status,
    picked_up_at = COALESCE(picked_up_at, NOW()),
    handover_protocol_autofilled = CASE
      WHEN handover_protocol_filled_at IS NULL THEN true
      ELSE handover_protocol_autofilled END,
    handover_protocol_filled_at = COALESCE(handover_protocol_filled_at, NOW())
  WHERE status = 'reserved'
    AND end_date < CURRENT_DATE
    AND payment_status IN ('paid', 'partial_refund', 'refund_pending');

  -- Krok 2: dokonči všechny aktivní (vč. právě promotovaných) po end_date.
  -- Přechod active→completed spustí KF trigger (generate_final_invoice_on_complete).
  UPDATE bookings SET
    status = 'completed'::booking_status,
    returned_at = NOW()
  WHERE status = 'active'
    AND end_date < CURRENT_DATE
    AND payment_status IN ('paid', 'partial_refund', 'refund_pending');
END;
$$;
