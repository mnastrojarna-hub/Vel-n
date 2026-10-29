-- =============================================================================
-- 2026-10-23 (b): Výpůjčka JEN výbavy jako rezervace — RPC, sklad, doklady (1/10)
-- Navazuje na 20261023a (booking_kind='gear'). Kvůli limitu velikosti souboru
-- (CLAUDE.md) je balík rozdělen do 10 souborů se SPOLEČNOU předponou, které
-- autodeploy aplikuje v bytovém pořadí názvu (vše před 20261023c):
--   20261023b_gear_booking_rpc.sql             — pomocné funkce: velikosti, sklad, doklady
--   20261023b_gear_booking_rpc_b_logistics     — Logistika zboží nad společnou poptávkou
--   20261023b_gear_booking_rpc_c_core          — pobočka, uzavření, překryv (triggery)
--   20261023b_gear_booking_rpc_c_docs          — doklady: jen totožnost + 18+ (brány kódů)
--   20261023b_gear_booking_rpc_d_loyalty       — věrnostní body bez výpůjček výbavy
--   20261023b_gear_booking_rpc_e_quote         — nacenění + validace, dostupnost, dry-run pro web
--   20261023b_gear_booking_rpc_f_create        — založení z webu (create_web_gear_booking)
--   20261023b_gear_booking_rpc_g_read          — čtení pro web/appku, stará cesta e-shopu off
--   20261023b_gear_booking_rpc_h_edit          — Velín založení, zákazník (velikosti), e-mail úpravy
--   20261023b_gear_booking_rpc_i_admin_update  — Velín úprava + práva souborů h/i
-- Motorkové chování zůstává beze změny (změněné řádky převzatých funkcí jsou
-- označené komentářem „gear 2026-10-23“). Idempotentní (CREATE OR REPLACE).
-- =============================================================================

-- ---- 1) Velikosti -------------------------------------------------------------
-- Klíč pro POROVNÁNÍ velikostí (sklad ↔ rezervace): trim + upper + aliasy
-- XXL→2XL … (parita s kioskem gear_limits.py ALIASES). Uložený zápis se nemění.
CREATE OR REPLACE FUNCTION public._gear_size_key(p text)
RETURNS text LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE upper(btrim(p))
           WHEN 'XXL' THEN '2XL' WHEN 'XXXL' THEN '3XL' WHEN 'XXXXL' THEN '4XL'
           WHEN 'XXXXXL' THEN '5XL' WHEN 'XXXXXXL' THEN '6XL'
           ELSE NULLIF(upper(btrim(p)), '') END;
$$;

-- Pořadí písmenné velikosti (XXS=0 … 6XL=10); NULL = pořadí ji nezná (čísla bot, UNI…).
CREATE OR REPLACE FUNCTION public._gear_size_rank(p text)
RETURNS integer LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT array_position(ARRAY['XXS','XS','S','M','L','XL','2XL','3XL','4XL','5XL','6XL'],
                        public._gear_size_key(p)) - 1;
$$;

-- Smí se velikost vydat na SAMOOBSLUŽNÉ pobočce? (zadání majitele 2026-10-10)
-- helma S–3XL, bunda/kalhoty/rukavice max. 4XL; boty a neznámé hodnoty vždy ano.
-- SQL dvojče selfServiceSizeOk (submit-handover-protocol/gear.ts), gear-ss-cap.js, gear_limits.py.
CREATE OR REPLACE FUNCTION public._gear_ss_size_ok(p_key text, p_size text)
RETURNS boolean LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE
           WHEN p_key IS NULL OR NOT (p_key = ANY (ARRAY['helmet','jacket','pants','gloves'])) THEN true
           WHEN public._gear_size_rank(p_size) IS NULL THEN true
           WHEN p_key = 'helmet' THEN public._gear_size_rank(p_size) BETWEEN 2 AND 7
           ELSE public._gear_size_rank(p_size) <= 8 END;
$$;

-- ---- 2) Nastavení kontroly skladu (Velín: app_settings.gear_stock_check) -------
CREATE OR REPLACE FUNCTION public._gear_stock_check_on(p_scope text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT (value->>p_scope)::boolean FROM app_settings WHERE key = 'gear_stock_check'), false);
$$;

CREATE OR REPLACE FUNCTION public._gear_stock_keep_free()
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT GREATEST(COALESCE((SELECT (value->>'keep_free')::int FROM app_settings WHERE key = 'gear_stock_check'), 0), 0);
$$;

-- ---- 3) Společná poptávka po výbavě (motorky + výpůjčky výbavy) ----------------
-- Řádek = jeden kus jedné živé rezervace. Pobočka: gear = bookings.branch_id,
-- motorka = pobočka motorky (jako dřív Logistika). p_branch_id NULL = všechny.
-- Filtry: pending/reserved/active, ne test, ne přistavení. Dny inkluzivně.
CREATE OR REPLACE FUNCTION public._gear_demand(p_branch_id uuid, p_from date, p_to date,
                                               p_exclude_booking uuid DEFAULT NULL)
RETURNS TABLE(booking_id uuid, branch_id uuid, sd date, ed date, lic text, type text, size_key text, size text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT b.id, br.id, b.start_date::date, b.end_date::date,
         CASE WHEN b.booking_kind = 'gear' THEN 'A' ELSE COALESCE(m.license_required::text, 'A') END,
         x.type, public._gear_size_key(x.size), x.size
    FROM bookings b
    LEFT JOIN motorcycles m ON m.id = b.moto_id
    CROSS JOIN LATERAL (SELECT CASE WHEN b.booking_kind = 'gear' THEN b.branch_id ELSE m.branch_id END AS id) br
    CROSS JOIN LATERAL (VALUES
      ('helmet', b.helmet_size), ('jacket', b.jacket_size), ('pants', b.pants_size),
      ('boots', b.boots_size),   ('gloves', b.gloves_size),
      ('helmet', b.passenger_helmet_size), ('jacket', b.passenger_jacket_size),
      ('pants', b.passenger_pants_size),   ('boots', b.passenger_boots_size),
      ('gloves', b.passenger_gloves_size)) AS x(type, size)
   WHERE br.id IS NOT NULL
     AND (p_branch_id IS NULL OR br.id = p_branch_id)
     AND b.status IN ('pending', 'reserved', 'active')
     AND b.is_test IS NOT TRUE
     AND COALESCE(b.pickup_method, '') <> 'delivery'
     AND x.size IS NOT NULL AND x.size <> ''
     AND b.start_date::date <= p_to AND b.end_date::date >= p_from
     AND (p_exclude_booking IS NULL OR b.id <> p_exclude_booking);
$$;

-- ---- 4) Volné kusy pobočky v termínu (minimum přes dny) ------------------------
-- free = sklad − nejvyšší denní obsazenost. tracked = pobočka má daný TYP ve
-- skladu (branch_accessories); netrackovaný typ = neomezeno (free NULL).
-- Vesmír velikostí: ceník výpůjčky ∪ accessory_types ∪ sklad pobočky (zápis
-- velikosti přednostně z ceníku výpůjčky — ten používá web).
CREATE OR REPLACE FUNCTION public.gear_stock_free(p_branch_id uuid, p_start date, p_end date,
                                                  p_exclude_booking uuid DEFAULT NULL)
RETURNS TABLE(accessory_type text, size text, stock integer, peak_booked integer, free integer, tracked boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH days AS (SELECT generate_series(p_start, p_end, interval '1 day')::date AS d),
  src AS (
    SELECT p.key AS type, s AS size, 1 AS pri FROM gear_rental_prices p CROSS JOIN LATERAL unnest(p.sizes) s
     WHERE p.kind = 'item' AND p.is_active
    UNION ALL
    SELECT at.key, s, 2 FROM accessory_types at CROSS JOIN LATERAL unnest(COALESCE(at.sizes, '{}'::text[])) s
     WHERE at.is_active IS TRUE
    UNION ALL
    SELECT ba.type, ba.size, 3 FROM branch_accessories ba WHERE ba.branch_id = p_branch_id),
  uni AS (
    SELECT type, public._gear_size_key(size) AS k, (array_agg(size ORDER BY pri, size))[1] AS size
      FROM src
     WHERE type IN ('helmet', 'jacket', 'pants', 'boots', 'gloves') AND public._gear_size_key(size) IS NOT NULL
     GROUP BY type, public._gear_size_key(size)),
  st AS (SELECT ba.type, public._gear_size_key(ba.size) AS k, sum(ba.quantity)::int AS qty
           FROM branch_accessories ba WHERE ba.branch_id = p_branch_id GROUP BY 1, 2),
  tr AS (SELECT DISTINCT ba.type FROM branch_accessories ba WHERE ba.branch_id = p_branch_id),
  per AS (SELECT dm.type, dm.size_key AS k, d.d, count(*)::int AS n
            FROM days d JOIN public._gear_demand(p_branch_id, p_start, p_end, p_exclude_booking) dm
              ON d.d BETWEEN dm.sd AND dm.ed
           GROUP BY 1, 2, 3),
  peak AS (SELECT type, k, max(n)::int AS n FROM per GROUP BY 1, 2)
  SELECT u.type, u.size, COALESCE(st.qty, 0), COALESCE(pk.n, 0),
         CASE WHEN tr.type IS NOT NULL THEN COALESCE(st.qty, 0) - COALESCE(pk.n, 0) END,
         tr.type IS NOT NULL
    FROM uni u
    LEFT JOIN st ON st.type = u.type AND st.k = u.k
    LEFT JOIN peak pk ON pk.type = u.type AND pk.k = u.k
    LEFT JOIN tr ON tr.type = u.type
   ORDER BY u.type, u.size;
$$;

-- Kusy, které v termínu NEJSOU volné (po odečtení keep_free): [{key,size,free}].
-- p_sizes = {klíč: velikost}; jen typy skladované na pobočce. Sama rezervace se
-- při úpravě vyjímá (p_exclude_booking). Prázdné pole = vše volné.
CREATE OR REPLACE FUNCTION public._gear_stock_shortfall(p_branch_id uuid, p_start date, p_end date,
                                                        p_sizes jsonb, p_exclude_booking uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r record; v_k text; v_stock int; v_peak int; v_free int;
  v_keep int := public._gear_stock_keep_free(); v_out jsonb := '[]'::jsonb;
BEGIN
  IF p_branch_id IS NULL OR p_start IS NULL OR p_end IS NULL OR jsonb_typeof(p_sizes) IS DISTINCT FROM 'object' THEN
    RETURN v_out;
  END IF;
  FOR r IN SELECT e.key, e.value FROM jsonb_each_text(p_sizes) e WHERE NULLIF(btrim(e.value), '') IS NOT NULL ORDER BY e.key LOOP
    CONTINUE WHEN NOT EXISTS (SELECT 1 FROM branch_accessories ba WHERE ba.branch_id = p_branch_id AND ba.type = r.key);
    v_k := public._gear_size_key(r.value);
    SELECT COALESCE(sum(ba.quantity), 0)::int INTO v_stock FROM branch_accessories ba
     WHERE ba.branch_id = p_branch_id AND ba.type = r.key AND public._gear_size_key(ba.size) = v_k;
    SELECT COALESCE(max(q.n), 0)::int INTO v_peak FROM (
      SELECT d.d, count(*) AS n
        FROM generate_series(p_start, p_end, interval '1 day') d(d)
        JOIN public._gear_demand(p_branch_id, p_start, p_end, p_exclude_booking) dm
          ON d.d::date BETWEEN dm.sd AND dm.ed
       WHERE dm.type = r.key AND dm.size_key = v_k
       GROUP BY d.d) q;
    v_free := v_stock - v_peak - v_keep;
    IF v_free < 1 THEN
      v_out := v_out || jsonb_build_object('key', r.key, 'size', r.value, 'free', GREATEST(v_free, 0));
    END IF;
  END LOOP;
  RETURN v_out;
END $$;

-- ---- 5) Doklady pro výpůjčku výbavy: JEN totožnost + 18+ (rozhodnutí majitele) --
-- Jádro _docs_gate_checklist zůstává (NULL-moto sémantika beze změny); z jeho
-- výstupu se bere jen totožnost (OP líc+rub nebo pas) a datum narození 18+ k začátku.
-- Návrat: stejné klíče jako _docs_gate_checklist + gear_only=true, ok/missing/reason přepočtené.
CREATE OR REPLACE FUNCTION public._gear_docs_checklist(p_user_id uuid, p_start date, p_end date DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v jsonb; v_miss text[] := '{}';
BEGIN
  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'gear_only', true, 'reason', 'Chybí uživatel',
                              'missing', jsonb_build_array('Chybí uživatel'));
  END IF;
  v := public._docs_gate_checklist(p_user_id, p_start, COALESCE(p_end, p_start), NULL);
  IF NOT COALESCE((v->>'identity_ok')::boolean, false) THEN
    v_miss := v_miss || CASE
      WHEN NOT COALESCE((v->>'id_front')::boolean, false) AND NOT COALESCE((v->>'id_back')::boolean, false)
        THEN 'Chybí OP (líc a rub) nebo pas'
      WHEN NOT COALESCE((v->>'id_back')::boolean, false) THEN 'Chybí rub OP'
      ELSE 'Chybí líc OP' END;
  END IF;
  IF v->>'date_of_birth' IS NULL THEN v_miss := v_miss || 'Chybí datum narození'::text;
  ELSIF NOT COALESCE((v->>'age_ok')::boolean, false) THEN v_miss := v_miss || 'Zákazníkovi není 18 let'::text;
  END IF;
  RETURN v || jsonb_build_object('ok', cardinality(v_miss) = 0, 'gear_only', true,
    'missing', to_jsonb(v_miss),
    'reason', CASE WHEN cardinality(v_miss) = 0 THEN NULL ELSE array_to_string(v_miss, '; ') END);
END $$;

-- ---- 6) Práva: vše interní (volají je SECURITY DEFINER funkce) ----------------
REVOKE ALL ON FUNCTION public._gear_size_key(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._gear_size_rank(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._gear_ss_size_ok(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._gear_stock_check_on(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._gear_stock_keep_free() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._gear_demand(uuid, date, date, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.gear_stock_free(uuid, date, date, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._gear_stock_shortfall(uuid, date, date, jsonb, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._gear_docs_checklist(uuid, date, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._gear_size_key(text) TO service_role;
GRANT EXECUTE ON FUNCTION public._gear_size_rank(text) TO service_role;
GRANT EXECUTE ON FUNCTION public._gear_ss_size_ok(text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public._gear_stock_check_on(text) TO service_role;
GRANT EXECUTE ON FUNCTION public._gear_stock_keep_free() TO service_role;
GRANT EXECUTE ON FUNCTION public._gear_demand(uuid, date, date, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.gear_stock_free(uuid, date, date, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._gear_stock_shortfall(uuid, date, date, jsonb, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._gear_docs_checklist(uuid, date, date) TO service_role;

COMMENT ON FUNCTION public.gear_stock_free(uuid, date, date, uuid) IS
  'Volné kusy výbavy pobočky v termínu (min přes dny; poptávka motorek + výpůjček výbavy přes _gear_demand). tracked=false = typ se na pobočce neskladuje (neomezeno). 2026-10-23.';
