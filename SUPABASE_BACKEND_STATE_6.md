# SUPABASE BACKEND STATE — MotoGo24 (Část 6: Changelog)
> **Soubory:** 1/6 (Tabulky) | 2/6 (Sloupce) | 3/6 (RPC funkce) | 4/6 (Triggery) | 5/6 (RLS, Realtime, Edge, Storage, Secrets) | **6/6 (Changelog)**

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
| 2026-03-09 | **FIX documents.type:** Sloupec `documents.type` změněn z `document_type` ENUM na TEXT. ENUM `document_type` zrušen. Trigger `sync_invoice_to_documents()` přepsán s TEXT mapováním |
| 2026-03-09 | **FIX generate_shop_invoice:** Opraven typ faktury z `'shop'` na `'shop_final'`. Přidán `source='shop'` a SECURITY DEFINER |
| 2026-03-09 | **NEW:** Přidán sloupec `bookings.modification_history` (jsonb, default '[]') |
| 2026-03-10 | **FIX SOS triggers:** Dropnut trigger `sos_auto_reply_on_create`. `trigger_sos_auto_reply()` přepsán na safe no-op |
| 2026-03-11 | **KOMPLETNÍ OPRAVA SOS v2:** DROP ALL triggers na sos_incidents + recreate. Klíčová oprava: `check_one_active_sos()` doplněn `WHEN OTHERS THEN RETURN NEW` |
| 2026-03-11 | **FIX license_group enum:** Přidána hodnota `N` (nevyžaduje ŘP) |
| 2026-03-11 | **NEW: Smluvní texty v document_templates:** Seed 3 šablon — VOP, Nájemní smlouva, Předávací protokol |
| 2026-03-11 | **FIX check_one_active_sos:** Změna logiky z per-user na per-booking |
| 2026-03-12 | **FIX confirm_payment:** Podmíněný přechod stavu dle start_date |
| 2026-03-12 | **NEW: Auto-cancel pending bookings:** `auto_cancel_expired_pending()` — app po 10 min, web po 4h |
| 2026-03-12 | **NEW: Header banner:** Nový klíč `header_banner` v `app_settings` |
| 2026-03-12 | **FIX confirm_payment v3 (robust):** Exception handling, fallback tiers |
| 2026-03-12 | **FIX header banner:** `.single()` → `.maybeSingle()` |
| 2026-03-12 | **FIX payment triggers (root cause):** `auto_accounting_on_booking_paid()` přepsán s EXCEPTION handling |
| 2026-03-13 | **NEW: Per-user overlap check:** `check_user_booking_overlap()` trigger |
| 2026-03-13 | **NEW: Auto-complete expired bookings:** `auto_complete_expired_bookings()` |
| 2026-03-13 | **FIX: Document templates .single()→array** |
| 2026-03-13 | **FIX: SOS flow + auto-activate reserved** |
| 2026-03-13 | **NEW: Auto voucher processing:** BEFORE UPDATE trigger `auto_process_voucher_order()` |
| 2026-03-14 | **FIX: Door codes in DP + email** |
| 2026-03-14 | **NEW: Autonomní pobočky:** branch_code, is_open, branch_accessories, branch_door_codes |
| 2026-03-14 | **FIX: Voucher trigger silent fail:** přidán `'voucher'` do CHECK constraint |
| 2026-03-15 | **REFACTOR: KF faktura triggerem:** `generate_final_invoice_on_complete()` |
| 2026-03-15 | **FIX: Robust SOS swap + KF + ZF/DP** |
| 2026-03-17 | **FIX: Mindee OCR document recognition:** Nová Edge Function `scan-document` |
| 2026-03-17 | **FIX: Nepřečtené zprávy:** Nové RPC `mark_thread_messages_read`, `get_unread_thread_message_count` |
| 2026-03-17 | **NEW: Produkty v e-shopu:** Tabulka `products`, Velín CRUD, dynamické načítání z DB |
| 2026-03-17 | **FIX: Přístupové kódy — automatický lifecycle:** `auto_generate_door_codes()`, `auto_deactivate_door_codes()` |
| 2026-03-18 | **SECURITY: Odstranění Service Role Key z frontendu** |
| 2026-03-18 | **NEW: Stripe integrace + Email retry:** `process-payment`, `webhook-receiver` |
| 2026-03-18 | **NEW: AI Copilot + AI Agent + SOS foto + Google recenze** |
| 2026-03-20 | **NEW: Kompletní účetnictví ve Velínu:** 8 nových DB tabulek (acc_employees, acc_payrolls, acc_vat_returns, acc_tax_returns, acc_short_term_assets, acc_long_term_assets, acc_depreciation_entries, acc_liabilities) |
| 2026-03-21 | **NEW: Claude Vision OCR + Flexi pull + Datová schránka:** `receive-invoice` přepsána (Claude Vision), `flexi-sync` rozšířena o PULL, nová tabulka `flexi_reports`, Edge Function `datova-schranka` |
| 2026-03-21 | **NEW: Automatické objednávky ve Financích:** 1) Nová tabulka `auto_order_rules` (trigger_type: stock_low/interval/manual, threshold_quantity, interval_days, order_quantity, email_override, is_active). 2) Nový sloupec `purchase_orders.sent_at`. 3) Nová Edge Function `send-order-email` — branded HTML email s tabulkou položek, retry 3×, aktualizuje PO status→sent. 4) Velín: nový tab „Objednávky" ve Finance s pod-záložkami Objednávky (CRUD + odeslání emailu) a Automatická pravidla (stock_low/interval/manual triggery, CRUD, ruční spuštění). Jednorázová objednávka: zadá se jen email + položky → vše se zařídí automaticky |
| 2026-03-21 | **NEW: Propojení poboček se skladem + dynamické typy příslušenství:** 1) Nová tabulka `accessory_types` (key, label, sizes[], is_consumable, sort_order, is_active) — nahrazuje hardcoded ACCESSORY_TYPES. 2) Rozšířen CHECK na `inventory.category` o 'prislusenstvi'. 3) Odstraněn CHECK na `branch_accessories.type`. 4) Velín: „Naplnit vše" zobrazuje dialog s přehledem skladu (co se doplní / co chybí). Přidání/úprava příslušenství kontroluje a strhává ze skladu. Spotřební zboží (kukly, ubrousky) se při snížení nevrací na sklad. „Správa typů" — přidání nových typů přímo v UI, auto-vytvoření skladových položek. |
