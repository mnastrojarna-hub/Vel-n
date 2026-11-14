// Ruční vratka převodem (dobropis bez Stripe vratky) v detailu rezervace — banner „VRÁTIT NA ÚČET“ a akce
// „Vratka odeslána“. Oprava i4 (2026-11-07, verify:refunds S7): rezervace placená kartou + doplatek převodem
// po plném stornu bez Fio má kartovou vratku (bookings.stripe_refund_id) A ruční dobropis na část převodem;
// dřív se ruční část ukazovala jen bez stripe_refund_id, takže ji obsluha neviděla (mail jí přitom říkal
// „potvrďte tlačítkem Vratka odeslána“) a „Vratka odeslána“ pak stav nastavila jen podle ručního dobropisu.

/** Otevřený ruční dobropis: rezervace „Čeká na vrácení“ a živý dobropis bez Stripe vratky (i vedle vratky kartou). */
export function manualRefundOpen(booking, creditNotes) {
  if (booking?.payment_status !== 'refund_pending') return null
  return (creditNotes || []).find((c) => !c.stripe_refund_id) || null
}

/** Stav po „Vratka odeslána“. Oprava i5r2 (verify:refunds R2): ŽIVÁ (nezrušená) rezervace má svou aktuální cenu dál
 *  zaplacenou → vždy 'partial_refund' (dřív součet dobropisů dvou zkrácení ≥ snížená cena → 'refunded' u živé rezervace:
 *  storno pak „už vráceno“ nevrátilo nic a triggery čekající paid/partial_refund se přeskočily). Zrušená: živé dobropisy
 *  (karta + převod) kryjí zaplacené doklady (Σ živých DP — `paidDocsCzk`; bez nich cenu) → 'refunded', jinak 'partial_refund'.
 *  Bez stavu rezervace jako dřív (dle ceny). */
export function manualRefundSentStatus(booking, creditNotes, paidDocsCzk = null) {
  if (booking?.status && booking.status !== 'cancelled') return 'partial_refund'
  const paid = Number(paidDocsCzk) || 0
  const total = booking?.status === 'cancelled' && paid > 0 ? paid : (Number(booking?.total_price) || 0)
  const back = (creditNotes || []).reduce((s, c) => s + Math.abs(Number(c.total) || 0), 0)
  return total > 0 && back + 1 < total ? 'partial_refund' : 'refunded'
}

/** Σ živých dokladů o přijaté platbě (DP, Kč) rezervace — pro manualRefundSentStatus u zrušené rezervace; null = nečitelné. */
export async function livePaidDocsCzk(supabase, bookingId) {
  try {
    const { data, error } = await supabase.from('invoices').select('total').eq('booking_id', bookingId)
      .eq('type', 'payment_receipt').neq('status', 'cancelled')
    if (error) return null
    return (data || []).reduce((s, r) => s + (Number(r.total) || 0), 0)
  } catch { return null }
}

/** Dobropis patří k tomuto stornu, vznikl-li nejdřív 2 min před bookings.cancelled_at (Velín: čas prohlížeče) — jako
 *  send-cancellation-email/refund-split.ts. */
const CN_SLACK_MS = 120_000

/** Oprava i6r1 (verify:refunds W2b): „Potvrdit vrácení“ u zrušené rezervace vratku přeskočí jen kvůli živému dobropisu
 *  TOHOTO storna na stejnou částku — dobropisy a cancelled_at čte znovu z DB v okamžiku kliknutí. Dřív stačil libovolný
 *  dobropis ze stránky načtené dřív (dobropis dřívějšího zkrácení 500 Kč, nebo storno dobropis, který webhook mezitím
 *  zrušil po selhání vratky) → nic se nevrátilo a mail zákazníkovi tvrdil vrácení. Nečitelné → nepřeskočit
 *  (process-refund má vlastní kontrolu duplicity); bez cancelled_at jako dřív (kterýkoli živý dobropis). */
export async function cancelRefundAlreadyIssued(supabase, bookingId, amountCzk) {
  if (!(Number(amountCzk) > 0)) return false
  try {
    const { data: bk, error } = await supabase.from('bookings').select('cancelled_at').eq('id', bookingId).maybeSingle()
    if (error) return false
    const since = Date.parse(String(bk?.cancelled_at || ''))
    let q = supabase.from('invoices').select('id, total, created_at').eq('booking_id', bookingId).eq('type', 'credit_note').neq('status', 'cancelled')
    if (Number.isFinite(since)) q = q.gte('created_at', new Date(since - CN_SLACK_MS).toISOString())
    const { data: cns, error: cnErr } = await q
    if (cnErr) return false
    return (cns || []).some((c) => Math.abs(Number(c.total) || 0) === Number(amountCzk))
  } catch { return false }
}

/** P2 (majitel 2026-11-08): kolik už se k TOMUTO stornu vrátilo (součet živých dobropisů od bookings.cancelled_at
 *  − 2 min) — „Potvrdit vrácení“ pak pošle jen rozdíl do zadané CELKOVÉ částky storna. null = nepodařilo se načíst. */
export async function cancelRefundedSoFarCzk(supabase, bookingId) {
  try {
    const { data: bk, error } = await supabase.from('bookings').select('cancelled_at').eq('id', bookingId).maybeSingle()
    if (error) return null
    const since = Date.parse(String(bk?.cancelled_at || ''))
    let q = supabase.from('invoices').select('id, total, created_at').eq('booking_id', bookingId).eq('type', 'credit_note').neq('status', 'cancelled')
    if (Number.isFinite(since)) q = q.gte('created_at', new Date(since - CN_SLACK_MS).toISOString())
    const { data: cns, error: cnErr } = await q
    if (cnErr) return null
    return Math.round((cns || []).reduce((sum, c) => sum + Math.abs(Number(c.total) || 0), 0))
  } catch { return null }
}

/** Oprava i6r1 (verify:refunds W3): „Vratka odeslána“ — stav z AKTUÁLNÍCH dat (živé dobropisy, DP, payment_status z DB)
 *  a zápis compare-and-set na přečtený payment_status. Dřív ze seznamu dobropisů z načtení stránky: kartová vratka mezitím
 *  selhala (webhook její dobropis zrušil), stará stránka pořád sečetla 3 500 = DP → 'refunded' a „Potvrdit vrácení“ pak
 *  nevrátilo nic. Vrací zapsaný stav; chyba čtení / zápisu nebo změněný stav → výjimka (UI ji ukáže). */
export async function manualRefundSentLive(supabase, booking) {
  const id = booking?.id
  if (!id) throw new Error('Chybí rezervace.')
  const { data: cur, error } = await supabase.from('bookings').select('status, payment_status, total_price').eq('id', id).maybeSingle()
  if (error || !cur) throw new Error('Stav rezervace se nepodařilo načíst — zkuste to znovu.')
  const { data: cns, error: cnErr } = await supabase.from('invoices').select('id, total, stripe_refund_id')
    .eq('booking_id', id).eq('type', 'credit_note').neq('status', 'cancelled')
  if (cnErr) throw new Error('Dobropisy se nepodařilo načíst — zkuste to znovu.')
  const paidDocs = cur.status === 'cancelled' ? await livePaidDocsCzk(supabase, id) : null
  const status = manualRefundSentStatus({ ...booking, ...cur }, cns || [], paidDocs)
  let upd = supabase.from('bookings').update({ payment_status: status }).eq('id', id)
  upd = cur.payment_status == null ? upd.is('payment_status', null) : upd.eq('payment_status', cur.payment_status)
  const { data: done, error: uErr } = await upd.select('id')
  if (uErr) throw new Error(uErr.message || 'Zápis stavu selhal.')
  if (!Array.isArray(done) || done.length === 0) throw new Error('Stav platby se mezitím změnil — obnovte stránku a zkontrolujte vratky.')
  return status
}
