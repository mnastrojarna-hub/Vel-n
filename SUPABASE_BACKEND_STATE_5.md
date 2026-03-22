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
- **booking_cancellations:** admin ALL, customer SELECT (cancelled_by=uid)
- **maintenance_log:** admin ALL (is_admin), public SELECT
- **maintenance_schedules:** admin ALL (is_admin), public SELECT
- **service_parts:** admin ALL (is_admin), public SELECT
- **service_orders:** admin ALL (is_admin)

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
| `scan-document` | OCR skenování dokladů (OP, ŘP, pas) přes Mindee API. Přijímá base64 JPEG + document_type (id/dl/passport), vrací strukturovaná data. Retry 3×, loguje do debug_log |
| `webhook-receiver` | Příjem Stripe webhooků v repozitáři. Ověřuje signature, zpracovává checkout.session.completed a payment_intent.succeeded |
| `send-message` | Centrální odesílání zpráv (SMS/WhatsApp přes Twilio, email přes Resend). Přijímá channel, recipient, template_slug, template_vars. Loguje do message_log |
| `send-invoice-email` | Odesílání faktur emailem zákazníkům |
| `send-order-email` | Odesílání objednávkových emailů dodavatelům. Branded HTML šablona s tabulkou položek. Retry 3×. Aktualizuje purchase_orders.status→sent a sent_at. Loguje do debug_log |
| `auto-check-service-parts` | Automatická kontrola dílů pro blížící se servisy. Volá RPC auto_check_service_parts() → vytvoří PO → odešle email dodavateli přes send-order-email. Spouštěno denně cron jobem |

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
| `expire-vouchers` | denně 01:00 UTC | `SELECT expire_vouchers()` |
| `auto-cancel-pending-bookings` | každé 2 min (`*/2 * * * *`) | `SELECT auto_cancel_expired_pending()` — ruší pending+unpaid bookings: app=10min, web=4h |
| `auto-complete-expired-bookings` | denně 00:01 (`1 0 * * *`) | `SELECT auto_complete_expired_bookings()` — active/reserved + end_date < today + paid → completed |
| `auto-activate-reserved-bookings` | denně 00:01 (`1 0 * * *`) | `SELECT auto_activate_reserved_bookings()` — reserved + paid + start_date <= today → active |
| `auto-check-service-parts` | denně 06:00 UTC (`0 6 * * *`) | Edge function `auto-check-service-parts` — kontrola dílů pro blížící se servisy, auto PO + email dodavateli |
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
- `service_parts.schedule_id` → `maintenance_schedules.id` (ON DELETE CASCADE)
- `service_parts.inventory_item_id` → `inventory.id` (ON DELETE CASCADE)
- `service_orders.moto_id` → `motorcycles.id`
- `branch_accessories.branch_id` → `branches.id`
- `branch_door_codes.branch_id` → `branches.id`
- `branch_door_codes.booking_id` → `bookings.id`
- `branch_door_codes.moto_id` → `motorcycles.id`
