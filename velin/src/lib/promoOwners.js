import { supabase } from './supabase'

// Kódy z vrácení mají tvar VRACENI-{posledních 8 znaků UUID rezervace bez pomlček}
// (generuje generate_final_invoice_on_complete). promo_codes žádný sloupec se
// zákazníkem nemá — vazba kód → zákazník se dovozuje přes bookings.user_id.

export const RETURN_PREFIX = 'VRACENI-'

export function bookingIdToSuffix(id) {
  return String(id).replace(/-/g, '').slice(-8).toUpperCase()
}

let suffixMapPromise = null

// Mapa suffix → user_id přes všechny rezervace (cache na dobu života stránky)
export function getBookingSuffixMap() {
  if (!suffixMapPromise) {
    suffixMapPromise = (async () => {
      const map = new Map()
      const CHUNK = 1000
      for (let from = 0; ; from += CHUNK) {
        const { data, error } = await supabase
          .from('bookings').select('id, user_id').range(from, from + CHUNK - 1)
        if (error) throw error
        for (const b of data || []) {
          if (b.user_id) map.set(bookingIdToSuffix(b.id), b.user_id)
        }
        if (!data || data.length < CHUNK) return map
      }
    })()
    suffixMapPromise.catch(() => { suffixMapPromise = null })
  }
  return suffixMapPromise
}

// Najde zákazníky dle jména/e-mailu/telefonu a vrátí seznam VRACENI-* kódů
// náležících jejich rezervacím. Prázdné hledání → null (= filtr se nepoužije).
export async function findCustomerReturnCodes(search) {
  const safe = String(search || '').replace(/[,()"']/g, ' ').trim()
  if (!safe) return null
  const { data: profs, error: pErr } = await supabase
    .from('profiles').select('id')
    .or(`full_name.ilike.%${safe}%,email.ilike.%${safe}%,phone.ilike.%${safe}%`)
    .limit(50)
  if (pErr) throw pErr
  const ids = (profs || []).map(p => p.id)
  if (!ids.length) return []
  const { data: bks, error: bErr } = await supabase
    .from('bookings').select('id').in('user_id', ids)
    .order('created_at', { ascending: false }).limit(600)
  if (bErr) throw bErr
  return (bks || []).map(b => RETURN_PREFIX + bookingIdToSuffix(b.id))
}

// Pro zobrazené kódy dohledá vlastníky: { [code]: { userId, name } }
export async function resolveCodeOwners(codes) {
  const returnCodes = (codes || []).filter(c => (c.code || '').toUpperCase().startsWith(RETURN_PREFIX))
  if (!returnCodes.length) return {}
  const map = await getBookingSuffixMap()
  const byCode = {}
  const userIds = new Set()
  for (const c of returnCodes) {
    const uid = map.get(c.code.toUpperCase().slice(RETURN_PREFIX.length))
    if (uid) { byCode[c.code] = { userId: uid, name: null }; userIds.add(uid) }
  }
  if (userIds.size) {
    const { data: profs } = await supabase
      .from('profiles').select('id, full_name, email').in('id', [...userIds])
    const profById = new Map((profs || []).map(p => [p.id, p]))
    for (const code of Object.keys(byCode)) {
      const p = profById.get(byCode[code].userId)
      if (p) byCode[code].name = p.full_name || p.email
    }
  }
  return byCode
}
