-- ============================================================================
-- PŘEVZETÍ MOTORKY = AKTIVACE REZERVACE (zadání uživatele 2026-09-20)
--
-- Pravidlo: „Posunutí termínu je možné kdykoliv, dokud není motorka přebraná.
-- Na samoobslužné pobočce se rezervace překlopí na 'active' zadáním kódu
-- k motorce do Raspberry Pi boxu."
--
-- Dosud rezervaci překlápěl noční cron `auto-activate-reserved` v 00:01 bez
-- ohledu na skutečné převzetí → `reschedule_booking_free` (vyžaduje
-- status='reserved') vracela v den vyzvednutí `wrong_status` a zákazník
-- o bezplatný posun přišel, i když si motorku ještě nevyzvedl.
--
-- Tato migrace:
--   1) okno platnosti přístupových kódů sleduje termín rezervace a pokrývá
--      CELÝ první i poslední den (dosud: valid_until = end_date = 00:00
--      posledního dne → kód byl po celý poslední den pronájmu neplatný
--      a zákazník s ním nemohl otevřít kóji při vracení),
--   2) otevření kóje kódem k MOTORCE překlápí rezervaci reserved → active
--      (+ picked_up_at) — bez zásahu do firmwaru jednotky, přes existující
--      audit `branch_door_events` (zapisuje ho RPC kiosk_log_open),
--   3) noční cron u samoobslužných poboček aktivuje až DEN PO začátku
--      termínu (pojistka pro případ, že signál z jednotky nedorazí),
--   4) bezplatný posun termínu je možný nejpozději v DEN začátku termínu
--      (po něm se nevyzvednutá rezervace řeší stornem dle podmínek),
--   5) denní ops report „zaplaceno, termín běží, nevyzvednuto".
--
-- Obslužné pobočky beze změny: aktivuje je předávací protokol
-- (`_gate_obsluzna_activation`).
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────
-- 1) OKNO PLATNOSTI PŘÍSTUPOVÝCH KÓDŮ
-- ─────────────────────────────────────────────────────────────────────────
-- bookings.start_date/end_date jsou timestamptz, ale klienti posílají čisté
-- datum (= půlnoc UTC). `auto_generate_door_codes` z nich dělá valid_from /
-- valid_until 1:1, takže kód platil od 02:00 prvního dne do 02:00 posledního
-- dne (Praha). `kiosk_resolve_code` i offline resolver v jednotce testují
-- `valid_from <= now() <= valid_until` → poslední den pronájmu kód nefungoval.
CREATE OR REPLACE FUNCTION public._door_code_valid_from(p_start timestamptz)
RETURNS timestamptz
LANGUAGE sql STABLE
SET search_path = public
AS $$
  SELECT ((p_start AT TIME ZONE 'Europe/Prague')::date)::timestamp AT TIME ZONE 'Europe/Prague';
$$;

CREATE OR REPLACE FUNCTION public._door_code_valid_until(p_end timestamptz)
RETURNS timestamptz
LANGUAGE sql STABLE
SET search_path = public
AS $$
  -- konec POSLEDNÍHO dne pronájmu (= půlnoc následujícího dne, Praha)
  SELECT (((p_end AT TIME ZONE 'Europe/Prague')::date + 1)::timestamp AT TIME ZONE 'Europe/Prague');
$$;

-- a) nově vznikající kódy (DB trigger auto_generate_door_codes, regenerace při
--    výměně/přesunu motorky i nouzové generování z Velína) dostanou správné okno
CREATE OR REPLACE FUNCTION public._normalize_door_code_window()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_b bookings%ROWTYPE;
BEGIN
  IF NEW.booking_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO v_b FROM bookings WHERE id = NEW.booking_id;
  IF NOT FOUND THEN RETURN NEW; END IF;
  NEW.valid_from  := public._door_code_valid_from(v_b.start_date);
  NEW.valid_until := public._door_code_valid_until(v_b.end_date);
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '_normalize_door_code_window failed for booking %: %', NEW.booking_id, SQLERRM;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_normalize_door_code_window ON public.branch_door_codes;
CREATE TRIGGER trg_normalize_door_code_window
  BEFORE INSERT ON public.branch_door_codes
  FOR EACH ROW EXECUTE FUNCTION public._normalize_door_code_window();

-- b) posun termínu (RPC, úprava rezervace, Velín přímým UPDATE) posune i okno
--    kódů — dosud je NEaktualizovalo nic, takže po posunu box kód odmítl
CREATE OR REPLACE FUNCTION public.sync_door_code_window()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  UPDATE public.branch_door_codes
     SET valid_from  = public._door_code_valid_from(NEW.start_date),
         valid_until = public._door_code_valid_until(NEW.end_date),
         updated_at  = now()
   WHERE booking_id = NEW.id
     AND is_active = true
     AND (valid_from  IS DISTINCT FROM public._door_code_valid_from(NEW.start_date)
       OR valid_until IS DISTINCT FROM public._door_code_valid_until(NEW.end_date));
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'sync_door_code_window failed for booking %: %', NEW.id, SQLERRM;
  RETURN NULL;
END; $$;

DROP TRIGGER IF EXISTS trg_sync_door_code_window ON public.bookings;
CREATE TRIGGER trg_sync_door_code_window
  AFTER UPDATE OF start_date, end_date ON public.bookings
  FOR EACH ROW
  WHEN (NEW.start_date IS DISTINCT FROM OLD.start_date
     OR NEW.end_date   IS DISTINCT FROM OLD.end_date)
  EXECUTE FUNCTION public.sync_door_code_window();

-- c) jednorázová oprava okna u kódů živých rezervací
--    (UPDATE valid_from/valid_until zároveň přes trg_door_codes_kiosk_sync
--     pošle jednotkám kiosk_request_sync → přepíšou si offline cache)
UPDATE public.branch_door_codes c
   SET valid_from  = public._door_code_valid_from(b.start_date),
       valid_until = public._door_code_valid_until(b.end_date),
       updated_at  = now()
  FROM public.bookings b
 WHERE c.booking_id = b.id
   AND c.is_active = true
   AND b.status IN ('reserved', 'active')
   AND (c.valid_from  IS DISTINCT FROM public._door_code_valid_from(b.start_date)
     OR c.valid_until IS DISTINCT FROM public._door_code_valid_until(b.end_date));

-- ─────────────────────────────────────────────────────────────────────────
-- 2) ZADÁNÍ KÓDU DO BOXU = PŘEVZETÍ MOTORKY → AKTIVACE REZERVACE
-- ─────────────────────────────────────────────────────────────────────────
-- Jednotka volá `kiosk_log_open`, která zapisuje do `branch_door_events`
-- (kind = typ kódu: motorcycle / accessories / service / invalid,
--  detail->>'event' = ACCESS_GRANTED, DOOR_OPENED, …). Otevření ŠATNY,
-- servisní heslo ani neplatný kód převzetí neznamenají.
-- Vrácení motorky se tímto triggerem nedotkne — rezervace je tou dobou
-- už 'active', takže podmínka status='reserved' neprojde.
CREATE OR REPLACE FUNCTION public._activate_booking_on_door_open()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_event text := COALESCE(NEW.detail->>'event', '');
  v_today date := (now() AT TIME ZONE 'Europe/Prague')::date;
BEGIN
  IF NEW.booking_id IS NULL OR NEW.success IS NOT TRUE OR NEW.kind <> 'motorcycle' THEN
    RETURN NULL;
  END IF;
  IF v_event <> '' AND v_event NOT IN ('ACCESS_GRANTED', 'DOOR_OPENED') THEN
    RETURN NULL;
  END IF;

  UPDATE public.bookings b
     SET status       = 'active',
         picked_up_at = COALESCE(b.picked_up_at, now())
   WHERE b.id = NEW.booking_id
     AND b.status = 'reserved'
     AND b.payment_status = 'paid'
     AND (b.start_date AT TIME ZONE 'Europe/Prague')::date <= v_today
     AND (b.end_date   AT TIME ZONE 'Europe/Prague')::date >= v_today;

  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  -- Audit dveří se NIKDY nesmí kvůli aktivaci nezapsat (offline outbox by se
  -- pokoušel donekonečna) — chybu jen zalogujeme.
  RAISE WARNING '_activate_booking_on_door_open failed for booking %: %', NEW.booking_id, SQLERRM;
  RETURN NULL;
END; $$;

DROP TRIGGER IF EXISTS trg_activate_booking_on_door_open ON public.branch_door_events;
CREATE TRIGGER trg_activate_booking_on_door_open
  AFTER INSERT ON public.branch_door_events
  FOR EACH ROW EXECUTE FUNCTION public._activate_booking_on_door_open();

-- ─────────────────────────────────────────────────────────────────────────
-- 3) NOČNÍ CRON — u samoobsluhy až DEN PO začátku termínu (pojistka)
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.auto_activate_reserved_bookings()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  UPDATE bookings b SET
    status = 'active',
    picked_up_at = COALESCE(b.picked_up_at, NOW())
  WHERE b.status = 'reserved'
    AND b.payment_status = 'paid'
    AND b.start_date::date <= CURRENT_DATE
    -- Testovací rezervace se nikdy neaktivují (NEW 2026-08-20)
    AND b.is_test IS NOT TRUE
    -- Obslužné pobočky se aktivují AŽ předávacím protokolem (strážce
    -- _gate_obsluzna_activation), nikoli půlnočním cronem.
    AND NOT EXISTS (
      SELECT 1 FROM motorcycles m
      JOIN branches br ON br.id = m.branch_id
      WHERE m.id = b.moto_id AND br.type = 'obslužná'
    )
    -- Samoobslužné pobočky se aktivují zadáním kódu do boxu (trigger
    -- _activate_booking_on_door_open). Cron je tu jen POJISTKA pro případ,
    -- že signál z jednotky nedorazí (výpadek LTE, ruční výdej obsluhou) —
    -- proto až DEN PO začátku termínu; v den vyzvednutí musí rezervace
    -- zůstat 'reserved', aby šel bezplatný posun termínu.
    AND (
      b.start_date::date < CURRENT_DATE
      OR NOT EXISTS (
        SELECT 1 FROM motorcycles m
        JOIN branches br ON br.id = m.branch_id
        WHERE m.id = b.moto_id AND br.type = 'samoobslužná'
      )
    );
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- 4) BEZPLATNÝ POSUN TERMÍNU — nejpozději v DEN začátku termínu
-- ─────────────────────────────────────────────────────────────────────────
-- Tělo je 1:1 živá funkce (snapshot supabase/_snapshot/schema_public.sql)
-- + JEDINÁ nová kontrola `term_started`: po začátku termínu se nevyzvednutá
-- rezervace řeší stornem dle podmínek, ne bezplatným posunem celé hodnoty.
-- Signatura, SECURITY DEFINER, search_path i GRANTy beze změny (žádný overload).
CREATE OR REPLACE FUNCTION public.reschedule_booking_free(
  p_booking_id uuid,
  p_new_start  date,
  p_new_end    date,
  p_source     text DEFAULT 'web_customer'
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid     uuid := auth.uid();
  v_bk      bookings%ROWTYPE;
  v_today   date := (now() AT TIME ZONE 'Europe/Prague')::date;
  v_hist    jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;

  SELECT * INTO v_bk FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND OR v_bk.user_id <> v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;

  -- Motorka nesmí být převzatá: na samoobslužné pobočce překlápí rezervaci na
  -- 'active' zadání kódu do boxu, na obslužné předávací protokol.
  IF v_bk.status <> 'reserved' THEN
    RETURN jsonb_build_object('success', false, 'error', 'wrong_status');
  END IF;
  IF v_bk.payment_status <> 'paid' THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_paid');
  END IF;

  -- NOVÉ: posun zdarma jen do konce dne začátku termínu.
  IF v_bk.start_date::date < v_today THEN
    RETURN jsonb_build_object('success', false, 'error', 'term_started');
  END IF;

  IF (p_new_end - p_new_start) <> (v_bk.end_date::date - v_bk.start_date::date) THEN
    RETURN jsonb_build_object('success', false, 'error', 'length_mismatch');
  END IF;

  IF p_new_start < v_today THEN
    RETURN jsonb_build_object('success', false, 'error', 'past_date');
  END IF;

  IF p_new_start = v_bk.start_date::date AND p_new_end = v_bk.end_date::date THEN
    RETURN jsonb_build_object('success', false, 'error', 'no_change');
  END IF;

  IF EXISTS (
    SELECT 1 FROM bookings b
     WHERE b.id <> v_bk.id
       AND b.moto_id = v_bk.moto_id
       AND b.status IN ('pending','reserved','active')
       AND b.start_date::date <= p_new_end
       AND b.end_date::date   >= p_new_start
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'moto_overlap');
  END IF;

  IF EXISTS (
    SELECT 1 FROM bookings b
     JOIN motorcycles m ON m.id = b.moto_id
     WHERE b.id <> v_bk.id
       AND b.user_id = v_bk.user_id
       AND b.status IN ('pending','reserved','active')
       AND m.license_required IS DISTINCT FROM 'N'
       AND b.start_date::date <= p_new_end
       AND b.end_date::date   >= p_new_start
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'customer_overlap');
  END IF;

  v_hist := COALESCE(v_bk.modification_history, '[]'::jsonb) || jsonb_build_array(
    jsonb_build_object(
      'at', now(),
      'from_start', v_bk.start_date::date, 'from_end', v_bk.end_date::date,
      'to_start', p_new_start, 'to_end', p_new_end,
      'source', COALESCE(p_source,'web_customer'), 'free_move', true
    )
  );

  UPDATE bookings SET
    start_date           = p_new_start,
    end_date             = p_new_end,
    original_start_date  = COALESCE(original_start_date, v_bk.start_date),
    original_end_date    = COALESCE(original_end_date,   v_bk.end_date),
    modification_history = v_hist
  WHERE id = v_bk.id;

  RETURN jsonb_build_object('success', true, 'new_start', p_new_start, 'new_end', p_new_end, 'free', true);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', 'server_error',
                            'detail', SQLERRM, 'sqlstate', SQLSTATE);
END;
$$;

REVOKE ALL ON FUNCTION public.reschedule_booking_free(uuid, date, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reschedule_booking_free(uuid, date, date, text) TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────
-- 5) DENNÍ OPS REPORT — „zaplaceno, termín běží, nevyzvednuto"
-- ─────────────────────────────────────────────────────────────────────────
-- Pojistka proti ztracenému signálu z jednotky (výpadek LTE, ruční výdej):
-- obsluha vidí, u kterých rezervací systém neví o převzetí.
CREATE OR REPLACE FUNCTION public.report_unpicked_bookings()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows   text := '';
  v_count  int  := 0;
  v_url    text;
  v_key    text;
  v_to     text;
  v_r      record;
BEGIN
  FOR v_r IN
    SELECT b.id, b.start_date::date AS sd, b.end_date::date AS ed,
           COALESCE(m.brand || ' ' || m.model, '?') AS moto,
           COALESCE(br.name, '?') AS branch,
           COALESCE(p.full_name, p.email, '?') AS customer
      FROM bookings b
      LEFT JOIN motorcycles m ON m.id = b.moto_id
      LEFT JOIN branches br   ON br.id = m.branch_id
      LEFT JOIN profiles p    ON p.id = b.user_id
     WHERE b.status = 'reserved'
       AND b.payment_status = 'paid'
       AND b.is_test IS NOT TRUE
       AND b.start_date::date <= CURRENT_DATE
       AND b.end_date::date   >= CURRENT_DATE
     ORDER BY b.start_date
  LOOP
    v_count := v_count + 1;
    v_rows := v_rows || format(
      '<tr><td>#%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s – %s</td></tr>',
      upper(right(v_r.id::text, 8)), v_r.customer, v_r.moto, v_r.branch,
      to_char(v_r.sd, 'DD.MM.YYYY'), to_char(v_r.ed, 'DD.MM.YYYY'));
  END LOOP;

  IF v_count = 0 THEN
    RETURN jsonb_build_object('success', true, 'count', 0);
  END IF;

  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
  SELECT COALESCE(value ->> 'email', 'info@motogo24.cz') INTO v_to FROM app_settings WHERE key = 'company_info';
  v_to := COALESCE(v_to, 'info@motogo24.cz');

  IF v_url IS NOT NULL AND v_key IS NOT NULL THEN
    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-email',
        headers := jsonb_build_object('Content-Type', 'application/json',
                                      'Authorization', 'Bearer ' || v_key),
        body    := jsonb_build_object(
          'to', v_to,
          'subject', format('MotoGo24 — %s nevyzvednutých rezervací (termín běží)', v_count),
          'raw_html', format(
            '<h3>Zaplacené rezervace, u kterých systém neví o převzetí motorky</h3>'
            '<p>Rezervace je pořád „Nadcházející“ — na samoobslužné pobočce ji překlopí zadání kódu do boxu, na obslužné předávací protokol. '
            'Pokud zákazník motorku fyzicky má, srovnejte stav ve Velíně (detail rezervace).</p>'
            '<table border="1" cellpadding="6" cellspacing="0">'
            '<tr><th>Rezervace</th><th>Zákazník</th><th>Motorka</th><th>Pobočka</th><th>Termín</th></tr>%s</table>', v_rows)
        )
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'report_unpicked_bookings: mail se nepodařilo odeslat: %', SQLERRM;
    END;
  END IF;

  RETURN jsonb_build_object('success', true, 'count', v_count);
END;
$$;

-- cron: denně 06:10 Praha (= 04:10 UTC)
DO $$
BEGIN
  PERFORM cron.unschedule('report-unpicked-bookings');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  PERFORM cron.schedule('report-unpicked-bookings', '10 4 * * *',
                        'SELECT public.report_unpicked_bookings()');
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'cron.schedule report-unpicked-bookings selhal (pg_cron nedostupný?): %', SQLERRM;
END $$;

COMMENT ON FUNCTION public._activate_booking_on_door_open() IS
  'Zadání kódu k motorce do boxu = převzetí → bookings.status reserved→active + picked_up_at (2026-09-20).';
COMMENT ON FUNCTION public.sync_door_code_window() IS
  'Posun termínu rezervace posouvá i okno platnosti přístupových kódů (2026-09-20).';
