// ===== MotoGo24 – Edge Function: Process Refund (Stripe LIVE) =====
// Handles partial and full refunds for bookings and shop orders.
// Endpoint: POST /functions/v1/process-refund
// Body: { booking_id?, order_id?, amount?, reason? }
// If amount is omitted, full refund is issued.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import Stripe from 'https://esm.sh/stripe@14'
import { authClassify, forbidden } from '../_shared/auth.ts'
import { refundRemainder, mainSource, refundedStatus, customerCapHaleru, staffFullBalanceHaleru, otherRefundableIntents, CUSTOMER_SHORT_TOLERANCE_HALERU, type ExtraRefund, type OtherIntentsStripe } from './other-intents.ts'
import { reconcileCreditNote, remainderForMainHaleru } from './credit-note-sync.ts'
import { isRecoveryOnlyReason, WEBHOOK_REFUND_RECOVERY_REASON } from '../_shared/refund-recovery.ts'
// Výpůjčka výbavy (2026-10-23): text dobropisu „výpůjčka výbavy“ + spodní mez ceny výbavy (gear.ts).
import { gearPriceFloorCzk, loadGearRefundRow, noMotoRefundSubject } from './gear.ts'
// HOTFIX storno 2026-10-29: storno vratka nejvýš jednou za storno (cancel-once.ts).
import { acquireCancelLock, cancelBusy, hasLiveManualCreditNote, cancelToken, cancelTargetHaleru, cancellationRefundedHaleru, duplicateAdminRefunds, logicalRefundHaleru, openCancelMains, priorCancellationRefunds, releaseCancelLock, respondExistingCancelRefund, type CancelLock, type StripeRefundLike } from './cancel-once.ts'
// Sloučení hotfixu s vratkou z více plateb (dev f1–f3, 2026-11-05): kontrola nad vratkami VŠECH plateb
// rezervace + dovrácení zbytku téhož storna po pádu (cancel-once-pool.ts).
import { cancellationRefundPool, closeStaleCancelMains, completeCancelRemainder, type PoolStripe } from './cancel-once-pool.ts'
// Oprava i3 (2026-11-07): dlužná částka dle dokladů jako DB trigger _cap_refund_to_paid, převodem placená část (doc-owed.ts).
import { bankPaidCzk, docSums, docsOwedCzk, shopPartHaleru, stripeRefundsWithoutCnHaleru } from './doc-owed.ts'
// Oprava i4 (2026-11-07): idempotency klíč vratky po SELHANÉ vratce nový (Stripe by přehrál selhanou) — retry-key.ts
import { failedRefundIds, isReplayOfFailed, REPLAYED_FAILED, retrySuffix } from './retry-key.ts'
import { paymentCurrencyOk } from '../_shared/currency.ts'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2024-04-10',
  httpClient: Stripe.createFetchHttpClient(),
})

const PDFSHIFT_API_KEY = Deno.env.get('PDFSHIFT_API_KEY') || ''

async function htmlToPdf(html: string): Promise<Uint8Array | null> {
  if (!PDFSHIFT_API_KEY) return null
  try {
    const res = await fetch('https://api.pdfshift.io/v3/convert/pdf', {
      method: 'POST',
      headers: { 'X-API-Key': PDFSHIFT_API_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({ source: html, format: 'A4', margin: '12mm', sandbox: false, use_print: false }),
    })
    if (!res.ok) return null
    return new Uint8Array(await res.arrayBuffer())
  } catch { return null }
}

const fmtPrice = (n: number) => Math.abs(n || 0).toLocaleString('cs-CZ', { minimumFractionDigits: 2 })
const fmtDate = (d: string) => d ? new Date(d).toLocaleDateString('cs-CZ') : '—'

// Jednotné popisy důvodu vratky pro položky dobropisu (web/app/Velín posílají
// různé reason kódy; volný text zákazníka NIKDY neinjektujeme do HTML dokladu).
function reasonTextFor(reason: string | undefined | null): string {
  switch (reason) {
    case 'cancellation': return 'Storno rezervace'
    case 'shortening':
    case 'edit_shortening': return 'Zkrácení rezervace'
    case 'moto_swap': return 'Výměna motorky'
    case 'gear_edit': return 'Úprava výbavy'
    case 'booking_modified':
    case 'booking_modified_retry':
    case 'edit': return 'Úprava rezervace'
    case 'duplicate': return 'Duplicitní platba'
    case 'paid_change_failed': return 'Vrácení doplatku – úpravu rezervace nešlo zapsat'
    default: return 'Vrácení platby zákazníkovi'
  }
}

// Firemní údaje zákazníka (web rezervace — checkbox „Firemní údaje" v kroku 3).
// Tolerantní samostatný dotaz: sloupce company_name/company_address přidává
// migrace 20260818 — kdyby ještě nebyla aplikovaná, dobropis nesmí spadnout.
async function loadCustomerCompany(supabase: any, customer: any) {
  if (!customer || !customer.id) return
  const { data, error } = await supabase.from('profiles')
    .select('company_name, company_address').eq('id', customer.id).maybeSingle()
  if (!error && data) {
    customer.company = data.company_name || null
    customer.company_address = data.company_address || null
  }
}

function renderCreditNoteHtml(opts: {
  number: string; issueDate: string; reasonText: string; motoModel: string;
  refundAmount: number; refundPercent: number; bookingDates: string;
  customer: { full_name?: string; email?: string; phone?: string; street?: string; city?: string; zip?: string; ico?: string; dic?: string; company?: string | null; company_address?: string | null };
  originalInvoiceNumber?: string | null; stripeRefundId: string | null;
  cardBrand?: string | null; cardLast4?: string | null; manual?: boolean;
}): string {
  const c = opts.customer || {}
  const cardLine = opts.manual
    ? 'Částka bude vrácena PŘEVODEM NA ÚČET do 14 dnů.'
    : opts.cardLast4
      ? `Refund proběhl na kartu ${(opts.cardBrand || 'CARD').toUpperCase()} **** ${opts.cardLast4}.`
      : 'Refund proběhl na původní platební kartu.'
  return `<!DOCTYPE html><html lang="cs"><head><meta charset="UTF-8"><title>Dobropis ${opts.number}</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#0f1a14;margin:0;padding:24px;font-size:13px}
.hdr{display:flex;justify-content:space-between;align-items:flex-start;border-bottom:3px solid #dc2626;padding-bottom:12px;margin-bottom:18px}
.hdr h1{margin:0;font-size:22px;color:#dc2626;letter-spacing:1px}
.hdr .num{font-size:14px;color:#4a5a52;margin-top:4px}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:24px;margin-bottom:18px}
.box{border:1px solid #d4e8e0;border-radius:6px;padding:12px;background:#f8fbfa}
.box h3{margin:0 0 8px;font-size:12px;color:#4a5a52;text-transform:uppercase;letter-spacing:1px}
.box p{margin:2px 0;font-size:13px}
table{width:100%;border-collapse:collapse;margin:12px 0}
th{text-align:left;padding:8px;background:#1a2e22;color:#fff;font-size:12px;text-transform:uppercase;letter-spacing:1px}
td{padding:10px 8px;border-bottom:1px solid #eef4f0;font-size:13px}
tr.total td{background:#fef2f2;font-weight:800;font-size:15px;color:#dc2626;border-bottom:none}
.note{margin-top:18px;padding:12px;background:#fef2f2;border-left:4px solid #dc2626;border-radius:4px;font-size:12px;line-height:1.6}
.foot{margin-top:24px;padding-top:12px;border-top:1px solid #d4e8e0;font-size:11px;color:#4a5a52;text-align:center}
</style></head><body>
<div class="hdr">
  <div>
    <h1>DOBROPIS</h1>
    <div class="num">Číslo: <strong>${opts.number}</strong></div>
    <div class="num">Datum vystavení: ${opts.issueDate}</div>
    ${opts.originalInvoiceNumber ? `<div class="num">K dokladu: ${opts.originalInvoiceNumber}</div>` : ''}
  </div>
  <div style="text-align:right">
    <div style="font-size:18px;font-weight:800">MotoGo24</div>
    <div style="color:#4a5a52">Bc. Petra Semorádová</div>
    <div style="color:#4a5a52">Mezná 9, 393 01 Pelhřimov</div>
    <div style="color:#4a5a52">IČO: 21874263</div>
  </div>
</div>
<div class="grid">
  <div class="box"><h3>Odběratel</h3>
    <p><strong>${c.full_name || '—'}</strong></p>
    ${c.company ? `<p>Firma: <strong>${c.company}</strong></p>` : ''}
    ${c.company_address ? `<p>Sídlo: ${c.company_address}</p>` : ''}
    ${c.street ? `<p>${c.street}</p>` : ''}
    ${(c.city || c.zip) ? `<p>${c.zip || ''} ${c.city || ''}</p>` : ''}
    ${c.ico ? `<p>IČO: ${c.ico}</p>` : ''}
    ${c.dic ? `<p>DIČ: ${c.dic}</p>` : ''}
    ${c.email ? `<p>${c.email}</p>` : ''}
    ${c.phone ? `<p>${c.phone}</p>` : ''}
  </div>
  <div class="box"><h3>Detaily refundu</h3>
    <p>Důvod: <strong>${opts.reasonText}</strong></p>
    <p>Rezervace: ${opts.motoModel}</p>
    <p>Termín: ${opts.bookingDates}</p>
    <p>Procento vrácení: <strong>${opts.refundPercent} %</strong></p>
    <p style="font-size:11px;color:#4a5a52;word-break:break-all">Stripe refund: ${opts.stripeRefundId}</p>
  </div>
</div>
<table>
  <thead><tr><th>Popis</th><th style="text-align:right">Částka</th></tr></thead>
  <tbody>
    <tr><td>Dobropis – ${opts.reasonText} (${opts.motoModel})</td><td style="text-align:right">−${fmtPrice(opts.refundAmount)} Kč</td></tr>
    <tr class="total"><td>K vrácení celkem</td><td style="text-align:right">−${fmtPrice(opts.refundAmount)} Kč</td></tr>
  </tbody>
</table>
<div class="note">
  <strong>${cardLine}</strong> Peníze obvykle dorazí do 5–7 pracovních dnů.<br>
  Tento dobropis slouží jako doklad o vrácení platby.
</div>
<div class="foot">www.motogo24.cz · info@motogo24.cz · +420 774 256 271</div>
</body></html>`
}

interface RefundRequest {
  booking_id?: string
  order_id?: string
  amount?: number      // partial refund in CZK (omit for full refund)
  reason?: string      // 'cancellation' | 'shortening' | 'duplicate' | 'requested_by_customer'
}

// Idempotent helper: for an already-refunded booking, locate the credit note,
// regenerate its PDF if the storage file is missing or pdf_path is empty.
// Returns { creditNoteId, pdfPath, refundId } so the caller can return success.
async function ensureCreditNotePdf(
  supabase: any,
  bookingId: string,
  bk: { stripe_refund_id?: string | null; card_brand?: string | null; card_last4?: string | null },
  /** i2: dobropis k TÉTO vratce (ne nejnovější dobropis rezervace) */
  opts: { refundId?: string | null } = {},
): Promise<{ creditNoteId: string | null; pdfPath: string | null; refundId: string | null }> {
  try {
    let q = supabase.from('invoices')
      .select('id, number, pdf_path, stripe_refund_id, total, original_invoice_id, notes, created_at')
      .eq('booking_id', bookingId)
      .eq('type', 'credit_note')
      .neq('status', 'cancelled')
    if (opts.refundId) q = q.eq('stripe_refund_id', opts.refundId)
    const { data: cnRows } = await q.order('created_at', { ascending: false }).limit(1)
    if (!cnRows?.length) return { creditNoteId: null, pdfPath: null, refundId: bk.stripe_refund_id || null }

    const cn = cnRows[0]
    const refundId = cn.stripe_refund_id || bk.stripe_refund_id || null
    if (cn.pdf_path) {
      // Verify file actually exists in storage; if missing, regenerate.
      try {
        const { data: blob } = await supabase.storage.from('documents').download(cn.pdf_path)
        if (blob && blob.size > 0) return { creditNoteId: cn.id, pdfPath: cn.pdf_path, refundId }
      } catch { /* file missing — fall through to regenerate */ }
    }

    // Regenerate PDF — load booking + customer for the template
    const { data: bk2 } = await supabase.from('bookings')
      .select('total_price, start_date, end_date, motorcycles!moto_id(model), profiles:user_id(id, full_name, email, phone, street, city, zip, ico, dic)')
      .eq('id', bookingId).single()
    const refundedAmount = Math.abs(Number(cn.total || 0))
    // Procento dopočítat z ceny rezervace — natvrdo 100 tisklo i u částečné
    // vratky „Procento vrácení: 100 %", takže přegenerovaný dobropis lhal.
    const bk2Total = Number((bk2 as any)?.total_price || 0)
    const refundPercent = bk2Total > 0
      ? Math.min(100, Math.round((refundedAmount / bk2Total) * 100))
      : 100
    const reasonText = (cn.notes || '').includes('Storno') ? 'Storno rezervace'
      : (cn.notes || '').includes('Zkrácení') ? 'Zkrácení rezervace'
      : 'Vrácení platby zákazníkovi'

    let originalNumber: string | null = null
    if (cn.original_invoice_id) {
      const { data: orig } = await supabase.from('invoices')
        .select('number').eq('id', cn.original_invoice_id).single()
      originalNumber = orig?.number || null
    }

    const cust1 = (bk2 as any)?.profiles || {}
    await loadCustomerCompany(supabase, cust1)
    const html = renderCreditNoteHtml({
      number: cn.number,
      issueDate: fmtDate(new Date().toISOString().slice(0, 10)),
      reasonText,
      // Výpůjčka výbavy (2026-10-23): bez motorky → „výpůjčka výbavy“ (gear) / „motorky“ (gear.ts).
      motoModel: (bk2 as any)?.motorcycles?.model || await noMotoRefundSubject(supabase, bookingId),
      refundAmount: refundedAmount,
      refundPercent,
      bookingDates: `${fmtDate(bk2?.start_date)} – ${fmtDate(bk2?.end_date)}`,
      customer: cust1,
      originalInvoiceNumber: originalNumber,
      stripeRefundId: refundId || '',
      cardBrand: bk.card_brand,
      cardLast4: bk.card_last4,
    })

    const pdfBytes = await htmlToPdf(html)
    let path: string
    if (pdfBytes) {
      path = `invoices/${cn.id}.pdf`
      await supabase.storage.from('documents').upload(
        path, new Blob([pdfBytes], { type: 'application/pdf' }),
        { upsert: true, contentType: 'application/pdf' },
      )
    } else {
      path = `invoices/${cn.id}.html`
      await supabase.storage.from('documents').upload(
        path, new Blob([html], { type: 'text/html' }),
        { upsert: true, contentType: 'text/html' },
      )
    }
    await supabase.from('invoices').update({ pdf_path: path }).eq('id', cn.id)
    return { creditNoteId: cn.id, pdfPath: path, refundId }
  } catch (e) {
    console.warn('[ensureCreditNotePdf] failed:', (e as Error).message)
    return { creditNoteId: null, pdfPath: null, refundId: bk.stripe_refund_id || null }
  }
}

// Safety-net: pro booking, kde Stripe refund proběhl (charge.refunded webhook fired,
// payment_status='refunded') ale credit_note v invoices NEexistuje (process-refund
// crashed po refunds.create() ale před INSERT). Vytvoří credit_note + PDF z dat,
// která dohledá ze Stripe API (refund.amount, refund.charge → card brand/last4).
// Volá se z process-refund's already_refunded branche, když ensureCreditNotePdf
// vrátí creditNoteId=null. Idempotentní (stripe_refund_id unique).
async function createCreditNoteForExistingRefund(
  supabase: any,
  bookingId: string,
  bk: { stripe_refund_id?: string | null; stripe_payment_intent_id?: string | null; total_price?: number | null },
): Promise<{ creditNoteId: string | null; pdfPath: string | null; refundId: string | null }> {
  if (!bk.stripe_refund_id) {
    return { creditNoteId: null, pdfPath: null, refundId: null }
  }
  try {
    // Idempotency: nemáme duplikát pro stejný refund.id
    const { data: dupe } = await supabase.from('invoices')
      .select('id, pdf_path').eq('stripe_refund_id', bk.stripe_refund_id).limit(1)
    if (dupe?.length) {
      return { creditNoteId: dupe[0].id, pdfPath: dupe[0].pdf_path, refundId: bk.stripe_refund_id }
    }

    // Načti Stripe refund + charge pro autoritní data (amount, card brand/last4)
    const refund = await stripe.refunds.retrieve(bk.stripe_refund_id)
    const rmd = ((refund.metadata || {}) as Record<string, string>)
    // Oprava f3: vratku rozdělenou mezi více plateb (hlavní + zbytek z ostatních plateb rezervace,
    // metadata mg_main_refund) započítat celou — dřív dobropis jen z hlavní vratky (podhodnocený).
    let restHaleru = 0
    if (rmd.mg_source === 'process-refund' && rmd.mg_part !== 'remainder') {
      const mainPi = typeof refund.payment_intent === 'string' ? refund.payment_intent : (refund.payment_intent as any)?.id || null
      restHaleru = await remainderForMainHaleru(stripe as unknown as OtherIntentsStripe, supabase, { bookingId, mainPi, mainRefundId: refund.id })
    }
    const refundedAmountCZK = ((refund.amount || 0) + restHaleru) / 100
    let cardBrand: string | null = null
    let cardLast4: string | null = null
    try {
      const chargeId = typeof refund.charge === 'string' ? refund.charge : (refund.charge as any)?.id
      if (chargeId) {
        const ch = await stripe.charges.retrieve(chargeId)
        cardBrand = ch?.payment_method_details?.card?.brand || null
        cardLast4 = ch?.payment_method_details?.card?.last4 || null
      }
    } catch { /* non-fatal */ }

    // Načti booking + customer pro template
    const { data: bkRow } = await supabase.from('bookings')
      .select('user_id, total_price, start_date, end_date, motorcycles!moto_id(model), profiles:user_id(id, full_name, email, phone, street, city, zip, ico, dic)')
      .eq('id', bookingId).single()
    if (!bkRow) return { creditNoteId: null, pdfPath: null, refundId: bk.stripe_refund_id }
    const refundPercent = (bkRow.total_price && bkRow.total_price > 0)
      ? Math.round((refundedAmountCZK / Number(bkRow.total_price)) * 100) : 100

    // Najít původní fakturu (payment_receipt / final / proforma) pro reference
    const { data: origInvs } = await supabase.from('invoices')
      .select('id, number')
      .eq('booking_id', bookingId)
      .neq('status', 'cancelled')
      .in('type', ['final', 'payment_receipt', 'advance', 'proforma'])
      .order('issue_date', { ascending: false }).limit(1)
    const originalInvoiceId = origInvs?.[0]?.id || null
    const originalInvoiceNumber = origInvs?.[0]?.number || null

    // Souběh s process-refund, které právě vystavuje dobropis k téže vratce (Stripe volání výše
    // trvají) → znovu ověřit těsně před vložením.
    const { data: dupe2 } = await supabase.from('invoices')
      .select('id, pdf_path').eq('stripe_refund_id', bk.stripe_refund_id).limit(1)
    if (dupe2?.length) {
      return { creditNoteId: dupe2[0].id, pdfPath: dupe2[0].pdf_path, refundId: bk.stripe_refund_id }
    }

    // Číslo dobropisu (DB-YYYY-NNNN) — atomicky, automatická řada < 5000.
    const cnNumber = await nextDocNumber(supabase, 'DB')
    const issueDate = new Date().toISOString().slice(0, 10)
    // Výpůjčka výbavy (2026-10-23): bez motorky → „výpůjčka výbavy“ (gear) / „motorky“ (gear.ts).
    const motoModel = (bkRow as any).motorcycles?.model || await noMotoRefundSubject(supabase, bookingId)
    // Důvod z naší vratky (zkrácení / výměna / úprava …); externí vratka (Stripe portál) = storno.
    const reasonText = rmd.mg_source === 'process-refund' && rmd.mg_reason ? reasonTextFor(rmd.mg_reason) : 'Storno rezervace'

    const { data: cnInv, error: cnInsErr } = await supabase.from('invoices').insert({
      number: cnNumber,
      type: 'credit_note',
      customer_id: bkRow.user_id,
      booking_id: bookingId,
      items: [{ description: `Dobropis – ${reasonText} (${motoModel})`, qty: 1, unit_price: -refundedAmountCZK }],
      subtotal: -refundedAmountCZK,
      tax_amount: 0,
      total: -refundedAmountCZK,
      notes: `Dobropis k rezervaci. ${refundPercent < 100 ? `Částečný refund ${refundPercent}%.` : 'Plný refund.'} ${reasonText} (recovery).`
        + (restHaleru > 0 ? ` Vráceno z více plateb: ${refund.id} + ${restHaleru / 100} Kč z dalších plateb rezervace.` : ''),
      issue_date: issueDate,
      due_date: issueDate,
      status: 'issued',
      source: 'refund',
      variable_symbol: cnNumber,
      original_invoice_id: originalInvoiceId,
      stripe_refund_id: bk.stripe_refund_id,
    }).select('id').single()
    if (!cnInv?.id && isUniqueViolation(cnInsErr)) {
      // Oprava i1 (2026-11-05): unikátní index (SQL návrh 20261105a) — dobropis k této vratce mezitím vystavil
      // souběžný process-refund → převzít.
      const { data: dupe3 } = await supabase.from('invoices')
        .select('id, pdf_path').eq('stripe_refund_id', bk.stripe_refund_id).neq('status', 'cancelled').limit(1)
      if (dupe3?.length) return { creditNoteId: dupe3[0].id, pdfPath: dupe3[0].pdf_path, refundId: bk.stripe_refund_id }
    }
    if (!cnInv?.id) return { creditNoteId: null, pdfPath: null, refundId: bk.stripe_refund_id }
    // Oprava i2 (2026-11-05): bez unikátního indexu mohl souběžný process-refund vložit dobropis k téže vratce
    // mezi naší kontrolou a INSERTem → ponechat jen nejstarší, náš zrušit (bez účetního záznamu).
    const dupe4 = await cancelDuplicateCreditNote(supabase, { cnId: cnInv.id, cnNumber, refundId: bk.stripe_refund_id, bookingId })
    if (dupe4) return { creditNoteId: dupe4.id, pdfPath: dupe4.pdf_path, refundId: bk.stripe_refund_id }

    // accounting_entries nemá sloupce vat_rate/source/entry_date — insert s nimi
    // tiše padal (chyba se zahazovala) a dobropis se nikdy nezaúčtoval
    await supabase.from('accounting_entries').insert({
      type: 'expense', amount: -refundedAmountCZK,
      description: `Dobropis ${cnNumber} - ${reasonText}`,
      category: 'refund',
      date: issueDate, booking_id: bookingId, invoice_id: cnInv.id,
    }).then(() => {}, () => {})

    const cust2 = (bkRow as any).profiles || {}
    await loadCustomerCompany(supabase, cust2)
    const html = renderCreditNoteHtml({
      number: cnNumber, issueDate: fmtDate(issueDate), reasonText, motoModel,
      refundAmount: refundedAmountCZK, refundPercent,
      bookingDates: `${fmtDate(bkRow.start_date)} – ${fmtDate(bkRow.end_date)}`,
      customer: cust2, originalInvoiceNumber,
      stripeRefundId: bk.stripe_refund_id, cardBrand, cardLast4,
    })
    const pdfBytes = await htmlToPdf(html)
    const path = pdfBytes ? `invoices/${cnInv.id}.pdf` : `invoices/${cnInv.id}.html`
    await supabase.storage.from('documents').upload(
      path,
      pdfBytes ? new Blob([pdfBytes], { type: 'application/pdf' }) : new Blob([html], { type: 'text/html' }),
      { upsert: true, contentType: pdfBytes ? 'application/pdf' : 'text/html' },
    )
    await supabase.from('invoices').update({ pdf_path: path }).eq('id', cnInv.id)
    return { creditNoteId: cnInv.id, pdfPath: path, refundId: bk.stripe_refund_id }
  } catch (e) {
    console.warn('[createCreditNoteForExistingRefund] failed:', (e as Error).message)
    return { creditNoteId: null, pdfPath: null, refundId: bk.stripe_refund_id || null }
  }
}

// Manuální vratka pro booking BEZ reálně zaplacené Stripe platby (QR/převod/
// hotově/ručně označená paid) — 2026-08-04 flow:
//  1. vystaví DOBROPIS (credit_note, stripe_refund_id NULL = manuální)
//     + účetní záznam — položkově, stejně jako Stripe větev,
//  2. rezervace → 'refund_pending' („Čeká na vrácení" ve Velíně; banner
//     „Vrátit X Kč na účet zákazníka" + akce „Vratka odeslána"/„Potvrdit vrácení"),
//  3. vrátí success + manual:true, aby volající (web/app/RPC/Velín) commit
//     dokončil a zákazníkovi ukázal „vrátíme do 14 dnů".
// Volá se ze dvou míst: a) booking nemá PI ani (zaplacenou) session,
// b) PI existuje, ale Stripe na něm nikdy nepřijal peníze (stale PI
//    z opuštěného pokusu o kartu — viz fix 2026-08-21 v serve handleru).
// ===== Fio API — automatické odeslání vratky převodem (parita se Stripe) =====
// Rezervace zaplacené QR / převodem na Fio účet se vrací AUTOMATICKY: platební
// příkaz se podá přes Fio API Bankovnictví (POST /v1/rest/import/, Fio XML
// DomesticTransaction — viz https://www.fio.cz/docs/cz/API_Bankovnictvi.pdf).
// Cílový účet = protiúčet příchozí platby z `fio_transactions` (plní fio-sync).
// Idempotence: UNIQUE(credit_note_id) v `fio_payment_orders` — jeden dobropis
// = maximálně JEDEN odeslaný příkaz, souběžný dispatch dostane konflikt.
// Když příkaz nejde odeslat (chybí token / protiúčet / platba nešla na Fio /
// banka odmítla), flow spadne na dosavadní ruční fallback (refund_pending +
// banner „VRÁTIT NA ÚČET" ve Velíně) — peníze se NIKDY nepošlou dvakrát ani
// naslepo. Token: FIO_PAYMENT_TOKEN (doporučený samostatný token s právem
// zadávání příkazů — vlastní 30s limit), fallback FIO_API_TOKEN.
const FIO_REFUND_TOKEN = Deno.env.get('FIO_PAYMENT_TOKEN') || Deno.env.get('FIO_API_TOKEN') || ''
const FIO_IMPORT_URL = 'https://fioapi.fio.cz/v1/rest/import/'
const OPS_EMAIL = 'info@motogo24.cz'

/** Atomicky přidělí další číslo dokladové řady (PREFIX-YYYY-NNNN).
 *
 *  Primárně přes RPC `next_document_number` — ta drží row-lock nad
 *  `document_number_counters`, takže dvě souběžné invokace nikdy nedostanou
 *  totéž číslo. Dřív se tu skládalo `MAX+1` read-then-write bez zámku; nad
 *  `invoices.number` je UNIQUE index, takže souběh nekončil duplicitou, ale
 *  SPADLÝM zápisem — a zákazníkovi doklad prostě nevznikl (viz DB-2026-0001 2×).
 *
 *  Fallback na původní MAX+1 zůstává jen pro případ, že RPC selže — ať
 *  výpadek číselníku nezablokuje fakturaci úplně.
 */
async function nextDocNumber(supabase: any, prefix: string): Promise<string> {
  try {
    const { data, error } = await supabase.rpc('next_document_number', { p_prefix: prefix })
    if (!error && typeof data === 'string' && /^[A-Z]{2}-\d{4}-\d{4}$/.test(data)) return data
    if (error) console.warn(`[doc-number] RPC next_document_number selhala (${error.message}) — fallback MAX+1`)
  } catch (e) {
    console.warn('[doc-number] RPC next_document_number nedostupná — fallback MAX+1:', (e as Error).message)
  }
  const year = new Date().getFullYear()
  const { data: last } = await supabase.from('invoices').select('number')
    .like('number', `${prefix}-${year}-%`).lt('number', `${prefix}-${year}-5000`)
    .order('number', { ascending: false }).limit(1)
  let seq = 1
  if (last?.length) { const m = last[0].number.match(/-(\d+)$/); if (m) seq = parseInt(m[1], 10) + 1 }
  return `${prefix}-${year}-${String(seq).padStart(4, '0')}`
}

const xmlEscape = (s: string) =>
  s.replace(/[<>&'"]/g, (c) => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', "'": '&apos;', '"': '&quot;' }[c] || c))

async function sendOpsMail(subject: string, html: string) {
  try {
    const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
    const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    await fetch(`${SUPABASE_URL}/functions/v1/send-email`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + SERVICE_KEY, apikey: SERVICE_KEY },
      body: JSON.stringify({ to: OPS_EMAIL, subject, raw_html: html }),
    })
  } catch (e) { console.warn('[process-refund] ops mail failed:', (e as Error).message) }
}

/** Mail obsluze nejvýš 1× za 10 min na rezervaci a akci (dedup přes debug_log) — oprava i1 2026-11-05:
 *  neúplný pool vratek storna / odložené dovrácení / nečitelné ostatní platby dřív skončily jen v debug_log,
 *  který Velín u plateb nezobrazuje. */
async function opsMailOnce(supabase: any, bookingId: string, action: string, subject: string, html: string,
  extra: Record<string, unknown> = {}): Promise<boolean> {
  try {
    const { data: prev } = await supabase.from('debug_log').select('id')
      .eq('source', 'process-refund').eq('action', action).eq('request_data->>booking_id', bookingId)
      .gte('created_at', new Date(Date.now() - 10 * 60_000).toISOString()).limit(1)
    if (prev?.length) return false
  } catch { /* bez dedupu */ }
  try {
    await supabase.from('debug_log').insert({ source: 'process-refund', action, status: 'error', request_data: { booking_id: bookingId, ...extra } })
  } catch { /* ignore */ }
  await sendOpsMail(subject, html)
  return true
}
const bookingNum = (id: string) => String(id).slice(-8).toUpperCase()
/** Oprava i4 (2026-11-07): skutečný postup vratky u NEzrušené rezervace (Velín ji z detailu rezervace vrátit neumí —
 *  „Potvrdit vrácení“ je jen u zrušených): vratka ve Stripe dashboardu (webhook stav dorovná), dobropis v Účetnictví. */
const STAFF_REFUND_HOWTO = 'Zkontrolujte platby; částku vraťte ve Stripe dashboardu (platba rezervace → Refund — stav rezervace se pak dorovná sám), '
  + 'dobropis vystavte ve Velíně (Finance → Dobropisy) a pošlete ho zákazníkovi e-mailem.'

async function tryFioRefund(
  supabase: any,
  booking_id: string,
  cnId: string | null,
  cnNumber: string | null,
  amount: number,
  reasonText: string,
  dlog: (action: string, status: string, extra?: Record<string, unknown>) => unknown,
): Promise<{ sent: boolean; instructionId?: string | null }> {
  if (!FIO_REFUND_TOKEN || !cnId || !(amount > 0)) return { sent: false }
  const bookingNumber = String(booking_id).slice(-8).toUpperCase()
  try {
    // 1) Zdrojový účet = účet tokenu. Bereme z company_info.bank_account a
    //    vyžadujeme kód banky 2010 (Fio) — dokud company_info míří na starý
    //    účet (mBank), automatická vratka se nepokouší (peníze tam nepřišly).
    const { data: ci } = await supabase.from('app_settings').select('value').eq('key', 'company_info').maybeSingle()
    const bankAccount = String((ci?.value as any)?.bank_account || '').replace(/\s+/g, '')
    const accMatch = bankAccount.match(/^(?:(\d{1,6})-)?(\d{2,10})\/(\d{4})$/)
    if (!accMatch || accMatch[3] !== '2010') {
      await dlog('fio_refund_skipped_not_fio_account', 'info', { bank_account: bankAccount })
      return { sent: false }
    }
    const accountFrom = accMatch[1] ? `${accMatch[1]}-${accMatch[2]}` : accMatch[2]

    // 2) Cílový účet = protiúčet PŘÍCHOZÍ platby této rezervace (fio_transactions
    //    plní fio-sync). Primárně dle booking_id (spárované auto-potvrzení),
    //    fallback dle VS (platba zaevidovaná, ale potvrzená ručně).
    const { data: bk } = await supabase.from('bookings')
      .select('payment_vs, mod_surcharge_vs').eq('id', booking_id).maybeSingle()
    let src: { counter_account: string | null; counter_bank: string | null } | null = null
    const { data: byBooking } = await supabase.from('fio_transactions')
      .select('counter_account, counter_bank').eq('booking_id', booking_id)
      .gt('amount', 0).not('counter_account', 'is', null)
      .order('fio_id', { ascending: false }).limit(1)
    src = byBooking?.[0] || null
    if (!src) {
      const vses = [bk?.payment_vs, bk?.mod_surcharge_vs].filter(Boolean).map(String)
      if (vses.length > 0) {
        const { data: byVs } = await supabase.from('fio_transactions')
          .select('counter_account, counter_bank').in('vs', vses)
          .gt('amount', 0).not('counter_account', 'is', null)
          .order('fio_id', { ascending: false }).limit(1)
        src = byVs?.[0] || null
      }
    }
    if (!src?.counter_account || !src?.counter_bank) {
      await dlog('fio_refund_no_source_account', 'info', { note: 'platba rezervace nedohledána ve fio_transactions — ruční vratka' })
      return { sent: false }
    }

    // 3) Idempotentní claim: UNIQUE(credit_note_id). Konflikt = příkaz už
    //    vznikl dřív — submitted vrátíme jako hotovo, cokoli jiného necháme
    //    na ručním fallbacku (žádné opakované odeslání peněz).
    const vsOut = String(bk?.payment_vs || cnNumber || '').replace(/\D/g, '').slice(0, 10) || null
    const msg = `MotoGo24 vratka ${bookingNumber} - ${reasonText}`.slice(0, 140)
    const { data: claim } = await supabase.from('fio_payment_orders')
      .upsert({
        credit_note_id: cnId, booking_id, amount,
        account_to: src.counter_account, bank_code: src.counter_bank,
        vs: vsOut, message: msg, status: 'pending',
      }, { onConflict: 'credit_note_id', ignoreDuplicates: true })
      .select('id').maybeSingle()
    if (!claim?.id) {
      const { data: prev } = await supabase.from('fio_payment_orders')
        .select('status, fio_instruction_id').eq('credit_note_id', cnId).maybeSingle()
      await dlog('fio_refund_claim_conflict', 'info', { prev_status: prev?.status || null })
      return prev?.status === 'submitted'
        ? { sent: true, instructionId: prev?.fio_instruction_id || null }
        : { sent: false }
    }

    // 4) Fio XML tuzemský příkaz (pořadí elementů dle importIB.xsd).
    const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'Europe/Prague' })
    const xml = `<?xml version="1.0" encoding="UTF-8"?>
<Import xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.fio.cz/schema/importIB.xsd">
<Orders>
<DomesticTransaction>
<accountFrom>${xmlEscape(accountFrom)}</accountFrom>
<currency>CZK</currency>
<amount>${amount.toFixed(2)}</amount>
<accountTo>${xmlEscape(String(src.counter_account))}</accountTo>
<bankCode>${xmlEscape(String(src.counter_bank))}</bankCode>
${vsOut ? `<vs>${vsOut}</vs>\n` : ''}<date>${today}</date>
<messageForRecipient>${xmlEscape(msg)}</messageForRecipient>
<comment>${xmlEscape('Dobropis ' + (cnNumber || ''))}</comment>
<paymentType>431001</paymentType>
</DomesticTransaction>
</Orders>
</Import>`

    // 5) Upload (multipart/form-data). 409 = 30s interval tokenu (sdílený se
    //    sync cronem) → jednou počkej a zopakuj.
    const submit = async () => {
      const fd = new FormData()
      fd.append('type', 'xml')
      fd.append('token', FIO_REFUND_TOKEN)
      fd.append('file', new Blob([xml], { type: 'application/xml' }), 'vratka.xml')
      return await fetch(FIO_IMPORT_URL, { method: 'POST', body: fd })
    }
    let resp = await submit()
    if (resp.status === 409) {
      await new Promise((r) => setTimeout(r, 31_000))
      resp = await submit()
    }
    const text = await resp.text()
    const errorCode = Number((text.match(/<errorCode>(\d+)<\/errorCode>/) || [])[1] ?? NaN)
    const instructionId = (text.match(/<idInstruction>(\d+)<\/idInstruction>/) || [])[1] || null
    // errorCode 0 = přijato, 2 = varování kontrol (příkazy s warning banka přijala)
    const ok = resp.ok && (errorCode === 0 || errorCode === 2)

    await supabase.from('fio_payment_orders').update({
      status: ok ? 'submitted' : 'failed',
      fio_instruction_id: instructionId,
      error: ok ? null : `HTTP ${resp.status}, errorCode ${Number.isNaN(errorCode) ? '?' : errorCode}: ${text.slice(0, 400)}`,
      submitted_at: ok ? new Date().toISOString() : null,
    }).eq('id', claim.id)
    await dlog(ok ? 'fio_refund_submitted' : 'fio_refund_failed', ok ? 'ok' : 'error', {
      amount, account_to: src.counter_account + '/' + src.counter_bank,
      fio_instruction_id: instructionId, http_status: resp.status,
      error_code: Number.isNaN(errorCode) ? null : errorCode,
      ...(ok ? {} : { response: text.slice(0, 400) }),
    })

    if (ok) {
      await sendOpsMail(
        `✅ Fio: vratka ${amount.toLocaleString('cs-CZ')} Kč odeslána (rez. #${bookingNumber}, dávka ${instructionId || '—'})`,
        `<h2 style="margin:0 0 8px;font-size:18px;color:#0f1a14">✅ Vratka odeslána automaticky přes Fio API</h2>
         <p style="margin:0 0 12px;color:#374151;font-size:14px">Vratka <strong>${amount.toLocaleString('cs-CZ')} Kč</strong> (${reasonText.toLowerCase()}, dobropis ${cnNumber || '—'}) k rezervaci <strong>#${bookingNumber}</strong> byla podána jako platební příkaz na účet <strong>${src.counter_account}/${src.counter_bank}</strong>, VS ${vsOut || '—'}, dávka č. ${instructionId || '—'}${errorCode === 2 ? ' (přijato s varováním kontrol)' : ''}.</p>
         <p style="margin:0;color:#b45309;font-size:13px">Pokud má účet nastavenou dodatečnou autorizaci API dávek, potvrďte dávku v internetbankingu — bez toho banka příkaz nezpracuje.</p>`
      )
    } else {
      await sendOpsMail(
        `⚠️ Fio: vratku ${amount.toLocaleString('cs-CZ')} Kč se NEPODAŘILO odeslat (rez. #${bookingNumber})`,
        `<h2 style="margin:0 0 8px;font-size:18px;color:#0f1a14">⚠️ Automatická vratka přes Fio selhala — pošlete ručně</h2>
         <p style="margin:0 0 12px;color:#374151;font-size:14px">Platební příkaz na <strong>${amount.toLocaleString('cs-CZ')} Kč</strong> (dobropis ${cnNumber || '—'}, rezervace <strong>#${bookingNumber}</strong>, účet ${src.counter_account}/${src.counter_bank}) banka nepřijala. Rezervace zůstává ve stavu „Čeká na vrácení" — pošlete vratku ručně převodem a potvrďte ve Velíně tlačítkem „Vratka odeslána".</p>
         <p style="margin:0;color:#6b7280;font-size:12px">Detail chyby: HTTP ${resp.status}, errorCode ${Number.isNaN(errorCode) ? '?' : errorCode}. Viz debug log (fio_refund_failed).</p>`
      )
    }
    return ok ? { sent: true, instructionId } : { sent: false }
  } catch (e) {
    await dlog('fio_refund_exception', 'error', { error: (e as Error).message })
    return { sent: false }
  }
}

// ── Strop ZÁKAZNICKÉ vratky (2026-10-11) ─────────────────────────────────────
// Zákazník (appka) smí dostat zpět jen PŘEPLATEK: co rezervace reálně zaplatila,
// minus co se už vrátilo, minus její AKTUÁLNÍ total_price (appka nižší cenu zapíše
// dřív, než refund zavolá — reservation_edit_screen). Stripe: customerCapHaleru
// (other-intents.ts — od opravy f2 2026-10-22 jen platby V CENĚ rezervace, tentýž
// výběr, ze kterého hlavní vratka i zbytek vrací). Převod / QR: níže.

/** Převod / QR: příchozí platby rezervace (fio_transactions dle booking_id nebo VS)
 *  − ruční dobropisy − total_price; Kč. Chyba = 0 (fail closed → vyřídí obsluha). */
async function customerManualCapCzk(supabase: any, bookingId: string, totalPrice: number): Promise<number> {
  try {
    const { data: bk } = await supabase.from('bookings')
      .select('payment_vs, mod_surcharge_vs').eq('id', bookingId).maybeSingle()
    const rows = new Map<string, number>()
    const { data: byId, error: e1 } = await supabase.from('fio_transactions')
      .select('fio_id, amount').eq('booking_id', bookingId).gt('amount', 0)
    if (e1) return 0
    for (const r of byId || []) rows.set(String(r.fio_id), Number(r.amount) || 0)
    const vses = [bk?.payment_vs, bk?.mod_surcharge_vs].filter(Boolean).map(String)
    if (vses.length) {
      const { data: byVs } = await supabase.from('fio_transactions')
        .select('fio_id, amount').in('vs', vses).gt('amount', 0)
      for (const r of byVs || []) rows.set(String(r.fio_id), Number(r.amount) || 0)
    }
    const paid = [...rows.values()].reduce((s, v) => s + v, 0)
    const { data: cns, error: e2 } = await supabase.from('invoices').select('total')
      .eq('booking_id', bookingId).eq('type', 'credit_note').neq('status', 'cancelled')
      .is('stripe_refund_id', null)
    if (e2) return 0
    const refunded = (cns || []).reduce((s: number, c: any) => s + Math.abs(Number(c.total) || 0), 0)
    return Math.max(0, Math.round((paid - refunded - (Number(totalPrice) || 0)) * 100) / 100)
  } catch { return 0 }
}

/** Spodní věrohodná mez ceny rezervace (Kč) ze serverového ceníku; null = nelze ověřit. */
async function customerPriceFloorCzk(supabase: any, bookingId: string): Promise<number | null> {
  try {
    const { data: bk } = await supabase.from('bookings')
      .select('moto_id, start_date, end_date').eq('id', bookingId).maybeSingle()
    // Výpůjčka výbavy (2026-10-23): mez z ceny výbavy × dny (gear.ts) — bez motorky dřív null = vždy obsluha.
    const gearBk = bk && !bk.moto_id ? await loadGearRefundRow(supabase, bookingId) : null
    if (gearBk) return await gearPriceFloorCzk(supabase, gearBk, bookingId)
    if (!bk?.moto_id || !bk?.start_date || !bk?.end_date) return null
    const s = String(bk.start_date).slice(0, 10), e = String(bk.end_date).slice(0, 10)
    const { data: sum, error } = await supabase.rpc('_moto_dayprice_sum', { p_moto_id: bk.moto_id, p_start: s, p_end: e })
    if (error) return null
    const { data: m } = await supabase.from('motorcycles')
      .select('price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun').eq('id', bk.moto_id).maybeSingle()
    const maxDay = Math.max(0, ...Object.values(m || {}).map((v) => Number(v) || 0))
    const { data: disc } = await supabase.from('booking_discounts').select('amount').eq('booking_id', bookingId)
    const discounts = (disc || []).reduce((t: number, d: any) => t + Math.max(0, Number(d.amount) || 0), 0)
    return Math.max(0, Math.floor(0.8 * (Number(sum) || 0) - 0.5 * maxDay - discounts))
  } catch { return null }
}

/** Zákaznická vratka bez ověřeného přeplatku → nic se nevrací, stav se nemění,
 *  obsluha dostane mail (max 1× za 10 min na rezervaci). HTTP 200 + success:false,
 *  aby appka (functions.invoke hází na ne-2xx) ukázala srozumitelný text. */
async function customerRefundNeedsStaff(
  supabase: any, bookingId: string, amount: unknown, reason: string | undefined,
  dlog: (action: string, status: string, extra?: Record<string, unknown>) => unknown,
): Promise<Response> {
  let recent = false
  try {
    const { data: prev } = await supabase.from('debug_log').select('id')
      .eq('source', 'process-refund').eq('action', 'customer_refund_needs_staff')
      .eq('request_data->>booking_id', bookingId)
      .gte('created_at', new Date(Date.now() - 10 * 60_000).toISOString()).limit(1)
    recent = !!prev?.length
  } catch { /* bez dedupu */ }
  await dlog('customer_refund_needs_staff', 'info', { requested: amount ?? null })
  if (!recent) {
    const num = String(bookingId).slice(-8).toUpperCase()
    const amt = (Number(amount) || 0).toLocaleString('cs-CZ')
    await sendOpsMail(
      `⚠️ Vratku za úpravu rezervace #${num} vyřiďte ručně`,
      `<p>Zákazník v aplikaci upravil rezervaci <strong>#${num}</strong> (${reasonTextFor(reason)}) a požádal o vrácení <strong>${amt} Kč</strong>.</p>`
      + '<p>Automatická vratka NEPROBĚHLA — k rezervaci se nenašel ověřený přeplatek (platby Stripe / Fio − vrácené − aktuální cena). '
      + `${STAFF_REFUND_HOWTO}</p>`,
    )
  }
  return new Response(
    // D5: bez „ozveme se“ (nic to neautomatizuje); 4.1.3 text zobrazí doslova. i4 (2026-11-07): bez slibu „potvrzení a dobropis
    // přijdou e-mailem“ — vratku obsluha dělá ve Stripe dashboardu a mail zákazníkovi nic automaticky neposílá.
    JSON.stringify({ success: false, code: 'refund_needs_staff', error: 'Změna je uložená. Vratku dokončí obsluha do 2 pracovních dnů – nemusíš nic dělat; vrácenou částku pak uvidíš v detailu rezervace.' }),
    { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
  )
}

/** Porušení unikátního indexu (PostgREST / PostgreSQL 23505) — dobropis k téže vratce už existuje. */
function isUniqueViolation(e: { code?: string | null; message?: string | null } | null | undefined): boolean {
  return !!e && (String(e.code || '') === '23505' || /duplicate key|uq_invoices_credit_note_refund/i.test(String(e.message || '')))
}

/** Oprava i2 (2026-11-05): živé dobropisy k téže Stripe vratce bez unikátního indexu (SQL návrh 20261105a ještě
 *  nenasazen) — dva souběžné dispatche téže vratky (fronta appky / dvojí klepnutí / pg_net + retry) prošly oba
 *  kontrolou „dobropis existuje?“ a vložily dva dobropisy + dva účetní záznamy k JEDNÉ vratce (Stripe ji sloučil
 *  idempotency klíčem). Po INSERTu se načtou všechny živé dobropisy k vratce (nejstarší první: created_at, id);
 *  není-li náš první, zruší se (status 'cancelled', číslo řady propadne — zalogováno) a vrátí se ten první. */
async function cancelDuplicateCreditNote(supabase: any, a: { cnId: string; cnNumber: string | null; refundId: string; bookingId: string }):
  Promise<{ id: string; number: string | null; pdf_path: string | null } | null> {
  try {
    const { data: same } = await supabase.from('invoices').select('id, number, pdf_path, created_at')
      .eq('type', 'credit_note').eq('stripe_refund_id', a.refundId).neq('status', 'cancelled')
      .order('created_at', { ascending: true }).order('id', { ascending: true })
    if (!Array.isArray(same) || same.length < 2 || same[0].id === a.cnId) return null
    const first = same[0]
    await supabase.from('invoices').update({ status: 'cancelled',
      notes: `Zrušeno automaticky: duplicitní dobropis k vratce ${a.refundId} (platí ${first.number || first.id}).` }).eq('id', a.cnId)
    try {
      await supabase.from('debug_log').insert({ source: 'process-refund', action: 'credit_note_duplicate_cancelled', status: 'warning',
        request_data: { booking_id: a.bookingId, refund_id: a.refundId, cancelled_credit_note_id: a.cnId, lost_number: a.cnNumber,
          kept_credit_note_id: first.id, kept_number: first.number } })
    } catch { /* ignore */ }
    return { id: first.id, number: first.number || null, pdf_path: first.pdf_path || null }
  } catch { return null }
}

/** Oprava i2 (2026-11-05): čerstvý dobropis na STEJNOU částku (≤15 min) = duplicitní dispatch téže vratky JEN když
 *  už zákazníkovi nic nedlužíme. Dvě zkrácení po sobě o stejnou částku (appka edit_shortening, web shortening,
 *  dvě odebrané položky výbavy za stejnou cenu, Velín) mají po druhém snížení ceny ověřený přeplatek ≥ částka →
 *  druhá vratka je po právu (dřív tiše přeskočena s odpovědí „success“). Ověřený přeplatek jako customerCapHaleru
 *  (Σ platby Stripe v ceně − vrácené − total_price), u ručně placených customerManualCapCzk; null = nelze ověřit. */
async function verifiedOverpaymentHaleru(supabase: any, bookingId: string, data: any, totalPrice: number): Promise<number | null> {
  if (isManualPayment(data)) return Math.round((await customerManualCapCzk(supabase, bookingId, totalPrice)) * 100)
  const ois = stripe as unknown as OtherIntentsStripe
  let storedPi: any = null, storedRefunds: any[] | null = null
  if (data.stripe_payment_intent_id) {
    try {
      storedPi = await stripe.paymentIntents.retrieve(data.stripe_payment_intent_id)
      storedRefunds = (await stripe.refunds.list({ payment_intent: data.stripe_payment_intent_id, limit: 100 })).data
    } catch (e) { console.warn('[process-refund] overpayment: stored PI lookup failed:', (e as Error).message); return null }
  }
  return await customerCapHaleru(ois, supabase, { bookingId, storedPi, storedRefunds, totalPrice })
}

/** Oprava i2 (2026-11-05): část ceny KARTOVÉ rezervace zaplacená mimo Stripe (doplatek úpravy převodem / QR —
 *  mod_surcharge_vs, fio_transactions) → plné storno z Velínu (bez částky) vracelo jen zůstatek Stripe a zapsalo
 *  'refunded'; převodem zaplacená část se nevrátila nikdy a nikdo se to nedozvěděl.
 *  Oprava i3 (2026-11-07, V1 / V36): mezera = (Σ DP − Σ dobropisů — jako _cap_refund_to_paid; i2 bral total_price −
 *  Σ dobropisů a snížení ceny s dobropisem odečetl dvakrát) − zůstatek Stripe − vratky Stripe bez dobropisu (dashboard /
 *  spadlý dobropis: peníze už odešly). Automaticky jen do doložených plateb převodem (fio_transactions − ruční
 *  dobropisy); bez nich (jen mod_surcharge_paid_at — hotově / jinak ručně) žádný dobropis ani Fio, mail obsluze.
 *  Vrací haléře k ručnímu dobropisu; 0 = nic. */
async function nonStripeOwedHaleru(supabase: any, bookingId: string, stripeBalanceH: number,
  dlog: (action: string, status: string, extra?: Record<string, unknown>) => unknown,
  stored: { piId: string | null; refunds: any[] | null }, totalPrice = 0): Promise<number> {
  const num = bookingNum(bookingId)
  const staffMail = (action: string, gapH: number, why: string) => opsMailOnce(supabase, bookingId, action,
    `⚠️ Storno #${num}: ${gapH / 100} Kč dle dokladů nejde vrátit automaticky — zkontrolujte`,
    `<p>Rezervace <strong>#${num}</strong> (${bookingId}): dle dokladů (DP − dobropisy) rezervaci dlužíme o <strong>${gapH / 100} Kč</strong> víc, `
    + `než zbývá na platbách kartou (Stripe ${stripeBalanceH / 100} Kč). ${why}</p>`
    + '<p>Automaticky se tato část NEvrátila. Ověřte, jak byla zaplacena, a případně ji vraťte ručně ve Velíně (storno: „Potvrdit vrácení“ / dobropis).</p>',
    { gap_haleru: gapH, stripe_balance_haleru: stripeBalanceH, why })
  try {
    const docs = await docSums(supabase, bookingId)
    const owed = docsOwedCzk(docs)
    if (owed == null) {
      // Bez DP nelze dle dokladů nic ověřit → automaticky nic (jen Stripe); je-li doložená platba převodem a cena
      // převyšuje zůstatek Stripe, ať o tom obsluha ví.
      await dlog('full_refund_docs_no_dp', 'info', { stripe_balance_haleru: stripeBalanceH })
      const legacyGapH = Math.round((Number(totalPrice) || 0) * 100) - Math.round(docs.cnCzk * 100) - Math.max(0, stripeBalanceH)
      if (legacyGapH > 100) {
        const bank = await bankPaidCzk(supabase, bookingId).catch(() => null)
        if (bank && (bank.rows || bank.modSurchargePaidAt)) {
          await staffMail('full_refund_non_stripe_no_dp_mail', legacyGapH, 'Rezervace nemá žádný doklad o platbě (DP), takže část zaplacenou mimo kartu nejde ověřit dle dokladů.')
        }
      }
      return 0
    }
    const docH = Math.round(owed * 100)
    if (docH - Math.max(0, stripeBalanceH) <= 100) return 0
    const pool = await cancellationRefundPool(stripe as unknown as OtherIntentsStripe, supabase, {
      bookingId, storedPiId: stored.piId, storedRefunds: stored.refunds as unknown as StripeRefundLike[] | null })
    if (!pool.complete) {
      await dlog('full_refund_non_stripe_unverified', 'error', { docs_owed_haleru: docH, stripe_balance_haleru: stripeBalanceH, error: pool.error })
      await staffMail('full_refund_non_stripe_unverified_mail', docH - Math.max(0, stripeBalanceH), 'Vratky ve Stripe se nepodařilo načíst úplně, takže nejde ověřit, zda část už neodešla.')
      return 0
    }
    const noCnH = stripeRefundsWithoutCnHaleru(pool.refunds, docs.stripeCnCzk)
    const gapH = docH - Math.max(0, stripeBalanceH) - noCnH
    if (gapH <= 100) {
      if (noCnH > 0) await dlog('full_refund_docs_gap_stripe_without_cn', 'info', { docs_owed_haleru: docH, stripe_balance_haleru: stripeBalanceH, stripe_without_cn_haleru: noCnH })
      return 0
    }
    const bank = await bankPaidCzk(supabase, bookingId)
    if (!bank.rows) {
      await dlog(bank.modSurchargePaidAt ? 'full_refund_non_stripe_no_bank_evidence' : 'full_refund_docs_gap_unexplained', 'warning', {
        docs_owed_haleru: docH, stripe_balance_haleru: stripeBalanceH, stripe_without_cn_haleru: noCnH, gap_haleru: gapH, mod_surcharge_paid_at: bank.modSurchargePaidAt })
      if (bank.modSurchargePaidAt) {
        await staffMail('full_refund_non_stripe_no_bank_mail', gapH, 'Doplatek je označený jako zaplacený (mod_surcharge_paid_at), ale příchozí platba převodem k rezervaci není (hotově / jinak ručně?).')
      }
      return 0
    }
    const bankH = Math.max(0, Math.round((bank.czk - docs.manualCnCzk) * 100))
    const part = Math.min(gapH, bankH)
    await dlog('full_refund_non_stripe_part', 'info', { docs_owed_haleru: docH, stripe_balance_haleru: stripeBalanceH, stripe_without_cn_haleru: noCnH,
      gap_haleru: gapH, bank_paid_czk: bank.czk, manual_cn_czk: docs.manualCnCzk, non_stripe_haleru: part, mod_surcharge_paid_at: bank.modSurchargePaidAt })
    if (gapH - part > 100) {
      await staffMail('full_refund_non_stripe_capped_bank_mail', gapH - part,
        `Doložené platby převodem (${bank.czk} Kč − ruční dobropisy ${docs.manualCnCzk} Kč) kryjí jen ${part / 100} Kč — ty se vrací automaticky.`)
    }
    return part > 100 ? part : 0
  } catch (e) {
    await dlog('full_refund_non_stripe_check_failed', 'error', { error: (e as Error).message })
    return 0
  }
}

/** Oprava i1 (2026-11-05): ostatní platby rezervace nejdou přečíst (limit Stripe search / výpadek) → vratka obsluhy /
 *  služby se NEprovede jen z uložené platby (doplatek) ani neskončí no_op → 'refunded'. HTTP 500 (Velín ukáže chybu,
 *  send-cancellation-email zaloguje refund_call_failed a mail zákazníkovi vratku neslibuje), mail obsluze (dedup 10 min). */
async function otherPaymentsUnavailable(
  supabase: any, bookingId: string, amount: unknown, reason: string | undefined,
  dlog: (action: string, status: string, extra?: Record<string, unknown>) => unknown, where: string,
): Promise<Response> {
  await dlog('other_payments_unavailable', 'error', { where, requested: amount ?? null })
  const num = bookingNum(bookingId)
  await opsMailOnce(supabase, bookingId, 'other_payments_unavailable_mail',
    `⚠️ Vratka rezervace #${num} se neprovedla — platby ve Stripe nejdou načíst`,
    `<p>Rezervace <strong>#${num}</strong> (${bookingId}, ${reasonTextFor(reason)}${Number(amount) > 0 ? `, ${Number(amount)} Kč` : ', celý zůstatek'}): `
    + 'ostatní platby rezervace se nepodařilo načíst ze Stripe (limit vyhledávání / výpadek), takže nejde ověřit, z čeho a kolik vracet.</p>'
    + '<p>Nic se nevrátilo. Zkuste vratku znovu z detailu rezervace ve Velíně (storno: „Potvrdit vrácení“), až Stripe odpoví.</p>',
    { where, requested: amount ?? null })
  return new Response(
    JSON.stringify({ success: false, code: 'other_payments_unavailable', retry: true,
      error: 'Platby rezervace ve Stripe teď nejdou načíst — vratka se neprovedla, zkuste to znovu za chvíli.' }),
    { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } }
  )
}

/** Oprava i1 (2026-11-05): storno má nevrácený zbytek a zámek drží jiné (možná zabité) volání → obsluze (dedup 10 min). */
async function deferredCancelMail(supabase: any, bookingId: string, a: { refundId: string; targetHaleru: number; refundedHaleru: number }): Promise<void> {
  const num = bookingNum(bookingId)
  await opsMailOnce(supabase, bookingId, 'cancellation_remainder_deferred_mail',
    `⚠️ Storno #${num}: vráceno ${a.refundedHaleru / 100} Kč z ${a.targetHaleru / 100} Kč — zbytek zkontrolujte`,
    `<p>Rezervace <strong>#${num}</strong> (${bookingId}): storno vratka <code>${a.refundId}</code> zatím vrátila <strong>${a.refundedHaleru / 100} Kč</strong> `
    + `z požadovaných <strong>${a.targetHaleru / 100} Kč</strong> a dokončení zbytku z dalších plateb drží jiné volání (zámek storna).</p>`
    + '<p>Pokud se zbytek do pár minut nevrátí sám (opakované volání / webhook Stripe), zkontrolujte vratky ve Stripe a zbytek potvrďte ve Velíně („Potvrdit vrácení“).</p>',
    a as unknown as Record<string, unknown>)
}

async function manualBookingRefund(
  supabase: any,
  booking_id: string,
  amount: number | undefined,
  reason: string | undefined,
  dlog: (action: string, status: string, extra?: Record<string, unknown>) => unknown,
  customerCap = false,
): Promise<Response> {
  const { data: bkFull } = await supabase.from('bookings')
    .select('user_id, total_price, start_date, end_date, motorcycles!moto_id(model), profiles:user_id(id, full_name, email, phone, street, city, zip, ico, dic)')
    .eq('id', booking_id).single()
  const totalPrice = Number(bkFull?.total_price || 0)
  let manAmount = Number(amount) > 0 ? Number(amount) : totalPrice
  // Oprava i2 (2026-11-05): strop = co dle dokladů ještě dlužíme; plný požadavek obsluhy (bez částky) = nejvýš tento
  // zbytek. Dřív jen total_price: po ruční vratce 500 „Potvrdit vrácení“ 100 % vystavilo druhý dobropis (trigger ho
  // ořízl na 2 500, kód to nečetl) a Fio příkaz i odpověď nesly nekrácených 3 000 → přeplatek 500 Kč.
  // Oprava i3 (2026-11-07, V1): dlužná částka PŘESNĚ jako DB trigger _cap_refund_to_paid (Σ DP − Σ dobropisů, doc-owed.ts) —
  // i2 bral total_price − Σ dobropisů a snížení ceny s dobropisem (zkrácení / úprava výbavy) odečetl dvakrát (QR 3000,
  // zkrácení 500, storno 100 % → jen 2000). Bez DP / nečitelné doklady → strop total_price jako před i2. Oříznutý
  // požadavek s částkou → mail obsluze (dřív jen info v debug_log).
  {
    let owedDocs: number | null = null
    try { owedDocs = docsOwedCzk(await docSums(supabase, booking_id)) }
    catch (e) { await dlog('manual_refund_docs_unreadable', 'error', { error: (e as Error).message }) }
    const cap = owedDocs ?? (totalPrice > 0 ? totalPrice : null)
    if (cap != null && manAmount > cap + 0.005) {
      await dlog('manual_refund_capped_docs', 'info', { requested: manAmount, docs_owed: owedDocs, cap })
      if (Number(amount) > 0 && !customerCap) {
        const num = bookingNum(booking_id)
        await opsMailOnce(supabase, booking_id, 'manual_refund_capped_docs_mail',
          `⚠️ Ruční vratka #${num} oříznuta na ${cap} Kč (požadováno ${manAmount} Kč)`,
          `<p>Rezervace <strong>#${num}</strong> (${booking_id}, ${reasonTextFor(reason)}): požadovaná vratka <strong>${manAmount} Kč</strong> převyšuje, `
          + `co dle dokladů ještě dlužíme (${owedDocs != null ? 'DP − dobropisy' : 'cena rezervace'} = <strong>${cap} Kč</strong>). Dobropis se vystaví jen na ${cap} Kč.</p>`
          + '<p>Pokud zákazník zaplatil víc, než ukazují doklady (chybí DP), doplňte doklad a zbytek vraťte ručně ve Velíně.</p>',
          { requested: manAmount, cap, docs_owed: owedDocs })
      }
      manAmount = cap
    }
  }
  const requestedCzk = Number(amount) > 0 ? Number(amount) : 0
  // Oprava i2 (2026-11-05): čerstvý ruční dobropis na STEJNOU částku (≤15 min) = duplicitní dispatch téže vratky
  // (pg_net z RPC + retry v send-booking-email, dvojí klepnutí) JEN když zákazníkovi už nic nedlužíme (ověřený
  // přeplatek z příchozích plateb < částka). Dvě zkrácení / dvě odebrané položky výbavy za stejnou cenu po sobě mají
  // po druhém snížení ceny přeplatek ≥ částka → druhý dobropis je po právu (dřív tiše přeskočen jako „už vystaveno“).
  let owedCzk: number | null = null
  const owed = async () => owedCzk ?? (owedCzk = await customerManualCapCzk(supabase, booking_id, totalPrice))
  let freshManCn: Array<{ id: string; number: string | null; pdf_path: string | null; total: number }> | null = null
  if (manAmount > 0) {
    const { data } = await supabase.from('invoices')
      .select('id, number, pdf_path, total')
      .eq('booking_id', booking_id).eq('type', 'credit_note').neq('status', 'cancelled')
      .is('stripe_refund_id', null)
      .eq('total', -manAmount)
      .gte('created_at', new Date(Date.now() - 15 * 60_000).toISOString())
      .order('created_at', { ascending: false }).limit(1)
    freshManCn = data?.length ? data : null
    if (freshManCn && (await owed()) + 0.005 >= manAmount) {
      await dlog('manual_refund_dedup_skipped_owed', 'info', { credit_note_id: freshManCn[0].id, amount: manAmount, owed: owedCzk })
      freshManCn = null
    }
  }
  // Zákazník (appka): jen ověřený přeplatek z příchozích plateb (strop výše); duplicitní dispatch (čerstvý
  // dobropis a nic nedlužíme) strop přeskočí — vrátí se existující dobropis níže (žádná druhá vratka).
  if (customerCap && manAmount > 0 && !freshManCn) {
    const capCzk = await owed()
    if (manAmount > capCzk) manAmount = capCzk
    if (!(manAmount > 0)) return await customerRefundNeedsStaff(supabase, booking_id, amount, reason, dlog)
  }
  // f2: zákazníkovi se vrací méně, než požadoval (strop ověřeného přeplatku; zbytek nad 1 Kč —
  // menší = zaokrouhlení) → odpověď `partial` (appka neslibuje celou částku) + obsluha dostane
  // mail níže (po vystavení dobropisu).
  const partial = requestedCzk > 0 && manAmount > 0
    && Math.round((requestedCzk - manAmount) * 100) > (customerCap ? CUSTOMER_SHORT_TOLERANCE_HALERU : 0)

  if (manAmount <= 0) {
    await dlog('manual_refund_noop_zero', 'info', { manual: true })
    return new Response(
      JSON.stringify({ success: true, manual: true, code: 'manual_refund_noop_zero', amount: 0, credit_note_id: null }),
      { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
    )
  }

  const reasonText = reasonTextFor(reason)
  // Výpůjčka výbavy (2026-10-23): bez motorky → „výpůjčka výbavy“ (gear) / „motorky“ (gear.ts).
  const motoModel = (bkFull as any)?.motorcycles?.model || await noMotoRefundSubject(supabase, booking_id)
  let refundPercent = totalPrice > 0 ? Math.min(100, Math.round((manAmount / totalPrice) * 100)) : 100

  let cnId: string | null = freshManCn?.[0]?.id || null
  let cnNumber: string | null = freshManCn?.[0]?.number || null
  let cnPdfPath: string | null = freshManCn?.[0]?.pdf_path || null
  const reusedCn = !!cnId

  if (!cnId) {
    const { data: origInvs } = await supabase.from('invoices')
      .select('id, number')
      .eq('booking_id', booking_id).neq('status', 'cancelled')
      .in('type', ['final', 'payment_receipt', 'advance', 'proforma'])
      .order('issue_date', { ascending: false }).limit(1)
    cnNumber = await nextDocNumber(supabase, 'DB')
    const issueDate = new Date().toISOString().slice(0, 10)

    const { data: cnInv, error: manCnErr } = await supabase.from('invoices').insert({
      number: cnNumber,
      type: 'credit_note',
      customer_id: bkFull?.user_id || null,
      booking_id,
      items: [{
        description: `Dobropis – ${reasonText} (${motoModel})`,
        qty: 1,
        unit_price: -manAmount,
      }],
      subtotal: -manAmount,
      tax_amount: 0,
      total: -manAmount,
      notes: `Dobropis k rezervaci. ${refundPercent < 100 ? `Částečný refund ${refundPercent}%.` : 'Plný refund.'} ${reasonText}. MANUÁLNÍ VRATKA — bez Stripe platby, k vrácení převodem na účet do 14 dnů.`,
      issue_date: issueDate,
      due_date: issueDate,
      status: 'issued',
      source: 'refund',
      variable_symbol: cnNumber,
      original_invoice_id: origInvs?.[0]?.id || null,
      stripe_refund_id: null,
    }).select('id').single()
    cnId = cnInv?.id || null
    await dlog('manual_credit_note_inserted', cnId ? 'info' : 'error',
      { credit_note_id: cnId, number: cnNumber, amount: manAmount, error: manCnErr?.message || null })
    if (!cnId) {
      // Vratka je domluvená, ale doklad k ní nevznikl — bez upozornění by to
      // nikdo nezjistil, dokud si zákazník neřekne o dobropis.
      await sendOpsMail(
        '⚠️ Dobropis k ruční vratce se nevystavil',
        `<p>Rezervace <strong>${booking_id}</strong>: ruční vratka <strong>${manAmount} Kč</strong>, `
        + `ale zápis dobropisu <strong>${cnNumber}</strong> selhal: ${manCnErr?.message || 'prázdná odpověď'}.</p>`
        + '<p>Vystavte dobropis ručně ve Velíně.</p>',
      )
    }

    if (cnId) {
      // Oprava i2 (2026-11-05): DB trigger _cap_refund_to_paid mohl dobropis oříznout (zaplacené DP − ostatní
      // dobropisy) → dál pracovat s částkou NA DOKLADU (účetní záznam, Fio příkaz, odpověď, mail); 0 = nic k vrácení.
      const { data: cnRow } = await supabase.from('invoices').select('total').eq('id', cnId).maybeSingle()
      const onDoc = Math.round(Math.abs(Number(cnRow?.total ?? -manAmount)) * 100) / 100
      if (Math.round((onDoc - manAmount) * 100) !== 0) {
        await dlog('manual_credit_note_capped', onDoc > 0 ? 'warning' : 'error', { credit_note_id: cnId, requested: manAmount, on_document: onDoc })
        manAmount = onDoc
        refundPercent = totalPrice > 0 ? Math.min(100, Math.round((manAmount / totalPrice) * 100)) : 100
      }
      if (!(manAmount > 0)) {
        await supabase.from('invoices').update({ status: 'cancelled', notes: 'Zrušeno automaticky: dobropis ořezán na 0 Kč (vše už vráceno).' }).eq('id', cnId)
        return new Response(
          JSON.stringify({ success: true, manual: true, code: 'manual_refund_noop_zero', amount: 0, credit_note_id: null }),
          { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }
      await supabase.from('accounting_entries').insert({
        type: 'expense',
        amount: -manAmount,
        description: `Dobropis ${cnNumber} – ${reasonText} (manuální vratka na účet)`,
        category: 'refund',
        date: issueDate,
        booking_id,
      })
      try {
        const cust3 = (bkFull as any)?.profiles || {}
        await loadCustomerCompany(supabase, cust3)
        const html = renderCreditNoteHtml({
          number: cnNumber, issueDate: fmtDate(issueDate), reasonText, motoModel,
          refundAmount: manAmount, refundPercent,
          bookingDates: `${fmtDate(String((bkFull as any)?.start_date || ''))} – ${fmtDate(String((bkFull as any)?.end_date || ''))}`,
          customer: cust3,
          originalInvoiceNumber: origInvs?.[0]?.number || null,
          stripeRefundId: null, manual: true,
        })
        const pdfBytes = await htmlToPdf(html)
        cnPdfPath = pdfBytes ? `invoices/${cnId}.pdf` : `invoices/${cnId}.html`
        await supabase.storage.from('documents').upload(
          cnPdfPath,
          pdfBytes ? new Blob([pdfBytes], { type: 'application/pdf' }) : new Blob([html], { type: 'text/html' }),
          { upsert: true, contentType: pdfBytes ? 'application/pdf' : 'text/html' },
        )
        await supabase.from('invoices').update({ pdf_path: cnPdfPath }).eq('id', cnId)
      } catch (e) {
        console.warn('[process-refund] manual CN pdf failed:', (e as Error).message)
      }
    }
  }

  if (customerCap && partial && !reusedCn) {
    const num = String(booking_id).slice(-8).toUpperCase()
    await dlog('refund_short', 'error', { manual: true, requested: requestedCzk, refunded: manAmount, customer: true })
    await sendOpsMail(
      `⚠️ Vratku za úpravu rezervace #${num} dořešte ručně (vráceno jen částečně)`,
      `<p>Zákazník v aplikaci upravil rezervaci <strong>#${num}</strong> (${reasonText}) a požádal o vrácení <strong>${requestedCzk.toLocaleString('cs-CZ')} Kč</strong>. `
      + `Dobropis ${cnNumber || '—'} je jen na <strong>${manAmount.toLocaleString('cs-CZ')} Kč</strong> — ověřený přeplatek z příchozích plateb převodem (platby − ruční dobropisy − aktuální cena).</p>`
      + '<p>Zbytek zkontrolujte a případně vraťte ručně ve Velíně.</p>',
    )
  }
  // AUTOMATICKÁ VRATKA PŘES FIO API (parita se Stripe): platba přijatá na Fio
  // účet se vrací platebním příkazem na protiúčet, ze kterého přišla. Když
  // příkaz odejde, rezervace jde rovnou do finálního stavu (refunded /
  // partial_refund — stejně jako Stripe refund) a ruční banner se nezobrazí.
  const fio = await tryFioRefund(supabase, booking_id, cnId, cnNumber, manAmount, reasonText, dlog)
  if (fio.sent) {
    // Zákaznická vratka = jen přeplatek → rezervace s nenulovou cenou zůstává zaplacená.
    const newStatus = refundPercent >= 100 && !(customerCap && totalPrice > 0) ? 'refunded' : 'partial_refund'
    await supabase.from('bookings').update({ payment_status: newStatus }).eq('id', booking_id)
    try {
      if (cnId) {
        await supabase.from('invoices').update({
          notes: `Dobropis k rezervaci. ${refundPercent < 100 ? `Částečný refund ${refundPercent}%.` : 'Plný refund.'} ${reasonText}. Vratka odeslána automaticky převodem přes Fio API (dávka ${fio.instructionId || '—'}).`,
        }).eq('id', cnId)
      }
    } catch { /* poznámka na dokladu — neblokuje */ }
    await dlog('fio_refund_done', 'ok', {
      manual: true, fio_sent: true, amount: manAmount, credit_note_id: cnId,
      new_payment_status: newStatus, fio_instruction_id: fio.instructionId || null,
    })
    return new Response(
      JSON.stringify({
        success: true, manual: true, fio_sent: true, code: 'fio_refund_sent',
        amount: manAmount, credit_note_id: cnId, credit_note_pdf_path: cnPdfPath,
        fio_instruction_id: fio.instructionId || null, partial,
      }),
      { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
    )
  }

  await supabase.from('bookings')
    .update({ payment_status: 'refund_pending' })
    .eq('id', booking_id)
  await dlog('manual_refund_pending', 'info', {
    manual: true, amount: manAmount, credit_note_id: cnId,
    note: 'no Stripe payment — vratka k ručnímu vyřízení převodem na účet (do 14 dnů)',
  })
  return new Response(
    JSON.stringify({
      success: true, manual: true, code: 'manual_refund_pending',
      amount: manAmount, credit_note_id: cnId, credit_note_pdf_path: cnPdfPath, partial,
    }),
    { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
  )
}

// Ručně potvrzená platba (QR / převod / hotově / krypto / voucher) — žádné peníze na Stripe.
const MANUAL_PAY_METHODS = ['bank_transfer', 'qr', 'cash', 'crypto', 'voucher', 'wire']
function isManualPayment(d: any): boolean {
  const m = String(d?.payment_method || '').toLowerCase().trim()
  return MANUAL_PAY_METHODS.includes(m) || (!m && d?.pay_channel === 'qr')
}

// Idempotentní odpověď „už vráceno“: dohraje PDF / chybějící dobropis k uložené vratce, Stripe nevolá.
async function respondAlreadyRefunded(
  supabase: any, booking_id: string, data: any,
  dlog: (action: string, status: string, extra?: Record<string, unknown>) => unknown,
): Promise<Response> {
  let result = await ensureCreditNotePdf(supabase, booking_id, data)
  // Recovery: pokud credit_note row vůbec neexistuje (process-refund spadl
  // dřív než stihl INSERT), vytvoř ho ze Stripe refund dat. Tohle je hlavní
  // safety-net cesta, kterou volá webhook-receiver charge.refunded.
  if (!result.creditNoteId && data.stripe_refund_id) {
    await dlog('credit_note_recovery_create', 'info', { stripe_refund_id: data.stripe_refund_id })
    result = await createCreditNoteForExistingRefund(supabase, booking_id, data)
    await dlog('credit_note_recovery_create_done', result.creditNoteId ? 'ok' : 'error', { credit_note_id: result.creditNoteId, pdf_path: result.pdfPath })
  }
  return new Response(
    JSON.stringify({
      success: true,
      already_refunded: true,
      refund_id: data.stripe_refund_id || result.refundId,
      credit_note_id: result.creditNoteId,
      credit_note_pdf_path: result.pdfPath,
      card_brand: data.card_brand,
      card_last4: data.card_last4,
    }),
    { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
  )
}

/** Karta z charge vratky (dorovnání stavu u existující storno vratky — cancel-once.ts). */
async function cardOfRefund(r: StripeRefundLike): Promise<{ brand: string | null; last4: string | null } | null> {
  const chargeId = typeof r.charge === 'string' ? r.charge : (r.charge as any)?.id
  if (!chargeId) return null
  const ch = await stripe.charges.retrieve(chargeId)
  return { brand: ch?.payment_method_details?.card?.brand || null, last4: ch?.payment_method_details?.card?.last4 || null }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS })
  }

  // Bezpečnostní gate: refund smí spustit service_role (DB triggery / webhook),
  // admin (Velín), NEBO přihlášený zákazník POUZE pro VLASTNÍ rezervaci/objednávku
  // (appka — zkrácení rezervace). Anon (jen apikey) je odmítnut. Ověření
  // vlastnictví u 'user' proběhne po načtení booking/order níže.
  const caller = await authClassify(req)
  if (caller.kind === 'none') return forbidden(CORS, 'auth_required')

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )
  let cancelLockBooking: string | null = null // HOTFIX storno 2026-10-29: uvolní se ve finally
  // Oprava i2 (2026-11-05): kontext pro vnější catch (mail obsluze u selhané zákaznické vratky z appky)
  const ctx: { bookingId: string | null; isCustomer: boolean; amount: unknown; reason: unknown } = { bookingId: null, isCustomer: false, amount: null, reason: null }

  try {
    const body: RefundRequest = await req.json()
    const { booking_id, order_id, amount, reason } = body
    ctx.bookingId = booking_id || null; ctx.amount = amount ?? null; ctx.reason = reason ?? null

    // Diagnostika — admin v Velin → Dokumenty → Debug log uvidí každý krok
    // refund flow a okamžitě pozná, kde to padá. Helper, aby fail v debug_log
    // insertu nezablokoval hlavní flow.
    const dlog = (action: string, status: string, extra?: Record<string, unknown>) =>
      supabase.from('debug_log').insert({
        source: 'process-refund', action, status,
        request_data: { booking_id, order_id, amount, reason, ...(extra || {}) },
      }).then(() => {}, () => {})
    await dlog('request_received', 'info')

    // ── ZÁKAZNÍK (2026-10-11) ────────────────────────────────────────────────
    // Dřív smí přihlášený zákazník vrátit si LIBOVOLNOU částku z vlastní zaplacené
    // rezervace/objednávky bez jakékoli změny (zaplatit, vrátit peníze, jet dál).
    // Jediný zákaznický volající = appka po zkrácení / levnější motorce
    // (reservation_edit_screen: nejdřív zapíše nižší total_price, pak refund s
    // reason edit_shortening | moto_swap). Proto jen rezervace, jen tyto důvody,
    // jen živá rezervace a částka max. ověřený PŘEPLATEK (customer*Cap* výše).
    // Oprava f2 2026-10-22: zdroj vratky jako u obsluhy (mainSource — ne vyčerpaný /
    // nezaplacený doplatek ani platba mimo cenu) a zbytek do ověřeného přeplatku
    // z ostatních plateb rezervace; co nejde automaticky → obsluha (mail) + `partial`.
    // service_role (DB triggery / jiné edge fn) a admin (Velín) beze změny.
    const isCustomer = caller.kind === 'user'
    ctx.isCustomer = isCustomer
    if (isCustomer && !booking_id) {
      await dlog('customer_order_refund_denied', 'error')
      return forbidden(CORS, 'customer_booking_only')
    }
    if (isCustomer && reason !== 'edit_shortening' && reason !== 'moto_swap') {
      await dlog('customer_reason_denied', 'error')
      return forbidden(CORS, 'reason_not_allowed')
    }
    let bookingTotalPrice = 0

    if (!booking_id && !order_id) {
      await dlog('missing_identifier', 'error')
      return new Response(
        JSON.stringify({ success: false, error: 'Missing booking_id or order_id', code: 'missing_identifier' }),
        { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    // Look up the Stripe payment_intent_id
    let stripePaymentIntentId: string | null = null
    let entityType = 'booking'
    let entityId = booking_id || order_id || ''
    let alreadyRefunded = false
    // HOTFIX storno 2026-10-29: identita storna (bookings.cancelled_at) + řádek pro dorovnání stavu
    const cancelOnce = !!booking_id && reason === 'cancellation' && !isCustomer
    let cancelTok = ''
    let cancelBk: Record<string, any> | null = null
    let wantsRest = false

    if (booking_id) {
      const { data } = await supabase.from('bookings')
        .select('user_id, status, stripe_payment_intent_id, stripe_session_id, total_price, payment_status, payment_method, pay_channel, stripe_refund_id, card_brand, card_last4, cancelled_at')
        .eq('id', booking_id)
        .single()

      if (!data) {
        return new Response(
          JSON.stringify({ success: false, error: 'Booking not found', code: 'not_found' }),
          { status: 404, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }

      // Vlastnictví: přihlášený zákazník smí refundovat jen SVOU rezervaci.
      if (caller.kind === 'user' && data.user_id !== caller.userId) {
        await dlog('ownership_denied', 'error')
        return forbidden(CORS, 'not_owner')
      }
      // Zákazník: jen živá rezervace (úprava v appce), ne storno/ukončená.
      if (isCustomer && data.status !== 'reserved' && data.status !== 'active') {
        await dlog('customer_wrong_status', 'error', { status: data.status })
        return new Response(
          JSON.stringify({ success: false, error: 'Rezervaci v tomto stavu nelze upravit s vrácením peněz.', code: 'wrong_status' }),
          { status: 409, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }
      bookingTotalPrice = Number(data.total_price) || 0
      cancelTok = cancelToken((data as any).cancelled_at)
      cancelBk = data
      // Zákazník si total_price zapisuje sám (appka při úpravě) — nesmí být
      // nesmyslně nízká vůči ceníku (jinak by strop „zaplaceno − cena“ vrátil
      // skoro vše). Spodní mez: 80 % denních cen termínu (věrnostní sleva ≤ 20 %)
      // − ½ nejdražšího dne (sleva za vyzvednutí od 12:00) − uplatněné slevy.
      if (isCustomer) {
        const floor = await customerPriceFloorCzk(supabase, booking_id)
        if (floor == null || bookingTotalPrice + 1 < floor) {
          await dlog('customer_price_below_floor', 'error', { total_price: bookingTotalPrice, floor })
          return await customerRefundNeedsStaff(supabase, booking_id, amount, reason, dlog)
        }
      }

      // RECOVERY-ONLY dispatche (reason '…_retry' z attach smyček
      // send-booking-email / send-cancellation-email) NIKDY nevytvářejí nový
      // Stripe refund — jen dohrají chybějící dobropis/PDF k vratce, která už
      // proběhla. Incident #DDC5A69D (2026-08-12): retry se s primární vratkou
      // minul o ~1 s (credit_note ještě nebyla v DB a Stripe idempotency klíč
      // se lišil kvůli mezitím změněnému refundable) → vznikla DRUHÁ reálná
      // 556Kč vratka a duplicitní dobropis DB-2026-0002.
      // Webhook charge.refunded volá s důvodem `webhook_refund_retry` (oprava f3 — dřív bez důvodu
      // a u 'refund_pending' tak vznikla druhá plná vratka), viz _shared/refund-recovery.ts.
      if (isRecoveryOnlyReason(reason)) {
        // Více plateb (2026-11-05): pád mezi hlavní storno vratkou a zbytkem z ostatních plateb — rozhodnutí
        // (mg_target) už padlo při původním volání; recovery storna (webhook charge.refunded, attach smyčka
        // storno mailu) ho jen idempotentně dokončí (cancel-once-pool.ts) a dorovná stav + dobropis. Zámek
        // storna PŘED čtením vratek (souběh s běžícím storno voláním); jinak beze změny (žádná nová vratka).
        let recRefunds: StripeRefundLike[] | null = null // vratky uložené platby (i2: dohledání vratky bez refund_id v těle)
        if ((reason === 'cancellation_retry' || reason === WEBHOOK_REFUND_RECOVERY_REASON) && data.stripe_payment_intent_id && !isManualPayment(data)) {
          const ois = stripe as unknown as OtherIntentsStripe
          const lock = await acquireCancelLock(supabase, booking_id)
          if (lock.held) cancelLockBooking = booking_id
          let storedPiR: any = null, storedRefundsR: StripeRefundLike[] | null = null
          try {
            storedPiR = await stripe.paymentIntents.retrieve(data.stripe_payment_intent_id)
            storedRefundsR = (await stripe.refunds.list({ payment_intent: data.stripe_payment_intent_id, limit: 100 })).data as unknown as StripeRefundLike[]
          } catch (e) { console.warn('[process-refund] recovery PI lookup failed:', (e as Error).message) }
          recRefunds = storedRefundsR
          if (storedRefundsR) {
            const pool = await cancellationRefundPool(ois, supabase, { bookingId: booking_id, storedPiId: data.stripe_payment_intent_id, storedRefunds: storedRefundsR })
            // Oprava i1 (2026-11-05): „otevřená“ = jen dokud stornu JAKO CELKU něco chybí (cíl = nejnovější rozhodnutí) —
            // zbytek staré vratky, který mezitím vrátila obsluha vědomě, se nedovrací podruhé (openCancelMains).
            const open = openCancelMains(pool.refunds, booking_id, cancelTok)
            if (open.length) {
              const busy = cancelBusy(open[0], lock.held)
              await dlog('recovery_cancel_remainder_open', 'info', { refund_id: open[0].id, target_haleru: cancelTargetHaleru(open[0]),
                done_haleru: logicalRefundHaleru(open[0], pool.refunds), pool_complete: pool.complete, lock_held: lock.held, busy })
              if (!busy) {
                return await respondExistingCancelRefund({
                  supabase, bookingId: booking_id, token: cancelTok, prior: open[0], refunds: pool.refunds, refundableHaleru: null, lockHeld: lock.held,
                  callerKind: caller.kind === 'admin' ? 'admin' : 'service',
                  complete: (main) => completeCancelRemainder(ois as PoolStripe, supabase, { bookingId: booking_id, main, pool: pool.refunds, token: cancelTok, poolComplete: pool.complete, dlog }),
                  remaining: () => staffFullBalanceHaleru(ois, supabase, { bookingId: booking_id, storedPi: storedPiR, storedRefunds: null }),
                  createCn: createCreditNoteForExistingRefund, ensureCn: ensureCreditNotePdf, cardOf: cardOfRefund, dlog,
                  headers: { ...CORS, 'Content-Type': 'application/json' },
                })
              }
              // Zámek drží jiné volání (nebo zabitý isolate) a storno má nevrácený zbytek: obsluze říct, webhooku odpovědět
              // 503 (Stripe charge.refunded doručí znovu po vypršení zámku → dovrácení), attach smyčka storno mailu
              // dál jako hotfix (dobropis k uložené vratce). Dřív se tu vrátilo bez dobropisu i bez jediné zprávy.
              await deferredCancelMail(supabase, booking_id, { refundId: open[0].id, targetHaleru: cancelTargetHaleru(open[0]) || 0,
                refundedHaleru: logicalRefundHaleru(open[0], pool.refunds) })
              if (reason === WEBHOOK_REFUND_RECOVERY_REASON) {
                await dlog('recovery_cancel_remainder_busy', 'error', { refund_id: open[0].id })
                return new Response(JSON.stringify({ success: false, code: 'cancellation_in_progress', retry: true, recovery_only: true, refund_id: open[0].id }),
                  { status: 503, headers: { ...CORS, 'Content-Type': 'application/json' } })
              }
            }
          }
        }
        // Oprava i2 (2026-11-05): dobropis k TÉ vratce, kvůli které recovery běží (webhook posílá refund_id; attach smyčka
        // bez něj → nejnovější živá vratka uložené platby). Dřív se vzal nejnovější dobropis rezervace: po pádu u DRUHÉ
        // vratky (zkrácení podruhé) měl dobropis jen první vratka a druhá zůstala bez dokladu (800 vráceno, 500 dobropisy).
        // Zbytek z jiné platby (mg_part remainder) patří k hlavní vratce (mg_main_refund); vratky mimo cenu (pozdní
        // platba, duplicita, nezapsaná změna) dobropis nemají.
        const bodyRefundId = typeof (body as Record<string, unknown>).refund_id === 'string' ? String((body as Record<string, unknown>).refund_id) : null
        let recKey: string | null = null
        try {
          if (!recRefunds && data.stripe_payment_intent_id && !isManualPayment(data)) {
            recRefunds = (await stripe.refunds.list({ payment_intent: data.stripe_payment_intent_id, limit: 100 })).data as unknown as StripeRefundLike[]
          }
          const liveR = (recRefunds || []).filter((r) => r.status === 'succeeded' || r.status === 'pending')
            .sort((x, y) => Number(y.created || 0) - Number(x.created || 0))
          const recId = bodyRefundId && /^re_/.test(bodyRefundId) ? bodyRefundId : (liveR[0]?.id || null)
          if (recId) {
            const r = liveR.find((x) => x.id === recId) || (await stripe.refunds.retrieve(recId) as unknown as StripeRefundLike)
            const md = (r?.metadata || {}) as Record<string, string | undefined>
            // jen NAŠE vratky (mg_source process-refund); externí (Stripe portál: plná = storno, částečná = dobropis vystaví
            // obsluha) a vratky mimo cenu (pozdní platba, duplicita, nezapsaná změna) → dosavadní chování níže
            if (md.mg_source !== 'process-refund') recKey = null
            else recKey = md.mg_part === 'remainder' ? (md.mg_main_refund || null) : recId
          }
        } catch (e) { await dlog('recovery_refund_resolve_failed', 'warning', { refund_id: bodyRefundId, error: (e as Error).message }) }
        let result = recKey
          ? await ensureCreditNotePdf(supabase, booking_id, data, { refundId: recKey })
          : await ensureCreditNotePdf(supabase, booking_id, data)
        if (!result.creditNoteId && (recKey || data.stripe_refund_id)) {
          result = await createCreditNoteForExistingRefund(supabase, booking_id, recKey ? { ...data, stripe_refund_id: recKey } : data)
        }
        // Uložená vratka → novější (CAS na starou hodnotu), ať další recovery / stav vycházejí z poslední vratky.
        if (recKey && result.creditNoteId && recKey !== (data.stripe_refund_id || null)) {
          const newer = (recRefunds || []).find((x) => x.id === recKey), stored = (recRefunds || []).find((x) => x.id === data.stripe_refund_id)
          if (!data.stripe_refund_id || (newer && stored && Number(newer.created) >= Number(stored.created))) {
            let upd = supabase.from('bookings').update({ stripe_refund_id: recKey }).eq('id', booking_id)
            upd = data.stripe_refund_id ? upd.eq('stripe_refund_id', data.stripe_refund_id) : upd.is('stripe_refund_id', null)
            await upd
          }
        }
        await dlog('recovery_only_dispatch', result.creditNoteId ? 'ok' : 'info', {
          credit_note_id: result.creditNoteId, pdf_path: result.pdfPath, webhook_refund_id: bodyRefundId, recovery_refund_id: recKey,
        })
        return new Response(
          JSON.stringify({
            success: !!result.creditNoteId,
            recovery_only: true,
            refund_id: result.refundId,
            credit_note_id: result.creditNoteId,
            credit_note_pdf_path: result.pdfPath,
            card_brand: data.card_brand,
            card_last4: data.card_last4,
          }),
          { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }

      // Idempotency: if booking is already refunded, ensure the credit note has pdf_path
      // (regenerate if missing) and return success — DON'T call Stripe again.
      // This handles the scenario where a previous refund attempt partially succeeded
      // (Stripe refund went through, status updated, but PDF/email step failed).
      //
      // POZOR: 'partial_refund' NENÍ terminální stav — je to běžný stav rezervace po
      // PRVNÍ rozdílové úpravě (levnější motorka / odebraná výbava / zkrácení).
      // Další úprava se slevou musí umět vystavit DALŠÍ částečný Stripe refund +
      // dobropis. Proto se 'partial_refund' chová idempotentně jen BEZ explicitní
      // částky; s `amount > 0` pokračuje na nový refund (po fresh-CN dedup checku níže).
      const wantsNewPartial = data.payment_status === 'partial_refund' && Number.isFinite(Number(amount)) && Number(amount) > 0
      // HOTFIX storno 2026-10-29: Velín „Potvrdit (částečné) vrácení“ 100 % (bez amount) u stornované,
      // částečně vrácené KARTOVÉ rezervace = vrátit ZBYTEK (modal: „omezí se na dosud nevrácenou část“).
      // Dřív větev „už vráceno“ nevrátila nic a mail zákazníkovi tvrdil 100 %. Ruční platby beze změny.
      wantsRest = caller.kind === 'admin' && reason === 'cancellation' && data.status === 'cancelled'
        && data.payment_status === 'partial_refund' && !(Number(amount) > 0)
        && !!data.stripe_payment_intent_id && !isManualPayment(data)
      if (data.payment_status === 'refunded' || (data.payment_status === 'partial_refund' && !wantsNewPartial && !wantsRest)) {
        alreadyRefunded = true
        return await respondAlreadyRefunded(supabase, booking_id, data, dlog)
      }

      // Duplicitní dispatch téže rozdílové úpravy (RPC pg_net + retry v
      // send-booking-email běží souběžně): čerstvý dobropis na STEJNOU částku
      // (≤15 min) znamená, že refund téhle úpravy už proběhl → vrať existující.
      // Oprava i1 (2026-11-05): storno NE — „jen jednou“ u storna hlídá zámek + kontrola vratek všech plateb
      // (cancel-once). Dřív čerstvý dobropis zkrácení na STEJNOU částku (zkrátit → do 15 min stornovat) storno vratku
      // tiše přeskočil a mail zákazníkovi tvrdil vrácení.
      // Oprava i4 (2026-11-07, S10): i u 'paid' / 'refund_pending' — vratka zkrácení / úpravy / výměny vrácená Stripem
      // jako „pending“ nechá rezervaci 'refund_pending' (webhook f3 ji už nepřepisuje) a klíč se změnil (pending vratka
      // snížila refundable) → stejné volání znovu (retry Velínu, druhý pg_net dispatch) vrátilo podruhé.
      const dedupCandidate = reason !== 'cancellation' && Number.isFinite(Number(amount)) && Number(amount) > 0
        && (wantsNewPartial || data.payment_status === 'paid' || data.payment_status === 'refund_pending')
      if (dedupCandidate) {
        const { data: freshCn } = await supabase.from('invoices')
          .select('id, number, pdf_path')
          .eq('booking_id', booking_id).eq('type', 'credit_note').neq('status', 'cancelled')
          .eq('total', -Math.abs(Number(amount)))
          .gte('created_at', new Date(Date.now() - 15 * 60_000).toISOString())
          .order('created_at', { ascending: false }).limit(1)
        // Oprava i2 (2026-11-05): čerstvý dobropis = duplicita JEN když už nic nedlužíme (ověřený přeplatek < částka).
        // Druhé zkrácení o stejnou částku do 15 min (appka / web / výbava / Velín) má po snížení ceny přeplatek ≥ částka
        // → nová vratka je po právu (dřív tiše přeskočena s odpovědí success). Nelze ověřit → duplicita jako dřív + mail obsluze.
        let dedupHit = !!freshCn?.length
        if (dedupHit) {
          const owedH = await verifiedOverpaymentHaleru(supabase, booking_id, data, bookingTotalPrice)
          const reqH = Math.round(Math.abs(Number(amount)) * 100)
          if (owedH != null && owedH >= reqH) {
            dedupHit = false
            await dlog('partial_refund_dedup_skipped_owed', 'info', { credit_note_id: freshCn![0].id, amount, owed_haleru: owedH })
          } else if (owedH == null) {
            await dlog('partial_refund_dedup_cap_unknown', 'warning', { credit_note_id: freshCn![0].id, amount })
            await opsMailOnce(supabase, booking_id, 'partial_refund_dedup_cap_unknown_mail',
              `⚠️ Vratka ${Number(amount)} Kč k rezervaci #${bookingNum(booking_id)} přeskočena — nejde ověřit přeplatek`,
              `<p>Rezervace <strong>#${bookingNum(booking_id)}</strong> (${booking_id}, ${reasonTextFor(reason)}): do 15 min existuje dobropis na stejnou částku `
              + `<strong>${Number(amount)} Kč</strong> a platby ve Stripe teď nejdou načíst, takže nejde rozhodnout, zda jde o duplicitní dispatch, nebo o další `
              + 'vratku (druhé zkrácení). Nic se nevrátilo — zkontrolujte platby a případně vraťte ručně ve Velíně.</p>', { amount })
          }
        }
        if (dedupHit && freshCn?.length) {
          await dlog('partial_refund_dedup_fresh_cn', 'info', { credit_note_id: freshCn[0].id, amount })
          // Dobropis existuje, ale PDF mohlo selhat (PDFShift/Storage) → dorenderuj,
          // ať má retry loop v send-booking-email co přiložit.
          let pdfPath = freshCn[0].pdf_path
          if (!pdfPath) {
            const ensured = await ensureCreditNotePdf(supabase, booking_id, data)
            if (ensured.creditNoteId === freshCn[0].id && ensured.pdfPath) pdfPath = ensured.pdfPath
          }
          return new Response(
            JSON.stringify({
              success: true,
              already_refunded: true,
              refund_id: data.stripe_refund_id,
              credit_note_id: freshCn[0].id,
              credit_note_pdf_path: pdfPath,
              card_brand: data.card_brand,
              card_last4: data.card_last4,
            }),
            { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
          )
        }
      }

      // Refund povolíme pro 'paid' i 'refund_pending' (= „Čeká na vrácení" — storno už
      // proběhlo, peníze jsou stále u nás a čeká se na vrácení), plus 'partial_refund'
      // s explicitní částkou (další rozdílová úprava). 'refunded' (a 'partial_refund'
      // bez částky) řeší idempotentní větev výše. Cokoli jiného (unpaid) refundovat nelze.
      if (data.payment_status !== 'paid' && data.payment_status !== 'refund_pending' && !wantsNewPartial && !wantsRest) {
        return new Response(
          JSON.stringify({
            success: false,
            error: `Booking is not paid (current: ${data.payment_status}) — cannot refund`,
            code: 'not_paid',
            current_status: data.payment_status,
          }),
          { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }
      // DŮVĚŘUJ ZPŮSOBU PLATBY (2026-08-21c, zadání provozovatele): rezervace
      // zaplacená RUČNĚ potvrzenou platbou (QR / bankovní převod / hotově /
      // krypto / voucher) nemá na Stripe žádné peníze — případný PaymentIntent
      // nebo session na řádku je jen pozůstatek opuštěného pokusu o kartu.
      // Stripe API se u ní VŮBEC nevolá: rovnou manuální vratka (dobropis +
      // refund_pending, peníze pošle admin převodem). Řeší i chybu
      // „This PaymentIntent ... does not have a successful charge to refund".
      // pay_channel='qr' je pojistka pro řádky bez payment_method; kartové
      // metody (card/stripe/google_pay/apple_pay/klarna/paypal) jdou dál na Stripe.
      const payMethod = String((data as any).payment_method || '').toLowerCase().trim()
      if (isManualPayment(data)) {
        await dlog('manual_method_direct', 'info', { payment_method: payMethod, pay_channel: (data as any).pay_channel })
        return await manualBookingRefund(supabase, booking_id, amount, reason, dlog, isCustomer)
      }

      stripePaymentIntentId = data.stripe_payment_intent_id

      // Robustnost: `stripe_payment_intent_id` může být prázdný — typicky u web
      // rezervací, kde se PI uloží až po dokončení Checkoutu (race s webhookem),
      // nebo když booking nikdy neprošel přes náš confirm flow. Bez PI by refund
      // spadl na `no_stripe_payment` a Stripe by se o vrácení vůbec nedozvěděl.
      // Dohledáme ho proto ze `stripe_session_id` přes Stripe API a doplníme do DB.
      if (!stripePaymentIntentId && data.stripe_session_id) {
        try {
          const sess = await stripe.checkout.sessions.retrieve(data.stripe_session_id)
          const piFromSess = typeof sess.payment_intent === 'string'
            ? sess.payment_intent
            : (sess.payment_intent as any)?.id || null
          // PI ze session převezmi JEN když session byla skutečně ZAPLACENÁ.
          // Rezervace placená QR/převodem může nést stripe_session_id z dřívějšího
          // opuštěného pokusu o kartu — jeho nezaplacený PI by níže vedl na
          // „refundable 0 → no_op → payment_status='refunded'" (peníze by se nikdy
          // nevrátily a nevznikl by ani manuální dobropis). Nezaplacená session →
          // PI ignoruj a spadni do manuální větve (dobropis + refund_pending).
          if (piFromSess && sess.payment_status === 'paid') {
            stripePaymentIntentId = piFromSess
            await supabase.from('bookings').update({ stripe_payment_intent_id: piFromSess }).eq('id', booking_id)
            await dlog('pi_resolved_from_session', 'info', { session_id: data.stripe_session_id, payment_intent_id: piFromSess })
          } else if (piFromSess) {
            await dlog('pi_from_session_ignored_unpaid', 'info', { session_id: data.stripe_session_id, payment_intent_id: piFromSess, session_payment_status: sess.payment_status })
          }
        } catch (e) { console.warn('[process-refund] session PI resolve failed:', (e as Error).message) }
      }
    } else if (order_id) {
      entityType = 'shop'
      const { data } = await supabase.from('shop_orders')
        .select('customer_id, stripe_payment_intent_id, stripe_session_id, total_amount, payment_status')
        .eq('id', order_id)
        .single()

      if (!data) {
        return new Response(
          JSON.stringify({ success: false, error: 'Order not found', code: 'not_found' }),
          { status: 404, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }

      // Vlastnictví: přihlášený zákazník smí refundovat jen SVOU objednávku.
      if (caller.kind === 'user' && data.customer_id !== caller.userId) {
        await dlog('ownership_denied', 'error')
        return forbidden(CORS, 'not_owner')
      }
      if (data.payment_status !== 'paid') {
        return new Response(
          JSON.stringify({
            success: false,
            error: `Order is not paid (current: ${data.payment_status}) — cannot refund`,
            code: 'not_paid',
            current_status: data.payment_status,
          }),
          { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }
      stripePaymentIntentId = data.stripe_payment_intent_id
      if (!stripePaymentIntentId && data.stripe_session_id) {
        try {
          const sess = await stripe.checkout.sessions.retrieve(data.stripe_session_id)
          const piFromSess = typeof sess.payment_intent === 'string'
            ? sess.payment_intent
            : (sess.payment_intent as any)?.id || null
          // Stejný guard jako u bookingu: PI jen ze ZAPLACENÉ session.
          if (piFromSess && sess.payment_status === 'paid') {
            stripePaymentIntentId = piFromSess
            await supabase.from('shop_orders').update({ stripe_payment_intent_id: piFromSess }).eq('id', order_id)
          }
        } catch (e) { console.warn('[process-refund] session PI resolve failed (order):', (e as Error).message) }
      }
    }

    if (!stripePaymentIntentId) {
      // Rezervace BEZ Stripe platby (QR/převod/hotově/ručně označená paid):
      // automatický Stripe refund nejde, ale vratku kvůli tomu NEBLOKUJEME —
      // manuální dobropis + refund_pending, viz manualBookingRefund.
      // Shop objednávky se chovají jako dřív (400 — řeší se ručně).
      if (booking_id) {
        return await manualBookingRefund(supabase, booking_id, amount, reason, dlog, isCustomer)
      }
      return new Response(
        JSON.stringify({
          success: false,
          error: `No Stripe payment found for this ${entityType}. Refund must be processed manually.`,
          code: 'no_stripe_payment',
        }),
        { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    // Cap refund at the amount actually charged on Stripe.
    // Without this, edge cases (100% promo code → tiny payment, but DB-side
    // refund_amount computed from gross per-day pricing) make us request a
    // refund larger than the captured charge — Stripe then errors with
    // "Refund amount ... is greater than charge amount ..." and the user
    // sees "Něco se pokazilo. Zkus to prosím znovu."
    // HOTFIX storno 2026-10-29: souběžná storno volání téže rezervace po sobě (zámek PŘED čtením
    // vratek ze Stripe, ať druhé volání vidí vratku prvního). Bez zámku dál — rozhoduje kontrola níže.
    let cancelLock: CancelLock | null = null
    if (cancelOnce) {
      cancelLock = await acquireCancelLock(supabase, booking_id!)
      if (cancelLock.held) cancelLockBooking = booking_id!
      else await dlog('cancellation_lock_busy', 'info', { waited: cancelLock.waited })
    }

    let refundableHaleru: number | null = null
    let refundableCZK: number | null = null
    let chargedHaleru: number | null = null
    // uložená platba + její vratky (mainSource: patří vůbec do ceny rezervace?)
    let storedPi: any = null
    let storedRefunds: any[] | null = null
    try {
      const pi = await stripe.paymentIntents.retrieve(stripePaymentIntentId)
      storedPi = pi
      // POZOR (fix 2026-08-21): dřívější fallback `|| pi.amount` počítal i
      // NEZAPLACENÝ PI jako nabitý (pi.amount = pouze POŽADOVANÁ částka) —
      // refunds.create pak na PI bez charge spadl („no successful charge")
      // → 500 a vratka se nikdy nevyřídila. amount_received = skutečně přijato.
      const charged = pi.amount_received || 0
      chargedHaleru = charged
      // Subtract refunds already issued on this PI
      let alreadyRefunded = 0
      try {
        const refundsList = await stripe.refunds.list({ payment_intent: stripePaymentIntentId, limit: 100 })
        storedRefunds = refundsList.data
        for (const r of refundsList.data) {
          if (r.status === 'succeeded' || r.status === 'pending') alreadyRefunded += r.amount
        }
      } catch { /* non-fatal */ }
      refundableHaleru = Math.max(0, charged - alreadyRefunded)
      refundableCZK = refundableHaleru / 100
    } catch (e) {
      console.warn('[process-refund] PI lookup failed:', (e as Error).message)
    }
    // Oprava i4 (2026-11-07, verify:charges): uložená platba v jiné měně než CZK (Stripe Checkout s Adaptive Pricing — strženo
    // v měně zákazníka) → žádná automatická vratka (částky rezervace jsou v haléřích CZK; ořez na „refundable“ v eurocentech
    // by u částečné vratky vrátil celou platbu). Obsluha vrátí ručně ve Stripe dashboardu.
    if (storedPi && !paymentCurrencyOk(storedPi.currency)) {
      const id = booking_id || order_id || ''
      await dlog('refund_foreign_currency', 'error', { payment_intent_id: stripePaymentIntentId, currency: storedPi.currency })
      if (booking_id) {
        await opsMailOnce(supabase, booking_id, 'refund_foreign_currency_mail',
          `⚠️ Vratka #${bookingNum(booking_id)}: platba v cizí měně (${String(storedPi.currency).toUpperCase()}) — vraťte ručně ve Stripe`,
          `<p>Rezervace <strong>#${bookingNum(booking_id)}</strong> (${booking_id}, ${reasonTextFor(reason)}${Number(amount) > 0 ? `, ${Number(amount)} Kč` : ', celý zůstatek'}): `
          + `platba <code>${stripePaymentIntentId}</code> byla stržena v měně <strong>${String(storedPi.currency).toUpperCase()}</strong> (Stripe Adaptive Pricing — má být vypnuté). `
          + 'Automatická vratka se NEprovedla. Vraťte odpovídající část ručně ve Stripe dashboardu a dobropis vystavte ve Velíně (Finance → Dobropisy).</p>',
          { payment_intent_id: stripePaymentIntentId, currency: storedPi.currency })
      }
      if (isCustomer && booking_id) return await customerRefundNeedsStaff(supabase, booking_id, amount, reason, dlog)
      return new Response(JSON.stringify({ success: false, code: 'foreign_currency_payment', entity: id,
        error: `Platba byla stržena v měně ${String(storedPi.currency).toUpperCase()} — vratku proveďte ručně ve Stripe dashboardu.` }),
        { status: 409, headers: { ...CORS, 'Content-Type': 'application/json' } })
    }
    // Oprava i3 (2026-11-07, V7): přibalená e-shop část hlavní platby (web checkout s doprodejem, metadata.shop_order_id)
    // do ceny rezervace nepatří — vratka rezervace ji nesmí vrátit a stav 'refunded' se počítá bez ní.
    let mainShopH = booking_id && storedPi ? await shopPartHaleru(supabase, (storedPi.metadata || {}).shop_order_id, storedRefunds) : 0

    // HOTFIX storno 2026-10-29 + více plateb (2026-11-05): volání ze serveru (send-cancellation-email) na
    // storno, ke kterému už naše HLAVNÍ storno vratka existuje (i pending / bez zapsaného stavu / na JINÉ
    // platbě rezervace než uložené — mainSource) → žádná druhá vratka; jen dovrácení nevráceného zbytku
    // TÉHOŽ storna do mg_target (cancel-once-pool.ts), dorovnání stavu a dobropisu. Obsluha (Velín): jen
    // duplicita TÉHOŽ požadavku (dvojité odeslání / souběh při čekání na zámek); vědomá další vratka
    // („Potvrdit vrácení“ jiné částky) projde jako dřív. Kontrola nad vratkami VŠECH plateb rezervace stojí
    // PŘED volbou zdroje vratky (mainSource / ruční fallback), aby opakované volání po pádu neskončilo
    // ruční vratkou ani vratkou z další platby.
    let cancelDoneHaleru = 0 // už vráceno k TOMUTO stornu (všechny platby) → metadata mg_cancel_total (mail webhooku)
    let poolComplete = true // false = ostatní platby nečitelné (mg_cancel_total jen z uložené platby → mail webhooku ho nepoužije)
    if (cancelOnce && cancelBk && storedRefunds) {
      const ois = stripe as unknown as OtherIntentsStripe
      const pool = await cancellationRefundPool(ois, supabase, { bookingId: booking_id!, storedPiId: stripePaymentIntentId,
        storedRefunds: storedRefunds as unknown as StripeRefundLike[] })
      poolComplete = pool.complete
      if (!pool.complete) {
        await dlog('cancellation_pool_incomplete', 'error', { error: pool.error, payment_intent_id: stripePaymentIntentId })
        // Oprava i1 (2026-11-05): ochrana „jen jednou“ přes všechny platby teď běží jen nad uloženou platbou → obsluha musí vědět.
        await opsMailOnce(supabase, booking_id!, 'cancellation_pool_incomplete_mail',
          `⚠️ Storno #${bookingNum(booking_id!)}: vratky ve Stripe se nepodařilo načíst úplně`,
          `<p>Rezervace <strong>#${bookingNum(booking_id!)}</strong> (${booking_id}): při stornu se nepodařilo načíst vratky VŠECH plateb rezervace `
          + `(${pool.error || 'chyba Stripe'}) — kontrola „vráceno jen jednou“ běžela jen nad uloženou platbou ${stripePaymentIntentId}.</p>`
          + `<p>Zkontrolujte ve Stripe, zda se k tomuto stornu${Number(amount) > 0 ? ` (${Number(amount)} Kč)` : ''} vrátilo jen jednou (rezervace má více plateb).</p>`,
          { error: pool.error })
      }
      cancelDoneHaleru = cancellationRefundedHaleru(pool.refunds, booking_id!, cancelTok)
      const prior = caller.kind === 'service'
        ? priorCancellationRefunds(pool.refunds, booking_id!, cancelTok)
        : duplicateAdminRefunds(pool.refunds, booking_id!, {
          amountHaleru: Number(amount) > 0 ? Math.round(Number(amount) * 100) : null,
          nowS: Math.floor(Date.now() / 1000), lock: cancelLock,
        })
      if (prior.length) {
        return await respondExistingCancelRefund({
          supabase, bookingId: booking_id!, token: cancelTok, prior: prior[0], refunds: pool.refunds, refundableHaleru,
          lockHeld: !!cancelLock?.held, callerKind: caller.kind === 'admin' ? 'admin' : 'service',
          onDeferred: (a) => deferredCancelMail(supabase, booking_id!, a),
          complete: (main) => completeCancelRemainder(ois as PoolStripe, supabase, { bookingId: booking_id!, main, pool: pool.refunds, token: cancelTok, poolComplete: pool.complete, dlog }),
          remaining: () => staffFullBalanceHaleru(ois, supabase, { bookingId: booking_id!, storedPi, storedRefunds: null }),
          createCn: createCreditNoteForExistingRefund, ensureCn: ensureCreditNotePdf, cardOf: cardOfRefund, dlog,
          headers: { ...CORS, 'Content-Type': 'application/json' },
        })
      }
      // Obsluha vědomě vrací další částku téhož storna → starší hlavní vratky s nedokončeným zbytkem uzavřít
      // (recovery by jejich zbytek dovrátila vedle této vratky — oprava i1 2026-11-05).
      if (caller.kind === 'admin') await closeStaleCancelMains(ois as PoolStripe, { bookingId: booking_id!, pool: pool.refunds, token: cancelTok, dlog })
    }

    // Vratka obsluhy / služby BEZ částky (Velín plné storno — bookingMessageHelpers isFull,
    // BookingDetail „Potvrdit vrácení" na celou cenu) = celý zůstatek plateb V CENĚ rezervace
    // (uložená platba, patří-li do ceny, + ostatní platby) a dál stejná cesta jako vratka s částkou
    // (mainSource → hlavní vratka → zbytek). Oprava f3 2026-10-22: dřív jen zbytek uložené platby —
    // po zaplacené úpravě / výměně je to doplatek, takže plné storno 3000 + 115 Kč vrátilo 115 Kč,
    // zapsalo 'refunded' a navazující volání na celou cenu (send-cancellation-email) skončilo
    // v idempotentní větvi: původní platba (i dorovnání na 15 Kč) se nevrátila nikdy; po nezapsané
    // výměně (uložený vrácený doplatek) no_op → 'refunded' a 0 Kč. Recovery (`_retry`) a idempotentní
    // větev výše se nemění; zákazník částku posílá vždy. Nelze zjistit → dosavadní chování.
    let reqAmount: number | undefined = amount
    let fullBalance = false
    let nonStripeOwedH = 0 // i2: část ceny zaplacená mimo Stripe (převod / QR doplatek) → ruční dobropis po vratce kartou
    // Oprava i1 (2026-11-05): ostatní platby rezervace se podařilo přečíst (search / historie) — bez toho nelze říct,
    // že „nic nezbývá“ (no_op → 'refunded' by rezervaci uzavřel bez vrácení původní platby).
    let othersKnown = false
    // Oprava i3 (2026-11-07, V7): plné volání a na platbách V CENĚ rezervace nic nezbývá → nic nevracet (no_op). Dřív
    // zůstal reqAmount prázdný a vrátil se celý zbytek uložené platby — u přibalené e-shop objednávky peníze za zboží.
    let balanceZero = false
    if (booking_id && !isCustomer && !(Number(amount) > 0) && refundableHaleru != null) {
      const balH = await staffFullBalanceHaleru(stripe as unknown as OtherIntentsStripe, supabase, { bookingId: booking_id, storedPi, storedRefunds })
      await dlog('full_refund_balance', 'info', { balance_haleru: balH, stored_refundable_haleru: refundableHaleru, payment_intent_id: stripePaymentIntentId })
      if (balH == null) {
        // Nečitelné ostatní platby (limit Stripe search / výpadek): dřív „dosavadní chování“ = vrátit jen zbytek uložené
        // platby (doplatek 115 Kč z 3 115) a zapsat 'refunded' → storno se už nikdy nedovrátilo. Teď selhat NAPEVNO:
        // volající (Velín / send-cancellation-email) zkusí znovu, až Stripe odpoví.
        return await otherPaymentsUnavailable(supabase, booking_id, amount, reason, dlog, 'full_balance')
      }
      othersKnown = true
      if (balH > 0) { reqAmount = balH / 100; fullBalance = true }
      nonStripeOwedH = await nonStripeOwedHaleru(supabase, booking_id, balH, dlog, { piId: stripePaymentIntentId, refunds: storedRefunds }, bookingTotalPrice)
      if (balH === 0 && nonStripeOwedH > 0) {
        // Na Stripe nic nezbývá, dle dokladů dlužíme část zaplacenou převodem → jen ruční dobropis (+ Fio / refund_pending).
        await dlog('full_refund_non_stripe_only', 'info', { non_stripe_haleru: nonStripeOwedH })
        return await manualBookingRefund(supabase, booking_id, nonStripeOwedH / 100, reason, dlog, false)
      }
      if (balH === 0) balanceZero = true
    }

    // Uložená platba nemá z čeho vracet (nikdy nezaplacený PI opuštěného doplatku, nebo
    // doplatek nezapsané změny, který se už celý vrátil přímo ze Stripe — oprava 2026-10-16),
    // nebo stojí MIMO cenu rezervace (doplatek změny, kterou webhook ještě nezapsal, platba
    // vrácená jen jako peníze mimo cenu — oprava f1 2026-10-22), ale rezervace má jiné úspěšné
    // platby kartou → hlavní vratka z nejstarší z nich (typicky původní platba rezervace),
    // zbytek níže z ostatních. Platba mimo cenu a žádná jiná platba kartou (rezervace placená
    // QR / převodem / hotově) → ruční vratka (dobropis + refund_pending). Dřív: no_op →
    // 'refunded' bez vrácení peněz, resp. storno část ceny z ještě nezapsaného doplatku. Jen
    // vratka s částkou — storno, obsluha i zákaznická vratka z appky (oprava f2 2026-10-22:
    // dřív jen z uložené platby, tj. z posledního doplatku oříznutá na jeho zbytek).
    if (booking_id && (chargedHaleru === 0 || refundableHaleru === 0 || storedPi)) {
      try {
        const src = await mainSource(stripe as unknown as OtherIntentsStripe, supabase, {
          bookingId: booking_id, storedPiId: stripePaymentIntentId, storedPi, storedRefunds, chargedHaleru, refundableHaleru, isCustomer, amount: reqAmount,
        })
        if (src.kind === 'retarget') {
          await dlog('main_pi_retargeted', 'info', { stored_payment_intent_id: stripePaymentIntentId, payment_intent_id: src.piId,
            stored_charged_haleru: chargedHaleru, refundable_haleru: src.refundableHaleru, stored_outside_price: src.outside })
          stripePaymentIntentId = src.piId
          mainShopH = 0 // kandidát z otherRefundableIntents už je bez e-shop části
          chargedHaleru = src.refundableHaleru
          refundableHaleru = src.refundableHaleru
          refundableCZK = refundableHaleru / 100
        } else if (src.kind === 'manual') {
          await dlog('stored_pi_outside_price_manual', 'info', { payment_intent_id: stripePaymentIntentId, outside: src.outside })
          return await manualBookingRefund(supabase, booking_id, amount, reason, dlog, isCustomer)
        }
        if (chargedHaleru === 0 || refundableHaleru === 0 || src.kind === 'retarget') othersKnown = true
      } catch (e) {
        await dlog('main_pi_retarget_failed', 'error', { error: (e as Error).message })
        // Oprava i1 (2026-11-05): uložená platba nemá z čeho vracet a ostatní platby se nepodařilo přečíst → obsluha /
        // služba dostane chybu a zkusí znovu (dřív no_op → 'refunded' a 0 Kč; zákazník: strop přes obsluhu níže).
        if (!isCustomer && (chargedHaleru === 0 || refundableHaleru === 0)) {
          return await otherPaymentsUnavailable(supabase, booking_id, amount, reason, dlog, 'main_source')
        }
      }
    }

    // PI existuje, ale Stripe na něm NIKDY nepřijal peníze → rezervace byla
    // reálně zaplacená jinak (QR/převod/hotově; stale PI z opuštěného pokusu
    // o kartu, který si starší verze uložila do bookings.stripe_payment_intent_id).
    // Bez tohoto fallbacku by no_op větev níže chybně označila 'refunded'
    // (peníze by se nikdy nevrátily a nevznikl by ani dobropis).
    if (booking_id && chargedHaleru === 0) {
      // „Vrátit zbytek“ jde jen ze Stripe platby — bez ní jako dřív „už vráceno“ (žádný ruční dobropis na celou cenu).
      if (wantsRest && cancelBk) return await respondAlreadyRefunded(supabase, booking_id, cancelBk, dlog)
      await dlog('pi_never_charged_manual_fallback', 'info', { payment_intent_id: stripePaymentIntentId })
      return await manualBookingRefund(supabase, booking_id, amount, reason, dlog, isCustomer)
    }

    // Decide effective amount (in haléře). Null = full refund.
    let effectiveAmountHaleru: number | null = null
    // i3: co z hlavní platby patří do ceny rezervace (bez přibalené e-shop části)
    const inPriceRefundableH = refundableHaleru == null ? null : Math.max(0, refundableHaleru - mainShopH)
    if (balanceZero) {
      effectiveAmountHaleru = 0
    } else if (reqAmount && reqAmount > 0) {
      effectiveAmountHaleru = Math.round(reqAmount * 100)
      if (refundableHaleru != null && effectiveAmountHaleru > refundableHaleru) {
        console.warn(`[process-refund] requested ${effectiveAmountHaleru/100} CZK > refundable ${refundableHaleru/100} CZK — clamping`)
        effectiveAmountHaleru = refundableHaleru
      }
      if (mainShopH > 0 && inPriceRefundableH != null && effectiveAmountHaleru > inPriceRefundableH) {
        await dlog('refund_clamped_shop_part', 'info', { requested_haleru: effectiveAmountHaleru, in_price_haleru: inPriceRefundableH, shop_haleru: mainShopH })
        effectiveAmountHaleru = inPriceRefundableH
      }
    } else if (refundableHaleru != null) {
      effectiveAmountHaleru = inPriceRefundableH
    }

    // Zákazník: max. ověřený přeplatek přes platby V CENĚ rezervace (customerCapHaleru).
    // Neověřitelné / nulové → nic se nevrací ani nemění (žádné no_op → 'refunded'),
    // vyřídí obsluha. Strop platí pro hlavní vratku i zbytek z ostatních plateb níže.
    let customerCapH: number | null = null
    if (isCustomer && booking_id) {
      customerCapH = refundableHaleru == null ? null
        : await customerCapHaleru(stripe as unknown as OtherIntentsStripe, supabase, { bookingId: booking_id, storedPi, storedRefunds,
          totalPrice: bookingTotalPrice })
      await dlog('customer_refund_cap', 'info', { cap_haleru: customerCapH, requested_haleru: effectiveAmountHaleru, refundable_haleru: refundableHaleru,
        payment_intent_id: stripePaymentIntentId })
      if (customerCapH == null || effectiveAmountHaleru == null || Math.min(effectiveAmountHaleru, customerCapH) <= 0) {
        return await customerRefundNeedsStaff(supabase, booking_id, amount, reason, dlog)
      }
      effectiveAmountHaleru = Math.min(effectiveAmountHaleru, customerCapH)
    }

    // Nothing left to refund (e.g. fully discounted booking that paid 0 Kč,
    // or already-refunded PI) — short-circuit with success so the caller
    // (web "Zkrátit a vrátit peníze" / change-bike flow) doesn't error out.
    if (effectiveAmountHaleru === 0) {
      if (booking_id) {
        // Oprava i1 (2026-11-05): u storna 'refunded' jen když se ostatní platby podařilo přečíst a uložená platba není
        // doplatek úpravy (původní platba rezervace mohla zůstat nevrácená) — jinak 'partial_refund' (Velín „Potvrdit
        // vrácení“ i další storno volání zůstanou možné; nic se nevrací).
        const closeIt = balanceZero || !(reason === 'cancellation' && (!othersKnown || (storedPi?.metadata || {}).type === 'extension'))
        // Oprava i4 (2026-11-07, S7): „Čeká na vrácení“ s živým RUČNÍM dobropisem (část ceny placená převodem — obsluha ji
        // teprve posílá, potvrdí „Vratka odeslána“) se no_op na kartě neuzavírá — dřív 'refunded', i když převod neodešel.
        const keepManual = closeIt && cancelBk?.payment_status === 'refund_pending' && await hasLiveManualCreditNote(supabase, booking_id)
        await dlog('refund_noop', 'info', { payment_status: keepManual ? 'refund_pending' : closeIt ? 'refunded' : 'partial_refund', others_known: othersKnown,
          stored_type: (storedPi?.metadata || {}).type || null, manual_pending: keepManual })
        if (!keepManual) await supabase.from('bookings').update({ payment_status: closeIt ? 'refunded' : 'partial_refund' }).eq('id', booking_id)
      } else if (order_id) {
        await supabase.from('shop_orders').update({ payment_status: 'refunded' }).eq('id', order_id)
      }
      return new Response(
        JSON.stringify({
          success: true,
          refund_id: null,
          status: 'no_op',
          amount_refunded: 0,
          currency: 'czk',
          credit_note_id: null,
          card_brand: null,
          card_last4: null,
          note: 'Nothing left to refund (already refunded or amount paid was 0)',
        }),
        { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    // Create Stripe refund. Metadata mg_* označují refund jako NÁŠ (interní) —
    // webhook-receiver charge.refunded podle nich pozná, že dobropis/mail/stavy
    // řeší tohle flow, a rezervaci NEzruší jako „Stripe portál storno"
    // (incident #DDC5A69D 2026-08-12: částečná vratka výměny motorky → auto-storno).
    // Požadavek celé vratky (hlavní + zbytek z ostatních plateb): zákazník jen do ověřeného přeplatku.
    const requestedHaleru = reqAmount && reqAmount > 0 ? Math.round(reqAmount * 100) : null
    const targetHaleru = requestedHaleru == null ? null
      : (isCustomer ? Math.min(requestedHaleru, customerCapH ?? 0) : requestedHaleru)
    const refundParams: Stripe.RefundCreateParams = {
      payment_intent: stripePaymentIntentId,
      reason: reason === 'duplicate' ? 'duplicate' : 'requested_by_customer',
      metadata: {
        mg_source: 'process-refund',
        mg_reason: reason || '',
        mg_booking_id: booking_id || '',
        mg_order_id: order_id || '',
        // Více plateb (2026-11-05): požadavek celé vratky (haléře) — webhook pozná, že tahle vratka je jen
        // část (zbytek z jiných plateb), recovery dovrátí storno do něj (cancel-once-pool.ts).
        ...(booking_id && targetHaleru != null ? { mg_target: String(targetHaleru) } : {}),
        // i2: požadavek vč. části zaplacené převodem (ruční dobropis po této vratce) — duplicita téhož požadavku obsluhy
        ...(booking_id && targetHaleru != null && nonStripeOwedH > 0 ? { mg_requested: String(targetHaleru + nonStripeOwedH) } : {}),
        // HOTFIX storno 2026-10-29: identita storna (cancel-once.ts); mg_cancel_total = vráceno k tomuto
        // stornu celkem vč. tohoto požadavku (pojistný mail webhooku — cancel-mail-amount.ts).
        ...(booking_id && reason === 'cancellation' ? { mg_cancel_at: cancelTok,
          ...(targetHaleru != null ? { mg_cancel_total: String(cancelDoneHaleru + targetHaleru) } : {}),
          // neúplný pool: mg_cancel_total jen z uložené platby (podhodnocený cíl = bezpečný pro dovracení, špatný pro
          // text mailu) → pojistný mail webhooku ho nepoužije (cancel-mail-amount.ts) — oprava i1 2026-11-05
          ...(poolComplete ? {} : { mg_pool_incomplete: '1' }) } : {}),
      },
    }
    if (effectiveAmountHaleru != null && (refundableHaleru == null || effectiveAmountHaleru < refundableHaleru)) {
      refundParams.amount = effectiveAmountHaleru
    }

    // Stripe idempotency key — dva souběžné dispatche TÉŽE refundace (pg_net z RPC
    // + recovery retry v send-booking-email startují dřív, než první stihne zapsat
    // credit_note) se na Stripe srazí do JEDNOHO refundu. Sekvenční složka =
    // `refundableHaleru` (charged − už refundováno na PI): souběžné duplicity ho
    // vidí stejné → stejný klíč → jeden refund; legitimní DALŠÍ refund (klidně
    // stejné částky) přijde až po provedení předchozího → refundable kleslo →
    // jiný klíč. Fallback na počet dobropisů, když PI lookup selhal.
    let seqPart: number | string | null = refundableHaleru
    if (seqPart == null) {
      try {
        let cq = supabase.from('invoices')
          .select('id', { count: 'exact', head: true })
          .eq('type', 'credit_note').neq('status', 'cancelled')
        cq = booking_id ? cq.eq('booking_id', booking_id) : cq.eq('order_id', order_id)
        const { count } = await cq
        seqPart = `cn${count || 0}`
      } catch { seqPart = 'na' }
    }
    // Oprava i4 (2026-11-07, S1a–S1c): selhaná vratka refundable nesníží → po pádu by klíč byl stejný a Stripe by do 24 h
    // přehrál selhanou vratku místo nové. Přípona = počet selhaných / zrušených vratek platby, ze které se vrací (retry-key.ts).
    let mainFailed: string[] = []
    try {
      const listFor = stripePaymentIntentId && stripePaymentIntentId === (storedPi?.id || null) ? storedRefunds
        : (await stripe.refunds.list({ payment_intent: stripePaymentIntentId, limit: 100 })).data
      mainFailed = failedRefundIds(listFor as unknown as Array<{ id?: string; status?: string }>)
    } catch (e) { console.warn('[process-refund] failed-refund lookup for key failed:', (e as Error).message) }
    const idempotencyKey = `refund:${booking_id || order_id}:${effectiveAmountHaleru ?? 'full'}:${seqPart}${retrySuffix(mainFailed)}`

    await dlog('stripe_refund_create_pre', 'info', { effectiveAmountHaleru, refundableHaleru, idempotency_key: idempotencyKey })
    const refund = await stripe.refunds.create(refundParams, { idempotencyKey })
    if (isReplayOfFailed(refund.id, mainFailed)) {
      // Stripe přehrál vratku, která už selhala (klíč staré verze / souběh) → peníze neodešly: bez zápisu stavu, dobropisu i zbytku.
      await dlog('stripe_refund_replayed_failed', 'error', { refund_id: refund.id, idempotency_key: idempotencyKey })
      throw new Error(`${REPLAYED_FAILED} ${refund.id}`)
    }
    await dlog('stripe_refund_create_ok', 'info', { refund_id: refund.id, refund_status: refund.status, refund_amount: refund.amount })

    // Vratka větší, než zbývá na hlavní platbě (doplatky úprav a výměn vč. dorovnání na 15 Kč
    // se platily jinými PaymentIntenty) → zbytek z ostatních plateb TÉŽE rezervace (odpověď
    // majitele 2026-10-16: dorovnání se při stornu vrací poměrně jako zbytek ceny). Zákaznická
    // vratka (appka; oprava f2 2026-10-22) stejně, ale celkem jen do ověřeného přeplatku
    // (customerCapH) — dřív šla jen z hlavní platby a zbytek se tiše ztratil.
    let extra: { refunds: ExtraRefund[]; refundedHaleru: number; leftHaleru: number; error?: string } =
      { refunds: [], refundedHaleru: 0, leftHaleru: 0 }
    if (booking_id && targetHaleru != null && effectiveAmountHaleru != null && targetHaleru > effectiveAmountHaleru) {
      extra = await refundRemainder(stripe as unknown as OtherIntentsStripe, supabase, {
        bookingId: booking_id, mainPi: stripePaymentIntentId, mainRefundId: refund.id, remainingHaleru: targetHaleru - effectiveAmountHaleru, reason,
        // storno: zbytek nese identitu storna (cancel-once.ts)
        ...(reason === 'cancellation' ? { metadata: { mg_cancel_at: cancelTok } } : {}),
      })
      await dlog(extra.error ? 'stripe_refund_remainder_partial' : 'stripe_refund_remainder', extra.error ? 'error' : 'info', {
        requested_haleru: requestedHaleru, target_haleru: targetHaleru, main_haleru: effectiveAmountHaleru, extra: extra.refunds,
        left_haleru: extra.leftHaleru, error: extra.error || null,
      })
    }
    // Co se z požadované částky automaticky NEvrátilo (zákazník: nad ověřený přeplatek, nebo
    // ostatní platby nestačily / selhaly) → obsluha (mail), rezervace partial_refund, odpověď
    // `partial: true` (appka pak neslibuje celou částku — pdRefundManual). Zákazník: zbytek
    // do 1 Kč = zaokrouhlení ceny na haléře → jen záznam (CUSTOMER_SHORT_TOLERANCE_HALERU).
    const shortRaw = booking_id && requestedHaleru != null && effectiveAmountHaleru != null
      ? Math.max(0, requestedHaleru - effectiveAmountHaleru - extra.refundedHaleru) : 0
    let shortHaleru = isCustomer && shortRaw <= CUSTOMER_SHORT_TOLERANCE_HALERU ? 0 : shortRaw
    if (shortRaw > 0 && !shortHaleru) await dlog('refund_short_rounding', 'info', { short_haleru: shortRaw })
    // Oprava i4 (2026-11-07, S2 / S3): obsluha / služba žádá víc, než rezervace dle dokladů zaplatila (nezaplacený doplatek
    // úpravy „Zákazník doplatí“ je v total_price → storno % × cena; „Potvrdit vrácení“ jiné částky po stornu) a po této
    // vratce už dle dokladů (DP − dobropisy, jako _cap_refund_to_paid) nic nedlužíme → nic nechybí: bez mailu obsluze
    // „vraťte ručně“, odpověď partial:false s vrácenou částkou, stav dle skutečnosti. Zbývá-li dle dokladů méně, než
    // požadavek přesahuje, hlásí se jen to (např. část zaplacená převodem). Bez DP / chyba čtení → jako dřív.
    if (booking_id && !isCustomer && shortHaleru > 0 && !extra.error) {
      try {
        const owed = docsOwedCzk(await docSums(supabase, booking_id))
        if (owed != null) {
          const owedAfterH = Math.max(0, Math.round(owed * 100) - Number(refund.amount || 0) - extra.refunds.reduce((t, x) => t + x.amountHaleru, 0))
          const cut = owedAfterH <= 100 ? shortHaleru : Math.max(0, shortHaleru - owedAfterH)
          if (cut > 0) {
            const { data: sur } = await supabase.from('bookings').select('mod_surcharge_due, mod_surcharge_paid_at').eq('id', booking_id).maybeSingle()
            await dlog('refund_request_above_paid', 'info', { requested_haleru: requestedHaleru, short_haleru: shortHaleru, docs_owed_after_haleru: owedAfterH,
              not_owed_haleru: cut, unpaid_surcharge: sur && !sur.mod_surcharge_paid_at ? Number(sur.mod_surcharge_due) || null : null })
            shortHaleru -= cut
          }
        }
      } catch (e) { await dlog('refund_short_docs_failed', 'warning', { error: (e as Error).message }) }
    }
    // Zbytek nad možnosti plateb rezervace BEZ chyby = trvale → cíl na hlavní vratce (mg_target, mg_cancel_total)
    // snížit na skutečně vrácené, ať recovery (cancel-once-pool.ts) vratku nepovažuje za nedokončenou.
    // Chyba vratky z dalších plateb = přechodné → cíl zůstává, dovrátí další volání / recovery.
    if (booking_id && shortRaw > 0 && !extra.error && targetHaleru != null) {
      const achieved = Number(refund.amount || 0) + extra.refundedHaleru
      try {
        await stripe.refunds.update(refund.id, { metadata: { mg_target: String(achieved),
          ...(reason === 'cancellation' ? { mg_cancel_total: String(cancelDoneHaleru + achieved) } : {}) } })
      } catch (e) { await dlog('refund_target_update_failed', 'error', { refund_id: refund.id, error: (e as Error).message }) }
    }
    if (shortHaleru > 0) {
      const reqH = requestedHaleru ?? 0
      const doneH = Number(refund.amount || 0) + extra.refundedHaleru
      await dlog('refund_short', 'error', { requested_haleru: requestedHaleru, refunded_haleru: doneH, short_haleru: shortHaleru,
        customer_cap_haleru: customerCapH, customer: isCustomer })
      const num = String(booking_id).slice(-8).toUpperCase()
      await sendOpsMail(
        isCustomer ? `⚠️ Vratku za úpravu rezervace #${num} dořešte ručně (vráceno jen částečně)` : '⚠️ Vratka rezervace se nevrátila celá automaticky',
        `<p>Rezervace <strong>${isCustomer ? '#' + num : booking_id}</strong> (${reasonTextFor(reason)}): požadováno <strong>${reqH / 100} Kč</strong>, `
        + `automaticky vráceno <strong>${doneH / 100} Kč</strong> `
        + `(hlavní platba ${stripePaymentIntentId}${extra.refunds.length ? ', další platby ' + extra.refunds.map((x) => x.piId).join(', ') : ''}), `
        + `zbývá <strong>${shortHaleru / 100} Kč</strong>.</p>`
        + (isCustomer
          ? `<p>Úprava v aplikaci je uložená. Automaticky se vrací jen ověřený přeplatek (platby kartou v ceně rezervace − vrácené − aktuální cena = ${(customerCapH ?? 0) / 100} Kč)${extra.error ? ' a vratka z dalších plateb selhala (debug log stripe_refund_remainder_partial)' : ''}. Zákazník v aplikaci vidí, že zbytek vratky dokončí obsluha.</p>`
          : (extra.error ? '<p>Vratka z dalších plateb selhala (debug log stripe_refund_remainder_partial).</p>' : ''))
        + (isCustomer || reason !== 'cancellation' ? `<p>Zbytek: ${STAFF_REFUND_HOWTO}</p>` : '<p>Zbytek zkontrolujte a případně vraťte ručně ve Velíně („Potvrdit vrácení“ u zrušené rezervace).</p>'),
      )
    }

    // Look up card brand/last4 from the underlying Charge (used both on credit note and bookings).
    let cardBrand: string | null = null
    let cardLast4: string | null = null
    try {
      const chargeId = typeof refund.charge === 'string' ? refund.charge : (refund.charge as any)?.id
      if (chargeId) {
        const ch = await stripe.charges.retrieve(chargeId)
        cardBrand = ch?.payment_method_details?.card?.brand || null
        cardLast4 = ch?.payment_method_details?.card?.last4 || null
      }
    } catch (e) { console.warn('[process-refund] charge retrieve failed:', (e as Error).message) }

    // Update payment_status in DB
    const refundedAmountCZK = (Number(refund.amount || 0) + extra.refundedHaleru) / 100
    let finalStatus: string | null = null
    if (booking_id) {
      // Mapování na payment_status dle reality vrácení peněz:
      //  - Stripe refund ještě nepotvrzen (status='pending') → 'refund_pending' (Čeká na vrácení).
      //    Finální stav dorazí webhookem charge.refunded / refund.updated.
      //  - částečné vrácení (zadaná `amount` menší než zbývající k vrácení) → 'partial_refund'.
      //  - jinak (plné vrácení / succeeded) → 'refunded'.
      // Zákaznická vratka = jen přeplatek → rezervace s nenulovou cenou zůstává zaplacená
      // (i když se tím vyčerpá aktuální PI, např. doplatkový).
      // i3: zbytek hlavní platby V CENĚ (bez přibalené e-shop části) — 100% storno 3000 z platby 3000 + zboží 500 = 'refunded'
      let newStatus = refundedStatus({ refundStatus: refund.status, isCustomer, bookingTotalPrice, amount: reqAmount,
        refundableHaleru: inPriceRefundableH, effectiveAmountHaleru, leftHaleru: extra.leftHaleru, shortHaleru, fullBalance,
        extraStatuses: extra.refunds.map((x) => x.status) })
      // Více plateb (2026-11-05): 'refunded' = na žádné platbě V CENĚ rezervace nic nezbývá (idempotentní větev
      // „už vráceno“ pak storno odmítne). Vratka s částkou, která přesně vyčerpala hlavní platbu (např. vrácení
      // doplatku 115 Kč z uložené platby doplatku), dřív rezervaci uzavřela, i když na původní platbě zbývalo vše.
      if (newStatus === 'refunded' && !fullBalance && reqAmount && reqAmount > 0) {
        try {
          const others = await otherRefundableIntents(stripe as unknown as OtherIntentsStripe, supabase, booking_id, stripePaymentIntentId)
          if (others.some((c) => c.refundableHaleru > 0)) {
            newStatus = 'partial_refund'
            await dlog('refunded_status_other_payments_left', 'info', { left_haleru: others.reduce((t, c) => t + c.refundableHaleru, 0) })
          }
        } catch (e) {
          // Oprava i1 (2026-11-05): nevíme, zda na ostatních platbách něco nezbývá → neuzavírat (další plné volání
          // skončí 'refunded' přes no_op, až se nic nenajde).
          newStatus = 'partial_refund'
          await dlog('refunded_status_check_failed', 'error', { error: (e as Error).message })
        }
      }
      // Oprava i1 (2026-11-05): zbytek z ostatních plateb selhal / nevrátilo se vše → nikdy 'refunded' (dovrátí
      // další storno volání / recovery, Velín „Potvrdit vrácení“ zůstává možné).
      if (newStatus === 'refunded' && (extra.error || shortHaleru > 0)) newStatus = 'partial_refund'
      finalStatus = newStatus
      const bkPatch: Record<string, any> = { payment_status: newStatus, stripe_refund_id: refund.id }
      if (cardBrand) bkPatch.card_brand = cardBrand
      if (cardLast4) bkPatch.card_last4 = cardLast4
      await supabase.from('bookings').update(bkPatch).eq('id', booking_id)
    } else if (order_id) {
      await supabase.from('shop_orders')
        .update({ payment_status: 'refunded' })
        .eq('id', order_id)
    }

    // Auto-generate credit note (dobropis) for booking refunds
    let creditNoteId: string | null = null
    if (booking_id) {
      try {
        // Fetch booking data for the credit note
        const { data: bk } = await supabase.from('bookings')
          .select('user_id, total_price, start_date, end_date, motorcycles!moto_id(model), profiles:user_id(id, full_name, email, phone, street, city, zip, ico, dic)')
          .eq('id', booking_id).single()
        if (bk) {
          const refundPercent = amount ? Math.round((amount / Number(bk.total_price || 1)) * 100) : 100
          const reasonText = reasonTextFor(reason)

          // Find original invoice to reference
          const { data: origInvs } = await supabase.from('invoices')
            .select('id, type, number')
            .eq('booking_id', booking_id)
            .neq('status', 'cancelled')
            .in('type', ['final', 'payment_receipt', 'advance', 'proforma'])
            .order('issue_date', { ascending: false })
            .limit(1)
          const originalInvoiceId = origInvs?.[0]?.id || null
          const originalInvoiceNumber = origInvs?.[0]?.number || null

          const cnNotes = `Dobropis k rezervaci. ${refundPercent < 100 ? `Částečný refund ${refundPercent}%.` : 'Plný refund.'} ${reasonText}`
            + (extra.refunds.length ? ` Vráceno z více plateb: ${refund.id} + ${extra.refunds.map((x) => x.refundId).join(', ')}.` : '')
          // Výpůjčka výbavy (2026-10-23): bez motorky → „výpůjčka výbavy“ (gear) / „motorky“ (gear.ts).
          const cnMotoModel = (bk as any).motorcycles?.model || await noMotoRefundSubject(supabase, booking_id)

          // Idempotency: if a credit_note already exists for this booking + refund, reuse it
          const { data: existingCn } = await supabase.from('invoices')
            .select('id, number, pdf_path, total, status')
            .eq('booking_id', booking_id)
            .eq('type', 'credit_note')
            .eq('stripe_refund_id', refund.id)
            .limit(1)
          let cnNumber: string
          let cnId: string | null = null

          if (existingCn?.length) {
            cnId = existingCn[0].id
            cnNumber = existingCn[0].number
            // Oprava f3: dobropis mohla k této vratce vystavit recovery z webhooku charge.refunded
            // dřív, než tohle volání vrátilo zbytek z ostatních plateb — jen z částky hlavní vratky.
            // Dorovnat na skutečně vrácenou částku (položka, základ, celkem, poznámka, účetní záznam).
            if (existingCn[0].status !== 'cancelled') {
              try {
                const fixed = await reconcileCreditNote(supabase, { cnId: cnId!, cnNumber, bookingId: booking_id,
                  currentTotal: Number(existingCn[0].total || 0), targetCzk: refundedAmountCZK,
                  description: `Dobropis – ${reasonText} (${cnMotoModel})`, reasonText, notes: cnNotes,
                  issueDate: new Date().toISOString().slice(0, 10) })
                if (fixed != null) await dlog('credit_note_reconciled', 'info', { credit_note_id: cnId, from: existingCn[0].total, to: -fixed })
              } catch (e) {
                await dlog('credit_note_reconcile_failed', 'error', { credit_note_id: cnId, error: (e as Error).message })
              }
            }
          } else {
            // Číslo dobropisu (DB-YYYY-NNNN) — atomicky, automatická řada < 5000.
            cnNumber = await nextDocNumber(supabase, 'DB')

            const issueDate = new Date().toISOString().slice(0, 10)
            const motoModel = cnMotoModel
            const { data: cnInv, error: cnErr } = await supabase.from('invoices').insert({
              number: cnNumber,
              type: 'credit_note',
              customer_id: bk.user_id,
              booking_id,
              items: [{
                description: `Dobropis – ${reasonText} (${motoModel})`,
                qty: 1,
                unit_price: -refundedAmountCZK,
              }],
              subtotal: -refundedAmountCZK,
              tax_amount: 0,
              total: -refundedAmountCZK,
              notes: cnNotes,
              issue_date: issueDate,
              due_date: issueDate,
              status: 'issued',
              source: 'refund',
              variable_symbol: cnNumber,
              original_invoice_id: originalInvoiceId,
              stripe_refund_id: refund.id,
            }).select('id').single()

            cnId = cnInv?.id || null
            let reused = false, reusedPdf: string | null = null
            if (!cnId && isUniqueViolation(cnErr)) {
              // Oprava i1 (2026-11-05): souběžný dispatch téže vratky (Stripe ji sloučil idempotency klíčem) vystavil
              // dobropis o chlup dřív — unikátní index uq_invoices_credit_note_refund (SQL návrh 20261105a) druhý
              // INSERT odmítl → převzít ten jeho (bez mailu obsluze; číslo řady propadne).
              const { data: again } = await supabase.from('invoices').select('id, number, pdf_path')
                .eq('stripe_refund_id', refund.id).eq('type', 'credit_note').neq('status', 'cancelled').limit(1)
              if (again?.length) {
                reused = true
                await dlog('credit_note_insert_reused', 'info', { credit_note_id: again[0].id, number: again[0].number, lost_number: cnNumber })
                cnId = again[0].id; cnNumber = again[0].number; reusedPdf = again[0].pdf_path || null
              }
            }
            if (cnId && !cnErr) {
              // Oprava i2 (2026-11-05): bez unikátního indexu (SQL návrh 20261105a) — souběžný dispatch vložil dobropis
              // k téže vratce mezi kontrolou a INSERTem → ponechat jen nejstarší, náš zrušit (bez účetního záznamu).
              const dupe = await cancelDuplicateCreditNote(supabase, { cnId, cnNumber, refundId: refund.id, bookingId: booking_id })
              if (dupe) { reused = true; cnId = dupe.id; cnNumber = dupe.number || cnNumber; reusedPdf = dupe.pdf_path }
            }
            if (reused) creditNoteId = cnId
            else if (cnErr || !cnId) {
              // Stripe refund UŽ PROBĚHL — bez dobropisu by k vrácené částce
              // nebyl daňový doklad a dřív se to tiše zalogovalo jako úspěch.
              await dlog('credit_note_insert_failed', 'error', {
                booking_id, number: cnNumber, error: cnErr?.message || 'insert vrátil prázdno',
              })
              await sendOpsMail(
                '⚠️ Dobropis se nevystavil — vratka ale odešla',
                `<p>Rezervace <strong>${booking_id}</strong>: Stripe refund <code>${refund.id}</code> `
                + `proběhl na <strong>${refundedAmountCZK} Kč</strong>, ale zápis dobropisu `
                + `<strong>${cnNumber}</strong> selhal: ${cnErr?.message || 'prázdná odpověď'}.</p>`
                + '<p>Peníze zákazníkovi odešly, daňový doklad k nim ale chybí — '
                + 'vystavte dobropis ručně ve Velíně.</p>',
              )
            } else if (!cnErr) {
              await dlog('credit_note_inserted', 'info', { credit_note_id: cnId, number: cnNumber })
            }

            // Create negative accounting entry only on first creation
            if (cnId && !cnErr && !reused) {
              await supabase.from('accounting_entries').insert({
                type: 'expense',
                amount: -refundedAmountCZK,
                description: `Dobropis ${cnNumber} – ${reasonText}`,
                category: 'refund',
                date: issueDate,
                booking_id,
              })
            }
            if (reused && reusedPdf) cnId = null // dobropis i PDF už má souběžné volání (bez PDF ho dorenderujeme my)
          }

          if (cnId) creditNoteId = cnId

          // Render and upload dobropis PDF/HTML so it can be attached to the cancellation email.
          if (cnId) {
            try {
              // Výpůjčka výbavy (2026-10-23): bez motorky → „výpůjčka výbavy“ (gear) / „motorky“ (gear.ts).
              const motoModel2 = (bk as any).motorcycles?.model || await noMotoRefundSubject(supabase, booking_id)
              const cust4 = (bk as any).profiles || {}
              await loadCustomerCompany(supabase, cust4)
              const html = renderCreditNoteHtml({
                number: cnNumber,
                issueDate: fmtDate(new Date().toISOString().slice(0, 10)),
                reasonText,
                motoModel: motoModel2,
                refundAmount: refundedAmountCZK,
                refundPercent,
                bookingDates: `${fmtDate(bk.start_date)} – ${fmtDate(bk.end_date)}`,
                customer: cust4,
                originalInvoiceNumber,
                stripeRefundId: refund.id,
                cardBrand,
                cardLast4,
              })
              const pdfBytes = await htmlToPdf(html)
              await dlog('pdfshift_render_done', 'info', { credit_note_id: cnId, has_pdf: !!pdfBytes, pdf_bytes: pdfBytes?.length || 0 })
              let path: string
              if (pdfBytes) {
                path = `invoices/${cnId}.pdf`
                const { error: upErr } = await supabase.storage.from('documents').upload(
                  path, new Blob([pdfBytes], { type: 'application/pdf' }),
                  { upsert: true, contentType: 'application/pdf' },
                )
                if (upErr) await dlog('pdf_upload_failed', 'error', { path, error: upErr.message })
              } else {
                path = `invoices/${cnId}.html`
                const { error: upErr } = await supabase.storage.from('documents').upload(
                  path, new Blob([html], { type: 'text/html' }),
                  { upsert: true, contentType: 'text/html' },
                )
                if (upErr) await dlog('pdf_upload_failed', 'error', { path, error: upErr.message })
              }
              const { error: updErr } = await supabase.from('invoices').update({ pdf_path: path }).eq('id', cnId)
              await dlog('credit_note_finalized', updErr ? 'error' : 'ok', { credit_note_id: cnId, pdf_path: path, update_error: updErr?.message })
            } catch (pdfErr) {
              console.warn('[process-refund] credit note PDF render failed:', (pdfErr as Error).message)
              await dlog('pdfshift_render_failed', 'error', { credit_note_id: cnId, error: (pdfErr as Error).message })
            }
          }
        }
      } catch (cnErr) {
        console.error('Credit note generation failed:', (cnErr as Error).message)
        // Non-blocking — refund was already processed
      }
    }

    // Oprava i2 (2026-11-05): část ceny zaplacená mimo Stripe (doplatek převodem / QR) — po vratce kartou ruční
    // dobropis na zbytek dle dokladů (manualBookingRefund: Fio příkaz, jinak 'refund_pending' + banner ve Velíně)
    // a mail obsluze. Dřív se tahle část nevrátila nikdy a rezervace skončila 'refunded'.
    let manualPart: { amount: number; credit_note_id: string | null; fio_sent: boolean; code: string | null } | null = null
    if (booking_id && nonStripeOwedH > 0) {
      const num = bookingNum(booking_id)
      try {
        const mr = await manualBookingRefund(supabase, booking_id, nonStripeOwedH / 100, reason, dlog, false)
        const mj = await mr.json().catch(() => ({})) as Record<string, any>
        manualPart = { amount: Number(mj.amount) || 0, credit_note_id: mj.credit_note_id ?? null, fio_sent: mj.fio_sent === true, code: mj.code ?? null }
        if (manualPart.fio_sent && finalStatus) await supabase.from('bookings').update({ payment_status: finalStatus }).eq('id', booking_id)
        await dlog('full_refund_non_stripe_part_done', 'info', { ...manualPart, payment_status: manualPart.fio_sent ? finalStatus : 'refund_pending' })
        await sendOpsMail(
          `${manualPart.fio_sent ? 'ℹ️' : '⚠️'} Storno #${num}: ${refundedAmountCZK.toLocaleString('cs-CZ')} Kč vráceno na kartu, ${manualPart.amount.toLocaleString('cs-CZ')} Kč bylo zaplaceno převodem`,
          `<p>Rezervace <strong>#${num}</strong> (${booking_id}, ${reasonTextFor(reason)}): na kartu se vrátilo <strong>${refundedAmountCZK.toLocaleString('cs-CZ')} Kč</strong> `
          + `(Stripe ${stripePaymentIntentId}); část ceny <strong>${manualPart.amount.toLocaleString('cs-CZ')} Kč</strong> byla zaplacena převodem / QR → `
          + (manualPart.fio_sent
            ? 'vratka odeslána automaticky přes Fio (dobropis vystaven).</p>'
            : `ruční dobropis vystaven, rezervace je ve stavu „Čeká na vrácení“ — pošlete <strong>${manualPart.amount.toLocaleString('cs-CZ')} Kč</strong> převodem na účet zákazníka a potvrďte ve Velíně tlačítkem „Vratka odeslána“.</p>`),
        )
      } catch (e) {
        await dlog('full_refund_non_stripe_part_failed', 'error', { non_stripe_haleru: nonStripeOwedH, error: (e as Error).message })
        await sendOpsMail(`⚠️ Storno #${num}: ${nonStripeOwedH / 100} Kč zaplacených převodem se nevrátilo`,
          `<p>Rezervace <strong>#${num}</strong> (${booking_id}): na kartu se vrátilo ${refundedAmountCZK} Kč, ale ruční dobropis na část zaplacenou převodem `
          + `(<strong>${nonStripeOwedH / 100} Kč</strong>) se nepodařilo vystavit (${(e as Error).message}). Vraťte převodem a dobropis vystavte ručně ve Velíně.</p>`)
      }
    }

    // Log to debug_log
    try {
      await supabase.from('debug_log').insert({
        source: 'process-refund',
        action: 'stripe_refund_created',
        component: entityType,
        status: 'ok',
        request_data: { booking_id, order_id, amount, reason },
        response_data: { refund_id: refund.id, status: refund.status, amount_refunded: refundedAmountCZK, credit_note_id: creditNoteId, extra_refunds: extra.refunds,
          short_haleru: shortHaleru, manual_part: manualPart },
      })
    } catch (e) { /* ignore */ }

    return new Response(
      JSON.stringify({
        success: true,
        refund_id: refund.id,
        status: refund.status,
        // i2: část zaplacená převodem se počítá jako vrácená jen po odeslání Fio příkazu
        amount_refunded: refundedAmountCZK + (manualPart?.fio_sent ? manualPart.amount : 0),
        currency: refund.currency,
        credit_note_id: creditNoteId,
        card_brand: cardBrand,
        card_last4: cardLast4,
        // f2: automaticky se nevrátila celá požadovaná částka (zbytek vyřídí obsluha); i2: část převodem čeká na obsluhu
        partial: shortHaleru > 0 || (!!manualPart && !manualPart.fio_sent),
        requested_amount: requestedHaleru != null ? (requestedHaleru + nonStripeOwedH) / 100 : null,
        ...(manualPart ? { manual_part: manualPart } : {}),
        // i4 (S2): storno — vráceno k TOMUTO stornu celkem (dřívější vratky + tato; Velín „Potvrdit vrácení“ jiné částky
        // po stornu vrací rozdíl navíc → mail a booking_cancellations nesou skutečný součet, ne zvolenou částku)
        ...(booking_id && reason === 'cancellation' && poolComplete ? { cancel_refunded_total: (cancelDoneHaleru + Number(refund.amount || 0) + extra.refundedHaleru) / 100 } : {}),
      }),
      { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    console.error('Refund error:', err)

    try {
      await supabase.from('debug_log').insert({
        source: 'process-refund',
        action: 'stripe_refund_error',
        component: 'stripe',
        status: 'error',
        error_message: (err as Error).message,
        request_data: { booking_id: ctx.bookingId, amount: ctx.amount, reason: ctx.reason, customer: ctx.isCustomer },
      })
    } catch (e) { /* ignore */ }
    // Oprava i2 (2026-11-05): zákaznická vratka z appky (po zkrácení / levnější motorce) spadla → appka ukáže
    // „vratku dokončí obsluha“, ale nikdo se to nedozvěděl (jen debug_log bez rezervace). Mail obsluze (dedup 10 min).
    if (ctx.isCustomer && ctx.bookingId) {
      const num = bookingNum(ctx.bookingId)
      await opsMailOnce(supabase, ctx.bookingId, 'customer_refund_failed_mail',
        `⚠️ Vratka za úpravu rezervace #${num} selhala — vyřiďte ručně`,
        `<p>Zákazník v aplikaci upravil rezervaci <strong>#${num}</strong> (${ctx.bookingId}, ${reasonTextFor(typeof ctx.reason === 'string' ? ctx.reason : null)}) `
        + `a požádal o vrácení <strong>${Number(ctx.amount) || 0} Kč</strong>, ale vratka spadla chybou: ${(err as Error).message}.</p>`
        + `<p>Zákazník v aplikaci vidí, že vratku dokončí obsluha. ${STAFF_REFUND_HOWTO}</p>`,
        { error: (err as Error).message }).catch(() => {})
    } else if (ctx.bookingId) {
      // Oprava i4 (2026-11-07, S6): vratka z webu (RPC zkrácení / výbava přes pg_net), Velínu i služby spadla → obsluha
      // to musí vědět (dřív jen debug_log; mail úpravy zákazníkovi pak zprávu o vratce převzal od dřívějšího dobropisu).
      const num = bookingNum(ctx.bookingId)
      await opsMailOnce(supabase, ctx.bookingId, 'refund_failed_mail',
        `⚠️ Vratka k rezervaci #${num} selhala — zkontrolujte`,
        `<p>Rezervace <strong>#${num}</strong> (${ctx.bookingId}, ${reasonTextFor(typeof ctx.reason === 'string' ? ctx.reason : null)}): vratka `
        + `<strong>${Number(ctx.amount) > 0 ? `${Number(ctx.amount)} Kč` : 'celého zůstatku'}</strong> spadla chybou: ${(err as Error).message}.</p>`
        + `<p>Nic se nevrátilo (nebo jen část — viz Stripe). Storno: zopakujte „Potvrdit vrácení“ ve Velíně. Úprava / zkrácení: ${STAFF_REFUND_HOWTO}</p>`,
        { error: (err as Error).message, caller: caller.kind }).catch(() => {})
    }

    return new Response(
      JSON.stringify({ success: false, error: 'Refund failed: ' + (err as Error).message }),
      { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } }
    )
  } finally {
    if (cancelLockBooking) await releaseCancelLock(supabase, cancelLockBooking)
  }
})
