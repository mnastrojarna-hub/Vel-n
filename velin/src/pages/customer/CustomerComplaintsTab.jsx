import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import Card from '../../components/ui/Card'
import Badge from '../../components/ui/Badge'
import SearchInput from '../../components/ui/SearchInput'

const STATUS_MAP = {
  open: { label: 'Otevřená', color: '#b45309', bg: '#fef3c7' },
  in_progress: { label: 'Řeší se', color: '#2563eb', bg: '#dbeafe' },
  resolved: { label: 'Vyřešená', color: '#1a8a18', bg: '#dcfce7' },
  rejected: { label: 'Zamítnuta', color: '#dc2626', bg: '#fee2e2' },
}

const FILTER_OPTIONS = [
  { value: 'all', label: 'Vše' },
  { value: 'open', label: 'Otevřené' },
  { value: 'in_progress', label: 'Řeší se' },
  { value: 'resolved', label: 'Vyřešené' },
  { value: 'rejected', label: 'Zamítnuté' },
]

export default function CustomerComplaintsTab({ userId }) {
  const navigate = useNavigate()
  const [complaints, setComplaints] = useState([])
  const [loading, setLoading] = useState(true)
  const [expanded, setExpanded] = useState(null)
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('all')
  const [sortOrder, setSortOrder] = useState('date_desc')

  useEffect(() => { load() }, [userId])

  async function load() {
    setLoading(true)
    try {
      const { data, error } = await supabase
        .from('booking_complaints')
        .select('*')
        .eq('customer_id', userId)
        .order('created_at', { ascending: false })
      if (error) throw error

      const items = data || []

      // Load related bookings + motorcycles separately
      const bookingIds = [...new Set(items.map(c => c.booking_id).filter(Boolean))]
      let bookingMap = {}
      if (bookingIds.length > 0) {
        const { data: bookings } = await supabase
          .from('bookings')
          .select('id, start_date, end_date, status, total_price, motorcycles(id, model, spz)')
          .in('id', bookingIds)
        if (bookings) bookingMap = Object.fromEntries(bookings.map(b => [b.id, b]))
      }

      // Load resolver names
      const resolverIds = [...new Set(items.map(c => c.resolved_by).filter(Boolean))]
      let resolverMap = {}
      if (resolverIds.length > 0) {
        const { data: resolvers } = await supabase
          .from('profiles')
          .select('id, full_name')
          .in('id', resolverIds)
        if (resolvers) resolverMap = Object.fromEntries(resolvers.map(r => [r.id, r.full_name]))
      }

      items.forEach(c => {
        c._booking = bookingMap[c.booking_id] || null
        c._resolverName = resolverMap[c.resolved_by] || null
      })

      setComplaints(items)
    } catch {
      setComplaints([])
    }
    setLoading(false)
  }

  function getFiltered() {
    let items = [...complaints]
    if (statusFilter !== 'all') items = items.filter(c => c.status === statusFilter)
    if (search) {
      const s = search.toLowerCase()
      items = items.filter(c =>
        (c.subject || '').toLowerCase().includes(s) ||
        (c.description || '').toLowerCase().includes(s) ||
        (c._booking?.motorcycles?.model || '').toLowerCase().includes(s) ||
        (c._booking?.motorcycles?.spz || '').toLowerCase().includes(s)
      )
    }
    items.sort((a, b) => {
      const da = a.created_at || '', db = b.created_at || ''
      return sortOrder === 'date_asc' ? da.localeCompare(db) : db.localeCompare(da)
    })
    return items
  }

  if (loading) return <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>

  const filtered = getFiltered()
  const openCount = complaints.filter(c => c.status === 'open' || c.status === 'in_progress').length

  return (
    <div className="space-y-4">
      {/* Souhrn */}
      <Card>
        <div className="flex items-center gap-4">
          <div>
            <div className="text-2xl font-extrabold" style={{ color: '#0f1a14' }}>{complaints.length}</div>
            <div className="text-sm" style={{ color: '#1a2e22' }}>celkem reklamaci</div>
          </div>
          {openCount > 0 && (
            <Badge label={`${openCount} otevrenych`} color="#b45309" bg="#fef3c7" />
          )}
          {complaints.length > 0 && openCount === 0 && (
            <Badge label="Vsechny vyreseny" color="#1a8a18" bg="#dcfce7" />
          )}
        </div>
      </Card>

      {/* Filtr */}
      <Card>
        <div className="flex flex-wrap items-center gap-3 mb-1">
          <SearchInput value={search} onChange={v => setSearch(v)} placeholder="Hledat v reklamacich…" />
          <div className="flex gap-1">
            {FILTER_OPTIONS.map(opt => (
              <button key={opt.value} onClick={() => setStatusFilter(opt.value)}
                className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
                style={{ padding: '6px 14px', background: statusFilter === opt.value ? '#74FB71' : '#f1faf7', color: '#1a2e22', border: 'none', boxShadow: statusFilter === opt.value ? '0 4px 16px rgba(116,251,113,.35)' : 'none' }}>
                {opt.label}
              </button>
            ))}
          </div>
          <select value={sortOrder} onChange={e => setSortOrder(e.target.value)}
            className="rounded-btn text-sm font-bold outline-none cursor-pointer"
            style={{ padding: '6px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
            <option value="date_desc">Nejnovejsi</option>
            <option value="date_asc">Nejstarsi</option>
          </select>
          <span className="text-sm" style={{ color: '#1a2e22' }}>
            {filtered.length} {filtered.length === 1 ? 'reklamace' : filtered.length < 5 ? 'reklamace' : 'reklamaci'}
          </span>
        </div>
      </Card>

      {/* Seznam */}
      {filtered.length === 0 ? (
        <Card><p style={{ color: '#1a2e22', fontSize: 13 }}>{search || statusFilter !== 'all' ? 'Zadne reklamace odpovidajici filtru' : 'Zadne reklamace'}</p></Card>
      ) : (
        <div className="space-y-3">
          {filtered.map(c => {
            const st = STATUS_MAP[c.status] || STATUS_MAP.open
            const isExpanded = expanded === c.id
            const booking = c._booking

            return (
              <Card key={c.id}>
                {/* Hlavička */}
                <div className="flex items-center gap-3 cursor-pointer" onClick={() => setExpanded(isExpanded ? null : c.id)}>
                  <span style={{ fontSize: 20 }}>📋</span>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="text-sm font-bold" style={{ color: '#0f1a14' }}>{c.subject || 'Reklamace'}</span>
                      <Badge label={st.label} color={st.color} bg={st.bg} />
                    </div>
                    <div className="flex items-center gap-3 mt-1 text-sm" style={{ color: '#1a2e22' }}>
                      <span>{c.created_at ? new Date(c.created_at).toLocaleString('cs-CZ') : '—'}</span>
                      {booking?.motorcycles && <span>🏍 {booking.motorcycles.model} ({booking.motorcycles.spz})</span>}
                    </div>
                  </div>
                  <span style={{ fontSize: 14, color: '#1a2e22', transition: 'transform .2s', transform: isExpanded ? 'rotate(180deg)' : 'none' }}>▼</span>
                </div>

                {/* Akce — vždy viditelné */}
                {booking && (
                  <div className="flex flex-wrap gap-2 mt-3">
                    <button onClick={() => navigate(`/rezervace/${c.booking_id}`)}
                      className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
                      style={{ padding: '6px 14px', background: '#dbeafe', color: '#2563eb', border: 'none' }}>
                      Detail rezervace
                    </button>
                    {booking.motorcycles?.id && (
                      <button onClick={() => navigate(`/flotila/${booking.motorcycles.id}`)}
                        className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
                        style={{ padding: '6px 14px', background: '#f1faf7', color: '#1a2e22', border: 'none' }}>
                        Detail motorky
                      </button>
                    )}
                  </div>
                )}

                {/* Rozbalitelný detail */}
                {isExpanded && (
                  <div className="mt-4 space-y-4">
                    {/* Popis reklamace */}
                    {c.description && (
                      <div>
                        <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Popis</div>
                        <p className="text-sm p-3 rounded-lg" style={{ background: '#f1faf7', color: '#0f1a14' }}>{c.description}</p>
                      </div>
                    )}

                    {/* Detaily */}
                    <div className="grid grid-cols-2 gap-3">
                      <InfoField label="Status" value={st.label} />
                      <InfoField label="Vytvoreno" value={c.created_at ? new Date(c.created_at).toLocaleString('cs-CZ') : '—'} />
                      {c.resolved_at && <InfoField label="Vyreseno" value={new Date(c.resolved_at).toLocaleString('cs-CZ')} />}
                      {c._resolverName && <InfoField label="Vyresil" value={c._resolverName} />}
                    </div>

                    {/* Info o rezervaci */}
                    {booking && (
                      <div>
                        <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Propojena rezervace</div>
                        <div className="p-3 rounded-lg flex items-center gap-3 cursor-pointer" style={{ background: '#f1faf7' }}
                          onClick={() => navigate(`/rezervace/${c.booking_id}`)}>
                          <span style={{ fontSize: 16 }}>🏍</span>
                          <div className="flex-1">
                            <span className="text-sm font-bold">{booking.motorcycles?.model || '—'}</span>
                            <span className="text-sm ml-2" style={{ color: '#1a2e22' }}>{booking.motorcycles?.spz || ''}</span>
                            <span className="text-sm ml-3" style={{ color: '#1a2e22' }}>{booking.start_date} → {booking.end_date}</span>
                          </div>
                          <span className="text-sm font-bold">{booking.total_price?.toLocaleString('cs-CZ')} Kc</span>
                        </div>
                      </div>
                    )}

                    {/* Řešení */}
                    {c.resolution && (
                      <div>
                        <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Reseni</div>
                        <p className="text-sm p-3 rounded-lg" style={{ background: c.status === 'resolved' ? '#dcfce7' : c.status === 'rejected' ? '#fee2e2' : '#f1faf7', color: '#0f1a14' }}>{c.resolution}</p>
                      </div>
                    )}
                  </div>
                )}
              </Card>
            )
          })}
        </div>
      )}
    </div>
  )
}

function InfoField({ label, value }) {
  return (
    <div className="p-2 rounded-lg" style={{ background: '#f1faf7' }}>
      <div className="text-xs font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>{label}</div>
      <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>{value || '—'}</div>
    </div>
  )
}
