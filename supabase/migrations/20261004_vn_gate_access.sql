-- =============================================================================
-- Velké Němčice: kód schránky s klíčem od brány (TŘETÍ přístupový kód)
-- Migrace: 20261004_vn_gate_access.sql (1/5 — tabulka, data, helpery, RPC)
--
-- Zadání majitele 2026-10-04: na pravém sloupku vrat samoobslužné pobočky
-- Velké Němčice jsou dvě ocelové schránky na klíče; HORNÍ (kód 661, neměnný)
-- obsahuje klíč od visacího zámku brány. Zákazník dostává kódy v pořadí
-- 1) brána, 2) šatna (má-li výbavu), 3) motorka — v appce, zprávách, SMS/WA
-- i e-mailech; jen u pobočky, která má bránu (nic jiného se nemění).
--
-- PROČ NE `branches` ani `branch_door_codes`:
--   * `branches` je veřejně čitelná (RLS USING true + anon) — kód by si přečetl
--     kdokoli přes REST.
--   * řádek v `branch_door_codes` by kiosk synchronizoval jako zákaznický PIN
--     (kiosk_resolve_code/kiosk_sync_* nefiltrují code_type) a 661 by otevřel
--     kóji náhodné rezervace; navíc CHECK motorcycle/accessories.
-- → nová tabulka jen pro adminy + SECURITY DEFINER helpery pro DB funkce
--   a jedno RPC pro zákazníka (vlastní rezervace, až po vydání kódů).
--
-- Idempotentní (IF NOT EXISTS / OR REPLACE / ON CONFLICT DO NOTHING).
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.branch_gate_access (
  branch_id    uuid PRIMARY KEY REFERENCES public.branches(id) ON DELETE CASCADE,
  lockbox_code text NOT NULL CHECK (lockbox_code ~ '^[0-9]{3,8}$'),
  is_active    boolean NOT NULL DEFAULT true,
  note         text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.branch_gate_access IS
  'Kód schránky s klíčem od brány pobočky (Velké Němčice: horní schránka na pravém sloupku vrat, 661). Jen admin (RLS); zákazník ho dostává ve zprávách s kódy a přes get_booking_gate_info. NE do branches (veřejná) ani branch_door_codes (kiosk).';

ALTER TABLE public.branch_gate_access ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS branch_gate_access_admin ON public.branch_gate_access;
CREATE POLICY branch_gate_access_admin ON public.branch_gate_access
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
REVOKE ALL ON public.branch_gate_access FROM anon;

DROP TRIGGER IF EXISTS trg_branch_gate_access_touch ON public.branch_gate_access;
CREATE TRIGGER trg_branch_gate_access_touch BEFORE UPDATE ON public.branch_gate_access
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- Data: Velké Němčice (id ověřeno živě 2026-10-04; záloha dle adresy z 20260923b)
DO $$
DECLARE n integer;
BEGIN
  INSERT INTO public.branch_gate_access (branch_id, lockbox_code, note)
  SELECT b.id, '661', 'Horní schránka na pravém sloupku vrat — klíč od visacího zámku brány'
    FROM public.branches b
   WHERE b.id = '22222222-2222-2222-2222-222222222222'
      OR (b.type = 'samoobslužná' AND b.address = 'Boudky' AND b.city ~* 'n[eě]m[cč]ic')
  ON CONFLICT (branch_id) DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT;
  RAISE NOTICE 'branch_gate_access: vloženo % řádků', n;
  IF NOT EXISTS (SELECT 1 FROM public.branch_gate_access) THEN
    RAISE WARNING 'branch_gate_access: pobočka Velké Němčice nenalezena — kód brány doplňte ve Velínu';
  END IF;
END $$;

-- Kód brány pobočky (NULL = pobočka bránu se schránkou nemá) — jen pro DB funkce.
CREATE OR REPLACE FUNCTION public._branch_gate_code(p_branch_id uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT g.lockbox_code FROM branch_gate_access g
   WHERE g.branch_id = p_branch_id AND g.is_active LIMIT 1;
$$;

-- Číslo dveří šatny = číslo zóny šatny z HW mapy (branch_doors.hw.zone; na
-- dveřích jsou jen čísla — Velké Němčice: 8). NULL = neznámé → text bez čísla.
CREATE OR REPLACE FUNCTION public._branch_locker_door_no(p_branch_id uuid)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE WHEN d.hw->>'zone' ~ '^[0-9]{1,3}$' THEN (d.hw->>'zone')::integer END
    FROM branch_doors d
   WHERE d.branch_id = p_branch_id AND d.door_kind = 'accessories' AND d.is_active
   ORDER BY d.sort_order NULLS LAST LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public._branch_gate_code(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._branch_locker_door_no(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._branch_gate_code(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._branch_locker_door_no(uuid) TO service_role;

-- Řádky kódů do in-app zprávy. Bez brány přesně dosavadní text (motorka, šatna);
-- s bránou pořadí brána → šatna (dveře č. N) → motorka.
CREATE OR REPLACE FUNCTION public._door_codes_msg_lines(p_gate text, p_locker_door integer, p_code_gear text, p_code_moto text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN p_gate IS NULL THEN
      'Kód k motorce: ' || COALESCE(p_code_moto, '–') ||
      CASE WHEN p_code_gear IS NOT NULL THEN E'\nKód šatny: ' || p_code_gear ELSE '' END
    ELSE
      'Kód schránky s klíčem od brány: ' || p_gate ||
      CASE WHEN p_code_gear IS NOT NULL THEN
        E'\nKód šatny' || CASE WHEN p_locker_door IS NOT NULL THEN ' (dveře č. ' || p_locker_door || ')' ELSE '' END
        || ': ' || p_code_gear ELSE '' END ||
      E'\nKód k motorce: ' || COALESCE(p_code_moto, '–')
  END;
$$;

-- Úvod věty o platnosti (do „(“). Bez brány dosavadní „Kódy jsou platné“ /
-- „Kód je platný“; s bránou jen kódy rezervace (kód brány je trvalý).
CREATE OR REPLACE FUNCTION public._door_codes_msg_valid(p_gate text, p_has_gear boolean, p_long boolean)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
      WHEN p_gate IS NULL AND p_has_gear THEN 'Kódy jsou platné '
      WHEN p_gate IS NULL THEN 'Kód je platný '
      WHEN p_has_gear THEN 'Kód šatny a kód k motorce platí '
      ELSE 'Kód k motorce platí ' END
    || CASE WHEN p_long THEN 'po dobu trvání pronájmu (' ELSE '(' END;
$$;

-- Stručný postup pro pobočku s bránou (připojí se ZA kódy — push nese jen
-- prvních 200 znaků). Bez brány prázdný řetězec.
CREATE OR REPLACE FUNCTION public._gate_procedure_msg(p_gate text, p_locker_door integer, p_has_gear boolean)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN p_gate IS NULL THEN '' ELSE
    E'\n\nPostup na pobočce:' ||
    E'\n1) Je-li vjezdová brána zavřená, otevřete HORNÍ schránku na pravém sloupku vrat kódem ' || p_gate ||
    ' — je v ní klíč od visacího zámku brány. Bránu odemkněte, vjeďte dovnitř a zaparkujte na kterémkoli místě 1–7 vpravo u plotu. Auto tu může zdarma stát po celou dobu výpůjčky.' ||
    CASE WHEN p_has_gear THEN
      E'\n2) Na displeji zadejte kód šatny' ||
      CASE WHEN p_locker_door IS NOT NULL THEN ' (šatna = dveře č. ' || p_locker_door || ')' ELSE '' END ||
      ', převlékněte se, v předávacím protokolu upravte velikosti a protokol podepište.' ||
      E'\n3) Zadejte kód motorky, vezměte motorku a zavřete dveře šatny i kóje.'
    ELSE
      E'\n2) Na displeji zadejte kód motorky, podepište předávací protokol, vezměte motorku a zavřete dveře kóje.'
    END ||
    E'\n' || CASE WHEN p_has_gear THEN '4' ELSE '3' END ||
    ') DŮLEŽITÉ: Byla-li brána zavřená, po odjezdu ji zase zavřete, zamkněte visacím zámkem, klíč vraťte do horní schránky a přetočte číselník, aby kód nezůstal nastavený. Otevřenou bránu nechte otevřenou. Stejně postupujte i při vrácení motorky.'
  END;
$$;

-- SMS/WA šablona kódů: s bránou varianty *_gate (navíc {{gate_code}} —
-- klíč řadí abecedně ZA door_code_*; WA šablony nemají Meta SID, posílá se text).
CREATE OR REPLACE FUNCTION public._door_codes_sms_slug(p_gate text, p_has_gear boolean)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN p_gate IS NULL
              THEN CASE WHEN p_has_gear THEN 'door_codes' ELSE 'door_codes_moto_only' END
              ELSE CASE WHEN p_has_gear THEN 'door_codes_gate' ELSE 'door_codes_gate_moto_only' END END;
$$;

-- Jazyk SMS/WA: jazyk rezervace/profilu, jen podporované (šablony existují), jinak cs.
CREATE OR REPLACE FUNCTION public._door_codes_sms_lang(p_user_id uuid, p_booking_id uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE WHEN l IN ('cs','en','de','nl','es','fr','pl','uk') THEN l ELSE 'cs' END
    FROM (SELECT lower(COALESCE(public.detect_customer_language(p_user_id, p_booking_id, NULL), 'cs')) AS l) x;
$$;

REVOKE ALL ON FUNCTION public._door_codes_sms_slug(text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._door_codes_sms_lang(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._door_codes_msg_lines(text, integer, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._door_codes_msg_valid(text, boolean, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._gate_procedure_msg(text, integer, boolean) FROM PUBLIC, anon, authenticated;

-- Má pobočka bránu se schránkou? (jen příznak, NE kód) — web/appka podle toho
-- zobrazí postup s bránou.
CREATE OR REPLACE FUNCTION public.branch_has_gate(p_branch_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM branch_gate_access g WHERE g.branch_id = p_branch_id AND g.is_active);
$$;
GRANT EXECUTE ON FUNCTION public.branch_has_gate(uuid) TO anon, authenticated, service_role;

-- Zákazník (appka): brána k VLASTNÍ rezervaci. Kód jen u reserved/active
-- rezervace s VYDANÝM kódem motorky (stejné pravidlo jako ostatní kódy).
CREATE OR REPLACE FUNCTION public.get_booking_gate_info(p_booking_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_b record;
  v_gate text;
  v_released boolean;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('has_gate', false); END IF;
  SELECT b.status, m.branch_id INTO v_b
    FROM bookings b LEFT JOIN motorcycles m ON m.id = b.moto_id
   WHERE b.id = p_booking_id AND b.user_id = v_uid;
  IF NOT FOUND OR v_b.branch_id IS NULL THEN RETURN jsonb_build_object('has_gate', false); END IF;
  v_gate := _branch_gate_code(v_b.branch_id);
  IF v_gate IS NULL THEN RETURN jsonb_build_object('has_gate', false); END IF;
  SELECT EXISTS (SELECT 1 FROM branch_door_codes c
                  WHERE c.booking_id = p_booking_id AND c.code_type = 'motorcycle'
                    AND c.is_active AND c.sent_to_customer)
    INTO v_released;
  RETURN jsonb_build_object(
    'has_gate', true,
    'gate_code', CASE WHEN v_released AND v_b.status IN ('reserved', 'active') THEN v_gate END,
    'locker_door', _branch_locker_door_no(v_b.branch_id));
END;
$$;
REVOKE ALL ON FUNCTION public.get_booking_gate_info(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_booking_gate_info(uuid) TO authenticated, service_role;
