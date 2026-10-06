/* MotoGo24 kiosk — kód, který EXISTUJE, ale už nic neotevře nebo začne platit do 24 h (2026-10-05, kiosk_resolve_code
   `reason`, CONTRACT §16): nahrazený / zneplatněný / prošlý / ještě neplatný → srozumitelná hláška a BEZ PIN lockoutu
   (controller_codes.KNOWN_CODE_ERRORS). Od 1.2.7 `code_no_gear` = kód šatny stažený, protože rezervace nemá vybranou
   výbavu (RPC `no_gear: true`, models.CODE_NO_GEAR) → „šatnu nepotřebujete, zadejte kód k motorce“. Stejných 8 jazyků jako
   i18n.js; přes MG.i18n.extend() do `et` (titulek) a `es` (text, slot {s} = telefon podpory). Česky displej ukazuje hlášku
   jednotky (`message`). */
'use strict';
window.MG = window.MG || {};

MG.i18n.extend({
  cs: {
    et: { code_revoked: 'Kód už neplatí', code_not_yet_valid: 'Kód ještě neplatí',
      code_expired: 'Platnost kódu skončila', code_no_gear: 'Šatnu nepotřebujete' },
    es: { code_revoked: 'Rezervace byla zrušena nebo ukončena, případně kód zneplatnila obsluha. Platné kódy najdete v aplikaci MotoGo24, případně volejte podporu: {s}.',
      code_not_yet_valid: 'Kód platí až od 0:00 v den začátku vaší rezervace. Přijďte prosím v den vyzvednutí.',
      code_expired: 'Rezervace už proběhla. Aktuální kódy najdete v aplikaci MotoGo24.',
      code_no_gear: 'Rezervace nemá zapůjčenou výbavu — šatnu nepotřebujete. Zadejte kód k motorce.' } },
  en: {
    et: { code_revoked: 'This code is no longer valid', code_not_yet_valid: 'Code not valid yet',
      code_expired: 'Code has expired', code_no_gear: 'No locker room needed' },
    es: { code_revoked: 'The booking was cancelled or has ended, or the code was revoked by staff. Find your valid codes in the MotoGo24 app or call support: {s}.',
      code_not_yet_valid: 'The code is valid only from 0:00 on the first day of your booking. Please come on your pickup day.',
      code_expired: 'The booking is already over. Find your current codes in the MotoGo24 app.',
      code_no_gear: 'Your booking has no rented gear — you don’t need the locker room. Enter the motorcycle code.' } },
  de: {
    et: { code_revoked: 'Dieser Code gilt nicht mehr', code_not_yet_valid: 'Code noch nicht gültig',
      code_expired: 'Code abgelaufen', code_no_gear: 'Umkleide nicht nötig' },
    es: { code_revoked: 'Die Buchung wurde storniert oder ist beendet, oder das Personal hat den Code gesperrt. Gültige Codes finden Sie in der MotoGo24-App oder rufen Sie den Support an: {s}.',
      code_not_yet_valid: 'Der Code gilt erst ab 0:00 Uhr am ersten Tag Ihrer Buchung. Bitte kommen Sie am Abholtag.',
      code_expired: 'Die Buchung ist bereits vorbei. Aktuelle Codes finden Sie in der MotoGo24-App.',
      code_no_gear: 'Ihre Buchung enthält keine Leihausrüstung — Sie brauchen die Umkleide nicht. Geben Sie den Motorrad-Code ein.' } },
  es: {
    et: { code_revoked: 'Este código ya no es válido', code_not_yet_valid: 'El código aún no es válido',
      code_expired: 'El código ha caducado', code_no_gear: 'No necesita el vestuario' },
    es: { code_revoked: 'La reserva fue cancelada o ha terminado, o el personal anuló el código. Encontrará los códigos válidos en la app MotoGo24 o llame a soporte: {s}.',
      code_not_yet_valid: 'El código es válido solo desde las 0:00 del primer día de su reserva. Venga el día de la recogida.',
      code_expired: 'La reserva ya ha terminado. Encontrará los códigos actuales en la app MotoGo24.',
      code_no_gear: 'Su reserva no incluye equipo de alquiler — no necesita el vestuario. Introduzca el código de la moto.' } },
  fr: {
    et: { code_revoked: 'Ce code n’est plus valable', code_not_yet_valid: 'Code pas encore valable',
      code_expired: 'Code expiré', code_no_gear: 'Pas besoin du vestiaire' },
    es: { code_revoked: 'La réservation a été annulée ou est terminée, ou le personnel a désactivé le code. Vos codes valables sont dans l’application MotoGo24, sinon appelez l’assistance : {s}.',
      code_not_yet_valid: 'Le code n’est valable qu’à partir de 0:00 le premier jour de votre réservation. Venez le jour du retrait.',
      code_expired: 'La réservation est déjà terminée. Vos codes actuels sont dans l’application MotoGo24.',
      code_no_gear: 'Votre réservation ne comprend pas d’équipement loué — vous n’avez pas besoin du vestiaire. Saisissez le code moto.' } },
  nl: {
    et: { code_revoked: 'Deze code is niet meer geldig', code_not_yet_valid: 'Code nog niet geldig',
      code_expired: 'Code verlopen', code_no_gear: 'Kleedkamer niet nodig' },
    es: { code_revoked: 'De reservering is geannuleerd of afgelopen, of het personeel heeft de code ingetrokken. Geldige codes vindt u in de MotoGo24-app, of bel support: {s}.',
      code_not_yet_valid: 'De code is pas geldig vanaf 0:00 op de eerste dag van uw reservering. Kom op uw ophaaldag.',
      code_expired: 'De reservering is al voorbij. Uw actuele codes vindt u in de MotoGo24-app.',
      code_no_gear: 'Uw reservering bevat geen gehuurde uitrusting — u hebt de kleedkamer niet nodig. Voer de motorcode in.' } },
  pl: {
    et: { code_revoked: 'Ten kod jest już nieważny', code_not_yet_valid: 'Kod jeszcze nie obowiązuje',
      code_expired: 'Kod wygasł', code_no_gear: 'Szatnia niepotrzebna' },
    es: { code_revoked: 'Rezerwacja została anulowana lub zakończona albo obsługa unieważniła kod. Ważne kody znajdziesz w aplikacji MotoGo24 lub zadzwoń do wsparcia: {s}.',
      code_not_yet_valid: 'Kod obowiązuje dopiero od 0:00 w pierwszym dniu Twojej rezerwacji. Przyjdź w dniu odbioru.',
      code_expired: 'Rezerwacja już się zakończyła. Aktualne kody znajdziesz w aplikacji MotoGo24.',
      code_no_gear: 'Rezerwacja nie obejmuje wypożyczonego wyposażenia — szatnia nie jest potrzebna. Wpisz kod do motocykla.' } },
  uk: {
    et: { code_revoked: 'Цей код уже недійсний', code_not_yet_valid: 'Код ще не діє',
      code_expired: 'Термін дії коду минув', code_no_gear: 'Роздягальня не потрібна' },
    es: { code_revoked: 'Бронювання скасовано або завершено, або персонал анулював код. Дійсні коди знайдете в застосунку MotoGo24 або зателефонуйте в підтримку: {s}.',
      code_not_yet_valid: 'Код діє лише з 0:00 у перший день вашого бронювання. Приходьте, будь ласка, в день отримання.',
      code_expired: 'Бронювання вже завершилося. Актуальні коди знайдете в застосунку MotoGo24.',
      code_no_gear: 'Бронювання не містить орендованого екіпірування — роздягальня вам не потрібна. Введіть код мотоцикла.' } },
});
