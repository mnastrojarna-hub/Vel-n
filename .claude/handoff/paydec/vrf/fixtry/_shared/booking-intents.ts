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
// (paid_change_failed — vrací se celá zvlášť, do ceny nepatří), doplatek úpravy, kterou
// webhook / fronta ještě nezapsala (oprava f1 2026-10-22: storno v tu chvíli vrátilo z doplatku
// část ceny, doplatek se pak kvůli „už vracené" platbě nezapsal ani nevrátil — zákazník přišel
// o doplatek), platba jiné rezervace. Viz `outsidePrice`.

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

async function logged(sb: Sb, action: string, payRef: string, errAs = true): Promise<boolean> {
  try {
    const { data, error } = await sb.from('debug_log').select('id').eq('action', action).eq('request_data->>payment_ref', payRef).limit(1)
    if (error) return errAs
    return Array.isArray(data) && data.length > 0
  } catch { return errAs } // nejistota → u ostatních plateb tuhle nepoužít (raději vyřídí obsluha)
}

/** Platby, na které odkazuje historie úprav rezervace (payment_ref `pi_…` / `cs_…`). */
async function historyRefs(sb: Sb, bookingId: string): Promise<string[]> {
  try {
    const { data } = await sb.from('bookings').select('modification_history').eq('id', bookingId).maybeSingle()
    const h = data?.modification_history
    if (!Array.isArray(h)) return []
    return [...new Set(h.map((e: Record<string, unknown> | null) => String((e && e.payment_ref) || '')).filter((r: string) => /^(pi|cs)_[A-Za-z0-9_]+$/.test(r)))] as string[]
  } catch { return [] }
}

export type Outside = 'failed' | 'duplicate' | 'pending' | 'returned'
/** Zdroje vratek, které vracejí peníze MIMO cenu rezervace (ne storno / vratku ceny). */
const OUTSIDE_REFUND_SOURCES = ['unapplied_change', 'duplicate_payment', 'late_payment']
/** Doplatek bez zápisu starší než fronta v appce (7 dní) už není „čekající" (zapsaný klientem bez značky). */
const PENDING_MAX_AGE_S = 7 * 24 * 3600

/** Platba NEpatří do ceny rezervace → storno ani vratka obsluhy z ní nevrací (null = patří):
 *  'failed'    — doplatek nezapsané změny (paid_change_failed; vrací se celý zvlášť),
 *  'duplicate' — druhá platba (duplicate_of / duplicate_payment; vrací se celá zvlášť),
 *  'pending'   — doplatek úpravy z nového process-payment (attempt_id / chg_hash), který ještě
 *                nikdo nezapsal (bez značky applied_at a bez payment_ref v historii, do 7 dní) —
 *                webhook / fronta ho teprve vyhodnotí; u zrušené rezervace ho vrátí celý,
 *  'returned'  — (jen s `refunds`) z platby se vracelo výhradně mimo cenu (doplatek nezapsané
 *                změny, duplicita, pozdní platba zrušené rezervace).
 *  `errAs` = výsledek při chybě čtení debug_log (ostatní platby: raději nepoužít). */
export async function outsidePrice(sb: Sb, bookingId: string, pi: IntentLike, o: {
  refunds?: RefundLike[] | null; history?: string[] | null; errAs?: boolean; nowMs?: number
} = {}): Promise<Outside | null> {
  const md = (pi.metadata || {}) as Record<string, string>
  const errAs = o.errAs !== false
  if (await logged(sb, 'paid_change_failed', pi.id, errAs)) return 'failed'
  if (md.duplicate_of || await logged(sb, 'duplicate_payment', pi.id, errAs)) return 'duplicate'
  if (md.type === 'extension' && !md.applied_at && (md.attempt_id || md.chg_hash)) {
    const h = o.history ?? await historyRefs(sb, bookingId)
    const ageS = (o.nowMs ?? Date.now()) / 1000 - Number(pi.created || 0)
    if (!h.includes(pi.id) && (!pi.created || ageS <= PENDING_MAX_AGE_S)) return 'pending'
  }
  const back = (o.refunds || []).filter((r) => r.status === 'succeeded' || r.status === 'pending')
  if (back.length && back.every((r) => OUTSIDE_REFUND_SOURCES.includes(String((r.metadata || {}).mg_source || '')))) return 'returned'
  return null
}

/** Platby z historie úprav rezervace (pi_ přímo, cs_ přes session) — jen ty, které search nenašel. */
async function historyIntents(stripe: BookingIntentsStripe, sb: Sb, bookingId: string, known: Set<string>, refs: string[]): Promise<IntentLike[]> {
  if (!stripe.paymentIntents.retrieve) return []
  const out: IntentLike[] = []
  for (const ref of refs) {
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
  const refs = await historyRefs(sb, bookingId)
  const fromHistory = await historyIntents(stripe, sb, bookingId, known, refs)
  all.push(...fromHistory)
  const history = [...refs, ...fromHistory.map((p) => p.id)] // i PI webové session (cs_) z historie = zapsaná platba
  const rows = all.filter((p) => p.id !== mainPi && p.status === 'succeeded'
    && (p.metadata || {}).booking_id === bookingId && ((p.metadata || {}).type || 'booking') !== 'shop'
    && !(p.metadata || {}).duplicate_of)
  rows.sort((a, b) => (Number(a.created || 0) - Number(b.created || 0)) || (a.id < b.id ? -1 : 1))
  const out: Candidate[] = []
  for (const p of rows) {
    if (await outsidePrice(sb, bookingId, p, { history })) continue
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

/** Poslední (nejnovější) úspěšná platba rezervace, ze které se ještě dá vracet — kromě `excludePi`.
 *  null = žádná taková není; chyba Stripe / DB se propaguje (volající rozliší „nevím" od „není"). */
export async function lastRefundableIntent(stripe: BookingIntentsStripe, sb: Sb, bookingId: string, excludePi: string): Promise<string | null> {
  const c = (await otherRefundableIntents(stripe, sb, bookingId, excludePi)).filter((x) => x.refundableHaleru > 0)
  return c.length ? c[c.length - 1].id : null
}
