// Výpůjčka JEN výbavy jako rezervace (bookings.booking_kind='gear', 2026-10-23) — e-maily.
// send-booking-email / send-cancellation-email: když je rezervace gear, tělo + předmět jdou
// z Velín šablony `gear_<typ>` (renderType; web_ varianta má přednost), NIKDY z motorkové
// šablony / textu. Logovaný slug zůstává dle `type` (dedup cronů/triggerů). Proměnné níže =
// kontrakt DESIGN-GEAR §3.3 (seed šablon 20261023d), v jazyce zákazníka, HTML-escapované.
import { daysLabel, esc, fmtDay, gearItemsText, gearTexts, kc, renderGearChangesBlock, renderGearItemsBlock } from './email-gear-blocks.ts';
/** Typ mailu → gear šablona. Zbytek 'gear_' + typ (bez šablony → gear fallback, ne motorka). */ export const GEAR_RENDER_TYPES = {
  booking_reserved: 'gear_booking_reserved',
  invoice_payment_receipt: 'gear_invoice_payment_receipt',
  booking_missing_docs: 'gear_booking_missing_docs',
  booking_abandoned: 'gear_booking_abandoned',
  booking_abandoned_full: 'gear_booking_abandoned',
  door_codes: 'gear_door_codes',
  booking_modified: 'gear_booking_modified',
  booking_cancelled: 'gear_booking_cancelled',
  booking_completed: 'gear_booking_completed'
};
export function gearRenderType(t) {
  // Object.hasOwn — typ 'constructor'/'toString' nesmí trefit prototyp objektu.
  if (Object.hasOwn(GEAR_RENDER_TYPES, t)) return GEAR_RENDER_TYPES[t];
  return t.startsWith('gear_') ? t : 'gear_' + t;
}
/** Přílohy, když gear šablona ve Velínu chybí (= výchozí hodnoty seedu 20261023d). */ export const GEAR_DEFAULT_ATTACHMENTS = {
  gear_booking_reserved: [
    'Smlouva',
    'VOP'
  ],
  gear_invoice_payment_receipt: [
    'ZF',
    'DP'
  ],
  gear_booking_cancelled: [
    'Dobropis'
  ],
  gear_booking_completed: [
    'KF'
  ]
};
const SIZE_KEYS = [
  'helmet',
  'jacket',
  'pants',
  'gloves',
  'boots'
];
/** Datum (timestamptz i 'YYYY-MM-DD') → den v Praze 'YYYY-MM-DD' (web ukládá UTC půlnoc, Velín pražskou). */ export function pragueDay(v) {
  const s = String(v || '');
  if (!s) return '';
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return s;
  const d = new Date(s);
  if (Number.isNaN(d.getTime())) return s.slice(0, 10);
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Prague',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  }).format(d);
}
const hhmm = (v)=>{
  const m = /^(\d{1,2}):(\d{2})/.exec(String(v || ''));
  return m ? `${m[1].padStart(2, '0')}:${m[2]}` : '';
};
const dayDiff = (a, b)=>Math.round((Date.parse(b + 'T00:00:00Z') - Date.parse(a + 'T00:00:00Z')) / 86400000);
const CORE_COLS = 'id, booking_kind, status, payment_status, user_id, start_date, end_date, total_price, branch_id';
const GEAR_COLS = CORE_COLS + ', pickup_time, return_time, gear_lines, helmet_size, jacket_size, pants_size, gloves_size, boots_size';
/** Chyba „sloupec neexistuje“ (PostgREST 42703 / PGRST204). */ // deno-lint-ignore no-explicit-any
export function isMissingColumnError(e) {
  const code = String(e?.code || '');
  return code === '42703' || code === 'PGRST204' || /column .* does not exist/i.test(String(e?.message || ''));
}
// deno-lint-ignore no-explicit-any
const selectBooking = async (supabase, id, cols)=>{
  try {
    return await supabase.from('bookings').select(cols).eq('id', id).maybeSingle();
  } catch (e) {
    return {
      data: null,
      error: e
    };
  }
};
/** Načte gear rezervaci; null = není gear (nebo DB ještě bez sloupce booking_kind → motorkový mail beze změny).
 *  Jiná (přechodná) chyba DB NESMÍ gear mail přepnout na motorkový text (DESIGN §3.3): 1× opakovat, pak
 *  sonda se základními sloupci; selže-li i ta (ne kvůli chybějícímu booking_kind), rozhodne `kindHint`
 *  z payloadu volajícího (SQL volání posílají booking_kind:'gear'). */ export async function loadGearBooking(supabase, bookingId, kindHint) {
  if (!bookingId) return null;
  try {
    let { data: b, error } = await selectBooking(supabase, bookingId, GEAR_COLS);
    if (error && !isMissingColumnError(error)) ({ data: b, error } = await selectBooking(supabase, bookingId, GEAR_COLS));
    if (error) {
      // Plný select padl → sonda: jen dlouholeté sloupce + booking_kind (gear údaje mohou chybět).
      const probe = await selectBooking(supabase, bookingId, CORE_COLS);
      if (probe.error) {
        if (isMissingColumnError(probe.error) || kindHint !== 'gear') return null;
        b = {
          id: bookingId,
          booking_kind: 'gear'
        } // jen víme, že je gear: text bez detailů, nikdy motorka
        ;
      } else b = probe.data;
    }
    if (!b || b.booking_kind !== 'gear') return null;
    const g = {
      id: String(b.id),
      status: String(b.status || ''),
      paymentStatus: String(b.payment_status || ''),
      start: pragueDay(b.start_date),
      end: pragueDay(b.end_date),
      days: 1,
      pickupTime: hhmm(b.pickup_time),
      returnTime: hhmm(b.return_time),
      totalPrice: Number(b.total_price) || 0,
      lines: Array.isArray(b.gear_lines) ? b.gear_lines : [],
      sizes: Object.fromEntries(SIZE_KEYS.map((k)=>[
          k,
          b[`${k}_size`] ? String(b[`${k}_size`]) : null
        ])),
      labels: {},
      branch: null,
      customerName: ''
    };
    const span = g.start && g.end ? dayDiff(g.start, g.end) + 1 : 1;
    g.days = Number.isFinite(span) ? Math.max(1, span) : 1;
    // Gear už je jisté — dílčí výpadek níže mail nepřepne na motorku, jen chybí údaj.
    if (b.branch_id) try {
      const { data: br } = await supabase.from('branches').select('id, name, address, city, type').eq('id', b.branch_id).maybeSingle();
      if (br) g.branch = {
        id: String(br.id),
        name: String(br.name || ''),
        address: String(br.address || ''),
        city: String(br.city || ''),
        type: String(br.type || '')
      };
    } catch  {}
    try {
      const { data: pr } = await supabase.from('gear_rental_prices').select('key, label, translations');
      for (const p of pr || []){
        g.labels[p.key] = {
          cs: p.label
        };
        for (const [l, v] of Object.entries(p.translations || {}))if (v?.label) g.labels[p.key][l] = v.label;
      }
    } catch  {}
    if (b.user_id) {
      try {
        const { data: pf } = await supabase.from('profiles').select('full_name').eq('id', b.user_id).maybeSingle();
        g.customerName = String(pf?.full_name || '');
      } catch  {}
    }
    return g;
  } catch  {
    return null;
  }
}
/** Odkazy výpůjčky (web /pujceni-obleceni); cizí jazyk = ?lang (web lokalizuje slug sám, 301 se zachovaným dotazem). */ export function gearLinks(g, lang, site) {
  const base = site.replace(/\/+$/, '');
  const q = lang === 'cs' ? '' : `&lang=${lang}`;
  const pay = `${base}/pujceni-obleceni?resume=${g.id}${q}`;
  return {
    pay,
    docs: `${base}/pujceni-obleceni?resume=${g.id}&docs=1${q}`,
    manage: `${base}/upravit-rezervaci${lang === 'cs' ? '' : `?lang=${lang}`}`,
    base
  };
}
const fmtPrice = (n)=>(Number(n) || 0).toLocaleString('cs-CZ', {
    minimumFractionDigits: 0
  });
/** {{changes_block}} z payloadu triggeru úpravy (original_* vs. nový stav) + `changes.gear.{from,to}` z RPC. */ export function buildGearChanges(g, lang, p) {
  const t = gearTexts(lang);
  const rows = [];
  const os = pragueDay(p.original_start_date), oe = pragueDay(p.original_end_date);
  if (os && oe) rows.push([
    t.chPeriod,
    `${fmtDay(os, lang)} – ${fmtDay(oe, lang)}`,
    `${fmtDay(g.start, lang)} – ${fmtDay(g.end, lang)}`
  ]);
  if (p.original_pickup_time !== undefined) rows.push([
    t.chPickup,
    hhmm(p.original_pickup_time),
    hhmm(p.pickup_time) || g.pickupTime
  ]);
  if (p.original_return_time !== undefined) rows.push([
    t.chReturn,
    hhmm(p.original_return_time),
    hhmm(p.return_time) || g.returnTime
  ]);
  const ch = p.changes && typeof p.changes === 'object' ? p.changes.gear : null;
  if (ch && (ch.from !== undefined || ch.to !== undefined)) {
    rows.push([
      t.chItems,
      gearItemsText(ch.from, g.labels, lang),
      gearItemsText(ch.to, g.labels, lang)
    ]);
  }
  // Přesun pobočky z Velínu (admin_update_gear_booking, FIX-R1): changes.branch {from, to} = názvy poboček
  const brc = p.changes && typeof p.changes === 'object' ? p.changes.branch : null;
  if (brc && (brc.from || brc.to)) rows.push([
    t.chBranch,
    String(brc.from || ''),
    String(brc.to || g.branch?.name || '')
  ]);
  if (p.original_total_price != null && p.original_total_price !== '') {
    rows.push([
      t.chTotal,
      kc(Number(p.original_total_price)),
      kc(g.totalPrice)
    ]);
  }
  return renderGearChangesBlock(lang, rows);
}
/** Proměnné gear šablon (bez {{door_codes_block}} — ten skládá send-booking-email/gear-booking.ts). */ export function buildGearVars(g, lang, o) {
  const l = gearLinks(g, lang, o.site);
  const br = g.branch;
  return {
    customer_name: esc(o.customerName || g.customerName),
    booking_number: g.id.slice(-8).toUpperCase(),
    branch_name: esc(br?.name || ''),
    branch_address: esc([
      br?.address,
      br?.city
    ].filter(Boolean).join(', ')),
    gear_period: `${fmtDay(g.start, lang)} – ${fmtDay(g.end, lang)}`,
    gear_days: daysLabel(lang, g.days),
    start_date: fmtDay(g.start, lang),
    end_date: fmtDay(g.end, lang),
    pickup_time: g.pickupTime,
    return_time: g.returnTime,
    gear_items_block: renderGearItemsBlock(g.lines, g.labels, lang, g.sizes),
    total_price: fmtPrice(g.totalPrice),
    docs_url: l.docs,
    pay_url: l.pay,
    resume_link: l.pay,
    manage_url: l.manage,
    site_url: l.base,
    changes_block: o.payload ? buildGearChanges(g, lang, o.payload) : ''
  };
}
/** Předmět = čistý text: bez HTML bloků (kód brány nikdy do předmětu), jména bez escapování. */ export function gearSubjectVars(v, g, customerName) {
  return {
    ...v,
    door_codes_block: '',
    gate_codes_block: '',
    gear_items_block: '',
    changes_block: '',
    customer_name: customerName || g.customerName,
    branch_name: g.branch?.name || '',
    branch_address: [
      g.branch?.address,
      g.branch?.city
    ].filter(Boolean).join(', ')
  };
}
/** Důvod storna pro šablonu (escapovaný). Prázdný / systémové české texty → v jazyce zákazníka. */ export function gearCancellationReason(reason, lang) {
  const r = String(reason || '').trim();
  const t = gearTexts(lang);
  if (!r || r === 'Neuvedeno') return esc(t.notSpecified);
  if (r === 'Stornováno zákazníkem') return esc(t.byCustomer);
  return esc(r);
}
