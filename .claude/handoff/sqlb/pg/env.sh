# Shared settings of the sqlb PG16 test rig. Sourced by every script here.
# Never point anything at the live database: the only connection target is the
# unix socket of the local cluster below.
RIG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO=/home/user/Vel-n
BIN=/usr/lib/postgresql/16/bin
PGD=/var/tmp/pg-sqlb
PGSOCK=$PGD/sock
PGPORT_SQLB=5498
TPL=live_tpl
SNAP_COMMIT=e5d5b0f7                 # origin/supabase-live-snapshot, 2026-11-12 11:01 UTC
SU=supabase_admin                    # bootstrap superuser (as on Supabase)
# Role used by default = "postgres": NOT a superuser, exactly like the role the
# deploy workflow (and the SQL editor) uses on Supabase. PGU=supabase_admin
# switches a single call to the superuser.
PGU="${PGU:-postgres}"
as_pg() { runuser -u postgres -- "$@"; }
# psql against the local cluster; stdin is passed through.
PSQL_AS() { local u="$1"; shift; as_pg "$BIN/psql" -X -h "$PGSOCK" -p "$PGPORT_SQLB" -U "$u" "$@"; }
PSQL() { PSQL_AS "$PGU" "$@"; }
SUPSQL() { PSQL_AS "$SU" "$@"; }
ensure_up() {
  if ! as_pg "$BIN/pg_ctl" -D "$PGD/data" status >/dev/null 2>&1; then
    as_pg "$BIN/pg_ctl" -D "$PGD/data" -l "$PGD/log" -w start >/dev/null
  fi
}
BASE=base                            # pristine read-only copy of the template (reference for diffs)
writable_db() { valid_db "$1" || return 1; [ "$1" != "$BASE" ] || { echo "database '$BASE' is the shared read-only reference - use your own database" >&2; return 1; }; }
valid_db() {
  case "$1" in
    ''|postgres|template0|template1|"$TPL") echo "refusing database name '$1'" >&2; return 1 ;;
  esac
  [[ "$1" =~ ^[a-z][a-z0-9_]{0,40}$ ]] || { echo "database name must match ^[a-z][a-z0-9_]{0,40}\$ (got '$1')" >&2; return 1; }
}
