-- FIX: profiles.registration_source se PO migraci 20260701 znovu plní placeholderem 'auth_trigger'
--
-- Kontext: migrace 20260701_fix_registration_source_default.sql shodila DEFAULT a udělala backfill
-- (po ní živě 31× web / 2× app / 1× NULL). Jenže 28. 7. je v živé DB znovu 65× 'auth_trigger' —
-- placeholder tedy zapisuje SAMOTNÝ živý trigger handle_new_user() (vytvořen v dashboardu, mimo
-- migrace; jeho tělo hodnotu vkládá explicitně, ne přes DEFAULT). Non-null placeholder pak blokuje
-- COALESCE(registration_source, 'app'/'web') v RPC app_save_full_profile / create_web_booking,
-- takže zdroj registrace se u nových zákazníků už nikdy nedoplní. Důsledek: segmentace app/web
-- ve Velíně i v AI Copilotu je nepoužitelná (67 % profilů „auth_trigger").
--
-- Řešení nezávislé na těle handle_new_user (nelze slepě přepsat — žije mimo migrace):
--   1) normalizační BEFORE trigger na profiles zahodí 'auth_trigger' při KAŽDÉM insertu/updatu
--   2) DEFAULT pryč (idempotentní pojistka, kdyby ho něco vrátilo)
--   3) backfill existujících placeholderů: aktivní instalace appky → 'app';
--      jinak zdroj nejstarší rezervace; jinak NULL (doplní RPC při první akci)
-- Idempotentní — opakované spuštění nic nerozbije.

-- 1) Normalizace placeholderu při zápisu
CREATE OR REPLACE FUNCTION public.normalize_registration_source()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.registration_source = 'auth_trigger' THEN
    NEW.registration_source := NULL;
  END IF;
  RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS trg_normalize_registration_source ON public.profiles;
CREATE TRIGGER trg_normalize_registration_source
  BEFORE INSERT OR UPDATE OF registration_source ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.normalize_registration_source();

-- 2) Default pryč (pojistka)
ALTER TABLE public.profiles ALTER COLUMN registration_source DROP DEFAULT;

-- 3a) Backfill: aktivní instalace appky = jasný důkaz 'app'
UPDATE public.profiles p
SET registration_source = 'app'
WHERE p.registration_source = 'auth_trigger'
  AND EXISTS (SELECT 1 FROM public.app_installations ai WHERE ai.user_id = p.id);

-- 3b) Backfill: jinak zdroj nejstarší rezervace zákazníka
UPDATE public.profiles p
SET registration_source = sub.src
FROM (
  SELECT DISTINCT ON (b.user_id) b.user_id, b.booking_source AS src
  FROM public.bookings b
  WHERE b.booking_source IN ('app', 'web')
  ORDER BY b.user_id, b.created_at ASC
) sub
WHERE p.id = sub.user_id
  AND p.registration_source = 'auth_trigger';

-- 3c) Zbytek (bez instalace i bez rezervace) → NULL
UPDATE public.profiles
SET registration_source = NULL
WHERE registration_source = 'auth_trigger';
