// MotoGo24 — Velín → Dokumenty: dotazy, které čtou bookings.booking_kind (migrace 20261023a).
// Merge do main nasadí Velín (Vercel) a SQL (deploy-sql.yml) nezávisle; když je deploy-sql zablokovaný
// starší vadnou migrací, sloupec ještě neexistuje a PostgREST vrátí 42703 → celý seznam (faktury,
// vygenerované dokumenty, rezervace k přeposlání) by spadl i pro motorky. Proto dotaz zopakujeme bez
// booking_kind — štítek „Jen výbava“ / gear šablony se pak jen nezobrazí (před migrací gear řádky nejsou).

/** Chyba PostgREST/PG kvůli chybějícímu sloupci booking_kind (select, embed i filtr). */
export function isMissingBookingKind(err) {
  if (!err) return false
  const text = [err.message, err.details, err.hint].filter(Boolean).join(' ')
  return /booking_kind/i.test(text) || (err.code === '42703' && !text)
}

/**
 * run(withKind) → Promise<{data, error, count}>; při chybě kvůli booking_kind jednou zopakuje s withKind=false.
 * `kindCol(withKind)` = ', booking_kind' do select stringu (nebo '').
 */
export async function withBookingKind(run) {
  const res = await run(true)
  if (res?.error && isMissingBookingKind(res.error)) return run(false)
  return res
}

export const kindCol = (withKind) => (withKind ? ', booking_kind' : '')
