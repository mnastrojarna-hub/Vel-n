// ===== _shared/duplicate-payment.ts =====
// D4 (oprava 2026-10-16): DRUHÁ platba za totéž (dvě záložky webu, starší otevřená
// Checkout Session, opakované zaplacení téže úpravy) se už tiše nenechává:
// webhook-receiver ji pozná a celou ji AUTOMATICKY vrátí (Stripe refund s klíčem
// mg-dup-<pi>, metadata mg_source=duplicate_payment) + upozorní obsluhu.
//  • rezervace / SOS / e-shop: platba přišla k řádku, který už je zaplacený, a ve Stripe
//    existuje JINÁ úspěšná, nevrácená platba téhož typu a téže rezervace/objednávky
//    (do 24 h od sebe) → ponechá se ta s nejdřívějším stržením, ostatní se vrátí;
//  • doplatek úpravy: změnu už zapsala jiná platba (extension-apply → state 'duplicate').
// Jen JEDNOU na platbu: první zapsaný řádek debug_log `duplicate_payment` vyhrává.
// Vratka nejde přes process-refund (žádný dobropis — k duplicitní platbě nevznikl
// doklad) a charge.refunded ji podle mg_source nepromítne do stavu rezervace.
import type { Sb } from './extension-apply-types.ts'

export type DupMode = 'refunded' | 'staff' | 'duplicate'
type Charge = { id?: string; amount?: number; amount_refunded?: number; created?: number }
type PiRow = { id: string; status?: string; amount?: number; created?: number; customer?: unknown
  metadata?: Record<string, string> | null; latest_charge?: string | Charge | null }
export type StripeDupLike = {
  refunds: { create: (p: Record<string, unknown>, o?: Record<string, unknown>) => Promise<{ id: string }> }
  paymentIntents: {
    retrieve: (id: string, p?: Record<string, unknown>) => Promise<PiRow>
    update?: (id: string, p: Record<string, unknown>) => Promise<unknown>
    list?: (p: Record<string, unknown>) => Promise<{ data: PiRow[] }>
    search?: (p: Record<string, unknown>) => Promise<{ data: PiRow[] }>
  }
}

const OPS_EMAIL = 'info@motogo24.cz'
const DAY_S = 24 * 3600
const chargeOf = (p: PiRow): Charge | null => (p.latest_charge && typeof p.latest_charge === 'object' ? p.latest_charge : null)

/** Úspěšné, nevrácené platby téhož typu k téže rezervaci/objednávce → {keep, refund[]}; null = žádná duplicita. */
export async function findDuplicateCharges(stripe: StripeDupLike, a: {
  piId: string; customer: string | null; refKey: 'booking_id' | 'order_id'; refId: string; type: string; nowMs?: number
}): Promise<{ keep: string; refund: Array<{ id: string; amountCzk: number }> } | null> {
  if (!/^[0-9a-f-]{36}$/i.test(a.refId)) return null
  const nowS = Math.floor((a.nowMs ?? Date.now()) / 1000)
  let rows: PiRow[] = []
  try {
    if (a.customer && stripe.paymentIntents.list) {
      rows = (await stripe.paymentIntents.list({ customer: a.customer, created: { gte: nowS - 7 * DAY_S }, limit: 100,
        expand: ['data.latest_charge'] })).data || []
    } else if (stripe.paymentIntents.search) {
      rows = (await stripe.paymentIntents.search({ query: `metadata['${a.refKey}']:'${a.refId}' AND status:'succeeded'`,
        limit: 20, expand: ['data.latest_charge'] })).data || []
    }
  } catch { return null }
  const live = rows.filter((p) => p.status === 'succeeded' && (p.metadata || {})[a.refKey] === a.refId
    && ((p.metadata || {}).type || 'booking') === a.type && !!chargeOf(p) && Number(chargeOf(p)!.amount_refunded || 0) === 0)
  if (live.length < 2 || !live.some((p) => p.id === a.piId)) return null
  live.sort((x, y) => (Number(chargeOf(x)!.created || 0) - Number(chargeOf(y)!.created || 0)) || (x.id < y.id ? -1 : 1))
  const keep = live[0]
  const kAt = Number(chargeOf(keep)!.created || 0)
  const refund = live.slice(1).filter((p) => Math.abs(Number(chargeOf(p)!.created || 0) - kAt) <= DAY_S)
    .map((p) => ({ id: p.id, amountCzk: Number(p.amount || 0) / 100 }))
  return refund.length ? { keep: keep.id, refund } : null
}

/** Vrátí celou duplicitní platbu `piId` (jednou) a upozorní obsluhu. */
export async function refundDuplicatePayment(sb: Sb, stripe: StripeDupLike, a: {
  piId: string; table: 'bookings' | 'shop_orders'; refId: string; keepRef: string | null; amountCzk: number
  via: string; autoRefund?: boolean
}): Promise<DupMode> {
  const reqData = { payment_ref: a.piId, table: a.table, ref_id: a.refId, kept: a.keepRef, amount: a.amountCzk, via: a.via }
  let myId: string | null = null
  try {
    const { data } = await sb.from('debug_log').insert({ source: 'duplicate-payment', action: 'duplicate_payment', component: 'stripe',
      status: 'warning', error_message: 'Druhá platba za totéž — vrací se celá.', request_data: reqData }).select('id').single()
    myId = data?.id ?? null
    const { data: first } = await sb.from('debug_log').select('id, response_data').eq('action', 'duplicate_payment')
      .eq('request_data->>payment_ref', a.piId).order('created_at', { ascending: true }).order('id', { ascending: true }).limit(1)
    if (first?.length && myId && first[0].id !== myId) {
      try { await sb.from('debug_log').delete().eq('id', myId) } catch { /* ignore */ }
      return ((first[0].response_data || {}) as { refund?: DupMode }).refund || 'duplicate'
    }
  } catch { /* bez zámku — Stripe idempotency klíč vratku nezdvojí */ }

  let mode: DupMode = 'staff'
  if (a.autoRefund !== false && a.piId.startsWith('pi_')) {
    // Uložený PaymentIntent řádku (process-refund / charge.refunded z něj vycházejí) = ta PONECHANÁ platba.
    if (a.keepRef && a.keepRef.startsWith('pi_')) {
      try { await sb.from(a.table).update({ stripe_payment_intent_id: a.keepRef }).eq('id', a.refId).eq('stripe_payment_intent_id', a.piId) } catch { /* ignore */ }
    }
    try {
      await stripe.refunds.create({ payment_intent: a.piId, reason: 'duplicate',
        metadata: { mg_source: 'duplicate_payment', [a.table === 'bookings' ? 'booking_id' : 'order_id']: a.refId, kept: a.keepRef || '' } },
        { idempotencyKey: `mg-dup-${a.piId}` })
      mode = 'refunded'
    } catch {
      try {
        const p = await stripe.paymentIntents.retrieve(a.piId, { expand: ['latest_charge'] })
        const ch = chargeOf(p)
        if (ch && Number(ch.amount_refunded || 0) >= Number(ch.amount || p.amount || 0)) mode = 'refunded'
      } catch { /* zůstává staff */ }
    }
    try { await stripe.paymentIntents.update?.(a.piId, { metadata: { duplicate_of: a.keepRef || 'yes' } }) } catch { /* ignore */ }
  }
  if (myId) { try { await sb.from('debug_log').update({ response_data: { refund: mode } }).eq('id', myId) } catch { /* ignore */ } }

  try {
    const url = Deno.env.get('SUPABASE_URL') ?? ''
    const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const what = a.table === 'bookings' ? `rezervace #${a.refId.slice(-8).toUpperCase()}` : `objednávky #${a.refId.slice(-8).toUpperCase()}`
    await fetch(`${url}/functions/v1/send-email`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}`, apikey: key },
      body: JSON.stringify({ to: OPS_EMAIL, subject: `⚠️ Dvojí platba ${what}`,
        raw_html: `<h2 style="margin:0 0 8px;font-size:18px">Dvojí platba ${what}</h2>`
          + `<p style="margin:0 0 8px">Platba ${a.piId} (${a.amountCzk} Kč) je druhá platba za totéž (ponechaná platba: ${a.keepRef || '—'}; ${a.via}).</p>`
          + `<p style="margin:0">${mode === 'refunded' ? 'Duplicitní platba byla zákazníkovi automaticky vrácena celá.'
            : 'Duplicitní platbu se NEPODAŘILO vrátit automaticky — vraťte ji prosím ručně ve Stripe (celou částku).'}</p>` }),
    })
  } catch { /* ignore */ }
  return mode
}

/** Byla platba vyhodnocená jako duplicitní (vrácená / k ruční vratce)? */
export async function duplicateRow(sb: Sb, payRef: string): Promise<boolean> {
  try {
    const { data } = await sb.from('debug_log').select('id').eq('action', 'duplicate_payment').eq('request_data->>payment_ref', payRef).limit(1)
    return Array.isArray(data) && data.length > 0
  } catch { return false }
}
