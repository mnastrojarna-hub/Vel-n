-- =============================================================================
-- MIGRACE: sledování zařízení u webové rezervace (PC / mobil / tablet)
-- Datum: 2026-05-30
-- Branch: claude/customer-info-storage-bug-QGk6Y
--
-- Požadavek: ve Velíně u rezervace vidět, na jakém zařízení zákazník rezervoval
-- (PC / mobil / tablet) a zachytit i cross-device průběh „začal na PC, dokončil
-- na mobilu" (typicky QR resume). Proto dvě fáze:
--   - created_device   = zařízení při vytvoření rezervace (krok 1)
--   - completed_device = zařízení při kliknutí na platbu (krok 2 / dokončení)
-- Pokud se liší, Velín zobrazí „PC → Mobil".
--
-- Hodnoty: 'pc' | 'mobile' | 'tablet' (detekuje frontend z user-agenta + šířky).
-- =============================================================================

ALTER TABLE bookings ADD COLUMN IF NOT EXISTS created_device   text;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS completed_device text;

-- Post-create / post-payment helper — keyed přes booking_id, obchází RLS.
-- p_phase = 'created'  → nastaví created_device jen poprvé (NULL → hodnota),
--                        ať „Zpět"/resume nepřepíše původní zařízení startu.
-- p_phase = 'completed'→ nastaví completed_device (poslední zařízení = to,
--                        ze kterého se rezervace dokončila / platilo).
CREATE OR REPLACE FUNCTION public.set_web_booking_device(
  p_booking_id uuid,
  p_device text,
  p_phase text DEFAULT 'created'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_source text;
  v_device text;
BEGIN
  IF p_booking_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Booking ID je povinné');
  END IF;

  -- normalizace na povolené hodnoty (neznámé → NULL, neukládáme)
  v_device := CASE lower(COALESCE(p_device, ''))
    WHEN 'pc' THEN 'pc'
    WHEN 'desktop' THEN 'pc'
    WHEN 'mobile' THEN 'mobile'
    WHEN 'phone' THEN 'mobile'
    WHEN 'tablet' THEN 'tablet'
    ELSE NULL
  END;
  IF v_device IS NULL THEN
    RETURN jsonb_build_object('error', 'Neznámé zařízení');
  END IF;

  SELECT booking_source INTO v_source FROM bookings WHERE id = p_booking_id;
  IF v_source IS NULL THEN
    RETURN jsonb_build_object('error', 'Rezervace nenalezena');
  END IF;
  IF v_source IS DISTINCT FROM 'web' THEN
    RETURN jsonb_build_object('error', 'Pouze pro webové rezervace');
  END IF;

  IF p_phase = 'completed' THEN
    UPDATE bookings SET completed_device = v_device WHERE id = p_booking_id;
  ELSE
    -- jen poprvé — zachová zařízení, na kterém rezervace skutečně začala
    UPDATE bookings SET created_device = v_device
      WHERE id = p_booking_id AND created_device IS NULL;
  END IF;

  RETURN jsonb_build_object('success', true);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_web_booking_device(uuid, text, text) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
