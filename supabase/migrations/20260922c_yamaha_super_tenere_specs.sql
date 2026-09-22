-- =============================================================================
-- 2026-09-22 — Yamaha XTZ 1200 Super Ténéré (MY2016, facelift 2014+): karta stroje
-- Datová migrace (bez schema změn), idempotentní.
-- Kus id a0000001-0000-0000-0000-000000000009 byl v DB založený jen s názvem.
-- Zdroj: veřejné tovární údaje Yamaha pro XT1200Z MY2014–2016.
--
-- UŽ APLIKOVÁNO RUČNĚ v SQL editoru 2026-09-22 (ověřeno kontrolním SELECTem).
-- Guard `coalesce(description,'') = ''` → na živé DB je re-aplikace no-op, takže
-- nepřepíše popis/výbavu, kdyby byly mezitím upravené ve Velíně. Soubor slouží
-- jako evidence změny + obnova pro případ nové/prázdné DB.
-- NEmění: model, spz, vin, mileage, color, fotky, ceny, kauci, pobočku, status
-- (doplňuje uživatel ručně ve Velíně). Překlady doplní edge `translate-content`.
-- =============================================================================
UPDATE public.motorcycles SET
  brand         = 'Yamaha',
  year          = 2016,                 -- dle zadání — ověřit v TP
  category      = 'cestovni',
  engine_cc     = 1199,
  power_kw      = 82.4,                 -- 112 k @ 7 250 ot./min
  power_hp      = 112,
  torque_nm     = 117,                  -- @ 6 000 ot./min
  fuel_tank_l   = 23,
  weight_kg     = 257,                  -- provozní hmotnost (plná nádrž)
  seat_height_mm = 845,                 -- dvoupolohové sedlo 845 / 870 mm
  top_speed_kmh = 210,                  -- orientační (výrobce neudává)
  fuel_consumption_l100km = 5.7,        -- WMTC dle Yamaha
  fuel_type     = 'Natural 95',
  engine_type   = 'řadový dvouválec 4T, DOHC, kapalinou chlazený, kliková hřídel 270°, vstřikování YCC-T',
  transmission  = '6stupňová manuální',
  drivetrain    = 'shaft',
  brake_type    = 'kotoučové — vpředu 2×310 mm, vzadu 282 mm, ABS + sdružené brzdy (UBS)',
  seats_count   = 2,
  has_abs       = true,
  has_asc       = true,                 -- trakční kontrola TCS (2 stupně + vyp.)
  license_required = 'A',
  license_groups   = ARRAY['A'],
  features      = ARRAY[
    'ABS se sdruženými brzdami (Unified Brake System)',
    'Trakční kontrola TCS (2 stupně, lze vypnout)',
    'Jízdní režimy D-Mode (Touring / Sport)',
    'Tempomat',
    'Ride-by-wire (YCC-T)',
    'Kardanový pohon (bez řetězu)',
    'Výškově nastavitelné plexi',
    'Dvoupolohové sedlo 845 / 870 mm',
    'USD vidlice 43 mm, plně nastavitelná, zdvih 190 mm',
    'Zadní tlumič s dálkovým nastavením předpětí',
    'Drátová kola s bezdušovými pneu (19" / 17")',
    'Centrální stojan',
    '12V zásuvka',
    'LCD přístrojový panel',
    'Nádrž 23 l — dojezd přes 400 km'
  ],
  description   = 'Velké cestovní enduro, se kterým zvládneš dálnici, alpské průsmyky i šotolinu na jeden zátah. Řadový dvouválec 1 199 cm³ s klikou 270° dává 82,4 kW / 112 koní a hlavně 117 Nm točivého momentu už od nízkých otáček — motorka táhne líně a jistě, s plnou výbavou i se spolujezdcem. O bezúdržbový přenos síly se stará kardan, elektronika nabízí ABS se sdruženými brzdami, trakční kontrolu, dva jízdní režimy D-Mode a tempomat na dlouhé přesuny. Plně nastavitelná USD vidlice se zdvihem 190 mm a drátová kola s bezdušovými pneumatikami se nezaleknou ani rozbité cesty. Nádrž na 23 litrů při spotřebě kolem 5,7 l/100 km znamená dojezd přes 400 km, výškově nastavitelné plexi a dvoupolohové sedlo si přizpůsobíš sobě. Ideální stroj pro vícedenní cestu kamkoliv v Evropě — vyžaduje řidičák skupiny A.',
  ideal_usage   = ARRAY[                -- POZOR: sloupec je text[] (pole krátkých tagů)
    'Dálkové cestování a dovolená na motorce',
    'Jízda ve dvou s plnou výbavou',
    'Alpy a horské průsmyky',
    'Zpevněná šotolina a lehký terén',
    'Denní přesuny po dálnici'
  ],
  suitable_for  = 'Pro zkušené jezdce s řidičákem skupiny A, kteří plánují delší cestu — víkend v Alpách, týden na Balkáně nebo cestu k moři.
Díky točivému dvouválci, kardanu, tempomatu a velké nádrži je stavěná na kilometry: pohodlně vezme spolujezdce i kufry a nemusíš řešit řetěz.
Vyšší sedlo (845 / 870 mm) a hmotnost 257 kg ocení spíš vyšší a silnější jezdec; pro úplné začátečníky není vhodná.',
  short_desc_fields = CASE
    WHEN cardinality(coalesce(short_desc_fields, '{}')) = 0
    THEN ARRAY['engine','drivetrain','fuel_consumption_l100km','fuel_tank_l','weight_kg','seat_height_mm','license_required']
    ELSE short_desc_fields                -- už nastavené pole nepřepisujeme
  END,
  updated_at    = now()
WHERE id = 'a0000001-0000-0000-0000-000000000009'
  AND coalesce(description, '') = '';   -- guard: jen prázdná karta (viz hlavička)
