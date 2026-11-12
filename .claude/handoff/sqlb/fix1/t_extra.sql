\set ON_ERROR_STOP 1
SET client_min_messages = warning;
BEGIN;
SET LOCAL session_replication_role = replica;
INSERT INTO admin_users (id, email, role) VALUES ('d1000000-0000-0000-0000-0000000000d1','x1@example.invalid','superadmin') ON CONFLICT DO NOTHING;
INSERT INTO bookings (id, user_id, moto_id, branch_id, start_date, end_date, status, payment_status, total_price, booking_source)
VALUES ('cc000000-0000-0000-0000-00000000f001','a0000000-0000-0000-0000-00000000000a','e0000000-0000-0000-0000-00000000000e','f0000000-0000-0000-0000-00000000000f', current_date+20, current_date+21,'pending','unpaid',2000,'app'),
       ('cc000000-0000-0000-0000-00000000f002','a0000000-0000-0000-0000-00000000000a','e0000000-0000-0000-0000-00000000000e','f0000000-0000-0000-0000-00000000000f', current_date+40, current_date+41,'reserved','paid',2000,'app');
INSERT INTO booking_rating_reviews(booking_id, handled_by) VALUES ('cc000000-0000-0000-0000-00000000f002','d1000000-0000-0000-0000-0000000000d1');
SET LOCAL session_replication_role = origin;
SAVEPOINT s1;
-- customer cancels own pending booking the way the app does (cancelled_by_source 'customer')
SELECT public.t_login('a0000000-0000-0000-0000-00000000000a');
SET LOCAL ROLE authenticated;
UPDATE bookings SET status='cancelled', cancelled_at=now(), cancelled_by_source='customer', cancellation_reason='x' WHERE id='cc000000-0000-0000-0000-00000000f001';
SELECT 'cancel', status, cancelled_by_source FROM bookings WHERE id='cc000000-0000-0000-0000-00000000f001';
RESET ROLE;
-- admin d1 deletes own admin row: FK SET NULL must keep NULL, no FK error
SELECT public.t_login('d1000000-0000-0000-0000-0000000000d1');
SET LOCAL ROLE authenticated;
SELECT 'is_admin', public.is_admin();
RESET ROLE;
SET LOCAL ROLE postgres;
SELECT set_config('request.jwt.claims','{"sub":"d1000000-0000-0000-0000-0000000000d1","role":"authenticated"}',true);
DELETE FROM admin_users WHERE id='d1000000-0000-0000-0000-0000000000d1';
SELECT 'after_self_delete', handled_by FROM booking_rating_reviews WHERE booking_id='cc000000-0000-0000-0000-00000000f002';
-- admin d0 re-marks: handled_by stamped d0
SELECT set_config('request.jwt.claims','{"sub":"d0000000-0000-0000-0000-00000000000d","role":"authenticated"}',true);
SELECT set_config('request.jwt.claim.sub','d0000000-0000-0000-0000-00000000000d',true);
INSERT INTO booking_rating_reviews(booking_id, handled_at) VALUES ('cc000000-0000-0000-0000-00000000f002', now()) ON CONFLICT (booking_id) DO UPDATE SET handled_at = EXCLUDED.handled_at;
SELECT 'remark', handled_by FROM booking_rating_reviews WHERE booking_id='cc000000-0000-0000-0000-00000000f002';
ROLLBACK;
