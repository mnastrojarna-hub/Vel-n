#!/usr/bin/env bash
# Načte živé řádky (anon REST, staženo 2026-11-12) motorcycles + branches do dané DB.
# Spouštět PŘED aplikací balíku. Testy skupiny a vlastní fixtures mají; seed slouží k ověření,
# že kontroly ceníku (_moto_dayprice_sum v a02/a07) pracují nad skutečnými ceníky (všech 27 motorek má ceny na všechny dny).
set -euo pipefail
DB="${1:?usage: seed.sh <db>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
python3 -I "$HERE/../pg/seed_json.py" "$DB" branches "$HERE/live_rows/branches.json"
python3 -I "$HERE/../pg/seed_json.py" "$DB" motorcycles "$HERE/live_rows/motorcycles.json"
