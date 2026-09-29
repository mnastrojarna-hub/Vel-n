-- =============================================================================
-- STAV TACHOMETRU (2026-09-29) — 6/6 (merge B, AŽ po nasazení Velínu/AI na admin_move_motorcycle):
-- strážci přesunu obslužná ↔ samoobslužná
-- Migrace: 20260929h_moto_move_guards.sql — idempotentní
--  • motorcycles.branch_id mezi režimy (i NULL → samoobslužná) jen přes admin_move_motorcycle (GUC = id motorky);
--    odebrání pobočky (→ NULL, i FK ON DELETE SET NULL při smazání pobočky) projde
--  • branches.type mezi režimy jen bez přiřazených (nevyřazených) motorek — nejdřív přesun motorek (se stavem km)
-- =============================================================================

CREATE OR REPLACE FUNCTION public._guard_moto_branch_type_move()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.branch_id IS NULL
     OR public.branch_is_self_service(OLD.branch_id) = public.branch_is_self_service(NEW.branch_id)
     OR COALESCE(current_setting('motogo.moto_move_ok', true), '') = NEW.id::text THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'moto_move_requires_odometer'
    USING DETAIL = 'Přesun motorky mezi obslužnou a samoobslužnou pobočkou vyžaduje aktuální stav tachometru.',
          HINT   = 'Použijte RPC admin_move_motorcycle(p_moto_id, p_branch_id, p_km).';
END;
$$;
REVOKE ALL ON FUNCTION public._guard_moto_branch_type_move() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_guard_moto_branch_type_move ON public.motorcycles;
CREATE TRIGGER trg_guard_moto_branch_type_move
  BEFORE UPDATE OF branch_id ON public.motorcycles
  FOR EACH ROW WHEN (OLD.branch_id IS DISTINCT FROM NEW.branch_id)
  EXECUTE FUNCTION public._guard_moto_branch_type_move();

CREATE OR REPLACE FUNCTION public._guard_branch_type_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF COALESCE(NEW.type = 'samoobslužná', false) = COALESCE(OLD.type = 'samoobslužná', false) THEN
    RETURN NEW;
  END IF;
  IF EXISTS (SELECT 1 FROM motorcycles m WHERE m.branch_id = NEW.id AND m.status IS DISTINCT FROM 'retired') THEN
    RAISE EXCEPTION 'branch_type_change_requires_odometer'
      USING DETAIL = 'Pobočka má přiřazené motorky — změna obslužná/samoobslužná by je přesunula bez stavu tachometru.',
            HINT   = 'Nejdřív motorky přesuňte (Velín se zeptá na stav tachometru), pak změňte typ pobočky.';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public._guard_branch_type_change() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_guard_branch_type_change ON public.branches;
CREATE TRIGGER trg_guard_branch_type_change
  BEFORE UPDATE OF type ON public.branches
  FOR EACH ROW WHEN (OLD.type IS DISTINCT FROM NEW.type)
  EXECUTE FUNCTION public._guard_branch_type_change();
