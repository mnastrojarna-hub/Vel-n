-- =============================================================================
-- Kontrola mailových šablon a toku kódu brány (Velké Němčice) — opravy z auditu
-- Migrace: 20261004h_gate_notify_pickup_only_and_universal_texts.sql (DATA + 2× CREATE OR REPLACE)
--
-- 1) admin_notify_branch_gate_code (20261004f): dopo­slání kódu brány z Velína šlo
--    i rezervacím s PŘISTAVENÍM na adresu — ty kód brány nedostávají
--    (_booking_gate_code → NULL), zákazník ale dostal zprávu „Kód schránky s klíčem
--    od brány“ bez kódu + zbytečně znovu SMS/e-mail; počet v potvrzovacím dialogu
--    byl nadsazený. Nově jen rezervace s nárokem na kód brány
--    (`_booking_gate_code(b.id) IS NOT NULL` = vyzvednutí na pobočce).
-- 2) trg_email_on_door_codes_message (živá, AFTER INSERT admin_messages type
--    door_codes): ignorovala NEW.booking_id a mailovala NEJNOVĚJŠÍ rezervaci
--    uživatele → ruční uvolnění / dopo­slání z Velína (_door_codes_notify) u
--    zákazníka s více rezervacemi adresovalo cizí rezervaci (dedup v
--    send_door_codes_email to většinou utlumil). Nově přednostně NEW.booking_id
--    (je-li to aktivní rezervace uživatele s vydanými kódy), jinak původní dohledání.
-- 3) email_templates (šablony z Velína se NEPŘEPISUJÍ, jen cílená věta):
--    booking_reserved + web_booking_reserved: „…můžete je u nás zdarma uložit do
--    uzamykatelné skříňky.“ platí jen pro Meznou → věta s uvedením obslužné pobočky;
--    booking_missing_docs + web_booking_missing_docs: „Abychom vám mohli předat
--    motorku a poslat přístupové kódy…“ (obslužné „předat“) → „vydat přístupové
--    kódy k motorce“. Změněným šablonám se vynuluje cache překladů.
-- 4) cms_variables (jen existující řádky s původním textem): děkovací stránka
--    `web.layout.confirm.success.nextBookingDocsMissing` („…nebo osobně při
--    vyzvednutí … půjčíme motorku po kontrole dokladů na pobočce“ = jen obslužná)
--    → univerzální text; `web.layout.rez.gear.intro` „vyzkoušíme ji na místě“ →
--    „vyzkoušíte ji na místě“. Překlady se obnoví uložením ve Velínu.
-- Idempotentní.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.admin_notify_branch_gate_code(p_branch_id uuid, p_dry_run boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r record;
  v_n integer := 0;
BEGIN
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
  END IF;
  IF public._branch_gate_code(p_branch_id) IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'no_active_gate');
  END IF;

  FOR r IN
    SELECT b.id
      FROM bookings b
      JOIN motorcycles m ON m.id = b.moto_id
     WHERE m.branch_id = p_branch_id
       AND b.is_test IS NOT TRUE
       AND b.status IN ('reserved', 'active')
       AND b.end_date::date >= (now() AT TIME ZONE 'Europe/Prague')::date
       AND EXISTS (SELECT 1 FROM branch_door_codes c
                    WHERE c.booking_id = b.id AND c.code_type = 'motorcycle'
                      AND c.is_active AND c.sent_to_customer)
       -- jen rezervace s nárokem na kód brány (vyzvednutí na pobočce; přistavení = NULL)
       AND public._booking_gate_code(b.id) IS NOT NULL
     ORDER BY b.start_date
  LOOP
    IF p_dry_run THEN
      v_n := v_n + 1;
      CONTINUE;
    END IF;
    BEGIN
      IF public._door_codes_notify(r.id, 'Kód schránky s klíčem od brány',
           'K vaší rezervaci přibyl kód schránky s klíčem od vjezdové brány — aktuální kódy:', true) THEN
        v_n := v_n + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'admin_notify_branch_gate_code %: %', r.id, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'count', v_n, 'notified', CASE WHEN p_dry_run THEN 0 ELSE v_n END);
END $$;

REVOKE ALL ON FUNCTION public.admin_notify_branch_gate_code(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_notify_branch_gate_code(uuid, boolean) TO authenticated, service_role;

-- 2) trigger na admin_messages: mail s kódy pro rezervaci ZE ZPRÁVY, jinak jako dřív nejnovější
CREATE OR REPLACE FUNCTION public.trg_email_on_door_codes_message()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_booking_id uuid;
BEGIN
  IF NEW.type IS DISTINCT FROM 'door_codes' THEN
    RETURN NEW;
  END IF;

  -- Přednostně rezervace uvedená ve zprávě (ruční uvolnění / dopo­slání z Velína,
  -- regenerace) — musí patřit uživateli, být aktivní a mít vydané kódy.
  IF NEW.booking_id IS NOT NULL THEN
    SELECT b.id INTO v_booking_id
      FROM bookings b
     WHERE b.id = NEW.booking_id
       AND b.user_id = NEW.user_id
       AND b.status IN ('active', 'reserved')
       AND EXISTS (SELECT 1 FROM branch_door_codes bdc
                    WHERE bdc.booking_id = b.id AND bdc.is_active = true AND bdc.sent_to_customer = true);
  END IF;

  -- Jinak (zpráva bez booking_id) nejnovější aktivní rezervace s uvolněnými kódy — původní chování
  IF v_booking_id IS NULL THEN
    SELECT b.id INTO v_booking_id
      FROM bookings b
     WHERE b.user_id = NEW.user_id
       AND b.status IN ('active', 'reserved')
       AND EXISTS (SELECT 1 FROM branch_door_codes bdc
                    WHERE bdc.booking_id = b.id AND bdc.is_active = true AND bdc.sent_to_customer = true)
     ORDER BY b.created_at DESC
     LIMIT 1;
  END IF;

  IF v_booking_id IS NOT NULL THEN
    PERFORM send_door_codes_email(v_booking_id, NEW.user_id);
  END IF;

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_email_on_door_codes_message failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.trg_email_on_door_codes_message() IS 'Při insertu door_codes admin_message pošle email s kódy (idempotentní přes message_log dedup). Od 2026-10-04 přednostně pro NEW.booking_id, jinak nejnovější aktivní rezervace uživatele.';

-- 3) šablony z Velína — jen cílená náhrada věty
DO $$
DECLARE
  r record;
  v_locker_old constant text := 'Pokud s sebou budete mít osobní věci, které nechcete brát na cestu, můžete je u nás zdarma uložit do uzamykatelné skříňky.';
  v_locker_new constant text := 'Osobní věci, které nechcete brát na cestu, si na obslužné pobočce v Mezné můžete zdarma uložit do uzamykatelné skříňky.';
  v_md_old constant text := 'Abychom vám mohli předat motorku a poslat přístupové kódy, potřebujeme ještě ověřit vaše doklady';
  v_md_new constant text := 'Abychom vám mohli vydat přístupové kódy k motorce, potřebujeme ještě ověřit vaše doklady';
BEGIN
  FOR r IN SELECT slug, body_html FROM public.email_templates WHERE slug IN ('booking_reserved', 'web_booking_reserved') LOOP
    IF position(v_locker_old IN r.body_html) > 0 THEN
      UPDATE public.email_templates
         SET body_html = replace(body_html, v_locker_old, v_locker_new),
             body_translations = '{}'::jsonb, updated_at = now()
       WHERE slug = r.slug;
      RAISE NOTICE '20261004h: % — věta o skříňce upřesněna na obslužnou pobočku', r.slug;
    END IF;
  END LOOP;
  FOR r IN SELECT slug, body_html FROM public.email_templates WHERE slug IN ('booking_missing_docs', 'web_booking_missing_docs') LOOP
    IF position(v_md_old IN r.body_html) > 0 THEN
      UPDATE public.email_templates
         SET body_html = replace(body_html, v_md_old, v_md_new),
             body_translations = '{}'::jsonb, updated_at = now()
       WHERE slug = r.slug;
      RAISE NOTICE '20261004h: % — „předat motorku“ → „vydat přístupové kódy“', r.slug;
    END IF;
  END LOOP;
END $$;

-- 4) Web CMS (jen existující řádky s původním textem; value = jsonb string)
DO $$
DECLARE
  v_pairs constant text[][] := ARRAY[
    ['web.layout.confirm.success.nextBookingDocsMissing', 'Doklady zatím nejsou ověřené — můžeš je ověřit dodatečně v úpravě rezervace (foto OP/pasu + ŘP) nebo osobně při vyzvednutí. Bez ověření ti nepošleme přístupové kódy předem; půjčíme motorku po kontrole dokladů na pobočce.', 'Doklady zatím nejsou ověřené — ověř je dodatečně v úpravě rezervace (foto OP/pasu + ŘP). Bez ověření ti nepošleme přístupové kódy: na samoobslužné pobočce se bez nich dovnitř nedostaneš, na obslužné pobočce doklady zkontrolujeme při převzetí na místě.'],
    ['web.layout.confirm.success.nextBookingDocsMissing', 'Doklady zatím nejsou ověřené — můžeš je ověřit dodatečně v úpravě rezervace (foto OP/pasu + ŘP) nebo osobně při vyzvednutí.', 'Doklady zatím nejsou ověřené — ověř je dodatečně v úpravě rezervace (foto OP/pasu + ŘP). Bez ověření ti nepošleme přístupové kódy: na samoobslužné pobočce se bez nich dovnitř nedostaneš, na obslužné pobočce doklady zkontrolujeme při převzetí na místě.'],
    ['web.layout.rez.gear.intro', 'Pokud velikost nezvolíte, vyzkoušíme ji na místě.', 'Pokud velikost nezvolíte, vyzkoušíte ji na místě.']
  ];
  i integer;
  v_val text;
BEGIN
  FOR i IN 1..array_length(v_pairs, 1) LOOP
    SELECT value #>> '{}' INTO v_val FROM public.cms_variables
     WHERE key = v_pairs[i][1] AND jsonb_typeof(value) = 'string';
    IF v_val IS NOT NULL AND position(v_pairs[i][2] IN v_val) > 0 THEN
      UPDATE public.cms_variables
         SET value = to_jsonb(replace(v_val, v_pairs[i][2], v_pairs[i][3])), updated_at = now()
       WHERE key = v_pairs[i][1];
      RAISE NOTICE '20261004h: cms_variables % — text sjednocen pro obě pobočky', v_pairs[i][1];
    END IF;
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
