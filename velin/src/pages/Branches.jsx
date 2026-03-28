import { useState, useEffect, Component } from 'react'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import { Table, TRow, TH, TD } from '../components/ui/Table'
import Button from '../components/ui/Button'
import Card from '../components/ui/Card'
import ConfirmDialog from '../components/ui/ConfirmDialog'
import SearchInput from '../components/ui/SearchInput'
import { StatCard, SmallBtn } from './BranchHelpers'
import BranchModal from './BranchModal'
import BranchDetailModal from './BranchDetailModal'

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
          if (!s[m.branch_id]) s[m.branch_id] = { total: 0, active: 0, maintenance: 0, unavailable: 0 }
          s[m.branch_id].total++
          if (m.status === 'active') s[m.branch_id].active++
          if (m.status === 'maintenance') s[m.branch_id].maintenance++
          if (m.status === 'unavailable' || m.status === 'retired') s[m.branch_id].unavailable++
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
