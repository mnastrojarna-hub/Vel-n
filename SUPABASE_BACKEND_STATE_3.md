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
| `create_shop_order(items, shipping, address, payment, promo)` | Vytvoří e-shop objednávku. **Procentuální sleva se počítá z celkové ceny (subtotal + shipping)** |
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
| `auto_generate_door_codes()` | Trigger funkce: auto-generuje 2 přístupové kódy (motorcycle+accessories) při přechodu bookingu na 'active'. Kontroluje doklady zákazníka (id_card/passport + drivers_license, fallback na license_number+id_number v profilu). Posílá kódy jako admin_message jen pokud má doklady. SECURITY DEFINER, EXCEPTION safe |
| `verify_customer_docs(p_ocr_name, p_ocr_dob, p_ocr_id_number, p_ocr_license_number, p_ocr_license_category, p_ocr_license_expiry, p_rental_end)` | Verifikace naskenovaných dokladů proti profilu. Kontroluje jméno, datum narození, číslo ŘP, platnost ŘP (i proti datu konce rezervace), skupiny ŘP. Vrací jsonb {success, status, mismatches, warnings}. SECURITY DEFINER |
| `auto_deactivate_door_codes()` | Trigger funkce: deaktivuje všechny aktivní kódy (is_active=false) při přechodu bookingu na 'completed' nebo 'cancelled'. SECURITY DEFINER, EXCEPTION safe |

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
| `check_moto_availability()` | Kontrola dostupnosti motorky |
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
| `create_web_booking(p_moto_id, p_start_date, p_end_date, p_name, p_email, p_phone, ...)` | Vytvoří web rezervaci: najde/vytvoří auth usera + profil, zkontroluje dostupnost, vypočte cenu, vytvoří booking (source='web'). Vrací {booking_id, amount, user_id}. SECURITY DEFINER |
| `notify_web_booking_abandoned()` | Trigger funkce: při auto-cancel web bookingu (pending→cancelled, source=web, unpaid) odešle abandoned email přes send-booking-email. SECURITY DEFINER, EXCEPTION safe |
