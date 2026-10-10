import { useState } from 'react'
import Button from '../ui/Button'
import { DUE_STATE, fmtDate, fmtKm, dueText } from '../../lib/serviceBook'
import { computeBundle, planServiceBundle } from '../../lib/serviceBundle'

/**
 * Doporučený SPOLEČNÝ servis motorky: po termínu + blížící se + úkony, které dozrají do 2 000 km / 60 dní
 * (sdružení, ne po drobkách). Termín = nejbližší odhad (po termínu = dnes), km = nejbližší příští stav.
 * Jedno tlačítko založí jeden plánovaný servisní záznam se všemi úkony (lze odškrtnout, co nebrat).
 */
export default function ServiceBundleBox({ moto, due, onPlanned, unitLabel = 'km' }) {
  const bundle = computeBundle(due)
  const [excluded, setExcluded] = useState(new Set())
  const [date, setDate] = useState(bundle?.date || '')
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState(null)
  if (!bundle) return null
  const chosen = bundle.items.filter(r => !excluded.has(r.schedule_id))
  const toggle = (id) => setExcluded(s => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n })

  async function plan() {
    if (chosen.length === 0) return
    setBusy(true); setErr(null)
    try { const r = await planServiceBundle(moto.id, chosen, { date: date || bundle.date }); if (r) onPlanned?.() } catch (e) { setErr(e.message) } finally { setBusy(false) }
  }

  return (
    <div className="rounded-lg mb-3" style={{ background: bundle.overdue ? '#fef2f2' : '#fffbeb', border: `2px solid ${bundle.overdue ? '#fca5a5' : '#fde68a'}`, padding: 12 }}>
      <div className="flex items-center gap-3 flex-wrap mb-2">
        <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: bundle.overdue ? '#dc2626' : '#b45309' }}>Doporučený příští servis — provést společně</span>
        <span className="text-sm" style={{ color: '#1a2e22' }}>termín <b>{fmtDate(bundle.date)}</b>{bundle.overdue ? ' (po termínu — co nejdříve; od termínu je motorka v servisu)' : ' (odhad)'} · při <b>{fmtKm(bundle.km, unitLabel)}</b></span>
      </div>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-1 mb-2">
        {bundle.items.map(r => {
          const st = DUE_STATE[r.state]
          const on = !excluded.has(r.schedule_id)
          return (
            <label key={r.schedule_id} className="flex items-center gap-2 cursor-pointer rounded text-sm px-1.5 py-[3px] max-lg:py-1.5 max-md:flex-wrap max-md:gap-y-0" style={{ background: on ? '#fff' : '#f3f4f6', border: `1px solid ${st.border}` }}>
              <input type="checkbox" checked={on} onChange={() => toggle(r.schedule_id)} style={{ accentColor: '#16a34a' }} />
              <span className="font-bold flex-1 max-md:basis-[calc(100%-36px)]" style={{ color: on ? '#0f1a14' : '#9ca3af' }}>{r.label}</span>
              <span className="text-xs max-md:pl-7" style={{ color: st.color }}>{r.state === 'ok' ? `vzít s sebou · ${dueText(r, unitLabel)}` : dueText(r, unitLabel)}</span>
            </label>
          )
        })}
      </div>
      <div className="flex items-center gap-2 flex-wrap">
        <span className="text-xs font-bold" style={{ color: '#1a2e22' }}>Termín servisu:</span>
        <input type="date" value={date} onChange={e => setDate(e.target.value)} className="rounded text-sm outline-none" style={{ padding: '4px 8px', background: '#fff', border: '1px solid #d4e8e0' }} />
        <Button small green onClick={plan} disabled={busy || chosen.length === 0}>{busy ? 'Plánuji…' : `Naplánovat společný servis (${chosen.length})`}</Button>
        {err && <span className="text-xs" style={{ color: '#dc2626' }}>{err}</span>}
        <span className="text-xs ml-auto" style={{ color: '#6b7280' }}>Založí jeden servisní záznam se všemi vybranými úkony.</span>
      </div>
    </div>
  )
}
