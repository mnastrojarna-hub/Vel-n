// ===== _shared/agent-knowledge/site-url.ts =====
// Odkazy na web v JAZYCE ZÁKAZNÍKA (audit i18n 2026-10-10, AI-03/AI-08/AI-12).
// motogo24.cz vždy renderuje češtinu (Accept-Language ignoruje) → cizinec z odkazu
// agenta dostal českou stránku. Pravidlo webu (motogo-web-php/i18n.php):
// ?lang=xx má nejvyšší prioritu (uloží i cookie), lokalizovaný slug se servíruje bez
// 301 (mapa = motogo-web-php/i18n_slugs.php I18N_SLUG_ROUTES/PREFIXES — při změně
// slugů tam uprav i tuto kopii). cs → www.motogo24.cz + česká cesta; ostatní →
// www.motogo24.com + lokalizovaná cesta + ?lang=xx (i pro en — přebije starou cookie).

export const AGENT_LANGS = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'] as const
export type AgentLang = typeof AGENT_LANGS[number]

/** Normalizuje vstup ('de-AT', 'UK', null…) na jeden z 8 jazyků webu; jinak fallback. */
export function normLang(v: unknown, fallback: AgentLang = 'cs'): AgentLang {
  const s = String(v ?? '').trim().slice(0, 2).toLowerCase()
  return (AGENT_LANGS as readonly string[]).includes(s) ? s as AgentLang : fallback
}

// Pořadí jazyků v kompaktních záznamech níže: en|de|es|fr|nl|pl|uk
const ORDER = ['en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'] as const
const ROUTES: Record<string, string> = {
  '/katalog': '/catalog|/katalog|/catalogo|/catalogue|/catalogus|/katalog|/catalog',
  '/pujcovna-motorek': '/motorcycle-rental|/motorradverleih|/alquiler-de-motos|/location-de-motos|/motorverhuur|/wypozyczalnia-motocykli|/motorcycle-rental',
  '/jak-pujcit': '/how-to-rent|/mietanleitung|/como-alquilar|/comment-louer|/hoe-huren|/jak-wypozyczyc|/how-to-rent',
  '/jak-pujcit/faq': '/how-to-rent/faq|/mietanleitung/faq|/como-alquilar/faq|/comment-louer/faq|/hoe-huren/faq|/jak-wypozyczyc/faq|/how-to-rent/faq',
  '/jak-pujcit/dokumenty': '/how-to-rent/documents|/mietanleitung/dokumente|/como-alquilar/documentos|/comment-louer/documents|/hoe-huren/documenten|/jak-wypozyczyc/dokumenty|/how-to-rent/documents',
  '/jak-pujcit/co-v-cene': '/how-to-rent/whats-included|/mietanleitung/was-ist-im-preis|/como-alquilar/que-incluye|/comment-louer/ce-qui-est-inclus|/hoe-huren/wat-is-inbegrepen|/jak-wypozyczyc/co-w-cenie|/how-to-rent/whats-included',
  '/poukazy': '/vouchers|/gutscheine|/tarjetas-regalo|/bons-cadeaux|/cadeaubonnen|/vouchery|/vouchers',
  '/koupit-darkovy-poukaz': '/buy-gift-voucher|/gutschein-kaufen|/comprar-tarjeta-regalo|/acheter-bon-cadeau|/cadeaubon-kopen|/kup-voucher|/buy-gift-voucher',
  '/pobocky': '/branches|/filialen|/sucursales|/agences|/filialen|/oddzialy|/branches',
  '/kontakt': '/contact|/kontakt|/contacto|/contact|/contact|/kontakt|/contact',
  '/partneri': '/partners|/partner|/socios|/partenaires|/partners|/partnerzy|/partners',
  '/eshop': '/shop|/shop|/tienda|/boutique|/winkel|/sklep|/shop',
  '/rezervace': '/booking|/reservierung|/reserva|/reservation|/reservering|/rezerwacja|/booking',
  '/upravit-rezervaci': '/manage-booking|/reservierung-verwalten|/gestionar-reserva|/gerer-reservation|/reservering-beheren|/zarzadzaj-rezerwacja|/manage-booking',
  '/potvrzeni': '/confirmation|/bestaetigung|/confirmacion|/confirmation|/bevestiging|/potwierdzenie|/confirmation',
  '/pujceni-obleceni': '/gear-rental|/ausruestung-mieten|/alquiler-de-equipo|/location-equipement|/uitrusting-huren|/wypozyczenie-odziezy|/gear-rental',
}
// Prefixy dynamických cest (UUID/slug za prefixem se nepřekládá)
const PREFIXES: Record<string, string> = {
  '/katalog/': '/catalog/|/katalog/|/catalogo/|/catalogue/|/catalogus/|/katalog/|/catalog/',
  '/dokumenty/': '/documents/|/dokumente/|/documentos/|/documents/|/documenten/|/dokumenty/|/documents/',
  '/pobocky/': '/branches/|/filialen/|/sucursales/|/agences/|/filialen/|/oddzialy/|/branches/',
  '/eshop/': '/shop/|/shop/|/tienda/|/boutique/|/winkel/|/sklep/|/shop/',
}

function pick(entry: string, lang: AgentLang): string {
  return entry.split('|')[ORDER.indexOf(lang as typeof ORDER[number])] || ''
}

/** Česká (kanonická) cesta → lokalizovaný slug pro jazyk (neznámé cesty beze změny). */
export function localizePath(path: string, lang: AgentLang): string {
  if (lang === 'cs' || !path.startsWith('/')) return path
  if (ROUTES[path]) return pick(ROUTES[path], lang) || path
  for (const [canon, entry] of Object.entries(PREFIXES)) {
    if (path.startsWith(canon)) return (pick(entry, lang) || canon) + path.slice(canon.length)
  }
  return path
}

/** Lokalizovaná cesta (libovolný jazyk) → kanonická česká (pro typ stránky z widgetu). */
export function canonicalPath(path: string): string {
  const p = String(path || '/').replace(/\/+$/, '') || '/'
  for (const [canon, entry] of Object.entries(ROUTES)) {
    if (p === canon || entry.split('|').includes(p)) return canon
  }
  for (const [canon, entry] of Object.entries(PREFIXES)) {
    for (const loc of [canon, ...entry.split('|')]) if (p.startsWith(loc)) return canon + p.slice(loc.length)
  }
  return p
}

/**
 * Absolutní URL webu pro jazyk zákazníka. `czechPath` = česká cesta, smí obsahovat
 * ?query i #fragment (např. '/rezervace?resume=<id>', '/dokumenty/obchodni-podminky').
 */
export function siteUrl(lang: unknown, czechPath = '/'): string {
  const L = normLang(lang)
  const raw = czechPath.startsWith('/') ? czechPath : '/' + czechPath
  if (L === 'cs') return 'https://www.motogo24.cz' + raw
  const [beforeHash, hash = ''] = raw.split('#', 2)
  const [path, query = ''] = beforeHash.split('?', 2)
  const q = (query ? query + '&' : '') + 'lang=' + L
  return 'https://www.motogo24.com' + localizePath(path, L) + '?' + q + (hash ? '#' + hash : '')
}

/** Web dokumenty: document_templates.type → veřejný slug (/dokumenty/<slug>, components.php mgPublicDocuments). */
export const TEMPLATE_DOC_SLUG: Record<string, string> = {
  vop: 'obchodni-podminky',
  rental_contract: 'smlouva-o-pronajmu',
  handover_protocol: 'predavaci-protokol',
  damage_protocol: 'protokol-o-poskozeni',
  gdpr: 'zasady-ochrany-osobnich-udaju',
}

/** Blok do promptu: hotové odkazy v jazyce zákazníka (nahrazují české cesty z pravidel). */
export function webLinksBlock(lang: unknown): string {
  const L = normLang(lang)
  const u = (p: string) => siteUrl(L, p)
  return `ODKAZY NA WEB V JAZYCE ZÁKAZNÍKA (${L}) — kde pravidla zmiňují motogo24.cz/… nebo https://www.motogo24.cz/…, dej zákazníkovi VÝHRADNĚ tyto (nebo URL vrácené toolem); české cesty jsou jen interní označení stránek:
- web: ${u('/')}
- katalog motorek: ${u('/katalog')} (detail motorky = pole \`url\` ze \`search_motorcycles\`)
- Moje rezervace / Upravit rezervaci (doklady, posun termínu, storno, faktury, zapomenuté heslo): ${u('/upravit-rezervaci')}
- obchodní podmínky (VOP): ${u('/dokumenty/obchodni-podminky')}
- smlouva o pronájmu: ${u('/dokumenty/smlouva-o-pronajmu')}
- ochrana osobních údajů (GDPR): ${u('/dokumenty/zasady-ochrany-osobnich-udaju')}
- pobočky: ${u('/pobocky')} · kontakt: ${u('/kontakt')} · časté dotazy: ${u('/jak-pujcit/faq')}
- dárkové poukazy: ${u('/poukazy')} · e-shop: ${u('/eshop')}
- půjčení výbavy BEZ motorky (helma, bunda, kalhoty, rukavice, boty): ${u('/pujceni-obleceni')} (s pobočkou/termínem = pole \`order_url\` z \`get_gear_rental_offer\`)`
}
