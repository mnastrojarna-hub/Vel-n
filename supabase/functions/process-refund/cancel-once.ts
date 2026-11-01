// HOTFIX storno 2026-10-29 — vratka storna nejvýš JEDNOU za storno rezervace.
// Dřív dostalo DRUHÉ volání téže storno vratky (send-cancellation-email po Velínu, když Stripe
// vratka čekala „pending“ nebo process-refund spadl po refunds.create; webhook charge.refunded
// doručený znovu po 30min okně claimu mailu; ruční vratka v Stripe dashboardu později) NOVÝ Stripe
// idempotency klíč (`refundable` už první vratku odečetl) a vrátilo peníze podruhé.
//  • Zámek: claim_email_send(booking, 'refund_cancellation') — souběžná storno volání téže
//    rezervace jdou po sobě (uvolní se po doběhnutí, jinak vyprší za LOCK_WINDOW_MIN).
//  • Značka: každá storno vratka nese v metadatech mg_cancel_at = bookings.cancelled_at (identita
//    storna; po obnovení a novém stornu je jiná). Porovnává se OKAMŽIK, ne text.
//  • Server (send-cancellation-email → reason 'cancellation'): ke stornu, ke kterému už naše storno
//    vratka existuje (succeeded/pending), žádnou další nevytvoří — jen dorovná stav platby a dobropis.
//  • Obsluha (Velín): vědomá další vratka („Potvrdit vrácení“ jiné částky) projde; zastaví se jen
//    DUPLICITA téhož požadavku — stejná částka ≤ 3 min (dvojité odeslání, i když první vratka čeká
//    „pending“), nebo vratka vzniklá, zatímco volání čekalo na zámek (souběžný dvojklik / dvě okna).
//    Dřív (bez zámku) duplicitu srazil stejný Stripe idempotency klíč; zámek ji jinak rozbil.
export const CANCEL_LOCK_SLUG = 'refund_cancellation';
const LOCK_WINDOW_MIN = 3;
const LOCK_WAIT_MS = 8000;
const LOCK_POLL_MS = 250;
// Vratka z verze před hotfixem (bez mg_cancel_at): k tomuto stornu patří, vznikla-li nejdřív hodinu
// před bookings.cancelled_at (Velín zapisuje čas prohlížeče — tolerance posunutých hodin).
const LEGACY_SLACK_MS = 60 * 60_000;
const CLOCK_SLACK_S = 2 // hodiny Stripe vs. edge
;
const DUP_WINDOW_S = LOCK_WINDOW_MIN * 60;
// Vratka mladší než tohle, zatímco zámek drží jiné volání = to ji ještě dokončuje (stav, dobropis).
const FRESH_MS = 60_000;
/** Identita storna = bookings.cancelled_at (timestamptz z PostgRESTu). */ export function cancelToken(cancelledAt) {
  return typeof cancelledAt === 'string' ? cancelledAt : '';
}
/** timestamptz → klíč okamžiku na mikrosekundy ('Z' i '+00:00', ořezané koncové nuly). */ export function instantKey(s) {
  if (typeof s !== 'string' || !s) return null;
  const ms = Date.parse(s);
  if (!Number.isFinite(ms)) return null;
  return `${ms}.${(/\.(\d+)/.exec(s)?.[1] || '').padEnd(6, '0').slice(3, 6)}`;
}
function ours(r, bookingId) {
  const md = r.metadata || {};
  return (r.status === 'succeeded' || r.status === 'pending') && md.mg_source === 'process-refund' && md.mg_reason === 'cancellation' && md.mg_booking_id === bookingId;
}
/** Naše vratky TOHOTO storna (succeeded/pending), v pořadí ze Stripe (nejnovější první). */ export function priorCancellationRefunds(refunds, bookingId, token) {
  const t = Date.parse(token), key = instantKey(token);
  return (refunds || []).filter((r)=>{
    if (!ours(r, bookingId)) return false;
    const at = r.metadata?.mg_cancel_at;
    if (typeof at === 'string') return at === token || key != null && instantKey(at) === key;
    return !token || !Number.isFinite(t) || Number(r.created) * 1000 >= t - LEGACY_SLACK_MS;
  });
}
/** Obsluha: duplicita téhož požadavku — stejná částka ≤ 3 min, nebo (bez částky) vratka vzniklá při čekání na zámek. */ export function duplicateAdminRefunds(refunds, bookingId, o) {
  const since = o.lock?.waited ? o.lock.sinceS : null;
  return (refunds || []).filter((r)=>{
    if (!ours(r, bookingId)) return false;
    const c = Number(r.created);
    if (o.amountHaleru != null && o.amountHaleru > 0) {
      return Number(r.amount) === o.amountHaleru && c >= Math.min(o.nowS - DUP_WINDOW_S, since ?? Infinity);
    }
    return since != null && c >= since;
  });
}
/** Od kdy drží zámek jiné volání (jeho vratka vznikla až potom); bez údaje = teď. */ async function lockSinceS(supabase, bookingId) {
  const now = Math.floor(Date.now() / 1000) - CLOCK_SLACK_S;
  try {
    const { data } = await supabase.from('email_send_locks').select('locked_at').eq('booking_id', bookingId).eq('template_slug', CANCEL_LOCK_SLUG).maybeSingle();
    const v = data?.locked_at;
    const ms = typeof v === 'number' ? v : Date.parse(String(v ?? ''));
    return Number.isFinite(ms) ? Math.min(now, Math.floor(ms / 1000) - CLOCK_SLACK_S) : now;
  } catch  {
    return now;
  }
}
/** Zámek storno vratky rezervace (čeká až LOCK_WAIT_MS). held=false = bez zámku (RPC chybí / stále drženo). */ export async function acquireCancelLock(supabase, bookingId) {
  const until = Date.now() + LOCK_WAIT_MS;
  let sinceS = null;
  const out = (held)=>({
      held,
      waited: sinceS != null,
      sinceS
    });
  for(;;){
    try {
      const { data, error } = await supabase.rpc('claim_email_send', {
        p_booking_id: bookingId,
        p_slug: CANCEL_LOCK_SLUG,
        p_window_minutes: LOCK_WINDOW_MIN
      });
      if (error) return out(false);
      if (data === true) return out(true);
    } catch  {
      return out(false);
    }
    if (sinceS == null) sinceS = await lockSinceS(supabase, bookingId);
    if (Date.now() >= until) return out(false);
    await new Promise((r)=>setTimeout(r, LOCK_POLL_MS));
  }
}
export async function releaseCancelLock(supabase, bookingId) {
  try {
    await supabase.from('email_send_locks').delete().eq('booking_id', bookingId).eq('template_slug', CANCEL_LOCK_SLUG);
  } catch  {}
}
/** Stav platby nezná vratku storna (process-refund spadl po refunds.create): uložená vratka chybí nebo je STARŠÍ. */ function statusLags(cur, prior, refunds) {
  if (![
    'paid',
    'refund_pending',
    'partial_refund'
  ].includes(cur.payment_status)) return false;
  const stored = cur.stripe_refund_id || null;
  if (stored === prior.id) return false;
  if (!stored) return true;
  const s = (refunds || []).find((r)=>r.id === stored);
  return !!s && Number(s.created) <= Number(prior.created);
}
async function findCn(supabase, bookingId, refundId) {
  try {
    const { data } = await supabase.from('invoices').select('id, pdf_path').eq('booking_id', bookingId).eq('type', 'credit_note').eq('stripe_refund_id', refundId).neq('status', 'cancelled').limit(1);
    return {
      creditNoteId: data?.[0]?.id ?? null,
      pdfPath: data?.[0]?.pdf_path ?? null,
      refundId
    };
  } catch  {
    return {
      creditNoteId: null,
      pdfPath: null,
      refundId
    };
  }
}
/** Vratka tohoto storna už existuje → žádný nový Stripe refund; dorovnat stav + dobropis a vrátit ji. */ export async function respondExistingCancelRefund(o) {
  const { supabase, bookingId, prior } = o;
  const { data: cur } = await supabase.from('bookings').select('payment_status, stripe_refund_id, card_brand, card_last4').eq('id', bookingId).maybeSingle();
  // Zámek drží jiné volání a vratka je čerstvá → to ji právě dokončuje (stav, dobropis): nesahat,
  // jen vrátit existující dobropis (souběžný INSERT by vystavil druhý; attach smyčka mailu počká).
  const busy = !o.lockHeld && Date.now() - Number(prior.created) * 1000 < FRESH_MS;
  const card = {
    brand: cur?.card_brand ?? null,
    last4: cur?.card_last4 ?? null
  };
  let repaired = false;
  if (!busy && cur && statusLags(cur, prior, o.refunds)) {
    // process-refund spadl po refunds.create a před zápisem stavu → dopsat, co by zapsal sám.
    const patch = {
      stripe_refund_id: prior.id,
      payment_status: prior.status === 'pending' ? 'refund_pending' : o.refundableHaleru === 0 ? 'refunded' : 'partial_refund'
    };
    if (!card.brand || !card.last4) {
      const c = await o.cardOf(prior).catch(()=>null);
      if (c?.brand && !card.brand) patch.card_brand = card.brand = c.brand;
      if (c?.last4 && !card.last4) patch.card_last4 = card.last4 = c.last4;
    }
    await supabase.from('bookings').update(patch).eq('id', bookingId);
    repaired = true;
  }
  let cn;
  if (busy) cn = await findCn(supabase, bookingId, prior.id);
  else {
    cn = await o.createCn(supabase, bookingId, {
      stripe_refund_id: prior.id
    });
    if (cn.creditNoteId && !cn.pdfPath) cn = await o.ensureCn(supabase, bookingId, {
      stripe_refund_id: prior.id
    });
  }
  await o.dlog('cancellation_refund_exists', 'info', {
    refund_id: prior.id,
    refund_status: prior.status,
    cancel_token: o.token,
    credit_note_id: cn.creditNoteId,
    busy,
    repaired
  });
  return new Response(JSON.stringify({
    success: true,
    already_refunded: true,
    cancellation_refund_exists: true,
    refund_id: prior.id,
    status: prior.status,
    credit_note_id: cn.creditNoteId,
    credit_note_pdf_path: cn.pdfPath,
    card_brand: card.brand,
    card_last4: card.last4
  }), {
    status: 200,
    headers: o.headers
  });
}
