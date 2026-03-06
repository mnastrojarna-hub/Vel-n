-- ═══════════════════════════════════════════════════════════
-- MotoGo24 — SEED DATA
-- Produkční seed s reálnými daty z motos.js + motos-extra.js
-- ═══════════════════════════════════════════════════════════

-- ===== 1. POBOČKY =====

INSERT INTO branches (id, name, address, city, zip, coordinates, phone, email) VALUES
(
    '11111111-1111-1111-1111-111111111111',
    'MotoGo24 Mezná',
    'Mezná 9',
    'Mezná',
    '393 01',
    POINT(15.2245, 49.4314),
    '+420774256271',
    'mezna@motogo24.cz'
),
(
    '22222222-2222-2222-2222-222222222222',
    'MotoGo24 Brno',
    'Vídeňská 42',
    'Brno',
    '639 00',
    POINT(16.6068, 49.1951),
    '+420774256271',
    'brno@motogo24.cz'
);

-- ===== 2. MOTORKY (z motos.js + motos-extra.js) =====

INSERT INTO motorcycles (id, branch_id, model, category, license_required, power_kw, engine_cc, weight_kg, seat_height_mm, fuel_tank_l, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun, price_weekday, price_weekend, image_url, description, features, year, deposit_amount, status) VALUES
-- BMW R 1200 GS Adventure
(
    'a0000001-0000-0000-0000-000000000001',
    '11111111-1111-1111-1111-111111111111',
    'BMW R 1200 GS Adventure',
    'cestovni',
    'A',
    92, 1254, 268, 850, 30.0,
    4208, 3788, 3367, 3788, 4208, 4882, 4629,
    3788, 4629,
    'https://images.unsplash.com/photo-1558981359-219d6364c9c8?w=800&q=85&auto=format&fit=crop',
    'Legenda mezi adventure motorkami. Ideální pro dlouhé roadtripy po silnici i lehkém terénu. Boxer motor s charakteristickým zvukem, nádrž 30 L a prémiové vybavení z ní dělají perfektního společníka na každý výlet.',
    ARRAY['Cestovní enduro – prémiová třída','Dlouhé trasy, roadtripy, přejezdy','Jízda ve dvou (spolujezdec OK)','Silnice + lehký terén','Velcí jezdci 175–200 cm'],
    2023, 5000, 'active'
),
-- Jawa RVM 500 Adventure
(
    'a0000001-0000-0000-0000-000000000002',
    '11111111-1111-1111-1111-111111111111',
    'Jawa RVM 500 Adventure',
    'cestovni',
    'A2',
    35, 500, 195, 810, 18.0,
    1986, 1788, 1589, 1788, 1986, 2383, 2185,
    1788, 2185,
    'https://images.unsplash.com/photo-1609630875171-b1321377ee65?w=800&q=85&auto=format&fit=crop',
    'Moderní česká legenda v kategorii A2. Výborný poměr ceny a kvality. Díky omezení na 35 kW vhodná pro A2 průkaz. Pohodlná i na delší výlety, přívětivá pro menší jezdce.',
    ARRAY['Cestovní enduro – kategorie A2','Pro začátečníky i pokročilé','Menší a střední jezdci','Silnice + lehký terén','Výborná cena/výkon'],
    2023, 5000, 'active'
),
-- Benelli TRK 702 X
(
    'a0000001-0000-0000-0000-000000000003',
    '11111111-1111-1111-1111-111111111111',
    'Benelli TRK 702 X',
    'cestovni',
    'A2',
    35, 702, 215, 830, 20.0,
    2951, 2725, 2422, 2725, 2892, 3541, 3331,
    2725, 3331,
    'https://images.unsplash.com/photo-1547549082-6bc09f2049ae?w=800&q=85&auto=format&fit=crop',
    'Italský charakter a moderní crossover design. TRK 702X je adventure motorka pro vyšší jezdce kategorie A2 se solidní výbavou. Vhodná na silnici i nezpevněné cesty.',
    ARRAY['Crossover adventure – A2 kategorie','Vyšší jezdci 175–195 cm','Delší cesty a výlety','Silnice i nezpevněno','Italský design'],
    2022, 5000, 'active'
),
-- CF MOTO 800 MT
(
    'a0000001-0000-0000-0000-000000000004',
    '11111111-1111-1111-1111-111111111111',
    'CF MOTO 800 MT',
    'cestovni',
    'A',
    67, 800, 221, 835, 18.5,
    3941, 3663, 3256, 3663, 3892, 4729, 4476,
    3663, 4476,
    'https://images.unsplash.com/photo-1449426468159-d96dbf08f19f?w=800&q=85&auto=format&fit=crop',
    'Moderní adventure tourer s výkonným dvojválcem. Skvělá aerodynamika, velký nádrž a pohodlná ergonomie. Výborná volba pro dlouhé trasy i jízdu ve dvou.',
    ARRAY['Adventure tourer','Dlouhé roadtripy','Jízda ve dvou (spolujezdec OK)','Silnice + lehký terén','Výborný poměr cena/výkon'],
    2023, 5000, 'active'
),
-- Yamaha Niken GT
(
    'a0000001-0000-0000-0000-000000000005',
    '11111111-1111-1111-1111-111111111111',
    'Yamaha Niken GT',
    'cestovni',
    'A',
    84, 847, 263, 820, 18.0,
    3931, 3538, 3144, 3538, 3931, 4717, 4252,
    3538, 4252,
    'photos/yamaha-niken_1.jpg',
    'Unikátní tříkolová motorka s předními dvěma koly pro maximální stabilitu. Niken GT je revoluční stroj pro dobrodruhy, kteří chtějí zažít něco zcela jiného. Výborná stabilita v zatáčkách, pohodlné GT vybavení.',
    ARRAY['Tříkolová – unikátní zážitek','Extrémní stabilita v zatáčkách','GT výbava – vyhřívání, TFT displej','Dlouhé trasy','Pro zkušené jezdce'],
    2021, 5000, 'active'
),
-- Yamaha XT 660 X
(
    'a0000001-0000-0000-0000-000000000006',
    '11111111-1111-1111-1111-111111111111',
    'Yamaha XT 660 X',
    'supermoto',
    'A2',
    35, 659, 179, 895, 15.0,
    1986, 1788, 1589, 1788, 1986, 2383, 2185,
    1788, 2185,
    'photos/yamaha-xt660_1.jpg',
    'Legendární supermoto s jednoválcovým motorem. XT 660 X je ikonou mezi supermoto motorkami – lehká, agilní, perfektní pro město i silnici. Ideální pro jezdce A2 kategorie.',
    ARRAY['Supermoto – město i silnice','Lehká a agilní','Kategorie A2','Průjezd hustou zástavbou','Sportovní styl'],
    2018, 5000, 'active'
),
-- Kawasaki Z 900
(
    'a0000001-0000-0000-0000-000000000007',
    '11111111-1111-1111-1111-111111111111',
    'Kawasaki Z 900',
    'naked',
    'A',
    95, 948, 193, 795, 17.0,
    3514, 3163, 2811, 3163, 3514, 4217, 3865,
    3163, 3865,
    'photos/kawasaki-z900_1.jpg',
    'Čtyřválcový naked bike plný adrenalinu. Kawasaki Z 900 nabízí brutální výkon, ostrý design a moderní elektroniku. Perfektní volba pro jezdce, kteří chtějí výkon a styl v jednom.',
    ARRAY['Naked bike – sportovní jízda','Čtyřválcový motor – brutální výkon','Moderní elektronika','Styl a výkon','Pro zkušené jezdce'],
    2022, 5000, 'active'
),
-- Yamaha MT-09
(
    'a0000001-0000-0000-0000-000000000008',
    '11111111-1111-1111-1111-111111111111',
    'Yamaha MT-09',
    'naked',
    'A',
    87, 847, 193, 820, 14.0,
    3097, 2788, 2478, 2788, 3097, 3717, 3407,
    2788, 3407,
    'photos/yamaha-mt09_1.jpg',
    'Trojválcový naked bike se zuřivým charakterem. Yamaha MT-09 je "Dark Side of Japan" – agresivní, zábavný a nepředvídatelný. Výborná volba pro jezdce, kteří chtějí maximální zábavu na silnici.',
    ARRAY['Naked bike – maximální zábava','Trojválcový motor – unikátní charakter','Agresivní výkon','Lehká a agilní','Dark Side of Japan'],
    2017, 5000, 'active'
),
-- Yamaha XTZ 1200 Super Ténéré
(
    'a0000001-0000-0000-0000-000000000009',
    '11111111-1111-1111-1111-111111111111',
    'Yamaha XTZ 1200 Super Ténéré',
    'cestovni',
    'A',
    76, 1199, 261, 845, 23.0,
    4417, 3975, 3533, 3975, 4417, 5300, 4858,
    3975, 4858,
    'photos/yamaha-tenere_1.jpg',
    'Rallye legenda pro silnici. Yamaha Super Ténéré je inspirována vítězi Dakaru – výkonný dvojválec, obří nádrž a výborná ergonomie pro extrémně dlouhé trasy. Dokonalý cestovní partner.',
    ARRAY['Rallye adventure – inspirace Dakarem','Obrovský dojezd','Extrémně pohodlná','Jízda ve dvou','Silnice + terén'],
    2019, 5000, 'active'
),
-- Ducati Multistrada 1200 ABS
(
    'a0000001-0000-0000-0000-000000000010',
    '11111111-1111-1111-1111-111111111111',
    'Ducati Multistrada 1200 ABS',
    'cestovni',
    'A',
    104, 1198, 229, 820, 20.0,
    3486, 3138, 2789, 3138, 3486, 4183, 3835,
    3138, 3835,
    'photos/ducati-multistrada_1.jpg',
    'Italská vášeň v podobě adventure motorky. Ducati Multistrada 1200 nabízí brutální výkon L-twin motoru, prémiové elektronické systémy a charakteristický italský zvuk. Pro milovníky Ducati.',
    ARRAY['Italský L-twin – unikátní zvuk','Prémiová elektronika – 4 jízdní režimy','Silnice i terén','Jízda ve dvou','Pro zkušené jezdce'],
    2015, 5000, 'active'
),
-- KTM 1290 Super Adventure
(
    'a0000001-0000-0000-0000-000000000011',
    '11111111-1111-1111-1111-111111111111',
    'KTM 1290 Super Adventure',
    'cestovni',
    'A',
    118, 1301, 218, 850, 23.0,
    4625, 4163, 3700, 4163, 4625, 5550, 5088,
    4163, 5088,
    'photos/ktm-1290_1.jpg',
    'Ready to Race v adventure světě. KTM 1290 Super Adventure je nejextrémnější adventure motorka v naší flotile. Výkonný V-twin, prémiová WP elektronika a oranzové barvy KTM. Pro skutečné dobrodruhy.',
    ARRAY['Nejvýkonnější adventure v nabídce','V-twin 160 koní – extrémní výkon','WP elektronika – terén i silnice','Prémiové vybavení','Pouze pro zkušené'],
    2017, 5000, 'active'
),
-- Yamaha PW 50
(
    'a0000001-0000-0000-0000-000000000012',
    '11111111-1111-1111-1111-111111111111',
    'Yamaha PW 50',
    'detske',
    'A1',
    1, 49, 25, 485, 0,
    1333, 1200, 1067, 1200, 1333, 1600, 1467,
    1200, 1467,
    'photos/yamaha-pw50_1.jpg',
    'Malý pomocník pro velké začátky. Yamaha PW 50 je legendární dětská motorka pro první kroky v motosportu. Automatická převodovka, nízké sedlo a maximálních 50 ccm jsou ideální pro děti od 3 let.',
    ARRAY['Dětská motorka – od 3 let','Automatická převodovka','Nízké sedlo – 485 mm','Omezovač plynu pro rodiče','Legendární volba pro začátky'],
    2016, 2000, 'active'
),
-- KTM SX 65
(
    'a0000001-0000-0000-0000-000000000013',
    '11111111-1111-1111-1111-111111111111',
    'KTM SX 65',
    'detske',
    'A1',
    8, 65, 49, 670, 0,
    1000, 1000, 1000, 1000, 1200, 1200, 1200,
    1000, 1200,
    'photos/ktm-sx65_1.jpg',
    'Závodní motokros pro mladé piloty. KTM SX 65 je skutečná závodní motorka v malém provedení – pro děti 7–12 let. Výkonný dvoutaktní motor, závodní podvozek a oranžové KTM barvy.',
    ARRAY['Závodní motokros pro děti','Dvoutaktní motor – závodní výkon','Věk 7–12 let','Uzavřené tratě / areály','Výchozí bod závodní kariéry'],
    2020, 2000, 'active'
),
-- Triumph Tiger 1200 Explorer
(
    'a0000001-0000-0000-0000-000000000014',
    '11111111-1111-1111-1111-111111111111',
    'Triumph Tiger 1200 Explorer',
    'cestovni',
    'A',
    96, 1215, 259, 810, 20.0,
    4208, 3788, 3367, 3788, 4208, 5050, 4629,
    3788, 4629,
    'photos/triumph-tiger_1.jpg',
    'Britský elegán pro světové dobrodružství. Triumph Tiger 1200 Explorer je prémiová adventure motorka s trojválcovým motorem, bohatou výbavou a elegantním britským designem. Ideální pro dlouhé transcontinentální jízdy.',
    ARRAY['Britský trojválec – unikátní charakter','Prémiové GT vybavení','Transcontinentální cestování','Jízda ve dvou','Elegantní design'],
    2018, 5000, 'active'
);

-- ===== 3. EXTRAS KATALOG =====

INSERT INTO extras_catalog (id, name, category, price_per_day, branch_id, available) VALUES
('e0000001-0000-0000-0000-000000000001', 'Helma přilba L', 'ochranné', 150, '11111111-1111-1111-1111-111111111111', 5),
('e0000001-0000-0000-0000-000000000002', 'Helma přilba XL', 'ochranné', 150, '11111111-1111-1111-1111-111111111111', 5),
('e0000001-0000-0000-0000-000000000003', 'Bunda S', 'ochranné', 100, '11111111-1111-1111-1111-111111111111', 3),
('e0000001-0000-0000-0000-000000000004', 'Bunda M', 'ochranné', 100, '11111111-1111-1111-1111-111111111111', 3),
('e0000001-0000-0000-0000-000000000005', 'Bunda L', 'ochranné', 100, '11111111-1111-1111-1111-111111111111', 3),
('e0000001-0000-0000-0000-000000000006', 'Bunda XL', 'ochranné', 100, '11111111-1111-1111-1111-111111111111', 3),
('e0000001-0000-0000-0000-000000000007', 'Rukavice', 'ochranné', 50, '11111111-1111-1111-1111-111111111111', 6),
('e0000001-0000-0000-0000-000000000008', 'Boční kufry pár', 'zavazadla', 200, '11111111-1111-1111-1111-111111111111', 4),
('e0000001-0000-0000-0000-000000000009', 'Top case', 'zavazadla', 100, '11111111-1111-1111-1111-111111111111', 4),
('e0000001-0000-0000-0000-000000000010', 'GPS navigace', 'navigace', 150, '11111111-1111-1111-1111-111111111111', 3),
-- Brno duplicity
('e0000001-0000-0000-0000-000000000011', 'Helma přilba L', 'ochranné', 150, '22222222-2222-2222-2222-222222222222', 3),
('e0000001-0000-0000-0000-000000000012', 'Helma přilba XL', 'ochranné', 150, '22222222-2222-2222-2222-222222222222', 3),
('e0000001-0000-0000-0000-000000000013', 'Bunda M', 'ochranné', 100, '22222222-2222-2222-2222-222222222222', 2),
('e0000001-0000-0000-0000-000000000014', 'Bunda L', 'ochranné', 100, '22222222-2222-2222-2222-222222222222', 2),
('e0000001-0000-0000-0000-000000000015', 'Rukavice', 'ochranné', 50, '22222222-2222-2222-2222-222222222222', 4),
('e0000001-0000-0000-0000-000000000016', 'GPS navigace', 'navigace', 150, '22222222-2222-2222-2222-222222222222', 2);

-- ===== 4. PRICING RULES =====

INSERT INTO pricing_rules (name, type, modifier, valid_from, valid_to, min_days, promo_code, active) VALUES
-- Sezóna duben–září: +15%
('Hlavní sezóna (duben–září)', 'seasonal', 1.15, '2026-04-01', '2026-09-30', NULL, NULL, true),
-- Long-term slevy
('7+ dní sleva 10%', 'long_term', 0.90, NULL, NULL, 7, NULL, true),
('14+ dní sleva 15%', 'long_term', 0.85, NULL, NULL, 14, NULL, true),
-- Promo kód
('PRVNIJIZDA – 20% sleva', 'promo', 0.80, '2026-01-01', '2026-12-31', NULL, 'PRVNIJIZDA', true);

-- ===== 5. PROMO KÓDY =====

INSERT INTO promo_codes (code, type, value, valid_from, valid_to, max_uses, active) VALUES
('PRVNIJIZDA', 'percent', 20, '2026-01-01', '2026-12-31', 100, true),
('MOTO10', 'percent', 10, '2026-01-01', '2026-12-31', 200, true),
('MOTO20', 'percent', 20, '2026-01-01', '2026-12-31', 50, true),
('JARO25', 'percent', 25, '2026-03-01', '2026-05-31', 30, true);

-- ===== 6. ADMIN SUPERADMIN =====

-- Insert admin user into auth.users (Supabase manages this, but we seed it)
-- NOTE: In production, create the user via Supabase Auth UI/API first,
-- then INSERT into admin_users only. This seed assumes the user already exists.

-- Vytvoření admina: admin@motogo24.cz
-- Heslo se nastavuje přes Supabase Auth, zde jen reference
DO $$
DECLARE
    v_admin_id UUID := 'ad000001-0000-0000-0000-000000000001';
BEGIN
    -- Pokus o INSERT do auth.users (funguje jen s service_role key)
    -- V produkci se admin vytváří přes Supabase Dashboard
    BEGIN
        INSERT INTO auth.users (
            id,
            instance_id,
            email,
            encrypted_password,
            email_confirmed_at,
            raw_app_meta_data,
            raw_user_meta_data,
            role,
            aud,
            created_at,
            updated_at
        ) VALUES (
            v_admin_id,
            '00000000-0000-0000-0000-000000000000',
            'admin@motogo24.cz',
            crypt('MotoGo24Admin!2026', gen_salt('bf')),
            NOW(),
            '{"provider": "email", "providers": ["email"]}'::jsonb,
            '{"full_name": "MotoGo24 Admin"}'::jsonb,
            'authenticated',
            'authenticated',
            NOW(),
            NOW()
        );
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'auth.users INSERT skipped (user may already exist or insufficient permissions)';
    END;

    -- Profil
    BEGIN
        INSERT INTO profiles (id, email, full_name, phone, language)
        VALUES (v_admin_id, 'admin@motogo24.cz', 'MotoGo24 Admin', '+420774256271', 'cs');
    EXCEPTION WHEN unique_violation THEN
        RAISE NOTICE 'Profile already exists';
    END;

    -- Admin role
    INSERT INTO admin_users (id, role, branch_access, permissions)
    VALUES (
        v_admin_id,
        'superadmin',
        ARRAY['11111111-1111-1111-1111-111111111111'::UUID, '22222222-2222-2222-2222-222222222222'::UUID],
        '{"all": true}'::jsonb
    )
    ON CONFLICT (id) DO UPDATE SET role = 'superadmin', branch_access = EXCLUDED.branch_access;
END;
$$;

-- ===== 7. CMS VARIABLES =====

INSERT INTO cms_variables (key, value, category, description) VALUES
('company_name', '"MotoGo24 s.r.o."', 'content', 'Název firmy'),
('company_phone', '"+420774256271"', 'content', 'Hlavní telefon'),
('company_email', '"info@motogo24.cz"', 'content', 'Hlavní e-mail'),
('company_web', '"https://motogo24.cz"', 'content', 'Webová stránka'),
('default_deposit', '5000', 'pricing', 'Výchozí záloha v CZK'),
('season_start', '"2026-04-01"', 'pricing', 'Začátek hlavní sezóny'),
('season_end', '"2026-09-30"', 'pricing', 'Konec hlavní sezóny'),
('delivery_price_per_km', '15', 'pricing', 'Cena za km přistavení'),
('min_rental_days', '1', 'pricing', 'Minimální délka pronájmu'),
('max_rental_days', '30', 'pricing', 'Maximální délka pronájmu');

-- ===== 8. FEATURE FLAGS =====

INSERT INTO feature_flags (key, enabled, description) VALUES
('ai_assistant', true, 'AI asistent v admin panelu'),
('online_payments', true, 'Online platby (Stripe)'),
('document_scanner', true, 'Skenování dokladů v appce'),
('push_notifications', true, 'Push notifikace'),
('whatsapp_integration', false, 'WhatsApp integrace'),
('multi_language', true, 'Vícejazyčná podpora (CZ/EN/DE)'),
('sos_system', true, 'SOS systém pro zákazníky'),
('delivery_service', true, 'Přistavení motorky');

-- ===== 9. NOTIFICATION RULES =====

INSERT INTO notification_rules (name, trigger_type, conditions, actions, enabled) VALUES
('Servis za 500 km', 'mileage', '{"threshold_km": 500}', '{"notify": "admin", "channel": "email", "template": "service_due"}', true),
('Booking potvrzení', 'booking_status', '{"status": "active"}', '{"notify": "customer", "channel": "email", "template": "booking_confirmed"}', true),
('SOS alert', 'sos', '{"types": ["accident_major", "theft"]}', '{"notify": "admin", "channel": "sms", "template": "sos_alert", "phone": "+420774256271"}', true),
('Nízký sklad', 'stock_level', '{"below_min": true}', '{"notify": "admin", "channel": "email", "template": "low_stock"}', true);

-- ===== 10. DOCUMENT TEMPLATES =====

INSERT INTO document_templates (type, name, html_content, variables, version, status) VALUES
('smlouva', 'Nájemní smlouva – standard', '<h1>Nájemní smlouva</h1><p>Pronajímatel: {{company_name}}</p><p>Nájemce: {{customer_name}}</p><p>Předmět: {{moto_model}}</p><p>Období: {{start_date}} – {{end_date}}</p><p>Cena: {{total_price}} CZK</p>', '["company_name","customer_name","moto_model","start_date","end_date","total_price"]', 1, 'active'),
('protokol', 'Předávací protokol', '<h1>Předávací protokol</h1><p>Motorka: {{moto_model}}</p><p>Stav km: {{mileage}}</p><p>Stav paliva: {{fuel_level}}</p><p>Poznámky: {{notes}}</p>', '["moto_model","mileage","fuel_level","notes"]', 1, 'active'),
('vop', 'Všeobecné obchodní podmínky', '<h1>VOP MotoGo24</h1><p>Platné od 1.1.2026</p>', '[]', 1, 'active');
