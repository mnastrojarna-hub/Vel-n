-- 2026-10-05: update_booking_gear (úprava výbavy z webu / appky / Velínu) — 2 opravy, zbytek beze změny (živá
-- definice z 20260925a):
--  1) „vlastní výbava“ (own_gear=true) + nově doplněná helma/bunda/kalhoty/rukavice bez p_own_gear (web Upravit
--     rezervaci → Výbava) → own_gear=false → kód šatny přijde (dřív se velikost uložila a kód šatny nepřišel).
--     Opačný směr (vše „žádná“ při own_gear=false) řeší pravidlo _booking_needs_locker (20261005g).
--  2) placená výbava v booking_extras se poznává i podle názvů v jazycích webu (_booking_extra_is_gear z 20261005g:
--     Stiefel Fahrer, Laarzen bestuurder, Buty kierowca, Взуття водія, Beifahrerausrüstung, Équipement passager…).
--     Dřív filtr znal jen cs/en/es/fr → u ostatních jazyků úprava výbavy počítala zaplacené boty/spolujezdce jako
--     nové (doplatek podruhé) a starý řádek nesmazala.
-- Idempotentní (CREATE OR REPLACE).

CREATE OR REPLACE FUNCTION "public"."update_booking_gear"("p_booking_id" "uuid", "p_sizes" "jsonb", "p_dry_run" boolean DEFAULT false, "p_settle_refund" boolean DEFAULT false, "p_own_gear" boolean DEFAULT NULL::boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  b record;
  v_pp int; v_pbr int; v_pbp int;
  v_new_pass boolean; v_new_br boolean; v_new_bp boolean;
  v_old_paid int := 0; v_new_paid int := 0; v_diff int;
  s_h text; s_j text; s_p text; s_b text; s_g text;
  s_ph text; s_pj text; s_pp_ text; s_pb text; s_pg text;
  v_dtype text;
  v_calc jsonb;
  v_net_diff numeric;
  v_new_total numeric;
  v_new_discount numeric;
  v_loy_level int := 0;
  -- NOVÉ 2026-09-15: od ranku 3 je placená výbava u APP rezervací zdarma
  -- (parita s appkou: booking_models.dart loyaltyFreeGearLevel = 3).
  v_gear_free boolean := false;
  v_loy_pct numeric := 0;
  v_loy_disc numeric := 0;
  v_refund numeric := 0;
  v_manual boolean := false;
  v_url text; v_key text;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success',false,'error','unauthenticated'); END IF;
  SELECT * INTO b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'error','not_found'); END IF;
  IF b.user_id <> v_uid AND NOT is_admin() THEN RETURN jsonb_build_object('success',false,'error','not_owner'); END IF;
  IF b.status NOT IN ('reserved','active') THEN RETURN jsonb_build_object('success',false,'error','wrong_status'); END IF;
  IF b.payment_status NOT IN ('paid','partial_refund','refund_pending') THEN RETURN jsonb_build_object('success',false,'error','not_paid'); END IF;

  SELECT COALESCE(MAX(CASE WHEN key='passenger_gear'  AND pricing_unit<>'free' THEN price_czk END),690),
         COALESCE(MAX(CASE WHEN key='boots_rider'     AND pricing_unit<>'free' THEN price_czk END),290),
         COALESCE(MAX(CASE WHEN key='boots_passenger' AND pricing_unit<>'free' THEN price_czk END),290)
    INTO v_pp, v_pbr, v_pbp
    FROM accessory_types WHERE key IN ('passenger_gear','boots_rider','boots_passenger');

  -- Rank spočítej VŽDY (ne jen u doplatku) — rozhoduje o nároku na výbavu
  -- zdarma. Gate na booking_source='app' je stejný jako u věrnostní % slevy:
  -- web rezervace nemá věrnostní výhodu, ať ji upravuje kdokoli odkudkoli.
  IF COALESCE(b.booking_source, 'web') = 'app' THEN
    v_loy_level := LEAST(20, CEIL((_loyalty_qualifying_count(b.user_id) + 1) / 2.0))::int;
    v_gear_free := v_loy_level >= 3;
  END IF;

  s_h  := NULLIF(p_sizes->>'helmet','');  s_j := NULLIF(p_sizes->>'jacket','');
  s_p  := NULLIF(p_sizes->>'pants','');   s_b := NULLIF(p_sizes->>'boots','');
  s_g  := NULLIF(p_sizes->>'gloves','');
  s_ph := NULLIF(p_sizes->>'passenger_helmet','');  s_pj := NULLIF(p_sizes->>'passenger_jacket','');
  s_pp_:= NULLIF(p_sizes->>'passenger_pants','');   s_pb := NULLIF(p_sizes->>'passenger_boots','');
  s_pg := NULLIF(p_sizes->>'passenger_gloves','');

  v_new_pass := (s_ph IS NOT NULL OR s_pj IS NOT NULL OR s_pp_ IS NOT NULL OR s_pg IS NOT NULL);
  v_new_br   := (s_b  IS NOT NULL);
  v_new_bp   := (s_pb IS NOT NULL);
  IF v_new_pass THEN v_new_paid := v_new_paid + CASE WHEN v_gear_free THEN 0 ELSE v_pp  END; END IF;
  IF v_new_br   THEN v_new_paid := v_new_paid + CASE WHEN v_gear_free THEN 0 ELSE v_pbr END; END IF;
  IF v_new_bp   THEN v_new_paid := v_new_paid + CASE WHEN v_gear_free THEN 0 ELSE v_pbp END; END IF;

  -- OPRAVA 2026-09-15: baseline = co je REÁLNĚ uložené v booking_extras, ne
  -- dnešní ceník. Původní verze dopočítávala cenu z NÁZVU řádku, takže řádek
  -- za 0 Kč (výbava zdarma od ranku 3) ocenila plnou cenou → při odebrání
  -- výbavy se vracely peníze, které zákazník nikdy nezaplatil. Filtr je
  -- shodný s DELETE níže, aby se nepočítaly nemodelované doplňky (vozík…).
  -- 2026-10-05: názvy řádků z webu jsou v jazyce zákazníka (Stiefel Fahrer, Buty kierowca…) → _booking_extra_is_gear.
  SELECT COALESCE(ROUND(SUM(COALESCE(unit_price,0) * COALESCE(quantity,1))),0)::int
  INTO v_old_paid FROM booking_extras WHERE booking_id = p_booking_id
    AND public._booking_extra_is_gear(name);

  v_diff := v_new_paid - v_old_paid;

  -- ── VĚRNOSTNÍ SLEVA (2026-08-06) — app rezervace, kladný rozdíl výbavy ──
  -- Výbava je součást loyalty base i při vzniku rezervace; doplatek za
  -- přidanou výbavu se sníží o pct dle aktuálního ranku.
  IF COALESCE(b.booking_source, 'web') = 'app' AND v_diff > 0 THEN
    -- v_loy_level je spočítaný výše (nároky na výbavu zdarma) — nepočítat 2×.
    SELECT COALESCE(discount_percent, 0) INTO v_loy_pct FROM loyalty_levels WHERE level = v_loy_level;
    v_loy_pct := COALESCE(v_loy_pct, 0);
    v_loy_disc := ROUND(v_diff * v_loy_pct / 100.0);
  END IF;

  -- ── VARIANTA B (2026-06-11): sleva se přepočítá na nový obsah rezervace ──
  -- v_diff je HRUBÝ rozdíl výbavy; net_diff (po slevě) je to, co se účtuje /
  -- vrací zákazníkovi. Loyalty sleva se odečítá už z gross rozdílu.
  -- typ slevy a multi-rozklad řeší _recalc_booking_discount (krok 3c)
  v_calc  := public._recalc_booking_discount(b.id, b.total_price, b.discount_amount, v_diff - v_loy_disc, false);
  v_net_diff     := (v_calc->>'net_diff')::numeric;
  v_new_total    := (v_calc->>'new_total')::numeric;
  v_new_discount := (v_calc->>'new_discount')::numeric;

  v_manual := (b.stripe_payment_intent_id IS NULL AND b.stripe_session_id IS NULL);

  IF p_dry_run THEN
    RETURN jsonb_build_object('success',true,'payment_required', v_net_diff>0,'net_diff',v_net_diff,
      'refund_amount', CASE WHEN v_net_diff<0 THEN -v_net_diff ELSE 0 END,
      'refund_manual', v_manual,
      'new_total', v_new_total, 'gross_diff', v_diff, 'new_discount', v_new_discount,
      'loyalty_discount', v_loy_disc, 'loyalty_percent', v_loy_pct, 'loyalty_level', v_loy_level);
  END IF;

  UPDATE bookings SET
    helmet_size=s_h, jacket_size=s_j, pants_size=s_p, boots_size=s_b, gloves_size=s_g,
    passenger_helmet_size = CASE WHEN v_new_pass THEN s_ph  ELSE NULL END,
    passenger_jacket_size = CASE WHEN v_new_pass THEN s_pj  ELSE NULL END,
    passenger_pants_size  = CASE WHEN v_new_pass THEN s_pp_ ELSE NULL END,
    passenger_gloves_size = CASE WHEN v_new_pass THEN s_pg  ELSE NULL END,
    passenger_boots_size  = CASE WHEN v_new_bp   THEN s_pb  ELSE NULL END,
    -- 2026-09-25: vlastní výbava (NULL = beze změny) → trg_sync_locker_code řeší kód šatny
    -- 2026-10-05: nově doplněná velikost helmy/bundy/kalhot/rukavic u „vlastní výbavy“ (web úprava posílá
    -- p_own_gear NULL) = zákazník výbavu chce → own_gear false → trg_sync_locker_code vydá kód šatny + zprávu + mail
    own_gear = COALESCE(p_own_gear,
                 CASE WHEN b.own_gear IS TRUE AND (
                        (s_h IS NOT NULL AND s_h IS DISTINCT FROM b.helmet_size)
                     OR (s_j IS NOT NULL AND s_j IS DISTINCT FROM b.jacket_size)
                     OR (s_p IS NOT NULL AND s_p IS DISTINCT FROM b.pants_size)
                     OR (s_g IS NOT NULL AND s_g IS DISTINCT FROM b.gloves_size))
                      THEN false ELSE own_gear END),
    extras_price = GREATEST(0, COALESCE(extras_price,0) + v_diff),
    total_price  = v_new_total,
    discount_amount = v_new_discount,
    loyalty_discount_amount = CASE WHEN v_loy_disc > 0
                                   THEN COALESCE(loyalty_discount_amount, 0) + v_loy_disc
                                   ELSE loyalty_discount_amount END,
    loyalty_level   = CASE WHEN v_loy_disc > 0 THEN v_loy_level ELSE loyalty_level END,
    loyalty_percent = CASE WHEN v_loy_disc > 0 THEN v_loy_pct   ELSE loyalty_percent END
  WHERE id = p_booking_id;

  DELETE FROM booking_extras WHERE booking_id = p_booking_id
    AND public._booking_extra_is_gear(name);
  -- Řádky se ukládají za cenu, která se SKUTEČNĚ účtovala (0 Kč od ranku 3),
  -- aby SUM(booking_extras.unit_price) = bookings.extras_price a faktury
  -- (ZF/DP/KF) vykázaly správnou cenu pronájmu.
  IF v_new_pass THEN INSERT INTO booking_extras(booking_id,name,unit_price,quantity) VALUES (p_booking_id,'Výbava spolujezdce',CASE WHEN v_gear_free THEN 0 ELSE v_pp  END,1); END IF;
  IF v_new_br   THEN INSERT INTO booking_extras(booking_id,name,unit_price,quantity) VALUES (p_booking_id,'Boty řidič',      CASE WHEN v_gear_free THEN 0 ELSE v_pbr END,1); END IF;
  IF v_new_bp   THEN INSERT INTO booking_extras(booking_id,name,unit_price,quantity) VALUES (p_booking_id,'Boty spolujezdce',CASE WHEN v_gear_free THEN 0 ELSE v_pbp END,1); END IF;

  -- Vratka AŽ PO úspěšném commitu (2026-08-22) — dřív ji klient volal PŘED
  -- uložením a selhaný commit nechal „osiřelý" refund (incident DB-2026-0008/9).
  IF p_settle_refund AND v_net_diff < -0.5 THEN
    v_refund := -v_net_diff;
    BEGIN
      SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
      SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
      IF COALESCE(v_url,'') <> '' AND COALESCE(v_key,'') <> '' THEN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/process-refund',
          headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
          body := jsonb_build_object('booking_id', p_booking_id, 'amount', v_refund, 'reason', 'gear_edit', 'source', 'edit')
        );
      ELSE
        INSERT INTO debug_log(source, action, status, error_message, request_data)
        VALUES ('update_booking_gear','refund_dispatch_skipped_no_settings','error',
                'app_settings supabase_url/service_role_key missing',
                jsonb_build_object('booking_id',p_booking_id,'refund',v_refund));
      END IF;
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO debug_log(source, action, status, error_message, request_data)
      VALUES ('update_booking_gear','refund_dispatch_failed','error',SQLERRM,
              jsonb_build_object('booking_id',p_booking_id,'refund',v_refund));
    END;
  END IF;

  RETURN jsonb_build_object('success',true,'payment_required',false,'net_diff',v_net_diff,
    'refund_amount', CASE WHEN v_net_diff<0 THEN -v_net_diff ELSE 0 END,
    'refund_dispatched', (v_refund > 0), 'refund_manual', v_manual,
    'new_total', v_new_total, 'gross_diff', v_diff, 'new_discount', v_new_discount,
    'loyalty_discount', v_loy_disc, 'loyalty_percent', v_loy_pct, 'loyalty_level', v_loy_level);
END;
$$;

ALTER FUNCTION public.update_booking_gear(uuid, jsonb, boolean, boolean, boolean) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.update_booking_gear(uuid, jsonb, boolean, boolean, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_booking_gear(uuid, jsonb, boolean, boolean, boolean) TO authenticated, service_role;
