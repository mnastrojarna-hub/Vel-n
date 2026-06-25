// Jednotná SKU konvence MotoGo — ZDROJ PRAVDY pro celý Velín i AI.
// Formát: kategorie-typ-varianta · malá písmena, číslice, pomlčky · bez mezer a diakritiky.
// Výjimka: velikost příslušenství se píše PŘESNĚ jako v číselníku (XL, 2XL, 43).

export const SKU_CATEGORY_PREFIX = {
  prislusenstvi: 'prislusenstvi', // půjčované/spotřební gear
  material: 'material',
  inventory: 'zbozi',             // „Zboží" v číselníku inventory.category = inventory
  supplies: 'spotrebni',          // „Spotřební materiál"
  dily: 'dily',                   // náhradní díly / servis
}

export const ACCESSORY_TYPE_LABELS = {
  helmet: 'Helma', jacket: 'Bunda', pants: 'Kalhoty', boots: 'Boty', gloves: 'Rukavice', balaclava: 'Kukla',
}
export const CATEGORY_LABELS = {
  prislusenstvi: 'Příslušenství', dily: 'Náhradní díl', material: 'Materiál',
  zbozi: 'Zboží / e-shop', spotrebni: 'Spotřební',
}
const KNOWN_PREFIXES = ['prislusenstvi', 'dily', 'material', 'zbozi', 'spotrebni']

// Vzorové řádky pro nápovědu v UI.
export const SKU_CONVENTION = [
  { label: 'Příslušenství', pattern: 'prislusenstvi-{typ}-{velikost}', example: 'prislusenstvi-boots-43' },
  { label: 'Náhradní díly (servis)', pattern: 'dily-{slug}', example: 'dily-olej-10w40' },
  { label: 'Materiál', pattern: 'material-{slug}', example: 'material-cistic-retezu' },
  { label: 'Zboží / e-shop', pattern: 'zbozi-{slug}', example: 'zbozi-tricko-logo' },
  { label: 'Spotřební (provoz)', pattern: 'spotrebni-{slug}', example: 'spotrebni-ubrousky' },
]
export const SKU_RULES = [
  'Jen malá písmena a–z, číslice a pomlčky. Žádné mezery ani diakritika.',
  'Typ příslušenství: helmet, jacket, pants, boots, gloves, balaclava.',
  'Velikost u příslušenství je vždy POSLEDNÍ a píše se přesně jako v číselníku (43, XL, 2XL, UNI).',
  'slug = krátký výstižný název: značka-typ-parametr.',
]

// Diakritika pryč, lowercase, mezery → pomlčky (pro slug u ne-příslušenství).
export function normalizeSlug(s) {
  return (s || '').toString().normalize('NFD').replace(/[̀-ͯ]/g, '')
    .toLowerCase().trim().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '')
}

// Příslušenství: ZACHOVÁVÁ stávající tvar `prislusenstvi-{type}-{size}` (size as-is,
// shoda s BranchHelpers.accSku, IssueToBranchModal a daty v DB).
export function accessorySku(type, size) {
  return `prislusenstvi-${type}-${size}`
}

export function buildSku(category, slug) {
  const pre = SKU_CATEGORY_PREFIX[category] || normalizeSlug(category)
  return `${pre}-${normalizeSlug(slug)}`
}

export function parseSku(sku) {
  if (!sku) return null
  const s = String(sku)
  const m = /^prislusenstvi-([a-z0-9_]+)-(.+)$/i.exec(s)
  if (m) return { category: 'prislusenstvi', type: m[1], size: m[2], isAccessory: true }
  const m2 = /^([a-z]+)-(.+)$/.exec(s)
  if (m2) return { category: m2[1], slug: m2[2], isAccessory: false }
  return { raw: s, unknown: true }
}

export function describeSku(sku) {
  const p = parseSku(sku)
  if (!p || p.unknown) return null
  if (p.isAccessory) return `Příslušenství · ${ACCESSORY_TYPE_LABELS[p.type] || p.type} · velikost ${p.size}`
  return `${CATEGORY_LABELS[p.category] || p.category} · ${p.slug}`
}

// Vrací { ok, warning } — ok=false jen u tvarově špatného SKU; warning i u ok (nestandardní prefix).
export function validateSku(sku) {
  const s = (sku || '').toString().trim()
  if (!s) return { ok: false, warning: 'Chybí SKU.' }
  if (/\s/.test(s) || /[^\w-]/.test(s)) return { ok: false, warning: 'SKU smí mít jen písmena, číslice a pomlčky (bez mezer a diakritiky).' }
  if (!/^[a-z0-9]+(-[a-zA-Z0-9]+)+$/.test(s)) return { ok: false, warning: 'Formát: kategorie-typ-varianta (např. prislusenstvi-boots-43).' }
  const pre = s.split('-')[0]
  if (!KNOWN_PREFIXES.includes(pre)) return { ok: true, warning: `Nestandardní prefix „${pre}". Doporučené: ${KNOWN_PREFIXES.join(', ')}.` }
  return { ok: true }
}
