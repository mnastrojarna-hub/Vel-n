# SUPABASE BACKEND STATE — MotoGo24 (Část 4: Triggery)
> **Soubory:** 1/6 (Tabulky) | 2/6 (Sloupce) | 3/6 (RPC funkce) | **4/6 (Triggery)** | 5/6 (RLS, Realtime, Edge, Storage, Secrets) | 6/6 (Changelog)

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
| `trg_check_booking_overlap` | bookings (INSERT/UPDATE OF start_date, end_date, moto_id) | check_booking_overlap() |
| ~~`trg_generate_shop_invoice`~~ | ~~shop_orders (payment_status)~~ | **NAHRAZENO** `trg_generate_shop_final_on_ship` (2026-03-21) |
| `trg_generate_shop_final_on_ship` | shop_orders (AFTER UPDATE OF status, payment_status, WHEN shipped/delivered + status changed + paid) | generate_shop_final_on_ship() — FV konečná faktura, odečet DP. Elektronické poukazy: FV okamžitě (status='delivered' z auto_process_voucher_order). Fyzické: FV při odeslání z velínu |
| `moto_day_prices_updated` | moto_day_prices | update_updated_at() |
| `trg_ai_conversations_updated` | ai_conversations | update_updated_at() |
| `trg_sos_notify_user` | sos_incidents (INSERT) | sos_notify_user_on_create() — SECURITY DEFINER, dedup 2min |
| `trg_one_active_sos` | sos_incidents (BEFORE INSERT) | check_one_active_sos() — SECURITY DEFINER, blokuje duplikáty |
| `trg_bridge_admin_message` | messages (INSERT) | bridge_admin_message_to_app() |
| `trg_restore_vouchers_on_cancel` | bookings (UPDATE) | restore_vouchers_on_cancel() |
| `trg_auto_process_voucher_order` | shop_orders (BEFORE UPDATE OF payment_status, WHEN paid) | auto_process_voucher_order() — auto voucher kódy + in-app notifikace + status update |
| `trg_sync_invoice_to_documents` | invoices (INSERT) | sync_invoice_to_documents() |
| `trg_sync_invoice_pdf_update` | invoices (UPDATE pdf_path) | sync_invoice_pdf_update() |
| `trg_sync_generated_doc_to_documents` | generated_documents (INSERT) | sync_generated_doc_to_documents() |
| `trg_sync_moto_day_prices` | moto_day_prices (INSERT/UPDATE) | sync_moto_day_prices_to_motorcycles() |
| `trg_generate_final_invoice` | bookings (AFTER UPDATE OF status, WHEN active→completed) | generate_final_invoice_on_complete() — SECURITY DEFINER, EXCEPTION safe |
| ~~`trg_auto_generate_door_codes`~~ | ~~bookings~~ | **SMAZÁN 2026-03-24** — nahrazen _insert + _update verzemi |
| `trg_auto_generate_door_codes_insert` | bookings (AFTER INSERT, WHEN status=active) | auto_generate_door_codes() — pro SOS replacement bookings vytvořené rovnou jako active |
| `trg_auto_generate_door_codes_update` | bookings (AFTER UPDATE OF status, WHEN →active) | auto_generate_door_codes() — SECURITY DEFINER, generuje 2 kódy (motorcycle+accessories), posílá admin_message. EXCEPTION safe |
| `trg_auto_deactivate_door_codes` | bookings (AFTER UPDATE OF status, WHEN →completed/cancelled) | auto_deactivate_door_codes() — deaktivuje is_active=false. EXCEPTION safe |
| `trg_notify_booking_confirmed` | bookings (AFTER INSERT/UPDATE OF status, WHEN reserved) | trg_notify_booking_confirmed() — SMS+WA potvrzení rezervace. Dedup přes message_log. SECURITY DEFINER |
| `trg_notify_door_codes` | branch_door_codes (AFTER INSERT, WHEN motorcycle) | trg_notify_door_codes() — SMS+WA přístupové kódy. Dedup přes message_log. SECURITY DEFINER |
| `trg_notify_booking_cancelled` | bookings (AFTER UPDATE OF status, WHEN →cancelled) | trg_notify_booking_cancelled() — SMS+WA storno. Dedup přes message_log. SECURITY DEFINER |
| `trg_notify_ride_completed` | bookings (AFTER UPDATE OF status, WHEN →completed) | trg_notify_ride_completed() — SMS+WA dokončení jízdy + review link. Dedup přes message_log. SECURITY DEFINER |
| `trg_notify_voucher_purchased` | vouchers (AFTER INSERT, WHEN active) | trg_notify_voucher_purchased() — SMS voucher info. Dedup přes message_log. SECURITY DEFINER |
| ~~`trg_notify_web_booking_abandoned`~~ | ~~bookings (AFTER UPDATE OF status, WHEN pending→cancelled)~~ | **DROPPED 2026-04-29** — abandoned mail se posílá dříve (10/20 min) přes cron `send_abandoned_booking_emails`, takže emit při auto-cancel po 4 h by způsobil duplicitní mail. Funkce `notify_web_booking_abandoned()` ponechána v DB (nevolaná). |
| `trg_release_codes_on_doc_upload` | documents (AFTER INSERT, WHEN type IN id_card/passport/drivers_license/id_photo/license_photo) | release_withheld_door_codes() → deleguje na release_withheld_door_codes_for_user(NEW.user_id) — ta ověří pro každou rezervaci přesný stav dokladů (vč. platnosti ŘP vs. end_date) a uvolní/aktualizuje withheld_reason. SECURITY DEFINER, EXCEPTION safe |
| `trg_regen_codes_on_moto_change` | bookings (AFTER UPDATE OF moto_id, WHEN moto_id změněn + status IN active/reserved) | regen_door_codes_on_moto_change() — deaktivuje staré kódy a vygeneruje nové pro novou motorku. SECURITY DEFINER, EXCEPTION safe |
| `trg_push_on_admin_message` | admin_messages (AFTER INSERT) | trg_push_on_admin_message() — pošle FCM push přes `send-push` edge function. SECURITY DEFINER, EXCEPTION safe |
| `trg_send_booking_completed_email` | invoices (AFTER INSERT, WHEN type='final') | trg_send_booking_completed_email() — po vložení KF odešle `booking_completed` e-mail přes `send-booking-email` (poděkování + KF v příloze + slevový kód `VRACENI-*`). **FIX 2026-05-03:** čte config z `app_settings` tabulky (GUC nefunguje na Supabase managed). Dedup přes message_log. SECURITY DEFINER, EXCEPTION safe |
| `trg_shop_order_confirmed_email` | shop_orders (AFTER UPDATE OF payment_status, WHEN pending→paid) | **NEW 2026-05-03:** trg_send_shop_order_confirmed_email() — pošle zákazníkovi potvrzení e-shop objednávky + DP přes send-booking-email s `type='shop_order_confirmed'`. Dedup přes message_log.content_preview. SECURITY DEFINER, EXCEPTION safe |
| `trg_booking_modified_email` | bookings (AFTER UPDATE) | **NEW 2026-05-03 (B):** trg_send_booking_modified_email() — detekuje změnu moto/datumy/cena/místo přistavení a pošle `booking_modified` mail s plným `original_*` payloadem z OLD. Pokrývá Velin / web / Flutter / RPC. Dedup 5min přes message_log. SECURITY DEFINER, EXCEPTION safe |

### Další triggery v reálné DB
| Trigger | Tabulka | Funkce |
|---------|---------|--------|
| `bookings_auto_accounting` | bookings (AFTER UPDATE OF payment_status, WHEN paid) | auto_accounting_on_booking_paid() — EXCEPTION safe |
| `maintenance_log_after_insert` | maintenance_log | update_moto_after_service() |
| ~~`sos_auto_reply_on_create`~~ | ~~sos_incidents (INSERT)~~ | **DROPPED 2026-03-10** — crashoval INSERT bez error handleru |
| ~~`admin_users_updated_at`~~ | ~~admin_users~~ | **SMAZÁN 2026-03-24** — duplicitní s trg_admin_users_updated |
| ~~`ai_conversations_updated_at`~~ | ~~ai_conversations~~ | **SMAZÁN 2026-03-24** — duplicitní s trg_ai_conversations_updated |
| `trg_accessory_types_updated` | accessory_types | update_updated_at() |
| `trg_emp_attendance_updated` | emp_attendance | update_updated_at() |
| `trg_emp_vacations_updated` | emp_vacations | update_updated_at() |
| `trg_emp_shifts_updated` | emp_shifts | update_updated_at() |
| `trg_emp_documents_updated` | emp_documents | update_updated_at() |
| `trg_delivery_notes_updated` | delivery_notes | update_updated_at() |
| `trg_contracts_updated` | contracts | update_updated_at() |
| `faq_items_set_updated_at` | faq_items (BEFORE UPDATE) | set_updated_at_now() — auto-aktualizace `updated_at` při změně FAQ položky |
| Různé `_updated_at` triggery | více tabulek | update_updated_at() |
