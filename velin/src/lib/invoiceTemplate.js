/**
 * Czech invoice HTML template generator
 * Generates proforma (zálohová) and final (konečná) invoices
 * compliant with Czech accounting law (zákon o DPH §28)
 */

const COMPANY = {
  name: 'MotoGo24 s.r.o.',
  address: 'Mezná 9, 393 01 Pelhřimov',
  ico: '12345678',
  dic: 'CZ12345678',
  bank: 'Fio banka',
  iban: 'CZ6520100000002800123456',
  swift: 'FIOBCZPPXXX',
  account: '2800123456/2010',
  phone: '+420 777 000 024',
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
      <td style="padding:6px 10px;border-bottom:1px solid #e5e7eb;font-size:12px;text-align:center">${it.vat_rate || 21} %</td>
      <td style="padding:6px 10px;border-bottom:1px solid #e5e7eb;font-size:12px;text-align:right;font-weight:600">${fmtPrice((it.unit_price || 0) * (it.qty || 1))} Kč</td>
    </tr>`).join('')
}

export function generateInvoiceHtml(data) {
  const isProforma = data.type === 'proforma' || data.type === 'shop_proforma'
  const title = isProforma ? 'ZÁLOHOVÁ FAKTURA' : 'FAKTURA – DAŇOVÝ DOKLAD'
  const subtitle = isProforma ? 'Proforma invoice' : 'Tax invoice'
  const accent = isProforma ? '#2563eb' : '#1a8a18'

  const supplier = data.supplier || COMPANY
  const customer = data.customer || {}
  const items = data.items || []
  const subtotal = data.subtotal || items.reduce((s, it) => s + (it.unit_price || 0) * (it.qty || 1), 0)
  const taxAmount = data.tax_amount || Math.round(subtotal * 0.21 * 100) / 100
  const total = data.total || subtotal + taxAmount
  const vs = data.variable_symbol || data.number || ''

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
      ${!isProforma ? `<p style="margin:2px 0;font-size:11px;color:#666">DÚZP: ${fmtDate(data.duzp || data.issue_date)}</p>` : ''}
      <p style="margin:2px 0;font-size:11px;color:#666">Splatnost: ${fmtDate(data.due_date)}</p>
    </div>
  </div>

  <!-- Supplier + Customer -->
  <div style="display:flex;gap:24px;margin-bottom:24px">
    <div style="flex:1;padding:14px;background:#f8faf9;border-radius:8px">
      <p style="margin:0 0 6px;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:1px;color:#888">Dodavatel</p>
      <p style="margin:0;font-size:13px;font-weight:700">${supplier.name}</p>
      <p style="margin:2px 0;font-size:11px">${supplier.address}</p>
      <p style="margin:2px 0;font-size:11px">IČO: ${supplier.ico} | DIČ: ${supplier.dic}</p>
      <p style="margin:2px 0;font-size:11px">${supplier.phone} | ${supplier.email}</p>
    </div>
    <div style="flex:1;padding:14px;background:#f8faf9;border-radius:8px">
      <p style="margin:0 0 6px;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:1px;color:#888">Odběratel</p>
      <p style="margin:0;font-size:13px;font-weight:700">${customer.name || customer.full_name || '—'}</p>
      <p style="margin:2px 0;font-size:11px">${customer.address || ''}</p>
      ${customer.ico ? `<p style="margin:2px 0;font-size:11px">IČO: ${customer.ico}${customer.dic ? ` | DIČ: ${customer.dic}` : ''}</p>` : ''}
      <p style="margin:2px 0;font-size:11px">${customer.email || ''}</p>
    </div>
  </div>

  <!-- Items table -->
  <table style="width:100%;border-collapse:collapse;margin-bottom:20px">
    <thead>
      <tr style="background:${accent}">
        <th style="padding:8px 10px;color:#fff;font-size:10px;font-weight:700;text-transform:uppercase;text-align:left">#</th>
        <th style="padding:8px 10px;color:#fff;font-size:10px;font-weight:700;text-transform:uppercase;text-align:left">Popis</th>
        <th style="padding:8px 10px;color:#fff;font-size:10px;font-weight:700;text-transform:uppercase;text-align:center">Ks</th>
        <th style="padding:8px 10px;color:#fff;font-size:10px;font-weight:700;text-transform:uppercase;text-align:right">Cena/ks</th>
        <th style="padding:8px 10px;color:#fff;font-size:10px;font-weight:700;text-transform:uppercase;text-align:center">DPH</th>
        <th style="padding:8px 10px;color:#fff;font-size:10px;font-weight:700;text-transform:uppercase;text-align:right">Celkem</th>
      </tr>
    </thead>
    <tbody>${buildItems(items)}</tbody>
  </table>

  <!-- Totals -->
  <div style="display:flex;justify-content:flex-end;margin-bottom:24px">
    <table style="border-collapse:collapse;min-width:280px">
      <tr><td style="padding:4px 12px;font-size:12px;color:#666">Základ daně</td><td style="padding:4px 12px;font-size:12px;text-align:right">${fmtPrice(subtotal)} Kč</td></tr>
      <tr><td style="padding:4px 12px;font-size:12px;color:#666">DPH 21 %</td><td style="padding:4px 12px;font-size:12px;text-align:right">${fmtPrice(taxAmount)} Kč</td></tr>
      <tr style="border-top:2px solid ${accent}">
        <td style="padding:8px 12px;font-size:15px;font-weight:800;color:${accent}">Celkem k úhradě</td>
        <td style="padding:8px 12px;font-size:15px;font-weight:800;text-align:right;color:${accent}">${fmtPrice(total)} Kč</td>
      </tr>
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
    <div style="display:flex;gap:24px;font-size:12px;margin-top:4px">
      <div><span style="color:#888">IBAN:</span> ${supplier.iban}</div>
      <div><span style="color:#888">SWIFT:</span> ${supplier.swift}</div>
    </div>
  </div>

  ${data.notes ? `<div style="padding:10px 14px;background:#fffbeb;border-radius:8px;font-size:11px;color:#92400e;margin-bottom:16px"><strong>Poznámka:</strong> ${data.notes}</div>` : ''}

  ${isProforma ? `<div style="padding:10px 14px;background:#dbeafe;border-radius:8px;font-size:11px;color:#1e40af;margin-bottom:16px">Tento doklad není daňovým dokladem. Po přijetí platby Vám bude vystavena konečná faktura – daňový doklad.</div>` : ''}

  <!-- Footer -->
  <div style="text-align:center;margin-top:24px;padding-top:12px;border-top:1px solid #e5e7eb">
    <p style="margin:0;font-size:10px;color:#aaa">${supplier.name} | ${supplier.address} | IČO: ${supplier.ico} | DIČ: ${supplier.dic}</p>
    <p style="margin:2px 0;font-size:10px;color:#aaa">${supplier.web} | ${supplier.email} | ${supplier.phone}</p>
  </div>

</div>
</body>
</html>`
}

export { COMPANY, fmtDate, fmtPrice }
