// Výpůjčka JEN výbavy (2026-10-23) — POSLEDNÍ záchrana, když gear šablona ve Velínu chybí
// nebo je vypnutá (zdroj pravdy = email_templates gear_*, seed 20261023d). Minimální CZ (tykání)
// + EN text (ostatní jazyky EN); NIKDY motorková šablona / text. Každé použití → debug_log
// `email_template_fallback`, ať je výpadek šablony vidět. Placeholdery = tytéž jako v šablonách.
// deno-lint-ignore no-explicit-any
const P = (s)=>`<p>${s}</p>`;
const BTN = (href, label)=>`<div style="text-align:center;margin:24px 0"><a href="{{${href}}}" style="display:inline-block;background:#74FB71;color:#1a2e22;padding:14px 28px;border-radius:25px;text-decoration:none;font-weight:800;font-size:15px">${label}</a></div>`;
const SUMMARY = {
  cs: '<table style="width:100%;border-collapse:collapse;margin:16px 0;font-size:13px">' + '<tr><td style="padding:6px 12px 6px 0;color:#6b7280">Rezervace:</td><td style="padding:6px 0;font-weight:700">{{booking_number}}</td></tr>' + '<tr><td style="padding:6px 12px 6px 0;color:#6b7280">Termín:</td><td style="padding:6px 0;font-weight:700">{{gear_period}} ({{gear_days}})</td></tr>' + '<tr><td style="padding:6px 12px 6px 0;color:#6b7280">Pobočka:</td><td style="padding:6px 0;font-weight:700">{{branch_name}}, {{branch_address}}</td></tr>' + '<tr><td style="padding:6px 12px 6px 0;color:#6b7280">Cena:</td><td style="padding:6px 0;font-weight:700">{{total_price}} Kč</td></tr></table>' + '<p style="margin:0"><strong>Výbava:</strong></p>{{gear_items_block}}',
  en: '<table style="width:100%;border-collapse:collapse;margin:16px 0;font-size:13px">' + '<tr><td style="padding:6px 12px 6px 0;color:#6b7280">Booking:</td><td style="padding:6px 0;font-weight:700">{{booking_number}}</td></tr>' + '<tr><td style="padding:6px 12px 6px 0;color:#6b7280">Dates:</td><td style="padding:6px 0;font-weight:700">{{gear_period}} ({{gear_days}})</td></tr>' + '<tr><td style="padding:6px 12px 6px 0;color:#6b7280">Branch:</td><td style="padding:6px 0;font-weight:700">{{branch_name}}, {{branch_address}}</td></tr>' + '<tr><td style="padding:6px 12px 6px 0;color:#6b7280">Price:</td><td style="padding:6px 0;font-weight:700">{{total_price}} CZK</td></tr></table>' + '<p style="margin:0"><strong>Gear:</strong></p>{{gear_items_block}}'
};
const HI = {
  cs: P('Ahoj,'),
  en: P('Hi,')
};
const BYE = {
  cs: P('Tým MotoGo24'),
  en: P('MOTO GO 24 Team')
};
// [předmět, úvod, CTA odkaz, CTA text, dovětek]
const T = {
  gear_booking_reserved: {
    cs: [
      'Výpůjčka výbavy č. {{booking_number}} je potvrzená — MOTO GO 24',
      'tvoje výpůjčka výbavy je potvrzená. Výbavu vrať nejpozději poslední den výpůjčky na stejnou pobočku.',
      'manage_url',
      'Upravit rezervaci',
      '{{door_codes_block}}'
    ],
    en: [
      'Gear rental #{{booking_number}} confirmed — MOTO GO 24',
      'your gear rental is confirmed. Please return the gear to the same branch by the last day of the rental.',
      'manage_url',
      'Manage booking',
      '{{door_codes_block}}'
    ]
  },
  gear_invoice_payment_receipt: {
    cs: [
      'Platba přijata — výpůjčka výbavy č. {{booking_number}}',
      'děkujeme, platbu za výpůjčku výbavy jsme přijali. Ještě prosím nahraj doklad totožnosti (občanka nebo pas).',
      'docs_url',
      'Nahrát doklad totožnosti',
      ''
    ],
    en: [
      'Payment received — gear rental #{{booking_number}}',
      'thank you, we have received the payment for your gear rental. Please upload an identity document (ID card or passport).',
      'docs_url',
      'Upload identity document',
      ''
    ]
  },
  gear_booking_missing_docs: {
    cs: [
      'Nahraj doklad totožnosti — výpůjčka výbavy č. {{booking_number}}',
      'k výpůjčce výbavy nám ještě chybí doklad totožnosti (občanka nebo pas).',
      'docs_url',
      'Nahrát doklad totožnosti',
      ''
    ],
    en: [
      'Upload your ID — gear rental #{{booking_number}}',
      'we still need an identity document (ID card or passport) for your gear rental.',
      'docs_url',
      'Upload identity document',
      ''
    ]
  },
  gear_booking_abandoned: {
    cs: [
      'Dokonči výpůjčku výbavy č. {{booking_number}} — MOTO GO 24',
      'výpůjčka výbavy zatím není zaplacená. Dokončit ji můžeš tady:',
      'pay_url',
      'Dokončit výpůjčku',
      ''
    ],
    en: [
      'Complete your gear rental #{{booking_number}} — MOTO GO 24',
      'your gear rental has not been paid yet. You can complete it here:',
      'pay_url',
      'Complete rental',
      ''
    ]
  },
  gear_door_codes: {
    cs: [
      'Přístupové kódy — výpůjčka výbavy č. {{booking_number}}',
      'k tvé výpůjčce výbavy jsou připravené přístupové kódy:',
      '',
      '',
      '{{door_codes_block}}'
    ],
    en: [
      'Access codes — gear rental #{{booking_number}}',
      'the access codes for your gear rental are ready:',
      '',
      '',
      '{{door_codes_block}}'
    ]
  },
  gear_booking_modified: {
    cs: [
      'Změna výpůjčky výbavy č. {{booking_number}} — MOTO GO 24',
      'tvoje výpůjčka výbavy byla upravena.',
      'manage_url',
      'Zobrazit rezervaci',
      '{{changes_block}}{{door_codes_block}}'
    ],
    en: [
      'Gear rental #{{booking_number}} changed — MOTO GO 24',
      'your gear rental has been changed.',
      'manage_url',
      'View booking',
      '{{changes_block}}{{door_codes_block}}'
    ]
  },
  gear_booking_cancelled: {
    cs: [
      'Výpůjčka výbavy č. {{booking_number}} je stornovaná — MOTO GO 24',
      'potvrzujeme storno tvé výpůjčky výbavy. Důvod: {{cancellation_reason}}.',
      '',
      '',
      '<p>Vrácená částka: <strong>{{refund_amount}} Kč</strong> ({{refund_percent}} %).</p>'
    ],
    en: [
      'Gear rental #{{booking_number}} cancelled — MOTO GO 24',
      'we confirm the cancellation of your gear rental. Reason: {{cancellation_reason}}.',
      '',
      '',
      '<p>Refunded amount: <strong>{{refund_amount}} CZK</strong> ({{refund_percent}} %).</p>'
    ]
  },
  gear_booking_completed: {
    cs: [
      'Díky za výpůjčku výbavy č. {{booking_number}} — MOTO GO 24',
      'výbavu máme zpátky a výpůjčka je ukončená. Díky! Budeme rádi za tvé hodnocení.',
      'google_review_url',
      'Napsat hodnocení',
      ''
    ],
    en: [
      'Thank you for gear rental #{{booking_number}} — MOTO GO 24',
      'we have the gear back and your rental is complete. Thank you! We would appreciate your review.',
      'google_review_url',
      'Write a review',
      ''
    ]
  }
};
const GENERIC = {
  cs: [
    'Výpůjčka výbavy č. {{booking_number}} — MOTO GO 24',
    'posíláme informace k tvé výpůjčce výbavy.',
    'manage_url',
    'Zobrazit rezervaci',
    ''
  ],
  en: [
    'Gear rental #{{booking_number}} — MOTO GO 24',
    'here is an update on your gear rental.',
    'manage_url',
    'View booking',
    ''
  ]
};
/** Jazyk fallback textu: čeština, jinak angličtina (de/es/fr/nl/pl/uk vlastní fallback nemají). */ export const gearFallbackLang = (lang)=>lang === 'cs' ? 'cs' : 'en';
// Odkazy zůstávají v jazyce zákazníka (web se mu otevře v jeho jazyce), text proměnných jde s textem mailu.
const LINK_VARS = [
  'docs_url',
  'pay_url',
  'resume_link',
  'manage_url',
  'site_url',
  'google_review_url'
];
/** Proměnné pro fallback text: gear proměnné (termín, dny, výbava, kódy, změny, důvod) znovu v jazyce
 *  fallbacku, ať anglický text nemá německé „1 Tag“ / „Nicht angegeben“; odkazy beze změny. */ export function gearFallbackVars(lang, vars, varsFor) {
  const L = gearFallbackLang(lang);
  if (L === lang) return vars;
  const out = {
    ...vars,
    ...varsFor(L)
  };
  for (const k of LINK_VARS)if (k in vars) out[k] = vars[k];
  return out;
}
/** Nevyplněné šablonové tělo + předmět (s {{placeholdery}}) pro gear renderType. */ export function gearFallbackTemplate(renderType, lang, vars = {}) {
  const L = gearFallbackLang(lang);
  const [subject, intro, href, cta, extraRaw] = (Object.hasOwn(T, renderType) ? T[renderType] : GENERIC)[L];
  // Storno bez vratky: řádek s částkou jen když nějaká je (prázdné refund_amount → bez řádku).
  const extra = renderType === 'gear_booking_cancelled' && !vars.refund_amount ? '' : extraRaw;
  const body = HI[L] + P(intro) + SUMMARY[L] + extra + (href && vars[href] !== '' ? BTN(href, cta) : '') + BYE[L];
  return {
    subject,
    body
  };
}
/** Šablona chybí → záznam do debug_log (mail přesto odejde z fallbacku). */ export async function logGearTemplateFallback(supabase, source, data) {
  try {
    await supabase.from('debug_log').insert({
      source,
      action: 'email_template_fallback',
      component: 'gear-email',
      status: 'warning',
      request_data: data
    });
  } catch  {}
}
/** send-email: šablona chybí / vypnutá → zkusí se náhradní slug (protokol výbavy → obecný protokol). */ export const EMAIL_SLUG_FALLBACKS = {
  handover_protocol_gear_sent: 'handover_protocol_sent'
};
