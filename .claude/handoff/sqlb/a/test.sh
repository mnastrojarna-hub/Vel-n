#!/usr/bin/env bash
# Testy skupiny a (platby) — spouští se na DB, kde je aplikovaný celý balík 20261112a01–a07.
# Vše běží v JEDNÉ transakci zakončené ROLLBACK → databázi nemění, lze opakovat.
# Použití: test.sh <db>   (exit 0 = vše prošlo)
set -euo pipefail
DB="${1:?usage: test.sh <db>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
RIG="$HERE/../pg"
MIG=/home/user/Vel-n/supabase/migrations
T="$HERE/t"
OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT
{
  cat "$T/00_setup.sql" "$T/10_p1.sql" "$T/20_p2.sql" "$T/30_p3.sql" "$T/40_p4.sql" "$T/50_p567.sql" "$T/60_a05dup.sql"
  cat "$MIG/20261112a05_uq_invoices_credit_note_refund.sql"
  cat "$T/61_a05dup_check.sql"
  cat "$MIG/20261112a05_uq_invoices_credit_note_refund.sql"
  cat "$T/62_a05dup_check2.sql" "$T/99_report.sql"
} | "$RIG/psql.sh" "$DB" -X -v ON_ERROR_STOP=1 >"$OUT" 2>&1 || { cat "$OUT"; echo "TEST RUN ERROR"; exit 2; }
grep -E '^(PASS|FAIL|SUMMARY)|WARNING:  \[20261112a05\]' "$OUT"
grep -q 'WARNING:  \[20261112a05\] index uq_invoices_credit_note_refund NEVYTVOŘEN' "$OUT" || { echo "FAIL a05: chybí WARNING o duplicitách"; exit 1; }
grep -q '^SUMMARY .* 0 failed$' "$OUT"
