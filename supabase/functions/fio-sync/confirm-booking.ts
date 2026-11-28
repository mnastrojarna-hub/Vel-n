// ===== fio-sync/confirm-booking.ts =====
// Potvrzení CELÉ platby rezervace (motorka i výpůjčka jen výbavy) a DOPLATKU z Velína bankovním
// převodem. Tělo potvrzení je 1:1 původní blok fio-sync (= ruční tlačítko „Potvrdit platbu“ ve Velíně /
// Stripe webhook): payment_reference → RPC confirm_payment (bank_transfer) → ZF + DP → mail →
// zpráva do appky → audit. Stejnou rutinu volá automatické párování i ruční spárování z Velína.
// Nové (jen s nasazeným SQL 20261130a1 — ctx.caps.state): částečné platby se sčítají, duplicitní
// platba jde obsluze, pozdní platba po automatickém zrušení rezervaci obnoví, je-li termín volný
// (confirm_payment zrušenou oživí; nejde-li to kvůli překryvu, rezervace zůstane zrušená → obsluha).
import { bookingKindOf, paidMailType } from '../webhook-receiver/gear-docs.ts'
import { gearPaidMessageFor } from './gear-msg.ts'
import { audit, type Ctx, debugLog, edgePost, fmtAmount, type Outcome, RetryError, type Row, short, type Tx } from './util.ts'
import { notifyConfirmed, notifyMismatch, notifyReview, notifyUnderpaid, notifyUnmatched } from './ops-mail.ts'
import { confirmedByOther, priorPartial } from './partials.ts'

export const BOOKING_SELECT = 'id, status, payment_status, payment_method, total_price, booking_source, user_id, moto_id, start_date, end_date, docs_completed_at, cancelled_by_source, motorcycles!moto_id(model, manual_url), profiles(full_name, email)'

export type PairOpts = { manual: boolean; accept: boolean; vs: string }

/** Celá platba rezervace. */
export async function handleBooking(ctx: Ctx, p: Tx, booking: Row, o: PairOpts): Promise<Outcome> {
  const { sb, caps, env } = ctx
  const bId = String(booking.id)
  const bn = '#' + short(bId)
  const expected = Number(booking.total_price) || 0
  const base = { bookingId: bId, targetType: 'booking' as const, expected }

  if (booking.payment_status === 'paid') {
    if (caps.state) {
      const other = await confirmedByOther(ctx, p, 'booking', bId, 'confirmed_booking')
      if (other != null || String(booking.payment_method || '') !== 'bank_transfer') {
        await notifyReview(env, p, 'duplicitní platba', `Rezervace <strong>${bn}</strong> už je zaplacená (${other != null ? 'pohybem FIO ' + other : 'jiným způsobem: ' + (booking.payment_method || '—')}). Tato platba je navíc — vraťte ji zákazníkovi převodem.`)
        return { ...base, status: 'needs_review', reason: 'duplicate', note: 'duplicitní platba — rezervace už je zaplacená, vraťte' }
      }
    }
    return { ...base, status: 'already_paid', note: 'rezervace už zaplacená' }
  }

  const st = String(booking.status)
  let late = false
  if (!['pending', 'reserved', 'active'].includes(st)) {
    // Pozdní platba po automatickém zrušení (nezaplaceno ve lhůtě) → zkusit obnovit jako u karty.
    // Ručně spárovanou zrušenou a nezaplacenou rezervaci zkusíme obnovit vždy (rozhodla obsluha).
    late = caps.state && st === 'cancelled' && booking.payment_status === 'unpaid' &&
      (o.manual || String(booking.cancelled_by_source || '') === 'auto')
    if (!late) {
      if (!caps.state) {
        // Např. platba po 4h auto-zrušení — revive nechává na adminovi
        // (motorka mohla být mezitím zarezervovaná jinému zákazníkovi).
        await notifyUnmatched(env, p, `Platba sedí na rezervaci ${bn}, ale ta je ve stavu „${st}" (pravděpodobně platba po automatickém zrušení). Potvrďte / vraťte ručně ve Velíně.`)
        return { ...base, status: 'needs_review', note: `rezervace ve stavu ${st}` }
      }
      await notifyReview(env, p, 'platba k uzavřené rezervaci', `Platba patří k rezervaci <strong>${bn}</strong>, ale ta je ve stavu „${st}“ — nepotvrdila se. Vraťte ji zákazníkovi, nebo rozhodněte ručně.`)
      return { ...base, status: 'needs_review', reason: 'target_closed', note: `rezervace ve stavu ${st}` }
    }
  }

  const part = await priorPartial(ctx, p, 'booking', bId)
  const received = p.amount + part.sum
  if (received + 0.01 < expected && !(caps.state && o.accept)) {
    if (caps.state) await notifyUnderpaid(env, p, 'rezervace ' + bn, expected, received)
    else await notifyMismatch(env, p, bId, expected, 'rezervace')
    return { ...base, status: 'amount_mismatch', reason: 'underpaid',
      note: part.ids.length ? `přišlo celkem ${fmtAmount(received)} (${part.ids.length + 1} platby), cena ${fmtAmount(expected)} Kč` : `přišlo ${fmtAmount(p.amount)}, cena ${fmtAmount(expected)} Kč` }
  }

  const txRef = 'FIO ' + p.fio_id
  // ── Potvrzení — 1:1 s ručním tlačítkem ve Velíně / Stripe webhookem ──
  await sb.from('bookings').update({ payment_reference: txRef }).eq('id', bId)

  const { data: cp, error: cpErr } = await sb.rpc('confirm_payment', { p_booking_id: bId, p_method: 'bank_transfer' })
  if (cpErr || (cp as { success?: boolean } | null)?.success === false) {
    const msg = cpErr?.message || (cp as { error?: string } | null)?.error || 'rpc_failed'
    if (late && !cpErr) {
      // Zrušenou rezervaci nešlo obnovit (termín / kus mezitím obsadil někdo jiný) → zůstává zrušená.
      const { data: again } = await sb.from('bookings').select('status').eq('id', bId).maybeSingle()
      if ((again as { status?: string } | null)?.status === 'cancelled') {
        await debugLog(sb, 'late_payment_revive_failed', 'warning', { fio_id: p.fio_id, booking_id: bId }, msg)
        await notifyReview(env, p, 'pozdní platba — termín už není volný', `Platba přišla po automatickém zrušení rezervace <strong>${bn}</strong> a rezervaci už nešlo obnovit (termín nebo výbava jsou mezitím obsazené). Rezervace zůstává zrušená — vraťte platbu zákazníkovi převodem.`)
        return { ...base, status: 'needs_review', reason: 'late_cancelled', note: 'pozdní platba — rezervaci nešlo obnovit, vraťte' }
      }
    }
    await debugLog(sb, 'confirm_payment_failed', 'error', { fio_id: p.fio_id, booking_id: bId }, msg)
    if (caps.state) throw new RetryError('confirm_payment: ' + msg, bId)
    return { ...base, status: 'error', note: 'confirm_payment: ' + msg }
  }
  if ((cp as { was_already_paid?: boolean } | null)?.was_already_paid) {
    return { ...base, status: 'already_paid', note: 'souběh — už potvrzeno jinou cestou' }
  }
  await debugLog(sb, 'confirm_payment', 'ok', { fio_id: p.fio_id, booking_id: bId, amount: p.amount, vs: o.vs, ...(late ? { revived: true } : {}) })

  await afterBookingPaid(ctx, p, booking, o.vs)

  const overpay = received > expected + 0.01
  const under = received + 0.01 < expected
  await notifyConfirmed(env, p, bId, expected, false, overpay)
  const notes = [
    late ? 'pozdní platba — rezervace obnovena' : null,
    overpay ? `přeplatek: přišlo ${fmtAmount(received)}, cena ${fmtAmount(expected)} Kč` : null,
    under ? `obsluha přijala nižší částku: ${fmtAmount(received)} z ${fmtAmount(expected)} Kč` : null,
    o.manual ? 'spárováno ručně' : null,
  ].filter(Boolean)
  return { ...base, status: 'confirmed_booking', absorbed: part.ids,
    reason: overpay ? 'overpaid' : under ? 'accepted_lower' : late ? 'late_revived' : o.manual ? 'manual' : null,
    followup: overpay ? 'overpaid' : null, note: notes.length ? notes.join('; ') : null }
}

/** Doklady, potvrzovací mail, zpráva do appky a audit po potvrzené platbě (beze změny proti dřívějšku). */
async function afterBookingPaid(ctx: Ctx, p: Tx, booking: Row, vs: string) {
  const { sb, env } = ctx
  const bId = String(booking.id)
  // ── ZF (pokud chybí) + DP se skutečným VS a datem úhrady — stejné
  //    doklady jako ruční potvrzení; send-booking-email je pak reuse-ne. ──
  const invoiceErrors: string[] = []
  try {
    const { data: existingInv } = await sb.from('invoices').select('id, type')
      .eq('booking_id', bId).in('type', ['advance', 'proforma', 'payment_receipt']).neq('status', 'cancelled')
    const genInvoice = (body: Row) => edgePost(env, 'generate-invoice', body).then((r) => r.json().catch(() => ({})))
    if (!(existingInv || []).some((i: { type: string }) => i.type === 'advance' || i.type === 'proforma')) {
      const zf = await genInvoice({ type: 'advance', booking_id: bId, source: 'booking', variable_symbol: vs || undefined, send_email: false })
      if (!zf?.success) invoiceErrors.push('ZF: ' + (zf?.error || 'failed'))
    }
    if (!(existingInv || []).some((i: { type: string }) => i.type === 'payment_receipt')) {
      const dp = await genInvoice({ type: 'payment_receipt', booking_id: bId, variable_symbol: vs || undefined, invoice_date: p.tx_date, send_email: false })
      if (!dp?.success) invoiceErrors.push('DP: ' + (dp?.error || 'failed'))
    }
  } catch (e) { invoiceErrors.push((e as Error).message) }
  if (invoiceErrors.length > 0) {
    await debugLog(sb, 'invoice_generation_failed', 'warning', { fio_id: p.fio_id, booking_id: bId }, invoiceErrors.join('; '))
  }

  // ── Potvrzovací mail — stejné rozhodnutí jako webhook / ruční flow:
  //    web + nedokončené doklady → invoice_payment_receipt (ZF+DP + výzva
  //    doplnit údaje), jinak kompletní booking_reserved. ──
  const profile = (booking.profiles ?? null) as { full_name?: string; email?: string } | null
  const moto = (booking.motorcycles ?? null) as { model?: string; manual_url?: string } | null
  const source = String(booking.booking_source || 'app')
  // Výpůjčka výbavy (2026-10-23): doklady per rezervace (jen totožnost + 18+) a vlastní
  // text zprávy do appky — webhook-receiver/gear-docs.ts; motorka beze změny.
  // Řádek s motorkou = vždy motorka (CHECK bookings_gear_shape) → bez dotazu na booking_kind.
  const kind = booking.moto_id ? 'moto' : await bookingKindOf(sb, bId)
  if (profile?.email) {
    const mailType = await paidMailType(sb, {
      id: bId, user_id: booking.user_id as string | null, end_date: booking.end_date as string | null,
      moto_id: booking.moto_id as string | null, docs_completed_at: booking.docs_completed_at as string | null,
    }, source, kind)
    try {
      const mr = await edgePost(env, 'send-booking-email', {
        type: mailType, booking_id: bId,
        customer_email: profile.email, customer_name: profile.full_name || '',
        motorcycle: moto?.model || '', start_date: booking.start_date, end_date: booking.end_date,
        total_price: booking.total_price, source, manual_url: moto?.manual_url || '',
      })
      if (!mr.ok) await debugLog(sb, 'confirmation_mail_http_error', 'error', { fio_id: p.fio_id, booking_id: bId, http_status: mr.status })
    } catch (e) {
      await debugLog(sb, 'confirmation_mail_failed', 'error', { fio_id: p.fio_id, booking_id: bId }, (e as Error).message)
    }
  }

  // ── In-app zpráva (parita se sendBookingMessage ve Velíně) ──
  try {
    const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'Europe/Prague' })
    const newStatus = String(booking.start_date || '').slice(0, 10) <= today ? 'active' : 'reserved'
    const fmtCs = (s: unknown) => s ? new Date(String(s)).toLocaleDateString('cs-CZ') : ''
    // gear: text v jazyce zákazníka (gear-msg.ts, 8 jazyků); motorka beze změny
    const msg = kind === 'gear'
      ? await gearPaidMessageFor(sb, bId, booking.start_date, booking.end_date)
      : newStatus === 'active'
      ? `Motorka ${moto?.model || ''} byla vydána. Přejeme příjemnou jízdu! V případě problému nás kontaktujte nebo použijte SOS tlačítko.`
      : `Vaše rezervace motorky ${moto?.model || ''} (${fmtCs(booking.start_date)} – ${fmtCs(booking.end_date)}) byla potvrzena. Smlouvu a fakturu najdete v sekci Dokumenty.`
    const userId = String(booking.user_id || '')
    if (userId) {
      let { data: thread } = await sb.from('message_threads').select('id').eq('customer_id', userId).limit(1).maybeSingle()
      if (!thread) {
        const { data: nt } = await sb.from('message_threads')
          .insert({ customer_id: userId, subject: 'Rezervace', channel: 'app' }).select('id').maybeSingle()
        thread = nt
      }
      if (thread) {
        await sb.from('messages').insert({ thread_id: (thread as { id: string }).id, direction: 'admin', sender_name: 'MotoGo', content: msg })
        await sb.from('message_threads').update({ last_message_at: new Date().toISOString() }).eq('id', (thread as { id: string }).id)
      }
    }
  } catch { /* best-effort */ }

  // ── Audit (správné sloupce admin_audit_log — new_data, žádný `details`) ──
  await audit(sb, 'booking_payment_confirmed_fio', 'booking', bId,
    { fio_id: p.fio_id, amount: p.amount, vs, paid_date: p.tx_date, method: 'bank_transfer' })
}

/** Doplatek za úpravu zaplacené rezervace zadaný ve Velínu (bookings.mod_surcharge_due / _vs). */
export async function handleSurcharge(ctx: Ctx, p: Tx, sur: Row, o: PairOpts): Promise<Outcome> {
  const { sb, caps, env } = ctx
  const surId = String(sur.id)
  const bn = '#' + short(surId)
  const due = Number(sur.mod_surcharge_due) || 0
  const base = { bookingId: surId, targetType: 'surcharge' as const, expected: due }
  const vs = o.vs || String(sur.mod_surcharge_vs || '')

  if (due <= 0) {
    if (caps.state && (await confirmedByOther(ctx, p, 'surcharge', surId, 'confirmed_surcharge', vs)) != null) {
      await notifyReview(env, p, 'duplicitní platba doplatku', `Doplatek rezervace <strong>${bn}</strong> už je zaplacený. Tato platba je navíc — vraťte ji zákazníkovi převodem.`)
      return { ...base, status: 'needs_review', reason: 'duplicate', note: 'duplicitní platba — doplatek už je zaplacený, vraťte' }
    }
    return { ...base, status: 'already_paid', note: 'doplatek už potvrzen' }
  }
  // Oprava i5 (2026-11-07, verify:refunds): doplatek úpravy dorazil až po stornu → nepotvrzovat (confirm_booking_surcharge
  // stav rezervace nekontroluje a storno mod_surcharge_due nemaže — obsluha dřív dostala „Doplatek potvrzen … Není
  // potřeba nic dělat“ a peníze zůstaly); kartový doplatek zrušené rezervace se vrací sám (D4) — tady obsluha.
  if (String(sur.status || '') === 'cancelled') {
    await notifyUnmatched(env, p, `Doplatek ${fmtAmount(p.amount)} Kč dorazil k ZRUŠENÉ rezervaci ${bn} — nepotvrdil se. Vraťte ho převodem a vystavte dobropis (Velín → Finance → Dobropisy).`)
    return { ...base, status: 'needs_review', reason: caps.state ? 'target_closed' : null, note: 'doplatek ke zrušené rezervaci' }
  }
  const part = await priorPartial(ctx, p, 'surcharge', surId)
  const received = p.amount + part.sum
  if (received + 0.01 < due && !(caps.state && o.accept)) {
    if (caps.state) await notifyUnderpaid(env, p, 'doplatku rezervace ' + bn, due, received)
    else await notifyMismatch(env, p, surId, due, 'doplatek za úpravu rezervace')
    return { ...base, status: 'amount_mismatch', reason: 'underpaid',
      note: part.ids.length ? `přišlo celkem ${fmtAmount(received)}, doplatek ${fmtAmount(due)} Kč` : `přišlo ${fmtAmount(p.amount)}, doplatek ${fmtAmount(due)} Kč` }
  }
  const { data: cs, error: csErr } = await sb.rpc('confirm_booking_surcharge', {
    p_booking_id: surId, p_method: 'bank_transfer', p_vs: vs,
    p_paid_date: p.tx_date, p_transaction_ref: 'FIO ' + p.fio_id,
  })
  if (csErr || (cs as { success?: boolean } | null)?.success === false) {
    const msg = csErr?.message || (cs as { error?: string } | null)?.error || 'rpc_failed'
    await debugLog(sb, 'confirm_surcharge_failed', 'error', { fio_id: p.fio_id, booking_id: surId }, msg)
    if (caps.state) throw new RetryError('confirm_booking_surcharge: ' + msg, surId)
    return { ...base, status: 'error', note: 'confirm_booking_surcharge: ' + msg }
  }
  const overpay = received > due + 0.01
  const under = received + 0.01 < due
  await debugLog(sb, 'surcharge_confirmed', 'ok', { fio_id: p.fio_id, booking_id: surId, amount: p.amount, vs })
  await notifyConfirmed(env, p, surId, due, true, overpay)
  return { ...base, status: 'confirmed_surcharge', absorbed: part.ids,
    reason: overpay ? 'overpaid' : under ? 'accepted_lower' : o.manual ? 'manual' : null,
    followup: overpay ? 'overpaid' : null,
    note: overpay ? `přeplatek: přišlo ${fmtAmount(received)}, doplatek ${fmtAmount(due)} Kč`
      : under ? `obsluha přijala nižší částku: ${fmtAmount(received)} z ${fmtAmount(due)} Kč` : null }
}
