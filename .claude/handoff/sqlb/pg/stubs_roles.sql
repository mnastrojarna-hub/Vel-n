-- Cluster-wide roles of the test rig (run once as the bootstrap superuser
-- supabase_admin; idempotent). Role ATTRIBUTES and MEMBERSHIPS follow the
-- standard Supabase platform setup - they are NOT in the snapshot (its
-- roles.sql only holds three statement_timeout settings, loaded separately).
\set ON_ERROR_STOP 1
select format('create role %I %s', r.name, r.attrs)
from (values
  ('postgres',                   'login nosuperuser createdb createrole replication bypassrls'),
  ('anon',                       'nologin'),
  ('authenticated',              'nologin'),
  ('service_role',               'nologin bypassrls'),
  ('authenticator',              'login noinherit'),
  ('dashboard_user',             'nologin createdb createrole replication'),
  ('pgbouncer',                  'login'),
  ('supabase_auth_admin',        'login noinherit createrole'),
  ('supabase_storage_admin',     'login noinherit createrole'),
  ('supabase_functions_admin',   'login noinherit createrole'),
  ('supabase_realtime_admin',    'nologin noinherit'),
  ('supabase_replication_admin', 'login replication'),
  ('supabase_read_only_user',    'login bypassrls'),
  ('supabase_etl_admin',         'login replication')
) as r(name, attrs)
where not exists (select 1 from pg_roles where rolname = r.name)
\gexec

-- memberships (GRANT of an existing membership is a no-op with a notice)
set client_min_messages = warning;
grant anon, authenticated, service_role to authenticator;
grant anon, authenticated, service_role to postgres with admin option;
grant authenticator to postgres with admin option;
grant authenticator to supabase_storage_admin;
grant supabase_realtime_admin to postgres;
grant pg_read_all_data, pg_signal_backend, pg_monitor to postgres with admin option;
grant pg_create_subscription to postgres;
grant pg_read_all_data to supabase_read_only_user;
-- RIG APPROXIMATION of supautils "policy_grants" / "drop_trigger_grants": on
-- Supabase the role postgres may CREATE/ALTER/DROP POLICY on storage.objects /
-- storage.buckets and CREATE/DROP TRIGGER on auth.users although the service
-- roles own those tables. Membership is the closest local equivalent. It is
-- BROADER than live: it also lets postgres ALTER TABLE / CREATE INDEX on auth.*
-- and storage.* tables, which live refuses - apply.sh prints a lint warning
-- for such statements.
grant supabase_storage_admin to postgres;
grant supabase_auth_admin to postgres;
-- supautils "privileged_role_allowed_configs" lets postgres set this on live.
grant set on parameter session_replication_role to postgres;

-- Supabase session defaults
alter role postgres       set search_path to "$user", public, extensions;
alter role supabase_admin set search_path to "$user", public, extensions;
alter role authenticator  set search_path to public, extensions;
alter role anon           set search_path to public, extensions;
alter role authenticated  set search_path to public, extensions;
alter role service_role   set search_path to public, extensions;
