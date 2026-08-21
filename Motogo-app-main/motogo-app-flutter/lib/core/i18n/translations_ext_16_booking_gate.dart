/// Booking gate (2026-08-22): povinné údaje profilu + povinné souhlasy před
/// vytvořením rezervace. Adresa (ulice, město, PSČ) je povinná vždy; číslo a
/// platnost ŘP jen u motorek vyžadujících ŘP (ne dětské 'N'). Foto dokladů
/// povinné NENÍ — lze doplnit dodatečně. `{fields}` = výčet chybějících polí.
/// Merged into the global translations map.
const Map<String, Map<String, String>> translationsExt16BookingGate = {
  'cs': {
    'validationMissingProfile': 'Pro dokončení rezervace nejdřív doplňte v profilu: {fields}. Foto dokladů můžete nahrát i později.',
    'validationLicenseExpired': 'Váš řidičský průkaz má propadlou platnost. Aktualizujte platnost ŘP v profilu.',
    'completeProfileBtn': 'Doplnit v profilu',
    'consentsRequired': 'Pro pokračování potvrďte povinné souhlasy.',
  },
  'en': {
    'validationMissingProfile': 'To complete the booking, first fill in your profile: {fields}. Document photos can be uploaded later.',
    'validationLicenseExpired': 'Your driver\'s license has expired. Update its validity in your profile.',
    'completeProfileBtn': 'Complete profile',
    'consentsRequired': 'Please confirm the required consents to continue.',
  },
  'de': {
    'validationMissingProfile': 'Um die Buchung abzuschließen, ergänzen Sie zuerst Ihr Profil: {fields}. Dokumentfotos können später hochgeladen werden.',
    'validationLicenseExpired': 'Ihr Führerschein ist abgelaufen. Aktualisieren Sie die Gültigkeit in Ihrem Profil.',
    'completeProfileBtn': 'Profil vervollständigen',
    'consentsRequired': 'Bitte bestätigen Sie die erforderlichen Einwilligungen, um fortzufahren.',
  },
  'es': {
    'validationMissingProfile': 'Para completar la reserva, primero rellena en tu perfil: {fields}. Las fotos de los documentos se pueden subir más tarde.',
    'validationLicenseExpired': 'Tu permiso de conducir está caducado. Actualiza su validez en tu perfil.',
    'completeProfileBtn': 'Completar perfil',
    'consentsRequired': 'Confirma los consentimientos obligatorios para continuar.',
  },
  'fr': {
    'validationMissingProfile': 'Pour finaliser la réservation, complétez d\'abord votre profil : {fields}. Les photos des documents peuvent être ajoutées plus tard.',
    'validationLicenseExpired': 'Votre permis de conduire est expiré. Mettez à jour sa validité dans votre profil.',
    'completeProfileBtn': 'Compléter le profil',
    'consentsRequired': 'Veuillez confirmer les consentements obligatoires pour continuer.',
  },
  'nl': {
    'validationMissingProfile': 'Vul eerst uw profiel aan om de reservering af te ronden: {fields}. Foto\'s van documenten kunt u later uploaden.',
    'validationLicenseExpired': 'Uw rijbewijs is verlopen. Werk de geldigheid bij in uw profiel.',
    'completeProfileBtn': 'Profiel aanvullen',
    'consentsRequired': 'Bevestig de verplichte toestemmingen om door te gaan.',
  },
  'pl': {
    'validationMissingProfile': 'Aby dokończyć rezerwację, najpierw uzupełnij w profilu: {fields}. Zdjęcia dokumentów można dodać później.',
    'validationLicenseExpired': 'Twoje prawo jazdy straciło ważność. Zaktualizuj ważność w profilu.',
    'completeProfileBtn': 'Uzupełnij profil',
    'consentsRequired': 'Aby kontynuować, potwierdź wymagane zgody.',
  },
  'uk': {
    'validationMissingProfile': 'Щоб завершити бронювання, спочатку заповніть у профілі: {fields}. Фото документів можна додати пізніше.',
    'validationLicenseExpired': 'Термін дії вашого посвідчення водія минув. Оновіть його чинність у профілі.',
    'completeProfileBtn': 'Заповнити профіль',
    'consentsRequired': 'Щоб продовжити, підтвердьте обов\'язкові згоди.',
  },
};
