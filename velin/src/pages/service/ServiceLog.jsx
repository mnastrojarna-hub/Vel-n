import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'

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
  const [logs, setLogs] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [filters, setFilters] = useState({ search: '', type: '' })
  const [showAdd, setShowAdd] = useState(false)
  const [editing, setEditing] = useState(null)

  useEffect(() => { load() }, [page, filters])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      let query = supabase
        .from('maintenance_log')
        .select('*, motorcycles(model, spz)', { count: 'exact' })
      if (filters.type) query = query.eq('type', filters.type)
      if (filters.search) query = query.or(`motorcycles.model.ilike.%${filters.search}%,motorcycles.spz.ilike.%${filters.search}%`)
      query = query.order('created_at', { ascending: false }).range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      const { data, count, error: err } = await query
      if (err) throw err
      setLogs(data || [])
      setTotal(count || 0)
    } catch (e) { setError(e.message) }
    finally { setLoading(false) }
  }

  const totalPages = Math.ceil(total / PER_PAGE)
  const fmt = (n) => n ? `${n.toLocaleString('cs-CZ')} Kč` : '—'

  return (
    <div>
      <div className="flex flex-wrap items-center gap-3 mb-4">
        <SearchInput value={filters.search} onChange={v => { setPage(1); setFilters(f => ({ ...f, search: v })) }} placeholder="Hledat motorku…" />
        <select value={filters.type} onChange={e => { setPage(1); setFilters(f => ({ ...f, type: e.target.value })) }}
          className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#4a6357' }}>
          <option value="">Všechny typy</option>
          {TYPES.map(t => <option key={t} value={t}>{TYPE_LABELS[t]}</option>)}
        </select>
        <div className="ml-auto">
          <Button green onClick={() => setShowAdd(true)}>+ Naplánovat servis</Button>
        </div>
      </div>

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Motorka</TH><TH>SPZ</TH><TH>Typ</TH><TH>Plán. datum</TH>
                <TH>Skut. datum</TH><TH>Náklady</TH><TH>Stav</TH><TH>Technik</TH>
              </TRow>
            </thead>
            <tbody>
              {logs.map(l => (
                <tr key={l.id} onClick={() => setEditing(l)} className="cursor-pointer hover:bg-[#f1faf7] transition-colors" style={{ borderBottom: '1px solid #d4e8e0' }}>
                  <TD bold>{l.motorcycles?.model || '—'}</TD>
                  <TD mono>{l.motorcycles?.spz || '—'}</TD>
                  <TD>{TYPE_LABELS[l.type] || l.type || '—'}</TD>
                  <TD>{l.created_at ? new Date(l.created_at).toLocaleDateString('cs-CZ') : '—'}</TD>
                  <TD>{l.completed_date ? new Date(l.completed_date).toLocaleDateString('cs-CZ') : '—'}</TD>
                  <TD bold>{fmt(l.cost)}</TD>
                  <TD><StatusBadge status={l.status || 'pending'} /></TD>
                  <TD>{l.performed_by || '—'}</TD>
                </tr>
              ))}
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

function ServiceModal({ entry, onClose, onSaved }) {
  const [motos, setMotos] = useState([])
  const [form, setForm] = useState(entry ? {
    moto_id: entry.moto_id || '', type: entry.type || '', scheduled_date: entry.scheduled_date || '',
    completed_date: entry.completed_date || '', description: entry.description || '',
    cost: entry.cost || '', performed_by: entry.performed_by || '', status: entry.status || 'pending',
  } : { moto_id: '', type: '', scheduled_date: '', completed_date: '', description: '', cost: '', performed_by: '', status: 'pending' })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)

  useEffect(() => {
    supabase.from('motorcycles').select('id, model, spz').order('model').then(({ data }) => setMotos(data || []))
  }, [])

  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const { scheduled_date: _sd, ...rest } = form
      const payload = { ...rest, cost: Number(rest.cost) || null }
      if (entry) {
        const { error } = await supabase.from('maintenance_log').update(payload).eq('id', entry.id)
        if (error) throw error
      } else {
        const { error } = await supabase.from('maintenance_log').insert(payload)
        if (error) throw error
      }
      if (form.status === 'completed' && form.moto_id) {
        await supabase.from('motorcycles').update({ status: 'active', last_service_date: new Date().toISOString().slice(0, 10) }).eq('id', form.moto_id)
      }
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: entry ? 'service_updated' : 'service_created', details: { moto_id: form.moto_id } })
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

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
        <div><Label>Plánované datum</Label><input type="date" value={form.scheduled_date} onChange={e => set('scheduled_date', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Skutečné datum</Label><input type="date" value={form.completed_date} onChange={e => set('completed_date', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Náklady (Kč)</Label><input type="number" value={form.cost} onChange={e => set('cost', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Technik</Label><input type="text" value={form.performed_by} onChange={e => set('performed_by', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div className="col-span-2"><Label>Popis</Label><textarea value={form.description} onChange={e => set('description', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, minHeight: 60, resize: 'vertical' }} /></div>
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
  return <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>{children}</label>
}
