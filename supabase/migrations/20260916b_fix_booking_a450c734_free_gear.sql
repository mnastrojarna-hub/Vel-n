-- ════════════════════════════════════════════════════════════════════
-- Oprava DAT jedné historické rezervace — #A450C734 (Hambálek)
--
-- Zákazník s rankem 4 (app rezervace) zaplatil 980 Kč za výbavu + boty
-- spolujezdce, na které měl mít dle věrnostního programu nárok zdarma —
-- ostrý rezervační formulář pravidlo od ranku 3 vůbec nečetl (opraveno
-- v appce 4.0.0). Tahle migrace srovná jen ten JEDEN záznam:
-- gear řádky na `unit_price = 0` a o stejnou částku dolů `extras_price`
-- i `total_price`.
--
-- ROZSAH: jde o HISTORICKOU rezervaci → NEPOSÍLÁ se Stripe vratka ani
-- se nevystavuje dobropis (zadání uživatele). Pouze data.
-- `loyalty_discount_amount` se ZÁMĚRNĚ nepřepočítává — sleva byla
-- spočtená ze základu vč. výbavy a zákazníkovi zůstává.
--
-- BEZPEČNOST: filtr řádků je shodný s `update_booking_gear`, takže
-- nemodelované doplňky (vozík…) zůstanou nedotčené. Idempotentní —
-- po prvním běhu jsou řádky na 0, takže se odečítá 0. Když rezervace
-- v DB není, jen to zaloguje a NESPADNE (vadná migrace by zablokovala
-- všechny další).
-- ════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_id      uuid;
  v_castka  numeric;
  v_total   numeric;
  v_extras  numeric;
BEGIN
  SELECT id INTO v_id FROM bookings WHERE right(id::text, 8) = 'a450c734';

  IF v_id IS NULL THEN
    RAISE NOTICE '[A450C734] Rezervace v teto DB neni - preskakuji.';
    RETURN;
  END IF;

  SELECT COALESCE(SUM(COALESCE(unit_price, 0) * COALESCE(quantity, 1)), 0)
    INTO v_castka
    FROM booking_extras
   WHERE booking_id = v_id
     AND ( lower(name) LIKE '%bot%'      OR lower(name) LIKE '%boots%'
        OR lower(name) LIKE '%spolujez%' OR lower(name) LIKE '%passenger%' );

  IF v_castka <= 0 THEN
    RAISE NOTICE '[A450C734] Gear radky uz jsou na 0 Kc - nic se nemeni.';
    RETURN;
  END IF;

  UPDATE booking_extras SET unit_price = 0
   WHERE booking_id = v_id
     AND ( lower(name) LIKE '%bot%'      OR lower(name) LIKE '%boots%'
        OR lower(name) LIKE '%spolujez%' OR lower(name) LIKE '%passenger%' );

  UPDATE bookings
     SET extras_price = GREATEST(0, COALESCE(extras_price, 0) - v_castka),
         total_price  = GREATEST(0, COALESCE(total_price,  0) - v_castka)
   WHERE id = v_id
  RETURNING total_price, extras_price INTO v_total, v_extras;

  RAISE NOTICE '[A450C734] Odecteno % Kc -> total_price=%, extras_price=%.',
    v_castka, v_total, v_extras;
END $$;
