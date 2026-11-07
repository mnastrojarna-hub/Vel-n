// ===== process-refund/retry-of.ts =====
// Oprava i6r1 (2026-11-07, verify:refunds W1 / W6) — opakování SELHANÉ logické vratky (hlavní vratka + zbytky z jiných
// plateb, mg_main_refund):
//  • retriedLogicalRefund — požadavek opakuje naši logickou vratku téže rezervace a důvodu se stejným požadavkem
//    (mg_target, jinak částka), které část selhala (hlavní nebo zbytek 'failed' / 'canceled') a zatím nemá živé opakování
//    (mg_retry_of = kořen řetězu). Mimo storno navíc jen když se cena rezervace od NEJNOVĚJŠÍ naší vratky úpravy nezměnila
//    (mg_price — jiná cena = DALŠÍ úprava o stejnou částku, ne opakování; bez mg_price = starší vratka → opakování);
//    storno: téhož storna (mg_cancel_at). Výsledek: kořen řetězu + živá část řetězu (haléře).
//  • process-refund vratku označí mg_retry_of = kořen / 'none' (jen když přečetl vratky všech plateb) — webhook
//    failed-refund.ts pak za „nahrazenou“ bere jen označené opakování. Dřív stačila pozdější živá vratka téhož důvodu
//    a částky, takže legitimní DRUHÉ zkrácení o stejnou částku „nahradilo“ selhanou vratku prvního (rezervace se neotevřela).
//  • mimo storno (obsluha / služba): živá část selhané logické vratky se od požadavku odečte. Dřív opakování dle mailu
//    („stejná úprava“) vrátilo celou úpravu znovu — osiřelý zbytek z jiné platby podruhé (přeplatek).
import { instantKey, type StripeRefundLike } from './cancel-once.ts'

// deno-lint-ignore no-explicit-any
type Db = any
export const NO_RETRY = 'none'

const live = (r: StripeRefundLike) => r.status === 'succeeded' || r.status === 'pending'
const failed = (r: StripeRefundLike) => r.status === 'failed' || r.status === 'canceled'
/** Požadavek logické vratky (mg_target, bez něj částka hlavní vratky), haléře. */
export function askHaleru(m: StripeRefundLike): number {
  const t = Number(m.metadata?.mg_target)
  return Number.isFinite(t) && t > 0 ? Math.round(t) : Number(m.amount || 0)
}
/** Kořen řetězu opakování (první vratka, kterou další opakují). */
export function retryRootOf(m: StripeRefundLike): string {
  const x = m.metadata?.mg_retry_of
  return x && x !== NO_RETRY ? x : m.id
}

export type RetriedRefund = { root: string; mainId: string; liveHaleru: number }

/** Logická vratka, kterou požadavek opakuje (viz hlavička); null = nový požadavek. `refunds` = vratky všech plateb. */
export function retriedLogicalRefund(refunds: StripeRefundLike[] | null | undefined, a: {
  bookingId: string; reason: string; reqHaleru: number; priceHaleru: number | null; cancelTok?: string | null
}): RetriedRefund | null {
  const rs = refunds || []
  const mains = rs.filter((r) => {
    const md = r.metadata || {}
    return md.mg_source === 'process-refund' && md.mg_booking_id === a.bookingId && (md.mg_reason || '') === (a.reason || '') && md.mg_part !== 'remainder'
  })
  if (a.reason !== 'cancellation' && a.priceHaleru != null) {
    // cena od poslední vratky úpravy jiná → požadavek je nová úprava (např. druhé zkrácení o stejnou částku), ne opakování
    const newest = rs.find((r) => {
      const md = r.metadata || {}
      return md.mg_source === 'process-refund' && md.mg_booking_id === a.bookingId && md.mg_part !== 'remainder'
        && md.mg_reason !== 'cancellation' && md.mg_price != null && md.mg_price !== ''
    })
    if (newest && Math.round(Number(newest.metadata?.mg_price)) !== a.priceHaleru) return null
  }
  const partsLive = (m: StripeRefundLike) => (live(m) ? Number(m.amount || 0) : 0)
    + rs.filter((x) => x.id !== m.id && x.metadata?.mg_main_refund === m.id && live(x)).reduce((s, x) => s + Number(x.amount || 0), 0)
  for (const m of mains) {
    if (!(a.reqHaleru > 0) || askHaleru(m) !== a.reqHaleru) continue
    const md = m.metadata || {}
    if (a.reason === 'cancellation') {
      const k = instantKey(a.cancelTok || '')
      if (k == null || instantKey(md.mg_cancel_at || '') !== k) continue
    }
    const rems = rs.filter((x) => x.id !== m.id && x.metadata?.mg_main_refund === m.id)
    if (!failed(m) && !rems.some(failed)) continue
    if (partsLive(m) >= askHaleru(m)) continue // recovery už logickou vratku dokončila
    const root = retryRootOf(m)
    if (mains.some((x) => x.id !== m.id && live(x) && x.metadata?.mg_retry_of === root)) continue // už zopakováno
    const chain = mains.filter((x) => x.id === root || x.metadata?.mg_retry_of === root)
    if (!chain.some((x) => x.id === m.id)) chain.push(m)
    return { root, mainId: m.id, liveHaleru: chain.reduce((s, x) => s + partsLive(x), 0) }
  }
  return null
}

/** Opakování je celé kryté živou částí selhané logické vratky → žádná nová vratka; dorovnat stav a odpovědět jako „už vráceno“. */
export async function respondRetryCovered(o: {
  supabase: Db; bookingId: string; retry: RetriedRefund; remaining: () => Promise<number | null>
  dlog: (action: string, status: string, extra?: Record<string, unknown>) => unknown; headers: Record<string, string>
}): Promise<Response> {
  const { data: cur } = await o.supabase.from('bookings').select('status, payment_status, card_brand, card_last4').eq('id', o.bookingId).maybeSingle()
  let repaired = false
  if (cur?.payment_status === 'refund_pending') {
    const left = await o.remaining().catch(() => null)
    const next = left === 0 && cur.status === 'cancelled' ? 'refunded' : 'partial_refund'
    const { data: upd } = await o.supabase.from('bookings').update({ payment_status: next }).eq('id', o.bookingId).eq('payment_status', 'refund_pending').select('id')
    repaired = Array.isArray(upd) && upd.length > 0
  }
  await o.dlog('refund_retry_covered', 'info', { retry_of: o.retry.root, live_haleru: o.retry.liveHaleru, repaired })
  return new Response(JSON.stringify({ success: true, already_refunded: true, refund_id: null, retry_of: o.retry.root,
    refunded_haleru: o.retry.liveHaleru, card_brand: cur?.card_brand ?? null, card_last4: cur?.card_last4 ?? null }), { status: 200, headers: o.headers })
}
