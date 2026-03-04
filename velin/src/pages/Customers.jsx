import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'

import { Table, TRow, TH, TD } from '../components/ui/Table'
import SearchInput from '../components/ui/SearchInput'
import Pagination from '../components/ui/Pagination'

const PER_PAGE = 25

export default function Customers() {
  const navigate = useNavigate()
  const [customers, setCustomers] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [search, setSearch] = useState('')

  useEffect(() => { loadCustomers() }, [page, search])

  async function loadCustomers() {
    setLoading(true)
    setError(null)
    try {
      let query = supabase
        .from('profiles')
        .select('*, bookings(count)', { count: 'exact' })

      if (search) {
        query = query.or(`full_name.ilike.%${search}%,email.ilike.%${search}%,phone.ilike.%${search}%`)
      }

      query = query.order('full_name').range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      const { data, count, error: err } = await query
      if (err) throw err
      setCustomers(data || [])
      setTotal(count || 0)
    } catch (e) {
      setError(e.message)    } finally {
      setLoading(false)
    }
  }

  const totalPages = Math.ceil(total / PER_PAGE)

  return (
    <div>
      <div className="flex flex-wrap items-center gap-3 mb-5">
        <SearchInput
          value={search}
          onChange={v => { setPage(1); setSearch(v) }}
          placeholder="Hledat jméno, email, telefon…"
        />
      </div>

      {error && (
        <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>
          {error}
          <button onClick={loadCustomers} className="ml-3 underline cursor-pointer">Zkusit znovu</button>
        </div>
      )}

      {loading ? (
        <div className="flex justify-center py-16">
          <div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" />
        </div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Jméno</TH><TH>Email</TH><TH>Telefon</TH>
                <TH>Řidičák</TH><TH>Registrace</TH><TH>Rezervací</TH>
              </TRow>
            </thead>
            <tbody>
              {customers.map(c => (
                <tr
                  key={c.id}
                  onClick={() => navigate(`/zakaznici/${c.id}`)}
                  className="cursor-pointer hover:bg-[#f1faf7] transition-colors"
                  style={{ borderBottom: '1px solid #d4e8e0' }}
                >
                  <TD bold>{c.full_name || '—'}</TD>
                  <TD>{c.email || '—'}</TD>
                  <TD mono>{c.phone || '—'}</TD>
                  <TD>{c.driver_license ? '✓' : '—'}</TD>
                  <TD>{c.created_at?.slice(0, 10) || '—'}</TD>
                  <TD bold>{c.bookings?.[0]?.count ?? 0}</TD>
                </tr>
              ))}
              {customers.length === 0 && (
                <TRow><TD>Žádní zákazníci</TD></TRow>
              )}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}
    </div>
  )
}
