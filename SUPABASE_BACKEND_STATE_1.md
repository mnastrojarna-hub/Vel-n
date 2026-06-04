# SUPABASE BACKEND STATE — MotoGo24 (Část 1: Tabulky)
> **Poslední aktualizace:** 2026-05-20 (Fix door codes — `auto_generate_door_codes` + `check_booking_docs_status` vyžadují fotku NEBO reálné OCR `verified_at`, holá ručně zadaná čísla už kódy neuvolní; Velín rozlišuje tři stavy ověření + nový admin upload dokladů s kamerou)
> **Zdroj:** Reálný stav Supabase databáze (SQL dump z dashboardu) + Edge Functions
> **Projekt:** `vnwnqteskbykeucanlhk.supabase.co`
> **POZOR:** Tento soubor MUSÍ být aktualizován při každé SQL změně!
> **Soubory:** 1/6 (Tabulky) | 2/6 (Sloupce) | 3/6 (RPC funkce) | 4/6 (Triggery) | 5/6 (RLS, Realtime, Edge, Storage, Secrets) | 6/6 (Changelog)

---

## 1. ENUM TYPY

| Typ | Hodnoty |
|-----|---------|
| `admin_role` | viewer, manager, operator, technician, readonly, admin, superadmin |
| `booking_status` | pending, reserved, active, completed, cancelled |
| `payment_status` | unpaid, paid, refund_pending, partial_refund, refunded — **`refund_pending` NEW 2026-05-31** = „Čeká na vrácení" (storno zaplacené rezervace, Stripe refund ještě nepotvrzen; peníze jsou stále u nás). Životní cyklus: `paid` → (storno) `refund_pending` → (Stripe potvrdil) `partial_refund` (50 %) / `refunded` (100 %). Velín mapuje přes `paymentStatusInfo()` (Zaplaceno/Čeká na vrácení/Částečně vráceno/Vráceno/Nezaplaceno) + filtr `PAYMENT_STATUS_FILTER_OPTIONS`. |
| `moto_status` | active, maintenance, unavailable, retired |
| `sos_status` | reported, acknowledged, in_progress, resolved, closed |
| `license_group` | AM, A1, A2, A, B, N |
| ~~`document_type`~~ | **ZRUŠENO** — sloupec `documents.type` je nyní TEXT (ne ENUM). Používané hodnoty: contract, vop, invoice_advance, payment_receipt, invoice_final, invoice_shop, protocol, credit_note |

---

## 2. TABULKY (public schema) — 98 tabulek (živý snapshot 2026-06-04; vč. 2 dočasných `cms_variables_backup_*` určených ke smazání → cílově 96)

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
| `booking_complaints` | **NEW v docs 2026-06-04 (ze snapshotu)** — Reklamace k rezervacím (booking_id, customer_id FK→profiles ON DELETE SET NULL, subject, description, status, resolution, resolved_at, resolved_by FK→auth.users ON DELETE SET NULL, created_at, updated_at) |
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
| `admin_messages` | Admin zprávy (type TEXT, bez CHECK constraintu — používané hodnoty: sos_response, accident_response, replacement, tow, info, thanks, voucher, door_codes) |
| `notification_log` | Log notifikací |
| `notification_rules` | Pravidla notifikací |
| `push_tokens` | Push tokeny zařízení |
| `message_log` | Centrální log všech odeslaných zpráv (SMS, WhatsApp, email) — channel, recipient, template_slug, status, provider_response, metadata |
| `broadcast_campaigns` | **NEW v docs 2026-06-04 (ze snapshotu)** — Hromadné kampaně (name, channel, template_id, segment, segment_filter jsonb, template_vars jsonb, scheduled_at, status, total_recipients, sent_count, failed_count, created_by, completed_at) — edge fn `send-broadcast` |
| `message_templates_sms` | SMS/WhatsApp šablony (slug unikátní, body_template s {{placeholdery}}) |

### Dokumenty a faktury

| Tabulka | Popis |
|---------|-------|
| `invoices` | Faktury (type: issued/received/final/proforma/shop_proforma/shop_final/advance/payment_receipt/**credit_note**, source: booking/edit/sos/shop/restore/**refund**) |
| `document_templates` | Šablony dokumentů (id uuid, type TEXT, name TEXT, content_html TEXT, active BOOL, version INT, updated_by uuid, created_at, updated_at, **content_translations JSONB** = `{ "<lang>": "<html string>" }` — přeložený obsah, čte RPC `get_document_translation`, sloupec z mig. `20260503_i18n_customer_comms.sql` §5.6; **name_translations JSONB** = `{ "<lang>": "<přeložený název>" }` — mig. `20260512_document_templates_name_translations.sql`; oba plní edge fn `translate-document`) |
| `custom_documents` | Vlastní dokumenty z Velína mimo 5 pevných smluvních typů (id uuid, title, slug UNIQUE, description, kind TEXT 'html'\|'pdf', content_html, pdf_path [veřejná URL v bucketu `media`], show_on_web BOOL, sort_order INT, active BOOL, version INT, updated_by uuid→admin_users, created_at, updated_at, **translations JSONB** = `{ "<lang>": { "title", "description", "content_html" } }` — plní edge fn `translate-document`, mig. `20260512_document_translations.sql`). Web: /jak-pujcit/dokumenty (výpis vedle kanonických karet `mgPublicDocuments()`) + /dokumenty/<slug> (HTML render přes `localized()` nebo redirect na PDF; u přeloženého PDF se na cizojazyčné verzi zobrazí přeložené HTML). Migrace `20260512_custom_documents.sql` |
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
| `maintenance_log` | Log údržby (service_date NOT NULL, km_at_service, completed_date, scheduled_date, service_type, status, description, performed_by, cost, technician_id FK→acc_employees, labor_hours, extra_cost) |
| `maintenance_schedules` | Plány údržby (schedule_type, interval_km, interval_days, first_service_km, first_service_desc) |
| `service_parts` | Díly potřebné pro konkrétní servisní plán (schedule_id FK→maintenance_schedules, inventory_item_id FK→inventory, quantity, notes). UNIQUE(schedule_id, inventory_item_id) |
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
| `acc_employees` | Zaměstnanci (jméno, typ smlouvy, hrubá mzda, sleva na dani, bankovní účet, **phone**, **email**, **position**, **vacation_days_total**, **vacation_days_used**) |
| `acc_payrolls` | Výpočty mezd (hrubá, SP/ZP zaměstnanec i zaměstnavatel, záloha daně, čistá, celk. náklad) |
| `emp_attendance` | Docházka zaměstnanců (employee_id, date, check_in, check_out, break_minutes, hours_worked, status: present/absent/sick/vacation/home_office/half_day, note) UNIQUE(employee_id, date) |
| `emp_vacations` | Dovolená zaměstnanců (employee_id, start_date, end_date, days, type: vacation/sick/personal/unpaid/maternity/other, status: pending/approved/rejected/cancelled, approved_by, note) |
| `emp_shifts` | Plánování směn (employee_id, date, shift_type: morning/afternoon/night/full_day/free, start_time, end_time, branch_id, note) UNIQUE(employee_id, date) |
| `emp_documents` | Dokumenty zaměstnanců (employee_id, type: contract/amendment/termination/agreement/certificate/other, name, description, file_url, valid_from, valid_until) |
| `acc_vat_returns` | Přiznání k DPH (čtvrtletní, zdanitelné vstupy/výstupy, DPH vstup/výstup, k úhradě/vrácení) |
| `acc_tax_returns` | Daňové přiznání (roční, příjmy, výdaje, odpisy, mzdy, základ daně, daň 15%/23%, slevy) |
| `acc_short_term_assets` | Krátkodobý majetek (materiál, drobný majetek, zásoby, pohledávky, peníze) |
| `acc_long_term_assets` | Dlouhodobý majetek (vozidla, stroje, stavby, odpisová skupina 1-6, metoda odpisu, **motorcycle_id** uuid FK→motorcycles, **missing_purchase_doc** boolean) |
| `acc_depreciation_entries` | Odpisy DM (roční odpis, kumulativní, zůstatková hodnota, metoda, skupina) |
| `acc_liabilities` | Závazky (dodavatelé, daně, SP, ZP, mzdy, úvěry, splatnost, stav úhrady, **financial_event_id** uuid FK→financial_events ON DELETE CASCADE) |
| `flexi_reports` | Výkazy stažené z Abra Flexi (DPH přiznání, daňové přiznání, rozvaha, výsledovka, OSSZ, VZP) — status: draft/approved/submitted/rejected, schválení + odeslání datovkou |
| `accounting_exceptions` | **NEW v docs 2026-06-04 (ze snapshotu)** — Účetní výjimky k řešení (financial_event_id, reason, suggested_fix jsonb, assigned_to, resolved_at, resolution_note, created_at) |
| `approval_queue` | **NEW v docs 2026-06-04 (ze snapshotu)** — Fronta finančních schválení (financial_event_id, approval_type, submitted_by, approved_by, approved_at, status, note, created_at) |
| `flexi_sync_log` | **NEW v docs 2026-06-04 (ze snapshotu)** — Log synchronizace s Abra Flexi (financial_event_id, direction, flexi_entity_type, payload jsonb, response_code, response_body jsonb, status, error_message, created_at) — edge fn `flexi-sync` |
| `delivery_notes` | Dodací listy (dl_number, supplier_name/ico, total_amount, delivery_date, items jsonb, AI matching s fakturami: matched_invoice_id, match_method ai/manual, match_confidence, storage_path, extracted_data jsonb, financial_event_id FK→financial_events) |
| `contracts` | Smlouvy obecné + zaměstnanecké (contract_number, contract_type: rental/lease/service/insurance/employment/employment_amendment/employment_termination/dpp/dpc/vacation_request/supply/nda/other, title, counterparty/ico, amount, payment_frequency, valid_from/until, status: pending/active/expired/terminated/draft, employee_id FK→acc_employees, storage_path, extracted_data jsonb, financial_event_id FK→financial_events) |

### Nákupy a sklad

| Tabulka | Popis |
|---------|-------|
| `purchase_orders` | Nákupní objednávky (sent_at — datum odeslání emailu dodavateli) |
| `purchase_order_items` | Položky nákupních objednávek |
| `auto_order_rules` | Pravidla automatických objednávek (trigger_type: stock_low/interval/manual, threshold_quantity, interval_days, order_quantity, email_override, is_active) |
| `suppliers` | Dodavatelé (name, normalized_name, ico, dic, address, bank_account, default_category, default_account, contact_email, notes, created_at, updated_at). Index na normalized_name a ico. Funkce normalize_supplier_name() pro matching bez diakritiky. Auto-upsert z OCR v receive-invoice. |
| `inventory` | Skladové zásoby (category CHECK rozšířen o 'prislusenstvi') |
| `inventory_movements` | Pohyby na skladě |
| `accessory_types` | Dynamické typy příslušenství (key, label, sizes[], is_consumable, **price_czk**, **pricing_unit** (per_booking/per_day/free), sort_order, is_active) — Velín admin spravuje (BranchAccessoryModals → „Spravovat typy"). Web `/rezervace` čte při init přes `MG._loadAccessoryConfig()` — řídí cenu i velikosti gear cards/chips v kroku 5. |

### AI a automatizace

| Tabulka | Popis |
|---------|-------|
| `ai_conversations` | Konverzace s AI Copilotem (admin_id, messages jsonb) |
| `ai_customer_conversations` | **NEW v docs 2026-06-04 (ze snapshotu)** — Konverzace zákazníka s AI (user_id, title, messages jsonb, booking_id, created_at, updated_at) — odlišné od `ai_public_conversations` (anonymní web widget) |
| `ai_actions` | AI akce |
| `ai_logs` | AI logy |
| `automation_rules` | Automatizační pravidla |
| `predictions` | Predikce |
| `api_keys` | REST API klíče pro partnery (key_hash sha256, key_prefix, partner_name/email, rate_limit_rpm, scopes[], is_active, request_count, revoked_at). Plain klíč se vrací jen 1× při vytvoření. |
| `ai_traffic_log` | Log AI provozu — crawler/rest_api/mcp/widget. ts, source, bot_name, user_agent, path, endpoint, ip_hash (sha256+salt pro GDPR), partner_id, status_code, latency_ms, outcome (view/quote/booking_created/error/rate_limited), booking_id, details jsonb. Indexy na ts, source, bot_name, path, partner_id, outcome. |
| `ai_citations` | Manuální tracking "kde nás zmínil AI". observed_at, ai_platform (chatgpt/claude/perplexity/gemini/copilot/grok/duckassist/other), query, response_excerpt, cited_url, screenshot_url, rank, notes, recorded_by. |
| `ai_public_conversations` | **NEW 2026-05-02** — kompletní log konverzací s veřejným AI agentem (motogo24.cz widget). Jeden řádek per `session_id` (UUID stabilní per browser session, upsertuje se z edge fn `ai-public-agent` po každé Anthropic odpovědi). Sloupce: id, session_id (UNIQUE), lang, page_context (jsonb — URL, type, h1, moto_id, selection), messages (jsonb — array `{role, content}` 8 KB cap per message), message_count, ip_hash (sha256 + salt), user_agent (max 500), outcome (view/quote/booking_created/error/rate_limited), booking_id (FK→bookings ON DELETE SET NULL), started_at, last_activity_at. Indexy na started_at DESC a outcome. Velín → Analýza → AI konverzace (čte přes `is_admin()` RLS). Slouží pro pozdější analýzu — co zákazníci řeší, kde se zasekávají, jak končí. |

### Platby

| Tabulka | Popis |
|---------|-------|
| `payment_methods` | Uložené platební karty (Stripe sync) — brand, last4, exp_month/year, holder_name, is_default, stripe_payment_method_id |

### CMS a nastavení

| Tabulka | Popis |
|---------|-------|
| `app_settings` | Nastavení aplikace (key-value, jsonb) |
| `cms_pages` | CMS stránky |
| `cms_variables` | CMS proměnné |
| `faq_items` | FAQ otázky (DB-driven) — kategorie, otázka, HTML odpověď, sort_order, featured_home (zobrazit i na home), published, jsonb translations. Spravuje se ve Velíně CMS → Texty webu → Časté dotazy. |
| `feature_flags` | Feature flags |
| `reviews` | Recenze zákazníků |

### Audit a debug

| Tabulka | Popis |
|---------|-------|
| `admin_audit_log` | Audit log admin akcí — **OPRAVENO 2026-06-04 dle snapshotu:** reálné sloupce `id, admin_id, action, entity_type, entity_id, old_data jsonb, new_data jsonb, ip_address, created_at`. **NEMÁ sloupec `details`** (dřívější docs i kód edge fn `generate-invoice` ho omylem používaly → INSERT tiše selhával; diagnostika přesunuta do `debug_log`). |
| `debug_log` | Debug log (source, action, component, status, request/response_data, error_message, duration_ms, created_at) |
| `app_crash_reports` | **NEW v docs 2026-06-04 (ze snapshotu)** — Pády appky (user_id, app_version, platform, screen, action, error_type, error_message, stack_trace, severity, extra_data jsonb, created_at) |
| `app_debug_logs` | **NEW v docs 2026-06-04 (ze snapshotu)** — Debug logy z appky (user_id, app_version, platform, category, action, detail, data jsonb, duration_ms, created_at) |
| `visitor_log` | **NEW v docs 2026-06-04 (ze snapshotu)** — Návštěvnost webu (id bigint, ts, host, path, referrer, referrer_domain, referrer_type, lang, device, country, ip_hash, visitor_hash, user_agent, utm_source/medium/campaign) |
