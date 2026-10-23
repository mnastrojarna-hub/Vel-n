-- =============================================================================
-- 2026-10-23 (b/1a, FIX-R1): Logistika zboží — jeden řádek deficitu na velikost
-- _gear_size_key srovná zápisy (XXL = 2XL), ale řádky gear_shortages mají UNIQUE
-- na PŘESNÝ zápis velikosti → dřív vznikaly duplicitní otevřené řádky jednoho
-- deficitu (zastaralá čísla, dvojí deficit v Logistice). Pomocníci pro
-- detect_gear_shortages_for_window (20261023b_gear_booking_rpc_b_logistics.sql):
--  • _gear_shortage_size: kanonický zápis = číselník accessory_types (popisek
--    kalendáře skladu, SKU objednávky prislusenstvi-{typ}-{velikost} dle CLAUDE.md),
--    bez číselníku zápis skladu pobočky, jinak klíč;
--  • _gear_shortages_merge_sizes: sloučení řádků s jiným zápisem téže velikosti.
-- Jen service_role (volá je SECURITY DEFINER detekce). Idempotentní.
-- =============================================================================

-- FIX-R1: kanonický zápis velikosti řádku deficitu (_gear_size_key: XXL = 2XL) — stejný jako popisek
-- get_branch_gear_calendar: zápis z číselníku accessory_types (aktivní typ), jinak ze skladu pobočky
-- (víc zápisů → nejmenší), jinak klíč sám.
CREATE OR REPLACE FUNCTION public._gear_shortage_size(p_branch_id uuid, p_type text, p_size text)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT min(x.s) FROM accessory_types at CROSS JOIN LATERAL unnest(COALESCE(at.sizes, '{}'::text[])) x(s)
                    WHERE at.key = p_type AND at.is_active = true
                      AND public._gear_size_key(x.s) = public._gear_size_key(p_size)),
                  (SELECT min(ba.size) FROM branch_accessories ba
                    WHERE ba.branch_id = p_branch_id AND ba.type = p_type
                      AND public._gear_size_key(ba.size) = public._gear_size_key(p_size)),
                  public._gear_size_key(p_size), p_size);
$$;
REVOKE ALL ON FUNCTION public._gear_shortage_size(uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._gear_shortage_size(uuid, text, text) TO service_role;

-- FIX-R1: sloučení řádků deficitu s různým zápisem téže velikosti (pobočka, den, typ, klíč) do JEDNOHO
-- řádku s kanonickým zápisem. Ponechaný řádek: rozpracovaný (order_created / warehouse_filled /
-- transfer_requested) > otevřený s prací (objednávka, přesun, přiřazení, poznámka) > ostatní; při shodě
-- kanonický, pak nejstarší. Ostatní nekanonické neuzavřené → resolved „sloučeno do …“ (objednávka zůstane
-- v historii); kanonický, který prohrál (bez rozpracované práce), se smaže a jeho přiřazení / poznámka
-- přejdou na ponechaný řádek, ten se přejmenuje. Uzavřené nekanonické řádky = historie, beze změny.
CREATE OR REPLACE FUNCTION public._gear_shortages_merge_sizes(p_branch_id uuid, p_from date, p_to date)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record; v_keep record; v_gone record;
BEGIN
  FOR r IN SELECT DISTINCT g.accessory_type, g.shortage_date, x.canon
             FROM gear_shortages g
             CROSS JOIN LATERAL (SELECT public._gear_shortage_size(p_branch_id, g.accessory_type, g.size) canon) x
            WHERE g.branch_id = p_branch_id AND g.shortage_date BETWEEN p_from AND p_to
              AND g.status NOT IN ('resolved', 'dismissed') AND g.size IS DISTINCT FROM x.canon
  LOOP
    SELECT g.* , (g.size = r.canon) AS is_canon INTO v_keep
      FROM gear_shortages g
     WHERE g.branch_id = p_branch_id AND g.accessory_type = r.accessory_type AND g.shortage_date = r.shortage_date
       AND public._gear_size_key(g.size) = public._gear_size_key(r.canon)
       AND (g.size = r.canon OR g.status NOT IN ('resolved', 'dismissed'))
     ORDER BY CASE WHEN g.status IN ('order_created', 'warehouse_filled', 'transfer_requested') THEN 2
                   WHEN g.status = 'open' AND (g.purchase_order_id IS NOT NULL OR g.transfer_from_branch_id IS NOT NULL
                        OR g.assigned_to IS NOT NULL OR NULLIF(g.resolution, '') IS NOT NULL) THEN 1 ELSE 0 END DESC,
              (g.size = r.canon) DESC, g.created_at, g.id
     LIMIT 1;
    UPDATE gear_shortages g
       SET status = 'resolved', deficit_qty = 0, resolved_at = now(), updated_at = now(),
           resolution = concat_ws('; ', NULLIF(g.resolution, ''), 'sloučeno do ' || r.canon)
     WHERE g.branch_id = p_branch_id AND g.accessory_type = r.accessory_type AND g.shortage_date = r.shortage_date
       AND public._gear_size_key(g.size) = public._gear_size_key(r.canon)
       AND g.size IS DISTINCT FROM r.canon AND g.status NOT IN ('resolved', 'dismissed') AND g.id <> v_keep.id;
    IF NOT v_keep.is_canon THEN
      DELETE FROM gear_shortages g
       WHERE g.branch_id = p_branch_id AND g.accessory_type = r.accessory_type
         AND g.shortage_date = r.shortage_date AND g.size = r.canon
      RETURNING g.status, g.assigned_to, g.resolution INTO v_gone;
      UPDATE gear_shortages k
         SET size = r.canon, updated_at = now(),
             assigned_to = COALESCE(k.assigned_to, CASE WHEN v_gone.status = 'open' THEN v_gone.assigned_to END),
             resolution = COALESCE(NULLIF(k.resolution, ''), CASE WHEN v_gone.status = 'open' THEN NULLIF(v_gone.resolution, '') END)
       WHERE k.id = v_keep.id;
    END IF;
  END LOOP;
END $$;
REVOKE ALL ON FUNCTION public._gear_shortages_merge_sizes(uuid, date, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._gear_shortages_merge_sizes(uuid, date, date) TO service_role;
