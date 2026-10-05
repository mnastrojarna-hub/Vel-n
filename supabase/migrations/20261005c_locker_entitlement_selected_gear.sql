-- 2026-10-05 — nárok na kód šatny podle VYBRANÉ výbavy (zadání majitele po incidentu ve Velkých Němčicích):
-- „Kód šatny musí přijít, když si zákazník výbavu doplní v úpravě rezervace; kdo má ,základní výbavu v ceně‘,
--  kód šatny dostane; co si vybral, musí být vidět na displeji.“
--
-- Dosud: rider_own = own_gear (je-li NOT NULL) → zákazník s „vlastní výbavou“ (own_gear = true), který si pak
-- výbavu řidiče doplnil (web /upravit-rezervaci volá update_booking_gear bez p_own_gear → own_gear zůstane true,
-- Velín), kód šatny NEdostal, ačkoli protokol na displeji tu výbavu ukazuje (_kiosk_protocol bere všechny
-- neprázdné velikosti). Nově: šatna = own_gear = false („základní výbava v ceně“ — i bez velikostí; starší appka
-- velikost nevynucovala, kiosk ≥ 1.2.5 se pak na převzatou výbavu zeptá) NEBO jakákoli vybraná velikost z 10.
-- Mění se jen případ own_gear = true + vybrané velikosti řidiče (dřív bez šatny, nově se šatnou); ostatní beze změny.
--
-- Jednorázově: živým rezervacím (reserved/active, ne test, výbava nevyzvednutá, protokol nepodepsaný, aktivní kód
-- k motorce, bez aktivního kódu šatny) s own_gear = true a nově vzniklým nárokem se kód šatny vydá stejnou cestou
-- jako při úpravě výbavy — trigger trg_sync_locker_code (no-op UPDATE own_gear): kód šatny + in-app zpráva + e-mail.
-- Idempotentní (druhý běh nic nenajde — kód šatny už je aktivní).

CREATE OR REPLACE FUNCTION public._booking_needs_locker(p_booking_id uuid)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record;
BEGIN
  SELECT own_gear, helmet_size, jacket_size, pants_size, boots_size, gloves_size,
         passenger_helmet_size, passenger_jacket_size, passenger_pants_size,
         passenger_boots_size, passenger_gloves_size
    INTO r FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN RETURN false; END IF;

  -- „základní výbava v ceně“ (own_gear = false) NEBO jakákoli vybraná velikost (řidič i spolujezdec —
  -- přesně to, co _kiosk_protocol ukáže v protokolu na displeji). NULL bez velikostí = vlastní výbava.
  RETURN r.own_gear IS FALSE
      OR nullif(btrim(r.helmet_size), '')           IS NOT NULL
      OR nullif(btrim(r.jacket_size), '')           IS NOT NULL
      OR nullif(btrim(r.pants_size),  '')           IS NOT NULL
      OR nullif(btrim(r.boots_size),  '')           IS NOT NULL
      OR nullif(btrim(r.gloves_size), '')           IS NOT NULL
      OR nullif(btrim(r.passenger_helmet_size), '') IS NOT NULL
      OR nullif(btrim(r.passenger_jacket_size), '') IS NOT NULL
      OR nullif(btrim(r.passenger_pants_size),  '') IS NOT NULL
      OR nullif(btrim(r.passenger_boots_size),  '') IS NOT NULL
      OR nullif(btrim(r.passenger_gloves_size), '') IS NOT NULL;
END;
$$;

ALTER FUNCTION public._booking_needs_locker(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public._booking_needs_locker(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._booking_needs_locker(uuid) TO service_role;

-- Jednorázové vydání kódu šatny rezervacím, které nárok získaly touto změnou (own_gear = true + vybraná výbava).
DO $$
DECLARE v_n int := 0; r record;
BEGIN
  FOR r IN
    SELECT b.id FROM public.bookings b
     WHERE b.own_gear IS TRUE AND b.status IN ('reserved', 'active') AND b.is_test IS NOT TRUE
       AND b.gear_collected_at IS NULL AND b.handover_protocol_filled_at IS NULL
       AND public._booking_needs_locker(b.id)
       AND EXISTS (SELECT 1 FROM public.branch_door_codes c
                    WHERE c.booking_id = b.id AND c.code_type = 'motorcycle' AND c.is_active)
       AND NOT EXISTS (SELECT 1 FROM public.branch_door_codes c
                        WHERE c.booking_id = b.id AND c.code_type = 'accessories' AND c.is_active)
  LOOP
    BEGIN
      UPDATE public.bookings SET own_gear = own_gear WHERE id = r.id;   -- → trg_sync_locker_code
      v_n := v_n + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'locker backfill failed for booking %: %', r.id, SQLERRM;
    END;
  END LOOP;
  RAISE NOTICE 'kód šatny dodatečně: % rezervací (own_gear = true + vybraná výbava)', v_n;
END $$;
