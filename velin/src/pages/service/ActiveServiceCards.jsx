import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import StatusBadge from '../../components/ui/StatusBadge'
import ServiceLogCard from './ServiceLogCard'

export function Section({ title, color, bg, border, count, subtitle, children }) {
  return (
    <div>
      <div className="flex items-center gap-2 mb-2">
        <span className="text-sm font-extrabold uppercase tracking-widest" style={{ color }}>{title}</span>
        <span className="text-xs font-bold px-2 py-0.5 rounded-full" style={{ background: bg, color, border: `1px solid ${border}` }}>{count}</span>
        {subtitle && <span className="text-xs" style={{ color: '#6b7280' }}>{subtitle}</span>}
      </div>
      <div className="space-y-3">
        {children}
      </div>
    </div>
  )
}

export function MotoCard({ m, logs: mLogs, expanded, setExpanded, onAction, onReload, upcoming }) {
  const isExp = expanded[m.id]
  const hasUrgent = mLogs.some(l => l.is_urgent)
  const isStuck = m._stuck

  return (
    <Card style={isStuck ? { border: '2px solid #dc2626' } : hasUrgent ? { border: '2px solid #f87171' } : undefined}>
      <div className="flex items-center gap-3 cursor-pointer select-none" onClick={() => setExpanded(e => ({ ...e, [m.id]: !e[m.id] }))}>
        <span style={{ fontSize: 14, fontWeight: 700, transition: 'transform .2s', transform: isExp ? 'rotate(90deg)' : 'rotate(0deg)', color: '#1a2e22' }}>▶</span>
        <div className="flex-1 flex items-center gap-2 flex-wrap">
          <span className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{m.model}</span>
          <span className="font-mono text-sm" style={{ color: '#1a2e22' }}>{m.spz}</span>
          {m.branches?.name && <span className="text-sm" style={{ color: '#1a2e22' }}>{m.branches.name}</span>}
          {hasUrgent && <span className="text-xs font-bold px-2 py-0.5 rounded" style={{ background: '#dc2626', color: '#fff' }}>URGENT</span>}
          {isStuck && <span className="text-xs font-bold px-2 py-0.5 rounded" style={{ background: '#fef3c7', color: '#b45309' }}>Otevřený log — stav: {m.status}</span>}
          {upcoming && mLogs[0]?.service_date && (
            <span className="text-xs font-bold px-2 py-0.5 rounded" style={{ background: '#ecfdf5', color: '#059669' }}>
              {new Date(mLogs[0].service_date).toLocaleDateString('cs-CZ')}
            </span>
          )}
        </div>
        <StatusBadge status={isStuck ? m.status : 'maintenance'} />
        {mLogs.length > 0 && <span className="text-sm font-bold" style={{ color: '#b45309' }}>{mLogs.length} záznam{mLogs.length > 1 ? 'y' : ''}</span>}
        <button onClick={e => { e.stopPropagation(); onAction(m) }}
          className="rounded-btn text-sm font-extrabold uppercase cursor-pointer"
          style={{ padding: '4px 10px', background: '#dbeafe', color: '#2563eb', border: 'none' }}>Správa</button>
      </div>
      {isExp && (
        <div className="mt-4 space-y-3">
          {mLogs.length > 0 ? mLogs.map(l => (
            <ServiceLogCard key={l.id} log={l} moto={m} onReload={onReload} />
          )) : <NoLogCard motoId={m.id} onReload={onReload} />}
        </div>
      )}
    </Card>
  )
}

export function UnavailableMotoCard({ m, logs: mLogs, expanded, setExpanded, onAction, onReload }) {
  const isExp = expanded[m.id]
  const reasonText = m.unavailable_reason || 'Dočasně vyřazena'
  const untilDate = m.unavailable_until
    ? new Date(m.unavailable_until).toLocaleString('cs-CZ', { day: 'numeric', month: 'numeric', hour: '2-digit', minute: '2-digit' })
    : null

  return (
    <Card style={{ border: '2px solid #c4b5fd' }}>
      <div className="flex items-center gap-3 cursor-pointer select-none" onClick={() => setExpanded(e => ({ ...e, [m.id]: !e[m.id] }))}>
        <span style={{ fontSize: 14, fontWeight: 700, transition: 'transform .2s', transform: isExp ? 'rotate(90deg)' : 'rotate(0deg)', color: '#7c3aed' }}>▶</span>
        <div className="flex-1 flex items-center gap-2 flex-wrap">
          <span className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{m.model}</span>
          <span className="font-mono text-sm" style={{ color: '#1a2e22' }}>{m.spz}</span>
          {m.branches?.name && <span className="text-sm" style={{ color: '#1a2e22' }}>{m.branches.name}</span>}
          <span className="text-xs font-bold px-2 py-0.5 rounded" style={{ background: '#ede9fe', color: '#7c3aed' }}>
            {reasonText}{untilDate ? ` do ${untilDate}` : ''}
          </span>
        </div>
        <StatusBadge status="unavailable" />
        {mLogs.length > 0 && <span className="text-sm font-bold" style={{ color: '#7c3aed' }}>{mLogs.length} záznam{mLogs.length > 1 ? 'y' : ''}</span>}
        <button onClick={e => { e.stopPropagation(); onAction(m) }}
          className="rounded-btn text-sm font-extrabold uppercase cursor-pointer"
          style={{ padding: '4px 10px', background: '#ede9fe', color: '#7c3aed', border: 'none' }}>Správa</button>
      </div>
      {isExp && (
        <div className="mt-4 space-y-3">
          <div className="p-3 rounded-lg" style={{ background: '#f5f3ff', border: '1px solid #c4b5fd' }}>
            <div className="text-xs font-bold" style={{ color: '#7c3aed' }}>
              Motorka je dočasně vyřazena ze servisu ({reasonText}).
              {untilDate && <> Návrat plánován na {untilDate}.</>}
              {' '}Servisní záznamy jsou zachovány.
            </div>
          </div>
          {mLogs.map(l => (
            <ServiceLogCard key={l.id} log={l} moto={m} onReload={onReload} />
          ))}
        </div>
      )}
    </Card>
  )
}

export function NoLogCard({ motoId, onReload }) {
  const [desc, setDesc] = useState('')
  const [saving, setSaving] = useState(false)
  const [ending, setEnding] = useState(false)

  async function create() {
    if (!desc.trim()) return; setSaving(true)
    const today = new Date().toISOString().slice(0, 10)
    await supabase.from('motorcycles').update({ status: 'maintenance' }).eq('id', motoId)
    await supabase.from('maintenance_log').insert({ moto_id: motoId, description: desc.trim(), service_type: 'repair', service_date: today, status: 'in_service' })
    setSaving(false); onReload()
  }
  async function endDirect() {
    setEnding(true)
    const today = new Date().toISOString().slice(0, 10)
    await supabase.from('motorcycles').update({ status: 'active', last_service_date: today }).eq('id', motoId)
    await supabase.from('maintenance_log').update({ completed_date: today, status: 'completed' }).eq('moto_id', motoId).is('completed_date', null)
    await supabase.from('service_orders').update({ status: 'completed', completed_at: new Date().toISOString() }).eq('moto_id', motoId).in('status', ['pending', 'in_service'])
    setEnding(false); onReload()
  }

  return (
    <div className="p-3 rounded-lg" style={{ background: '#fef3c7', border: '1px solid #fde68a' }}>
      <div className="text-sm font-bold mb-2" style={{ color: '#b45309' }}>Motorka v servisu bez záznamu.</div>
      <div className="flex gap-2 items-end">
        <textarea value={desc} onChange={e => setDesc(e.target.value)} placeholder="Popište závadu…"
          className="flex-1 rounded-btn text-sm outline-none" style={{ padding: '6px 10px', background: '#fff', border: '1px solid #d4e8e0', minHeight: 40, resize: 'vertical' }} />
        <Button onClick={create} disabled={saving || !desc.trim()} style={{ fontSize: 13, padding: '6px 12px' }}>{saving ? 'Ukládám…' : 'Vytvořit'}</Button>
        <Button green onClick={endDirect} disabled={ending} style={{ fontSize: 13, padding: '6px 12px' }}>{ending ? 'Vracím…' : 'Ukončit servis'}</Button>
      </div>
    </div>
  )
}
