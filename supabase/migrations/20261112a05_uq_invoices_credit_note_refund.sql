-- =============================================================================
-- 20261112a05_uq_invoices_credit_note_refund.sql — jeden živý dobropis na jednu Stripe vratku
--
-- Oprava i1 (2026-11-05). process-refund vystavuje dobropis „načti → vlož“ bez zámku.
-- Dva souběžné dispatche TÉŽE zákaznické vratky (fronta PaidChangeQueue v appce / dvojí
-- klepnutí) se ve Stripe srazí do JEDNÉ vratky (idempotency klíč), ale každé volání
-- vložilo vlastní dobropis + účetní záznam → dobropisy 1 000 Kč k vratce 500 Kč.
-- Živá DB nemá na invoices.stripe_refund_id žádný unikátní index.
--
-- Co dělá: částečný UNIQUE index přes stripe_refund_id u NEzrušených dobropisů.
-- process-refund (verze z téhož merge) bere porušení 23505 jako „dobropis už existuje“
-- → převezme ho a pokračuje PDF krokem. Starší edge verze při porušení pošle mail obsluze
-- a vratka proběhne — peníze správně, jen jeden doklad.
--
-- Data: obsah živé tabulky invoices není z repa čitelný. Index se proto vytváří až po
-- kontrole duplicit pod zámkem SHARE (stejný zámek, jaký bere CREATE INDEX — souběžný
-- zápis dobropisu mezi kontrolou a stavbou indexu tak nevznikne; tabulka je malá, zámek
-- trvá zlomek sekundy). Existují-li duplicity (víc živých dobropisů na touž vratku),
-- index se NEVYTVOŘÍ a soubor skončí jen s WARNING (počet + jak postupovat) — deploy se
-- nezablokuje. Pak: zrušit duplicitní dobropisy ve Velíně (status 'cancelled') a spustit
-- deploy-sql.yml ručně s `only=20261112a05` a `force=true`.
-- Idempotentní (index už existuje → nic). Bez BEGIN/COMMIT.
-- Záměrně se nemění: ostatní indexy invoices, dobropisy bez stripe_refund_id (ruční vratky).
-- =============================================================================
DO $mg$
DECLARE
  v_dup integer;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'invoices'
             AND indexname = 'uq_invoices_credit_note_refund') THEN
    RAISE NOTICE '[20261112a05] index uq_invoices_credit_note_refund už existuje — nic';
    RETURN;
  END IF;

  -- SHARE: čtení dál běží, zápisy do invoices počkají do konce transakce (jako u CREATE INDEX).
  LOCK TABLE public.invoices IN SHARE MODE;

  SELECT count(*) INTO v_dup FROM (
    SELECT stripe_refund_id FROM public.invoices
     WHERE type = 'credit_note' AND stripe_refund_id IS NOT NULL AND status <> 'cancelled'
     GROUP BY stripe_refund_id HAVING count(*) > 1
  ) d;
  IF v_dup > 0 THEN
    RAISE WARNING '[20261112a05] index uq_invoices_credit_note_refund NEVYTVOŘEN: % Stripe vratek má víc živých dobropisů — zrušte duplicity (status cancelled) a spusťte deploy-sql.yml ručně (only=20261112a05, force=true)', v_dup;
    RETURN;
  END IF;

  BEGIN
    CREATE UNIQUE INDEX uq_invoices_credit_note_refund ON public.invoices (stripe_refund_id)
      WHERE type = 'credit_note' AND stripe_refund_id IS NOT NULL AND status <> 'cancelled';
  EXCEPTION WHEN unique_violation THEN
    -- nemá nastat (kontrola výše pod zámkem); pojistka, aby soubor nezablokoval deploy
    RAISE WARNING '[20261112a05] index uq_invoices_credit_note_refund NEVYTVOŘEN (duplicita: %) — zrušte duplicitní dobropisy a spusťte soubor znovu', SQLERRM;
    RETURN;
  END;
  COMMENT ON INDEX public.uq_invoices_credit_note_refund IS
    'Jeden živý dobropis na jednu Stripe vratku (process-refund: souběžný dispatch téže vratky → dobropis se převezme, nevystaví podruhé). 2026-11-05.';
  RAISE NOTICE '[20261112a05] index uq_invoices_credit_note_refund vytvořen';
END
$mg$;
