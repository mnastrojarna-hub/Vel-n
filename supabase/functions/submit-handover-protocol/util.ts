// Pomocné funkce submit-handover-protocol: odpovědi, datum/čas v Praze,
// kontrola podpisu (PNG data-URL) a uložení dokumentu do bucketu `documents`.
// Tok requestu je v index.ts.

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

export const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

export function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })
}
export function fail(error: string, status: number, extra: Record<string, unknown> = {}) {
  return json({ success: false, error, ...extra }, status)
}

export const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

// ── Podpis ───────────────────────────────────────────────────────────────────
// Podpis = PNG data-URL. Limit se měří jako DEKÓDOVANÉ bajty PNG STEJNÝM vzorcem
// jako kiosk (ui/signature.js: floor((délka − pozice čárky − 1) · 3/4),
// handover_submit.py SIGNATURE_MAX_BYTES) — jednotka pustí jen podpis ≤ 150 kB
// a edge ho pak NESMÍ odmítnout (413 je pro kiosk trvalá chyba → podpis by
// skončil ve failed[] a kóje se přitom už otevřela). Appka má jen bezpečnostní
// strop (data-URL se ukládá do filled_data._signed_html).
export const SIG_MAX_KIOSK = 150 * 1024
export const SIG_MAX_APP = 2 * 1024 * 1024
export const SIG_RE = /^data:image\/(png|jpeg|jpg|webp);base64,[A-Za-z0-9+/=]+$/

/** Dekódovaná velikost obrázku v data-URL (bajty), bez odečtu paddingu — jako kiosk. */
export function signatureBytes(sig: string): number {
  const idx = sig.indexOf(',')
  return idx < 0 ? sig.length : Math.floor((sig.length - idx - 1) * 3 / 4)
}

// ── Datum/čas ────────────────────────────────────────────────────────────────
export function fmtDate(d: string | null): string {
  if (!d) return ''
  try { return new Date(d).toLocaleDateString('cs-CZ', { timeZone: 'Europe/Prague' }) } catch { return d }
}
/** Kalendářní den v Praze (YYYY-MM-DD) — porovnání „je už den převzetí?“. */
export function pragueDay(d: Date): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Prague', year: 'numeric', month: '2-digit', day: '2-digit' }).format(d)
}
/** signed_at z kiosku (podpis mohl čekat ve frontě); mimo rozumné okno → teď. */
export function parseSignedAt(raw: unknown, now: Date): Date {
  const d = typeof raw === 'string' ? new Date(raw) : null
  if (!d || Number.isNaN(d.getTime())) return now
  const diff = now.getTime() - d.getTime()
  return diff < -5 * 60_000 || diff > 30 * 86_400_000 ? now : d
}

// ── Dokument v bucketu `documents` ───────────────────────────────────────────
// deno-lint-ignore no-explicit-any
type Admin = any

/** PDF přes render-pdf do bucketu `documents`; když se nepovede, uloží HTML. Vrací cestu. */
export async function storeDocument(admin: Admin, bookingId: string, docId: string, html: string): Promise<string> {
  let pdfPath = `generated/${bookingId}/handover-${docId}.pdf`
  try {
    const rp = await fetch(`${SUPABASE_URL}/functions/v1/render-pdf`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE_KEY}` },
      body: JSON.stringify({ html }),
    })
    if (rp.ok && rp.headers.get('content-type')?.includes('application/pdf')) {
      const bytes = new Uint8Array(await rp.arrayBuffer())
      const up = await admin.storage.from('documents').upload(pdfPath, bytes, { upsert: true, contentType: 'application/pdf' })
      if (!up.error) return pdfPath
    }
  } catch (_) { /* fallback níže */ }
  pdfPath = `generated/${bookingId}/handover-${docId}.html`
  const up = await admin.storage.from('documents').upload(pdfPath, new Blob([html], { type: 'text/html' }), { upsert: true, contentType: 'text/html' })
  if (up.error) throw new Error(`storage: ${up.error.message}`)
  return pdfPath
}

/** Úklid souboru, ke kterému nevznikl řádek generated_documents (sirotek); best-effort. */
export async function removeDocument(admin: Admin, path: string): Promise<void> {
  if (!path) return
  try { await admin.storage.from('documents').remove([path]) } catch (_) { /* best-effort */ }
}
