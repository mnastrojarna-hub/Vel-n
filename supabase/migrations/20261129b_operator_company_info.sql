-- =============================================================================
-- 20261129b_operator_company_info.sql
-- Změna provozovatele (2/9): přepnutí app_settings.company_info na MotoGo24 s.r.o.
--
-- Zadání majitele 2026-11-27 (údaje ověřené v ARES a v seznamu datových schránek 2026-11-27):
--   MotoGo24 s.r.o., IČO 29909864, sídlo Mezná 9, 393 01 Mezná, zapsaná v obchodním rejstříku
--   vedeném Krajským soudem v Českých Budějovicích, oddíl C, vložka 36876; není plátce DPH;
--   účet 2303580494/2010 (Fio banka), IBAN CZ8320100000002303580494; datová schránka 2xfihrd.
--   Kontakty (telefon, e-mail, web, sociální sítě) se NEMĚNÍ.
--
-- company_info je JEDINÝ zdroj provozovatele pro: faktury a doklady (edge generate-invoice),
-- smlouvy / VOP / protokoly ({{company_*}}), QR platbu a platební údaje, patičky e-mailů,
-- AI asistenty, strukturovaná data webu a Velín. Od této chvíle každý NOVÝ doklad nese nového
-- provozovatele; dosavadní doklady drží původního (invoices.issuer_snapshot – soubor 20261129a,
-- který MUSÍ proběhnout dřív; přepnutí to hlídá a bez něj se zastaví s chybou).
--
-- valid_from = okamžik aplikace: smlouvy / VOP / protokoly vygenerované dřív se nepřemazávají.
-- Důsledek (beze změny logiky, jen jiný účet): účet je u Fio → automatické párování plateb a
-- vratky příkazem začnou fungovat, jakmile jsou v Supabase secrets tokeny TOHOTO účtu.
-- Idempotentní: přepíná jen z dosavadního provozovatele (IČO 21874263); 2. běh nic nezmění.
-- Bez BEGIN/COMMIT – deploy-sql.yml pouští soubor v jedné transakci (ON_ERROR_STOP).
-- =============================================================================
-- Schváleno majitelem 2026-11-27.

DO $$
DECLARE
  v_ico text;
  n     integer;
  c_new constant jsonb := jsonb_build_object(
    'name',           'MotoGo24 s.r.o.',
    'ico',            '29909864',
    'dic',            NULL,
    'vat_payer',      false,
    'address',        'Mezná 9, 393 01 Mezná',
    'register',       'zapsaná v obchodním rejstříku vedeném Krajským soudem v Českých Budějovicích, oddíl C, vložka 36876',
    'register_short', 'C 36876 vedená u Krajského soudu v Českých Budějovicích',
    'bank_account',   '2303580494/2010',
    'bank_iban',      'CZ8320100000002303580494',
    'bank_name',      'Fio banka',
    'bank_bic',       'FIOBCZPPXXX',
    'data_box',       '2xfihrd');
BEGIN
  SELECT value ->> 'ico' INTO v_ico FROM public.app_settings WHERE key = 'company_info';

  IF NOT FOUND THEN
    INSERT INTO public.app_settings (key, value)
    VALUES ('company_info', c_new || jsonb_build_object(
      'phone', '+420 774 256 271', 'email', 'info@motogo24.cz', 'web', 'https://motogo24.com',
      'valid_from', to_jsonb(now())));
    RAISE NOTICE 'company_info: řádek chyběl – založen (MotoGo24 s.r.o.)';
  ELSIF v_ico = '21874263' THEN
    -- pojistka pořadí: bez sloupce, triggeru a doplněných dokladů by dosavadní doklady po přepnutí změnily dodavatele
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = 'invoices' AND column_name = 'issuer_snapshot')
       OR NOT EXISTS (SELECT 1 FROM pg_trigger
                       WHERE tgrelid = 'public.invoices'::regclass AND tgname = 'trg_invoices_stamp_issuer' AND NOT tgisinternal) THEN
      RAISE EXCEPTION 'company_info: nejdřív musí proběhnout 20261129a_invoices_issuer_snapshot.sql (sloupec invoices.issuer_snapshot + trigger)';
    END IF;
    SELECT count(*) INTO n FROM public.invoices WHERE issuer_snapshot IS NULL AND type <> 'received';
    IF n > 0 THEN
      RAISE EXCEPTION 'company_info: % vydaných dokladů nemá uloženého vystavitele (issuer_snapshot IS NULL) – přepnutí by jim změnilo dodavatele', n;
    END IF;
    -- || přepíše jen uvedené klíče; phone, email, web, facebook, instagram zůstávají
    UPDATE public.app_settings
       SET value = value || c_new || jsonb_build_object('valid_from', to_jsonb(now())),
           updated_at = now()
     WHERE key = 'company_info' AND value ->> 'ico' = '21874263';
    GET DIAGNOSTICS n = ROW_COUNT;
    RAISE NOTICE 'company_info: přepnuto na MotoGo24 s.r.o. (IČO 29909864, účet 2303580494/2010) – řádků %', n;
  ELSIF v_ico = '29909864' THEN
    -- už přepnuto (2. běh / ruční úprava ve Velínu): jen doplnit klíče, které by chyběly, nic nepřepisovat
    UPDATE public.app_settings
       SET value = (c_new || jsonb_build_object('valid_from', to_jsonb(now()))) || value,
           updated_at = now()
     WHERE key = 'company_info'
       AND NOT (value ?& ARRAY['register', 'register_short', 'bank_account', 'bank_iban', 'bank_name', 'bank_bic', 'data_box', 'valid_from']);
    GET DIAGNOSTICS n = ROW_COUNT;
    RAISE NOTICE 'company_info: nový provozovatel už nastaven – doplněny chybějící klíče u % řádků', n;
  ELSE
    RAISE WARNING 'company_info: neočekávané IČO „%“ – nic se nemění (zkontrolujte Velín → Státní správa → IČO / DIČ)', v_ico;
  END IF;
END $$;
