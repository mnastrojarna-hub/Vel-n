// ===== _tests/i4_units_test.ts =====
// Oprava i4 (2026-11-07): jednotkové testy čistých pomocníků + chování webových skriptů /potvrzeni a půjčení výbavy
// (falešné DOM / RPC / časovače). Flow testy celých handlerů → storno_i4_flow_test.ts.
// deno-lint-ignore-file no-explicit-any
import { failedRefundIds, isReplayOfFailed, retrySuffix } from '../process-refund/retry-key.ts'
import { refundedStatus } from '../process-refund/other-intents.ts'
import { remainderPending, statusLags, type StripeRefundLike } from '../process-refund/cancel-once.ts'
import { coversModification, newestModificationMs } from '../send-booking-email/modified-refund.ts'
import { checkoutCzk } from '../_shared/currency.ts'
import { manualRefundOpen, manualRefundSentStatus } from '../../../velin/src/pages/booking/manualRefundState.js'

function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
const WEB = new URL('../../../motogo-web-php/', import.meta.url)

Deno.test('i4 retry-key: klíč beze změny bez selhaných vratek, po pádu nový; přehraná selhaná vratka se pozná', () => {
  const list = [{ id: 're_1', status: 'failed' }, { id: 're_2', status: 'succeeded' }, { id: 're_3', status: 'canceled' }, { id: 're_4', status: 'pending' }]
  eq(failedRefundIds(list), ['re_1', 're_3'])
  eq([retrySuffix([]), retrySuffix(null), retrySuffix(['re_1']), retrySuffix(['re_1', 're_3'])], ['', '', ':f1', ':f2'])
  eq([isReplayOfFailed('re_1', ['re_1']), isReplayOfFailed('re_5', ['re_1']), isReplayOfFailed(null, ['re_1'])], [true, false, false])
})

Deno.test('i4 refundedStatus / statusLags: čekající zbytek z jiné platby = refund_pending, ne refunded', () => {
  const base = { refundStatus: 'succeeded', isCustomer: false, bookingTotalPrice: 3500, amount: 3500, refundableHaleru: 50000, effectiveAmountHaleru: 50000, leftHaleru: 0, fullBalance: true }
  eq(refundedStatus(base), 'refunded')
  eq(refundedStatus({ ...base, extraStatuses: ['pending'] }), 'refund_pending')
  eq(refundedStatus({ ...base, extraStatuses: ['succeeded'] }), 'refunded')
  const main: StripeRefundLike = { id: 're_1', amount: 50000, status: 'succeeded', created: 100, metadata: { mg_target: '350000' } }
  const rem: StripeRefundLike = { id: 're_2', amount: 300000, status: 'pending', created: 101, metadata: { mg_main_refund: 're_1', mg_part: 'remainder' } }
  eq(remainderPending(main, [rem, main]), true)
  eq(remainderPending(main, [{ ...rem, status: 'succeeded' }, main]), false)
  const cur = { payment_status: 'refund_pending', stripe_refund_id: 're_1' }
  eq(statusLags(cur, main, [rem, main]), false, 'zbytek čeká → stav nezaostává')
  eq(statusLags(cur, main, [{ ...rem, status: 'succeeded' }, main]), true, 'zbytek hotový → dorovnat')
})

Deno.test('i4 modifiedRefundCovered: dobropis dřívější úpravy nekryje novou (okamžik úpravy / tatáž částka)', () => {
  const now = Date.parse('2026-11-07T12:00:00Z')
  const at = '2026-11-07T11:59:00.123456+00:00'
  eq(newestModificationMs([{ at: '2026-11-07T10:00:00Z' }, { at }, { at: '2026-11-07T12:30:00' }, null]), Date.parse(at), 'místní čas appky bez zóny se ignoruje')
  eq(newestModificationMs([{ at: '2026-11-07T12:30:00.000' }]), null)
  const old = { total: -500, created_at: '2026-11-07T11:30:00Z' }, fresh = { total: -300, created_at: '2026-11-07T11:59:30Z' }
  eq([coversModification(old, 300, Date.parse(at), now), coversModification(fresh, 300, Date.parse(at), now)], [false, true], 'se známým okamžikem')
  eq([coversModification(old, 300, null, now), coversModification({ total: -300, created_at: '2026-11-07T09:00:00Z' }, 300, null, now),
    coversModification({ total: -500, created_at: '2026-11-07T11:50:00Z' }, 300, null, now)], [false, true, true], 'bez okamžiku: tatáž částka, nebo čerstvý')
  eq(coversModification({ total: -299.5, created_at: '2026-11-07T11:59:30Z' }, 300, Date.parse(at), now), true, 'tolerance 1 Kč')
})

Deno.test('i4 checkoutCzk: Adaptive Pricing (cena v CZK převedená do EUR) = CZK s částkou z currency_conversion', () => {
  eq(checkoutCzk({ currency: 'czk', amount_total: 300000 }), { ok: true, amountTotalH: 300000, converted: false })
  eq(checkoutCzk({ currency: 'eur', amount_total: 12000, currency_conversion: { source_currency: 'czk', amount_total: 300000 } }), { ok: true, amountTotalH: 300000, converted: true })
  eq(checkoutCzk({ currency: 'huf', amount_total: 50000 }), { ok: false, amountTotalH: null, converted: false })
  eq(checkoutCzk({ currency: 'eur', amount_total: 12000, currency_conversion: { source_currency: 'usd', amount_total: 13000 } }).ok, false)
  eq(checkoutCzk({ currency: null }).ok, true, 'setup session bez měny')
})

Deno.test('i4 Velín manualRefundState: ruční část i vedle vratky kartou; „Vratka odeslána“ dle všech dobropisů', () => {
  const cns = [{ total: -3000, stripe_refund_id: 're_1' }, { total: -500, stripe_refund_id: null, number: 'DB-2026-0002' }]
  eq(manualRefundOpen({ payment_status: 'refund_pending', stripe_refund_id: 're_1' }, cns)?.number, 'DB-2026-0002')
  eq(manualRefundOpen({ payment_status: 'refunded', stripe_refund_id: 're_1' }, cns), null)
  eq(manualRefundSentStatus({ total_price: 3500 }, cns), 'refunded')
  eq(manualRefundSentStatus({ total_price: 3000 }, [{ total: -1500, stripe_refund_id: null }]), 'partial_refund')
  eq(manualRefundSentStatus({ total_price: 3000 }, [{ total: -3000, stripe_refund_id: null }]), 'refunded')
})

// ── web: /potvrzeni (js/pages-potvrzeni.js) a potvrzení výpůjčky výbavy (js/gear-rental-done.js) ──
type Clock = { timers: Array<() => void>; set: (fn: () => void) => number }
const clock = (): Clock => { const c: Clock = { timers: [], set: (fn) => { c.timers.push(fn); return c.timers.length } }; return c }
async function drain(c: Clock, max = 400) {
  for (let i = 0; i < max; i++) {
    for (let k = 0; k < 20; k++) await Promise.resolve()
    const t = c.timers.shift()
    if (!t) { await new Promise((r) => setTimeout(r, 0)); if (!c.timers.length) return } else t()
  }
}

async function potvrzeni(seq: any[]): Promise<{ el: { innerHTML: string }; html: string[] }> {
  const code = await Deno.readTextFile(new URL('js/pages-potvrzeni.js', WEB))
  const el = { innerHTML: '' }, html: string[] = []
  const box = new Proxy(el, { set: (t: any, k, v) => { t[k] = v; if (k === 'innerHTML') html.push(String(v)); return true } })
  const c = clock()
  const i18n = { cancelledRefundTitle: 'CR_TITLE', cancelledRefundText: 'CR_TEXT', cancelledRefundTextBundled: 'CRB {amount} {order}', cancelledVerifyTitle: 'CV_TITLE',
    cancelledVerifyText: 'CV_TEXT', cancelledOtherTitle: 'CO_TITLE', cancelledOtherText: 'CO_TEXT', backHome: 'HOME', cancelledRefundCta: 'NEW' }
  const win: any = { MG: {}, MOTOGO_CONFIRM_I18N: i18n, MOTOGO_CONFIG: {}, dataLayer: [], sessionStorage: { getItem: () => null, setItem() {} },
    location: { search: '?session_id=cs_test_1' },
    sb: { rpc: () => Promise.resolve({ data: seq.length > 1 ? seq.shift() : seq[0] }) } }
  const doc = { readyState: 'complete', cookie: '', getElementById: (id: string) => id === 'confirm-content' ? box : null, addEventListener() {} }
  const fn = new Function('window', 'document', 'setTimeout', 'fetch', 'URLSearchParams', 'console', code)
  fn(win, doc, c.set, () => Promise.resolve(new Response('{}')), URLSearchParams, { warn() {}, log() {} })
  await drain(c)
  return { el, html }
}
const BK = { id: '11111111-2222-4333-8444-555555555555', start_date: '2026-12-10', end_date: '2026-12-12', total_price: 3000 }

Deno.test('i4 web /potvrzeni: zrušená a nezaplacená → „ověřujeme“ (ne „platbu vracíme“ / Nová rezervace), pak výsledek', async () => {
  const unpaid = { ...BK, status: 'cancelled', payment_status: 'unpaid' }
  // webhook rozhodne až po vypršení smyčky: vratka → „platbu vracíme“
  const a = await potvrzeni([...Array(16).fill(unpaid), { ...unpaid, payment_status: 'refunded' }])
  if (!a.html.some((h) => h.includes('CV_TITLE')) || a.html.some((h) => h.includes('CV_TITLE') && h.includes('NEW'))) throw new Error('chybí neutrální „ověřujeme“: ' + a.html.map((h) => h.slice(0, 80)).join(' | '))
  if (!a.el.innerHTML.includes('CR_TITLE')) throw new Error('po vratce čekáno „platbu vracíme“: ' + a.el.innerHTML.slice(0, 200))
  // oživení → potvrzení rezervace (žádná vratka)
  const b = await potvrzeni([...Array(16).fill(unpaid), { ...BK, status: 'reserved', payment_status: 'paid' }])
  if (b.el.innerHTML.includes('CR_TITLE') || b.el.innerHTML.includes('CV_TITLE')) throw new Error('oživená rezervace: ' + b.el.innerHTML.slice(0, 200))
  // vratka známá hned / přibalené zboží / běžné storno (RPC late_refund false)
  const c = await potvrzeni([{ ...unpaid, payment_status: 'refunded', bundled_order_number: 'OBJ-7', late_refund_amount: 2500 }])
  if (!c.el.innerHTML.includes('CRB') || !c.el.innerHTML.includes('OBJ-7')) throw new Error('přibalené zboží: ' + c.el.innerHTML.slice(0, 300))
  const d = await potvrzeni([{ ...unpaid, payment_status: 'refunded', late_refund: false }])
  if (!d.el.innerHTML.includes('CO_TITLE')) throw new Error('běžné storno: ' + d.el.innerHTML.slice(0, 200))
})

async function gearDone(seq: any[], session: string | null): Promise<string[]> {
  const code = await Deno.readTextFile(new URL('js/gear-rental-done.js', WEB))
  const html: string[] = []
  const box: any = new Proxy({ hidden: true, innerHTML: '' }, { set: (t: any, k, v) => { t[k] = v; if (k === 'innerHTML') html.push(String(v)); return true } })
  const c = clock()
  const T = new Proxy({ res_cancelled: 'RC', res_cancelled_refund: 'RCR', res_cancelled_verify: 'RCV', res_new: 'NEW', ok_title: 'OKT' } as Record<string, string>,
    { get: (t, k: string) => k in t ? t[k] : 'x' })
  const G: any = { C: { page: '/p', home: '/', katalog: '/k', manage: '/m' }, T, K: { ico: () => '', count: () => 1 }, esc: (x: unknown) => String(x),
    tpl: (t: string) => t, q: (sel: string) => sel === '[data-gr-done]' ? box : sel === '[data-gr-main]' ? { hidden: false } : null,
    rpc: () => Promise.resolve(seq.length > 1 ? seq.shift() : seq[0]), edge: () => Promise.resolve({}), num: (x: unknown) => Number(x) || 0,
    czk: (x: unknown) => `${x} Kč`, period: () => '', days: () => '', lc: (x: string) => x, by: {} }
  new Function('window', 'location', 'setTimeout', 'URLSearchParams', code)({ MGGR: G }, { search: '' }, c.set, URLSearchParams)
  G.confirmView(BK.id, session)
  await drain(c)
  return html
}

Deno.test('i4 web výbava: návrat ze Stripe u zrušené nezaplacené rezervace dopoluje (oživení → zaplaceno), jinak „ověřujeme“ / „vracíme“', async () => {
  const unpaid = { ...BK, status: 'cancelled', payment_status: 'unpaid' }
  const a = await gearDone([unpaid, unpaid, { ...BK, status: 'reserved', payment_status: 'paid' }], 'cs_1')
  if (a.some((h) => h.includes('RC') || h.includes('NEW')) || !a.at(-1)!.includes('OKT')) throw new Error('oživení: ' + a.map((h) => h.slice(0, 60)).join(' | '))
  const b = await gearDone([...Array(13).fill(unpaid), { ...unpaid, payment_status: 'refunded' }], 'cs_1')
  if (!b.some((h) => h.includes('RCV')) || !b.at(-1)!.includes('RCR') || b.some((h) => h.includes('NEW'))) throw new Error('vratka: ' + b.map((h) => h.slice(0, 60)).join(' | '))
  const c = await gearDone([unpaid], null) // ?resume= (bez session) → dosavadní „zrušená, vytvoř novou“
  if (!c.at(-1)!.includes('RC') || !c.at(-1)!.includes('NEW')) throw new Error('resume: ' + c.at(-1))
})

Deno.test('i4 web texty: nové klíče potvrzení ve všech 8 jazycích', async () => {
  const miss: string[] = []
  for (const l of ['cs', 'en', 'de', 'nl', 'es', 'fr', 'pl', 'uk']) {
    const s = await Deno.readTextFile(new URL(`lang/${l}.php`, WEB))
    for (const k of ['confirm.cancelledRefund.textBundled', 'confirm.cancelledVerify.title', 'confirm.cancelledVerify.text', 'confirm.cancelledOther.title', 'confirm.cancelledOther.text']) {
      if (!s.includes(`'${k}' =>`)) miss.push(`${l}:${k}`)
    }
    const g = await Deno.readTextFile(new URL(l === 'cs' ? 'data/gear-rental-flow-texts.php' : `lang/v2/${l}/gear-flow.php`, WEB))
    for (const k of ['res_cancelled_refund', 'res_cancelled_verify']) if (!g.includes(`'${k}' =>`)) miss.push(`${l}:${k}`)
  }
  if (miss.length) throw new Error('chybí: ' + miss.join(', '))
})
