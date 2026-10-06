-- 2026-10-05 (zadání majitele): kód ŠATNY jen když si zákazník nějakou výbavu VYBRAL.
-- „Mám vlastní výbavu“ a nic dalšího = bez kódu šatny; „nemám vlastní“, ale nic nevybral = taky bez kódu šatny.
-- Idempotentní (CREATE OR REPLACE, DROP TRIGGER IF EXISTS). Úklid existujících rezervací = 20261005k.
--
-- A) _booking_needs_locker: šatna = (vybraná velikost helmy/bundy/kalhot/rukavic řidiče A NE „vlastní výbava“)
--    NEBO boty řidiče NEBO jakákoli výbava spolujezdce NEBO ZAPLACENÁ výbava v booking_extras (i bez velikosti —
--    web ji do 2026-10-05 dovolil zaplatit bez velikosti a kód šatny pak nepřišel ani podle starého pravidla).
--    Dřív own_gear=false (appka 4.0.8/4.1.0 bez povinného výběru, Velín „Ne — půjčuje si“) dávalo kód šatny
--    i bez jediné velikosti. own_gear=true dál ignoruje velikosti řidiče (starší appka je ukládala z profilu
--    i při vlastní výbavě — důvod stažení 20261005c). own_gear NULL (web, Velín, AI) = stejně jako dřív.
-- A2) trg_booking_extras_locker_resync: přidání / odebrání řádku placené výbavy přepočítá kód šatny.
-- C) BEFORE INSERT: „vlastní výbava“ + velikosti řidiče (starší appka předvyplněné z profilu) → velikosti řidiče
--    NULL, aby je protokol (kiosk, appka, Velín) nenabízel jako převzaté. Jen INSERT — Velín po převzetí
--    velikosti při „Ano — vlastní výbava“ záměrně nechává (záznam, co si zákazník vzal).

-- A0) placená výbava v booking_extras podle názvu řádku (appka česky, web v jazyce zákazníka)
CREATE OR REPLACE FUNCTION public._booking_extra_is_gear(p_name text)
RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path = public
AS $$
  SELECT coalesce(lower(p_name), '') ~ '(bot|boots|stiefel|laarzen|buty|spolujez|passenger|beifahrer|passager|pasajero|passagier|pasażer)'
      OR coalesce(p_name, '') ~ '(Взуття|взуття|пасажир|Пасажир)';
$$;
ALTER FUNCTION public._booking_extra_is_gear(text) OWNER TO postgres;
COMMENT ON FUNCTION public._booking_extra_is_gear(text) IS
  'Je řádek booking_extras placená výbava (boty řidiče/spolujezdce, výbava spolujezdce)? Názvy z appky (cs) i webu ve všech 8 jazycích.';

-- A) nárok na šatnu
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

  -- základní výbava řidiče: jen VYBRANÁ velikost a ne „vlastní výbava“ (false bez velikosti = nic nevybral)
  RETURN (r.own_gear IS NOT TRUE AND (
            nullif(btrim(r.helmet_size), '') IS NOT NULL
         OR nullif(btrim(r.jacket_size), '') IS NOT NULL
         OR nullif(btrim(r.pants_size),  '') IS NOT NULL
         OR nullif(btrim(r.gloves_size), '') IS NOT NULL))
      -- boty (placené extra) i výbava spolujezdce jsou v šatně vždy, když mají velikost
      OR nullif(btrim(r.boots_size), '')            IS NOT NULL
      OR nullif(btrim(r.passenger_helmet_size), '') IS NOT NULL
      OR nullif(btrim(r.passenger_jacket_size), '') IS NOT NULL
      OR nullif(btrim(r.passenger_pants_size),  '') IS NOT NULL
      OR nullif(btrim(r.passenger_boots_size),  '') IS NOT NULL
      OR nullif(btrim(r.passenger_gloves_size), '') IS NOT NULL
      -- ZAPLACENÉ boty / výbava spolujezdce bez velikosti (web do 2026-10-05 „vyzkoušíte na místě“, webhook
      -- doplatku bez velikostí) — zákazník ji zaplatil, vybere si ji v šatně (kiosk ji pak zapíše z protokolu)
      OR EXISTS (SELECT 1 FROM booking_extras x
                  WHERE x.booking_id = p_booking_id AND public._booking_extra_is_gear(x.name));
END;
$$;
ALTER FUNCTION public._booking_needs_locker(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public._booking_needs_locker(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._booking_needs_locker(uuid) TO service_role;
COMMENT ON FUNCTION public._booking_needs_locker(uuid) IS
  'Nárok na kód šatny (2026-10-05): vybraná velikost helmy/bundy/kalhot/rukavic řidiče (a own_gear není true) NEBO boty řidiče NEBO jakákoli velikost spolujezdce NEBO zaplacená výbava v booking_extras (_booking_extra_is_gear). Bez vybrané výbavy = bez šatny (i při own_gear=false).';
COMMENT ON COLUMN public.bookings.own_gear IS
  'Vlastní výbava řidiče: true = základní výbava řidiče (helma, bunda, kalhoty, rukavice) se nepůjčuje, jeho velikosti se ignorují; false/NULL = půjčuje se jen to, co má velikost. Kód šatny jen při vybrané výbavě (_booking_needs_locker, 2026-10-05).';

-- C) pojistka pro starší buildy appky: „vlastní výbava“ bez velikostí řidiče předvyplněných z profilu
CREATE OR REPLACE FUNCTION public._bookings_own_gear_normalize()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.own_gear IS TRUE THEN
    NEW.helmet_size := NULL; NEW.jacket_size := NULL; NEW.pants_size := NULL; NEW.gloves_size := NULL;
  END IF;
  RETURN NEW;
END $$;
ALTER FUNCTION public._bookings_own_gear_normalize() OWNER TO postgres;
REVOKE ALL ON FUNCTION public._bookings_own_gear_normalize() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_bookings_own_gear_normalize ON public.bookings;
CREATE TRIGGER trg_bookings_own_gear_normalize BEFORE INSERT ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public._bookings_own_gear_normalize();

-- A2) nárok závisí i na booking_extras → změna řádku placené výbavy (přidání / odebrání; update_booking_gear i appka
--     mažou a vkládají řádky AŽ PO úpravě rezervace) přepočítá kód šatny: „prázdný“ UPDATE own_gear spustí
--     trg_sync_locker_code (vydá / zadrží kód šatny + zprávu jako při změně velikosti). Jen živá rezervace před
--     výdejem výbavy; chyba nikdy neshodí změnu doplňků.
CREATE OR REPLACE FUNCTION public._booking_extras_locker_resync()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_bid uuid := CASE WHEN TG_OP = 'DELETE' THEN OLD.booking_id ELSE NEW.booking_id END;
BEGIN
  IF (TG_OP <> 'INSERT' AND public._booking_extra_is_gear(OLD.name))
     OR (TG_OP <> 'DELETE' AND public._booking_extra_is_gear(NEW.name)) THEN
    BEGIN
      UPDATE bookings SET own_gear = own_gear
       WHERE id = v_bid AND status IN ('reserved','active') AND is_test IS NOT TRUE
         AND gear_collected_at IS NULL AND handover_protocol_filled_at IS NULL;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '_booking_extras_locker_resync failed for booking %: %', v_bid, SQLERRM;
    END;
  END IF;
  RETURN NULL;
END $$;
ALTER FUNCTION public._booking_extras_locker_resync() OWNER TO postgres;
REVOKE ALL ON FUNCTION public._booking_extras_locker_resync() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_booking_extras_locker_resync ON public.booking_extras;
CREATE TRIGGER trg_booking_extras_locker_resync AFTER INSERT OR DELETE OR UPDATE OF name ON public.booking_extras
  FOR EACH ROW EXECUTE FUNCTION public._booking_extras_locker_resync();
