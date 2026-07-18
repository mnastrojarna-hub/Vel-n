import { supabase } from '../../lib/supabase'

// Odeslání elektronického protokolu zákazníkovi e-mailem — šablona z Velína
// (handover_protocol_sent / damage_protocol_sent), protokol v příloze (PDF/HTML);
// fallback raw_html, když šablona v DB chybí. Volá se AUTOMATICKY po uložení
// protokolu (ElectronicProtocolModal) a ručně jako „Odeslat znovu" při selhání.
export async function sendProtocolEmail(info) {
  if (!info?.customerEmail) return { sent: false, error: 'Zákazník nemá uložený e-mail.' }
  const isDamage = info.type === 'damage_protocol'
  const slug = isDamage ? 'damage_protocol_sent' : 'handover_protocol_sent'
  const template_vars = {
    customer_name: info.customerName || '', moto: info.moto || '', moto_model: info.moto || '',
    rental_period: info.rentalPeriod || '', booking_number: info.bookingNumber || '', doc_name: info.docName || '',
  }
  const ext = info.pdfPath && info.pdfPath.toLowerCase().endsWith('.html') ? '.html' : '.pdf'
  const filename = `${(info.docName || 'protokol').replace(/[^\wÀ-ſ]+/g, '_')}${ext}`
  const attachment_paths = info.pdfPath ? [{ filename, path: info.pdfPath }] : []
  const base = { to: info.customerEmail, customer_id: info.customerId || null, booking_id: info.bookingId || null, attachment_paths }
  try {
    const res = await supabase.functions.invoke('send-email', { body: { ...base, template_slug: slug, template_vars } })
    const failed = res?.error || (res?.data && res.data.success === false)
    if (failed) {
      const res2 = await supabase.functions.invoke('send-email', { body: { ...base, template_slug: slug, subject: `${info.docName || 'Předávací protokol'} — MOTO GO 24`, raw_html: info.html } })
      if (res2?.error || (res2?.data && res2.data.success === false)) {
        return { sent: false, error: res2?.error?.message || res2?.data?.error || 'Odeslání selhalo' }
      }
    }
    return { sent: true, error: null }
  } catch (e) {
    return { sent: false, error: e.message || String(e) }
  }
}
