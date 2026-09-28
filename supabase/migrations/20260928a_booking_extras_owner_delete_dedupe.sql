-- =====================================================================
-- 20260928a_booking_extras_owner_delete_dedupe.sql
-- FIX: „ve Velíně dvoje boty / dvoje oblečení“ u rezervací upravených v appce.
--
-- PŘÍČINA (ověřeno proti živému snapshotu schématu 2026-09-27): `booking_extras`
-- má pro zákazníka jen politiky SELECT („Users can view own booking extras“)
-- a INSERT („Users can create own booking extras“) — ŽÁDNOU DELETE. Appka při
-- úpravě výbavy dělá delete + insert celé sady modelovaných doplňků
-- (výbava spolujezdce, boty řidiče/spolujezdce): PostgREST DELETE bez politiky
-- tiše smaže 0 řádků (bez chyby) a následný INSERT (politika owner) projde →
-- každá úprava, která mění sadu placených doplňků, zdvojí už existující řádky.
-- Web ani Velín postiženy nejsou (RPC `update_booking_gear` je SECURITY DEFINER,
-- Velín má admin FOR ALL).
--
-- ŘEŠENÍ:
--  1) DELETE politika pro vlastníka rezervace (zrcadlí owner predikát SELECT/INSERT;
--     omezeno na živé stavy pending/reserved/active — hotové/zrušené rezervace
--     zákazník nemění, stejně jako RPC `update_booking_gear`). Platí i pro už
--     vydané verze appky (jejich delete začne fungovat).
--  2) Jednorázový úklid existujících duplicit: stejná rezervace + stejný název
--     (bez ohledu na velikost písmen) + stejná cena + stejné množství → zůstává
--     nejstarší řádek. `bookings.extras_price` se NEMĚNÍ (appka ho počítá
--     rozdílově, sedí i u postižených rezervací — špatné byly jen řádky).
--     Před úklidem se počet dotčených rezervací vypíše do logu (NOTICE).
--
-- Idempotentní: DROP POLICY IF EXISTS + CREATE; opakovaný úklid smaže 0 řádků.
-- Unikátní index (booking_id, lower(name)) se ZÁMĚRNĚ nezakládá — vozík
-- (quantity = dny) je jeden řádek, ale rozhodnutí o tvrdém guardu je na majiteli.
-- Bez BEGIN/COMMIT — deploy-sql.yml aplikuje soubor přes `psql --single-transaction`.
-- =====================================================================

-- 1) DELETE politika pro vlastníka rezervace
DROP POLICY IF EXISTS "Users can delete own booking extras" ON public.booking_extras;
CREATE POLICY "Users can delete own booking extras" ON public.booking_extras
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.bookings b
      WHERE b.id = booking_extras.booking_id
        AND b.user_id = auth.uid()
        AND b.status IN ('pending', 'reserved', 'active')
    )
  );

-- 2) Úklid duplicit (nejstarší řádek zůstává)
DO $$
DECLARE
  v_bookings integer;
  v_rows integer;
BEGIN
  SELECT count(DISTINCT booking_id), coalesce(sum(cnt - 1), 0)
    INTO v_bookings, v_rows
  FROM (
    SELECT booking_id, count(*) AS cnt
    FROM public.booking_extras
    GROUP BY booking_id, lower(btrim(name)), unit_price, coalesce(quantity, 1)
    HAVING count(*) > 1
  ) d;
  RAISE NOTICE 'booking_extras dedupe: % duplicitních řádků u % rezervací', v_rows, v_bookings;

  DELETE FROM public.booking_extras a
  USING public.booking_extras b
  WHERE a.booking_id = b.booking_id
    AND lower(btrim(a.name)) = lower(btrim(b.name))
    AND a.unit_price = b.unit_price
    AND coalesce(a.quantity, 1) = coalesce(b.quantity, 1)
    AND (coalesce(a.created_at, 'epoch'::timestamptz), a.id) > (coalesce(b.created_at, 'epoch'::timestamptz), b.id);

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RAISE NOTICE 'booking_extras dedupe: smazáno % řádků', v_rows;
END $$;
