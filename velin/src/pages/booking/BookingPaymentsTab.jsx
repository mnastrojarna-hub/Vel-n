import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { generateAdvanceInvoice, generatePaymentReceipt, generateFinalInvoice } from '../../lib/invoiceUtils'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'

const TYPE_MAP = {
  proforma: { label: 'Zálohová (ZF)', color: '#2563eb', bg: '#dbeafe' },
  advance: { label: 'Zálohová (ZF)', color: '#2563eb', bg: '#dbeafe' },
  issued: { label: 'Vystavená', color: '#6b7280', bg: '#f3f4f6' },
  received: { label: 'Přijatá', color: '#6b7280', bg: '#f3f4f6' },
  final: { label: 'Konečná (KF)', color: '#1a8a18', bg: '#dcfce7' },
  payment_receipt: { label: 'Doklad k platbě (DP)', color: '#0891b2', bg: '#cffafe' },
  shop_proforma: { label: 'Shop zálohová', color: '#8b5cf6', bg: '#ede9fe' },
  shop_final: { label: 'Shop konečná', color: '#059669', bg: '#d1fae5' },
}

const STATUS_MAP = {
  draft: { label: 'Koncept', color: '#6b7280', bg: '#f3f4f6' },
  issued: { label: 'Vystavena', color: '#b45309', bg: '#fef3c7' },
  paid: { label: 'Zaplacena', color: '#1a8a18', bg: '#dcfce7' },
  cancelled: { label: 'Stornována', color: '#dc2626', bg: '#fee2e2' },
  refunded: { label: 'Refundována', color: '#6b7280', bg: '#f3f4f6' },
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
      const [invRes, entRes] = await Promise.all([
        supabase.from('invoices').select('*').eq('booking_id', bookingId).order('issue_date', { ascending: false, nullsFirst: false }),
        supabase.from('accounting_entries').select('*').eq('booking_id', bookingId).order('date', { ascending: false }),
      ])
      setInvoices(invRes.data || [])
      setEntries(entRes.data || [])
    } catch (e) { setError(e.message) }
    setLoading(false)
  }

  async function handleGenerateInvoice(type) {
    setGenerating(type); setError(null)
    try {
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
      console.error('[Invoice] Generation failed:', e)
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
        <h3 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Faktury</h3>
        {invoices.length === 0 ? (
          <p style={{ color: '#8aab99', fontSize: 13 }}>Žádné faktury</p>
        ) : (
          invoices.map(inv => {
            const tp = TYPE_MAP[inv.type] || { label: inv.type || 'Neznámý', color: '#6b7280', bg: '#f3f4f6' }
            const st = STATUS_MAP[inv.status] || STATUS_MAP.draft
            return (
              <div key={inv.id} className="flex items-center gap-4 p-3 rounded-lg mb-2" style={{ background: '#f1faf7' }}>
                <span className="text-sm font-bold font-mono">{inv.number || '—'}</span>
                <Badge label={tp.label} color={tp.color} bg={tp.bg} />
                <span className="text-sm font-bold" style={{ color: inv.status === 'paid' ? '#1a8a18' : '#0f1a14' }}>
                  {(inv.total || 0).toLocaleString('cs-CZ')} Kč
                </span>
                <Badge label={st.label} color={st.color} bg={st.bg} />
                <span className="text-xs" style={{ color: '#8aab99' }}>{inv.issue_date || '—'}</span>
                <button onClick={() => setViewInvoice(inv)} className="text-[10px] font-bold cursor-pointer ml-auto"
                  style={{ color: '#2563eb', background: 'none', border: 'none' }}>Zobrazit</button>
              </div>
            )
          })
        )}
      </Card>

      {/* Accounting entries */}
      <Card>
        <h3 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Platby</h3>
        {entries.length === 0 ? (
          <p style={{ color: '#8aab99', fontSize: 13 }}>Žádné platby</p>
        ) : (
          entries.map(e => (
            <div key={e.id} className="flex items-center gap-4 p-3 rounded-lg mb-2" style={{ background: '#f1faf7' }}>
              <div className="flex-1">
                <span className="text-sm font-bold">{e.description || 'Platba'}</span>
                <span className="text-xs ml-3" style={{ color: '#8aab99' }}>{e.date || e.created_at?.slice(0, 10) || '—'}</span>
              </div>
              <span className="text-sm font-bold" style={{ color: e.amount >= 0 ? '#1a8a18' : '#dc2626' }}>
                {e.amount?.toLocaleString('cs-CZ')} Kč
              </span>
            </div>
          ))
        )}
      </Card>

      {viewInvoice && (
        <Modal open title={`Faktura ${viewInvoice.number}`} onClose={() => setViewInvoice(null)} wide>
          <div className="py-8 text-center" style={{ color: '#8aab99', fontSize: 13 }}>
            Detail faktury {viewInvoice.number}. Částka: {(viewInvoice.total || 0).toLocaleString('cs-CZ')} Kč
          </div>
          <div className="flex justify-end mt-4">
            <Button onClick={() => setViewInvoice(null)}>Zavřít</Button>
          </div>
        </Modal>
      )}
    </div>
  )
}
