# SUPABASE BACKEND STATE — MotoGo24 (Část 3: RPC funkce)
> **Soubory:** 1/6 (Tabulky) | 2/6 (Sloupce) | **3/6 (RPC funkce)** | 4/6 (Triggery) | 5/6 (RLS, Realtime, Edge, Storage, Secrets) | 6/6 (Changelog)

---

## 4. RPC FUNKCE (callable z frontendu)

### Existující v migracích
| Funkce | Popis |
|--------|-------|
| `is_admin()` | Vrací boolean — je aktuální user admin? |
| `is_superadmin()` | Vrací boolean — je aktuální user superadmin? |
| `validate_promo_code(code)` | Validuje promo kód, vrací jsonb |
| `use_promo_code(code, booking_id, base_amount)` | Použije promo kód atomicky |
| `create_shop_order(items, shipping, address, payment, promo)` | Vytvoří e-shop objednávku. **Procentuální sleva se počítá z celkové ceny (subtotal + shipping)**. **Login-only**, používá Flutter app. |
| `create_web_shop_order(items, customer_name, customer_email, customer_phone, shipping_method, shipping_address, payment_method, promo_code, notes)` | **Anon-friendly RPC pro web e-shop** (motogo24.cz). Items: `[{product_id uuid, size text|null, qty int}]` — cena z DB (ne z klienta), velikost validována proti `products.sizes[]`, kontrola `stock_quantity`. Doprava: `pickup`=0, `post`=99, `zasilkovna`=79 Kč. Vytvoří `shop_orders` + `shop_order_items` (s `product_id` FK + `size`). Vrací `{success, order_id}` nebo `{error, ...}`. SECURITY DEFINER, GRANT TO anon, authenticated. **NEPŘEPISUJE** stávající `create_shop_order` — Flutter dál používá login-only verzi. |
| `cancel_booking_tracked(booking_id, reason)` | Stornuje rezervaci s refund kalkulací |
| `shorten_booking_with_refund(p_booking_id, p_new_start, p_new_end, p_reason)` | **NEW (2026-04-29):** Atomicky zkrátí rezervaci a vystaví refund podle storno tabulky (≥168h=100 %, ≥48h=50 %, jinak 0 %). Validace: ownership přes `auth.uid()=user_id`, status IN reserved/active, payment_status='paid', nové datumy uvnitř původních, aktivní rezervace má start zamčený. Per-day cena z `motorcycles.price_mon..price_sun` (ISODOW). UPDATE bookingu (start/end, total_price, `original_start_date`/`original_end_date` při prvním zásahu, modification_history append s `source='web_customer'`). Stripe refund přes `pg_net.http_post` na Edge `process-refund` (vytvoří dobropis credit_note). Vrací jsonb `{success, refund_amount, refund_percent, new_total}` nebo `{success:false, error}` (kódy: `unauthenticated`, `not_found`, `wrong_status`, `not_paid`, `not_a_shortening`, `invalid_range`, `active_start_locked`, `no_change`, `no_diff`). SECURITY DEFINER. GRANT EXECUTE TO authenticated. |
| `apply_booking_changes(p_booking_id, p_new_start, p_new_end, p_new_moto_id, p_new_pickup_method, p_new_pickup_address, p_new_pickup_lat, p_new_pickup_lng, p_new_pickup_fee, p_new_return_method, p_new_return_address, p_new_return_lat, p_new_return_lng, p_new_return_fee, p_reason, p_dry_run)` | **NEW (2026-04-29):** Univerzální atomic RPC pro úpravu existující rezervace přes web. Jedna funkce zvládne kombinaci: změnu datumů, změnu motorky, změnu pickup/return method+address. Pro každou kategorii vypočítá price diff: **(a) datumy** — extend plný rozdíl, shorten podle storno tabulky (≥168h=100 %, ≥48h=50 %, <48h=0 % refund); **(b) motorka** — plný per-day rozdíl (license hierarchie kontrolována na serveru: AM<A1<A2<A; B; N=žádný); **(c) pickup/return delivery_fee** — VŽDY 100 % refund staré, plný doplatek nové, **bez ohledu na čas změny** (separátní business pravidlo, mimo storno tabulku). Validace: ownership, status IN reserved/active, paid, nelze měnit start/motorku u aktivní rezervace, overlap check pro novou motorku/datumy přes existing pending+reserved+active bookings. Net diff > 0 → vrací `payment_required:true` + breakdown bez aplikace (klient otevře Stripe Checkout). Net diff ≤ 0 → atomický UPDATE všech polí (start/end, moto_id, pickup_*, return_*, delivery_fee=pickup_fee+return_fee, total_price, modification_history append) + Stripe refund spuštěn async přes pg_net na Edge `process-refund`. **Dry run režim** (`p_dry_run:=true`) vrátí jen breakdown — používá se pro live preview ceny při psaní v UI. Vrací jsonb `{success, payment_required, net_diff, refund_amount, new_total, breakdown:{dates_diff, moto_diff, pickup_fee_diff, return_fee_diff, storno_pct}}` nebo `{success:false, error}` (kódy: `unauthenticated`, `not_found`, `wrong_status`, `active_start_locked`, `active_moto_locked`, `invalid_range`, `overlap`, `license_insufficient`, `moto_not_found`, `no_change`). SECURITY DEFINER. GRANT EXECUTE TO authenticated. |
| `sos_swap_bookings(incident_id, replacement_moto_id, ...)` | SOS výměna motorky — atomický swap |
| `expire_vouchers()` | Automatická expirace voucherů (pg_cron) |
| `expire_vouchers_and_promos()` | Expirace voucherů + deaktivace promo kódů po valid_to |
| `auto_cancel_expired_pending()` | Auto-cancel pending+unpaid bookings (app: 10min, web: 4h). SECURITY DEFINER. **IMPLEMENTOVÁNO 2026-04-12** — pg_cron každé 2 min |
| `auto_complete_expired_bookings()` | Auto-complete: active/reserved + end_date < today + paid → completed (BEZ fakturace — KF generuje trigger). SECURITY DEFINER |
| `generate_final_invoice_on_complete()` | Trigger funkce: generuje KF (konečnou fakturu) při přechodu active→completed. Rozpis položek: Pronájem (brutto = total_price + discount_amount − extras − delivery), Příslušenství, Přistavení, Sleva (záporná), Odpočty DP. SECURITY DEFINER |
| `trg_send_booking_completed_email()` | Trigger funkce: po vložení KF (invoices.type='final') zavolá send-booking-email (type='booking_completed') přes pg_net — pošle zákazníkovi poděkování s KF v příloze. Dedup přes message_log. SECURITY DEFINER |
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
| `auto_generate_door_codes()` | Trigger funkce: auto-generuje 2 přístupové kódy (motorcycle+accessories) při přechodu bookingu na 'active'. Kontroluje doklady zákazníka (id_card/passport + drivers_license, fallback na license_number+id_number v profilu). Posílá kódy jako admin_message jen pokud má doklady. SECURITY DEFINER, EXCEPTION safe |
| `verify_customer_docs(p_ocr_name, p_ocr_dob, p_ocr_id_number, p_ocr_license_number, p_ocr_license_category, p_ocr_license_expiry, p_rental_end)` | Verifikace naskenovaných dokladů proti profilu. Kontroluje jméno, datum narození, číslo ŘP, platnost ŘP (i proti datu konce rezervace), skupiny ŘP. Vrací jsonb {success, status, mismatches, warnings}. SECURITY DEFINER |
| `auto_deactivate_door_codes()` | Trigger funkce: deaktivuje všechny aktivní kódy (is_active=false) při přechodu bookingu na 'completed' nebo 'cancelled'. SECURITY DEFINER, EXCEPTION safe |
| `release_withheld_door_codes()` | Trigger funkce na `documents` (AFTER INSERT, type IN id_card/passport/drivers_license/id_photo/license_photo): při nahrání dokladů uvolní zadržené door codes pro všechny aktivní bookings uživatele, posílá `door_codes` admin_message + SMS/WA. SECURITY DEFINER, EXCEPTION safe |
| `regen_door_codes_on_moto_change()` | Trigger funkce na `bookings` (AFTER UPDATE OF moto_id, status IN active/reserved): deaktivuje staré kódy a vygeneruje 2 nové pro novou motorku. Pokud má doklady → admin_message + SMS/WA. SECURITY DEFINER, EXCEPTION safe |
| `send_push_via_edge(user_id, title, body, data jsonb)` | Helper: pošle FCM push notifikaci přes Edge Function `send-push` (pg_net). Čte `app.settings.supabase_url` + `service_role_key`. SECURITY DEFINER, EXCEPTION safe |
| `send_door_codes_email(booking_id, user_id)` | Helper: pošle email s přístupovými kódy přes Edge Function `send-booking-email` (type=`door_codes`). Dedup přes `message_log` (template_slug='door_codes'/'web_door_codes', channel='email'). Volá se z `auto_generate_door_codes`, `release_withheld_door_codes`, `regen_door_codes_on_moto_change`, `release_my_door_codes`. SECURITY DEFINER, EXCEPTION safe |
| `trg_push_on_admin_message()` | Trigger funkce na `admin_messages` (AFTER INSERT): volá `send_push_via_edge()` s deep-link payloadem (`type: door_codes` nebo `message`, `id`). SECURITY DEFINER, EXCEPTION safe |
| `release_my_door_codes(p_booking_id)` | RPC pro authenticated zákazníka: ověří doklady (Mindee + fallback) a uvolní zadržené door codes pro vlastní booking. Posílá `door_codes` admin_message + SMS/WA. Vrací jsonb {success, released, error?, withheld_reason?}. Přesný důvod když nejsou doklady (rozlišuje chybí/propadlý/neúplný ŘP). SECURITY DEFINER. GRANT EXECUTE TO authenticated. |
| `check_booking_docs_status(p_user_id, p_end_date)` | Vrací NULL pokud má zákazník platné doklady pro rezervaci končící p_end_date, jinak konkrétní withheld_reason: `Chybí doklady (OP/pas/ŘP)`, `Chybí doklad totožnosti (OP/pas)`, `Chybí ŘP`, `Neúplné údaje ŘP (chybí číslo)`, `ŘP propadlý DD.MM.YYYY`. STABLE, SECURITY DEFINER. Používá se v `auto_generate_door_codes`, `release_withheld_door_codes_for_user`, `regen_door_codes_on_moto_change`, `release_my_door_codes`. |
| `release_withheld_door_codes_for_user(p_user_id)` | Helper: projede všechny aktivní bookings uživatele, pro každý zvlášť zavolá `check_booking_docs_status` proti jeho `end_date`. Pokud OK → uvolní kódy + notifikuje. Pokud ne → jen přepíše withheld_reason (např. "Chybí doklady" → "ŘP propadlý 20.07.2023"). SECURITY DEFINER, EXCEPTION safe. |

### Další funkce v reálné DB (ne v migracích)
| Funkce | Popis |
|--------|-------|
| `auto_accounting_on_booking_paid()` | Auto účetní záznam při zaplacení bookingu |
| `auto_reply_sos()` | Automatická odpověď na SOS |
| `auto_schedule_services()` | Auto plánování servisů |
| `auto_check_service_parts()` | Auto kontrola dílů pro blížící se servisy (~30 kalendářních dní) — zkontroluje sklad, dedup dle konkrétních dílů (nová PO jen pokud díl nemá otevřenou draft/sent objednávku), vytvoří PO seskupené dle dodavatele. Vrací jsonb {created_orders}. SECURITY DEFINER |
| `calc_booking_price_v2()` | Kalkulace ceny bookingu v2 |
| `calculate_moto_roi()` | Výpočet ROI motorky |
| `check_admin_permission()` | Kontrola admin oprávnění |
| `check_moto_availability()` | Kontrola dostupnosti motorky (status: pending/reserved/active) |
| `create_sos_incident()` | Vytvoření SOS incidentu |
| `extend_booking()` | Prodloužení bookingu |
| `generate_invoice_number()` | Generování čísla faktury |
| `get_available_motos()` | Získání dostupných motorek |
| `handle_new_user()` | Zpracování nového uživatele (auth trigger) |
| `send_admin_message()` | Odeslání admin zprávy |
| `snapshot_daily_stats()` | Snapshot denních statistik |
| `sos_share_location()` | Sdílení lokace v SOS |
| ~~`trigger_sos_auto_reply()`~~ | **SMAZÁNO 2026-03-24** — byl no-op, žádný trigger ho nevolal |
| ~~`calc_booking_price()`~~ | **SMAZÁNO 2026-03-24** — nahrazeno calc_booking_price_v2 |
| `update_moto_after_service()` | Aktualizace motorky po servisu |
| `validate_voucher_code(p_code)` | Validace voucherového kódu (vrací {valid, id, type:'fixed', value, code}) |
| `create_test_booking(p_user_id, p_moto_id, p_start, p_end)` | Vytvoření testovací rezervace (SECURITY DEFINER, bypass RLS). Vrací uuid. |
| `update_test_booking_status(p_booking_id, p_status, p_payment_status?)` | Změna stavu testovací rezervace (SECURITY DEFINER). Triggery se spouští normálně (KF, SMS, door codes). |
| `create_test_service_order(p_moto_id, p_type, p_notes)` | Vytvoření testovací servisní zakázky (SECURITY DEFINER, bypass RLS). Vrací uuid. |
| `update_test_booking_fields(p_booking_id, p_fields jsonb)` | Universální update booking polí (end_date, picked_up_at, mileage, rating, pickup/return address+GPS). SECURITY DEFINER. |
| `create_test_sos_timeline(p_incident_id, p_action, p_data)` | Zápis do SOS timeline (SECURITY DEFINER). |
| `update_test_sos_status(p_incident_id, p_status, p_notes)` | Změna stavu SOS incidentu (SECURITY DEFINER). |
| `update_test_profile(p_user_id, p_data jsonb)` | Update profilu zákazníka (full_name, phone, city, license_group). SECURITY DEFINER. |
| `cleanup_all_test_data()` | Smaže vše testovací: bookings, SOS, service, profiles + auth.users. SECURITY DEFINER. Vrací jsonb. |
| `get_moto_booked_dates(p_moto_id)` | Veřejná RPC: vrací obsazené date ranges pro kalendář (start_date, end_date, status, created_at). SECURITY DEFINER, STABLE. Bez citlivých dat — bezpečné pro anon. |
| `create_web_booking(...)` | Vytvoří rezervaci: najde/vytvoří auth usera + profil, zkontroluje dostupnost, vypočte cenu (per-day pricing price_mon..price_sun, inclusive start+end), vytvoří booking. Aktuální signatura (32 parametrů): `p_moto_id, p_start_date, p_end_date, p_name, p_email, p_phone, p_street, p_city, p_zip, p_country, p_note, p_pickup_time, p_delivery_address, p_return_address, p_extras, p_discount_amount, p_discount_code, p_promo_code, p_voucher_id, p_license_group, p_password, p_helmet_size, p_jacket_size, p_pants_size, p_boots_size, p_gloves_size, p_passenger_helmet_size, p_passenger_jacket_size, p_passenger_gloves_size, p_passenger_boots_size, p_return_time, p_existing_booking_id`. p_extras formát: `[{name, unit_price}]`. p_password: nastaví heslo. Velikosti výbavy: 5 sloupců pro řidiče (helmet/jacket/pants/boots/gloves) + 4 pro spolujezdce (helmet/jacket/gloves/boots — kalhoty u spolujezdce nejsou v základní sadě). **p_return_time** (text HH:MM, default NULL) — frontend ho posílá pouze při vrácení mimo provozovnu (return-other zaškrtnuto, nebo delivery + same-as-delivery); jinak zůstává NULL (vrácení v půjčovně Mezná). **p_existing_booking_id** (uuid DEFAULT NULL, od 2026-04-28) — když uživatel klikne "Zpět" v kroku 2 a vrací se s úpravami, frontend pošle bookingId původní pending rezervace. Pokud booking patří stejnému user_id, je pending+unpaid A `booking_source='web'`, RPC ji **UPDATE**uje (přepíše motorku, datum, extras, slevu, velikosti, ...) místo vytvoření nové; vlastní existující booking ignoruje v overlap checku. App/SOS/admin bookingy nelze přes tuto RPC nikdy přepsat (kontrola `booking_source='web'`). Tím se předchází chybě "Booking overlap — motorka není v termínu dostupná" při změně rezervace přes Zpět. **Pozn.:** v DB NENÍ `p_booking_source` — booking_source je do INSERT zapisován hardcoded jako `'web'`. Vrací {booking_id, amount, user_id, is_new_user, reused}. SECURITY DEFINER |
| `set_web_booking_password(p_booking_id, p_password)` | Nastaví heslo zákazníka přes booking ID (pouze web bookings). Heslo se použije pro editaci rezervace i budoucí přihlášení do app. SECURITY DEFINER |
| `get_web_booking_resume(p_booking_id)` | Veřejná RPC pro resume flow (QR kód / abandoned email). Vrací booking data jen pro pending+unpaid+web bookings: {booking_id, user_id, moto_id, moto_model, start_date, end_date, total_price, customer_name/email/phone, has_id_number, has_license_number}. SECURITY DEFINER |
| `notify_web_booking_abandoned()` | Trigger funkce: při auto-cancel web bookingu (pending→cancelled, source=web, unpaid) odešle abandoned email přes send-booking-email. SECURITY DEFINER, EXCEPTION safe |
| `get_ai_traffic_stats(p_from, p_to)` | Agregované AI stats pro Velín dashboard (Analýza → AI traffic). Vrací jsonb {total_requests, by_source, by_bot, top_paths, bookings_from_ai, top_partners, daily_timeline}. Admin only. SECURITY DEFINER |
| `get_page_ai_traffic(p_path, p_from, p_to)` | Per-stránka AI traffic detail (CMS → AI návštěvnost drawer). Vrací jsonb {total, by_bot, daily, led_to_bookings}. Admin only. SECURITY DEFINER |
| `create_api_key(p_partner_name, p_partner_email, p_partner_url, p_rate_limit_rpm, p_scopes)` | Vytvoří REST API klíč pro partnera. Generuje 32-byte random klíč (mk_live_<base64url>), uloží sha256 hash do api_keys. Vrací jsonb {id, api_key, prefix, warning} — **api_key se vrací POUZE TEĎ**, dál uložen není. Admin only. SECURITY DEFINER |
| `revoke_api_key(p_id, p_reason)` | Zneplatní API klíč (is_active=false, revoked_at=now). Admin only. SECURITY DEFINER |
