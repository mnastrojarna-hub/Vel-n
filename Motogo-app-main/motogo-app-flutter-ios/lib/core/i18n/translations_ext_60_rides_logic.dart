/// Záznam jízd — upozornění „vlastní cesta stojí u svého startu" (oprava
/// logiky 2026-10-29: místo vypnutí GPS jen upozornit, rozjezd se nahraje
/// sám). Sdílené klíče obou stromů appky; registrované přes
/// `translations_ext_47_rides.dart`. Tyká se ve všech jazycích.
const Map<String, Map<String, String>> translationsExt60RidesLogic = {
  'cs': {
    'rpNotifHomeTitle': 'Jsi zpátky tam, kde cesta začala',
    'rpNotifHomeText': 'Už nikam nejedeš? Otevři appku a cestu ukonči a ulož. Pokračuješ? Nic nedělej, po rozjezdu nahrávám dál sám.',
  },
  'en': {
    'rpNotifHomeTitle': 'You’re back where the trip started',
    'rpNotifHomeText': 'Done riding? Open the app to end and save the trip. Carrying on? Do nothing — I’ll keep recording as soon as you ride off.',
  },
  'de': {
    'rpNotifHomeTitle': 'Du bist wieder am Startpunkt der Tour',
    'rpNotifHomeText': 'Fertig mit Fahren? Öffne die App und beende und speichere die Tour. Fährst du weiter? Nichts tun – sobald du losfährst, zeichne ich von selbst weiter auf.',
  },
  'es': {
    'rpNotifHomeTitle': 'Has vuelto al punto de salida del viaje',
    'rpNotifHomeText': '¿Ya no vas a rodar? Abre la app para terminar y guardar el viaje. ¿Sigues? No hagas nada: en cuanto arranques, sigo grabando solo.',
  },
  'fr': {
    'rpNotifHomeTitle': 'Tu es revenu au point de départ du voyage',
    'rpNotifHomeText': 'Tu as fini de rouler ? Ouvre l’appli pour terminer et enregistrer le voyage. Tu continues ? Ne fais rien : dès que tu repars, j’enregistre de nouveau tout seul.',
  },
  'nl': {
    'rpNotifHomeTitle': 'Je bent terug bij het startpunt van de reis',
    'rpNotifHomeText': 'Klaar met rijden? Open de app om de reis te beëindigen en op te slaan. Rij je verder? Niets doen — zodra je wegrijdt, neem ik vanzelf weer op.',
  },
  'pl': {
    'rpNotifHomeTitle': 'Wróciłeś tam, gdzie zaczęła się podróż',
    'rpNotifHomeText': 'Koniec jazdy? Otwórz aplikację, zakończ i zapisz podróż. Jedziesz dalej? Nic nie rób — gdy ruszysz, sam nagrywam dalej.',
  },
  'uk': {
    'rpNotifHomeTitle': 'Ти повернувся туди, звідки почалася подорож',
    'rpNotifHomeText': 'Більше не їдеш? Відкрий застосунок, заверши й збережи подорож. Їдеш далі? Нічого не роби — щойно рушиш, я сам продовжу запис.',
  },
};
