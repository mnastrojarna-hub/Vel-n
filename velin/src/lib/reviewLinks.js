// Odkaz na recenze = VŽDY Google (majitel 2026-10-15: „odkaz na recenze by měl být vždy google“).
// Zrcadlo supabase/functions/_shared/review-links.ts (edge send-booking-email) pro náhled
// a testovací odeslání poděkovacího mailu ve Velíně — při změně upravit OBA soubory.
// Živý zdroj odkazu: app_settings.google_review_url (čte ho appka i DB trigger mailu);
// konstanta je výchozí hodnota / ukázka pro náhled.

export const GOOGLE_REVIEW_URL_DEFAULT = 'https://g.page/r/CUmeYvk-sNf6EBM/review'

const ANCHOR_RE = /<a\b[^>]*>[\s\S]*?<\/a>/gi
const HREF_RE = /\bhref\s*=\s*["'][^"']*["']/i
const GOOGLE_TEXT_RE = /^googl\w*$/i
// Názvy platforem (i skloňované „na Facebooku“); obecná slova („mapy“, „seznam“) jen s doménou.
const OTHER_REVIEW_TEXT_RE = /^(?:facebook\w*|instagram\w*|firmy(?:\.cz)?|mapy\.(?:cz|com)|tripadvisor\w*|seznam\.cz)$/i
const OTHER_REVIEW_HREF_RE = /firmy\.cz|tripadvisor\.|sk=reviews|facebook\.com\/[^"']*reviews/i
const REVIEW_WORD_RE = /recenz|hodno[tcť]|review|bewert|rezension|avis|rese[ñn]|valora|opini|beoordel|oce[nń]|відгук|оцін|рецензі/i
const BREAK_RE = /<\/?(?:p|div|li|ul|ol|tr|td|th|table|tbody|h[1-6]|blockquote|section)\b[^>]*>|<br\s*\/?>|[.!?](?=\s|<|&nbsp;|$)/gi

const anchorText = (a) => a.replace(/<[^>]+>/g, '').replace(/&nbsp;/gi, ' ').trim()
const anchorHref = (a) => (a.match(/\bhref\s*=\s*["']([^"']*)["']/i) || [])[1] || ''
const setHref = (a, url) => (HREF_RE.test(a) ? a.replace(HREF_RE, `href="${url}"`) : a.replace(/^<a\b/i, `<a href="${url}"`))
const isGoogleReviewAnchor = (a, url) => {
  const h = anchorHref(a)
  return GOOGLE_TEXT_RE.test(anchorText(a)) || h === url || /writereview|g\.page\//i.test(h)
}
/** Krátká spojka mezi odkazy („, “, „ nebo na “, „ or “, „ | “…) — bez tagů a konce věty. */
function isConnector(t) {
  const s = t.replace(/&nbsp;/gi, ' ')
  return s.length <= 24 && !/[<>.!?:]/.test(s) && /^[\s,;/&+|·•–—-]*(?:[\p{L}]+[\s,|·•]*){0,3}$/u.test(s)
}
/** Prostý text věty (bloku), ve které leží odkaz parts[i]. */
function sentenceAround(parts, i) {
  const before = parts.slice(0, i).join('')
  const after = parts.slice(i + 1).join('')
  let start = 0
  for (const m of before.matchAll(BREAK_RE)) start = m.index + m[0].length
  const end = after.search(BREAK_RE)
  const s = before.slice(start) + parts[i] + (end < 0 ? after : after.slice(0, end))
  return s.replace(/<[^>]+>/g, ' ').replace(/&nbsp;/gi, ' ')
}

/**
 * Poděkovací mail (booking_completed): odkazy „Google…“ → Google odkaz na recenzi. Jiné recenzní
 * weby: ve VÝČTU s Google odkazem („Google, Facebook nebo Instagram“) pryč i se spojkou →
 * „recenzi na Google.“; jinde se změní na Google odkaz jen recenzní URL (Firmy.cz, Tripadvisor,
 * …/reviews) nebo odkaz ve větě o recenzi/hodnocení. „Sledujte nás na Facebooku“ i ikony profilů
 * zůstávají. Idempotentní.
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
  // Výčet = po sobě jdoucí odkazy spojené krátkou spojkou.
  const group = []
  for (let i = 1, g = 0; i < parts.length; i += 2) {
    if (i > 1 && !isConnector(parts[i - 1])) g++
    group[i] = g
  }
  const google = new Set()
  const googleGroups = new Set()
  for (let i = 1; i < parts.length; i += 2) {
    if (isGoogleReviewAnchor(parts[i], url)) { parts[i] = setHref(parts[i], url); google.add(i); googleGroups.add(group[i]) }
  }
  const textHit = (i) => OTHER_REVIEW_TEXT_RE.test(anchorText(parts[i]))
  const hrefHit = (i) => OTHER_REVIEW_HREF_RE.test(anchorHref(parts[i]))
  // 1) Recenzní odkaz mimo výčet s Googlem → Google odkaz (věta zůstane celá).
  for (let i = 1; i < parts.length; i += 2) {
    if (google.has(i) || googleGroups.has(group[i])) continue
    const t = textHit(i)
    if (!hrefHit(i) && !(t && REVIEW_WORD_RE.test(sentenceAround(parts, i)))) continue
    parts[i] = setHref(parts[i], url)
    if (t) parts[i] = parts[i].replace(/^(<a\b[^>]*>)[\s\S]*(<\/a>)$/i, '$1Google$2')
    google.add(i); googleGroups.add(group[i])
  }
  // 2) Ostatní recenzní weby ve výčtu s Googlem → pryč i se spojkou.
  const removed = new Set()
  for (let i = 1; i < parts.length; i += 2) {
    if (google.has(i) || !googleGroups.has(group[i]) || !(textHit(i) || hrefHit(i))) continue
    let p = i - 2
    while (p >= 1 && removed.has(p)) p -= 2
    if (p >= 1 && group[p] === group[i]) {
      for (let k = p + 1; k < i; k++) parts[k] = ''
    } else if (i + 2 < parts.length && group[i + 2] === group[i]) {
      parts[i + 1] = ''
    }
    parts[i] = ''
    removed.add(i)
  }
  return parts.join('')
}
