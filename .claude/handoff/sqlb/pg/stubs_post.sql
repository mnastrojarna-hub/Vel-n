-- Per-database stubs loaded AFTER the live snapshot (as supabase_admin).
\set ON_ERROR_STOP 1
set client_min_messages = warning;
-- realtime.messages is partitioned per day and the Realtime service creates the
-- partitions on live; a default partition keeps realtime.send() working for
-- every (fake) date in tests.
create table if not exists realtime.messages_default partition of realtime.messages default;
alter table realtime.messages_default owner to supabase_realtime_admin;
-- Publication used by Supabase Realtime. Its MEMBERSHIP is not part of the
-- snapshot, so it starts empty here (live has members).
create publication supabase_realtime;
alter publication supabase_realtime owner to postgres;
