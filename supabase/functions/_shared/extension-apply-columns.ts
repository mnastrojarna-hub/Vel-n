// ===== _shared/extension-apply-columns.ts =====
// Zaplacená změna rezervace ve tvaru sloupců (web p_new_* / appka DB názvy) —
// přesunuto z webhook-receiver (applyExtensionChange, 2026-10-16) a doplněno:
//  • D1: dorovnání na minimální platbu kartou (`rounding`, +r = 15 Kč − doplatek,
//    −r = odpuštěný doplatek do 1 Kč) jde do total_price i bookings.card_rounding
//    v TÉMŽE UPDATE + do historie (price_diff = zaplaceno, card_rounding = r),
//  • F1: změnu už zapsal klient (appka ≤ 4.1.3 po 8 s bez webhooku) → NEpřičítat
//    doplatek podruhé (dřív „zastaralý základ" → cena + doplatek ještě jednou),
//  • optimistický zámek (updated_at) proti souběhu webhook ↔ complete_extension,
//  • výsledek ApplyResult (applied / already_applied / retry / failed).
import type { ApplyArgs, ApplyResult, Sb } from './extension-apply-types.ts'
import { placeFingerprint, round2, isPermanentDbError, logDebug } from './extension-apply-types.ts'

type Srv = { t?: number | null; df?: number | null; pf?: number | null; rf?: number | null; x?: boolean; l?: number | null; f?: string }
type Row = Record<string, unknown>

const fin = (v: unknown) => v != null && Number.isFinite(Number(v))
const def = (v: unknown) => v !== undefined
const defNN = (v: unknown) => v !== undefined && v !== null
const day = (v: unknown) => String(v || '').slice(0, 10)
const hm = (v: unknown) => (v == null ? '' : String(v).slice(0, 5))
const norm = (v: unknown) => String(v ?? '').trim().toLowerCase().replace(/\s+/g, ' ')

/** Cílové sloupce ze změny (1:1 s původním webhookem). */
function buildTarget(a: Row, srv: Srv): Row {
  const d: Row = {}
  if (a.p_new_start) d.start_date = a.p_new_start
  if (a.p_new_end) d.end_date = a.p_new_end
  if (a.p_new_moto_id) d.moto_id = a.p_new_moto_id
  if (a.p_new_pickup_method) d.pickup_method = a.p_new_pickup_method
  if (def(a.p_new_pickup_address)) d.pickup_address = a.p_new_pickup_address
  if (defNN(a.p_new_pickup_lat)) d.pickup_lat = a.p_new_pickup_lat
  if (defNN(a.p_new_pickup_lng)) d.pickup_lng = a.p_new_pickup_lng
  if (a.p_new_return_method) d.return_method = a.p_new_return_method
  if (def(a.p_new_return_address)) d.return_address = a.p_new_return_address
  if (defNN(a.p_new_return_lat)) d.return_lat = a.p_new_return_lat
  if (defNN(a.p_new_return_lng)) d.return_lng = a.p_new_return_lng
  // delivery_fee počítá server (srv.df z dry-runu); klientský součet jen jako
  // fallback starých plateb bez srv (web u zamčené strany posílal 0, 2026-10-01).
  if (fin(srv.df) && (def(a.p_new_pickup_fee) || def(a.p_new_return_fee) || a.p_new_pickup_method || a.p_new_return_method)) {
    d.delivery_fee = Number(srv.df)
  } else if (def(a.p_new_pickup_fee) || def(a.p_new_return_fee)) {
    d.delivery_fee = Number(a.p_new_pickup_fee || 0) + Number(a.p_new_return_fee || 0)
  }
  if (a.p_new_pickup_time) d.pickup_time = a.p_new_pickup_time
  const tu = a._time_update as Row | undefined
  if (tu && typeof tu === 'object') {
    // NULL čas vyzvednutí nezapisovat (web ho u aktivní rezervace posílal null).
    if (defNN(tu.pickup_time)) d.pickup_time = tu.pickup_time
    if (def(tu.return_time)) d.return_time = tu.return_time
  }
  // App formát (DB názvy sloupců, payment_screen.dart).
  for (const col of ['start_date', 'end_date', 'moto_id', 'pickup_method', 'pickup_address',
                     'return_method', 'return_address', 'pickup_time', 'return_time',
                     'discount_amount', 'delivery_fee', 'extras_price',
                     'loyalty_discount_amount', 'late_pickup_discount_amount',
                     'pickup_lat', 'pickup_lng', 'return_lat', 'return_lng'] as const) {
    if (def(a[col]) && d[col] === undefined) d[col] = a[col]
  }
  return d
}

/** Absolutní cílová cena BEZ dorovnání (serverový dry-run → web new_total → app total_price). */
function targetTotal(a: Row, srv: Srv): number | null {
  if (fin(srv.t)) return Number(srv.t)
  if (a.new_total != null && Number.isFinite(Number(a.new_total))) return Number(a.new_total)
  if (a.total_price != null && Number.isFinite(Number(a.total_price))) return Number(a.total_price)
  return null
}

/** F1: řádek už odpovídá cíli změny (klient ji zapsal dřív než webhook). */
function alreadyWritten(d: Row, cur: Row, target: number | null, r: number): boolean {
  if (target == null) return false
  const keys = ['start_date', 'end_date', 'moto_id', 'pickup_time', 'return_time', 'pickup_method',
    'pickup_address', 'return_method', 'return_address', 'delivery_fee'].filter((k) => d[k] !== undefined)
  if (keys.length === 0) return false
  for (const k of keys) {
    const same = k === 'start_date' || k === 'end_date' ? day(d[k]) === day(cur[k])
      : k === 'pickup_time' || k === 'return_time' ? hm(d[k]) === hm(cur[k])
      : k === 'delivery_fee' ? Math.round(Number(d[k] || 0)) === Math.round(Number(cur[k] || 0))
      : norm(d[k]) === norm(cur[k])
    if (!same) return false
  }
  const t = Math.round(Number(cur.total_price || 0))
  return t === Math.round(target) || t === Math.round(target + r)
}

export async function applyColumnChange(sb: Sb, a: Row, args: ApplyArgs, srv: Srv): Promise<ApplyResult> {
  const { bookingId, paidCzk, payRef } = args
  let r = round2(Number(args.rounding || 0))
  const target = targetTotal(a, srv)
  const base = a._base as { s?: string; e?: string; t?: string | null; p?: number; l?: number } | undefined

  for (let pass = 0; pass < 2; pass++) {
    const d = buildTarget(a, srv)
    let cur: Row | null = null
    try {
      const { data, error } = await sb.from('bookings').select('*').eq('id', bookingId).maybeSingle()
      if (error) return { state: 'retry', code: 'read_failed', detail: error.message }
      cur = (data as Row | null) || null
    } catch (e) { return { state: 'retry', code: 'read_failed', detail: (e as Error).message } }
    if (!cur) return { state: 'failed', code: 'change_failed', reason: 'not_found' }
    const hasRoundingCol = 'card_rounding' in cur
    if (r !== 0 && !hasRoundingCol) {
      // Rozdíl platby v celých Kč (zaplaceno kartou, |r| < 1) bez sloupce jen nezaznamenat;
      // dorovnání na 15 Kč / odpuštění bez sloupce zapsat nejde (process-payment ho bez SQL nepovolí).
      if (paidCzk != null && paidCzk > 0 && Math.abs(r) < 1) r = 0
      else return { state: 'retry', code: 'rounding_unavailable' }
    }

    // Opakované doručení / druhý dokončovatel — změna už je zapsaná (payment_ref).
    const hist0 = Array.isArray(cur.modification_history) ? (cur.modification_history as Array<Row | null>) : []
    if (payRef && hist0.some((h) => !!h && h.payment_ref === payRef)) {
      await logDebug(sb, 'extension_change_duplicate_skipped', 'info', { booking_id: bookingId, payment_ref: payRef })
      return { state: 'already_applied', bookingId, totalPrice: Number(cur.total_price || 0) }
    }

    // Aktivní rezervace: vyzvednutí už proběhlo → místo ani čas vyzvednutí se nemění.
    let pickupDropped = false
    if (cur.status === 'active') {
      for (const k of ['pickup_method', 'pickup_address', 'pickup_lat', 'pickup_lng']) {
        if (d[k] !== undefined && String(d[k] ?? '') !== String(cur[k] ?? '')) pickupDropped = true
        delete d[k]
      }
      if (d.pickup_time !== undefined) {
        const nt = hm(d.pickup_time), ot = hm(cur.pickup_time)
        if (nt !== ot && !((ot === '00:01' || ot === '') && nt < '12:00')) pickupDropped = true
        delete d.pickup_time
      }
    }
    const written = !pickupDropped && alreadyWritten(d, cur, target, r)
    const placeTarget: Row = { ...cur }
    for (const k of ['pickup_method', 'pickup_address', 'return_method', 'return_address', 'delivery_fee']) {
      if (d[k] !== undefined) placeTarget[k] = d[k]
    }
    const placeStale = typeof srv.f === 'string' && !!srv.f && srv.f !== placeFingerprint(cur)
      && placeFingerprint(placeTarget) !== placeFingerprint(cur)
    const stale = !written && (pickupDropped || placeStale || !!(base && typeof base === 'object' && (
      (base.s && day(base.s) !== day(cur.start_date)) ||
      (base.e && day(base.e) !== day(cur.end_date)) ||
      (base.t !== undefined && hm(base.t) !== hm(cur.pickup_time)) ||
      (base.p != null && Math.round(Number(base.p)) !== Math.round(Number(cur.total_price || 0)))
    )))

    if (target != null) d.total_price = round2(target + r)
    // Dorovnání bez absolutní cílové ceny (neobvyklý payload) → cena + skutečně zaplaceno,
    // aby card_rounding zůstalo součástí total_price.
    else if (r !== 0 && paidCzk != null && Number.isFinite(paidCzk)) d.total_price = round2(Number(cur.total_price || 0) + paidCzk)
    if (stale) {
      // Zastaralý základ: místo ani delivery_fee se z platby nepřepisují; cena = aktuální + zaplaceno
      // (zaplaceno už obsahuje dorovnání r).
      for (const k of ['pickup_method', 'pickup_address', 'pickup_lat', 'pickup_lng',
                       'return_method', 'return_address', 'return_lat', 'return_lng', 'delivery_fee']) delete d[k]
      if (paidCzk != null && Number.isFinite(paidCzk)) d.total_price = Math.round(Number(cur.total_price || 0) + paidCzk)
      await logDebug(sb, 'extension_change_stale_baseline', 'error', {
        booking_id: bookingId, base, paid_czk: paidCzk, card_rounding: r, change: d,
        current: { start_date: cur.start_date, end_date: cur.end_date, pickup_time: cur.pickup_time, total_price: cur.total_price },
      }, 'Změna naceněna proti jinému stavu rezervace než je v DB — zapsána delta (aktuální cena + zaplaceno)')
    }
    if (written) {
      await logDebug(sb, 'extension_change_already_written', 'info', { booking_id: bookingId, payment_ref: payRef, total_price: cur.total_price })
    }
    // Řádek už nese cenu VČETNĚ dorovnání (zapsal ho dřív souběžný dokončovatel bez
    // payment_ref) → dorovnání nepřičítat podruhé.
    const roundingIn = written && target != null && round2(Number(cur.total_price || 0)) === round2(target + r)
      && round2(target + r) !== round2(target)
    if (r !== 0 && !roundingIn) d.card_rounding = round2(Number(cur.card_rounding || 0) + r)

    // Late-pickup sleva — autoritativně (beze změny oproti webhooku 2026-10-01).
    if (!stale && fin(srv.l) && (d.start_date || d.end_date || d.moto_id || d.pickup_time)) {
      d.late_pickup_discount_amount = Math.max(0, Math.round(Number(srv.l)))
    } else if (d.start_date || d.end_date || d.moto_id || d.pickup_time || def(a.late_pickup_discount_amount)) {
      try {
        const pt = d.pickup_time !== undefined ? d.pickup_time : cur.pickup_time
        const { data: late, error: lateErr } = await sb.rpc('_late_pickup_discount', {
          p_moto_id: (d.moto_id ?? cur.moto_id) as string,
          p_start: String(d.start_date ?? cur.start_date),
          p_end: String(d.end_date ?? cur.end_date),
          p_pickup_time: pt == null ? null : String(pt),
        })
        if (!lateErr && late != null && Number.isFinite(Number(late))) {
          const sent = a.late_pickup_discount_amount != null ? Number(a.late_pickup_discount_amount) : NaN
          d.late_pickup_discount_amount = Number.isFinite(sent) && sent >= 0 ? Math.min(Number(late), Math.round(sent)) : Number(late)
        }
      } catch { /* best-effort */ }
    }
    if (Object.keys(d).length === 0) return { state: 'already_applied', bookingId, totalPrice: Number(cur.total_price || 0) }

    addHistory(d, cur, base, srv, { paidCzk, payRef, stale, r })

    let q = sb.from('bookings').update(d).eq('id', bookingId)
    if (cur.updated_at) q = q.eq('updated_at', cur.updated_at)
    const { data: upd, error } = await q.select('id')
    if (error) {
      const permanent = isPermanentDbError(error)
      await logDebug(sb, 'extension_change_apply_failed', 'error', { booking_id: bookingId, fields: Object.keys(d), paid_czk: paidCzk, code: error.code }, error.message)
      return permanent ? { state: 'failed', code: 'change_failed', reason: 'db_refused', detail: error.message }
        : { state: 'retry', code: 'apply_failed', detail: error.message }
    }
    if (Array.isArray(upd) && upd.length === 0) continue // souběh (updated_at se změnil) → načíst znovu
    await logDebug(sb, 'extension_change_applied', 'ok', { booking_id: bookingId, fields: Object.keys(d), paid_czk: paidCzk, stale_baseline: stale, card_rounding: r, already_written: written })
    return { state: 'applied', bookingId, totalPrice: Number(d.total_price ?? cur.total_price ?? 0) }
  }
  return { state: 'retry', code: 'concurrent_update' }
}

function addHistory(d: Row, cur: Row, base: { s?: string; e?: string; t?: string | null; l?: number } | undefined, srv: Srv,
  o: { paidCzk: number | null; payRef: string | null; stale: boolean; r: number }) {
  try {
    const fromS = day((base && base.s) || cur.start_date), fromE = day((base && base.e) || cur.end_date)
    const toS = d.start_date ? day(d.start_date) : day(cur.start_date)
    const toE = d.end_date ? day(d.end_date) : day(cur.end_date)
    const fromT = hm(base && base.t !== undefined ? base.t : cur.pickup_time)
    const toT = d.pickup_time !== undefined ? hm(d.pickup_time) : hm(cur.pickup_time)
    const fromL = Math.round(Number((base && base.l != null) ? base.l : (cur.late_pickup_discount_amount ?? 0)))
    const toL = Math.round(Number(d.late_pickup_discount_amount ?? cur.late_pickup_discount_amount ?? 0))
    const datesChanged = toS !== fromS || toE !== fromE
    const motoChanged = !!d.moto_id && String(d.moto_id) !== String(cur.moto_id || '')
    const chgd = (k: string) => d[k] !== undefined && String(d[k] ?? '') !== String(cur[k] ?? '')
    const placeChanged = chgd('pickup_method') || chgd('pickup_address') || chgd('return_method') || chgd('return_address')
      || (d.delivery_fee !== undefined && Math.round(Number(d.delivery_fee)) !== Math.round(Number(cur.delivery_fee || 0)))
    const returnTimeChanged = d.return_time !== undefined && hm(d.return_time) !== hm(cur.return_time)
    // Vždy zapsat záznam s payment_ref (dedup opakování); dřív jen při viditelné změně.
    const meaningful = datesChanged || motoChanged || placeChanged || returnTimeChanged || toT !== fromT || fromL !== toL
      || o.r !== 0 || !!o.payRef
    if (!meaningful) return
    const hist = Array.isArray(cur.modification_history) ? [...(cur.modification_history as unknown[])] : []
    const priceDiff = (o.paidCzk != null && Number.isFinite(o.paidCzk)) ? Math.round(o.paidCzk)
      : (d.total_price != null ? Math.round(Number(d.total_price) - Number(cur.total_price || 0)) : null)
    hist.push({
      at: new Date().toISOString(),
      from_start: fromS, from_end: fromE, to_start: toS, to_end: toE,
      from_pickup_time: fromT || null, to_pickup_time: toT || null,
      from_late_pickup: fromL, to_late_pickup: toL,
      ...(motoChanged ? { from_moto_id: cur.moto_id, to_moto_id: d.moto_id } : {}),
      ...(returnTimeChanged ? { from_return_time: hm(cur.return_time) || null, to_return_time: hm(d.return_time) || null } : {}),
      ...(placeChanged ? {
        from_pickup_method: cur.pickup_method ?? null, to_pickup_method: (d.pickup_method ?? cur.pickup_method) ?? null,
        from_pickup_address: cur.pickup_address ?? null, to_pickup_address: (d.pickup_address !== undefined ? d.pickup_address : cur.pickup_address) ?? null,
        from_return_method: cur.return_method ?? null, to_return_method: (d.return_method ?? cur.return_method) ?? null,
        from_return_address: cur.return_address ?? null, to_return_address: (d.return_address !== undefined ? d.return_address : cur.return_address) ?? null,
        from_delivery_fee: cur.delivery_fee ?? null, to_delivery_fee: (d.delivery_fee ?? cur.delivery_fee) ?? null,
        ...(fin(srv.pf) && fin(srv.rf) && d.delivery_fee !== undefined && Math.round(Number(srv.pf) + Number(srv.rf)) === Math.round(Number(d.delivery_fee))
          ? { pickup_fee_to: Number(srv.pf), return_fee_to: Number(srv.rf), fee_split_exact: srv.x === true } : {}),
      } : {}),
      ...(priceDiff != null ? { price_diff: priceDiff } : {}),
      ...(o.r !== 0 ? { card_rounding: o.r } : {}),
      source: 'stripe_webhook',
      ...(o.payRef ? { payment_ref: o.payRef } : {}),
      ...(o.stale ? { stale_baseline: true } : {}),
    })
    d.modification_history = hist
    if (datesChanged && !cur.original_start_date) {
      d.original_start_date = fromS
      d.original_end_date = fromE
    }
  } catch { /* historie je best-effort */ }
}
