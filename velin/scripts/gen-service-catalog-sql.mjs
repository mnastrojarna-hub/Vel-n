#!/usr/bin/env node
// Vygeneruje SQL seed tabulky `service_task_catalog` z katalogu úkonů
// (velin/src/components/fleet/serviceCatalog.js) — JEDEN zdroj pravdy pro UI i DB.
// Použití:  node velin/scripts/gen-service-catalog-sql.mjs > /tmp/seed.sql
// Výstup je idempotentní (INSERT … ON CONFLICT (key) DO UPDATE); vložte ho do migrace.
import { SERVICE_GROUPS } from '../src/components/fleet/serviceCatalog.js'

const q = (s) => s == null ? 'NULL' : `'${String(s).replace(/'/g, "''")}'`
const n = (v) => v == null ? 'NULL' : String(v)
const arr = (a) => (a && a.length) ? `ARRAY[${a.map(q).join(',')}]::text[]` : `'{}'::text[]`

const rows = []
let sort = 0
for (const g of SERVICE_GROUPS) {
  for (const it of g.items) {
    sort += 10
    rows.push(`  (${q(it.id)}, ${q(it.label)}, ${q(g.key)}, ${q(g.label)}, ${sort}, ${q(it.kind || 'other')}, ${n(it.km)}, ${n(it.months)}, ${it.track ? 'true' : 'false'}, ${q(it.only || null)}, ${q(it.moto || null)}, ${arr(it.implies)}, ${arr(it.aliases)})`)
  }
}

process.stdout.write(`INSERT INTO public.service_task_catalog
  (key, label, group_key, group_label, sort_order, kind, default_interval_km, default_interval_months, tracked, only_for, moto_interval, implies, aliases)
VALUES
${rows.join(',\n')}
ON CONFLICT (key) DO UPDATE SET
  label = EXCLUDED.label, group_key = EXCLUDED.group_key, group_label = EXCLUDED.group_label,
  sort_order = EXCLUDED.sort_order, kind = EXCLUDED.kind,
  default_interval_km = EXCLUDED.default_interval_km, default_interval_months = EXCLUDED.default_interval_months,
  tracked = EXCLUDED.tracked, only_for = EXCLUDED.only_for, moto_interval = EXCLUDED.moto_interval,
  implies = EXCLUDED.implies, aliases = EXCLUDED.aliases, updated_at = now();
`)
