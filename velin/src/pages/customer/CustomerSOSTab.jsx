import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import { TYPE_LABELS, TYPE_ICONS, SEVERITY_MAP, STATUS_COLORS } from '../SOSPanel'
import Card from '../../components/ui/Card'
import Badge from '../../components/ui/Badge'
import SearchInput from '../../components/ui/SearchInput'
import SOSTimeline from '../sos/SOSTimeline'

const STATUS_OPTIONS = [
  { value: 'all', label: 'Vše' },
  { value: 'reported', label: 'Nový' },
  { value: 'acknowledged', label: 'Potvrzeno' },
  { value: 'in_progress', label: 'Řeší se' },
  { value: 'resolved', label: 'Vyřešeno' },
  { value: 'closed', label: 'Uzavřeno' },
]

export default function CustomerSOSTab({ userId }) {
  const navigate = useNavigate()
  const [incidents, setIncidents] = useState([])
  const [loading, setLoading] = useState(true)
  const [expanded, setExpanded] = useState(null)
  const [messages, setMessages] = useState({})

  // Filters
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('all')
  const [sortOrder, setSortOrder] = useState('date_desc')

  useEffect(() => { loadIncidents() }, [userId])

  async function loadIncidents() {
    setLoading(true)
    try {
      // Load with related booking + motorcycle data
      let { data, error } = await supabase
        .from('sos_incidents')
        .select('*, motorcycles(id, model, spz), bookings(id, start_date, end_date, status, ended_by_sos)')
        .eq('user_id', userId)
        .order('created_at', { ascending: false })

      if (error) throw error

      // Fallback: search via bookings if user_id on sos_incidents is null
      if (!data || data.length === 0) {
        const { data: d2 } = await supabase
          .from('sos_incidents')
          .select('*, motorcycles(id, model, spz), bookings!inner(id, user_id, start_date, end_date, status, ended_by_sos)')
          .eq('bookings.user_id', userId)
          .order('created_at', { ascending: false })
        data = d2 || []
      }

      // For incidents with replacement_booking_id, load replacement booking info
      const replIds = data.filter(i => i.replacement_booking_id).map(i => i.replacement_booking_id)
      let replMap = {}
      if (replIds.length > 0) {
        const { data: replBookings } = await supabase
          .from('bookings')
          .select('id, start_date, end_date, status, motorcycles(id, model, spz)')
          .in('id', replIds)
        if (replBookings) replMap = Object.fromEntries(replBookings.map(b => [b.id, b]))
      }

      data.forEach(i => {
        i._replacementBooking = replMap[i.replacement_booking_id] || null
      })

      setIncidents(data)
    } catch {
      setIncidents([])
    }
    setLoading(false)
  }

  async function loadMessages(incidentId) {
    if (messages[incidentId]) return
    try {
      const inc = incidents.find(i => i.id === incidentId)
      if (!inc) return
      // Load admin_messages for the customer related to SOS
      const { data } = await supabase
        .from('admin_messages')
        .select('*')
        .eq('user_id', userId)
        .eq('type', 'sos_response')
        .order('created_at', { ascending: true })
      setMessages(m => ({ ...m, [incidentId]: data || [] }))
    } catch {
      setMessages(m => ({ ...m, [incidentId]: [] }))
    }
  }

  function toggleExpand(id) {
    if (expanded === id) { setExpanded(null); return }
    setExpanded(id)
    loadMessages(id)
  }

  function getFiltered() {
    let items = [...incidents]
    if (statusFilter !== 'all') items = items.filter(i => i.status === statusFilter)
    if (search) {
      const s = search.toLowerCase()
      items = items.filter(i =>
        (TYPE_LABELS[i.type] || i.type || '').toLowerCase().includes(s) ||
        (i.description || '').toLowerCase().includes(s) ||
        (i.title || '').toLowerCase().includes(s) ||
        (i.motorcycles?.model || '').toLowerCase().includes(s) ||
        (i.motorcycles?.spz || '').toLowerCase().includes(s)
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

  return (
    <div className="space-y-4">
      {/* Filtr */}
      <Card>
        <div className="flex flex-wrap items-center gap-3 mb-1">
          <SearchInput value={search} onChange={v => setSearch(v)} placeholder="Hledat v incidentech…" />
          <div className="flex gap-1">
            {STATUS_OPTIONS.map(opt => (
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
            <option value="date_desc">Nejnovější</option>
            <option value="date_asc">Nejstarší</option>
          </select>
          <span className="text-sm" style={{ color: '#1a2e22' }}>
            {filtered.length} {filtered.length === 1 ? 'incident' : filtered.length < 5 ? 'incidenty' : 'incidentů'}
          </span>
        </div>
      </Card>

      {/* Seznam */}
      {filtered.length === 0 ? (
        <Card><p style={{ color: '#1a2e22', fontSize: 13 }}>{search || statusFilter !== 'all' ? 'Žádné incidenty odpovídající filtru' : 'Žádné SOS incidenty'}</p></Card>
      ) : (
        <div className="space-y-3">
          {filtered.map(inc => {
            const sev = SEVERITY_MAP[inc.severity] || SEVERITY_MAP.medium
            const st = STATUS_COLORS[inc.status] || STATUS_COLORS.reported
            const isExpanded = expanded === inc.id
            const typeIcon = TYPE_ICONS[inc.type] || '📞'
            const typeLabel = TYPE_LABELS[inc.type] || inc.type || 'Incident'

            return (
              <Card key={inc.id}>
                {/* Hlavička incidentu */}
                <div className="flex items-center gap-3 cursor-pointer" onClick={() => toggleExpand(inc.id)}>
                  <span style={{ fontSize: 20 }}>{typeIcon}</span>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="text-sm font-bold" style={{ color: '#0f1a14' }}>{inc.title || typeLabel}</span>
                      <Badge label={sev.label} color={sev.color} bg={sev.bg} />
                      <Badge label={st.label} color={st.color} bg={st.bg} />
                    </div>
                    <div className="flex items-center gap-3 mt-1 text-sm" style={{ color: '#1a2e22' }}>
                      <span>{inc.created_at ? new Date(inc.created_at).toLocaleString('cs-CZ') : '—'}</span>
                      {inc.motorcycles && <span>🏍 {inc.motorcycles.model} ({inc.motorcycles.spz})</span>}
                    </div>
                  </div>
                  <span style={{ fontSize: 14, color: '#1a2e22', transition: 'transform .2s', transform: isExpanded ? 'rotate(180deg)' : 'none' }}>▼</span>
                </div>

                {/* Akční tlačítka — vždy viditelná */}
                <div className="flex flex-wrap gap-2 mt-3">
                  <button onClick={() => navigate('/sos', { state: { openIncidentId: inc.id } })}
                    className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
                    style={{ padding: '6px 14px', background: '#fee2e2', color: '#dc2626', border: 'none' }}>
                    Detail v SOS panelu
                  </button>

                  {inc.booking_id && (
                    <button onClick={() => navigate(`/rezervace/${inc.booking_id}`)}
                      className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
                      style={{ padding: '6px 14px', background: '#dbeafe', color: '#2563eb', border: 'none' }}>
                      Původní rezervace
                    </button>
                  )}

                  {inc.replacement_booking_id && (
                    <button onClick={() => navigate(`/rezervace/${inc.replacement_booking_id}`)}
                      className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
                      style={{ padding: '6px 14px', background: '#dcfce7', color: '#1a8a18', border: 'none' }}>
                      Náhradní rezervace
                    </button>
                  )}
                </div>

                {/* Rozbalitelný detail */}
                {isExpanded && (
                  <div className="mt-4 space-y-4">
                    {/* Popis */}
                    {inc.description && (
                      <div>
                        <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Popis</div>
                        <p className="text-sm p-3 rounded-lg" style={{ background: '#f1faf7', color: '#0f1a14' }}>{inc.description}</p>
                      </div>
                    )}

                    {/* Detaily incidentu */}
                    <div className="grid grid-cols-2 gap-3">
                      <InfoField label="Typ" value={typeLabel} />
                      <InfoField label="Závažnost" value={sev.label} />
                      <InfoField label="Status" value={st.label} />
                      <InfoField label="Rozhodnutí zákazníka" value={inc.customer_decision === 'replacement_moto' ? 'Náhradní motorka' : inc.customer_decision === 'end_ride' ? 'Ukončení jízdy' : inc.customer_decision === 'continue' ? 'Pokračuje' : inc.customer_decision || '—'} />
                      <InfoField label="Vina zákazníka" value={inc.is_customer_fault === true ? 'Ano' : inc.is_customer_fault === false ? 'Ne' : '—'} />
                      <InfoField label="Poškození" value={inc.damage_severity ? `${inc.damage_severity}${inc.damage_description ? ' — ' + inc.damage_description : ''}` : '—'} />
                      {inc.address && <InfoField label="Místo" value={inc.address} span2 />}
                      {inc.police_report_number && <InfoField label="Policejní zpráva" value={inc.police_report_number} />}
                      {inc.tow_requested && <InfoField label="Odtah" value="Požadován" />}
                    </div>

                    {/* Vazby na rezervace */}
                    <div>
                      <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Propojené rezervace</div>
                      <div className="space-y-2">
                        {inc.bookings && (
                          <BookingLink
                            label="Původní rezervace"
                            booking={inc.bookings}
                            moto={inc.motorcycles}
                            badge={inc.bookings.ended_by_sos ? { label: 'Ukončena SOS', color: '#dc2626', bg: '#fee2e2' } : null}
                            onClick={() => navigate(`/rezervace/${inc.booking_id}`)}
                          />
                        )}
                        {inc._replacementBooking && (
                          <BookingLink
                            label="Náhradní rezervace"
                            booking={inc._replacementBooking}
                            moto={inc._replacementBooking.motorcycles}
                            badge={{ label: 'Náhradní', color: '#1a8a18', bg: '#dcfce7' }}
                            onClick={() => navigate(`/rezervace/${inc.replacement_booking_id}`)}
                          />
                        )}
                        {!inc.bookings && !inc._replacementBooking && (
                          <p className="text-sm" style={{ color: '#1a2e22' }}>Žádné propojené rezervace</p>
                        )}
                      </div>
                    </div>

                    {/* Fotky */}
                    {inc.photos && inc.photos.length > 0 && (
                      <div>
                        <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Fotky ({inc.photos.length})</div>
                        <div className="flex gap-2 flex-wrap">
                          {inc.photos.map((url, i) => (
                            <a key={i} href={url} target="_blank" rel="noopener noreferrer">
                              <img src={url} alt={`SOS foto ${i + 1}`} className="rounded-lg" style={{ width: 80, height: 80, objectFit: 'cover', border: '1px solid #d4e8e0' }} />
                            </a>
                          ))}
                        </div>
                      </div>
                    )}

                    {/* Timeline */}
                    <div>
                      <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Průběh incidentu</div>
                      <SOSTimeline incidentId={inc.id} />
                    </div>

                    {/* Komunikace */}
                    <div>
                      <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Komunikace</div>
                      {!messages[inc.id] ? (
                        <p className="text-sm" style={{ color: '#1a2e22' }}>Načítám…</p>
                      ) : messages[inc.id].length === 0 ? (
                        <p className="text-sm" style={{ color: '#1a2e22' }}>Žádná komunikace k tomuto incidentu</p>
                      ) : (
                        <div className="space-y-2">
                          {messages[inc.id].map(msg => (
                            <div key={msg.id} className="p-3 rounded-lg" style={{ background: '#f1faf7' }}>
                              <div className="flex items-center gap-2 mb-1">
                                <span className="text-sm font-bold" style={{ color: '#0f1a14' }}>{msg.type === 'sos_response' ? 'Admin' : msg.type || 'Zpráva'}</span>
                                <span className="text-sm" style={{ color: '#1a2e22' }}>{msg.created_at ? new Date(msg.created_at).toLocaleString('cs-CZ') : ''}</span>
                                {msg.read_at && <Badge label="Přečteno" color="#1a8a18" bg="#dcfce7" />}
                              </div>
                              {msg.subject && <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>{msg.subject}</div>}
                              <p className="text-sm" style={{ color: '#1a2e22' }}>{msg.content || '—'}</p>
                            </div>
                          ))}
                        </div>
                      )}
                    </div>

                    {/* Vyřešení */}
                    {inc.resolution && (
                      <div>
                        <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Řešení</div>
                        <p className="text-sm p-3 rounded-lg" style={{ background: '#dcfce7', color: '#1a8a18' }}>{inc.resolution}</p>
                        {inc.resolved_at && <p className="text-sm mt-1" style={{ color: '#1a2e22' }}>Vyřešeno: {new Date(inc.resolved_at).toLocaleString('cs-CZ')}</p>}
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

function InfoField({ label, value, span2 }) {
  return (
    <div className={span2 ? 'col-span-2' : ''}>
      <div className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22', fontSize: 11 }}>{label}</div>
      <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>{value}</div>
    </div>
  )
}

function BookingLink({ label, booking, moto, badge, onClick }) {
  return (
    <div className="flex items-center gap-3 p-3 rounded-lg cursor-pointer hover:shadow-sm transition-shadow"
      style={{ background: '#f1faf7' }} onClick={onClick}>
      <span style={{ fontSize: 14 }}>📅</span>
      <div className="flex-1">
        <span className="text-sm font-bold" style={{ color: '#0f1a14' }}>{label}</span>
        {moto && <span className="text-sm ml-2" style={{ color: '#1a2e22' }}>🏍 {moto.model} ({moto.spz})</span>}
        <span className="text-sm ml-2" style={{ color: '#1a2e22' }}>{booking.start_date} → {booking.end_date}</span>
      </div>
      {badge && <Badge label={badge.label} color={badge.color} bg={badge.bg} />}
      <span className="text-sm font-bold" style={{ color: '#2563eb' }}>→</span>
    </div>
  )
}
