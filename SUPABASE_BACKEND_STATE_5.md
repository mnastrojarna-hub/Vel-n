# SUPABASE BACKEND STATE — MotoGo24 (Část 5: RLS, Realtime, Edge, Storage, Secrets, Cron, FK)
> **Soubory:** 1/6 (Tabulky) | 2/6 (Sloupce) | 3/6 (RPC funkce) | 4/6 (Triggery) | **5/6 (RLS, Realtime, Edge, Storage, Secrets)** | 6/6 (Changelog)

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
- **payment_methods:** admin ALL, customer SELECT/INSERT/UPDATE/DELETE (user_id=uid)
- **booking_cancellations:** admin ALL, customer SELECT (cancelled_by=uid)
- **maintenance_log:** admin ALL (is_admin), public SELECT
- **maintenance_schedules:** admin ALL (is_admin), public SELECT
- **service_parts:** admin ALL (is_admin), public SELECT
- **service_orders:** admin ALL (is_admin)
- **emp_attendance:** admin ALL (is_admin)
- **emp_vacations:** admin ALL (is_admin)
- **emp_shifts:** admin ALL (is_admin)
- **emp_documents:** admin ALL (is_admin)
- **delivery_notes:** admin ALL (is_admin)
- **contracts:** admin ALL (is_admin)
- **api_keys:** admin ALL (is_admin)
- **ai_traffic_log:** admin SELECT (is_admin), service_role INSERT (WITH CHECK true) — anon + edge fns mohou logovat
- **ai_citations:** admin ALL (is_admin)

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

## 8. EDGE FUNKCE (31 aktivních po cleanup)

### V repozitáři (27 — všechny deployované)

| Funkce | JWT | Popis |
|--------|-----|-------|
| `admin-auth` | OFF | Autentizace a auto-provisioning admin uživatelů (ověření JWT + insert do admin_users přes service role) |
| `admin-reset-password` | OFF | Admin reset hesla zákazníka |
| `ai-copilot` | OFF | AI Copilot pro Velín dashboard — Anthropic Claude API, system prompt CZ, načítá kontext z DB (bookings, tržby, servis, SOS), ukládá do ai_conversations |
| `ai-moto-agent` | OFF | AI Servisní agent pro zákazníky — diagnostika závad motorek přes Claude API, vrací {reply, is_rideable, suggest_sos}, načítá kontext motorky z booking_id |
| `auto-check-service-parts` | OFF | Automatická kontrola dílů pro blížící se servisy. Volá RPC auto_check_service_parts() → vytvoří PO → odešle email dodavateli přes send-order-email. Spouštěno denně cron jobem |
| `datova-schranka` | OFF | Podání schválených finančních reportů přes ISDS (datová schránka) |
| `flexi-sync` | OFF | Synchronizace s Abra Flexi účetním softwarem |
| `generate-document` | OFF | Generuje dokumenty z šablon (rental_contract, handover_protocol, vop). Firemní údaje načítá z app_settings (company_info) |
| `generate-invoice` | OFF | Generuje proforma/finální fakturu (ZF-/FV-/DP-YYYY-NNNN). Firemní údaje načítá z app_settings (company_info). Deduplikace, odečet záloh |
| `manage-payment-methods` | OFF | Správa uložených platebních metod (Stripe). Akce: list, delete, set_default, setup. Synchronizuje karty do tabulky payment_methods |
| `process-payment` | OFF | Stripe platební brána (**LIVE mode**). Podporuje booking, shop, extension i SOS platby. Vytváří Stripe Checkout Session. Automaticky vytváří/používá Stripe Customer. **Web shop:** ukládá kompletní data (telefon, adresa, oddělené položky), generuje ZF (proforma) + odesílá email se shrnutím. **Bundled booking + shop (od 2026-04-28):** `handleWebBookingCheckout` přijímá volitelný `shop_order_id` — načte `shop_order_items` a přidá je jako další Stripe `line_items` do stejné Checkout Session (jedna platba zákazníka, dva oddělené účetní doklady). `metadata.shop_order_id` umožní webhooku zavolat `confirmShopPayment` vedle `confirmBookingPayment` → vygenerují se **dvě nezávislé faktury** (booking ZF/FV + shop ZF/DP) a odešlou se **dva emaily**. |
| `process-refund` | OFF | Stripe refundy (LIVE). Částečné i plné vrácení peněz. Volá Stripe Refund API |
| `receive-invoice` | OFF | OCR + AI zpracování přijatých faktur (Claude Vision). Extrakce dat, klasifikace, routing do účetních tabulek |
| `scan-document` | OFF | OCR skenování dokladů (OP, ŘP, pas) přes Mindee v2 API (enqueue+poll). Model ID z MINDEE_MODEL_ID secret. Retry 3×, loguje do debug_log |
| `send-booking-email` | OFF | Odesílá branded HTML emaily (booking_reserved, booking_completed, booking_modified, voucher_purchased, **door_codes**, sos_incident, booking_abandoned, booking_cancelled). Retry 3×. Automaticky načítá aktivní uvolněné přístupové kódy z `branch_door_codes` a vystavuje je jako `{{door_code_moto}}`, `{{door_code_gear}}`, `{{door_codes_block}}` template vars. |
| `send-broadcast` | OFF | Hromadné zasílání kampaní (email, SMS, WhatsApp). Rate-limited, failure threshold 20% |
| `send-cancellation-email` | OFF | Email o stornování rezervace s "obnovit" CTA. Retry 3× |
| `send-email` | OFF | Obecné odesílání emailů s podporou šablon |
| `send-invoice-email` | OFF | Odesílání faktur emailem zákazníkům |
| `send-message` | OFF | Centrální odesílání zpráv (SMS/WhatsApp přes Twilio, email přes Resend) |
| `send-order-email` | OFF | Odesílání objednávkových emailů dodavatelům. Retry 3× |
| `translate-content` | ON | Auto-překlad textů z Velínu pro veřejný web. Volá Anthropic API (`claude-haiku-4-5-20251001`), překládá zadaná pole do 6 jazyků (en, de, es, fr, nl, pl) a UPDATEuje sloupec `translations` v cílové tabulce přes service_role. Striktně zachovává HTML tagy, ICO, čísla, SPZ, ceny. Vstup: `{table, id, fields, target_langs?}`. |
| `send-push` | OFF | FCM v1 push notifikace na zákaznická zařízení. Volá se ze SQL přes `send_push_via_edge()` (pouze service_role). Načítá `push_tokens.active=true`, podepisuje JWT pro Google OAuth2, posílá FCM message s Android channel `motogo_door_codes` + APNS payload. Auto-deaktivuje invalid tokeny (NOT_FOUND/UNREGISTERED). |
| `webhook-receiver` | OFF | Příjem Stripe webhooků (**LIVE mode**, signature povinná). Auto-generuje dokumenty po platbě. Synchronizuje karty do payment_methods. **Shop platby:** auto-generuje DP + odesílá voucher_purchased email s kódy poukazů. **Bundled booking + shop (od 2026-04-28):** když `event.metadata.type='booking'` a obsahuje `metadata.shop_order_id`, zavolá vedle `confirmBookingPayment` ještě `confirmShopPayment` → trigger `generate_shop_invoice` vystaví shop_final fakturu, odešle voucher/order email. Výsledek: jedna Stripe session, dvě faktury, dva emaily. |
| `public-api` | OFF | **Veřejné REST API** pro AI agenty / partnery / integrátory. Tenká vrstva nad RPC. 9 endpointů (motorcycles list+detail+availability, branches, extras, quote, bookings, promo/voucher validate) + GET /api/v1/openapi.json (OpenAPI 3.1 spec). Hybrid auth: bez klíče = rate-limit per IP (60/min read, 30/h create_booking), s X-Api-Key header = per-partner rate_limit_rpm z `api_keys`. Loguje do `ai_traffic_log` (source='rest_api'). |
| `mcp-server` | OFF | **Model Context Protocol server** (HTTP + JSON-RPC 2.0) pro Claude Desktop, Cursor, Cline, Smithery, custom agenty. 9 tools (motogo_search_motorcycles, motogo_get_motorcycle, motogo_get_availability, motogo_quote, motogo_create_booking, motogo_get_branches, motogo_get_faq, motogo_validate_promo, motogo_validate_voucher) + 5 resources (about, motorcycles, branches, faq, policies). Methods: initialize, tools/list, tools/call, resources/list, resources/read, ping. GET / vrací discovery JSON. Optional X-Api-Key auth. Loguje do `ai_traffic_log` (source='mcp'). |
| `ai-public-agent` | OFF | **AI booking widget backend** (anonymní, bez JWT). Anthropic Claude Haiku 4.5 + **9 tools**: `search_motorcycles`, `get_availability`, `calculate_price`, `get_faq`, `get_extras_catalog`, `get_branches`, `validate_promo_or_voucher`, **`create_booking_request`**, `redirect_to_booking`. Anti-halucinace: model nikdy nevymýšlí ceny ani datum — system prompt obsahuje hlavičku "DNES JE …" v Europe/Prague. **Jazykově adaptivní**: model detekuje jazyk poslední user zprávy a odpovídá vždy ve stejném (přepínání mid-konverzace OK). UI lang z prohlížeče je jen hint pro 1. zprávu. **Konfigurovatelný z Velínu** přes `app_settings.ai_public_agent_config` (persona_name, system_prompt, situations, mustDo, forbidden, tone, max_tokens, enabled, welcome_cs/en/de). `create_booking_request` přijímá kompletní data: moto_id, datumy, kontakt (jméno/email/telefon/adresa), ŘP skupina, promo kód, pickup/return time, delivery_address/return_address pro přistavení mimo Mezná, extras (jako pole {name, unit_price}), všechny gear sizes řidič+spolujezdec. Po vytvoření booking přes RPC `create_web_booking` edge funkce **interně volá `process-payment` (source=web, booking_id)** a vrací reálný **Stripe Checkout URL** v `payment_url` (fallback na `/rezervace/dokoncit?id=X` pokud Stripe selže). Rate-limit 20 req/min/IP. Loguje do `ai_traffic_log` (source='widget', outcome=`view`/`quote`/`booking_created`). |

### Pouze v Supabase dashboardu (4 — bez kódu v repo)

| Funkce | Popis |
|--------|-------|
| `cron-daily` | Denní cron úlohy (snapshot_daily_stats, auto_schedule_services) |
| `cron-monthly` | Měsíční cron úlohy (generate-tax, monthly reports) |
| `export-data` | Export dat (CSV/XLSX) — voláno z Velín Finance + TaxTab |
| `generate-report` | Generování reportů — voláno z Velín Statistics |
| `generate-tax` | Generování daňových záznamů — voláno z Velín TaxTab |

### SMAZANÉ duplicity/nepoužívané (cleanup 2026-03-24)

| Funkce | Důvod smazání |
|--------|---------------|
| `document-generator` | Duplikát generate-document |
| `generate_document` | Duplikát generate-document (starší verze) |
| `generate-html-document` | Duplikát generate-document (nejstarší, fiktivní IČO) |
| `redeploy` | Duplikát generate-invoice |
| `redeploy-invoice` | Duplikát generate-invoice (starší) |
| `bright-endpoint` | Nepoužívané — Bright Data endpoint |
| `cms-sync` | Nepoužívané — žádné CMS v projektu |
| `prediction-engine` | Nepoužívané — nerealizovaná funkce |
| `send-sos` | Nepoužívané — nahrazeno DB triggerem sos_notify_user_on_create() + send-message |
| `upload-handler` | Nepoužívané — upload jde přímo přes Supabase Storage SDK |
| `inventory-check` | Nepoužívané — nahrazeno auto-check-service-parts |

---

## 9. STORAGE BUCKETY

| Bucket | Přístup | Použití |
|--------|---------|---------|
| `documents` | **private** | Faktury (invoices/{id}.html), generované dokumenty (generated/{uuid}.html), smlouvy |
| `media` | **public** | Fotky motorek, loga, marketingové materiály |
| `sos-photos` | **private** | Fotky z SOS incidentů (poškození, nehody) |

---

## 10. SECRETS (16+)

| Secret | Kde se používá |
|--------|---------------|
| `SUPABASE_URL` | Všechny edge funkce |
| `SUPABASE_SERVICE_ROLE_KEY` | Všechny edge funkce |
| `SUPABASE_ANON_KEY` | admin-reset-password, ai-copilot, ai-moto-agent, webhook-receiver (doc gen) |
| `SUPABASE_DB_URL` | Přímý DB přístup z edge funkcí |
| `ANTHROPIC_API_KEY` | ai-copilot, ai-moto-agent (Anthropic Claude API) |
| `MINDEE_API_KEY` | scan-document (OCR) — Mindee v2 API key |
| `MINDEE_MODEL_ID` | scan-document — Mindee v2 model ID pro National ID / OP (`2e169fdb...`) |
| `MINDEE_MODEL_DRIVERS_LICENSE` | scan-document — Mindee v2 model ID pro Driver's Licence / ŘP (`c9797f99...`) |
| `MINDEE_MODEL_PASSPORT` | scan-document — Mindee v2 model ID pro Passport / pas |
| `STRIPE_SECRET_KEY` | process-payment, webhook-receiver, manage-payment-methods (**LIVE sk_live_...**) |
| `STRIPE_WEBHOOK_SECRET` | webhook-receiver (**POVINNÉ** — ověření Stripe signature, whsec_...) |
| `ADMIN_EMAIL` | SOS notifikace, cron alerty |
| `ADMIN_PHONE` | SOS SMS notifikace |
| `TWILIO_ACCOUNT_SID` | send-message (Twilio SMS/WhatsApp) |
| `TWILIO_API_KEY_SID` | send-message (Twilio API Key) |
| `TWILIO_API_KEY_SECRET` | send-message (Twilio API Key Secret) |
| `TWILIO_PHONE_NUMBER` | send-message (Twilio odesílací číslo) |
| `TWILIO_WHATSAPP_NUMBER` | send-message (Twilio WhatsApp číslo) |
| `INVOICE_API_KEY` | fakturace |
| `FCM_PROJECT_ID` | send-push (Firebase project ID) |
| `FCM_SERVICE_ACCOUNT_JSON` | send-push (Firebase service account JSON, base64 encoded) |

**App settings (DB) pro pg_net push:**
| Klíč | Účel |
|------|------|
| `app.settings.supabase_url` | URL pro `send_push_via_edge()` SQL helper |
| `app.settings.service_role_key` | Service role key pro autorizaci `send-push` z DB triggerů |

**Frontend config (ne secret):**
| Klíč | Hodnota |
|------|---------|
| `STRIPE_PUBLISHABLE_KEY` | `pk_live_51TBLTTRzZyj...` (v index.html MOTOGO_CONFIG) |

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
```json
{
  "enabled": true,
  "text": "Letní akce -20% na všechny motorky!",
  "bg": "#1a2e22",
  "color": "#74FB71"
}
```

### google_review_url (app_settings key)
```
https://search.google.com/local/writereview?placeid=PLACE_ID
```

---

## 12. SEKVENCE

- `shop_order_seq` — formát: OBJ-YYYY-NNNNN (start 1001)

---

## 13. CRON JOBS (pg_cron)

| Job | Čas | Funkce |
|-----|-----|--------|
| `auto-cancel-pending-bookings` (1) | každé 2 min (`*/2 * * * *`) | `SELECT auto_cancel_expired_pending()` — ruší pending+unpaid bookings: app=10min, web=4h |
| `auto-complete-expired-bookings` (4) | denně 00:01 (`1 0 * * *`) | `SELECT auto_complete_expired_bookings()` — active/reserved + end_date < today + paid → completed |
| `expire-vouchers` (8) | denně 01:00 UTC (`0 1 * * *`) | `SELECT expire_vouchers()` |
| `cron-daily` (9) | denně 02:00 UTC (`0 2 * * *`) | `SELECT snapshot_daily_stats(); SELECT auto_schedule_services();` |
| `auto-check-service-parts` (10) | denně 06:00 UTC (`0 6 * * *`) | `SELECT auto_check_service_parts()` — kontrola dílů, auto PO + email dodavateli |
| `auto-activate-reserved` (11) | denně 00:01 (`1 0 * * *`) | `SELECT auto_activate_reserved_bookings()` — reserved + paid + start_date <= today → active |

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
- `service_parts.schedule_id` → `maintenance_schedules.id` (ON DELETE CASCADE)
- `service_parts.inventory_item_id` → `inventory.id` (ON DELETE CASCADE)
- `service_orders.moto_id` → `motorcycles.id`
- `branch_accessories.branch_id` → `branches.id`
- `payment_methods.user_id` → `profiles.id` (ON DELETE CASCADE)
- `branch_door_codes.branch_id` → `branches.id`
- `branch_door_codes.booking_id` → `bookings.id`
- `branch_door_codes.moto_id` → `motorcycles.id`
- `invoices.matched_delivery_note_id` → `delivery_notes.id` (ON DELETE SET NULL)
- `invoices.original_invoice_id` → `invoices.id` (ON DELETE SET NULL)
- `delivery_notes.matched_invoice_id` → `invoices.id` (ON DELETE SET NULL)
- `delivery_notes.financial_event_id` → `financial_events.id` (ON DELETE SET NULL)
- `contracts.financial_event_id` → `financial_events.id` (ON DELETE SET NULL)
- `contracts.employee_id` → `acc_employees.id` (ON DELETE SET NULL)
