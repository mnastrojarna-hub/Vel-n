import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import Pagination from '../../components/ui/Pagination'

const PER_PAGE = 25

export default function CashRegisterTab() {
  const [entries, setEntries] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [showAdd, setShowAdd] = useState(false)

  useEffect(() => { load() }, [page])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const { data, count, error: err } = await supabase
        .from('cash_register')
        .select('*', { count: 'exact' })
        .order('date', { ascending: false })
        .range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      if (err) throw err
      setEntries(data || [])
      setTotal(count || 0)
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  const totalPages = Math.ceil(total / PER_PAGE)
  const fmt = (n) => (n || 0).toLocaleString('cs-CZ') + ' Kč'

  return (
    <div>
      <div className="flex items-center gap-3 mb-4">
        <div className="ml-auto">
          <Button green onClick={() => setShowAdd(true)}>+ Nový záznam</Button>
        </div>
      </div>

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Datum</TH><TH>Typ</TH><TH>Popis</TH><TH>Částka</TH><TH>Zůstatek</TH>
              </TRow>
            </thead>
            <tbody>
              {entries.map(e => (
                <TRow key={e.id}>
                  <TD>{e.date ? new Date(e.date).toLocaleDateString('cs-CZ') : '—'}</TD>
                  <TD>
                    <span className="inline-block rounded-btn text-[10px] font-extrabold tracking-wide uppercase"
                      style={{
                        padding: '4px 10px',
                        background: e.type === 'income' ? '#dcfce7' : '#fee2e2',
                        color: e.type === 'income' ? '#1a8a18' : '#dc2626',
                      }}>
                      {e.type === 'income' ? 'Příjem' : 'Výdej'}
                    </span>
                  </TD>
                  <TD>{e.description || '—'}</TD>
                  <TD bold color={e.type === 'income' ? '#1a8a18' : '#dc2626'}>{fmt(e.amount)}</TD>
                  <TD bold>{fmt(e.balance)}</TD>
                </TRow>
              ))}
              {entries.length === 0 && <TRow><TD>Žádné záznamy</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {showAdd && <AddCashModal onClose={() => setShowAdd(false)} onSaved={() => { setShowAdd(false); load() }} />}
    </div>
  )
}

function AddCashModal({ onClose, onSaved }) {
  const [form, setForm] = useState({ type: 'income', amount: '', description: '' })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)

  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const { error } = await supabase.from('cash_register').insert({
        type: form.type,
        amount: Number(form.amount) || 0,
        description: form.description,
        date: new Date().toISOString().slice(0, 10),
      })
      if (error) throw error
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id, action: 'cash_register_entry', details: { type: form.type },
      })
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title="Nový pokladní záznam" onClose={onClose}>
      <div className="space-y-3">
        <div>
          <Label>Typ</Label>
          <select value={form.type} onChange={e => set('type', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            <option value="income">Příjem</option>
            <option value="expense">Výdej</option>
          </select>
        </div>
        <div>
          <Label>Částka (Kč)</Label>
          <input type="number" value={form.amount} onChange={e => set('amount', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div>
          <Label>Popis</Label>
          <input type="text" value={form.description} onChange={e => set('description', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.amount}>{saving ? 'Ukládám…' : 'Uložit'}</Button>
      </div>
    </Modal>
  )
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>{children}</label>
}
