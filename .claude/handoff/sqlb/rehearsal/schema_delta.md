# Schema delta of the 20261112 bundle versus pristine live (snapshot e5d5b0f7)

Produced 2026-11-12 by the round-2 rehearsal. Method: fresh copy of the live template (`sqlb_reh2s`), each file of `supabase/migrations/20261112*.sql` applied in `LC_ALL=C` order with `apply.sh` (one transaction, ON_ERROR_STOP), `sig.sh` taken after every file and diffed against the previous one. The cumulative result is identical to the `deploy_sim.sh` result on the seeded database `sqlb_reh2` and on the empty database `sqlb_reh2e`. Raw per-file diffs (with body md5): `rehearsal/r2/steps/<file>.diff`.

Legend: **ADDED** = object that does not exist live; **CHANGED** = live object whose signature line differs (old line, then new line). Function lines give the full signature, language, SECURITY DEFINER, volatility, `SET` config, owner and ACL (`=X` = PUBLIC). Body md5 is omitted here, so a CHANGED entry whose old and new lines read the same is a change of the function body only (signature, config, owner and ACL kept).

Object kinds with **no change at all** in the whole bundle: views, enum types, sequences, cron jobs (`cron.job` untouched; b06 only replaces the body of `close_stale_user_rides`, which the existing job calls by name), default privileges, storage buckets, policies on existing tables, existing triggers, existing indexes and constraints. No column, function or overload is removed except the two old overloads named under a03 and a04 (replaced by a superset signature with defaults).


## 20261112a01_card_rounding.sql

- **ADDED** `COLUMN bookings.card_rounding numeric(10,2) NOT NULL DEFAULT 0`
- **ADDED** `COLUMN shop_orders.card_rounding numeric(10,2) NOT NULL DEFAULT 0`
- **ADDED** `FUNCTION _protect_card_rounding() -> trigger | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`
- **ADDED** `FUNCTION _reset_card_rounding_on_reprice() -> trigger | lang=plpgsql kind=f secdef=false vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`
- **CHANGED** `FUNCTION generate_final_invoice_on_complete() -> trigger | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl==X/postgres,anon=X/postgres,authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`
  - now: `FUNCTION generate_final_invoice_on_complete() -> trigger | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl==X/postgres,anon=X/postgres,authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`
- **ADDED** `TRIGGER public.bookings trg_protect_card_rounding enabled=O | CREATE TRIGGER trg_protect_card_rounding BEFORE INSERT OR UPDATE OF card_rounding ON public.bookings FOR EACH ROW EXECUTE FUNCTION public._protect_card_rounding()`
- **ADDED** `TRIGGER public.bookings trg_reset_card_rounding_on_reprice enabled=O | CREATE TRIGGER trg_reset_card_rounding_on_reprice BEFORE UPDATE OF total_price, moto_id, start_date, end_date, extras_price, delivery_fee, discount_amount, discount_code, promo_code_id, voucher_id, loyalty_discount_amount, late_pickup_discount_amount ON public.bookings FOR EACH ROW EXECUTE FUNCTION public._reset_card_rounding_on_reprice()`

## 20261112a02_customer_restore.sql

- **ADDED** `COLUMN bookings.restore_count smallint NOT NULL DEFAULT 0`
- **ADDED** `COLUMN bookings.restored_by_source text`
- **ADDED** `FUNCTION _customer_restore_check(p_b public.bookings, p_uid uuid) -> jsonb | lang=plpgsql kind=f secdef=true vol=s strict=false par=u cfg=[search_path=public] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`
- **ADDED** `FUNCTION _customer_restore_guard() -> trigger | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`
- **ADDED** `FUNCTION _customer_restore_redeem(p_b public.bookings) -> text | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`
- **CHANGED** `FUNCTION auto_cancel_expired_pending() -> void | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`
  - now: `FUNCTION auto_cancel_expired_pending() -> void | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`
- **ADDED** `FUNCTION customer_restore_booking(p_booking_id uuid) -> jsonb | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`
- **CHANGED** `FUNCTION restore_vouchers_on_cancel() -> trigger | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[] owner=postgres acl==X/postgres,anon=X/postgres,authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`
  - now: `FUNCTION restore_vouchers_on_cancel() -> trigger | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl==X/postgres,anon=X/postgres,authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`
- **ADDED** `TRIGGER public.bookings trg_a_customer_restore_guard enabled=O | CREATE TRIGGER trg_a_customer_restore_guard BEFORE INSERT OR UPDATE OF status, restored_at, restored_by_source, restore_count, checkout_started_at, cancelled_by, cancelled_by_source, booking_source, created_at ON public.bookings FOR EACH ROW EXECUTE FUNCTION public._customer_restore_guard()`

## 20261112a03_swap_card_rounding.sql

- **CHANGED** `FUNCTION split_booking_moto_swap(p_booking_id uuid, p_new_moto_id uuid, p_swap_date date, p_swap_time text DEFAULT NULL::text, p_dry_run boolean DEFAULT false, p_settle_refund boolean DEFAULT false) -> jsonb | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`
  - now: `FUNCTION split_booking_moto_swap(p_booking_id uuid, p_new_moto_id uuid, p_swap_date date, p_swap_time text DEFAULT NULL::text, p_dry_run boolean DEFAULT false, p_settle_refund boolean DEFAULT false, p_card_rounding numeric DEFAULT 0, p_paid numeric DEFAULT NULL::numeric, p_payment_ref text DEFAULT NULL::text) -> jsonb | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`

## 20261112a04_gear_rounding_modified_mail.sql

- **CHANGED** `FUNCTION apply_paid_gear_change(p_booking_id uuid, p_sizes jsonb) -> jsonb | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`
  - now: `FUNCTION apply_paid_gear_change(p_booking_id uuid, p_sizes jsonb, p_paid numeric DEFAULT NULL::numeric, p_card_rounding numeric DEFAULT 0, p_payment_ref text DEFAULT NULL::text, p_chg_hash text DEFAULT NULL::text) -> jsonb | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`
- **CHANGED** `FUNCTION trg_send_booking_modified_email() -> trigger | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[] owner=postgres acl==X/postgres,anon=X/postgres,authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`
  - now: `FUNCTION trg_send_booking_modified_email() -> trigger | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl==X/postgres,anon=X/postgres,authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`
- **CHANGED** `FUNCTION update_booking_gear(p_booking_id uuid, p_sizes jsonb, p_dry_run boolean DEFAULT false, p_settle_refund boolean DEFAULT false, p_own_gear boolean DEFAULT NULL::boolean) -> jsonb | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`
  - now: `FUNCTION update_booking_gear(p_booking_id uuid, p_sizes jsonb, p_dry_run boolean DEFAULT false, p_settle_refund boolean DEFAULT false, p_own_gear boolean DEFAULT NULL::boolean) -> jsonb | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`

## 20261112a05_uq_invoices_credit_note_refund.sql

- **ADDED** `INDEX public.invoices CREATE UNIQUE INDEX uq_invoices_credit_note_refund ON public.invoices USING btree (stripe_refund_id) WHERE ((type = 'credit_note'::text) AND (stripe_refund_id IS NOT NULL) AND (status <> 'cancelled'::text))`

## 20261112a06_web_booking_confirmation_late_refund.sql

- **CHANGED** `FUNCTION get_web_booking_confirmation(p_session_id text DEFAULT NULL::text, p_booking_id uuid DEFAULT NULL::uuid) -> jsonb | lang=plpgsql kind=f secdef=true vol=s strict=false par=u cfg=[search_path=public, auth] owner=postgres acl=anon=X/postgres,authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`
  - now: `FUNCTION get_web_booking_confirmation(p_session_id text DEFAULT NULL::text, p_booking_id uuid DEFAULT NULL::uuid) -> jsonb | lang=plpgsql kind=f secdef=true vol=s strict=false par=u cfg=[search_path=public, auth] owner=postgres acl=anon=X/postgres,authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`

## 20261112a07_guard_customer_booking_pricing.sql

- **ADDED** `FUNCTION _guard_customer_booking_pricing() -> trigger | lang=plpgsql kind=f secdef=false vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=anon=X/postgres,authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`
- **ADDED** `TRIGGER public.bookings _trg_guard_customer_booking_pricing enabled=O | CREATE TRIGGER _trg_guard_customer_booking_pricing BEFORE UPDATE OF start_date, end_date, moto_id, trailer_moto_id, pickup_time, total_price, extras_price, delivery_fee, discount_amount, loyalty_discount_amount, late_pickup_discount_amount ON public.bookings FOR EACH ROW EXECUTE FUNCTION public._guard_customer_booking_pricing()`

## 20261112b01_rides_columns.sql

- **ADDED** `COLUMN user_rides.pause_aware boolean NOT NULL DEFAULT false`
- **ADDED** `COLUMN user_rides.pause_sec integer NOT NULL DEFAULT 0`
- **ADDED** `COLUMN user_rides.stages jsonb NOT NULL DEFAULT '[]'::jsonb`
- **ADDED** `COLUMN user_rides.stats_state jsonb`
- **ADDED** `COLUMN user_rides.trip_id uuid`
- **ADDED** `COLUMN user_rides.trip_name text`
- **ADDED** `CONSTRAINT user_rides user_rides_trip_name_len CHECK (((trip_name IS NULL) OR (char_length(trip_name) <= 120)))`
- **ADDED** `INDEX public.user_rides CREATE INDEX idx_user_rides_trip ON public.user_rides USING btree (user_id, trip_id) WHERE (trip_id IS NOT NULL)`
- Data written by the file itself (outside function bodies): `feature_flags (INSERT ride_autopause, ON CONFLICT DO NOTHING)`
## 20261112b02_rides_stats_core.sql

- **ADDED** `FUNCTION _ride_prague_night(p_from double precision, p_to double precision) -> boolean | lang=sql kind=f secdef=false vol=s strict=false par=u cfg=[search_path=public] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`
- **ADDED** `FUNCTION _ride_stage_days(p_stages jsonb) -> integer | lang=sql kind=f secdef=false vol=s strict=false par=u cfg=[search_path=public] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`
- **CHANGED** `FUNCTION _ride_stats(p_track jsonb) -> jsonb | lang=plpgsql kind=f secdef=false vol=i strict=false par=u cfg=[] owner=postgres acl=authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`
  - now: `FUNCTION _ride_stats(p_track jsonb) -> jsonb | lang=plpgsql kind=f secdef=true vol=s strict=false par=u cfg=[search_path=public] owner=postgres acl=authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`
- **ADDED** `FUNCTION _ride_stats_v2(p_seg jsonb, p_state jsonb, p_stages jsonb) -> jsonb | lang=plpgsql kind=f secdef=false vol=s strict=false par=u cfg=[search_path=public] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`
- **CHANGED** `FUNCTION _ride_track_cap(p_track jsonb, p_max integer DEFAULT 4000) -> jsonb | lang=sql kind=f secdef=false vol=i strict=false par=u cfg=[] owner=postgres acl=authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`
  - now: `FUNCTION _ride_track_cap(p_track jsonb, p_max integer DEFAULT 4000) -> jsonb | lang=plpgsql kind=f secdef=false vol=i strict=false par=u cfg=[search_path=public] owner=postgres acl=authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`

## 20261112b03_rides_append_core.sql

- **ADDED** `COMMENT function _ride_booking_end(p_booking_id uuid) md5=045c87c5710cbe405d4498bf5f1019ec`
- **ADDED** `FUNCTION _ride_append_core(p_ride_id uuid, p_points jsonb) -> jsonb | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`
- **ADDED** `FUNCTION _ride_booking_end(p_booking_id uuid) -> timestamp with time zone | lang=sql kind=f secdef=true vol=s strict=false par=u cfg=[search_path=public] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`

## 20261112b04_rides_finish.sql

- **ADDED** `FUNCTION _ride_auto_name(p_from date, p_to date) -> text | lang=sql kind=f secdef=false vol=s strict=false par=u cfg=[search_path=public] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`
- **ADDED** `FUNCTION _ride_close(p_ride_id uuid, p_ended_at timestamp with time zone, p_by text, p_reclose boolean) -> jsonb | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`
- **CHANGED** `FUNCTION _ride_finalize(p_ride_id uuid, p_ended_at timestamp with time zone DEFAULT NULL::timestamp with time zone) -> jsonb | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`
  - now: `FUNCTION _ride_finalize(p_ride_id uuid, p_ended_at timestamp with time zone DEFAULT NULL::timestamp with time zone) -> jsonb | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`
- **CHANGED** `FUNCTION _ride_json(p_ride public.user_rides) -> jsonb | lang=sql kind=f secdef=false vol=s strict=false par=u cfg=[] owner=postgres acl=authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`
  - now: `FUNCTION _ride_json(p_ride public.user_rides) -> jsonb | lang=sql kind=f secdef=false vol=s strict=false par=u cfg=[] owner=postgres acl=authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`
- **CHANGED** `FUNCTION get_public_rides(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0) -> jsonb | lang=sql kind=f secdef=true vol=s strict=false par=u cfg=[search_path=public] owner=postgres acl=authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`
  - now: `FUNCTION get_public_rides(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0) -> jsonb | lang=sql kind=f secdef=true vol=s strict=false par=u cfg=[search_path=public] owner=postgres acl=authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`

## 20261112b05_rides_append_finish.sql

- **ADDED** `FUNCTION _ride_append_late(p_ride_id uuid, p_points jsonb) -> integer | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`
- **ADDED** `FUNCTION _ride_reopen(p_ride_id uuid, p_points jsonb) -> boolean | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`
- **CHANGED** `FUNCTION append_ride_track(p_ride_id uuid, p_points jsonb, p_max_speed_kmh numeric DEFAULT NULL::numeric) -> jsonb | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`
  - now: `FUNCTION append_ride_track(p_ride_id uuid, p_points jsonb, p_max_speed_kmh numeric DEFAULT NULL::numeric) -> jsonb | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`
- **CHANGED** `FUNCTION finish_user_ride(p_ride_id uuid, p_points jsonb DEFAULT NULL::jsonb, p_name text DEFAULT NULL::text) -> jsonb | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`
  - now: `FUNCTION finish_user_ride(p_ride_id uuid, p_points jsonb DEFAULT NULL::jsonb, p_name text DEFAULT NULL::text) -> jsonb | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`

## 20261112b06_rides_start_cron.sql

- **CHANGED** `COMMENT function close_stale_user_rides() md5=47929ed9cf8326caba0a1b6a52df78df`
  - now: `COMMENT function close_stale_user_rides() md5=8361068c14b3a48115a72dedb6c32d1f`
- **ADDED** `COMMENT function start_user_trip_from(p_booking_id uuid, p_first_ts double precision) md5=917a9ccc5523e6a7de188ebca1202e41`
- **ADDED** `FUNCTION _ride_reopen_parked(p_uid uuid, p_booking_id uuid, p_adopt boolean) -> uuid | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`
- **ADDED** `FUNCTION _ride_start_trip(p_uid uuid, p_booking_id uuid, p_first_ts double precision) -> jsonb | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`
- **ADDED** `FUNCTION _ride_trip_json(p_r public.user_rides, p_resumed boolean, p_now timestamp with time zone) -> jsonb | lang=sql kind=f secdef=false vol=s strict=false par=u cfg=[search_path=public] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`
- **CHANGED** `FUNCTION admin_booking_live_ride(p_booking_id uuid) -> jsonb | lang=plpgsql kind=f secdef=true vol=s strict=false par=u cfg=[search_path=public] owner=postgres acl=authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`
  - now: `FUNCTION admin_booking_live_ride(p_booking_id uuid) -> jsonb | lang=plpgsql kind=f secdef=true vol=s strict=false par=u cfg=[search_path=public] owner=postgres acl=authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`
- **CHANGED** `FUNCTION close_stale_user_rides() -> jsonb | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`
  - now: `FUNCTION close_stale_user_rides() -> jsonb | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`
- **CHANGED** `FUNCTION start_user_ride(p_booking_id uuid DEFAULT NULL::uuid, p_lat double precision DEFAULT NULL::double precision, p_lng double precision DEFAULT NULL::double precision) -> jsonb | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`
  - now: `FUNCTION start_user_ride(p_booking_id uuid DEFAULT NULL::uuid, p_lat double precision DEFAULT NULL::double precision, p_lng double precision DEFAULT NULL::double precision) -> jsonb | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`
- **ADDED** `FUNCTION start_user_trip(p_booking_id uuid) -> jsonb | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`
- **ADDED** `FUNCTION start_user_trip_from(p_booking_id uuid, p_first_ts double precision) -> jsonb | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`
- Data written by the file itself (outside function bodies): `user_rides (data fix: booking_id detached from gear-only bookings)`
## 20261112b07_rides_trip_group.sql

- **ADDED** `COMMENT function set_user_rides_trip(p_items jsonb) md5=961bc1029bff2ed554a5d50342a08c41`
- **ADDED** `FUNCTION set_user_rides_trip(p_items jsonb) -> jsonb | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public] owner=postgres acl=authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres`

## 20261112b08_rides_backfill.sql

No schema change (data only). Writes rows of: `user_rides (bounded backfill of pause statistics on closed legacy rides; temporary pg_temp function created and dropped)`.


## 20261112c01_velin_rating_handled.sql

- **ADDED** `COLUMN booking_rating_reviews.booking_id uuid NOT NULL`
- **ADDED** `COLUMN booking_rating_reviews.handled_at timestamp with time zone NOT NULL DEFAULT now()`
- **ADDED** `COLUMN booking_rating_reviews.handled_by uuid DEFAULT auth.uid()`
- **ADDED** `COLUMN booking_rating_reviews.note text`
- **ADDED** `COLUMN booking_rating_reviews.rated_at_seen timestamp with time zone`
- **ADDED** `CONSTRAINT booking_rating_reviews booking_rating_reviews_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id) ON DELETE CASCADE`
- **ADDED** `CONSTRAINT booking_rating_reviews booking_rating_reviews_handled_by_fkey FOREIGN KEY (handled_by) REFERENCES public.admin_users(id) ON DELETE SET NULL`
- **ADDED** `CONSTRAINT booking_rating_reviews booking_rating_reviews_note_check CHECK (((note IS NULL) OR (char_length(note) <= 2000)))`
- **ADDED** `CONSTRAINT booking_rating_reviews booking_rating_reviews_pkey PRIMARY KEY (booking_id)`
- **ADDED** `FUNCTION _booking_rating_reviews_stamp() -> trigger | lang=plpgsql kind=f secdef=false vol=v strict=false par=u cfg=[search_path=public, pg_temp] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`
- **ADDED** `INDEX public.booking_rating_reviews CREATE UNIQUE INDEX booking_rating_reviews_pkey ON public.booking_rating_reviews USING btree (booking_id)`
- **ADDED** `POLICY public.booking_rating_reviews booking_rating_reviews_admin_all PERMISSIVE ALL to=authenticated using=public.is_admin() check=public.is_admin()`
- **ADDED** `PUBLICATION supabase_realtime public.booking_rating_reviews`
- **ADDED** `RELATION public.booking_rating_reviews kind=r owner=postgres acl=authenticated=arwd/postgres,postgres=arwdDxt/postgres,service_role=arwdDxt/postgres opts=`
- **ADDED** `RLS public.booking_rating_reviews enabled=true forced=false`
- **ADDED** `TRIGGER public.booking_rating_reviews trg_booking_rating_reviews_stamp enabled=O | CREATE TRIGGER trg_booking_rating_reviews_stamp BEFORE INSERT OR UPDATE ON public.booking_rating_reviews FOR EACH ROW EXECUTE FUNCTION public._booking_rating_reviews_stamp()`

## 20261112c02_booking_rating_guard.sql

- **ADDED** `COMMENT function _bookings_rating_guard() md5=c8b473a754f14444bbe07300a1eaf943`
- **ADDED** `FUNCTION _bookings_rating_guard() -> trigger | lang=plpgsql kind=f secdef=false vol=v strict=false par=u cfg=[search_path=public, pg_temp] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`
- **ADDED** `TRIGGER public.bookings trg_bookings_rating_guard enabled=O | CREATE TRIGGER trg_bookings_rating_guard BEFORE UPDATE OF rating, rated_at ON public.bookings FOR EACH ROW EXECUTE FUNCTION public._bookings_rating_guard()`

## 20261112c03_messages_bump_thread.sql

- **ADDED** `COMMENT function _messages_bump_thread() md5=51146d9de2fe27624ad01cc438974bb5`
- **ADDED** `FUNCTION _messages_bump_thread() -> trigger | lang=plpgsql kind=f secdef=true vol=v strict=false par=u cfg=[search_path=public, pg_temp] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`
- **ADDED** `TRIGGER public.messages trg_messages_bump_thread enabled=O | CREATE TRIGGER trg_messages_bump_thread AFTER INSERT ON public.messages FOR EACH ROW EXECUTE FUNCTION public._messages_bump_thread()`

## 20261112c04_feature_flag_app_v2_ui.sql

No schema change (data only). Writes rows of: `feature_flags (INSERT app_v2_ui = true, ON CONFLICT DO NOTHING)`.


## 20261112t01_owner_texts_cms_return_1.sql

No schema change (data only). Writes rows of: `cms_variables`.


## 20261112t02_owner_texts_cms_return_2.sql

No schema change (data only). Writes rows of: `cms_variables`.


## 20261112t03_owner_texts_cms_pickup_1.sql

No schema change (data only). Writes rows of: `cms_variables`.


## 20261112t04_owner_texts_cms_pickup_2.sql

No schema change (data only). Writes rows of: `cms_variables`.


## 20261112t05_owner_texts_cms_pickup_3.sql

No schema change (data only). Writes rows of: `cms_variables`.


## 20261112t06_owner_texts_cms_home_app.sql

No schema change (data only). Writes rows of: `cms_variables`.


## 20261112t07_owner_texts_faq_fuel.sql

No schema change (data only). Writes rows of: `faq_items`.


## 20261112t08_owner_texts_faq_branches_1.sql

No schema change (data only). Writes rows of: `faq_items`.


## 20261112t09_owner_texts_faq_branches_2.sql

No schema change (data only). Writes rows of: `faq_items`.


## 20261112t10_owner_texts_faq_branches_3.sql

No schema change (data only). Writes rows of: `faq_items`.


## 20261112t11_owner_texts_faq_app.sql

No schema change (data only). Writes rows of: `faq_items`.


## 20261112t12_owner_texts_overlay_dokumenty.sql

No schema change (data only). Writes rows of: `app_settings`.


## 20261112t13_owner_texts_overlay_vraceni_pujcovna.sql

No schema change (data only). Writes rows of: `app_settings`.


## 20261112t14_owner_texts_overlay_vraceni_jinde.sql

No schema change (data only). Writes rows of: `app_settings`.


## 20261112t15_owner_texts_overlay_postup.sql

No schema change (data only). Writes rows of: `app_settings`.


## 20261112t16_owner_texts_overlay_pristaveni_vyzvednuti.sql

No schema change (data only). Writes rows of: `app_settings`.


## 20261112t17_owner_texts_overlay_home_pujcovna.sql

No schema change (data only). Writes rows of: `app_settings`.


## 20261112t18_owner_texts_layout_1.sql

No schema change (data only). Writes rows of: `cms_variables`.


## 20261112t19_owner_texts_layout_2.sql

No schema change (data only). Writes rows of: `cms_variables`.


## 20261112t20_owner_texts_blog_app.sql

No schema change (data only). Writes rows of: `cms_pages`.


## 20261112t21_owner_texts_ai_policies.sql

No schema change (data only). Writes rows of: `app_settings`.


## 20261112t22_owner_texts_banner.sql

No schema change (data only). Writes rows of: `app_settings`.


## 20261112t23_owner_texts_pobocky_steps.sql

No schema change (data only). Writes rows of: `cms_variables`.


## 20261112t24_owner_texts_pobocky_preklady_1.sql

No schema change (data only). Writes rows of: `cms_variables`.


## 20261112t25_owner_texts_pobocky_preklady_2.sql

No schema change (data only). Writes rows of: `cms_variables`.


## 20261112t26_owner_texts_pobocky_preklady_3.sql

No schema change (data only). Writes rows of: `cms_variables`.


## 20261112t27_owner_texts_pobocky_preklady_4.sql

No schema change (data only). Writes rows of: `cms_variables`.


## 20261112t28_owner_texts_pobocky_preklady_5.sql

No schema change (data only). Writes rows of: `cms_variables`.


## 20261112t29_owner_texts_pobocky_preklady_6.sql

No schema change (data only). Writes rows of: `cms_variables`.


## 20261112t30_owner_texts_pobocky_preklady_7.sql

No schema change (data only). Writes rows of: `cms_variables`.


## 20261112t31_owner_texts_gate_procedure.sql

- **CHANGED** `FUNCTION _gate_procedure_msg(p_gate text, p_locker_door integer, p_has_gear boolean) -> text | lang=sql kind=f secdef=false vol=i strict=false par=u cfg=[] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`
  - now: `FUNCTION _gate_procedure_msg(p_gate text, p_locker_door integer, p_has_gear boolean) -> text | lang=sql kind=f secdef=false vol=i strict=false par=u cfg=[] owner=postgres acl=postgres=X/postgres,service_role=X/postgres`

## 20261112t32_owner_texts_email_templates.sql

No schema change (data only). Writes rows of: `email_templates`.


## 20261112u01_qa_faq_review_google_only.sql

No schema change (data only). Writes rows of: `faq_items`.


## 20261112u02_qa_translation_fixes.sql

No schema change (data only). Writes rows of: `cms_pages`, `cms_variables`, `faq_items`, `motorcycles`.


## 20261112u03_qa_texts_branches.sql

No schema change (data only). Writes rows of: `app_settings`, `cms_pages`, `cms_variables`.


## 20261112u04_qa_vop_stale_translations.sql

No schema change (data only). Writes rows of: `document_templates`.


## 20261112u05_qa_vop_footer_address.sql

No schema change (data only). Writes rows of: `document_templates`.


## 20261112u06_qa_contract_stale_translations.sql

No schema change (data only). Writes rows of: `document_templates`.


## 20261112u07_qa_uk_texts.sql

No schema change (data only). Writes rows of: `cms_variables`, `custom_documents`, `products`.


## 20261112u08_qa_faq_uk_1.sql

No schema change (data only). Writes rows of: `faq_items`.


## 20261112u09_qa_faq_uk_2.sql

No schema change (data only). Writes rows of: `faq_items`.


## 20261112u10_qa_moto_translations.sql

No schema change (data only). Writes rows of: `motorcycles`.


## 20261112u11_qa_nl_wrong_language.sql

No schema change (data only). Writes rows of: `cms_variables`, `motorcycles`.


## 20261112u12_qa_blog_top10_nl.sql

No schema change (data only). Writes rows of: `cms_pages`.


## 20261112u13_web_editrez_h1_terms.sql

No schema change (data only). Writes rows of: `cms_variables`.


## 20261112u14_web_blog_slug_p.sql

No schema change (data only). Writes rows of: `cms_pages`.


## Notes for the STATE documentation (changes that are easy to miss in the lines above)

- **a03, a04 — overloads replaced, not added.** `split_booking_moto_swap` loses its 6-argument form and `apply_paid_gear_change` its 2-argument form; each now exists only once, with the extra parameters defaulted (old named calls still resolve). ACLs are unchanged against live.
- **a02, a04 — `SET search_path TO 'public'` added to three live SECURITY DEFINER functions** that had no `SET` config live: `auto_cancel_expired_pending()`, `restore_vouchers_on_cancel()`, `trg_send_booking_modified_email()`. This is stated in the file headers (a02 line 55, a04 line 39). Their bodies call `net.http_post` schema-qualified and use no other non-public object unqualified (checked by grep of the deployed bodies), so behaviour is unchanged. Owner and ACL are identical to live.
- **a05 — the unique index is conditional.** It is created only when live `invoices` has no duplicate live credit notes per `stripe_refund_id`; otherwise the file logs a WARNING and the index is missing (deploy log must be read).
- **a07 — `_guard_customer_booking_pricing()` ACL** = postgres, service_role, anon, authenticated (PUBLIC revoked), the same as its live sibling `_guard_customer_booking_status()`.
- **b02 — `_ride_stats(jsonb)` changes class:** IMMUTABLE/INVOKER/no config live → STABLE SECURITY DEFINER with `search_path=public`; `_ride_track_cap` changes language sql → plpgsql and gains `search_path=public`. Signatures and ACLs unchanged.
- **c01 — new table `booking_rating_reviews`** with RLS (one admin policy), grants authenticated S/I/U/D only (no anon), realtime publication membership added by a guarded DO block.
- **No cron job, view, enum, sequence, bucket or default-privilege change** anywhere in the bundle.
- **Data effect on realistic rows** (seeded with the live REST rows of 2026-11-12, rows whose content changed after the first deploy): cms_variables 112, faq_items 79, app_settings 57, motorcycles 7, cms_pages 6, email_templates 5 (synthetic), custom_documents 3, document_templates 2, products 2, feature_flags 2 rows inserted (`ride_autopause`, `app_v2_ui`). The second run changed no row.
