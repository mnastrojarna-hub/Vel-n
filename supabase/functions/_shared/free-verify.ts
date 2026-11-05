// ===== _shared/free-verify.ts =====
// Oprava i2 (2026-11-05): rezervace za 0 Kč přes Stripe Checkout v režimu setup (jen ověření karty) se potvrzovala
// (webhook checkout.session.completed `verify_free_booking` i synchronní fallback process-payment
// `verify_setup_session`) BEZ opětovné kontroly, že cena je stále 0. Session vzniká jen při ceně 0, ale než
// zákazník ověření karty dokončí, může se cena změnit (přecenění ve Velínu, vlastní REST UPDATE zákazníka — RLS
// bookings_user_update) → rezervace s cenou > 0 byla 'paid' a nic se nestrhlo (doklady ≠ stržené).
// Teď se těsně před potvrzením přečte total_price: > 0 → nepotvrdit, záznam + mail obsluze.
// deno-lint-ignore no-explicit-any
type Sb = any

export type FreeVerify = { ok: true; paid: boolean } | { ok: false; code: 'free_mismatch' | 'not_found'; serverTotal: number }

export async function freeVerifyCheck(sb: Sb, a: { bookingId: string; sessionId: string; source: 'webhook-receiver' | 'process-payment' }): Promise<FreeVerify> {
  const { data: bk } = await sb.from('bookings').select('payment_status, total_price').eq('id', a.bookingId).maybeSingle()
  if (!bk) return { ok: false, code: 'not_found', serverTotal: 0 }
  const total = Number(bk.total_price) || 0
  if (total > 0 && bk.payment_status !== 'paid') {
    try {
      await sb.from('debug_log').insert({ source: a.source, action: 'free_verify_price_changed', component: 'free_booking', status: 'error',
        error_message: `Rezervace za 0 Kč: cena se před ověřením karty změnila na ${total} Kč — NEPOTVRZENO (nic se nestrhlo).`,
        request_data: { booking_id: a.bookingId, session_id: a.sessionId, total_price: total } })
    } catch { /* ignore */ }
    try {
      const url = Deno.env.get('SUPABASE_URL') ?? ''
      const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
      const num = a.bookingId.slice(-8).toUpperCase()
      await fetch(`${url}/functions/v1/send-email`, {
        method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}`, apikey: key },
        body: JSON.stringify({ to: 'info@motogo24.cz', subject: `⚠️ Rezervace #${num}: cena se změnila na ${total} Kč před ověřením karty — nepotvrzeno`,
          raw_html: `<p style="margin:0 0 8px">Rezervace <strong>#${num}</strong> (${a.bookingId}) měla cenu 0 Kč a zákazník ověřoval kartu přes Stripe (session ${a.sessionId}), `
            + `ale těsně před potvrzením je její cena <strong>${total} Kč</strong>.</p>`
            + '<p style="margin:0">Rezervace NEBYLA potvrzena a nic se nestrhlo. Zkontrolujte cenu a domluvte se zákazníkem platbu (nebo cenu vraťte na 0 a potvrďte ručně).</p>' }),
      })
    } catch { /* ignore */ }
    return { ok: false, code: 'free_mismatch', serverTotal: total }
  }
  return { ok: true, paid: bk.payment_status === 'paid' }
}
