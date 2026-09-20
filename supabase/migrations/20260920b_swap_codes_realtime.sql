-- ============================================================================
-- VÝMĚNA MOTORKY — KÓDY V REÁLNÉM ČASE (zadání uživatele 2026-09-20)
--
-- Stav PŘED touto migrací:
--   • Výměna PŘED vyzvednutím (a výměna k datu začátku) funguje real-time:
--     `trg_regen_codes_on_moto_change` → `regen_door_codes_for_booking()`
--     zneplatní staré kódy, vydá dva nové na pobočce NOVÉ motorky a hned je
--     pošle (in-app zpráva + push, SMS, WhatsApp, e-mail); jednotka dostane
--     přes `trg_door_codes_kiosk_sync` → `kiosk_request_sync` realtime příkaz
--     `sync_config`, a online ověření kódu čte DB živě → platí okamžitě.
--   • Výměna UPROSTŘED pronájmu (handoff/split: vzniká navazující rezervace B
--     se `continues_booking_id`) na SAMOOBSLUŽNÉ pobočce ale real-time NENÍ:
--     `withhold_swap_next_codes` kódy k nové motorce zadrží s důvodem
--     „Vraťte nejdřív původní motorku" a uvolní je až `trg_release_swap_next_codes`
--     při `returned_at`/`completed`. Jenže `returned_at` na samoobslužné pobočce
--     v reálném čase NIKDO nenastaví — box pojem „vrácení" nemá a jediné cesty
--     jsou noční cron `auto_complete_expired_bookings` (00:01) nebo ruční zásah
--     ve Velíně. Zákazník tedy vrátí starou motorku do kóje a na kód k nové
--     čeká do půlnoci.
--
-- Tato migrace:
--   1) ZAVŘENÍ KÓJE původní motorky (DOOR_CLOSED / SESSION_COMPLETED z jednotky)
--      při čekající výměně = vrácení → nastaví `bookings.returned_at`, čímž
--      existující trigger OKAMŽITĚ uvolní kódy k nové motorce.
--   2) Uvolnění kódů při výměně nově notifikuje stejně jako jejich vydání:
--      in-app zpráva (+ push) a SMS/WhatsApp, ne jen e-mail — zákazník stojí
--      u kóje a potřebuje kód hned. Zpráva obsahuje i POBOČKU a KÓJI.
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────
-- 1) Zavření kóje staré motorky = vrácení (jen když se čeká na výměnu)
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._swap_handoff_return_on_door_close()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_event text := COALESCE(NEW.detail->>'event', '');
  v_next  uuid;
BEGIN
  IF NEW.booking_id IS NULL OR NEW.success IS NOT TRUE OR NEW.kind <> 'motorcycle' THEN
    RETURN NULL;
  END IF;
  -- Relace u kóje skončila zavřením dveří (motorka je uvnitř).
  IF v_event NOT IN ('DOOR_CLOSED', 'SESSION_COMPLETED') THEN
    RETURN NULL;
  END IF;

  -- Jen když na TUHLE rezervaci navazuje výměna motorky, jejíž kódy čekají na
  -- vrácení původního stroje. Mimo tenhle stav se zavření kóje nijak neprojeví
  -- (zákazník si jen něco bere z motorky).
  SELECT b.id INTO v_next
    FROM bookings b
    JOIN branch_door_codes c
      ON c.booking_id = b.id
     AND c.is_active = true
     AND c.withheld_reason = 'Vraťte nejdřív původní motorku'
   WHERE b.continues_booking_id = NEW.booking_id
     AND b.status IN ('pending', 'reserved', 'active')
   LIMIT 1;

  IF v_next IS NULL THEN RETURN NULL; END IF;

  -- Zapíše vrácení → trg_release_swap_next_codes okamžitě uvolní kódy k nové
  -- motorce (status rezervace nechává na standardním flow / Velínu).
  UPDATE bookings
     SET returned_at = now()
   WHERE id = NEW.booking_id
     AND returned_at IS NULL;

  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '_swap_handoff_return_on_door_close failed for booking %: %', NEW.booking_id, SQLERRM;
  RETURN NULL;
END; $$;

DROP TRIGGER IF EXISTS trg_swap_handoff_return_on_door_close ON public.branch_door_events;
CREATE TRIGGER trg_swap_handoff_return_on_door_close
  AFTER INSERT ON public.branch_door_events
  FOR EACH ROW EXECUTE FUNCTION public._swap_handoff_return_on_door_close();

-- ─────────────────────────────────────────────────────────────────────────
-- 2) Uvolněné kódy k nové motorce pošli VŠEMI kanály (parita s vydáním kódů)
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.release_swap_next_codes()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  r            record;
  v_released   int;
  v_code_moto  text;
  v_code_gear  text;
  v_branch     text;
  v_box        integer;
  v_phone      text;
  v_lang       text;
  v_start      date;
  v_end        date;
BEGIN
  FOR r IN
    SELECT b.id AS booking_id, b.user_id,
           -- Doklady se musí ověřit ZNOVU: `withhold_swap_next_codes` (BEFORE INSERT)
           -- přepsal případný důvod „Chybí doklady" svým „Vraťte nejdřív původní
           -- motorku", takže bez téhle kontroly by se kód uvolnil i zákazníkovi
           -- s chybějícím / propadlým dokladem.
           CASE WHEN m.license_required::text = 'N' THEN NULL
                ELSE check_booking_docs_status(b.user_id, b.end_date::date, b.moto_id) END AS docs_reason
      FROM bookings b
      LEFT JOIN motorcycles m ON m.id = b.moto_id
     WHERE b.continues_booking_id = NEW.id
       AND b.status IN ('reserved','active','pending')
  LOOP
    IF r.docs_reason IS NOT NULL THEN
      -- Motorka je vrácená, ale kód drží doklady → přepiš důvod, ať zákazník
      -- i Velín vidí, na čem to stojí (appka ho ukazuje místo kódu; uvolní ho
      -- pak standardní doklad-flow — nahrání dokladu kódy pustí automaticky).
      UPDATE branch_door_codes
         SET withheld_reason = r.docs_reason
       WHERE booking_id = r.booking_id AND is_active = true
         AND withheld_reason = 'Vraťte nejdřív původní motorku';
      -- Zákazník stojí u kóje a čeká na kód — řekni mu rovnou, PROČ nepřišel
      -- a co s tím (bez tohohle by jen koukal na prázdné místo po kódu).
      BEGIN
        INSERT INTO admin_messages (user_id, booking_id, type, title, message)
        VALUES (r.user_id, r.booking_id, 'info', 'Kód k nové motorce zatím držíme',
          'Původní motorku máme vrácenou, ale kód k nové zatím nemůžeme vydat: ' || r.docs_reason || E'\n' ||
          'Nahrajte prosím doklad v aplikaci (Profil → Dokumenty) — kód se uvolní automaticky hned po nahrání.');
      EXCEPTION WHEN OTHERS THEN NULL; END;
      CONTINUE;
    END IF;

    UPDATE branch_door_codes
       SET sent_to_customer = true, sent_at = now(), withheld_reason = NULL
     WHERE booking_id = r.booking_id AND is_active = true
       AND withheld_reason = 'Vraťte nejdřív původní motorku';
    GET DIAGNOSTICS v_released = ROW_COUNT;
    IF v_released = 0 THEN CONTINUE; END IF;

    SELECT door_code INTO v_code_moto FROM branch_door_codes
     WHERE booking_id = r.booking_id AND code_type = 'motorcycle' AND is_active = true LIMIT 1;
    SELECT door_code INTO v_code_gear FROM branch_door_codes
     WHERE booking_id = r.booking_id AND code_type = 'accessories' AND is_active = true LIMIT 1;
    SELECT br.name, m.box_number, b.start_date::date, b.end_date::date
      INTO v_branch, v_box, v_start, v_end
      FROM bookings b
      LEFT JOIN motorcycles m ON m.id = b.moto_id
      LEFT JOIN branches br   ON br.id = m.branch_id
     WHERE b.id = r.booking_id;

    -- a) in-app zpráva (+ push přes trg_push_on_admin_message) — zákazník stojí
    --    u kóje, e-mail sám o sobě nestačí
    BEGIN
      INSERT INTO admin_messages (user_id, title, message, type)
      VALUES (r.user_id, 'Nové přístupové kódy',
        'Původní motorka je vrácená — tady jsou kódy k nové:' || E'\n' ||
        'Kód k motorce: ' || COALESCE(v_code_moto, '—') || E'\n' ||
        'Kód k příslušenství: ' || COALESCE(v_code_gear, '—') || E'\n' ||
        'Kódy jsou platné (' || TO_CHAR(v_start, 'DD.MM.YYYY') || ' – ' || TO_CHAR(v_end, 'DD.MM.YYYY') || ').' ||
        CASE WHEN v_branch IS NOT NULL THEN E'\nPobočka: ' || v_branch ELSE '' END ||
        CASE WHEN v_box IS NOT NULL AND v_box > 0 THEN E'\nKóje: ' || v_box ELSE '' END,
        'door_codes');
    EXCEPTION WHEN OTHERS THEN NULL; END;

    -- b) SMS + WhatsApp (stejně jako při vydání kódů)
    BEGIN
      SELECT phone, COALESCE(language, 'cs') INTO v_phone, v_lang FROM profiles WHERE id = r.user_id;
      IF v_phone IS NOT NULL AND v_phone <> '' AND v_code_moto IS NOT NULL THEN
        PERFORM send_sms_and_wa(v_phone, 'door_codes',
          jsonb_build_object(
            'booking_number', upper(left(r.booking_id::text, 8)),
            'door_code_moto', v_code_moto,
            'door_code_gear', COALESCE(v_code_gear, '')
          ), r.user_id, r.booking_id, COALESCE(v_lang, 'cs'));
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL; END;

    -- c) e-mail (beze změny; dedup GUC brání dvojímu odeslání)
    BEGIN PERFORM send_door_codes_email(r.booking_id, r.user_id); EXCEPTION WHEN OTHERS THEN NULL; END;
  END LOOP;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'release_swap_next_codes failed: %', SQLERRM;
  RETURN NEW;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────
-- 3) Nahrání dokladů NESMÍ uvolnit kódy zadržené kvůli nevrácené motorce
-- ─────────────────────────────────────────────────────────────────────────
-- Živý bug: `release_withheld_door_codes_for_user` (volá ji trigger při nahrání
-- dokladu i tlačítko „Uvolnit kódy" v appce) uvolňovala VŠECHNY zadržené kódy
-- zákazníka, jakmile byly doklady v pořádku — tedy i ty, které drží výměna
-- motorky („Vraťte nejdřív původní motorku"). Zákazník uprostřed výměny tak
-- mohl mít otevřené obě kóje a držet dvě motorky zároveň.
-- Tělo je 1:1 živá funkce + dvě podmínky, které swap-hold nechají být.
CREATE OR REPLACE FUNCTION public.release_withheld_door_codes_for_user(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_booking record;
  v_withheld text;
  v_code_moto text;
  v_code_gear text;
  v_phone text;
  v_released int;
BEGIN
  IF p_user_id IS NULL THEN RETURN; END IF;

  FOR v_booking IN
    SELECT DISTINCT b.id AS booking_id, b.user_id, b.start_date, b.end_date
    FROM bookings b
    JOIN branch_door_codes bdc ON bdc.booking_id = b.id
    WHERE b.user_id = p_user_id
      AND b.status IN ('reserved','active')   -- POJISTKA: jen aktivní/nadcházející rezervace
      AND bdc.is_active = true
      AND bdc.sent_to_customer = false
      -- NOVÉ: kódy držené kvůli nevrácené původní motorce sem nepatří —
      -- ty uvolní až vrácení stroje (trg_release_swap_next_codes).
      AND bdc.withheld_reason IS DISTINCT FROM 'Vraťte nejdřív původní motorku'
  LOOP
    v_withheld := check_booking_docs_status(v_booking.user_id, v_booking.end_date::date);
    IF v_withheld IS NOT NULL THEN
      -- Aktualizuj jen důvod (třeba z "Chybí doklady" na "ŘP propadlý")
      UPDATE branch_door_codes
      SET withheld_reason = v_withheld
      WHERE booking_id = v_booking.booking_id
        AND is_active = true
        AND sent_to_customer = false
        AND withheld_reason IS DISTINCT FROM 'Vraťte nejdřív původní motorku'
        AND withheld_reason IS DISTINCT FROM v_withheld;
      CONTINUE; -- neuvolňujeme
    END IF;

    -- Uvolni (kromě kódů čekajících na vrácení původní motorky)
    UPDATE branch_door_codes
    SET sent_to_customer = true, sent_at = NOW(), withheld_reason = NULL
    WHERE booking_id = v_booking.booking_id
      AND is_active = true
      AND sent_to_customer = false
      AND withheld_reason IS DISTINCT FROM 'Vraťte nejdřív původní motorku';
    GET DIAGNOSTICS v_released = ROW_COUNT;
    IF v_released = 0 THEN CONTINUE; END IF;

    SELECT door_code INTO v_code_moto FROM branch_door_codes
     WHERE booking_id = v_booking.booking_id AND code_type = 'motorcycle' AND is_active = true LIMIT 1;
    SELECT door_code INTO v_code_gear FROM branch_door_codes
     WHERE booking_id = v_booking.booking_id AND code_type = 'accessories' AND is_active = true LIMIT 1;

    BEGIN
      INSERT INTO admin_messages (user_id, title, message, type)
      VALUES (
        v_booking.user_id,
        'Přístupové kódy k pobočce',
        'Kód k motorce: ' || COALESCE(v_code_moto,'–') || E'\n' ||
        'Kód k příslušenství: ' || COALESCE(v_code_gear,'–') || E'\n' ||
        'Kódy jsou platné po dobu trvání pronájmu (' ||
        TO_CHAR(v_booking.start_date::date,'DD.MM.YYYY') || ' – ' ||
        TO_CHAR(v_booking.end_date::date,'DD.MM.YYYY') || ').',
        'door_codes'
      );
    EXCEPTION WHEN OTHERS THEN NULL; END;

    BEGIN
      SELECT phone INTO v_phone FROM profiles WHERE id = v_booking.user_id;
      IF v_phone IS NOT NULL AND v_phone <> '' THEN
        PERFORM send_sms_and_wa(v_phone, 'door_codes',
          jsonb_build_object(
            'booking_number', upper(left(v_booking.booking_id::text,8)),
            'door_code_moto', COALESCE(v_code_moto,'–'),
            'door_code_gear', COALESCE(v_code_gear,'–')
          ), v_booking.user_id, v_booking.booking_id);
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL; END;

    PERFORM send_door_codes_email(v_booking.booking_id, v_booking.user_id);
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'release_withheld_door_codes_for_user failed: %', SQLERRM;
END;
$$;

COMMENT ON FUNCTION public.release_withheld_door_codes_for_user(uuid) IS
  'Uvolní kódy zadržené kvůli dokladům; kódy čekající na vrácení původní motorky (výměna) nechává být (2026-09-20).';

COMMENT ON FUNCTION public._swap_handoff_return_on_door_close() IS
  'Zavření kóje původní motorky při čekající výměně = vrácení → uvolní kódy k nové motorce v reálném čase (2026-09-20).';
COMMENT ON FUNCTION public.release_swap_next_codes() IS
  'Uvolnění zadržených kódů po vrácení původní motorky — nově i in-app zpráva (push) a SMS/WhatsApp, vč. pobočky a kóje (2026-09-20).';
