#!/usr/bin/env bash
# seed_gearfix.sh <db> — BEFORE the bundle: a ride linked to a gear-only booking
# (state 4.1.3 could create since 2026-10-23); b06 must detach it. Then run
# test.sh with GEARFIX=1. Test data only (no live rows are fetched for group b:
# user_rides / bookings are not readable with the anon key).
set -euo pipefail
RIG="$(cd "$(dirname "$0")/../pg" && pwd)"
"$RIG/psql.sh" "${1:?db}" -X -q -v ON_ERROR_STOP=1 -c "set session_replication_role = replica;
  insert into auth.users (id, email, aud, role, created_at) values ('ab000000-0000-0000-0000-0000000000ab','gearfix@test.cz','authenticated','authenticated', now()) on conflict do nothing;
  insert into public.bookings (id, user_id, booking_kind, moto_id, start_date, end_date, status, gear_lines, gear_per_day)
    values ('ab000000-0000-0000-0000-0000000000b1','ab000000-0000-0000-0000-0000000000ab','gear',null,'2026-10-23','2026-10-25','active','[]',100) on conflict do nothing;
  insert into public.user_rides (id, user_id, booking_id, track, is_recording, distance_km)
    values ('ab000000-0000-0000-0000-0000000000c1','ab000000-0000-0000-0000-0000000000ab','ab000000-0000-0000-0000-0000000000b1','[]',false,5) on conflict do nothing;"
echo "seeded gear-linked ride"
