# SUPABASE BACKEND STATE — MotoGo24
> **Poslední aktualizace:** 2026-03-08 21:45 UTC
> **Zdroj:** Migrace v `supabase/functions/migrations/` + edge funkce
> **POZOR:** Tento soubor MUSÍ být aktualizován při každé SQL změně!

---

## 1. TABULKY (public schema)

### Hlavní entity

| Tabulka | Popis |
|---------|-------|
| `profiles` | Zákaznické profily (vazba na auth.users) |
| `motorcycles` | Flotila motorek |
| `bookings` | Rezervace |
| `branches` | Pobočky |
| `admin_users` | Admin uživatelé (role: admin, superadmin, technician, readonly) |

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
| `sos_timeline` | Timeline akcí v rámci incidentu |

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
| `invoices` | Faktury (type: issued/received/final/proforma/shop_proforma/shop_final/advance/payment_receipt) |
| `document_templates` | Šablony dokumentů (type, html_content, variables) |
| `generated_documents` | Vygenerované dokumenty |
| `documents` | Nahrané dokumenty (soubory) |
| `email_templates` | Šablony emailů (slug: booking_reserved, booking_abandoned, booking_cancelled, booking_completed, voucher_purchased, booking_modified) |
| `sent_emails` | Log odeslaných emailů |

### E-shop

| Tabulka | Popis |
|---------|-------|
| `shop_orders` | Objednávky (status: new/confirmed/processing/shipped/delivered/cancelled/returned/refunded) |
| `shop_order_items` | Položky objednávek |

### Promo a vouchery

| Tabulka | Popis |
|---------|-------|
| `promo_codes` | Slevové kódy (type: percent/fixed) |
| `promo_code_usage` | Použití slevových kódů |
| `vouchers` | Dárkové poukazy (status: active/redeemed/expired/cancelled) |

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
| `debug_log` | Debug log |

### Audit

| Tabulka | Popis |
|---------|-------|
| `admin_audit_log` | Audit log admin akcí (admin_id, action, details jsonb, ip_address) |

---

## 2. KLÍČOVÉ SLOUPCE

### bookings
- id, user_id, moto_id, start_date, end_date, pickup_time
- status (pending/reserved/active/completed/cancelled/rejected)
- payment_status (pending/paid/unpaid/refunded/failed)
- payment_method, total_price, delivery_fee, deposit
- promo_code_id, voucher_id, notes
- confirmed_at, picked_up_at, returned_at
- cancelled_by, cancelled_by_source, cancellation_reason, cancelled_at, cancellation_notified
- sos_replacement (boolean), replacement_for_booking_id, sos_incident_id, ended_by_sos
- pickup_date, return_date (timestamptz pro overlap check)

### profiles
- id (refs auth.users), full_name, email, phone
- street, city, zip, country
- ico, dic, license_number, license_expiry
- license_group (text[]), riding_experience
- emergency_contact, emergency_phone
- gear_sizes (jsonb), reliability_score (jsonb)
- marketing_consent (boolean)

### motorcycles
- id, model, spz, vin, year, status
- stk_valid_until, acquired_at
- (další sloupce definované mimo migrace v repo)

### sos_incidents
- id, user_id, booking_id, type, title, description
- severity (low/medium/high/critical)
- status (reported/acknowledged/in_progress/resolved/closed)
- moto_rideable, customer_decision, customer_fault
- damage_description, damage_severity (none/cosmetic/functional/totaled)
- latitude, longitude, address, photos[]
- nearest_service_name/address/phone
- assigned_to, contact_phone, admin_notes
- resolution, resolved_at, resolved_by
- original_booking_id, replacement_booking_id, original_moto_id
- type CHECK: theft/accident_minor/accident_major/breakdown_minor/breakdown_major/defect_question/location_share/other

### invoices
- id, number, type, customer_id, supplier_id, booking_id
- issue_date, due_date, paid_date
- subtotal, tax_amount, total, status, pdf_path
- items (jsonb), notes, variable_symbol, source

### vouchers
- id, code, amount, currency, status (active/redeemed/expired/cancelled)
- buyer_id, buyer_name, buyer_email
- valid_from, valid_until
- redeemed_at, redeemed_by, redeemed_for, booking_id
- description, category (rental/gear/experience/gift)
- created_by

---

## 3. RPC FUNKCE (callable z frontendu)

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

---

## 4. TRIGGERY

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

---

## 5. RLS POLITIKY (souhrn)

Všechny tabulky mají RLS zapnuté. Vzor:
- **Admin full access:** `FOR ALL USING (is_admin())`
- **Superadmin write:** `FOR ALL USING (is_superadmin())`
- **Customer read own:** `FOR SELECT USING (user_id = auth.uid())`
- **Customer insert own:** `FOR INSERT WITH CHECK (user_id = auth.uid())`
- **Public read:** `FOR SELECT USING (true)` — branches, moto_locations, moto_day_prices, promo_codes(active), app_settings

---

## 6. REALTIME (supabase_realtime publication)

- `sos_incidents`
- `sos_timeline`
- `messages`
- `message_threads`

---

## 7. EDGE FUNKCE

### send-booking-email
- **Secrets:** RESEND_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, FROM_EMAIL, SITE_URL
- **Popis:** Odesílá branded HTML emaily (booking_reserved, booking_completed, booking_modified, voucher_purchased)
- **Tabulky:** email_log (write)

### generate-invoice
- **Secrets:** SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, RESEND_API_KEY, FROM_EMAIL
- **Popis:** Generuje proforma (ZF-YYYY-NNNN) nebo finální (FV-YYYY-NNNN) fakturu
- **Tabulky:** bookings, motorcycles, profiles (read), invoices, admin_audit_log (write)
- **Storage:** documents/invoices/{id}.html

### generate-document
- **Secrets:** SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
- **Popis:** Generuje dokumenty z šablon (rental_contract, handover_protocol)
- **Tabulky:** document_templates, bookings, motorcycles, profiles (read), generated_documents, admin_audit_log (write)
- **Storage:** documents/generated/{uuid}.html

### send-cancellation-email
- **Secrets:** RESEND_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, FROM_EMAIL, SITE_URL
- **Popis:** Odesílá email o stornování rezervace s "obnovit" CTA
- **Tabulky:** bookings (write: cancellation_notified=true)

### admin-reset-password
- **Secrets:** SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY
- **Popis:** Admin reset hesla zákazníka (direct nebo email recovery link)
- **Tabulky:** admin_users, profiles (read), admin_audit_log (write)

### process-payment (motogo-app-frontend)
- **Secrets:** SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
- **Popis:** SIMULOVANÁ platební brána (90% úspěšnost, 2s delay) — DEV ONLY
- **Tabulky:** bookings (write: payment_status, payment_method)

---

## 8. STORAGE BUCKETY

| Bucket | Použití |
|--------|---------|
| `documents` | Faktury (invoices/{id}.html), generované dokumenty (generated/{uuid}.html) |
| (ověřit v dashboardu další buckety pro fotky motorek, SOS fotky atd.) |

---

## 9. SECRETS PŘEHLED

| Secret | Kde se používá |
|--------|---------------|
| `SUPABASE_URL` | Všechny edge funkce |
| `SUPABASE_SERVICE_ROLE_KEY` | Všechny edge funkce |
| `SUPABASE_ANON_KEY` | admin-reset-password |
| `RESEND_API_KEY` | send-booking-email, generate-invoice, send-cancellation-email |
| `FROM_EMAIL` | send-booking-email, generate-invoice, send-cancellation-email (default: noreply@motogo24.cz) |
| `SITE_URL` | send-booking-email, send-cancellation-email (default: https://motogo24.cz) |

---

## 10. SEED DATA (app_settings)

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

## 11. SEKVENCE

- `shop_order_seq` — formát: OBJ-YYYY-NNNNN (start 1001)

---

## 12. CRON JOBS (pg_cron)

- `expire-vouchers` — denně 01:00 UTC — `SELECT expire_vouchers()`

---

## CHANGELOG

| Datum | Změna |
|-------|-------|
| 2026-03-08 | Prvotní vytvoření ze 32 migrací + 6 edge funkcí |
