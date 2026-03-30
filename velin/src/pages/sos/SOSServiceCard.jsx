import { useState, useMemo } from 'react'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import { SERVICE_CHECKLIST } from '../../components/fleet/motoActionConstants'

const SOS_SERVICE_TYPES = [
  { id: 'sos_accident_major', label: 'Těžká nehoda' },
  { id: 'sos_accident_minor', label: 'Lehká nehoda' },
  { id: 'sos_breakdown', label: 'Porucha' },
  { id: 'sos_theft_damage', label: 'Poškození při krádeži' },
]

// Build reverse map: label → id for pre-filling
const LABEL_TO_ID = {}
SERVICE_CHECKLIST.forEach(g => g.items.forEach(i => { LABEL_TO_ID[i.label] = i.id }))
SOS_SERVICE_TYPES.forEach(i => { LABEL_TO_ID[i.label] = i.id })

export default function SOSServiceCard({ incident, serviceLog, onUpdate, busy }) {
  const [expanded, setExpanded] = useState(!serviceLog?.items?.length)

  const defaults = useMemo(() => {
    if (!serviceLog) return { checks: {}, urgent: true, from: new Date().toISOString().slice(0, 10), to: '', note: '' }
    const checks = {}
    if (serviceLog.items?.length > 0) {
      for (const item of serviceLog.items) {
        const id = LABEL_TO_ID[item.label]
        if (id) checks[id] = true
      }
    }
    return {
      checks,
      urgent: serviceLog.is_urgent !== false,
      from: serviceLog.service_date?.slice(0, 10) || new Date().toISOString().slice(0, 10),
      to: serviceLog.scheduled_date?.slice(0, 10) || '',
      note: serviceLog.description || '',
    }
  }, [serviceLog?.id, serviceLog?.items, serviceLog?.description])

  const [checkedItems, setCheckedItems] = useState(defaults.checks)
  const [isUrgent, setIsUrgent] = useState(defaults.urgent)
  const [serviceDateFrom, setServiceDateFrom] = useState(defaults.from)
  const [serviceDateTo, setServiceDateTo] = useState(defaults.to)
  const [note, setNote] = useState(defaults.note)
  const [saved, setSaved] = useState(false)

  const checkedCount = Object.values(checkedItems).filter(Boolean).length
  const hasItems = serviceLog?.items?.length > 0

  async function handleSave() {
    const selected = Object.entries(checkedItems).filter(([, v]) => v).map(([k]) => k)
    const selectedLabels = []
    // SOS types first
    SOS_SERVICE_TYPES.forEach(i => { if (selected.includes(i.id)) selectedLabels.push(i.label) })
    // Then standard checklist
    SERVICE_CHECKLIST.forEach(g => g.items.forEach(i => { if (selected.includes(i.id)) selectedLabels.push(i.label) }))
    const fullDescription = note.trim() || null
    if (!fullDescription && selectedLabels.length === 0) return
    const result = await onUpdate({ selected, selectedLabels, fullDescription, isUrgent, serviceDateFrom, serviceDateTo })
    if (result?.success) {
      setSaved(true)
      setExpanded(false)
      setTimeout(() => setSaved(false), 3000)
    }
  }

  return (
    <Card>
      <div className="flex items-center justify-between mb-3">
        <h4 className="text-[10px] font-extrabold uppercase tracking-wider" style={{ color: '#dc2626' }}>
          URGENT Servisní záznam
        </h4>
        <div className="flex items-center gap-2">
          {hasItems && (
            <span className="text-xs px-2 py-0.5 rounded-full font-bold" style={{ background: '#dcfce7', color: '#166534' }}>
              {serviceLog.items.length} položek
            </span>
          )}
          {saved && (
            <span className="text-xs font-bold" style={{ color: '#16a34a' }}>Uloženo</span>
          )}
          <button onClick={() => setExpanded(!expanded)}
            className="text-xs font-bold px-2 py-1 rounded"
            style={{ background: '#f1faf7', color: '#1a2e22', border: '1px solid #d4e8e0' }}>
            {expanded ? 'Sbalit' : 'Upravit detaily'}
          </button>
        </div>
      </div>

      {/* Summary when collapsed */}
      {!expanded && (
        <div className="space-y-1">
          {hasItems && (
            <div className="flex flex-wrap gap-1">
              {serviceLog.items.map((item, i) => (
                <span key={i} className="text-xs px-2 py-0.5 rounded-full font-medium"
                  style={{ background: '#fef2f2', color: '#991b1b', border: '1px solid #fecaca' }}>
                  {item.label}
                </span>
              ))}
            </div>
          )}
          {serviceLog?.description && (
            <p className="text-sm" style={{ color: '#374151' }}>{serviceLog.description}</p>
          )}
          {!hasItems && !serviceLog?.description && (
            <p className="text-sm italic" style={{ color: '#9ca3af' }}>Detaily zatím nevyplněny — klikněte "Upravit detaily"</p>
          )}
        </div>
      )}

      {/* Expanded form */}
      {expanded && (
        <div>
          {/* SOS specific types */}
          <div className="mb-4">
            <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#dc2626' }}>Typ SOS události</div>
            <div className="grid grid-cols-2 gap-1">
              {SOS_SERVICE_TYPES.map(item => (
                <label key={item.id} className="flex items-center gap-2 p-2 rounded cursor-pointer"
                  style={{ background: checkedItems[item.id] ? '#fee2e2' : '#f1faf7', border: `1px solid ${checkedItems[item.id] ? '#dc2626' : '#d4e8e0'}` }}>
                  <input type="checkbox" checked={!!checkedItems[item.id]}
                    onChange={e => setCheckedItems(c => ({ ...c, [item.id]: e.target.checked }))}
                    style={{ accentColor: '#dc2626', width: 16, height: 16 }} />
                  <span className="text-sm" style={{ color: '#0f1a14', fontWeight: checkedItems[item.id] ? 700 : 400 }}>{item.label}</span>
                </label>
              ))}
            </div>
          </div>

          {/* Standard service checklist */}
          <div className="space-y-4 mb-4" style={{ maxHeight: 350, overflowY: 'auto' }}>
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

          {/* Urgent toggle */}
          <div className="mb-4">
            <label className="flex items-center gap-2 cursor-pointer p-2 rounded" style={{ background: isUrgent ? '#fef2f2' : '#f1faf7', border: `1px solid ${isUrgent ? '#dc2626' : '#d4e8e0'}` }}>
              <input type="checkbox" checked={isUrgent} onChange={e => setIsUrgent(e.target.checked)} style={{ accentColor: '#dc2626', width: 18, height: 18 }} />
              <span className="text-sm font-bold" style={{ color: isUrgent ? '#dc2626' : '#1a2e22' }}>URGENT — Mimořádný/SOS servis</span>
            </label>
          </div>

          {/* Date range */}
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

          {/* Description */}
          <div className="mb-4">
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Popis závady / okolnosti</label>
            <textarea value={note} onChange={e => setNote(e.target.value)}
              placeholder="Popište závadu, rozsah poškození, okolnosti nehody, další info pro technika…" rows={3}
              className="w-full rounded-btn text-sm outline-none"
              style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14', resize: 'vertical' }} />
          </div>

          {/* Actions */}
          <div className="flex items-center justify-between">
            <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>
              {checkedCount > 0 ? `Zaškrtnuto: ${checkedCount} položek` : 'Nic nezaškrtnuto'}
            </span>
            <div className="flex gap-2">
              <Button onClick={() => setExpanded(false)}>Zrušit</Button>
              <Button green onClick={handleSave} disabled={busy || (!note.trim() && checkedCount === 0)}>
                {busy ? 'Ukládám…' : 'Uložit servisní detaily'}
              </Button>
            </div>
          </div>
        </div>
      )}
    </Card>
  )
}
