// Nízká hodnocení jízd (1–3 ★) k vyřízení — odznak MIMO Zprávy: menu „Zprávy“ (Sidebar) a zvonek
// (Topbar), aby je obsluha viděla, i když Zprávy neotevře. Počítá stejně jako záložka
// Zprávy → Hodnocení (buildRatingRows: vyřízeno = odpověď po hodnocení / uzavřené vlákno / ručně),
// ale BEZ řádků s nepřečteným komentářem — ty už jsou v počtu nepřečtených zpráv.
// Jeden sdílený výpočet + realtime pro všechny odběratele (Sidebar i Topbar).
import { supabase } from './supabase'
import { buildRatingRows, LOW_MAX } from '../pages/messages/ratingsData'
import { fetchFeedbackThreads, fetchHandledMap, HANDLED_TABLE } from '../pages/messages/ratingsFetch'

const listeners = new Set()
let count = 0
let threadIds = new Set()
let channel = null
let handledChannel = null
let timer = null
let poll = null
let running = false
let again = false

function emit() { listeners.forEach(fn => fn(count)) }

async function recompute() {
  if (running) { again = true; return }
  running = true
  try {
    const { data, error } = await supabase.from('bookings').select('id, user_id, rating, rated_at, updated_at, start_date')
      .gte('rating', 1).lte('rating', LOW_MAX).order('rated_at', { ascending: false, nullsFirst: false }).limit(500)
    if (error) throw error
    const [threads, handled] = await Promise.all([fetchFeedbackThreads((data || []).map(b => b.user_id)), fetchHandledMap()])
    if (!handled) return // výpadek sítě → ponech poslední stav
    count = buildRatingRows(data, threads, handled.map).filter(r => r.low && !r.handled && !r.unread.length).length
    threadIds = new Set(threads.map(t => t.id))
    // Realtime tabulky „vyřízeno“ až když existuje (neexistující tabulka by shodila kanál).
    if (handled.mode === 'db' && !handledChannel && listeners.size) {
      handledChannel = supabase.channel('velin-rating-alerts-handled')
        .on('postgres_changes', { event: '*', schema: 'public', table: HANDLED_TABLE }, () => schedule())
        .subscribe()
    }
    emit()
  } catch { /* odznak nesmí shodit menu; další pokus při změně nebo pollingu */ } finally {
    running = false
    if (again) { again = false; schedule() }
  }
}

function schedule(delay = 1500) {
  clearTimeout(timer)
  timer = setTimeout(recompute, delay)
}

function start() {
  channel = supabase.channel('velin-rating-alerts')
    // nové / změněné hvězdičky (i zvýšení 2 → 5 ★, které odznak zhasne)
    .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'bookings', filter: 'rating=gte.1' }, () => schedule())
    .on('postgres_changes', { event: '*', schema: 'public', table: 'message_threads' }, p => {
      if (!(p.new?.subject || '').includes('#') && !threadIds.has(p.old?.id)) return
      if (p.new?.id) threadIds.add(p.new.id) // první zpráva nového vlákna může přijít dřív než přepočet
      schedule()
    })
    // jen zprávy ve vláknech zpětné vazby (ne každá SMS / AI návrh v systému)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'messages' }, p => {
      if (threadIds.has(p.new?.thread_id || p.old?.thread_id)) schedule()
    })
    .subscribe()
  poll = setInterval(recompute, 120000)
  recompute()
}

function stop() {
  clearTimeout(timer); clearInterval(poll)
  if (channel) supabase.removeChannel(channel)
  if (handledChannel) supabase.removeChannel(handledChannel)
  channel = null; handledChannel = null
}

/** Odběr počtu nízkých nevyřízených hodnocení; vrací funkci pro odhlášení. */
export function subscribeRatingAlerts(fn) {
  listeners.add(fn)
  if (listeners.size === 1) start()
  else fn(count)
  return () => {
    listeners.delete(fn)
    if (!listeners.size) stop()
  }
}

/** Po akci v záložce Hodnocení (vyřízeno, odpověď) — přepočítat hned. */
export function refreshRatingAlerts() {
  if (listeners.size) schedule(300)
}
