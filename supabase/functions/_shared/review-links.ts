// Odkaz na recenze v e-mailech — VŽDY Google (rozhodnutí majitele 2026-10-15:
// „odkaz na recenze by měl být vždy google“). Jiné recenzní weby (Facebook, Firmy.cz,
// Instagram, Tripadvisor…) se zákazníkům jako „napište recenzi“ neodkazují.
//
// Zdroj pravdy: app_settings.google_review_url — stejný klíč čte appka
// (googleReviewUrlProvider) i DB trigger trg_send_booking_completed_email (payload
// `google_review_url`). Konstanta níže je jen záloha, když hodnota chybí / není Google.
//
// Formulace musí být neutrální (Google zakazuje „review gating“ = žádat o recenzi
// jen spokojené zákazníky) — žádné „pokud jste byli spokojeni…“.

export const GOOGLE_REVIEW_URL_DEFAULT = 'https://g.page/r/CUmeYvk-sNf6EBM/review'

const GOOGLE_HOST_RE = /^https:\/\/(?:[a-z0-9-]+\.)*(?:google\.[a-z]{2,3}(?:\.[a-z]{2})?|g\.page|goo\.gl)(?:[/?#]|$)/i
// Zrušené vlastní krátké názvy (g.page/<jmeno>/review) Google už neobsluhuje — platné jsou jen g.page/r/<id>.
const LEGACY_GPAGE_RE = /^https:\/\/g\.page\/(?!r\/)/i

/** Je to použitelný odkaz na recenze na Googlu? */
export function isGoogleReviewUrl(u: unknown): u is string {
  if (typeof u !== 'string') return false
  const s = u.trim()
  return GOOGLE_HOST_RE.test(s) && !LEGACY_GPAGE_RE.test(s)
}

/** První Google odkaz z kandidátů, jinak výchozí. */
export function pickGoogleReviewUrl(...candidates: unknown[]): string {
  for (const c of candidates) if (isGoogleReviewUrl(c)) return c.trim()
  return GOOGLE_REVIEW_URL_DEFAULT
}

/** Odkaz z payloadu (pokud je Google), jinak z app_settings.google_review_url, jinak výchozí. */
// deno-lint-ignore no-explicit-any
export async function loadGoogleReviewUrl(supabase: any, provided?: unknown): Promise<string> {
  if (isGoogleReviewUrl(provided)) return provided.trim()
  try {
    const { data } = await supabase.from('app_settings').select('value').eq('key', 'google_review_url').maybeSingle()
    const v = data?.value
    const s = typeof v === 'string' ? v : (v && typeof v === 'object' ? (v as { url?: unknown }).url : null)
    if (isGoogleReviewUrl(s)) return s.trim()
  } catch { /* nastavení nesmí shodit odeslání mailu */ }
  return GOOGLE_REVIEW_URL_DEFAULT
}

// ── Úprava těla poděkovacího mailu (DB šablona z Velína i její AI překlad) ──────────
// Odkazy s textem „Google…“ → správný Google odkaz. Odkazy na jiné recenzní weby
// (text Facebook/Instagram/Firmy.cz/Mapy.cz/Tripadvisor/Seznam nebo recenzní URL těchto
// webů) se odstraní i se spojkou mezi odkazy („, “, „ nebo na “, „ or “…), takže
// „recenzi na Google, Facebook nebo Instagram.“ → „recenzi na Google.“ v každém jazyce.
// Ikony „Sledujte nás“ (obrázek bez textu, odkaz na profil) zůstávají. Idempotentní.

const ANCHOR_RE = /<a\b[^>]*>[\s\S]*?<\/a>/gi
const OTHER_REVIEW_TEXT_RE = /^(?:facebook\w*|instagram\w*|firmy(?:\.cz)?|mapy(?:\.cz|\.com)?|tripadvisor\w*|seznam\w*)$/i
const OTHER_REVIEW_HREF_RE = /firmy\.cz|mapy\.(?:cz|com)|tripadvisor\.|sk=reviews|facebook\.com\/[^"']*reviews/i
const GOOGLE_TEXT_RE = /^googl\w*$/i

function anchorText(a: string): string {
  return a.replace(/<[^>]+>/g, '').replace(/&nbsp;/gi, ' ').trim()
}
function anchorHref(a: string): string {
  return (a.match(/\bhref\s*=\s*["']([^"']*)["']/i) || [])[1] || ''
}
function isOtherReviewAnchor(a: string): boolean {
  return OTHER_REVIEW_TEXT_RE.test(anchorText(a)) || OTHER_REVIEW_HREF_RE.test(anchorHref(a))
}
/** Krátká spojka mezi dvěma odkazy (bez tagů a konce věty): „, “ „ nebo na “ „ or “ „ oder auf “ … */
function isConnector(t: string): boolean {
  const s = t.replace(/&nbsp;/gi, ' ')
  return s.length <= 24 && !/[<>.!?:]/.test(s) && /^[\s,;/&+–—-]*(?:[\p{L}]+[\s,]*){0,3}$/u.test(s)
}

const HREF_RE = /\bhref\s*=\s*["'][^"']*["']/i
function setHref(a: string, url: string): string {
  return HREF_RE.test(a) ? a.replace(HREF_RE, `href="${url}"`) : a.replace(/^<a\b/i, `<a href="${url}"`)
}
/** Odkaz na Google recenze: text „Google…“ nebo recenzní URL Googlu (g.page, writereview). */
function isGoogleReviewAnchor(a: string): boolean {
  return GOOGLE_TEXT_RE.test(anchorText(a)) || /writereview|g\.page\//i.test(anchorHref(a))
}

export function googleOnlyReviewLinks(html: string, googleUrl: string): string {
  if (!html) return html
  const url = pickGoogleReviewUrl(googleUrl)
  // Rozložit na [text, odkaz, text, odkaz, …, text] (liché indexy = odkazy).
  const parts: string[] = []
  let last = 0
  for (const m of html.matchAll(ANCHOR_RE)) {
    parts.push(html.slice(last, m.index), m[0])
    last = (m.index ?? 0) + m[0].length
  }
  parts.push(html.slice(last))
  let hasGoogle = false
  for (let i = 1; i < parts.length; i += 2) {
    if (isGoogleReviewAnchor(parts[i])) { parts[i] = setHref(parts[i], url); hasGoogle = true }
  }
  const removed = new Set<number>()
  for (let i = 1; i < parts.length; i += 2) {
    if (!isOtherReviewAnchor(parts[i])) continue
    if (!hasGoogle) {
      // Šablona Google odkaz nemá — první recenzní odkaz se stane odkazem na Google.
      parts[i] = setHref(parts[i], url).replace(/^(<a\b[^>]*>)[\s\S]*(<\/a>)$/i, '$1Google$2')
      hasGoogle = true
      continue
    }
    let p = i - 2
    while (p >= 1 && removed.has(p)) p -= 2
    if (p >= 1 && isConnector(parts.slice(p + 1, i).join(''))) {
      for (let k = p + 1; k < i; k++) parts[k] = ''
    } else if (i + 2 < parts.length && isConnector(parts[i + 1])) {
      parts[i + 1] = ''
    }
    parts[i] = ''
    removed.add(i)
  }
  return parts.join('')
}

// ── Blok „napište nám recenzi“ (expedice e-shopu, konečná faktura e-shopu) ─────────
const REVIEW_BLOCK_LABELS: Record<string, { title: string; body: string; cta: string }> = {
  cs: { title: 'Pomohlo by nám vaše hodnocení', body: 'Budeme rádi, když nám zanecháte upřímnou recenzi na Googlu — pomáháte tím dalším motorkářům.', cta: '⭐ Ohodnotit na Google' },
  en: { title: 'Your review would help us', body: 'We’d be glad if you left us an honest review on Google — it helps fellow riders.', cta: '⭐ Review on Google' },
  de: { title: 'Ihre Bewertung würde uns helfen', body: 'Wir freuen uns über Ihre ehrliche Bewertung auf Google — Sie helfen damit anderen Bikern.', cta: '⭐ Auf Google bewerten' },
  nl: { title: 'Je review helpt ons enorm', body: 'We stellen een eerlijke review op Google erg op prijs — je helpt er andere motorrijders mee.', cta: '⭐ Beoordeel op Google' },
  es: { title: 'Tu reseña nos ayudaría mucho', body: 'Nos encantaría que nos dejaras una reseña sincera en Google — ayudas a otros moteros.', cta: '⭐ Reseña en Google' },
  fr: { title: 'Votre avis nous aiderait', body: 'Nous serions ravis que vous nous laissiez un avis sincère sur Google — vous aidez d’autres motards.', cta: '⭐ Avis sur Google' },
  pl: { title: 'Twoja recenzja by nam pomogła', body: 'Będzie nam miło, jeśli zostawisz nam szczerą recenzję w Google — pomożesz innym motocyklistom.', cta: '⭐ Oceń w Google' },
  uk: { title: 'Ваш відгук нам дуже допоможе', body: 'Будемо раді вашому чесному відгуку в Google — ви допоможете іншим мотоциклістам.', cta: '⭐ Оцінити в Google' },
}

export function googleReviewBlock(lang: string, url?: string): string {
  const l = REVIEW_BLOCK_LABELS[lang] || REVIEW_BLOCK_LABELS.cs
  const href = pickGoogleReviewUrl(url)
  return `<div style="background:#000000;border:2px solid #74FB71;border-radius:8px;padding:24px;margin:24px 0;text-align:center">
  <div style="color:#74FB71;font-size:18px;font-weight:800;margin:0 0 8px">${l.title}</div>
  <div style="color:#ffffff;font-size:13px;margin:0 0 16px">${l.body}</div>
  <a href="${href}" target="_blank" rel="noopener" style="display:inline-block;background:#74FB71;color:#000000;font-size:13px;font-weight:700;text-decoration:none;padding:12px 28px;border-radius:24px">${l.cta}</a>
</div>`
}
