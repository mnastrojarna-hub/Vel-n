// ===== _tests/storno-fake-stripe.ts =====
// Falešný Stripe pro flow testy storna (HOTFIX 2026-10-29): PaymentIntenty, charge, vratky
// (i „pending“), idempotency klíče (stejný klíč + jiné parametry = chyba jako Stripe), seznamy
// nejnovější první a fronta událostí charge.refunded, které test doručuje webhooku sám.
// deno-lint-ignore-file no-explicit-any
export type Md = Record<string, string>
export type Refund = { id: string; object: 'refund'; amount: number; status: string; metadata: Md; payment_intent: string
  charge: string; created: number; reason: string | null; currency: 'czk'; seq: number }
type Pi = { id: string; status: string; amount: number; amount_received: number; created: number; metadata: Md; latest_charge: string; customer: string }
type Charge = { id: string; object: 'charge'; payment_intent: string; amount: number; amount_captured: number; amount_refunded: number
  created: number; refunded: boolean; payment_method_details: { card: { brand: string; last4: string } } }

const clone = <T>(x: T): T => JSON.parse(JSON.stringify(x))

export class World {
  intents = new Map<string, Pi>()
  charges = new Map<string, Charge>()
  refunds: Refund[] = []
  byKey = new Map<string, { params: string; refund: Refund }>()
  events: any[] = []
  creates: Array<{ params: any; key: string | null; result: string }> = []
  seq = 0
  clock = Math.floor(Date.now() / 1000)
  /** stav nově vytvořené vratky ('succeeded' | 'pending') */
  refundStatus: () => string = () => 'succeeded'
  /** awaited uvnitř refunds.create po vzniku vratky (webhook doručený dřív, než process-refund doběhne) */
  onRefundCreated: ((r: Refund) => Promise<void>) | null = null

  addPi(id: string, czk: number, md: Md) {
    const h = Math.round(czk * 100)
    const created = this.clock - 86400 * 20
    const ch: Charge = { id: 'ch_' + id.slice(3), object: 'charge', payment_intent: id, amount: h, amount_captured: h, amount_refunded: 0,
      created, refunded: false, payment_method_details: { card: { brand: 'visa', last4: '4242' } } }
    this.charges.set(ch.id, ch)
    this.intents.set(id, { id, status: 'succeeded', amount: h, amount_received: h, created, metadata: { ...md }, latest_charge: ch.id, customer: 'cus_1' })
  }
  left(piId: string): number {
    const back = this.refunds.filter((r) => r.payment_intent === piId && (r.status === 'succeeded' || r.status === 'pending')).reduce((s, r) => s + r.amount, 0)
    return (this.intents.get(piId)?.amount_received || 0) - back
  }
  /** vráceno celkem (haléře) — succeeded + pending */
  refundedTotal(): number {
    return this.refunds.filter((r) => r.status === 'succeeded' || r.status === 'pending').reduce((s, r) => s + r.amount, 0)
  }
  /** hodiny Stripe = reálný čas (neklesající); advance() v harnessu posouvá starší vratky do minulosti */
  now(): number { return (this.clock = Math.max(this.clock, Math.floor(Date.now() / 1000))) }
  takeEvents(): any[] { const e = this.events; this.events = []; return e }
  /** ruční vratka v Stripe dashboardu (bez našich mg_* metadat) */
  dashboardRefund(piId: string, haleru?: number) { return this.api().refunds.create({ payment_intent: piId, amount: haleru, reason: 'requested_by_customer' }) }

  api() {
    const w = this
    return {
      paymentIntents: {
        retrieve: (id: string) => {
          const pi = w.intents.get(id)
          return pi ? Promise.resolve(clone(pi)) : Promise.reject(Object.assign(new Error(`No such payment_intent: '${id}'`), { code: 'resource_missing' }))
        },
        search: (_p: any) => Promise.resolve({ data: [...w.intents.values()].map(clone) }),
        list: (_p: any) => Promise.resolve({ data: [...w.intents.values()].map(clone) }),
        update: (id: string) => Promise.resolve(clone(w.intents.get(id))),
      },
      charges: { retrieve: (id: string) => Promise.resolve(clone(w.charges.get(id))) },
      checkout: { sessions: { retrieve: () => Promise.reject(new Error('No such checkout.session')) } },
      refunds: {
        list: (p: any) => Promise.resolve({ data: clone(w.refunds
          .filter((r) => (!p.payment_intent || r.payment_intent === p.payment_intent) && (!p.charge || r.charge === p.charge))
          .sort((a, b) => b.seq - a.seq)) }),
        retrieve: (id: string) => {
          const r = w.refunds.find((x) => x.id === id)
          return r ? Promise.resolve(clone(r)) : Promise.reject(new Error('No such refund'))
        },
        create: async (p: any, o: any = {}) => {
          const key: string | null = o?.idempotencyKey || null
          const sig = JSON.stringify({ pi: p.payment_intent, amount: p.amount ?? null })
          const prev = key ? w.byKey.get(key) : undefined
          if (prev) {
            if (prev.params !== sig) { w.creates.push({ params: p, key, result: 'idempotency_error' }); throw new Error('Keys for idempotent requests can only be used with the same parameters they were first used with.') }
            w.creates.push({ params: p, key, result: 'replayed:' + prev.refund.id })
            return clone(prev.refund)
          }
          const pi = w.intents.get(p.payment_intent)
          if (!pi || !(pi.amount_received > 0)) throw new Error(`This PaymentIntent (${p.payment_intent}) does not have a successful charge to refund.`)
          const amt = p.amount != null ? Number(p.amount) : w.left(pi.id)
          if (!(amt > 0) || amt > w.left(pi.id)) { w.creates.push({ params: p, key, result: 'too_much' }); throw new Error('Refund amount is greater than unrefunded amount on charge') }
          const r: Refund = { id: `re_${++w.seq}`, object: 'refund', amount: amt, status: w.refundStatus(), metadata: { ...(p.metadata || {}) },
            payment_intent: pi.id, charge: pi.latest_charge, created: w.now(), reason: p.reason || null, currency: 'czk', seq: w.seq }
          w.refunds.push(r)
          const ch = w.charges.get(pi.latest_charge)!
          ch.amount_refunded += amt
          ch.refunded = ch.amount_refunded >= ch.amount_captured
          if (key) w.byKey.set(key, { params: sig, refund: clone(r) })
          w.creates.push({ params: p, key, result: 'created:' + r.id })
          w.events.push({ id: `evt_${w.seq}`, type: 'charge.refunded', created: r.created, data: { object: clone(ch) } })
          if (w.onRefundCreated) await w.onRefundCreated(r)
          return clone(r)
        },
      },
      webhooks: { constructEventAsync: (body: string) => Promise.resolve(JSON.parse(body)) },
      customers: { list: () => Promise.resolve({ data: [] }), create: () => Promise.resolve({ id: 'cus_new' }) },
    }
  }
}

export function world(): World { return (globalThis as any).__STORNO_WORLD as World }
export function setWorld(w: World) { (globalThis as any).__STORNO_WORLD = w }
