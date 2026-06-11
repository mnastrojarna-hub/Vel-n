-- ════════════════════════════════════════════════════════════════════
-- VĚRNOSTNÍ RANKY — slevy 1–20 % JEN pro rezervace v aplikaci
-- (booking_source='app'). 20 levelů, level = % slevy.
-- Aplikováno v živé DB 2026-06-11 (potvrzeno adminem).
-- ════════════════════════════════════════════════════════════════════

-- 1) Tabulka levelů (názvy/barvy editovatelné bez release appky)
CREATE TABLE IF NOT EXISTS loyalty_levels (
  level int PRIMARY KEY CHECK (level BETWEEN 1 AND 20),
  discount_percent int NOT NULL,
  min_booking_order int NOT NULL,   -- od kolikáté app rezervace platí
  name text NOT NULL,
  color_hex text NOT NULL,
  translations jsonb NOT NULL DEFAULT '{}'
);
ALTER TABLE loyalty_levels ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public read" ON loyalty_levels FOR SELECT USING (true);
CREATE POLICY "Admin write" ON loyalty_levels FOR ALL USING (is_admin());

INSERT INTO loyalty_levels (level, discount_percent, min_booking_order, name, color_hex) VALUES
 (1,1,1,'Startér','#9CA3AF'),(2,2,3,'Jezdec','#86EFAC'),(3,3,5,'Motorkář','#4ADE80'),
 (4,4,7,'Stálý jezdec','#22C55E'),(5,5,9,'Věrný zákazník','#14B8A6'),
 (6,6,11,'Bronzový jezdec','#CD7F32'),(7,7,13,'Stříbrný jezdec','#C0C0C0'),
 (8,8,15,'Zlatý jezdec','#FFD700'),(9,9,17,'Platinový jezdec','#E5E4E2'),
 (10,10,19,'Diamantový jezdec','#7DD3FC'),(11,11,21,'Prémiový zákazník','#38BDF8'),
 (12,12,23,'Mistr silnic','#3B82F6'),(13,13,25,'Šampion','#6366F1'),
 (14,14,27,'Veterán MotoGo','#8B5CF6'),(15,15,29,'Elitní jezdec','#A855F7'),
 (16,16,31,'Ambasador','#D946EF'),(17,17,33,'VIP','#EF4444'),
 (18,18,35,'VIP Gold','#D4AF37'),(19,19,37,'VIP Platinum','#F1F5F9'),
 (20,20,39,'Legenda MotoGo','#FFD700')
ON CONFLICT (level) DO NOTHING;

-- 2) Sloupce na bookings (oddělené od promo/voucher discount_amount)
ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS loyalty_level int,
  ADD COLUMN IF NOT EXISTS loyalty_percent int,
  ADD COLUMN IF NOT EXISTS loyalty_discount_amount numeric DEFAULT 0;

-- 3) Helper: počet kvalifikačních rezervací (dokončené app rezervace)
CREATE OR REPLACE FUNCTION _loyalty_qualifying_count(p_user_id uuid)
RETURNS int LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COUNT(*)::int FROM bookings
  WHERE user_id = p_user_id AND booking_source = 'app' AND status = 'completed';
$$;
REVOKE ALL ON FUNCTION _loyalty_qualifying_count(uuid) FROM PUBLIC, anon, authenticated;

-- 4) RPC pro appku: aktuální rank + progress do dalšího
-- Vzorec: pořadí příští rezervace = count+1; % = min(20, ceil(pořadí/2))
CREATE OR REPLACE FUNCTION get_loyalty_status()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_cnt int; v_pct int;
  v_cur loyalty_levels%ROWTYPE; v_next loyalty_levels%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'unauthenticated'); END IF;
  v_cnt := _loyalty_qualifying_count(v_uid);
  v_pct := LEAST(20, CEIL((v_cnt + 1) / 2.0))::int;
  SELECT * INTO v_cur  FROM loyalty_levels WHERE level = v_pct;
  SELECT * INTO v_next FROM loyalty_levels WHERE level = v_pct + 1;
  RETURN jsonb_build_object(
    'level', v_pct,
    'percent', COALESCE(v_cur.discount_percent, v_pct),
    'rank_name', COALESCE(v_cur.name, 'Startér'),
    'color_hex', COALESCE(v_cur.color_hex, '#9CA3AF'),
    'qualifying_count', v_cnt,
    'max_level', 20,
    'next_rank_name', v_next.name,
    'next_percent', v_next.discount_percent,
    'next_color_hex', v_next.color_hex,
    'bookings_to_next', CASE WHEN v_pct >= 20 THEN NULL ELSE 2 * v_pct - v_cnt END
  );
END; $$;
REVOKE ALL ON FUNCTION get_loyalty_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_loyalty_status() TO authenticated;

-- 5) Server-side guard: klientovi se nevěří — BEFORE INSERT přepočet/ořez.
-- Web/admin rezervace věrnostní slevu NIKDY nedostanou (jen app).
CREATE OR REPLACE FUNCTION validate_app_loyalty_discount()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cnt int; v_pct int; v_base numeric; v_max numeric;
BEGIN
  IF COALESCE(NEW.booking_source, 'app') <> 'app' THEN
    IF COALESCE(NEW.loyalty_discount_amount, 0) > 0 THEN
      NEW.total_price := COALESCE(NEW.total_price, 0) + NEW.loyalty_discount_amount;
    END IF;
    NEW.loyalty_level := NULL; NEW.loyalty_percent := NULL; NEW.loyalty_discount_amount := 0;
    RETURN NEW;
  END IF;
  IF COALESCE(NEW.loyalty_discount_amount, 0) <= 0 THEN RETURN NEW; END IF;

  v_cnt := _loyalty_qualifying_count(NEW.user_id);
  v_pct := LEAST(20, CEIL((v_cnt + 1) / 2.0))::int;
  -- základ = pronájem + příslušenství (total + slevy − přistavení)
  v_base := COALESCE(NEW.total_price,0) + COALESCE(NEW.discount_amount,0)
          + COALESCE(NEW.loyalty_discount_amount,0) - COALESCE(NEW.delivery_fee,0);
  v_max  := ROUND(v_base * v_pct / 100.0);
  IF NEW.loyalty_discount_amount > v_max + 1 OR COALESCE(NEW.loyalty_percent, 0) > v_pct THEN
    NEW.total_price := COALESCE(NEW.total_price,0) + (NEW.loyalty_discount_amount - v_max);
    NEW.loyalty_discount_amount := v_max;
    NEW.loyalty_percent := v_pct;
    NEW.loyalty_level := v_pct;
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'validate_app_loyalty_discount failed: %', SQLERRM;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_validate_app_loyalty ON bookings;
CREATE TRIGGER trg_validate_app_loyalty
  BEFORE INSERT ON bookings FOR EACH ROW
  EXECUTE FUNCTION validate_app_loyalty_discount();

-- 6) KF trigger — věrnostní sleva jako samostatný řádek; brutto pronájmu
-- += loyalty_discount_amount. Matematika KF (Σslužby − ΣDP + Σ|dobropis| = 0) drží.
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
  v_loyalty numeric;
  v_loyalty_pct int;
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
  -- Věrnostní sleva (ranky, jen app rezervace) — oddělená od promo/voucher
  v_loyalty     := COALESCE(NEW.loyalty_discount_amount, 0);
  v_loyalty_pct := COALESCE(NEW.loyalty_percent, 0);
  v_base_rental := COALESCE(NEW.total_price, 0) - v_extras - v_delivery + v_discount + v_loyalty;

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

  -- Řádek věrnostní slevy (jen app rezervace)
  IF v_loyalty > 0 THEN
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'description', 'Věrnostní sleva' ||
        CASE WHEN v_loyalty_pct > 0 THEN ' ' || v_loyalty_pct || ' %' ELSE '' END ||
        ' — rezervace přes aplikaci MotoGo24',
      'qty', 1, 'unit_price', -v_loyalty));
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
        'discount', v_discount, 'loyalty_discount', v_loyalty, 'items', v_items,
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
