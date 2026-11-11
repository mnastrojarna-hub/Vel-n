// qr-payment — texty pro zákazníka v 8 jazycích (audit W2 / WEB-PAY-01).
// Do přeložené šablony (send-email přeloží booking_qr_payment[_surcharge] do jazyka
// zákazníka) se dřív dosazovaly ČESKÉ proměnné → smíšený mail. Čeština je 1:1 s původním
// kódem (ověřuje texts_test.ts). Částky, účet, IBAN, VS a formát SPD se tu NEmění.
//
// `lead` šablony pokračuje textem šablony: „{{lead}} za rezervaci #X…“ a u doplatku
// „{{lead}} #X se váže doplatek…“ → cizojazyčné leady jsou krátké a bez zájmen
// (tykání/vykání určuje přeložená šablona), aby navazovaly na běžné znění překladu.
export const QR_LANGS = [
  'cs',
  'en',
  'de',
  'es',
  'fr',
  'nl',
  'pl',
  'uk'
];
/** 'uk-UA' / 'EN' → 'uk' / 'en'; nepodporovaný nebo prázdný → null. */ export function normalizeQrLang(v) {
  const s = String(v ?? '').trim().toLowerCase().slice(0, 2);
  return QR_LANGS.includes(s) ? s : null;
}
/** Platný `locale` z požadavku má přednost (web = jazyk stránky, Velín = zvolený jazyk mailu),
 *  jinak jazyk rezervace (bookings.language), jinak 'cs'. */ export function pickQrLang(locale, bookingLang) {
  return normalizeQrLang(locale) ?? normalizeQrLang(bookingLang) ?? 'cs';
}
const withName = (name, named, plain)=>name ? name + ', ' + named : plain;
export const QR_TEXTS = {
  cs: {
    thanks: (n)=>n ? n + ', děkujeme' : 'Děkujeme',
    surchargeLead: (n)=>(n ? n + ', k' : 'K') + ' úpravě vaší rezervace',
    invoicePrefix: 'č. ',
    subject: (bn)=>'Platební údaje k rezervaci #' + bn + ' — QR / bankovní převod',
    subjectSurcharge: (bn)=>'Doplatek k rezervaci #' + bn + ' — QR / bankovní převod',
    spdSurcharge: 'doplatek'
  },
  en: {
    thanks: (n)=>withName(n, 'thank you', 'Thank you'),
    surchargeLead: (n)=>withName(n, 'the change to your booking', 'The change to your booking'),
    invoicePrefix: 'No. ',
    subject: (bn)=>'Payment details for booking #' + bn + ' — QR / bank transfer',
    subjectSurcharge: (bn)=>'Additional payment for booking #' + bn + ' — QR / bank transfer',
    spdSurcharge: 'surcharge'
  },
  de: {
    thanks: (n)=>withName(n, 'vielen Dank', 'Vielen Dank'),
    surchargeLead: (n)=>withName(n, 'mit der Änderung der Reservierung', 'Mit der Änderung der Reservierung'),
    invoicePrefix: 'Nr. ',
    subject: (bn)=>'Zahlungsdaten zur Reservierung #' + bn + ' — QR / Banküberweisung',
    subjectSurcharge: (bn)=>'Nachzahlung zur Reservierung #' + bn + ' — QR / Banküberweisung',
    spdSurcharge: 'Nachzahlung'
  },
  es: {
    thanks: (n)=>withName(n, 'gracias', 'Gracias'),
    surchargeLead: (n)=>withName(n, 'la modificación de la reserva', 'La modificación de la reserva'),
    invoicePrefix: 'n.º ',
    subject: (bn)=>'Datos de pago de la reserva #' + bn + ' — QR / transferencia bancaria',
    subjectSurcharge: (bn)=>'Pago adicional de la reserva #' + bn + ' — QR / transferencia bancaria',
    spdSurcharge: 'suplemento'
  },
  fr: {
    thanks: (n)=>withName(n, 'merci', 'Merci'),
    surchargeLead: (n)=>withName(n, 'la modification de la réservation', 'La modification de la réservation'),
    invoicePrefix: 'n° ',
    subject: (bn)=>'Coordonnées de paiement de la réservation #' + bn + ' — QR / virement bancaire',
    subjectSurcharge: (bn)=>'Supplément pour la réservation #' + bn + ' — QR / virement bancaire',
    spdSurcharge: 'supplement'
  },
  nl: {
    thanks: (n)=>withName(n, 'bedankt', 'Bedankt'),
    surchargeLead: (n)=>withName(n, 'aan de wijziging van de reservering', 'Aan de wijziging van de reservering'),
    invoicePrefix: 'nr. ',
    subject: (bn)=>'Betaalgegevens voor reservering #' + bn + ' — QR / bankoverschrijving',
    subjectSurcharge: (bn)=>'Bijbetaling voor reservering #' + bn + ' — QR / bankoverschrijving',
    spdSurcharge: 'bijbetaling'
  },
  pl: {
    thanks: (n)=>withName(n, 'dziękujemy', 'Dziękujemy'),
    surchargeLead: (n)=>withName(n, 'ze zmianą rezerwacji', 'Ze zmianą rezerwacji'),
    invoicePrefix: 'nr ',
    subject: (bn)=>'Dane do płatności za rezerwację #' + bn + ' — QR / przelew bankowy',
    subjectSurcharge: (bn)=>'Dopłata do rezerwacji #' + bn + ' — QR / przelew bankowy',
    spdSurcharge: 'doplata'
  },
  uk: {
    thanks: (n)=>withName(n, 'дякуємо', 'Дякуємо'),
    surchargeLead: (n)=>withName(n, 'зі зміною бронювання', 'Зі зміною бронювання'),
    invoicePrefix: '№ ',
    subject: (bn)=>'Платіжні дані до бронювання #' + bn + ' — QR / банківський переказ',
    subjectSurcharge: (bn)=>'Доплата до бронювання #' + bn + ' — QR / банківський переказ',
    spdSurcharge: 'doplata'
  }
};
/** bookings.language (NOT NULL, výchozí 'cs'); chyba → null (pak 'cs'). Nikdy nehází. */ // deno-lint-ignore no-explicit-any
export async function loadBookingLanguage(sb, bookingId) {
  try {
    const { data } = await sb.from('bookings').select('language').eq('id', bookingId).maybeSingle();
    return data?.language ?? null;
  } catch  {
    return null;
  }
}
/** {{invoice_suffix}} — „ (č. ZF-2026-0001)“ / prázdné bez čísla ZF. */ export function invoiceSuffix(lang, invoiceNumber) {
  return invoiceNumber ? ' (' + QR_TEXTS[lang].invoicePrefix + invoiceNumber + ')' : '';
}
/** Zpráva pro příjemce v QR (SPD MSG): „MotoGo24 [doplatek ]ABCD1234“ — jen ASCII bez „*“. */ export function spdMessage(lang, surcharge, bookingNumber) {
  const raw = 'MotoGo24 ' + (surcharge ? QR_TEXTS[lang].spdSurcharge + ' ' : '') + bookingNumber;
  return raw.replace(/[^\x20-\x29\x2B-\x7E]/g, '');
}
