// ===== send-booking-email/modified-refund.ts =====
// Oprava i3 (2026-11-07, verify:ux) — mail úpravy rezervace s vratkou (booking_modified, price_difference < 0) dřív
// VŽDY tvrdil „vrácení X formou dobropisu, který najdete v příloze, refund jde zpět na kartu“ — i když dobropis
// nevznikl (vratka appky se k serveru nedostala, process-refund odpověděl refund_needs_staff / vrátil jen část).
// Retry v attach smyčce (booking_modified_retry) je jen recovery a vratku nevytvoří; obsluha se dozvěděla jen
// z debug_log, který Velín nezobrazuje. Teď: nejdřív se ověří, že živý dobropis na |price_difference| existuje
// (stejná čekací / recovery smyčka jako u přílohy); když ne → text „vratku dokončuje obsluha“ (bez „v příloze“ /
// „na kartu“) + mail obsluze (1× za 24 h na rezervaci a částku) — slib appky pdRefundManual tím má krytí.
// deno-lint-ignore no-explicit-any
type Sb = any

/** Dobropis k vratce úpravy: živý, nejvýš WINDOW starý, na částku ≥ |price_difference| − 1 Kč.
 *  Oprava i4 (2026-11-07, S6): dřív kryl i dobropis DŘÍVĚJŠÍ úpravy (zkrácení o 500, za 30 min o 300 se spadlou vratkou →
 *  mail tvrdil dobropis i vratku na kartu, 300 Kč se nevrátilo nikdy). Teď jen dobropis vzniklý po zápisu mailované
 *  úpravy (`sinceMs` = nejnovější modification_history[].at s časovou zónou, −SLACK), bez něj jen dobropis na tutéž
 *  částku (±1 Kč) nebo čerstvý (≤ FRESH) větší. */
const WINDOW_MS = 6 * 3600_000
const TOL_CZK = 1
const SLACK_MS = 2 * 60_000
const FRESH_MS = 15 * 60_000
export const DEFERRED_MARK = '<!--mg-mod-refund-deferred-->'

/** Okamžik nejnovější úpravy z modification_history (ms) — jen `at` s časovou zónou (Z / ±hh:mm; appka píše místní čas
 *  bez zóny → neznámý). null = nelze určit. */
export function newestModificationMs(history: unknown): number | null {
  if (!Array.isArray(history)) return null
  let best: number | null = null
  for (const e of history) {
    const at = e && typeof e === 'object' ? (e as Record<string, unknown>).at : null
    if (typeof at !== 'string' || !/(Z|[+-]\d{2}:?\d{2})$/.test(at.trim())) continue
    const ms = Date.parse(at)
    if (Number.isFinite(ms) && (best == null || ms > best)) best = ms
  }
  return best
}

/** Kryje dobropis `c` vratku úpravy `refundCzk`? (viz výše) */
export function coversModification(c: { total: unknown; created_at?: unknown }, refundCzk: number, sinceMs: number | null, nowMs = Date.now()): boolean {
  const amt = Math.abs(Number(c.total) || 0)
  if (amt + TOL_CZK < refundCzk) return false
  const at = Date.parse(String(c.created_at ?? ''))
  if (sinceMs != null) return Number.isFinite(at) && at >= sinceMs - SLACK_MS
  return amt <= refundCzk + TOL_CZK || (Number.isFinite(at) && nowMs - at <= FRESH_MS)
}

export async function modifiedRefundCovered(sb: Sb, bookingId: string, refundCzk: number, o: {
  recover?: () => Promise<void>; tries?: number; waitMs?: number
  /** i4: okamžik mailované úpravy (newestModificationMs); null / chybí = neznámý */
  sinceMs?: number | null
} = {}): Promise<boolean> {
  const tries = o.tries ?? 3
  for (let i = 0; i < tries; i++) {
    try {
      const { data } = await sb.from('invoices').select('id, total, created_at')
        .eq('booking_id', bookingId).eq('type', 'credit_note').neq('status', 'cancelled')
        .gte('created_at', new Date(Date.now() - WINDOW_MS).toISOString())
      if ((data || []).some((c: { total: unknown; created_at?: unknown }) => coversModification(c, refundCzk, o.sinceMs ?? null))) return true
    } catch { /* další pokus */ }
    if (i < tries - 1) {
      try { await o.recover?.() } catch { /* ignore */ }
      await new Promise((r) => setTimeout(r, o.waitMs ?? 2500))
    }
  }
  return false
}

const NOTE: Record<string, (pd: string) => string> = {
  cs: (pd) => `K úpravě se vztahuje <strong>vrácení ${pd}</strong> — vratku dokončuje obsluha, nemusíte nic dělat.`,
  en: (pd) => `A refund of <strong>${pd}</strong> applies — our staff is completing it, you don't need to do anything.`,
  de: (pd) => `Eine Rückerstattung von <strong>${pd}</strong> fällt an — unser Team schließt sie ab, Sie müssen nichts tun.`,
  nl: (pd) => `Er geldt een terugbetaling van <strong>${pd}</strong> — ons team rondt die af, je hoeft niets te doen.`,
  es: (pd) => `Se aplica un reembolso de <strong>${pd}</strong> — nuestro equipo lo está completando, no tienes que hacer nada.`,
  fr: (pd) => `Un remboursement de <strong>${pd}</strong> s'applique — notre équipe le finalise, vous n'avez rien à faire.`,
  pl: (pd) => `Przysługuje zwrot <strong>${pd}</strong> — nasza obsługa go finalizuje, nie musisz nic robić.`,
  uk: (pd) => `Передбачено повернення <strong>${pd}</strong> — наша служба його завершує, вам нічого робити не потрібно.`,
}
/** Věta o vratce, kterou dokončuje obsluha (bez „v příloze“ / „na kartu“), se značkou pro detekci. */
export function modifiedRefundDeferredNote(lang: string, priceDifference: string, o: { informal?: boolean } = {}): string {
  if (o.informal && (lang === 'cs' || !(lang in NOTE))) return `${DEFERRED_MARK}K úpravě se vztahuje <strong>vrácení ${priceDifference}</strong> — vratku dokončuje obsluha, nemusíš nic dělat.`
  return DEFERRED_MARK + (NOTE[lang] || NOTE.cs)(priceDifference)
}

/** Mail obsluze: k úpravě s vratkou chybí dobropis (1× za 24 h na rezervaci a částku; dedup přes debug_log). */
export async function modifiedRefundMissingMail(sb: Sb, bookingId: string, refundCzk: number): Promise<void> {
  try {
    const { data: prev } = await sb.from('debug_log').select('id').eq('source', 'send-booking-email')
      .eq('action', 'modified_refund_missing_mail').eq('request_data->>booking_id', bookingId)
      .eq('request_data->>refund_czk', String(refundCzk))
      .gte('created_at', new Date(Date.now() - 24 * 3600_000).toISOString()).limit(1)
    if (prev?.length) return
  } catch { /* bez dedupu */ }
  try {
    await sb.from('debug_log').insert({ source: 'send-booking-email', action: 'modified_refund_missing_mail', status: 'error',
      request_data: { booking_id: bookingId, refund_czk: String(refundCzk) },
      error_message: 'Úprava s vratkou: dobropis / vratka chybí — zákazníkovi řečeno „dokončuje obsluha“.' })
  } catch { /* ignore */ }
  const num = bookingId.slice(-8).toUpperCase()
  const url = Deno.env.get('SUPABASE_URL') ?? '', key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  try {
    await fetch(`${url}/functions/v1/send-email`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}`, apikey: key },
      body: JSON.stringify({ to: 'info@motogo24.cz',
        subject: `⚠️ Úprava #${num} s vratkou ${refundCzk} Kč: vratka / dobropis chybí — zkontrolujte a vraťte`,
        raw_html: `<p>Rezervace <strong>#${num}</strong> (${bookingId}) byla upravena s vratkou <strong>${refundCzk} Kč</strong>, ale k úpravě nevznikl dobropis `
          + '(vratka z aplikace / webu se neprovedla nebo jen zčásti, případně čeká na obsluhu).</p>'
          + '<p>Zákazník dostal mail „vratku dokončuje obsluha“ (aplikace slibuje do 2 pracovních dnů). Zkontrolujte platby; částku vraťte ve Stripe dashboardu '
          + '(platba rezervace → Refund — stav rezervace se pak dorovná sám), dobropis vystavte ve Velíně (Finance → Dobropisy) a pošlete ho zákazníkovi e-mailem.</p>' }),
    })
  } catch { /* ignore */ }
}
