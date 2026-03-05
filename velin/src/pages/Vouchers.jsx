import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import { Table, TRow, TH, TD } from '../components/ui/Table'
import Button from '../components/ui/Button'
import Badge from '../components/ui/Badge'
import SearchInput from '../components/ui/SearchInput'
import Pagination from '../components/ui/Pagination'
import Card from '../components/ui/Card'

const PER_PAGE = 25

const STATUS_MAP = {
  active: { label: 'Aktivní', color: '#1a8a18', bg: '#dcfce7' },
  redeemed: { label: 'Uplatněn', color: '#2563eb', bg: '#dbeafe' },
  expired: { label: 'Expirován', color: '#dc2626', bg: '#fee2e2' },
  cancelled: { label: 'Zrušen', color: '#6b7280', bg: '#f3f4f6' },
}

export default function Vouchers() {
  const [vouchers, setVouchers] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [filters, setFilters] = useState({ status: '', search: '' })
  const [summary, setSummary] = useState({ total: 0, active: 0, redeemed: 0, expired: 0, totalValue: 0 })

  useEffect(() => { loadVouchers() }, [page, filters])
  useEffect(() => { loadSummary() }, [])

  async function loadVouchers() {
    setLoading(true)
    setError(null)
    try {
      // Poukazy do 3 let zpátky
      const threeYearsAgo = new Date()
      threeYearsAgo.setFullYear(threeYearsAgo.getFullYear() - 3)

      let query = supabase
        .from('vouchers')
        .select('*, profiles(full_name, email), bookings(id, start_date, motorcycles(model))', { count: 'exact' })
        .gte('created_at', threeYearsAgo.toISOString())

      if (filters.status) query = query.eq('status', filters.status)
      if (filters.search) {
        query = query.or(`code.ilike.%${filters.search}%,profiles.full_name.ilike.%${filters.search}%`)
      }

      query = query.order('created_at', { ascending: false }).range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      const { data, count, error: err } = await query
      if (err) throw err
      setVouchers(data || [])
      setTotal(count || 0)
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function loadSummary() {
    try {
      const threeYearsAgo = new Date()
      threeYearsAgo.setFullYear(threeYearsAgo.getFullYear() - 3)

      const { data } = await supabase
        .from('vouchers')
        .select('status, amount')
        .gte('created_at', threeYearsAgo.toISOString())

      if (data) {
        setSummary({
          total: data.length,
          active: data.filter(v => v.status === 'active').length,
          redeemed: data.filter(v => v.status === 'redeemed').length,
          expired: data.filter(v => v.status === 'expired').length,
          totalValue: data.reduce((s, v) => s + (v.amount || 0), 0),
        })
      }
    } catch {}
  }

  const totalPages = Math.ceil(total / PER_PAGE)
  const fmt = (n) => (n || 0).toLocaleString('cs-CZ') + ' Kč'

  return (
    <div>
      {/* Souhrn */}
      <div className="grid grid-cols-5 gap-3 mb-5">
        <SummaryCard label="Celkem poukazů" value={summary.total} color="#0f1a14" />
        <SummaryCard label="Aktivní" value={summary.active} color="#1a8a18" />
        <SummaryCard label="Uplatněné" value={summary.redeemed} color="#2563eb" />
        <SummaryCard label="Expirované" value={summary.expired} color="#dc2626" />
        <SummaryCard label="Celková hodnota" value={fmt(summary.totalValue)} color="#b45309" />
      </div>

      {/* Filtry */}
      <div className="flex flex-wrap items-center gap-3 mb-5">
        <SearchInput
          value={filters.search}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, search: v })) }}
          placeholder="Hledat kód, zákazníka…"
        />
        <FilterSelect
          value={filters.status}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, status: v })) }}
          options={[
            { value: '', label: 'Všechny stavy' },
            { value: 'active', label: 'Aktivní' },
            { value: 'redeemed', label: 'Uplatněné' },
            { value: 'expired', label: 'Expirované' },
            { value: 'cancelled', label: 'Zrušené' },
          ]}
        />
      </div>

      {error && (
        <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>
          {error}
          <button onClick={loadVouchers} className="ml-3 underline cursor-pointer">Zkusit znovu</button>
        </div>
      )}

      {loading ? (
        <div className="flex justify-center py-16"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Kód</TH><TH>Zákazník</TH><TH>Hodnota</TH><TH>Stav</TH>
                <TH>Zakoupeno</TH><TH>Platné do</TH><TH>Uplatněno na</TH><TH>Datum uplatnění</TH>
              </TRow>
            </thead>
            <tbody>
              {vouchers.map(v => {
                const st = STATUS_MAP[v.status] || STATUS_MAP.active
                const isExpired = v.valid_until && new Date(v.valid_until) < new Date() && v.status === 'active'
                return (
                  <TRow key={v.id}>
                    <TD mono bold>{v.code || '—'}</TD>
                    <TD>{v.profiles?.full_name || v.buyer_name || '—'}</TD>
                    <TD bold>{v.amount ? fmt(v.amount) : '—'}</TD>
                    <TD>
                      {isExpired
                        ? <Badge label="Expirován" color="#dc2626" bg="#fee2e2" />
                        : <Badge label={st.label} color={st.color} bg={st.bg} />
                      }
                    </TD>
                    <TD>{v.created_at ? new Date(v.created_at).toLocaleDateString('cs-CZ') : '—'}</TD>
                    <TD>{v.valid_until ? new Date(v.valid_until).toLocaleDateString('cs-CZ') : '—'}</TD>
                    <TD>
                      {v.bookings?.motorcycles?.model
                        ? `${v.bookings.motorcycles.model} (${v.bookings.start_date?.split('T')[0] || ''})`
                        : v.redeemed_for || '—'
                      }
                    </TD>
                    <TD>{v.redeemed_at ? new Date(v.redeemed_at).toLocaleDateString('cs-CZ') : '—'}</TD>
                  </TRow>
                )
              })}
              {vouchers.length === 0 && <TRow><TD>Žádné poukazy</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}
    </div>
  )
}

function SummaryCard({ label, value, color }) {
  return (
    <Card>
      <div className="text-[10px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#8aab99' }}>{label}</div>
      <div className="text-xl font-extrabold" style={{ color }}>{value}</div>
    </Card>
  )
}

function FilterSelect({ value, onChange, options }) {
  return (
    <select value={value} onChange={e => onChange(e.target.value)}
      className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer outline-none"
      style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#4a6357' }}>
      {options.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
    </select>
  )
}
