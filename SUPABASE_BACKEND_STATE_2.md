# SUPABASE BACKEND STATE — MotoGo24 (Část 2: Klíčové sloupce)
> **Soubory:** 1/6 (Tabulky) | **2/6 (Sloupce)** | 3/6 (RPC funkce) | 4/6 (Triggery) | 5/6 (RLS, Realtime, Edge, Storage, Secrets) | 6/6 (Changelog)

---

## 3. KLÍČOVÉ SLOUPCE (reálný stav DB)

### admin_users
- id, email, name, role (`admin_role` ENUM), password_hash
- branch_access (uuid[]), permissions (jsonb)
- last_login_at, created_at, updated_at

### bookings
- id, user_id, moto_id, start_date, end_date, pickup_time
- status (`booking_status` ENUM)
- payment_status (`payment_status` ENUM)
- payment_method, total_price, delivery_fee, deposit
- promo_code_id, voucher_id, notes
- confirmed_at, picked_up_at, returned_at
- cancelled_by, cancelled_by_source, cancellation_reason, cancelled_at, cancellation_notified
- sos_replacement (boolean), replacement_for_booking_id, sos_incident_id, ended_by_sos
- pickup_date, return_date (timestamptz pro overlap check)
- **actual_return_date** — skutečné datum vrácení
- **pickup_method, pickup_address** — způsob vyzvednutí
- **return_method, return_address** — způsob vrácení
- **extras_price** — cena příslušenství
- **discount_amount, discount_code** — sleva
- **contract_url** — URL smlouvy
- **insurance_type** — typ pojištění
- **signed_contract** — podepsaná smlouva (boolean)
- **mileage_start, mileage_end** — nájezd km
- **damage_report** — hlášení poškození
- **promo_code** — promo kód (text)
- **rating, rated_at** — hodnocení zákazníkem
- **boots_size, helmet_size, jacket_size** — velikosti výbavy
- **original_start_date, original_end_date** — původní data rezervace (před prodloužením/zkrácením)
- **modification_history** (jsonb, default '[]') — historie všech úprav termínu. Každý záznam: `{at, from_start, from_end, to_start, to_end, source}`
- **complaint_status** — stav reklamace (open, in_progress, resolved, rejected, null)
- **booking_source** — zdroj rezervace (text, default 'app') — 'app' nebo 'web'

### booking_complaints
- id (uuid PK), booking_id (refs bookings), customer_id (refs profiles)
- subject (text NOT NULL), description (text)
- status (text: open, in_progress, resolved, rejected)
- resolution (text), created_at, updated_at, resolved_at
- resolved_by (refs auth.users)
- RLS: Admin full access

### profiles
- id (refs auth.users), full_name, email, phone
- street, city, zip, country
- ico, dic, license_number, license_expiry
- license_group (text[]), riding_experience
- emergency_contact, emergency_phone
- gear_sizes (jsonb), reliability_score (jsonb)
- marketing_consent (boolean)
- **date_of_birth** — datum narození
- **avatar_url** — URL avataru
- **preferred_branch** — preferovaná pobočka
- **language** — jazyk (cs/en/de)
- **is_blocked** (boolean DEFAULT false) — zákazník zablokován
- **blocked_at** (timestamptz) — datum blokace
- **blocked_reason** (text) — důvod blokace
- **consent_gdpr** (boolean DEFAULT false) — souhlas GDPR
- **consent_vop** (boolean DEFAULT false) — souhlas VOP
- **consent_email** (boolean DEFAULT false) — souhlas email komunikace
- **consent_sms** (boolean DEFAULT false) — souhlas SMS komunikace
- **consent_push** (boolean DEFAULT false) — souhlas push notifikace
- **consent_data_processing** (boolean DEFAULT false) — souhlas zpracování dat
- **consent_photo** (boolean DEFAULT false) — souhlas fotografování dokladů

### motorcycles
- id, model, spz, vin, year, status (`moto_status` ENUM)
- stk_valid_until, acquired_at
- power_kw, torque_nm, weight_kg, fuel_tank_l, seat_height_mm
- license_required, has_abs, has_asc
- description, ideal_usage, features, manual_url
- engine_type, power_hp
- **branch_id** — pobočka (FK→branches)
- **category** — kategorie motorky
- **engine_cc** — objem motoru
- **price_weekday, price_weekend** — ceny
- **price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun** — ceny dle dne
- **mileage** — aktuální nájezd
- **image_url** — hlavní fotka
- **images[]** — galerie fotek
- **color** — barva
- **deposit_amount** — výše kauce
- **insurance_price** — cena pojištění
- **min_rental_days, max_rental_days** — min/max délka pronájmu
- **oil_interval_km, oil_interval_days** — interval výměny oleje
- **tire_interval_km** — interval výměny pneumatik
- **full_service_interval_km, full_service_interval_days** — interval celkového servisu
- **last_service_date, next_service_date** — datum posledního/příštího servisu
- **brand** (TEXT DEFAULT NULL) — značka motorky (Honda, Yamaha, BMW...)
- **purchase_price** (NUMERIC DEFAULT 0) — pořizovací cena motorky v Kč
- **purchase_mileage** (INTEGER DEFAULT NULL) — km při zakoupení, základ pro výpočet servisních intervalů

### sos_incidents
- id, user_id, booking_id, moto_id, type, title, description
- severity (low/medium/high/critical)
- status (`sos_status` ENUM)
- moto_rideable, customer_decision, customer_fault
- damage_description, damage_severity (none/cosmetic/functional/totaled)
- latitude, longitude, address, photos[]
- nearest_service_name/address/phone
- assigned_to, contact_phone, admin_notes
- resolution, resolved_at, resolved_by
- replacement_data (jsonb), replacement_status
- original_booking_id, replacement_booking_id, original_moto_id
- **is_customer_fault** — vina zákazníka (boolean)
- **police_report_number** — číslo policejní zprávy
- **replacement_moto_id** — ID náhradní motorky
- **tow_requested** — požadavek na odtah (boolean)
- type CHECK: theft/accident_minor/accident_major/breakdown_minor/breakdown_major/defect_question/location_share/other

### invoices
- id, number, type, customer_id, supplier_id, booking_id, order_id
- issue_date, due_date, paid_date, issued_at
- subtotal, tax_amount, total, amount, currency, status, pdf_path
- items (jsonb), notes, variable_symbol, source

### vouchers
- id, code, amount, currency, status (active/redeemed/expired/cancelled)
- buyer_id, buyer_name, buyer_email
- valid_from, valid_until
- redeemed_at, redeemed_by, redeemed_for, booking_id
- description, category (rental/gear/experience/gift)
- created_by
- **order_id** (FK→shop_orders) — vazba na e-shop objednávku
- **source** — zdroj voucheru

### shop_orders
- id, order_number, customer_id, status, payment_status, payment_method
- total_amount, currency, shipping_address, shipping_method
- promo_code_id, notes
- **confirmed_at** — datum potvrzení
- created_at, updated_at

### branches (nové sloupce)
- **branch_code** (TEXT UNIQUE) — unikátní kód pobočky (6 číslic, např. "000126")
- **is_open** (BOOLEAN DEFAULT false) — otevřená (nonstop provoz) / zavřená
- **type** (TEXT DEFAULT NULL) — typ pobočky: turistická, městská, horská, rekreační voda, metropolitní centrum, městská tranzitní

### branch_accessories
- id (UUID PK), branch_id (FK→branches ON DELETE CASCADE)
- type (TEXT) — CHECK constraint odstraněn, typy se řídí tabulkou `accessory_types`
- size (TEXT) — velikost (36-46 pro boty, XS-XXL pro ostatní, UNI pro kukly/spotřební)
- quantity (INTEGER DEFAULT 0)
- created_at, updated_at
- UNIQUE(branch_id, type, size)
- RLS: Admin full access
- **Propojení se skladem:** Při přidání/zvýšení množství se strhne z `inventory` (SKU: `prislusenstvi-{type}-{size}`). Při snížení půjčovaného zboží se vrátí na sklad. Spotřební zboží se nevrací.

### accessory_types
- id (UUID PK), key (TEXT UNIQUE) — slug typu (boots, helmet, ubrousky...)
- label (TEXT) — zobrazovaný název
- sizes (TEXT[]) — povolené velikosti
- is_consumable (BOOLEAN DEFAULT false) — spotřební zboží (kukly, ubrousky) vs. půjčované (boty, helmy)
- sort_order (INTEGER DEFAULT 0), is_active (BOOLEAN DEFAULT true)
- created_at, updated_at
- RLS: Admin full access, Public read
- Trigger: trg_accessory_types_updated → update_updated_at()

### branch_door_codes
- id (UUID PK), branch_id (FK→branches ON DELETE CASCADE)
- booking_id (FK→bookings ON DELETE CASCADE)
- moto_id (FK→motorcycles ON DELETE SET NULL)
- code_type (TEXT CHECK: motorcycle/accessories)
- door_code (TEXT NOT NULL) — 6-místný kód
- is_active (BOOLEAN DEFAULT false) — aktivní jen po dobu aktivní rezervace
- valid_from, valid_until (TIMESTAMPTZ)
- sent_to_customer (BOOLEAN DEFAULT false) — odesláno zákazníkovi
- sent_at (TIMESTAMPTZ)
- withheld_reason (TEXT) — důvod zadržení kódu (chybí doklady)
- created_at, updated_at
- RLS: Admin full access, Customer read own (via booking.user_id)
- Realtime: ANO
