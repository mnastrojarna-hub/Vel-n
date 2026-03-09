import { useState, useEffect, Component } from 'react'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import { Table, TRow, TH, TD } from '../components/ui/Table'
import Button from '../components/ui/Button'
import Card from '../components/ui/Card'
import Modal from '../components/ui/Modal'
import ConfirmDialog from '../components/ui/ConfirmDialog'
import SearchInput from '../components/ui/SearchInput'

const DAY_NAMES = { mo: 'Po', tu: 'Út', we: 'St', th: 'Čt', fr: 'Pá', sa: 'So', su: 'Ne' }

function formatOpeningHours(oh) {
  if (!oh) return '—'
  if (typeof oh === 'string') return oh
  if (typeof oh !== 'object') return String(oh)
  try {
    return ['mo','tu','we','th','fr','sa','su']
      .filter(d => oh[d])
      .map(d => `${DAY_NAMES[d]}: ${oh[d]}`)
      .join(', ') || '—'
  } catch { return '—' }
}

class BranchesErrorBoundary extends Component {
  constructor(props) { super(props); this.state = { hasError: false, error: null } }
  static getDerivedStateFromError(error) { return { hasError: true, error } }
  render() {
    if (this.state.hasError) {
      return (
        <div style={{ padding: 24 }}>
          <div className="p-4 rounded-card" style={{ background: '#fee2e2', color: '#dc2626' }}>
            <p className="font-bold mb-2">Chyba při zobrazení poboček</p>
            <p className="text-xs mb-3">{this.state.error?.message || 'Neznámá chyba'}</p>
            <button onClick={() => { this.setState({ hasError: false, error: null }) }}
              className="rounded-btn text-xs font-bold cursor-pointer"
              style={{ padding: '6px 14px', background: '#dc2626', color: '#fff', border: 'none' }}>
              Zkusit znovu
            </button>
          </div>
        </div>
      )
    }
    return this.props.children
  }
}

export default function BranchesPage() {
  return (
    <BranchesErrorBoundary>
      <Branches />
    </BranchesErrorBoundary>
  )
}

function Branches() {
  const [branches, setBranches] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [search, setSearch] = useState('')
  const [showModal, setShowModal] = useState(false)
  const [editing, setEditing] = useState(null)
  const [deleteConfirm, setDeleteConfirm] = useState(null)
  const [stats, setStats] = useState({})
  const [detail, setDetail] = useState(null)
  const [statusFilter, setStatusFilter] = useState('all')
  const [bookingStats, setBookingStats] = useState({})

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      // Load branches
      const { data, error: branchErr } = await supabase
        .from('branches')
        .select('*')
        .order('name')
      if (branchErr) {
        const msg = branchErr.message || 'Neznámá chyba'
        const hint = branchErr.hint || ''
        const code = branchErr.code || ''
        throw new Error(
          `Načtení poboček selhalo: ${msg}` +
          (code ? ` (kód: ${code})` : '') +
          (hint ? ` — ${hint}` : '') +
          (code === '42501' || msg.includes('permission') || msg.includes('RLS')
            ? '\n\nPravděpodobně chybí RLS politika pro tabulku "branches". Zkontrolujte nastavení v Supabase.'
            : '')
        )
      }
      setBranches(data || [])

      // Load moto counts per branch
      try {
        const { data: motos, error: motoErr } = await supabase
          .from('motorcycles')
          .select('branch_id, status')
        if (motoErr) {
          console.warn('[Branches] motorcycles query failed:', motoErr.message)
        }
        const s = {}
        ;(motos || []).forEach(m => {
          if (!m.branch_id) return
          if (!s[m.branch_id]) s[m.branch_id] = { total: 0, active: 0, maintenance: 0, out_of_service: 0 }
          s[m.branch_id].total++
          if (m.status === 'active' || m.status === 'rented') s[m.branch_id].active++
          if (m.status === 'maintenance') s[m.branch_id].maintenance++
          if (m.status === 'unavailable' || m.status === 'retired') s[m.branch_id].out_of_service++
        })
        setStats(s)
      } catch (e) {
        console.warn('[Branches] motorcycles stats failed:', e.message)
      }

      // Load active bookings per branch
      try {
        const { data: bookings } = await supabase
          .from('bookings')
          .select('id, moto_id')
          .in('status', ['active', 'reserved', 'pending'])
        if (bookings && bookings.length > 0) {
          const motoIds = [...new Set(bookings.map(b => b.moto_id).filter(Boolean))]
          if (motoIds.length > 0) {
            const { data: motosForBookings } = await supabase
              .from('motorcycles')
              .select('id, branch_id')
              .in('id', motoIds)
            const motoToBranch = {}
            ;(motosForBookings || []).forEach(m => { motoToBranch[m.id] = m.branch_id })
            const bs = {}
            bookings.forEach(b => {
              const bid = motoToBranch[b.moto_id]
              if (!bid) return
              bs[bid] = (bs[bid] || 0) + 1
            })
            setBookingStats(bs)
          }
        }
      } catch (e) {
        console.warn('[Branches] booking stats failed:', e.message)
      }
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function handleDelete(branch) {
    try {
      // Check for assigned motorcycles
      const { count } = await supabase
        .from('motorcycles')
        .select('id', { count: 'exact', head: true })
        .eq('branch_id', branch.id)
      if (count && count > 0) {
        if (!window.confirm(`Pobočka "${branch.name}" má ${count} přiřazených motorek.\n\nPokračováním jim bude odebráno přiřazení. Pokračovat?`)) {
          setDeleteConfirm(null)
          return
        }
        await supabase.from('motorcycles').update({ branch_id: null }).eq('branch_id', branch.id)
      }

      const result = await debugAction('branches.delete', 'Branches', () =>
        supabase.from('branches').delete().eq('id', branch.id)
      , { branch_id: branch.id, name: branch.name })
      if (result?.error) {
        setError(`Smazání selhalo: ${result.error.message}`)
        setDeleteConfirm(null)
        return
      }
      await logAudit('branch_deleted', { name: branch.name })
      setDeleteConfirm(null)
      load()
    } catch (e) {
      setError(`Smazání selhalo: ${e.message}`)
      setDeleteConfirm(null)
    }
  }

  async function toggleActive(branch) {
    const newActive = branch.active === false ? true : false
    try {
      const { error: err } = await supabase
        .from('branches')
        .update({ active: newActive })
        .eq('id', branch.id)
      if (err) throw err
      await logAudit(newActive ? 'branch_activated' : 'branch_deactivated', { name: branch.name })
      load()
    } catch (e) {
      setError(`Změna stavu selhala: ${e.message}`)
    }
  }

  async function logAudit(action, details) {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, details })
    } catch {}
  }

  const filtered = branches.filter(b => {
    if (statusFilter === 'active' && b.active === false) return false
    if (statusFilter === 'inactive' && b.active !== false) return false
    if (!search) return true
    const s = search.toLowerCase()
    return (b.name || '').toLowerCase().includes(s) ||
      (b.city || '').toLowerCase().includes(s) ||
      (b.address || '').toLowerCase().includes(s) ||
      (b.email || '').toLowerCase().includes(s) ||
      (b.phone || '').toLowerCase().includes(s)
  })

  const totalMotos = Object.values(stats).reduce((s, v) => s + v.total, 0)
  const activeMotos = Object.values(stats).reduce((s, v) => s + v.active, 0)
  const totalBookings = Object.values(bookingStats).reduce((s, v) => s + v, 0)

  return (
    <div>
      {/* Summary cards */}
      <div className="grid grid-cols-2 md:grid-cols-5 gap-3 mb-5">
        <StatCard label="Celkem poboček" value={branches.length} color="#0f1a14" />
        <StatCard label="Aktivní" value={branches.filter(b => b.active !== false).length} color="#1a8a18" />
        <StatCard label="Motorek celkem" value={totalMotos} color="#2563eb" />
        <StatCard label="Aktivních motorek" value={activeMotos} color="#b45309" />
        <StatCard label="Aktivní rezervace" value={totalBookings} color="#8b5cf6" />
      </div>

      {/* DIAGNOSTIKA */}
      <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 11, fontFamily: 'monospace', color: '#78350f' }}>
        <strong>DIAGNOSTIKA Branches</strong><br/>
        <div>branches: {branches.length} (zobrazeno: {filtered.length}), statusFilter: {statusFilter}</div>
        <div>totalMotos: {totalMotos} (active: {activeMotos}), totalBookings: {totalBookings}</div>
        <div>search: "{search}"</div>
        {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
      </div>

      <div className="flex items-center gap-3 mb-5 flex-wrap">
        <SearchInput value={search} onChange={setSearch} placeholder="Hledat pobočku, město, adresu..." />
        <div className="flex gap-1">
          {[
            { key: 'all', label: 'Vše' },
            { key: 'active', label: 'Aktivní' },
            { key: 'inactive', label: 'Neaktivní' },
          ].map(f => (
            <button key={f.key} onClick={() => setStatusFilter(f.key)}
              className="rounded-btn text-[10px] font-extrabold uppercase tracking-wide cursor-pointer border-none"
              style={{
                padding: '6px 12px',
                background: statusFilter === f.key ? '#1a2e22' : '#f1faf7',
                color: statusFilter === f.key ? '#74FB71' : '#4a6357',
              }}>
              {f.label}
            </button>
          ))}
        </div>
        <div className="ml-auto">
          <Button green onClick={() => { setEditing(null); setShowModal(true) }}>+ Nová pobočka</Button>
        </div>
      </div>

      {error && (
        <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13, whiteSpace: 'pre-wrap' }}>
          {error}
          <button onClick={() => { setError(null); load() }} className="ml-3 underline cursor-pointer font-bold"
            style={{ background: 'none', border: 'none', color: '#dc2626' }}>
            Zkusit znovu
          </button>
        </div>
      )}

      {loading ? (
        <div className="flex justify-center py-16">
          <div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" />
        </div>
      ) : branches.length === 0 && !error ? (
        <Card>
          <div className="text-center py-12">
            <div className="text-4xl mb-3">🏢</div>
            <div className="text-sm font-bold mb-1" style={{ color: '#4a6357' }}>Žádné pobočky</div>
            <div className="text-xs mb-4" style={{ color: '#8aab99' }}>
              Zatím nemáte vytvořené žádné pobočky. Vytvořte první pobočku kliknutím na tlačítko výše.
            </div>
            <Button green onClick={() => { setEditing(null); setShowModal(true) }}>+ Vytvořit pobočku</Button>
          </div>
        </Card>
      ) : (
        <Table>
          <thead>
            <TRow header>
              <TH>Stav</TH><TH>Název</TH><TH>Město</TH><TH>Adresa</TH><TH>Telefon</TH>
              <TH>Email</TH><TH>Motorky</TH><TH>Rezervace</TH><TH>Otevírací doba</TH><TH>Akce</TH>
            </TRow>
          </thead>
          <tbody>
            {filtered.map(b => (
              <tr key={b.id}
                className="cursor-pointer hover:bg-[#f1faf7] transition-colors"
                style={{ borderBottom: '1px solid #d4e8e0', opacity: b.active === false ? 0.5 : 1 }}
                onClick={() => setDetail(b)}>
                <TD>
                  <span className="inline-block rounded-btn text-[9px] font-extrabold tracking-wide uppercase"
                    style={{
                      padding: '3px 8px',
                      background: b.active === false ? '#fee2e2' : '#dcfce7',
                      color: b.active === false ? '#dc2626' : '#1a8a18',
                    }}>
                    {b.active === false ? 'Neaktivní' : 'Aktivní'}
                  </span>
                </TD>
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
                  {stats[b.id]?.maintenance > 0 && (
                    <span className="text-[9px] ml-1" style={{ color: '#b45309' }}>({stats[b.id].maintenance} servis)</span>
                  )}
                </TD>
                <TD>
                  <span className="font-bold" style={{ color: bookingStats[b.id] > 0 ? '#8b5cf6' : '#8aab99' }}>
                    {bookingStats[b.id] || 0}
                  </span>
                </TD>
                <TD>{formatOpeningHours(b.opening_hours)}</TD>
                <TD>
                  <div className="flex gap-1" onClick={e => e.stopPropagation()}>
                    <SmallBtn color="#2563eb" onClick={() => { setEditing(b); setShowModal(true) }}>Upravit</SmallBtn>
                    <SmallBtn color={b.active === false ? '#1a8a18' : '#b45309'}
                      onClick={() => toggleActive(b)}>
                      {b.active === false ? 'Aktivovat' : 'Deaktivovat'}
                    </SmallBtn>
                    <SmallBtn color="#dc2626" onClick={() => setDeleteConfirm(b)}>Smazat</SmallBtn>
                  </div>
                </TD>
              </tr>
            ))}
            {filtered.length === 0 && branches.length > 0 && (
              <TRow><TD>Žádné pobočky neodpovídají filtru</TD></TRow>
            )}
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
          message={`Opravdu chcete smazat pobočku "${deleteConfirm.name}"?${
            stats[deleteConfirm.id]?.total > 0
              ? `\n\n⚠️ Tato pobočka má ${stats[deleteConfirm.id].total} přiřazených motorek, které ztratí přiřazení.`
              : ''
          }`}
          danger onConfirm={() => handleDelete(deleteConfirm)}
          onCancel={() => setDeleteConfirm(null)}
        />
      )}

      {detail && (
        <BranchDetailModal
          branch={detail}
          stats={stats[detail.id]}
          bookings={bookingStats[detail.id] || 0}
          onClose={() => setDetail(null)}
          onEdit={() => { setDetail(null); setEditing(detail); setShowModal(true) }}
        />
      )}
    </div>
  )
}

function BranchDetailModal({ branch, stats: branchStats, bookings, onClose, onEdit }) {
  const [motos, setMotos] = useState([])
  const [loadingMotos, setLoadingMotos] = useState(true)

  useEffect(() => {
    loadMotos()
  }, [branch.id])

  async function loadMotos() {
    setLoadingMotos(true)
    try {
      const { data } = await supabase
        .from('motorcycles')
        .select('id, model, spz, status, mileage')
        .eq('branch_id', branch.id)
        .order('model')
      setMotos(data || [])
    } catch {}
    setLoadingMotos(false)
  }

  const STATUS_LABELS = {
    active: { label: 'Dostupná', bg: '#dcfce7', color: '#1a8a18' },
    rented: { label: 'Pronajatá', bg: '#dbeafe', color: '#2563eb' },
    maintenance: { label: 'V servisu', bg: '#fef3c7', color: '#b45309' },
    unavailable: { label: 'Nedostupná', bg: '#fee2e2', color: '#dc2626' },
    retired: { label: 'Vyřazena', bg: '#f3f4f6', color: '#6b7280' },
  }

  return (
    <Modal open title={`Pobočka: ${branch.name}`} onClose={onClose} wide>
      <div className="grid grid-cols-2 gap-4 mb-4">
        <DRow label="Město" value={branch.city} />
        <DRow label="Adresa" value={branch.address} />
        <DRow label="Telefon" value={branch.phone} mono />
        <DRow label="Email" value={branch.email} />
        <DRow label="Otevírací doba" value={formatOpeningHours(branch.opening_hours)} />
        <DRow label="Stav" value={branch.active === false ? 'Neaktivní' : 'Aktivní'} />
        {branch.gps_lat && branch.gps_lng && (
          <div className="col-span-2">
            <DRow label="GPS" value={`${branch.gps_lat}, ${branch.gps_lng}`} mono />
            <a href={`https://www.google.com/maps?q=${branch.gps_lat},${branch.gps_lng}`}
              target="_blank" rel="noopener noreferrer"
              className="inline-flex items-center gap-1 text-[10px] font-bold px-2 py-0.5 rounded-btn mt-1"
              style={{ background: '#dbeafe', color: '#2563eb', textDecoration: 'none' }}>
              Otevřít v mapách
            </a>
          </div>
        )}
        {branch.notes && (
          <div className="col-span-2">
            <DRow label="Poznámky" value={branch.notes} />
          </div>
        )}
      </div>

      <div className="grid grid-cols-3 gap-3 mb-4">
        <div className="rounded-lg text-center" style={{ padding: '10px', background: '#f1faf7' }}>
          <div className="text-[10px] font-extrabold uppercase tracking-wide" style={{ color: '#8aab99' }}>Motorky</div>
          <div className="text-lg font-extrabold" style={{ color: '#2563eb' }}>
            {branchStats?.active || 0} / {branchStats?.total || 0}
          </div>
        </div>
        <div className="rounded-lg text-center" style={{ padding: '10px', background: '#f1faf7' }}>
          <div className="text-[10px] font-extrabold uppercase tracking-wide" style={{ color: '#8aab99' }}>Rezervace</div>
          <div className="text-lg font-extrabold" style={{ color: '#8b5cf6' }}>{bookings}</div>
        </div>
        <div className="rounded-lg text-center" style={{ padding: '10px', background: '#f1faf7' }}>
          <div className="text-[10px] font-extrabold uppercase tracking-wide" style={{ color: '#8aab99' }}>V servisu</div>
          <div className="text-lg font-extrabold" style={{ color: '#b45309' }}>{branchStats?.maintenance || 0}</div>
        </div>
      </div>

      <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#8aab99' }}>Motorky na pobočce</h4>
      {loadingMotos ? (
        <div className="flex justify-center py-4"><div className="animate-spin rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>
      ) : motos.length === 0 ? (
        <div className="text-xs py-3 text-center" style={{ color: '#8aab99' }}>Žádné motorky na této pobočce</div>
      ) : (
        <div className="space-y-1 max-h-48 overflow-y-auto">
          {motos.map(m => {
            const st = STATUS_LABELS[m.status] || STATUS_LABELS.active
            return (
              <div key={m.id} className="flex items-center text-xs" style={{ padding: '6px 10px', background: '#f8fcfa', borderRadius: 8 }}>
                <span className="font-bold" style={{ color: '#0f1a14' }}>{m.model}</span>
                <span className="ml-2 font-mono text-[10px]" style={{ color: '#8aab99' }}>{m.spz || '—'}</span>
                <span className="ml-auto mr-2 text-[10px]" style={{ color: '#8aab99' }}>
                  {m.mileage ? `${m.mileage.toLocaleString('cs-CZ')} km` : ''}
                </span>
                <span className="inline-block rounded-btn text-[9px] font-extrabold tracking-wide uppercase"
                  style={{ padding: '2px 6px', background: st.bg, color: st.color }}>
                  {st.label}
                </span>
              </div>
            )
          })}
        </div>
      )}

      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onEdit}>Upravit</Button>
        <Button onClick={onClose}>Zavřít</Button>
      </div>
    </Modal>
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
    opening_hours: typeof existing?.opening_hours === 'object' ? formatOpeningHours(existing.opening_hours) : (existing?.opening_hours || ''),
    gps_lat: existing?.gps_lat || '',
    gps_lng: existing?.gps_lng || '',
    notes: existing?.notes || '',
    active: existing?.active !== false,
  })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    if (!form.name?.trim()) {
      setErr('Název pobočky je povinný.')
      return
    }
    setSaving(true); setErr(null)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      const payload = {
        name: form.name.trim(),
        city: form.city?.trim() || null,
        address: form.address?.trim() || null,
        phone: form.phone?.trim() || null,
        email: form.email?.trim() || null,
        opening_hours: form.opening_hours?.trim() || null,
        notes: form.notes?.trim() || null,
        gps_lat: form.gps_lat ? Number(form.gps_lat) : null,
        gps_lng: form.gps_lng ? Number(form.gps_lng) : null,
        active: form.active,
      }
      const result = await debugAction(isEdit ? 'branches.update' : 'branches.create', 'BranchModal', () =>
        isEdit ? supabase.from('branches').update(payload).eq('id', existing.id) : supabase.from('branches').insert(payload)
      , payload)
      if (result?.error) {
        const msg = result.error.message || 'Neznámá chyba'
        throw new Error(msg + (result.error.code === '42501' ? ' — Zkontrolujte RLS politiky v Supabase.' : ''))
      }
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
        <FormField label="Název pobočky *" value={form.name} onChange={v => set('name', v)} />
        <FormField label="Město" value={form.city} onChange={v => set('city', v)} />
        <div className="col-span-2">
          <FormField label="Adresa" value={form.address} onChange={v => set('address', v)} />
        </div>
        <FormField label="Telefon" value={form.phone} onChange={v => set('phone', v)} />
        <FormField label="Email" value={form.email} onChange={v => set('email', v)} type="email" />
        <div className="col-span-2">
          <FormField label="Otevírací doba" value={form.opening_hours} onChange={v => set('opening_hours', v)}
            placeholder="např. Po-Pá 8:00-17:00, So 9:00-12:00" />
        </div>
        <FormField label="GPS šířka" value={form.gps_lat} onChange={v => set('gps_lat', v)} type="number"
          placeholder="např. 49.7437" />
        <FormField label="GPS délka" value={form.gps_lng} onChange={v => set('gps_lng', v)} type="number"
          placeholder="např. 15.3386" />
        <div className="col-span-2">
          <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Poznámky</label>
          <textarea value={form.notes} onChange={e => set('notes', e.target.value)}
            className="w-full rounded-btn text-sm outline-none"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', minHeight: 60, resize: 'vertical' }} />
        </div>
        <div className="col-span-2 flex items-center gap-2">
          <input type="checkbox" checked={form.active} onChange={e => set('active', e.target.checked)} id="branch-active" />
          <label htmlFor="branch-active" className="text-xs font-bold" style={{ color: '#4a6357' }}>Pobočka je aktivní</label>
        </div>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626', whiteSpace: 'pre-wrap' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.name?.trim()}>
          {saving ? 'Ukládám...' : isEdit ? 'Uložit změny' : 'Vytvořit'}
        </Button>
      </div>
    </Modal>
  )
}

function DRow({ label, value, mono }) {
  return (
    <div>
      <div className="text-[10px] font-extrabold uppercase tracking-wide mb-0.5" style={{ color: '#8aab99' }}>{label}</div>
      <div className={`text-sm font-semibold ${mono ? 'font-mono' : ''}`} style={{ color: '#0f1a14' }}>{value || '—'}</div>
    </div>
  )
}

function FormField({ label, value, onChange, type = 'text', placeholder }) {
  return (
    <div>
      <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>{label}</label>
      <input type={type} value={value} onChange={e => onChange(e.target.value)}
        placeholder={placeholder}
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
