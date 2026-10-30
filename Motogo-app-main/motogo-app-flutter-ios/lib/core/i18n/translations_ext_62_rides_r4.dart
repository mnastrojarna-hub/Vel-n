/// Záznam jízd — připomínka „cesta stojí od …" při otevření appky po
/// ≥ 20 h stání (oprava logiky 2026-10-30, kolo 4): GPS běží dál a ranní
/// rozjezd vícedenní cesty se nahraje sám; GPS vypne a zeptá se až pojistka
/// po 48 h. Sdílené klíče obou stromů appky; registrované přes
/// `translations_ext_47_rides.dart`. Tyká se ve všech jazycích.
const Map<String, Map<String, String>> translationsExt62RidesR4 = {
  'cs': {
    'rpTripIdleRemind': 'Tvoje cesta stojí od {date}. Jedeš dál? Nic nedělej – jakmile se rozjedeš, nahrávám dál sám a cesta zůstane jedna. Je hotová? Ukonči ji a ulož.',
    'rpNotifRemindTitle': 'Cesta stojí od {date}',
    'rpNotifRemindText': 'Jedeš dál? Nic nedělej, po rozjezdu nahrávám sám. Je cesta hotová? Otevři appku, ukonči ji a ulož.',
  },
  'en': {
    'rpTripIdleRemind': 'Your trip has been standing still since {date}. Riding on? Do nothing – as soon as you set off, I’ll keep recording and it stays one trip. Finished? End and save it.',
    'rpNotifRemindTitle': 'Trip standing still since {date}',
    'rpNotifRemindText': 'Riding on? Do nothing – I’ll keep recording once you set off. Trip finished? Open the app to end and save it.',
  },
  'de': {
    'rpTripIdleRemind': 'Deine Tour steht seit {date} still. Fährst du weiter? Nichts tun – sobald du losfährst, zeichne ich weiter auf und es bleibt eine Tour. Fertig? Beende und speichere sie.',
    'rpNotifRemindTitle': 'Tour steht seit {date} still',
    'rpNotifRemindText': 'Fährst du weiter? Nichts tun – sobald du losfährst, zeichne ich weiter auf. Ist die Tour vorbei? Öffne die App, beende und speichere sie.',
  },
  'es': {
    'rpTripIdleRemind': 'Tu viaje está parado desde el {date}. ¿Sigues? No hagas nada: en cuanto arranques, sigo grabando y seguirá siendo un solo viaje. ¿Ya terminó? Termínalo y guárdalo.',
    'rpNotifRemindTitle': 'Viaje parado desde el {date}',
    'rpNotifRemindText': '¿Sigues? No hagas nada: en cuanto arranques, sigo grabando. ¿Terminó el viaje? Abre la app, termínalo y guárdalo.',
  },
  'fr': {
    'rpTripIdleRemind': 'Ton voyage est à l’arrêt depuis le {date}. Tu repars ? Ne fais rien : dès que tu roules, je continue d’enregistrer et ça reste un seul voyage. C’est fini ? Termine-le et enregistre-le.',
    'rpNotifRemindTitle': 'Voyage à l’arrêt depuis le {date}',
    'rpNotifRemindText': 'Tu repars ? Ne fais rien : dès que tu roules, je continue d’enregistrer. Le voyage est fini ? Ouvre l’appli, termine-le et enregistre-le.',
  },
  'nl': {
    'rpTripIdleRemind': 'Je reis staat sinds {date} stil. Rij je verder? Niets doen – zodra je wegrijdt, neem ik verder op en blijft het één reis. Klaar? Beëindig hem en sla hem op.',
    'rpNotifRemindTitle': 'Reis staat stil sinds {date}',
    'rpNotifRemindText': 'Rij je verder? Niets doen – zodra je wegrijdt, neem ik verder op. Is de reis klaar? Open de app, beëindig hem en sla hem op.',
  },
  'pl': {
    'rpTripIdleRemind': 'Twoja podróż stoi od {date}. Jedziesz dalej? Nic nie rób – gdy tylko ruszysz, nagrywam dalej i to nadal będzie jedna podróż. Skończona? Zakończ ją i zapisz.',
    'rpNotifRemindTitle': 'Podróż stoi od {date}',
    'rpNotifRemindText': 'Jedziesz dalej? Nic nie rób – gdy ruszysz, nagrywam dalej. Podróż skończona? Otwórz aplikację, zakończ ją i zapisz.',
  },
  'uk': {
    'rpTripIdleRemind': 'Твоя подорож стоїть з {date}. Їдеш далі? Нічого не роби – щойно рушиш, я записую далі, і це залишиться однією подорожжю. Завершено? Заверши й збережи її.',
    'rpNotifRemindTitle': 'Подорож стоїть з {date}',
    'rpNotifRemindText': 'Їдеш далі? Нічого не роби – щойно рушиш, я записую далі. Подорож завершена? Відкрий застосунок, заверши й збережи її.',
  },
};
