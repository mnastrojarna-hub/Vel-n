import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import Pagination from '../../components/ui/Pagination'

const PER_PAGE = 25

const STATUS_MAP = {
  pending:   { label: 'Čeká',        color: '#6b7280', bg: '#f3f4f6' },
  enriched:  { label: 'Ke schválení', color: '#b45309', bg: '#fef3c7' },
  validated: { label: 'Připraven',    color: '#2563eb', bg: '#dbeafe' },
  exported:  { label: 'Odesláno',     color: '#7c3aed', bg: '#ede9fe' },
  approved:  { label: 'Schváleno',    color: '#1a8a18', bg: '#dcfce7' },
  submitted: { label: 'Podáno FÚ',   color: '#059669', bg: '#d1fae5' },
  error:     { label: 'Chyba',        color: '#dc2626', bg: '#fee2e2' },
}

const TYPE_MAP = {
  revenue: { label: 'Příjem',  color: '#1a8a18', bg: '#dcfce7' },
  expense: { label: 'Výdaj',   color: '#dc2626', bg: '#fee2e2' },
  asset:   { label: 'Majetek', color: '#7c3aed', bg: '#ede9fe' },
  payroll: { label: 'Mzdy',    color: '#b45309', bg: '#fef3c7' },
}

const SOURCE_LABELS = { stripe: 'Stripe', ocr: 'OCR', system: 'Systém', manual: 'Ručně' }

const CATEGORY_LABELS = {
  phm: 'PHM', pojisteni: 'Pojištění', servis_opravy: 'Servis', najem: 'Nájem',
  energie: 'Energie', telekomunikace: 'Telekom', marketing: 'Marketing',
  kancelar: 'Kancelář', mzdy: 'Mzdy', dane_odvody: 'Daně', ostatni_naklady: 'Ostatní',
  pronajem_motorek: 'Pronájem', prodej_zbozi: 'E-shop', dlouhodoby_majetek: 'DM',
}

const ALL_STATUSES = ['pending', 'enriched', 'validated', 'exported', 'approved', 'submitted', 'error']
const ALL_TYPES = ['revenue', 'expense', 'asset', 'payroll']
const ALL_SOURCES = ['stripe', 'ocr', 'system', 'manual']

export default function FinancialEventsTab() {
  const [events, setEvents] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [resultMsg, setResultMsg] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [stats, setStats] = useState({ pending: 0, validated: 0, error: 0 })

  // Filters
  const [statusFilter, setStatusFilter] = useState([])
  const [typeFilter, setTypeFilter] = useState('')
  const [sourceFilter, setSourceFilter] = useState('')
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')

  // Detail expand
  const [expandedId, setExpandedId] = useState(null)
  // Per-row action loading
  const [actionId, setActionId] = useState(null)

  useEffect(() => { load() }, [page, statusFilter, typeFilter, sourceFilter, dateFrom, dateTo])

  async function load() {
    setLoading(true); setError(null)
    try {
      // Stats
      const { data: allEvents } = await supabase.from('financial_events').select('status')
      const s = { pending: 0, validated: 0, error: 0 }
      for (const e of (allEvents || [])) {
        if (e.status === 'pending' || e.status === 'enriched') s.pending++
        if (e.status === 'validated') s.validated++
        if (e.status === 'error') s.error++
      }
      setStats(s)

      // Events query
      let query = supabase.from('financial_events')
        .select('*', { count: 'exact' })
        .order('duzp', { ascending: false })
        .range((page - 1) * PER_PAGE, page * PER_PAGE - 1)

      if (statusFilter.length > 0) query = query.in('status', statusFilter)
      if (typeFilter) query = query.eq('event_type', typeFilter)
      if (sourceFilter) query = query.eq('source', sourceFilter)
      if (dateFrom) query = query.gte('duzp', dateFrom)
      if (dateTo) query = query.lte('duzp', dateTo)

      const { data, count, error: err } = await query
      if (err) throw err
      setEvents(data || [])
      setTotal(count || 0)
    } catch (e) { setError(e.message) }
    setLoading(false)
  }

  async function pushToFlexi(event) {
    setActionId(event.id); setResultMsg(null)
    try {
      const action = event.event_type === 'expense' ? 'pushExpense'
        : event.event_type === 'asset' ? 'pushAsset' : 'pushInvoice'
      const { data, error: err } = await supabase.functions.invoke('flexi-sync', {
        body: { action, id: event.id },
      })
      if (err) throw err
      if (data?.ok) {
        setResultMsg(`Odesláno do Flexi (ID: ${data.flexi_id})`)
      } else {
        setResultMsg(`Chyba Flexi: ${data?.error || 'neznámá'}`)
      }
      await load()
    } catch (e) { setResultMsg(`Chyba: ${e.message}`) }
    finally { setActionId(null) }
  }

  async function approveEvent(event) {
    setActionId(event.id); setResultMsg(null)
    try {
      const { error: err } = await supabase.from('financial_events')
        .update({ status: 'approved' }).eq('id', event.id)
      if (err) throw err
      setResultMsg('Událost schválena')
      await load()
    } catch (e) { setResultMsg(`Chyba: ${e.message}`) }
    finally { setActionId(null) }
  }

  function toggleStatus(st) {
    setPage(1)
    setStatusFilter(prev => prev.includes(st) ? prev.filter(s => s !== st) : [...prev, st])
  }

  const totalPages = Math.ceil(total / PER_PAGE)
  const fmt = n => (n || 0).toLocaleString('cs-CZ') + ' Kč'

  return (
    <div>
      {/* Stats */}
      <div className="grid grid-cols-3 gap-3 mb-4">
        <StatCard label="Čekající klasifikaci" value={stats.pending} color="#b45309" />
        <StatCard label="Připraveno k exportu" value={stats.validated} color="#2563eb" />
        <StatCard label="Chyby" value={stats.error} color="#dc2626" />
      </div>

      {/* Filters */}
      <div className="flex flex-wrap items-center gap-3 mb-4">
        <div className="flex items-center gap-1 flex-wrap rounded-btn" style={{ padding: '4px 10px', background: statusFilter.length > 0 ? '#e8fde8' : '#f1faf7', border: '1px solid #d4e8e0' }}>
          <span className="text-sm font-extrabold uppercase tracking-wide mr-1" style={{ color: '#1a2e22' }}>Status:</span>
          {ALL_STATUSES.map(st => {
            const m = STATUS_MAP[st]
            return (
              <label key={st} className="flex items-center gap-1 cursor-pointer" style={{ padding: '3px 6px', borderRadius: 6, background: statusFilter.includes(st) ? '#74FB71' : 'transparent' }}>
                <input type="checkbox" checked={statusFilter.includes(st)} onChange={() => toggleStatus(st)} className="accent-[#1a8a18]" style={{ width: 14, height: 14 }} />
                <span className="text-sm font-bold" style={{ color: '#1a2e22', whiteSpace: 'nowrap' }}>{m.label}</span>
              </label>
            )
          })}
        </div>
        <select value={typeFilter} onChange={e => { setPage(1); setTypeFilter(e.target.value) }}
          className="rounded-btn text-sm outline-none" style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <option value="">Všechny typy</option>
          {ALL_TYPES.map(t => <option key={t} value={t}>{TYPE_MAP[t]?.label || t}</option>)}
        </select>
        <select value={sourceFilter} onChange={e => { setPage(1); setSourceFilter(e.target.value) }}
          className="rounded-btn text-sm outline-none" style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <option value="">Všechny zdroje</option>
          {ALL_SOURCES.map(s => <option key={s} value={s}>{SOURCE_LABELS[s]}</option>)}
        </select>
        <input type="date" value={dateFrom} onChange={e => { setPage(1); setDateFrom(e.target.value) }}
          className="rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        <span className="text-sm font-bold" style={{ color: '#6b7280' }}>–</span>
        <input type="date" value={dateTo} onChange={e => { setPage(1); setDateTo(e.target.value) }}
          className="rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        {(statusFilter.length > 0 || typeFilter || sourceFilter || dateFrom || dateTo) && (
          <button onClick={() => { setPage(1); setStatusFilter([]); setTypeFilter(''); setSourceFilter(''); setDateFrom(''); setDateTo('') }}
            className="text-sm font-bold cursor-pointer rounded-btn"
            style={{ padding: '8px 14px', background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}>
            Reset
          </button>
        )}
      </div>

      {error && <div className="mb-3 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}
      {resultMsg && <div className="mb-3 p-3 rounded-card" style={{ background: '#dcfce7', color: '#1a8a18', fontSize: 13 }}>{resultMsg}</div>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Datum</TH><TH>Typ</TH><TH>Zdroj</TH><TH>Částka</TH>
                <TH>AI kategorie</TH><TH>Status</TH><TH>Flexi ID</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {events.map(ev => {
                const st = STATUS_MAP[ev.status] || STATUS_MAP.pending
                const tp = TYPE_MAP[ev.event_type] || TYPE_MAP.expense
                const aiCat = ev.metadata?.ai_classification?.category || ev.metadata?.category || null
                const catLabel = aiCat ? (CATEGORY_LABELS[aiCat] || aiCat) : null
                const isExpanded = expandedId === ev.id
                const isActing = actionId === ev.id
                const hasVat = ev.vat_rate > 0

                return (
                  <>
                    <TRow key={ev.id}>
                      <TD>{ev.duzp ? new Date(ev.duzp).toLocaleDateString('cs-CZ') : '—'}</TD>
                      <TD><Badge label={tp.label} color={tp.color} bg={tp.bg} /></TD>
                      <TD><span className="text-sm font-bold" style={{ color: '#6b7280' }}>{SOURCE_LABELS[ev.source] || ev.source}</span></TD>
                      <TD bold color={ev.event_type === 'revenue' ? '#1a8a18' : '#dc2626'}>
                        {fmt(ev.amount_czk)}
                        {hasVat && <Badge label="DPH" color="#b45309" bg="#fef3c7" />}
                      </TD>
                      <TD>
                        {catLabel ? (
                          <Badge label={catLabel} color="#7c3aed" bg="#ede9fe" />
                        ) : <span className="text-sm" style={{ color: '#d4d4d8' }}>—</span>}
                      </TD>
                      <TD><Badge label={st.label} color={st.color} bg={st.bg} /></TD>
                      <TD mono>
                        {ev.flexi_id ? (
                          <span className="text-sm font-bold" style={{ color: '#1a8a18' }}>{ev.flexi_id}</span>
                        ) : <span className="text-sm" style={{ color: '#d4d4d8' }}>—</span>}
                      </TD>
                      <TD>
                        <div className="flex gap-1 flex-wrap">
                          {ev.status === 'validated' && (
                            <button onClick={() => pushToFlexi(ev)} disabled={isActing}
                              className="text-sm font-bold cursor-pointer"
                              style={{ color: '#2563eb', background: 'none', border: 'none', padding: '4px 6px', opacity: isActing ? 0.5 : 1 }}>
                              {isActing ? '…' : '→ Flexi'}
                            </button>
                          )}
                          {ev.status === 'exported' && (
                            <button onClick={() => approveEvent(ev)} disabled={isActing}
                              className="text-sm font-bold cursor-pointer"
                              style={{ color: '#1a8a18', background: 'none', border: 'none', padding: '4px 6px', opacity: isActing ? 0.5 : 1 }}>
                              {isActing ? '…' : 'Schválit'}
                            </button>
                          )}
                          <button onClick={() => setExpandedId(isExpanded ? null : ev.id)}
                            className="text-sm font-bold cursor-pointer"
                            style={{ color: '#6b7280', background: 'none', border: 'none', padding: '4px 6px' }}>
                            {isExpanded ? 'Skrýt ▴' : 'Detail ▾'}
                          </button>
                        </div>
                      </TD>
                    </TRow>
                    {isExpanded && (
                      <tr key={ev.id + '-detail'} style={{ background: '#f9fafb', borderBottom: '1px solid #d4e8e0' }}>
                        <td colSpan={8} style={{ padding: '12px 16px' }}>
                          <EventDetail event={ev} />
                        </td>
                      </tr>
                    )}
                  </>
                )
              })}
              {events.length === 0 && <TRow><TD>Žádné finanční události</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}
    </div>
  )
}

function EventDetail({ event }) {
  const ai = event.metadata?.ai_classification
  const meta = { ...event.metadata }
  delete meta.ai_classification // show separately

  return (
    <div className="flex flex-wrap gap-8">
      {ai && (
        <div>
          <div className="text-[9px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#7c3aed' }}>AI klasifikace</div>
          <div className="grid grid-cols-2 gap-x-6 gap-y-1">
            <MiniLabel label="Kategorie" value={CATEGORY_LABELS[ai.category] || ai.category || '—'} />
            <MiniLabel label="Účet" value={ai.suggested_account || '—'} mono />
            <MiniLabel label="Opakující se" value={ai.is_recurring ? 'Ano' : 'Ne'} />
            <MiniLabel label="Poznámka" value={ai.classification_note || '—'} />
          </div>
        </div>
      )}
      <div>
        <div className="text-[9px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#6b7280' }}>Metadata</div>
        <pre className="text-xs font-mono p-2 rounded" style={{ background: '#f1faf7', color: '#1a2e22', maxWidth: 500, overflow: 'auto', maxHeight: 200 }}>
          {JSON.stringify(meta, null, 2)}
        </pre>
      </div>
      <div>
        <div className="text-[9px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#6b7280' }}>Info</div>
        <div className="grid grid-cols-2 gap-x-6 gap-y-1">
          <MiniLabel label="ID" value={event.id?.slice(0, 8)} mono />
          <MiniLabel label="Confidence" value={event.confidence_score != null ? `${(event.confidence_score * 100).toFixed(0)}%` : '—'} />
          <MiniLabel label="Vytvořeno" value={event.created_at ? new Date(event.created_at).toLocaleString('cs-CZ') : '—'} />
          <MiniLabel label="Linked" value={event.linked_entity_type ? `${event.linked_entity_type} ${event.linked_entity_id?.slice(0, 8) || ''}` : '—'} />
        </div>
      </div>
    </div>
  )
}

function MiniLabel({ label, value, mono }) {
  return (
    <div className="mb-1">
      <span className="text-[9px] font-extrabold uppercase tracking-wide" style={{ color: '#6b7280' }}>{label}: </span>
      <span className={`text-sm font-bold ${mono ? 'font-mono' : ''}`} style={{ color: '#1a2e22' }}>{value}</span>
    </div>
  )
}

function StatCard({ label, value, color }) {
  return (
    <div className="p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
      <div className="text-[9px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{label}</div>
      <div className="text-lg font-extrabold" style={{ color }}>{value}</div>
    </div>
  )
}
