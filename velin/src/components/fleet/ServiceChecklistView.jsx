import { useState, useMemo } from 'react'
import Button from '../ui/Button'
import { SERVICE_CHECKLIST } from './motoActionConstants'

// Build reverse map: label → id for pre-filling from existing log items
const LABEL_TO_ID = {}
SERVICE_CHECKLIST.forEach(g => g.items.forEach(i => { LABEL_TO_ID[i.label] = i.id }))

export default function ServiceChecklistView({ moto, onConfirm, onBack, busy, error, initialData, editMode }) {
  // Pre-fill from initialData (existing maintenance_log entry)
  const defaults = useMemo(() => {
    if (!initialData) return { checks: {}, urgent: false, from: new Date().toISOString().slice(0, 10), to: '', note: '' }
    const checks = {}
    if (initialData.items?.length > 0) {
      for (const item of initialData.items) {
        const id = LABEL_TO_ID[item.label]
        if (id) checks[id] = true
      }
    }
    return {
      checks,
      urgent: !!initialData.is_urgent,
      from: initialData.service_date?.slice(0, 10) || new Date().toISOString().slice(0, 10),
      to: initialData.scheduled_date?.slice(0, 10) || '',
      note: initialData.description || '',
    }
  }, [initialData])

  const [checkedItems, setCheckedItems] = useState(defaults.checks)
  const [isUrgent, setIsUrgent] = useState(defaults.urgent)
  const [serviceDateFrom, setServiceDateFrom] = useState(defaults.from)
  const [serviceDateTo, setServiceDateTo] = useState(defaults.to)
  const [note, setNote] = useState(defaults.note)

  const checkedCount = Object.values(checkedItems).filter(Boolean).length

  function handleConfirm() {
    const selected = Object.entries(checkedItems).filter(([, v]) => v).map(([k]) => k)
    const selectedLabels = []
    SERVICE_CHECKLIST.forEach(g => g.items.forEach(i => {
      if (selected.includes(i.id)) selectedLabels.push(i.label)
    }))
    const fullDescription = note.trim() || null
    if (!fullDescription && selectedLabels.length === 0) return
    onConfirm({ selected, selectedLabels, fullDescription, isUrgent, serviceDateFrom, serviceDateTo })
  }

  return (
    <div>
      <div className="mb-4 p-3 rounded-lg" style={{ background: editMode ? '#dbeafe' : '#fef3c7', border: `1px solid ${editMode ? '#93c5fd' : '#fde68a'}` }}>
        <div className="text-sm font-bold" style={{ color: editMode ? '#2563eb' : '#b45309' }}>
          {editMode ? 'Upravte servisní plán — zaškrtnuté položky a poznámka se aktualizují.' : 'Zaškrtněte co je potřeba opravit / zkontrolovat. Můžete přidat i vlastní poznámku.'}
        </div>
      </div>

      <div className="space-y-4 mb-4" style={{ maxHeight: 400, overflowY: 'auto' }}>
        {SERVICE_CHECKLIST.map(group => (
          <div key={group.group}>
            <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>{group.group}</div>
            <div className="grid grid-cols-2 gap-1">
              {group.items.map(item => (
                <label key={item.id} className="flex items-center gap-2 p-2 rounded cursor-pointer"
                  style={{ background: checkedItems[item.id] ? '#dcfce7' : '#f1faf7', border: `1px solid ${checkedItems[item.id] ? '#1a8a18' : '#d4e8e0'}` }}>
                  <input type="checkbox" checked={!!checkedItems[item.id]}
                    onChange={e => setCheckedItems(c => ({ ...c, [item.id]: e.target.checked }))}
                    className="accent-[#1a8a18]" style={{ width: 16, height: 16 }} />
                  <span className="text-sm" style={{ color: '#0f1a14', fontWeight: checkedItems[item.id] ? 700 : 400 }}>{item.label}</span>
                </label>
              ))}
            </div>
          </div>
        ))}
      </div>

      <div className="mb-4">
        <label className="flex items-center gap-2 cursor-pointer p-2 rounded" style={{ background: isUrgent ? '#fef2f2' : '#f1faf7', border: `1px solid ${isUrgent ? '#dc2626' : '#d4e8e0'}` }}>
          <input type="checkbox" checked={isUrgent} onChange={e => setIsUrgent(e.target.checked)} style={{ accentColor: '#dc2626', width: 18, height: 18 }} />
          <span className="text-sm font-bold" style={{ color: isUrgent ? '#dc2626' : '#1a2e22' }}>URGENT — Mimořádný/SOS servis</span>
        </label>
      </div>

      <div className="grid grid-cols-2 gap-3 mb-4">
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Servis od</label>
          <input type="date" value={serviceDateFrom} onChange={e => setServiceDateFrom(e.target.value)}
            className="w-full rounded-btn text-sm outline-none"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }} />
        </div>
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Plánované dokončení</label>
          <input type="date" value={serviceDateTo} onChange={e => setServiceDateTo(e.target.value)} min={serviceDateFrom}
            className="w-full rounded-btn text-sm outline-none"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }} />
        </div>
      </div>

      <div className="mb-4">
        <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Doplňující poznámka</label>
        <textarea value={note} onChange={e => setNote(e.target.value)}
          placeholder="Popište závadu, okolnosti, další info pro technika…" rows={3}
          className="w-full rounded-btn text-sm outline-none"
          style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14', resize: 'vertical' }} />
      </div>

      {error && <div className="mb-3 p-2 rounded text-sm" style={{ background: '#fee2e2', color: '#dc2626' }}>{error}</div>}

      <div className="flex items-center justify-between">
        <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>
          {checkedCount > 0 ? `Zaškrtnuto: ${checkedCount} položek` : 'Nic nezaškrtnuto'}
        </span>
        <div className="flex gap-2">
          <Button onClick={onBack}>Zpět</Button>
          <Button green onClick={handleConfirm} disabled={busy || (!note.trim() && checkedCount === 0)}>
            {busy ? (editMode ? 'Ukládám…' : 'Odesílám…') : (editMode ? 'Uložit změny' : 'Odeslat do servisu')}
          </Button>
        </div>
      </div>
    </div>
  )
}
