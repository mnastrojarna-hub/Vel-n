// ===== webhook-receiver/refund-updated.ts =====
// Oprava i2 (2026-11-05): Stripe vratka vytvořená jako „pending“ (nízký zůstatek účtu) — process-refund zapíše
// 'refund_pending'; charge.refunded dorazí ještě s pending vratkou (syncRefundBooking mění stav jen z 'paid') a
// když vratka později uspěje, Stripe pošle `charge.refund.updated` / `refund.updated`, které se dřív nezpracovávaly
// → rezervace zůstala v „Čeká na vrácení“ napořád (Velín sváděl k další vratce). Teď:
//  • status 'succeeded' → rezervace s touto vratkou (bookings.stripe_refund_id = refund.id, nebo metadata
//    mg_booking_id) ve stavu 'refund_pending' → compare-and-set na 'refunded' (na platbách V CENĚ rezervace nic
//    nezbývá — staffFullBalanceHaleru jako process-refund) / 'partial_refund' (něco zbývá, nebo nelze zjistit).
//    Živý RUČNÍ dobropis (část ceny placená převodem — obsluha ji teprve posílá) → stav nechat, jen záznam.
//  • status 'failed' / 'canceled' → peníze NEodešly: debug_log error + mail obsluze (dobropis je třeba zrušit,
//    vratku zopakovat); stav rezervace se nemění (zůstává „Čeká na vrácení“).
// Oprava i4 (2026-11-07, verify:refunds S1c / S5):
//  • selhaná / zrušená NAŠE vratka v ceně rezervace (mg_source process-refund, i zbytek z jiné platby) → rezervaci
//    znovu otevřít: compare-and-set 'refunded' / 'partial_refund' → 'refund_pending' (Velín „Potvrdit vrácení“,
//    recovery i další volání pak vratku zopakují — klíč se po pádu mění, process-refund/retry-key.ts),
//  • rezervace i podle metadata.booking_id (automatické vratky MIMO cenu: duplicitní platba, nezapsaná změna / obsazená
//    motorka při výměně, pozdní platba zrušené rezervace) — stav rezervace se jimi NEmění (peníze mimo cenu),
//  • mail obsluze při selhání VŽDY (i bez nalezené rezervace; 1× na vratku): částka, platba, zdroj, dobropis k vratce
//    a skutečný stav rezervace. Vratky mimo cenu mají pevný klíč (mg-dup- / mg-pcf- / mg-late-cancelled-) → samy se
//    nezopakují: vrátit ručně ve Stripe dashboardu.
// Oprava i5 (2026-11-07, verify:refunds V2 / V3 / V9): dobropis selhané vratky se sám zmenší na skutečně vrácenou část
// (0 → zrušen; mail už nevelí „zrušte dobropis“ a říká, kolik chybí vrátit), stará událost „failed“ po úspěšném
// opakování rezervaci znovu neotevírá — failed-refund.ts.
// Stripe endpoint musí události `charge.refund.updated` (případně `refund.updated`) odesílat — STATE_5.
import { staffFullBalanceHaleru, type OtherIntentsStripe } from '../process-refund/other-intents.ts'
import { failedRefundState, shrinkFailedRefundCreditNote, type FailedRefundState, type FailedRefundStripe } from './failed-refund.ts'

// deno-lint-ignore no-explicit-any
type Sb = any
type RefundObj = { id: string; status?: string | null; amount?: number | null; created?: number | null; payment_intent?: unknown; metadata?: Record<string, string> | null }
const OPS_EMAIL = 'info@motogo24.cz'

async function log(sb: Sb, action: string, status: string, data: Record<string, unknown>, err?: string) {
  try {
    await sb.from('debug_log').insert({ source: 'webhook-receiver', action, component: 'stripe', status, request_data: data, ...(err ? { error_message: err } : {}) })
  } catch { /* ignore */ }
}

async function opsMail(subject: string, html: string) {
  try {
    const url = Deno.env.get('SUPABASE_URL') ?? ''
    const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    await fetch(`${url}/functions/v1/send-email`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}`, apikey: key },
      body: JSON.stringify({ to: OPS_EMAIL, subject, raw_html: html }),
    })
  } catch { /* ignore */ }
}

const UUID_RX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
/** Vratky MIMO cenu rezervace (vlastní flow s pevným idempotency klíčem, bez dobropisu) — jako _shared/booking-intents.ts. */
const OUTSIDE_SOURCES: Record<string, string> = {
  duplicate_payment: 'duplicitní platba', unapplied_change: 'doplatek nezapsané změny', late_payment: 'pozdní platba zrušené rezervace',
}

/** Rezervace, ke které vratka patří (uložená vratka, metadata naší vratky, i4: metadata.booking_id vratek mimo cenu). */
async function bookingOfRefund(sb: Sb, r: RefundObj): Promise<Record<string, any> | null> {
  const cols = 'id, status, payment_status, stripe_refund_id, stripe_payment_intent_id'
  const { data: byId } = await sb.from('bookings').select(cols).eq('stripe_refund_id', r.id).maybeSingle()
  if (byId) return byId
  const md = r.metadata || {}
  for (const bid of [md.mg_booking_id, md.booking_id]) {
    if (!bid || !UUID_RX.test(bid)) continue
    const { data: byMd } = await sb.from('bookings').select(cols).eq('id', bid).maybeSingle()
    if (byMd) return byMd
  }
  return null
}

const PAY_LABEL: Record<string, string> = { paid: 'Zaplaceno', refund_pending: 'Čeká na vrácení', partial_refund: 'Částečně vráceno', refunded: 'Vráceno', unpaid: 'Nezaplaceno' }

/** Oprava i4: selhaná / zrušená vratka — znovu otevřít rezervaci (jen naše vratka v ceně) a VŽDY mail obsluze (1× na vratku).
 *  i5: dobropis se sám zmenší na skutečně vrácenou část (failed-refund.ts); stará událost po úspěšném opakování
 *  rezervaci neotevírá (superseded). */
async function onRefundFailed(sb: Sb, stripe: FailedRefundStripe, r: RefundObj, status: string, bk: Record<string, any> | null): Promise<void> {
  const md = r.metadata || {}
  const src = String(md.mg_source || '')
  const ours = src === 'process-refund'
  const outside = OUTSIDE_SOURCES[src] || null
  const amt = Number(r.amount || 0) / 100
  const pi = typeof r.payment_intent === 'string' ? r.payment_intent : ((r.payment_intent as { id?: string } | null)?.id ?? null)
  let payment = bk?.payment_status ?? null
  let reopened = false
  let st: FailedRefundState | null = null
  if (bk && ours) {
    try { st = await failedRefundState(sb, stripe, r, bk) } catch (e) { console.warn('[webhook] failed refund state:', (e as Error).message) }
  }
  if (bk && ours && st?.failedNow !== false && !st?.superseded) {
    try {
      const { data: upd, error } = await sb.from('bookings').update({ payment_status: 'refund_pending' })
        .eq('id', bk.id).in('payment_status', ['refunded', 'partial_refund']).select('id')
      reopened = !error && Array.isArray(upd) && upd.length > 0
      if (reopened) payment = 'refund_pending'
    } catch { /* stav beze změny */ }
  }
  // dobropis k vratce (zbytek z jiné platby patří k hlavní vratce — mg_main_refund) → i5: zmenšit na živou část
  let cn: { number: string | null; before: number; after: number | null } | null = null
  if (bk && ours && st && st.failedNow && st.liveHaleru != null) {
    try { cn = await shrinkFailedRefundCreditNote(sb, { bookingId: bk.id, mainId: st.mainId, refundId: r.id, amountKc: amt, liveHaleru: st.liveHaleru }) }
    catch (e) { await log(sb, 'refund_failed_credit_note_shrink_failed', 'error', { booking_id: bk.id, refund_id: r.id }, (e as Error).message) }
  } else if (bk) {
    try {
      const ids = [r.id, md.mg_main_refund].filter((x): x is string => !!x)
      const { data } = await sb.from('invoices').select('id, number, total').eq('booking_id', bk.id).eq('type', 'credit_note')
        .neq('status', 'cancelled').in('stripe_refund_id', ids).limit(1)
      if (data?.[0]) cn = { number: data[0].number || null, before: Math.abs(Number(data[0].total || 0)), after: null }
    } catch { /* bez údaje */ }
  }
  let dup = false
  try {
    const { data: prev } = await sb.from('debug_log').select('id').eq('source', 'webhook-receiver').eq('action', 'refund_updated_failed')
      .eq('request_data->>refund_id', r.id).limit(1)
    dup = !!prev?.length
  } catch { /* bez dedupu */ }
  await log(sb, 'refund_updated_failed', 'error', { booking_id: bk?.id ?? null, refund_id: r.id, status, amount: r.amount ?? null, payment_intent: pi,
    mg_source: src || null, payment_status: payment, reopened, credit_note: cn?.number ?? null, credit_note_after: cn?.after ?? null,
    live_haleru: st?.liveHaleru ?? null, superseded: st?.superseded ?? null }, `Stripe vratka ${r.id} skončila '${status}' — peníze zákazníkovi NEODEŠLY.`)
  if (st?.superseded) await log(sb, 'refund_updated_failed_superseded', 'info', { booking_id: bk?.id ?? null, refund_id: r.id, stored_refund_id: bk?.stripe_refund_id ?? null })
  if (dup) return
  const num = bk ? String(bk.id).slice(-8).toUpperCase() : null
  const what = `Stripe vratka <code>${r.id}</code> (${amt} Kč, platba <code>${pi || '?'}</code>, zdroj ${src || 'Stripe dashboard / neznámý'}${outside ? ` — ${outside}` : ''})`
  let todo: string
  if (outside || !ours) {
    todo = `<p>${outside ? 'Jde o automatickou vratku MIMO cenu rezervace s pevným klíčem — sama se NEzopakuje.' : 'Vratka nevznikla ve Velínu / aplikaci.'} `
      + 'Vraťte částku ručně ve Stripe dashboardu (platba výše → Refund).</p>'
  } else {
    const cnText = !cn ? 'Dobropis k této vratce nebyl nalezen.'
      : cn.after === 0 ? `Dobropis <strong>${cn.number}</strong> (${cn.before} Kč) byl automaticky zrušen — peníze neodešly.`
      : cn.after != null ? `Dobropis <strong>${cn.number}</strong> byl automaticky upraven z ${cn.before} Kč na <strong>${cn.after} Kč</strong> (skutečně vrácená část).`
      : st?.liveHaleru != null ? `Dobropis <strong>${cn.number}</strong> (${cn.before} Kč) odpovídá skutečně vrácené části — beze změny.`
      : `Dobropis <strong>${cn.number}</strong> (${cn.before} Kč) se nepodařilo automaticky dorovnat (platby ve Stripe nešly načíst) — zkontrolujte, že odpovídá skutečně vrácené částce.`
    const retry = st?.superseded
      ? 'Vratku mezitím nahradila novější vratka — zkontrolujte, že pokrývá i tuto částku.'
      : `Chybí vrátit <strong>${amt} Kč</strong>: ` + (md.mg_reason === 'cancellation'
        ? `vraťte je ve Velíně („Potvrdit vrácení“ u zrušené rezervace na ${amt} Kč — nový dobropis vznikne sám) nebo ve Stripe dashboardu.`
        : 'vratku zopakujte (Velín / stejná úprava) nebo ji vraťte ve Stripe dashboardu.')
    todo = `<p>Rezervace je teď ve stavu <strong>„${PAY_LABEL[String(payment)] || payment || '?'}“</strong>${reopened ? ' (znovu otevřena — dřív vypadala jako vrácená)' : ''}. `
      + `${cnText}</p><p>${retry}</p>`
  }
  await opsMail(`⚠️ Vratka ${amt} Kč${num ? ` k rezervaci #${num}` : ''} ve Stripe SELHALA (${status})`,
    `<p>${what}${bk ? ` k rezervaci <strong>#${num}</strong> (${bk.id})` : ' — rezervaci se nepodařilo dohledat'} skončila stavem <strong>${status}</strong> — peníze zákazníkovi neodešly.</p>${todo}`)
}

export async function onRefundUpdated(sb: Sb, stripe: OtherIntentsStripe & FailedRefundStripe, r: RefundObj): Promise<void> {
  const status = String(r.status || '')
  const bk = await bookingOfRefund(sb, r)
  if (status === 'failed' || status === 'canceled') return await onRefundFailed(sb, stripe, r, status, bk)
  if (!bk) { await log(sb, 'refund_updated_no_booking', 'info', { refund_id: r.id, status }); return }
  // i4: rezervace dohledaná jen přes metadata.booking_id (vratka MIMO cenu) stav platby rezervace nedorovnává
  if (bk.stripe_refund_id !== r.id && !(r.metadata || {}).mg_booking_id) {
    await log(sb, 'refund_updated_outside_price', 'info', { booking_id: bk.id, refund_id: r.id, status, mg_source: (r.metadata || {}).mg_source ?? null }); return
  }
  if (status !== 'succeeded') { await log(sb, 'refund_updated_ignored', 'info', { booking_id: bk.id, refund_id: r.id, status }); return }
  if (bk.payment_status !== 'refund_pending') {
    await log(sb, 'refund_updated_no_change', 'info', { booking_id: bk.id, refund_id: r.id, payment_status: bk.payment_status }); return
  }
  // Ruční část (převodem) teprve posílá obsluha → „Čeká na vrácení“ je správně.
  try {
    const { data: man } = await sb.from('invoices').select('id').eq('booking_id', bk.id).eq('type', 'credit_note')
      .neq('status', 'cancelled').is('stripe_refund_id', null).limit(1)
    if (man?.length) { await log(sb, 'refund_updated_manual_pending', 'info', { booking_id: bk.id, refund_id: r.id, manual_credit_note_id: man[0].id }); return }
  } catch { /* bez údaje → dorovnat */ }
  let left: number | null = null
  try {
    const storedPi = bk.stripe_payment_intent_id && stripe.paymentIntents.retrieve ? await stripe.paymentIntents.retrieve(bk.stripe_payment_intent_id) : null
    left = await staffFullBalanceHaleru(stripe, sb, { bookingId: bk.id, storedPi, storedRefunds: null })
  } catch (e) { console.warn('[webhook] refund.updated balance failed:', (e as Error).message) }
  const next = left === 0 ? 'refunded' : 'partial_refund'
  const { data: upd, error } = await sb.from('bookings').update({ payment_status: next }).eq('id', bk.id).eq('payment_status', 'refund_pending').select('id')
  const written = !error && Array.isArray(upd) && upd.length > 0
  await log(sb, 'refund_updated_status_synced', written ? 'ok' : 'info', { booking_id: bk.id, refund_id: r.id, left_haleru: left, payment_status: next, written })
}
