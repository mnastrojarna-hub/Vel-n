/// Doc-scan messages. Shown when the document photo was uploaded but OCR could
/// not read the fields — the step still succeeds (door codes release on a photo
/// OR real OCR). Merged into the global translations map.
const Map<String, Map<String, String>> translationsExt4DocScan = {
  'cs': {
    'docPhotoSavedNoOcr': 'Fotka dokladu byla uložena. Údaje se nepodařilo automaticky přečíst, ale doklad je nahraný — kódy ke dveřím se uvolní.',
  },
  'en': {
    'docPhotoSavedNoOcr': 'Document photo saved. We couldn\'t read the details automatically, but the document is uploaded — your access codes will be released.',
  },
  'de': {
    'docPhotoSavedNoOcr': 'Dokumentfoto gespeichert. Die Daten konnten nicht automatisch gelesen werden, aber das Dokument ist hochgeladen — die Zugangscodes werden freigegeben.',
  },
  'es': {
    'docPhotoSavedNoOcr': 'Foto del documento guardada. No pudimos leer los datos automáticamente, pero el documento está subido: los códigos de acceso se liberarán.',
  },
  'fr': {
    'docPhotoSavedNoOcr': 'Photo du document enregistrée. Nous n\'avons pas pu lire les données automatiquement, mais le document est téléversé — les codes d\'accès seront débloqués.',
  },
  'nl': {
    'docPhotoSavedNoOcr': 'Documentfoto opgeslagen. We konden de gegevens niet automatisch lezen, maar het document is geüpload — de toegangscodes worden vrijgegeven.',
  },
  'pl': {
    'docPhotoSavedNoOcr': 'Zdjęcie dokumentu zapisane. Nie udało się odczytać danych automatycznie, ale dokument został przesłany — kody dostępu zostaną udostępnione.',
  },
};
