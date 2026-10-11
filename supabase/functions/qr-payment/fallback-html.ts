// qr-payment — HTML záložního mailu zákazníkovi (1:1 se šablonami booking_qr_payment /
// booking_qr_payment_surcharge; použije se, jen když šablona chybí / je vypnutá / mail
// ze šablony neodešel). Čeština byte-identická s původním kódem v index.ts (fallback_test.ts).

import { QR_TEXTS, invoiceSuffix, type QrLang } from './texts.ts'
import { QR_FALLBACK } from './fallback-texts.ts'

export const fmtAmount = (n: number) => (Math.round((Number(n) || 0) * 100) / 100).toFixed(2)

export function row(label: string, value: string, big = false): string {
  return `<tr>
    <td style="padding:8px 0;color:#16a34a;font-weight:600;font-size:13px">${label}</td>
    <td style="padding:8px 0;text-align:right;color:#0f1a14;font-weight:700;font-size:${big ? '18px' : '14px'};font-variant-numeric:tabular-nums">${value}</td>
  </tr>`
}

interface PayParams {
  custName: string; amount: number; account: string; iban: string; bank: string;
  vs: string; qrUrl: string; bookingNumber: string
}

function payTable(lang: QrLang, p: PayParams): string {
  const f = QR_FALLBACK[lang]
  return `<table style="width:100%;border-collapse:collapse;margin:0 0 14px">
    ${row(f.amount, fmtAmount(p.amount) + ' Kč', true)}
    ${row(f.account, p.account)}
    ${row('IBAN', p.iban.replace(/(.{4})/g, '$1 ').trim())}
    ${row(f.bank, p.bank)}
    ${row(f.vs, p.vs)}
  </table>`
}

const qrImg = (lang: QrLang, qrUrl: string) =>
  `<div style="text-align:center;margin:0 0 16px"><img src="${qrUrl}" alt="${QR_FALLBACK[lang].qrAlt}" style="width:240px;height:240px;border:1px solid #e5e7eb;border-radius:12px"></div>`

export function customerEmailHtml(p: PayParams & { invoiceNumber: string | null }, lang: QrLang = 'cs'): string {
  const f = QR_FALLBACK[lang]
  return `
  <h2 style="margin:0 0 6px;font-size:20px;color:#0f1a14">${f.title}</h2>
  <p style="margin:0 0 16px;color:#374151;font-size:14px">${QR_TEXTS[lang].thanks(p.custName)}${f.intro(`<strong>#${p.bookingNumber}</strong>`)}</p>
  ${qrImg(lang, p.qrUrl)}
  ${payTable(lang, p)}
  <p style="margin:0 0 10px;padding:12px 14px;background:#fef2f2;border-radius:10px;color:#b91c1c;font-weight:700;font-size:14px">${f.deadline}</p>
  <p style="margin:0 0 6px;color:#374151;font-size:13px">${f.after}${invoiceSuffix(lang, p.invoiceNumber)}</p>
  <p style="margin:0;color:#6b7280;font-size:12px">${f.card}</p>
  `
}

// DOPLATEK za úpravu rezervace — bez 4h splatnosti a bez ZF (rezervace je zaplacená,
// nic se automaticky neruší; doklad přijde po potvrzení).
export function surchargeEmailHtml(p: PayParams, lang: QrLang = 'cs'): string {
  const f = QR_FALLBACK[lang]
  return `
  <h2 style="margin:0 0 6px;font-size:20px;color:#0f1a14">${f.surchargeTitle}</h2>
  <p style="margin:0 0 16px;color:#374151;font-size:14px">${QR_TEXTS[lang].surchargeLead(p.custName)}${f.surchargeIntro(`<strong>#${p.bookingNumber}</strong>`)}</p>
  ${qrImg(lang, p.qrUrl)}
  ${payTable(lang, p)}
  <p style="margin:0;color:#374151;font-size:13px">${f.surchargeAfter}</p>
  `
}
