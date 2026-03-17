import { useState, useEffect, Component } from 'react'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import { Table, TRow, TH, TD } from '../components/ui/Table'
import Button from '../components/ui/Button'
import Card from '../components/ui/Card'
import Modal from '../components/ui/Modal'
import ConfirmDialog from '../components/ui/ConfirmDialog'
import SearchInput from '../components/ui/SearchInput'

// ─── Constants ────────────────────────────────────────────────────
const ACCESSORY_TYPES = [
  { key: 'boots', label: 'Boty', sizes: ['36','37','38','39','40','41','42','43','44','45','46'] },
  { key: 'helmet', label: 'Helmy', sizes: ['XS','S','M','L','XL','XXL'] },
  { key: 'balaclava', label: 'Kukly', sizes: ['UNI'] },
  { key: 'gloves', label: 'Rukavice', sizes: ['XS','S','M','L','XL','XXL'] },
  { key: 'pants', label: 'Kalhoty', sizes: ['XS','S','M','L','XL','XXL'] },
]

const MAX_MOTOS = 24
const DETAIL_TABS = ['Info', 'Motorky & Koje', 'Příslušenství', 'Přístupové kódy']

// ─── Helpers ──────────────────────────────────────────────────────
function generateDoorCode() {
  return String(Math.floor(100000 + Math.random() * 900000))
}

function generateBranchCode() {
  return String(Math.floor(100000 + Math.random() * 900000)).padStart(6, '0')
}

// ─── Error Boundary ───────────────────────────────────────────────
class BranchesErrorBoundary extends Component {
  constructor(props) { super(props); this.state = { hasError: false, error: null } }
  static getDerivedStateFromError(error) { return { hasError: true, error } }
  render() {
    if (this.state.hasError) {
      return (
        <div style={{ padding: 24 }}>
          <div className="p-4 rounded-card" style={{ background: '#fee2e2', color: '#dc2626' }}>
            <p className="font-bold mb-2">Chyba při zobrazení poboček</p>
            <p className="text-sm mb-3">{this.state.error?.message || 'Neznámá chyba'}</p>
            <button onClick={() => { this.setState({ hasError: false, error: null }) }}
              className="rounded-btn text-sm font-bold cursor-pointer"
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

// ─── Main List ────────────────────────────────────────────────────
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
        if (motoErr) console.warn('[Branches] motorcycles query failed:', motoErr.message)
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

  async function toggleOpen(branch) {
    const newOpen = !branch.is_open
    try {
      const { error: err } = await supabase
        .from('branches')
        .update({ is_open: newOpen, updated_at: new Date().toISOString() })
        .eq('id', branch.id)
      if (err) throw err
      await logAudit(newOpen ? 'branch_opened' : 'branch_closed', { name: branch.name })
      load()
    } catch (e) {
      setError(`Změna stavu selhala: ${e.message}`)
    }
  }

  async function toggleActive(branch) {
    const newActive = branch.active === false ? true : false
    try {
      const { error: err } = await supabase
        .from('branches')
        .update({ active: newActive, updated_at: new Date().toISOString() })
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
    if (statusFilter === 'open' && !b.is_open) return false
    if (statusFilter === 'closed' && b.is_open) return false
    if (!search) return true
    const s = search.toLowerCase()
    return (b.name || '').toLowerCase().includes(s) ||
      (b.city || '').toLowerCase().includes(s) ||
      (b.address || '').toLowerCase().includes(s) ||
      (b.branch_code || '').toLowerCase().includes(s) ||
      (b.phone || '').toLowerCase().includes(s)
  })

  const totalMotos = Object.values(stats).reduce((s, v) => s + v.total, 0)
  const activeMotos = Object.values(stats).reduce((s, v) => s + v.active, 0)
  const totalBookings = Object.values(bookingStats).reduce((s, v) => s + v, 0)
  const openCount = branches.filter(b => b.is_open).length

  return (
    <div>
      {/* Summary cards */}
      <div className="grid grid-cols-2 md:grid-cols-5 gap-3 mb-5">
        <StatCard label="Celkem poboček" value={branches.length} color="#0f1a14" />
        <StatCard label="Otevřené" value={openCount} color="#1a8a18" />
        <StatCard label="Motorek celkem" value={totalMotos} color="#2563eb" />
        <StatCard label="Aktivních motorek" value={activeMotos} color="#b45309" />
        <StatCard label="Aktivní rezervace" value={totalBookings} color="#8b5cf6" />
      </div>

      <div className="flex items-center gap-3 mb-5 flex-wrap">
        <SearchInput value={search} onChange={setSearch} placeholder="Hledat pobočku, kód, město..." />
        <div className="flex gap-1">
          {[
            { key: 'all', label: 'Vše' },
            { key: 'open', label: 'Otevřené' },
            { key: 'closed', label: 'Zavřené' },
            { key: 'active', label: 'Aktivní' },
            { key: 'inactive', label: 'Neaktivní' },
          ].map(f => (
            <button key={f.key} onClick={() => setStatusFilter(f.key)}
              className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer border-none"
              style={{
                padding: '6px 12px',
                background: statusFilter === f.key ? '#1a2e22' : '#f1faf7',
                color: statusFilter === f.key ? '#74FB71' : '#1a2e22',
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
            <div className="text-sm font-bold mb-1" style={{ color: '#1a2e22' }}>Žádné pobočky</div>
            <div className="text-sm mb-4" style={{ color: '#1a2e22' }}>
              Zatím nemáte vytvořené žádné pobočky. Vytvořte první pobočku kliknutím na tlačítko výše.
            </div>
            <Button green onClick={() => { setEditing(null); setShowModal(true) }}>+ Vytvořit pobočku</Button>
          </div>
        </Card>
      ) : (
        <Table>
          <thead>
            <TRow header>
              <TH>Provoz</TH><TH>Kód</TH><TH>Název</TH><TH>Město</TH><TH>Adresa</TH><TH>Telefon</TH>
              <TH>Motorky</TH><TH>Rezervace</TH><TH>Akce</TH>
            </TRow>
          </thead>
          <tbody>
            {filtered.map(b => (
              <tr key={b.id}
                className="cursor-pointer hover:bg-[#f1faf7] transition-colors"
                style={{ borderBottom: '1px solid #d4e8e0', opacity: b.active === false ? 0.5 : 1 }}
                onClick={() => setDetail(b)}>
                <TD>
                  <button
                    onClick={e => { e.stopPropagation(); toggleOpen(b) }}
                    className="inline-block rounded-btn text-[9px] font-extrabold tracking-wide uppercase cursor-pointer border-none"
                    style={{
                      padding: '3px 8px',
                      background: b.is_open ? '#dcfce7' : '#fee2e2',
                      color: b.is_open ? '#1a8a18' : '#dc2626',
                    }}>
                    {b.is_open ? 'Otevřená' : 'Zavřená'}
                  </button>
                </TD>
                <TD mono bold>{b.branch_code || '—'}</TD>
                <TD bold>{b.name}</TD>
                <TD>{b.city || '—'}</TD>
                <TD>{b.address || '—'}</TD>
                <TD mono>{b.phone || '—'}</TD>
                <TD>
                  <span className="font-bold" style={{ color: '#1a8a18' }}>
                    {stats[b.id]?.active || 0}
                  </span>
                  <span style={{ color: '#1a2e22' }}> / {stats[b.id]?.total || 0}</span>
                  {stats[b.id]?.maintenance > 0 && (
                    <span className="text-[9px] ml-1" style={{ color: '#b45309' }}>({stats[b.id].maintenance} servis)</span>
                  )}
                </TD>
                <TD>
                  <span className="font-bold" style={{ color: bookingStats[b.id] > 0 ? '#8b5cf6' : '#1a2e22' }}>
                    {bookingStats[b.id] || 0}
                  </span>
                </TD>
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
          onRefresh={load}
        />
      )}
    </div>
  )
}

// ─── Branch Detail Modal (Tabbed) ─────────────────────────────────
function BranchDetailModal({ branch, stats: branchStats, bookings, onClose, onEdit, onRefresh }) {
  const [tab, setTab] = useState(0)
  const [motos, setMotos] = useState([])
  const [loadingMotos, setLoadingMotos] = useState(true)
  const [accessories, setAccessories] = useState([])
  const [loadingAccessories, setLoadingAccessories] = useState(true)
  const [doorCodes, setDoorCodes] = useState([])
  const [loadingCodes, setLoadingCodes] = useState(true)
  const [activeBookings, setActiveBookings] = useState([])

  useEffect(() => {
    loadMotos()
    loadAccessories()
    loadDoorCodes()
    loadActiveBookings()
  }, [branch.id])

  async function loadMotos() {
    setLoadingMotos(true)
    try {
      const { data } = await supabase
        .from('motorcycles')
        .select('id, model, spz, status, mileage, image_url, box_number')
        .eq('branch_id', branch.id)
        .order('box_number', { ascending: true, nullsFirst: false })
      setMotos(data || [])
    } catch {}
    setLoadingMotos(false)
  }

  async function loadAccessories() {
    setLoadingAccessories(true)
    try {
      const { data, error } = await supabase
        .from('branch_accessories')
        .select('*')
        .eq('branch_id', branch.id)
        .order('type')
      if (error) {
        console.warn('[Branches] branch_accessories query failed:', error.message)
        setAccessories([])
      } else {
        setAccessories(data || [])
      }
    } catch (e) {
      console.warn('[Branches] accessories load failed:', e.message)
      setAccessories([])
    }
    setLoadingAccessories(false)
  }

  async function loadDoorCodes() {
    setLoadingCodes(true)
    try {
      const { data, error } = await supabase
        .from('branch_door_codes')
        .select('*, bookings(id, status, start_date, end_date, user_id, profiles:user_id(full_name, email)), motorcycles:moto_id(model, spz)')
        .eq('branch_id', branch.id)
        .order('created_at', { ascending: false })
      if (error) {
        console.warn('[Branches] branch_door_codes query failed:', error.message)
        setDoorCodes([])
      } else {
        setDoorCodes(data || [])
      }
    } catch (e) {
      console.warn('[Branches] door codes load failed:', e.message)
      setDoorCodes([])
    }
    setLoadingCodes(false)
  }

  async function loadActiveBookings() {
    try {
      const { data: branchMotos } = await supabase
        .from('motorcycles')
        .select('id')
        .eq('branch_id', branch.id)
      if (!branchMotos || branchMotos.length === 0) { setActiveBookings([]); return }
      const motoIds = branchMotos.map(m => m.id)
      const { data } = await supabase
        .from('bookings')
        .select('id, moto_id, status, start_date, end_date, user_id, profiles:user_id(full_name)')
        .in('moto_id', motoIds)
        .in('status', ['active', 'reserved'])
        .order('start_date')
      setActiveBookings(data || [])
    } catch {
      setActiveBookings([])
    }
  }

  const MOTO_STATUS = {
    active: { label: 'Dostupná', bg: '#dcfce7', color: '#1a8a18' },
    rented: { label: 'Pronajatá', bg: '#dbeafe', color: '#2563eb' },
    maintenance: { label: 'V servisu', bg: '#fef3c7', color: '#b45309' },
    unavailable: { label: 'Nedostupná', bg: '#fee2e2', color: '#dc2626' },
    retired: { label: 'Vyřazena', bg: '#f3f4f6', color: '#1a2e22' },
  }

  return (
    <Modal open title={`Pobočka: ${branch.name}`} onClose={onClose} wide>
      {/* Status bar */}
      <div className="flex items-center gap-3 mb-4">
        <span className="inline-block rounded-btn text-[10px] font-extrabold tracking-wide uppercase"
          style={{
            padding: '3px 10px',
            background: branch.is_open ? '#dcfce7' : '#fee2e2',
            color: branch.is_open ? '#1a8a18' : '#dc2626',
          }}>
          {branch.is_open ? 'Otevřená — Nonstop' : 'Zavřená'}
        </span>
        {branch.branch_code && (
          <span className="font-mono text-sm font-bold" style={{ color: '#1a2e22' }}>
            Kód: {branch.branch_code}
          </span>
        )}
        <span className="inline-block rounded-btn text-[10px] font-extrabold tracking-wide uppercase"
          style={{
            padding: '3px 10px',
            background: branch.active === false ? '#fee2e2' : '#f1faf7',
            color: branch.active === false ? '#dc2626' : '#1a2e22',
          }}>
          {branch.active === false ? 'Neaktivní' : 'Aktivní'}
        </span>
      </div>

      {/* Tabs */}
      <div className="flex gap-1 mb-4 border-b" style={{ borderColor: '#d4e8e0' }}>
        {DETAIL_TABS.map((t, i) => (
          <button key={t} onClick={() => setTab(i)}
            className="text-sm font-extrabold uppercase tracking-wide cursor-pointer border-none"
            style={{
              padding: '8px 16px',
              background: tab === i ? '#1a2e22' : 'transparent',
              color: tab === i ? '#74FB71' : '#1a2e22',
              borderRadius: '8px 8px 0 0',
            }}>
            {t}
          </button>
        ))}
      </div>

      {/* Tab content */}
      {tab === 0 && (
        <TabInfo branch={branch} branchStats={branchStats} bookings={bookings} />
      )}
      {tab === 1 && (
        <TabMotorcycles motos={motos} loading={loadingMotos} statusLabels={MOTO_STATUS} branchId={branch.id} onRefresh={loadMotos} />
      )}
      {tab === 2 && (
        <TabAccessories accessories={accessories} loading={loadingAccessories} branchId={branch.id} onRefresh={loadAccessories} />
      )}
      {tab === 3 && (
        <TabDoorCodes
          doorCodes={doorCodes}
          loading={loadingCodes}
          branchId={branch.id}
          motos={motos}
          activeBookings={activeBookings}
          onRefresh={() => { loadDoorCodes(); loadActiveBookings() }}
        />
      )}

      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onEdit}>Upravit</Button>
        <Button onClick={onClose}>Zavřít</Button>
      </div>
    </Modal>
  )
}

// ─── Tab: Info ────────────────────────────────────────────────────
function TabInfo({ branch, branchStats, bookings }) {
  return (
    <>
      <div className="grid grid-cols-2 gap-4 mb-4">
        <DRow label="Kód pobočky" value={branch.branch_code} mono />
        <DRow label="Provoz" value={branch.is_open ? 'Otevřená — Nonstop' : 'Zavřená'} />
        <DRow label="Město" value={branch.city} />
        <DRow label="Adresa" value={branch.address} />
        <DRow label="Telefon" value={branch.phone} mono />
        <DRow label="Stav" value={branch.active === false ? 'Neaktivní' : 'Aktivní'} />
        {branch.gps_lat && branch.gps_lng && (
          <div className="col-span-2">
            <DRow label="GPS" value={`${branch.gps_lat}, ${branch.gps_lng}`} mono />
            <a href={`https://www.google.com/maps?q=${branch.gps_lat},${branch.gps_lng}`}
              target="_blank" rel="noopener noreferrer"
              className="inline-flex items-center gap-1 text-sm font-bold px-2 py-0.5 rounded-btn mt-1"
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
          <div className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Motorky</div>
          <div className="text-lg font-extrabold" style={{ color: '#2563eb' }}>
            {branchStats?.active || 0} / {branchStats?.total || 0}
          </div>
        </div>
        <div className="rounded-lg text-center" style={{ padding: '10px', background: '#f1faf7' }}>
          <div className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Rezervace</div>
          <div className="text-lg font-extrabold" style={{ color: '#8b5cf6' }}>{bookings}</div>
        </div>
        <div className="rounded-lg text-center" style={{ padding: '10px', background: '#f1faf7' }}>
          <div className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>V servisu</div>
          <div className="text-lg font-extrabold" style={{ color: '#b45309' }}>{branchStats?.maintenance || 0}</div>
        </div>
      </div>
    </>
  )
}

// ─── Tab: Motorcycles & Koje ──────────────────────────────────────
function TabMotorcycles({ motos, loading, statusLabels, branchId, onRefresh }) {
  const [saving, setSaving] = useState(false)

  if (loading) return <Spinner />
  if (motos.length === 0) return <EmptyState text="Žádné motorky na této pobočce" />

  // Sort by box_number (nulls last)
  const sorted = [...motos].sort((a, b) => {
    if (a.box_number == null && b.box_number == null) return 0
    if (a.box_number == null) return 1
    if (b.box_number == null) return -1
    return a.box_number - b.box_number
  })

  async function setBoxNumber(motoId, num) {
    setSaving(true)
    try {
      const { error } = await supabase.from('motorcycles').update({ box_number: num }).eq('id', motoId)
      if (error) throw error
      onRefresh()
    } catch (e) {
      alert('Chyba: ' + e.message)
    } finally {
      setSaving(false)
    }
  }

  async function swapBoxNumbers(indexA, indexB) {
    if (indexA < 0 || indexB < 0 || indexA >= sorted.length || indexB >= sorted.length) return
    setSaving(true)
    try {
      const mA = sorted[indexA]
      const mB = sorted[indexB]
      const numA = mA.box_number
      const numB = mB.box_number
      // Swap: set A to temp -1, set B to A's number, set A to B's number
      await supabase.from('motorcycles').update({ box_number: -1 }).eq('id', mA.id)
      await supabase.from('motorcycles').update({ box_number: numA }).eq('id', mB.id)
      await supabase.from('motorcycles').update({ box_number: numB }).eq('id', mA.id)
      onRefresh()
    } catch (e) {
      alert('Chyba: ' + e.message)
    } finally {
      setSaving(false)
    }
  }

  async function autoAssignBoxNumbers() {
    if (!window.confirm(`Automaticky přiřadit čísla kojí 1–${motos.length} všem motorkám na pobočce?`)) return
    setSaving(true)
    try {
      for (let i = 0; i < sorted.length; i++) {
        const { error } = await supabase.from('motorcycles').update({ box_number: i + 1 }).eq('id', sorted[i].id)
        if (error) throw error
      }
      onRefresh()
    } catch (e) {
      alert('Chyba: ' + e.message)
    } finally {
      setSaving(false)
    }
  }

  const hasUnassigned = sorted.some(m => m.box_number == null)

  return (
    <div>
      <div className="flex items-center justify-between mb-2">
        <div className="text-sm" style={{ color: '#1a2e22' }}>
          <strong>{motos.length}</strong> motorek na pobočce (max {MAX_MOTOS})
        </div>
        <div className="flex gap-2">
          {hasUnassigned && (
            <button onClick={autoAssignBoxNumbers} disabled={saving}
              className="rounded-btn text-sm font-bold cursor-pointer border-none"
              style={{ padding: '4px 10px', background: '#dbeafe', color: '#2563eb', opacity: saving ? 0.5 : 1 }}>
              Auto-přiřadit čísla kojí
            </button>
          )}
        </div>
      </div>

      <div className="space-y-1 max-h-96 overflow-y-auto">
        {sorted.map((m, i) => {
          const st = statusLabels[m.status] || statusLabels.active
          return (
            <div key={m.id} className="flex items-center text-sm gap-1" style={{ padding: '6px 8px', background: i % 2 === 0 ? '#f8fcfa' : '#fff', borderRadius: 8 }}>
              {/* Box number */}
              <div className="flex items-center gap-0.5 mr-1" style={{ minWidth: 70 }}>
                <span className="font-mono font-extrabold text-sm" style={{
                  color: m.box_number != null ? '#1a2e22' : '#dc2626',
                  background: m.box_number != null ? '#dcfce7' : '#fee2e2',
                  padding: '2px 6px',
                  borderRadius: 6,
                  minWidth: 32,
                  textAlign: 'center',
                  display: 'inline-block',
                }}>
                  {m.box_number != null ? `#${m.box_number}` : '—'}
                </span>
                {/* Move arrows */}
                <div className="flex flex-col" style={{ lineHeight: 0 }}>
                  <button onClick={() => swapBoxNumbers(i, i - 1)} disabled={i === 0 || saving}
                    className="cursor-pointer border-none bg-transparent"
                    style={{ padding: 0, fontSize: 10, color: i === 0 ? '#ccc' : '#1a2e22', lineHeight: '12px' }}
                    title="Posunout nahoru">
                    ▲
                  </button>
                  <button onClick={() => swapBoxNumbers(i, i + 1)} disabled={i === sorted.length - 1 || saving}
                    className="cursor-pointer border-none bg-transparent"
                    style={{ padding: 0, fontSize: 10, color: i === sorted.length - 1 ? '#ccc' : '#1a2e22', lineHeight: '12px' }}
                    title="Posunout dolů">
                    ▼
                  </button>
                </div>
              </div>
              {/* Moto info */}
              <span className="font-bold" style={{ color: '#0f1a14' }}>{m.model}</span>
              <span className="ml-1 font-mono text-sm" style={{ color: '#1a2e22' }}>{m.spz || '—'}</span>
              <span className="ml-auto mr-2 text-sm" style={{ color: '#1a2e22' }}>
                {m.mileage ? `${m.mileage.toLocaleString('cs-CZ')} km` : ''}
              </span>
              <span className="inline-block rounded-btn text-[9px] font-extrabold tracking-wide uppercase"
                style={{ padding: '2px 6px', background: st.bg, color: st.color }}>
                {st.label}
              </span>
              {/* Manual box number edit */}
              {m.box_number == null && (
                <input type="number" min="1" max={MAX_MOTOS} placeholder="Koje"
                  className="rounded-btn text-sm outline-none font-mono ml-1"
                  style={{ width: 50, padding: '2px 4px', background: '#fffbeb', border: '1px solid #fbbf24', textAlign: 'center' }}
                  onKeyDown={e => {
                    if (e.key === 'Enter') {
                      const val = parseInt(e.target.value)
                      if (val >= 1 && val <= MAX_MOTOS) setBoxNumber(m.id, val)
                    }
                  }}
                  onBlur={e => {
                    const val = parseInt(e.target.value)
                    if (val >= 1 && val <= MAX_MOTOS) setBoxNumber(m.id, val)
                  }}
                />
              )}
            </div>
          )
        })}
      </div>
    </div>
  )
}

// ─── Tab: Accessories ─────────────────────────────────────────────
function TabAccessories({ accessories, loading, branchId, onRefresh }) {
  const [showAdd, setShowAdd] = useState(false)
  const [editItem, setEditItem] = useState(null)
  const [saving, setSaving] = useState(false)

  if (loading) return <Spinner />

  // Group by type
  const grouped = {}
  ACCESSORY_TYPES.forEach(at => { grouped[at.key] = [] })
  accessories.forEach(a => {
    if (grouped[a.type]) grouped[a.type].push(a)
  })

  async function handleSaveAccessory(item) {
    setSaving(true)
    try {
      if (item.id) {
        const { error } = await supabase
          .from('branch_accessories')
          .update({ quantity: item.quantity })
          .eq('id', item.id)
        if (error) throw error
      } else {
        const { error } = await supabase
          .from('branch_accessories')
          .upsert({
            branch_id: branchId,
            type: item.type,
            size: item.size,
            quantity: item.quantity,
          }, { onConflict: 'branch_id,type,size' })
        if (error) throw error
      }
      setEditItem(null)
      setShowAdd(false)
      onRefresh()
    } catch (e) {
      alert('Chyba: ' + e.message)
    } finally {
      setSaving(false)
    }
  }

  async function handleDeleteAccessory(id) {
    if (!window.confirm('Smazat tuto položku příslušenství?')) return
    try {
      await supabase.from('branch_accessories').delete().eq('id', id)
      onRefresh()
    } catch (e) {
      alert('Chyba: ' + e.message)
    }
  }

  async function seedAllAccessories() {
    if (!window.confirm('Naplnit sklad všemi typy příslušenství (s nulovým počtem)?')) return
    setSaving(true)
    try {
      const rows = []
      ACCESSORY_TYPES.forEach(at => {
        at.sizes.forEach(size => {
          rows.push({ branch_id: branchId, type: at.key, size, quantity: 0 })
        })
      })
      const { error } = await supabase
        .from('branch_accessories')
        .upsert(rows, { onConflict: 'branch_id,type,size' })
      if (error) throw error
      onRefresh()
    } catch (e) {
      alert('Chyba: ' + e.message)
    } finally {
      setSaving(false)
    }
  }

  const totalItems = accessories.reduce((s, a) => s + (a.quantity || 0), 0)

  return (
    <div>
      <div className="flex items-center justify-between mb-3">
        <div className="text-sm" style={{ color: '#1a2e22' }}>
          <strong>{accessories.length}</strong> typů, <strong>{totalItems}</strong> kusů celkem
        </div>
        <div className="flex gap-2">
          {accessories.length === 0 && (
            <button onClick={seedAllAccessories} disabled={saving}
              className="rounded-btn text-sm font-bold cursor-pointer border-none"
              style={{ padding: '5px 12px', background: '#dbeafe', color: '#2563eb' }}>
              Naplnit vše
            </button>
          )}
          <button onClick={() => setShowAdd(true)}
            className="rounded-btn text-sm font-bold cursor-pointer border-none"
            style={{ padding: '5px 12px', background: '#1a2e22', color: '#74FB71' }}>
            + Přidat
          </button>
        </div>
      </div>

      {ACCESSORY_TYPES.map(at => {
        const items = grouped[at.key] || []
        if (items.length === 0 && accessories.length > 0) return null
        return (
          <div key={at.key} className="mb-3">
            <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>
              {at.label}
            </div>
            {items.length === 0 ? (
              <div className="text-sm py-1" style={{ color: '#1a2e22', opacity: 0.5 }}>Žádné položky</div>
            ) : (
              <div className="flex flex-wrap gap-2">
                {items.sort((a, b) => a.size.localeCompare(b.size, 'cs', { numeric: true })).map(item => (
                  <div key={item.id}
                    className="flex items-center gap-2 rounded-lg cursor-pointer"
                    style={{ padding: '4px 10px', background: item.quantity > 0 ? '#f1faf7' : '#fff5f5', border: '1px solid #d4e8e0' }}
                    onClick={() => setEditItem(item)}>
                    <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>{item.size}</span>
                    <span className="text-sm font-extrabold" style={{ color: item.quantity > 0 ? '#1a8a18' : '#dc2626' }}>
                      {item.quantity} ks
                    </span>
                  </div>
                ))}
              </div>
            )}
          </div>
        )
      })}

      {(showAdd || editItem) && (
        <AccessoryEditModal
          existing={editItem}
          branchId={branchId}
          onSave={handleSaveAccessory}
          onDelete={editItem?.id ? () => handleDeleteAccessory(editItem.id) : null}
          onClose={() => { setShowAdd(false); setEditItem(null) }}
          saving={saving}
        />
      )}
    </div>
  )
}

function AccessoryEditModal({ existing, branchId, onSave, onDelete, onClose, saving }) {
  const [form, setForm] = useState({
    type: existing?.type || 'boots',
    size: existing?.size || '',
    quantity: existing?.quantity ?? 0,
  })

  const typeConfig = ACCESSORY_TYPES.find(t => t.key === form.type)

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center" style={{ background: 'rgba(0,0,0,0.3)' }}>
      <div className="rounded-card" style={{ background: '#fff', padding: 24, minWidth: 320, maxWidth: 400 }}>
        <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>
          {existing ? 'Upravit příslušenství' : 'Přidat příslušenství'}
        </h3>
        <div className="space-y-3">
          <div>
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Typ</label>
            <select value={form.type} onChange={e => setForm(f => ({ ...f, type: e.target.value, size: '' }))}
              disabled={!!existing}
              className="w-full rounded-btn text-sm outline-none"
              style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }}>
              {ACCESSORY_TYPES.map(t => (
                <option key={t.key} value={t.key}>{t.label}</option>
              ))}
            </select>
          </div>
          <div>
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Velikost</label>
            <select value={form.size} onChange={e => setForm(f => ({ ...f, size: e.target.value }))}
              disabled={!!existing}
              className="w-full rounded-btn text-sm outline-none"
              style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }}>
              <option value="">Vyberte...</option>
              {(typeConfig?.sizes || []).map(s => (
                <option key={s} value={s}>{s}</option>
              ))}
            </select>
          </div>
          <div>
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Počet kusů</label>
            <input type="number" min="0" value={form.quantity}
              onChange={e => setForm(f => ({ ...f, quantity: Math.max(0, parseInt(e.target.value) || 0) }))}
              className="w-full rounded-btn text-sm outline-none"
              style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }} />
          </div>
        </div>
        <div className="flex justify-between mt-4">
          <div>
            {onDelete && (
              <button onClick={() => { onDelete(); onClose() }}
                className="rounded-btn text-sm font-bold cursor-pointer border-none"
                style={{ padding: '6px 14px', background: '#fee2e2', color: '#dc2626' }}>
                Smazat
              </button>
            )}
          </div>
          <div className="flex gap-2">
            <button onClick={onClose}
              className="rounded-btn text-sm font-bold cursor-pointer border-none"
              style={{ padding: '6px 14px', background: '#f1faf7', color: '#1a2e22' }}>
              Zrušit
            </button>
            <button
              onClick={() => onSave({ id: existing?.id, type: form.type, size: form.size, quantity: form.quantity })}
              disabled={saving || !form.size}
              className="rounded-btn text-sm font-bold cursor-pointer border-none"
              style={{ padding: '6px 14px', background: '#1a2e22', color: '#74FB71', opacity: saving || !form.size ? 0.5 : 1 }}>
              {saving ? 'Ukládám...' : 'Uložit'}
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}

// ─── Tab: Door Codes ──────────────────────────────────────────────
// Kódy se generují AUTOMATICKY v DB triggerem při změně bookingu na active.
// Velín jen zobrazuje stav a umožňuje nouzový zásah admina.
function TabDoorCodes({ doorCodes, loading, branchId, motos, activeBookings, onRefresh }) {
  const [generating, setGenerating] = useState(false)
  const [error, setError] = useState(null)

  if (loading) return <Spinner />

  const activeCodes = doorCodes.filter(c => c.is_active)
  const inactiveCodes = doorCodes.filter(c => !c.is_active).slice(0, 20)

  // Nouzové manuální generování — pouze při výpadku DB triggeru
  async function emergencyGenerateCodes(booking) {
    setGenerating(true)
    setError(null)
    try {
      const { data: docs } = await supabase
        .from('documents')
        .select('id, type')
        .eq('user_id', booking.user_id)
        .in('type', ['contract', 'protocol'])
      const { data: profile } = await supabase
        .from('profiles')
        .select('license_number')
        .eq('id', booking.user_id)
        .maybeSingle()

      const hasDocuments = (docs && docs.length > 0) || profile?.license_number
      const withheldReason = hasDocuments ? null : 'Chybí doklady (OP/pas/ŘP)'

      const codes = [
        {
          branch_id: branchId,
          booking_id: booking.id,
          moto_id: booking.moto_id,
          code_type: 'motorcycle',
          door_code: generateDoorCode(),
          is_active: booking.status === 'active',
          valid_from: booking.start_date,
          valid_until: booking.end_date,
          sent_to_customer: hasDocuments && booking.status === 'active',
          sent_at: hasDocuments && booking.status === 'active' ? new Date().toISOString() : null,
          withheld_reason: withheldReason,
        },
        {
          branch_id: branchId,
          booking_id: booking.id,
          moto_id: booking.moto_id,
          code_type: 'accessories',
          door_code: generateDoorCode(),
          is_active: booking.status === 'active',
          valid_from: booking.start_date,
          valid_until: booking.end_date,
          sent_to_customer: hasDocuments && booking.status === 'active',
          sent_at: hasDocuments && booking.status === 'active' ? new Date().toISOString() : null,
          withheld_reason: withheldReason,
        },
      ]

      const { error: insertErr } = await supabase.from('branch_door_codes').insert(codes)
      if (insertErr) throw insertErr

      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id,
        action: 'door_codes_emergency_generated',
        details: { booking_id: booking.id, branch_id: branchId, withheld: !hasDocuments },
      })

      onRefresh()
    } catch (e) {
      setError(e.message)
    } finally {
      setGenerating(false)
    }
  }

  async function deactivateCode(codeId) {
    try {
      await supabase.from('branch_door_codes').update({ is_active: false }).eq('id', codeId)
      onRefresh()
    } catch (e) {
      setError(e.message)
    }
  }

  async function activateCode(codeId) {
    try {
      await supabase.from('branch_door_codes').update({ is_active: true }).eq('id', codeId)
      onRefresh()
    } catch (e) {
      setError(e.message)
    }
  }

  async function resendCode(code) {
    try {
      await supabase.from('branch_door_codes').update({
        sent_to_customer: true,
        sent_at: new Date().toISOString(),
        withheld_reason: null,
      }).eq('id', code.id)

      if (code.bookings?.user_id) {
        await supabase.from('admin_messages').insert({
          user_id: code.bookings.user_id,
          title: 'Přístupový kód k pobočce',
          content: `Váš kód k ${code.code_type === 'motorcycle' ? 'motorce' : 'příslušenství'}: ${code.door_code}`,
          type: 'info',
        }).catch(() => {})
      }

      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id,
        action: 'door_code_resent',
        details: { code_id: code.id, booking_id: code.booking_id },
      })

      onRefresh()
    } catch (e) {
      setError(e.message)
    }
  }

  // Rezervace bez kódů = trigger nestihl / selhal
  const bookingsWithCodes = new Set(doorCodes.map(c => c.booking_id))
  const bookingsWithoutCodes = activeBookings.filter(b => !bookingsWithCodes.has(b.id))

  return (
    <div>
      {/* Info banner */}
      <div className="mb-3 p-2 rounded-card text-sm" style={{ background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
        Kódy se generují <strong>automaticky při změně rezervace na aktivní</strong> (DB trigger).
        Nouzové ruční generování pouze při výpadku triggeru.
      </div>

      {error && (
        <div className="mb-3 p-2 rounded-card text-sm" style={{ background: '#fee2e2', color: '#dc2626' }}>{error}</div>
      )}

      {/* Bookings without codes — trigger failure fallback */}
      {bookingsWithoutCodes.length > 0 && (
        <div className="mb-4">
          <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#dc2626' }}>
            Výpadek triggeru — rezervace bez kódů ({bookingsWithoutCodes.length})
          </div>
          <div className="space-y-1">
            {bookingsWithoutCodes.map(b => (
              <div key={b.id} className="flex items-center gap-2 rounded-lg" style={{ padding: '6px 10px', background: '#fee2e2', border: '1px solid #fca5a5' }}>
                <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>
                  {b.profiles?.full_name || 'Neznámý'}
                </span>
                <span className="text-sm" style={{ color: '#1a2e22' }}>
                  {new Date(b.start_date).toLocaleDateString('cs-CZ')} — {new Date(b.end_date).toLocaleDateString('cs-CZ')}
                </span>
                <span className="inline-block rounded-btn text-[9px] font-extrabold tracking-wide uppercase"
                  style={{ padding: '2px 6px', background: b.status === 'active' ? '#dcfce7' : '#dbeafe', color: b.status === 'active' ? '#1a8a18' : '#2563eb' }}>
                  {b.status === 'active' ? 'Aktivní' : 'Nadcházející'}
                </span>
                <button onClick={() => emergencyGenerateCodes(b)} disabled={generating}
                  className="ml-auto rounded-btn text-sm font-bold cursor-pointer border-none"
                  style={{ padding: '4px 10px', background: '#dc2626', color: '#fff', opacity: generating ? 0.5 : 1 }}>
                  {generating ? 'Generuji...' : 'Nouzově generovat'}
                </button>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Active codes */}
      <div className="mb-4">
        <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a8a18' }}>
          Aktivní kódy ({activeCodes.length})
        </div>
        {activeCodes.length === 0 ? (
          <EmptyState text="Žádné aktivní kódy — kódy se vytvoří automaticky při aktivaci rezervace" />
        ) : (
          <div className="space-y-1 max-h-60 overflow-y-auto">
            {activeCodes.map(c => (
              <DoorCodeRow key={c.id} code={c} onDeactivate={deactivateCode} onResend={resendCode} />
            ))}
          </div>
        )}
      </div>

      {/* Inactive (history) */}
      {inactiveCodes.length > 0 && (
        <div>
          <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>
            Historie kódů (posledních {inactiveCodes.length})
          </div>
          <div className="space-y-1 max-h-40 overflow-y-auto">
            {inactiveCodes.map(c => (
              <DoorCodeRow key={c.id} code={c} onActivate={activateCode} inactive />
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

function DoorCodeRow({ code, onDeactivate, onActivate, onResend, inactive }) {
  const isMotorcycle = code.code_type === 'motorcycle'
  const booking = code.bookings
  const moto = code.motorcycles

  return (
    <div className="flex items-center gap-2 text-sm rounded-lg"
      style={{
        padding: '6px 10px',
        background: inactive ? '#f3f4f6' : (isMotorcycle ? '#f1faf7' : '#eff6ff'),
        border: `1px solid ${inactive ? '#e5e7eb' : (isMotorcycle ? '#d4e8e0' : '#bfdbfe')}`,
        opacity: inactive ? 0.6 : 1,
      }}>
      <span className="inline-block rounded-btn text-[8px] font-extrabold tracking-wide uppercase"
        style={{
          padding: '2px 6px',
          background: isMotorcycle ? '#dcfce7' : '#dbeafe',
          color: isMotorcycle ? '#1a8a18' : '#2563eb',
          minWidth: 60,
          textAlign: 'center',
        }}>
        {isMotorcycle ? 'Motorka' : 'Přísluš.'}
      </span>
      <span className="font-mono font-extrabold text-base tracking-widest" style={{ color: '#0f1a14', letterSpacing: 3 }}>
        {code.door_code}
      </span>
      <span className="text-sm" style={{ color: '#1a2e22' }}>
        {moto ? `${moto.model} (${moto.spz || '?'})` : ''}
      </span>
      <span className="text-sm" style={{ color: '#1a2e22' }}>
        {booking?.profiles?.full_name || ''}
      </span>
      {code.withheld_reason && (
        <span className="inline-block rounded-btn text-[8px] font-bold"
          style={{ padding: '2px 6px', background: '#fef3c7', color: '#b45309' }}>
          Zadržen: {code.withheld_reason}
        </span>
      )}
      {!code.sent_to_customer && !inactive && (
        <span className="inline-block rounded-btn text-[8px] font-bold"
          style={{ padding: '2px 6px', background: '#fee2e2', color: '#dc2626' }}>
          Neodesláno
        </span>
      )}
      {code.sent_to_customer && (
        <span className="inline-block rounded-btn text-[8px] font-bold"
          style={{ padding: '2px 6px', background: '#dcfce7', color: '#1a8a18' }}>
          Odesláno
        </span>
      )}
      <div className="ml-auto flex gap-1">
        {!inactive && onResend && !code.sent_to_customer && (
          <button onClick={() => onResend(code)}
            className="rounded-btn text-[10px] font-bold cursor-pointer border-none"
            style={{ padding: '2px 8px', background: '#dbeafe', color: '#2563eb' }}>
            Odeslat
          </button>
        )}
        {!inactive && onDeactivate && (
          <button onClick={() => onDeactivate(code.id)}
            className="rounded-btn text-[10px] font-bold cursor-pointer border-none"
            style={{ padding: '2px 8px', background: '#fee2e2', color: '#dc2626' }}>
            Deaktivovat
          </button>
        )}
        {inactive && onActivate && (
          <button onClick={() => onActivate(code.id)}
            className="rounded-btn text-[10px] font-bold cursor-pointer border-none"
            style={{ padding: '2px 8px', background: '#dcfce7', color: '#1a8a18' }}>
            Aktivovat
          </button>
        )}
      </div>
    </div>
  )
}

// ─── Branch Create/Edit Modal ─────────────────────────────────────
function BranchModal({ existing, onClose, onSaved }) {
  const isEdit = !!existing
  const [form, setForm] = useState({
    name: existing?.name || '',
    branch_code: existing?.branch_code || '',
    city: existing?.city || '',
    address: existing?.address || '',
    phone: existing?.phone || '',
    type: existing?.type || '',
    is_open: existing?.is_open ?? false,
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
        branch_code: form.branch_code?.trim() || generateBranchCode(),
        city: form.city?.trim() || null,
        address: form.address?.trim() || null,
        phone: form.phone?.trim() || null,
        type: form.type?.trim() || null,
        is_open: form.is_open,
        notes: form.notes?.trim() || null,
        gps_lat: form.gps_lat ? Number(form.gps_lat) : null,
        gps_lng: form.gps_lng ? Number(form.gps_lng) : null,
        active: form.active,
        updated_at: new Date().toISOString(),
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
        <FormField label="Kód pobočky" value={form.branch_code} onChange={v => set('branch_code', v)}
          placeholder="Automaticky generován pokud prázdný" />
        <FormField label="Město" value={form.city} onChange={v => set('city', v)} />
        <FormField label="Telefon" value={form.phone} onChange={v => set('phone', v)} />
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Typ pobočky</label>
          <select value={form.type} onChange={e => set('type', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }}>
            <option value="">—</option>
            <option value="centrum">Centrum</option>
            <option value="předměstí">Předměstí</option>
            <option value="letiště">Letiště</option>
            <option value="turistická">Turistická</option>
          </select>
        </div>
        <div className="col-span-2">
          <FormField label="Adresa" value={form.address} onChange={v => set('address', v)} />
        </div>
        <FormField label="GPS šířka" value={form.gps_lat} onChange={v => set('gps_lat', v)} type="number"
          placeholder="např. 49.7437" />
        <FormField label="GPS délka" value={form.gps_lng} onChange={v => set('gps_lng', v)} type="number"
          placeholder="např. 15.3386" />
        <div className="col-span-2">
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Poznámky</label>
          <textarea value={form.notes} onChange={e => set('notes', e.target.value)}
            className="w-full rounded-btn text-sm outline-none"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', minHeight: 60, resize: 'vertical' }} />
        </div>
        <div className="col-span-2 flex items-center gap-4">
          <label className="flex items-center gap-2 cursor-pointer">
            <div onClick={() => set('is_open', !form.is_open)}
              className="rounded-btn font-extrabold text-sm cursor-pointer border-none"
              style={{
                padding: '6px 16px',
                background: form.is_open ? '#1a8a18' : '#dc2626',
                color: '#fff',
                userSelect: 'none',
              }}>
              {form.is_open ? 'OTEVŘENÁ — Nonstop' : 'ZAVŘENÁ'}
            </div>
          </label>
          <label className="flex items-center gap-2">
            <input type="checkbox" checked={form.active} onChange={e => set('active', e.target.checked)} />
            <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Pobočka je aktivní</span>
          </label>
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

// ─── Shared Components ────────────────────────────────────────────
function DRow({ label, value, mono }) {
  return (
    <div>
      <div className="text-sm font-extrabold uppercase tracking-wide mb-0.5" style={{ color: '#1a2e22' }}>{label}</div>
      <div className={`text-sm font-semibold ${mono ? 'font-mono' : ''}`} style={{ color: '#0f1a14' }}>{value || '—'}</div>
    </div>
  )
}

function FormField({ label, value, onChange, type = 'text', placeholder }) {
  return (
    <div>
      <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{label}</label>
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
      <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>{label}</div>
      <div className="text-xl font-extrabold" style={{ color }}>{value}</div>
    </Card>
  )
}

function SmallBtn({ children, color, onClick }) {
  return (
    <button onClick={onClick} className="text-sm font-bold cursor-pointer"
      style={{ color, background: 'none', border: 'none', padding: '4px 6px' }}>
      {children}
    </button>
  )
}

function Spinner() {
  return (
    <div className="flex justify-center py-8">
      <div className="animate-spin rounded-full h-6 w-6 border-t-2 border-brand-gd" />
    </div>
  )
}

function EmptyState({ text }) {
  return (
    <div className="text-sm py-3 text-center" style={{ color: '#1a2e22', opacity: 0.5 }}>{text}</div>
  )
}
