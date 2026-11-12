-- ════════════════════════════════════════════════════════════════════
-- TEST-ONLY fake clock for the local rig. NEVER put any of this into a
-- migration. Loaded by "newdb.sh <db> --shim" or by hand:
--     psql.sh <db> -v ON_ERROR_STOP=1 < timeshim.sql
--
--   public.t_now()                  fake "now": GUC test.now, or the real
--                                   now() while test.now is not set
--   public.t_set(ts [, uid])        set the clock (session level) and, when
--                                   uid is given, the JWT subject
--                                   (request.jwt.claim.sub -> auth.uid());
--                                   uid NULL leaves the subject untouched
--   public.t_shim([regex [, tables]])
--        rewrite now() / CURRENT_TIMESTAMP / transaction_timestamp() /
--        statement_timestamp() / clock_timestamp() -> public.t_now() and
--        CURRENT_DATE -> (public.t_now())::date in every public plpgsql/sql
--        function whose NAME matches the regex (default '(ride|trip)'; the
--        trigger function set_updated_at is always included), and in the
--        column defaults of the listed tables (default: user_rides,
--        user_ride_points). Returns the number of rewritten functions.
--        RE-RUN after loading any draft (CREATE OR REPLACE restores now()).
--        t_shim('.') shims every public function.
--   public.t_login(uid [, role])    full PostgREST-like JWT context:
--        request.jwt.claims + request.jwt.claim.sub/.role (session level)
--   public.t_logout()               clear the JWT context
-- The rewritten bodies differ from live, so take sig.sh / defn.sh output
-- BEFORE calling t_shim(), or in a database without the shim.
-- ════════════════════════════════════════════════════════════════════
create or replace function public.t_now() returns timestamptz
language sql stable as $$
  select coalesce(nullif(current_setting('test.now', true), '')::timestamptz, pg_catalog.now())
$$;

create or replace function public.t_set(p_now timestamptz, p_uid uuid default null) returns void
language plpgsql as $$
begin
  perform set_config('test.now', coalesce(p_now::text, ''), false);
  if p_uid is not null then
    perform set_config('request.jwt.claim.sub', p_uid::text, false);
  end if;
end $$;

create or replace function public.t_login(p_uid uuid, p_role text default 'authenticated') returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), false);
  perform set_config('request.jwt.claim.role', p_role, false);
  perform set_config('request.jwt.claims',
    (jsonb_build_object('role', p_role) || case when p_uid is null then '{}'::jsonb
                                                else jsonb_build_object('sub', p_uid::text) end)::text, false);
end $$;

create or replace function public.t_logout() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', '', false);
  perform set_config('request.jwt.claim.role', '', false);
  perform set_config('request.jwt.claims', '', false);
end $$;

create or replace function public.t_shim_text(p text) returns text
language sql immutable as $$
  select regexp_replace(
           regexp_replace(p,
             '\m(now|transaction_timestamp|statement_timestamp|clock_timestamp)\s*\(\s*\)|\mcurrent_timestamp\M(\s*\(\s*\d*\s*\))?',
             'public.t_now()', 'gi'),
           '\mcurrent_date\M', '(public.t_now())::date', 'gi')
$$;

create or replace function public.t_shim(p_regex text default '(ride|trip)',
                                         p_tables text[] default array['user_rides', 'user_ride_points'])
returns integer language plpgsql as $$
declare r record; v_def text; v_new text; n integer := 0;
begin
  for r in
    select p.oid, p.proname from pg_proc p
      join pg_namespace ns on ns.oid = p.pronamespace
      join pg_language l on l.oid = p.prolang
     where ns.nspname = 'public' and p.prokind in ('f', 'p') and l.lanname in ('plpgsql', 'sql')
       and (p.proname ~ p_regex or p.proname = 'set_updated_at')
       and p.proname !~ '^t_(now|set|shim|shim_text|login|logout)$'
  loop
    v_def := pg_get_functiondef(r.oid);
    v_new := public.t_shim_text(v_def);
    if v_new is distinct from v_def then
      execute v_new;
      n := n + 1;
    end if;
  end loop;
  for r in
    select c.relname, a.attname, pg_get_expr(d.adbin, d.adrelid) as def
      from pg_attrdef d
      join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
      join pg_class c on c.oid = d.adrelid
      join pg_namespace ns on ns.oid = c.relnamespace
     where ns.nspname = 'public' and c.relname = any (p_tables) and a.attgenerated = ''
  loop
    v_new := public.t_shim_text(r.def);
    if v_new is distinct from r.def then
      execute format('alter table public.%I alter column %I set default %s', r.relname, r.attname, v_new);
    end if;
  end loop;
  return n;
end $$;
