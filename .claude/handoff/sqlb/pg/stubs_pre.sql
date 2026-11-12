-- Per-database stubs loaded BEFORE the live snapshot (as supabase_admin).
-- They stand in for Supabase platform pieces that the snapshot does not hold:
-- schema extensions (+ uuid-ossp, pgcrypto), pg_net (net.*), pg_cron (cron.*),
-- supabase_vault (vault.*), supabase_functions, graphql, publication
-- supabase_realtime. auth / storage / realtime come from schema_system.sql (real).
\set ON_ERROR_STOP 1
set client_min_messages = warning;

-- ── extensions ───────────────────────────────────────────────────────────
create schema extensions authorization postgres;
grant usage on schema extensions to public;
create extension "uuid-ossp" schema extensions;
create extension pgcrypto    schema extensions;

-- ── pg_net stub ──────────────────────────────────────────────────────────
-- Same signatures, owner, SECURITY DEFINER and grants as pg_net on Supabase.
-- Nothing is ever sent: a call is only recorded in net.http_request_queue
-- (inspect it in tests to assert "an e-mail / edge call was queued").
-- Like the real extension it fails on a NULL url (NOT NULL column).
create schema net authorization supabase_admin;
create table net.http_request_queue (
  id bigserial primary key,
  method text not null,
  url text not null,
  headers jsonb not null,
  body bytea,
  timeout_milliseconds integer not null,
  created timestamptz not null default clock_timestamp()
);
create table net._http_response (
  id bigint, status_code integer, content_type text, headers jsonb, content text,
  timed_out boolean, error_msg text, created timestamptz not null default now()
);
create function net.http_post(url text, body jsonb default '{}'::jsonb, params jsonb default '{}'::jsonb,
    headers jsonb default '{"Content-Type": "application/json"}'::jsonb, timeout_milliseconds integer default 5000)
  returns bigint language plpgsql security definer set search_path = net as $$
declare v_id bigint; v_ct text;
begin
  select value into v_ct from jsonb_each_text(coalesce(headers, '{}'::jsonb)) where lower(key) = 'content-type';
  if v_ct is null then raise exception 'Content-Type header must be "application/json"'; end if;
  if v_ct <> 'application/json' then raise exception 'Content-Type header must be "application/json"'; end if;
  insert into net.http_request_queue (method, url, headers, body, timeout_milliseconds)
  values ('POST', url, headers, convert_to(body::text, 'UTF8'), timeout_milliseconds) returning id into v_id;
  return v_id;
end $$;
create function net.http_get(url text, params jsonb default '{}'::jsonb, headers jsonb default '{}'::jsonb,
    timeout_milliseconds integer default 5000)
  returns bigint language plpgsql security definer set search_path = net as $$
declare v_id bigint;
begin
  insert into net.http_request_queue (method, url, headers, body, timeout_milliseconds)
  values ('GET', url, headers, null, timeout_milliseconds) returning id into v_id;
  return v_id;
end $$;
create function net.http_delete(url text, params jsonb default '{}'::jsonb, headers jsonb default '{}'::jsonb,
    timeout_milliseconds integer default 5000, body jsonb default null)
  returns bigint language plpgsql security definer set search_path = net as $$
declare v_id bigint;
begin
  insert into net.http_request_queue (method, url, headers, body, timeout_milliseconds)
  values ('DELETE', url, headers, convert_to(body::text, 'UTF8'), timeout_milliseconds) returning id into v_id;
  return v_id;
end $$;
revoke all on all functions in schema net from public;
grant usage on schema net to supabase_functions_admin, postgres, anon, authenticated, service_role;
grant execute on all functions in schema net to supabase_functions_admin, postgres, anon, authenticated, service_role;
grant all on all tables in schema net to postgres;
grant all on all sequences in schema net to postgres;

-- ── pg_cron stub ─────────────────────────────────────────────────────────
-- Jobs are only stored in cron.job, nothing ever runs. Behaviour copied from
-- pg_cron 1.6: schedule(name, ...) is an upsert by (jobname, username);
-- unschedule() of a job that does not exist RAISES AN ERROR (so an unguarded
-- unschedule in a migration is not idempotent - exactly as on live);
-- an invalid schedule string is rejected.
-- The table starts EMPTY: the live cron jobs are not part of the snapshot.
create schema cron authorization supabase_admin;
create sequence cron.jobid_seq;
create sequence cron.runid_seq;
create table cron.job (
  jobid bigint primary key default nextval('cron.jobid_seq'),
  schedule text not null,
  command text not null,
  nodename text not null default 'localhost',
  nodeport integer not null default 5432,
  database text not null default 'postgres',
  username text not null default current_user,
  active boolean not null default true,
  jobname text,
  constraint jobname_username_uniq unique (jobname, username)
);
create table cron.job_run_details (
  jobid bigint, runid bigint primary key default nextval('cron.runid_seq'), job_pid integer,
  database text, username text, command text, status text, return_message text,
  start_time timestamptz, end_time timestamptz
);
create function cron._check_schedule(p text) returns void language plpgsql as $$
begin
  if p is null then raise exception 'invalid schedule: (null)'; end if;
  if btrim(p) ~ '^[0-9]+ +seconds?$' then return; end if;
  if btrim(p) ~* '^(@(yearly|annually|monthly|weekly|daily|midnight|hourly))$' then return; end if;
  if btrim(p) ~* '^([0-9*/,\-]+) +([0-9*/,\-]+) +([0-9*/,\-$]+) +([0-9a-z*/,\-]+) +([0-9a-z*/,\-]+)$' then return; end if;
  raise exception 'invalid schedule: %', p using hint = 'Use cron format (e.g. 5 4 * * *), or interval format ''[1-59] seconds''';
end $$;
create function cron.schedule(job_name text, schedule text, command text) returns bigint
  language plpgsql as $$
declare v_id bigint;
begin
  perform cron._check_schedule(schedule);
  if job_name is null then raise exception 'job_name can not be NULL'; end if;
  if command is null then raise exception 'command can not be NULL'; end if;
  insert into cron.job (schedule, command, jobname, username) values (schedule, command, job_name, current_user)
  on conflict on constraint jobname_username_uniq
    do update set schedule = excluded.schedule, command = excluded.command
  returning jobid into v_id;
  return v_id;
end $$;
create function cron.schedule(schedule text, command text) returns bigint
  language plpgsql as $$
declare v_id bigint;
begin
  perform cron._check_schedule(schedule);
  insert into cron.job (schedule, command, username) values (schedule, command, current_user) returning jobid into v_id;
  return v_id;
end $$;
create function cron.schedule_in_database(job_name text, schedule text, command text, database text,
    username text default null, active boolean default true) returns bigint
  language plpgsql as $$
declare v_id bigint;
begin
  perform cron._check_schedule(schedule);
  insert into cron.job (schedule, command, jobname, database, username, active)
  values (schedule, command, job_name, database, coalesce(username, current_user), active)
  on conflict on constraint jobname_username_uniq
    do update set schedule = excluded.schedule, command = excluded.command,
                  database = excluded.database, active = excluded.active
  returning jobid into v_id;
  return v_id;
end $$;
create function cron.unschedule(job_name text) returns boolean
  language plpgsql as $$
begin
  delete from cron.job where jobname = job_name and username = current_user;
  if not found then raise exception 'could not find valid entry for job ''%''', job_name; end if;
  return true;
end $$;
create function cron.unschedule(job_id bigint) returns boolean
  language plpgsql as $$
begin
  delete from cron.job where jobid = job_id;
  if not found then raise exception 'could not find valid entry for job %', job_id; end if;
  return true;
end $$;
create function cron.alter_job(job_id bigint, schedule text default null, command text default null,
    database text default null, username text default null, active boolean default null) returns void
  language plpgsql as $$
begin
  if schedule is not null then perform cron._check_schedule(schedule); end if;
  update cron.job j set schedule = coalesce(alter_job.schedule, j.schedule),
                        command  = coalesce(alter_job.command, j.command),
                        database = coalesce(alter_job.database, j.database),
                        username = coalesce(alter_job.username, j.username),
                        active   = coalesce(alter_job.active, j.active)
   where j.jobid = job_id;
  if not found then raise exception 'could not find valid entry for job %', job_id; end if;
end $$;
grant usage on schema cron to postgres with grant option;
grant all on all tables in schema cron to postgres with grant option;
grant all on all sequences in schema cron to postgres with grant option;
grant execute on all functions in schema cron to postgres with grant option;

-- ── supabase_vault stub (not referenced by the public schema today) ──────
create schema vault authorization supabase_admin;
create table vault.secrets (
  id uuid primary key default gen_random_uuid(), name text unique, description text not null default '',
  secret text not null, key_id uuid, nonce bytea,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create view vault.decrypted_secrets as
  select id, name, description, secret, secret as decrypted_secret, key_id, nonce, created_at, updated_at from vault.secrets;
create function vault.create_secret(new_secret text, new_name text default null, new_description text default '',
    new_key_id uuid default null) returns uuid language sql as $$
  insert into vault.secrets (secret, name, description) values (new_secret, new_name, new_description) returning id $$;
grant usage on schema vault to postgres, service_role;
grant select, delete, truncate, references on vault.secrets, vault.decrypted_secrets to postgres, service_role;
grant execute on all functions in schema vault to postgres, service_role;

-- ── supabase_functions / graphql (empty shells) ──────────────────────────
create schema supabase_functions authorization supabase_admin;
grant usage on schema supabase_functions to postgres, anon, authenticated, service_role;
create schema graphql authorization supabase_admin;
