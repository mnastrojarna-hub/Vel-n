#!/bin/bash
# seed.sh <db> : nahraje živé řádky (REST, stav 2026-11-12) tabulek skupiny u do testovací DB. Spouštět PŘED aplikací bundle.
set -e
[ -n "$1" ] || { echo "usage: seed.sh <db>"; exit 2; }
R=/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad/sqlb/pg; L=/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad/sqlb/u/live
for t in branches cms_variables faq_items cms_pages motorcycles app_settings document_templates custom_documents products; do
  python3 -I $R/seed_json.py "$1" $t $L/$t.json
done
python3 -I $R/seed_json.py "$1" admin_users $L/admin_users_ids.json
