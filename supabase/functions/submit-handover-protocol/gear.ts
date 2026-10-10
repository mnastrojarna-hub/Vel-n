// Výbava v předávacím protokolu — položky `form.accessories[]`
// ({key, who, field?, label?, size, checked}) ↔ sloupce bookings.<key>_size /
// passenger_<key>_size. Položka bez vazby (jen label+size, staré appky) se
// pouze vykreslí; položka s vazbou a velikostí z číselníku accessory_types
// se PŘED podpisem propíše do rezervace (zákazník si u displeje/v appce
// upravil velikost). NEPŘEVZATÁ položka s vazbou (checked=false) se z rezervace
// ODEBÍRÁ (sloupec → NULL, `removed: true` pro dokument) — zadání majitele
// 2026-10-05; ceny / booking_extras se NEMĚNÍ (vratku řeší Velín ručně).
export const GEAR_KEYS = [
  'helmet',
  'jacket',
  'pants',
  'boots',
  'gloves'
];
const GEAR_LABELS = {
  helmet: 'Helma',
  jacket: 'Bunda',
  pants: 'Kalhoty',
  boots: 'Boty',
  gloves: 'Rukavice'
};
const WHO_LABELS = {
  rider: 'řidič',
  passenger: 'spolujezdec'
};
export function gearField(key, who) {
  return who === 'passenger' ? `passenger_${key}_size` : `${key}_size`;
}
/** Z názvu sloupce odvodí {key, who}; cizí sloupec → null (nikdy neaktualizovat). */ export function parseGearField(field) {
  const m = /^(passenger_)?(helmet|jacket|pants|boots|gloves)_size$/.exec(field || '');
  if (!m) return null;
  return {
    key: m[2],
    who: m[1] ? 'passenger' : 'rider'
  };
}
export function gearLabel(key, who) {
  return `${GEAR_LABELS[key]} (${WHO_LABELS[who]})`;
}
/** Výbava dle rezervace (jen neprázdné velikosti) — výchozí seznam pro kiosk. */ export function bookingGearItems(booking) {
  const out = [];
  for (const who of [
    'rider',
    'passenger'
  ]){
    for (const key of GEAR_KEYS){
      const field = gearField(key, who);
      const size = String(booking[field] ?? '').trim();
      if (size) out.push({
        key,
        who,
        field,
        label: gearLabel(key, who),
        size,
        checked: true
      });
    }
  }
  return out;
}
/**
 * Normalizuje položky z klienta: doplní field/key/who/label. `defaultChecked`
 * platí pro položky bez `checked` (kiosk = předáno, appka = nezaškrtnuto).
 */ export function normalizeAccessories(raw, defaultChecked) {
  if (!Array.isArray(raw)) return [];
  const out = [];
  for (const a of raw.slice(0, 40)){
    if (!a || typeof a !== 'object') continue;
    const it = a;
    let key = GEAR_KEYS.includes(String(it.key)) ? it.key : undefined;
    let who = it.who === 'rider' || it.who === 'passenger' ? it.who : undefined;
    let field = typeof it.field === 'string' && it.field ? it.field : undefined;
    if (field) {
      const p = parseGearField(field);
      if (p) {
        key = p.key;
        who = p.who;
      } else field = undefined;
    }
    if (!field && key && who) field = gearField(key, who);
    const size = String(it.size ?? '').trim().slice(0, 20);
    const label = String(it.label ?? '').trim().slice(0, 80) || (key && who ? gearLabel(key, who) : '');
    if (!label && !size) continue;
    out.push({
      key,
      who,
      field,
      label,
      size,
      checked: typeof it.checked === 'boolean' ? it.checked : defaultChecked,
      ...it.added === true ? {
        added: true
      } : {}
    });
  }
  return out;
}
/**
 * Změny výbavy k propsání do rezervace. Bere se JEN položka s vazbou na sloupec:
 * - převzatá (checked) a v rezervaci je: jiná velikost z číselníku `accessory_types.sizes` → nová velikost;
 * - NEpřevzatá a v rezervaci je: sloupec → NULL (odebrána z rezervace) + `a.removed = true`;
 *   poslaná `size` je původní z rezervace a NIKDY se nepropisuje;
 * - převzatá a v rezervaci NENÍ = výbava NAVÍC (2026-10-05, zadání majitele: „co si vezme navíc, musí být v
 *   protokolu“): `a.extra = true` (dokument „navíc“); do rezervace se zapíše JEN s `allowAdd` (kiosk ≥ 1.2.5 s přístupem
 *   do šatny — jinak by přidání vyvolalo nový kód šatny uprostřed převzetí) a velikostí z číselníku. Ceny / booking_extras
 *   se nemění (doúčtování placené výbavy navíc řeší Velín ručně).
 * `allowRemove=false` (starý klient bez opt-in `form.gear_remove`): nepřevzatá
 * položka je jen ☐ v dokumentu jako dřív — rezervace se nemění.
 * `markExtra` (kiosk s `form.gear_add`): „navíc“ v dokumentu; jiný klient výbavu navíc přidat neumí → bez označení.
 */ export async function resolveGearUpdates(admin, booking, items, allowRemove = true, allowAdd = false, markExtra = allowAdd) {
  const linked = items.filter((a)=>a.field && a.key && a.who);
  const res = {
    updates: {},
    changes: {}
  };
  if (!linked.length) return res;
  const allowed = new Map();
  if (linked.some((a)=>a.checked && a.size)) {
    const { data: types } = await admin.from('accessory_types').select('key, sizes, is_active').in('key', [
      ...GEAR_KEYS
    ]);
    for (const t of types || []){
      if (t.is_active === false) continue;
      const s = allowed.get(t.key) ?? new Set();
      for (const x of t.sizes || [])s.add(String(x).trim());
      allowed.set(t.key, s);
    }
  }
  const currentOf = (a)=>String(booking[a.field] ?? '').trim();
  for (const a of linked){
    const field = a.field;
    const current = currentOf(a);
    const changeKey = a.who === 'passenger' ? `passenger_${a.key}` : a.key;
    if (!current) {
      if (allowAdd && a.checked && a.size && allowed.get(a.key)?.has(a.size)) {
        res.updates[field] = a.size;
        res.changes[changeKey] = {
          from: null,
          to: a.size
        };
      }
      continue;
    }
    if (!a.checked) {
      if (allowRemove) {
        res.updates[field] = null;
        res.changes[changeKey] = {
          from: current,
          to: null
        };
      }
      continue;
    }
    const sizes = allowed.get(a.key);
    if (!a.size || !sizes || !sizes.has(a.size)) continue; // mimo číselník → jen zobrazit
    if (current === a.size) continue;
    res.updates[field] = a.size;
    res.changes[changeKey] = {
      from: current,
      to: a.size
    };
  }
  // `removed` až podle VÝSLEDKU (duplicitní položka s týmž `field` = poslední vyhrává): sloupec je po tomto
  // podpisu NULL — odebrán teď, nebo už dřív (opakovaný podpis po 5xx; 1. pokus ho odebral i se záznamem historie;
  // klient posílá u nepřevzaté položky původní velikost — bez ní položka v rezervaci nikdy nebyla).
  if (allowRemove) {
    for (const a of linked){
      if (!a.checked && (res.updates[a.field] === null || !currentOf(a) && a.size)) a.removed = true;
    }
  }
  // navíc = v rezervaci není, nebo ji tam doplnil už 1. pokus téhož podpisu (klient ji posílá s `added`)
  if (markExtra) {
    for (const a of linked)if (a.checked && a.size && (a.added === true || !currentOf(a))) a.extra = true;
  }
  return res;
}
