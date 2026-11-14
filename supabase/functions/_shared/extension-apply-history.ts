// ===== _shared/extension-apply-history.ts =====
// Záznam zaplacené změny do bookings.modification_history (vyčleněno z
// extension-apply-columns.ts kvůli limitu velikosti souboru, beze změny chování):
// payment_ref = deduplikace opakování, chg_hash = pozná se tatáž změna zaplacená
// jinou platbou (duplicita), card_rounding = dorovnání D1, price_diff = zaplaceno.
import type { Srv } from './extension-apply-columns.ts'

type Row = Record<string, unknown>
const fin = (v: unknown) => v != null && Number.isFinite(Number(v))
const day = (v: unknown) => String(v || '').slice(0, 10)
const hm = (v: unknown) => (v == null ? '' : String(v).slice(0, 5))

export function addHistory(d: Row, cur: Row, base: { s?: string; e?: string; t?: string | null; l?: number } | undefined, srv: Srv,
  o: { paidCzk: number | null; payRef: string | null; stale: boolean; r: number; hash: string | null }) {
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
      ...(o.hash ? { chg_hash: o.hash } : {}),
      ...(o.stale ? { stale_baseline: true } : {}),
    })
    d.modification_history = hist
    if (datesChanged && !cur.original_start_date) {
      d.original_start_date = fromS
      d.original_end_date = fromE
    }
  } catch { /* historie je best-effort */ }
}
