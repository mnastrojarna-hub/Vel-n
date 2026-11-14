// Texty předávacího protokolu výpůjčky JEN výbavy (booking_kind = 'gear', 2026-10-23) — cs + 7 jazyků.
// Klíče `gr_*` se v i18n.ts přimíchají k HO_CS a k cizím slovníkům (makeTr je pak zná i dvojjazyčně).
// Termíny shodně s motorkovým protokolem (i18n-a.ts / i18n-b.ts): pobočka, šatna, výbava.
export const HO_GEAR_CS = {
  gr_title: 'Předávací protokol — výbava',
  gr_heading: 'PŘEDÁVACÍ PROTOKOL — ZAPŮJČENÁ VÝBAVA',
  gr_parties: 'Smluvní strany a předmět nájmu',
  gr_subject: 'Předmět nájmu',
  gr_subject_val: 'Motorkářská výbava (bez motocyklu)',
  gr_branch: 'Pobočka',
  gr_identity: 'Ověření nájemce',
  gr_identity_kiosk: 'kód šatny této rezervace zadaný na displeji pobočky',
  gr_identity_app: 'přihlášení do aplikace MotoGo24',
  gr_chk_gear_condition: 'Výbava předána čistá, kompletní a bez poškození',
  gr_chk_gear_fit: 'Velikosti vyzkoušeny a odpovídají',
  gr_chk_gear_return: 'Nájemce poučen o vrácení (termín, pobočka, šatna)',
  gr_damageAt: 'Poškození výbavy při předání',
  gr_day_one: 'den',
  gr_day_few: 'dny',
  gr_day_many: 'dní',
  gr_day_other: 'dní'
};
export const HO_GEAR = {
  en: {
    gr_title: 'Handover protocol — gear',
    gr_heading: 'HANDOVER PROTOCOL — RENTED GEAR',
    gr_parties: 'Contracting parties and subject of rental',
    gr_subject: 'Subject of rental',
    gr_subject_val: 'Motorcycle riding gear (without a motorcycle)',
    gr_branch: 'Branch',
    gr_identity: 'Renter verification',
    gr_identity_kiosk: 'locker code of this booking entered on the branch display',
    gr_identity_app: 'signed in to the MotoGo24 app',
    gr_chk_gear_condition: 'Gear handed over clean, complete and undamaged',
    gr_chk_gear_fit: 'Sizes tried on and fitting',
    gr_chk_gear_return: 'Renter instructed on the return (date, branch, locker)',
    gr_damageAt: 'Damage to the gear at handover',
    gr_day_one: 'day',
    gr_day_other: 'days'
  },
  de: {
    gr_title: 'Übergabeprotokoll — Ausrüstung',
    gr_heading: 'ÜBERGABEPROTOKOLL — GELIEHENE AUSRÜSTUNG',
    gr_parties: 'Vertragsparteien und Mietgegenstand',
    gr_subject: 'Mietgegenstand',
    gr_subject_val: 'Motorradausrüstung (ohne Motorrad)',
    gr_branch: 'Filiale',
    gr_identity: 'Überprüfung des Mieters',
    gr_identity_kiosk: 'Schließfachcode dieser Buchung am Display der Filiale eingegeben',
    gr_identity_app: 'Anmeldung in der MotoGo24-App',
    gr_chk_gear_condition: 'Ausrüstung sauber, vollständig und unbeschädigt übergeben',
    gr_chk_gear_fit: 'Größen anprobiert und passend',
    gr_chk_gear_return: 'Mieter über die Rückgabe informiert (Termin, Filiale, Schließfach)',
    gr_damageAt: 'Schäden an der Ausrüstung bei Übergabe',
    gr_day_one: 'Tag',
    gr_day_other: 'Tage'
  },
  es: {
    gr_title: 'Protocolo de entrega — equipo',
    gr_heading: 'PROTOCOLO DE ENTREGA — EQUIPO ALQUILADO',
    gr_parties: 'Partes contratantes y objeto del alquiler',
    gr_subject: 'Objeto del alquiler',
    gr_subject_val: 'Equipo de motorista (sin motocicleta)',
    gr_branch: 'Sucursal',
    gr_identity: 'Verificación del arrendatario',
    gr_identity_kiosk: 'código de taquilla de esta reserva introducido en la pantalla de la sucursal',
    gr_identity_app: 'sesión iniciada en la app MotoGo24',
    gr_chk_gear_condition: 'Equipo entregado limpio, completo y sin daños',
    gr_chk_gear_fit: 'Tallas probadas y adecuadas',
    gr_chk_gear_return: 'Arrendatario informado sobre la devolución (fecha, sucursal, taquilla)',
    gr_damageAt: 'Daños en el equipo en la entrega',
    gr_day_one: 'día',
    gr_day_other: 'días'
  },
  fr: {
    gr_title: 'Protocole de remise — équipement',
    gr_heading: 'PROTOCOLE DE REMISE — ÉQUIPEMENT LOUÉ',
    gr_parties: 'Parties contractantes et objet de la location',
    gr_subject: 'Objet de la location',
    gr_subject_val: 'Équipement de motard (sans moto)',
    gr_branch: 'Agence',
    gr_identity: 'Vérification du locataire',
    gr_identity_kiosk: 'code du casier de cette réservation saisi sur l’écran de l’agence',
    gr_identity_app: 'connexion à l’application MotoGo24',
    gr_chk_gear_condition: 'Équipement remis propre, complet et sans dommage',
    gr_chk_gear_fit: 'Tailles essayées et adaptées',
    gr_chk_gear_return: 'Locataire informé du retour (date, agence, casier)',
    gr_damageAt: 'Dommages à l’équipement lors de la remise',
    gr_day_one: 'jour',
    gr_day_other: 'jours'
  },
  nl: {
    gr_title: 'Overdrachtsprotocol — uitrusting',
    gr_heading: 'OVERDRACHTSPROTOCOL — GEHUURDE UITRUSTING',
    gr_parties: 'Contractpartijen en huurobject',
    gr_subject: 'Huurobject',
    gr_subject_val: 'Motoruitrusting (zonder motor)',
    gr_branch: 'Vestiging',
    gr_identity: 'Verificatie van de huurder',
    gr_identity_kiosk: 'kluiscode van deze boeking ingevoerd op het scherm van de vestiging',
    gr_identity_app: 'ingelogd in de MotoGo24-app',
    gr_chk_gear_condition: 'Uitrusting schoon, compleet en onbeschadigd overhandigd',
    gr_chk_gear_fit: 'Maten gepast en passend',
    gr_chk_gear_return: 'Huurder geïnformeerd over het terugbrengen (datum, vestiging, kluis)',
    gr_damageAt: 'Schade aan de uitrusting bij overdracht',
    gr_day_one: 'dag',
    gr_day_other: 'dagen'
  },
  pl: {
    gr_title: 'Protokół przekazania — wyposażenie',
    gr_heading: 'PROTOKÓŁ PRZEKAZANIA — WYPOŻYCZONE WYPOSAŻENIE',
    gr_parties: 'Strony umowy i przedmiot najmu',
    gr_subject: 'Przedmiot najmu',
    gr_subject_val: 'Odzież motocyklowa (bez motocykla)',
    gr_branch: 'Oddział',
    gr_identity: 'Weryfikacja najemcy',
    gr_identity_kiosk: 'kod szafki tej rezerwacji wpisany na ekranie oddziału',
    gr_identity_app: 'zalogowanie w aplikacji MotoGo24',
    gr_chk_gear_condition: 'Wyposażenie przekazane czyste, kompletne i bez uszkodzeń',
    gr_chk_gear_fit: 'Rozmiary przymierzone i pasują',
    gr_chk_gear_return: 'Najemca pouczony o zwrocie (termin, oddział, szafka)',
    gr_damageAt: 'Uszkodzenia wyposażenia przy przekazaniu',
    gr_day_one: 'dzień',
    gr_day_few: 'dni',
    gr_day_many: 'dni',
    gr_day_other: 'dnia'
  },
  uk: {
    gr_title: 'Протокол передачі — спорядження',
    gr_heading: 'ПРОТОКОЛ ПЕРЕДАЧІ — ОРЕНДОВАНЕ СПОРЯДЖЕННЯ',
    gr_parties: 'Сторони договору та предмет оренди',
    gr_subject: 'Предмет оренди',
    gr_subject_val: 'Мотоспорядження (без мотоцикла)',
    gr_branch: 'Філія',
    gr_identity: 'Перевірка орендаря',
    gr_identity_kiosk: 'код шафки цього бронювання, введений на дисплеї філії',
    gr_identity_app: 'вхід у застосунок MotoGo24',
    gr_chk_gear_condition: 'Спорядження передано чистим, повним і без пошкоджень',
    gr_chk_gear_fit: 'Розміри приміряно, вони підходять',
    gr_chk_gear_return: 'Орендаря поінформовано про повернення (термін, філія, шафка)',
    gr_damageAt: 'Пошкодження спорядження при передачі',
    gr_day_one: 'день',
    gr_day_few: 'дні',
    gr_day_many: 'днів',
    gr_day_other: 'дня'
  }
};
const LOCALE = {
  cs: 'cs-CZ',
  en: 'en-GB',
  de: 'de-DE',
  es: 'es-ES',
  fr: 'fr-FR',
  nl: 'nl-NL',
  pl: 'pl-PL',
  uk: 'uk-UA'
};
/** „3 dny“ / „3 days“ … v jazyce dokumentu (Intl.PluralRules + slovník výše). */ export function gearDaysLabel(days, lang) {
  const d = lang === 'cs' || !HO_GEAR[lang] ? HO_GEAR_CS : HO_GEAR[lang];
  let cat = 'other';
  try {
    cat = new Intl.PluralRules(LOCALE[lang] || 'cs-CZ').select(days);
  } catch  {}
  return `${days} ${d[`gr_day_${cat}`] || d.gr_day_other}`;
}
/** Datum („15. 6. 2026“ / „15/06/2026“…) v jazyce dokumentu, kalendářní den v Praze. */ export function gearDateLabel(v, lang) {
  if (!v) return '';
  try {
    return new Date(String(v)).toLocaleDateString(LOCALE[lang] || 'cs-CZ', {
      timeZone: 'Europe/Prague'
    });
  } catch  {
    return String(v);
  }
}
