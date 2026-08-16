-- =============================================================================
-- 2026-08-16 — Linhai ADV 125: doplnění karty stroje + plošné zlevnění úterý
-- Datová migrace (bez schema změn), idempotentní.
--
-- 1) Linhai (id 18fe5633-…) — technické údaje z COC / informačního dokumentu
--    výrobce (Jiangsu Linhai Power Machinery Group): motor LH152MI-A,
--    124.4 cm3, 8.3 kW @ 8000 min-1, max 94 km/h, 3.3 l/100 km, Euro 5+,
--    2 místa, CVT. Výbava (TCS/ABS/plexi/kufr) ověřena z fotek kusu.
-- 2) Ceník: u VŠECH motorek úterní cena = středeční (zlevnění úterý)
--    v OBOU úložištích (moto_day_prices + zrcadlo motorcycles.price_*)
--    + přepočet price_weekday (průměr po–pá, stejná logika jako PricingTab).
-- =============================================================================

-- 1) Linhai ADV 125 — vyplnění karty stroje
UPDATE public.motorcycles SET
  model         = 'Linhai ADV 125',
  brand         = 'Linhai',
  color         = 'matná černá',
  engine_cc     = 124,   -- COC 3.2.1.5: přesně 124.4 cm3
  power_kw      = 8.3,   -- COC 1.9: 8.3 kW @ 8000 min-1
  power_hp      = 11,
  top_speed_kmh = 94,    -- COC 1.8
  fuel_consumption_l100km = 3.3,  -- COC 4.0.2
  fuel_type     = 'Natural 95',
  engine_type   = 'jednoválec 4T, vstřikování (EFI), Euro 5+',
  transmission  = 'automatická (CVT variátor)',
  drivetrain    = 'belt',
  brake_type    = 'kotoučové (ABS + TCS)',
  seats_count   = 2,     -- COC 6.16.1
  weight_kg     = 138,   -- odvozeno z COC 1.10 (poměr 0.06 kW/kg při 8.3 kW)
  has_asc       = true,  -- trakční kontrola TCS (samolepka TCS na kapotáži)
  features      = ARRAY[
    'ABS',
    'Trakční kontrola (TCS)',
    'LED světlomety',
    'Digitální přístrojový panel',
    'Vysoké plexi',
    'Chrániče rukou',
    'Hliníkový zadní kufr',
    'Homologace pro 2 osoby',
    'Emisní norma Euro 5+'
  ],
  description   = 'Adventure skútr v matně černém provedení — kombinuje pohodlnou jízdu po městě s odolností malého cestovního endura. Zážehový jednoválec LH152MI-A (124,4 cm³) dává 8,3 kW / 11 koní při 8 000 ot./min a o řazení se stará bezstarostný CVT automat — prostě přidáš plyn a jedeš. Spotřeba jen 3,3 l/100 km (Euro 5+), maximálka 94 km/h. Polooffroadové pneumatiky (14"/13"), ABS a trakční kontrola TCS si poradí i s horší cestou, vysoké plexi a chrániče rukou přidají komfort a do hliníkového kufru se vejde helma i nákup. Homologován pro dvě osoby. Stačí ti řidičák skupiny B (nebo A1).',
  ideal_usage   = ARRAY[         -- POZOR: sloupec je text[] (pole krátkých tagů)
    'Město a dojíždění',
    'Lehké výlety po okreskách',
    'Občasná lehká šotolina',
    'První stroj — stačí ŘP skupiny B'
  ],
  suitable_for  = 'Pro každého, kdo se chce svézt bez motorkářského řidičáku — stačí skupina B (automat) nebo A1.
Skvělý pro začátečníky a dojíždění po městě, ale díky adventure podvozku, vyšší stavbě a prostornému kufru zvládne i celodenní výlet po okreskách či lehkou šotolinu.
Vezme i spolujezdce.',
  image_alts    = ARRAY[
    'zepředu z boku, s hliníkovým kufrem',
    'z boku',
    'kokpit s digitálním displejem',
    'zepředu — LED světla a vysoké plexi'
  ],
  updated_at    = now()
WHERE id = '18fe5633-86cd-48d6-a0d4-8b8cc8d3badb';

-- 2a) CENÍK — úterý = středa, primární úložiště Velína (moto_day_prices)
UPDATE public.moto_day_prices
SET    price_tuesday = price_wednesday
WHERE  price_tuesday IS DISTINCT FROM price_wednesday;

-- 2b) CENÍK — zrcadlo v motorcycles (čte web i appka) + přepočet price_weekday
--     (round(průměr po–pá); price_weekend se nemění — so/ne beze změny)
UPDATE public.motorcycles
SET    price_tue     = price_wed,
       price_weekday = round((coalesce(price_mon,0) + 2*coalesce(price_wed,0)
                             + coalesce(price_thu,0) + coalesce(price_fri,0)) / 5.0)
WHERE  price_tue IS DISTINCT FROM price_wed;
