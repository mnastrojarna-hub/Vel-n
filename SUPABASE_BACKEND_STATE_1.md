# SUPABASE BACKEND STATE — MotoGo24 (Část 1: Tabulky)
> **Poslední aktualizace:** 2026-06-24 (Živý snapshot přes GitHub Action — přibyly tabulky `financial_events` [finanční/účetní událost: revenue/expense/asset/payroll] + `loyalty_monthly_winners` [měsíční loyalty výherci]; ENUM sekce sladěna s živými `CREATE TYPE` — doplněny `ai_suggestion_status`, `message_channel`, `sos_type`, `tax_type`, opraveny živé hodnoty `admin_role` a `document_type`)
> **Zdroj:** Reálný stav Supabase databáze (SQL dump z dashboardu) + Edge Functions
> **Projekt:** `vnwnqteskbykeucanlhk.supabase.co`
> **POZOR:** Tento soubor MUSÍ být aktualizován při každé SQL změně!
> **Soubory:** 1/6 (Tabulky) | 2/6 (Sloupce) | 3/6 (RPC funkce) | 4/6 (Triggery) | 5/6 (RLS, Realtime, Edge, Storage, Secrets) | 6/6 (Changelog)

---

## 1. ENUM TYPY

| Typ | Hodnoty |
|-----|---------|
| `admin_role` | superadmin, manager, operator, viewer — **OPRAVENO 2026-06-24 dle živého snapshotu:** reálný ENUM má JEN tyto 4 hodnoty. (Dřívější docs uváděly i `technician, readonly, admin` — ty v živém typu nejsou.) |
| `ai_suggestion_status` | pending, approved, edited, rejected, sent, auto_sent, failed — **doplněno 2026-06-24 dle snapshotu** |
| `booking_status` | pending, active, completed, cancelled, reserved |
| `payment_status` | unpaid, paid, refund_pending, refunded, partial_refund — **`refund_pending` NEW 2026-05-31** = „Čeká na vrácení" (storno zaplacené rezervace, Stripe refund ještě nepotvrzen; peníze jsou stále u nás). Životní cyklus: `paid` → (storno) `refund_pending` → (Stripe potvrdil) `partial_refund` (50 %) / `refunded` (100 %). Velín mapuje přes `paymentStatusInfo()` (Zaplaceno/Čeká na vrácení/Částečně vráceno/Vráceno/Nezaplaceno) + filtr `PAYMENT_STATUS_FILTER_OPTIONS`. |
| `message_channel` | sms, whatsapp, email — **doplněno 2026-06-24 dle snapshotu** |
| `moto_status` | active, maintenance, unavailable, retired |
| `sos_status` | reported, acknowledged, in_progress, resolved, closed |
| `sos_type` | accident_minor, accident_major, theft, breakdown_minor, breakdown_major, location_share — **doplněno 2026-06-24 dle snapshotu** |
| `tax_type` | dph_monthly, dph_quarterly, dppo_annual, kontrolni_hlaseni, silnicni_dan — **doplněno 2026-06-24 dle snapshotu** |
| `license_group` | A, A1, A2, AM, B, N |
| `entry_type` | income, expense — **doplněno 2026-06-11**: typ sloupce `accounting_entries.type`. POZOR: migrace `20260321_accounting_entries.sql` mylně tvrdí TEXT s CHECK ('revenue','expense') — reálná DB má tento ENUM |
| `document_type` | contract, protocol, invoice, license_photo, id_photo, vop, invoice_advance, invoice_final — **OPRAVENO 2026-06-24:** ENUM typ v živé DB STÁLE EXISTUJE (toto jsou jeho reálné hodnoty), ALE sloupec `documents.type` ho už nepoužívá — je TEXT (používané hodnoty: contract, vop, invoice_advance, payment_receipt, invoice_final, invoice_shop, protocol, credit_note). Dřívější poznámka „ENUM ZRUŠENO" se týkala jen sloupce, ne typu samotného. |

---

## 2. TABULKY (public schema) — 102 tabulek (živý snapshot 2026-06-24; dočasné `cms_variables_backup_*` už v živém schématu NEJSOU — smazány)

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
| `push_tokens` | Push tokeny zařízení (id uuid PK, user_id, token NOT NULL, platform, active default true, created_at). **FIX 2026-07-03:** doplněn chybějící `UNIQUE (token)` (`push_tokens_token_key`) — bez něj appčí upsert `onConflict:'token'` padal u VŠECH uživatelů (tabulka byla trvale prázdná → žádné FCM pushe). Viz changelog. |
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
| `documents` | Nahrané dokumenty (type TEXT — contract, vop, invoice_advance, payment_receipt, invoice_final, invoice_shop, protocol). Sloupce vč. `name` (TEXT — popisek řádku, např. „Doklad totožnosti — líc (web sken)"), `file_path`, `file_name`, `metadata` (jsonb), `user_id`, `booking_id`, `type`, `created_at`. **FIX 2026-06-10 (`20260610_documents_name_column.sql`):** sloupec `name` v reálné DB chyběl, ačkoli ho `save-verification-document` (i web fallback v `pages-rezervace-scan.js`) vkládá → insert padal na `Could not find the 'name' column`, funkce dělala early-return PŘED zápisem `profiles.*_verified_at` → naskenované doklady zůstávaly „Neověřeno" (fotka i čísla se uložily jinou cestou, jen verified_at ne). Přidáním sloupce se opravily všechny scan cesty (web rezervace krok 2, úprava rezervace, Flutter app). |
| `email_templates` | Šablony emailů (slug: booking_reserved, booking_abandoned, booking_cancelled, booking_completed, voucher_purchased, booking_modified, **handover_protocol_sent, damage_protocol_sent NEW 2026-06-23** — odeslání el. předávacího / škodního protokolu zákazníkovi z Velína, mig. `20260623_protocol_email_templates.sql`; přílohu protokolu řídí `send-email` přes `attachment_paths`, sloupec `attachments` prázdný; **booking_qr_payment NEW 2026-07-05** — platební údaje pro QR / bankovní převod (web krok 2 → edge `qr-payment`), mig. `20260705_qr_payment_email_template.sql`, placeholdery `{{lead}} {{booking_number}} {{qr_url}} {{amount}} {{account}} {{iban}} {{bank}} {{vs}} {{invoice_suffix}}`, obsah 1:1 s dřívějším inline mailem, edge fn má fallback na inline HTML; **UPDATE 2026-07-10 (flow platba PŘED doklady, `20260710_web_pay_before_docs.sql`):** `attachments` u `web_booking_reserved`→`[Smlouva,VOP]` (ZF/DP se přesunuly do `invoice_payment_receipt`→`[ZF,DP]`), base `booking_reserved` NETKNUTA = app; `invoice_payment_receipt` se nově posílá i z rezervačního flow (web: na Stripe platbu / QR potvrzení), sloupec `attachments` čte JEN `send-booking-email`, ruční fakturace `send-invoice-email` ho ignoruje); **NEW 2026-07-17 (`20260717_editable_missing_docs_template.sql`):** připomínka `booking_missing_docs` + web varianta `web_booking_missing_docs` nově jako EDITOVATELNÉ DB šablony (dřív jen hardcoded fallback v `send-booking-email` → nešly editovat ve Velíně); attachments `[]`, tlačítko `{{docs_url}}`, idempotentní; **UPDATE 2026-07-18 (`20260718_web_invoice_receipt_cta_rename.sql`):** v šabloně `web_invoice_payment_receipt` přejmenováno CTA tlačítko **„Nahrát doklady" → „Doplnit údaje"** (v novém flow povinná jen ČÍSLA dokladů, scany nepovinné), targeted `replace` na živém řádku + `body_translations` vynulovány (re-translate), edge fn fallback přejmenován souběžně; **booking_qr_payment_surcharge NEW 2026-07-27 (`20260727_booking_edit_surcharge_flow.sql`)** — sestra `booking_qr_payment` pro DOPLATEK za úpravu ZAPLACENÉ rezervace (Velín úprava s „Zákazník doplatí" → edge `qr-payment` režim surcharge): stejné placeholdery, text bez 4h splatnosti/auto-zrušení a bez ZF (rozdílový DP přijde až v odloženém `booking_modified` mailu po potvrzení doplatku RPC `confirm_booking_surcharge`), attachments `[]`, idempotentní ON CONFLICT DO NOTHING |
| `sent_emails` | Log odeslaných emailů |

### E-shop

| Tabulka | Popis |
|---------|-------|
| `products` | Katalog produktů (name, description, price, images[], sizes[], sku, stock_quantity, category, color, material, is_active, sort_order) |
| `shop_orders` | Objednávky (status: new/confirmed/processing/shipped/delivered/cancelled/returned/refunded, confirmed_at) |
| `shop_order_items` | Položky objednávek |

### Trasy (doporučené vyjížďky) — **NEW 2026-06-21 (`20260621_routes_feature.sql`)**

| Tabulka | Popis |
|---------|-------|
| `routes` | Doporučené motorkářské trasy vedoucí od pobočky. Sloupce: `id`, `branch_id` FK→branches ON DELETE CASCADE, `name`, `description`, `route_type` (CHECK loop/poi — okruh / za body zájmu), `distance_km` numeric(6,1), `duration_min` int, `difficulty` (CHECK easy/medium/hard), `waypoints` jsonb (`[{lat,lng,label,order}]`), `geometry` jsonb (`{coordinates:[[lng,lat],…]}` — cache polyline z Mapy.com routing, plní Velín; appka má fallback živý dopočet), `mapy_url` (originální mapy.com share link), `cover_image`, `images` text[], `image_alts` text[], `translations` jsonb (`{lang:{name,description}}` — plní `autoTranslate`), `is_active` (public read jen aktivní), `sort_order`, `created_at`, `updated_at`. RLS: Public read (`is_active=true` nebo admin) + Admin write. Spravuje Velín → Trasy; appka čte přes RPC `get_branch_routes`. **UPDATE 2026-07-04 (`20260704_routes_fix_waypoints_pois.sql`, APLIKOVÁNO):** `waypoints` všech 384 seedovaných tras přegenerovány, aby vedly přes VŠECHNY body zájmu (start + POI + průjezdní města + cíl), `distance_km`/`duration_min` přepočteny u 155 tras, `mapy_url` přegenerován, `geometry` vynulována (dopočte se živě); + 145 souřadnicových korekcí `route_pois` (viz STATE_6 2026-07-04 (B) a `ANALYZA_TRASY_POI.md`). **UPDATE 2026-07-04 (C) (`20260705_route_pois_fill_gaps.sql`, APLIKUJE AUTO-DEPLOY po merge opravy — viz STATE_6 2026-07-04 (D): fix NOT NULL `images`):** do 116 tras s úsekem ≥ 30 km bez POI doplněno 238 nových `route_pois` PODÉL cesty (212 z katalogu `points_of_interest` ≤ 7 km od čáry, 26 kurátorovaných pro BG/EE/LT/MD/MK — souřadnice ověřeny proti webu); sort_order dotčených tras přečíslován dle pořadí na trase, `waypoints` přegenerovány přes nové body, km/min přepočteny při odchylce > 15 %, `geometry` = null; na konci se přeplánuje cron `backfill-route-translations` (překlady kurátorovaných bodů). Generátor `tools/fill_route_poi_gaps.py`, přehled `tools/route_poi_gap_report.txt`. |
| `route_pois` | Body zájmu na trase (1:N k `routes`). Sloupce: `id`, `route_id` FK→routes ON DELETE CASCADE, `name`, `description`, `lat`/`lng` double precision, `image_url`, `images` text[], `translations` jsonb, `sort_order`, `created_at`, `updated_at`. RLS: Public read (přes nadřazenou aktivní trasu nebo admin) + Admin write. Velín ukládá delete-and-reinsert (drží pořadí). Appka čte body přes RPC `get_branch_routes` (`order by sort_order`) a čísluje markery `i+1` — **`sort_order` MUSÍ odpovídat pořadí po směru trasy**. **UPDATE 2026-07-07 (`20260707_route_pois_reorder_along_route.sql`, NASADÍ AUTO-DEPLOY po merge):** `sort_order` VŠECH `route_pois` přečíslován (0-based) podle projekce bodu na čáru trasy (`waypoints`) → markery 1–x jdou po směru jízdy (dřív u tras nepřečíslovaných `20260705_route_pois_fill_gaps.sql` v pořadí „na přeskáčku" ze seedu). Idempotentní, `waypoints`/`geometry` se nemění. Viz STATE_6 2026-07-07 + `ANALYZA_TRASY_POI.md`. **UPDATE 2026-07-28 (`20260728_routes_systematize_waypoints.sql`, APLIKUJE AUTO-DEPLOY po merge):** systematizace na OKRUHY bez vracení — 1074 tras s volným koncem UZAVŘENO do okruhu (na konec přidán waypoint = kopie startu s labelem „Cíl: …", `route_type='loop'`), body všech tras seřazeny jako nejkratší cyklus/cesta (Held-Karp exakt ≤13 volných bodů, jinak NN+2-opt; start vždy pevný; 51 záměrných přejezdů A→B s labelem „Cíl…" ≠ start zůstává lineárních); celkem změněno 1095 tras, u nich `geometry=null`, `mapy_url` přegenerován, km/min přepočteny při odchylce >15 % (944 tras); poté `sort_order` všech `route_pois` znovu přečíslován projekcí na novou čáru (5719 bodů). Komunitní trasy (`created_by is not null`) nedotčeny. Viz STATE_6 2026-07-28 + `ANALYZA_TRASY_SYSTEMATIZACE.md`. **NEW 2026-06-29:** `routes` má navíc `created_by` (FK auth.users SET NULL) + `status` (approved/pending/rejected, default approved) + `submitted_note` — uživatelské návrhy tras (přes Mapy.com URL z appky) jdou jako `status='pending'`, admin ve Velíně potvrdí. |
| `user_pois` | **NEW 2026-06-29 (`20260629_community_routes_pois.sql`)** — Komunitní (uživatelské) body zájmu, nezávislé na trase. Sloupce: `id`, `user_id` FK→auth.users SET NULL, `name`, `description`, `lat`/`lng` double precision NOT NULL, `image_url` (foto v bucketu `media`), `status` (approved/pending/rejected, default pending), `created_at`, `updated_at`. RLS: Public read jen `approved` (+ vlastník + admin), authenticated insert vlastní pending, admin all. Trigger `set_updated_at`. Appka: návrh přes FAB „+" v Trasách → moderace ve Velíně; schválené čte RPC `get_user_pois` a zobrazí v katalogu bodů zájmu. |
| `route_reviews` | **NEW 2026-07-01 (`20260701_route_reviews.sql`)** — Recenze TRAS: hvězdičky (1–5) + textová recenze + fotky. Sloupce: `id`, `route_id` FK→routes CASCADE, `user_id` FK→auth.users CASCADE, `rating` int 1–5, `review_text`, `photos` text[] (bucket `media` prefix `route-reviews/`), `status` (approved/hidden, default approved), `created_at`, `updated_at`. UNIQUE(`user_id`,`route_id`) = max 1 recenze na uživatele a trasu (lze měnit). RLS: public read jen `approved` (+ vlastník + admin), vlastník RW své recenze, admin all (skrýt/smazat nevhodné). Trigger `set_updated_at`. Zápis přes RPC `submit_route_review` / `delete_route_review`, čtení přes `get_route_reviews`; průměr+počet i v `get_branch_routes` (`review_avg`/`review_count`). Appka: sekce recenzí v detailu trasy; Velín → Trasy sloupec „Recenze" + moderační modal. |
| `poi_ratings` | **NEW 2026-06-29 (`20260629_community_routes_pois.sql`)** — Hvězdičkové hodnocení bodů zájmu (1–5). Sloupce: `id`, `user_id` FK→auth.users CASCADE, `route_poi_id` FK→route_pois CASCADE **NEBO** `user_poi_id` FK→user_pois CASCADE **NEBO** `poi_id` FK→points_of_interest CASCADE (CHECK právě jeden), `rating` int 1–5, `created_at`, `updated_at`. UNIQUE(`user_id`,`route_poi_id`) + UNIQUE(`user_id`,`user_poi_id`) + UNIQUE(`user_id`,`poi_id`) = **max 1 hodnocení na uživatele a bod** (lze měnit). RLS: public read, vlastník write. Zápis přes RPC `rate_poi`, čtení přes `poi_rating_summary` / agregace v `get_branch_routes`, `get_user_pois` a `get_pois_catalog`. **UPDATE 2026-07-04 (`20260704_points_of_interest.sql`, NUTNO APLIKOVAT):** přidán 3. cíl `poi_id` (katalogové body zájmu) — CHECK i UNIQUE rozšířeny. |
| `points_of_interest` | **NEW 2026-07-04 (`20260704_points_of_interest.sql`, NUTNO APLIKOVAT)** — Katalog SAMOSTATNÝCH bodů zájmu nezávislých na trasách (přehrady, velké rybníky a jezera, hrady/zámky, rozhledny/vyhlídky, památky, přírodní rezervace) pro CZ/SK/PL/AT ad. Sloupce: `id`, `category` NOT NULL CHECK ∈ (food/castle/lookout/water/sights/nature/other + **NEW 2026-07-06 cílovka: military/aviation/tech/moto**, mig. `20260706_poi_categories_cilovka.sql`, APLIKOVÁNO 2026-07-04 — vč. reklasifikace bunkrů/leteckých/technických bodů z castle/sights) — **explicitní kategorie = 100% spolehlivý filtr v appce** (hrad se nikdy neplete do „jídla"), `name`, `description` (kanonicky cs), `lat`/`lng` double precision NOT NULL, `country` (ISO), `region`, `image_url`, `images` text[], `image_alts` text[], `translations` jsonb `{lang:{name,description}}` (en/de/pl/nl/es/fr/uk), `source`, `is_active` (default true), `sort_order`, `created_at`, `updated_at`. RLS: public read `is_active` (+admin), admin all. Trigger `set_updated_at`. Appka čte přes RPC `get_pois_catalog` (`catalogPoisProvider`) a zobrazí ve zdroji „Zajímavá místa" v katalogu bodů zájmu. Seed dávka 1 = `20260704_poi_catalog_seed_batch1.sql` (20 flagship bodů, 8 jazyků). |

| `user_saved_routes` | **NEW 2026-07-15 (`20260725_my_experiences.sql`, APLIKUJE AUTO-DEPLOY po merge)** — „Moje trasy": vlastní trasy uložené JEN PRO SEBE (appka → Trasy → Moje zážitky; NENÍ to návrh ostatním — ten dál jde přes `routes.status='pending'`). Sloupce: `id`, `user_id` FK→auth.users CASCADE NOT NULL, `name`, `description`, `source_route_id` FK→routes SET NULL (z jaké doporučené trasy vychází), `waypoints` jsonb (`[{lat,lng,label,order}]`), `poi_refs` jsonb (snapshot bodů `[{order,kind:route/user/catalog,id,name,lat,lng,image_url}]` — `order` váže bod na zastávku), `profile` (CHECK recommended/fastest/shortest), `distance_km` numeric(6,1), `duration_min`, `created_at`, `updated_at`. Trigger `trg_user_saved_routes_updated` (set_updated_at). RLS: owner ALL + admin SELECT. Limit 200 tras/uživatel (v RPC). Zápis/čtení výhradně přes RPC `save_user_route`/`delete_user_route`/`get_my_saved_routes`. |
| `user_visited_places` | **NEW 2026-07-15 (`20260725_my_experiences.sql`)** — „Moje místa": objevená místa — bod zájmu se při dojezdu navigací v appce (≤200 m) automaticky označí jako navštívený. Trojcílový vzor jako `poi_ratings`: `route_poi_id` FK→route_pois CASCADE **NEBO** `user_poi_id` FK→user_pois CASCADE **NEBO** `poi_id` FK→points_of_interest CASCADE (CHECK právě jeden) + UNIQUE(user, cíl) per cíl = jeden řádek na uživatele a bod (opakovaný dojezd jen zvedá `visit_count` + `last_visited_at`). Sloupce: `user_id` FK CASCADE NOT NULL, `name` (snapshot názvu — server-side lookup, klient posílá jen id), `lat`/`lng` (snapshot), `route_id` FK→routes SET NULL (na jaké trase objeveno), `first_visited_at`, `last_visited_at`, `visit_count`. RLS: owner ALL + admin SELECT. Zápis přes RPC `mark_place_visited`, čtení `get_my_places`. |

### Promo a vouchery

| Tabulka | Popis |
|---------|-------|
| `promo_codes` | Slevové kódy (type: percent/fixed; **`source` text NEW 2026-06-20** — slevomat/eshop/spoluprace/vraceni/ostatni pro Velín filtr) |
| `promo_code_usage` | Použití slevových kódů |
| `vouchers` | Dárkové poukazy (status: active/redeemed/expired/cancelled, order_id FK→shop_orders, source — vč. `slevomat`) |
| `booking_discounts` | **NEW 2026-06-25 (`20260625_00_multi_discount_helpers.sql`)** — Víc slev/voucherů na jednu rezervaci (booking_id FK→bookings ON DELETE CASCADE, kind promo_code/voucher, code, promo_code_id, voucher_id, discount_type percent/fixed, value [% nebo nominální Kč], amount [skutečně odečtená Kč], created_at). Pravidlo: max JEDNA procentní sleva. Zdroj pravdy pro rozpad slev na ZF/DP/KF **i pro uplatnění (used_count / voucher redeemed)**. Plní `create_web_booking` (od 2026-06-30 znovu — přepisy 26./29. 6. zápis omylem zahodily, viz STATE_3/STATE_6; derivuje z `p_discount_code`/`p_promo_code`/`p_voucher_id`, ne z `p_discounts`), `realloc_booking_discounts` po úpravě ceny, uplatnění `redeem_booking_discounts_on_paid`. |
| `loyalty_levels` | **NEW 2026-06-11** — Věrnostní ranky pro APP rezervace (20 řádků: level PK 1–20 = % slevy, discount_percent, min_booking_order = od kolikáté app rezervace, name [Startér…Legenda MotoGo], color_hex [barva ringu MG loga v appce], translations jsonb). RLS: Public read + Admin write. Sleva platí JEN pro `booking_source='app'`. Mig. `20260611_loyalty_ranks.sql` |
| `loyalty_monthly_winners` | **NEW 2026-06-24 (ze snapshotu)** — Měsíční loyalty výherci (loyalty „soutěž"). Sloupce: `month` date **PK** (jeden řádek per měsíc), `user_id` uuid, `nickname` text, `days` int (nasbírané dny), `awarded_level_before` int (level před udělením), `awarded_at` timestamptz DEFAULT now(). Plní/čte loyalty RPC (viz STATE_3). |

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
| `accounting_entries` | Účetní záznamy — reálné sloupce viz STATE_2 (type = ENUM `entry_type`, **category NOT NULL**) |
| `financial_events` | **NEW 2026-06-24 (ze snapshotu)** — Centrální finanční/účetní událost (jednotný vstup pro účetní pipeline). Sloupce: `id`, `event_type` (CHECK revenue/expense/asset/payroll), `source` (CHECK stripe/ocr/system/manual), `amount_czk` numeric(12,2), `vat_rate` numeric(5,2) DEFAULT 0, `duzp` date NOT NULL, `linked_entity_type` text, `linked_entity_id` uuid, `confidence_score` numeric(3,2) DEFAULT 1.0 (CHECK 0–1), `status` (pending/enriched/validated/exported/approved/submitted/error) DEFAULT pending, `flexi_id` text, `metadata` jsonb DEFAULT `{}`, `document_type` text, `created_at`, `updated_at`. Trigger `trg_fe_updated` (update_updated_at). Indexy na duzp, linked_entity_id, status. Navazují FK z `acc_liabilities`, `delivery_notes`, `contracts`, `accounting_exceptions`, `approval_queue`, `flexi_sync_log`. |
| `document_number_counters` | **NEW 2026-06-23 (`20260623_atomic_document_numbering.sql`)** — Atomický čítač číselných řad dokladů. Sloupce: `prefix` text, `year` int, `last_seq` int DEFAULT 0, PK(`prefix`,`year`). Plní fce `next_document_number(prefix)` (viz STATE_3) — řeší duplicity (bug report: dvojité `DB-2026-0001`), které vznikaly neatomickým `MAX(seq)+1`. Pojistka: UNIQUE index `invoices_number_unique` na `invoices.number`. |
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
| `gear_shortages` | **NEW 2026-06-23 (`20260623_gear_logistics.sql`)** — Fronta deficitů výbavy (Logistika zboží). Per `(branch_id, accessory_type, size, shortage_date)` UNIQUE. Sloupce: `branch_id` FK→branches CASCADE, `accessory_type` (boots/helmet/gloves/pants/jacket…), `size`, `audience` (adult/child), `shortage_date`, `needed_qty`, `stock_qty`, `deficit_qty`, `status` (open/warehouse_filled/transfer_requested/order_created/resolved/dismissed), `resolution`, `purchase_order_id` FK→purchase_orders SET NULL, `transfer_from_branch_id` FK→branches SET NULL, `booking_ids` uuid[] (rezervace, co deficit způsobily), `assigned_to`, `created_at/updated_at/resolved_at`. Plní trigger `gear_shortage_on_booking` (AFTER na bookings, exception-safe = rezervaci nikdy neshodí) + fce `detect_gear_shortages*`. Hlídá JEN typy přítomné v `branch_accessories` (bunda `jacket` až po zavedení). Pickup-at-branch (delivery pool mimo). RLS: Admin full. Realtime: ANO (badge Velín → Logistika zboží). Index `idx_gear_shortages_open`. |
| `stock_receipts` | **NEW 2026-06-25 (`20260625_stock_receipts_pairing.sql`)** — Ledger naskladnění pro párování DL⇄faktura, kontrolu duplicity a ochranu proti duplicitnímu naskladnění (Logistika → Naskladnění, Fáze 6). Sloupce: `doc_type` (`invoice`/`delivery_note`, CHECK), `doc_number`, **`doc_date`** (datum dokladu — klíč duplicity „č. dokladu + datum"), `variable_symbol`, `supplier_ico`, `supplier_name`, `amount_czk`, `financial_event_id`, `stocked` (zboží skutečně naskladněno z tohoto dokladu), `matched_receipt_id` FK→self (spárovaný protějšek), `needs_dl` (faktura bez DL = „chybí DL"), `note`, `created_at`. Plní RPC `record_stock_receipt`; čte `check_document_status` (STATE_3). DL = jen sklad; faktura = finance i sklad; proforma se neeviduje (nenaskladňuje se). Indexy `idx_stock_receipts_supplier`, partial `idx_stock_receipts_needs_dl`, `idx_stock_receipts_docnum (lower(doc_number), doc_date)`. RLS: authenticated full. |
| `accessory_types` | Dynamické typy příslušenství (key, label, sizes[], is_consumable, **price_czk**, **pricing_unit** (per_booking/per_day/free), sort_order, is_active) — Velín admin spravuje (BranchAccessoryModals → „Spravovat typy"). Web `/rezervace` čte při init přes `MG._loadAccessoryConfig()` — řídí cenu i velikosti gear cards/chips v kroku 5. |

### AI a automatizace

| Tabulka | Popis |
|---------|-------|
| `ai_conversations` | Konverzace s AI Copilotem (admin_id, messages jsonb) |
| `ai_customer_conversations` | **NEW v docs 2026-06-04 (ze snapshotu)** — Konverzace zákazníka s AI (user_id, title, messages jsonb, booking_id, created_at, updated_at) — odlišné od `ai_public_conversations` (anonymní web widget). **UPDATE 2026-07-04:** nově plní edge fn `ai-moto-agent` po každé odpovědi (dosud do tabulky nikdo nezapisoval — konverzace z appky se neukládaly); Velín → Analýza → AI konverzace → zdroj „AI agent (appka)" (čte přes `is_admin()` RLS) |
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
### Samoobslužná pobočka (kiosk / AlzaBox na motorky) — **NEW 2026-06-29 (`20260628_selfservice_kiosk.sql` + `20260629_kiosk_cameras_power.sql`, APLIKOVÁNO + OVĚŘENO uživatelem)**

| Tabulka | Popis |
|---------|-------|
| `branch_kiosk_config` | 1:1 konfigurace kiosku per pobočka (PK `branch_id`). Hudba (`music_on_url`/`music_off_url`), časování (`door_open_seconds`/`light_seconds`/`music_seconds`), stav FV (`power_status_url`/`power_poll_seconds`), `relay_base_url`, `is_active`. Token NENÍ zde (je per zařízení). |
| `kiosk_devices` | Zařízení (tablety) — **unikátní identita per app**. `id` uuid PK = identifikátor zařízení, `branch_id` FK→branches CASCADE, `name`, `device_token` uuid (tajný párovací token), `platform`, `app_version`, `last_seen_at` (heartbeat → online stav), `is_active` (revokace párování). |
| `branch_doors` | Mapování logických dveří → Shelly relé/světlo (LAN). `door_kind` (motorcycle/accessories), `box_number` (= `motorcycles.box_number`; NULL u oblečení), `label`, `relay_url`, `light_url`, `is_active`, `sort_order`. UNIQUE per (branch, box) u motorcycle, max 1 accessories per pobočka. |
| `branch_service_codes` | Servisní hesla (otevírají VŠE; app se zeptá které dveře). `branch_id`, `code`, `label`, `is_active`, `created_by`. UNIQUE(branch_id, code) WHERE is_active. |
| `kiosk_commands` | Fronta vzdálených příkazů Velín→kiosk. `device_id` FK→kiosk_devices CASCADE, `command` (open_door/music_on/music_off/identify/reload/camera_control/http_get), `params` jsonb, `status` (pending/done/failed/expired), `result` jsonb, `created_by`, `executed_at`. Realtime přes **DB Broadcast** (trigger → `realtime.send` na topic `kiosk:<device_id>`), NE přes publication (kiosk je anon). |
| `branch_door_events` | Audit otevření. `branch_id`, `device_id`, `door_id`, `kind` (motorcycle/accessories/service), `booking_id`, `code_masked`, `success`, `detail` jsonb. |
| `branch_cameras` | Kamery pobočky. `kind` (snapshot/mjpeg/hls/iframe), `stream_url`, `snapshot_url`, `control_url` (PTZ/relé — volá se přes tablet/LAN), `sort_order`, `is_active`. Náhled ve Velíně, ovládání přes online tablet. |
| `branch_power_status` | Poslední stav ostrovní FV elektrárny (PK `branch_id`). `battery_soc`, `battery_voltage`, `battery_power_w`, `pv_power_w`, `load_power_w`, `grid_present`, `generator_on`, `raw` jsonb, `updated_at`. Plní RPC `kiosk_report_power` (tablet stahuje z měniče na LAN). |

| `app_installations` | **NEW 2026-06-28 (`20260628_app_installations.sql`)** — Přesná evidence instalací mobilní appky (zdroj pravdy pro počítání instalací / aktivních zařízení / uživatelů, NEZÁVISLE na souhlasu s push). Appka (`InstallationService`, oba Flutter balíky) generuje stabilní **náhodné UUID per instalaci** (NE hardwarový identifikátor — Google Play safe) a throttlovaně (12 h) upsertuje „heartbeat". **FIX 2026-06-30:** id se ukládá do durable `SharedPreferences` (přežije aktualizaci buildu, maže se až při odinstalaci) s migrací ze staré `flutter_secure_storage` — dřív bylo id JEN v secure storage, kterou Android Keystore po updatu buildu občas nepřečetl → appka vygenerovala nové UUID → falešné „nové aktivní zařízení" ve Velíně. Sloupce: `device_id` (text **PK** = UUID), `user_id` (uuid FK→auth.users ON DELETE CASCADE), `platform` (android/ios), `app_version`, `push_enabled` (bool), `first_seen_at`, `last_seen_at`, `created_at`, `updated_at`. Trigger `trg_app_installations_touch` (updated_at). Indexy na user_id, last_seen_at DESC, lower(platform). RLS: owner RW (`user_id = auth.uid()`) + admin SELECT (`is_admin()`). Čte RPC `get_app_install_stats()` → Velín → Analýza → Aplikace (DAU/WAU/MAU, instalace, push povoleno). |
