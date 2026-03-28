import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import { useDebugMode } from '../hooks/useDebugMode'
import { Table, TRow, TH, TD } from '../components/ui/Table'
import Button from '../components/ui/Button'
import SearchInput from '../components/ui/SearchInput'
import Pagination from '../components/ui/Pagination'
import Card from '../components/ui/Card'
import ConfirmDialog from '../components/ui/ConfirmDialog'
import { VoucherModal, RedeemModal } from './GiftVouchersModals'

const PER_PAGE = 25
const CATEGORIES = [
  { value: 'rental', label: 'Pronájem' },
  { value: 'gear', label: 'Vybavení' },
  { value: 'experience', label: 'Zážitek' },
  { value: 'gift', label: 'Dárek' },
]

export default function GiftVouchers() {
  const debugMode = useDebugMode()
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
      {debugMode && (
      <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
        <strong>DIAGNOSTIKA GiftVouchers</strong><br/>
        <div>vouchers: {vouchers.length} zobrazeno / {total} celkem (strana {page}/{totalPages || 1})</div>
        <div>summary: total={summary.total}, active={summary.active}, redeemed={summary.redeemed}, expired={summary.expired}</div>
        <div>totalValue (active): {summary.totalValue?.toLocaleString('cs-CZ')} Kč</div>
        <div>filtry: status={filters.statuses?.length > 0 ? filters.statuses.join(',') : 'vše'}, search="{filters.search}"</div>
        {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
      </div>
      )}

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

// VoucherModal and RedeemModal moved to ./GiftVouchersModals.jsx

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
