// ===== fio-sync/dispatch.ts =====
// JEDEN rozcestník: co příchozí platba platí a která potvrzovací rutina ji vyřídí.
//   cíl = ručně zadaný obsluhou ve Velínu (manual_target_*), jinak podle variabilního symbolu v pořadí:
//     1. bank_payment_requests.vs  (poukaz / objednávka e-shopu, doplatek úpravy rezervace z webu)
//     2. bookings.payment_vs       (celá platba rezervace — motorka i výpůjčka jen výbavy)
//     3. bookings.mod_surcharge_vs (doplatek úpravy zadaný ve Velínu)
//     4. invoices.variable_symbol  (VS zálohové faktury → její rezervace, nově i objednávka e-shopu)
// Bez cíle = no_match: platba bez VS / s neznámým VS se NIKDY nepotvrdí sama — obsluze ji Velín
// navrhne ke spárování (suggest.ts) a potvrzuje se jedním kliknutím.
// Kroky 1 a „objednávka“ ve 4 fungují jen s nasazeným SQL (20261130a1 / b); bez něj = původní chování.
import { type Ctx, isMissing, type Outcome, type Row, type Tx, vsDigits } from './util.ts'
import { notifyUnmatched } from './ops-mail.ts'
import { BOOKING_SELECT, handleBooking, handleSurcharge, type PairOpts } from './confirm-booking.ts'
import { handleOrder, ORDER_SELECT } from './confirm-order.ts'
import { handleChange } from './confirm-change.ts'

const SUR_SELECT = 'id, status, mod_surcharge_due, mod_surcharge_vs'

async function one(q: PromiseLike<{ data: unknown; error: { code?: string; message?: string } | null }>): Promise<Row | null> {
  const { data, error } = await q
  if (error) throw new Error(error.message || 'db_error')
  return (data as Row | null) || null
}

/** Požadavek na platbu podle VS / id / objednávky. Chybí tabulka (SQL 20261130b nenasazené) → null. */
async function findRequest(ctx: Ctx, by: { vs?: string; id?: string; orderId?: string }): Promise<Row | null> {
  if (!ctx.caps.requests) return null
  let q = ctx.sb.from('bank_payment_requests').select('*')
  if (by.vs) q = q.eq('vs', by.vs)
  else if (by.id) q = q.eq('id', by.id)
  else q = q.eq('order_id', by.orderId).order('created_at', { ascending: false })
  const { data, error } = await q.limit(1)
  if (error) {
    if (isMissing(error)) { ctx.caps.requests = false; return null }
    throw new Error(error.message || 'db_error')
  }
  return ((data as Row[] | null) || [])[0] || null
}

const loadBooking = (ctx: Ctx, col: string, v: string) => one(ctx.sb.from('bookings').select(BOOKING_SELECT).eq(col, v).maybeSingle())
const loadOrder = (ctx: Ctx, id: string) => one(ctx.sb.from('shop_orders').select(ORDER_SELECT).eq('id', id).maybeSingle())

async function routeRequest(ctx: Ctx, p: Tx, r: Row, o: PairOpts): Promise<Outcome | null> {
  if (r.kind === 'booking_change') return await handleChange(ctx, p, r, o)
  const order = r.order_id ? await loadOrder(ctx, String(r.order_id)) : null
  return order ? await handleOrder(ctx, p, order, r, o) : null
}

export async function dispatch(ctx: Ctx, p: Tx): Promise<Outcome> {
  const { sb, caps, env } = ctx
  // úvodní nuly VS (doplňují je některé banky) se odřezávají až s novým SQL — bez něj přesně jako dřív
  const vs = caps.state ? vsDigits(p.vs) : String(p.vs || '').replace(/\D/g, '')

  if ((p.currency || 'CZK') !== 'CZK') {
    await notifyUnmatched(env, p, 'Platba v cizí měně (' + p.currency + ') — spárujte a potvrďte ručně ve Velíně.')
    return { status: 'no_match', reason: 'foreign_currency', note: 'cizí měna ' + p.currency }
  }

  // ── Ruční spárování z Velína (admin_fio_pair_transaction) — stejné rutiny jako automatika ──
  if (caps.state && p.manual_target_type && p.manual_target_id) {
    const o: PairOpts = { manual: true, accept: p.manual_accept_amount === true, vs }
    const id = String(p.manual_target_id)
    let out: Outcome | null = null
    if (p.manual_target_type === 'booking') {
      const b = await loadBooking(ctx, 'id', id)
      if (b) out = await handleBooking(ctx, p, b, o)
    } else if (p.manual_target_type === 'surcharge') {
      const s = await one(sb.from('bookings').select(SUR_SELECT).eq('id', id).maybeSingle())
      if (s) out = await handleSurcharge(ctx, p, s, o)
    } else if (p.manual_target_type === 'order') {
      const ord = await loadOrder(ctx, id)
      if (ord) out = await handleOrder(ctx, p, ord, await findRequest(ctx, { orderId: id }), o)
    } else if (p.manual_target_type === 'request') {
      const r = await findRequest(ctx, { id })
      if (r) out = await routeRequest(ctx, p, r, o)
    }
    return out ?? { status: 'no_match', reason: 'vs_not_found', note: 'ručně zvolený cíl nenalezen' }
  }

  const auto: PairOpts = { manual: false, accept: false, vs }
  if (vs) {
    // ── 1: požadavek na platbu (poukaz / objednávka, doplatek úpravy z webu) ──
    const req = await findRequest(ctx, { vs })
    if (req) {
      const out = await routeRequest(ctx, p, req, auto)
      if (out) return out
    }

    // ── 2: celá platba rezervace (bookings.payment_vs) ──
    let booking = await loadBooking(ctx, 'payment_vs', vs)

    // ── 3: doplatek za úpravu z Velína (bookings.mod_surcharge_vs) ──
    if (!booking) {
      const sur = await one(sb.from('bookings').select(SUR_SELECT).eq('mod_surcharge_vs', vs).maybeSingle())
      if (sur) return await handleSurcharge(ctx, p, sur, auto)
    }

    // ── 4 (fallback): VS zálohové faktury → rezervace; nově i objednávka e-shopu ──
    if (!booking) {
      const types = caps.state ? ['advance', 'proforma', 'shop_proforma'] : ['advance', 'proforma']
      let q = sb.from('invoices').select('booking_id, order_id').eq('variable_symbol', vs).in('type', types).neq('status', 'cancelled')
      if (!caps.state) q = q.not('booking_id', 'is', null)
      const { data: inv } = await q.order('created_at', { ascending: false }).limit(1)
      const hit = (inv as Array<{ booking_id?: string | null; order_id?: string | null }> | null)?.[0]
      if (hit?.booking_id) booking = await loadBooking(ctx, 'id', String(hit.booking_id))
      else if (caps.state && hit?.order_id) {
        const ord = await loadOrder(ctx, String(hit.order_id))
        if (ord) return await handleOrder(ctx, p, ord, await findRequest(ctx, { orderId: String(hit.order_id) }), auto)
      }
    }
    if (booking) return await handleBooking(ctx, p, booking, auto)
  }

  // Drobné příchozí položky bez VS (úroky apod.) nespamují — mail jen
  // když platba nese VS nebo je na „zákaznickou" částku. S novým SQL navíc ne u pohybů starších
  // 3 dnů (první stažení s novým tokenem / dohledání období nesmí zaplavit schránku; ve Velínu jsou vidět).
  const stale = caps.state && Date.parse(String(p.tx_date)) < (env.now ? env.now() : Date.now()) - 3 * 86400_000
  if ((vs || p.amount >= 50) && !stale) {
    await notifyUnmatched(env, p, caps.state
      ? 'Platbu se nepodařilo spárovat (chybí nebo nesedí variabilní symbol) — sama se NEpotvrdí. Ve Velíně (Finance → Banka) uvidíte návrh nejpravděpodobnější rezervace / objednávky a potvrdíte ji jedním kliknutím, nebo platbu vraťte.'
      : 'Platba se nepodařilo spárovat s žádnou rezervací — zkontrolujte a případně potvrďte/vraťte ručně.')
  }
  return { status: 'no_match', reason: vs ? 'vs_not_found' : 'no_vs', note: vs ? 'VS bez shody' : 'platba bez VS' }
}
