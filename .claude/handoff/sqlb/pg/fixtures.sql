-- ════════════════════════════════════════════════════════════════════
-- TEST-ONLY minimal fixtures for the local rig (never in a migration).
-- Loaded by "newdb.sh <db> --shim" or:  psql.sh <db> -v ON_ERROR_STOP=1 < fixtures.sql
-- Idempotent. Inserted with session_replication_role = replica, i.e. WITHOUT
-- triggers (auth.users -> handle_new_auth_user etc.) and without FK checks.
--   users   a0000000-0000-0000-0000-00000000000a  rental customer (new app)
--           b0000000-0000-0000-0000-00000000000b  own-bike rider (new app)
--           c0000000-0000-0000-0000-00000000000c  customer on app 4.1.3
--           e1000000-0000-0000-0000-0000000000e1, e2000000-0000-0000-0000-0000000000e2  extras
--   admin   d0000000-0000-0000-0000-00000000000d  superadmin in admin_users (+ auth user, profile)
--   branch  f0000000-0000-0000-0000-00000000000f  "Testovací pobočka"
--   moto    e0000000-0000-0000-0000-00000000000e  Honda CB 500 X (active, on the branch)
--   app_settings supabase_url / service_role_key = dummies, so that functions
--           calling edge functions reach the pg_net stub (rows appear in
--           net.http_request_queue) instead of skipping with a warning.
-- Bookings are NOT part of the fixtures: insert them per scenario with
-- session_replication_role = replica (bookings has many side-effect triggers).
-- ════════════════════════════════════════════════════════════════════
set session_replication_role = replica;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select u.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', u.email, '',
       timestamptz '2026-01-01 00:00+00', '{"provider":"email","providers":["email"]}'::jsonb,
       jsonb_build_object('full_name', u.name), timestamptz '2026-01-01 00:00+00', timestamptz '2026-01-01 00:00+00'
from (values
  ('a0000000-0000-0000-0000-00000000000a'::uuid, 'rental@test.cz', 'Test Rental'),
  ('b0000000-0000-0000-0000-00000000000b'::uuid, 'ownbike@test.cz', 'Test Ownbike'),
  ('c0000000-0000-0000-0000-00000000000c'::uuid, 'old413@test.cz', 'Test Old413'),
  ('e1000000-0000-0000-0000-0000000000e1'::uuid, 'extra1@test.cz', 'Test Extra1'),
  ('e2000000-0000-0000-0000-0000000000e2'::uuid, 'extra2@test.cz', 'Test Extra2'),
  ('d0000000-0000-0000-0000-00000000000d'::uuid, 'admin@test.cz', 'Test Admin')
) as u(id, email, name)
on conflict (id) do nothing;

insert into public.profiles (id, full_name, email)
select id, raw_user_meta_data->>'full_name', email from auth.users
 where email like '%@test.cz' and id::text ~ '^(a0|b0|c0|d0|e1|e2)0'
on conflict (id) do nothing;

insert into public.admin_users (id, email, name, role, active)
values ('d0000000-0000-0000-0000-00000000000d', 'admin@test.cz', 'Test Admin', 'superadmin', true)
on conflict (id) do nothing;

insert into public.branches (id, name, address, city, active)
values ('f0000000-0000-0000-0000-00000000000f', 'Testovací pobočka', 'Testovací 1', 'Brno', true)
on conflict (id) do nothing;

insert into public.motorcycles (id, brand, model, category, status, branch_id)
values ('e0000000-0000-0000-0000-00000000000e', 'Honda', 'CB 500 X', 'adventure', 'active',
        'f0000000-0000-0000-0000-00000000000f')
on conflict (id) do nothing;

insert into public.app_settings (key, value) values
  ('supabase_url', to_jsonb('http://edge.invalid'::text)),
  ('service_role_key', to_jsonb('rig-dummy-service-role-key'::text))
on conflict (key) do nothing;

reset session_replication_role;
