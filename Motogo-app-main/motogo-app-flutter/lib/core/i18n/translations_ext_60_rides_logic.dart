/// Záznam jízd — upozornění „vlastní cesta stojí u svého startu" (oprava
/// logiky 2026-10-29: místo vypnutí GPS jen upozornit, rozjezd se nahraje
/// sám) a hláška „cesta stojí od …, pokračuješ?" při otevření appky po
/// ≥ 20 h stání (2026-10-30, zapomenutý Stop). Sdílené klíče obou stromů
/// appky; registrované přes `translations_ext_47_rides.dart`. Tyká se ve
/// všech jazycích.
const Map<String, Map<String, String>> translationsExt60RidesLogic = {
  'cs': {
    'rpNotifHomeTitle': 'Jsi zpátky tam, kde cesta začala',
    'rpNotifHomeText': 'Už nikam nejedeš? Otevři appku a cestu ukonči a ulož. Pokračuješ? Nic nedělej, po rozjezdu nahrávám dál sám.',
    'rpTripIdleAsk': 'Tvoje cesta stojí od {date}, tak jsem kvůli baterii vypnul GPS a nic nenahrávám. Jedeš dál? Klepni na Pokračovat v cestě. Je cesta hotová? Ukonči ji a ulož.',
  },
  'en': {
    'rpNotifHomeTitle': 'You’re back where the trip started',
    'rpNotifHomeText': 'Done riding? Open the app to end and save the trip. Carrying on? Do nothing — I’ll keep recording as soon as you ride off.',
    'rpTripIdleAsk': 'Your trip has been standing still since {date}, so I turned GPS off to save battery and I’m not recording. Riding on? Tap Continue the trip. Trip finished? End and save it.',
  },
  'de': {
    'rpNotifHomeTitle': 'Du bist wieder am Startpunkt der Tour',
    'rpNotifHomeText': 'Fertig mit Fahren? Öffne die App und beende und speichere die Tour. Fährst du weiter? Nichts tun – sobald du losfährst, zeichne ich von selbst weiter auf.',
    'rpTripIdleAsk': 'Deine Tour steht seit {date} still, deshalb habe ich GPS ausgeschaltet, um Akku zu sparen, und zeichne nichts auf. Fährst du weiter? Tippe auf Tour fortsetzen. Ist die Tour vorbei? Beende und speichere sie.',
  },
  'es': {
    'rpNotifHomeTitle': 'Has vuelto al punto de salida del viaje',
    'rpNotifHomeText': '¿Ya no vas a rodar? Abre la app para terminar y guardar el viaje. ¿Sigues? No hagas nada: en cuanto arranques, sigo grabando solo.',
    'rpTripIdleAsk': 'Tu viaje está parado desde el {date}, así que apagué el GPS para ahorrar batería y no estoy grabando. ¿Sigues? Toca Seguir con el viaje. ¿Ya terminó? Termínalo y guárdalo.',
  },
  'fr': {
    'rpNotifHomeTitle': 'Tu es revenu au point de départ du voyage',
    'rpNotifHomeText': 'Tu as fini de rouler ? Ouvre l’appli pour terminer et enregistrer le voyage. Tu continues ? Ne fais rien : dès que tu repars, j’enregistre de nouveau tout seul.',
    'rpTripIdleAsk': 'Ton voyage est à l’arrêt depuis le {date}, j’ai donc coupé le GPS pour économiser la batterie et je n’enregistre rien. Tu repars ? Touche Continuer le voyage. Le voyage est fini ? Termine-le et enregistre-le.',
  },
  'nl': {
    'rpNotifHomeTitle': 'Je bent terug bij het startpunt van de reis',
    'rpNotifHomeText': 'Klaar met rijden? Open de app om de reis te beëindigen en op te slaan. Rij je verder? Niets doen — zodra je wegrijdt, neem ik vanzelf weer op.',
    'rpTripIdleAsk': 'Je reis staat sinds {date} stil, dus heb ik gps uitgezet om de batterij te sparen en neem ik niets op. Rij je verder? Tik op Reis voortzetten. Is de reis klaar? Beëindig en sla hem op.',
  },
  'pl': {
    'rpNotifHomeTitle': 'Wróciłeś tam, gdzie zaczęła się podróż',
    'rpNotifHomeText': 'Koniec jazdy? Otwórz aplikację, zakończ i zapisz podróż. Jedziesz dalej? Nic nie rób — gdy ruszysz, sam nagrywam dalej.',
    'rpTripIdleAsk': 'Twoja podróż stoi od {date}, więc wyłączyłem GPS, żeby oszczędzać baterię, i nic nie nagrywam. Jedziesz dalej? Stuknij Kontynuuj podróż. Podróż skończona? Zakończ i zapisz.',
  },
  'uk': {
    'rpNotifHomeTitle': 'Ти повернувся туди, звідки почалася подорож',
    'rpNotifHomeText': 'Більше не їдеш? Відкрий застосунок, заверши й збережи подорож. Їдеш далі? Нічого не роби — щойно рушиш, я сам продовжу запис.',
    'rpTripIdleAsk': 'Твоя подорож стоїть з {date}, тож я вимкнув GPS, щоб зберегти батарею, і нічого не записую. Їдеш далі? Торкнись «Продовжити подорож». Подорож завершена? Заверши й збережи її.',
  },
};
