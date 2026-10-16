// ===== _shared/extension-apply-rounding.ts =====
// D1 (2026-10-16): dorovnání na minimální platbu kartou zapsané SAMOSTATNÝM zápisem —
// jen když změnu zapsal klient bez dorovnání (web po návratu ze Stripe se starší verzí
// skriptu, výměna / výbava) nebo když SQL 20261016p4 ještě není nasazené. Běžně jde
// dorovnání do TÉHOŽ zápisu jako změna (split_booking_moto_swap rev.12,
// apply_paid_gear_change rev.2, extension-apply-columns).
// Oprava po kontrole: druhý zápis do 5 min po změně spadl do deduplikace mailu
// trg_send_booking_modified_email → rozdílový DP vznikl jen na doplatek (např. 3 Kč),
// karta zaplatila 15 Kč a konečná faktura ukázala 12 Kč „k doplacení". Proto:
//  • záznam v historii nese price_diff = r a card_rounding = r (DP z něj pozná, že jde
//    o dorovnání — řádek „Dorovnání na minimální platbu kartou"),
//  • když zápis trigger mailu nepustil dál (deduplikace, stav, nastavení), DP na
//    dorovnání vystaví generate-invoice přímo (bez mailu) → doklady dají dohromady
//    zaplacenou částku. Pustil-li ho (http_post_queued ve stejné transakci), DP vystaví
//    mail sám — druhé volání by se s ním mohlo minout a vystavit DP dvakrát.
import type { ApplyArgs, ApplyResult, Sb } from './extension-apply-types.ts'
import { logDebug, round2 } from './extension-apply-types.ts'

/** Dorovnání (r) do ceny a card_rounding rezervace `targetId` + záznam s payment_ref v její
 *  historii (deduplikace opakování) — u placené výbavy / výměny, kterou provedl klient bez
 *  dorovnání. null = hotovo (nebo už dřív), jinak výsledek k vrácení (retry). */
export async function roundingFixup(sb: Sb, targetId: string, r: number, args: ApplyArgs, hash: string | null): Promise<ApplyResult | null> {
  const bookingId = targetId
  for (let pass = 0; pass < 2; pass++) {
    const { data: cur, error } = await sb.from('bookings').select('*').eq('id', bookingId).maybeSingle()
    if (error || !cur) return { state: 'retry', code: 'read_failed', detail: error?.message }
    const hist = Array.isArray(cur.modification_history) ? [...(cur.modification_history as Array<Record<string, unknown> | null>)] : []
    if (args.payRef && hist.some((h) => !!h && h.payment_ref === args.payRef)) return null
    if (!('card_rounding' in cur)) {
      if (args.paidCzk != null && args.paidCzk > 0 && Math.abs(r) < 1) return null
      return { state: 'retry', code: 'rounding_unavailable' }
    }
    // price_diff = změna ceny TÍMTO zápisem (dorovnání); zaplaceno celkem → `paid`.
    hist.push({ at: new Date().toISOString(), type: 'card_rounding', source: 'stripe_webhook', card_rounding: r, price_diff: r,
      ...(args.paidCzk != null ? { paid: round2(args.paidCzk) } : {}), ...(args.payRef ? { payment_ref: args.payRef } : {}),
      ...(hash ? { chg_hash: hash } : {}) })
    let q = sb.from('bookings').update({ total_price: round2(Number(cur.total_price || 0) + r),
      card_rounding: round2(Number(cur.card_rounding || 0) + r), modification_history: hist }).eq('id', bookingId)
    if (cur.updated_at) q = q.eq('updated_at', cur.updated_at)
    const { data: upd, error: uErr } = await q.select('id, updated_at')
    if (uErr) return { state: 'retry', code: 'apply_failed', detail: uErr.message }
    if (Array.isArray(upd) && upd.length === 1) {
      await issueRoundingDoc(sb, bookingId, r, (upd[0] as { updated_at?: string }).updated_at ?? null)
      return null
    }
  }
  return { state: 'retry', code: 'concurrent_update' }
}

/** DP na samostatně zapsané dorovnání (r ≥ 1 Kč — dorovnání na 15 Kč; zaokrouhlení
 *  pod 1 Kč ani odpuštění doklad nemají), pokud ho nevystaví mail o úpravě.
 *  `updatedAt` = updated_at zápisu (now() transakce = created_at záznamů triggeru). */
export async function issueRoundingDoc(sb: Sb, bookingId: string, r: number, updatedAt: string | null,
  fetchFn: typeof fetch = fetch, env: { url?: string; key?: string } = {}): Promise<'mail' | 'issued' | 'skipped' | 'failed'> {
  if (!(r >= 1)) return 'skipped'
  try {
    if (updatedAt) {
      const t0 = Date.parse(updatedAt)
      const { data } = await sb.from('debug_log').select('action, created_at').eq('source', 'trg_booking_modified_email')
        .eq('request_data->>booking_id', bookingId).gte('created_at', updatedAt).order('created_at', { ascending: true }).limit(20)
      const same = (data || []).filter((d: Record<string, unknown>) => Date.parse(String(d.created_at || '')) === t0)
      if (same.some((d: Record<string, unknown>) => d.action === 'http_post_queued' || d.action === 'deferred_surcharge_pending')) return 'mail'
    }
  } catch { /* nezjištěno → vystavit (generate-invoice stejnou částku do 15 min deduplikuje) */ }
  const url = env.url ?? Deno.env.get('SUPABASE_URL') ?? ''
  const key = env.key ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  if (!url || !key) {
    await logDebug(sb, 'rounding_doc_skipped', 'error', { booking_id: bookingId, card_rounding: r }, 'SUPABASE_URL / service key missing')
    return 'failed'
  }
  try {
    const res = await fetchFn(`${url}/functions/v1/generate-invoice`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${key}`, 'apikey': key },
      body: JSON.stringify({ type: 'payment_receipt', booking_id: bookingId, source: 'edit', price_difference: r, send_email: false }),
    })
    const ok = res.ok
    await logDebug(sb, ok ? 'rounding_doc_issued' : 'rounding_doc_failed', ok ? 'ok' : 'error', { booking_id: bookingId, card_rounding: r, status: res.status })
    return ok ? 'issued' : 'failed'
  } catch (e) {
    await logDebug(sb, 'rounding_doc_failed', 'error', { booking_id: bookingId, card_rounding: r }, (e as Error).message)
    return 'failed'
  }
}
