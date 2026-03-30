import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { generateAdvanceInvoice, generatePaymentReceipt, generateFinalInvoice, loadInvoiceData, printInvoiceHtml } from '../../lib/invoiceUtils'
import { generateInvoiceHtml } from '../../lib/invoiceTemplate'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'

const TYPE_MAP = {
  proforma: { label: 'Zálohová (ZF)', color: '#2563eb', bg: '#dbeafe' },
  advance: { label: 'Zálohová (ZF)', color: '#2563eb', bg: '#dbeafe' },
  issued: { label: 'Vystavená', color: '#1a2e22', bg: '#f3f4f6' },
  received: { label: 'Přijatá', color: '#1a2e22', bg: '#f3f4f6' },
  final: { label: 'Konečná (KF)', color: '#1a8a18', bg: '#dcfce7' },
  payment_receipt: { label: 'Doklad k platbě (DP)', color: '#0891b2', bg: '#cffafe' },
  shop_proforma: { label: 'Shop zálohová', color: '#8b5cf6', bg: '#ede9fe' },
  shop_final: { label: 'Shop konečná', color: '#059669', bg: '#d1fae5' },
  credit_note: { label: 'Dobropis (DB)', color: '#dc2626', bg: '#fee2e2' },
}

const STATUS_MAP = {
  draft: { label: 'Koncept', color: '#1a2e22', bg: '#f3f4f6' },
  issued: { label: 'Vystavena', color: '#b45309', bg: '#fef3c7' },
  paid: { label: 'Zaplacena', color: '#1a8a18', bg: '#dcfce7' },
  cancelled: { label: 'Stornována', color: '#dc2626', bg: '#fee2e2' },
  refunded: { label: 'Refundována', color: '#1a2e22', bg: '#f3f4f6' },
}

export default function BookingPaymentsTab({ bookingId }) {
  const [invoices, setInvoices] = useState([])
  const [entries, setEntries] = useState([])
  const [loading, setLoading] = useState(true)
  const [generating, setGenerating] = useState(null)
  const [error, setError] = useState(null)
  const [viewInvoice, setViewInvoice] = useState(null)

  useEffect(() => { loadAll() }, [bookingId])

  async function loadAll() {
    setLoading(true)
    try {
      debugLog('BookingPaymentsTab', 'loadAll', { bookingId })
      const invRes = await debugAction('invoices.byBooking', 'BookingPaymentsTab', () =>
        supabase.from('invoices').select('*').eq('booking_id', bookingId).order('issue_date', { ascending: false, nullsFirst: false }))
      setInvoices(invRes.data || [])
      // accounting_entries may not have booking_id column — load all and filter client-side by reference
      try {
        const entRes = await debugAction('accounting_entries.byBooking', 'BookingPaymentsTab', () =>
          supabase.from('accounting_entries').select('*').order('created_at', { ascending: false }))
        const all = entRes.data || []
        setEntries(all.filter(e => e.booking_id === bookingId || e.reference_id === bookingId))
      } catch { setEntries([]) }
    } catch (e) { debugError('BookingPaymentsTab', 'loadAll', e); setError(e.message) }
    setLoading(false)
  }

  async function handleGenerateInvoice(type) {
    setGenerating(type); setError(null)
    try {
      debugLog('BookingPaymentsTab', 'handleGenerateInvoice', { type, bookingId })
      let result
      if (type === 'proforma' || type === 'advance') {
        result = await generateAdvanceInvoice(bookingId, 'booking')
      } else if (type === 'payment_receipt') {
        result = await generatePaymentReceipt(bookingId, 'booking')
      } else if (type === 'final') {
        result = await generateFinalInvoice(bookingId)
      }
      if (result) {
        console.log('[Invoice] Created:', result.number, result.id)
      }
      await loadAll()
    } catch (e) {
      debugError('BookingPaymentsTab', 'handleGenerateInvoice', e)
      setError(`Vystavení faktury selhalo: ${e.message}`)
    }
    setGenerating(null)
  }

  if (loading) return <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>

  return (
    <div className="space-y-5">
      {error && <div className="p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {/* Generate buttons */}
      <div className="flex gap-3">
        <Button green onClick={() => handleGenerateInvoice('proforma')} disabled={generating === 'proforma'}>
          {generating === 'proforma' ? 'Vystavuji…' : 'Vystavit zálohovou fakturu'}
        </Button>
        <Button green onClick={() => handleGenerateInvoice('payment_receipt')} disabled={generating === 'payment_receipt'}>
          {generating === 'payment_receipt' ? 'Vystavuji…' : 'Vystavit doklad k platbě'}
        </Button>
        <Button green onClick={() => handleGenerateInvoice('final')} disabled={generating === 'final'}>
          {generating === 'final' ? 'Vystavuji…' : 'Vystavit konečnou fakturu'}
        </Button>
      </div>

      {/* Invoices */}
      <Card>
        <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Faktury</h3>
        {invoices.length === 0 ? (
          <p style={{ color: '#1a2e22', fontSize: 13 }}>Žádné faktury</p>
        ) : (
          invoices.map(inv => {
            const tp = TYPE_MAP[inv.type] || { label: inv.type || 'Neznámý', color: '#1a2e22', bg: '#f3f4f6' }
            const st = STATUS_MAP[inv.status] || STATUS_MAP.draft
            const isCreditNote = inv.type === 'credit_note'
            return (
              <div key={inv.id} className="flex items-center gap-4 p-3 rounded-lg mb-2" style={{ background: isCreditNote ? '#fef2f2' : '#f1faf7', border: isCreditNote ? '1px solid #fca5a5' : 'none' }}>
                <span className="text-sm font-bold font-mono" style={isCreditNote ? { color: '#dc2626' } : {}}>{inv.number || '—'}</span>
                <Badge label={tp.label} color={tp.color} bg={tp.bg} />
                <span className="text-sm font-bold" style={{ color: isCreditNote ? '#dc2626' : inv.status === 'paid' ? '#1a8a18' : '#0f1a14' }}>
                  {isCreditNote ? '−' : ''}{Math.abs(inv.total || 0).toLocaleString('cs-CZ')} Kč
                </span>
                <Badge label={st.label} color={st.color} bg={st.bg} />
                <span className="text-sm" style={{ color: '#1a2e22' }}>{inv.issue_date || '—'}</span>
                <button onClick={() => setViewInvoice(inv)} className="text-sm font-bold cursor-pointer ml-auto"
                  style={{ color: '#2563eb', background: 'none', border: 'none' }}>Zobrazit</button>
              </div>
            )
          })
        )}
      </Card>

      {/* Accounting entries */}
      <Card>
        <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Platby</h3>
        {entries.length === 0 ? (
          <p style={{ color: '#1a2e22', fontSize: 13 }}>Žádné platby</p>
        ) : (
          entries.map(e => (
            <div key={e.id} className="flex items-center gap-4 p-3 rounded-lg mb-2" style={{ background: '#f1faf7' }}>
              <div className="flex-1">
                <span className="text-sm font-bold">{e.description || 'Platba'}</span>
                <span className="text-sm ml-3" style={{ color: '#1a2e22' }}>{e.date || e.created_at?.slice(0, 10) || '—'}</span>
              </div>
              <span className="text-sm font-bold" style={{ color: e.amount >= 0 ? '#1a8a18' : '#dc2626' }}>
                {e.amount?.toLocaleString('cs-CZ')} Kč
              </span>
            </div>
          ))
        )}
      </Card>

      {viewInvoice && (
        <InvoiceViewModal invoice={viewInvoice} onClose={() => setViewInvoice(null)} />
      )}
    </div>
  )
}

function InvoiceViewModal({ invoice, onClose }) {
  const [html, setHtml] = useState(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    loadHtml()
  }, [invoice.id])

  async function loadHtml() {
    setLoading(true)
    try {
      // Always generate from template (storage bucket may not exist)
      const fullInv = await loadInvoiceData(invoice.id)
      const generated = generateInvoiceHtml({
        ...fullInv,
        customer: fullInv.profiles || {},
        items: fullInv.items || [],
      })
      setHtml(generated)
    } catch {
      setHtml(null)
    }
    setLoading(false)
  }

  return (
    <Modal open title={`Faktura ${invoice.number}`} onClose={onClose} wide>
      {loading ? (
        <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>
      ) : html ? (
        <div className="border rounded-lg overflow-auto" style={{ maxHeight: 550, background: '#fff' }}>
          <iframe srcDoc={html} style={{ width: '100%', height: 500, border: 'none' }} title="Náhled faktury" />
        </div>
      ) : (
        <div className="py-8 text-center" style={{ color: '#1a2e22', fontSize: 13 }}>
          Náhled faktury není dostupný. Částka: {(invoice.total || 0).toLocaleString('cs-CZ')} Kč
        </div>
      )}
      <div className="flex justify-end gap-3 mt-4">
        {html && (
          <Button onClick={() => printInvoiceHtml(html)}>Tisk / PDF</Button>
        )}
        <Button onClick={onClose}>Zavřít</Button>
      </div>
    </Modal>
  )
}
