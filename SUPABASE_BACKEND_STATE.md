# SUPABASE BACKEND STATE — MotoGo24
> **Poslední aktualizace:** 2026-03-09 10:00 UTC
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
| `license_group` | AM, A1, A2, A, B |
| ~~`document_type`~~ | **ZRUŠENO** — sloupec `documents.type` je nyní TEXT (ne ENUM). Používané hodnoty: contract, vop, invoice_advance, payment_receipt, invoice_final, invoice_shop, protocol |

---

## 2. TABULKY (public schema) — 61 tabulek

### Hlavní entity

| Tabulka | Popis |
|---------|-------|
| `profiles` | Zákaznické profily (vazba na auth.users) |
| `motorcycles` | Flotila motorek |
| `bookings` | Rezervace |
| `branches` | Pobočky |
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
| `admin_messages` | Admin zprávy |
| `notification_log` | Log notifikací |
| `notification_rules` | Pravidla notifikací |
| `push_tokens` | Push tokeny zařízení |

### Dokumenty a faktury

| Tabulka | Popis |
|---------|-------|
| `invoices` | Faktury (type: issued/received/final/proforma/shop_proforma/shop_final/advance/payment_receipt, source: booking/edit/sos/shop/restore) |
| `document_templates` | Šablony dokumentů (type TEXT, html_content, variables) |
| `generated_documents` | Vygenerované dokumenty |
| `documents` | Nahrané dokumenty (type TEXT — contract, vop, invoice_advance, payment_receipt, invoice_final, invoice_shop, protocol) |
| `email_templates` | Šablony emailů (slug: booking_reserved, booking_abandoned, booking_cancelled, booking_completed, voucher_purchased, booking_modified) |
| `sent_emails` | Log odeslaných emailů |

### E-shop

| Tabulka | Popis |
|---------|-------|
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

### Nákupy a sklad

| Tabulka | Popis |
|---------|-------|
| `purchase_orders` | Nákupní objednávky |
| `purchase_order_items` | Položky nákupních objednávek |
| `suppliers` | Dodavatelé |
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
| `confirm_payment(booking_id, method)` | RPC: označí booking jako zaplacený |
| `confirm_shop_payment(order_id, method)` | RPC: označí shop objednávku jako zaplacenou (SECURITY DEFINER) |
| `check_booking_overlap()` | Trigger funkce: kontrola překrytí rezervací |
| `generate_shop_invoice()` | Trigger funkce: auto-faktura při zaplacení shop objednávky (type='shop_final', source='shop', SECURITY DEFINER) |

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
| `trigger_sos_auto_reply()` | Trigger pro auto SOS odpověď |
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
| `trg_check_booking_overlap` | bookings (INSERT/UPDATE) | check_booking_overlap() |
| `trg_generate_shop_invoice` | shop_orders (payment_status) | generate_shop_invoice() |
| `moto_day_prices_updated` | moto_day_prices | update_updated_at() |
| `trg_ai_conversations_updated` | ai_conversations | update_updated_at() |
| `trg_sos_notify_user` | sos_incidents (INSERT) | sos_notify_user_on_create() |
| `trg_one_active_sos` | sos_incidents (INSERT) | check_one_active_sos() |
| `trg_bridge_admin_message` | messages (INSERT) | bridge_admin_message_to_app() |
| `trg_restore_vouchers_on_cancel` | bookings (UPDATE) | restore_vouchers_on_cancel() |
| `trg_sync_invoice_to_documents` | invoices (INSERT) | sync_invoice_to_documents() |
| `trg_sync_invoice_pdf_update` | invoices (UPDATE pdf_path) | sync_invoice_pdf_update() |
| `trg_sync_generated_doc_to_documents` | generated_documents (INSERT) | sync_generated_doc_to_documents() |
| `trg_sync_moto_day_prices` | moto_day_prices (INSERT/UPDATE) | sync_moto_day_prices_to_motorcycles() |

### Další triggery v reálné DB
| Trigger | Tabulka | Funkce |
|---------|---------|--------|
| `bookings_auto_accounting` | bookings | auto_accounting_on_booking_paid() |
| `maintenance_log_after_insert` | maintenance_log | update_moto_after_service() |
| `sos_auto_reply_on_create` | sos_incidents (INSERT) | trigger_sos_auto_reply() |
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
- `documents`
- `invoices`
- `vouchers`

---

## 8. EDGE FUNKCE (20 deployovaných)

### V repozitáři (6)

| Funkce | Popis |
|--------|-------|
| `send-booking-email` | Odesílá branded HTML emaily (booking_reserved, booking_completed, booking_modified, voucher_purchased) |
| `generate-invoice` | Generuje proforma/finální fakturu (ZF-/FV-YYYY-NNNN) |
| `generate-document` | Generuje dokumenty z šablon (rental_contract, handover_protocol) |
| `send-cancellation-email` | Email o stornování rezervace s "obnovit" CTA |
| `admin-reset-password` | Admin reset hesla zákazníka |
| `process-payment` | SIMULOVANÁ platební brána (DEV ONLY, 90% úspěšnost) |

### Pouze v Supabase dashboardu (14 dalších)

| Funkce | Popis |
|--------|-------|
| `admin-auth` | Autentizace admin uživatelů |
| `ai-copilot` | AI Copilot pro Velín dashboard |
| `bright-endpoint` | Bright Data endpoint |
| `cms-sync` | Synchronizace CMS obsahu |
| `cron-daily` | Denní cron úlohy |
| `cron-monthly` | Měsíční cron úlohy |
| `export-data` | Export dat (CSV/XLSX) |
| `generate-report` | Generování reportů |
| `generate-tax` | Generování daňových záznamů |
| `inventory-check` | Kontrola stavu skladu |
| `prediction-engine` | Predikční engine (obsazenost, tržby) |
| `scan-document` | Skenování dokumentů (Mindee OCR) |
| `send-email` | Obecné odesílání emailů (jiné než booking) |
| `send-sos` | SOS notifikace |
| `upload-handler` | Zpracování nahraných souborů |
| `webhook-receiver` | Příjem webhooků (Stripe, platební brány) |

---

## 9. STORAGE BUCKETY

| Bucket | Přístup | Použití |
|--------|---------|---------|
| `documents` | **private** | Faktury (invoices/{id}.html), generované dokumenty (generated/{uuid}.html), smlouvy |
| `media` | **public** | Fotky motorek, loga, marketingové materiály |
| `sos-photos` | **private** | Fotky z SOS incidentů (poškození, nehody) |

---

## 10. SECRETS (8)

| Secret | Kde se používá |
|--------|---------------|
| `SUPABASE_URL` | Všechny edge funkce |
| `SUPABASE_SERVICE_ROLE_KEY` | Všechny edge funkce |
| `SUPABASE_ANON_KEY` | admin-reset-password |
| `SUPABASE_DB_URL` | Přímý DB přístup z edge funkcí |
| `RESEND_API_KEY` | send-booking-email, generate-invoice, send-cancellation-email, send-email |
| `FROM_EMAIL` | Email funkce (default: noreply@motogo24.cz) |
| `SITE_URL` | send-booking-email, send-cancellation-email (default: https://motogo24.cz) |
| `MINDEE_API_KEY` | scan-document (OCR) |
| `STRIPE_SECRET_KEY` | webhook-receiver, process-payment |
| `ADMIN_EMAIL` | SOS notifikace, cron alerty |
| `ADMIN_PHONE` | SOS SMS notifikace |

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

---

## 12. SEKVENCE

- `shop_order_seq` — formát: OBJ-YYYY-NNNNN (start 1001)

---

## 13. CRON JOBS (pg_cron)

| Job | Čas | Funkce |
|-----|-----|--------|
| `expire-vouchers` | denně 01:00 UTC | `SELECT expire_vouchers()` |
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
