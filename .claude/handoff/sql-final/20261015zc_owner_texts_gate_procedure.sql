-- =============================================================================
-- 20261015zc_owner_texts_gate_procedure.sql
-- datová migrace (bez změn schématu): postup na pobočce s bránou (in-app zpráva s kódy) – věta o vrácení.
--
-- Pravidlo majitele (2026-10-11 doslova: „Mytí ani tankování není třeba na obslužné pobočce. Na
-- samoobsluze není potřeba tankovat. To důležité je pouze, aby motorka byla umytá a nesvítila
-- rezerva.“; upřesnění 2026-10-12: stav paliva neřešíme, plnou nádrž při převzetí nikdy neslibovat,
-- žádný poplatek za palivo):
--   → Vrácení kdekoli: tankovat netřeba, jen ať nesvítí rezerva. Umytá jen na samoobslužné pobočce
--     Velké Němčice u Brna; v Mezné u Pelhřimova i při vrácení jinde (odvoz z Mezné) bez mytí.
--
-- public._gate_procedure_msg skládá „Postup na pobočce“ do zprávy s kódy (Velké Němčice). K bodu
-- „DŮLEŽITÉ … Stejně postupujte i při vrácení motorky.“ přidána věta o stavu při vrácení – shodná s e-mailem
-- (branch-gate-texts-a.ts stepImportant), appkou (procStepImportant) a webem (confirm.success.gateNotice).
-- Tělo jinak 1:1 z 20261004_vn_gate_access.sql (CREATE OR REPLACE, REVOKE zachován). Po aplikaci
-- aktualizovat SUPABASE_BACKEND_STATE_3.md.
--
-- Bezpečnost: funkci nahradí JEN když má živé tělo přesně znění z 20261004 (otisk md5 prosrc); jinak
-- ji nechá být a vypíše NOTICE. Idempotentní (2. běh: „už hotovo“). Bez BEGIN/COMMIT – deploy-sql.yml
-- pouští soubor v jedné transakci (ON_ERROR_STOP).
-- =============================================================================

-- Funkce se nahradí JEN když má živé tělo přesně znění z 20261004_vn_gate_access.sql (md5 prosrc, ověřeno proti
-- snapshotu živé DB 2026-10-10 i proti migraci); jiné tělo (někdo funkci mezitím změnil) → beze změny + NOTICE.
DO $do$
DECLARE
  c_old_md5 constant text := '7bbb079dedee0cf53a0e851fb6ccef01';   -- tělo 20261004_vn_gate_access.sql
  c_new_md5 constant text := '1972a4a83ca2587adc616a1964441d05';   -- tělo níže (+ věta o vrácení)
  v_fn regprocedure := to_regprocedure('public._gate_procedure_msg(text,integer,boolean)');
  v_md5 text;
BEGIN
  IF v_fn IS NULL THEN
    RAISE NOTICE 'gate_procedure: funkce public._gate_procedure_msg(text, integer, boolean) neexistuje – PŘESKOČENO';
    RETURN;
  END IF;
  SELECT md5(prosrc) INTO v_md5 FROM pg_proc WHERE oid = v_fn;
  IF v_md5 = c_new_md5 THEN
    RAISE NOTICE 'gate_procedure: už hotovo (tělo funkce už obsahuje větu o vrácení)';
  ELSIF v_md5 = c_old_md5 THEN
    EXECUTE $fn$
CREATE OR REPLACE FUNCTION public._gate_procedure_msg(p_gate text, p_locker_door integer, p_has_gear boolean)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN p_gate IS NULL THEN '' ELSE
    E'\n\nPostup na pobočce:' ||
    E'\n1) Je-li vjezdová brána zavřená, otevřete HORNÍ schránku na pravém sloupku vrat kódem ' || p_gate ||
    ' — je v ní klíč od visacího zámku brány. Bránu odemkněte, vjeďte dovnitř a zaparkujte na kterémkoli parkovacím místě 1–7 vpravo u plotu. Auto tu může zdarma stát po celou dobu výpůjčky.' ||
    CASE WHEN p_has_gear THEN
      E'\n2) Na displeji zadejte kód šatny' ||
      CASE WHEN p_locker_door IS NOT NULL THEN ' (šatna = dveře č. ' || p_locker_door || ')' ELSE '' END ||
      ', vezměte si výbavu, převlékněte se a zavřete dveře šatny. Poté na displeji v předávacím protokolu upravte velikosti a protokol podepište.' ||
      E'\n3) Zadejte kód motorky, vezměte motorku a zavřete dveře kóje.'
    ELSE
      E'\n2) Na displeji zadejte kód motorky, podepište předávací protokol, vezměte motorku a zavřete dveře kóje.'
    END ||
    E'\n' || CASE WHEN p_has_gear THEN '4' ELSE '3' END ||
    ') DŮLEŽITÉ: Byla-li brána zavřená, po odjezdu ji zase zavřete, zamkněte visacím zámkem, klíč vraťte do horní schránky a přetočte číselník, aby kód nezůstal nastavený. Otevřenou bránu nechte otevřenou. Stejně postupujte i při vrácení motorky. Motorku vracejte umytou a tak, aby nesvítila kontrolka rezervy (tankovat do plna nemusíte).'
  END;
$$
$fn$;
    EXECUTE 'REVOKE ALL ON FUNCTION public._gate_procedure_msg(text, integer, boolean) FROM PUBLIC, anon, authenticated';
    RAISE NOTICE 'gate_procedure: funkce public._gate_procedure_msg upravena (věta o vrácení)';
  ELSE
    RAISE NOTICE 'gate_procedure: PŘESKOČENO – tělo funkce se liší od verze 20261004 (md5 %), funkce ponechána; větu o vrácení doplňte ručně', v_md5;
  END IF;
END $do$;
