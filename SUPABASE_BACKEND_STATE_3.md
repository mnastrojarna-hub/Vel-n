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
| `auto_generate_door_codes()` | Trigger funkce: auto-generuje 2 přístupové kódy (motorcycle+accessories) při přechodu bookingu na 'active'. Kontroluje doklady zákazníka, posílá kódy jako admin_message. SECURITY DEFINER, EXCEPTION safe |
| `auto_deactivate_door_codes()` | Trigger funkce: deaktivuje všechny aktivní kódy (is_active=false) při přechodu bookingu na 'completed' nebo 'cancelled'. SECURITY DEFINER, EXCEPTION safe |

### Další funkce v reálné DB (ne v migracích)
| Funkce | Popis |
|--------|-------|
| `auto_accounting_on_booking_paid()` | Auto účetní záznam při zaplacení bookingu |
| `auto_reply_sos()` | Automatická odpověď na SOS |
| `auto_schedule_services()` | Auto plánování servisů |
| `auto_check_service_parts()` | Auto kontrola dílů pro blížící se servisy (~30 kalendářních dní) — zkontroluje sklad, dedup dle konkrétních dílů (nová PO jen pokud díl nemá otevřenou draft/sent objednávku), vytvoří PO seskupené dle dodavatele. Vrací jsonb {created_orders}. SECURITY DEFINER |
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
