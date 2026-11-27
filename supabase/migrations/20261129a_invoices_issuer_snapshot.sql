-- =============================================================================
-- 20261129a_invoices_issuer_snapshot.sql
-- Změna provozovatele (1/9): vystavitel dokladu se ukládá K DOKLADU.
--
-- Zadání majitele 2026-11-27: provozovatelem je nově MotoGo24 s.r.o.; doklady UŽ VYSTAVENÉ se
-- nepřepisují (staré faktury drží původního provozovatele, dobropis ke staré faktuře také).
--
-- Co soubor dělá (schéma + jednorázové doplnění dat):
--   1) nový sloupec invoices.issuer_snapshot (jsonb) = kopie app_settings.company_info v okamžiku
--      vystavení dokladu; doklad (faktura, zálohová faktura, doklad k platbě, dobropis) se vždy
--      tiskne z této hodnoty, ne z dnešního nastavení;
--   2) JEDNORÁZOVĚ doplní všem dosavadním vydaným dokladům dosavadního provozovatele
--      (app_settings.company_info, jak platí v okamžiku běhu = před přepnutím v souboru 20261129b);
--   3) trigger BEFORE INSERT: každý nový doklad dostane aktuálního provozovatele; DOBROPIS dostane
--      vystavitele dokladu, který opravuje (original_invoice_id, jinak poslední doklad téže
--      rezervace / objednávky).
--
-- MUSÍ běžet PŘED 20261129b (přepnutí company_info) — proto písmeno „a“. Kdyby company_info už
-- dosavadního provozovatele nedrželo, doplní se dosavadní provozovatel z hodnot ověřených v živé
-- DB 2026-11-27 (doklady vystavené před touto migrací nikdy nevystavila nová společnost).
-- Přijaté faktury (type = 'received') se netýká. Čtení sloupce = stejná pravidla jako zbytek řádku
-- (RLS invoices beze změny: zákazník vidí svůj doklad i s vystavitelem, Velín vše).
-- Idempotentní: doplnění proběhne jen při PRVNÍM běhu (dokud trigger neexistuje); 2. běh nic nemění.
-- Bez BEGIN/COMMIT – deploy-sql.yml pouští soubor v jedné transakci (ON_ERROR_STOP).
-- =============================================================================
-- Schváleno majitelem 2026-11-27.

ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS issuer_snapshot jsonb;

COMMENT ON COLUMN public.invoices.issuer_snapshot IS
  'Dodavatel (vystavitel) dokladu v okamžiku vystavení = kopie app_settings.company_info (plní trigger trg_invoices_stamp_issuer; dobropis dědí vystavitele opravovaného dokladu). Doklad se VŽDY renderuje z této hodnoty; NULL = aktuální company_info. Nikdy nepřepisovat.';

-- 2) jednorázové doplnění dosavadních dokladů (jen při prvním běhu = dokud trigger neexistuje)
DO $$
DECLARE
  v_ci   jsonb;
  v_old  jsonb;
  n      integer;
  -- dosavadní provozovatel podle živé DB 2026-11-27 (použije se jen když company_info už drží někoho jiného)
  c_prev constant jsonb := jsonb_build_object(
    'name', 'Bc. Petra Semorádová', 'ico', '21874263', 'dic', NULL, 'vat_payer', false,
    'address', 'Mezná 9, 393 01 Pelhřimov', 'bank_account', '670100-2225851630/6210',
    'phone', '+420 774 256 271', 'email', 'info@motogo24.cz', 'web', 'https://motogo24.com');
BEGIN
  IF EXISTS (SELECT 1 FROM pg_trigger
              WHERE tgrelid = 'public.invoices'::regclass AND tgname = 'trg_invoices_stamp_issuer' AND NOT tgisinternal) THEN
    RAISE NOTICE 'issuer_snapshot: trigger už existuje – jednorázové doplnění přeskočeno (2. běh)';
    RETURN;
  END IF;

  SELECT value INTO v_ci FROM public.app_settings WHERE key = 'company_info';
  IF v_ci IS NOT NULL AND v_ci ->> 'ico' = c_prev ->> 'ico' THEN
    v_old := v_ci;
    RAISE NOTICE 'issuer_snapshot: dosavadní provozovatel z app_settings.company_info (% / IČO %)', v_ci ->> 'name', v_ci ->> 'ico';
  ELSE
    v_old := c_prev;
    RAISE NOTICE 'issuer_snapshot: company_info už nedrží dosavadního provozovatele (IČO %) – použity hodnoty z 2026-11-27', coalesce(v_ci ->> 'ico', '—');
  END IF;
  -- název banky dosavadního účtu (company_info ho nemělo; doklady ho tiskly napevno)
  IF NOT (v_old ? 'bank_name') AND (v_old ->> 'bank_account') LIKE '%/6210' THEN
    v_old := v_old || jsonb_build_object('bank_name', 'mBank');
  END IF;

  UPDATE public.invoices
     SET issuer_snapshot = v_old
   WHERE issuer_snapshot IS NULL
     AND type <> 'received';
  GET DIAGNOSTICS n = ROW_COUNT;
  RAISE NOTICE 'issuer_snapshot: dosavadní provozovatel doplněn u % vydaných dokladů', n;

  -- kontrola: žádný vydaný doklad (faktura, zálohová faktura, doklad k platbě, dobropis) nesmí zůstat
  -- bez vystavitele – jinak by se po přepnutí provozovatele tiskl s novým (a Velín by změnu nepustil)
  SELECT count(*) INTO n FROM public.invoices WHERE issuer_snapshot IS NULL AND type <> 'received';
  IF n > 0 THEN
    RAISE EXCEPTION 'issuer_snapshot: % vydaných dokladů zůstalo bez vystavitele – migrace se neprovede', n;
  END IF;
END $$;

-- 3) nové doklady
CREATE OR REPLACE FUNCTION public.invoices_stamp_issuer() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v jsonb;
BEGIN
  -- výslovně zadaný vystavitel se respektuje; přijaté faktury vystavil dodavatel, ne my
  IF NEW.issuer_snapshot IS NOT NULL OR NEW.type = 'received' THEN
    RETURN NEW;
  END IF;

  -- Dobropis nese vystavitele dokladu, který opravuje.
  IF NEW.type = 'credit_note' THEN
    IF NEW.original_invoice_id IS NOT NULL THEN
      SELECT i.issuer_snapshot INTO v FROM public.invoices i WHERE i.id = NEW.original_invoice_id;
    END IF;
    -- bez odkazu na původní doklad: poslední vydaný doklad téže rezervace / objednávky
    IF v IS NULL AND NEW.booking_id IS NOT NULL THEN
      SELECT i.issuer_snapshot INTO v FROM public.invoices i
       WHERE i.booking_id = NEW.booking_id AND i.type NOT IN ('credit_note', 'received')
         AND i.status <> 'cancelled' AND i.issuer_snapshot IS NOT NULL
       ORDER BY i.issue_date DESC, i.created_at DESC LIMIT 1;
    END IF;
    IF v IS NULL AND NEW.order_id IS NOT NULL THEN
      SELECT i.issuer_snapshot INTO v FROM public.invoices i
       WHERE i.order_id = NEW.order_id AND i.type NOT IN ('credit_note', 'received')
         AND i.status <> 'cancelled' AND i.issuer_snapshot IS NOT NULL
       ORDER BY i.issue_date DESC, i.created_at DESC LIMIT 1;
    END IF;
  END IF;

  -- Každý jiný nový doklad (a dobropis bez dohledatelného původního dokladu): aktuální provozovatel.
  IF v IS NULL THEN
    SELECT s.value INTO v FROM public.app_settings s WHERE s.key = 'company_info';
  END IF;

  NEW.issuer_snapshot := v;   -- NULL (nastavení chybí) = doklad se tiskne z aktuálního company_info
  RETURN NEW;
END $$;

COMMENT ON FUNCTION public.invoices_stamp_issuer() IS
  'BEFORE INSERT invoices: uloží vystavitele dokladu (invoices.issuer_snapshot) = app_settings.company_info; dobropis dědí vystavitele opravovaného dokladu. Změna provozovatele 2026-11.';

DROP TRIGGER IF EXISTS trg_invoices_stamp_issuer ON public.invoices;
CREATE TRIGGER trg_invoices_stamp_issuer
  BEFORE INSERT ON public.invoices
  FOR EACH ROW EXECUTE FUNCTION public.invoices_stamp_issuer();
