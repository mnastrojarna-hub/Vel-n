import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import Pagination from '../../components/ui/Pagination'
import Card from '../../components/ui/Card'
import SearchInput from '../../components/ui/SearchInput'
import ConfirmDialog from '../../components/ui/ConfirmDialog'

const PER_PAGE = 25

export default function PromoCodesTab() {
  const [codes, setCodes] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [showAdd, setShowAdd] = useState(false)
  const [editCode, setEditCode] = useState(null)
  const [deleteConfirm, setDeleteConfirm] = useState(null)
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('')
  const [summary, setSummary] = useState({ total: 0, active: 0, inactive: 0, totalUsed: 0 })

  useEffect(() => { load() }, [page, search, statusFilter])
  useEffect(() => { loadSummary() }, [])

  async function load() {
    setLoading(true)
    let query = supabase
      .from('promo_codes')
      .select('*', { count: 'exact' })
      .order('created_at', { ascending: false })

    if (search) {
      query = query.ilike('code', `%${search}%`)
    }
    if (statusFilter) {
      query = query.eq('status', statusFilter)
    }

    query = query.range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
    const { data, count, error: err } = await query
    if (err) setError(err.message)
    else { setCodes(data || []); setTotal(count || 0) }
    setLoading(false)
  }

  async function loadSummary() {
    try {
      const { data } = await supabase.from('promo_codes').select('status, used_count')
      if (data) {
        const now = new Date()
        setSummary({
          total: data.length,
          active: data.filter(c => c.status === 'active').length,
          inactive: data.filter(c => c.status !== 'active').length,
          totalUsed: data.reduce((s, c) => s + (c.used_count || 0), 0),
        })
      }
    } catch {}
  }

  async function toggleStatus(code) {
    const newStatus = code.status === 'active' ? 'inactive' : 'active'
    const { error: err } = await supabase.from('promo_codes').update({ status: newStatus }).eq('id', code.id)
    if (err) { setError(err.message); return }
    await logAudit(newStatus === 'active' ? 'promo_code_activated' : 'promo_code_deactivated', { code: code.code })
    setCodes(prev => prev.map(c => c.id === code.id ? { ...c, status: newStatus } : c))
    loadSummary()
  }

  async function handleDelete(code) {
    const { error: err } = await supabase.from('promo_codes').delete().eq('id', code.id)
    if (err) { setError(err.message); return }
    await logAudit('promo_code_deleted', { code: code.code })
    setDeleteConfirm(null)
    load()
    loadSummary()
  }

  async function logAudit(action, details) {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, details })
    } catch {}
  }

  const totalPages = Math.ceil(total / PER_PAGE)

  return (
    <div>
      {/* Summary cards */}
      <div className="grid grid-cols-4 gap-3 mb-5">
        <SummaryCard label="Celkem kódů" value={summary.total} color="#0f1a14" />
        <SummaryCard label="Aktivní" value={summary.active} color="#1a8a18" />
        <SummaryCard label="Neaktivní" value={summary.inactive} color="#6b7280" />
        <SummaryCard label="Celkem použití" value={summary.totalUsed} color="#2563eb" />
      </div>

      {/* Filters + actions */}
      <div className="flex flex-wrap items-center gap-3 mb-5">
        <SearchInput
          value={search}
          onChange={v => { setPage(1); setSearch(v) }}
          placeholder="Hledat kód…"
        />
        <select
          value={statusFilter}
          onChange={e => { setPage(1); setStatusFilter(e.target.value) }}
          className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#4a6357' }}
        >
          <option value="">Všechny stavy</option>
          <option value="active">Aktivní</option>
          <option value="inactive">Neaktivní</option>
        </select>
        <div className="ml-auto">
          <Button green onClick={() => { setEditCode(null); setShowAdd(true) }}>+ Nový promo kód</Button>
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
                <TH>Použití / Limit</TH><TH>Stav</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {codes.map(c => {
                const isActive = c.status === 'active' && (!c.valid_to || new Date(c.valid_to) >= new Date())
                const isExpired = c.valid_to && new Date(c.valid_to) < new Date()
                const isLimitReached = c.usage_limit && (c.used_count || 0) >= c.usage_limit
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
                    <TD>
                      {c.valid_to ? (
                        <span style={{ color: isExpired ? '#dc2626' : undefined, fontWeight: isExpired ? 700 : undefined }}>
                          {new Date(c.valid_to).toLocaleDateString('cs-CZ')}
                          {isExpired && ' (expirováno)'}
                        </span>
                      ) : '—'}
                    </TD>
                    <TD>
                      <span style={{ color: isLimitReached ? '#dc2626' : undefined, fontWeight: isLimitReached ? 700 : undefined }}>
                        {c.used_count ?? 0} / {c.usage_limit ?? '∞'}
                      </span>
                      {isLimitReached && <span className="text-[10px] ml-1" style={{ color: '#dc2626' }}>(vyčerpáno)</span>}
                    </TD>
                    <TD>
                      <button
                        onClick={() => toggleStatus(c)}
                        className="inline-block rounded-btn text-[10px] font-extrabold tracking-wide uppercase cursor-pointer"
                        style={{
                          padding: '4px 10px',
                          background: isActive ? '#dcfce7' : '#f3f4f6',
                          color: isActive ? '#1a8a18' : '#6b7280',
                          border: 'none',
                        }}
                        title={isActive ? 'Klikni pro deaktivaci' : 'Klikni pro aktivaci'}
                      >
                        {isActive ? 'Aktivní' : 'Neaktivní'}
                      </button>
                    </TD>
                    <TD>
                      <div className="flex gap-1">
                        <button
                          onClick={() => { setEditCode(c); setShowAdd(true) }}
                          className="text-[10px] font-bold cursor-pointer"
                          style={{ color: '#2563eb', background: 'none', border: 'none', padding: '4px 8px' }}
                          title="Upravit"
                        >
                          Upravit
                        </button>
                        <button
                          onClick={() => setDeleteConfirm(c)}
                          className="text-[10px] font-bold cursor-pointer"
                          style={{ color: '#dc2626', background: 'none', border: 'none', padding: '4px 8px' }}
                          title="Smazat"
                        >
                          Smazat
                        </button>
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

      {showAdd && (
        <PromoModal
          existing={editCode}
          onClose={() => { setShowAdd(false); setEditCode(null) }}
          onSaved={() => { setShowAdd(false); setEditCode(null); load(); loadSummary() }}
        />
      )}

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
          discount_type: existing.discount_type || 'percent',
          discount_value: existing.discount_value?.toString() || '',
          valid_from: existing.valid_from || '',
          valid_to: existing.valid_to || '',
          usage_limit: existing.usage_limit?.toString() || '',
          status: existing.status || 'active',
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
        discount_type: form.discount_type,
        discount_value: Number(form.discount_value) || 0,
        usage_limit: form.usage_limit ? Number(form.usage_limit) : null,
        valid_from: form.valid_from || null,
        valid_to: form.valid_to || null,
        status: form.status,
      }

      if (isEdit) {
        const { error } = await supabase.from('promo_codes').update(payload).eq('id', existing.id)
        if (error) throw error
        await logAudit('promo_code_updated', { code: payload.code })
      } else {
        const { error } = await supabase.from('promo_codes').insert({ ...payload, used_count: 0 })
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
          <input
            type="number"
            value={form.discount_value}
            onChange={e => set('discount_value', e.target.value)}
            className="w-full rounded-btn text-sm outline-none"
            style={inputStyle}
            placeholder={form.discount_type === 'percent' ? '10' : '500'}
          />
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
          <input
            type="number"
            value={form.usage_limit}
            onChange={e => set('usage_limit', e.target.value)}
            placeholder="Neomezeno"
            className="w-full rounded-btn text-sm outline-none"
            style={inputStyle}
          />
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
            Tento kód byl použit {existing.used_count}× z {existing.usage_limit ?? '∞'} povolených.
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

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>{children}</label>
}
