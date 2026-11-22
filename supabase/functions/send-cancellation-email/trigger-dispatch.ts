// HOTFIX storno 2026-10-29 — volání z DB triggeru trg_notify_booking_cancelled_email
// (notify_booking_cancelled_email → pg_net, jen když je GUC supabase.url nastavené).
// Tělo triggeru = {booking_id, cancellation_reason, cancelled_by_source, source}: BEZ e-mailu
// zákazníka a BEZ refund_amount/refund_percent. Dřív si send-cancellation-email vratku dopočítal
// sám ze storno tabulky (bez stropu po posunu, bez LEAST časů vyzvednutí, bez volby admina),
// díky dřívějšímu claimu mailu vyhrál nad explicitním voláním (Velín / cancel_booking_tracked)
// a reálně vracel peníze: Velín 50 % / „bez vratky“ → 100 %, hromadné storno → vratka.
// Teď trigger o penězích NIKDY nerozhoduje:
//  • nezaplacená rezervace (unpaid / NULL) → jako dřív jen mail bez vratky (i když RPC zapsala
//    booking_cancellations s nenulovou částkou — mail nesmí tvrdit vratku, která se neplatila),
//  • storno přes cancel_booking_tracked (zákazník / server) → rozhodnutí z booking_cancellations,
//    které RPC zapsala v TÉŽE transakci (created_at = bookings.cancelled_at = now() na mikrosekundy,
//    týž cancelled_by; Velín zapisuje cancelled_at z prohlížeče a svůj záznam až potom, takže se
//    shodne nanejvýš náhodou — a i pak je to jeho vlastní rozhodnutí); RPC posílá totéž rozhodnutí
//    sama → kdo dřív získá claim mailu, provede ho (právě jednou),
//  • zaplacená rezervace bez takového záznamu (Velín storno / Stripe portál / hromadné storno /
//    AI copilot) → nic (žádný claim, žádné peníze, žádný mail) — Velín i webhook vratku a mail
//    posílají samy; hromadné storno a copilot (bez cancelled_by) dostanou varování do debug_log.
/** Tvar volání z triggeru (jediný volající bez customer_email; Velín bez e-mailu mail neposílá). */ export function isTriggerDispatch(body) {
  if (!body || typeof body !== 'object') return false;
  return !body.customer_email && body.refund_amount == null && body.refund_percent == null && body.force !== true && body.skip_refund !== true;
}
/** now() z DB má mikrosekundy (výstup Postgres ořezává koncové nuly); čas z prohlížeče jen milisekundy. */ export function hasSubMs(s) {
  const f = typeof s === 'string' ? /\.(\d+)/.exec(s)?.[1] || '' : '';
  return f.length > 3 && /[1-9]/.test(f.slice(3, 6));
}
/** Stejný okamžik dvou timestamptz z PostgRESTu (včetně mikrosekund). */ export function sameInstant(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || !a || !b) return false;
  if (a === b) return true;
  const frac = (s)=>(/\.(\d+)/.exec(s)?.[1] || '').padEnd(6, '0').slice(0, 6);
  const ta = Date.parse(a), tb = Date.parse(b);
  return Number.isFinite(ta) && ta === tb && frac(a) === frac(b);
}
// deno-lint-ignore no-explicit-any
export async function resolveTriggerDispatch(supabase, bookingId) {
  try {
    const { data: bk, error } = await supabase.from('bookings').select('payment_status, cancelled_at, cancelled_by, cancelled_by_source').eq('id', bookingId).maybeSingle();
    if (error || !bk) return {
      action: 'skip',
      why: 'booking_unreadable'
    };
    if (!bk.payment_status || bk.payment_status === 'unpaid') return {
      action: 'mail_only'
    };
    const { data: rows } = await supabase.from('booking_cancellations').select('refund_amount, refund_percent, created_at, cancelled_by').eq('booking_id', bookingId).order('created_at', {
      ascending: false
    }).limit(1);
    const bc = rows?.[0];
    // Shoda okamžiku na mikrosekundy = záznam z téže transakce jako storno (cancel_booking_tracked).
    // Čas bez mikrosekund (now() končící …000, 1 : 1000) navíc ověří týž cancelled_by.
    if (bc && sameInstant(bc.created_at, bk.cancelled_at) && (hasSubMs(bk.cancelled_at) || (bc.cancelled_by ?? null) === (bk.cancelled_by ?? null))) {
      return {
        action: 'adopt',
        refund_amount: Number(bc.refund_amount) || 0,
        refund_percent: Number(bc.refund_percent) || 0
      };
    }
    // Bez cancelled_by (hromadné „Zrušit“ ve Velínu, AI copilot) a mimo Stripe portál: vratku ani mail
    // nikdo neposílá → varování obsluze do debug_log (zákazník nic nevidí).
    const staff = !bk.cancelled_by && bk.cancelled_by_source !== 'stripe_portal';
    return {
      action: 'skip',
      why: 'paid_without_tracked_decision',
      staff,
      cancelled_by_source: bk.cancelled_by_source ?? null
    };
  } catch  {
    return {
      action: 'skip',
      why: 'resolve_failed'
    };
  }
}
