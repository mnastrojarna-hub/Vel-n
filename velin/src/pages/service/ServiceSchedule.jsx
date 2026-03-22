import { useState, useEffect, useMemo } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import {
  SEASON_MONTHS, seasonDaysBetween, addSeasonDays,
  findWinterServiceDate, scheduleStkDates, findFreeServiceDate,
  isLateOctober, isoDate, TYPE_LABELS,
} from './serviceScheduleUtils'

const FILTERS = ['Vše', 'Nejbližší', 'Následující měsíc', 'Vlastní']

export default function ServiceSchedule() {
  const [schedules, setSchedules] = useState([])
  const [bookings, setBookings] = useState([])
  const [avgKmPerDay, setAvgKmPerDay] = useState({})
  const [allMotos, setAllMotos] = useState([])
  const [loading, setLoading] = useState(true)
  const [filter, setFilter] = useState('Vše')
  const [customFrom, setCustomFrom] = useState('')
  const [customTo, setCustomTo] = useState('')
  const [manualDates, setManualDates] = useState({})
  const [editingDate, setEditingDate] = useState(null)
  const [savingDate, setSavingDate] = useState(null)

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    try {
      debugLog('ServiceSchedule', 'load')
      const [schedRes, bookRes, logRes, motosRes] = await Promise.all([
        debugAction('maintenance_schedules.list', 'ServiceSchedule', () =>
          supabase.from('maintenance_schedules').select('*, motorcycles(id, model, spz, mileage, purchase_mileage, year)')
            .eq('active', true).order('next_due', { ascending: true, nullsFirst: false })),
        supabase.from('bookings').select('moto_id, start_date, end_date')
          .in('status', ['pending', 'reserved', 'active']).gte('end_date', isoDate(new Date())),
        supabase.from('maintenance_log').select('moto_id, mileage_at_service, created_at').order('created_at', { ascending: true }),
        supabase.from('motorcycles').select('id, model, spz, stk_valid_until, license_required').order('model'),
      ])
      if (schedRes.error) throw schedRes.error
      setSchedules(schedRes.data || [])
      setBookings(bookRes.data || [])
      setAllMotos(motosRes.data || [])

      // Avg km/day per motorcycle
      const logs = logRes.data || []
      const byMoto = {}
      for (const l of logs) { if (l.moto_id && l.mileage_at_service) { if (!byMoto[l.moto_id]) byMoto[l.moto_id] = []; byMoto[l.moto_id].push(l) } }
      const avgMap = {}
      for (const [motoId, entries] of Object.entries(byMoto)) {
        if (entries.length >= 2) {
          const first = entries[0], last = entries[entries.length - 1]
          const kmDiff = (last.mileage_at_service || 0) - (first.mileage_at_service || 0)
          const sDays = seasonDaysBetween(new Date(first.created_at), new Date(last.created_at))
          if (sDays > 0 && kmDiff > 0) avgMap[motoId] = kmDiff / sDays
        }
      }
      for (const s of (schedRes.data || [])) {
        const moto = s.motorcycles
        if (moto && !avgMap[moto.id] && moto.mileage && moto.year) {
          avgMap[moto.id] = moto.mileage / (Math.max(1, (new Date().getFullYear() - moto.year) * SEASON_MONTHS) * 30)
        }
      }
      setAvgKmPerDay(avgMap)
    } catch (e) { debugError('ServiceSchedule', 'load', e) }
    setLoading(false)
  }

  const enriched = useMemo(() => {
    const now = new Date()
    const winterYear = now.getMonth() >= 2 ? now.getFullYear() + 1 : now.getFullYear()
    const results = schedules.map(s => {
      const currentKm = Number(s.motorcycles?.mileage) || 0
      const baseMileage = Number(s.motorcycles?.purchase_mileage) || 0
      let nextAt = !s.last_service_km && s.first_service_km ? baseMileage + Number(s.first_service_km)
        : s.last_service_km ? s.last_service_km + (s.interval_km || 0)
        : baseMileage + (s.interval_km || 0)
      const remaining = nextAt - currentKm
      const overdue = s.interval_km ? remaining <= 0 : false
      const dbDate = s.next_due || s.next_date || null
      let autoDate = null
      const motoId = s.motorcycles?.id || s.moto_id
      const dailyKm = avgKmPerDay[motoId]
      const isRegular = !!(s.interval_km || s.interval_days)
      let mergedWithWinter = false

      if (isRegular && overdue) {
        autoDate = findFreeServiceDate(now, bookings.filter(b => b.moto_id === motoId))
      } else if (isRegular && dailyKm > 0 && remaining > 0) {
        const est = addSeasonDays(now, Math.ceil(remaining / dailyKm))
        const mb = bookings.filter(b => b.moto_id === motoId)
        if (isLateOctober(est) && s.interval_km && remaining - s.interval_km * 0.25 > 0) {
          autoDate = findWinterServiceDate(winterYear, mb); mergedWithWinter = true
        } else { autoDate = findFreeServiceDate(est, mb) }
      }
      return { ...s, remaining, overdue, nextAt, estDate: dbDate ? new Date(dbDate) : autoDate, autoDate, isAutoEstimated: !dbDate && !!autoDate, dailyKm: dailyKm || 0, mergedWithWinter }
    })
    // Virtual winter service per moto
    const motoIds = new Set(schedules.map(s => s.motorcycles?.id || s.moto_id).filter(Boolean))
    for (const motoId of motoIds) {
      const ms = schedules.find(s => (s.motorcycles?.id || s.moto_id) === motoId)
      const wd = findWinterServiceDate(winterYear, bookings.filter(b => b.moto_id === motoId))
      results.push({ id: `winter-${motoId}`, moto_id: motoId, motorcycles: ms?.motorcycles || { id: motoId, model: '—', spz: '—' },
        description: 'Velký zimní servis', schedule_type: 'winter_service', remaining: null, overdue: false, estDate: wd, autoDate: wd, isAutoEstimated: true, dailyKm: 0, mergedWithWinter: false, isWinterService: true })
    }
    // Virtual STK entries — only for motos that require a license (go on public roads)
    // license_required === 'N' means no license needed = off-road/kids = no STK
    const stkMotos = allMotos.filter(m => m.license_required !== 'N')
    const stkYear = now.getMonth() >= 2 ? now.getFullYear() + 1 : now.getFullYear()
    const stkA = scheduleStkDates(stkMotos, bookings, stkYear)
    for (const moto of stkMotos) {
      const stkValid = moto.stk_valid_until ? new Date(moto.stk_valid_until) : null
      const md = schedules.find(s => (s.motorcycles?.id || s.moto_id) === moto.id)?.motorcycles || moto
      results.push({ id: `stk-${moto.id}`, moto_id: moto.id, motorcycles: md,
        description: 'STK & Emise', schedule_type: 'stk', remaining: null, overdue: stkValid ? stkValid < now : false,
        estDate: stkA[moto.id], autoDate: stkA[moto.id], isAutoEstimated: true, dailyKm: 0, mergedWithWinter: false, isStkService: true, stkValidUntil: stkValid })
    }
    return results
  }, [schedules, avgKmPerDay, bookings, allMotos])

  const filtered = useMemo(() => {
    let items = enriched
    if (filter === 'Nejbližší') {
      const byMoto = {}, byType = {}
      for (const s of items) {
        const mid = s.moto_id
        if (!byMoto[mid] || (s.remaining != null && (byMoto[mid].remaining == null || s.remaining < byMoto[mid].remaining))) byMoto[mid] = s
        const t = s.schedule_type
        if (t && !s.isWinterService && !s.isStkService && (!byType[t] || (s.remaining != null && (byType[t].remaining == null || s.remaining < byType[t].remaining)))) byType[t] = s
      }
      const merged = new Map()
      const typeIds = new Set(Object.values(byType).map(s => s.id))
      for (const s of Object.values(byMoto)) merged.set(s.id, { ...s, _nearestMoto: true, _nearestType: typeIds.has(s.id) })
      for (const s of Object.values(byType)) { if (merged.has(s.id)) merged.get(s.id)._nearestType = true; else merged.set(s.id, { ...s, _nearestMoto: false, _nearestType: true }) }
      items = Array.from(merged.values())
    } else if (filter === 'Následující měsíc') {
      const nm = new Date(); nm.setMonth(nm.getMonth() + 1)
      items = items.filter(s => s.overdue || (s.estDate && s.estDate <= nm))
    } else if (filter === 'Vlastní') {
      const from = customFrom ? new Date(customFrom) : null, to = customTo ? new Date(customTo + 'T23:59:59') : null
      if (from || to) items = items.filter(s => s.estDate && (!from || s.estDate >= from) && (!to || s.estDate <= to))
    }
    return items.sort((a, b) => { if (a.overdue !== b.overdue) return a.overdue ? -1 : 1; if (a.estDate && b.estDate) return a.estDate - b.estDate; if (a.estDate) return -1; if (b.estDate) return 1; return (a.remaining ?? Infinity) - (b.remaining ?? Infinity) })
  }, [enriched, filter, customFrom, customTo])

  async function saveDate(scheduleId, dateStr) {
    setSavingDate(scheduleId)
    try {
      const { error } = await supabase.from('maintenance_schedules').update({ next_due: dateStr || null }).eq('id', scheduleId)
      if (error) throw error
      setSchedules(prev => prev.map(s => s.id === scheduleId ? { ...s, next_due: dateStr || null } : s))
      setEditingDate(null); setManualDates(prev => { const n = { ...prev }; delete n[scheduleId]; return n })
    } catch (e) { debugError('ServiceSchedule', 'saveDate', e) }
    setSavingDate(null)
  }

  if (loading) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>

  return (
    <div>
      <div className="flex items-center gap-2 mb-4 flex-wrap">
        {FILTERS.map(f => (
          <button key={f} onClick={() => setFilter(f)} className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ padding: '6px 14px', background: filter === f ? '#74FB71' : '#f1faf7', color: '#1a2e22', border: 'none', boxShadow: filter === f ? '0 4px 16px rgba(116,251,113,.35)' : 'none' }}>{f}</button>
        ))}
        {filter === 'Vlastní' && (
          <div className="flex items-center gap-2 ml-2">
            <input type="date" value={customFrom} onChange={e => setCustomFrom(e.target.value)} className="rounded-lg text-xs px-2 py-1" style={{ border: '1px solid #d1d5db', background: '#fff' }} />
            <span className="text-xs" style={{ color: '#1a2e22' }}>—</span>
            <input type="date" value={customTo} onChange={e => setCustomTo(e.target.value)} className="rounded-lg text-xs px-2 py-1" style={{ border: '1px solid #d1d5db', background: '#fff' }} />
          </div>
        )}
        <span className="ml-auto text-xs" style={{ color: '#6b7280' }}>{filtered.length} záznamů</span>
      </div>

      <Table>
        <thead><TRow header><TH>Motorka</TH><TH>SPZ</TH><TH>Popis</TH><TH>Interval</TH><TH>Zbývá km</TH><TH>Plánované datum</TH></TRow></thead>
        <tbody>
          {filtered.map(s => {
            const isEditing = editingDate === s.id
            const dateVal = manualDates[s.id] ?? (s.estDate ? isoDate(s.estDate) : '')
            const hasManual = !!(s.next_due || s.next_date)
            return (
              <TRow key={s.id} style={s.isStkService ? { background: '#fef3c7' } : s.isWinterService || s.mergedWithWinter ? { background: '#eff6ff' } : undefined}>
                <TD bold>{s.motorcycles?.model || '—'}</TD>
                <TD mono>{s.motorcycles?.spz || '—'}</TD>
                <TD>
                  {s.isStkService ? <span style={{ color: '#b45309', fontWeight: 700 }}>STK & Emise</span>
                    : s.isWinterService ? <span style={{ color: '#2563eb', fontWeight: 700 }}>Velký zimní servis</span>
                    : (s.description || TYPE_LABELS[s.schedule_type] || s.schedule_type || '—')}
                  {filter === 'Nejbližší' && s._nearestMoto && <span className="ml-1" style={{ fontSize: 9, background: '#dcfce7', color: '#166534', borderRadius: 4, padding: '1px 4px', fontWeight: 600 }}>motorka</span>}
                  {filter === 'Nejbližší' && s._nearestType && <span className="ml-1" style={{ fontSize: 9, background: '#dbeafe', color: '#1e40af', borderRadius: 4, padding: '1px 4px', fontWeight: 600 }}>{TYPE_LABELS[s.schedule_type] || s.schedule_type}</span>}
                </TD>
                <TD>
                  {s.isStkService ? 'prosinec–únor' : s.isWinterService ? 'leden–únor' : ''}
                  {!s.isStkService && s.interval_km ? `${s.interval_km.toLocaleString('cs-CZ')} km` : ''}{!s.isStkService && s.interval_days ? ` / ${s.interval_days} dní` : ''}
                </TD>
                <TD style={s.overdue ? { color: '#dc2626', fontWeight: 700 } : s.mergedWithWinter ? { color: '#2563eb', fontWeight: 600 } : undefined}>
                  {s.isStkService ? (
                    s.stkValidUntil ? (() => { const days = Math.ceil((s.stkValidUntil - new Date()) / 86400000); const c = days < 0 ? '#dc2626' : days < 30 ? '#dc2626' : days < 90 ? '#b45309' : '#1a8a18'
                      return <span style={{ color: c, fontWeight: 700 }}>{days < 0 ? `⚠ ${Math.abs(days)} dní po` : `${days} dní`}<span style={{ fontWeight: 400, color: '#6b7280', marginLeft: 6, fontSize: 11 }}>(do {s.stkValidUntil.toLocaleDateString('cs-CZ')})</span></span> })()
                    : <span style={{ color: '#6b7280' }}>STK nenastaveno</span>
                  ) : s.isWinterService ? 'bez ohledu na km'
                  : s.interval_km ? (s.overdue ? `⚠ ${Math.abs(s.remaining).toLocaleString('cs-CZ')} km po` : `${s.remaining.toLocaleString('cs-CZ')} km`) : '—'}
                  {s.mergedWithWinter && ' → zimní servis'}
                  {!s.isStkService && !(Number(s.motorcycles?.mileage) || 0) && s.interval_km ? ' (km nenastaven)' : ''}
                </TD>
                <TD>
                  {s.isStkService ? <span style={{ color: '#b45309', fontWeight: 600 }}>{s.estDate ? s.estDate.toLocaleDateString('cs-CZ') : '—'}<span className="ml-1" style={{ fontSize: 10 }} title="Auto (Po–Pá, max 2/den)">~</span></span>
                  : s.isWinterService ? <span style={{ color: '#2563eb', fontWeight: 600 }}>{s.estDate ? s.estDate.toLocaleDateString('cs-CZ') : '—'}<span className="ml-1" style={{ fontSize: 10 }} title="Auto">~</span></span>
                  : isEditing ? (
                    <div className="flex items-center gap-1">
                      <input type="date" value={dateVal} onChange={e => setManualDates(prev => ({ ...prev, [s.id]: e.target.value }))}
                        className="rounded text-xs px-1 py-0.5" style={{ border: '1px solid #d1d5db', width: 130 }} />
                      <button onClick={() => saveDate(s.id, manualDates[s.id] || dateVal)} disabled={savingDate === s.id}
                        className="text-xs font-bold cursor-pointer" style={{ color: '#1a8a18', background: 'none', border: 'none' }}>{savingDate === s.id ? '…' : '✓'}</button>
                      <button onClick={() => { setEditingDate(null); setManualDates(prev => { const n = { ...prev }; delete n[s.id]; return n }) }}
                        className="text-xs cursor-pointer" style={{ color: '#6b7280', background: 'none', border: 'none' }}>✕</button>
                    </div>
                  ) : (
                    <div className="flex items-center gap-1">
                      <span className="cursor-pointer" onClick={() => setEditingDate(s.id)}
                        title={s.isAutoEstimated ? `Odhad (~${Math.round(s.dailyKm)} km/den)` : 'Klikni pro úpravu'}>
                        {s.estDate ? <>{s.estDate.toLocaleDateString('cs-CZ')}{s.mergedWithWinter && <span className="ml-1" style={{ color: '#2563eb', fontSize: 10 }}>→ zimní</span>}{s.isAutoEstimated && !s.mergedWithWinter && <span className="ml-1" style={{ color: '#6b7280', fontSize: 10 }}>~</span>}</> : '—'}
                      </span>
                      {hasManual && <button onClick={() => saveDate(s.id, null)} className="text-xs cursor-pointer ml-1" style={{ color: '#6b7280', background: 'none', border: 'none', fontSize: 10 }} title="Obnovit auto odhad">↺</button>}
                    </div>
                  )}
                </TD>
              </TRow>
            )
          })}
          {filtered.length === 0 && <TRow><TD colSpan={6}>Žádné servisní plány pro zvolený filtr.</TD></TRow>}
        </tbody>
      </Table>

      <div className="mt-3 text-xs" style={{ color: '#6b7280' }}>
        <span style={{ fontSize: 10 }}>~</span> = auto odhad (Út/St bez rezervace) · <span style={{ color: '#2563eb' }}>→ zimní</span> = sloučeno se zimním servisem · <span style={{ color: '#b45309' }}>STK</span> = prosinec–únor (Po–Pá, max 2/den) · Klikněte na datum pro úpravu
        {filter === 'Nejbližší' && <><br /><span style={{ background: '#dcfce7', color: '#166534', borderRadius: 4, padding: '1px 4px', fontSize: 9, fontWeight: 600 }}>motorka</span> = nejbližší motorky · <span style={{ background: '#dbeafe', color: '#1e40af', borderRadius: 4, padding: '1px 4px', fontSize: 9, fontWeight: 600 }}>typ</span> = nejbližší intervalu</>}
      </div>
    </div>
  )
}
