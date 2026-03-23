import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Button from '../../components/ui/Button'

const TYPE_LABELS = { regular: 'Pravidelný', extraordinary: 'Mimořádný', repair: 'Oprava' }

function parseItemsFromDesc(log) {
  if (log.items && Array.isArray(log.items) && log.items.length > 0) return log.items
  const lines = (log.description || '').split('\n')
  return lines.filter(l => l.trim().startsWith('- ')).map(l => ({ label: l.trim().slice(2), done: false, note: '' }))
}

export default function ServiceLogCard({ log, moto, onReload }) {
  const [items, setItems] = useState(() => parseItemsFromDesc(log))
  const [desc, setDesc] = useState(log.description || '')
  const [returnDate, setReturnDate] = useState(log.scheduled_date || '')
  const [saving, setSaving] = useState(false)
  const [ending, setEnding] = useState(false)

  const unitLabel = moto?.tracking_unit === 'mh' ? 'MH' : 'km'

  useEffect(() => {
    setItems(parseItemsFromDesc(log))
    setDesc(log.description || '')
    setReturnDate(log.scheduled_date || '')
  }, [log.id])

  function updateItem(idx, field, value) {
    setItems(prev => { const n = [...prev]; n[idx] = { ...n[idx], [field]: value }; return n })
  }

  async function saveAll() {
    setSaving(true)
    await supabase.from('maintenance_log').update({
      items, description: desc.trim() || null,
      scheduled_date: returnDate || null,
    }).eq('id', log.id)
    const tireItems = items.filter(i => (i.label || '').toLowerCase().includes('pneumatik') && i.done)
    if (tireItems.length > 0 && moto) await shiftTireSchedule(moto.id, moto.mileage)
    setSaving(false)
    onReload()
  }

  async function markCompleted() {
    setEnding(true)
    const today = new Date().toISOString().slice(0, 10)
    await supabase.from('maintenance_log').update({
      completed_date: today, status: 'completed', items,
      description: desc.trim() || null,
    }).eq('id', log.id)
    const tireItems = items.filter(i => (i.label || '').toLowerCase().includes('pneumatik') && i.done)
    if (tireItems.length > 0 && moto) await shiftTireSchedule(moto.id, moto.mileage)
    const { data: other } = await supabase.from('maintenance_log').select('id').eq('moto_id', log.moto_id).is('completed_date', null).neq('id', log.id)
    if (!other?.length) {
      await supabase.from('motorcycles').update({ status: 'active', last_service_date: today }).eq('id', log.moto_id)
    }
    const { data: { user } } = await supabase.auth.getUser()
    try { await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: 'service_completed', details: { log_id: log.id, moto_id: log.moto_id } }) } catch {}
    setEnding(false)
    onReload()
  }

  const isUrgent = log.is_urgent
  const sDate = log.service_date || log.scheduled_date || log.created_at

  return (
    <div className="p-3 rounded-lg" style={{ background: isUrgent ? '#fef2f2' : '#f1faf7', border: `1px solid ${isUrgent ? '#fca5a5' : '#d4e8e0'}` }}>
      <div className="flex items-start gap-3 mb-2 flex-wrap">
        <div>
          <div className="text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Typ</div>
          <div className="flex items-center gap-1">
            <span className="text-sm" style={{ color: '#1a2e22' }}>{TYPE_LABELS[log.service_type] || '—'}</span>
            {isUrgent && <span className="text-xs font-bold px-1.5 py-0.5 rounded" style={{ background: '#dc2626', color: '#fff' }}>URGENT</span>}
          </div>
        </div>
        <div>
          <div className="text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Servis od</div>
          <div className="text-sm" style={{ color: '#1a2e22' }}>{sDate ? new Date(sDate).toLocaleDateString('cs-CZ') : '—'}</div>
        </div>
        <div>
          <div className="text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Plán. dokončení</div>
          <input type="date" value={returnDate} onChange={e => setReturnDate(e.target.value)}
            className="rounded text-sm outline-none" style={{ padding: '3px 8px', background: '#fff', border: '1px solid #d4e8e0', width: 140 }} />
        </div>
        <div>
          <div className="text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{unitLabel}</div>
          <div className="text-sm font-mono" style={{ color: '#1a2e22' }}>{(log.km_at_service || 0).toLocaleString('cs-CZ')}</div>
        </div>
        <div>
          <div className="text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Technik</div>
          <div className="text-sm" style={{ color: '#1a2e22' }}>{log.performed_by || '—'}</div>
        </div>
      </div>

      {items.length > 0 && (
        <div className="mt-2 p-2 rounded-lg" style={{ background: '#fff', border: '1px solid #d4e8e0' }}>
          <div className="text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Servisní úkony</div>
          <div className="space-y-1">
            {items.map((item, idx) => (
              <div key={idx} className="flex items-start gap-2 p-1.5 rounded" style={{ background: item.done ? '#dcfce7' : '#f9fafb' }}>
                <input type="checkbox" checked={item.done || false} onChange={e => updateItem(idx, 'done', e.target.checked)}
                  style={{ marginTop: 2, accentColor: '#16a34a', width: 16, height: 16, cursor: 'pointer' }} />
                <div className="flex-1">
                  <span className="text-sm font-bold" style={{ color: item.done ? '#16a34a' : '#1a2e22', textDecoration: item.done ? 'line-through' : 'none' }}>{item.label}</span>
                  <input type="text" value={item.note || ''} onChange={e => updateItem(idx, 'note', e.target.value)}
                    placeholder="Poznámka…" className="w-full rounded text-xs outline-none mt-0.5"
                    style={{ padding: '2px 5px', background: '#fff', border: '1px solid #e5e7eb' }} />
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      <div className="mt-2">
        <div className="text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Popis servisu</div>
        <textarea value={desc} onChange={e => setDesc(e.target.value)} placeholder="Popis servisu…"
          className="w-full rounded-btn text-sm outline-none" rows={2}
          style={{ padding: '6px 10px', background: '#fff', border: '1px solid #d4e8e0', resize: 'vertical' }} />
      </div>

      <div className="flex gap-2 mt-3 justify-end flex-wrap">
        <Button onClick={saveAll} disabled={saving} style={{ fontSize: 13, padding: '6px 12px' }}>{saving ? 'Ukládám…' : 'Uložit změny'}</Button>
        <Button green onClick={markCompleted} disabled={ending} style={{ fontSize: 13, padding: '6px 12px' }}>{ending ? 'Dokončuji…' : 'Ukončit servis'}</Button>
      </div>
    </div>
  )
}

async function shiftTireSchedule(motoId, currentMileage) {
  const { data: schedules } = await supabase.from('maintenance_schedules')
    .select('id, interval_km, description').eq('moto_id', motoId).eq('active', true)
  const tireSchedule = schedules?.find(s => (s.description || '').toLowerCase().includes('pneumatik') || (s.description || '').toLowerCase().includes('tire'))
  if (tireSchedule) {
    await supabase.from('maintenance_schedules').update({
      last_service_km: Number(currentMileage) || 0,
      last_performed: new Date().toISOString().slice(0, 10),
    }).eq('id', tireSchedule.id)
  }
}
