// Zprávy → Hodnocení: sdílené dotazy (záložka Hodnocení i odznak v menu / zvonku).
import { supabase } from '../../lib/supabase'
import { readLocalHandled } from './ratingsData'

export const THREAD_SELECT = 'id, customer_id, subject, status, channel, created_at, last_message_at, messages(id, direction, content, created_at, read_at)'
const CHUNK = 150 // uuid v URL (in.(…)) — ~6 kB na dotaz

/**
 * Vlákna zpětné vazby (předmět se značkou „#“) jen hodnotících zákazníků — po dávkách, takže
 * starší vlákna nevypadnou ani při velkém počtu konverzací v systému.
 */
export async function fetchFeedbackThreads(userIds) {
  const ids = [...new Set((userIds || []).filter(Boolean))]
  const out = []
  for (let i = 0; i < ids.length; i += CHUNK) {
    const { data, error } = await supabase.from('message_threads').select(THREAD_SELECT)
      .in('customer_id', ids.slice(i, i + CHUNK)).ilike('subject', '%#%')
    if (error) throw error
    out.push(...(data || []))
  }
  return out
}

// Sdílený stav „vyřízeno“ = admin-only tabulka z návrhu SQL (scratchpad reviews/sql). Dokud v DB
// není, platí localStorage tohoto prohlížeče. Zjišťuje se jednou za 10 min, BEZ debugAction
// (chybějící tabulka by jinak při každém načtení zapsala chybu do debug_log).
export const HANDLED_TABLE = 'booking_rating_reviews'
export const probe = { mode: null, at: 0 }
function isMissingTable(err) {
  const m = `${err?.code || ''} ${err?.message || ''}`
  return /42P01|PGRST205|does not exist|Could not find the table/i.test(m)
}

/** { mode: 'db'|'local', map: { [booking_id]: {...} } }, při chybě sítě null (ponechat poslední stav). */
export async function fetchHandledMap() {
  const fresh = probe.mode && Date.now() - probe.at < 600000
  if (fresh && probe.mode === 'local') return { mode: 'local', map: readLocalHandled() }
  const { data, error } = await supabase.from(HANDLED_TABLE).select('booking_id, handled_at, handled_by, rated_at_seen')
  if (error) {
    if (!isMissingTable(error)) return null
    probe.mode = 'local'; probe.at = Date.now()
    return { mode: 'local', map: readLocalHandled() }
  }
  probe.mode = 'db'; probe.at = Date.now()
  const map = {}
  for (const r of data || []) map[r.booking_id] = r
  return { mode: 'db', map }
}
