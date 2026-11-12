#!/usr/bin/env bash
# test.sh <db> — testy skupin c (hodnocení, zprávy) a d (barvy ranků) na DB s aplikovaným bundle.
# Vše běží v jedné transakci a končí ROLLBACK (DB se nemění). Exit 0 = vše prošlo.
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd); RIG=$D/../pg
[ $# -eq 1 ] || { echo "usage: $0 <db>"; exit 2; }
"$RIG/psql.sh" "$1" -v ON_ERROR_STOP=1 -q < "$D/test.sql"
