// Fake Stripe "world" for end-to-end refund tests (verify:refunds). Models PaymentIntents, charges,
// refunds (incl. pending), idempotency keys (same key + different params = error, like Stripe),
// newest-first refund lists and a queue of charge.refunded events delivered by the test.
// deno-lint-ignore-file no-explicit-any
export type Md = Record<string, string>
export type Pi = { id: string; object: 'payment_intent'; status: string; amount: number; amount_received: number; created: number
  metadata: Md; latest_charge: string; customer: string | null; currency: 'czk' }
export type Charge = { id: string; object: 'charge'; payment_intent: string; amount: number; amount_captured: number; amount_refunded: number
  created: number; refunded: boolean; payment_method_details: { card: { brand: string; last4: string } } }
export type Refund = { id: string; object: 'refund'; amount: number; status: string; metadata: Md; payment_intent: string; charge: string
  created: number; reason: string | null; currency: 'czk'; seq: number }

export class World {
  intents = new Map<string, Pi>()
  charges = new Map<string, Charge>()
  refunds: Refund[] = []
  sessions = new Map<string, any>()
  byKey = new Map<string, { params: string; refund: Refund }>()
  events: any[] = []
  creates: Array<{ params: any; key: string | null; result: string }> = []
  seq = 0
  clock = Math.floor(Date.now() / 1000) - 86400 * 30
  /** status of the next created refund ('succeeded' | 'pending') */
  refundStatus: (p: any) => string = () => 'succeeded'
  /** inject an error into refunds.create */
  failCreate: ((p: any, key: string | null) => Error | null) | null = null
  /** awaited inside refunds.create after the refund exists (webhook delivered before the response) */
  onRefundCreated: ((r: Refund) => Promise<void>) | null = null

  addPi(id: string, czk: number, md: Md, opts: { createdAgoS?: number; customer?: string } = {}): Pi {
    const h = Math.round(czk * 100)
    const created = Math.floor(Date.now() / 1000) - (opts.createdAgoS ?? 86400 * (20 - this.intents.size))
    const ch: Charge = { id: 'ch_' + id.slice(3), object: 'charge', payment_intent: id, amount: h, amount_captured: h, amount_refunded: 0,
      created, refunded: false, payment_method_details: { card: { brand: 'visa', last4: '4242' } } }
    this.charges.set(ch.id, ch)
    const pi: Pi = { id, object: 'payment_intent', status: 'succeeded', amount: h, amount_received: h, created, metadata: { ...md },
      latest_charge: ch.id, customer: opts.customer ?? 'cus_1', currency: 'czk' }
    this.intents.set(id, pi)
    return pi
  }
  left(piId: string): number {
    const pi = this.intents.get(piId)
    const back = this.refunds.filter((r) => r.payment_intent === piId && (r.status === 'succeeded' || r.status === 'pending'))
      .reduce((s, r) => s + r.amount, 0)
    return (pi?.amount_received || 0) - back
  }
  refundedTotal(filter: (r: Refund) => boolean = () => true): number {
    return this.refunds.filter((r) => (r.status === 'succeeded' || r.status === 'pending') && filter(r)).reduce((s, r) => s + r.amount, 0)
  }
  chargeSnapshot(chId: string): Charge { return JSON.parse(JSON.stringify(this.charges.get(chId)!)) }
  /** queue of undelivered charge.refunded events (oldest first) */
  takeEvents(): any[] { const e = this.events; this.events = []; return e }

  // ---- Stripe API surface ----
  api() {
    const w = this
    return {
      paymentIntents: {
        retrieve: (id: string, p?: any) => {
          const pi = w.intents.get(id)
          if (!pi) return Promise.reject(Object.assign(new Error(`No such payment_intent: '${id}'`), { code: 'resource_missing' }))
          const out: any = JSON.parse(JSON.stringify(pi))
          if (p?.expand?.includes('latest_charge')) out.latest_charge = w.chargeSnapshot(pi.latest_charge)
          return Promise.resolve(out)
        },
        search: (p: any) => {
          const m = String(p.query || '').match(/metadata\['(\w+)'\]:'([^']+)'/)
          const rows = [...w.intents.values()].filter((x) => x.status === 'succeeded' && m && x.metadata[m[1]] === m[2])
          const exp = (p.expand || []).includes('data.latest_charge')
          return Promise.resolve({ data: rows.map((x) => { const o: any = JSON.parse(JSON.stringify(x)); if (exp) o.latest_charge = w.chargeSnapshot(x.latest_charge); return o }) })
        },
        list: (p: any) => {
          const rows = [...w.intents.values()].filter((x) => !p.customer || x.customer === p.customer)
          const exp = (p.expand || []).includes('data.latest_charge')
          return Promise.resolve({ data: rows.map((x) => { const o: any = JSON.parse(JSON.stringify(x)); if (exp) o.latest_charge = w.chargeSnapshot(x.latest_charge); return o }) })
        },
        update: (id: string, p: any) => {
          const pi = w.intents.get(id); if (pi && p?.metadata) Object.assign(pi.metadata, p.metadata)
          return Promise.resolve(pi)
        },
      },
      charges: { retrieve: (id: string) => Promise.resolve(w.chargeSnapshot(id)) },
      checkout: { sessions: { retrieve: (id: string) => {
        const s = w.sessions.get(id); return s ? Promise.resolve(s) : Promise.reject(new Error('No such checkout.session'))
      } } },
      refunds: {
        list: (p: any) => {
          const rows = w.refunds.filter((r) => (p.payment_intent ? r.payment_intent === p.payment_intent : true) && (p.charge ? r.charge === p.charge : true))
            .sort((a, b) => b.seq - a.seq)
          return Promise.resolve({ data: JSON.parse(JSON.stringify(rows)) })
        },
        retrieve: (id: string) => {
          const r = w.refunds.find((x) => x.id === id)
          return r ? Promise.resolve(JSON.parse(JSON.stringify(r))) : Promise.reject(new Error('No such refund'))
        },
        create: async (p: any, o: any = {}) => {
          const key: string | null = o?.idempotencyKey || null
          const sig = JSON.stringify({ pi: p.payment_intent, amount: p.amount ?? null })
          if (key && w.byKey.has(key)) {
            const prev = w.byKey.get(key)!
            if (prev.params !== sig) { w.creates.push({ params: p, key, result: 'idempotency_error' }); throw Object.assign(new Error('Keys for idempotent requests can only be used with the same parameters they were first used with.'), { type: 'StripeIdempotencyError' }) }
            w.creates.push({ params: p, key, result: 'replayed:' + prev.refund.id })
            return JSON.parse(JSON.stringify(prev.refund))
          }
          const err = w.failCreate?.(p, key)
          if (err) { w.creates.push({ params: p, key, result: 'error:' + err.message }); throw err }
          const pi = w.intents.get(p.payment_intent)
          if (!pi || !(pi.amount_received > 0)) { w.creates.push({ params: p, key, result: 'no_charge' }); throw new Error(`This PaymentIntent (${p.payment_intent}) does not have a successful charge to refund.`) }
          const amt = p.amount != null ? Number(p.amount) : w.left(pi.id)
          if (!(amt > 0) || amt > w.left(pi.id)) {
            w.creates.push({ params: p, key, result: 'too_much' })
            throw new Error(amt > 0 ? `Refund amount (${amt}) is greater than unrefunded amount on charge (${w.left(pi.id)})` : 'Charge has already been refunded.')
          }
          const r: Refund = { id: `re_${++w.seq}`, object: 'refund', amount: amt, status: w.refundStatus(p), metadata: { ...(p.metadata || {}) },
            payment_intent: pi.id, charge: pi.latest_charge, created: ++w.clock + 86400 * 30, reason: p.reason || null, currency: 'czk', seq: w.seq }
          w.refunds.push(r)
          const ch = w.charges.get(pi.latest_charge)!
          ch.amount_refunded += amt
          ch.refunded = ch.amount_refunded >= ch.amount_captured
          if (key) w.byKey.set(key, { params: sig, refund: JSON.parse(JSON.stringify(r)) })
          w.creates.push({ params: p, key, result: 'created:' + r.id })
          w.events.push({ id: `evt_${w.seq}`, type: 'charge.refunded', created: r.created, data: { object: w.chargeSnapshot(ch.id) } })
          if (w.onRefundCreated) await w.onRefundCreated(r)
          return JSON.parse(JSON.stringify(r))
        },
      },
      webhooks: { constructEventAsync: (body: string) => Promise.resolve(JSON.parse(body)) },
      customers: { list: () => Promise.resolve({ data: [] }), create: () => Promise.resolve({ id: 'cus_new' }) },
    }
  }
}

export function world(): World { return (globalThis as any).__WORLD as World }
export function setWorld(w: World) { (globalThis as any).__WORLD = w }
