// Jazykové hodnoty dosazované do {{placeholderů}} (audit EDGE-DOC-09): do PŘELOŽENÉHO dokumentu
// se dřív vkládaly české hodnoty (částka slovy, „3 dny“, tabulka výbavy, „Na pobočce“…).
// Platí jen pro jazyk dokumentu — u závazného českého textu (cs, nebo chybí čerstvý překlad)
// zůstávají české hodnoty i formát 1:1 jako dřív.

export interface DocLabels {
  locale: string
  gear: Record<'helmet' | 'jacket' | 'pants' | 'boots' | 'gloves', string>
  rider: string; passenger: string; child: string
  thItem: string; thSize: string; thHanded: string
  noGear: string; none: string; insuranceBasic: string
  delivery: string; atBranch: string; collection: string
  country: string
  /** Tvar slova „den“ podle Intl.PluralRules kategorie. */
  day: Partial<Record<Intl.LDMLPluralRule, string>> & { other: string }
  currency: string // částka „slovy“ pro cizí jazyk = číslo + název měny
}

export const LABELS: Record<string, DocLabels> = {
  cs: { locale: 'cs-CZ', gear: { helmet: 'Helma', jacket: 'Bunda / vesta', pants: 'Kalhoty', boots: 'Boty', gloves: 'Rukavice' },
    rider: 'řidič', passenger: 'spolujezdec', child: 'dětská velikost', thItem: 'Položka', thSize: 'Velikost', thHanded: 'Předáno',
    noGear: 'Žádné zapůjčené příslušenství.', none: 'Žádné', insuranceBasic: 'Základní', delivery: 'Přistavení', atBranch: 'Na pobočce',
    collection: 'Odvoz', country: 'Česká republika', day: { one: 'den', few: 'dny', other: 'dní' }, currency: 'korun českých' },
  en: { locale: 'en-GB', gear: { helmet: 'Helmet', jacket: 'Jacket / vest', pants: 'Trousers', boots: 'Boots', gloves: 'Gloves' },
    rider: 'rider', passenger: 'passenger', child: 'child size', thItem: 'Item', thSize: 'Size', thHanded: 'Handed over',
    noGear: 'No rented accessories.', none: 'None', insuranceBasic: 'Basic', delivery: 'Delivery', atBranch: 'At the branch',
    collection: 'Collection', country: 'Czech Republic', day: { one: 'day', other: 'days' }, currency: 'Czech korunas (CZK)' },
  de: { locale: 'de-DE', gear: { helmet: 'Helm', jacket: 'Jacke / Weste', pants: 'Hose', boots: 'Stiefel', gloves: 'Handschuhe' },
    rider: 'Fahrer', passenger: 'Beifahrer', child: 'Kindergröße', thItem: 'Artikel', thSize: 'Größe', thHanded: 'Übergeben',
    noGear: 'Kein geliehenes Zubehör.', none: 'Keine', insuranceBasic: 'Basis', delivery: 'Zustellung', atBranch: 'In der Filiale',
    collection: 'Abholung', country: 'Tschechische Republik', day: { one: 'Tag', other: 'Tage' }, currency: 'Tschechische Kronen (CZK)' },
  es: { locale: 'es-ES', gear: { helmet: 'Casco', jacket: 'Chaqueta / chaleco', pants: 'Pantalones', boots: 'Botas', gloves: 'Guantes' },
    rider: 'conductor', passenger: 'acompañante', child: 'talla infantil', thItem: 'Artículo', thSize: 'Talla', thHanded: 'Entregado',
    noGear: 'Sin accesorios alquilados.', none: 'Ninguno', insuranceBasic: 'Básico', delivery: 'Entrega a domicilio', atBranch: 'En la sucursal',
    collection: 'Recogida a domicilio', country: 'República Checa', day: { one: 'día', other: 'días' }, currency: 'coronas checas (CZK)' },
  fr: { locale: 'fr-FR', gear: { helmet: 'Casque', jacket: 'Blouson / gilet', pants: 'Pantalon', boots: 'Bottes', gloves: 'Gants' },
    rider: 'conducteur', passenger: 'passager', child: 'taille enfant', thItem: 'Article', thSize: 'Taille', thHanded: 'Remis',
    noGear: 'Aucun accessoire loué.', none: 'Aucun', insuranceBasic: 'De base', delivery: 'Livraison', atBranch: 'À l’agence',
    collection: 'Enlèvement', country: 'République tchèque', day: { one: 'jour', other: 'jours' }, currency: 'couronnes tchèques (CZK)' },
  nl: { locale: 'nl-NL', gear: { helmet: 'Helm', jacket: 'Jas / vest', pants: 'Broek', boots: 'Laarzen', gloves: 'Handschoenen' },
    rider: 'bestuurder', passenger: 'passagier', child: 'kindermaat', thItem: 'Artikel', thSize: 'Maat', thHanded: 'Overhandigd',
    noGear: 'Geen gehuurde accessoires.', none: 'Geen', insuranceBasic: 'Basis', delivery: 'Bezorging', atBranch: 'Bij de vestiging',
    collection: 'Ophalen', country: 'Tsjechië', day: { one: 'dag', other: 'dagen' }, currency: 'Tsjechische kronen (CZK)' },
  pl: { locale: 'pl-PL', gear: { helmet: 'Kask', jacket: 'Kurtka / kamizelka', pants: 'Spodnie', boots: 'Buty', gloves: 'Rękawice' },
    rider: 'kierowca', passenger: 'pasażer', child: 'rozmiar dziecięcy', thItem: 'Pozycja', thSize: 'Rozmiar', thHanded: 'Przekazano',
    noGear: 'Brak wypożyczonego wyposażenia.', none: 'Brak', insuranceBasic: 'Podstawowe', delivery: 'Dostawa', atBranch: 'W oddziale',
    collection: 'Odbiór', country: 'Czechy', day: { one: 'dzień', few: 'dni', many: 'dni', other: 'dnia' }, currency: 'koron czeskich (CZK)' },
  uk: { locale: 'uk-UA', gear: { helmet: 'Шолом', jacket: 'Куртка / жилет', pants: 'Штани', boots: 'Черевики', gloves: 'Рукавиці' },
    rider: 'водій', passenger: 'пасажир', child: 'дитячий розмір', thItem: 'Позиція', thSize: 'Розмір', thHanded: 'Передано',
    noGear: 'Без орендованого спорядження.', none: 'Немає', insuranceBasic: 'Базове', delivery: 'Доставка', atBranch: 'У філії',
    collection: 'Забір', country: 'Чехія', day: { one: 'день', few: 'дні', many: 'днів', other: 'дня' }, currency: 'чеських крон (CZK)' },
}

export const labelsFor = (lang: string): DocLabels => LABELS[lang] || LABELS.cs

/** „N dní“ v jazyce dokumentu; cs beze změny proti dřívějšku (1 den / 2–4 dny / 5+ dní). */
export function rentalPeriod(days: number, lang: string): string {
  const L = labelsFor(lang)
  if (lang === 'cs' || !LABELS[lang]) return days === 1 ? '1 den' : days < 5 ? `${days} dny` : `${days} dní`
  let cat: Intl.LDMLPluralRule = 'other'
  try { cat = new Intl.PluralRules(L.locale).select(days) } catch { /* other */ }
  return `${days} ${L.day[cat] || L.day.other}`
}

/** Číslo slovy česky (7800 → „sedm tisíc osm set“). Dřív se přípona „korun českých“ přidávala
 *  i v rekurzi pro tisíce → „sedm korun českých tisíc osm set korun českých“ (audit EDGE-DOC-09). */
function wordsCZ(abs: number): string {
  const ones = ['', 'jedna', 'dvě', 'tři', 'čtyři', 'pět', 'šest', 'sedm', 'osm', 'devět']
  const teens = ['deset', 'jedenáct', 'dvanáct', 'třináct', 'čtrnáct', 'patnáct', 'šestnáct', 'sedmnáct', 'osmnáct', 'devatenáct']
  const tens = ['', 'deset', 'dvacet', 'třicet', 'čtyřicet', 'padesát', 'šedesát', 'sedmdesát', 'osmdesát', 'devadesát']
  const hundreds = ['', 'sto', 'dvě stě', 'tři sta', 'čtyři sta', 'pět set', 'šest set', 'sedm set', 'osm set', 'devět set']
  if (abs === 0) return 'nula'
  const parts: string[] = []
  if (abs >= 1000000) { const m = Math.floor(abs / 1000000); parts.push(m === 1 ? 'milion' : m < 5 ? m + ' miliony' : m + ' milionů') }
  const thousands = Math.floor((abs % 1000000) / 1000)
  if (thousands > 0) {
    if (thousands === 1) parts.push('tisíc')
    // jen koncové „dvě/jedna“ (200 000 = „dvě stě tisíc“, ne „dva stě“; 21 000 = „dvacet jeden tisíc“)
    else parts.push(wordsCZ(thousands).replace(/dvě$/, 'dva').replace(/jedna$/, 'jeden') + (thousands < 5 ? ' tisíce' : ' tisíc'))
  }
  const rest = abs % 1000
  if (rest > 0) {
    const h = Math.floor(rest / 100), t = Math.floor((rest % 100) / 10), o = rest % 10
    if (h > 0) parts.push(hundreds[h])
    if (rest % 100 >= 10 && rest % 100 < 20) parts.push(teens[rest % 100 - 10])
    else { if (t > 0) parts.push(tens[t]); if (o > 0) parts.push(ones[o]) }
  }
  return parts.join(' ').trim()
}

export function numberToWordsCZ(n: number): string {
  const abs = Math.abs(Math.floor(n))
  const result = wordsCZ(abs)
  const dec = Math.round((Math.abs(n) - abs) * 100)
  return `${n < 0 ? 'mínus ' : ''}${result} korun českých${dec > 0 ? ` a ${dec}/100` : ''}`
}

export function fmtPriceL(n: number, lang: string): string {
  return (n || 0).toLocaleString(labelsFor(lang).locale, { minimumFractionDigits: 2 })
}
export function fmtDateL(d: string | null | undefined, lang: string): string {
  return d ? new Date(d).toLocaleDateString(labelsFor(lang).locale) : '—'
}

/** {{total_price_words}}: cs = česky slovy; jiný jazyk = částka + název měny (žádná čeština v cizím textu). */
export function priceWords(n: number, lang: string): string {
  if (lang === 'cs' || !LABELS[lang]) return numberToWordsCZ(n)
  return `${fmtPriceL(n, lang)} ${labelsFor(lang).currency}`
}
