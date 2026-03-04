import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { isDemoMode } from '../../lib/demoData'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import Pagination from '../../components/ui/Pagination'

const PER_PAGE = 25

export default function PromoCodesTab() {
  const [codes, setCodes] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [showAdd, setShowAdd] = useState(false)

  useEffect(() => { load() }, [page])

  async function load() {
    if (isDemoMode()) {
      setCodes([])
      setTotal(0)
      setLoading(false)
      return
    }
    setLoading(true)
    const { data, count, error: err } = await supabase
      .from('promo_codes')
      .select('*', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
    if (err) setError(err.message)
    else { setCodes(data || []); setTotal(count || 0) }
    setLoading(false)
  }

  const totalPages = Math.ceil(total / PER_PAGE)

  return (
    <div>
      <div className="flex items-center gap-3 mb-4">
        <div className="ml-auto">
          <Button green onClick={() => setShowAdd(true)}>+ Nový promo kód</Button>
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
                <TH>Kód</TH><TH>Sleva</TH><TH>Platnost od</TH><TH>Platnost do</TH>
                <TH>Použití/Limit</TH><TH>Stav</TH>
              </TRow>
            </thead>
            <tbody>
              {codes.map(c => {
                const isActive = c.status === 'active' && (!c.valid_to || new Date(c.valid_to) >= new Date())
                return (
                  <TRow key={c.id}>
                    <TD mono bold>{c.code}</TD>
                    <TD bold>
                      {c.discount_type === 'percent'
                        ? `${c.discount_value}%`
                        : `${(c.discount_value || 0).toLocaleString('cs-CZ')} Kč`
                      }
                    </TD>
                    <TD>{c.valid_from ? new Date(c.valid_from).toLocaleDateString('cs-CZ') : '—'}</TD>
                    <TD>{c.valid_to ? new Date(c.valid_to).toLocaleDateString('cs-CZ') : '—'}</TD>
                    <TD>{c.used_count ?? 0} / {c.usage_limit ?? '∞'}</TD>
                    <TD>
                      <span className="inline-block rounded-btn text-[10px] font-extrabold tracking-wide uppercase"
                        style={{
                          padding: '4px 10px',
                          background: isActive ? '#dcfce7' : '#f3f4f6',
                          color: isActive ? '#1a8a18' : '#6b7280',
                        }}>
                        {isActive ? 'Aktivní' : 'Neaktivní'}
                      </span>
                    </TD>
                  </TRow>
                )
              })}
              {codes.length === 0 && <TRow><TD>Žádné promo kódy</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {showAdd && <PromoModal onClose={() => setShowAdd(false)} onSaved={() => { setShowAdd(false); load() }} />}
    </div>
  )
}

function PromoModal({ onClose, onSaved }) {
  const [form, setForm] = useState({ code: '', discount_type: 'percent', discount_value: '', valid_from: '', valid_to: '', usage_limit: '' })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const { error } = await supabase.from('promo_codes').insert({
        ...form,
        discount_value: Number(form.discount_value) || 0,
        usage_limit: form.usage_limit ? Number(form.usage_limit) : null,
        valid_from: form.valid_from || null,
        valid_to: form.valid_to || null,
        status: 'active',
        used_count: 0,
      })
      if (error) throw error
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: 'promo_code_created', details: { code: form.code } })
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title="Nový promo kód" onClose={onClose}>
      <div className="grid grid-cols-2 gap-3">
        <div className="col-span-2"><Label>Kód</Label><input value={form.code} onChange={e => set('code', e.target.value.toUpperCase())} className="w-full rounded-btn text-sm outline-none font-mono" style={inputStyle} /></div>
        <div>
          <Label>Typ slevy</Label>
          <select value={form.discount_type} onChange={e => set('discount_type', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            <option value="percent">Procenta (%)</option>
            <option value="fixed">Pevná částka (Kč)</option>
          </select>
        </div>
        <div><Label>Hodnota slevy</Label><input type="number" value={form.discount_value} onChange={e => set('discount_value', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Platnost od</Label><input type="date" value={form.valid_from} onChange={e => set('valid_from', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Platnost do</Label><input type="date" value={form.valid_to} onChange={e => set('valid_to', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Limit použití</Label><input type="number" value={form.usage_limit} onChange={e => set('usage_limit', e.target.value)} placeholder="Neomezeno" className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.code}>{saving ? 'Ukládám…' : 'Vytvořit'}</Button>
      </div>
    </Modal>
  )
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>{children}</label>
}
