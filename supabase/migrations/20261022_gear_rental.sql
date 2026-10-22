-- =============================================================================
-- 2026-10-22: Půjčení JEN výbavy (oblečení) bez motorky
-- Web /pujceni-obleceni (vedle dárkových poukazů): termín (od–do), pobočka
-- (Mezná / Velké Němčice), výbava s velikostmi, kontakt → objednávka
-- `shop_orders` (platba Stripe stejnou cestou jako e-shop: process-payment
-- kind=products, cena z DB) + řádek `gear_rentals` (termín, pobočka, položky).
-- Ceník `gear_rental_prices` (kusy + komplety) spravuje Velín → Flotila →
-- Půjčení oblečení; ceny jsou výchozí návrh majitele a mění se tamtéž.
-- Nastavení `app_settings.gear_rental` = {enabled, max_days, max_ahead_days}.
-- Idempotentní: IF NOT EXISTS / CREATE OR REPLACE / ON CONFLICT DO NOTHING.
-- =============================================================================

-- ---- 1) Ceník ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.gear_rental_prices (
  key            text PRIMARY KEY CHECK (key ~ '^[a-z][a-z0-9_]{1,39}$'),
  kind           text NOT NULL DEFAULT 'item' CHECK (kind IN ('item', 'set')),
  label          text NOT NULL CHECK (length(btrim(label)) > 0),
  description    text,
  includes       text[] NOT NULL DEFAULT '{}',
  sizes          text[] NOT NULL DEFAULT '{}',
  price_per_day  numeric(10,2) NOT NULL DEFAULT 0 CHECK (price_per_day >= 0 AND price_per_day <= 100000),
  is_active      boolean NOT NULL DEFAULT true,
  sort_order     integer NOT NULL DEFAULT 0,
  translations   jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  updated_by     uuid,
  CONSTRAINT gear_rental_prices_set_includes CHECK (kind = 'item' OR cardinality(includes) >= 2)
);
COMMENT ON TABLE public.gear_rental_prices IS 'Ceník půjčení výbavy bez motorky (Kč/den). item = kus (velikosti v sizes), set = komplet (includes = klíče kusů; účtuje se, je-li levnější než součet kusů). Velín → Flotila → Půjčení oblečení.';

DROP TRIGGER IF EXISTS trg_gear_rental_prices_touch ON public.gear_rental_prices;
CREATE TRIGGER trg_gear_rental_prices_touch BEFORE UPDATE ON public.gear_rental_prices
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

ALTER TABLE public.gear_rental_prices ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS gear_rental_prices_public_read ON public.gear_rental_prices;
CREATE POLICY gear_rental_prices_public_read ON public.gear_rental_prices
  FOR SELECT USING (is_active OR public.is_admin());
DROP POLICY IF EXISTS gear_rental_prices_admin ON public.gear_rental_prices;
CREATE POLICY gear_rental_prices_admin ON public.gear_rental_prices
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Výchozí ceník (návrh: komplet bez bot ~490 Kč/den, s botami ~890 Kč/den)
INSERT INTO public.gear_rental_prices (key, kind, label, description, includes, sizes, price_per_day, sort_order, translations) VALUES
 ('set_rider', 'set', 'Komplet bez bot', 'Helma, bunda, kalhoty a rukavice', '{helmet,jacket,pants,gloves}', '{}', 490, 1,
  '{"en":{"label":"Full set without boots","description":"Helmet, jacket, trousers and gloves"},"de":{"label":"Komplett ohne Stiefel","description":"Helm, Jacke, Hose und Handschuhe"},"es":{"label":"Equipo completo sin botas","description":"Casco, chaqueta, pantalón y guantes"},"fr":{"label":"Ensemble complet sans bottes","description":"Casque, blouson, pantalon et gants"},"nl":{"label":"Complete set zonder laarzen","description":"Helm, jas, broek en handschoenen"},"pl":{"label":"Komplet bez butów","description":"Kask, kurtka, spodnie i rękawice"},"uk":{"label":"Комплект без чобіт","description":"Шолом, куртка, штани й рукавиці"}}'),
 ('set_rider_boots', 'set', 'Komplet s botami', 'Helma, bunda, kalhoty, rukavice a boty', '{helmet,jacket,pants,gloves,boots}', '{}', 890, 2,
  '{"en":{"label":"Full set with boots","description":"Helmet, jacket, trousers, gloves and boots"},"de":{"label":"Komplett mit Stiefeln","description":"Helm, Jacke, Hose, Handschuhe und Stiefel"},"es":{"label":"Equipo completo con botas","description":"Casco, chaqueta, pantalón, guantes y botas"},"fr":{"label":"Ensemble complet avec bottes","description":"Casque, blouson, pantalon, gants et bottes"},"nl":{"label":"Complete set met laarzen","description":"Helm, jas, broek, handschoenen en laarzen"},"pl":{"label":"Komplet z butami","description":"Kask, kurtka, spodnie, rękawice i buty"},"uk":{"label":"Комплект із чобітьми","description":"Шолом, куртка, штани, рукавиці й чоботи"}}'),
 ('helmet', 'item', 'Helma', NULL, '{}', '{XS,S,M,L,XL,2XL,3XL}', 200, 10,
  '{"en":{"label":"Helmet"},"de":{"label":"Helm"},"es":{"label":"Casco"},"fr":{"label":"Casque"},"nl":{"label":"Helm"},"pl":{"label":"Kask"},"uk":{"label":"Шолом"}}'),
 ('jacket', 'item', 'Bunda', NULL, '{}', '{S,M,L,XL,2XL,3XL,4XL,5XL,6XL}', 200, 20,
  '{"en":{"label":"Jacket"},"de":{"label":"Jacke"},"es":{"label":"Chaqueta"},"fr":{"label":"Blouson"},"nl":{"label":"Jas"},"pl":{"label":"Kurtka"},"uk":{"label":"Куртка"}}'),
 ('pants', 'item', 'Kalhoty', NULL, '{}', '{S,M,L,XL,2XL,3XL,4XL,5XL,6XL}', 150, 30,
  '{"en":{"label":"Trousers"},"de":{"label":"Hose"},"es":{"label":"Pantalón"},"fr":{"label":"Pantalon"},"nl":{"label":"Broek"},"pl":{"label":"Spodnie"},"uk":{"label":"Штани"}}'),
 ('gloves', 'item', 'Rukavice', NULL, '{}', '{S,M,L,XL,2XL,3XL,4XL,5XL}', 80, 40,
  '{"en":{"label":"Gloves"},"de":{"label":"Handschuhe"},"es":{"label":"Guantes"},"fr":{"label":"Gants"},"nl":{"label":"Handschoenen"},"pl":{"label":"Rękawice"},"uk":{"label":"Рукавиці"}}'),
 ('boots', 'item', 'Boty', NULL, '{}', '{39,40,41,42,43,44,45,46,47,48}', 400, 50,
  '{"en":{"label":"Boots"},"de":{"label":"Stiefel"},"es":{"label":"Botas"},"fr":{"label":"Bottes"},"nl":{"label":"Laarzen"},"pl":{"label":"Buty"},"uk":{"label":"Чоботи"}}')
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.app_settings (key, value)
VALUES ('gear_rental', '{"enabled": true, "max_days": 30, "max_ahead_days": 400}'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- ---- 2) Výpůjčky (1:1 k objednávce) ----------------------------------------
CREATE TABLE IF NOT EXISTS public.gear_rentals (
  order_id     uuid PRIMARY KEY REFERENCES public.shop_orders(id) ON DELETE CASCADE,
  branch_id    uuid NOT NULL REFERENCES public.branches(id) ON DELETE RESTRICT,
  start_date   date NOT NULL,
  end_date     date NOT NULL,
  days         integer NOT NULL CHECK (days BETWEEN 1 AND 366),
  pickup_time  time,
  items        jsonb NOT NULL DEFAULT '[]'::jsonb,
  lines        jsonb NOT NULL DEFAULT '[]'::jsonb,
  per_day      numeric(10,2) NOT NULL DEFAULT 0,
  status       text NOT NULL DEFAULT 'reserved' CHECK (status IN ('reserved', 'picked_up', 'returned', 'cancelled')),
  note         text,
  admin_note   text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT gear_rentals_dates CHECK (end_date >= start_date)
);
COMMENT ON TABLE public.gear_rentals IS 'Půjčení výbavy bez motorky (web /pujceni-obleceni). Platba a doklady = shop_orders (order_id). items = [{key,size}], lines = naceněné řádky [{key,kind,label,sizes,price_per_day,total}]. status vede obsluha ve Velínu.';
CREATE INDEX IF NOT EXISTS idx_gear_rentals_branch_dates ON public.gear_rentals (branch_id, start_date, end_date);

DROP TRIGGER IF EXISTS trg_gear_rentals_touch ON public.gear_rentals;
CREATE TRIGGER trg_gear_rentals_touch BEFORE UPDATE ON public.gear_rentals
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

ALTER TABLE public.gear_rentals ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS gear_rentals_admin ON public.gear_rentals;
CREATE POLICY gear_rentals_admin ON public.gear_rentals
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
REVOKE ALL ON public.gear_rentals FROM anon;

-- ---- 3) Nacenění (sdílí založení objednávky; web počítá stejně v JS) ---------
-- p_items = [{key, size}] jen aktivní kusy (kind='item'); komplet se použije,
-- když jsou vybrané všechny jeho kusy a je levnější než jejich součet.
CREATE OR REPLACE FUNCTION public._gear_rental_quote(p_items jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  it jsonb; r record; s record;
  v_keys text[] := '{}'; v_left text[]; v_sizes jsonb := '{}'::jsonb;
  v_lines jsonb := '[]'::jsonb; v_per_day numeric := 0; v_sum numeric; v_k text; v_size text;
BEGIN
  IF jsonb_typeof(p_items) IS DISTINCT FROM 'array' OR jsonb_array_length(p_items) = 0 THEN
    RETURN jsonb_build_object('error', 'no_items');
  END IF;
  IF jsonb_array_length(p_items) > 12 THEN RETURN jsonb_build_object('error', 'too_many_items'); END IF;
  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_k := it->>'key';
    v_size := NULLIF(btrim(COALESCE(it->>'size', '')), '');
    SELECT * INTO r FROM gear_rental_prices WHERE key = v_k AND kind = 'item' AND is_active;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'bad_item', 'key', v_k); END IF;
    IF v_k = ANY (v_keys) THEN RETURN jsonb_build_object('error', 'duplicate_item', 'key', v_k); END IF;
    IF cardinality(r.sizes) > 0 AND (v_size IS NULL OR NOT (v_size = ANY (r.sizes))) THEN
      RETURN jsonb_build_object('error', 'bad_size', 'key', v_k, 'size', v_size);
    END IF;
    v_keys := v_keys || v_k;
    v_sizes := v_sizes || jsonb_build_object(v_k, v_size);
  END LOOP;

  v_left := v_keys;
  FOR s IN SELECT * FROM gear_rental_prices WHERE kind = 'set' AND is_active
           ORDER BY cardinality(includes) DESC, price_per_day, key LOOP
    CONTINUE WHEN NOT (s.includes <@ v_left);
    SELECT sum(price_per_day) INTO v_sum FROM gear_rental_prices WHERE kind = 'item' AND key = ANY (s.includes);
    CONTINUE WHEN s.price_per_day >= COALESCE(v_sum, 0);
    v_lines := v_lines || jsonb_build_object('key', s.key, 'kind', 'set', 'label', s.label,
      'includes', to_jsonb(s.includes), 'sizes', (SELECT COALESCE(jsonb_object_agg(k, v_sizes->k), '{}'::jsonb) FROM unnest(s.includes) k),
      'price_per_day', s.price_per_day);
    v_per_day := v_per_day + s.price_per_day;
    v_left := ARRAY(SELECT x FROM unnest(v_left) x WHERE NOT (x = ANY (s.includes)));
  END LOOP;

  FOR r IN SELECT * FROM gear_rental_prices WHERE kind = 'item' AND key = ANY (v_left) ORDER BY sort_order, key LOOP
    v_lines := v_lines || jsonb_build_object('key', r.key, 'kind', 'item', 'label', r.label,
      'includes', to_jsonb(ARRAY[r.key]), 'sizes', jsonb_build_object(r.key, v_sizes->r.key), 'price_per_day', r.price_per_day);
    v_per_day := v_per_day + r.price_per_day;
  END LOOP;

  RETURN jsonb_build_object('keys', to_jsonb(v_keys), 'sizes', v_sizes, 'lines', v_lines, 'per_day', v_per_day);
END $$;
REVOKE ALL ON FUNCTION public._gear_rental_quote(jsonb) FROM PUBLIC, anon, authenticated;

-- ---- 4) Založení objednávky z webu (anon) -----------------------------------
CREATE OR REPLACE FUNCTION public.create_gear_rental_order(
  p_branch_id uuid, p_start date, p_end date, p_items jsonb, p_customer jsonb,
  p_pickup_time text DEFAULT NULL, p_lang text DEFAULT 'cs', p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cfg jsonb; v_today date := (now() AT TIME ZONE 'Europe/Prague')::date;
  v_days int; v_max int; v_ahead int; v_br record; v_q jsonb; ln jsonb;
  v_name text; v_email text; v_phone text; v_addr text; v_time time; v_lang text;
  v_order uuid := gen_random_uuid(); v_total numeric; v_num text; v_note text; v_desc text; v_sz text;
BEGIN
  SELECT value INTO v_cfg FROM app_settings WHERE key = 'gear_rental';
  IF COALESCE(v_cfg->>'enabled', 'true') = 'false' THEN RETURN jsonb_build_object('error', 'disabled'); END IF;
  v_max := LEAST(GREATEST(COALESCE((v_cfg->>'max_days')::int, 30), 1), 366);
  v_ahead := LEAST(GREATEST(COALESCE((v_cfg->>'max_ahead_days')::int, 400), 1), 800);

  SELECT id, name, type, active INTO v_br FROM branches WHERE id = p_branch_id;
  IF NOT FOUND OR v_br.active IS NOT TRUE THEN RETURN jsonb_build_object('error', 'bad_branch'); END IF;
  IF p_start IS NULL OR p_end IS NULL OR p_end < p_start THEN RETURN jsonb_build_object('error', 'bad_dates'); END IF;
  IF p_start < v_today OR p_start > v_today + v_ahead THEN RETURN jsonb_build_object('error', 'bad_dates'); END IF;
  v_days := (p_end - p_start) + 1;
  IF v_days > v_max THEN RETURN jsonb_build_object('error', 'too_long', 'max_days', v_max); END IF;
  IF public.branch_is_closed(p_branch_id, p_start, p_end) THEN RETURN jsonb_build_object('error', 'branch_closed'); END IF;

  v_name := left(btrim(COALESCE(p_customer->>'name', '')), 200);
  v_email := lower(left(btrim(COALESCE(p_customer->>'email', '')), 200));
  v_phone := NULLIF(left(btrim(COALESCE(p_customer->>'phone', '')), 30), '');
  IF length(v_name) < 3 OR v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' OR v_phone IS NULL THEN
    RETURN jsonb_build_object('error', 'bad_customer');
  END IF;
  IF (SELECT count(*) FROM shop_orders o JOIN gear_rentals g ON g.order_id = o.id
       WHERE lower(o.customer_email) = v_email AND o.payment_status = 'pending'
         AND o.created_at > now() - interval '1 hour') >= 5 THEN
    RETURN jsonb_build_object('error', 'too_many');
  END IF;
  BEGIN v_time := NULLIF(btrim(COALESCE(p_pickup_time, '')), '')::time;
  EXCEPTION WHEN others THEN v_time := NULL; END;
  v_lang := CASE WHEN p_lang IN ('cs','en','de','nl','es','fr','pl','uk') THEN p_lang ELSE 'cs' END;
  v_note := NULLIF(left(btrim(COALESCE(p_note, '')), 500), '');
  v_addr := NULLIF(concat_ws(', ', NULLIF(btrim(COALESCE(p_customer->>'street', '')), ''),
    NULLIF(btrim(concat_ws(' ', NULLIF(btrim(COALESCE(p_customer->>'zip', '')), ''), NULLIF(btrim(COALESCE(p_customer->>'city', '')), ''))), ''),
    NULLIF(btrim(COALESCE(p_customer->>'country', '')), '')), '');

  v_q := public._gear_rental_quote(p_items);
  IF v_q ? 'error' THEN RETURN v_q; END IF;
  v_total := (v_q->>'per_day')::numeric * v_days;
  IF v_total < 15 THEN RETURN jsonb_build_object('error', 'below_minimum'); END IF;

  v_desc := 'Půjčení výbavy (bez motorky) — ' || regexp_replace(v_br.name, '^MotoGo24\s*', '') || ', '
    || to_char(p_start, 'FMDD. FMMM.') || ' – ' || to_char(p_end, 'FMDD. FMMM. YYYY')
    || ' (' || v_days || CASE WHEN v_days = 1 THEN ' den' WHEN v_days < 5 THEN ' dny' ELSE ' dní' END || ')';

  INSERT INTO shop_orders (id, customer_name, customer_email, customer_phone, billing_address,
    customer_company, customer_ico, customer_dic, shipping_method, payment_method,
    status, payment_status, subtotal, shipping_cost, discount, total, notes, language)
  VALUES (v_order, v_name, v_email, v_phone, v_addr,
    NULLIF(left(btrim(COALESCE(p_customer->>'company', '')), 200), ''),
    NULLIF(left(btrim(COALESCE(p_customer->>'ico', '')), 20), ''),
    NULLIF(left(btrim(COALESCE(p_customer->>'dic', '')), 20), ''),
    'pickup', 'stripe', 'new', 'pending', v_total, 0, 0, v_total,
    v_desc || COALESCE(E'\n' || v_note, ''), v_lang)
  RETURNING order_number INTO v_num;

  -- Řádek dokladu: množství = dny, cena = Kč/den. Kus nese velikost ve `size`,
  -- komplet má velikosti kusů v názvu („helma M, bunda L, …“).
  -- Bez slov „poukaz/voucher“ (auto_process_voucher_order by z položky vyrobil poukaz).
  FOR ln IN SELECT * FROM jsonb_array_elements(v_q->'lines') LOOP
    SELECT string_agg(lower(p.label) || ' ' || e.value, ', ' ORDER BY p.sort_order) INTO v_sz
      FROM jsonb_each_text(ln->'sizes') e JOIN gear_rental_prices p ON p.key = e.key
     WHERE e.value IS NOT NULL;
    INSERT INTO shop_order_items (order_id, product_name, product_sku, size, quantity, unit_price, total_price)
    VALUES (v_order,
      'Půjčení výbavy: ' || (ln->>'label')
        || CASE WHEN ln->>'kind' = 'set' AND v_sz IS NOT NULL THEN ' (' || v_sz || ')' ELSE '' END
        || ' — ' || v_days || CASE WHEN v_days = 1 THEN ' den' WHEN v_days < 5 THEN ' dny' ELSE ' dní' END,
      'gear_rental_' || (ln->>'key'),
      CASE WHEN ln->>'kind' = 'item' THEN (SELECT e.value FROM jsonb_each_text(ln->'sizes') e LIMIT 1) END,
      v_days, (ln->>'price_per_day')::numeric, (ln->>'price_per_day')::numeric * v_days);
  END LOOP;

  INSERT INTO gear_rentals (order_id, branch_id, start_date, end_date, days, pickup_time, items, lines, per_day, note)
  SELECT v_order, p_branch_id, p_start, p_end, v_days, v_time,
    (SELECT COALESCE(jsonb_agg(jsonb_build_object('key', k, 'size', v_q->'sizes'->>k)), '[]'::jsonb)
       FROM jsonb_array_elements_text(v_q->'keys') k),
    (SELECT COALESCE(jsonb_agg(l || jsonb_build_object('total', (l->>'price_per_day')::numeric * v_days)), '[]'::jsonb)
       FROM jsonb_array_elements(v_q->'lines') l),
    (v_q->>'per_day')::numeric, v_note;

  RETURN jsonb_build_object('success', true, 'order_id', v_order, 'order_number', v_num,
    'days', v_days, 'per_day', (v_q->>'per_day')::numeric, 'total', v_total, 'lines', v_q->'lines');
END $$;
REVOKE ALL ON FUNCTION public.create_gear_rental_order(uuid, date, date, jsonb, jsonb, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_gear_rental_order(uuid, date, date, jsonb, jsonb, text, text, text) TO anon, authenticated, service_role;

-- ---- 5) Potvrzení pro web (stav platby + detail; osobní údaje jen se session / 2 h) ----
CREATE OR REPLACE FUNCTION public.get_gear_rental_confirmation(p_order_id uuid, p_session_id text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE o record; g record; b record; v_full boolean;
BEGIN
  IF p_order_id IS NULL THEN RETURN jsonb_build_object('error', 'missing_identifier'); END IF;
  SELECT id, order_number, customer_name, customer_email, total, payment_status, status,
         created_at, customer_id, stripe_session_id
    INTO o FROM shop_orders WHERE id = p_order_id;
  SELECT * INTO g FROM gear_rentals WHERE order_id = p_order_id;
  IF o.id IS NULL OR g.order_id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
  SELECT name, address, city, type INTO b FROM branches WHERE id = g.branch_id;
  v_full := public._web_booking_full_access(o.customer_id)
    OR (NULLIF(p_session_id, '') IS NOT NULL AND p_session_id = o.stripe_session_id)
    OR o.created_at > now() - interval '2 hours';
  RETURN jsonb_build_object(
    'id', o.id, 'order_number', o.order_number, 'total', o.total,
    'payment_status', o.payment_status, 'status', o.status, 'rental_status', g.status,
    'start_date', g.start_date, 'end_date', g.end_date, 'days', g.days, 'pickup_time', g.pickup_time,
    'branch', jsonb_build_object('id', g.branch_id, 'name', b.name, 'address', b.address, 'city', b.city, 'type', b.type),
    'lines', g.lines,
    'customer_name', CASE WHEN v_full THEN o.customer_name END,
    'customer_email', CASE WHEN v_full THEN o.customer_email END,
    'restricted', NOT v_full);
END $$;
REVOKE ALL ON FUNCTION public.get_gear_rental_confirmation(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_gear_rental_confirmation(uuid, text) TO anon, authenticated, service_role;
