-- =============================================================================
-- 2026-11-30f (VOLITELNÉ): úklid historie běhů pg_cron
--
-- pg_cron zapisuje každý běh každého jobu do cron.job_run_details a sám nic nemaže. V repu žádný
-- úklid není; minutové joby (backfill-poi-photos, backfill-route-translations,
-- kiosk-return-completion, nově fio-bank-sync) = ~5 800 řádků denně, 2minutové další ~1 400.
-- Tento job 1× denně smaže záznamy starší 7 dní (diagnostika posledních dní zůstává).
-- Není podmínkou minutové synchronizace — jen hygiena. Idempotentní.
-- NEOVĚŘENO na živé DB: právo role postgres mazat z cron.job_run_details (na Supabase běžně je;
-- kdyby nebylo, job skončí chybou v job_run_details a nic jiného neovlivní).
-- STATE soubory: 5 (cron), 6.
-- =============================================================================
DO $$
BEGIN
  IF to_regclass('cron.job_run_details') IS NULL THEN
    RAISE NOTICE 'cron.job_run_details neexistuje — úklid se neplánuje';
    RETURN;
  END IF;
  BEGIN
    PERFORM cron.unschedule('cron-run-details-retention');
  EXCEPTION WHEN OTHERS THEN NULL; -- job ještě neexistuje
  END;
  PERFORM cron.schedule(
    'cron-run-details-retention',
    '25 3 * * *',
    $cron$ DELETE FROM cron.job_run_details WHERE end_time < now() - interval '7 days'; $cron$
  );
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'cron-run-details-retention: %', SQLERRM;
END $$;
