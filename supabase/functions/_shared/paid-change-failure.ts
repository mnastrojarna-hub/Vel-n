// ===== _shared/paid-change-failure.ts =====
// Zaplacená změna rezervace, kterou TRVALE nejde zapsat (motorku mezitím obsadil
// někdo jiný, rezervace skončila / byla zrušená, den výměny uplynul…) — D6,
// rozhodnutí 2026-10-16 (výchozí odpověď na otázku Q4): doplatek se zákazníkovi
// AUTOMATICKY vrátí (process-refund, dobropis + e-mail zákazníkovi) a obsluha
// dostane upozornění (debug_log `paid_change_failed` + interní e-mail).
// Jen JEDNOU na platbu (payRef) — první zapsaný řádek debug_log vyhrává, souběžný
// webhook / complete_extension skončí jako 'duplicate'.
// `review` = nejednoznačný stav (stará platba mimo lhůtu / z doby před nasazením,
// rezervace už jezdí na nové motorce bez záznamu této platby) → žádná automatická
// vratka, obsluha zkontroluje, jestli je změna zapsaná, a případně vrátí ručně.
import type { Sb } from './extension-apply-types.ts'

export type FailureMode = 'auto' | 'staff' | 'none' | 'duplicate'

const OPS_EMAIL = 'info@motogo24.cz'

export async function handlePaidChangeFailure(sb: Sb, a: {
  bookingId: string; payRef: string; paidCzk: number; code: string; reason: string; via: string; autoRefund?: boolean; review?: boolean
}): Promise<FailureMode> {
  const url = Deno.env.get('SUPABASE_URL') ?? ''
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const reqData = { booking_id: a.bookingId, payment_ref: a.payRef, paid_czk: a.paidCzk, code: a.code, reason: a.reason, via: a.via }

  // 1) Zámek „jednou na platbu": vlož svůj řádek a ověř, že je PRVNÍ.
  let myId: string | null = null
  try {
    const { data } = await sb.from('debug_log').insert({
      source: 'paid-change', action: 'paid_change_failed', component: 'stripe', status: 'error',
      error_message: `Zaplacenou změnu rezervace nešlo zapsat (${a.reason}).`, request_data: reqData,
    }).select('id').single()
    myId = data?.id ?? null
    const { data: first } = await sb.from('debug_log').select('id, response_data')
      .eq('action', 'paid_change_failed').eq('request_data->>payment_ref', a.payRef)
      .order('created_at', { ascending: true }).order('id', { ascending: true }).limit(1)
    if (first?.length && myId && first[0].id !== myId) {
      try { await sb.from('debug_log').delete().eq('id', myId) } catch { /* ignore */ }
      const prev = (first[0].response_data || {}) as { refund?: FailureMode }
      return prev.refund || 'duplicate'
    }
  } catch { /* bez zámku pokračuj — process-refund má vlastní idempotenci */ }

  // 2) Vrácení doplatku (process-refund: Stripe refund z PaymentIntentu rezervace + dobropis).
  let mode: FailureMode = 'none'
  if (a.paidCzk > 0) {
    mode = 'staff'
    if (a.autoRefund !== false && !a.review) {
      // process-refund vrací z bookings.stripe_payment_intent_id — ať je to TATO platba
      // (mezitím mohl vzniknout novější, nezaplacený PaymentIntent dalšího pokusu).
      if (a.payRef.startsWith('pi_')) {
        try { await sb.from('bookings').update({ stripe_payment_intent_id: a.payRef }).eq('id', a.bookingId) } catch { /* ignore */ }
      }
      try {
        const resp = await fetch(`${url}/functions/v1/process-refund`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}`, apikey: key },
          body: JSON.stringify({ booking_id: a.bookingId, amount: a.paidCzk, reason: 'paid_change_failed', source: 'edit' }),
        })
        const j = await resp.json().catch(() => ({})) as { success?: boolean }
        if (resp.ok && j.success !== false) mode = 'auto'
      } catch { /* zůstává 'staff' */ }
    }
  }
  if (myId) {
    try { await sb.from('debug_log').update({ response_data: { refund: mode } }).eq('id', myId) } catch { /* ignore */ }
  }

  // 3) Interní upozornění obsluze (ne zákazníkovi).
  try {
    const num = a.bookingId.slice(-8).toUpperCase()
    const what = a.review && mode === 'staff'
      ? `Platbu ${a.paidCzk} Kč nešlo zapsat automaticky (${a.reason}). Zkontrolujte prosím, jestli je změna v rezervaci zapsaná; pokud ne, doplatek vraťte ručně (Velín → rezervace → vratka).`
      : mode === 'auto' ? `Doplatek ${a.paidCzk} Kč byl zákazníkovi automaticky vrácen (dobropis).`
      : mode === 'staff' ? `Doplatek ${a.paidCzk} Kč se NEPODAŘILO vrátit automaticky — vraťte ho prosím ručně (Velín → rezervace → vratka).`
      : 'Nic se nestrhlo (doplatek do 1 Kč se neúčtuje).'
    await fetch(`${url}/functions/v1/send-email`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}`, apikey: key },
      body: JSON.stringify({
        to: OPS_EMAIL,
        subject: `⚠️ Zaplacenou úpravu rezervace #${num} nešlo zapsat (${a.reason})`,
        raw_html: `<h2 style="margin:0 0 8px;font-size:18px">Zaplacená úprava rezervace #${num} se nezapsala</h2>`
          + `<p style="margin:0 0 8px">Důvod: <strong>${a.reason}</strong> (${a.via}). Platba ${a.payRef}.</p>`
          + `<p style="margin:0 0 8px">${what}</p>`
          + `<p style="margin:0;color:#6b7280;font-size:12px">${a.review ? 'Automaticky se nic nezměnilo.' : 'Rezervace zůstala v původním stavu.'} Detail: Velín → Debug log, akce paid_change_failed.</p>`,
      }),
    })
  } catch { /* ignore */ }
  return mode
}
