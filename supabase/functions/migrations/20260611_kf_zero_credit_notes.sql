-- =============================================================================
-- MIGRACE 2026-06-11: KF (konečná faktura) musí vyjít 0 Kč i po refundu —
--                     přičtení dobropisů (credit_note) do rozpisu KF
--
-- Kontext (reportováno zákazníkem + analýza):
--   Úprava rezervace s doplatkem nebo vratkou musí mít kompletní doklady:
--     - doplatek přes bránu → rozdílový DP (source='edit') — řeší edge fn
--       generate-invoice (param `price_difference`) + send-booking-email
--     - vratka → částečný dobropis + Stripe refund — řeší process-refund
--   KF při dokončení rezervace odečítá VŠECHNY DP (původní + rozdílové z úprav),
--   ale dobropisy dosud IGNOROVALA → po úpravě s vratkou vycházela KF záporně
--   (např. −500 Kč) a assertion „KF total != 0" se logovala při každém dokončení.
--
-- Matematika KF po této migraci:
--   Σ(služby v aktuální ceně) − Σ(DP) + Σ|dobropis| = 0
--   - doplatek: new_total − (DP_orig + DP_edit) = 0
--   - vratka:   new_total − DP_orig + |CN| = 0
--
-- Změny proti živé verzi (2026-05-13):
--   1) Nový blok „Vráceno dobropisem DB-…" — kladné řádky za každý nezrušený
--      credit_note k rezervaci (total dobropisu je záporný → unit_price = -total).
--   2) Debug payload assertion rozšířen o sum_credit_notes.
--   3) KF guard payment_status rozšířen z `= 'paid'` na IN ('paid',
--      'partial_refund', 'refund_pending') — rezervace po rozdílové úpravě
--      s vratkou má payment_status='partial_refund' a KF (i poděkovací mail,
--      který visí na INSERTu KF) by jinak NIKDY nevznikla.
--   4) auto_complete_expired_bookings() — stejné rozšíření filtru; rezervace
--      ve stavu partial_refund/refund_pending se jinak nikdy neauto-dokončila
--      (zůstávala navždy active).
--   Promo INSERT zachovává reálné sloupce (value/active) z fixu 2026-05-13.
-- =============================================================================

-- 1) Auto-complete: pusť i rezervace po částečném refundu (úprava s vratkou)
CREATE OR REPLACE FUNCTION auto_complete_expired_bookings()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE bookings
  SET status = 'completed'::booking_status,
      returned_at = NOW()
  WHERE status IN ('active', 'reserved')
    AND end_date < CURRENT_DATE
    AND payment_status IN ('paid', 'partial_refund', 'refund_pending');
END;
$$;

-- 2) KF trigger funkce — dobropisy + rozšířený payment_status guard

CREATE OR REPLACE FUNCTION generate_final_invoice_on_complete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_inv_num text;
  v_seq int;
  v_year int := EXTRACT(YEAR FROM CURRENT_DATE)::int;
  v_items jsonb;
  v_total numeric;
  v_moto_model text;
  v_moto_spz text;
  v_base_rental numeric;
  v_extras numeric;
  v_delivery numeric;
  v_discount numeric;
  v_discount_code text;
  v_booking_short text;
  v_promo_code text;
BEGIN
  IF OLD.status != 'active' OR NEW.status != 'completed' THEN RETURN NEW; END IF;
  IF EXISTS (SELECT 1 FROM invoices WHERE booking_id = NEW.id AND type = 'final') THEN RETURN NEW; END IF;
  IF NEW.payment_status NOT IN ('paid', 'partial_refund', 'refund_pending') THEN RETURN NEW; END IF;
  IF NEW.sos_replacement = true THEN
    RAISE NOTICE 'Skipping KF for SOS replacement booking %', NEW.id;
    RETURN NEW;
  END IF;

  SELECT model, spz INTO v_moto_model, v_moto_spz FROM motorcycles WHERE id = NEW.moto_id;

  SELECT COALESCE(MAX(CAST(SUBSTRING(number FROM '-(\d+)$') AS int)), 0) + 1
    INTO v_seq FROM invoices WHERE number LIKE 'KF-' || v_year || '-%';
  v_inv_num := 'KF-' || v_year || '-' || LPAD(v_seq::text, 4, '0');

  v_extras   := COALESCE(NEW.extras_price, 0);
  v_delivery := COALESCE(NEW.delivery_fee, 0);
  v_discount := COALESCE(NEW.discount_amount, 0);
  v_discount_code := COALESCE(NEW.discount_code, '');
  v_base_rental := COALESCE(NEW.total_price, 0) - v_extras - v_delivery + v_discount;

  v_items := jsonb_build_array(jsonb_build_object(
    'description', 'Pronájem ' || COALESCE(v_moto_model, 'motorky') ||
      ' (' || COALESCE(v_moto_spz, '') || ') — ' ||
      TO_CHAR(NEW.start_date, 'DD.MM.YYYY') || ' – ' || TO_CHAR(NEW.end_date, 'DD.MM.YYYY'),
    'qty', 1, 'unit_price', v_base_rental
  ));

  IF v_extras > 0 THEN
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'description', 'Příslušenství a výbava', 'qty', 1, 'unit_price', v_extras));
  END IF;

  IF v_delivery > 0 THEN
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'description', 'Přistavení / odvoz motorky', 'qty', 1, 'unit_price', v_delivery));
  END IF;

  IF v_discount > 0 THEN
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'description', CASE WHEN v_discount_code <> '' THEN 'Sleva (kód: ' || v_discount_code || ')'
                          ELSE 'Sleva / voucher' END,
      'qty', 1, 'unit_price', -v_discount));
  END IF;

  -- Odpočet všech přijatých plateb (DP) — původní platba i rozdílové DP z úprav
  v_items := v_items || COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'description', 'Odpočet dle DP ' || number, 'qty', 1, 'unit_price', -total))
    FROM invoices WHERE booking_id = NEW.id AND type = 'payment_receipt' AND status != 'cancelled'
  ), '[]'::jsonb);

  -- NOVÉ 2026-06-11: přičtení vrácených peněz (dobropisy z úprav / částečných refundů).
  -- total dobropisu je ZÁPORNÝ → -total = kladný řádek „vráceno zákazníkovi".
  -- Bez tohoto bloku KF po úpravě s vratkou vycházela záporně (−|refund|).
  v_items := v_items || COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'description', 'Vráceno dobropisem ' || number, 'qty', 1, 'unit_price', -total))
    FROM invoices WHERE booking_id = NEW.id AND type = 'credit_note' AND status != 'cancelled'
  ), '[]'::jsonb);

  v_total := (SELECT SUM((item->>'unit_price')::numeric * (item->>'qty')::numeric)
              FROM jsonb_array_elements(v_items) AS item);

  -- KF musí být MATEMATICKY vždy 0 Kč. Pokud ne, log warning pro účetní.
  IF ROUND(v_total::numeric, 2) <> 0 THEN
    INSERT INTO debug_log (source, action, component, status, error_message, request_data)
    VALUES (
      'generate_final_invoice_on_complete', 'kf_total_not_zero', 'KF assertion', 'warning',
      'KF total != 0 (booking: ' || NEW.id || ', total: ' || v_total || ' Kč) — chybí DP/dobropis pro plné pokrytí?',
      jsonb_build_object(
        'booking_id', NEW.id, 'kf_number', v_inv_num, 'computed_total', v_total,
        'base_rental', v_base_rental, 'extras', v_extras, 'delivery', v_delivery,
        'discount', v_discount, 'items', v_items,
        'sum_dp', (SELECT COALESCE(SUM(total),0) FROM invoices
                    WHERE booking_id=NEW.id AND type='payment_receipt' AND status!='cancelled'),
        'sum_credit_notes', (SELECT COALESCE(SUM(total),0) FROM invoices
                    WHERE booking_id=NEW.id AND type='credit_note' AND status!='cancelled')
      )
    );
    RAISE WARNING 'KF % pro booking % má total=% Kč (očekáváno 0). Zaloggováno do debug_log.',
      v_inv_num, NEW.id, v_total;
  END IF;

  -- Slevový kód VRACENI-{booking_short} (200 Kč / 1 rok / 1× použití)
  -- Sloupce value/active dle reálného schématu promo_codes (fix 2026-05-13).
  v_booking_short := UPPER(RIGHT(REPLACE(NEW.id::text, '-', ''), 8));
  v_promo_code    := 'VRACENI-' || v_booking_short;

  INSERT INTO promo_codes (code, type, value, active, valid_from, valid_to, max_uses, used_count)
  VALUES (
    v_promo_code, 'fixed', 200, true,
    now(), (CURRENT_DATE + INTERVAL '1 year')::timestamptz,
    1, 0
  )
  ON CONFLICT (code) DO NOTHING;

  INSERT INTO invoices (
    number, type, customer_id, booking_id, items, subtotal, tax_amount, total,
    issue_date, due_date, status, variable_symbol, source
  )
  VALUES (
    v_inv_num, 'final', NEW.user_id, NEW.id, v_items, v_total, 0, v_total,
    CURRENT_DATE, CURRENT_DATE, 'paid', v_inv_num, 'final_summary'
  );

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'generate_final_invoice_on_complete failed for booking %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;
