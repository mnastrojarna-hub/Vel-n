// Zprávy → Hodnocení: data + realtime + akce. Hook běží v Messages.jsx (odznak záložky
// je vidět i z jiných kanálů), RatingsTab dostane výsledek přes props.
import { useState, useEffect, useMemo, useRef } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugError } from '../../lib/debugLog'
import { BOOKING_BRANCH_EMBED } from '../../lib/bookingBranch'
import { buildRatingRows, ratingsSummary, readLocalHandled, writeLocalHandled, feedbackSubject } from './ratingsData'

const LIMIT = 1000
const BOOKING_SELECT = `id, user_id, moto_id, branch_id, rating, rated_at, start_date, end_date, status,
  profiles(id, full_name, email, phone, language),
  motorcycles!moto_id(model, spz, branch_id, branches(name)), ${BOOKING_BRANCH_EMBED}`
const THREAD_SELECT = 'id, customer_id, subject, status, channel, created_at, last_message_at, messages(id, direction, content, created_at, read_at)'

// Sdílený stav „vyřízeno“ = admin-only tabulka z návrhu SQL (scratchpad reviews/sql). Dokud v DB
// není, platí localStorage tohoto prohlížeče. Zjišťuje se jednou za 10 min, BEZ debugAction
// (chybějící tabulka by jinak při každém načtení zapsala chybu do debug_log).
const HANDLED_TABLE = 'booking_rating_reviews'
const probe = { mode: null, at: 0 }
function isMissingTable(err) {
  const m = `${err?.code || ''} ${err?.message || ''}`
  return /42P01|PGRST205|does not exist|Could not find the table/i.test(m)
}

export function useRatings() {
  const [bookings, setBookings] = useState([])
  const [threads, setThreads] = useState([])
  const [handled, setHandled] = useState(() => (probe.mode === 'db' ? {} : readLocalHandled()))
  const [mode, setMode] = useState(probe.mode || 'local')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [busy, setBusy] = useState(false)
  const timer = useRef(null)
  const alive = useRef(true)

  async function loadHandled() {
    const fresh = probe.mode && Date.now() - probe.at < 600000
    if (fresh && probe.mode === 'local') { setMode('local'); setHandled(readLocalHandled()); return }
    const { data, error: err } = await supabase.from(HANDLED_TABLE).select('booking_id, handled_at, handled_by, rated_at_seen')
    if (err) {
      if (isMissingTable(err)) { probe.mode = 'local'; probe.at = Date.now(); setMode('local'); setHandled(readLocalHandled()) }
      return // jiná chyba (síť) → ponech poslední stav
    }
    probe.mode = 'db'; probe.at = Date.now()
    const map = {}
    for (const r of data || []) map[r.booking_id] = r
    // Jednorázový převod lokálních značek do DB (vznikly před nasazením migrace).
    const local = readLocalHandled()
    const pending = Object.entries(local).filter(([id]) => !map[id])
      .map(([booking_id, e]) => ({ booking_id, handled_at: e.handled_at, rated_at_seen: e.rated_at_seen || null }))
    if (pending.length) {
      const { error: upErr } = await supabase.from(HANDLED_TABLE).upsert(pending, { onConflict: 'booking_id', ignoreDuplicates: true })
      if (!upErr) { pending.forEach(p => { map[p.booking_id] = p }); writeLocalHandled({}) }
    } else if (Object.keys(local).length) writeLocalHandled({})
    setMode('db'); setHandled(map)
  }

  async function load() {
    try {
      const [bRes, tRes] = await Promise.all([
        debugAction('ratings.bookings', 'RatingsTab', () => supabase.from('bookings').select(BOOKING_SELECT)
          .not('rating', 'is', null).order('rated_at', { ascending: false, nullsFirst: false }).limit(LIMIT)),
        debugAction('ratings.threads', 'RatingsTab', () => supabase.from('message_threads').select(THREAD_SELECT)
          .ilike('subject', '%#%').order('created_at', { ascending: false }).limit(LIMIT)),
        loadHandled(),
      ])
      if (bRes.error) throw bRes.error
      if (tRes.error) throw tRes.error
      if (!alive.current) return
      setBookings(bRes.data || []); setThreads(tRes.data || []); setError(null)
    } catch (e) {
      debugError('RatingsTab', 'load', e)
      if (alive.current) setError(e.message || String(e))
    } finally { if (alive.current) setLoading(false) }
  }

  function scheduleLoad() {
    clearTimeout(timer.current)
    timer.current = setTimeout(load, 700) // dávka událostí (AI návrhy, označení přečtení) = 1 načtení
  }

  useEffect(() => {
    alive.current = true
    load()
    const ch = supabase.channel('velin-ratings')
      // jen řádky s hodnocením (nové i změněné hvězdičky); ostatní změny rezervací tab nezajímají
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'bookings', filter: 'rating=gte.1' }, scheduleLoad)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'message_threads' }, scheduleLoad)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'messages' }, scheduleLoad)
      .subscribe()
    return () => { alive.current = false; clearTimeout(timer.current); supabase.removeChannel(ch) }
  }, [])

  // Realtime tabulky „vyřízeno“ až když existuje (neexistující tabulka by shodila celý kanál).
  useEffect(() => {
    if (mode !== 'db') return undefined
    const ch = supabase.channel('velin-ratings-handled')
      .on('postgres_changes', { event: '*', schema: 'public', table: HANDLED_TABLE }, scheduleLoad)
      .subscribe()
    return () => { supabase.removeChannel(ch) }
  }, [mode])

  const rows = useMemo(() => buildRatingRows(bookings, threads, handled), [bookings, threads, handled])
  const summary = useMemo(() => ratingsSummary(rows), [rows])

  async function markRead(list) {
    const ids = list.flatMap(r => r.unread.map(m => m.id))
    if (!ids.length) return
    await debugAction('ratings.markRead', 'RatingsTab', () =>
      supabase.from('messages').update({ read_at: new Date().toISOString() }).in('id', ids).is('read_at', null), { count: ids.length })
  }

  // Označit vyřízené (1 i více řádků): uloží „vyřízeno“ + přečte nepřečtené komentáře.
  async function markHandled(list) {
    if (!list?.length) return
    setBusy(true)
    try {
      const now = new Date().toISOString()
      const entries = list.map(r => ({ booking_id: r.id, handled_at: now, rated_at_seen: r.booking.rated_at || null }))
      if (mode === 'db') {
        const { error: err } = await debugAction('ratings.markHandled', 'RatingsTab', () =>
          supabase.from(HANDLED_TABLE).upsert(entries, { onConflict: 'booking_id' }), { count: entries.length })
        if (err) throw err
      } else {
        const map = { ...readLocalHandled() }
        entries.forEach(e => { map[e.booking_id] = e })
        writeLocalHandled(map)
      }
      setHandled(h => { const n = { ...h }; entries.forEach(e => { n[e.booking_id] = e }); return n })
      await markRead(list)
      scheduleLoad()
    } catch (e) {
      debugError('RatingsTab', 'markHandled', e)
      window.alert('Uložení „vyřízeno“ selhalo: ' + (e.message || e))
    } finally { setBusy(false) }
  }

  async function unmarkHandled(row) {
    setBusy(true)
    try {
      if (mode === 'db') {
        const { error: err } = await debugAction('ratings.unmarkHandled', 'RatingsTab', () =>
          supabase.from(HANDLED_TABLE).delete().eq('booking_id', row.id), { booking_id: row.id })
        if (err) throw err
      } else {
        const map = { ...readLocalHandled() }
        delete map[row.id]
        writeLocalHandled(map)
      }
      setHandled(h => { const n = { ...h }; delete n[row.id]; return n })
    } catch (e) {
      debugError('RatingsTab', 'unmarkHandled', e)
      window.alert('Změna selhala: ' + (e.message || e))
    } finally { setBusy(false) }
  }

  // Celé vlákno pro ChatPanel (potřebuje i profiles, assigned_admin…).
  async function fetchThread(threadId) {
    const { data, error: err } = await debugAction('ratings.fetchThread', 'RatingsTab', () =>
      supabase.from('message_threads').select('*, profiles(full_name, email)').eq('id', threadId).single(), { threadId })
    if (err) throw err
    return data
  }

  // Zákazník ještě nepsal → Velín založí vlákno se značkou rezervace a pošle první zprávu
  // (trigger trg_bridge_admin_message ji doručí do appky i s push notifikací).
  async function startThread(row, text) {
    const b = row.booking
    const now = new Date().toISOString()
    const { data: thread, error: tErr } = await debugAction('ratings.createThread', 'RatingsTab', () =>
      supabase.from('message_threads').insert({
        customer_id: b.user_id, channel: 'app', status: 'open',
        subject: feedbackSubject(b.profiles?.language, b.id), last_message_at: now,
      }).select('*, profiles(full_name, email)').single(), { booking_id: b.id })
    if (tErr) throw tErr
    const { error: mErr } = await debugAction('ratings.firstMessage', 'RatingsTab', () =>
      supabase.from('messages').insert({ thread_id: thread.id, direction: 'admin', sender_name: 'Admin', content: text.trim(), read_at: now }),
      { thread_id: thread.id })
    if (mErr) throw mErr
    scheduleLoad()
    return thread
  }

  return { rows, summary, loading, error, mode, busy, reload: load, markHandled, unmarkHandled, fetchThread, startThread }
}
