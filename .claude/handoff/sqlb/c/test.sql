\set ON_ERROR_STOP 1
\pset pager off
begin;
create temp table r(n serial, name text, ok boolean, info text);
grant all on r to public; grant all on sequence r_n_seq to public;

-- fixtury (bez triggerů / FK kontrol), vše se na konci vrátí ROLLBACKEM
set local session_replication_role = replica;
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
select u.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', u.email, '', now(), now()
  from (values ('dc000000-0000-0000-0000-0000000000dc'::uuid, 't-admin@example.invalid'),
               ('cc000000-0000-0000-0000-0000000000cc'::uuid, 't-cust@example.invalid'),
               ('dd000000-0000-0000-0000-0000000000dd'::uuid, 't-other@example.invalid')) u(id, email)
on conflict (id) do nothing;
insert into public.profiles (id, email) select id, email from auth.users where email like 't-%@example.invalid' on conflict (id) do nothing;
insert into public.admin_users (id, email, name, role, active)
  values ('dc000000-0000-0000-0000-0000000000dc','t-admin@example.invalid','T admin','superadmin',true) on conflict (id) do nothing;
-- zákazník cc…, rezervace: done (completed), past (reserved, konec včera), today (konec dnes), future, cancelled, sos
insert into public.bookings (id, user_id, start_date, end_date, status, ended_by_sos) values
 ('c1000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-0000000000cc', now()-interval '5 day', now()-interval '3 day','completed',false),
 ('c1000000-0000-0000-0000-000000000002','cc000000-0000-0000-0000-0000000000cc', now()-interval '5 day', now()-interval '1 day','active',false),
 ('c1000000-0000-0000-0000-000000000003','cc000000-0000-0000-0000-0000000000cc', now()-interval '2 day', (date_trunc('day', now() at time zone 'Europe/Prague') + interval '12 hours') at time zone 'Europe/Prague','active',false),
 ('c1000000-0000-0000-0000-000000000007','cc000000-0000-0000-0000-0000000000cc', now()-interval '2 day', (date_trunc('day', now() at time zone 'Europe/Prague') + interval '1 day 12 hours') at time zone 'Europe/Prague','active',false),
 ('c1000000-0000-0000-0000-000000000004','cc000000-0000-0000-0000-0000000000cc', now()+interval '5 day', now()+interval '7 day','reserved',false),
 ('c1000000-0000-0000-0000-000000000005','cc000000-0000-0000-0000-0000000000cc', now()-interval '5 day', now()-interval '3 day','cancelled',false),
 ('c1000000-0000-0000-0000-000000000006','cc000000-0000-0000-0000-0000000000cc', now()-interval '1 day', now()+interval '5 day','active',true);
insert into public.message_threads (id, customer_id, channel, status, subject, last_message_at) values
 ('c2000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-0000000000cc','app','closed','Rezervace #C1000000', now()-interval '30 day'),
 ('c2000000-0000-0000-0000-000000000002','dd000000-0000-0000-0000-0000000000dd','app','open','cizí', now()-interval '30 day');
set local session_replication_role = origin;

-- ========== c02: hodnocení jako zákazník ==========
select set_config('request.jwt.claims','{"sub":"cc000000-0000-0000-0000-0000000000cc","role":"authenticated"}',true),
       set_config('request.jwt.claim.sub','cc000000-0000-0000-0000-0000000000cc',true);
set local role authenticated;
update public.bookings set rating = 5, rated_at = '2001-01-01T00:00:00' where id = 'c1000000-0000-0000-0000-000000000001';
insert into r(name, ok, info) select 'c02 completed: rating uložen, rated_at = now() serveru', rating = 5 and rated_at = now(), rating||' '||rated_at from public.bookings where id='c1000000-0000-0000-0000-000000000001';
update public.bookings set rated_at = '2001-01-01T00:00:00' where id = 'c1000000-0000-0000-0000-000000000001';
insert into r(name, ok, info) select 'c02 změna jen rated_at zahozena', rated_at = now(), rated_at::text from public.bookings where id='c1000000-0000-0000-0000-000000000001';
update public.bookings set rating = 2 where id = 'c1000000-0000-0000-0000-000000000002';
insert into r(name, ok, info) select 'c02 konec nájmu včera (active): povoleno', rating = 2 and rated_at = now(), rating||'' from public.bookings where id='c1000000-0000-0000-0000-000000000002';
update public.bookings set rating = 3 where id = 'c1000000-0000-0000-0000-000000000003';
insert into r(name, ok, info) select 'c02 konec nájmu dnes (Praha): povoleno', rating = 3, coalesce(rating::text,'null') from public.bookings where id='c1000000-0000-0000-0000-000000000003';
update public.bookings set rating = 4 where id = 'c1000000-0000-0000-0000-000000000007';
insert into r(name, ok, info) select 'c02 konec nájmu zítra (Praha, active): tiše zahozeno', rating is null, coalesce(rating::text,'null') from public.bookings where id='c1000000-0000-0000-0000-000000000007';
update public.bookings set rating = 4, rated_at = now() where id = 'c1000000-0000-0000-0000-000000000004';
insert into r(name, ok, info) select 'c02 budoucí rezervace: tiše zahozeno', rating is null and rated_at is null, coalesce(rating::text,'null') from public.bookings where id='c1000000-0000-0000-0000-000000000004';
update public.bookings set rating = 1 where id = 'c1000000-0000-0000-0000-000000000005';
insert into r(name, ok, info) select 'c02 zrušená: tiše zahozeno', rating is null, coalesce(rating::text,'null') from public.bookings where id='c1000000-0000-0000-0000-000000000005';
update public.bookings set rating = 1 where id = 'c1000000-0000-0000-0000-000000000006';
insert into r(name, ok, info) select 'c02 ended_by_sos: povoleno', rating = 1, coalesce(rating::text,'null') from public.bookings where id='c1000000-0000-0000-0000-000000000006';
update public.bookings set rating = null where id = 'c1000000-0000-0000-0000-000000000006';
insert into r(name, ok, info) select 'c02 smazání hodnocení: rated_at NULL', rating is null and rated_at is null, coalesce(rated_at::text,'null') from public.bookings where id='c1000000-0000-0000-0000-000000000006';

-- ========== c01: zákazník tabulku nevidí ani nezapíše ==========
insert into r(name, ok) select 'c01 zákazník SELECT = 0 řádků', count(*) = 0 from public.booking_rating_reviews;
do $$ begin
  begin
    insert into public.booking_rating_reviews(booking_id) values ('c1000000-0000-0000-0000-000000000001');
    insert into r(name, ok, info) values ('c01 zákazník INSERT odmítnut', false, 'prošlo');
  exception when insufficient_privilege then
    insert into r(name, ok, info) values ('c01 zákazník INSERT odmítnut', true, sqlerrm);
  end;
end $$;

-- ========== c03: zpráva zákazníka posune vlákno ==========
insert into public.messages(thread_id, content, direction) values ('c2000000-0000-0000-0000-000000000001','co zlepšit','customer');
reset role;
insert into r(name, ok, info) select 'c03 zpráva posunula last_message_at na now(), status beze změny', last_message_at = now() and status = 'closed', last_message_at||' '||status from public.message_threads where id='c2000000-0000-0000-0000-000000000001';
set local role authenticated;
insert into public.messages(thread_id, content, direction, created_at) values ('c2000000-0000-0000-0000-000000000001','z budoucnosti','customer', now()+interval '10 day');
insert into public.messages(thread_id, content, direction, created_at) values ('c2000000-0000-0000-0000-000000000001','stará','customer', now()-interval '100 day');
reset role;
insert into r(name, ok, info) select 'c03 budoucí created_at oříznut na now(), starší nevrací zpět', last_message_at = now(), last_message_at::text from public.message_threads where id='c2000000-0000-0000-0000-000000000001';
set local role authenticated;
do $$ begin
  begin
    insert into public.messages(thread_id, content, direction) values ('c2000000-0000-0000-0000-000000000002','cizí vlákno','customer');
    insert into r(name, ok, info) values ('c03 cizí vlákno dál odmítnuto RLS', false, 'prošlo');
  exception when insufficient_privilege then
    insert into r(name, ok, info) values ('c03 cizí vlákno dál odmítnuto RLS', true, sqlerrm);
  end;
end $$;
reset role;
insert into r(name, ok, info) select 'c03 cizí vlákno neposunuto', last_message_at < now() - interval '29 day', last_message_at::text from public.message_threads where id='c2000000-0000-0000-0000-000000000002';

-- ========== anon ==========
set local role anon;
do $$ begin
  begin
    perform 1 from public.booking_rating_reviews;
    insert into r(name, ok, info) values ('c01 anon SELECT odmítnut', false, 'prošlo');
  exception when insufficient_privilege then
    insert into r(name, ok, info) values ('c01 anon SELECT odmítnut', true, sqlerrm);
  end;
end $$;
reset role;

-- ========== admin (Velín) ==========
select set_config('request.jwt.claims','{"sub":"dc000000-0000-0000-0000-0000000000dc","role":"authenticated"}',true),
       set_config('request.jwt.claim.sub','dc000000-0000-0000-0000-0000000000dc',true);
set local role authenticated;
update public.bookings set rating = 4, rated_at = '2020-02-02T10:00:00Z' where id = 'c1000000-0000-0000-0000-000000000004';
insert into r(name, ok, info) select 'c02 admin beze změny (i budoucí, vlastní rated_at)', rating = 4 and rated_at = '2020-02-02T10:00:00Z', rating||' '||rated_at from public.bookings where id='c1000000-0000-0000-0000-000000000004';
-- Velín: převod lokálních značek (ignoreDuplicates = ON CONFLICT DO NOTHING) a markHandled (upsert)
insert into public.booking_rating_reviews(booking_id, handled_at, rated_at_seen) values ('c1000000-0000-0000-0000-000000000001', now()-interval '1 day', now()) on conflict (booking_id) do nothing;
insert into public.booking_rating_reviews(booking_id, handled_at, rated_at_seen, handled_by) values ('c1000000-0000-0000-0000-000000000001', now(), now(), null)
  on conflict (booking_id) do update set handled_at = excluded.handled_at, rated_at_seen = excluded.rated_at_seen, handled_by = excluded.handled_by;
insert into r(name, ok, info) select 'c01 admin upsert, handled_by = admin', count(*) = 1 and bool_and(handled_by = 'dc000000-0000-0000-0000-0000000000dc' and handled_at = now()), max(handled_by::text) from public.booking_rating_reviews;
delete from public.booking_rating_reviews where booking_id = 'c1000000-0000-0000-0000-000000000001';
insert into r(name, ok) select 'c01 admin DELETE (zrušit vyřízeno)', count(*) = 0 from public.booking_rating_reviews;
reset role;

-- ========== service role / SQL bez JWT ==========
select set_config('request.jwt.claims','{"role":"service_role"}',true), set_config('request.jwt.claim.sub','',true);
set local role service_role;
update public.bookings set rating = 5 where id = 'c1000000-0000-0000-0000-000000000005';
insert into r(name, ok) select 'c02 service_role beze změny (i zrušená)', rating = 5 from public.bookings where id='c1000000-0000-0000-0000-000000000005';
reset role;

-- ========== katalog ==========
insert into r(name, ok) select 'c01 RLS zapnuto', relrowsecurity from pg_class where oid = 'public.booking_rating_reviews'::regclass;
insert into r(name, ok) select 'c01 anon bez práv', not has_table_privilege('anon','public.booking_rating_reviews','SELECT');
insert into r(name, ok) select 'trigger funkce bez EXECUTE pro anon/authenticated',
  not has_function_privilege('authenticated','public._bookings_rating_guard()','EXECUTE')
  and not has_function_privilege('anon','public._messages_bump_thread()','EXECUTE')
  and not has_function_privilege('authenticated','public._booking_rating_reviews_stamp()','EXECUTE');

-- ========== d01 (jen pokud je v bundle) ==========
insert into r(name, ok, info)
select 'd01 barvy ranků = škála v2.2 (nebo d01 není v bundle: všech 20 původních)',
       string_agg(upper(color_hex), ',' order by level) in (
         '#A3B8A8,#BDF6D1,#4ADE80,#00AC7F,#0AA2A4,#C2844A,#929496,#E5D376,#B9BEC6,#AEE9FF,#2CD1D4,#6EAFFF,#00A1C7,#5087D4,#117897,#165EEB,#D42020,#EDB42D,#F5F8FB,#FF8C1A',
         '#9CA3AF,#86EFAC,#4ADE80,#22C55E,#14B8A6,#CD7F32,#C0C0C0,#FFD700,#E5E4E2,#7DD3FC,#38BDF8,#3B82F6,#6366F1,#8B5CF6,#A855F7,#D946EF,#EF4444,#D4AF37,#F1F5F9,#FFD700'),
       count(*)||' řádků'
  from public.loyalty_levels having count(*) > 0;

select n, case when ok then 'PASS' else 'FAIL' end as res, name, info from r order by n;
do $$ begin
  if exists (select 1 from r where ok is not true) then raise exception 'TESTY SELHALY: %', (select count(*) from r where ok is not true); end if;
end $$;
rollback;
