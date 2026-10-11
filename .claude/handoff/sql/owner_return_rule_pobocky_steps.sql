-- DRAFT (NOT applied, NOT in git) — QA of workstream ai-app-mail, 2026-10-11.
-- Owner rule: Mezná (staffed, incl. return elsewhere) = no wash, no refuel;
-- Velké Němčice (self-service) = no full tank needed, but WASHED + reserve light NOT on.
--
-- Why: live cms_variables rows web.pobocky.branches.0.steps / .1.steps (CS only, translations {})
-- OVERRIDE the defaults in data/pobocky.php AND in the app (branches_info_provider.dart) —
-- without this the new step sentences are invisible on the CS web page /pobocky and in the app
-- (all languages: the app falls back to the CS DB value). m3a_owner_texts.sql does not cover them.
-- New text = byte-equal to data/pobocky.php and branchesInfoDefaults (app).
-- Idempotent: replaces only while the old phrase is present and the new one is not;
-- a row edited in Velín in the meantime is left alone (NOTICE). No BEGIN/COMMIT (deploy = 1 tx).

DO $$
DECLARE
  f record;
  cnt integer;
BEGIN
  FOR f IN
    SELECT * FROM (VALUES
      ($t$web.pobocky.branches.0.steps$t$,
       $t$(nebo si ji vyzvedneme na domluvené adrese).$t$,
       $t$(nebo si ji vyzvedneme na domluvené adrese) — mýt ani tankovat ji nemusíte.$t$),
      ($t$web.pobocky.branches.1.steps$t$,
       $t$kdykoliv poslední den výpůjčky do 24:00. Je-li brána zavřená$t$,
       $t$kdykoliv poslední den výpůjčky do 24:00. Motorku vraťte umytou a bez svítící rezervy (plnou nádrž nepotřebujete). Je-li brána zavřená$t$)
    ) AS x(k, old_txt, new_txt)
  LOOP
    UPDATE public.cms_variables
       SET value = to_jsonb(replace(value #>> '{}', f.old_txt, f.new_txt)), updated_at = now()
     WHERE key = f.k AND jsonb_typeof(value) = 'string'
       AND strpos(value #>> '{}', f.old_txt) > 0
       AND strpos(value #>> '{}', f.new_txt) = 0;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    IF cnt = 0 THEN
      RAISE NOTICE 'pobocky steps % — beze změny (už hotovo, nebo text ve Velíně změněn)', f.k;
    END IF;
  END LOOP;
END $$;
