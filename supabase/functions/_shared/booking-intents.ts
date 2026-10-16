// ===== _shared/booking-intents.ts =====
// Úspěšné platby (PaymentIntenty) jedné rezervace kromě „hlavní" — sdílí process-refund
// (storno / vratka obsluhy větší, než zbývá na uložené platbě → zbytek z ostatních plateb;
// odpověď majitele 2026-10-16: dorovnání na 15 Kč se při stornu vrací poměrně jako zbytek
// ceny) a _shared/paid-change-failure.ts (po vrácení doplatku nezapsané změny vrátí do
// bookings.stripe_payment_intent_id poslední platbu, ze které se ještě dá vracet).
// Zdroje: Stripe search podle metadata.booking_id (appka, web rezervace) + platby, na které
// odkazuje historie úprav rezervace (modification_history[].payment_ref: `pi_…` přímo,
// `cs_…` přes Checkout Session) — webové doplatky úprav / výměn / výbavy (process-payment
// mode 'checkout') metadata na PaymentIntentu nemají a search je nenajde.
// Nikdy: e-shop (type shop) a přibalená e-shop část platby, duplicitní platba
// (duplicate_of / záznam duplicate_payment — vrací se celá zvlášť), platba nezapsané změny
// (paid_change_failed — vrací se celá zvlášť, do ceny nepatří), platba jiné rezervace.

// deno-lint-ignore no-explicit-any
type Sb = any
export type IntentLike = {
  id: string; status?: string; amount_received?: number | null; created?: number | null; metadata?: Record<string, string> | null
}
export type RefundLike = { id?: string; amount: number; status?: string | null; metadata?: Record<string, string> | null }
export type BookingIntentsStripe = {
  paymentIntents: {
    search: (p: Record<string, unknown>) => Promise<{ data: IntentLike[] }>
    retrieve?: (id: string) => Promise<IntentLike>
  }
  refunds: {
    list: (p: Record<string, unknown>) => Promise<{ data: RefundLike[] }>
    create: (p: Record<string, unknown>, o?: Record<string, unknown>) => Promise<{ id: string; amount: number; status?: string | null }>
  }
  checkout?: { sessions: { retrieve: (id: string) => Promise<{ payment_intent?: string | { id?: string } | null; metadata?: Record<string, string> | null }> } }
}
export type Candidate = { id: string; refundableHaleru: number; created: number; refundsForMain: number }

const UUID_RX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

async function logged(sb: Sb, action: string, payRef: string): Promise<boolean> {
  try {
    const { data } = await sb.from('debug_log').select('id').eq('action', action).eq('request_data->>payment_ref', payRef).limit(1)
    return Array.isArray(data) && data.length > 0
  } catch { return true } // nejistota → tuhle platbu nepoužít (raději vyřídí obsluha)
}

/** Platby z historie úprav rezervace (pi_ přímo, cs_ přes session) — jen ty, které search nenašel. */
async function historyIntents(stripe: BookingIntentsStripe, sb: Sb, bookingId: string, known: Set<string>): Promise<IntentLike[]> {
  if (!stripe.paymentIntents.retrieve) return []
  let refs: string[] = []
  try {
    const { data } = await sb.from('bookings').select('modification_history').eq('id', bookingId).maybeSingle()
    const h = data?.modification_history
    if (Array.isArray(h)) refs = h.map((e: Record<string, unknown> | null) => String((e && e.payment_ref) || '')).filter((r: string) => /^(pi|cs)_[A-Za-z0-9_]+$/.test(r))
  } catch { return [] }
  const out: IntentLike[] = []
  for (const ref of [...new Set(refs)]) {
    let piId: string | null = ref.startsWith('pi_') ? ref : null
    if (!piId && stripe.checkout) {
      try {
        const s = await stripe.checkout.sessions.retrieve(ref)
        const smd = (s?.metadata || {}) as Record<string, string>
        if (smd.booking_id && smd.booking_id !== bookingId) continue
        const p = typeof s?.payment_intent === 'string' ? s.payment_intent : s?.payment_intent?.id
        piId = p && p.startsWith('pi_') ? p : null
      } catch { continue }
    }
    if (!piId || known.has(piId)) continue
    known.add(piId)
    try {
      const pi = await stripe.paymentIntents.retrieve(piId)
      const md = (pi?.metadata || {}) as Record<string, string>
      if (md.booking_id && md.booking_id !== bookingId) continue // platba jiné rezervace
      // webový doplatek metadata nemá — patří rezervaci, protože na něj odkazuje její historie
      out.push({ ...pi, metadata: { ...md, booking_id: bookingId } })
    } catch { /* nedohledaná platba → nepoužít */ }
  }
  return out
}

/** Ostatní úspěšné platby rezervace s tím, co z nich ještě jde vrátit (haléře), nejstarší první.
 *  `mainRefundId` → `refundsForMain` = kolik se z platby už vrátilo jako zbytek TÉTO hlavní vratky
 *  (metadata mg_main_refund) — opakovaný dispatch téhož storna ho od požadavku odečte. */
export async function otherRefundableIntents(stripe: BookingIntentsStripe, sb: Sb, bookingId: string, mainPi: string | null,
  mainRefundId: string | null = null): Promise<Candidate[]> {
  if (!UUID_RX.test(bookingId)) return []
  const found = await stripe.paymentIntents.search({ query: `metadata['booking_id']:'${bookingId}' AND status:'succeeded'`, limit: 100 })
  const all: IntentLike[] = [...(found?.data || [])]
  const known = new Set(all.map((p) => p.id))
  if (mainPi) known.add(mainPi)
  all.push(...await historyIntents(stripe, sb, bookingId, known))
  const rows = all.filter((p) => p.id !== mainPi && p.status === 'succeeded'
    && (p.metadata || {}).booking_id === bookingId && ((p.metadata || {}).type || 'booking') !== 'shop'
    && !(p.metadata || {}).duplicate_of)
  rows.sort((a, b) => (Number(a.created || 0) - Number(b.created || 0)) || (a.id < b.id ? -1 : 1))
  const out: Candidate[] = []
  for (const p of rows) {
    if (await logged(sb, 'paid_change_failed', p.id) || await logged(sb, 'duplicate_payment', p.id)) continue
    const received = Number(p.amount_received || 0)
    if (!(received > 0)) continue
    let refunded = 0
    let forMain = 0
    const rl = await stripe.refunds.list({ payment_intent: p.id, limit: 100 })
    for (const r of rl?.data || []) {
      if (r.status !== 'succeeded' && r.status !== 'pending') continue
      refunded += Number(r.amount || 0)
      if (mainRefundId && (r.metadata || {}).mg_main_refund === mainRefundId) forMain += Number(r.amount || 0)
    }
    let shopPart = 0
    const shopId = (p.metadata || {}).shop_order_id
    if (shopId) {
      const { data: so } = await sb.from('shop_orders').select('total').eq('id', shopId).maybeSingle()
      shopPart = Math.round((Number(so?.total) || 0) * 100)
    }
    const left = received - refunded - shopPart
    if (left > 0 || forMain > 0) out.push({ id: p.id, refundableHaleru: Math.max(0, left), created: Number(p.created || 0), refundsForMain: forMain })
  }
  return out
}

/** Poslední (nejnovější) úspěšná platba rezervace, ze které se ještě dá vracet — kromě `excludePi`. */
export async function lastRefundableIntent(stripe: BookingIntentsStripe, sb: Sb, bookingId: string, excludePi: string): Promise<string | null> {
  try {
    const c = (await otherRefundableIntents(stripe, sb, bookingId, excludePi)).filter((x) => x.refundableHaleru > 0)
    return c.length ? c[c.length - 1].id : null
  } catch { return null }
}
