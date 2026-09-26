// Výbava v předávacím protokolu — položky `form.accessories[]`
// ({key, who, field?, label?, size, checked}) ↔ sloupce bookings.<key>_size /
// passenger_<key>_size. Položka bez vazby (jen label+size, staré appky) se
// pouze vykreslí; položka s vazbou a velikostí z číselníku accessory_types
// se PŘED podpisem propíše do rezervace (zákazník si u displeje/v appce
// upravil velikost).
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
      checked: typeof it.checked === 'boolean' ? it.checked : defaultChecked
    });
  }
  return out;
}
/**
 * Změněné velikosti k propsání do rezervace. Bere se JEN položka s vazbou na
 * sloupec, jejíž velikost je v číselníku `accessory_types.sizes` daného typu,
 * a jen tam, kde rezervace už velikost má (výbavu nelze u protokolu přidat —
 * to by vyvolalo nový kód šatny uprostřed převzetí).
 */ export async function resolveSizeUpdates(admin, booking, items) {
  const linked = items.filter((a)=>a.field && a.key && a.who && a.size);
  const res = {
    updates: {},
    changes: {}
  };
  if (!linked.length) return res;
  const { data: types } = await admin.from('accessory_types').select('key, sizes, is_active').in('key', [
    ...GEAR_KEYS
  ]);
  const allowed = new Map();
  for (const t of types || []){
    if (t.is_active === false) continue;
    const s = allowed.get(t.key) ?? new Set();
    for (const x of t.sizes || [])s.add(String(x).trim());
    allowed.set(t.key, s);
  }
  for (const a of linked){
    const sizes = allowed.get(a.key);
    if (!sizes || !sizes.has(a.size)) continue; // mimo číselník → jen zobrazit
    const current = String(booking[a.field] ?? '').trim();
    if (!current || current === a.size) continue;
    res.updates[a.field] = a.size;
    res.changes[a.who === 'passenger' ? `passenger_${a.key}` : a.key] = {
      from: current,
      to: a.size
    };
  }
  return res;
}
