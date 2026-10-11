-- =============================================================================
-- 2026-10-11 BEZPEČNOST (dokončení 20261011d): booking_discounts bez RLS
-- Tabulka slev rezervací neměla RLS a anon i authenticated měli INSERT/UPDATE
-- → kdokoli mohl k cizí rezervaci připsat / změnit slevu (doklady, vratky,
-- uplatnění poukazu). Klienti: appka zapisuje slevy SVÉ nezaplacené rezervace
-- (payment_screen.dart, před platbou), Velín čte (admin); vše ostatní řeší
-- SECURITY DEFINER RPC / edge (service role), kterých se RLS netýká.
-- Idempotentní.
-- =============================================================================

ALTER TABLE public.booking_discounts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.booking_discounts FROM anon;

DROP POLICY IF EXISTS booking_discounts_admin_all ON public.booking_discounts;
CREATE POLICY booking_discounts_admin_all ON public.booking_discounts
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS booking_discounts_owner_select ON public.booking_discounts;
CREATE POLICY booking_discounts_owner_select ON public.booking_discounts
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.bookings b
                  WHERE b.id = booking_discounts.booking_id AND b.user_id = auth.uid()));

-- Zákazník jen ke SVÉ ještě NEZAPLACENÉ rezervaci (appka zapisuje slevy těsně
-- před platbou); po zaplacení slevy mění jen server / Velín.
DROP POLICY IF EXISTS booking_discounts_owner_insert ON public.booking_discounts;
CREATE POLICY booking_discounts_owner_insert ON public.booking_discounts
  FOR INSERT TO authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM public.bookings b
                       WHERE b.id = booking_discounts.booking_id AND b.user_id = auth.uid()
                         AND b.payment_status = 'unpaid'));
