import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { useDebugMode } from '../../hooks/useDebugMode'

import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import StatusBadge from '../../components/ui/StatusBadge'
import SearchInput from '../../components/ui/SearchInput'
import Pagination from '../../components/ui/Pagination'
import Modal from '../../components/ui/Modal'
import { TYPE_LABELS } from './ServiceSchedule'

const PER_PAGE = 25
const TYPES = Object.keys(TYPE_LABELS)

export default function ServiceLog() {
  const debugMode = useDebugMode()
  const [logs, setLogs] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const defaultFilters = { search: '', types: [] }
  const [filters, setFilters] = useState(() => {
    try {
      const saved = localStorage.getItem('velin_servicelog_filters')
      if (saved) return { ...defaultFilters, ...JSON.parse(saved) }
    } catch {}
    return defaultFilters
  })
  useEffect(() => { localStorage.setItem('velin_servicelog_filters', JSON.stringify(filters)) }, [filters])
  const [showAdd, setShowAdd] = useState(false)
  const [editing, setEditing] = useState(null)
  const [expandedLog, setExpandedLog] = useState(null)

  useEffect(() => { load() }, [page, filters])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      debugLog('ServiceLog', 'load', { page, filters })
      let query = supabase
        .from('maintenance_log')
        .select('*, motorcycles(model, spz)', { count: 'exact' })
      if (filters.types?.length > 0) {
        const typeFilter = filters.types.map(t => `type.eq.${t},service_type.eq.${t}`).join(',')
        query = query.or(typeFilter)
      }
      if (filters.search) query = query.or(`motorcycles.model.ilike.%${filters.search}%,motorcycles.spz.ilike.%${filters.search}%`)
      query = query.order('created_at', { ascending: false }).range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      const { data, count, error: err } = await debugAction('maintenance_log.list', 'ServiceLog', () => query)
      if (err) throw err
      setLogs(data || [])
      setTotal(count || 0)
    } catch (e) { debugError('ServiceLog', 'load', e); setError(e.message) }
    finally { setLoading(false) }
  }

  const totalPages = Math.ceil(total / PER_PAGE)
  const fmt = (n) => n ? `${n.toLocaleString('cs-CZ')} Kč` : '—'

  return (
    <div>
      <div className="flex flex-wrap items-center gap-3 mb-4">
        <SearchInput value={filters.search} onChange={v => { setPage(1); setFilters(f => ({ ...f, search: v })) }} placeholder="Hledat motorku…" />
        <CheckboxFilterGroup label="Typ" values={filters.types || []}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, types: v })) }}
          options={TYPES.map(t => ({ value: t, label: TYPE_LABELS[t] }))} />
        <button onClick={() => { setPage(1); setFilters({ ...defaultFilters }); localStorage.removeItem('velin_servicelog_filters') }}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
          style={{ padding: '8px 14px', background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}>
          Reset
        </button>
        <div className="ml-auto">
          <Button green onClick={() => setShowAdd(true)}>+ Naplánovat servis</Button>
        </div>
      </div>

      {/* DIAGNOSTIKA */}
      {debugMode && (
      <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
        <strong>DIAGNOSTIKA ServiceLog</strong><br/>
        <div>logs: {logs.length} zobrazeno / {total} celkem (strana {page}/{totalPages || 1})</div>
        <div>filtry: types={filters.types?.length > 0 ? filters.types.join(',') : 'vše'}, search="{filters.search}"</div>
        {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
      </div>
      )}

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Motorka</TH><TH>SPZ</TH><TH>Typ</TH><TH>Do servisu</TH>
                <TH>Ze servisu</TH><TH>Km</TH><TH>Náklady</TH><TH>Stav</TH><TH>Technik</TH>
              </TRow>
            </thead>
            <tbody>
              {logs.map(l => {
                const startDate = l.scheduled_date || l.created_at
                const isExp = expandedLog === l.id
                return (
                  <LogRow key={l.id} log={l} km={l.km_at_service || l.mileage_at_service} startDate={startDate}
                    isExpanded={isExp}
                    onToggle={() => setExpandedLog(isExp ? null : l.id)}
                    onEdit={() => setEditing(l)} fmt={fmt} />
                )
              })}
              {logs.length === 0 && <TRow><TD>Žádné servisní záznamy</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {(showAdd || editing) && (
        <ServiceModal
          entry={editing}
          onClose={() => { setShowAdd(false); setEditing(null) }}
          onSaved={() => { setShowAdd(false); setEditing(null); load() }}
        />
      )}
    </div>
  )
}

function LogRow({ log: l, km, startDate, isExpanded, onToggle, onEdit, fmt }) {
  return (
    <>
      <tr onClick={onToggle} className="cursor-pointer hover:bg-[#f1faf7] transition-colors" style={{ borderBottom: isExpanded ? 'none' : '1px solid #d4e8e0' }}>
        <TD bold>{l.motorcycles?.model || '—'}</TD>
        <TD mono>{l.motorcycles?.spz || '—'}</TD>
        <TD>{TYPE_LABELS[l.type] || { regular: 'Pravidelný', extraordinary: 'Mimořádný', repair: 'Oprava' }[l.service_type] || l.type || '—'}</TD>
        <TD>{startDate ? new Date(startDate).toLocaleDateString('cs-CZ') : '—'}</TD>
        <TD>{l.completed_date ? new Date(l.completed_date).toLocaleDateString('cs-CZ') : '—'}</TD>
        <TD mono>{km ? km.toLocaleString('cs-CZ') : '—'}</TD>
        <TD bold>{fmt(l.cost)}</TD>
        <TD><StatusBadge status={l.status || 'pending'} /></TD>
        <TD>{l.performed_by || '—'}</TD>
      </tr>
      {isExpanded && (
        <tr style={{ borderBottom: '1px solid #d4e8e0' }}>
          <td colSpan={9} style={{ padding: '8px 12px', background: '#f1faf7' }}>
            {l.items && Array.isArray(l.items) && l.items.length > 0 && (
              <div className="mb-3">
                <span className="text-sm font-extrabold" style={{ color: '#1a2e22' }}>Servisní úkony:</span>
                <div className="flex flex-wrap gap-1 mt-1">
                  {l.items.map((it, i) => (
                    <span key={i} className="text-xs font-bold rounded-full" style={{
                      padding: '3px 10px',
                      background: it.done ? '#dcfce7' : '#fef3c7',
                      color: it.done ? '#166534' : '#b45309',
                      border: `1px solid ${it.done ? '#86efac' : '#fde68a'}`,
                    }}>
                      {it.done ? '✓ ' : ''}{it.label}
                    </span>
                  ))}
                </div>
              </div>
            )}
            <div className="text-sm" style={{ color: '#0f1a14' }}>
              <span className="font-extrabold">Servisní záznam: </span>
              {l.description || <span style={{ color: '#9ca3af' }}>Bez popisu</span>}
            </div>
            {l.planned_end && (
              <div className="text-sm mt-1" style={{ color: '#1a2e22' }}>
                <span className="font-extrabold">Plánované dokončení: </span>
                {new Date(l.planned_end).toLocaleDateString('cs-CZ')}
              </div>
            )}
            <button onClick={e => { e.stopPropagation(); onEdit() }}
              className="mt-2 rounded-btn text-sm font-bold cursor-pointer"
              style={{ padding: '4px 12px', background: '#dbeafe', color: '#2563eb', border: 'none' }}>
              Upravit
            </button>
          </td>
        </tr>
      )}
    </>
  )
}

/* ═══ Checklist categories for service booking ═══ */
const SERVICE_CHECKLIST = [
  { category: 'Motor & olej', items: [
    'Výměna oleje', 'Výměna olejového filtru', 'Výměna vzduchového filtru',
    'Výměna svíček', 'Kontrola / výměna chladicí kapaliny', 'Neobvyklý zvuk motoru',
  ]},
  { category: 'Brzdy & podvozek', items: [
    'Brzdové destičky přední', 'Brzdové destičky zadní', 'Výměna brzdové kapaliny',
    'Kontrola brzdových kotoučů', 'Kontrola tlumičů / pružin',
  ]},
  { category: 'Pneumatiky & kola', items: [
    'Výměna přední pneumatiky', 'Výměna zadní pneumatiky',
    'Kontrola tlaku pneumatik', 'Kontrola ložisek kol',
  ]},
  { category: 'Řetěz & převody', items: [
    'Seřízení řetězu', 'Výměna řetězu + rozet', 'Promazání řetězu',
  ]},
  { category: 'Elektrika & světla', items: [
    'Kontrola / výměna baterie', 'Kontrola světel',
    'Kontrola pojistek', 'Problém se startérem',
  ]},
  { category: 'Ostatní', items: [
    'Příprava na STK', 'Kontrola / seřízení spojky',
    'Kosmetická oprava (lak, plasty)', 'Oprava po nehodě', 'Jiná oprava',
  ]},
]

function ServiceModal({ entry, onClose, onSaved }) {
  const [motos, setMotos] = useState([])
  // Parse existing items from entry
  const existingChecked = new Set()
  if (entry?.items && Array.isArray(entry.items)) {
    entry.items.forEach(it => existingChecked.add(it.label))
  }
  const [form, setForm] = useState(entry ? {
    moto_id: entry.moto_id || '', type: entry.type || '', scheduled_date: entry.scheduled_date || '',
    completed_date: entry.completed_date || '', description: entry.description || '',
    cost: entry.cost || '', performed_by: entry.performed_by || '', status: entry.status || 'pending',
    mileage_at_service: entry.mileage_at_service || entry.km_at_service || '',
    service_from: entry.service_date || '', planned_end: entry.planned_end || '',
    extra_note: entry.extra_note || '',
  } : { moto_id: '', type: '', scheduled_date: '', completed_date: '', description: '', cost: '', performed_by: '', status: 'pending', mileage_at_service: '', service_from: '', planned_end: '', extra_note: '' })
  const [checkedItems, setCheckedItems] = useState(() => {
    const m = {}
    SERVICE_CHECKLIST.forEach(cat => cat.items.forEach(it => { m[it] = existingChecked.has(it) }))
    return m
  })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)

  useEffect(() => {
    supabase.from('motorcycles').select('id, model, spz').order('model').then(({ data }) => setMotos(data || []))
  }, [])

  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))
  const toggleCheck = (label) => setCheckedItems(c => ({ ...c, [label]: !c[label] }))

  // Build items array from checked checkboxes
  function buildItems() {
    const items = []
    SERVICE_CHECKLIST.forEach(cat => {
      cat.items.forEach(label => {
        if (checkedItems[label]) {
          items.push({ label, done: false, note: '' })
        }
      })
    })
    return items
  }

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      debugLog('ServiceLog', 'handleSave', { isEdit: !!entry, moto_id: form.moto_id })
      const TYPE_TO_SERVICE = { oil_change: 'regular', tire_change: 'regular', brake_check: 'regular', full_service: 'regular', inspection: 'regular', repair: 'repair' }
      const items = buildItems()
      // Build description from checked items + free text
      const checkedLabels = items.map(i => `- ${i.label}`)
      const descParts = []
      if (checkedLabels.length > 0) descParts.push(checkedLabels.join('\n'))
      if (form.description?.trim()) descParts.push(form.description.trim())
      if (form.extra_note?.trim()) descParts.push('Poznámka: ' + form.extra_note.trim())
      const fullDescription = descParts.join('\n\n') || null

      const payload = {
        moto_id: form.moto_id,
        type: form.type || null,
        service_type: TYPE_TO_SERVICE[form.type] || 'repair',
        description: fullDescription,
        cost: Number(form.cost) || null,
        km_at_service: Number(form.mileage_at_service) || null,
        performed_by: form.performed_by || null,
        status: form.status || 'pending',
        service_date: form.service_from || form.scheduled_date || new Date().toISOString().slice(0, 10),
        scheduled_date: form.scheduled_date || form.service_from || null,
        completed_date: form.completed_date || null,
        items: items.length > 0 ? items : null,
        planned_end: form.planned_end || null,
        extra_note: form.extra_note || null,
      }
      if (entry) {
        const { error } = await debugAction('maintenance_log.update', 'ServiceLog', () =>
          supabase.from('maintenance_log').update(payload).eq('id', entry.id))
        if (error) throw error
      } else {
        const { error } = await debugAction('maintenance_log.insert', 'ServiceLog', () =>
          supabase.from('maintenance_log').insert(payload))
        if (error) throw error
      }
      if (form.status === 'completed' && form.moto_id) {
        await supabase.from('motorcycles').update({ status: 'active', last_service_date: new Date().toISOString().slice(0, 10) }).eq('id', form.moto_id)
      }
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: entry ? 'service_updated' : 'service_created', details: { moto_id: form.moto_id } })
      onSaved()
    } catch (e) { debugError('ServiceLog', 'handleSave', e); setErr(e.message) } finally { setSaving(false) }
  }

  const checkedCount = Object.values(checkedItems).filter(Boolean).length

  return (
    <Modal open title={entry ? 'Upravit servis' : 'Nový servis'} onClose={onClose}>
      <div className="grid grid-cols-2 gap-3">
        <div className="col-span-2">
          <Label>Motorka</Label>
          <select value={form.moto_id} onChange={e => set('moto_id', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            <option value="">—</option>
            {motos.map(m => <option key={m.id} value={m.id}>{m.model} ({m.spz})</option>)}
          </select>
        </div>
        <div>
          <Label>Typ servisu</Label>
          <select value={form.type} onChange={e => set('type', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            <option value="">—</option>
            {TYPES.map(t => <option key={t} value={t}>{TYPE_LABELS[t]}</option>)}
          </select>
        </div>
        <div>
          <Label>Stav</Label>
          <select value={form.status} onChange={e => set('status', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            <option value="pending">Čekající</option>
            <option value="in_service">V servisu</option>
            <option value="completed">Dokončeno</option>
          </select>
        </div>
        <div><Label>Servis od</Label><input type="date" value={form.service_from} onChange={e => set('service_from', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Plánované dokončení</Label><input type="date" value={form.planned_end} onChange={e => set('planned_end', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Plánované datum</Label><input type="date" value={form.scheduled_date} onChange={e => set('scheduled_date', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Skutečné datum</Label><input type="date" value={form.completed_date} onChange={e => set('completed_date', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Km při servisu</Label><input type="number" value={form.mileage_at_service} onChange={e => set('mileage_at_service', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Náklady (Kč)</Label><input type="number" value={form.cost} onChange={e => set('cost', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div className="col-span-2"><Label>Technik</Label><input type="text" value={form.performed_by} onChange={e => set('performed_by', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
      </div>

      {/* ═══ Servisní checklist ═══ */}
      <div className="mt-4">
        <Label>Škrtněte co je potřeba opravit / zkontrolovat {checkedCount > 0 && <span style={{ color: '#1a8a18' }}>({checkedCount} vybráno)</span>}</Label>
        <div className="grid grid-cols-2 gap-3 mt-2">
          {SERVICE_CHECKLIST.map(cat => (
            <div key={cat.category} className="p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
              <div className="text-xs font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a8a18' }}>{cat.category}</div>
              <div className="space-y-1">
                {cat.items.map(label => (
                  <label key={label} className="flex items-center gap-2 cursor-pointer p-1 rounded hover:bg-[#e8fde8] transition-colors">
                    <input
                      type="checkbox"
                      checked={checkedItems[label] || false}
                      onChange={() => toggleCheck(label)}
                      style={{ accentColor: '#16a34a', width: 16, height: 16, cursor: 'pointer' }}
                    />
                    <span className="text-sm" style={{ color: '#1a2e22', fontWeight: checkedItems[label] ? 700 : 400 }}>{label}</span>
                  </label>
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>

      <div className="grid grid-cols-1 gap-3 mt-4">
        <div>
          <Label>Servisní záznam (volný text)</Label>
          <textarea value={form.description} onChange={e => set('description', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, minHeight: 60, resize: 'vertical' }} placeholder="Popište co vše se opravovalo / vyměnilo…" />
        </div>
        <div>
          <Label>Doplňující poznámka</Label>
          <textarea value={form.extra_note} onChange={e => set('extra_note', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, minHeight: 50, resize: 'vertical' }} placeholder="Vlastní poznámka k servisu…" />
        </div>
      </div>

      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.moto_id}>{saving ? 'Ukládám…' : 'Uložit'}</Button>
      </div>
    </Modal>
  )
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}

function CheckboxFilterGroup({ label, values, onChange, options }) {
  const toggle = val => {
    if (values.includes(val)) onChange(values.filter(v => v !== val))
    else onChange([...values, val])
  }
  return (
    <div className="flex items-center gap-1 flex-wrap rounded-btn"
      style={{ padding: '4px 10px', background: values.length > 0 ? '#e8fde8' : '#f1faf7', border: '1px solid #d4e8e0' }}>
      <span className="text-sm font-extrabold uppercase tracking-wide mr-1" style={{ color: '#1a2e22' }}>{label}:</span>
      {options.map(o => (
        <label key={o.value} className="flex items-center gap-1 cursor-pointer"
          style={{ padding: '3px 6px', borderRadius: 6, background: values.includes(o.value) ? '#74FB71' : 'transparent' }}>
          <input type="checkbox" checked={values.includes(o.value)} onChange={() => toggle(o.value)}
            className="accent-[#1a8a18]" style={{ width: 14, height: 14 }} />
          <span className="text-sm font-bold" style={{ color: '#1a2e22', whiteSpace: 'nowrap' }}>{o.label}</span>
        </label>
      ))}
    </div>
  )
}
