-- Stable, sorted, one-line-per-object signature of the database (see sig.sh).
\pset format unaligned
\pset tuples_only on
\pset pager off
set search_path = pg_catalog;
set client_min_messages = warning;
with fn as (
  select p.oid, n.nspname, p.proname,
         pg_get_function_identity_arguments(p.oid) as iargs,
         pg_get_function_arguments(p.oid) as args,
         pg_get_function_result(p.oid) as res, l.lanname, p.prokind, p.prosecdef, p.provolatile, p.proisstrict,
         p.proparallel, p.proleakproof, coalesce(array_to_string(p.proconfig, ','), '') as cfg,
         pg_get_userbyid(p.proowner) as owner,
         coalesce((select string_agg(a::text, ',' order by a::text) from unnest(p.proacl) a), '(default)') as acl,
         md5(p.prosrc) as body
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace join pg_language l on l.oid = p.prolang
   where n.nspname = 'public'
)
select regexp_replace(line, '\s+', ' ', 'g') as line from (
  select 'FUNCTION ' || proname || '(' || args || ') -> ' || coalesce(res, '(procedure)')
         || ' | lang=' || lanname || ' kind=' || prokind::text || ' secdef=' || prosecdef || ' vol=' || provolatile::text
         || ' strict=' || proisstrict || ' par=' || proparallel::text || ' cfg=[' || cfg || '] owner=' || owner
         || ' acl=' || acl || ' body=' || body as line from fn
  union all
  select 'COMMENT function ' || proname || '(' || iargs || ') md5=' || md5(d.description)
    from fn join pg_description d on d.objoid = fn.oid and d.classoid = 'pg_proc'::regclass and d.objsubid = 0
  union all
  select 'TRIGGER ' || n.nspname || '.' || c.relname || ' ' || t.tgname || ' enabled=' || t.tgenabled::text || ' | '
         || pg_get_triggerdef(t.oid)
    from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
   where not t.tgisinternal and n.nspname in ('public', 'auth', 'storage')
  union all
  select 'POLICY ' || schemaname || '.' || tablename || ' ' || quote_ident(policyname) || ' ' || permissive || ' ' || cmd
         || ' to=' || array_to_string(roles, ',') || ' using=' || coalesce(qual, '-') || ' check=' || coalesce(with_check, '-')
    from pg_policies where schemaname in ('public', 'storage', 'auth')
  union all
  select 'RLS ' || n.nspname || '.' || c.relname || ' enabled=' || c.relrowsecurity || ' forced=' || c.relforcerowsecurity
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p')
  union all
  select 'INDEX ' || schemaname || '.' || tablename || ' ' || indexdef
    from pg_indexes where schemaname = 'public'
  union all
  select 'RELATION ' || n.nspname || '.' || c.relname || ' kind=' || c.relkind::text || ' owner=' || pg_get_userbyid(c.relowner)
         || ' acl=' || coalesce((select string_agg(a::text, ',' order by a::text) from unnest(c.relacl) a), '(default)')
         || ' opts=' || coalesce(array_to_string(c.reloptions, ','), '')
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm', 'S', 'f')
  union all
  select 'COLUMN ' || c.relname || '.' || a.attname || ' ' || format_type(a.atttypid, a.atttypmod)
         || case when a.attnotnull then ' NOT NULL' else '' end
         || case when a.attgenerated <> '' then ' GENERATED(' || coalesce(pg_get_expr(d.adbin, d.adrelid), '') || ')'
                 when d.adbin is not null then ' DEFAULT ' || pg_get_expr(d.adbin, d.adrelid) else '' end
         || case when a.attidentity <> '' then ' IDENTITY=' || a.attidentity::text else '' end
         || case when a.attacl is not null then ' colacl=' || (select string_agg(x::text, ',' order by x::text) from unnest(a.attacl) x) else '' end
    from pg_attribute a join pg_class c on c.oid = a.attrelid join pg_namespace n on n.oid = c.relnamespace
    left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
   where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm') and a.attnum > 0 and not a.attisdropped
  union all
  select 'CONSTRAINT ' || c.relname || ' ' || con.conname || ' ' || pg_get_constraintdef(con.oid)
         || case when con.convalidated then '' else ' [NOT VALIDATED]' end
    from pg_constraint con join pg_class c on c.oid = con.conrelid join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
  union all
  select 'VIEW ' || c.relname || ' opts=' || coalesce(array_to_string(c.reloptions, ','), '') || ' md5=' || md5(pg_get_viewdef(c.oid))
    from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind in ('v', 'm')
  union all
  select 'TYPE ' || t.typname || ' ' || case t.typtype when 'e' then 'enum(' ||
           (select string_agg(e.enumlabel, ',' order by e.enumsortorder) from pg_enum e where e.enumtypid = t.oid) || ')'
           else 'typtype=' || t.typtype::text end
    from pg_type t join pg_namespace n on n.oid = t.typnamespace
   where n.nspname = 'public' and t.typtype in ('e', 'd', 'r')
  union all
  select 'DEFACL ' || pg_get_userbyid(d.defaclrole) || ' ' || coalesce(n.nspname, '(all)') || ' ' || d.defaclobjtype::text || ' '
         || (select string_agg(a::text, ',' order by a::text) from unnest(d.defaclacl) a)
    from pg_default_acl d left join pg_namespace n on n.oid = d.defaclnamespace
  union all
  select 'PUBLICATION ' || pubname || ' ' || schemaname || '.' || tablename from pg_publication_tables
  union all
  select 'CRON ' || coalesce(jobname, '(unnamed #' || jobid || ')') || ' [' || schedule || '] active=' || active || ' | '
         || regexp_replace(command, '\s+', ' ', 'g')
    from cron.job
  union all
  select 'BUCKET ' || id || ' public=' || public from storage.buckets
) s order by regexp_replace(line, '\s+', ' ', 'g') collate "C";
