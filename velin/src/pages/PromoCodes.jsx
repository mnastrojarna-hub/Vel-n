import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import { Table, TRow, TH, TD } from '../components/ui/Table'
import Button from '../components/ui/Button'
import Badge from '../components/ui/Badge'
import SearchInput from '../components/ui/SearchInput'
import Pagination from '../components/ui/Pagination'
import Card from '../components/ui/Card'
import Modal from '../components/ui/Modal'
import ConfirmDialog from '../components/ui/ConfirmDialog'

const PER_PAGE = 25

export default function PromoCodes() {
  const [codes, setCodes] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [filters, setFilters] = useState({ status: '', search: '' })
  const [summary, setSummary] = useState({ total: 0, active: 0, inactive: 0, expired: 0, totalUsed: 0, totalValue: 0 })
  const [showModal, setShowModal] = useState(false)
  const [editCode, setEditCode] = useState(null)
  const [detailCode, setDetailCode] = useState(null)
  const [deleteConfirm, setDeleteConfirm] = useState(null)

  useEffect(() => { loadCodes() }, [page, filters])
  useEffect(() => { autoExpirePromos(); loadSummary() }, [])

  async function autoExpirePromos() {
    try {
      await supabase.from('promo_codes')
        .update({ active: false })
        .eq('active', true)
        .lt('valid_to', new Date().toISOString().slice(0, 10))
    } catch (e) { console.warn('Auto-expire promos error:', e) }
  }

  async function loadCodes() {
    setLoading(true)
    setError(null)
    try {
      let query = supabase
        .from('promo_codes')
        .select('*', { count: 'exact' })
        .order('created_at', { ascending: false })

      if (filters.status === 'active') query = query.eq('active', true)
      else if (filters.status === 'inactive') query = query.eq('active', false)
      else if (filters.status === 'expired') {
        query = query.lt('valid_to', new Date().toISOString().split('T')[0])
      }

      if (filters.search) {
        query = query.ilike('code', `%${filters.search}%`)
      }

      query = query.range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      const { data, count, error: err } = await debugAction('loadCodes', 'PromoCodes', () => query, { page, filters })
      if (err) throw err
      setCodes(data || [])
      setTotal(count || 0)
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function loadSummary() {
    try {
      const { data } = await supabase.from('promo_codes').select('active, used_count, value, type, valid_to')
      if (data) {
        const now = new Date()
        setSummary({
          total: data.length,
          active: data.filter(c => c.active && (!c.valid_to || new Date(c.valid_to) >= now)).length,
          inactive: data.filter(c => !c.active).length,
          expired: data.filter(c => c.valid_to && new Date(c.valid_to) < now).length,
          totalUsed: data.reduce((s, c) => s + (c.used_count || 0), 0),
        })
      }
    } catch {}
  }

  async function toggleStatus(code) {
    const newActive = !code.active
    const { error: err } = await debugAction('toggleStatus', 'PromoCodes', () => supabase.from('promo_codes').update({ active: newActive }).eq('id', code.id), { id: code.id, active: newActive })
    if (err) { setError(err.message); return }
    await logAudit(newActive ? 'promo_code_activated' : 'promo_code_deactivated', { code: code.code })
    setCodes(prev => prev.map(c => c.id === code.id ? { ...c, active: newActive } : c))
    loadSummary()
  }

  async function handleDelete(code) {
    const { error: err } = await debugAction('handleDelete', 'PromoCodes', () => supabase.from('promo_codes').delete().eq('id', code.id), { id: code.id, code: code.code })
    if (err) { setError(err.message); return }
    await logAudit('promo_code_deleted', { code: code.code })
    setDeleteConfirm(null)
    loadCodes()
    loadSummary()
  }

  async function logAudit(action, details) {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, details })
    } catch {}
  }

  function openEdit(code) {
    setEditCode(code)
    setShowModal(true)
    setDetailCode(null)
  }

  function openCreate() {
    setEditCode(null)
    setShowModal(true)
  }

  const totalPages = Math.ceil(total / PER_PAGE)

  return (
    <div>
      {/* Summary */}
      <div className="grid grid-cols-5 gap-3 mb-5">
        <SummaryCard label="Celkem kódů" value={summary.total} color="#0f1a14" />
        <SummaryCard label="Aktivní" value={summary.active} color="#1a8a18" />
        <SummaryCard label="Neaktivní" value={summary.inactive} color="#6b7280" />
        <SummaryCard label="Expirované" value={summary.expired} color="#dc2626" />
        <SummaryCard label="Celkem použití" value={summary.totalUsed} color="#2563eb" />
      </div>

      {/* Filters */}
      <div className="flex flex-wrap items-center gap-3 mb-5">
        <SearchInput
          value={filters.search}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, search: v })) }}
          placeholder="Hledat kód…"
        />
        <FilterSelect
          value={filters.status}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, status: v })) }}
          options={[
            { value: '', label: 'Všechny stavy' },
            { value: 'active', label: 'Aktivní' },
            { value: 'inactive', label: 'Neaktivní' },
            { value: 'expired', label: 'Expirované' },
          ]}
        />
        <div className="ml-auto">
          <Button green onClick={openCreate}>+ Nový promo kód</Button>
        </div>
      </div>

      {error && (
        <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>
          {error}
          <button onClick={loadCodes} className="ml-3 underline cursor-pointer">Zkusit znovu</button>
        </div>
      )}

      {loading ? (
        <div className="flex justify-center py-16"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Kód</TH><TH>Sleva</TH><TH>Platnost</TH>
                <TH>Použití / Limit</TH><TH>Stav</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {codes.map(c => {
                const isActive = c.active && (!c.valid_to || new Date(c.valid_to) >= new Date())
                const isExpired = c.valid_to && new Date(c.valid_to) < new Date()
                const isLimitReached = c.max_uses && (c.used_count || 0) >= c.max_uses
                return (
                  <TRow key={c.id}>
                    <TD>
                      <button
                        onClick={() => setDetailCode(c)}
                        className="font-mono font-bold text-sm cursor-pointer"
                        style={{ color: '#2563eb', background: 'none', border: 'none', padding: 0 }}
                      >
                        {c.code}
                      </button>
                    </TD>
                    <TD bold>
                      {c.type === 'percent'
                        ? `${c.value}%`
                        : `${(c.value || 0).toLocaleString('cs-CZ')} Kč`
                      }
                    </TD>
                    <TD>
                      <span className="text-xs">
                        {c.valid_from ? new Date(c.valid_from).toLocaleDateString('cs-CZ') : '—'}
                        {' → '}
                        {c.valid_to ? (
                          <span style={{ color: isExpired ? '#dc2626' : undefined, fontWeight: isExpired ? 700 : undefined }}>
                            {new Date(c.valid_to).toLocaleDateString('cs-CZ')}
                          </span>
                        ) : '∞'}
                      </span>
                    </TD>
                    <TD>
                      <span style={{ color: isLimitReached ? '#dc2626' : undefined, fontWeight: isLimitReached ? 700 : undefined }}>
                        {c.used_count ?? 0} / {c.max_uses ?? '∞'}
                      </span>
                      {isLimitReached && <span className="text-[10px] ml-1" style={{ color: '#dc2626' }}>(vyčerpáno)</span>}
                    </TD>
                    <TD>
                      <button
                        onClick={() => toggleStatus(c)}
                        className="inline-block rounded-btn text-[10px] font-extrabold tracking-wide uppercase cursor-pointer"
                        style={{
                          padding: '4px 10px',
                          background: isActive ? '#dcfce7' : isExpired ? '#fee2e2' : '#f3f4f6',
                          color: isActive ? '#1a8a18' : isExpired ? '#dc2626' : '#6b7280',
                          border: 'none',
                        }}
                        title={isExpired ? 'Expirovaný' : isActive ? 'Klikni pro deaktivaci' : 'Klikni pro aktivaci'}
                      >
                        {isExpired ? 'Expirovaný' : isActive ? 'Aktivní' : 'Neaktivní'}
                      </button>
                    </TD>
                    <TD>
                      <div className="flex gap-1">
                        <ActionBtn color="#2563eb" onClick={() => openEdit(c)}>Upravit</ActionBtn>
                        <ActionBtn color="#b45309" onClick={() => toggleStatus(c)}>
                          {c.active ? 'Deaktivovat' : 'Aktivovat'}
                        </ActionBtn>
                        <ActionBtn color="#dc2626" onClick={() => setDeleteConfirm(c)}>Smazat</ActionBtn>
                      </div>
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

      {/* Detail panel */}
      {detailCode && (
        <PromoDetailModal code={detailCode} onClose={() => setDetailCode(null)} onEdit={() => openEdit(detailCode)} />
      )}

      {/* Create/Edit modal */}
      {showModal && (
        <PromoModal
          existing={editCode}
          onClose={() => { setShowModal(false); setEditCode(null) }}
          onSaved={() => { setShowModal(false); setEditCode(null); loadCodes(); loadSummary() }}
        />
      )}

      {/* Delete confirm */}
      {deleteConfirm && (
        <ConfirmDialog
          open
          title="Smazat promo kód?"
          message={`Opravdu chcete trvale smazat promo kód "${deleteConfirm.code}"? Tuto akci nelze vrátit.`}
          danger
          onConfirm={() => handleDelete(deleteConfirm)}
          onCancel={() => setDeleteConfirm(null)}
        />
      )}
    </div>
  )
}

function PromoModal({ existing, onClose, onSaved }) {
  const isEdit = !!existing
  const [form, setForm] = useState(
    existing
      ? {
          code: existing.code || '',
          discount_type: existing.type || 'percent',
          discount_value: existing.value?.toString() || '',
          valid_from: existing.valid_from || '',
          valid_to: existing.valid_to || '',
          usage_limit: existing.max_uses?.toString() || '',
          status: existing.active ? 'active' : 'inactive',
        }
      : { code: '', discount_type: 'percent', discount_value: '', valid_from: '', valid_to: '', usage_limit: '', status: 'active' }
  )
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const payload = {
        code: form.code.trim().toUpperCase(),
        type: form.discount_type,
        value: Number(form.discount_value) || 0,
        max_uses: form.usage_limit ? Number(form.usage_limit) : null,
        valid_from: form.valid_from || null,
        valid_to: form.valid_to || null,
        active: form.status === 'active',
      }

      if (isEdit) {
        const { error } = await debugAction('handleSave:update', 'PromoCodes', () => supabase.from('promo_codes').update(payload).eq('id', existing.id), { id: existing.id, payload })
        if (error) throw error
        await logAudit('promo_code_updated', { code: payload.code })
      } else {
        const { error } = await debugAction('handleSave:insert', 'PromoCodes', () => supabase.from('promo_codes').insert({ ...payload, used_count: 0 }), { payload })
        if (error) throw error
        await logAudit('promo_code_created', { code: payload.code })
      }
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  async function logAudit(action, details) {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, details })
    } catch {}
  }

  return (
    <Modal open title={isEdit ? `Upravit: ${existing.code}` : 'Nový promo kód'} onClose={onClose}>
      <div className="grid grid-cols-2 gap-3">
        <div className="col-span-2">
          <Label>Kód</Label>
          <input
            value={form.code}
            onChange={e => set('code', e.target.value.toUpperCase())}
            className="w-full rounded-btn text-sm outline-none font-mono"
            style={inputStyle}
            placeholder="LETO2026"
            disabled={isEdit}
          />
          {isEdit && <span className="text-[10px]" style={{ color: '#8aab99' }}>Kód nelze měnit po vytvoření</span>}
        </div>
        <div>
          <Label>Typ slevy</Label>
          <select value={form.discount_type} onChange={e => set('discount_type', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            <option value="percent">Procenta (%)</option>
            <option value="fixed">Pevná částka (Kč)</option>
          </select>
        </div>
        <div>
          <Label>Hodnota slevy</Label>
          <input type="number" value={form.discount_value} onChange={e => set('discount_value', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} placeholder={form.discount_type === 'percent' ? '10' : '500'} />
        </div>
        <div>
          <Label>Platnost od</Label>
          <input type="date" value={form.valid_from} onChange={e => set('valid_from', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div>
          <Label>Platnost do</Label>
          <input type="date" value={form.valid_to} onChange={e => set('valid_to', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div>
          <Label>Limit použití</Label>
          <input type="number" value={form.usage_limit} onChange={e => set('usage_limit', e.target.value)} placeholder="Neomezeno" className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div>
          <Label>Stav</Label>
          <select value={form.status} onChange={e => set('status', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            <option value="active">Aktivní</option>
            <option value="inactive">Neaktivní</option>
          </select>
        </div>
      </div>

      {isEdit && existing.used_count > 0 && (
        <div className="mt-3 p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <span className="text-xs font-bold" style={{ color: '#4a6357' }}>
            Tento kód byl použit {existing.used_count}× z {existing.max_uses ?? '∞'} povolených.
          </span>
        </div>
      )}

      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.code || !form.discount_value}>
          {saving ? 'Ukládám…' : isEdit ? 'Uložit změny' : 'Vytvořit'}
        </Button>
      </div>
    </Modal>
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

function DetailRow({ label, value, mono }) {
  return (
    <div>
      <div className="text-[10px] font-extrabold uppercase tracking-wide mb-0.5" style={{ color: '#8aab99' }}>{label}</div>
      <div className={`text-sm font-semibold ${mono ? 'font-mono' : ''}`} style={{ color: '#0f1a14' }}>{value ?? '—'}</div>
    </div>
  )
}

function PromoDetailModal({ code, onClose, onEdit }) {
  const [usage, setUsage] = useState([])
  const [loadingUsage, setLoadingUsage] = useState(true)

  useEffect(() => {
    supabase.from('promo_code_usage')
      .select('*, profiles:customer_id(full_name, email)')
      .eq('promo_code_id', code.id)
      .order('used_at', { ascending: false })
      .limit(20)
      .then(({ data }) => { setUsage(data || []); setLoadingUsage(false) })
      .catch(() => { setUsage([]); setLoadingUsage(false) })
  }, [code.id])

  return (
    <Modal open title={`Detail: ${code.code}`} onClose={onClose}>
      <div className="grid grid-cols-2 gap-4">
        <DetailRow label="Kod" value={code.code} mono />
        <DetailRow label="Stav" value={code.active ? 'Aktivni' : 'Neaktivni'} />
        <DetailRow label="Typ slevy" value={code.type === 'percent' ? 'Procentualni' : 'Pevna castka'} />
        <DetailRow label="Hodnota" value={code.type === 'percent' ? `${code.value}%` : `${code.value?.toLocaleString('cs-CZ')} Kc`} />
        <DetailRow label="Platnost od" value={code.valid_from ? new Date(code.valid_from).toLocaleDateString('cs-CZ') : 'Neuvedeno'} />
        <DetailRow label="Platnost do" value={code.valid_to ? new Date(code.valid_to).toLocaleDateString('cs-CZ') : 'Neomezena'} />
        <DetailRow label="Pouzito" value={`${code.used_count ?? 0}x`} />
        <DetailRow label="Limit" value={code.max_uses ?? 'Neomezeno'} />
        <DetailRow label="Vytvoreno" value={code.created_at ? new Date(code.created_at).toLocaleString('cs-CZ') : '\u2014'} />
      </div>

      {/* Historie pouziti */}
      <div className="mt-5">
        <h4 className="text-[10px] font-extrabold uppercase tracking-widest mb-3" style={{ color: '#8aab99' }}>Historie pouziti</h4>
        {loadingUsage ? (
          <div className="text-xs" style={{ color: '#8aab99' }}>Nacitam...</div>
        ) : usage.length === 0 ? (
          <div className="text-xs" style={{ color: '#8aab99' }}>Zatim nepouzito</div>
        ) : (
          <div className="space-y-2 max-h-48 overflow-auto">
            {usage.map(u => (
              <div key={u.id} className="flex items-center gap-3 p-2 rounded-lg text-xs" style={{ background: '#f1faf7' }}>
                <span className="font-bold">{u.profiles?.full_name || u.profiles?.email || 'Neznamy'}</span>
                <span style={{ color: '#8aab99' }}>{u.used_at ? new Date(u.used_at).toLocaleString('cs-CZ') : ''}</span>
                <span className="ml-auto font-bold" style={{ color: '#1a8a18' }}>-{u.discount_applied?.toLocaleString('cs-CZ')} Kc</span>
              </div>
            ))}
          </div>
        )}
      </div>

      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zavrit</Button>
        <Button onClick={onEdit} style={{ background: '#2563eb', color: '#fff' }}>Upravit</Button>
      </div>
    </Modal>
  )
}

function ActionBtn({ children, color, onClick }) {
  return (
    <button
      onClick={onClick}
      className="text-[10px] font-bold cursor-pointer"
      style={{ color, background: 'none', border: 'none', padding: '4px 6px' }}
    >
      {children}
    </button>
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

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>{children}</label>
}
