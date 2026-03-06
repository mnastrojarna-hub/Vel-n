import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import { Table, TRow, TH, TD } from '../components/ui/Table'
import Button from '../components/ui/Button'
import Card from '../components/ui/Card'
import Modal from '../components/ui/Modal'
import ConfirmDialog from '../components/ui/ConfirmDialog'
import SearchInput from '../components/ui/SearchInput'

export default function Branches() {
  const [branches, setBranches] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [search, setSearch] = useState('')
  const [showModal, setShowModal] = useState(false)
  const [editing, setEditing] = useState(null)
  const [deleteConfirm, setDeleteConfirm] = useState(null)
  const [stats, setStats] = useState({})

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    try {
      const { data, error: err } = await supabase
        .from('branches')
        .select('*')
        .order('name')
      if (err) throw err
      setBranches(data || [])
      // Load moto counts per branch
      const { data: motos } = await supabase
        .from('motorcycles')
        .select('branch_id, status')
      const s = {}
      ;(motos || []).forEach(m => {
        if (!m.branch_id) return
        if (!s[m.branch_id]) s[m.branch_id] = { total: 0, active: 0 }
        s[m.branch_id].total++
        if (m.status === 'active') s[m.branch_id].active++
      })
      setStats(s)
    } catch (e) { setError(e.message) }
    setLoading(false)
  }

  async function handleDelete(branch) {
    const result = await debugAction('branches.delete', 'Branches', () =>
      supabase.from('branches').delete().eq('id', branch.id)
    , { branch_id: branch.id, name: branch.name })
    if (result?.error) { setError(result.error.message); return }
    await logAudit('branch_deleted', { name: branch.name })
    setDeleteConfirm(null)
    load()
  }

  async function logAudit(action, details) {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, details })
    } catch {}
  }

  const filtered = branches.filter(b =>
    !search || b.name?.toLowerCase().includes(search.toLowerCase()) ||
    b.city?.toLowerCase().includes(search.toLowerCase())
  )

  return (
    <div>
      {/* Summary cards */}
      <div className="grid grid-cols-4 gap-3 mb-5">
        <StatCard label="Celkem poboček" value={branches.length} color="#0f1a14" />
        <StatCard label="Aktivní" value={branches.filter(b => b.active !== false).length} color="#1a8a18" />
        <StatCard label="Motorek celkem" value={Object.values(stats).reduce((s, v) => s + v.total, 0)} color="#2563eb" />
        <StatCard label="Aktivních motorek" value={Object.values(stats).reduce((s, v) => s + v.active, 0)} color="#b45309" />
      </div>

      <div className="flex items-center gap-3 mb-5">
        <SearchInput value={search} onChange={setSearch} placeholder="Hledat pobočku..." />
        <div className="ml-auto">
          <Button green onClick={() => { setEditing(null); setShowModal(true) }}>+ Nová pobočka</Button>
        </div>
      </div>

      {error && (
        <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>
          {error}
          <button onClick={load} className="ml-3 underline cursor-pointer">Zkusit znovu</button>
        </div>
      )}

      {loading ? (
        <div className="flex justify-center py-16">
          <div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" />
        </div>
      ) : (
        <Table>
          <thead>
            <TRow header>
              <TH>Název</TH><TH>Město</TH><TH>Adresa</TH><TH>Telefon</TH>
              <TH>Email</TH><TH>Motorky</TH><TH>Otevírací doba</TH><TH>Akce</TH>
            </TRow>
          </thead>
          <tbody>
            {filtered.map(b => (
              <TRow key={b.id}>
                <TD bold>{b.name}</TD>
                <TD>{b.city || '—'}</TD>
                <TD>{b.address || '—'}</TD>
                <TD mono>{b.phone || '—'}</TD>
                <TD>{b.email || '—'}</TD>
                <TD>
                  <span className="font-bold" style={{ color: '#1a8a18' }}>
                    {stats[b.id]?.active || 0}
                  </span>
                  <span style={{ color: '#8aab99' }}> / {stats[b.id]?.total || 0}</span>
                </TD>
                <TD>{b.opening_hours || '—'}</TD>
                <TD>
                  <div className="flex gap-1">
                    <SmallBtn color="#2563eb" onClick={() => { setEditing(b); setShowModal(true) }}>Upravit</SmallBtn>
                    <SmallBtn color="#dc2626" onClick={() => setDeleteConfirm(b)}>Smazat</SmallBtn>
                  </div>
                </TD>
              </TRow>
            ))}
            {filtered.length === 0 && <TRow><TD>Žádné pobočky</TD></TRow>}
          </tbody>
        </Table>
      )}

      {showModal && (
        <BranchModal
          existing={editing}
          onClose={() => { setShowModal(false); setEditing(null) }}
          onSaved={() => { setShowModal(false); setEditing(null); load() }}
        />
      )}

      {deleteConfirm && (
        <ConfirmDialog
          open title="Smazat pobočku?"
          message={`Opravdu chcete smazat pobočku "${deleteConfirm.name}"? Motorky přiřazené k této pobočce ztratí přiřazení.`}
          danger onConfirm={() => handleDelete(deleteConfirm)}
          onCancel={() => setDeleteConfirm(null)}
        />
      )}
    </div>
  )
}

function BranchModal({ existing, onClose, onSaved }) {
  const isEdit = !!existing
  const [form, setForm] = useState({
    name: existing?.name || '',
    city: existing?.city || '',
    address: existing?.address || '',
    phone: existing?.phone || '',
    email: existing?.email || '',
    opening_hours: existing?.opening_hours || '',
    gps_lat: existing?.gps_lat || '',
    gps_lng: existing?.gps_lng || '',
    notes: existing?.notes || '',
  })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      const payload = {
        name: form.name, city: form.city || null, address: form.address || null,
        phone: form.phone || null, email: form.email || null,
        opening_hours: form.opening_hours || null, notes: form.notes || null,
        gps_lat: form.gps_lat ? Number(form.gps_lat) : null,
        gps_lng: form.gps_lng ? Number(form.gps_lng) : null,
      }
      const result = await debugAction(isEdit ? 'branches.update' : 'branches.create', 'BranchModal', () =>
        isEdit ? supabase.from('branches').update(payload).eq('id', existing.id) : supabase.from('branches').insert(payload)
      , payload)
      if (result?.error) throw result.error
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id,
        action: isEdit ? 'branch_updated' : 'branch_created',
        details: { name: form.name },
      })
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title={isEdit ? `Upravit: ${existing.name}` : 'Nová pobočka'} onClose={onClose} wide>
      <div className="grid grid-cols-2 gap-3">
        <FormField label="Název pobočky" value={form.name} onChange={v => set('name', v)} />
        <FormField label="Město" value={form.city} onChange={v => set('city', v)} />
        <div className="col-span-2">
          <FormField label="Adresa" value={form.address} onChange={v => set('address', v)} />
        </div>
        <FormField label="Telefon" value={form.phone} onChange={v => set('phone', v)} />
        <FormField label="Email" value={form.email} onChange={v => set('email', v)} type="email" />
        <div className="col-span-2">
          <FormField label="Otevírací doba" value={form.opening_hours} onChange={v => set('opening_hours', v)} />
        </div>
        <FormField label="GPS šířka" value={form.gps_lat} onChange={v => set('gps_lat', v)} type="number" />
        <FormField label="GPS délka" value={form.gps_lng} onChange={v => set('gps_lng', v)} type="number" />
        <div className="col-span-2">
          <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Poznámky</label>
          <textarea value={form.notes} onChange={e => set('notes', e.target.value)}
            className="w-full rounded-btn text-sm outline-none"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', minHeight: 60, resize: 'vertical' }} />
        </div>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.name}>
          {saving ? 'Ukládám...' : isEdit ? 'Uložit změny' : 'Vytvořit'}
        </Button>
      </div>
    </Modal>
  )
}

function FormField({ label, value, onChange, type = 'text' }) {
  return (
    <div>
      <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>{label}</label>
      <input type={type} value={value} onChange={e => onChange(e.target.value)}
        className="w-full rounded-btn text-sm outline-none"
        style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }} />
    </div>
  )
}

function StatCard({ label, value, color }) {
  return (
    <Card>
      <div className="text-[10px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#8aab99' }}>{label}</div>
      <div className="text-xl font-extrabold" style={{ color }}>{value}</div>
    </Card>
  )
}

function SmallBtn({ children, color, onClick }) {
  return (
    <button onClick={onClick} className="text-[10px] font-bold cursor-pointer"
      style={{ color, background: 'none', border: 'none', padding: '4px 6px' }}>
      {children}
    </button>
  )
}
