#!/usr/bin/env bash
# seed.sh <db> — nahraje živé řádky loyalty_levels (staženo REST 2026-11-12) do testovací DB.
# Spustit PŘED aplikací bundle.
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd); RIG=$D/../pg
[ $# -eq 1 ] || { echo "usage: $0 <db>"; exit 2; }
[ -s "$D/loyalty_levels.json" ] || "$RIG/rest_get.sh" loyalty_levels 'select=*&order=level' > "$D/loyalty_levels.json"
python3 -I "$RIG/seed_json.py" "$1" loyalty_levels "$D/loyalty_levels.json"
