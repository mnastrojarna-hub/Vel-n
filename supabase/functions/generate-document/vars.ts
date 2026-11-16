// Mapa {{proměnných}} dokumentu z rezervace. `docLang` = jazyk TEXTU dokumentu (čerstvý překlad),
// u závazného českého textu 'cs' → hodnoty i formát beze změny proti dřívějšku. `lang` = jazyk
// zákazníka (doména odkazů {{company_web}}). Popisky: labels.ts (audit EDGE-DOC-09).
import { fmtDateL, fmtPriceL, labelsFor, priceWords, rentalPeriod } from './labels.ts';
/**
 * Seznam zapůjčeného příslušenství z rezervace — řádky řidiče podle vyplněných `*_size`,
 * u spolujezdce druhá sada, u dětské motorky (`license_required === 'N'`) přípona „(dětská velikost)“.
 * Vrací HTML tabulku pro {{accessories_block}} a text pro {{accessories}}.
 */ export function buildAccessoriesBlock(booking, moto, docLang) {
  const L = labelsFor(docLang);
  const isChild = String(moto?.license_required || '').toUpperCase() === 'N';
  const childSuffix = isChild ? ` (${L.child})` : '';
  const keys = [
    'helmet',
    'jacket',
    'pants',
    'boots',
    'gloves'
  ];
  const rows = [];
  const textParts = [];
  const td = 'padding:6px 8px;border:1px solid #ddd;text-align:left';
  const addRow = (label, size)=>{
    rows.push(`<tr><td style="${td};background:#f8faf9;font-weight:600">${label}${childSuffix}</td><td style="${td}">${size}</td><td style="${td};text-align:center;width:60px">☐</td></tr>`);
    textParts.push(`${label} ${size}`);
  };
  let has = false;
  for (const k of keys){
    const size = booking?.[`${k}_size`];
    if (size) {
      addRow(`${L.gear[k]} (${L.rider})`, String(size));
      has = true;
    }
  }
  for (const k of keys){
    const size = booking?.[`passenger_${k}_size`];
    if (size) {
      addRow(`${L.gear[k]} (${L.passenger})`, String(size));
      has = true;
    }
  }
  if (!has) return {
    html: `<p style="font-size:12px">${L.noGear}</p>`,
    text: L.none
  };
  const th = 'padding:6px 8px;border:1px solid #ddd;text-align:left;background:#f0f7ff;font-weight:700;font-size:10px;text-transform:uppercase';
  const html = `<table class="checklist" style="width:100%;border-collapse:collapse;font-size:11px;margin:6px 0;border:1px solid #ddd"><tr><th style="${th}">${L.thItem}</th><th style="${th}">${L.thSize}</th><th style="${th}">${L.thHanded}</th></tr>${rows.join('')}</table>`;
  return {
    html,
    text: textParts.join(', ')
  };
}
export function buildVars(c) {
  const { booking, customer, moto, docLang: dl } = c;
  const L = labelsFor(dl);
  const d = (v)=>fmtDateL(v, dl);
  const p = (n)=>fmtPriceL(n, dl);
  const accessories = buildAccessoriesBlock(booking, moto, dl);
  const extrasHtml = c.extras.map((e)=>`${e.name}${e.quantity > 1 ? ' ×' + e.quantity : ''} — ${p(e.unit_price)} Kč`).join(', ');
  // Inkluzivní počet dní — ceník počítá start i end den (5. 5. → 6. 5. = 2 dny).
  const days = Math.max(1, Math.floor((new Date(booking.end_date).getTime() - new Date(booking.start_date).getTime()) / 86400000) + 1);
  const baseRental = (booking.total_price || 0) - (booking.extras_price || 0) - (booking.delivery_fee || 0) + (booking.discount_amount || 0);
  return {
    customer_name: customer.full_name || '—',
    customer_email: customer.email || '',
    customer_phone: customer.phone || '',
    customer_address: [
      customer.street,
      customer.city,
      customer.zip,
      customer.country
    ].filter(Boolean).join(', ') || '',
    customer_street: customer.street || '',
    customer_city: customer.city || '',
    customer_zip: customer.zip || '',
    customer_country: customer.country || L.country,
    customer_ico: customer.ico || '',
    customer_dic: customer.dic || '',
    customer_license: customer.license_number || '',
    customer_license_expiry: d(customer.license_expiry),
    customer_license_group: Array.isArray(customer.license_group) ? customer.license_group.join(', ') : customer.license_group || '',
    customer_dob: d(customer.date_of_birth),
    customer_id_number: customer.id_number || '',
    // Platnost OP (Mindee OCR) — bez skenu prázdné, potvrzuje se při převzetí.
    customer_id_expiry: d(customer.id_verified_until || customer.passport_verified_until),
    moto_model: moto.model || '—',
    moto_brand: moto.brand || '',
    moto_spz: moto.spz || '',
    moto_vin: moto.vin || '',
    moto_year: String(moto.year || ''),
    moto_category: moto.category || '',
    moto_engine: moto.engine_cc ? `${moto.engine_cc} ccm` : '',
    moto_power: moto.power_kw ? `${moto.power_kw} kW` : '',
    moto_color: moto.color || '',
    start_date: d(booking.start_date),
    end_date: d(booking.end_date),
    pickup_time: c.pickupTime,
    days: String(days),
    total_price: p(booking.total_price || 0),
    daily_rate: p(days > 0 ? Math.round(baseRental / days) : 0),
    rental_price: p(baseRental),
    extras_price: p(booking.extras_price || 0),
    extras_list: extrasHtml || L.none,
    delivery_fee: p(booking.delivery_fee || 0),
    discount_amount: p(booking.discount_amount || 0),
    discount_code: booking.discount_code || '',
    deposit: p(moto.deposit_amount || booking.deposit || 0),
    insurance: p(moto.insurance_price || 0),
    insurance_type: booking.insurance_type || L.insuranceBasic,
    pickup_method: booking.pickup_method === 'delivery' ? L.delivery : L.atBranch,
    pickup_address: booking.pickup_address || c.branchAddress || '',
    return_method: booking.return_method === 'delivery' ? L.collection : L.atBranch,
    return_address: booking.return_address || c.branchAddress || '',
    branch_name: c.branchName,
    branch_address: c.branchAddress,
    booking_id: c.bookingId.slice(-8),
    booking_number: c.bookingId.slice(-8).toUpperCase(),
    today: d(new Date().toISOString()),
    company_name: c.company.name,
    company_address: c.company.address,
    company_ico: c.company.ico,
    company_dic: c.company.dic,
    company_phone: '+420 774 256 271',
    company_email: 'info@motogo24.cz',
    company_web: c.webLabel,
    company_bank: 'mBank',
    company_account: '670100-2225851630/6210',
    // start_time = čas vyzvednutí, end_time = vrácení (samoobsluha 00:01 / 12:00 → 24:00, viz index.ts)
    start_time: c.startTime,
    end_time: c.endTime,
    rental_period: rentalPeriod(days, dl),
    total_price_words: priceWords(booking.total_price || 0, dl),
    pickup_location: booking.pickup_address || c.branchAddress || '',
    return_location: booking.return_address || c.branchAddress || '',
    mileage: String(booking.mileage_start || ''),
    technical_state: '',
    today_time: new Date().toLocaleTimeString(L.locale, {
      hour: '2-digit',
      minute: '2-digit'
    }),
    accessories_block: accessories.html,
    accessories: accessories.text
  };
}
