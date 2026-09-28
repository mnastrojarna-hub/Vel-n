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
--  2) Jednorázový úklid existujících duplicit:
--     a) modelovaná výbava (boty řidiče / boty spolujezdce / výbava spolujezdce):
--        rezervace má z každé třídy nejvýš JEDEN řádek — třída se pozná jazykově
--        nezávisle z názvu (appka „Boty řidiče“, web RPC „Boty řidič“, web
--        formulář „Rider boots“ / „Stiefel Fahrer“ …), bez ohledu na cenu
--        (rank 3+ vkládá 0 Kč vedle zaplacených 290 Kč) → zůstává nejstarší
--        (= původně zaplacený) řádek;
--     b) ostatní řádky (vozík, přistavení…): stejný název (bez ohledu na
--        velikost písmen) + stejná cena + stejné množství → zůstává nejstarší.
--     `bookings.extras_price` se NEMĚNÍ (appka ho počítá rozdílově, sedí
--     i u postižených rezervací — špatné byly jen řádky).
--     Před úklidem se počet dotčených řádků vypíše do logu (NOTICE).
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
  v_rows integer;
BEGIN
  -- a) modelovaná výbava: jedna třída = jeden řádek na rezervaci (jazykově nezávisle,
  --    stejná klasifikace jako appka `extraIdFromExtrasName`)
  WITH classed AS (
    SELECT id, booking_id, created_at,
      CASE
        WHEN lower(name) ~ '(bot|boots|stiefel|laarzen|buty|взуття)'
         AND lower(name) ~ '(spoluj|passenger|passag|beifahrer|pasajero|pasa[żz]er|пасажир)' THEN 'boty_spolujezdec'
        WHEN lower(name) ~ '(bot|boots|stiefel|laarzen|buty|взуття)' THEN 'boty_ridic'
        WHEN lower(name) ~ '(spoluj|passenger|passag|beifahrer|pasajero|pasa[żz]er|пасажир)' THEN 'spolujezdec'
      END AS cls
    FROM public.booking_extras
    WHERE booking_id IS NOT NULL
  ), ranked AS (
    SELECT id, row_number() OVER (
      PARTITION BY booking_id, cls
      ORDER BY coalesce(created_at, 'epoch'::timestamptz), id) AS rn
    FROM classed WHERE cls IS NOT NULL
  )
  DELETE FROM public.booking_extras e USING ranked r WHERE e.id = r.id AND r.rn > 1;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RAISE NOTICE 'booking_extras dedupe (výbava): smazáno % řádků', v_rows;

  -- b) ostatní řádky: přesné duplicity (název bez ohledu na velikost písmen + cena + množství)
  DELETE FROM public.booking_extras a
  USING public.booking_extras b
  WHERE a.booking_id = b.booking_id
    AND lower(btrim(a.name)) = lower(btrim(b.name))
    AND a.unit_price = b.unit_price
    AND coalesce(a.quantity, 1) = coalesce(b.quantity, 1)
    AND (coalesce(a.created_at, 'epoch'::timestamptz), a.id) > (coalesce(b.created_at, 'epoch'::timestamptz), b.id);
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RAISE NOTICE 'booking_extras dedupe (ostatní): smazáno % řádků', v_rows;
END $$;
