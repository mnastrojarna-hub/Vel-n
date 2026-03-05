import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'

const TYPE_MAP = {
  proforma: { label: 'Zálohová', color: '#2563eb', bg: '#dbeafe' },
  final: { label: 'Konečná', color: '#1a8a18', bg: '#dcfce7' },
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
        supabase.from('invoices').select('*').eq('booking_id', bookingId).order('created_at', { ascending: false }),
        supabase.from('accounting_entries').select('*').eq('booking_id', bookingId).order('created_at', { ascending: false }),
      ])
      setInvoices(invRes.data || [])
      setEntries(entRes.data || [])
    } catch (e) { setError(e.message) }
    setLoading(false)
  }

  async function handleGenerateInvoice(type) {
    setGenerating(type); setError(null)
    try {
      const { error: err } = await supabase.functions.invoke('generate-invoice', {
        body: { type, booking_id: bookingId },
      })
      if (err) throw err
      await loadAll()
    } catch (e) {
      setError(`Vystavení faktury selhalo: ${e.message || 'Edge Function nemusí být nasazena.'}`)
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
            const tp = TYPE_MAP[inv.type] || TYPE_MAP.proforma
            const st = STATUS_MAP[inv.status] || STATUS_MAP.draft
            return (
              <div key={inv.id} className="flex items-center gap-4 p-3 rounded-lg mb-2" style={{ background: '#f1faf7' }}>
                <span className="text-sm font-bold font-mono">{inv.invoice_number || '—'}</span>
                <Badge label={tp.label} color={tp.color} bg={tp.bg} />
                <span className="text-sm font-bold" style={{ color: inv.status === 'paid' ? '#1a8a18' : '#0f1a14' }}>
                  {(inv.total || 0).toLocaleString('cs-CZ')} Kč
                </span>
                <Badge label={st.label} color={st.color} bg={st.bg} />
                <span className="text-xs" style={{ color: '#8aab99' }}>{inv.created_at?.slice(0, 10)}</span>
                {inv.content_html && (
                  <button onClick={() => setViewInvoice(inv)} className="text-[10px] font-bold cursor-pointer ml-auto"
                    style={{ color: '#2563eb', background: 'none', border: 'none' }}>Zobrazit</button>
                )}
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
                <span className="text-xs ml-3" style={{ color: '#8aab99' }}>{e.created_at?.slice(0, 10)}</span>
              </div>
              <span className="text-sm font-bold" style={{ color: e.amount >= 0 ? '#1a8a18' : '#dc2626' }}>
                {e.amount?.toLocaleString('cs-CZ')} Kč
              </span>
            </div>
          ))
        )}
      </Card>

      {viewInvoice && (
        <Modal open title={`Faktura ${viewInvoice.invoice_number}`} onClose={() => setViewInvoice(null)} wide>
          <div className="rounded-card" style={{ padding: 16, background: '#fff', border: '1px solid #d4e8e0', maxHeight: 500, overflow: 'auto' }}
            dangerouslySetInnerHTML={{ __html: viewInvoice.content_html }} />
          <div className="flex justify-end mt-4">
            <Button onClick={() => setViewInvoice(null)}>Zavřít</Button>
          </div>
        </Modal>
      )}
    </div>
  )
}
