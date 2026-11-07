/// Bez dvojího vyplňování mimo rezervaci (majitel 2026-10-22: „neměl by
/// nikdy zákazník nic vyplňovat dvakrát“): SOS náhrada nabídne adresu
/// přistavení podle polohy telefonu („Kde právě jsi“). Klíče `sosHere*`
/// sdílí oba stromy appky. Tyká se ve všech jazycích.
const Map<String, Map<String, String>> translationsExt48SharedCarry = {
  'cs': {
    'sosHereTitle': 'Kde právě jsi',
    'sosHereTap': 'Klepni a adresu doplníme podle polohy telefonu.',
    'sosHereUsed': 'Doplněno podle polohy. Adresu můžeš upravit, třeba když se přesuneš na bezpečnější místo.',
  },
  'en': {
    'sosHereTitle': 'Where you are now',
    'sosHereTap': 'Tap and we’ll fill in the address from your phone’s location.',
    'sosHereUsed': 'Filled in from your location. You can edit the address, e.g. if you move somewhere safer.',
  },
  'de': {
    'sosHereTitle': 'Wo du gerade bist',
    'sosHereTap': 'Tippe hier und wir tragen die Adresse anhand deines Standorts ein.',
    'sosHereUsed': 'Anhand deines Standorts eingetragen. Du kannst die Adresse ändern, z. B. wenn du an einen sichereren Ort gehst.',
  },
  'es': {
    'sosHereTitle': 'Dónde estás ahora',
    'sosHereTap': 'Toca y rellenamos la dirección con la ubicación de tu móvil.',
    'sosHereUsed': 'Rellenada con tu ubicación. Puedes cambiar la dirección, por ejemplo si te mueves a un sitio más seguro.',
  },
  'fr': {
    'sosHereTitle': 'Là où tu es',
    'sosHereTap': 'Touche ici et nous remplirons l’adresse grâce à la position de ton téléphone.',
    'sosHereUsed': 'Remplie d’après ta position. Tu peux modifier l’adresse, par exemple si tu te déplaces vers un endroit plus sûr.',
  },
  'nl': {
    'sosHereTitle': 'Waar je nu bent',
    'sosHereTap': 'Tik en we vullen het adres in op basis van de locatie van je telefoon.',
    'sosHereUsed': 'Ingevuld op basis van je locatie. Je kunt het adres aanpassen, bijvoorbeeld als je naar een veiligere plek gaat.',
  },
  'pl': {
    'sosHereTitle': 'Gdzie teraz jesteś',
    'sosHereTap': 'Stuknij, a uzupełnimy adres na podstawie lokalizacji telefonu.',
    'sosHereUsed': 'Uzupełniono na podstawie lokalizacji. Możesz zmienić adres, np. gdy przejdziesz w bezpieczniejsze miejsce.',
  },
  'uk': {
    'sosHereTitle': 'Де ти зараз',
    'sosHereTap': 'Торкнися — і ми заповнимо адресу за місцезнаходженням телефона.',
    'sosHereUsed': 'Заповнено за місцезнаходженням. Адресу можна змінити, наприклад, якщо перейдеш у безпечніше місце.',
  },
};
