// Odkaz na recenze = VŽDY Google (majitel 2026-10-15: „odkaz na recenze by měl být vždy google“).
// Zrcadlo supabase/functions/_shared/review-links.ts (edge send-booking-email) pro náhled
// a testovací odeslání poděkovacího mailu ve Velíně — při změně upravit OBA soubory.
// Živý zdroj odkazu: app_settings.google_review_url (čte ho appka i DB trigger mailu);
// konstanta je výchozí hodnota / ukázka pro náhled.

export const GOOGLE_REVIEW_URL_DEFAULT = 'https://g.page/r/CUmeYvk-sNf6EBM/review'

const ANCHOR_RE = /<a\b[^>]*>[\s\S]*?<\/a>/gi
const HREF_RE = /\bhref\s*=\s*["'][^"']*["']/i
const GOOGLE_TEXT_RE = /^googl\w*$/i
const OTHER_REVIEW_TEXT_RE = /^(?:facebook\w*|instagram\w*|firmy(?:\.cz)?|mapy(?:\.cz|\.com)?|tripadvisor\w*|seznam\w*)$/i
const OTHER_REVIEW_HREF_RE = /firmy\.cz|mapy\.(?:cz|com)|tripadvisor\.|sk=reviews|facebook\.com\/[^"']*reviews/i

const anchorText = (a) => a.replace(/<[^>]+>/g, '').replace(/&nbsp;/gi, ' ').trim()
const anchorHref = (a) => (a.match(/\bhref\s*=\s*["']([^"']*)["']/i) || [])[1] || ''
const setHref = (a, url) => (HREF_RE.test(a) ? a.replace(HREF_RE, `href="${url}"`) : a.replace(/^<a\b/i, `<a href="${url}"`))
const isGoogleReviewAnchor = (a) => GOOGLE_TEXT_RE.test(anchorText(a)) || /writereview|g\.page\//i.test(anchorHref(a))
const isOtherReviewAnchor = (a) => OTHER_REVIEW_TEXT_RE.test(anchorText(a)) || OTHER_REVIEW_HREF_RE.test(anchorHref(a))
/** Krátká spojka mezi odkazy („, “, „ nebo na “, „ or “…) — bez tagů a konce věty. */
function isConnector(t) {
  const s = t.replace(/&nbsp;/gi, ' ')
  return s.length <= 24 && !/[<>.!?:]/.test(s) && /^[\s,;/&+–—-]*(?:[\p{L}]+[\s,]*){0,3}$/u.test(s)
}

/**
 * Poděkovací mail (booking_completed): odkazy „Google…“ → Google odkaz na recenzi; odkazy na jiné
 * recenzní weby (Facebook/Instagram/Firmy.cz/Mapy.cz/Tripadvisor/Seznam) pryč i se spojkou, takže
 * „recenzi na Google, Facebook nebo Instagram.“ → „recenzi na Google.“. Ikony profilů bez textu
 * zůstávají. Bez Google odkazu v šabloně se první recenzní odkaz změní na Google. Idempotentní.
 */
export function googleOnlyReviewLinks(html, googleUrl = GOOGLE_REVIEW_URL_DEFAULT) {
  if (!html) return html
  const url = googleUrl || GOOGLE_REVIEW_URL_DEFAULT
  const parts = []
  let last = 0
  for (const m of html.matchAll(ANCHOR_RE)) {
    parts.push(html.slice(last, m.index), m[0])
    last = m.index + m[0].length
  }
  parts.push(html.slice(last))
  let hasGoogle = false
  for (let i = 1; i < parts.length; i += 2) {
    if (isGoogleReviewAnchor(parts[i])) { parts[i] = setHref(parts[i], url); hasGoogle = true }
  }
  const removed = new Set()
  for (let i = 1; i < parts.length; i += 2) {
    if (!isOtherReviewAnchor(parts[i])) continue
    if (!hasGoogle) {
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
