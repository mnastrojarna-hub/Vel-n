#!/usr/bin/env bash
# rest_get.sh <table> [query string]
#   READ-ONLY look at live rows through the public REST API (PostgREST) with the
#   anon key the website ships (read from motogo-web-php/config.php at run time,
#   never printed, never stored). Only HTTP GET on /rest/v1/<table>; no /rpc/.
#   Output: one JSON array on stdout. Without "limit=" in the query string the
#   result is fetched in pages of 1000 rows (Range header) until exhausted - add
#   an "order=" on a unique column for a stable pagination.
#     rest_get.sh faq_items 'select=id,question&order=id&limit=3'
#     rest_get.sh cms_variables 'select=*&order=key' > /path/cms_variables.json
#     rest_get.sh app_settings 'select=key&key=like.gear*'
#   stderr: HTTP status, row count, Content-Range. Exit 1 on an HTTP error
#   (body printed to stderr). An empty array [] means "no rows" OR "anon may not
#   read this table" (RLS hides rows silently) - treat as "not readable".
#   Env: REST_MAX_ROWS (default 20000) upper bound for pagination.
set -euo pipefail
if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0; fi
CFG=/home/user/Vel-n/motogo-web-php/config.php
table="$1"; qs="${2:-select=*}"
[[ "$table" =~ ^[a-z_][a-z0-9_]*$ ]] || { echo "rest_get.sh: table name must be a plain identifier" >&2; exit 1; }
case "$table" in rpc|rpc_*) echo "rest_get.sh: rpc endpoints are forbidden" >&2; exit 1 ;; esac
case "$qs" in *$'\n'*|*' '*|*'#'*) echo "rest_get.sh: query string must not contain spaces, newlines or #" >&2; exit 1 ;; esac
url=$(sed -nE "s/^define\('SUPABASE_URL', *'([^']+)'\);.*/\1/p" "$CFG" | head -1)
key=$(sed -nE "s/^define\('SUPABASE_ANON_KEY', *'([^']+)'\);.*/\1/p" "$CFG" | head -1)
[ -n "$url" ] && [ -n "$key" ] || { echo "rest_get.sh: SUPABASE_URL / SUPABASE_ANON_KEY not found in $CFG" >&2; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fetch() { # fetch <outfile> [range]
  local out="$1" range="${2:-}" code
  local args=(-sS --request GET --max-time 60 --retry 2 --retry-delay 2 -o "$out" -D "$tmp/hdr" -w '%{http_code}' -H @- )
  [ -n "$range" ] && args+=(-H "Range-Unit: items" -H "Range: $range")
  code=$(printf 'apikey: %s\nAuthorization: Bearer %s\nAccept: application/json\n' "$key" "$key" \
         | curl "${args[@]}" "$url/rest/v1/$table?$qs")
  cr=$(grep -i '^content-range:' "$tmp/hdr" | tr -d '\r' | sed 's/^[^:]*: *//' || true)
  case "$code" in
    200|206) return 0 ;;
    *) echo "rest_get.sh: HTTP $code for $table" >&2; head -c 600 "$out" >&2; echo >&2; return 1 ;;
  esac
}
max="${REST_MAX_ROWS:-20000}"
if [[ "$qs" == *limit=* ]]; then
  fetch "$tmp/p0"
  n=$(jq 'length' "$tmp/p0")
  echo "rest_get.sh: $table HTTP ok, rows=$n, content-range=${cr:-?}" >&2
  jq -c '.' "$tmp/p0"
else
  i=0; total=0
  while :; do
    pf=$(printf "%s/p%05d" "$tmp" "$i"); fetch "$pf" "$((i*1000))-$((i*1000+999))"
    n=$(jq 'length' "$pf"); total=$((total+n))
    [ "$n" -lt 1000 ] && break
    [ "$total" -ge "$max" ] && { echo "rest_get.sh: stopped at REST_MAX_ROWS=$max" >&2; break; }
    i=$((i+1))
  done
  echo "rest_get.sh: $table HTTP ok, rows=$total, pages=$((i+1)), last content-range=${cr:-?}" >&2
  jq -c -s 'add // []' "$tmp"/p[0-9]*
fi
