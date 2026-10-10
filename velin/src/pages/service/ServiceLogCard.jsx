import { useState, useEffect, useRef } from 'react'
import { supabase } from '../../lib/supabase'
import Button from '../../components/ui/Button'
import { useAdminIdentity } from '../../hooks/useAdminIdentity'
import { SERVICE_TYPE_LABELS, fmtDate, fmtKm, unitLabel, todayIso, audit } from '../../lib/serviceBook'
import { withItemKeys, labelsToItems } from '../../components/fleet/CustomServiceItems'
import ServiceChecklistPicker from '../../components/fleet/ServiceChecklistPicker'
import { SERVICE_TASKS } from '../../components/fleet/serviceCatalog'
import ServiceInvoicesPanel from './ServiceInvoicesPanel'
import ServiceLogModal from './ServiceLogModal'
import { technicianLocked } from './ServiceFormFields'

/**
 * Karta OTEVŘENÉHO servisu (Aktivní v servisu / servisní knížka): technik odškrtává úkony s poznámkou,
 * PŘIDÁVÁ úkony, které objevil navíc (katalog + „Jiné“), píše zprávu technika, nahrává faktury
 * a servis dokončí (km ze stavu tachometru, technik = login).
 */
export default function ServiceLogCard({ log, moto, onReload }) {
  const me = useAdminIdentity()
  const [items, setItems] = useState(() => withItemKeys(log.items || []))
  const [report, setReport] = useState(log.technician_report || '')
  const [returnDate, setReturnDate] = useState((log.scheduled_date || '').slice(0, 10))
  const [adding, setAdding] = useState(false)
  const [addChecked, setAddChecked] = useState(new Set())
  const [addCustom, setAddCustom] = useState([])
  const [saving, setSaving] = useState(false)
  const [ending, setEnding] = useState(false)
  const [edit, setEdit] = useState(false)
  const [err, setErr] = useState(null)
  const unit = unitLabel(moto)

  // neuložené změny technika (úkony, zpráva) nesmí přepsat reload (např. po nahrání faktury / realtime)
  const dirty = useRef(false)
  useEffect(() => {
    if (dirty.current) return
    setItems(withItemKeys(log.items || [])); setReport(log.technician_report || ''); setReturnDate((log.scheduled_date || '').slice(0, 10))
  }, [log.id, log.updated_at, log.items, log.technician_report, log.scheduled_date])

  const updateItem = (idx, field, value) => { dirty.current = true; setItems(prev => prev.map((it, i) => i === idx ? { ...it, [field]: value } : it)) }
  const setReportDirty = (v) => { dirty.current = true; setReport(v) }
  const setReturnDateDirty = (v) => { dirty.current = true; setReturnDate(v) }
  // superadmin: technik se zapisuje až při DOKONČENÍ (DB trigger = kdo dokončil), průběžné uložení ho nepřiřazuje;
  // běžný (servisní) účet zapisuje VŽDY pod sebou — nikdy za admina / jiného technika (hlídá i DB trigger)
  const locked = technicianLocked(me)
  const techPatch = () => locked ? { technician_admin_id: me.id, technician_id: null, performed_by: me.name }
    : (!log.technician_admin_id && me?.id) ? { technician_admin_id: me.id, performed_by: log.performed_by || me.name } : {}

  async function persist(nextItems, extra = {}) {
    setSaving(true); setErr(null)
    const { error } = await supabase.from('maintenance_log').update({ items: nextItems, technician_report: report.trim() || null, scheduled_date: returnDate || null, ...(locked ? techPatch() : {}), ...extra }).eq('id', log.id)
    setSaving(false)
    if (error) { setErr(error.message); return false }
    dirty.current = false
    return true
  }

  async function addTasks() {
    const labels = SERVICE_TASKS.filter(t => addChecked.has(t.id)).map(t => t.label).concat(addCustom)
    const fresh = labelsToItems(labels).filter(n => !items.some(i => i.label === n.label)).map(n => ({ ...n, added_by: me?.name || null, added_at: todayIso() }))
    if (fresh.length === 0) { setAdding(false); return }
    const next = [...items, ...fresh]
    setItems(next)
    if (await persist(next)) { await audit('service_items_added_by_technician', { log_id: log.id, labels: fresh.map(f => f.label) }); setAdding(false); setAddChecked(new Set()); setAddCustom([]); onReload() }
  }

  async function saveAll() { if (await persist(items)) onReload() }

  async function markCompleted() {
    const current = Number(moto?.mileage || 0)
    const kmStr = window.prompt(`Dokončit servis — stav tachometru při dokončení (${unit}):`, current ? String(current) : '')
    if (kmStr === null) return
    const km = Number(String(kmStr).replace(/\s/g, ''))
    if (kmStr !== '' && (!Number.isFinite(km) || km < 0)) { setErr('Neplatný stav tachometru.'); return }
    const open = items.filter(i => !i.done)
    if (open.length > 0 && !window.confirm(`${open.length} úkon(ů) není odškrtnuto (${open.slice(0, 3).map(i => i.label).join(', ')}${open.length > 3 ? '…' : ''}). Neodškrtnuté se do servisní knížky nezapíší jako provedené. Dokončit přesto?`)) return
    setEnding(true); setErr(null)
    const payload = { completed_date: todayIso(), status: 'completed', items, technician_report: report.trim() || null, ...techPatch() }
    if (kmStr !== '' && km !== Number(log.km_at_service)) payload.km_at_service = km
    const { error } = await supabase.from('maintenance_log').update(payload).eq('id', log.id)
    if (error) { setEnding(false); setErr(error.message); return }
    dirty.current = false
    const { data: other } = await supabase.from('maintenance_log').select('id').eq('moto_id', log.moto_id).is('completed_date', null).neq('id', log.id).limit(1)
    if (!other?.length) await supabase.from('motorcycles').update({ status: 'active' }).eq('id', log.moto_id).eq('status', 'maintenance')
    await supabase.from('service_orders').update({ status: 'completed', completed_at: new Date().toISOString() }).eq('maintenance_log_id', log.id).in('status', ['pending', 'in_service'])
    await audit('service_completed', { log_id: log.id, moto_id: log.moto_id, km })
    setEnding(false)
    onReload()
  }

  const isUrgent = log.is_urgent
  const doneCount = items.filter(i => i.done).length
  const Chip = ({ title, children }) => <div><div className="text-xs font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>{title}</div><div className="text-sm" style={{ color: '#1a2e22' }}>{children}</div></div>

  return (
    <div className="p-3 rounded-lg" style={{ background: isUrgent ? '#fef2f2' : '#f1faf7', border: `1px solid ${isUrgent ? '#fca5a5' : '#d4e8e0'}` }}>
      <div className="flex items-start gap-4 mb-2 flex-wrap">
        <Chip title="Typ">{SERVICE_TYPE_LABELS[log.service_type] || '—'}{isUrgent && <span className="ml-1 text-xs font-bold px-1.5 py-0.5 rounded" style={{ background: '#dc2626', color: '#fff' }}>URGENT</span>}</Chip>
        <Chip title="Servis od">{fmtDate(log.service_date || log.created_at)}</Chip>
        <div><div className="text-xs font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Plán. dokončení</div>
          <input type="date" value={returnDate} onChange={e => setReturnDateDirty(e.target.value)} className="rounded text-sm outline-none" style={{ padding: '2px 6px', background: '#fff', border: '1px solid #d4e8e0', width: 140 }} /></div>
        <Chip title={unit}>{fmtKm(log.km_at_service, '')}{log.km_auto && <span className="text-xs ml-1" style={{ color: '#6b7280' }} title="Doplněno automaticky ze stavu tachometru">auto</span>}</Chip>
        <Chip title="Technik">{log.performed_by || <span style={{ color: '#6b7280' }}>zapíše se podle loginu</span>}</Chip>
        <div className="ml-auto"><button onClick={() => setEdit(true)} className="text-xs font-bold cursor-pointer rounded-btn px-2.5 py-1 max-lg:py-2 max-lg:px-3.5" style={{ background: '#dbeafe', color: '#2563eb', border: 'none' }}>Upravit záznam</button></div>
      </div>

      {log.description && <div className="text-sm p-2 rounded mb-2" style={{ background: '#fff', border: '1px solid #d4e8e0', color: '#0f1a14', whiteSpace: 'pre-wrap' }}><span className="font-extrabold">Zadání: </span>{log.description}</div>}

      <div className="p-2 rounded-lg mb-2" style={{ background: '#fff', border: '1px solid #d4e8e0' }}>
        <div className="flex items-center gap-2 mb-1">
          <span className="text-xs font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Úkony <span style={{ color: '#1a8a18' }}>{doneCount}/{items.length}</span></span>
          <button onClick={() => setAdding(a => !a)} className="ml-auto text-xs font-extrabold uppercase cursor-pointer rounded-btn px-2.5 py-[3px] max-lg:py-2 max-lg:px-3.5" style={{ background: adding ? '#f3f4f6' : '#74FB71', color: '#1a2e22', border: 'none' }} title="Technik přidá úkon, který zjistil navíc (nebyl objednaný)">{adding ? 'Zavřít' : '+ Přidat úkon'}</button>
        </div>
        {items.length === 0 && !adding && <div className="text-xs" style={{ color: '#9ca3af' }}>Bez úkonů — přidejte, co se dělá.</div>}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-1">
          {items.map((item, idx) => (
            <div key={idx} className="flex items-start gap-2 p-1.5 rounded" style={{ background: item.done ? '#dcfce7' : '#f9fafb' }}>
              <input type="checkbox" checked={!!item.done} onChange={e => updateItem(idx, 'done', e.target.checked)} style={{ marginTop: 3, accentColor: '#16a34a', width: 16, height: 16, cursor: 'pointer' }} />
              <div className="flex-1 min-w-0">
                <span className="text-sm font-bold" style={{ color: item.done ? '#16a34a' : '#1a2e22' }}>{item.custom && <span title="Vlastní úkon (Jiné)">✎ </span>}{item.label}{item.added_by && <span className="text-xs font-normal" style={{ color: '#b45309' }} title="Přidal technik navíc"> · navíc ({item.added_by})</span>}{item.done_legacy && <span className="text-xs font-normal" style={{ color: '#9ca3af' }} title="Historický záznam ze staré verze — odškrtnuto automaticky"> · historicky</span>}</span>
                <input type="text" value={item.note || ''} onChange={e => updateItem(idx, 'note', e.target.value)} placeholder="Poznámka technika (díl, nález, cena…)" className="w-full rounded text-xs outline-none mt-0.5" style={{ padding: '2px 5px', background: '#fff', border: '1px solid #e5e7eb' }} />
              </div>
            </div>
          ))}
        </div>
        {adding && (
          <div className="mt-2 p-2 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #74FB71' }}>
            <div className="text-xs font-bold mb-1" style={{ color: '#1a2e22' }}>Zjistili jste něco navíc? Zaškrtněte úkon (nebo vypište jako „Jiné“) a přidejte do tohoto servisu.</div>
            <ServiceChecklistPicker checked={addChecked} onToggle={id => setAddChecked(s => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n })} customLabels={addCustom} onCustomChange={setAddCustom} moto={moto} compact maxHeight={260} />
            <div className="flex justify-end gap-2 mt-2"><Button small onClick={() => setAdding(false)}>Zrušit</Button><Button small green onClick={addTasks} disabled={saving || (addChecked.size === 0 && addCustom.length === 0)}>{saving ? 'Ukládám…' : `Přidat do servisu (${addChecked.size + addCustom.length})`}</Button></div>
          </div>
        )}
      </div>

      <div className="mb-2">
        <div className="text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#b45309' }}>Zpráva technika — co bylo provedeno / zjištěno / vyměněno</div>
        <textarea value={report} onChange={e => setReportDirty(e.target.value)} rows={3} placeholder="Např. vyměněn olej 4 l Motul 7100 + filtr; destičky přední 1,5 mm → vyměněny; zjištěno: vůle v ložisku řízení — doporučuji výměnu do 2 000 km."
          className="w-full rounded-btn text-sm outline-none" style={{ padding: '6px 10px', background: '#fffbeb', border: '1px solid #fde68a', resize: 'vertical' }} />
      </div>

      <ServiceInvoicesPanel log={log} moto={moto} onChanged={onReload} compact />

      {err && <div className="text-sm mt-2" style={{ color: '#dc2626' }}>{err}</div>}
      <div className="flex gap-2 mt-3 justify-end flex-wrap">
        <Button onClick={saveAll} disabled={saving} style={{ fontSize: 13, padding: '6px 12px' }}>{saving ? 'Ukládám…' : 'Uložit průběh'}</Button>
        <Button green onClick={markCompleted} disabled={ending} style={{ fontSize: 13, padding: '6px 12px' }}>{ending ? 'Dokončuji…' : 'Dokončit servis'}</Button>
      </div>
      {edit && <ServiceLogModal entry={log} onClose={() => setEdit(false)} onSaved={() => { setEdit(false); onReload() }} />}
    </div>
  )
}
