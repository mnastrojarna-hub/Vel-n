/// Extra profile/documents/consent keys — added for:
///  • OP / passport number field in the personal-info form
///  • document samples (handover + damage protocol) in Documents & Contracts
///  • consent lock during an active reservation
///  • required-permissions notice during an active reservation
///
/// Kept in a standalone file so all 7 languages stay together and the base
/// language maps don't need scattered edits. Merged by translations.dart.
const Map<String, Map<String, String>> translationsExt6Profile = {
  'cs': {
    'idNumberFull': 'Č. OP / pasu',
    'documentSamplesSection': 'Vzory dokumentů',
    'damageProtocol': 'Protokol o poškození',
    'handoverProtocolSubtitle': 'Vzor předávacího protokolu',
    'damageProtocolSubtitle': 'Vzor protokolu o poškození',
    'consentsLockedActive': 'Během aktivní rezervace nelze souhlasy odebrat.',
    'consentsLockedHint':
        'Máte aktivní rezervaci — souhlasy jsou po dobu pronájmu povinné. Odebrat je můžete po jejím ukončení.',
    'permsRequiredActive':
        'Máte aktivní rezervaci. Pro správné fungování aplikace (přístupové kódy, navigace, oznámení) jsou všechna oprávnění kromě galerie/fotek vyžadována.',
    'requiredLabel': 'Vyžadováno',
  },
  'pl': {
    'idNumberFull': 'Nr dowodu / paszportu',
    'documentSamplesSection': 'Wzory dokumentów',
    'damageProtocol': 'Protokół uszkodzeń',
    'handoverProtocolSubtitle': 'Wzór protokołu przekazania',
    'damageProtocolSubtitle': 'Wzór protokołu uszkodzeń',
    'consentsLockedActive': 'Podczas aktywnej rezerwacji nie można cofnąć zgód.',
    'consentsLockedHint':
        'Masz aktywną rezerwację — zgody są wymagane przez czas najmu. Możesz je cofnąć po jego zakończeniu.',
    'permsRequiredActive':
        'Masz aktywną rezerwację. Do prawidłowego działania aplikacji (kody dostępu, nawigacja, powiadomienia) wszystkie uprawnienia oprócz galerii/zdjęć są wymagane.',
    'requiredLabel': 'Wymagane',
  },
  'en': {
    'idNumberFull': 'ID / passport no.',
    'documentSamplesSection': 'Document samples',
    'damageProtocol': 'Damage protocol',
    'handoverProtocolSubtitle': 'Handover protocol sample',
    'damageProtocolSubtitle': 'Damage protocol sample',
    'consentsLockedActive': "Consents can't be withdrawn during an active reservation.",
    'consentsLockedHint':
        'You have an active reservation — consents are required for the rental period. You can withdraw them once it ends.',
    'permsRequiredActive':
        'You have an active reservation. For the app to work correctly (access codes, navigation, notifications) all permissions except gallery/photos are required.',
    'requiredLabel': 'Required',
  },
  'de': {
    'idNumberFull': 'Ausweis-/Passnr.',
    'documentSamplesSection': 'Dokumentvorlagen',
    'damageProtocol': 'Schadensprotokoll',
    'handoverProtocolSubtitle': 'Muster-Übergabeprotokoll',
    'damageProtocolSubtitle': 'Muster-Schadensprotokoll',
    'consentsLockedActive': 'Während einer aktiven Reservierung können Einwilligungen nicht widerrufen werden.',
    'consentsLockedHint':
        'Sie haben eine aktive Reservierung — die Einwilligungen sind für den Mietzeitraum erforderlich. Nach Ende können Sie sie widerrufen.',
    'permsRequiredActive':
        'Sie haben eine aktive Reservierung. Für die korrekte Funktion der App (Zugangscodes, Navigation, Benachrichtigungen) sind alle Berechtigungen außer Galerie/Fotos erforderlich.',
    'requiredLabel': 'Erforderlich',
  },
  'nl': {
    'idNumberFull': 'ID-/paspoortnr.',
    'documentSamplesSection': 'Documentsjablonen',
    'damageProtocol': 'Schadeprotocol',
    'handoverProtocolSubtitle': 'Voorbeeld overdrachtsprotocol',
    'damageProtocolSubtitle': 'Voorbeeld schadeprotocol',
    'consentsLockedActive': 'Toestemmingen kunnen niet worden ingetrokken tijdens een actieve reservering.',
    'consentsLockedHint':
        'U hebt een actieve reservering — toestemmingen zijn vereist tijdens de huurperiode. U kunt ze intrekken zodra deze eindigt.',
    'permsRequiredActive':
        'U hebt een actieve reservering. Voor een correcte werking van de app (toegangscodes, navigatie, meldingen) zijn alle rechten behalve galerij/foto’s vereist.',
    'requiredLabel': 'Vereist',
  },
  'es': {
    'idNumberFull': 'Nº DNI / pasaporte',
    'documentSamplesSection': 'Plantillas de documentos',
    'damageProtocol': 'Protocolo de daños',
    'handoverProtocolSubtitle': 'Modelo de protocolo de entrega',
    'damageProtocolSubtitle': 'Modelo de protocolo de daños',
    'consentsLockedActive': 'No se pueden retirar los consentimientos durante una reserva activa.',
    'consentsLockedHint':
        'Tiene una reserva activa: los consentimientos son obligatorios durante el alquiler. Podrá retirarlos cuando finalice.',
    'permsRequiredActive':
        'Tiene una reserva activa. Para que la app funcione correctamente (códigos de acceso, navegación, notificaciones) se requieren todos los permisos excepto galería/fotos.',
    'requiredLabel': 'Obligatorio',
  },
  'fr': {
    'idNumberFull': 'N° CNI / passeport',
    'documentSamplesSection': 'Modèles de documents',
    'damageProtocol': 'Protocole de dommages',
    'handoverProtocolSubtitle': 'Modèle de protocole de remise',
    'damageProtocolSubtitle': 'Modèle de protocole de dommages',
    'consentsLockedActive': 'Les consentements ne peuvent pas être retirés pendant une réservation active.',
    'consentsLockedHint':
        'Vous avez une réservation active — les consentements sont requis pendant la location. Vous pourrez les retirer une fois terminée.',
    'permsRequiredActive':
        'Vous avez une réservation active. Pour que l’application fonctionne correctement (codes d’accès, navigation, notifications), toutes les autorisations sauf galerie/photos sont requises.',
    'requiredLabel': 'Requis',
  },
};
