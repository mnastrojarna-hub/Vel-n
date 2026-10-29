-- =============================================================================
-- 2026-10-23 (c): Výpůjčka JEN výbavy — kiosek: protokol (7/14)
-- _kiosk_gear_sizes_catalog (ceník ∩ samoobsluha), _kiosk_protocol + gear_only (+ sizes_catalog u výbavy).
-- Používá ho kiosk_resolve_code i kiosk_sync_config (protocols[]). Aditivní — jednotka 1.2.x ignoruje.
-- Celek a pořadí souborů: viz 20261023c_gear_booking_codes.sql. Motorka beze změny (změny označené „2026-10-23“).
-- Idempotentní.
-- =============================================================================

-- Číselník velikostí pro protokol výpůjčky výbavy na kiosku: aktivní kusy ceníku gear_rental_prices
-- (helmet/jacket/pants/boots/gloves) ∩ meze samoobsluhy (_gear_ss_size_ok z 20261023b = SQL dvojče
-- selfServiceSizeOk / gear_limits.py); pořadí z ceníku. {helmet: [...], ...}
CREATE OR REPLACE FUNCTION public._kiosk_gear_sizes_catalog()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_object_agg(g.key, g.sizes), '{}'::jsonb)
    FROM (SELECT p.key, jsonb_agg(btrim(s.size) ORDER BY s.ord) AS sizes
            FROM gear_rental_prices p
            CROSS JOIN LATERAL unnest(p.sizes) WITH ORDINALITY AS s(size, ord)
           WHERE p.is_active AND p.kind = 'item' AND p.key IN ('helmet', 'jacket', 'pants', 'boots', 'gloves')
             AND btrim(COALESCE(s.size, '')) <> '' AND public._gear_ss_size_ok(p.key, s.size)
           GROUP BY p.key) g;
$$;

REVOKE ALL ON FUNCTION public._kiosk_gear_sizes_catalog() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._kiosk_gear_sizes_catalog() TO service_role;

CREATE OR REPLACE FUNCTION public._kiosk_protocol(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r record;
  v_parts text[];
  v_name text;
  v_gear jsonb;
BEGIN
  SELECT b.id, b.moto_id, b.handover_protocol_filled_at, b.gear_collected_at, b.handover_protocol_prompted_at,
         b.start_date, b.end_date,
         b.helmet_size, b.jacket_size, b.pants_size, b.boots_size, b.gloves_size,
         b.passenger_helmet_size, b.passenger_jacket_size, b.passenger_pants_size,
         b.passenger_boots_size, b.passenger_gloves_size,
         p.full_name, p.email, m.model, m.spz, m.tracking_unit,
         (m.license_required::text = 'N') AS is_child,
         b.booking_kind
    INTO r
    FROM bookings b
    LEFT JOIN profiles p    ON p.id = b.user_id
    LEFT JOIN motorcycles m ON m.id = b.moto_id
   WHERE b.id = p_booking_id;
  IF NOT FOUND THEN RETURN NULL; END IF;

  -- Jméno na displeji zkráceně (křestní + iniciála), fallback část e-mailu, nikdy NULL;
  -- tituly („Bc.", „Ing.", „Ph.D.") = tokeny končící tečkou se přeskočí
  SELECT coalesce(array_agg(p ORDER BY o), '{}'::text[]) INTO v_parts
    FROM unnest(regexp_split_to_array(btrim(coalesce(r.full_name, '')), '\s+')) WITH ORDINALITY AS u(p, o)
   WHERE p <> '' AND right(p, 1) <> '.';
  IF coalesce(v_parts[1], '') <> '' THEN
    v_name := v_parts[1] || CASE WHEN array_length(v_parts, 1) > 1
                                 THEN ' ' || left(v_parts[array_length(v_parts, 1)], 1) || '.' ELSE '' END;
  ELSE
    v_name := nullif(split_part(coalesce(r.email, ''), '@', 1), '');
  END IF;
  v_name := coalesce(v_name, '—');

  -- Půjčená výbava: jen neprázdné velikosti; field = sloupec bookings (Velín/edge)
  SELECT coalesce(jsonb_agg(jsonb_build_object('key', g.key, 'who', g.who, 'field', g.field, 'size', btrim(g.size))
                            ORDER BY g.ord), '[]'::jsonb)
    INTO v_gear
    FROM (VALUES
      (1,  'helmet', 'rider',     'helmet_size',           r.helmet_size),
      (2,  'jacket', 'rider',     'jacket_size',           r.jacket_size),
      (3,  'pants',  'rider',     'pants_size',            r.pants_size),
      (4,  'boots',  'rider',     'boots_size',            r.boots_size),
      (5,  'gloves', 'rider',     'gloves_size',           r.gloves_size),
      (6,  'helmet', 'passenger', 'passenger_helmet_size', r.passenger_helmet_size),
      (7,  'jacket', 'passenger', 'passenger_jacket_size', r.passenger_jacket_size),
      (8,  'pants',  'passenger', 'passenger_pants_size',  r.passenger_pants_size),
      (9,  'boots',  'passenger', 'passenger_boots_size',  r.passenger_boots_size),
      (10, 'gloves', 'passenger', 'passenger_gloves_size', r.passenger_gloves_size)
    ) AS g(ord, key, who, field, size)
   WHERE nullif(btrim(g.size), '') IS NOT NULL;

  RETURN jsonb_build_object(
    'booking_id',        r.id,
    'moto_id',           r.moto_id,          -- 2026-09-29: jednotka páruje čekající stav vrácení téže motorky
    'required',          (r.handover_protocol_filled_at IS NULL),
    'filled_at',         r.handover_protocol_filled_at,
    'needs_locker',      public._booking_needs_locker(r.id),
    'gear_collected_at', r.gear_collected_at,
    'prompted_at',       r.handover_protocol_prompted_at,
    'is_child',          coalesce(r.is_child, false),
    'data', jsonb_build_object(
      'customer_name', v_name,
      'moto_model',    r.model,
      'moto_spz',      r.spz,
      'start_date',    r.start_date,
      'end_date',      r.end_date,
      -- 2026-09-29: km vyplní systém (zákazník nezadává) = poslední stav (vrácení předchozím zákazníkem)
      'mileage',       public._handover_pickup_km(r.id),
      'mileage_unit',  CASE WHEN r.tracking_unit = 'mh' THEN 'mh' ELSE 'km' END,
      'gear',          v_gear))
    -- 2026-10-23 (kiosk 1.3.0, aditivní): gear_only = výpůjčka JEN výbavy (bez motorky — protokol bez motorkových
    -- částí, identita = kód šatny téže rezervace, žádná kóje); u ní sizes_catalog = velikosti z ceníku
    -- gear_rental_prices ∩ meze samoobsluhy (kiosk je vždy samoobsluha) — přednost před gear_sizes ze syncu
    || jsonb_build_object('gear_only', r.booking_kind = 'gear')
    || CASE WHEN r.booking_kind = 'gear'
            THEN jsonb_build_object('sizes_catalog', public._kiosk_gear_sizes_catalog()) ELSE '{}'::jsonb END;
EXCEPTION WHEN OTHERS THEN
  -- Fail-open (§0): NULL = stav neznámý → jednotka otevírá; chyba jednoho
  -- protokolu nesmí shodit resolve kódu ani celý sync_config pobočky.
  RAISE WARNING '_kiosk_protocol failed for booking %: %', p_booking_id, SQLERRM;
  RETURN NULL;
END;
$function$
;
