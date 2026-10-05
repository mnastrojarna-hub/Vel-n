/* MotoGo24 kiosk — kód, který EXISTUJE, ale už nic neotevře nebo začne platit do 24 h (2026-10-05, kiosk_resolve_code
   `reason`, CONTRACT §16): nahrazený / zneplatněný / prošlý / ještě neplatný → srozumitelná hláška a BEZ PIN lockoutu
   (controller_codes.KNOWN_CODE_ERRORS). Stejných 8 jazyků jako i18n.js; přes MG.i18n.extend() do `et` (titulek)
   a `es` (text, slot {s} = telefon podpory). Česky displej ukazuje hlášku jednotky (`message`). */
'use strict';
window.MG = window.MG || {};

MG.i18n.extend({
  cs: {
    et: { code_revoked: 'Kód už neplatí', code_not_yet_valid: 'Kód ještě neplatí',
      code_expired: 'Platnost kódu skončila' },
    es: { code_revoked: 'Rezervace byla zrušena nebo ukončena, případně kód zneplatnila obsluha. Platné kódy najdete v aplikaci MotoGo24, případně volejte podporu: {s}.',
      code_not_yet_valid: 'Kód platí od začátku vaší rezervace. Zkuste to prosím v čase vyzvednutí.',
      code_expired: 'Rezervace už proběhla. Aktuální kódy najdete v aplikaci MotoGo24.' } },
  en: {
    et: { code_revoked: 'This code is no longer valid', code_not_yet_valid: 'Code not valid yet',
      code_expired: 'Code has expired' },
    es: { code_revoked: 'The booking was cancelled or has ended, or the code was revoked by staff. Find your valid codes in the MotoGo24 app or call support: {s}.',
      code_not_yet_valid: 'The code is valid from the start of your booking. Please try again at your pickup time.',
      code_expired: 'The booking is already over. Find your current codes in the MotoGo24 app.' } },
  de: {
    et: { code_revoked: 'Dieser Code gilt nicht mehr', code_not_yet_valid: 'Code noch nicht gültig',
      code_expired: 'Code abgelaufen' },
    es: { code_revoked: 'Die Buchung wurde storniert oder ist beendet, oder das Personal hat den Code gesperrt. Gültige Codes finden Sie in der MotoGo24-App oder rufen Sie den Support an: {s}.',
      code_not_yet_valid: 'Der Code gilt ab Beginn Ihrer Buchung. Bitte versuchen Sie es zur Abholzeit erneut.',
      code_expired: 'Die Buchung ist bereits vorbei. Aktuelle Codes finden Sie in der MotoGo24-App.' } },
  es: {
    et: { code_revoked: 'Este código ya no es válido', code_not_yet_valid: 'El código aún no es válido',
      code_expired: 'El código ha caducado' },
    es: { code_revoked: 'La reserva fue cancelada o ha terminado, o el personal anuló el código. Encontrará los códigos válidos en la app MotoGo24 o llame a soporte: {s}.',
      code_not_yet_valid: 'El código es válido desde el inicio de su reserva. Inténtelo de nuevo a la hora de recogida.',
      code_expired: 'La reserva ya ha terminado. Encontrará los códigos actuales en la app MotoGo24.' } },
  fr: {
    et: { code_revoked: 'Ce code n’est plus valable', code_not_yet_valid: 'Code pas encore valable',
      code_expired: 'Code expiré' },
    es: { code_revoked: 'La réservation a été annulée ou est terminée, ou le personnel a désactivé le code. Vos codes valables sont dans l’application MotoGo24, sinon appelez l’assistance : {s}.',
      code_not_yet_valid: 'Le code est valable à partir du début de votre réservation. Réessayez à l’heure de retrait.',
      code_expired: 'La réservation est déjà terminée. Vos codes actuels sont dans l’application MotoGo24.' } },
  nl: {
    et: { code_revoked: 'Deze code is niet meer geldig', code_not_yet_valid: 'Code nog niet geldig',
      code_expired: 'Code verlopen' },
    es: { code_revoked: 'De reservering is geannuleerd of afgelopen, of het personeel heeft de code ingetrokken. Geldige codes vindt u in de MotoGo24-app, of bel support: {s}.',
      code_not_yet_valid: 'De code is geldig vanaf het begin van uw reservering. Probeer het op uw ophaaltijd opnieuw.',
      code_expired: 'De reservering is al voorbij. Uw actuele codes vindt u in de MotoGo24-app.' } },
  pl: {
    et: { code_revoked: 'Ten kod jest już nieważny', code_not_yet_valid: 'Kod jeszcze nie obowiązuje',
      code_expired: 'Kod wygasł' },
    es: { code_revoked: 'Rezerwacja została anulowana lub zakończona albo obsługa unieważniła kod. Ważne kody znajdziesz w aplikacji MotoGo24 lub zadzwoń do wsparcia: {s}.',
      code_not_yet_valid: 'Kod obowiązuje od początku Twojej rezerwacji. Spróbuj ponownie w godzinie odbioru.',
      code_expired: 'Rezerwacja już się zakończyła. Aktualne kody znajdziesz w aplikacji MotoGo24.' } },
  uk: {
    et: { code_revoked: 'Цей код уже недійсний', code_not_yet_valid: 'Код ще не діє',
      code_expired: 'Термін дії коду минув' },
    es: { code_revoked: 'Бронювання скасовано або завершено, або персонал анулював код. Дійсні коди знайдете в застосунку MotoGo24 або зателефонуйте в підтримку: {s}.',
      code_not_yet_valid: 'Код діє з початку вашого бронювання. Спробуйте, будь ласка, у час отримання.',
      code_expired: 'Бронювання вже завершилося. Актуальні коди знайдете в застосунку MotoGo24.' } },
});
