// ===== fio-sync/confirm-change.ts =====
// DOPLATEK ÚPRAVY REZERVACE z webu zaplacený převodem (bank_payment_requests, kind 'booking_change').
// Změna se zapisuje AŽ PO připsání peněz — stejnou rutinou jako po platbě kartou
// (_shared/extension-apply.ts → applyPaidExtension; payload chg/srv je tentýž, jaký jde u karty do
// Stripe metadat). Rozhodnutí majitele 2026-11-27: nový termín se mezitím NEblokuje; když změnu už
// nejde zapsat (termín / motorku mezitím obsadil někdo jiný, rezervace skončila…), rezervace zůstane
// beze změny a peníze vrací OBSLUHA ručně (žádná automatická vratka) — _shared/paid-change-failure.ts
// zapíše záznam a pošle obsluze e-mail. Platba po lhůtě 60 min nebo po zrušení požadavku jde obsluze
// („Přesto provést“ = ruční spárování s požadavkem → tatáž rutina, která znovu ověří proveditelnost).
import { applyPaidExtension } from '../_shared/extension-apply.ts'
import type { ApplyResult } from '../_shared/extension-apply-types.ts'
import { changeKindOf, handlePaidChangeFailure } from '../_shared/paid-change-failure.ts'
import { markPaidAfterChange } from '../_shared/paid-change-guard.ts'
import { audit, type Ctx, fmtAmount, type Outcome, RetryError, type Row, short, type Tx } from './util.ts'
import { notifyDone, notifyReview, notifyUnderpaid } from './ops-mail.ts'
import { priorPartial } from './partials.ts'
import type { PairOpts } from './confirm-booking.ts'

async function setRequest(ctx: Ctx, id: string, patch: Row, from: string[]) {
  try { await ctx.sb.from('bank_payment_requests').update(patch).eq('id', id).in('status', from) } catch { /* ignore */ }
}

export async function handleChange(ctx: Ctx, p: Tx, r: Row, o: PairOpts): Promise<Outcome> {
  const { sb, env } = ctx
  const rId = String(r.id)
  const bId = String(r.booking_id)
  const bn = '#' + short(bId)
  const expected = Number(r.amount) || 0
  const base = { bookingId: bId, requestId: rId, targetType: 'request' as const, expected }
  const st = String(r.status || '')
  const now = env.now ? env.now() : Date.now()
  const lapsed = st === 'expired' || (st === 'pending' && Date.parse(String(r.expires_at || '')) <= now)

  if (st === 'paid') {
    // Opakované zpracování téhož pohybu po pádu (požadavek už je označený) = hotovo.
    if (Number(r.fio_id) === Number(p.fio_id)) return { ...base, status: 'confirmed_change', note: 'úprava zapsána' }
    await notifyReview(env, p, 'duplicitní platba doplatku', `Doplatek za úpravu rezervace <strong>${bn}</strong> už je zaplacený a úprava zapsaná. Tato platba je navíc — vraťte ji zákazníkovi převodem.`)
    return { ...base, status: 'needs_review', reason: 'duplicate', note: 'duplicitní platba — úprava už je zaplacená, vraťte' }
  }
  if (!o.manual) {
    if (st === 'failed') {
      await notifyReview(env, p, 'další platba k úpravě, kterou nešlo provést', `K úpravě rezervace <strong>${bn}</strong>, kterou už nešlo zapsat, přišla další platba. Vraťte ji zákazníkovi převodem.`)
      return { ...base, status: 'needs_review', reason: 'change_failed', note: 'úpravu nešlo provést — vraťte platbu' }
    }
    if (st === 'cancelled') {
      await notifyReview(env, p, 'doplatek ke zrušené úpravě', `Zákazník úpravu rezervace <strong>${bn}</strong> mezitím zrušil (nebo zvolil jinou), ale doplatek dorazil. Úprava se NEprovedla. Vraťte platbu, nebo ji spárujte s požadavkem („Přesto provést“) — proveditelnost se ověří znovu.`)
      return { ...base, status: 'needs_review', reason: 'request_cancelled', note: 'doplatek ke zrušenému požadavku — provést, nebo vrátit' }
    }
    if (lapsed) {
      await notifyReview(env, p, 'doplatek úpravy po lhůtě', `Doplatek za úpravu rezervace <strong>${bn}</strong> dorazil až po lhůtě 60 minut. Úprava se NEprovedla. Spárujte platbu s požadavkem („Přesto provést“) — proveditelnost se ověří znovu —, nebo ji vraťte.`)
      return { ...base, status: 'needs_review', reason: 'request_expired', note: 'doplatek po lhůtě — provést, nebo vrátit' }
    }
  }

  const part = await priorPartial(ctx, p, 'request', rId)
  const received = p.amount + part.sum
  if (received + 0.01 < expected && !o.accept) {
    await notifyUnderpaid(env, p, 'doplatku úpravy rezervace ' + bn, expected, received)
    return { ...base, status: 'amount_mismatch', reason: 'underpaid', note: `přišlo ${part.ids.length ? 'celkem ' : ''}${fmtAmount(received)}, doplatek ${fmtAmount(expected)} Kč` }
  }

  // ── Zápis zaplacené změny — stejná rutina jako po kartě ──
  const payRef = 'FIO ' + p.fio_id
  let res: ApplyResult
  try {
    res = await applyPaidExtension(sb, {
      bookingId: bId, chg: String(r.chg || ''), srv: (r.srv as string | null) ?? null, paidCzk: expected,
      payRef, rounding: 0, since: (r.created_at as string | null) ?? null, via: 'webhook',
    })
  } catch (e) {
    res = { state: 'retry', code: 'apply_exception', detail: (e as Error).message }
  }
  if (res.state === 'retry') throw new RetryError(`úprava rezervace: ${res.code}${res.detail ? ' — ' + res.detail : ''}`, bId, rId)

  const paidAt = new Date(now).toISOString()
  if (res.state === 'applied' || res.state === 'already_applied') {
    await markPaidAfterChange(sb, bId, 'bank_transfer')
    await setRequest(ctx, rId, { status: 'paid', paid_at: paidAt, fio_id: p.fio_id,
      result: { state: res.state, new_booking_id: res.newBookingId ?? null, total_price: res.totalPrice ?? null } },
      ['pending', 'expired', 'cancelled', 'failed'])
    await audit(sb, 'booking_change_paid_fio', 'booking', bId,
      { fio_id: p.fio_id, amount: p.amount, vs: o.vs, request_id: rId, state: res.state, paid_date: p.tx_date })
    const overpay = received > expected + 0.01
    const under = received + 0.01 < expected
    await notifyDone(env, p, `Doplatek úpravy rezervace ${bn} zaplacen — úprava zapsána`,
      `Zákazník zaplatil převodem doplatek za úpravu rezervace <strong>${bn}</strong> a úprava se zapsala stejně jako po platbě kartou (zákazníkovi odchází e-mail o úpravě s dokladem).`,
      expected, overpay)
    return { ...base, status: 'confirmed_change', absorbed: part.ids,
      reason: overpay ? 'overpaid' : under ? 'accepted_lower' : o.manual ? 'manual' : null,
      followup: overpay ? 'overpaid' : null,
      note: overpay ? `úprava zapsána; přeplatek: přišlo ${fmtAmount(received)}, doplatek ${fmtAmount(expected)} Kč`
        : under ? `úprava zapsána; obsluha přijala nižší částku ${fmtAmount(received)} z ${fmtAmount(expected)} Kč`
        : o.manual ? 'úprava zapsána (spárováno ručně)' : 'úprava zapsána' }
  }

  if (res.state === 'duplicate') {
    await setRequest(ctx, rId, { status: 'failed', fio_id: p.fio_id, result: { state: 'duplicate', reason: 'duplicate', other: res.otherRef } }, ['pending', 'expired', 'cancelled'])
    await notifyReview(env, p, 'úprava už je zaplacená jinou platbou', `Tutéž úpravu rezervace <strong>${bn}</strong> už zapsala jiná platba (${res.otherRef}). Tento převod je navíc — vraťte ho zákazníkovi.`)
    return { ...base, status: 'needs_review', reason: 'duplicate', note: 'úpravu už zapsala jiná platba — vraťte' }
  }

  // failed / no_payload → rezervace beze změny, peníze vrací obsluha (záznam + e-mail: paid-change-failure)
  const code = res.state === 'failed' ? res.code : 'change_failed'
  const reason = res.state === 'failed' ? res.reason : 'no_payload'
  await setRequest(ctx, rId, { status: 'failed', fio_id: p.fio_id, result: { state: 'failed', code, reason } }, ['pending', 'expired', 'cancelled', 'failed'])
  await handlePaidChangeFailure(sb, {
    bookingId: bId, payRef, paidCzk: received, code, reason, via: 'fio-sync', autoRefund: false,
    review: res.state === 'failed' && res.manual === true, kind: changeKindOf(String(r.chg || '')),
    bank: { account: p.counter_account ? `${p.counter_account}/${p.counter_bank || ''}` : null },
  })
  return { ...base, status: 'needs_review', reason: 'change_failed', note: `úpravu nešlo provést (${reason}) — rezervace beze změny, vraťte doplatek` }
}
