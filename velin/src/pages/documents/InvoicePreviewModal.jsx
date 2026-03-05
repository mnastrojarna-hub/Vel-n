import { useState, useEffect } from 'react'
import { generateInvoiceHtml } from '../../lib/invoiceTemplate'
import { loadInvoiceData, printInvoiceHtml, storeInvoicePdf } from '../../lib/invoiceUtils'
import { supabase } from '../../lib/supabase'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'

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

export default function InvoicePreviewModal({ invoice, onClose, onUpdated }) {
  const [fullData, setFullData] = useState(null)
  const [html, setHtml] = useState('')
  const [loading, setLoading] = useState(true)
  const [sending, setSending] = useState(false)
  const [storing, setStoring] = useState(false)
  const [msg, setMsg] = useState(null)
  const [editItems, setEditItems] = useState(false)
  const [items, setItems] = useState(invoice.items || [])
  const [notes, setNotes] = useState(invoice.notes || '')

  useEffect(() => {
    loadFull()
  }, [invoice.id])

  async function loadFull() {
    setLoading(true)
    try {
      const data = await loadInvoiceData(invoice.id)
      setFullData(data)
      setItems(data.items || [])
      setNotes(data.notes || '')
      const invoiceHtml = generateInvoiceHtml({
        type: data.type,
        number: data.number,
        issue_date: data.issue_date,
        due_date: data.due_date,
        duzp: data.issue_date,
        items: data.items || [],
        subtotal: data.subtotal,
        tax_amount: data.tax_amount,
        total: data.total,
        notes: data.notes,
        variable_symbol: data.number?.replace(/[^0-9]/g, ''),
        customer: {
          name: data.profiles?.full_name,
          email: data.profiles?.email,
          phone: data.profiles?.phone,
          address: data.profiles?.address,
          ico: data.profiles?.ico,
          dic: data.profiles?.dic,
        },
      })
      setHtml(invoiceHtml)
    } catch (e) {
      setMsg({ type: 'error', text: e.message })
    }
    setLoading(false)
  }

  function handlePrint() {
    printInvoiceHtml(html)
  }

  async function handleStore() {
    setStoring(true); setMsg(null)
    try {
      await storeInvoicePdf(invoice.id, html)
      setMsg({ type: 'ok', text: 'Faktura uložena do úložiště.' })
      onUpdated?.()
    } catch (e) {
      setMsg({ type: 'error', text: `Uložení selhalo: ${e.message}` })
    }
    setStoring(false)
  }

  async function handleSendEmail() {
    setSending(true); setMsg(null)
    try {
      // Store first
      if (!invoice.pdf_path) {
        await storeInvoicePdf(invoice.id, html)
      }
      // Try Edge Function; fallback to direct email
      const { error } = await supabase.functions.invoke('send-invoice-email', {
        body: {
          invoice_id: invoice.id,
          html_content: html,
          customer_email: fullData?.profiles?.email,
          customer_name: fullData?.profiles?.full_name,
          invoice_number: fullData?.number,
        },
      })
      if (error) throw error
      setMsg({ type: 'ok', text: 'Faktura odeslána zákazníkovi.' })
    } catch (e) {
      // Fallback: log the sent attempt
      await supabase.from('sent_emails').insert({
        template_slug: 'invoice',
        recipient_email: fullData?.profiles?.email,
        recipient_id: fullData?.customer_id,
        booking_id: fullData?.booking_id,
        subject: `Faktura ${fullData?.number}`,
        body_html: html,
        status: 'queued',
      })
      setMsg({ type: 'warn', text: 'E-mail zařazen do fronty. Edge Function pro odesílání ještě není nasazena.' })
    }
    setSending(false)
  }

  async function handleSaveItems() {
    try {
      const subtotal = items.reduce((s, it) => s + (it.unit_price || 0) * (it.qty || 1), 0)
      const taxAmount = Math.round(subtotal * 0.21 * 100) / 100
      const { error } = await supabase.from('invoices').update({
        items, notes, subtotal, tax_amount: taxAmount, total: subtotal + taxAmount,
      }).eq('id', invoice.id)
      if (error) throw error
      setEditItems(false)
      setMsg({ type: 'ok', text: 'Faktura aktualizována.' })
      onUpdated?.()
      loadFull()
    } catch (e) { setMsg({ type: 'error', text: e.message }) }
  }

  async function handleMarkPaid() {
    try {
      const { error } = await supabase.from('invoices')
        .update({ status: 'paid', paid_date: new Date().toISOString().slice(0, 10) })
        .eq('id', invoice.id)
      if (error) throw error
      setMsg({ type: 'ok', text: 'Faktura označena jako zaplacená.' })
      onUpdated?.()
    } catch (e) { setMsg({ type: 'error', text: e.message }) }
  }

  const tp = TYPE_MAP[invoice.type] || TYPE_MAP.proforma
  const st = STATUS_MAP[invoice.status] || STATUS_MAP.draft

  return (
    <Modal open title={`Faktura ${invoice.number || '(nová)'}`} onClose={onClose} wide noBackdropClose>
      <div className="flex items-center gap-3 mb-4">
        <Badge label={tp.label} color={tp.color} bg={tp.bg} />
        <Badge label={st.label} color={st.color} bg={st.bg} />
        <span className="text-sm font-bold ml-auto">{(invoice.total || 0).toLocaleString('cs-CZ')} Kč</span>
      </div>

      {msg && (
        <div className="mb-3 p-2 rounded-lg text-xs font-bold" style={{
          background: msg.type === 'error' ? '#fee2e2' : msg.type === 'warn' ? '#fef3c7' : '#dcfce7',
          color: msg.type === 'error' ? '#dc2626' : msg.type === 'warn' ? '#92400e' : '#1a8a18',
        }}>{msg.text}</div>
      )}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : editItems ? (
        <div>
          <p className="text-[10px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#8aab99' }}>Upravit položky</p>
          {items.map((it, i) => (
            <div key={i} className="flex gap-2 mb-2">
              <input value={it.description} onChange={e => { const n = [...items]; n[i] = { ...n[i], description: e.target.value }; setItems(n) }}
                className="flex-1 text-sm rounded-btn outline-none" style={{ padding: '6px 8px', background: '#f1faf7', border: '1px solid #d4e8e0' }}
                placeholder="Popis" />
              <input type="number" value={it.qty} onChange={e => { const n = [...items]; n[i] = { ...n[i], qty: Number(e.target.value) }; setItems(n) }}
                className="w-16 text-sm rounded-btn outline-none text-center" style={{ padding: '6px 4px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
              <input type="number" value={it.unit_price} onChange={e => { const n = [...items]; n[i] = { ...n[i], unit_price: Number(e.target.value) }; setItems(n) }}
                className="w-24 text-sm rounded-btn outline-none text-right" style={{ padding: '6px 8px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
            </div>
          ))}
          <textarea value={notes} onChange={e => setNotes(e.target.value)} placeholder="Poznámka…"
            className="w-full text-sm rounded-btn outline-none mt-2" style={{ padding: '6px 8px', background: '#f1faf7', border: '1px solid #d4e8e0', minHeight: 50 }} />
          <div className="flex justify-end gap-2 mt-3">
            <Button onClick={() => setEditItems(false)}>Zrušit</Button>
            <Button green onClick={handleSaveItems}>Uložit změny</Button>
          </div>
        </div>
      ) : (
        <>
          {/* Invoice HTML preview */}
          <div className="rounded-card" style={{ border: '1px solid #d4e8e0', maxHeight: 420, overflow: 'auto', background: '#fff' }}
            dangerouslySetInnerHTML={{ __html: html }} />

          {/* Actions */}
          <div className="flex flex-wrap justify-between gap-3 mt-4">
            <div className="flex gap-2">
              <Button onClick={handlePrint}>Tisk / PDF</Button>
              <Button onClick={handleStore} disabled={storing}>{storing ? 'Ukládám…' : 'Uložit do dokumentů'}</Button>
              <Button onClick={handleSendEmail} disabled={sending}>
                {sending ? 'Odesílám…' : 'Odeslat zákazníkovi'}
              </Button>
            </div>
            <div className="flex gap-2">
              {invoice.status === 'issued' && (
                <Button green onClick={handleMarkPaid}>Označit jako zaplacenou</Button>
              )}
              <Button onClick={() => setEditItems(true)}>Upravit</Button>
              <Button onClick={onClose}>Zavřít</Button>
            </div>
          </div>
        </>
      )}
    </Modal>
  )
}
