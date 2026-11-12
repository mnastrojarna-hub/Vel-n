#!/usr/bin/env bash
# seed.sh <db> — nahraje živé řádky (staženo REST anon klíčem 2026-11-12) do testovací DB.
# Spouštět PŘED aplikací balíku. email_templates anon nečte → syntetické řádky (synthetic_email.sql).
set -euo pipefail
DB=${1:?usage: seed.sh <db>}
S=/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad/sqlb
RIG=$S/pg; L=$S/t/live
for t in cms_variables faq_items app_settings cms_pages; do
  python3 -I $RIG/seed_json.py "$DB" "$t" "$L/$t.json"
done
if [ -f $S/t/synthetic_email.sql ]; then
  $RIG/psql.sh "$DB" -q -v ON_ERROR_STOP=1 < $S/t/synthetic_email.sql
fi
