// ===== process-payment/app-change-price.ts =====
// D1 (oprava 2026-10-16): app formát úpravy (DB názvy sloupců, payment_screen.dart)
// nese cenu spočítanou KLIENTEM (change.total_price). Odpustit doplatek do 1 Kč bez
// karty jde jen po SERVEROVÉM přecenění — tady se změna termínu / motorky / času
// vyzvednutí převede na dry-run apply_booking_changes (stejně jako web, pod JWT
// zákazníka). Změna, kterou takhle ocenit nejde (místo, výbava, slevy…), se
// neodpouští: platí se kartou 15 Kč (dorovnání na dokladu).
const day = (v)=>String(v ?? '').slice(0, 10);
const hm = (v)=>v == null ? '' : String(v).slice(0, 5);
const money = (v)=>Math.round((Number(v) || 0) * 100) / 100;
const text = (v)=>String(v ?? '').trim().toLowerCase().replace(/\s+/g, ' ');
/** Klíče, které dry-run neocení — smí jen zůstat beze změny. */ const MUST_MATCH = [
  [
    'delivery_fee',
    (a, b)=>money(a) === money(b)
  ],
  [
    'extras_price',
    (a, b)=>money(a) === money(b)
  ],
  [
    'discount_amount',
    (a, b)=>money(a) === money(b)
  ],
  [
    'loyalty_discount_amount',
    (a, b)=>money(a) === money(b)
  ],
  [
    'pickup_method',
    (a, b)=>text(a) === text(b)
  ],
  [
    'pickup_address',
    (a, b)=>text(a) === text(b)
  ],
  [
    'return_method',
    (a, b)=>text(a) === text(b)
  ],
  [
    'return_address',
    (a, b)=>text(a) === text(b)
  ]
];
/** Klíče bez vlivu na cenu, nebo je přepočítá server sám. */ const IGNORED = new Set([
  'return_time',
  'late_pickup_discount_amount',
  'total_price',
  'pickup_lat',
  'pickup_lng',
  'return_lat',
  'return_lng'
]);
const PRICED = new Set([
  'start_date',
  'end_date',
  'moto_id',
  'pickup_time'
]);
/** Parametry dry-runu apply_booking_changes, nebo null (změnu takhle ocenit nejde). */ export function appChangeParams(c, cur) {
  for (const k of Object.keys(c)){
    if (k.startsWith('_') || IGNORED.has(k) || PRICED.has(k)) continue;
    const rule = MUST_MATCH.find(([key])=>key === k);
    if (!rule || !rule[1](c[k], cur[k])) return null;
  }
  const p = {};
  if (c.start_date != null && day(c.start_date) !== day(cur.start_date)) p.p_new_start = day(c.start_date);
  if (c.end_date != null && day(c.end_date) !== day(cur.end_date)) p.p_new_end = day(c.end_date);
  if (typeof c.moto_id === 'string' && c.moto_id && c.moto_id !== cur.moto_id) p.p_new_moto_id = c.moto_id;
  if (c.pickup_time != null && hm(c.pickup_time) !== hm(cur.pickup_time)) p.p_new_pickup_time = hm(c.pickup_time);
  return Object.keys(p).length ? p : null;
}
/** Serverová cena app změny: {net, newTotal} nebo null (nejde ocenit / dry-run selhal). */ export async function priceAppChange(userClient, bookingId, c, cur) {
  const params = appChangeParams(c, cur);
  if (!params) return null;
  try {
    const { data, error } = await userClient.rpc('apply_booking_changes', {
      p_booking_id: bookingId,
      p_dry_run: true,
      ...params
    });
    if (error || !data || data.success !== true || !Number.isFinite(Number(data.net_diff))) return null;
    const nt = data.new_total;
    return {
      net: money(data.net_diff),
      newTotal: nt != null && Number.isFinite(Number(nt)) ? money(nt) : null
    };
  } catch  {
    return null;
  }
}
