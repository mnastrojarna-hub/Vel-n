-- ============================================================================
-- 20261105a_uq_invoices_credit_note_refund.sql — NÁVRH (oprava i1 2026-11-05), NENASAZENO
-- Jeden živý dobropis na jednu Stripe vratku.
--
-- Proč: process-refund vystavuje dobropis „načti → vlož“ (bez zámku). Dva souběžné dispatche TÉŽE
-- zákaznické vratky (fronta PaidChangeQueue v appce / dvojí klepnutí) se ve Stripe srazí do JEDNÉ
-- vratky (idempotency klíč), ale každé volání vložilo vlastní dobropis + účetní záznam → dobropisy
-- 1 000 Kč k vratce 500 Kč. Ruční cesta (manualBookingRefund) má 15min dedup, Stripe cesta žádný.
-- Živá DB nemá na invoices.stripe_refund_id žádný unikátní index (snapshot 2026-10-29: jen
-- invoices_number_key / pkey / uq_invoices_active_order_type).
--
-- Co dělá: částečný UNIQUE index přes stripe_refund_id u NEzrušených dobropisů. process-refund
-- (verze z vývojové větve) porušení 23505 bere jako „dobropis už existuje“ → převezme ho a pokračuje
-- PDF krokem (bez mailu „Dobropis se nevystavil“). Starší edge verze (živá dnes) při porušení pošle
-- mail obsluze a vratka proběhne — peníze správně, jen jeden doklad (lepší než dva).
--
-- Bezpečnost: feature-detekce (tabulka / sloupec), idempotentní (index už existuje → nic),
-- a POKUD v živé DB existují duplicity (víc živých dobropisů na touž vratku), index se NEVYTVOŘÍ
-- a jen se zapíše WARNING s počtem — nejdřív je třeba duplicity ručně zrušit (status 'cancelled')
-- ve Velíně a migraci spustit znovu (ruční běh deploy-sql.yml s `only`+`force`). Bez BEGIN/COMMIT
-- (deploy-sql.yml aplikuje soubor v jedné transakci).
-- ============================================================================
DO $mg$
DECLARE
  v_dup integer;
BEGIN
  IF to_regclass('public.invoices') IS NULL THEN
    RAISE NOTICE '[20261105a] tabulka public.invoices chybí — nic';
    RETURN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'invoices' AND column_name = 'stripe_refund_id') THEN
    RAISE NOTICE '[20261105a] sloupec invoices.stripe_refund_id chybí — nic';
    RETURN;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'invoices'
             AND indexname = 'uq_invoices_credit_note_refund') THEN
    RAISE NOTICE '[20261105a] index uq_invoices_credit_note_refund už existuje — nic';
    RETURN;
  END IF;

  SELECT count(*) INTO v_dup FROM (
    SELECT stripe_refund_id FROM public.invoices
    WHERE type = 'credit_note' AND stripe_refund_id IS NOT NULL AND status <> 'cancelled'
    GROUP BY stripe_refund_id HAVING count(*) > 1
  ) d;
  IF v_dup > 0 THEN
    RAISE WARNING '[20261105a] index uq_invoices_credit_note_refund NEVYTVOŘEN: % Stripe vratek má víc živých dobropisů — zrušte duplicity (status cancelled) a migraci spusťte znovu', v_dup;
    RETURN;
  END IF;

  EXECUTE 'CREATE UNIQUE INDEX uq_invoices_credit_note_refund ON public.invoices (stripe_refund_id) '
       || 'WHERE type = ''credit_note'' AND stripe_refund_id IS NOT NULL AND status <> ''cancelled''';
  EXECUTE 'COMMENT ON INDEX public.uq_invoices_credit_note_refund IS '
       || '''Jeden živý dobropis na jednu Stripe vratku (process-refund: souběžný dispatch téže vratky → dobropis se převezme, nevystaví podruhé). 2026-11-05.''';
  RAISE NOTICE '[20261105a] index uq_invoices_credit_note_refund vytvořen';
END
$mg$;
