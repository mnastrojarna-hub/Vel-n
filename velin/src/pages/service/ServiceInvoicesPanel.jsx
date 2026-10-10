import { useEffect, useRef, useState } from 'react'
import { supabase } from '../../lib/supabase'
import Button from '../../components/ui/Button'
import { useAdminIdentity } from '../../hooks/useAdminIdentity'
import { fmtDate, fmtMoney } from '../../lib/serviceBook'
import { extractInvoiceData, uploadInvoiceFile, registerServiceInvoice, fetchServiceInvoices, signedInvoiceUrl, deleteServiceInvoice } from '../../lib/serviceInvoices'

const inp = { padding: '6px 10px', background: '#fff', border: '1px solid #d4e8e0', color: '#0f1a14' }
const INP = 'rounded-btn text-sm outline-none max-lg:block max-lg:w-full'
// Popisek nad polem jen pod lg (placeholder po vyplnění zmizí); na desktopu label = display:contents → mřížka beze změny.
const F = ({ label, className = '', children }) => (
  <label className={`lg:contents ${className}`}><span className="lg:hidden block text-xs font-bold mb-0.5" style={{ color: '#1a2e22' }}>{label}</span>{children}</label>
)

/**
 * „+ Přidat fakturu“ u servisního záznamu: nahrání PDF / fotky dokladu, u fotky OCR (receive-invoice extract),
 * kontrola údajů → zaevidování do Financí (invoices type=received + financial_events) a vazba na servis.
 * Fakturační údaje přihlášeného účtu (service_provider_profiles) předvyplní dodavatele.
 */
export default function ServiceInvoicesPanel({ log, moto, onChanged, compact = false }) {
  const me = useAdminIdentity()
  const [rows, setRows] = useState([])
  const [file, setFile] = useState(null)
  const [meta, setMeta] = useState(null) // null = formulář zavřený
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState(null)
  const [profile, setProfile] = useState(null)
  const inputRef = useRef(null)

  useEffect(() => { load() }, [log?.id])
  useEffect(() => { if (me?.id) supabase.from('service_provider_profiles').select('*').eq('admin_id', me.id).maybeSingle().then(({ data }) => setProfile(data || null)) }, [me?.id])

  async function load() { if (log?.id) setRows(await fetchServiceInvoices([log.id])) }

  async function pick(f) {
    if (!f) return
    setErr(null); setFile(f); setBusy(true)
    const ocr = await extractInvoiceData(f)
    setBusy(false)
    setMeta({
      supplier_name: ocr?.supplier || profile?.company_name || me?.name || '', supplier_ico: ocr?.supplier_ico || profile?.ico || '',
      invoice_number: ocr?.invoice_number || '', amount: ocr?.amount || '', issue_date: ocr?.date || '', due_date: ocr?.due_date || '', note: '', ocr: !!ocr,
    })
  }

  async function save() {
    if (!file || !meta) return
    if (!meta.amount || Number(meta.amount) <= 0) { setErr('Vyplňte částku dokladu.'); return }
    setBusy(true); setErr(null)
    try {
      const path = await uploadInvoiceFile(log.id, file)
      await registerServiceInvoice({ log, moto, file, storagePath: path, meta, uploadedBy: me })
      setFile(null); setMeta(null); if (inputRef.current) inputRef.current.value = ''
      await load(); onChanged?.()
    } catch (e) { setErr(e.message) } finally { setBusy(false) }
  }

  async function open(row) { const u = await signedInvoiceUrl(row); if (u) window.open(u, '_blank', 'noopener') }
  async function remove(row) {
    if (!window.confirm(`Smazat doklad ${row.invoice_number || row.file_name || ''} včetně záznamu ve Financích?`)) return
    setBusy(true); try { await deleteServiceInvoice(row); await load(); onChanged?.() } catch (e) { setErr(e.message) } finally { setBusy(false) }
  }

  const total = rows.reduce((s, r) => s + (Number(r.amount) || 0), 0)
  const set = (k, v) => setMeta(m => ({ ...m, [k]: v }))

  return (
    <div className="rounded-lg" style={{ background: '#fff', border: '1px solid #d4e8e0', padding: compact ? 8 : 12 }}>
      <div className="flex items-center gap-2 flex-wrap mb-1">
        <span className="text-xs font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Faktury / doklady k servisu</span>
        {rows.length > 0 && <span className="text-xs font-bold" style={{ color: '#1a8a18' }}>{rows.length}× · {fmtMoney(total)}</span>}
        <input ref={inputRef} type="file" accept="application/pdf,image/*" style={{ display: 'none' }} onChange={e => pick(e.target.files?.[0])} />
        <button type="button" onClick={() => inputRef.current?.click()} disabled={busy || !log?.id} className="ml-auto rounded-btn text-xs font-extrabold uppercase cursor-pointer disabled:opacity-50 px-3 py-[5px] max-lg:py-2"
          style={{ background: '#74FB71', color: '#1a2e22', border: 'none' }}>+ Přidat fakturu</button>
      </div>
      {!log?.id && <div className="text-xs" style={{ color: '#9ca3af' }}>Doklady lze nahrát po uložení záznamu.</div>}
      {rows.map(r => (
        <div key={r.id} className="flex items-center gap-2 flex-wrap text-sm py-1" style={{ borderTop: '1px solid #eef5f1' }}>
          <button type="button" onClick={() => open(r)} className="font-bold cursor-pointer p-0 max-lg:py-1.5" style={{ background: 'none', border: 'none', color: '#2563eb' }} title="Otevřít doklad">📎 {r.invoice_number || r.file_name || 'doklad'}</button>
          <span style={{ color: '#1a2e22' }}>{r.supplier_name || '—'}</span>
          <span className="font-bold" style={{ color: '#0f1a14' }}>{fmtMoney(r.amount)}</span>
          <span className="text-xs" style={{ color: '#6b7280' }}>{fmtDate(r.issue_date)}{r.uploaded_by_name ? ` · nahrál ${r.uploaded_by_name}` : ''}</span>
          <button type="button" onClick={() => remove(r)} disabled={busy} className="ml-auto text-xs cursor-pointer max-lg:text-base max-lg:px-2 max-lg:py-1" style={{ background: 'none', border: 'none', color: '#dc2626' }} title="Smazat doklad">✕</button>
        </div>
      ))}
      {busy && !meta && <div className="text-xs mt-1" style={{ color: '#6b7280' }}>Čtu doklad…</div>}
      {meta && (
        <div className="mt-2 p-2 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #74FB71' }}>
          <div className="text-xs font-bold mb-2" style={{ color: '#1a2e22' }}>📄 {file?.name} {meta.ocr ? '· údaje vyčteny z fotky — zkontrolujte' : '· doplňte údaje dokladu'}</div>
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-2 max-sm:grid-cols-1 max-lg:items-end">
            <F label="Dodavatel (servis)"><input value={meta.supplier_name} onChange={e => set('supplier_name', e.target.value)} placeholder="Dodavatel (servis)" className={INP} style={inp} /></F>
            <F label="IČO"><input value={meta.supplier_ico} onChange={e => set('supplier_ico', e.target.value)} placeholder="IČO" className={INP} style={inp} /></F>
            <F label="Číslo dokladu"><input value={meta.invoice_number} onChange={e => set('invoice_number', e.target.value)} placeholder="Číslo dokladu" className={INP} style={inp} /></F>
            <F label="Částka Kč *"><input type="number" min="0" value={meta.amount} onChange={e => set('amount', e.target.value)} placeholder="Částka Kč *" className={INP} style={inp} /></F>
            <F label="Datum vystavení"><input type="date" value={meta.issue_date} onChange={e => set('issue_date', e.target.value)} className={INP} style={inp} title="Datum vystavení" /></F>
            <F label="Splatnost"><input type="date" value={meta.due_date} onChange={e => set('due_date', e.target.value)} className={INP} style={inp} title="Splatnost" /></F>
          </div>
          <F label="Poznámka (volitelné)" className="max-lg:block max-lg:mt-2"><input value={meta.note} onChange={e => set('note', e.target.value)} placeholder="Poznámka (volitelné)" className="w-full rounded-btn text-sm outline-none mt-2 max-lg:block max-lg:mt-0" style={inp} /></F>
          {err && <div className="text-xs mt-1" style={{ color: '#dc2626' }}>{err}</div>}
          <div className="flex gap-2 justify-end mt-2">
            <Button small onClick={() => { setMeta(null); setFile(null); setErr(null); if (inputRef.current) inputRef.current.value = '' }}>Zrušit</Button>
            <Button small green onClick={save} disabled={busy}>{busy ? 'Ukládám…' : 'Zaevidovat do Financí'}</Button>
          </div>
        </div>
      )}
      {err && !meta && <div className="text-xs mt-1" style={{ color: '#dc2626' }}>{err}</div>}
    </div>
  )
}
