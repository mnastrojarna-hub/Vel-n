-- ============================================================================
-- 20261011_profiles_customer_column_guard.sql
-- ZÁKAZNÍK NESMÍ PŘEPSAT ADMIN / SERVEROVÉ SLOUPCE SVÉHO PROFILU (2026-10-11)
--
-- RLS `profiles_user_update` (USING id = auth.uid(), bez WITH CHECK) + GRANT
-- UPDATE pro authenticated dovolují přihlášenému zákazníkovi přímým REST zápisem
-- (PATCH /rest/v1/profiles?id=eq.<své id>) změnit LIBOVOLNÝ sloupec svého
-- řádku: věrnostní body (až 20 % sleva, kterou validate_app_loyalty_discount
-- uzná), stripe_customer_id (cizí uložené karty), odblokování, příznak
-- testovacího účtu, reliability_score, docs_verified_* (auto-aktivace ve Velínu)…
--
-- Zákazník DÁL edituje svá data (jméno, kontakt, adresa, OP / pas / ŘP včetně
-- čísel a platnosti, datum narození, skupina ŘP, velikosti výbavy, souhlasy,
-- jazyk, oprávnění appky, firma, přezdívka žebříčku) I OCR razítka
-- *_verified_at / *_verified_until (appka i web je zapisují přímo po skenu a
-- při resetu dokladu je nulují). Změněné NE-NULL *_verified_at = čas DB
-- (žádné antedatování; appka posílala lokální čas bez zóny).
--
-- Ověřené zapisovatele (appka OBA stromy identické, web JS, Velín, edge, DB):
-- žádný zákaznický klient nezapisuje zamčený sloupec. SECURITY DEFINER RPC /
-- triggery (current_user = vlastník postgres: app_save_full_profile,
-- set_my_license_group, set_loyalty_*, loyalty_advance_celebrated,
-- set_web_booking_*, create_web_booking, admin_*, handle_new_user …), edge
-- funkce (service_role) a Velín (is_admin()) projdou beze změny — kontroluje se
-- current_user PŘÍMÉHO zápisu, ne auth.uid(). Funkce je proto SECURITY INVOKER.
-- Sloupcový REVOKE nejde: Velín admini běží také jako role authenticated.
-- Idempotentní (CREATE OR REPLACE + DROP TRIGGER IF EXISTS).
-- ============================================================================

CREATE OR REPLACE FUNCTION public._guard_customer_profile_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
  -- Jen přímý zápis zákazníka (PostgREST role anon/authenticated) mimo Velín
  IF current_user NOT IN ('anon', 'authenticated') THEN
    RETURN NEW;
  END IF;
  IF public.is_admin() THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    -- Dnes RLS zákazníkovi INSERT nedovolí (jen profiles_admin_all); pojistka pro případnou budoucí politiku
    NEW.email                    := COALESCE(lower(auth.email()), NEW.email);
    NEW.created_at               := now();
    NEW.registration_source      := NULL;
    NEW.stripe_customer_id       := NULL;
    NEW.password_last4_bcrypt    := NULL;
    NEW.is_blocked               := false;
    NEW.blocked_at               := NULL;
    NEW.blocked_reason           := NULL;
    NEW.is_test_account          := false;
    NEW.reliability_score        := '{"notes": "", "accidents": 0, "late_returns": 0}'::jsonb;
    NEW.docs_verified_at         := NULL;
    NEW.docs_verification_status := NULL;
    NEW.marketing_consent_at     := NULL;
    NEW.loyalty_bonus_points     := 0;
    NEW.loyalty_points_floor     := 0;
    NEW.loyalty_points_penalty   := 0;
    NEW.loyalty_celebrated_level := 0;
    IF NEW.id_verified_at IS NOT NULL THEN NEW.id_verified_at := now(); END IF;
    IF NEW.passport_verified_at IS NOT NULL THEN NEW.passport_verified_at := now(); END IF;
    IF NEW.license_verified_at IS NOT NULL THEN NEW.license_verified_at := now(); END IF;
    RETURN NEW;
  END IF;

  -- UPDATE: admin / serverové sloupce si drží původní hodnotu (tiše, bez chyby)
  NEW.email                    := OLD.email;                     -- zrcadlo auth.users.email
  NEW.created_at               := OLD.created_at;
  NEW.registration_source      := OLD.registration_source;
  NEW.stripe_customer_id       := OLD.stripe_customer_id;        -- jen edge (service_role)
  NEW.password_last4_bcrypt    := OLD.password_last4_bcrypt;     -- jen set_web_booking_password
  NEW.is_blocked               := OLD.is_blocked;
  NEW.blocked_at               := OLD.blocked_at;
  NEW.blocked_reason           := OLD.blocked_reason;
  NEW.is_test_account          := OLD.is_test_account;
  NEW.reliability_score        := OLD.reliability_score;
  NEW.docs_verified_at         := OLD.docs_verified_at;
  NEW.docs_verification_status := OLD.docs_verification_status;
  NEW.marketing_consent_at     := OLD.marketing_consent_at;
  NEW.loyalty_bonus_points     := OLD.loyalty_bonus_points;
  NEW.loyalty_points_floor     := OLD.loyalty_points_floor;
  NEW.loyalty_points_penalty   := OLD.loyalty_points_penalty;
  NEW.loyalty_celebrated_level := OLD.loyalty_celebrated_level;  -- jen RPC loyalty_advance_celebrated

  -- OCR razítka: zákazník smí nastavit (sken) i vynulovat (reset dokladu),
  -- ale ne zvolit čas
  IF NEW.id_verified_at IS DISTINCT FROM OLD.id_verified_at AND NEW.id_verified_at IS NOT NULL THEN
    NEW.id_verified_at := now();
  END IF;
  IF NEW.passport_verified_at IS DISTINCT FROM OLD.passport_verified_at AND NEW.passport_verified_at IS NOT NULL THEN
    NEW.passport_verified_at := now();
  END IF;
  IF NEW.license_verified_at IS DISTINCT FROM OLD.license_verified_at AND NEW.license_verified_at IS NOT NULL THEN
    NEW.license_verified_at := now();
  END IF;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public._guard_customer_profile_columns() IS
  'BEFORE INSERT/UPDATE profiles: přímý zápis zákazníka (current_user anon/authenticated, ne is_admin) nemění admin/serverové sloupce; změněné *_verified_at = now(). DEFINER RPC, service_role a Velín beze změny. 20261011.';

-- Triggerová funkce: EXECUTE se kontroluje jen při CREATE TRIGGER, ne při spuštění
REVOKE ALL ON FUNCTION public._guard_customer_profile_columns() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._guard_customer_profile_columns() TO service_role;

-- Název začíná '_' → běží PŘED profiles_updated_at, trg_normalize_registration_source
-- i trg_profiles_ignore_masked_docs (abecedně: '_' 0x5F < 'p' < 't'); AFTER trigger
-- trg_release_codes_on_profile_verify vidí už opravený řádek.
-- Záměrně bez UPDATE OF (seznam chráněných sloupců je jen ve funkci).
DROP TRIGGER IF EXISTS _trg_guard_customer_profile_columns ON public.profiles;
CREATE TRIGGER _trg_guard_customer_profile_columns
  BEFORE INSERT OR UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public._guard_customer_profile_columns();
