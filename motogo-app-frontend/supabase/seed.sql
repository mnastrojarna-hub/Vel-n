-- ===== MotoGo24 – Seed Data =====
-- Realistic test data for 2 branches, 10 motorcycles, 5 users, 20 bookings
-- Run AFTER schema.sql

-- ===== 1. BRANCHES =====
INSERT INTO branches (id, name, address, city, zip, coordinates, phone, email) VALUES
(
    'b0000001-0000-0000-0000-000000000001',
    'MotoGo24 Mezná',
    'Mezná 9',
    'Pelhřimov',
    '393 01',
    POINT(15.2245, 49.4314),
    '+420 774 256 000',
    'mezna@motogo24.cz'
),
(
    'b0000001-0000-0000-0000-000000000002',
    'MotoGo24 Brno',
    'Vídeňská 42',
    'Brno',
    '639 00',
    POINT(16.6068, 49.1951),
    '+420 774 256 001',
    'brno@motogo24.cz'
);

-- ===== 2. TEST USERS (auth.users entries) =====
-- In real Supabase, users are created via auth.signUp().
-- For seeding, we insert directly into auth.users and profiles.
-- NOTE: Run these only in a development/test environment!

-- User 1: Jan Novák (A license)
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, raw_user_meta_data)
VALUES (
    'u0000001-0000-0000-0000-000000000001',
    'jan.novak@email.cz',
    crypt('Test1234!', gen_salt('bf')),
    NOW(),
    '{"full_name":"Jan Novák"}'::jsonb
);
INSERT INTO profiles (id, email, full_name, phone, license_group, date_of_birth, street, city, zip, gear_sizes)
VALUES (
    'u0000001-0000-0000-0000-000000000001',
    'jan.novak@email.cz',
    'Jan Novák',
    '+420 774 256 000',
    ARRAY['A']::license_group[],
    '1990-05-15',
    'Lipová 12',
    'Praha',
    '110 00',
    '{"helmet":"L","jacket":"52","pants":"50","gloves":"L","boots":"43"}'::jsonb
);

-- User 2: Marie Svobodová (A2 license)
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, raw_user_meta_data)
VALUES (
    'u0000001-0000-0000-0000-000000000002',
    'marie.svobodova@email.cz',
    crypt('Test1234!', gen_salt('bf')),
    NOW(),
    '{"full_name":"Marie Svobodová"}'::jsonb
);
INSERT INTO profiles (id, email, full_name, phone, license_group, date_of_birth, street, city, zip)
VALUES (
    'u0000001-0000-0000-0000-000000000002',
    'marie.svobodova@email.cz',
    'Marie Svobodová',
    '+420 602 111 222',
    ARRAY['A2']::license_group[],
    '1995-08-22',
    'Hlavní 45',
    'Brno',
    '602 00'
);

-- User 3: Petr Dvořák (A, A1 licenses)
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, raw_user_meta_data)
VALUES (
    'u0000001-0000-0000-0000-000000000003',
    'petr.dvorak@email.cz',
    crypt('Test1234!', gen_salt('bf')),
    NOW(),
    '{"full_name":"Petr Dvořák"}'::jsonb
);
INSERT INTO profiles (id, email, full_name, phone, license_group, date_of_birth, street, city, zip)
VALUES (
    'u0000001-0000-0000-0000-000000000003',
    'petr.dvorak@email.cz',
    'Petr Dvořák',
    '+420 603 333 444',
    ARRAY['A','A1']::license_group[],
    '1988-01-10',
    'Nádražní 8',
    'Plzeň',
    '301 00'
);

-- User 4: Eva Procházková (A license)
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, raw_user_meta_data)
VALUES (
    'u0000001-0000-0000-0000-000000000004',
    'eva.prochazkova@email.cz',
    crypt('Test1234!', gen_salt('bf')),
    NOW(),
    '{"full_name":"Eva Procházková"}'::jsonb
);
INSERT INTO profiles (id, email, full_name, phone, license_group, date_of_birth, street, city, zip)
VALUES (
    'u0000001-0000-0000-0000-000000000004',
    'eva.prochazkova@email.cz',
    'Eva Procházková',
    '+420 604 555 666',
    ARRAY['A']::license_group[],
    '1992-11-30',
    'Korunní 88',
    'Praha',
    '130 00'
);

-- User 5: Tomáš Krejčí (A2 license)
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, raw_user_meta_data)
VALUES (
    'u0000001-0000-0000-0000-000000000005',
    'tomas.krejci@email.cz',
    crypt('Test1234!', gen_salt('bf')),
    NOW(),
    '{"full_name":"Tomáš Krejčí"}'::jsonb
);
INSERT INTO profiles (id, email, full_name, phone, license_group, date_of_birth, street, city, zip)
VALUES (
    'u0000001-0000-0000-0000-000000000005',
    'tomas.krejci@email.cz',
    'Tomáš Krejčí',
    '+420 605 777 888',
    ARRAY['A2']::license_group[],
    '1998-03-05',
    'Masarykova 15',
    'Ostrava',
    '702 00'
);

-- ===== 3. MOTORCYCLES =====
INSERT INTO motorcycles (id, branch_id, model, vin, spz, category, license_required, power_kw, engine_cc, weight_kg, seat_height_mm, fuel_tank_l, price_weekday, price_weekend, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun, status, mileage, image_url, features, description) VALUES
-- Mezná branch
('m0000001-0000-0000-0000-000000000001', 'b0000001-0000-0000-0000-000000000001',
 'Jawa RVM 500 Adventure', 'JAWA500ADV2024001', '4A1 2345',
 'adventure', 'A', 33, 471, 200, 830, 18,
 2200, 2600, 2200, 2200, 2200, 2200, 2600, 2600, 2600,
 'active', 12500,
 'https://images.unsplash.com/photo-1609630875171-b1321377ee65?w=800',
 ARRAY['Adventure touring','Lehký a obratný','Kategorie A','ABS','LED osvětlení'],
 'Česká legenda v adventure provedení. Jawa RVM 500 je ideální pro cestování i každodenní jízdu.'),

('m0000001-0000-0000-0000-000000000002', 'b0000001-0000-0000-0000-000000000001',
 'BMW R 1200 GS Adventure', 'BMW1200GS2020001', '4A2 6789',
 'adventure', 'A', 92, 1170, 249, 850, 30,
 2600, 3000, 2600, 2600, 2600, 2600, 3000, 3000, 3000,
 'active', 38000,
 'https://images.unsplash.com/photo-1558981359-219d6364c9c8?w=800',
 ARRAY['Prémiové adventure','Boxer motor','Cestování ve dvou','Elektronické odpružení','GPS navigace'],
 'Král adventure segmentu. BMW R 1200 GS Adventure je nejprodávanější adventure motorka na světě.'),

('m0000001-0000-0000-0000-000000000003', 'b0000001-0000-0000-0000-000000000001',
 'Benelli TRK 702X', 'BEN702X2023001', '4A3 1111',
 'adventure', 'A', 55, 698, 230, 840, 20,
 2400, 2800, 2400, 2400, 2400, 2400, 2800, 2800, 2800,
 'active', 8200,
 'https://images.unsplash.com/photo-1547549082-6bc09f2049ae?w=800',
 ARRAY['Italský adventure','Dvojválec','Komfortní jízda','Velká nádrž','ABS'],
 'Italský středotonážní adventure s výborným poměrem cena/výkon.'),

('m0000001-0000-0000-0000-000000000004', 'b0000001-0000-0000-0000-000000000001',
 'CF MOTO 800 MT', 'CFM800MT2023001', '4A4 2222',
 'adventure', 'A', 70, 799, 230, 830, 19,
 2600, 3000, 2600, 2600, 2600, 2600, 3000, 3000, 3000,
 'active', 5300,
 'https://images.unsplash.com/photo-1449426468159-d96dbf08f19f?w=800',
 ARRAY['Moderní adventure','Vyspělá elektronika','BOSCH ABS','Jízda ve dvou','Dobrá cena'],
 'Moderní čínský adventure s KTM technologiemi. CF MOTO 800 MT překvapí kvalitou.'),

('m0000001-0000-0000-0000-000000000005', 'b0000001-0000-0000-0000-000000000001',
 'Honda CRF 1100L Africa Twin', 'HON1100AT2022001', '4A5 3333',
 'adventure', 'A', 75, 1084, 226, 850, 24,
 2800, 3200, 2800, 2800, 2800, 2800, 3200, 3200, 3200,
 'active', 22000,
 'https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=800',
 ARRAY['Legendární Africa Twin','DCT automatická převodovka','Terénní schopnosti','Spolehlivost Honda','Rally heritage'],
 'Legendární Africa Twin v nejnovější generaci. Spolehlivost a výkon pro nejnáročnější cesty.'),

('m0000001-0000-0000-0000-000000000006', 'b0000001-0000-0000-0000-000000000001',
 'Yamaha XT 660 X', 'YAM660X2018001', '4A6 4444',
 'supermoto', 'A2', 35, 659, 179, 895, 15,
 1800, 2100, 1800, 1800, 1800, 1800, 2100, 2100, 2100,
 'active', 31000,
 'https://images.unsplash.com/photo-1568772585407-9361f9bf3a87?w=800',
 ARRAY['Supermoto','Lehká a agilní','Kategorie A2','Město i silnice','Sportovní styl'],
 'Legendární supermoto pro kategorii A2. Ideální pro město i okolí.'),

('m0000001-0000-0000-0000-000000000007', 'b0000001-0000-0000-0000-000000000001',
 'Kawasaki Z 900', 'KAW900Z2022001', '4A7 5555',
 'naked', 'A', 95, 948, 193, 795, 17,
 2800, 3200, 2800, 2800, 2800, 2800, 3200, 3200, 3200,
 'active', 9800,
 'https://images.unsplash.com/photo-1609149040535-1e5b6f7aaab4?w=800',
 ARRAY['Naked bike','Čtyřválcový motor','Brutální výkon','Moderní elektronika','Pro zkušené'],
 'Čtyřválcový naked bike plný adrenalinu. Z 900 nabízí výkon a styl.'),

('m0000001-0000-0000-0000-000000000008', 'b0000001-0000-0000-0000-000000000001',
 'Yamaha PW 50', 'YAMPW502016001', '---',
 'kids', 'AM', 1, 49, 25, 485, 2,
 800, 900, 800, 800, 800, 800, 900, 900, 900,
 'active', 1200,
 'https://images.unsplash.com/photo-1558618047-3c8c76ca7d13?w=800',
 ARRAY['Dětská motorka','Automatická převodovka','Od 3 let','Omezovač plynu','Bezpečná'],
 'Legendární dětská motorka pro první kroky v motosportu. Od 3 let.'),

-- Brno branch
('m0000001-0000-0000-0000-000000000009', 'b0000001-0000-0000-0000-000000000002',
 'KTM 1290 Super Adventure', 'KTM1290SA2017001', '4B1 6666',
 'adventure', 'A', 118, 1301, 218, 860, 23,
 3600, 4000, 3600, 3600, 3600, 3600, 4000, 4000, 4000,
 'active', 42000,
 'https://images.unsplash.com/photo-1558981852-426c349548ab?w=800',
 ARRAY['Nejvýkonnější adventure','V-twin 160 koní','WP elektronika','Prémiové vybavení','Pro zkušené'],
 'Nejextrémnější adventure v nabídce. KTM 1290 je Ready to Race.'),

('m0000001-0000-0000-0000-000000000010', 'b0000001-0000-0000-0000-000000000002',
 'Triumph Tiger 1200 Explorer', 'TRI1200EX2018001', '4B2 7777',
 'adventure', 'A', 96, 1215, 259, 820, 20,
 3200, 3600, 3200, 3200, 3200, 3200, 3600, 3600, 3600,
 'active', 28000,
 'https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800',
 ARRAY['Britský trojválec','Prémiové GT','Transcontinentální','Jízda ve dvou','Elegantní'],
 'Britský elegán pro světové dobrodružství. Trojválcový charakter a bohatá výbava.');

-- ===== 4. BOOKINGS (20 reservations) =====
-- Mix of statuses: completed (past), active (ongoing), pending (future), cancelled

-- === COMPLETED (past) bookings ===
INSERT INTO bookings (id, user_id, moto_id, branch_id, start_date, end_date, actual_return_date, total_price, status, payment_status, payment_method) VALUES
-- Booking 1: Jan – Jawa, completed
('bk000001-0000-0000-0000-000000000001',
 'u0000001-0000-0000-0000-000000000001',
 'm0000001-0000-0000-0000-000000000001',
 'b0000001-0000-0000-0000-000000000001',
 '2025-10-10 09:00:00+02', '2025-10-12 09:00:00+02', '2025-10-12 10:30:00+02',
 6600, 'completed', 'paid', 'card'),

-- Booking 2: Marie – Yamaha XT660, completed
('bk000001-0000-0000-0000-000000000002',
 'u0000001-0000-0000-0000-000000000002',
 'm0000001-0000-0000-0000-000000000006',
 'b0000001-0000-0000-0000-000000000001',
 '2025-09-20 10:00:00+02', '2025-09-22 10:00:00+02', '2025-09-22 11:00:00+02',
 5700, 'completed', 'paid', 'card'),

-- Booking 3: Petr – BMW GS, completed
('bk000001-0000-0000-0000-000000000003',
 'u0000001-0000-0000-0000-000000000003',
 'm0000001-0000-0000-0000-000000000002',
 'b0000001-0000-0000-0000-000000000001',
 '2025-11-01 09:00:00+01', '2025-11-04 09:00:00+01', '2025-11-04 08:45:00+01',
 10800, 'completed', 'paid', 'apple_pay'),

-- Booking 4: Eva – Benelli, completed
('bk000001-0000-0000-0000-000000000004',
 'u0000001-0000-0000-0000-000000000004',
 'm0000001-0000-0000-0000-000000000003',
 'b0000001-0000-0000-0000-000000000001',
 '2025-08-15 09:00:00+02', '2025-08-18 09:00:00+02', '2025-08-18 09:30:00+02',
 9600, 'completed', 'paid', 'card'),

-- Booking 5: Tomáš – CF Moto, completed
('bk000001-0000-0000-0000-000000000005',
 'u0000001-0000-0000-0000-000000000005',
 'm0000001-0000-0000-0000-000000000004',
 'b0000001-0000-0000-0000-000000000001',
 '2025-12-01 09:00:00+01', '2025-12-03 09:00:00+01', '2025-12-03 10:00:00+01',
 7800, 'completed', 'paid', 'card'),

-- Booking 6: Jan – KTM 1290, completed (Brno)
('bk000001-0000-0000-0000-000000000006',
 'u0000001-0000-0000-0000-000000000001',
 'm0000001-0000-0000-0000-000000000009',
 'b0000001-0000-0000-0000-000000000002',
 '2025-07-10 09:00:00+02', '2025-07-13 09:00:00+02', '2025-07-13 09:15:00+02',
 14800, 'completed', 'paid', 'card'),

-- Booking 7: Petr – Honda Africa Twin, completed
('bk000001-0000-0000-0000-000000000007',
 'u0000001-0000-0000-0000-000000000003',
 'm0000001-0000-0000-0000-000000000005',
 'b0000001-0000-0000-0000-000000000001',
 '2026-01-05 09:00:00+01', '2026-01-08 09:00:00+01', '2026-01-08 10:00:00+01',
 11200, 'completed', 'paid', 'apple_pay'),

-- Booking 8: Marie – Kawasaki Z900, completed
('bk000001-0000-0000-0000-000000000008',
 'u0000001-0000-0000-0000-000000000002',
 'm0000001-0000-0000-0000-000000000007',
 'b0000001-0000-0000-0000-000000000001',
 '2026-01-15 10:00:00+01', '2026-01-17 10:00:00+01', '2026-01-17 10:30:00+01',
 8400, 'completed', 'paid', 'card'),

-- Booking 9: Eva – Triumph Tiger, completed (Brno)
('bk000001-0000-0000-0000-000000000009',
 'u0000001-0000-0000-0000-000000000004',
 'm0000001-0000-0000-0000-000000000010',
 'b0000001-0000-0000-0000-000000000002',
 '2026-01-20 09:00:00+01', '2026-01-22 09:00:00+01', '2026-01-22 09:00:00+01',
 9600, 'completed', 'paid', 'card'),

-- Booking 10: Tomáš – Yamaha XT660, completed
('bk000001-0000-0000-0000-000000000010',
 'u0000001-0000-0000-0000-000000000005',
 'm0000001-0000-0000-0000-000000000006',
 'b0000001-0000-0000-0000-000000000001',
 '2026-02-01 09:00:00+01', '2026-02-03 09:00:00+01', '2026-02-03 11:00:00+01',
 5700, 'completed', 'paid', 'card'),

-- === ACTIVE (ongoing) bookings – started yesterday, ends in 3 days ===
-- Booking 11: Jan – Jawa RVM 500 (currently riding)
('bk000001-0000-0000-0000-000000000011',
 'u0000001-0000-0000-0000-000000000001',
 'm0000001-0000-0000-0000-000000000001',
 'b0000001-0000-0000-0000-000000000001',
 NOW() - INTERVAL '1 day', NOW() + INTERVAL '2 days',
 NULL,
 8800, 'active', 'paid', 'card'),

-- Booking 12: Eva – Honda Africa Twin (currently riding)
('bk000001-0000-0000-0000-000000000012',
 'u0000001-0000-0000-0000-000000000004',
 'm0000001-0000-0000-0000-000000000005',
 'b0000001-0000-0000-0000-000000000001',
 NOW() - INTERVAL '2 days', NOW() + INTERVAL '1 day',
 NULL,
 11200, 'active', 'paid', 'apple_pay'),

-- Booking 13: Petr – KTM 1290 (currently riding, Brno)
('bk000001-0000-0000-0000-000000000013',
 'u0000001-0000-0000-0000-000000000003',
 'm0000001-0000-0000-0000-000000000009',
 'b0000001-0000-0000-0000-000000000002',
 NOW() - INTERVAL '1 day', NOW() + INTERVAL '3 days',
 NULL,
 18000, 'active', 'paid', 'card'),

-- === PENDING (future) bookings ===
-- Booking 14: Jan – BMW GS (starts in 2 days)
('bk000001-0000-0000-0000-000000000014',
 'u0000001-0000-0000-0000-000000000001',
 'm0000001-0000-0000-0000-000000000002',
 'b0000001-0000-0000-0000-000000000001',
 NOW() + INTERVAL '2 days', NOW() + INTERVAL '5 days',
 NULL,
 10200, 'pending', 'paid', 'card'),

-- Booking 15: Marie – CF Moto (starts in 5 days)
('bk000001-0000-0000-0000-000000000015',
 'u0000001-0000-0000-0000-000000000002',
 'm0000001-0000-0000-0000-000000000004',
 'b0000001-0000-0000-0000-000000000001',
 NOW() + INTERVAL '5 days', NOW() + INTERVAL '8 days',
 NULL,
 10200, 'pending', 'paid', 'card'),

-- Booking 16: Tomáš – Benelli (starts in 10 days)
('bk000001-0000-0000-0000-000000000016',
 'u0000001-0000-0000-0000-000000000005',
 'm0000001-0000-0000-0000-000000000003',
 'b0000001-0000-0000-0000-000000000001',
 NOW() + INTERVAL '10 days', NOW() + INTERVAL '12 days',
 NULL,
 7200, 'pending', 'unpaid', 'card'),

-- Booking 17: Eva – Triumph Tiger (starts in 7 days, Brno)
('bk000001-0000-0000-0000-000000000017',
 'u0000001-0000-0000-0000-000000000004',
 'm0000001-0000-0000-0000-000000000010',
 'b0000001-0000-0000-0000-000000000002',
 NOW() + INTERVAL '7 days', NOW() + INTERVAL '10 days',
 NULL,
 12000, 'pending', 'paid', 'apple_pay'),

-- Booking 18: Petr – Yamaha PW50 for kids (starts in 14 days)
('bk000001-0000-0000-0000-000000000018',
 'u0000001-0000-0000-0000-000000000003',
 'm0000001-0000-0000-0000-000000000008',
 'b0000001-0000-0000-0000-000000000001',
 NOW() + INTERVAL '14 days', NOW() + INTERVAL '14 days',
 NULL,
 800, 'pending', 'unpaid', 'card'),

-- === CANCELLED bookings ===
-- Booking 19: Marie – Kawasaki Z900 (cancelled, was future)
('bk000001-0000-0000-0000-000000000019',
 'u0000001-0000-0000-0000-000000000002',
 'm0000001-0000-0000-0000-000000000007',
 'b0000001-0000-0000-0000-000000000001',
 NOW() + INTERVAL '20 days', NOW() + INTERVAL '22 days',
 NULL,
 8400, 'cancelled', 'refunded', 'card'),

-- Booking 20: Tomáš – BMW GS (cancelled)
('bk000001-0000-0000-0000-000000000020',
 'u0000001-0000-0000-0000-000000000005',
 'm0000001-0000-0000-0000-000000000002',
 'b0000001-0000-0000-0000-000000000001',
 NOW() + INTERVAL '25 days', NOW() + INTERVAL '28 days',
 NULL,
 10200, 'cancelled', 'refunded', 'card');

-- ===== 5. DOCUMENTS =====
INSERT INTO documents (booking_id, user_id, type, file_path, file_name) VALUES
('bk000001-0000-0000-0000-000000000001',
 'u0000001-0000-0000-0000-000000000001',
 'contract',
 'u0000001-0000-0000-0000-000000000001/bk000001-0000-0000-0000-000000000001/smlouva.pdf',
 'Smlouva_RES-2025-001.pdf'),
('bk000001-0000-0000-0000-000000000001',
 'u0000001-0000-0000-0000-000000000001',
 'protocol',
 'u0000001-0000-0000-0000-000000000001/bk000001-0000-0000-0000-000000000001/protokol.pdf',
 'Protokol_RES-2025-001.pdf'),
('bk000001-0000-0000-0000-000000000011',
 'u0000001-0000-0000-0000-000000000001',
 'contract',
 'u0000001-0000-0000-0000-000000000001/bk000001-0000-0000-0000-000000000011/smlouva.pdf',
 'Smlouva_RES-2026-011.pdf');

-- ===== 6. REVIEWS =====
INSERT INTO reviews (booking_id, user_id, moto_id, rating, comment) VALUES
('bk000001-0000-0000-0000-000000000001',
 'u0000001-0000-0000-0000-000000000001',
 'm0000001-0000-0000-0000-000000000001',
 5, 'Skvělá motorka, perfektní stav. Vřele doporučuji!'),
('bk000001-0000-0000-0000-000000000003',
 'u0000001-0000-0000-0000-000000000003',
 'm0000001-0000-0000-0000-000000000002',
 4, 'BMW GS je fantastická. Jen trochu těžká pro terén.'),
('bk000001-0000-0000-0000-000000000004',
 'u0000001-0000-0000-0000-000000000004',
 'm0000001-0000-0000-0000-000000000003',
 4, 'Benelli překvapil kvalitou. Dobrý poměr cena/výkon.'),
('bk000001-0000-0000-0000-000000000006',
 'u0000001-0000-0000-0000-000000000001',
 'm0000001-0000-0000-0000-000000000009',
 5, 'KTM 1290 je šílená! Výkon jako z jiné planety.');
