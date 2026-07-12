-- =============================================================================
-- MIGRACE 2026-07-20: Výměna motorky bez přerušení (handoff / switch) — Model A
--
-- Scénář (zadání): jeden zákazník má dvě NAVAZUJÍCÍ rezervace na různé motorky
-- (A do 12.7, B od 13.7). Na OBSLUŽNÉ pobočce proběhne v jedné návštěvě switch:
-- zákazník vrátí moto A a po podpisu PŘEDÁVACÍHO PROTOKOLU nové motorky B jede dál.
--
-- Pravidla (dle upřesnění uživatele):
--   • Stará A se v kalendáři uvolní AŽ podpisem protokolu B (switch RPC → A completed),
--     NE datem/půlnocí — aby v 1:00 ráno nikdo nezarezervoval nevrácenou motorku.
--   • Toto „blokuj do vrácení" platí JEN u motorky, která má navazující rezervaci
--     téhož zákazníka (výměna). Běžné rezervace blokují jen do end_date jako dosud.
--   • Nová B blokuje celý den normálně (denní granularita, beze změny).
--   • Výjimka z pravidla „1 zákazník = max 1 rezervace/den" platí JEN pro dvojici
--     spojenou přes continues_booking_id (switch chain).
--
-- Čtyři kusy:
--   1) bookings.continues_booking_id — měkká vazba řetězu výměny.
--   2) get_moto_booked_dates — nevrácená motorka s navazující rezervací blokuje do dneška.
--   3) check_user_booking_overlap — výjimka pro switch chain.
--   4) swap_handoff_bookings(prev, next) — atomický switch (uzavře A, aktivuje B).
--
-- Staví na 20260719_obsluzna_activate_on_handover.sql (trg_gate_obsluzna_activation):
-- aktivaci B pustí strážce až s vyplněným handover_protocol_filled_at.
-- =============================================================================

-- 1) Vazba řetězu výměny -------------------------------------------------------
ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS continues_booking_id uuid
    REFERENCES bookings(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_bookings_continues
  ON bookings(continues_booking_id);

COMMENT ON COLUMN bookings.continues_booking_id IS
  'Výměna motorky bez přerušení: tato rezervace navazuje na rezervaci continues_booking_id (jiná motorka téhož zákazníka, obslužná pobočka). Plní swap_handoff_bookings při switchi.';

-- 2) Kalendář — nevrácená motorka s navazující rezervací blokuje do dneška -----
--    (řeší „v 1:00 ráno nikdo nezarezervuje motorku, která se ještě nevrátila").
--    Zúženo: blok do dneška JEN když má motorka navazující rezervaci téhož usera.
CREATE OR REPLACE FUNCTION public.get_moto_booked_dates(p_moto_id uuid)
RETURNS TABLE (
  start_date  date,
  end_date    date,
  status      text,
  created_at  timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT b.start_date::date,
         CASE
           -- Blokuj do dneška JEN když: motorka je fyzicky venku (active, nevrácená)
           -- A ZÁROVEŇ má tento zákazník navazující rezervaci na JINOU motorku
           -- (výměna bez přerušení). Běžné rezervace blokují jen do end_date.
           WHEN b.status = 'active' AND b.returned_at IS NULL
                AND EXISTS (
                  SELECT 1 FROM bookings s
                  WHERE s.user_id = b.user_id
                    AND s.moto_id <> b.moto_id
                    AND s.status IN ('pending','reserved','active')
                    AND s.start_date::date BETWEEN b.end_date::date AND b.end_date::date + 1
                )
             THEN GREATEST(b.end_date::date, CURRENT_DATE)
           ELSE b.end_date::date
         END,
         b.status::text,
         b.created_at
  FROM bookings b
  WHERE b.moto_id = p_moto_id
    AND b.status IN ('pending','reserved','active')

  UNION ALL

  -- Servis blokuje POUZE rozsah service_date → scheduled_date (beze změny).
  SELECT
    m.service_date::date,
    COALESCE(m.scheduled_date, m.service_date)::date,
    'service'::text,
    m.created_at
  FROM maintenance_log m
  WHERE m.moto_id = p_moto_id
    AND m.service_date IS NOT NULL
    AND m.completed_date IS NULL
    AND COALESCE(m.status,'') NOT IN ('completed','cancelled')
    AND COALESCE(m.scheduled_date, m.service_date) >= CURRENT_DATE;
$$;

GRANT EXECUTE ON FUNCTION public.get_moto_booked_dates(uuid) TO anon, authenticated, service_role;

-- 3) Overlap výjimka pro switch chain -----------------------------------------
--    Dvojici A↔B spojenou přes continues_booking_id nepovažuj za kolizi
--    (jen v tomto konkrétním případě smí mít 1 zákazník 2 rezervace ve sdílený den).
CREATE OR REPLACE FUNCTION check_user_booking_overlap()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- SOS replacement bookings are exempt from overlap check
  IF NEW.sos_replacement = true THEN
    RETURN NEW;
  END IF;

  -- Skip cancelled/completed bookings
  IF NEW.status IN ('cancelled', 'completed') THEN
    RETURN NEW;
  END IF;

  -- Check for overlapping bookings for the same user
  IF EXISTS (
    SELECT 1 FROM bookings o
    WHERE o.user_id = NEW.user_id
      AND o.id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
      AND o.status NOT IN ('cancelled', 'completed')
      AND o.sos_replacement IS NOT TRUE
      AND o.start_date::date <= NEW.end_date::date
      AND o.end_date::date >= NEW.start_date::date
      -- Výjimka: dětské motorky (license_required = 'N')
      AND o.moto_id NOT IN (SELECT id FROM motorcycles WHERE license_required = 'N')
      -- Výjimka: výměna motorky (switch chain) — dvojice A↔B spojená přes
      -- continues_booking_id se nepovažuje za kolizi ani na sdílený hraniční den.
      AND o.id IS DISTINCT FROM NEW.continues_booking_id
      AND o.continues_booking_id IS DISTINCT FROM NEW.id
  ) THEN
    RAISE EXCEPTION 'Zákazník má překrývající se rezervaci v tomto období';
  END IF;

  RETURN NEW;
END;
$$;

-- 4) Atomický switch — uzavře A (vrácení), aktivuje B (předání) ----------------
--    Předpoklad: UI PŘED voláním uloží podepsaný PŘEDÁVACÍ PROTOKOL B
--    (nastaví B.handover_protocol_filled_at). Vrácení A protokol NEMÁ (jen stav).
--    Aktivaci B pustí strážce trg_gate_obsluzna_activation (protokol B vyplněn).
CREATE OR REPLACE FUNCTION swap_handoff_bookings(p_prev uuid, p_next uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  a bookings;
  b bookings;
BEGIN
  IF NOT is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
  END IF;

  SELECT * INTO a FROM bookings WHERE id = p_prev;
  SELECT * INTO b FROM bookings WHERE id = p_next;
  IF a.id IS NULL OR b.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  IF a.user_id IS DISTINCT FROM b.user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'different_customer');
  END IF;
  IF b.payment_status NOT IN ('paid', 'partial_refund', 'refund_pending') THEN
    RETURN jsonb_build_object('success', false, 'error', 'next_not_paid');
  END IF;
  IF b.handover_protocol_filled_at IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'handover_protocol_missing');
  END IF;

  -- Uvolni A: completed + returned_at → get_moto_booked_dates ji přestane blokovat.
  UPDATE bookings
     SET status = 'completed',
         returned_at = COALESCE(returned_at, now()),
         actual_return_date = COALESCE(actual_return_date, CURRENT_DATE)
   WHERE id = p_prev
     AND status IN ('active', 'reserved');

  -- Aktivuj B (předání) + zapiš vazbu řetězu. Přechod reserved→active pustí
  -- strážce trg_gate_obsluzna_activation (protokol B je vyplněn).
  UPDATE bookings
     SET status = 'active',
         picked_up_at = COALESCE(picked_up_at, now()),
         continues_booking_id = p_prev
   WHERE id = p_next
     AND status = 'reserved';

  RETURN jsonb_build_object('success', true, 'prev', p_prev, 'next', p_next);
END;
$$;

REVOKE ALL ON FUNCTION swap_handoff_bookings(uuid, uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION swap_handoff_bookings(uuid, uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
