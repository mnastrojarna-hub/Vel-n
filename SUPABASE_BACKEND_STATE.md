# SUPABASE BACKEND STATE — MotoGo24
> **Poslední aktualizace:** 2026-03-21 12:30 UTC
> **Zdroj:** Reálný stav Supabase databáze (SQL dump z dashboardu) + Edge Functions
> **Projekt:** `vnwnqteskbykeucanlhk.supabase.co`
> **POZOR:** Tento soubor MUSÍ být aktualizován při každé SQL změně!

---

## 1. ENUM TYPY

| Typ | Hodnoty |
|-----|---------|
| `admin_role` | viewer, manager, operator, technician, readonly, admin, superadmin |
| `booking_status` | pending, reserved, active, completed, cancelled, rejected |
| `payment_status` | pending, paid, unpaid, refunded, failed |
| `moto_status` | active, rented, maintenance, unavailable, retired |
| `sos_status` | reported, acknowledged, in_progress, resolved, closed |
| `license_group` | AM, A1, A2, A, B, N |
| ~~`document_type`~~ | **ZRUŠENO** — sloupec `documents.type` je nyní TEXT (ne ENUM). Používané hodnoty: contract, vop, invoice_advance, payment_receipt, invoice_final, invoice_shop, protocol |

---

## 2. TABULKY (public schema) — 61 tabulek

### Hlavní entity

| Tabulka | Popis |
|---------|-------|
| `profiles` | Zákaznické profily (vazba na auth.users) |
| `motorcycles` | Flotila motorek |
| `bookings` | Rezervace |
| `branches` | Pobočky (autonomní, branch_code, is_open toggle) |
| `branch_accessories` | Příslušenství na pobočce (boty, helmy, kukly, rukavice, kalhoty) — typ+velikost+počet |
| `branch_door_codes` | Přístupové kódy ke dveřím (motorka / příslušenství) — per booking, auto-generované |
| `admin_users` | Admin uživatelé (role: admin_role ENUM, branch_access uuid[], permissions jsonb) |

### Booking systém

| Tabulka | Popis |
|---------|-------|
| `bookings` | Hlavní tabulka rezervací |
| `booking_extras` | Příslušenství k rezervacím |
| `booking_cancellations` | Záznamy o stornech (refund_amount, refund_percent) |
| `extras_catalog` | Katalog příslušenství |
| `moto_day_prices` | Ceník dle dne v týdnu (po-ne) |
| `pricing_rules` | Pravidla dynamického ceníku |

### SOS systém

| Tabulka | Popis |
|---------|-------|
| `sos_incidents` | Nouzové incidenty (typ, závažnost, lokace, fotky) |
| `sos_timeline` | Timeline akcí v rámci incidentu (data jsonb) |

### Komunikace

| Tabulka | Popis |
|---------|-------|
| `message_threads` | Vlákna zpráv (channel, status, assigned_admin) |
| `messages` | Jednotlivé zprávy (direction, content, ai_suggested_reply) |
| `message_templates` | Šablony pro rychlé odpovědi |
| `admin_messages` | Admin zprávy (type CHECK: sos_response, accident_response, replacement, tow, info, thanks, voucher) |
| `notification_log` | Log notifikací |
| `notification_rules` | Pravidla notifikací |
| `push_tokens` | Push tokeny zařízení |
| `message_log` | Centrální log všech odeslaných zpráv (SMS, WhatsApp, email) — channel, recipient, template_slug, status, provider_response, metadata |
| `message_templates_sms` | SMS/WhatsApp šablony (slug unikátní, body_template s {{placeholdery}}) |

### Dokumenty a faktury

| Tabulka | Popis |
|---------|-------|
| `invoices` | Faktury (type: issued/received/final/proforma/shop_proforma/shop_final/advance/payment_receipt, source: booking/edit/sos/shop/restore) |
| `document_templates` | Šablony dokumentů (id uuid, type TEXT, name TEXT, content_html TEXT, active BOOL, version INT, updated_by uuid, created_at, updated_at) |
| `generated_documents` | Vygenerované dokumenty |
| `documents` | Nahrané dokumenty (type TEXT — contract, vop, invoice_advance, payment_receipt, invoice_final, invoice_shop, protocol) |
| `email_templates` | Šablony emailů (slug: booking_reserved, booking_abandoned, booking_cancelled, booking_completed, voucher_purchased, booking_modified) |
| `sent_emails` | Log odeslaných emailů |

### E-shop

| Tabulka | Popis |
|---------|-------|
| `products` | Katalog produktů (name, description, price, images[], sizes[], sku, stock_quantity, category, color, material, is_active, sort_order) |
| `shop_orders` | Objednávky (status: new/confirmed/processing/shipped/delivered/cancelled/returned/refunded, confirmed_at) |
| `shop_order_items` | Položky objednávek |

### Promo a vouchery

| Tabulka | Popis |
|---------|-------|
| `promo_codes` | Slevové kódy (type: percent/fixed) |
| `promo_code_usage` | Použití slevových kódů |
| `vouchers` | Dárkové poukazy (status: active/redeemed/expired/cancelled, order_id FK→shop_orders, source) |

### Servis a údržba

| Tabulka | Popis |
|---------|-------|
| `maintenance_log` | Log údržby (km_at_service, completed_date, scheduled_date) |
| `maintenance_schedules` | Plány údržby (schedule_type, interval_km, interval_days) |
| `service_orders` | Servisní objednávky (status: pending/in_service/completed/cancelled) |
| `moto_locations` | GPS pozice motorek (lat, lng, source: gps/manual/tracker) |

### Finance a účetnictví

| Tabulka | Popis |
|---------|-------|
| `accounting_entries` | Účetní záznamy |
| `cash_register` | Pokladna |
| `tax_records` | Daňové záznamy |
| `daily_stats` | Denní statistiky |
| `moto_performance` | Výkonnost motorek |
| `branch_performance` | Výkonnost poboček |
| `acc_employees` | Zaměstnanci (jméno, typ smlouvy, hrubá mzda, sleva na dani, bankovní účet) |
| `acc_payrolls` | Výpočty mezd (hrubá, SP/ZP zaměstnanec i zaměstnavatel, záloha daně, čistá, celk. náklad) |
| `acc_vat_returns` | Přiznání k DPH (čtvrtletní, zdanitelné vstupy/výstupy, DPH vstup/výstup, k úhradě/vrácení) |
| `acc_tax_returns` | Daňové přiznání (roční, příjmy, výdaje, odpisy, mzdy, základ daně, daň 15%/23%, slevy) |
| `acc_short_term_assets` | Krátkodobý majetek (materiál, drobný majetek, zásoby, pohledávky, peníze) |
| `acc_long_term_assets` | Dlouhodobý majetek (vozidla, stroje, stavby, odpisová skupina 1-6, metoda odpisu) |
| `acc_depreciation_entries` | Odpisy DM (roční odpis, kumulativní, zůstatková hodnota, metoda, skupina) |
| `acc_liabilities` | Závazky (dodavatelé, daně, SP, ZP, mzdy, úvěry, splatnost, stav úhrady) |
| `flexi_reports` | Výkazy stažené z Abra Flexi (DPH přiznání, daňové přiznání, rozvaha, výsledovka, OSSZ, VZP) — status: draft/approved/submitted/rejected, schválení + odeslání datovkou |

### Nákupy a sklad

| Tabulka | Popis |
|---------|-------|
| `purchase_orders` | Nákupní objednávky |
| `purchase_order_items` | Položky nákupních objednávek |
| `suppliers` | Dodavatelé (name, normalized_name, ico, dic, address, bank_account, default_category, default_account, contact_email, notes, created_at, updated_at). Index na normalized_name a ico. Funkce normalize_supplier_name() pro matching bez diakritiky. Auto-upsert z OCR v receive-invoice. |
| `inventory` | Skladové zásoby |
| `inventory_movements` | Pohyby na skladě |

### AI a automatizace

| Tabulka | Popis |
|---------|-------|
| `ai_conversations` | Konverzace s AI Copilotem (admin_id, messages jsonb) |
| `ai_actions` | AI akce |
| `ai_logs` | AI logy |
| `automation_rules` | Automatizační pravidla |
| `predictions` | Predikce |

### CMS a nastavení

| Tabulka | Popis |
|---------|-------|
| `app_settings` | Nastavení aplikace (key-value, jsonb) |
| `cms_pages` | CMS stránky |
| `cms_variables` | CMS proměnné |
| `feature_flags` | Feature flags |
| `reviews` | Recenze zákazníků |

### Audit a debug

| Tabulka | Popis |
|---------|-------|
| `admin_audit_log` | Audit log admin akcí (admin_id, action, details jsonb, ip_address) |
| `debug_log` | Debug log (source, action, component, status, request/response_data, error_message, duration_ms) |

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

---

## 4. RPC FUNKCE (callable z frontendu)

### Existující v migracích
| Funkce | Popis |
|--------|-------|
| `is_admin()` | Vrací boolean — je aktuální user admin? |
| `is_superadmin()` | Vrací boolean — je aktuální user superadmin? |
| `validate_promo_code(code)` | Validuje promo kód, vrací jsonb |
| `use_promo_code(code, booking_id, base_amount)` | Použije promo kód atomicky |
| `create_shop_order(items, shipping, address, payment, promo)` | Vytvoří e-shop objednávku |
| `cancel_booking_tracked(booking_id, reason)` | Stornuje rezervaci s refund kalkulací |
| `sos_swap_bookings(incident_id, replacement_moto_id, ...)` | SOS výměna motorky — atomický swap |
| `expire_vouchers()` | Automatická expirace voucherů (pg_cron) |
| `expire_vouchers_and_promos()` | Expirace voucherů + deaktivace promo kódů po valid_to |
| `auto_cancel_expired_pending()` | Auto-cancel pending+unpaid bookings (app: 10min, web: 4h). SECURITY DEFINER |
| `auto_complete_expired_bookings()` | Auto-complete: active/reserved + end_date < today + paid → completed (BEZ fakturace — KF generuje trigger). SECURITY DEFINER |
| `generate_final_invoice_on_complete()` | Trigger funkce: generuje KF (konečnou fakturu) při přechodu active→completed. SECURITY DEFINER |
| `auto_activate_reserved_bookings()` | Auto-activate: reserved + paid + start_date <= today → active (+picked_up_at). SECURITY DEFINER |
| `check_user_booking_overlap()` | Trigger: per-user overlap check — zákazník nesmí mít 2 překrývající se rezervace. Výjimka: dětské motorky (license_required=N). SECURITY DEFINER |
| `confirm_payment(booking_id, method)` | RPC: označí booking jako zaplacený. start_date<=dnes → pending→**active** (+picked_up_at), start_date>dnes → pending→**reserved** (+confirmed_at). SECURITY DEFINER |
| `confirm_shop_payment(order_id, method)` | RPC: označí shop objednávku jako zaplacenou (SECURITY DEFINER) |
| `check_booking_overlap()` | Trigger funkce: kontrola překrytí rezervací |
| `generate_shop_invoice()` | Trigger funkce: auto-faktura při zaplacení shop objednávky (type='shop_final', source='shop', SECURITY DEFINER) |
| `auto_process_voucher_order()` | BEFORE UPDATE trigger na shop_orders: při payment_status→'paid' automaticky generuje voucher kódy, posílá in-app notifikaci, nastavuje status (delivered pro digitální, confirmed pro mixed). SECURITY DEFINER |
| `send_message_via_edge(channel, recipient, slug, vars, customer_id, booking_id)` | Odešle zprávu přes Edge Function `send-message` pomocí pg_net. Loguje do `message_log`. SECURITY DEFINER |
| `send_sms_and_wa(to, slug, vars, customer_id, booking_id)` | Helper: odešle SMS + WhatsApp přes `send_message_via_edge`. SECURITY DEFINER |
| `mark_thread_messages_read(p_thread_id)` | RPC: označí admin zprávy ve vlákně jako přečtené (read_at=now). Ověřuje vlastnictví vlákna. SECURITY DEFINER |
| `get_unread_thread_message_count(p_customer_id)` | RPC: vrací počet nepřečtených admin zpráv napříč všemi vlákny zákazníka. SECURITY DEFINER |
| `auto_generate_door_codes()` | Trigger funkce: auto-generuje 2 přístupové kódy (motorcycle+accessories) při přechodu bookingu na 'active'. Kontroluje doklady zákazníka, posílá kódy jako admin_message. SECURITY DEFINER, EXCEPTION safe |
| `auto_deactivate_door_codes()` | Trigger funkce: deaktivuje všechny aktivní kódy (is_active=false) při přechodu bookingu na 'completed' nebo 'cancelled'. SECURITY DEFINER, EXCEPTION safe |

### Další funkce v reálné DB (ne v migracích)
| Funkce | Popis |
|--------|-------|
| `auto_accounting_on_booking_paid()` | Auto účetní záznam při zaplacení bookingu |
| `auto_reply_sos()` | Automatická odpověď na SOS |
| `auto_schedule_services()` | Auto plánování servisů |
| `calc_booking_price()` | Kalkulace ceny bookingu v1 |
| `calc_booking_price_v2()` | Kalkulace ceny bookingu v2 |
| `calculate_moto_roi()` | Výpočet ROI motorky |
| `check_admin_permission()` | Kontrola admin oprávnění |
| `check_moto_availability()` | Kontrola dostupnosti motorky |
| `create_sos_incident()` | Vytvoření SOS incidentu |
| `extend_booking()` | Prodloužení bookingu |
| `generate_invoice_number()` | Generování čísla faktury |
| `get_available_motos()` | Získání dostupných motorek |
| `handle_new_user()` | Zpracování nového uživatele (auth trigger) |
| `send_admin_message()` | Odeslání admin zprávy |
| `snapshot_daily_stats()` | Snapshot denních statistik |
| `sos_share_location()` | Sdílení lokace v SOS |
| `trigger_sos_auto_reply()` | **REPLACED** safe no-op (SECURITY DEFINER) — původní funkce crashovala INSERT |
| `update_moto_after_service()` | Aktualizace motorky po servisu |
| `validate_voucher_code(p_code)` | Validace voucherového kódu (vrací {valid, id, type:'fixed', value, code}) |

---

## 5. TRIGGERY

### Z migrací
| Trigger | Tabulka | Funkce |
|---------|---------|--------|
| `trg_admin_users_updated` | admin_users | update_updated_at() |
| `trg_promo_usage_increment` | promo_code_usage | increment_promo_used_count() |
| `trg_sos_auto_severity` | sos_incidents (INSERT) | sos_auto_severity() |
| `trg_sos_auto_timeline` | sos_incidents (INSERT) | sos_auto_timeline() |
| `trg_sos_incidents_updated` | sos_incidents | update_updated_at() |
| `trg_email_templates_updated` | email_templates | update_updated_at() |
| `trg_document_templates_updated` | document_templates | update_updated_at() |
| `trg_app_settings_updated` | app_settings | update_updated_at() |
| `trg_vouchers_updated` | vouchers | update_updated_at() |
| `trg_service_orders_updated` | service_orders | update_updated_at() |
| `trg_branches_updated` | branches | update_updated_at() |
| `trg_shop_orders_updated` | shop_orders | update_updated_at() |
| `trg_shop_order_number` | shop_orders (INSERT) | generate_shop_order_number() |
| `trg_check_booking_overlap` | bookings (INSERT/UPDATE OF start_date, end_date, moto_id) | check_booking_overlap() |
| `trg_generate_shop_invoice` | shop_orders (payment_status) | generate_shop_invoice() |
| `moto_day_prices_updated` | moto_day_prices | update_updated_at() |
| `trg_ai_conversations_updated` | ai_conversations | update_updated_at() |
| `trg_sos_notify_user` | sos_incidents (INSERT) | sos_notify_user_on_create() — SECURITY DEFINER, dedup 2min |
| `trg_one_active_sos` | sos_incidents (BEFORE INSERT) | check_one_active_sos() — SECURITY DEFINER, blokuje duplikáty |
| `trg_bridge_admin_message` | messages (INSERT) | bridge_admin_message_to_app() |
| `trg_restore_vouchers_on_cancel` | bookings (UPDATE) | restore_vouchers_on_cancel() |
| `trg_auto_process_voucher_order` | shop_orders (BEFORE UPDATE OF payment_status, WHEN paid) | auto_process_voucher_order() — auto voucher kódy + in-app notifikace + status update |
| `trg_sync_invoice_to_documents` | invoices (INSERT) | sync_invoice_to_documents() |
| `trg_sync_invoice_pdf_update` | invoices (UPDATE pdf_path) | sync_invoice_pdf_update() |
| `trg_sync_generated_doc_to_documents` | generated_documents (INSERT) | sync_generated_doc_to_documents() |
| `trg_sync_moto_day_prices` | moto_day_prices (INSERT/UPDATE) | sync_moto_day_prices_to_motorcycles() |
| `trg_generate_final_invoice` | bookings (AFTER UPDATE OF status, WHEN active→completed) | generate_final_invoice_on_complete() — SECURITY DEFINER, EXCEPTION safe |
| `trg_auto_generate_door_codes` | bookings (AFTER UPDATE OF status, WHEN →active) | auto_generate_door_codes() — SECURITY DEFINER, generuje 2 kódy (motorcycle+accessories), posílá admin_message. EXCEPTION safe |
| `trg_auto_generate_door_codes_insert` | bookings (AFTER INSERT, WHEN status=active) | auto_generate_door_codes() — pro SOS replacement bookings vytvořené rovnou jako active |
| `trg_auto_deactivate_door_codes` | bookings (AFTER UPDATE OF status, WHEN →completed/cancelled) | auto_deactivate_door_codes() — deaktivuje is_active=false. EXCEPTION safe |
| `trg_notify_booking_confirmed` | bookings (AFTER INSERT/UPDATE OF status, WHEN reserved) | trg_notify_booking_confirmed() — SMS+WA potvrzení rezervace. Dedup přes message_log. SECURITY DEFINER |
| `trg_notify_door_codes` | branch_door_codes (AFTER INSERT, WHEN motorcycle) | trg_notify_door_codes() — SMS+WA přístupové kódy. Dedup přes message_log. SECURITY DEFINER |
| `trg_notify_booking_cancelled` | bookings (AFTER UPDATE OF status, WHEN →cancelled) | trg_notify_booking_cancelled() — SMS+WA storno. Dedup přes message_log. SECURITY DEFINER |
| `trg_notify_ride_completed` | bookings (AFTER UPDATE OF status, WHEN →completed) | trg_notify_ride_completed() — SMS+WA dokončení jízdy + review link. Dedup přes message_log. SECURITY DEFINER |
| `trg_notify_voucher_purchased` | vouchers (AFTER INSERT, WHEN active) | trg_notify_voucher_purchased() — SMS voucher info. Dedup přes message_log. SECURITY DEFINER |

### Další triggery v reálné DB
| Trigger | Tabulka | Funkce |
|---------|---------|--------|
| `bookings_auto_accounting` | bookings (AFTER UPDATE OF payment_status, WHEN paid) | auto_accounting_on_booking_paid() — EXCEPTION safe |
| `maintenance_log_after_insert` | maintenance_log | update_moto_after_service() |
| ~~`sos_auto_reply_on_create`~~ | ~~sos_incidents (INSERT)~~ | **DROPPED 2026-03-10** — crashoval INSERT bez error handleru |
| Různé `_updated_at` triggery | více tabulek | update_updated_at() |

---

## 6. RLS POLITIKY (kompletní)

Všechny tabulky mají RLS zapnuté. Vzory:
- **Admin full access:** `FOR ALL USING (is_admin())`
- **Superadmin write:** `FOR ALL USING (is_superadmin())`
- **Customer read own:** `FOR SELECT USING (user_id = auth.uid())`
- **Customer insert own:** `FOR INSERT WITH CHECK (user_id = auth.uid())`
- **Public read:** `FOR SELECT USING (true)` — branches, moto_locations, moto_day_prices, promo_codes(active), app_settings, motorcycles
- **Branch-based admin access:** Některé politiky kontrolují `admin_users.branch_access` pro omezení přístupu dle pobočky

Detailní politiky:
- **bookings:** user SELECT/INSERT/UPDATE (user_id=uid OR is_admin), admin DELETE
- **profiles:** user SELECT (id=uid OR is_admin), user UPDATE (id=uid), admin ALL
- **motorcycles:** public SELECT, admin ALL
- **sos_incidents:** admin ALL, customer SELECT/INSERT/UPDATE (user_id=uid)
- **sos_timeline:** admin ALL, customer SELECT/INSERT (own incident)
- **messages:** admin ALL, customer SELECT (own thread), customer INSERT (direction='customer' + own thread)
- **message_threads:** admin ALL, customer SELECT/UPDATE/INSERT (customer_id=uid)
- **admin_messages:** admin ALL + INSERT, user SELECT (user_id=uid OR is_admin), user UPDATE (own)
- **vouchers:** admin ALL, user SELECT (buyer_id OR redeemed_by = uid)
- **reviews:** admin ALL, customer SELECT (own OR visible=true), customer INSERT (own)
- **documents:** admin ALL, customer SELECT/INSERT (user_id=uid)
- **invoices:** admin ALL, customer SELECT/INSERT (customer_id=uid)
- **products:** public SELECT (is_active), admin ALL
- **shop_orders:** admin ALL, customer SELECT/INSERT/UPDATE (customer_id=uid)
- **shop_order_items:** admin ALL, customer SELECT/INSERT (order owned by user)
- **booking_cancellations:** admin ALL, customer SELECT (cancelled_by=uid)

---

## 7. REALTIME (supabase_realtime publication)

- `sos_incidents`
- `sos_timeline`
- `messages`
- `message_threads`
- `admin_messages`
- `motorcycles`
- `bookings`
- `products`
- `documents`
- `invoices`
- `vouchers`

---

## 8. EDGE FUNKCE (20 deployovaných)

### V repozitáři (11)

| Funkce | Popis |
|--------|-------|
| `admin-auth` | Autentizace a auto-provisioning admin uživatelů (ověření JWT + insert do admin_users přes service role) |
| `ai-copilot` | AI Copilot pro Velín dashboard — Anthropic Claude API, system prompt CZ, načítá kontext z DB (bookings, tržby, servis, SOS), ukládá do ai_conversations |
| `ai-moto-agent` | AI Servisní agent pro zákazníky — diagnostika závad motorek přes Claude API, vrací {reply, is_rideable, suggest_sos}, načítá kontext motorky z booking_id |
| `send-booking-email` | Odesílá branded HTML emaily (booking_reserved, booking_completed, booking_modified, voucher_purchased). Retry 3× s exponential backoff. Při selhání loguje do debug_log |
| `generate-invoice` | Generuje proforma/finální fakturu (ZF-/FV-YYYY-NNNN). Firemní údaje načítá z app_settings (company_info) |
| `generate-document` | Generuje dokumenty z šablon (rental_contract, handover_protocol). Firemní údaje načítá z app_settings (company_info) |
| `send-cancellation-email` | Email o stornování rezervace s "obnovit" CTA. Retry 3× s exponential backoff. Při selhání loguje do debug_log |
| `admin-reset-password` | Admin reset hesla zákazníka |
| `process-payment` | Stripe platební brána (TEST mode). Podporuje booking i shop platby (parametr `type`). Vytváří Checkout Session (redirect) + PaymentIntent (Stripe Elements). Vrací `checkout_url`, `session_id`, `client_secret` |
| `scan-document` | OCR skenování dokladů (OP, ŘP, pas) přes Mindee API. Přijímá base64 JPEG + document_type (id/dl/passport), vrací strukturovaná data (jméno, datum narození, adresa, číslo ŘP, kategorie atd.). Retry 3×, loguje do debug_log |
| `webhook-receiver` | Příjem Stripe webhooků v repozitáři. Ověřuje signature, zpracovává checkout.session.completed a payment_intent.succeeded |
| `send-message` | Centrální odesílání zpráv (SMS/WhatsApp přes Twilio, email přes Resend). Přijímá channel, recipient, template_slug, template_vars. Loguje do message_log |
| `send-invoice-email` | Odesílání faktur emailem zákazníkům |

### Pouze v Supabase dashboardu (11 dalších)

| Funkce | Popis |
|--------|-------|
| `bright-endpoint` | Bright Data endpoint |
| `cms-sync` | Synchronizace CMS obsahu |
| `cron-daily` | Denní cron úlohy |
| `cron-monthly` | Měsíční cron úlohy |
| `export-data` | Export dat (CSV/XLSX) |
| `generate-report` | Generování reportů |
| `generate-tax` | Generování daňových záznamů |
| `inventory-check` | Kontrola stavu skladu |
| `prediction-engine` | Predikční engine (obsazenost, tržby) |
| `send-email` | Obecné odesílání emailů (jiné než booking) |
| `send-sos` | SOS notifikace |
| `upload-handler` | Zpracování nahraných souborů |

---

## 9. STORAGE BUCKETY

| Bucket | Přístup | Použití |
|--------|---------|---------|
| `documents` | **private** | Faktury (invoices/{id}.html), generované dokumenty (generated/{uuid}.html), smlouvy |
| `media` | **public** | Fotky motorek, loga, marketingové materiály |
| `sos-photos` | **private** | Fotky z SOS incidentů (poškození, nehody) |

---

## 10. SECRETS (9)

| Secret | Kde se používá |
|--------|---------------|
| `SUPABASE_URL` | Všechny edge funkce |
| `SUPABASE_SERVICE_ROLE_KEY` | Všechny edge funkce |
| `SUPABASE_ANON_KEY` | admin-reset-password, ai-copilot, ai-moto-agent |
| `SUPABASE_DB_URL` | Přímý DB přístup z edge funkcí |
| `ANTHROPIC_API_KEY` | ai-copilot, ai-moto-agent (Anthropic Claude API) |
| `RESEND_API_KEY` | send-booking-email, generate-invoice, send-cancellation-email, send-email |
| `FROM_EMAIL` | Email funkce (default: noreply@motogo24.cz) |
| `SITE_URL` | send-booking-email, send-cancellation-email (default: https://motogo24.cz) |
| `MINDEE_API_KEY` | scan-document (OCR) |
| `STRIPE_SECRET_KEY` | webhook-receiver, process-payment |
| `STRIPE_WEBHOOK_SECRET` | webhook-receiver (ověření Stripe signature) |
| `ADMIN_EMAIL` | SOS notifikace, cron alerty |
| `ADMIN_PHONE` | SOS SMS notifikace |
| `TWILIO_ACCOUNT_SID` | send-message (Twilio SMS/WhatsApp) |
| `TWILIO_AUTH_TOKEN` | send-message (Twilio SMS/WhatsApp) |
| `TWILIO_PHONE_NUMBER` | send-message (Twilio odesílací číslo) |

---

## 11. SEED DATA (app_settings)

```json
{
  "company_info": {
    "name": "Bc. Petra Semorádová",
    "ico": "21874263",
    "dic": null,
    "vat_payer": false,
    "address": "Mezná 9, 393 01 Mezná",
    "bank_account": "670100-2225851630/6210",
    "phone": "+420 774 256 271",
    "email": "info@motogo24.cz",
    "web": "https://motogo24.cz"
  }
}
```

### header_banner (app_settings key)
Řídí rotující banner v horní části mobilní aplikace. Spravuje se z Velín dashboardu.
```json
{
  "enabled": true,
  "text": "Letní akce -20% na všechny motorky!",
  "bg": "#1a2e22",
  "color": "#74FB71"
}
```

### google_review_url (app_settings key)
URL pro přesměrování zákazníka na Google recenze po dokončení rezervace.
```
https://search.google.com/local/writereview?placeid=PLACE_ID
```
> **POZNÁMKA:** PLACE_ID je potřeba zjistit z Google Business profilu MotoGo24 a nastavit v app_settings.

---

## 12. SEKVENCE

- `shop_order_seq` — formát: OBJ-YYYY-NNNNN (start 1001)

---

## 13. CRON JOBS (pg_cron)

| Job | Čas | Funkce |
|-----|-----|--------|
| `expire-vouchers` | denně 01:00 UTC | `SELECT expire_vouchers()` |
| `auto-cancel-pending-bookings` | každé 2 min (`*/2 * * * *`) | `SELECT auto_cancel_expired_pending()` — ruší pending+unpaid bookings: app=10min, web=4h |
| `auto-complete-expired-bookings` | denně 00:01 (`1 0 * * *`) | `SELECT auto_complete_expired_bookings()` — active/reserved + end_date < today + paid → completed |
| `auto-activate-reserved-bookings` | denně 00:01 (`1 0 * * *`) | `SELECT auto_activate_reserved_bookings()` — reserved + paid + start_date <= today → active |
| Denní cron | denně | `cron-daily` edge function (snapshot_daily_stats, auto_schedule_services) |
| Měsíční cron | 1. den měsíce | `cron-monthly` edge function (generate-tax, monthly reports) |

---

## 14. FOREIGN KEYS (klíčové vazby)

- `bookings.user_id` → `profiles.id`
- `bookings.moto_id` → `motorcycles.id`
- `bookings.promo_code_id` → `promo_codes.id`
- `bookings.voucher_id` → `vouchers.id`
- `bookings.replacement_for_booking_id` → `bookings.id`
- `bookings.sos_incident_id` → `sos_incidents.id`
- `booking_extras.booking_id` → `bookings.id`
- `booking_extras.extra_id` → `extras_catalog.id`
- `sos_incidents.user_id` → `profiles.id`
- `sos_incidents.booking_id` → `bookings.id`
- `sos_incidents.moto_id` → `motorcycles.id`
- `sos_incidents.original_booking_id` → `bookings.id`
- `sos_incidents.replacement_booking_id` → `bookings.id`
- `invoices.customer_id` → `profiles.id`
- `invoices.booking_id` → `bookings.id`
- `invoices.order_id` → `shop_orders.id`
- `vouchers.order_id` → `shop_orders.id`
- `shop_orders.customer_id` → `profiles.id`
- `shop_order_items.order_id` → `shop_orders.id`
- `motorcycles.branch_id` → `branches.id`
- `moto_day_prices.moto_id` → `motorcycles.id`
- `message_threads.customer_id` → `profiles.id`
- `messages.thread_id` → `message_threads.id`
- `promo_code_usage.promo_code_id` → `promo_codes.id`
- `promo_code_usage.user_id` → `profiles.id`
- `maintenance_log.moto_id` → `motorcycles.id`
- `service_orders.moto_id` → `motorcycles.id`
- `branch_accessories.branch_id` → `branches.id`
- `branch_door_codes.branch_id` → `branches.id`
- `branch_door_codes.booking_id` → `bookings.id`
- `branch_door_codes.moto_id` → `motorcycles.id`

---

### branches (nové sloupce)
- **branch_code** (TEXT UNIQUE) — unikátní kód pobočky (6 číslic, např. "000126")
- **is_open** (BOOLEAN DEFAULT false) — otevřená (nonstop provoz) / zavřená
- **type** (TEXT DEFAULT NULL) — typ pobočky: turistická, městská, horská, rekreační voda, metropolitní centrum, městská tranzitní

### motorcycles (nové sloupce pro analytiku)
- **brand** (TEXT DEFAULT NULL) — značka motorky (Honda, Yamaha, BMW...)
- **purchase_price** (NUMERIC DEFAULT 0) — pořizovací cena motorky v Kč

### branch_accessories
- id (UUID PK), branch_id (FK→branches ON DELETE CASCADE)
- type (TEXT CHECK: boots/helmet/balaclava/gloves/pants)
- size (TEXT) — velikost (36-46 pro boty, XS-XXL pro ostatní, UNI pro kukly)
- quantity (INTEGER DEFAULT 0)
- created_at, updated_at
- UNIQUE(branch_id, type, size)
- RLS: Admin full access

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

---

## CHANGELOG

| Datum | Změna |
|-------|-------|
| 2026-03-08 | Prvotní vytvoření ze 32 migrací + 6 edge funkcí |
| 2026-03-08 | Aktualizace: doplněny chybějící triggery, realtime tabulky, RLS detaily |
| 2026-03-08 23:30 | **MAJOR UPDATE:** Kompletní přepis dle reálného stavu Supabase DB. Doplněno: ENUM typy, 14 dalších edge funkcí, 3 storage buckety, branch-based RLS, dodatečné sloupce (bookings, motorcycles, profiles, sos_incidents), 19+ dalších DB funkcí, foreign keys, 11 secrets, cron jobs |
| 2026-03-09 00:15 | Přidána funkce `validate_voucher_code(p_code)` — validace dárkových poukazů ve slevovém kódu |
| 2026-03-09 | **FIX invoices:** Oprava sync triggeru (payment_receipt → správný doc type), přidán WITH CHECK na RLS policy, zajištění sloupců variable_symbol/source/order_id, customer INSERT policy |
| 2026-03-09 | **FIX shop payment:** Přidána RPC `confirm_shop_payment(p_order_id, p_method)` (SECURITY DEFINER) + UPDATE RLS policy na shop_orders pro zákazníka |
| 2026-03-09 | **FIX documents.type:** Sloupec `documents.type` změněn z `document_type` ENUM na TEXT. ENUM `document_type` zrušen. Trigger `sync_invoice_to_documents()` přepsán s TEXT mapováním (invoice_advance, payment_receipt, invoice_shop, invoice_final) |
| 2026-03-09 | **FIX generate_shop_invoice:** Opraven typ faktury z `'shop'` na `'shop_final'` (splňuje CHECK constraint). Přidán `source='shop'` a SECURITY DEFINER |
| 2026-03-09 | **NEW:** Přidán sloupec `bookings.modification_history` (jsonb, default '[]') — historie všech úprav termínu rezervace |
| 2026-03-10 | **FIX SOS triggers:** Dropnut trigger `sos_auto_reply_on_create` (crashoval INSERT bez error handleru). `trigger_sos_auto_reply()` přepsán na safe no-op. `check_one_active_sos()` a `sos_notify_user_on_create()` přepsány s SECURITY DEFINER |
| 2026-03-11 | **KOMPLETNÍ OPRAVA SOS v2:** DROP ALL triggers na sos_incidents + recreate. Klíčová oprava: `check_one_active_sos()` doplněn `WHEN OTHERS THEN RETURN NEW` (dříve libovolná neočekávaná chyba blokovala INSERT). Všechny SOS funkce s explicitním `::text` castem pro ENUM kompatibilitu. Přidán diagnostický + test INSERT v migraci |
| 2026-03-11 | **FIX license_group enum:** Přidána hodnota `N` (nevyžaduje ŘP) do enumu `license_group` — oprava chyby při ukládání dětských motorek s `license_required = 'N'` |
| 2026-03-11 | **NEW: Smluvní texty v document_templates:** Seed 3 šablon — VOP (type=`vop`), Nájemní smlouva (type=`rental_contract`), Předávací protokol (type=`handover_protocol`) s kompletními právními texty jako HTML. Velín: nový tab „Smluvní texty" v Dokumenty. BookingDocumentsTab nyní načítá šablony z DB místo hardcoded HTML |
| 2026-03-11 | **FIX check_one_active_sos:** Změna logiky z per-user na per-booking. Kontrola: max 1 závažný aktivní incident (typ NOT IN breakdown_minor, defect_question, location_share, other) na jednu aktivní rezervaci (status reserved/active). Lehké incidenty nejsou omezeny. Pokud incident nemá booking_id, fallback na per-user kontrolu |
| 2026-03-12 | **FIX confirm_payment:** Podmíněný přechod stavu dle start_date: start_date <= dnes → `pending→active` (pronájem začíná), start_date > dnes → `pending→reserved` (nadcházející). Nastavení `confirmed_at`, při active i `picked_up_at` |
| 2026-03-12 | **NEW: Auto-cancel pending bookings:** Přidán sloupec `bookings.booking_source` (text, default 'app'). Nová funkce `auto_cancel_expired_pending()` (SECURITY DEFINER) — ruší pending+unpaid: app po 10 min, web po 4h. pg_cron job `auto-cancel-pending-bookings` každé 2 minuty |
| 2026-03-12 | **NEW: Header banner:** Nový klíč `header_banner` v `app_settings` (jsonb: enabled, text, bg, color). Rotující promo banner v mobilní aplikaci nad logem, editovatelný z Velín dashboardu |
| 2026-03-12 | **FIX confirm_payment v3 (robust):** Přidáno exception handling — pokud trigger (bookings_auto_accounting) zhavaruje, funkce provede minimální update (payment_status+payment_method) a pak separátní update statusu. Frontend: opraveno parsování RPC jsonb odpovědi (string vs object), přidán 5. fallback tier (minimální update). Edge function: přidán CORS Allow-Methods, robustnější error handling |
| 2026-03-12 | **FIX header banner:** Frontend: `.single()` → `.maybeSingle()` (nehavaruje když klíč neexistuje). Přidán realtime subscription pro okamžitou aktualizaci banneru. Velín: opraveno načítání banneru |
| 2026-03-12 | **FIX payment triggers (root cause):** `auto_accounting_on_booking_paid()` přepsán s EXCEPTION handling — crashující trigger blokoval VŠECHNY booking UPDATy (platba vždy zamítnuta). Trigger `bookings_auto_accounting` omezen na `AFTER UPDATE OF payment_status WHEN (NEW='paid' AND OLD IS DISTINCT FROM 'paid')`. Trigger `trg_check_booking_overlap` omezen na `UPDATE OF start_date, end_date, moto_id` (nefiruje při platebních updatech). Edge function: `!amount` → `amount == null` (akceptuje amount=0). Znovuaplikován robust `confirm_payment` s EXCEPTION handling |
| 2026-03-13 | **NEW: Per-user overlap check:** `check_user_booking_overlap()` trigger — zákazník nesmí mít 2 překrývající se rezervace (kromě dětských motorek license_required=N). Trigger `trg_check_user_booking_overlap` BEFORE INSERT/UPDATE OF start_date, end_date, user_id, status |
| 2026-03-13 | **NEW: Auto-complete expired bookings:** `auto_complete_expired_bookings()` — active/reserved + end_date < today + paid → completed. pg_cron job `auto-complete-expired-bookings` denně v 00:01 |
| 2026-03-13 | **FIX: Document templates .single()→array:** Edge function generate-document a app apiFetchDocTemplate: `.single()` nahrazeno `.limit(1)` + array[0] (single selhával při 0/2+ výsledcích → fallback místo DB šablony). Per-user overlap check v apiCreateBooking a Velín NewBookingModal. Velín getDisplayStatus: end_date < today → completed, reserved → Nadcházející/Aktivní dle data |
| 2026-03-13 | **FIX: SOS flow + auto-activate reserved:** 1) SOS booking queries přidán status 'reserved' (apiGetActiveLoan, ui-controller 4× query, sos_swap_bookings RPC). 2) sosEndRide/sosEndRideFree: booking→completed+ended_by_sos+moto→maintenance. 3) sosPaymentSubmit: opraveno ZF/DP generování (fallback booking_id, payment_status update). 4) Velín: StatusBadge 'Dokončeno SOS', FleetDetail SOS incidenty. 5) auto_activate_reserved_bookings() — reserved+paid+start_date<=today→active. pg_cron denně 00:01. Velín Bookings.jsx: autoActivateReserved() při každém načtení |
| 2026-03-13 | **NEW: Auto voucher processing:** BEFORE UPDATE trigger `auto_process_voucher_order()` na shop_orders — při zaplacení automaticky: (1) generuje voucher kódy, (2) posílá in-app notifikaci do admin_messages, (3) nastavuje status (delivered pro čistě digitální, confirmed pro mixed/fyzické). Velín: odstraněna klientská autoConfirmPaidVouchers, nahrazena DB triggerem. Frontend: checkout zobrazuje specifickou success zprávu s odkazem na zprávy pro voucher objednávky |
| 2026-03-14 | **FIX: Door codes in DP + email:** Edge function `generate-invoice` nyní pro payment_receipt (DP) načítá přístupové kódy z `branch_door_codes` a renderuje je v HTML faktuře i v emailu zákazníkovi. Motogo app: blokuje rezervace na zavřených pobočkách (`is_open=false`) |
| 2026-03-14 | **NEW: Autonomní pobočky:** 1) Nové sloupce `branches.branch_code` (TEXT UNIQUE) a `branches.is_open` (BOOLEAN). Odstraněny opening_hours a email z UI. 2) Nová tabulka `branch_accessories` — sklad příslušenství per pobočka (boty, helmy, kukly, rukavice, kalhoty v různých velikostech). 3) Nová tabulka `branch_door_codes` — přístupové kódy ke dveřím per motorka a příslušenství. Kódy auto-generovány (6 číslic), aktivní jen při aktivní rezervaci. Pokud zákazník nemá nahrané doklady (OP/pas/ŘP), kód je zadržen a odeslán dodatečně. Každá motorka má vlastní dveře (vlastní kód), příslušenství má sdílené dveře (max 8 aktivních kódů). Velín: kompletní přepis Branches.jsx s taby (Info, Motorky, Příslušenství, Přístupové kódy) |
| 2026-03-14 | **FIX: Voucher trigger silent fail:** `admin_messages_type_check` CHECK constraint neobsahoval hodnotu `'voucher'` → trigger `auto_process_voucher_order()` tiše padal (EXCEPTION handler). Oprava: přidán `'voucher'` do CHECK constraint. Platnost voucherů: 3 roky. Doklady (ZF/DP/FK) + email: zobrazují kód, částku i platnost |
| 2026-03-15 | **REFACTOR: KF faktura triggerem:** `auto_complete_expired_bookings()` přepsána — pouze mění status, negeneruje KF. Nová trigger funkce `generate_final_invoice_on_complete()` generuje KF (konečnou fakturu) při přechodu `active→completed`. Trigger `trg_generate_final_invoice` AFTER UPDATE OF status WHEN (active→completed). EXCEPTION safe — chyba logována ale neblokuje UPDATE |
| 2026-03-15 | **FIX: Robust SOS swap + KF + ZF/DP:** 1) `sos_swap_bookings` RPC: přidán fallback pro nalezení `ended_by_sos` bookingů (pokud `_sosEndBooking` běžel dříve), ukládá `original_end_date`, nastavuje `picked_up_at`. 2) `generate_final_invoice_on_complete()`: přeskakuje KF pro `ended_by_sos` a `sos_replacement` bookings (SOS potřebuje separátní fakturaci). 3) `check_user_booking_overlap()`: výjimka pro `sos_replacement=true` bookings. 4) Frontend `sosPaymentSubmit`: robustnější hledání replacement_booking_id (3 fallback metody), po platbě nastaví `status=active`+`picked_up_at`. Manuální fallback hledá i `ended_by_sos` bookings. 5) Velín: tlačítko "Reaktivovat" pro completed SOS replacement bookings |
| 2026-03-17 | **FIX: Mindee OCR document recognition:** 1) Nová Edge Function `scan-document` v repozitáři — správná integrace Mindee API (international_id/v2 pro OP+ŘP, passport/v1 pro pasy). Multipart upload, retry 3×, logování do debug_log. 2) Frontend: strip data URI prefix z base64 před odesláním. 3) Auto-save OCR dat do profiles tabulky (jméno, datum narození, adresa, číslo ŘP, kategorie, expirace). 4) Upload fotek dokladů do Supabase storage (`documents` bucket, `user-docs/{uid}/`). 5) Nové API funkce: `apiSaveOcrToProfile()`, `apiUploadDocPhoto()`. 6) Po dokončení skenu automatický refresh profilu z DB |
| 2026-03-17 | **FIX: Nepřečtené zprávy v konverzacích:** 1) Nové RPC `mark_thread_messages_read(p_thread_id)` — SECURITY DEFINER, označí admin zprávy jako přečtené (read_at=now). 2) Nové RPC `get_unread_thread_message_count(p_customer_id)` — vrací počet nepřečtených admin zpráv. 3) Frontend fix: `apiFetchMyThreads()` nyní načítá i `read_at` sloupec (dříve chyběl → badge vždy ukazoval nepřečtené) |
| 2026-03-17 | **NEW: Produkty v e-shopu:** 1) Nová tabulka `products` (name, description, price, images[], sizes[], sku, stock_quantity, category, color, material, is_active, sort_order). RLS: public SELECT, admin ALL. Realtime. Trigger `trg_products_updated`. 2) Velín: nový tab „Produkty" v E-shop sekci s kompletním CRUD (přidání, editace, smazání, toggle aktivní/neaktivní). 3) Mobilní app: `templates-shop.js` přepsán — produkty se načítají dynamicky z DB místo hardcoded MERCH_ITEMS. Dynamické velikosti z DB. Kontrola skladového množství (vyprodáno). 4) Seed 4 existujících produktů (Snapback čepice, Tričko Classic, Hoodie Premium, Tričko Ride Hard) |
| 2026-03-18 | **SECURITY: Odstranění Service Role Key z frontendu:** 1) `useAdmin.js` — odstraněn hardcoded service_role klient, hook nyní používá pouze anon key z `supabase.js`. Auto-provisioning přesunut do Edge Function `admin-auth`. 2) `admin-auth` Edge Function přidána do repozitáře — ověří JWT, vytvoří admin_users záznam přes service role (server-side). 3) `supabase.js` — exportuje `supabaseUrl` a `supabaseAnonKey` jako jedinou instanci. 4) `generate-invoice` a `generate-document` nyní načítají firemní údaje z `app_settings` (key: company_info) místo hardcoded konstant. 5) Všechny DIAGNOSTIKA panely ve Velínu (26 souborů) schované za `useDebugMode()` hook — zobrazí se jen přes URL `?debug=1`, localStorage `debug_mode=1`, nebo feature flag `debug_mode` v DB. 6) Dashboard: ISO datumy formátovány přes `toLocaleDateString('cs-CZ')` |
| 2026-03-18 | **NEW: Stripe integrace + Email retry:** 1) `process-payment` přepsán na reálnou Stripe integraci (TEST mode) — Checkout Session + PaymentIntent. Podporuje 4 typy plateb: `booking`, `shop`, `extension` (prodloužení rezervace), `sos` (placený SOS incident). 2) Nová edge function `webhook-receiver` v repozitáři — ověření Stripe signature, zpracování `checkout.session.completed` a `payment_intent.succeeded`, volání `confirm_payment`/`confirm_shop_payment` RPC + přímý update pro SOS. 3) `send-booking-email` a `send-cancellation-email` — přidán `sendWithRetry()` wrapper (3 pokusy, exponential backoff 2s/4s/8s). Při finálním selhání logování do `debug_log`. 4) Nový secret: `STRIPE_WEBHOOK_SECRET`. 5) Frontend: `apiProcessPayment()` rozšířen o 4. parametr `opts` ({type, order_id, incident_id}). `doEditPayment` posílá `type:'extension'`. `sosPaymentSubmit` přepsán — místo simulace volá Stripe přes `apiProcessPayment` s `type:'sos'` |
| 2026-03-17 | **FIX: Přístupové kódy — automatický lifecycle:** 1) Nové trigger funkce `auto_generate_door_codes()` — auto-generuje 2 kódy (motorcycle+accessories) při přechodu bookingu na 'active'. Kontroluje doklady, posílá kódy jako admin_message. 2) `auto_deactivate_door_codes()` — deaktivuje kódy při přechodu na 'completed'/'cancelled'. 3) Triggery: `trg_auto_generate_door_codes` (UPDATE), `trg_auto_generate_door_codes_insert` (INSERT), `trg_auto_deactivate_door_codes` (UPDATE). 4) Jednorázový cleanup: deaktivace kódů u existujících dokončených/zrušených rezervací. 5) Mobilní app: `_autoActivateAndCompleteBookings()` — automatická aktivace reserved+paid bookingů a dokončení expired bookingů při otevření rezervací (nečeká na Velín nebo cron) |
| 2026-03-18 | **NEW: AI Copilot + AI Agent + SOS foto + Google recenze:** 1) Edge Function `ai-copilot` přepsána — Anthropic Claude API (claude-sonnet-4), system prompt CZ, načítá DB kontext (bookings, tržby, servis, SOS), JWT auth. 2) Velín AICopilot.jsx: suggested prompts nyní kliknutím odešlou zprávu rovnou. 3) Nová Edge Function `ai-moto-agent` — servisní AI chatbot pro zákazníky, diagnostika závad, vrací {reply, is_rideable, suggest_sos}. 4) Nový screen `s-ai-agent` v mobilní app s chat UI, přístupný ze SOS/porucha. 5) SOS fotodokumentace: nový modul `sos-photo.js` — Capacitor Camera + HTML fallback, resize 2048px/JPEG 80%, upload do `sos-photos` bucket, 1-5 fotek. Photo step injektován do s-sos-nehoda, s-sos-porucha, s-sos-kradez. 6) Google recenze: po dokončení rezervace banner s přesměrováním na Google Reviews. URL z `app_settings.google_review_url`. Tracking v `reviews` tabulce. 7) Nový secret: `ANTHROPIC_API_KEY` |
| 2026-03-21 | **NEW: Claude Vision OCR + Flexi pull + Datová schránka:** 1) `receive-invoice` přepsána — Mindee nahrazena Claude Vision (claude-opus-4-5), rozpoznává 10 typů dokumentů (faktura, účtenka, kupní smlouva, úvěr, pracovní smlouva, pojistka, leasing aj.). routeDocument() automaticky směruje do acc_long_term_assets (kupní smlouvy), acc_liabilities (úvěry/leasing/pojistky), acc_employees (pracovní smlouvy). 2) `flexi-sync` rozšířena o 7 PULL akcí (pullVatReturn, pullIncomeTax, pullBalanceSheet, pullProfitLoss, pullOSSZ, pullVZP, pullAll) — stahuje výkazy z Abra Flexi do tabulky `flexi_reports`. 3) Nová tabulka `flexi_reports` (report_type, year, quarter, raw_data, rendered_html, status draft/approved/submitted/rejected, approval tracking, datova_schranka_message_id). 4) Nová Edge Function `datova-schranka` — generuje ISDS XML, ukládá do Storage bucket `datova-schranka-outbox`, volitelně odesílá přes ISDS SOAP API. Secrets: DS_FINANCNI_URAD, DS_CSSZ, DS_VZP, DS_API_URL, DS_LOGIN, DS_PASSWORD. 5) Velín: nový subtab „Výkazy a přiznání" v Účetnictví (ReportsTab.jsx — stahování z Flexi, schvalování, XML export). DataBoxTab ve Státní správě rozšířen o odeslání schválených výkazů datovkou |
| 2026-03-20 | **NEW: Kompletní účetnictví ve Velínu:** Finance tab přestrukturován — záložka „Daňové podklady" nahrazena sekcí „Účetnictví" se 6 pod-záložkami: **Zaměstnanci** (evidence zaměstnanců, typy smluv HPP/DPP/DPC/IČO, automatický výpočet mezd — SP 6.5%+24.8%, ZP 4.5%+9%, záloha daně 15%, sleva na poplatníka 2570 Kč/měs), **Přiznání k DPH** (čtvrtletní generování, XML export pro EPO, zdanitelné vstupy/výstupy), **Daňové přiznání** (roční DP, progresivní daň 15%/23%, odpisy, mzdy, sleva 30840 Kč), **Krátkodobý majetek** (materiál, drobný majetek, zásoby, pohledávky), **Dlouhodobý majetek** (odpisové skupiny 1-6 dle § 30 ZDP, rovnoměrné i zrychlené odpisy, automatické generování odpisů, vizuální progress bar), **Závazky** (dodavatelé, daně, SP, ZP, mzdy, úvěry, auto-detekce po splatnosti). 8 nových DB tabulek: acc_employees, acc_payrolls, acc_vat_returns, acc_tax_returns, acc_short_term_assets, acc_long_term_assets, acc_depreciation_entries, acc_liabilities. Trigger `auto_liabilities_from_payroll()` automaticky vytváří závazky (SP, ZP, daň, mzda) při generování mezd. Přidána Pokladna do hlavních záložek Finance |
