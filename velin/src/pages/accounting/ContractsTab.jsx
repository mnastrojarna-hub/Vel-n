import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Badge from '../../components/ui/Badge'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import Pagination from '../../components/ui/Pagination'

const PER_PAGE = 25

const CONTRACT_TYPES = {
  rental: { label: 'Nájem', color: '#2563eb', bg: '#dbeafe' },
  lease: { label: 'Leasing', color: '#7c3aed', bg: '#ede9fe' },
  service: { label: 'Služba', color: '#0891b2', bg: '#cffafe' },
  insurance: { label: 'Pojištění', color: '#059669', bg: '#d1fae5' },
  employment: { label: 'Pracovní smlouva', color: '#b45309', bg: '#fef3c7' },
  employment_amendment: { label: 'Dodatek k PS', color: '#92400e', bg: '#fef3c7' },
  employment_termination: { label: 'Výpověď', color: '#dc2626', bg: '#fee2e2' },
  dpp: { label: 'DPP', color: '#6d28d9', bg: '#ede9fe' },
  dpc: { label: 'DPČ', color: '#6d28d9', bg: '#ede9fe' },
  vacation_request: { label: 'Žádost o dovolenou', color: '#0284c7', bg: '#e0f2fe' },
  supply: { label: 'Dodavatelská', color: '#1a8a18', bg: '#dcfce7' },
  nda: { label: 'NDA', color: '#6b7280', bg: '#f3f4f6' },
  other: { label: 'Ostatní', color: '#6b7280', bg: '#f3f4f6' },
}

const STATUS_MAP = {
  active: { label: 'Aktivní', color: '#1a8a18', bg: '#dcfce7' },
  pending: { label: 'Ke schválení', color: '#b45309', bg: '#fef3c7' },
  expired: { label: 'Vypršela', color: '#6b7280', bg: '#f3f4f6' },
  terminated: { label: 'Ukončena', color: '#dc2626', bg: '#fee2e2' },
  draft: { label: 'Koncept', color: '#6b7280', bg: '#f3f4f6' },
}

const FILTER_GROUPS = [
  { value: 'all', label: 'Vše' },
  { value: 'general', label: 'Obecné' },
  { value: 'employee', label: 'Zaměstnanecké' },
  { value: 'pending', label: 'Ke schválení' },
]

export default function ContractsTab() {
  const [contracts, setContracts] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [stats, setStats] = useState({ total: 0, active: 0, pending: 0, expiringSoon: 0 })
  const [filterGroup, setFilterGroup] = useState('all')
  const [search, setSearch] = useState('')
  const [detail, setDetail] = useState(null)
  const [resultMsg, setResultMsg] = useState(null)

  useEffect(() => { load() }, [page, filterGroup, search])

  async function load() {
    setLoading(true); setError(null)
    try {
      // Stats
      const { data: all } = await supabase.from('contracts').select('id, status, contract_type, valid_until')
      const now = new Date()
      const in30 = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000)
      const active = (all || []).filter(c => c.status === 'active').length
      const pending = (all || []).filter(c => c.status === 'pending').length
      const expiringSoon = (all || []).filter(c =>
        c.status === 'active' && c.valid_until && new Date(c.valid_until) <= in30
      ).length
      setStats({ total: (all || []).length, active, pending, expiringSoon })

      // Build query
      let query = supabase.from('contracts')
        .select('*', { count: 'exact' })
        .order('created_at', { ascending: false })
        .range((page - 1) * PER_PAGE, page * PER_PAGE - 1)

      const employeeTypes = ['employment', 'employment_amendment', 'employment_termination', 'dpp', 'dpc', 'vacation_request']

      if (filterGroup === 'general') query = query.not('contract_type', 'in', `(${employeeTypes.join(',')})`)
      if (filterGroup === 'employee') query = query.in('contract_type', employeeTypes)
      if (filterGroup === 'pending') query = query.eq('status', 'pending')

      if (search) {
        query = query.or(`title.ilike.%${search}%,counterparty.ilike.%${search}%,contract_number.ilike.%${search}%,notes.ilike.%${search}%`)
      }

      const { data, count, error: err } = await query
      if (err) throw err
      setContracts(data || [])
      setTotal(count || 0)
    } catch (e) { setError(e.message) }
    setLoading(false)
  }

  async function approveContract(contract) {
    try {
      await supabase.from('contracts')
        .update({ status: 'active', approved_at: new Date().toISOString() })
        .eq('id', contract.id)
      setResultMsg('Smlouva schválena')
      await load()
    } catch (e) { setResultMsg(`Chyba: ${e.message}`) }
  }

  async function terminateContract(contract) {
    try {
      await supabase.from('contracts')
        .update({ status: 'terminated', terminated_at: new Date().toISOString() })
        .eq('id', contract.id)
      setResultMsg('Smlouva ukončena')
      await load()
    } catch (e) { setResultMsg(`Chyba: ${e.message}`) }
  }

  async function deleteContract(contract) {
    try {
      await supabase.from('contracts').delete().eq('id', contract.id)
      setResultMsg('Smlouva smazána')
      setDetail(null)
      await load()
    } catch (e) { setResultMsg(`Chyba: ${e.message}`) }
  }

  const totalPages = Math.ceil(total / PER_PAGE)
  const fmt = n => (n || 0).toLocaleString('cs-CZ') + ' Kč'

  return (
    <div>
      {/* Stats */}
      <div className="grid grid-cols-4 gap-3 mb-4">
        <StatCard label="Celkem smluv" value={stats.total} color="#1a2e22" />
        <StatCard label="Aktivní" value={stats.active} color="#1a8a18" />
        <StatCard label="Ke schválení" value={stats.pending} color="#b45309" />
        <StatCard label="Brzy vyprší (30d)" value={stats.expiringSoon} color="#dc2626" />
      </div>

      {/* Filters */}
      <div className="flex flex-wrap items-center gap-3 mb-4">
        {FILTER_GROUPS.map(f => (
          <button key={f.value} onClick={() => { setPage(1); setFilterGroup(f.value) }}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
            style={{
              padding: '6px 14px',
              background: filterGroup === f.value ? '#1a2e22' : '#f1faf7',
              color: filterGroup === f.value ? '#74FB71' : '#1a2e22',
              border: 'none',
              boxShadow: filterGroup === f.value ? '0 2px 8px rgba(26,46,34,.25)' : 'none',
            }}>
            {f.label}
          </button>
        ))}
        <input type="text" value={search} onChange={e => { setPage(1); setSearch(e.target.value) }}
          placeholder="Hledat název, protistranu…"
          className="rounded-btn text-sm outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22', minWidth: 180 }} />
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
                <TH>Číslo</TH><TH>Typ</TH><TH>Název</TH><TH>Protistrana</TH>
                <TH>Částka</TH><TH>Platnost</TH><TH>Status</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {contracts.map(c => {
                const ct = CONTRACT_TYPES[c.contract_type] || CONTRACT_TYPES.other
                const st = STATUS_MAP[c.status] || STATUS_MAP.draft
                const isExpiringSoon = c.status === 'active' && c.valid_until &&
                  new Date(c.valid_until) <= new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)

                return (
                  <TRow key={c.id}>
                    <TD mono bold>{c.contract_number || '—'}</TD>
                    <TD><Badge label={ct.label} color={ct.color} bg={ct.bg} /></TD>
                    <TD><span className="text-sm font-bold" style={{ color: '#1a2e22' }}>{c.title || '—'}</span></TD>
                    <TD>{c.counterparty || '—'}</TD>
                    <TD bold>{c.amount ? fmt(c.amount) : '—'}</TD>
                    <TD>
                      <span className="text-sm" style={{ color: isExpiringSoon ? '#dc2626' : '#1a2e22' }}>
                        {c.valid_from ? new Date(c.valid_from).toLocaleDateString('cs-CZ') : '—'}
                        {c.valid_until ? ` — ${new Date(c.valid_until).toLocaleDateString('cs-CZ')}` : ' — neurčito'}
                      </span>
                      {isExpiringSoon && <span className="ml-1 text-[9px] font-bold" style={{ color: '#dc2626' }}>BRZY VYPRŠÍ</span>}
                    </TD>
                    <TD><Badge label={st.label} color={st.color} bg={st.bg} /></TD>
                    <TD>
                      <div className="flex gap-1 flex-wrap">
                        <button onClick={() => setDetail(c)}
                          className="text-sm font-bold cursor-pointer rounded"
                          style={{ color: '#2563eb', background: '#dbeafe', border: 'none', padding: '4px 10px' }}>
                          Detail
                        </button>
                        {c.status === 'pending' && (
                          <button onClick={() => approveContract(c)}
                            className="text-sm font-bold cursor-pointer rounded"
                            style={{ color: '#fff', background: '#1a8a18', border: 'none', padding: '4px 10px' }}>
                            Schválit
                          </button>
                        )}
                        {c.status === 'active' && (
                          <button onClick={() => terminateContract(c)}
                            className="text-sm font-bold cursor-pointer rounded"
                            style={{ color: '#dc2626', background: '#fee2e2', border: '1px solid #fca5a5', padding: '4px 10px' }}>
                            Ukončit
                          </button>
                        )}
                      </div>
                    </TD>
                  </TRow>
                )
              })}
              {contracts.length === 0 && <TRow><TD>Žádné smlouvy</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {/* Detail modal */}
      {detail && (
        <Modal open title="Detail smlouvy" onClose={() => setDetail(null)}>
          <div className="grid grid-cols-2 gap-4 mb-4">
            <MiniField label="Číslo smlouvy" value={detail.contract_number || '—'} mono />
            <MiniField label="Typ" value={(CONTRACT_TYPES[detail.contract_type] || CONTRACT_TYPES.other).label} />
            <MiniField label="Název" value={detail.title || '—'} />
            <MiniField label="Protistrana" value={detail.counterparty || '—'} />
            <MiniField label="IČO protistrany" value={detail.counterparty_ico || '—'} mono />
            <MiniField label="Částka" value={detail.amount ? fmt(detail.amount) : '—'} />
            <MiniField label="Platnost od" value={detail.valid_from ? new Date(detail.valid_from).toLocaleDateString('cs-CZ') : '—'} />
            <MiniField label="Platnost do" value={detail.valid_until ? new Date(detail.valid_until).toLocaleDateString('cs-CZ') : 'Neurčito'} />
            <MiniField label="Frekvence platby" value={detail.payment_frequency || '—'} />
            <MiniField label="Status" value={(STATUS_MAP[detail.status] || STATUS_MAP.draft).label} />
          </div>

          {/* Employee link */}
          {detail.employee_id && (
            <div className="mb-4 p-3 rounded" style={{ background: '#fef3c7', border: '1px solid #fcd34d' }}>
              <span className="text-[9px] font-extrabold uppercase tracking-wide" style={{ color: '#b45309' }}>Zaměstnanec: </span>
              <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>{detail.employee_name || detail.employee_id.slice(0, 8)}</span>
            </div>
          )}

          {/* AI extracted data */}
          {detail.extracted_data && (
            <div className="mb-4">
              <div className="text-[9px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#7c3aed' }}>AI extrahovaná data</div>
              <pre className="text-xs p-3 rounded" style={{ background: '#f1faf7', color: '#1a2e22', whiteSpace: 'pre-wrap', maxHeight: 200, overflow: 'auto' }}>
                {JSON.stringify(detail.extracted_data, null, 2)}
              </pre>
            </div>
          )}

          {/* Photo */}
          {detail.photo_url && (
            <div className="mb-4">
              <div className="text-[9px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#2563eb' }}>Sken dokumentu</div>
              <a href={detail.photo_url} target="_blank" rel="noopener noreferrer">
                <img src={detail.photo_url} alt="Sken smlouvy" style={{ maxWidth: '100%', maxHeight: 300, borderRadius: 8, border: '1px solid #d4e8e0' }} />
              </a>
            </div>
          )}

          {detail.notes && (
            <div className="mb-4">
              <div className="text-[9px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#6b7280' }}>Poznámky</div>
              <p className="text-sm" style={{ color: '#1a2e22', whiteSpace: 'pre-wrap' }}>{detail.notes}</p>
            </div>
          )}

          <div className="flex justify-between mt-4">
            <button onClick={() => deleteContract(detail)}
              className="text-sm font-bold cursor-pointer rounded"
              style={{ padding: '8px 20px', background: '#dc2626', border: 'none', color: '#fff' }}>
              Smazat
            </button>
            <div className="flex gap-2">
              {detail.status === 'pending' && (
                <button onClick={() => { approveContract(detail); setDetail(null) }}
                  className="text-sm font-bold cursor-pointer rounded"
                  style={{ padding: '8px 20px', background: '#1a8a18', border: 'none', color: '#fff' }}>
                  Schválit
                </button>
              )}
              <Button onClick={() => setDetail(null)}>Zavřít</Button>
            </div>
          </div>
        </Modal>
      )}
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

function MiniField({ label, value, mono }) {
  return (
    <div>
      <div className="text-[9px] font-extrabold uppercase tracking-wide mb-0.5" style={{ color: '#6b7280' }}>{label}</div>
      <div className={`text-sm font-bold ${mono ? 'font-mono' : ''}`} style={{ color: '#1a2e22' }}>{value}</div>
    </div>
  )
}
