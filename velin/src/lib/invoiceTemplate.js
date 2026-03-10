/**
 * Czech invoice HTML template generator
 * Generates proforma (zálohová) and final (konečná) invoices
 * Dodavatel: Bc. Petra Semorádová, IČO 21874263, neplátce DPH
 */

const COMPANY = {
  name: 'Bc. Petra Semorádová',
  address: 'Mezná 9, 393 01 Mezná',
  ico: '21874263',
  dic: null,
  vatPayer: false,
  bank: 'mBank',
  account: '670100-2225851630/6210',
  phone: '+420 774 256 271',
  email: 'info@motogo24.cz',
  web: 'www.motogo24.cz',
}

const fmtDate = (d) => {
  if (!d) return '—'
  return new Date(d).toLocaleDateString('cs-CZ')
}

const fmtPrice = (n) => (n || 0).toLocaleString('cs-CZ', { minimumFractionDigits: 2 })

function buildItems(items) {
  if (!items || items.length === 0) return ''
  return items.map((it, i) => `
    <tr>
      <td style="padding:6px 10px;border-bottom:1px solid #e5e7eb;font-size:12px">${i + 1}</td>
      <td style="padding:6px 10px;border-bottom:1px solid #e5e7eb;font-size:12px">${it.description || ''}</td>
      <td style="padding:6px 10px;border-bottom:1px solid #e5e7eb;font-size:12px;text-align:center">${it.qty || 1}</td>
      <td style="padding:6px 10px;border-bottom:1px solid #e5e7eb;font-size:12px;text-align:right">${fmtPrice(it.unit_price)} Kč</td>
      <td style="padding:6px 10px;border-bottom:1px solid #e5e7eb;font-size:12px;text-align:right;font-weight:600">${fmtPrice((it.unit_price || 0) * (it.qty || 1))} Kč</td>
    </tr>`).join('')
}

export function generateInvoiceHtml(data) {
  const isProforma = data.type === 'proforma' || data.type === 'shop_proforma' || data.type === 'advance'
  const isPaymentReceipt = data.type === 'payment_receipt'
  const title = isPaymentReceipt ? 'DAŇOVÝ DOKLAD K PŘIJATÉ PLATBĚ' : isProforma ? 'ZÁLOHOVÁ FAKTURA' : 'FAKTURA'
  const subtitle = isPaymentReceipt ? 'Payment receipt' : isProforma ? 'Proforma invoice' : 'Invoice'
  const accent = isPaymentReceipt ? '#0891b2' : isProforma ? '#2563eb' : '#1a8a18'

  const supplier = data.supplier || COMPANY
  const customer = data.customer || {}
  const items = data.items || []
  // Neplátce DPH — žádná daň
  const subtotal = data.subtotal || items.reduce((s, it) => s + (it.unit_price || 0) * (it.qty || 1), 0)
  const total = data.total || subtotal
  const vs = data.variable_symbol || data.number || ''

  const supplierDicLine = supplier.dic
    ? `<p style="margin:2px 0;font-size:11px">IČO: ${supplier.ico} | DIČ: ${supplier.dic}</p>`
    : `<p style="margin:2px 0;font-size:11px">IČO: ${supplier.ico}</p><p style="margin:2px 0;font-size:11px;color:#888">Neplátce DPH</p>`

  return `<!DOCTYPE html>
<html lang="cs">
<head><meta charset="utf-8"><title>${title} ${data.number || ''}</title></head>
<body style="margin:0;padding:0;font-family:'Segoe UI',Helvetica,Arial,sans-serif;color:#1a1a1a;background:#fff">
<div style="max-width:780px;margin:0 auto;padding:32px 28px">

  <!-- Header -->
  <div style="display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:24px;border-bottom:3px solid ${accent};padding-bottom:16px">
    <div>
      <h1 style="margin:0;font-size:22px;font-weight:800;letter-spacing:1px;color:${accent}">${title}</h1>
      <p style="margin:2px 0 0;font-size:11px;color:#888">${subtitle}</p>
    </div>
    <div style="text-align:right">
      <p style="margin:0;font-size:13px;font-weight:700">Číslo: ${data.number || '—'}</p>
      <p style="margin:2px 0;font-size:11px;color:#666">Vystaveno: ${fmtDate(data.issue_date)}</p>
      <p style="margin:2px 0;font-size:11px;color:#666">Splatnost: ${fmtDate(data.due_date)}</p>
    </div>
  </div>

  <!-- Supplier + Customer -->
  <div style="display:flex;gap:24px;margin-bottom:24px">
    <div style="flex:1;padding:14px;background:#f8faf9;border-radius:8px">
      <p style="margin:0 0 6px;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:1px;color:#888">Dodavatel</p>
      <p style="margin:0;font-size:13px;font-weight:700">${supplier.name}</p>
      <p style="margin:2px 0;font-size:11px">${supplier.address}</p>
      ${supplierDicLine}
      <p style="margin:2px 0;font-size:11px">${supplier.phone} | ${supplier.email}</p>
    </div>
    <div style="flex:1;padding:14px;background:#f8faf9;border-radius:8px">
      <p style="margin:0 0 6px;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:1px;color:#888">Odběratel</p>
      <p style="margin:0;font-size:13px;font-weight:700">${customer.name || customer.full_name || '—'}</p>
      <p style="margin:2px 0;font-size:11px">${customer.address || [customer.street, customer.city, customer.zip].filter(Boolean).join(', ') || ''}</p>
      ${customer.ico ? `<p style="margin:2px 0;font-size:11px">IČO: ${customer.ico}${customer.dic ? ` | DIČ: ${customer.dic}` : ''}</p>` : ''}
      <p style="margin:2px 0;font-size:11px">${customer.email || ''}</p>
    </div>
  </div>

  ${data.bookings ? `
  <!-- Booking info -->
  <div style="margin-bottom:16px;padding:10px 14px;background:#f0fdf4;border-radius:8px;font-size:12px;color:#1a1a1a">
    <span style="color:#888;font-weight:600">Rezervace:</span> #${(data.bookings.id || data.booking_id || '').slice(-8).toUpperCase()}
    &nbsp;|&nbsp; <span style="color:#888;font-weight:600">Období:</span> ${fmtDate(data.bookings.start_date)} – ${fmtDate(data.bookings.end_date)}
    ${data.bookings.motorcycles ? `&nbsp;|&nbsp; <span style="color:#888;font-weight:600">Motorka:</span> ${data.bookings.motorcycles.model || '—'} (${data.bookings.motorcycles.spz || '—'})` : ''}
  </div>` : ''}

  <!-- Items table -->
  <table style="width:100%;border-collapse:collapse;margin-bottom:20px">
    <thead>
      <tr style="background:${accent}">
        <th style="padding:8px 10px;color:#fff;font-size:10px;font-weight:700;text-transform:uppercase;text-align:left">#</th>
        <th style="padding:8px 10px;color:#fff;font-size:10px;font-weight:700;text-transform:uppercase;text-align:left">Položka</th>
        <th style="padding:8px 10px;color:#fff;font-size:10px;font-weight:700;text-transform:uppercase;text-align:center">Množství</th>
        <th style="padding:8px 10px;color:#fff;font-size:10px;font-weight:700;text-transform:uppercase;text-align:right">Cena/j.</th>
        <th style="padding:8px 10px;color:#fff;font-size:10px;font-weight:700;text-transform:uppercase;text-align:right">Celkem</th>
      </tr>
    </thead>
    <tbody>${buildItems(items)}</tbody>
  </table>

  <!-- Totals -->
  <div style="display:flex;justify-content:flex-end;margin-bottom:24px">
    <table style="border-collapse:collapse;min-width:280px">
      <tr style="border-top:2px solid ${accent}">
        <td style="padding:8px 12px;font-size:15px;font-weight:800;color:${accent}">Celkem k úhradě</td>
        <td style="padding:8px 12px;font-size:15px;font-weight:800;text-align:right;color:${accent}">${fmtPrice(total)} Kč</td>
      </tr>
      <tr><td colspan="2" style="padding:2px 12px;font-size:10px;color:#888">Cena je konečná — dodavatel není plátce DPH</td></tr>
    </table>
  </div>

  <!-- Payment info -->
  <div style="padding:14px;background:#f8faf9;border-radius:8px;margin-bottom:16px">
    <p style="margin:0 0 6px;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:1px;color:#888">Platební údaje</p>
    <div style="display:flex;gap:24px;font-size:12px">
      <div><span style="color:#888">Banka:</span> ${supplier.bank}</div>
      <div><span style="color:#888">Č. účtu:</span> ${supplier.account}</div>
      <div><span style="color:#888">VS:</span> ${vs}</div>
    </div>
  </div>

  ${data.voucher_codes && data.voucher_codes.length > 0 ? `
  <div style="padding:14px;background:#dcfce7;border-radius:8px;margin-bottom:16px;border:1px solid #86efac">
    <p style="margin:0 0 6px;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:1px;color:#166534">Kódy dárkových poukazů</p>
    ${data.voucher_codes.map(c => `<p style="margin:2px 0;font-size:14px;font-weight:700;font-family:monospace;color:#166534">${c}</p>`).join('')}
    <p style="margin:6px 0 0;font-size:10px;color:#4a6357">Kódy uplatníte při rezervaci motorky na motogo24.cz nebo v mobilní aplikaci MotoGo24.</p>
  </div>` : ''}

  ${data.notes ? `<div style="padding:10px 14px;background:#fffbeb;border-radius:8px;font-size:11px;color:#92400e;margin-bottom:16px"><strong>Poznámka:</strong> ${data.notes}</div>` : ''}

  ${isProforma ? `<div style="padding:10px 14px;background:#dbeafe;border-radius:8px;font-size:11px;color:#1e40af;margin-bottom:16px">Tento doklad není daňovým dokladem. Po přijetí platby Vám bude vystavena konečná faktura.</div>` : ''}
  ${isPaymentReceipt ? `<div style="padding:10px 14px;background:#cffafe;border-radius:8px;font-size:11px;color:#0e7490;margin-bottom:16px">Daňový doklad k přijaté platbě dle zákona č. 235/2004 Sb., o dani z přidané hodnoty.</div>` : ''}

  <!-- Footer -->
  <div style="text-align:center;margin-top:24px;padding-top:12px;border-top:1px solid #e5e7eb">
    <p style="margin:0;font-size:10px;color:#aaa">${supplier.name} | ${supplier.address} | IČO: ${supplier.ico}</p>
    <p style="margin:2px 0;font-size:10px;color:#aaa">${supplier.web} | ${supplier.email} | ${supplier.phone}</p>
  </div>

</div>
</body>
</html>`
}

export { COMPANY, fmtDate, fmtPrice }
