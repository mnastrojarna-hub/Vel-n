import { supabase } from './supabase'

/**
 * Sdílený fulltext filtr seznamů faktur (Finance → Faktury i Dokumenty → Faktury).
 * Hledá číslo dokladu, variabilní symbol, jméno a e-mail ze zamraženého
 * customer_snapshot a zákazníky dle profiles (jméno/e-mail/telefon — přes seznam
 * id, protože PostgREST or() neumí filtrovat řádky podle joinované tabulky bez !inner).
 *
 * Vrací STRING pro query.or() (nebo null bez hledání). Záměrně NEvrací query
 * builder: builder je thenable a návrat z async funkce přes `await` by dotaz
 * předčasně vykonal — výsledkem by byl objekt {data, error} a následné
 * .order()/.range() by spadlo na „.order is not a function".
 */
export async function invoiceSearchOrFilter(search) {
  const s = String(search || '').trim().replace(/[(),]/g, ' ')
  if (!s) return null
  const ors = [
    `number.ilike.%${s}%`,
    `variable_symbol.ilike.%${s}%`,
    `customer_snapshot->>name.ilike.%${s}%`,
    `customer_snapshot->>email.ilike.%${s}%`,
  ]
  try {
    const { data: profs } = await supabase.from('profiles').select('id')
      .or(`full_name.ilike.%${s}%,email.ilike.%${s}%,phone.ilike.%${s}%`)
      .limit(50)
    if (profs?.length) ors.push(`customer_id.in.(${profs.map(p => p.id).join(',')})`)
  } catch { /* hledání dle profilu je best-effort */ }
  return ors.join(',')
}
