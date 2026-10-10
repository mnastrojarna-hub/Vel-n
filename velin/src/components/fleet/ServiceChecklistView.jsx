import { useState, useMemo } from 'react'
import Button from '../ui/Button'
import { SERVICE_TASKS, TASK_BY_ID } from './serviceCatalog'
import { SERVICE_LABEL_TO_ID } from './motoActionConstants'
import ServiceChecklistPicker from './ServiceChecklistPicker'
import { customLabelsFromItems } from './CustomServiceItems'

/**
 * Checklist „Odeslat do servisu“ / „Upravit servisní plán“ (Správa motorky, Naplánovat servis).
 * Výběr úkonů = ServiceChecklistPicker (katalog + neomezené „Jiné“). API beze změny:
 * onConfirm({ selected, selectedLabels, fullDescription, isUrgent, serviceDateFrom, serviceDateTo }).
 */
export default function ServiceChecklistView({ moto, onConfirm, onBack, busy, error, initialData, editMode }) {
  const defaults = useMemo(() => {
    const today = new Date().toLocaleDateString('sv-SE')
    if (!initialData) return { checks: new Set(), custom: [], urgent: false, from: today, to: '', note: '' }
    const checks = new Set()
    for (const item of (initialData.items || [])) { const id = item?.key || SERVICE_LABEL_TO_ID[item?.label]; if (id && TASK_BY_ID[id]) checks.add(id) }
    return {
      checks, custom: customLabelsFromItems(initialData.items), urgent: !!initialData.is_urgent,
      from: initialData.service_date?.slice(0, 10) || today, to: initialData.scheduled_date?.slice(0, 10) || '', note: initialData.description || '',
    }
  }, [initialData])

  const [checked, setChecked] = useState(defaults.checks)
  const [customLabels, setCustomLabels] = useState(defaults.custom)
  const [isUrgent, setIsUrgent] = useState(defaults.urgent)
  const [serviceDateFrom, setServiceDateFrom] = useState(defaults.from)
  const [serviceDateTo, setServiceDateTo] = useState(defaults.to)
  const [note, setNote] = useState(defaults.note)
  const toggle = (id) => setChecked(s => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n })
  const checkedCount = checked.size + customLabels.length

  function handleConfirm() {
    const selected = SERVICE_TASKS.filter(t => checked.has(t.id)).map(t => t.id)
    // štítky, které tento formulář nenabízí (SOS typy události), se zachovají
    const passthrough = (initialData?.items || []).filter(it => { const id = it?.key || SERVICE_LABEL_TO_ID[it?.label]; return id && !TASK_BY_ID[id] }).map(it => it.label)
    const selectedLabels = SERVICE_TASKS.filter(t => checked.has(t.id)).map(t => t.label).concat(passthrough, customLabels)
    const fullDescription = note.trim() || null
    if (!fullDescription && selectedLabels.length === 0) return
    onConfirm({ selected, selectedLabels, fullDescription, isUrgent, serviceDateFrom, serviceDateTo })
  }

  const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }
  return (
    <div>
      <div className="mb-3 p-3 rounded-lg" style={{ background: editMode ? '#dbeafe' : '#fef3c7', border: `1px solid ${editMode ? '#93c5fd' : '#fde68a'}` }}>
        <div className="text-sm font-bold" style={{ color: editMode ? '#2563eb' : '#b45309' }}>
          {editMode ? 'Upravte servisní plán — zaškrtnuté úkony a zadání se aktualizují.' : 'Zaškrtněte, co je potřeba opravit / zkontrolovat (hledejte nebo rozbalte skupiny), a doplňte zadání pro technika.'}
        </div>
      </div>

      <div className="mb-4"><ServiceChecklistPicker checked={checked} onToggle={toggle} customLabels={customLabels} onCustomChange={setCustomLabels} moto={moto} compact maxHeight={340} /></div>

      <div className="mb-4">
        <label className="flex items-center gap-2 cursor-pointer p-2 rounded" style={{ background: isUrgent ? '#fef2f2' : '#f1faf7', border: `1px solid ${isUrgent ? '#dc2626' : '#d4e8e0'}` }}>
          <input type="checkbox" checked={isUrgent} onChange={e => setIsUrgent(e.target.checked)} style={{ accentColor: '#dc2626', width: 18, height: 18 }} />
          <span className="text-sm font-bold" style={{ color: isUrgent ? '#dc2626' : '#1a2e22' }}>URGENT — Mimořádný/SOS servis</span>
        </label>
      </div>

      <div className="grid grid-cols-2 gap-3 mb-4">
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Servis od</label>
          <input type="date" value={serviceDateFrom} onChange={e => setServiceDateFrom(e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Plánované dokončení</label>
          <input type="date" value={serviceDateTo} onChange={e => setServiceDateTo(e.target.value)} min={serviceDateFrom} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
      </div>

      <div className="mb-4">
        <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Zadání / popis závady</label>
        <textarea value={note} onChange={e => setNote(e.target.value)} placeholder="Popište závadu, okolnosti, další info pro technika…" rows={3}
          className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, resize: 'vertical' }} />
        <div className="text-xs mt-1" style={{ color: '#6b7280' }}>Km při servisu a jméno technika se doplní automaticky (stav tachometru, přihlášený účet).</div>
      </div>

      {error && <div className="mb-3 p-2 rounded text-sm" style={{ background: '#fee2e2', color: '#dc2626' }}>{error}</div>}

      <div className="flex items-center justify-between max-md:flex-wrap max-md:gap-2">
        <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>{checkedCount > 0 ? `Zaškrtnuto: ${checkedCount} úkonů` : 'Nic nezaškrtnuto'}</span>
        <div className="flex gap-2 max-md:ml-auto">
          <Button onClick={onBack}>Zpět</Button>
          <Button green onClick={handleConfirm} disabled={busy || (!note.trim() && checkedCount === 0)}>
            {busy ? (editMode ? 'Ukládám…' : 'Odesílám…') : (editMode ? 'Uložit změny' : 'Odeslat do servisu')}
          </Button>
        </div>
      </div>
    </div>
  )
}
