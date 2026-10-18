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
export const GOOGLE_REVIEW_URL_DEFAULT = 'https://g.page/r/CUmeYvk-sNf6EBM/review';
const GOOGLE_HOST_RE = /^https:\/\/(?:[a-z0-9-]+\.)*(?:google\.[a-z]{2,3}(?:\.[a-z]{2})?|g\.page|goo\.gl)(?:[/?#]|$)/i;
// Zrušené vlastní krátké názvy (g.page/<jmeno>/review) Google už neobsluhuje — platné jsou jen g.page/r/<id>.
const LEGACY_GPAGE_RE = /^https:\/\/g\.page\/(?!r\/)/i;
/** Je to použitelný odkaz na recenze na Googlu? */ export function isGoogleReviewUrl(u) {
  if (typeof u !== 'string') return false;
  const s = u.trim();
  return GOOGLE_HOST_RE.test(s) && !LEGACY_GPAGE_RE.test(s);
}
/** První Google odkaz z kandidátů, jinak výchozí. */ export function pickGoogleReviewUrl(...candidates) {
  for (const c of candidates)if (isGoogleReviewUrl(c)) return c.trim();
  return GOOGLE_REVIEW_URL_DEFAULT;
}
/** Odkaz z payloadu (pokud je Google), jinak z app_settings.google_review_url, jinak výchozí. */ // deno-lint-ignore no-explicit-any
export async function loadGoogleReviewUrl(supabase, provided) {
  if (isGoogleReviewUrl(provided)) return provided.trim();
  try {
    const { data } = await supabase.from('app_settings').select('value').eq('key', 'google_review_url').maybeSingle();
    const v = data?.value;
    const s = typeof v === 'string' ? v : v && typeof v === 'object' ? v.url : null;
    if (isGoogleReviewUrl(s)) return s.trim();
  } catch  {}
  return GOOGLE_REVIEW_URL_DEFAULT;
}
// ── Úprava těla poděkovacího mailu (DB šablona z Velína i její AI překlad) ──────────
// Odkazy s textem „Google…“ → správný Google odkaz. Jiné recenzní weby se řeší podle kontextu,
// aby se nerozbily běžné odkazy („Sledujte nás na Facebooku“ zůstává):
//  • ve VÝČTU s Google odkazem („Google, Facebook nebo Instagram“ — odkazy spojené krátkou
//    spojkou) se odstraní i se spojkou → „recenzi na Google.“ v každém jazyce,
//  • jinde se změní na Google odkaz, jen když jde o recenzní URL (Firmy.cz, Tripadvisor,
//    …/reviews) nebo věta mluví o recenzi/hodnocení — věta tak zůstane celá.
// Ikony „Sledujte nás“ (obrázek bez textu, odkaz na profil) zůstávají. Idempotentní.
const ANCHOR_RE = /<a\b[^>]*>[\s\S]*?<\/a>/gi;
// Názvy platforem (i skloňované „na Facebooku“); obecná slova („mapy“, „seznam“) jen s doménou.
const OTHER_REVIEW_TEXT_RE = /^(?:facebook\w*|instagram\w*|firmy(?:\.cz)?|mapy\.(?:cz|com)|tripadvisor\w*|seznam\.cz)$/i;
const OTHER_REVIEW_HREF_RE = /firmy\.cz|tripadvisor\.|sk=reviews|facebook\.com\/[^"']*reviews/i;
const GOOGLE_TEXT_RE = /^googl\w*$/i;
// Věta o recenzi/hodnocení (8 jazyků webu/appky).
const REVIEW_WORD_RE = /recenz|hodno[tcť]|review|bewert|rezension|avis|rese[ñn]|valora|opini|beoordel|oce[nń]|відгук|оцін|рецензі/i;
// Konec věty / blok — hranice „věty“ kolem odkazu.
const BREAK_RE = /<\/?(?:p|div|li|ul|ol|tr|td|th|table|tbody|h[1-6]|blockquote|section)\b[^>]*>|<br\s*\/?>|[.!?](?=\s|<|&nbsp;|$)/gi;
function anchorText(a) {
  return a.replace(/<[^>]+>/g, '').replace(/&nbsp;/gi, ' ').trim();
}
function anchorHref(a) {
  return (a.match(/\bhref\s*=\s*["']([^"']*)["']/i) || [])[1] || '';
}
// Slova, která smí stát mezi odkazy výčtu: spojky a předložky (8 jazyků). Sloveso („a sledujte“,
// „and follow“) výčet ukončí — odkaz za ním není recenzní a zůstává.
const CONNECTOR_WORD_RE = /^(?:a|i|e|o|u|y|nebo|anebo|či|na|ve?|přes|and|or|on|at|via|und|oder|auf|bei|bzw|sowie|en|of|op|bij|ni|et|ou|sur|lub|albo|oraz|czy|w|й|і|у|в|та|або|чи|на)$/iu;
/** Krátká spojka mezi dvěma odkazy (bez tagů a konce věty): „, “ „ nebo na “ „ or “ „ | “ … */ function isConnector(t) {
  const s = t.replace(/&nbsp;/gi, ' ');
  if (s.length > 24 || /[<>.!?:]/.test(s) || !/^[\s,;/&+|·•–—-]*(?:[\p{L}]+[\s,|·•]*){0,3}$/u.test(s)) return false;
  return (s.match(/\p{L}+/gu) || []).every((w)=>CONNECTOR_WORD_RE.test(w));
}
/** Prostý text úseku věty, ke kterému patří odkaz parts[i]: text od předchozího odkazu (nebo od
 *  začátku věty) k odkazu; je-li odkaz ve větě poslední, i text za ním do konce věty. */ function clauseAround(parts, i) {
  const prev = parts[i - 1] ?? '';
  let start = 0;
  for (const m of prev.matchAll(BREAK_RE))start = (m.index ?? 0) + m[0].length;
  const next = parts[i + 1] ?? '';
  const end = next.search(BREAK_RE);
  const lastInSentence = end >= 0 || i + 2 >= parts.length;
  const s = prev.slice(start) + ' ' + (lastInSentence ? end < 0 ? next : next.slice(0, end) : '');
  return s.replace(/<[^>]+>/g, ' ').replace(/&nbsp;/gi, ' ');
}
const HREF_RE = /\bhref\s*=\s*["'][^"']*["']/i;
function setHref(a, url) {
  return HREF_RE.test(a) ? a.replace(HREF_RE, `href="${url}"`) : a.replace(/^<a\b/i, `<a href="${url}"`);
}
/** Odkaz na Google recenze: text „Google…“ nebo recenzní URL Googlu (g.page, writereview). */ function isGoogleReviewAnchor(a, url) {
  const h = anchorHref(a);
  return GOOGLE_TEXT_RE.test(anchorText(a)) || h === url || /writereview|g\.page\//i.test(h);
}
export function googleOnlyReviewLinks(html, googleUrl) {
  if (!html) return html;
  const url = pickGoogleReviewUrl(googleUrl);
  // Rozložit na [text, odkaz, text, odkaz, …, text] (liché indexy = odkazy).
  const parts = [];
  let last = 0;
  for (const m of html.matchAll(ANCHOR_RE)){
    parts.push(html.slice(last, m.index), m[0]);
    last = (m.index ?? 0) + m[0].length;
  }
  parts.push(html.slice(last));
  // Výčet = po sobě jdoucí odkazy spojené krátkou spojkou.
  const group = [];
  for(let i = 1, g = 0; i < parts.length; i += 2){
    if (i > 1 && !isConnector(parts[i - 1])) g++;
    group[i] = g;
  }
  const google = new Set();
  const googleGroups = new Set();
  for(let i = 1; i < parts.length; i += 2){
    if (isGoogleReviewAnchor(parts[i], url)) {
      parts[i] = setHref(parts[i], url);
      google.add(i);
      googleGroups.add(group[i]);
    }
  }
  const textHit = (i)=>OTHER_REVIEW_TEXT_RE.test(anchorText(parts[i]));
  const hrefHit = (i)=>OTHER_REVIEW_HREF_RE.test(anchorHref(parts[i]));
  // 1) Recenzní odkaz mimo výčet s Googlem → Google odkaz (věta zůstane celá). Nejdřív recenzní
  //    URL, pak název platformy v úseku věty o recenzi — ten jen, když věta ještě Google odkaz nemá
  //    („Hodnoťte nás na Facebooku a sledujte Instagram“ → Instagram zůstává).
  const sentence = [];
  for(let i = 1, n = 0; i < parts.length; i += 2){
    n += (parts[i - 1].match(BREAK_RE) || []).length;
    sentence[i] = n;
  }
  for (const byHref of [
    true,
    false
  ]){
    for(let i = 1; i < parts.length; i += 2){
      if (google.has(i) || googleGroups.has(group[i])) continue;
      const t = textHit(i);
      if (byHref ? !hrefHit(i) : !(t && REVIEW_WORD_RE.test(clauseAround(parts, i)) && ![
        ...google
      ].some((j)=>sentence[j] === sentence[i]))) continue;
      parts[i] = setHref(parts[i], url);
      if (t) parts[i] = parts[i].replace(/^(<a\b[^>]*>)[\s\S]*(<\/a>)$/i, '$1Google$2');
      google.add(i);
      googleGroups.add(group[i]);
    }
  }
  // 2) Ostatní recenzní weby ve výčtu s Googlem → pryč i se spojkou.
  const removed = new Set();
  for(let i = 1; i < parts.length; i += 2){
    if (google.has(i) || !googleGroups.has(group[i]) || !(textHit(i) || hrefHit(i))) continue;
    let p = i - 2;
    while(p >= 1 && removed.has(p))p -= 2;
    if (p >= 1 && group[p] === group[i]) {
      for(let k = p + 1; k < i; k++)parts[k] = '';
    } else if (i + 2 < parts.length && group[i + 2] === group[i]) {
      parts[i + 1] = '';
    }
    parts[i] = '';
    removed.add(i);
  }
  return parts.join('');
}
// ── Blok „napište nám recenzi“ (expedice e-shopu, konečná faktura e-shopu) ─────────
const REVIEW_BLOCK_LABELS = {
  cs: {
    title: 'Pomohlo by nám vaše hodnocení',
    body: 'Budeme rádi, když nám zanecháte upřímnou recenzi na Googlu — pomáháte tím dalším motorkářům.',
    cta: '⭐ Ohodnotit na Google'
  },
  en: {
    title: 'Your review would help us',
    body: 'We’d be glad if you left us an honest review on Google — it helps fellow riders.',
    cta: '⭐ Review on Google'
  },
  de: {
    title: 'Ihre Bewertung würde uns helfen',
    body: 'Wir freuen uns über Ihre ehrliche Bewertung auf Google — Sie helfen damit anderen Bikern.',
    cta: '⭐ Auf Google bewerten'
  },
  nl: {
    title: 'Je review helpt ons enorm',
    body: 'We stellen een eerlijke review op Google erg op prijs — je helpt er andere motorrijders mee.',
    cta: '⭐ Beoordeel op Google'
  },
  es: {
    title: 'Tu reseña nos ayudaría mucho',
    body: 'Nos encantaría que nos dejaras una reseña sincera en Google — ayudas a otros moteros.',
    cta: '⭐ Reseña en Google'
  },
  fr: {
    title: 'Votre avis nous aiderait',
    body: 'Nous serions ravis que vous nous laissiez un avis sincère sur Google — vous aidez d’autres motards.',
    cta: '⭐ Avis sur Google'
  },
  pl: {
    title: 'Twoja recenzja by nam pomogła',
    body: 'Będzie nam miło, jeśli zostawisz nam szczerą recenzję w Google — pomożesz innym motocyklistom.',
    cta: '⭐ Oceń w Google'
  },
  uk: {
    title: 'Ваш відгук нам дуже допоможе',
    body: 'Будемо раді вашому чесному відгуку в Google — ви допоможете іншим мотоциклістам.',
    cta: '⭐ Оцінити в Google'
  }
};
export function googleReviewBlock(lang, url) {
  const l = REVIEW_BLOCK_LABELS[lang] || REVIEW_BLOCK_LABELS.cs;
  const href = pickGoogleReviewUrl(url);
  return `<div style="background:#000000;border:2px solid #74FB71;border-radius:8px;padding:24px;margin:24px 0;text-align:center">
  <div style="color:#74FB71;font-size:18px;font-weight:800;margin:0 0 8px">${l.title}</div>
  <div style="color:#ffffff;font-size:13px;margin:0 0 16px">${l.body}</div>
  <a href="${href}" target="_blank" rel="noopener" style="display:inline-block;background:#74FB71;color:#000000;font-size:13px;font-weight:700;text-decoration:none;padding:12px 28px;border-radius:24px">${l.cta}</a>
</div>`;
}
