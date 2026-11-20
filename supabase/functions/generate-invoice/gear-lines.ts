// ===== generate-invoice/gear-lines.ts =====
// Výpůjčka JEN výbavy (bookings.booking_kind = 'gear', DESIGN-GEAR §3.4, 2026-10-23):
// ZF / DP / rozdílový doklad bez řádku „Pronájem motorky“ a bez přistavení. Položky
// z bookings.gear_lines (tvar _gear_rental_quote().lines: {key, kind set|item, label,
// includes[], sizes{key: velikost}, price_per_day, total}) — „Půjčení výbavy: <název>
// (<velikosti>) — <termín>“, množství = dny (VČETNĚ prvního i posledního dne, jako ceník
// výpůjčky), cena = Kč/den. Poukaz / dorovnání karty doplní index.ts stejně jako u motorky.
// Nesedí-li součet řádků na cenu rezervace (ruční zásah, úprava), srovná ho řádek korekce
// → doklad vždy = zaplacená částka. Účetní text dokladu zůstává česky (jako motorka).
// deno-lint-ignore no-explicit-any
// Názvy kusů v kompletu (malými písmeny, jako dřívější e-shop doklad výpůjčky).
const PART_CS = {
  helmet: 'helma',
  jacket: 'bunda',
  pants: 'kalhoty',
  gloves: 'rukavice',
  boots: 'boty'
};
export const GEAR_DAY_LABEL = 'Půjčení výbavy';
export const GEAR_SUBJECT = 'výpůjčka výbavy';
export function isGearBooking(b) {
  return !!b && b.booking_kind === 'gear';
}
/** Počet dní výpůjčky včetně prvního i posledního dne (z kalendářních dat). */ export function gearDays(start, end) {
  const s = Date.parse(String(start || '').slice(0, 10) + 'T00:00:00Z');
  const e = Date.parse(String(end || '').slice(0, 10) + 'T00:00:00Z');
  if (!Number.isFinite(s) || !Number.isFinite(e) || e < s) return 1;
  return Math.round((e - s) / 86400000) + 1;
}
/** Velikosti řádku: kus → „M“, komplet → „helma M, bunda L, …“ (pořadí dle includes).
 *  Kus nepřevzatý při předání (`not_taken`, submit-handover-protocol; řádek se platí dál) → „nepřevzato“. */ export function gearSizesText(line) {
  const sizes = line && typeof line.sizes === 'object' && line.sizes ? line.sizes : {};
  const nt = Array.isArray(line?.not_taken) ? line.not_taken.map(String) : [];
  const keys = Array.isArray(line?.includes) && line.includes.length ? line.includes.map(String) : [
    ...Object.keys(sizes),
    ...nt.filter((k)=>!(k in sizes))
  ];
  const parts = [];
  for (const k of keys){
    const v = nt.includes(k) ? 'nepřevzato' : String(sizes[k] ?? '').trim();
    if (!v) continue;
    parts.push(line?.kind === 'set' || keys.length > 1 ? `${PART_CS[k] || k} ${v}` : v);
  }
  return parts.join(', ');
}
const r2 = (n)=>Math.round((Number(n) || 0) * 100) / 100;
/**
 * Položky pronájmu výbavy pro běžný doklad. `expectedRental` = cena pronájmu před slevami
 * (stejný vzorec jako baseRental u motorky: total − výbava − doprava + slevy − dorovnání).
 */ export function gearInvoiceItems(b, o) {
  const days = gearDays(b.start_date, b.end_date);
  const period = `${o.startDate} – ${o.endDate}`;
  const items = [];
  const lines = Array.isArray(b.gear_lines) ? b.gear_lines : [];
  for (const ln of lines){
    if (!ln || typeof ln !== 'object') continue;
    const ppd = Number(ln.price_per_day);
    if (!Number.isFinite(ppd)) continue;
    const sz = gearSizesText(ln);
    const label = String(ln.label || ln.key || 'výbava').trim();
    items.push({
      description: `${GEAR_DAY_LABEL}: ${label}${sz ? ` (${sz})` : ''} — ${period}`,
      qty: days,
      unit_price: r2(ppd)
    });
  }
  const expected = r2(o.expectedRental);
  if (!items.length) {
    // Bez naceněných řádků (ruční řádek z Velína) — jediný řádek jako u motorky.
    items.push({
      description: `${GEAR_DAY_LABEL} — ${period}`,
      qty: days,
      unit_price: r2(expected / days)
    });
    const diff1 = r2(expected - r2(expected / days) * days);
    if (Math.abs(diff1) >= 0.01) items.push({
      description: 'Korekce ceny výpůjčky',
      qty: 1,
      unit_price: diff1
    });
    return items;
  }
  const sum = r2(items.reduce((s, it)=>s + it.unit_price * it.qty, 0));
  const diff = r2(expected - sum);
  if (Math.abs(diff) >= 0.01) items.push({
    description: 'Korekce ceny výpůjčky',
    qty: 1,
    unit_price: diff
  });
  return items;
}
/** Zdroj denních cen pro rozpis přidaných/odebraných dnů u rozdílového dokladu (calcPriceBreakdown). */ export function gearDaySource(b) {
  const ppd = Number(b?.gear_per_day);
  if (Number.isFinite(ppd) && ppd > 0) return {
    price_weekday: ppd
  };
  const lines = Array.isArray(b?.gear_lines) ? b.gear_lines : [];
  const sum = lines.reduce((s, l)=>s + (Number(l?.price_per_day) || 0), 0);
  return sum > 0 ? {
    price_weekday: sum
  } : null;
}
