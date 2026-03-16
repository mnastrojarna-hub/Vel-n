import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import { Table, TRow, TH, TD } from '../components/ui/Table'
import Button from '../components/ui/Button'
import SearchInput from '../components/ui/SearchInput'
import Pagination from '../components/ui/Pagination'
import Card from '../components/ui/Card'
import Modal from '../components/ui/Modal'
import ConfirmDialog from '../components/ui/ConfirmDialog'

const PER_PAGE = 25
const CATEGORIES = [
  { value: 'rental', label: 'Pronájem' },
  { value: 'gear', label: 'Vybavení' },
  { value: 'experience', label: 'Zážitek' },
  { value: 'gift', label: 'Dárek' },
]

export default function GiftVouchers() {
  const [vouchers, setVouchers] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const defaultFilters = { statuses: [], search: '' }
  const [filters, setFilters] = useState(() => {
    try {
      const saved = localStorage.getItem('velin_vouchers_filters')
      if (saved) return { ...defaultFilters, ...JSON.parse(saved) }
    } catch {}
    return defaultFilters
  })
  useEffect(() => { localStorage.setItem('velin_vouchers_filters', JSON.stringify(filters)) }, [filters])
  const [summary, setSummary] = useState({ total: 0, active: 0, redeemed: 0, expired: 0, totalValue: 0 })
  const [showModal, setShowModal] = useState(false)
  const [editVoucher, setEditVoucher] = useState(null)
  const [detailVoucher, setDetailVoucher] = useState(null)
  const [deleteConfirm, setDeleteConfirm] = useState(null)
  const [redeemModal, setRedeemModal] = useState(null)

  useEffect(() => { loadVouchers() }, [page, filters])
  useEffect(() => { autoExpireVouchers(); loadSummary() }, [])

  async function autoExpireVouchers() {
    try {
      // Auto-expire vouchers past valid_until
      await supabase.from('vouchers')
        .update({ status: 'expired', updated_at: new Date().toISOString() })
        .eq('status', 'active')
        .lt('valid_until', new Date().toISOString().slice(0, 10))
      // Auto-deactivate promo codes past valid_to
      await supabase.from('promo_codes')
        .update({ active: false })
        .eq('active', true)
        .lt('valid_to', new Date().toISOString().slice(0, 10))
    } catch (e) { console.warn('Auto-expire error:', e) }
  }

  async function loadVouchers() {
    setLoading(true)
    setError(null)
    try {
      let query = supabase
        .from('vouchers')
        .select('*', { count: 'exact' })
        .order('created_at', { ascending: false })

      if (filters.statuses?.length > 0) query = query.in('status', filters.statuses)
      else if (filters.status) query = query.eq('status', filters.status)
      if (filters.search) {
        query = query.or(`code.ilike.%${filters.search}%,buyer_name.ilike.%${filters.search}%,buyer_email.ilike.%${filters.search}%`)
      }

      query = query.range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
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
      const { data } = await supabase.from('vouchers').select('status, amount')
      if (data) {
        setSummary({
          total: data.length,
          active: data.filter(v => v.status === 'active').length,
          redeemed: data.filter(v => v.status === 'redeemed').length,
          expired: data.filter(v => v.status === 'expired').length,
          totalValue: data.filter(v => v.status === 'active').reduce((s, v) => s + Number(v.amount || 0), 0),
        })
      }
    } catch {}
  }

  async function handleCancel(voucher) {
    const { error: err } = await debugAction('cancelVoucher', 'GiftVouchers', () =>
      supabase
        .from('vouchers')
        .update({ status: 'cancelled', updated_at: new Date().toISOString() })
        .eq('id', voucher.id),
      { voucherId: voucher.id, code: voucher.code }
    )
    if (err) { setError(err.message); return }
    await logAudit('voucher_cancelled', { code: voucher.code })
    setDeleteConfirm(null)
    loadVouchers()
    loadSummary()
  }

  async function handleRedeem(voucher, redeemData) {
    const { data: { user } } = await supabase.auth.getUser()
    const { error: err } = await debugAction('redeemVoucher', 'GiftVouchers', () =>
      supabase
        .from('vouchers')
        .update({
          status: 'redeemed',
          redeemed_at: new Date().toISOString(),
          redeemed_by: redeemData.redeemed_by || null,
          redeemed_for: redeemData.redeemed_for || null,
          booking_id: redeemData.booking_id || null,
          updated_at: new Date().toISOString(),
        })
        .eq('id', voucher.id),
      { voucherId: voucher.id, code: voucher.code, redeemData }
    )
    if (err) { setError(err.message); return }
    await logAudit('voucher_redeemed', { code: voucher.code, redeemed_for: redeemData.redeemed_for })
    setRedeemModal(null)
    loadVouchers()
    loadSummary()
  }

  async function logAudit(action, details) {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, details })
    } catch {}
  }

  const statusBadge = (status) => {
    const map = {
      active: { bg: '#dcfce7', color: '#1a8a18', label: 'Aktivní' },
      redeemed: { bg: '#dbeafe', color: '#2563eb', label: 'Uplatněn' },
      expired: { bg: '#fee2e2', color: '#dc2626', label: 'Expirovaný' },
      cancelled: { bg: '#f3f4f6', color: '#1a2e22', label: 'Zrušen' },
    }
    const s = map[status] || map.cancelled
    return (
      <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase"
        style={{ padding: '4px 10px', background: s.bg, color: s.color }}>
        {s.label}
      </span>
    )
  }

  const totalPages = Math.ceil(total / PER_PAGE)

  return (
    <div>
      {/* DIAGNOSTIKA */}
      <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
        <strong>DIAGNOSTIKA GiftVouchers</strong><br/>
        <div>vouchers: {vouchers.length} zobrazeno / {total} celkem (strana {page}/{totalPages || 1})</div>
        <div>summary: total={summary.total}, active={summary.active}, redeemed={summary.redeemed}, expired={summary.expired}</div>
        <div>totalValue (active): {summary.totalValue?.toLocaleString('cs-CZ')} Kč</div>
        <div>filtry: status={filters.statuses?.length > 0 ? filters.statuses.join(',') : 'vše'}, search="{filters.search}"</div>
        {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
      </div>

      {/* Summary */}
      <div className="grid grid-cols-5 gap-3 mb-5">
        <SummaryCard label="Celkem poukazů" value={summary.total} color="#0f1a14" />
        <SummaryCard label="Aktivní" value={summary.active} color="#1a8a18" />
        <SummaryCard label="Uplatněné" value={summary.redeemed} color="#2563eb" />
        <SummaryCard label="Expirované" value={summary.expired} color="#dc2626" />
        <SummaryCard label="Hodnota aktivních" value={`${summary.totalValue.toLocaleString('cs-CZ')} Kč`} color="#b45309" />
      </div>

      {/* Filters */}
      <div className="flex flex-wrap items-center gap-3 mb-5">
        <SearchInput
          value={filters.search}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, search: v })) }}
          placeholder="Hledat kód, jméno, email…"
        />
        <CheckboxFilterGroup label="Stav" values={filters.statuses || []}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, statuses: v })) }}
          options={[{ value: 'active', label: 'Aktivní' }, { value: 'redeemed', label: 'Uplatněné' }, { value: 'expired', label: 'Expirované' }, { value: 'cancelled', label: 'Zrušené' }]} />
        <button onClick={() => { setPage(1); setFilters({ ...defaultFilters }); localStorage.removeItem('velin_vouchers_filters') }}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
          style={{ padding: '8px 14px', background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}>
          Reset
        </button>
        <div className="ml-auto">
          <Button green onClick={() => { setEditVoucher(null); setShowModal(true) }}>+ Nový poukaz</Button>
        </div>
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
                <TH>Kód</TH><TH>Hodnota</TH><TH>Kupující</TH>
                <TH>Platnost</TH><TH>Kategorie</TH><TH>Stav</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {vouchers.map(v => (
                <TRow key={v.id}>
                  <TD>
                    <button
                      onClick={() => setDetailVoucher(v)}
                      className="font-mono font-bold text-sm cursor-pointer"
                      style={{ color: '#2563eb', background: 'none', border: 'none', padding: 0 }}
                    >
                      {v.code}
                    </button>
                  </TD>
                  <TD bold>{Number(v.amount || 0).toLocaleString('cs-CZ')} {v.currency}</TD>
                  <TD>
                    <span className="text-sm">{v.buyer_name || v.buyer_email || '—'}</span>
                  </TD>
                  <TD>
                    <span className="text-sm">
                      {v.valid_from ? new Date(v.valid_from).toLocaleDateString('cs-CZ') : '—'}
                      {' → '}
                      {v.valid_until ? new Date(v.valid_until).toLocaleDateString('cs-CZ') : '∞'}
                    </span>
                  </TD>
                  <TD>
                    <span className="text-sm">{CATEGORIES.find(c => c.value === v.category)?.label || v.category || '—'}</span>
                  </TD>
                  <TD>{statusBadge(v.status)}</TD>
                  <TD>
                    <div className="flex gap-1">
                      {v.status === 'active' && (
                        <ActionBtn color="#1a8a18" onClick={() => setRedeemModal(v)}>Uplatnit</ActionBtn>
                      )}
                      <ActionBtn color="#2563eb" onClick={() => { setEditVoucher(v); setShowModal(true); setDetailVoucher(null) }}>Upravit</ActionBtn>
                      {v.status === 'active' && (
                        <ActionBtn color="#dc2626" onClick={() => setDeleteConfirm(v)}>Zrušit</ActionBtn>
                      )}
                    </div>
                  </TD>
                </TRow>
              ))}
              {vouchers.length === 0 && <TRow><TD>Žádné dárkové poukazy</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {/* Detail */}
      {detailVoucher && (
        <Modal open title={`Poukaz: ${detailVoucher.code}`} onClose={() => setDetailVoucher(null)}>
          <div className="grid grid-cols-2 gap-4">
            <DetailRow label="Kód" value={detailVoucher.code} mono />
            <DetailRow label="Stav" value={statusBadge(detailVoucher.status)} />
            <DetailRow label="Hodnota" value={`${Number(detailVoucher.amount).toLocaleString('cs-CZ')} ${detailVoucher.currency}`} />
            <DetailRow label="Kategorie" value={CATEGORIES.find(c => c.value === detailVoucher.category)?.label || detailVoucher.category || '—'} />
            <DetailRow label="Kupující" value={detailVoucher.buyer_name || '—'} />
            <DetailRow label="Email kupujícího" value={detailVoucher.buyer_email || '—'} />
            <DetailRow label="Platnost od" value={detailVoucher.valid_from ? new Date(detailVoucher.valid_from).toLocaleDateString('cs-CZ') : '—'} />
            <DetailRow label="Platnost do" value={detailVoucher.valid_until ? new Date(detailVoucher.valid_until).toLocaleDateString('cs-CZ') : '—'} />
            {detailVoucher.redeemed_at && (
              <>
                <DetailRow label="Uplatněn dne" value={new Date(detailVoucher.redeemed_at).toLocaleString('cs-CZ')} />
                <DetailRow label="Uplatněn za" value={detailVoucher.redeemed_for || '—'} />
              </>
            )}
            {detailVoucher.description && (
              <div className="col-span-2">
                <DetailRow label="Popis" value={detailVoucher.description} />
              </div>
            )}
          </div>
          <div className="flex justify-end gap-3 mt-5">
            <Button onClick={() => setDetailVoucher(null)}>Zavřít</Button>
            {detailVoucher.status === 'active' && (
              <Button onClick={() => { setRedeemModal(detailVoucher); setDetailVoucher(null) }} style={{ background: '#1a8a18', color: '#fff' }}>Uplatnit</Button>
            )}
            <Button onClick={() => { setEditVoucher(detailVoucher); setShowModal(true); setDetailVoucher(null) }} style={{ background: '#2563eb', color: '#fff' }}>Upravit</Button>
          </div>
        </Modal>
      )}

      {/* Create/Edit — rendered always to prevent unmount on outside click */}
      <VoucherModal
        open={showModal}
        existing={editVoucher}
        onClose={() => { setShowModal(false); setEditVoucher(null) }}
        onSaved={() => { setShowModal(false); setEditVoucher(null); loadVouchers(); loadSummary() }}
      />

      {/* Redeem */}
      {redeemModal && (
        <RedeemModal
          voucher={redeemModal}
          onClose={() => setRedeemModal(null)}
          onRedeem={(data) => handleRedeem(redeemModal, data)}
        />
      )}

      {/* Cancel confirm */}
      {deleteConfirm && (
        <ConfirmDialog
          open
          title="Zrušit poukaz?"
          message={`Opravdu chcete zrušit poukaz "${deleteConfirm.code}" (${Number(deleteConfirm.amount).toLocaleString('cs-CZ')} ${deleteConfirm.currency})? Tuto akci nelze vrátit.`}
          danger
          onConfirm={() => handleCancel(deleteConfirm)}
          onCancel={() => setDeleteConfirm(null)}
        />
      )}
    </div>
  )
}

function generateCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
  let code = 'MG'
  for (let i = 0; i < 6; i++) code += chars[Math.floor(Math.random() * chars.length)]
  return code
}

function VoucherModal({ open, existing, onClose, onSaved }) {
  const isEdit = !!existing
  const [form, setForm] = useState(
    existing
      ? {
          code: existing.code || '',
          amount: existing.amount?.toString() || '',
          currency: existing.currency || 'CZK',
          category: existing.category || 'gift',
          buyer_name: existing.buyer_name || '',
          buyer_email: existing.buyer_email || '',
          valid_from: existing.valid_from || '',
          valid_until: existing.valid_until || '',
          description: existing.description || '',
        }
      : {
          code: generateCode(),
          amount: '',
          currency: 'CZK',
          category: 'gift',
          buyer_name: '',
          buyer_email: '',
          valid_from: new Date().toISOString().split('T')[0],
          valid_until: new Date(Date.now() + 365 * 86400000).toISOString().split('T')[0],
          description: '',
        }
  )
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      const payload = {
        code: form.code.trim().toUpperCase(),
        amount: Number(form.amount) || 0,
        currency: form.currency,
        category: form.category || null,
        buyer_name: form.buyer_name || null,
        buyer_email: form.buyer_email || null,
        valid_from: form.valid_from || null,
        valid_until: form.valid_until || null,
        description: form.description || null,
      }

      if (isEdit) {
        const { error } = await debugAction('updateVoucher', 'VoucherModal', () =>
          supabase.from('vouchers').update(payload).eq('id', existing.id),
          { voucherId: existing.id, payload }
        )
        if (error) throw error
        await logAudit('voucher_updated', { code: payload.code })
      } else {
        const { error } = await debugAction('createVoucher', 'VoucherModal', () =>
          supabase.from('vouchers').insert({ ...payload, status: 'active', created_by: user?.id }),
          { payload }
        )
        if (error) throw error
        await logAudit('voucher_created', { code: payload.code, amount: payload.amount })
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

  if (!open) return null

  return (
    <Modal open noBackdropClose title={isEdit ? `Upravit: ${existing?.code}` : 'Nový dárkový poukaz'} onClose={onClose}>
      <div className="grid grid-cols-2 gap-3">
        <div className="col-span-2">
          <Label>Kód poukazu</Label>
          <div className="flex gap-2">
            <input
              value={form.code}
              onChange={e => set('code', e.target.value.toUpperCase())}
              className="flex-1 rounded-btn text-sm outline-none font-mono"
              style={inputStyle}
              placeholder="MGXXXXXX"
              disabled={isEdit}
            />
            {!isEdit && (
              <button
                onClick={() => set('code', generateCode())}
                className="rounded-btn text-sm font-bold cursor-pointer"
                style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}
              >
                Generovat
              </button>
            )}
          </div>
          {isEdit && <span className="text-sm" style={{ color: '#1a2e22' }}>Kód nelze měnit po vytvoření</span>}
        </div>
        <div>
          <Label>Hodnota</Label>
          <input type="number" value={form.amount} onChange={e => set('amount', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} placeholder="2000" />
        </div>
        <div>
          <Label>Měna</Label>
          <select value={form.currency} onChange={e => set('currency', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            <option value="CZK">CZK</option>
            <option value="EUR">EUR</option>
          </select>
        </div>
        <div>
          <Label>Kategorie</Label>
          <select value={form.category} onChange={e => set('category', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            {CATEGORIES.map(c => <option key={c.value} value={c.value}>{c.label}</option>)}
          </select>
        </div>
        <div>
          <Label>Jméno kupujícího</Label>
          <input value={form.buyer_name} onChange={e => set('buyer_name', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} placeholder="Jan Novák" />
        </div>
        <div className="col-span-2">
          <Label>Email kupujícího</Label>
          <input type="email" value={form.buyer_email} onChange={e => set('buyer_email', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} placeholder="jan@email.cz" />
        </div>
        <div>
          <Label>Platnost od</Label>
          <input type="date" value={form.valid_from} onChange={e => set('valid_from', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div>
          <Label>Platnost do</Label>
          <input type="date" value={form.valid_until} onChange={e => set('valid_until', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div className="col-span-2">
          <Label>Popis / poznámka</Label>
          <textarea value={form.description} onChange={e => set('description', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, minHeight: 60, resize: 'vertical' }} placeholder="Dárkový poukaz k narozeninám…" />
        </div>
      </div>

      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.code || !form.amount}>
          {saving ? 'Ukládám…' : isEdit ? 'Uložit změny' : 'Vytvořit poukaz'}
        </Button>
      </div>
    </Modal>
  )
}

function RedeemModal({ voucher, onClose, onRedeem }) {
  const [form, setForm] = useState({ redeemed_for: '', booking_id: '' })
  const [saving, setSaving] = useState(false)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  return (
    <Modal open title={`Uplatnit poukaz: ${voucher.code}`} onClose={onClose}>
      <div className="mb-4 p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
        <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>
          Hodnota: {Number(voucher.amount).toLocaleString('cs-CZ')} {voucher.currency}
        </span>
      </div>
      <div className="grid gap-3">
        <div>
          <Label>Na co uplatněn</Label>
          <input value={form.redeemed_for} onChange={e => set('redeemed_for', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} placeholder="Pronájem Honda CB500F, 3 dny…" />
        </div>
        <div>
          <Label>ID rezervace (volitelné)</Label>
          <input value={form.booking_id} onChange={e => set('booking_id', e.target.value)} className="w-full rounded-btn text-sm outline-none font-mono" style={inputStyle} placeholder="uuid…" />
        </div>
      </div>
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={() => { setSaving(true); onRedeem(form) }} disabled={saving}>
          {saving ? 'Uplatňuji…' : 'Potvrdit uplatnění'}
        </Button>
      </div>
    </Modal>
  )
}

function SummaryCard({ label, value, color }) {
  return (
    <Card>
      <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>{label}</div>
      <div className="text-xl font-extrabold" style={{ color }}>{value}</div>
    </Card>
  )
}

function DetailRow({ label, value, mono }) {
  return (
    <div>
      <div className="text-sm font-extrabold uppercase tracking-wide mb-0.5" style={{ color: '#1a2e22' }}>{label}</div>
      <div className={`text-sm font-semibold ${mono ? 'font-mono' : ''}`} style={{ color: '#0f1a14' }}>{value ?? '—'}</div>
    </div>
  )
}

function ActionBtn({ children, color, onClick }) {
  return (
    <button
      onClick={onClick}
      className="text-sm font-bold cursor-pointer"
      style={{ color, background: 'none', border: 'none', padding: '4px 6px' }}
    >
      {children}
    </button>
  )
}

function CheckboxFilterGroup({ label, values, onChange, options }) {
  const toggle = val => {
    if (values.includes(val)) onChange(values.filter(v => v !== val))
    else onChange([...values, val])
  }
  return (
    <div className="flex items-center gap-1 flex-wrap rounded-btn"
      style={{ padding: '4px 10px', background: values.length > 0 ? '#e8fde8' : '#f1faf7', border: '1px solid #d4e8e0' }}>
      <span className="text-sm font-extrabold uppercase tracking-wide mr-1" style={{ color: '#1a2e22' }}>{label}:</span>
      {options.map(o => (
        <label key={o.value} className="flex items-center gap-1 cursor-pointer"
          style={{ padding: '3px 6px', borderRadius: 6, background: values.includes(o.value) ? '#74FB71' : 'transparent' }}>
          <input type="checkbox" checked={values.includes(o.value)} onChange={() => toggle(o.value)}
            className="accent-[#1a8a18]" style={{ width: 14, height: 14 }} />
          <span className="text-sm font-bold" style={{ color: '#1a2e22', whiteSpace: 'nowrap' }}>{o.label}</span>
        </label>
      ))}
    </div>
  )
}

function FilterSelect({ value, onChange, options }) {
  return (
    <select value={value} onChange={e => onChange(e.target.value)}
      className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none"
      style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
      {options.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
    </select>
  )
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}
