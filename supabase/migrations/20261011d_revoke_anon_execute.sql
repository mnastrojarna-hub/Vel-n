-- ============================================================================
-- 20261011d_revoke_anon_execute.sql  (běží jako POSLEDNÍ ze sady 20261011*)
-- FUNKCE NEVOLÁ NIKDO BEZ PŘIHLÁŠENÍ (rozhodnutí majitele 2026-10-11)
--
-- Postgres dává EXECUTE na nové funkce roli PUBLIC a Supabase navíc výchozími
-- právy anon/authenticated/service_role → 192 funkcí v public bylo volatelných
-- anonymně přes /rest/v1/rpc/*. Tady se EXECUTE ODEBÍRÁ PUBLIC + anon (a u
-- serverových funkcí i authenticated) a potřebným rolím se dává EXPLICITNĚ.
-- Seznam a klasifikace: audit všech volajících (appka oba stromy, web JS + PHP
-- server, Velín, edge, Raspberry kiosk, pg_cron, SQL/triggery, RLS politiky
-- vč. storage/realtime, pohledy, defaulty/generated sloupce).
--
--  A) jen přihlášení (authenticated: appka / Velín admin) + service_role
--  S) jen server (service_role; volají je jen edge funkce se service klíčem,
--     pg_cron a SECURITY DEFINER funkce/triggery jako vlastník postgres —
--     vlastník EXECUTE neztrácí)
--  H) veřejné toky (web host / e-shop / poukazy) — anon ZŮSTÁVÁ, jen se
--     ruší PUBLIC a práva se dávají explicitně; těla zpřísňují jiné soubory
--
-- NEDOTČENO: is_admin(), is_superadmin() (RLS politiky role public se
-- vyhodnocují i pro anon), veřejný katalog (get_moto_booked_dates,
-- get_motos_availability_status, get_trailer_availability,
-- get_document_translation) a kiosk RPC s tokenem zařízení (kiosk_heartbeat,
-- kiosk_resolve_code, kiosk_sync_* …) — všechny SECURITY DEFINER.
-- is_admin(uuid) RLS nepoužívá a nikdo ji nevolá → skupina A.
-- INVOKER funkce/triggery spouštěné jako authenticated volají jen funkce
-- skupiny A (route_detect_countries/point_country z routes_set_countries,
-- branch_is_self_service z _guard_moto_branch_type_move, analytics_*,
-- merge_license_group*, _service_*), generated sloupce
-- points_of_interest jsou A (zapisuje jen admin / service / DEFINER).
--
-- Idempotentní: chybějící signatura se přeskočí (NOTICE), REVOKE/GRANT lze
-- opakovat. Signatury = pg_get_function_identity_arguments ze živého schématu
-- (+ nová get_web_shop_order_confirmation(uuid,text) z 20261011b_…_b_confirm).
-- ============================================================================

DO $$
DECLARE
  v_sig text;
  v_fn  regprocedure;
  v_n   int := 0;
BEGIN
  PERFORM set_config('search_path', 'public, pg_catalog', true);
  FOREACH v_sig IN ARRAY ARRAY[
    '_addr_norm(text)', '_apply_discount_variant_b(numeric,numeric,numeric,text)',
    '_booking_extra_is_gear(text)', '_calc_stacked_discount(numeric,jsonb)',
    '_delivery_fee_floor(float8,float8,numeric)',
    '_delivery_place_moved(text,float8,float8,text,float8,float8)', '_door_code_valid_from(timestamptz)',
    '_door_code_valid_until(timestamptz)', '_is_self_service_booking(uuid)',
    '_license_moto_rank(public.license_group)', '_moto_dayprice_sum(uuid,date,date)', '_norm_supplier(text)',
    '_ride_json(public.user_rides)', '_ride_stats(jsonb)', '_ride_track_cap(jsonb,integer)',
    '_ride_track_km(jsonb)', '_service_done_task_keys(jsonb,text,text)', '_service_items_with_keys(jsonb)',
    '_storno_cap_after_move(jsonb,date,date)', 'admin_booking_live_ride(uuid)',
    'admin_create_customer(text,text,text,text,text,text,text)', 'admin_finish_user_ride(uuid)',
    'admin_poi_duplicate_groups(integer,text,integer,boolean)', 'admin_poi_merge(uuid,uuid)',
    'analytics_customer_km()', 'analytics_moto_km()', 'analytics_moto_rental_km()',
    'analytics_service_plan(numeric)', 'app_save_full_profile(jsonb)',
    'append_ride_track(uuid,jsonb,numeric)', 'auto_check_service_parts()', 'auto_reply_sos(uuid,text)',
    'branch_has_gate(uuid)', 'branch_is_closed(uuid,date,date)', 'branch_is_self_service(uuid)',
    'calc_booking_price_v2(uuid,date,date,text)', 'calculate_moto_roi(uuid,date,date)',
    'cancel_booking_tracked(uuid,text)', 'check_admin_permission(uuid,text)',
    'check_asset_status(text,text,text,text,numeric)',
    'check_document_status(text,text,date,text,text,text,numeric)', 'check_license_for_moto(uuid,date)',
    'check_moto_availability(uuid,timestamptz,timestamptz,uuid)',
    'confirm_booking_surcharge(uuid,text,text,date,text)', 'correct_motorcycle_mileage(uuid,integer,text)',
    'create_api_key(text,text,text,integer,text[])', 'create_manual_ride(text,text,jsonb)',
    'create_sos_incident(public.sos_type,uuid,numeric,numeric,text,boolean)',
    'delete_customer_account(uuid)', 'delete_poi_review(uuid,uuid,uuid)', 'delete_ride_point(uuid)',
    'delete_route_review(uuid)', 'delete_user_ride(uuid)', 'delete_user_route(uuid)',
    'find_email_templates_for_event(text)', 'finish_user_ride(uuid,jsonb,text)',
    'generate_invoice_number(text)', 'get_ai_traffic_stats(timestamptz,timestamptz)',
    'get_app_install_stats()', 'get_available_motos(timestamptz,timestamptz,text,public.license_group,uuid)',
    'get_booking_rides(uuid)', 'get_branch_routes(uuid)', 'get_branch_routes_lite()', 'get_my_places()',
    'get_my_rides(integer)', 'get_my_saved_routes()', 'get_page_ai_traffic(text,timestamptz,timestamptz)',
    'get_poi_detail(uuid)', 'get_poi_reviews(uuid,uuid,uuid)', 'get_pois_catalog()',
    'get_promo_code_type(text)', 'get_public_rides(integer,integer)', 'get_route_detail(uuid)',
    'get_route_poi_detail(uuid)', 'get_route_reviews(uuid)', 'get_unread_thread_message_count(uuid)',
    'get_visitor_stats(timestamptz,timestamptz,text,text)', 'is_admin(uuid)',
    'jsonb_name_translations(jsonb)', 'kiosk_device_branch(uuid,uuid,boolean)',
    'kiosk_jbool(jsonb,text[])', 'kiosk_jnum(jsonb,text[])', 'kiosk_rollout_cancel(uuid)',
    'kiosk_rollout_start(text,uuid,uuid,integer,integer,boolean,text)', 'kiosk_rollout_tick()',
    'mark_place_visited(uuid,uuid,uuid,uuid)',
    'merge_license_group(public.license_group[],text)',
    'merge_license_group_multi(public.license_group[],text)', 'moto_branch_closed(uuid,date,date)',
    'moto_is_self_service(uuid)', 'next_document_number(text)', 'normalize_supplier_name(text)',
    'poi_norm_name(text)', 'poi_rating_summary(uuid,uuid,uuid)', 'point_country(float8,float8)',
    'rate_poi(uuid,uuid,integer,uuid)',
    'record_stock_receipt(text,text,date,text,text,text,numeric,uuid,boolean)',
    'release_my_door_codes(uuid)', 'revoke_api_key(uuid,text)', 'route_detect_countries(jsonb,jsonb)',
    'save_ride_point(uuid,uuid,text,text,text,float8,float8,text[],integer,timestamptz)',
    'save_user_route(text,text,uuid,jsonb,jsonb,text,numeric,integer)', 'service_task_key_for_label(text)',
    'set_my_license_group(text[])', 'shorten_booking_with_refund(uuid,date,date,text)',
    'sos_share_location(uuid,numeric,numeric)', 'sos_swap_bookings(uuid,uuid,text,numeric,numeric,boolean)',
    'split_booking_moto_swap(uuid,uuid,date,text,boolean,boolean)', 'start_user_ride(uuid,float8,float8)',
    'submit_poi_review(uuid,uuid,uuid,integer,text,text[])', 'submit_route_review(uuid,integer,text,text[])',
    'sync_moto_service_status(uuid)', 'trailer_unit_busy(uuid,date,date,uuid)',
    'update_user_ride(uuid,text,text,text,text)', 'verify_customer_docs(text,text,text,text,text,text,text)'
  ] LOOP
    v_fn := to_regprocedure('public.' || v_sig);
    -- pojistka: jazykové RPC webu/appky (migrace i18n jiné větve) nikdy nesahat
    IF v_sig ~ '^(set_booking_language|set_shop_order_language|get_document_translation)\(' THEN CONTINUE; END IF;
    IF v_fn IS NULL THEN RAISE NOTICE 'skip (missing) %', v_sig; CONTINUE; END IF;
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', v_fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', v_fn);
    v_n := v_n + 1;
  END LOOP;
  RAISE NOTICE 'A (authenticated + service_role): % funkcí', v_n;
END $$;

DO $$
DECLARE
  v_sig text;
  v_fn  regprocedure;
  v_n   int := 0;
BEGIN
  PERFORM set_config('search_path', 'public, pg_catalog', true);
  FOREACH v_sig IN ARRAY ARRAY[
    '_reallocate_booking_discounts(uuid,numeric)', 'ai_booking_readiness(text)',
    'ai_get_booking_emails(text)', 'ai_get_order_status(text)', 'ai_lookup_bookings_by_contact(text)',
    'apply_booking_change_light(uuid,date,date,uuid,text,text,numeric,text,text,numeric,time,text,boolean)',
    'apply_booking_changes_anon(uuid,text,text,date,date,uuid,text,text,float8,float8,numeric,text,text,float8,float8,numeric,text,boolean)',
    'auto_activate_reserved_bookings()', 'auto_cancel_expired_pending()', 'auto_complete_expired_bookings()',
    'cleanup_old_verification_documents()', 'detect_customer_language(uuid,uuid,uuid)',
    'dispatch_email_event(text,jsonb)', 'expire_vouchers()', 'expire_vouchers_and_promos()',
    'find_booking_for_modification(uuid,text,text)', 'find_booking_light(uuid)', 'fio_sync_tick()',
    'list_pending_ai_suggestions(integer)', 'mirror_route_images_tick()', 'report_unpicked_bookings()',
    'resolve_booking_ref(text)', 'send_abandoned_booking_emails()',
    'send_admin_message(uuid,text,text,text,uuid,uuid)',
    'send_message_via_edge(text,text,text,jsonb,uuid,uuid)',
    'send_message_via_edge(text,text,text,jsonb,uuid,uuid,text)', 'send_missing_booking_reserved_emails()',
    'send_push_via_edge(uuid,text,text,jsonb)', 'send_sms_and_wa(text,text,jsonb,uuid,uuid,text)',
    'set_booking_mod_surcharge(uuid)', 'set_booking_qr_payment(uuid)', 'snapshot_daily_stats()',
    'trigger_poi_photo_backfill()', 'trigger_poi_surroundings_backfill()',
    'trigger_route_translation_backfill()',
    -- interní pomocníci hromadné aktualizace (CONTRACT.md §fleet: bez GRANT),
    -- volají je jen DEFINER kiosk_rollout_start/tick/cancel jako vlastník
    'kiosk_device_update_error(public.kiosk_rollouts,public.kiosk_devices,timestamptz,uuid)',
    'kiosk_device_updated(public.kiosk_rollouts,public.kiosk_devices,timestamptz)',
    'kiosk_rollout_counts(uuid)', 'kiosk_rollout_jts(text)',
    'kiosk_rollout_send_command(public.kiosk_rollouts,public.kiosk_devices)',
    'kiosk_version_matches(text,text)'
  ] LOOP
    v_fn := to_regprocedure('public.' || v_sig);
    -- pojistka: jazykové RPC webu/appky (migrace i18n jiné větve) nikdy nesahat
    IF v_sig ~ '^(set_booking_language|set_shop_order_language|get_document_translation)\(' THEN CONTINUE; END IF;
    IF v_fn IS NULL THEN RAISE NOTICE 'skip (missing) %', v_sig; CONTINUE; END IF;
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', v_fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', v_fn);
    v_n := v_n + 1;
  END LOOP;
  RAISE NOTICE 'S (jen service_role): % funkcí', v_n;
END $$;

DO $$
DECLARE
  v_sig text;
  v_fn  regprocedure;
  v_n   int := 0;
BEGIN
  PERFORM set_config('search_path', 'public, pg_catalog', true);
  FOREACH v_sig IN ARRAY ARRAY[
    'cancel_pending_web_booking(uuid)', 'check_web_booking_email(text)',
    'check_web_booking_user_overlap(text,date,date,uuid)',
    'create_web_booking(uuid,timestamptz,timestamptz,text,text,text,text,text,text,text,text,time,text,text,jsonb,numeric,text,text,uuid,text,text,text,text,text,text,text,text,text,text,text,text,uuid,text,boolean,boolean,boolean,boolean,text,uuid,jsonb)',
    'create_web_shop_order(jsonb,text,text,text,text,text,text,text,text)',
    'get_web_booking_confirmation(text,uuid)', 'get_web_booking_resume(uuid)',
    'get_web_shop_order_confirmation(uuid)', 'get_web_shop_order_confirmation(uuid,text)',
    'set_booking_form_seconds(uuid,timestamptz)',
    'set_web_booking_chosen_method(uuid,text)', 'set_web_booking_company(uuid,text,text,text,text)',
    'set_web_booking_device(uuid,text,text)', 'set_web_booking_docs(uuid,text,text,text,text,text)',
    'set_web_booking_docs_completed(uuid)', 'set_web_booking_password(uuid,text)',
    'validate_promo_code(text)', 'validate_voucher_code(text)'
  ] LOOP
    v_fn := to_regprocedure('public.' || v_sig);
    -- pojistka: jazykové RPC webu/appky (migrace i18n jiné větve) nikdy nesahat
    IF v_sig ~ '^(set_booking_language|set_shop_order_language|get_document_translation)\(' THEN CONTINUE; END IF;
    IF v_fn IS NULL THEN RAISE NOTICE 'skip (missing) %', v_sig; CONTINUE; END IF;
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', v_fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon, authenticated, service_role', v_fn);
    v_n := v_n + 1;
  END LOOP;
  RAISE NOTICE 'H (veřejné, explicitně anon): % funkcí', v_n;
END $$;
