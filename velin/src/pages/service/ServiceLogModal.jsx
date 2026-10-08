import { useState, useEffect, useMemo } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import ServiceChecklistPicker from '../../components/fleet/ServiceChecklistPicker'
import { customLabelsFromItems, labelsToItems } from '../../components/fleet/CustomServiceItems'
import { SERVICE_TASKS, TASK_BY_ID } from '../../components/fleet/serviceCatalog'
import { SERVICE_LABEL_TO_ID } from '../../components/fleet/motoActionConstants'
import { useAdminIdentity } from '../../hooks/useAdminIdentity'
import { LOG_TYPE_LABELS, todayIso, audit } from '../../lib/serviceBook'
import { inputStyle, Field, TechnicianSelect, CostFields, STATUS_OPTIONS, SERVICE_TYPE_OPTIONS } from './ServiceFormFields'
import ServiceInvoicesPanel from './ServiceInvoicesPanel'

/**
 * Servisní záznam (nový / úprava). Zadání majitele: zadání + zpráva technika, km automaticky,
 * technik = přihlášený účet, rozšířený checklist + neomezené „Jiné“, faktury k servisu.
 * Props: entry (editace) | motoId (předvolená motorka), defaultStatus, onClose, onSaved(logId)
 */
export default function ServiceLogModal({ entry, motoId: presetMotoId, defaultStatus = 'pending', onClose, onSaved }) {
  const me = useAdminIdentity()
  const [motos, setMotos] = useState([])
  const [form, setForm] = useState(() => entry ? {
    moto_id: entry.moto_id || '', service_type: entry.service_type || 'extraordinary', type: entry.type || '', status: entry.status || 'pending',
    service_from: (entry.service_date || '').slice(0, 10), scheduled_date: (entry.scheduled_date || '').slice(0, 10), completed_date: (entry.completed_date || '').slice(0, 10),
    km: entry.km_auto ? '' : (entry.km_at_service ?? ''), description: entry.description || '', technician_report: entry.technician_report || '',
    is_urgent: !!entry.is_urgent, labor_hours: entry.labor_hours || '', extra_cost: entry.extra_cost || '', cost: entry.cost || '',
    technician_admin_id: entry.technician_admin_id || null, technician_id: entry.technician_id || null, performed_by: entry.performed_by || '',
  } : {
    moto_id: presetMotoId || '', service_type: 'extraordinary', type: '', status: defaultStatus, service_from: todayIso(), scheduled_date: '', completed_date: '',
    km: '', description: '', technician_report: '', is_urgent: false, labor_hours: '', extra_cost: '', cost: '',
    technician_admin_id: null, technician_id: null, performed_by: '',
  })
  const [checked, setChecked] = useState(() => {
    const s = new Set()
    for (const it of (entry?.items || [])) { const id = it?.key || SERVICE_LABEL_TO_ID[it?.label]; if (id && TASK_BY_ID[id]) s.add(id) }
    return s
  })
  const [customLabels, setCustomLabels] = useState(() => customLabelsFromItems(entry?.items))
  const [showCosts, setShowCosts] = useState(!!(entry?.cost || entry?.labor_hours || entry?.extra_cost))
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)

  useEffect(() => {
    supabase.from('motorcycles').select('id, model, spz, tracking_unit, mileage, drivetrain, engine_type, status, branch_id').neq('status', 'retired').order('model').then(({ data }) => setMotos(data || []))
  }, [])

  const moto = useMemo(() => motos.find(m => m.id === form.moto_id), [motos, form.moto_id])
  const unit = moto?.tracking_unit === 'mh' ? 'MH' : 'km'
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))
  const toggle = (id) => setChecked(s => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n })
  const isNew = !entry
  const technician = { technician_admin_id: form.technician_admin_id, technician_id: form.technician_id, performed_by: form.performed_by }
  const needsReport = form.status === 'completed' || form.status === 'in_service'

  function buildItems() {
    const done = form.status === 'completed'
    const labels = SERVICE_TASKS.filter(t => checked.has(t.id)).map(t => t.label)
    const items = labelsToItems(labels, [], done)
    // zachovat poznámky / stav odškrtnutí z existujícího záznamu
    if (entry?.items?.length) {
      const prev = Object.fromEntries(entry.items.filter(i => i?.label).map(i => [i.label, i]))
      return items.map(i => prev[i.label] ? { ...i, note: prev[i.label].note || '', done: done || !!prev[i.label].done } : i)
        .concat(labelsToItems(customLabels, [], done).filter(c => !items.some(i => i.label === c.label)).map(c => prev[c.label] ? { ...c, note: prev[c.label].note || '', done: done || !!prev[c.label].done } : c))
    }
    return items.concat(labelsToItems(customLabels, [], done).filter(c => !items.some(i => i.label === c.label)))
  }

  async function handleSave() {
    if (!form.moto_id) { setErr('Vyberte motorku.'); return }
    const items = buildItems()
    if (items.length === 0 && !form.description.trim()) { setErr('Zaškrtněte aspoň jeden úkon nebo popište, co je potřeba.'); return }
    setSaving(true); setErr(null)
    try {
      debugLog('ServiceLog', 'handleSave', { isEdit: !!entry, moto_id: form.moto_id, status: form.status })
      const today = todayIso()
      const serviceFrom = form.service_from || today
      const goesToMaintenance = form.status === 'in_service' && serviceFrom <= today
      if (isNew && goesToMaintenance) {
        const { data: active } = await supabase.from('bookings').select('id, profiles(full_name)').eq('moto_id', form.moto_id).eq('status', 'active').gte('end_date', today)
        if (active?.length > 0 && !window.confirm(`Motorka má ${active.length} aktivní pronájem (${active.map(b => b.profiles?.full_name || '?').join(', ')}). Pokračovat? Zákazníkovi bude potřeba nabídnout náhradu.`)) { setSaving(false); return }
        const { data: future } = await supabase.from('bookings').select('id, start_date, end_date, profiles(full_name)').eq('moto_id', form.moto_id).in('status', ['pending', 'reserved']).gte('start_date', today).order('start_date').limit(5)
        if (future?.length > 0) window.alert(`Upozornění — nadcházející rezervace (${future.length}):\n${future.map(b => `  ${b.profiles?.full_name || '?'}: ${new Date(b.start_date).toLocaleDateString('cs-CZ')} – ${new Date(b.end_date).toLocaleDateString('cs-CZ')}`).join('\n')}\nMotorka musí být ze servisu zpět včas, nebo nabídněte náhradu.`)
      }
      const hourly = 500
      const calc = (Number(form.labor_hours) || 0) * hourly + (Number(form.extra_cost) || 0)
      const payload = {
        moto_id: form.moto_id, service_type: form.service_type || 'extraordinary', type: form.type || null, status: form.status,
        service_date: serviceFrom, scheduled_date: form.scheduled_date || null,
        completed_date: form.status === 'completed' ? (form.completed_date || today) : (form.completed_date || null),
        description: form.description.trim() || null, technician_report: form.technician_report.trim() || null,
        is_urgent: !!form.is_urgent, items,
        labor_hours: Number(form.labor_hours) || null, extra_cost: Number(form.extra_cost) || null, cost: Number(form.cost) || (calc || null),
        technician_admin_id: form.technician_admin_id || null, technician_id: form.technician_id || null, performed_by: form.performed_by?.trim() || null,
      }
      // km: zadané ručně se uloží, prázdné doplní DB ze stavu tachometru (km_auto)
      if (form.km !== '' && form.km !== null && form.km !== undefined) payload.km_at_service = Number(form.km)
      else if (isNew) payload.km_at_service = null
      let logId = entry?.id
      if (entry) {
        const { error } = await debugAction('maintenance_log.update', 'ServiceLog', () => supabase.from('maintenance_log').update(payload).eq('id', entry.id))
        if (error) throw error
      } else {
        const { data, error } = await debugAction('maintenance_log.insert', 'ServiceLog', () => supabase.from('maintenance_log').insert(payload).select('id').single())
        if (error) throw error
        logId = data?.id
      }
      // stav motorky řeší DB (sync_moto_service_status); ruční dokončení → aktivní jen když nemá jiný otevřený servis
      if (form.status === 'completed') {
        const { data: other } = await supabase.from('maintenance_log').select('id').eq('moto_id', form.moto_id).is('completed_date', null).neq('id', logId || '00000000-0000-0000-0000-000000000000').limit(1)
        if (!other?.length) await supabase.from('motorcycles').update({ status: 'active' }).eq('id', form.moto_id).eq('status', 'maintenance')
      }
      await audit(entry ? 'service_updated' : 'service_created', { moto_id: form.moto_id, log_id: logId, status: form.status })
      onSaved?.(logId)
    } catch (e) { debugError('ServiceLog', 'handleSave', e); setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title={entry ? 'Upravit servisní záznam' : 'Nový servisní záznam'} onClose={onClose} wide>
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <Field label="Motorka" className="sm:col-span-2">
          <select value={form.moto_id} onChange={e => set('moto_id', e.target.value)} disabled={!!entry} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            <option value="">— vyberte —</option>
            {motos.map(m => <option key={m.id} value={m.id}>{m.model} ({m.spz || 'bez SPZ'}) · {Number(m.mileage || 0).toLocaleString('cs-CZ')} {m.tracking_unit === 'mh' ? 'MH' : 'km'}</option>)}
          </select>
        </Field>
        <Field label="Stav">
          <select value={form.status} onChange={e => set('status', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            {STATUS_OPTIONS.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
          </select>
        </Field>
        <Field label="Druh servisu">
          <select value={form.service_type} onChange={e => set('service_type', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            {SERVICE_TYPE_OPTIONS.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
          </select>
        </Field>
        <Field label="Servis od"><input type="date" value={form.service_from} onChange={e => set('service_from', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></Field>
        <Field label="Plánované dokončení"><input type="date" value={form.scheduled_date} min={form.service_from} onChange={e => set('scheduled_date', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></Field>
        {form.status === 'completed' && <Field label="Skutečné dokončení"><input type="date" value={form.completed_date} onChange={e => set('completed_date', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></Field>}
        <Field label={`${unit} při servisu`} hint={moto ? `auto: ${Number(moto.mileage || 0).toLocaleString('cs-CZ')} ${unit} (stav tachometru)` : 'doplní se automaticky'}>
          <input type="number" value={form.km} onChange={e => set('km', e.target.value)} placeholder={moto ? `${Number(moto.mileage || 0).toLocaleString('cs-CZ')} — automaticky` : 'automaticky'} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </Field>
        <Field label="Kategorie (servisní kniha)" className="sm:col-span-2">
          <div className="flex items-center gap-3 flex-wrap">
            <select value={form.type} onChange={e => set('type', e.target.value)} className="rounded-btn text-sm outline-none" style={{ ...inputStyle, minWidth: 220 }}>
              <option value="">— dle úkonů —</option>
              {Object.entries(LOG_TYPE_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </select>
            <label className="flex items-center gap-2 cursor-pointer p-2 rounded" style={{ background: form.is_urgent ? '#fef2f2' : '#f1faf7', border: `1px solid ${form.is_urgent ? '#dc2626' : '#d4e8e0'}` }}>
              <input type="checkbox" checked={form.is_urgent} onChange={e => set('is_urgent', e.target.checked)} style={{ accentColor: '#dc2626', width: 16, height: 16 }} />
              <span className="text-sm font-bold" style={{ color: form.is_urgent ? '#dc2626' : '#1a2e22' }}>URGENT</span>
            </label>
          </div>
        </Field>
      </div>

      <div className="mt-4">
        <Field label="Co je potřeba udělat" hint={`katalog ${SERVICE_TASKS.length} úkonů + vlastní „Jiné“ bez omezení`}>
          <ServiceChecklistPicker checked={checked} onToggle={toggle} customLabels={customLabels} onCustomChange={setCustomLabels} moto={moto} maxHeight={330} />
        </Field>
      </div>

      <div className="mt-4 grid grid-cols-1 gap-3">
        <Field label="Zadání / popis závady" hint="vstup do servisu — co se má udělat, co zákazník / obsluha hlásí">
          <textarea value={form.description} onChange={e => set('description', e.target.value)} rows={3} className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, resize: 'vertical' }} placeholder="Např. při brzdění vibrace v řídítkách, zkontrolovat kotouče; výměna oleje dle plánu…" />
        </Field>
        <Field label="Zpráva technika" hint={needsReport ? 'co bylo provedeno, zjištěno, vyměněno' : 'vyplní technik při servisu'}>
          <textarea value={form.technician_report} onChange={e => set('technician_report', e.target.value)} rows={needsReport ? 4 : 2} className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, resize: 'vertical', background: needsReport ? '#fffbeb' : inputStyle.background }} placeholder="Např. vyměněn olej 4 l + filtr, destičky přední 2 mm → vyměněny; zjištěn únik u víka ventilů — doporučuji přetěsnit…" />
        </Field>
      </div>

      <div className="mt-4">
        <Field label="Technik" hint="automaticky podle přihlášení">
          <TechnicianSelect value={technician} onChange={t => setForm(f => ({ ...f, ...t }))} me={me} />
        </Field>
      </div>

      <div className="mt-4">
        <button type="button" onClick={() => setShowCosts(s => !s)} className="text-sm font-extrabold uppercase tracking-wide cursor-pointer" style={{ background: 'none', border: 'none', color: '#2563eb', padding: 0 }}>
          {showCosts ? '▾' : '▸'} Náklady {entry?.invoiced_amount > 0 ? `· faktury ${Number(entry.invoiced_amount).toLocaleString('cs-CZ')} Kč` : ''}
        </button>
        {showCosts && <div className="mt-2"><CostFields form={form} set={set} invoiced={entry?.invoiced_amount || 0} /></div>}
      </div>

      <div className="mt-4"><ServiceInvoicesPanel log={entry || null} moto={moto} compact /></div>

      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.moto_id}>{saving ? 'Ukládám…' : (form.status === 'completed' ? 'Uložit do servisní knížky' : 'Uložit')}</Button>
      </div>
    </Modal>
  )
}
