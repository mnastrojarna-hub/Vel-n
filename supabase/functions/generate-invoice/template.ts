// ===== INVOICE HTML TEMPLATE GENERATOR =====
// Unified design — used for ZF / DP / KF / Shop / Credit note

const LOGO_URL = 'https://motogo24.cz/gfx/logo-icon.png'

const fmtDate = (d: string) => d ? new Date(d).toLocaleDateString('cs-CZ') : '—'
const fmtPrice = (n: number) => `${(n || 0).toLocaleString('cs-CZ', { maximumFractionDigits: 0 })} Kč`

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
  bookingNumber?: string
  paymentMethodLabel?: string
  cardInfo?: { brand: string; last4: string } | null
  isEdit?: boolean
  // optional — for richer payment block:
  stripePaymentIntentId?: string
  paidDate?: string
}

// Split "Pronájem BMW R 1200 GS — 13.5.2026 – 13.5.2026" → name + desc
function splitItem(desc: string): { name: string; detail: string } {
  if (!desc) return { name: '—', detail: '' }
  const m = desc.split(/\s+—\s+/)
  if (m.length >= 2) return { name: m[0].trim(), detail: m.slice(1).join(' — ').trim() }
  return { name: desc.trim(), detail: '' }
}

function typeLabel(p: TemplateParams): string {
  if (p.isProforma) return 'ZF'
  if (p.isPaymentReceipt) return 'DAŇOVÝ DOKLAD'
  return 'FAKTURA'
}

function statusBadge(p: TemplateParams): { label: string; tone: 'paid' | 'pending' } {
  if (p.isProforma) return { label: 'K ÚHRADĚ', tone: 'pending' }
  if (p.isPaymentReceipt) return { label: 'UHRAZENO', tone: 'paid' }
  if (p.isShopFinal) return { label: 'UHRAZENO', tone: 'paid' }
  return { label: 'VYÚČTOVÁNO', tone: 'paid' }
}

function statusLabelFull(p: TemplateParams): string {
  if (p.isProforma) return 'K úhradě'
  return 'Uhrazena'
}

export function generateInvoiceHtml(p: TemplateParams): string {
  const badge = statusBadge(p)
  const tcode = typeLabel(p)
  const status = statusLabelFull(p)
  const customerAddr = [p.customer.street, p.customer.city, p.customer.zip].filter(Boolean).join(', ')
  const vc = p.voucher_codes || []
  const dc = p.doorCodes || []

  // Item rows
  const itemsHtml = p.items.map((it) => {
    if (it.description && it.description.startsWith('──') && (it.unit_price || 0) === 0) {
      const label = it.description.replace(/──/g, '').trim()
      return `<tr><td colspan="4" style="padding:14px 16px 6px;font-weight:700;font-size:11px;color:#16a34a;text-transform:uppercase;letter-spacing:.5px">${label}</td></tr>`
    }
    const { name, detail } = splitItem(it.description)
    const lineTotal = (it.unit_price || 0) * (it.qty || 1)
    const neg = lineTotal < 0 ? 'color:#b91c1c;' : 'color:#0f1a14;'
    return `<tr>
      <td style="padding:14px 16px;border-top:1px solid #e5e7eb;font-size:13px;font-weight:700;color:#0f1a14;vertical-align:top;width:30%">${name}</td>
      <td style="padding:14px 16px;border-top:1px solid #e5e7eb;font-size:12px;color:#6b7280;vertical-align:top">${detail}</td>
      <td style="padding:14px 16px;border-top:1px solid #e5e7eb;font-size:13px;color:#0f1a14;text-align:right;vertical-align:top;white-space:nowrap;width:60px">${it.qty || 1}</td>
      <td style="padding:14px 16px;border-top:1px solid #e5e7eb;font-size:13px;text-align:right;vertical-align:top;white-space:nowrap;width:110px;font-variant-numeric:tabular-nums;${neg}">${fmtPrice(lineTotal)}</td>
    </tr>`
  }).join('')

  // Subtotal / VAT / Total
  const subtotal = p.items.reduce((s, it) => s + (it.unit_price || 0) * (it.qty || 1), 0)

  // Payment block — Stripe card vs bank
  const paymentBlock = p.cardInfo ? `
    <div style="display:flex;justify-content:space-between;font-size:13px;padding:6px 0">
      <span style="color:#16a34a;font-weight:600">Stav</span>
      <span style="color:#0f1a14;font-weight:700">${status}</span>
    </div>
    <div style="display:flex;justify-content:space-between;font-size:13px;padding:6px 0">
      <span style="color:#16a34a;font-weight:600">Uhrazeno online</span>
      <span style="color:#0f1a14;font-weight:700;font-variant-numeric:tabular-nums">${fmtPrice(p.total)}</span>
    </div>
    ${p.stripePaymentIntentId ? `<div style="font-size:10px;color:#9ca3af;text-align:right;margin-top:-4px;font-family:'Courier New',monospace">${p.stripePaymentIntentId}</div>` : ''}
  ` : `
    <div style="display:flex;justify-content:space-between;font-size:13px;padding:6px 0">
      <span style="color:#16a34a;font-weight:600">Stav</span>
      <span style="color:#0f1a14;font-weight:700">${status}</span>
    </div>
    <div style="display:flex;justify-content:space-between;font-size:13px;padding:6px 0">
      <span style="color:#16a34a;font-weight:600">Bankovní účet</span>
      <span style="color:#0f1a14;font-weight:700">${p.company.account || ''}</span>
    </div>
    <div style="display:flex;justify-content:space-between;font-size:13px;padding:6px 0">
      <span style="color:#16a34a;font-weight:600">Banka</span>
      <span style="color:#0f1a14;font-weight:700">${p.company.bank || 'mBank'}</span>
    </div>
  `

  const badgeBg = badge.tone === 'paid' ? '#74FB71' : '#fbbf24'
  const badgeText = '#0a1f15'

  return `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>${p.title} ${p.number}</title>
<style>body{margin:0;padding:0;background:#d9dee2;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#0f1a14;-webkit-font-smoothing:antialiased}</style>
</head>
<body>
<div style="max-width:780px;margin:0 auto;background:#ffffff">

  <!-- HEADER -->
  <div style="background:#0a1f15;padding:24px 32px">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse">
      <tr>
        <td style="vertical-align:top;width:50%">
          <table role="presentation" cellpadding="0" cellspacing="0"><tr>
            <td style="vertical-align:middle;padding-right:14px"><img src="${LOGO_URL}" alt="MotoGo24" width="52" height="52" style="display:block;border:0"/></td>
            <td style="vertical-align:middle">
              <div style="color:#74FB71;font-size:20px;font-weight:900;letter-spacing:1px;line-height:1">MOTO GO 24</div>
              <div style="color:#74FB71;font-size:9px;font-weight:700;letter-spacing:2px;margin-top:4px">PŮJČOVNA MOTOREK</div>
            </td>
          </tr></table>
        </td>
        <td style="vertical-align:top;text-align:right">
          <div style="display:inline-block;border-radius:3px;overflow:hidden;font-size:0;margin-bottom:12px">
            <span style="display:inline-block;background:#0f3320;color:#74FB71;font-size:10px;font-weight:800;letter-spacing:1px;padding:5px 9px">${tcode}</span><span style="display:inline-block;background:${badgeBg};color:${badgeText};font-size:10px;font-weight:800;letter-spacing:1px;padding:5px 9px">${badge.label}</span>
          </div>
          <div style="color:#ffffff;font-size:20px;font-weight:600;line-height:1.2">${p.title} č. ${p.number}</div>
          ${p.bookingNumber ? `<div style="color:#9ca3af;font-size:12px;margin-top:4px">Rezervace č. ${p.bookingNumber}</div>` : ''}
        </td>
      </tr>
    </table>
  </div>

  <!-- DODAVATEL / ODBĚRATEL -->
  <div style="padding:24px 32px 8px">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:separate;border-spacing:24px 0">
      <tr>
        <td style="vertical-align:top;width:50%">
          <div style="font-size:11px;font-weight:800;color:#16a34a;letter-spacing:1.5px;margin-bottom:10px">DODAVATEL</div>
          <table role="presentation" cellpadding="0" cellspacing="0" style="font-size:12px;line-height:1.7">
            <tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">Název</td><td style="color:#0f1a14;font-weight:700">${p.company.name}</td></tr>
            <tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">Adresa</td><td style="color:#0f1a14;font-weight:700">${p.company.address}</td></tr>
            <tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">IČO</td><td style="color:#0f1a14;font-weight:700">${p.company.ico}</td></tr>
            <tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">E-mail</td><td style="color:#0f1a14;font-weight:700">${p.company.email}</td></tr>
            <tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">Telefon</td><td style="color:#0f1a14;font-weight:700">${p.company.phone}</td></tr>
          </table>
        </td>
        <td style="vertical-align:top;width:50%">
          <div style="font-size:11px;font-weight:800;color:#16a34a;letter-spacing:1.5px;margin-bottom:10px">ODBĚRATEL</div>
          <table role="presentation" cellpadding="0" cellspacing="0" style="font-size:12px;line-height:1.7">
            <tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">Jméno</td><td style="color:#0f1a14;font-weight:700">${p.customer.full_name || p.customer.name || '—'}</td></tr>
            <tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">Adresa</td><td style="color:#0f1a14;font-weight:700">${customerAddr || '—'}</td></tr>
            ${p.customer.ico ? `<tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">IČO</td><td style="color:#0f1a14;font-weight:700">${p.customer.ico}${p.customer.dic ? ` / DIČ ${p.customer.dic}` : ''}</td></tr>` : ''}
            <tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">E-mail</td><td style="color:#0f1a14;font-weight:700">${p.customer.email || '—'}</td></tr>
            <tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">Telefon</td><td style="color:#0f1a14;font-weight:700">${p.customer.phone || '—'}</td></tr>
          </table>
        </td>
      </tr>
    </table>
  </div>

  <!-- FAKTURAČNÍ ÚDAJE / PLATBA -->
  <div style="padding:16px 32px 8px">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:separate;border-spacing:24px 0">
      <tr>
        <td style="vertical-align:top;width:50%">
          <div style="font-size:11px;font-weight:800;color:#16a34a;letter-spacing:1.5px;margin-bottom:10px">FAKTURAČNÍ ÚDAJE</div>
          <table role="presentation" cellpadding="0" cellspacing="0" style="font-size:12px;line-height:1.7">
            <tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">Číslo faktury</td><td style="color:#0f1a14;font-weight:700">${p.number}</td></tr>
            <tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">Variabilní symbol</td><td style="color:#0f1a14;font-weight:700">${p.number}</td></tr>
            ${p.bookingNumber ? `<tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">Číslo rezervace</td><td style="color:#0f1a14;font-weight:700">${p.bookingNumber}</td></tr>` : ''}
            <tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">Datum vystavení</td><td style="color:#0f1a14;font-weight:700">${fmtDate(p.issueDate)}</td></tr>
            <tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">Datum splatnosti</td><td style="color:#0f1a14;font-weight:700">${fmtDate(p.dueDate)}</td></tr>
            ${badge.tone === 'paid' ? `<tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">Datum úhrady</td><td style="color:#0f1a14;font-weight:700">${fmtDate(p.paidDate || p.issueDate)}</td></tr>` : ''}
          </table>
        </td>
        <td style="vertical-align:top;width:50%">
          <div style="font-size:11px;font-weight:800;color:#16a34a;letter-spacing:1.5px;margin-bottom:10px">PLATBA</div>
          ${paymentBlock}
        </td>
      </tr>
    </table>
  </div>

  <!-- POLOŽKY -->
  <div style="padding:16px 32px 0">
    <div style="font-size:11px;font-weight:800;color:#16a34a;letter-spacing:1.5px;margin-bottom:10px">POLOŽKY</div>
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;border:1px solid #e5e7eb">
      <thead>
        <tr style="background:#0a1f15">
          <th style="padding:12px 16px;color:#ffffff;font-size:11px;font-weight:700;text-align:left;letter-spacing:.5px">Položka</th>
          <th style="padding:12px 16px;color:#ffffff;font-size:11px;font-weight:700;text-align:left;letter-spacing:.5px">Popis</th>
          <th style="padding:12px 16px;color:#ffffff;font-size:11px;font-weight:700;text-align:right;letter-spacing:.5px">Ks</th>
          <th style="padding:12px 16px;color:#ffffff;font-size:11px;font-weight:700;text-align:right;letter-spacing:.5px">Cena</th>
        </tr>
      </thead>
      <tbody>${itemsHtml}</tbody>
    </table>
  </div>

  <!-- SOUHRN -->
  <div style="padding:16px 32px 24px">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
      <tr>
        <td style="width:55%">&nbsp;</td>
        <td style="width:45%">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;border:1px solid #e5e7eb">
            <tr style="background:#f3f4f6">
              <td style="padding:12px 16px;font-size:13px;color:#0f1a14;border-bottom:1px solid #e5e7eb">Mezisoučet</td>
              <td style="padding:12px 16px;font-size:13px;color:#0f1a14;text-align:right;border-bottom:1px solid #e5e7eb;font-variant-numeric:tabular-nums">${fmtPrice(subtotal)}</td>
            </tr>
            <tr style="background:#f3f4f6">
              <td style="padding:12px 16px;font-size:13px;color:#0f1a14">DPH</td>
              <td style="padding:12px 16px;font-size:13px;color:#0f1a14;text-align:right;font-variant-numeric:tabular-nums">0 Kč</td>
            </tr>
            <tr style="background:#dcfce7">
              <td style="padding:14px 16px;font-size:15px;color:#0f1a14;font-weight:800;border-top:1px solid #86efac">Celkem</td>
              <td style="padding:14px 16px;font-size:15px;color:#0f1a14;font-weight:800;text-align:right;border-top:1px solid #86efac;font-variant-numeric:tabular-nums">${fmtPrice(p.total)}</td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </div>

  ${vc.length > 0 ? `<div style="margin:0 32px 16px;padding:14px;background:#dcfce7;border-radius:6px;border:1px solid #86efac">
    <div style="font-size:11px;font-weight:800;color:#166534;letter-spacing:1.5px;margin-bottom:6px">DÁRKOVÉ POUKAZY</div>
    ${vc.map((c: string) => `<div style="font-size:14px;font-weight:700;font-family:'Courier New',monospace;color:#166534;padding:2px 0">${c}</div>`).join('')}
    ${p.voucherValidUntil ? `<div style="font-size:11px;color:#166534;margin-top:6px">Platnost: 3 roky (do ${fmtDate(p.voucherValidUntil)})</div>` : ''}
    <div style="font-size:10px;color:#4a6357;margin-top:4px">Kód uplatníte při rezervaci na motogo24.cz nebo v aplikaci MotoGo24.</div>
  </div>` : ''}

  ${dc.length > 0 ? `<div style="margin:0 32px 16px;padding:14px;background:#e0f2fe;border-radius:6px;border:1px solid #0284c7">
    <div style="font-size:11px;font-weight:800;color:#0c4a6e;letter-spacing:1.5px;margin-bottom:8px">PŘÍSTUPOVÉ KÓDY K POBOČCE</div>
    ${dc.filter((c: any) => !c.withheld_reason).map((d: any) => `<div style="font-size:13px;font-weight:700;color:#0c4a6e;padding:3px 0">${d.code_type === 'motorcycle' ? 'Kód k motorce' : 'Kód k příslušenství'}: <span style="font-size:18px;letter-spacing:3px;color:#0369a1;font-family:'Courier New',monospace">${d.door_code}</span></div>`).join('')}
    ${dc.some((c: any) => c.withheld_reason) ? '<div style="font-size:12px;font-weight:600;color:#b45309;margin-top:6px">Kódy budou zaslány po ověření dokladů (OP/pas/ŘP).</div>' : '<div style="font-size:11px;color:#164e63;margin-top:6px">Kódy jsou platné pouze po dobu trvání pronájmu.</div>'}
  </div>` : ''}

  ${p.isProforma ? `<div style="margin:0 32px 16px;padding:10px 14px;background:#fef3c7;border-left:3px solid #f59e0b;font-size:11px;color:#78350f">Tento doklad není daňovým dokladem. Po přijetí platby Vám bude vystavena konečná faktura.</div>` : ''}
  ${p.isPaymentReceipt ? `<div style="margin:0 32px 16px;padding:10px 14px;background:#ecfdf5;border-left:3px solid #16a34a;font-size:11px;color:#065f46">Tento doklad potvrzuje přijetí platby dle zákona č. 235/2004 Sb., o dani z přidané hodnoty.</div>` : ''}
  ${p.isShopFinal ? `<div style="margin:0 32px 16px;padding:10px 14px;background:#ecfdf5;border-left:3px solid #16a34a;font-size:11px;color:#065f46">Konečná faktura — platba byla již provedena na základě dokladu ${p.dpNumber || 'DP'}. K úhradě: 0 Kč.</div>` : ''}

  <!-- FOOTER -->
  <div style="background:#0a1f15;padding:14px 32px;color:#ffffff;font-size:11px;line-height:1.6">
    <strong style="color:#ffffff">${p.company.name}</strong>
    <span style="color:#9ca3af"> &nbsp;|&nbsp; </span>${p.company.address}
    <span style="color:#9ca3af"> &nbsp;|&nbsp; </span>IČO: ${p.company.ico}
    <span style="color:#9ca3af"> &nbsp;|&nbsp; </span><span style="color:#74FB71">${p.company.phone}</span>
    <span style="color:#9ca3af"> &nbsp;|&nbsp; </span><span style="color:#74FB71">${p.company.email}</span>
    <span style="color:#9ca3af"> &nbsp;|&nbsp; </span><span style="color:#74FB71">${p.company.web || 'www.motogo24.cz'}</span>
  </div>

</div>
</body></html>`
}

