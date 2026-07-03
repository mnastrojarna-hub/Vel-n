-- Fix: profiles.registration_source uvíznuté na 'auth_trigger'
--
-- Root cause: sloupec profiles.registration_source měl v DB DEFAULT 'auth_trigger'
-- (dokumentace v STATE_2 chybně uváděla DEFAULT NULL). Trigger handle_new_user()
-- registration_source vůbec nenastavuje, takže každý nový profil dostal placeholder
-- 'auth_trigger'. Ten je non-null, proto ho pozdější COALESCE(registration_source,'app'/'web')
-- v RPC app_save_full_profile / create_web_booking NIKDY nepřepsal → i aktivní
-- app/web zákazníci zůstali navždy 'auth_trigger' (Velín je zobrazoval jako matoucí
-- "AUTH_TRIGGER" v dlaždici Platforma; "Registrace přes" ukazovalo "—").
--
-- Ověřeno na živé DB: před = 33× auth_trigger + 1× app; po = 31× web, 2× app, 1× NULL.

-- 1) Zdroj: default zpět na NULL. Nové profily necha RPC správně doplnit na 'app'/'web'.
ALTER TABLE public.profiles
  ALTER COLUMN registration_source DROP DEFAULT;

-- 2) Backfill existujících placeholderů: odvoď zdroj z nejstarší rezervace zákazníka.
UPDATE public.profiles p
SET registration_source = sub.src
FROM (
  SELECT DISTINCT ON (b.user_id) b.user_id, b.booking_source AS src
  FROM public.bookings b
  WHERE b.booking_source IN ('app','web')
  ORDER BY b.user_id, b.created_at ASC
) sub
WHERE p.id = sub.user_id
  AND p.registration_source = 'auth_trigger';

-- 3) Zbytek bez rezervace: NULL (doplní se při první akci přes RPC).
UPDATE public.profiles
SET registration_source = NULL
WHERE registration_source = 'auth_trigger';
