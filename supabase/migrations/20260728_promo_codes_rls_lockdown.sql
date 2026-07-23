-- =====================================================
-- MotoGo24 — SECURITY FIX: promo_codes už NENÍ čitelné anon/authenticated klíčem
-- =====================================================
-- Report (security researcher, 2026-07): veřejný anon klíč dokázal přes
-- REST `GET /rest/v1/promo_codes?select=...` vylistovat CELÝ ciník slevových
-- kódů (TEST98 = 98 %, TEST6000 = 6000 Kč, ~35× jednorázové VRACENI- kredity).
-- Příčina: RLS byla sice ZAPNUTÁ, ale policy `promo_codes_public_read`
--   FOR SELECT USING (active = true)
-- povolovala komukoli (anon i authenticated) přečíst všechny AKTIVNÍ řádky.
--
-- Oprava: policy public_read se ruší. Frontend/web/appka kódy z tabulky
-- NEČTOU napřímo — validace jde přes SECURITY DEFINER RPC `validate_promo_code`
-- (a `use_promo_code`), které RLS obcházejí. Jediné přímé čtení bylo v appce
-- (`_loadDiscountType` při úpravě rezervace) — přesměrováno na nové
-- SECURITY DEFINER RPC `get_promo_code_type` (viz níže + změna v appce).
--
-- Po opravě zůstává na promo_codes jen admin policy (FOR ALL USING is_admin())
-- → Velín (authenticated admin) čte/píše dál; anon/běžný authenticated dostane
-- prázdný výsledek (RLS default-deny bez odpovídající SELECT policy).
--
-- Idempotentní — bezpečné spustit opakovaně.
-- =====================================================

-- Jistota, že RLS je zapnutá (byla, ale ať je to explicitní a idempotentní).
ALTER TABLE public.promo_codes ENABLE ROW LEVEL SECURITY;

-- ── 1. Zruš veřejné čtení kódů ──────────────────────────────────────────
DROP POLICY IF EXISTS promo_codes_public_read ON public.promo_codes;

-- Admin policy (FOR ALL USING is_admin()) ponecháváme beze změny — Velín ji
-- potřebuje pro správu kódů. Znovu ji NEvytváříme, aby migrace nezávisela na
-- jejím přesném znění; jen se ubezpečíme, že existuje (jinak by admin ztratil
-- přístup). Idempotentní re-create pod stejným názvem:
DROP POLICY IF EXISTS promo_codes_admin ON public.promo_codes;
CREATE POLICY promo_codes_admin ON public.promo_codes
  FOR ALL USING (is_admin());

-- ── 2. Náhrada přímého čtení typu kódu v appce ─────────────────────────
-- Appka při úpravě rezervace potřebuje znát typ (percent/fixed) použitého
-- kódu i tehdy, když už je kód neaktivní/vyčerpaný (validate_promo_code by
-- pro neaktivní vrátil valid=false bez typu). Vrací JEN 'type' — žádnou
-- hodnotu ani ciník; vyžaduje znát přesný `code`, takže neumožňuje enumeraci.
CREATE OR REPLACE FUNCTION public.get_promo_code_type(p_code text)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT type FROM public.promo_codes WHERE code = upper(p_code) LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_promo_code_type(text) TO anon, authenticated;
