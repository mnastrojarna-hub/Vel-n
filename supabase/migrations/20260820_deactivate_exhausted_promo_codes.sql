-- =====================================================
-- MotoGo24 — promo kód vyčerpaný na limit použití se deaktivuje přímo v DB
-- =====================================================
-- Požadavek (Velín, 2026-08-20): kód uplatněný tolikrát, kolik dovoluje
-- max_uses, má přejít na neaktivní. Velín má frontendovou pojistku
-- (autoDeactivateExhausted při otevření stránky Promo kódy), tento trigger
-- to řeší v okamžiku vyčerpání — used_count zvyšuje increment_promo_used_count
-- (trg_promo_usage_increment na promo_code_usage), tím se sepne i tento trigger.
--
-- Jen nastavuje NEW.active, nikdy nevyhazuje výjimku — update nemůže shodit.
-- max_uses IS NULL = neomezený kód, ten se nedeaktivuje nikdy.
-- Idempotentní — bezpečné spustit opakovaně.
-- =====================================================

CREATE OR REPLACE FUNCTION public.deactivate_exhausted_promo_code()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.max_uses IS NOT NULL AND NEW.used_count >= NEW.max_uses THEN
    NEW.active := false;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_deactivate_exhausted_promo ON public.promo_codes;
CREATE TRIGGER trg_deactivate_exhausted_promo
  BEFORE INSERT OR UPDATE OF used_count ON public.promo_codes
  FOR EACH ROW EXECUTE FUNCTION public.deactivate_exhausted_promo_code();

-- Jednorázový backfill: už vyčerpané kódy, které jsou dosud aktivní
UPDATE public.promo_codes
SET active = false
WHERE active = true AND max_uses IS NOT NULL AND used_count >= max_uses;
