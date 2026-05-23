-- =============================================================================
-- MIGRACE: RPC delete_customer_account — atomické smazání profilu + auth.users
-- Datum: 2026-05-23
-- Branch: claude/amazing-babbage-vnnpM
--
-- Reportováno (uživatel): zákazník info@nastrojarstvi.com byl ve Velíně smazán,
-- přesto web rezervace na tento e-mail hlásí „tento mail už u nás máme" a
-- confirmation flow ho bere jako známého zákazníka.
--
-- Root cause:
--   Velín (CustomerDetail.jsx:95) i Flutter app (profile_screen.dart:235) volají
--   RPC `delete_customer_account(p_user_id)`, jenže ta NIKDY nevznikla žádnou
--   migrací → volání selhalo s „function does not exist" (42883). Velín UI má
--   fallback, který smaže POUZE řádek v `public.profiles`
--   (CustomerDetail.jsx:100). Protože FK je jednosměrný
--   (`profiles.id REFERENCES auth.users(id) ON DELETE CASCADE`), smazání profilu
--   NEsmaže odpovídající řádek v `auth.users`. Zůstane osiřelý auth záznam.
--
--   Kontrola e-mailu při web rezervaci se přitom ptá výhradně na `auth.users`:
--     - check_web_booking_email()  → SELECT FROM auth.users WHERE lower(email)=…
--     - create_web_booking() dedup → totéž
--   → osiřelý auth záznam = e-mail navždy „známý".
--
-- Fix:
--   Vytvořit chybějící RPC. Maže `auth.users` (kaskádou padne i profiles a dle
--   FK politiky SET NULL / CASCADE u navázaných tabulek). Tím Velín i app
--   přestanou padat do profile-only fallbacku a osiřelé auth záznamy už
--   nevzniknou.
--
--   Oprávnění: admin (Velín) NEBO sám vlastník účtu (Flutter self-delete přes
--   auth.uid()). Blokace, pokud má zákazník aktivní/čekající/rezervované
--   rezervace (stejná pojistka jako v UI).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.delete_customer_account(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $func$
DECLARE
  v_active int;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'missing_user_id');
  END IF;

  -- Oprávnění: admin NEBO sám vlastník účtu
  IF NOT (public.is_admin() OR auth.uid() = p_user_id) THEN
    RETURN jsonb_build_object('error', 'not_authorized');
  END IF;

  -- Blokace při aktivních/čekajících/rezervovaných rezervacích
  SELECT count(*) INTO v_active
    FROM bookings
    WHERE user_id = p_user_id
      AND status IN ('pending','reserved','active');
  IF v_active > 0 THEN
    RETURN jsonb_build_object('error','active_bookings','count',v_active);
  END IF;

  -- Smazání auth.users → kaskádou smaže profiles
  -- (profiles.id REFERENCES auth.users ON DELETE CASCADE) a dle FK politiky
  -- SET NULL / CASCADE u navázaných tabulek (invoices, shop_orders, vouchers…).
  DELETE FROM auth.users WHERE id = p_user_id;

  RETURN jsonb_build_object('success', true, 'user_id', p_user_id);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$func$;

REVOKE ALL ON FUNCTION public.delete_customer_account(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_customer_account(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
