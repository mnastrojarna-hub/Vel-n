# sqlb test rig — local PG16 copy of the LIVE MotoGo24 schema

Directory: `/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad/sqlb/pg` (below: `$RIG`).
Everything here talks only to the local cluster (unix socket). Nothing can reach the live database
except `rest_get.sh`, which does read-only HTTP GET with the public anon key.

## 0. Rules for every agent

1. Use only databases you created yourself with `newdb.sh` (prefix them with your group letter,
   e.g. `a_pay`, `b_rides`, `c_rev1`). Never touch another agent's database.
2. Never stop, restart or re-initialise the cluster, never run `build_tpl.sh`, never connect to `live_tpl`.
3. `base` is a shared, read-only, pristine copy of the live schema. Read it (`defn.sh base …`,
   `sig.sh base`, `fndiff.sh base mydb`), never write to it (the scripts refuse; the database is read-only).
4. The postgres OS user cannot read the scratchpad: always feed SQL through stdin
   (`psql.sh db < file.sql`); `apply.sh` and `deploy_sim.sh` do that for you.
5. Fake clock, fixtures and everything in `$RIG` are test-only. Nothing of it belongs in a migration.

## 1. Quick start

```bash
RIG=/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad/sqlb/pg
$RIG/newdb.sh a_pay                      # fresh copy of the live schema (0.15 s); drops an existing a_pay
$RIG/defn.sh base confirm_payment        # LIVE definition of a function (all overloads, owner, grants, comment)
$RIG/sig.sh a_pay > before.txt
$RIG/apply.sh a_pay /path/20261112a01_x.sql /path/20261112a02_y.sql    # like the deploy, stops at first failure
$RIG/apply.sh a_pay /path/20261112a01_x.sql /path/20261112a02_y.sql    # second run = idempotency
$RIG/sig.sh a_pay > after.txt; diff before.txt after.txt               # every schema-level change, one line each
$RIG/fndiff.sh base a_pay                # unified diff of all changed function/view bodies against live
$RIG/deploy_sim.sh a_pay                 # all supabase/migrations/20261112*.sql in deploy order + evidence table
$RIG/deploy_sim.sh a_pay --again         # re-apply all of them; proves "second run changes nothing"
$RIG/psql.sh a_pay -c 'select 1'         # ad-hoc SQL;  psql.sh a_pay -v ON_ERROR_STOP=1 < test.sql
```

## 2. Scripts (each prints its usage with `-h`)

| Script | Purpose |
|---|---|
| `newdb.sh <name> [--shim]` | Drop + create database `<name>` from template `live_tpl`. `--shim` also loads `timeshim.sql` + `fixtures.sql`. Name must match `^[a-z][a-z0-9_]{0,40}$`; `base`, `live_tpl`, `postgres` are refused. Safe to run concurrently (6 parallel calls tested). |
| `psql.sh <db> [psql args]` | psql into `<db>`, stdin passed through. Role = `postgres` (not a superuser — see §4). `PGU=supabase_admin psql.sh …` gives a superuser session. |
| `apply.sh <db> <file>...` | Each file exactly like `deploy-sql.yml`: `psql -v ON_ERROR_STOP=1 --single-transaction -f <file>` as role `postgres`, with `statement_timeout=120s`. Stops at the first failure (exit 1, transaction rolled back), prints NOTICE/WARNING lines and the failing statement (`STATEMENT:` line, psql `ECHO=errors`). Prints `LINT` warnings for statements that can behave differently on live (see §5) and **refuses a file that contains `BEGIN;`/`COMMIT;`** (repo rule; `ALLOW_TXN=1` overrides). `QUIET=1` hides NOTICEs. |
| `deploy_sim.sh <db> [--again] [--only S]` | Applies every `/home/user/Vel-n/supabase/migrations/20261112*.sql` in `LC_ALL=C sort` order through `apply.sh` and records the name in `public._git_migrations` like the workflow; already recorded files are skipped. `--again` re-applies all of them regardless of the evidence and compares `sig.sh` + `datasig.sh` before/after: exit 0 = nothing changed, 1 = error, 2 = schema signature changed, 3 = only table data changed (the changed tables are listed). `MIG_DIR`/`MIG_GLOB` override the source (to test drafts that are not in the repo yet). |
| `sig.sh <db> [grep -E pattern]` | Stable sorted dump, one line per object: `FUNCTION` (arguments with defaults, result, language, SECURITY DEFINER, volatility, `SET` config incl. search_path, owner, **ACL**, md5 of body), `COMMENT`, `TRIGGER` (public + auth + storage tables), `POLICY` (public + storage + auth), `RLS` flags, `INDEX`, `RELATION` (owner, ACL, reloptions), `COLUMN` (type, NOT NULL, default, generated, column ACL), `CONSTRAINT`, `VIEW`, `TYPE` (enum labels), `DEFACL`, `PUBLICATION` members, `CRON` jobs, `BUCKET`. 4,637 lines for the pristine schema. |
| `datasig.sh <db> [schema…]` | One line per table: row count + md5 over all rows (default: public + cron.job + storage.buckets; `_git_migrations` excluded). For proving that a re-run of a text/data migration changes no row. |
| `defn.sh <db> <function>` | `pg_get_functiondef` of every overload (+ owner, ACL, comment). `defn.sh base <fn>` = live body of today. |
| `fndiff.sh <dbA> <dbB> [regex]` | Unified diff of all public function + view definitions (with owner/ACL) between two databases; hunk headers name the function. `fndiff.sh base mydb` shows exactly what your migrations changed against live. Warns when part of a diff is line-ending only (see §5 CRLF). |
| `rest_get.sh <table> [query]` | Read-only REST GET of live rows with the anon key (read from `motogo-web-php/config.php` at run time, never printed/stored). Paginates (1000 rows per page) unless the query has `limit=`. JSON array on stdout. Only `/rest/v1/<table>`; rpc is refused. |
| `seed_json.py <db> <table> <json>` | `python3 -I $RIG/seed_json.py …` — upsert rows fetched by `rest_get.sh` into the test database with `session_replication_role = replica`, only columns that exist (others are listed and ignored), conflict target = primary key. |
| `timeshim.sql`, `fixtures.sql` | Test-only fake clock and minimal fixtures (§7). |
| `build_tpl.sh`, `verify_tpl.sh`, `split_sql.py`, `stubs_*.sql`, `sig.sql`, `env.sh` | Rig internals (template build + proof). Rig owner only. |

Typical data test for a text migration (rows that live really has):

```bash
$RIG/rest_get.sh cms_variables 'select=*&order=key' > cms.json      # 1,232 rows, 2 pages
python3 -I $RIG/seed_json.py t_txt cms_variables cms.json
$RIG/datasig.sh t_txt > d0; $RIG/apply.sh t_txt file.sql; $RIG/datasig.sh t_txt > d1
$RIG/apply.sh t_txt file.sql; $RIG/datasig.sh t_txt > d2; diff d1 d2   # must be empty
```

Acting as an API role (what PostgREST does for the app / web):

```sql
begin;
set local role authenticated;            -- or anon / service_role
select set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
select public.some_rpc(...);             -- auth.uid(), auth.role(), RLS and GRANTs behave as on live
rollback;
```

## 3. What the cluster contains

* Cluster `/var/tmp/pg-sqlb` (data `…/data`, socket dir `…/sock`, server log `…/log`), PostgreSQL 16.15,
  port **5498**, `listen_addresses=''` (unix socket only), `timezone=UTC`, `fsync=off`, encoding UTF8,
  locale C.UTF-8, owned by OS user `postgres`. Scripts start it automatically when it is down.
* Bootstrap superuser `supabase_admin` (as on Supabase). **Role `postgres` is NOT a superuser**
  (`CREATEDB CREATEROLE REPLICATION BYPASSRLS`), owns the databases and all public objects — same as live.
* Template `live_tpl` (connections disabled) = snapshot `origin/supabase-live-snapshot` @ `e5d5b0f7`
  (2026-11-12 11:01 UTC), loaded in this order (`build_tpl.sh`):
  1. `stubs_roles.sql` — Supabase roles (`anon`, `authenticated`, `service_role`, `authenticator`,
     `supabase_auth_admin`, `supabase_storage_admin`, `supabase_realtime_admin`, `supabase_functions_admin`,
     `dashboard_user`, `pgbouncer`, …), memberships, `search_path "$user", public, extensions`.
  2. `stubs_pre.sql` — schema `extensions` with **uuid-ossp + pgcrypto** (the only two extensions the
     public schema references), stub **pg_net** (`net.http_post/http_get/http_delete`: same signatures,
     SECURITY DEFINER, grants; a call only inserts a row into `net.http_request_queue`; NULL url fails
     like the real one), stub **pg_cron** (`cron.job`, `cron.schedule` = upsert by name,
     `cron.unschedule` raises for an unknown job like the real one, schedule string is validated),
     stub `vault`, empty `supabase_functions` and `graphql` schemas.
  3. snapshot `roles.sql` (statement_timeout: anon 3 s, authenticated 8 s, authenticator 8 s).
  4. snapshot `schema_system.sql` — the **real** `auth`, `storage`, `realtime`, `graphql_public`
     schemas (so `auth.users`, `auth.uid()`, `auth.role()`, `auth.jwt()`, `auth.email()`,
     `storage.objects`, `storage.buckets`, `storage.foldername()`, `realtime.send()` are the live
     definitions), except 14 statements that need public objects first (2 triggers on `auth.users`,
     12 policies on `storage.objects`) — those run after step 5.
  5. snapshot `schema_public.sql`.
  6. snapshot `triggers.sql`.
  7. `stubs_post.sql` — default partition for `realtime.messages`, empty publication `supabase_realtime`.
  8. `public._git_migrations` filled with the 395 migration file names of the snapshot commit.
* `base` = untouched copy of `live_tpl`, `default_transaction_read_only = on`.

### Load errors (complete list)

| Step | Errors | Explanation |
|---|---|---|
| stubs, roles.sql, schema_system.sql (both parts), schema_public.sql | **0** | The PG17-only privilege `MAINTAIN` is removed from 25 GRANT statements by `sed` before loading (23 in schema_system.sql, 2 in schema_public.sql: `user_rides`, `user_ride_points` → anon). Without that those 25 GRANTs would fail on PG16 and the listed privileges would be missing. |
| triggers.sql | **177** | All 177 are `trigger "…" for relation "…" already exists`: today's `schema_public.sql` already contains the same 177 triggers as `CREATE OR REPLACE TRIGGER`. Harmless duplicates. |

No other error, warning or skipped statement (logs: `$RIG/load/*.log`).

### Proof that nothing is missing (`verify_tpl.sh`, output in `$RIG/load/verify.txt`)

| Object kind | CREATE statements in snapshot | In the loaded database |
|---|---|---|
| public tables | 150 | 150 |
| public functions | 481 | 481 |
| public triggers | 177 | 177 (definitions text-identical to `triggers.sql`) |
| public policies | 298 | 298 |
| public indexes (300 CREATE INDEX + 14 UNIQUE + 192 PK/UNIQUE constraints) | 506 | 506 |
| public views / enum types / explicit sequences | 4 / 12 / 2 | 4 / 12 / 2 |
| public tables with RLS enabled | 147 | 147 |
| public function comments | 62 | 62 |
| auth tables / functions / indexes / triggers | 27 / 4 / 107 / 2 | 27 / 4 / 107 / 2 |
| storage tables / functions / indexes / policies / triggers | 10 / 24 / 26 / 23 / 11 | 10 / 24 / 26 / 23 / 11 |
| realtime tables / functions / indexes / triggers | 10 / 19 / 20 / 1 | 10 / 19 / 20 / 1 |
| PK / UNIQUE / FK constraints (all four schemas) | 498 | 498 |

Strongest check: a `pg_dump` of the loaded public schema, normalised, is **line-for-line identical** to
the snapshot `schema_public.sql` (26,231 lines; the only raw differences are cosmetic: 8 policies list
`"anon", "authenticated"` in the other order and one function prints `RETURNS json` vs `"json"`).

End-to-end checks done on 2026-11-12: (a) the 39 newest live migrations (`20261022*`, `20261023*`) were
re-applied through `apply.sh` as role `postgres`: 39/39 succeeded and `sig.sh` + `fndiff.sh` showed **no
difference** afterwards (so the snapshot contains them and the rig runs real migrations like live);
(b) all 19 repo migrations that call `cron.schedule/unschedule` applied on the stubs; (c) the live table
`_git_migrations` (anon-readable) holds 395 rows = exactly the 395 files of `supabase/migrations` at HEAD,
at `origin/main` and at the snapshot commit; newest applied: `20261023f_faq_gear_rental.sql`
(2026-10-23 11:52 UTC). Nothing has been deployed to live since.

## 4. Role model (important)

`apply.sh` and `psql.sh` connect as `postgres`, a non-superuser, because that is what the deploy and
the SQL editor use on Supabase; SECURITY DEFINER functions owned by `postgres` therefore run with the
same limited rights as on live. Privileges on `auth.*`, `storage.*`, `realtime.*` come from the GRANTs
in the snapshot. Things that are **approximations** (not in the snapshot, taken from the standard
Supabase platform setup):

* role attributes and memberships (`postgres` is a member of `anon`, `authenticated`, `service_role`,
  `authenticator`, `supabase_realtime_admin`, `pg_read_all_data`, `pg_monitor`, `pg_signal_backend`);
* `postgres` may `SET session_replication_role` (supautils allows it on live);
* `postgres` is a member of `supabase_storage_admin` and `supabase_auth_admin` to imitate supautils
  (`CREATE/DROP POLICY` on `storage.objects`, `CREATE/DROP TRIGGER` on `auth.users` work on live).
  This is **broader** than live: `ALTER TABLE` / `CREATE INDEX` on `auth.*` / `storage.*` passes here
  but is refused on live — `apply.sh` prints a `LINT` line for such statements;
* `statement_timeout = 120s` in `apply.sh` (Supabase's default cap for `postgres`; not verified for this project).

If a file fails here with `permission denied` / `must be owner`, re-run with `PGU=supabase_admin apply.sh …`
to see whether it is a privilege question, then judge by precedent (did an already applied migration do
the same thing?). Do not create objects in a test database as `supabase_admin` that a migration will
later replace — they would be owned by the superuser and `CREATE OR REPLACE` as `postgres` then fails
with "must be owner" (a rig artefact).

## 5. Differences between the rig and live — read before trusting a green run

* **Live is PostgreSQL 17, the rig is 16.15** (the snapshot contains the PG17-only `MAINTAIN`). Anything
  that parses on 16 parses on 17; do not use PG17-only syntax (it cannot be tested here).
* **No data.** The snapshot is schema only: every table is empty (except `_git_migrations`). A migration
  that depends on rows (UPDATE of texts, unique index over existing rows, new NOT NULL / CHECK on a
  filled table, backfill duration, locks) is only tested as far as you seed rows (`rest_get.sh` +
  `seed_json.py`, or hand-made rows). Row counts and timing of big live tables cannot be tested.
* **`app_settings` is empty** → functions that read `supabase_url` / `service_role_key` skip their edge
  calls with a warning. `fixtures.sql` inserts dummy values so the calls reach the pg_net stub.
* **`cron.job` is empty** (live jobs are not in the snapshot). `cron.schedule(name, …)` is an upsert, but
  `cron.unschedule('x')` of a job missing here fails exactly like on live for a missing job; the repo
  pattern is an inner `BEGIN … EXCEPTION WHEN OTHERS THEN NULL; END` or an `EXISTS (SELECT FROM cron.job …)` guard.
* **Publication `supabase_realtime` is empty** (membership is not in the snapshot). An unguarded
  `ALTER PUBLICATION … ADD TABLE` passes here on the first run but fails on live when the table is
  already a member — always guard with `pg_publication_tables` (`deploy_sim.sh --again` catches the unguarded form).
* `storage.buckets` / `storage.objects` are empty; `net.http_post` never sends anything.
* **CRLF:** 156 of the 481 live public functions have CRLF line endings in their body. A draft written
  with LF shows up in `fndiff.sh` as a whole-body change; `FNDIFF_OPTS=--strip-trailing-cr` shows the real
  content change. (`sig.sh` body md5 also changes when only line endings change.)
* New functions created by `postgres` in `public` automatically get EXECUTE for `anon`, `authenticated`,
  `service_role` (default privileges, as on live) **plus PUBLIC** (PostgreSQL default). Check the `acl=`
  part of the `FUNCTION` line in `sig.sh` against sibling live functions and REVOKE explicitly where needed.
* Policy role lists in `sig.sh` are ordered by local role OIDs — stable inside this cluster only.

## 6. Reading live data (REST, anon key, GET only) — readability probed 2026-11-12

`rest_get.sh <table> 'select=count'` was run for all 150 public tables.

| Table (asked for in the task) | Anon readable | Rows visible to anon |
|---|---|---|
| `cms_variables` | yes | 1,232 |
| `faq_items` | yes | 110 |
| `cms_pages` | yes | 13 |
| `app_settings` | yes, except keys `service_role_key` and `cms_admin_token` (RLS policy) | 86 |
| `document_templates` | yes | 8 |
| `email_templates` | **not readable** (HTTP 200, 0 rows: admin-only policy) | 0 |
| `message_templates` | yes | 184 |
| `motorcycles` | yes | 27 |
| `branches` | yes | 2 |
| `loyalty_levels` (the loyalty levels table; PK `level`, 6 columns) | yes | 20 |

Other tables with rows visible to anon: `_git_migrations` 395, `accessory_types` 8, `admin_users` 2,
`branch_closures` 2, `custom_documents` 3, `document_number_counters` 5, `extras_catalog` 16,
`feature_flags` 12, `gear_rental_prices` 7, `loyalty_monthly_winners` 2, `maintenance_log` 97,
`moto_day_prices` 19, `poi_ratings` 1, `pricing_rules` 4, `products` 6, `route_pois` 8,456,
`route_reviews` 2, `routes` 1,174, `service_interval_presets` 186, `service_task_catalog` 95,
`sku_catalog` 36. 107 tables answer HTTP 200 with 0 rows (RLS hides everything or the table is empty —
e.g. `bookings`, `profiles`, `reviews`, `messages`, `message_threads`, `promo_codes`, `payment_methods`,
`invoices`, `vouchers`, `user_pois`): treat as **not readable** and rely on guards inside the SQL.
HTTP 401 `permission denied` (no SELECT grant for anon): `user_rides`, `user_ride_points`,
`booking_complaints`, `booking_discounts`, `booking_kiosk_returns`, `branch_gate_access`,
`branch_temp_codes`, `gear_rentals`, `moto_odometer_readings`, `voucher_code_attempts`, `web_engagement`.
`points_of_interest` and `visitor_log` are readable but `select=count` hits the 3 s anon statement
timeout — page through them with `limit`/`order` instead. Full list: `$RIG/load/rest_probe.tsv`.
Fetched rows are customer/owner data: keep them in your scratch directory, never in the repo or a report.

## 7. Fake clock, fixtures, ride tests

`newdb.sh <db> --shim` loads both files (or `psql.sh <db> -v ON_ERROR_STOP=1 < $RIG/timeshim.sql`).

* `public.t_now()` — fake now (GUC `test.now`), real `now()` while unset.
* `public.t_set(ts [, uid])` — set the clock for the session; a non-NULL uid also sets
  `request.jwt.claim.sub` (→ `auth.uid()`); NULL uid leaves the subject as it is.
* `public.t_shim([regex [, tables]])` — rewrites `now()`, `CURRENT_TIMESTAMP`, `transaction_timestamp()`,
  `statement_timestamp()`, `clock_timestamp()` → `public.t_now()` and `CURRENT_DATE` → `(public.t_now())::date`
  in every public plpgsql/sql function whose name matches the regex (default `(ride|trip)`, plus
  `set_updated_at`) and in the column defaults of the listed tables (default `user_rides`,
  `user_ride_points`); returns the number of rewritten functions (10 on the pristine schema).
  **Re-run it after loading any draft** (CREATE OR REPLACE brings `now()` back). `t_shim('.')` = all functions.
  Take `sig.sh` / `fndiff.sh` output before shimming — the shim changes function bodies.
* `public.t_login(uid [, role])` / `public.t_logout()` — full JWT context (`request.jwt.claims` + claim GUCs).
* Fixtures: users `a0000000-0000-0000-0000-00000000000a` (rental), `b0000000-…-0b` (own bike),
  `c0000000-…-0c` (4.1.3), `e1000000-0000-0000-0000-0000000000e1`, `e2000000-…-e2`; admin
  `d0000000-0000-0000-0000-00000000000d` (superadmin in `admin_users`); branch `f0000000-…-0f`;
  motorcycle `e0000000-0000-0000-0000-00000000000e` Honda CB 500 X; dummy `app_settings`
  `supabase_url` / `service_role_key`. Inserted without triggers. Bookings: insert per scenario with
  `session_replication_role = replica`.

`/home/user/Vel-n/.claude/handoff/rides/sql/run_tests.sh` expects exactly these helpers (`t_shim`, `t_set`,
`t_now`), a database called `rides`, user `postgres`, and `$PGD/sock` + `$PGPORT_RIDES`. It works
unchanged against this rig — verified 2026-11-12 with the existing drafts 01–06 on a scratch copy
(applied twice, 337/337 tests passed twice, both race checks OK) — when started like this:

```bash
cp -r /home/user/Vel-n/.claude/handoff/rides/sql /your/scratch/rides_sql   # it writes out/ and stats_vectors.json next to itself
$RIG/newdb.sh rides --shim                                                  # the name "rides" is hard-coded in run_tests.sh
FRESH=0 PGD=/var/tmp/pg-sqlb PGPORT_RIDES=5498 bash /your/scratch/rides_sql/run_tests.sh
```

**Never run it with `FRESH=1` (its default!) and `PGD=/var/tmp/pg-sqlb`: that stops the shared cluster
and deletes it (`rm -rf "$PGD"`).** With `FRESH=0` it skips two things that `FRESH=1` did: recording
`out/sig_before.txt` (signature-unchanged check) and inserting the gear-booking ride used by the
"GEAR DATA FIX" check — do both by hand before the first apply if you need those checks (the statements
are in the `if [ "${FRESH:-1}" = 1 ]` block of the script). Only one agent can use the database name `rides`.

## 8. Maintenance (rig owner)

* Cluster down (e.g. after a container restart): any script starts it again
  (`pg_ctl -D /var/tmp/pg-sqlb/data -l /var/tmp/pg-sqlb/log start` as OS user postgres).
* Rebuild the template from the snapshot files in `$RIG/snap`: `build_tpl.sh --force`, then `verify_tpl.sh`
  (existing test databases are not affected; `base` is recreated).
* New snapshot: change `SNAP_COMMIT` in `env.sh`, delete `$RIG/snap/*.sql`, rebuild, verify.
