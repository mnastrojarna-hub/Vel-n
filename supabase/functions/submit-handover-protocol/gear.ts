// Výbava v předávacím protokolu — položky `form.accessories[]`
// ({key, who, field?, label?, size, checked}) ↔ sloupce bookings.<key>_size /
// passenger_<key>_size. Položka bez vazby (jen label+size, staré appky) se
// pouze vykreslí; položka s vazbou a velikostí z číselníku accessory_types
// se PŘED podpisem propíše do rezervace (zákazník si u displeje/v appce
// upravil velikost). NEPŘEVZATÁ položka s vazbou (checked=false) se z rezervace
// ODEBÍRÁ (sloupec → NULL, `removed: true` pro dokument) — zadání majitele
// 2026-10-05; ceny / booking_extras se NEMĚNÍ (vratku řeší Velín ručně).

export const GEAR_KEYS = ['helmet', 'jacket', 'pants', 'boots', 'gloves'] as const
export type GearKey = typeof GEAR_KEYS[number]
export type GearWho = 'rider' | 'passenger'

const GEAR_LABELS: Record<GearKey, string> = { helmet: 'Helma', jacket: 'Bunda', pants: 'Kalhoty', boots: 'Boty', gloves: 'Rukavice' }
const WHO_LABELS: Record<GearWho, string> = { rider: 'řidič', passenger: 'spolujezdec' }

// Velikosti na SAMOOBSLUŽNÉ pobočce (zadání majitele 2026-10-10) — edge je vždy samoobsluha (index.ts
// odmítá not_self_service). Jen dospělá motorka: helma S–3XL, bunda/kalhoty/rukavice max. 4XL; boty,
// velikosti mimo pořadí (čísla, dětské popisky) a dětská motorka (license_required 'N') beze změny.
// Filtr podle POŘADÍ (trim + upper, aliasy XXL…). Parita: kiosk gear_limits.py, web gear-ss-cap.js, appka.
const SIZE_RANK: Record<string, number> = {
  XXS: 0, XS: 1, S: 2, M: 3, L: 4, XL: 5, '2XL': 6, XXL: 6, '3XL': 7, XXXL: 7, '4XL': 8, XXXXL: 8, '5XL': 9, XXXXXL: 9,
  '6XL': 10, XXXXXXL: 10,
}
const SS_LIMITS: Partial<Record<GearKey, [number, number]>> = { // [min, max] rank
  helmet: [SIZE_RANK.S, SIZE_RANK['3XL']], jacket: [0, SIZE_RANK['4XL']], pants: [0, SIZE_RANK['4XL']], gloves: [0, SIZE_RANK['4XL']],
}
// Záloha pro klíč bez aktivního neprázdného řádku v accessory_types (živá DB 2026-10-10: `jacket` chybí) — jen dospělá motorka.
const SS_FALLBACK: Partial<Record<GearKey, string[]>> = {
  helmet: ['S', 'M', 'L', 'XL', '2XL', '3XL'],
  jacket: ['S', 'M', 'L', 'XL', '2XL', '3XL', '4XL'],
  pants: ['S', 'M', 'L', 'XL', '2XL', '3XL', '4XL'],
  gloves: ['S', 'M', 'L', 'XL', '2XL', '3XL', '4XL'],
}

/** Smí se velikost vydat na samoobsluze? Dětská motorka / klíč bez pravidla / velikost mimo pořadí = ano. */
export function selfServiceSizeOk(key: string, size: string, isChild: boolean): boolean {
  const lim = SS_LIMITS[key as GearKey]
  const r = SIZE_RANK[String(size ?? '').trim().toUpperCase()]
  if (isChild || !lim || r === undefined) return true
  return r >= lim[0] && r <= lim[1]
}

/** Dětská motorka rezervace (`motorcycles!moto_id(license_required)` v selectu index.ts). */
export function bookingIsChild(booking: Record<string, unknown>): boolean {
  return ((booking.motorcycles || {}) as Record<string, unknown>).license_required === 'N'
}

/**
 * Velikosti, které smí protokol zapsat do rezervace: aktivní `accessory_types.sizes` (všechna audience),
 * u dospělé motorky ∪ záloha pro chybějící klíč a filtr samoobsluhy (5XL/6XL, helma XS → nezapíše se).
 */
export function allowedSizes(types: Array<{ key: string; sizes: string[] | null; is_active: boolean | null }>, isChild: boolean): Map<string, Set<string>> {
  const allowed = new Map<string, Set<string>>()
  const listed = new Set<string>() // klíč s aktivním neprázdným řádkem (jako gear_sizes kiosku) → bez zálohy
  for (const t of types) {
    if (t.is_active === false) continue
    const s = allowed.get(t.key) ?? new Set<string>()
    for (const x of t.sizes || []) {
      const v = String(x).trim()
      if (!v) continue
      listed.add(t.key)
      if (selfServiceSizeOk(t.key, v, isChild)) s.add(v)
    }
    allowed.set(t.key, s)
  }
  if (!isChild) for (const [k, list] of Object.entries(SS_FALLBACK)) if (!listed.has(k)) allowed.set(k, new Set(list))
  return allowed
}

export interface AccessoryItem {
  key?: GearKey; who?: GearWho; field?: string; label?: string; size?: string; checked?: boolean
  /** Nastaví edge: nepřevzatá položka, kterou z rezervace skutečně odebrala (sloupec → NULL). */
  removed?: boolean
  /** Nastaví edge: převzatá položka, kterou rezervace NEMĚLA (zákazník si ji vzal navíc) — v dokumentu „(navíc)“. */
  extra?: boolean
  added?: boolean     // kiosk ≥ 1.2.5: položka NAVÍC (při opakovaném podpisu po 5xx už je v rezervaci z 1. pokusu)
}

export function gearField(key: GearKey, who: GearWho): string {
  return who === 'passenger' ? `passenger_${key}_size` : `${key}_size`
}

/** Z názvu sloupce odvodí {key, who}; cizí sloupec → null (nikdy neaktualizovat). */
export function parseGearField(field: string): { key: GearKey; who: GearWho } | null {
  const m = /^(passenger_)?(helmet|jacket|pants|boots|gloves)_size$/.exec(field || '')
  if (!m) return null
  return { key: m[2] as GearKey, who: m[1] ? 'passenger' : 'rider' }
}

export function gearLabel(key: GearKey, who: GearWho): string {
  return `${GEAR_LABELS[key]} (${WHO_LABELS[who]})`
}

/** Výbava dle rezervace (jen neprázdné velikosti) — výchozí seznam pro kiosk. */
export function bookingGearItems(booking: Record<string, unknown>): AccessoryItem[] {
  const out: AccessoryItem[] = []
  for (const who of ['rider', 'passenger'] as GearWho[]) {
    for (const key of GEAR_KEYS) {
      const field = gearField(key, who)
      const size = String(booking[field] ?? '').trim()
      if (size) out.push({ key, who, field, label: gearLabel(key, who), size, checked: true })
    }
  }
  return out
}

/**
 * Normalizuje položky z klienta: doplní field/key/who/label. `defaultChecked`
 * platí pro položky bez `checked` (kiosk = předáno, appka = nezaškrtnuto).
 */
export function normalizeAccessories(raw: unknown, defaultChecked: boolean): AccessoryItem[] {
  if (!Array.isArray(raw)) return []
  const out: AccessoryItem[] = []
  for (const a of raw.slice(0, 40)) {
    if (!a || typeof a !== 'object') continue
    const it = a as Record<string, unknown>
    let key = (GEAR_KEYS as readonly string[]).includes(String(it.key)) ? it.key as GearKey : undefined
    let who = it.who === 'rider' || it.who === 'passenger' ? it.who as GearWho : undefined
    let field = typeof it.field === 'string' && it.field ? it.field : undefined
    if (field) {
      const p = parseGearField(field)
      if (p) { key = p.key; who = p.who } else field = undefined
    }
    if (!field && key && who) field = gearField(key, who)
    const size = String(it.size ?? '').trim().slice(0, 20)
    const label = String(it.label ?? '').trim().slice(0, 80) || (key && who ? gearLabel(key, who) : '')
    if (!label && !size) continue
    out.push({ key, who, field, label, size, checked: typeof it.checked === 'boolean' ? it.checked : defaultChecked,
      ...(it.added === true ? { added: true } : {}) })
  }
  return out
}

export interface SizeUpdates {
  updates: Record<string, string | null>                       // sloupec bookings → nová velikost, null = odebráno
  changes: Record<string, { from: string | null; to: string | null }> // klíč jako track_booking_content_changes (helmet, passenger_helmet…); from null = přidáno
}

// deno-lint-ignore no-explicit-any
type Admin = any

/**
 * Změny výbavy k propsání do rezervace. Bere se JEN položka s vazbou na sloupec:
 * - převzatá (checked) a v rezervaci je: jiná velikost z číselníku (`allowedSizes` — accessory_types v rozsahu
 *   samoobsluhy, 2026-10-10) → nová velikost;
 * - NEpřevzatá a v rezervaci je: sloupec → NULL (odebrána z rezervace) + `a.removed = true`;
 *   poslaná `size` je původní z rezervace a NIKDY se nepropisuje;
 * - převzatá a v rezervaci NENÍ = výbava NAVÍC (2026-10-05, zadání majitele: „co si vezme navíc, musí být v
 *   protokolu“): `a.extra = true` (dokument „navíc“); do rezervace se zapíše JEN s `allowAdd` (kiosk ≥ 1.2.5 s přístupem
 *   do šatny — jinak by přidání vyvolalo nový kód šatny uprostřed převzetí) a velikostí z číselníku. Ceny / booking_extras
 *   se nemění (doúčtování placené výbavy navíc řeší Velín ručně).
 * `allowRemove=false` (starý klient bez opt-in `form.gear_remove`): nepřevzatá
 * položka je jen ☐ v dokumentu jako dřív — rezervace se nemění.
 * `markExtra` (kiosk s `form.gear_add`): „navíc“ v dokumentu; jiný klient výbavu navíc přidat neumí → bez označení.
 */
export async function resolveGearUpdates(admin: Admin, booking: Record<string, unknown>, items: AccessoryItem[], allowRemove = true, allowAdd = false, markExtra = allowAdd): Promise<SizeUpdates> {
  const linked = items.filter((a) => a.field && a.key && a.who)
  const res: SizeUpdates = { updates: {}, changes: {} }
  if (!linked.length) return res
  let allowed = new Map<string, Set<string>>()
  if (linked.some((a) => a.checked && a.size)) {
    const { data: types, error } = await admin.from('accessory_types').select('key, sizes, is_active').in('key', [...GEAR_KEYS])
    // chyba dotazu = bez číselníku i zálohy → velikost se nezapíše (jako dřív)
    if (!error) allowed = allowedSizes((types || []) as Array<{ key: string; sizes: string[] | null; is_active: boolean | null }>, bookingIsChild(booking))
  }
  const currentOf = (a: AccessoryItem) => String(booking[a.field as string] ?? '').trim()
  for (const a of linked) {
    const field = a.field as string
    const current = currentOf(a)
    const changeKey = a.who === 'passenger' ? `passenger_${a.key}` : (a.key as string)
    if (!current) { // v rezervaci není → nic neodebírat; převzatá = navíc (zapsat jen s allowAdd a velikostí z číselníku)
      if (allowAdd && a.checked && a.size && allowed.get(a.key as string)?.has(a.size)) {
        res.updates[field] = a.size
        res.changes[changeKey] = { from: null, to: a.size }
      }
      continue
    }
    if (!a.checked) { // nepřevzato → odebrat z rezervace (jen klient, který sémantiku zná)
      if (allowRemove) { res.updates[field] = null; res.changes[changeKey] = { from: current, to: null } }
      continue
    }
    const sizes = allowed.get(a.key as string)
    if (!a.size || !sizes || !sizes.has(a.size)) continue // mimo číselník → jen zobrazit
    if (current === a.size) continue
    res.updates[field] = a.size
    res.changes[changeKey] = { from: current, to: a.size }
  }
  // `removed` až podle VÝSLEDKU (duplicitní položka s týmž `field` = poslední vyhrává): sloupec je po tomto
  // podpisu NULL — odebrán teď, nebo už dřív (opakovaný podpis po 5xx; 1. pokus ho odebral i se záznamem historie;
  // klient posílá u nepřevzaté položky původní velikost — bez ní položka v rezervaci nikdy nebyla).
  if (allowRemove) {
    for (const a of linked) {
      if (!a.checked && (res.updates[a.field as string] === null || (!currentOf(a) && a.size))) a.removed = true
    }
  }
  // navíc = v rezervaci není, nebo ji tam doplnil už 1. pokus téhož podpisu (klient ji posílá s `added`)
  if (markExtra) for (const a of linked) if (a.checked && a.size && (a.added === true || !currentOf(a))) a.extra = true
  return res
}
