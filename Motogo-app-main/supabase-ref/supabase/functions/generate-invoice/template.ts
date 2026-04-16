// ===== INVOICE HTML TEMPLATE GENERATOR =====

const fmtDate = (d: string) => d ? new Date(d).toLocaleDateString('cs-CZ') : '—'
const fmtPrice = (n: number) => (n || 0).toLocaleString('cs-CZ', { minimumFractionDigits: 2 })

interface InvoiceItem { description: string; qty: number; unit_price: number }

interface TemplateParams {
  title: string; number: string; accent: string
  issueDate: string; dueDate: string; total: number
  company: any; customer: any
  items: InvoiceItem[]
  voucher_codes?: string[]; voucherValidUntil?: string | null
  doorCodes?: any[]
  isProforma: boolean; isPaymentReceipt: boolean; isShopFinal: boolean
  dpNumber?: string
}

export function generateInvoiceHtml(p: TemplateParams): string {
  const itemsHtml = p.items.map((it, i) => {
    if (it.description && it.description.startsWith('──') && (it.unit_price || 0) === 0) {
      const label = it.description.replace(/──/g, '').trim()
      return `<tr><td colspan="5" style="padding:10px 10px 4px;font-weight:800;font-size:12px;border-bottom:2px solid ${p.accent};color:${p.accent}">${label}</td></tr>`
    }
    const pc = (it.unit_price || 0) < 0 ? 'color:#b91c1c;' : ''
    return `<tr>
      <td style="padding:6px 10px;border-bottom:1px solid #e5e7eb;font-size:12px">${i + 1}</td>
      <td style="padding:6px 10px;border-bottom:1px solid #e5e7eb;font-size:12px">${it.description}</td>
      <td style="padding:6px 10px;border-bottom:1px solid #e5e7eb;font-size:12px;text-align:center">${it.qty}</td>
      <td style="padding:6px 10px;border-bottom:1px solid #e5e7eb;font-size:12px;text-align:right;${pc}">${fmtPrice(it.unit_price)} Kč</td>
      <td style="padding:6px 10px;border-bottom:1px solid #e5e7eb;font-size:12px;text-align:right;font-weight:600;${pc}">${fmtPrice(it.unit_price * it.qty)} Kč</td>
    </tr>`
  }).join('')

  const custIco = p.customer.ico ? `<p style="margin:2px 0;font-size:11px">IČO: ${p.customer.ico}${p.customer.dic ? ' | DIČ: ' + p.customer.dic : ''}</p>` : ''
  const custAddr = [p.customer.street, p.customer.city, p.customer.zip, p.customer.country].filter(Boolean).join(', ')
  const vc = p.voucher_codes || []
  const dc = p.doorCodes || []

  return `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>${p.title} ${p.number}</title></head>
<body style="margin:0;padding:0;font-family:'Segoe UI',Helvetica,Arial,sans-serif;color:#1a1a1a;background:#fff">
<div style="max-width:780px;margin:0 auto;padding:32px 28px">
  <div style="display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:24px;border-bottom:3px solid ${p.accent};padding-bottom:16px">
    <div><h1 style="margin:0;font-size:22px;font-weight:800;color:${p.accent}">${p.title}</h1></div>
    <div style="text-align:right">
      <p style="margin:0;font-size:13px;font-weight:700">Číslo: ${p.number}</p>
      <p style="margin:2px 0;font-size:11px;color:#666">Vystaveno: ${fmtDate(p.issueDate)}</p>
      <p style="margin:2px 0;font-size:11px;color:#666">Splatnost: ${fmtDate(p.dueDate)}</p>
    </div>
  </div>
  <div style="display:flex;gap:24px;margin-bottom:24px">
    <div style="flex:1;padding:14px;background:#f8faf9;border-radius:8px">
      <p style="margin:0 0 6px;font-size:10px;font-weight:700;text-transform:uppercase;color:#888">Dodavatel</p>
      <p style="margin:0;font-size:13px;font-weight:700">${p.company.name}</p>
      <p style="margin:2px 0;font-size:11px">${p.company.address}</p>
      <p style="margin:2px 0;font-size:11px">IČO: ${p.company.ico}</p>
      <p style="margin:2px 0;font-size:11px;color:#888">Neplátce DPH</p>
    </div>
    <div style="flex:1;padding:14px;background:#f8faf9;border-radius:8px">
      <p style="margin:0 0 6px;font-size:10px;font-weight:700;text-transform:uppercase;color:#888">Odběratel</p>
      <p style="margin:0;font-size:13px;font-weight:700">${p.customer.full_name || '—'}</p>
      <p style="margin:2px 0;font-size:11px">${custAddr}</p>
      ${custIco}
      <p style="margin:2px 0;font-size:11px">${p.customer.email || ''}</p>
    </div>
  </div>
  <table style="width:100%;border-collapse:collapse;margin-bottom:20px">
    <thead><tr style="background:${p.accent}">
      <th style="padding:8px 10px;color:#fff;font-size:10px;text-align:left">#</th>
      <th style="padding:8px 10px;color:#fff;font-size:10px;text-align:left">Popis</th>
      <th style="padding:8px 10px;color:#fff;font-size:10px;text-align:center">Ks</th>
      <th style="padding:8px 10px;color:#fff;font-size:10px;text-align:right">Cena/ks</th>
      <th style="padding:8px 10px;color:#fff;font-size:10px;text-align:right">Celkem</th>
    </tr></thead>
    <tbody>${itemsHtml}</tbody>
  </table>
  <div style="display:flex;justify-content:flex-end;margin-bottom:24px">
    <table style="border-collapse:collapse;min-width:280px">
      <tr style="border-top:2px solid ${p.accent}"><td style="padding:8px 12px;font-size:15px;font-weight:800;color:${p.accent}">Celkem</td><td style="padding:8px 12px;font-size:15px;font-weight:800;text-align:right;color:${p.accent}">${fmtPrice(p.total)} Kč</td></tr>
      <tr><td colspan="2" style="padding:2px 12px;font-size:10px;color:#888">Cena je konečná — dodavatel není plátce DPH</td></tr>
    </table>
  </div>
  <div style="padding:14px;background:#f8faf9;border-radius:8px;margin-bottom:16px">
    <p style="margin:0 0 6px;font-size:10px;font-weight:700;text-transform:uppercase;color:#888">Platební údaje</p>
    <div style="font-size:12px"><span style="color:#888">Banka:</span> ${p.company.bank} | <span style="color:#888">Č. účtu:</span> ${p.company.account} | <span style="color:#888">VS:</span> ${p.number}</div>
  </div>
  ${vc.length > 0 ? `<div style="padding:14px;background:#dcfce7;border-radius:8px;margin-bottom:16px;border:1px solid #86efac">
    <p style="margin:0 0 6px;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:1px;color:#166534">Dárkové poukazy</p>
    ${vc.map((c: string) => `<p style="margin:4px 0;font-size:14px;font-weight:700;font-family:monospace;color:#166534">${c}</p>`).join('')}
    ${p.voucherValidUntil ? `<p style="margin:8px 0 2px;font-size:11px;font-weight:600;color:#166534">Platnost poukazu: 3 roky (do ${fmtDate(p.voucherValidUntil)})</p>` : ''}
    <p style="margin:4px 0 0;font-size:10px;color:#4a6357">Kód uplatníte při rezervaci motorky na motogo24.cz nebo v mobilní aplikaci MotoGo24 v sekci „Slevový kód".</p>
  </div>` : ''}
  ${dc.length > 0 ? `<div style="padding:14px;background:#e0f2fe;border-radius:8px;margin-bottom:16px;border:2px solid #0284c7">
    <p style="margin:0 0 8px;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:1px;color:#0c4a6e">Přístupové kódy k pobočce</p>
    ${dc.filter((c: any) => !c.withheld_reason).map((d: any) => `<p style="margin:4px 0;font-size:14px;font-weight:700;font-family:'Courier New',monospace;color:#0c4a6e">${d.code_type === 'motorcycle' ? 'Kód k motorce' : 'Kód k příslušenství'}: <span style="font-size:18px;letter-spacing:3px;color:#0369a1">${d.door_code}</span></p>`).join('')}
    ${dc.some((c: any) => c.withheld_reason) ? '<p style="margin:6px 0 0;font-size:12px;font-weight:600;color:#b45309">Kódy budou zaslány po ověření dokladů (OP/pas/ŘP).</p>' : '<p style="margin:8px 0 0;font-size:11px;color:#164e63">Kódy jsou platné pouze po dobu trvání pronájmu.</p>'}
  </div>` : ''}
  ${p.isProforma ? '<div style="padding:10px 14px;background:#dbeafe;border-radius:8px;font-size:11px;color:#1e40af">Tento doklad není daňovým dokladem. Po přijetí platby Vám bude vystavena konečná faktura.</div>' : ''}
  ${p.isPaymentReceipt ? '<div style="padding:10px 14px;background:#cffafe;border-radius:8px;font-size:11px;color:#0e7490">Tento doklad potvrzuje přijetí platby. Konečná faktura bude vystavena po odeslání zboží.</div>' : ''}
  ${p.isShopFinal ? `<div style="padding:10px 14px;background:#dcfce7;border-radius:8px;font-size:11px;color:#15803d">Konečná faktura — platba byla již provedena na základě dokladu ${p.dpNumber || 'DP'}. K úhradě: 0,00 Kč.</div>` : ''}
</div></body></html>`
}

export function generateEmailHtml(p: {
  customer: any; company: any; title: string; number: string; total: number
  dueDate: string; voucher_codes?: string[]; voucherValidUntil?: string | null
  doorCodes?: any[]; isPaymentReceipt: boolean; isProforma: boolean; isShopFinal: boolean
}): string {
  const docLabel = p.isPaymentReceipt ? 'doklad k přijaté platbě' : p.isProforma ? 'zálohovou fakturu' : p.isShopFinal ? 'konečnou fakturu' : 'fakturu'
  const vc = p.voucher_codes || []
  const dc = p.doorCodes || []
  return `<div style="font-family:sans-serif;padding:24px">
    <h2 style="color:#1a2e22">Dobrý den${p.customer.full_name ? ` ${p.customer.full_name}` : ''},</h2>
    <p>Zasíláme vám ${docLabel} č. <strong>${p.number}</strong> na částku <strong>${fmtPrice(p.total)} Kč</strong>.</p>
    <p>Splatnost: <strong>${fmtDate(p.dueDate)}</strong></p>
    <p>Variabilní symbol: <strong>${p.number}</strong></p>
    ${vc.length > 0 ? `<div style="padding:12px;background:#dcfce7;border-radius:8px;margin:12px 0"><p style="margin:0 0 4px;font-size:11px;font-weight:700;color:#166534">Dárkové poukazy:</p>${vc.map((c: string) => `<p style="margin:2px 0;font-size:16px;font-weight:700;font-family:monospace;color:#166534">${c}</p>`).join('')}${p.voucherValidUntil ? `<p style="margin:6px 0 0;font-size:11px;color:#166534">Platnost: 3 roky (do ${fmtDate(p.voucherValidUntil)}). Kód uplatníte při rezervaci v aplikaci MotoGo24.</p>` : ''}</div>` : ''}
    ${dc.length > 0 ? `<div style="padding:12px;background:#e0f2fe;border-radius:8px;margin:12px 0;border:2px solid #0284c7"><p style="margin:0 0 8px;font-size:11px;font-weight:700;color:#0c4a6e">PŘÍSTUPOVÉ KÓDY K POBOČCE:</p>${dc.filter((c: any) => !c.withheld_reason).map((d: any) => `<p style="margin:4px 0;font-size:18px;font-weight:700;font-family:monospace;letter-spacing:3px;color:#0369a1">${d.code_type === 'motorcycle' ? 'Motorka' : 'Příslušenství'}: ${d.door_code}</p>`).join('')}${dc.some((c: any) => c.withheld_reason) ? '<p style="margin:6px 0 0;font-size:12px;color:#b45309">Kódy budou zaslány po ověření dokladů.</p>' : '<p style="margin:6px 0 0;font-size:11px;color:#164e63">Kódy jsou platné po dobu trvání pronájmu.</p>'}</div>` : ''}
    <hr style="border:1px solid #e5e7eb">
    <p style="font-size:12px;color:#888">${p.company.name} | ${p.company.email}</p>
  </div>`
}
