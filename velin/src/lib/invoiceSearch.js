import { supabase } from './supabase'

/**
 * Sdílený fulltext filtr seznamů faktur (Finance → Faktury i Dokumenty → Faktury).
 * Hledá číslo dokladu, variabilní symbol, jméno ze zamraženého customer_snapshot
 * a zákazníky dle profiles.full_name (přes seznam id — PostgREST or() neumí
 * filtrovat řádky podle joinované tabulky bez !inner).
 *
 * Vrací query s aplikovaným .or(); volat PŘED .range().
 */
export async function applyInvoiceSearch(query, search) {
  const s = String(search || '').trim().replace(/[(),]/g, ' ')
  if (!s) return query
  const ors = [
    `number.ilike.%${s}%`,
    `variable_symbol.ilike.%${s}%`,
    `customer_snapshot->>name.ilike.%${s}%`,
  ]
  try {
    const { data: profs } = await supabase.from('profiles').select('id').ilike('full_name', `%${s}%`).limit(50)
    if (profs?.length) ors.push(`customer_id.in.(${profs.map(p => p.id).join(',')})`)
  } catch { /* hledání dle jména je best-effort */ }
  return query.or(ors.join(','))
}
