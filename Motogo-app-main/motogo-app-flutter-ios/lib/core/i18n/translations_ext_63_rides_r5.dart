/// Záznam jízd — výpůjčka po pojistce „dlouhá pauza" (oprava logiky
/// 2026-10-30, kolo 5): motorka stojí 48 h bez jízdy i bez otevření appky
/// → GPS se kvůli baterii vypne; otevřením appky se záznam zapne sám.
/// Sdílené klíče obou stromů appky; registrované přes
/// `translations_ext_47_rides.dart`. Tyká se ve všech jazycích.
const Map<String, Map<String, String>> translationsExt63RidesR5 = {
  'cs': {
    'rpNotifRentIdleText': 'Motorka dlouho stojí, tak jsem kvůli baterii vypnul GPS. Až vyrazíš, stačí otevřít appku a záznam se zapne sám.',
    'rpRentGuardWoke': 'Motorka stála od {date}, tak jsem mezitím kvůli baterii vypnul GPS. Teď je zase zapnuté a po rozjezdu nahrávám sám. Pokud jsi mezitím jel, tahle jízda se nenahrála.',
  },
  'en': {
    'rpNotifRentIdleText': 'The bike has been standing for a long time, so I turned GPS off to save battery. When you set off, just open the app and recording switches back on by itself.',
    'rpRentGuardWoke': 'The bike had been standing since {date}, so I turned GPS off in the meantime to save battery. It’s back on now, and I’ll record by myself as soon as you set off. If you rode in the meantime, that ride wasn’t recorded.',
  },
  'de': {
    'rpNotifRentIdleText': 'Das Motorrad steht schon lange, deshalb habe ich GPS ausgeschaltet, um Akku zu sparen. Wenn du losfährst, öffne einfach die App – die Aufzeichnung schaltet sich von selbst wieder ein.',
    'rpRentGuardWoke': 'Das Motorrad stand seit {date}, deshalb hatte ich GPS zwischendurch ausgeschaltet, um Akku zu sparen. Jetzt ist es wieder an, und sobald du losfährst, zeichne ich von selbst auf. Bist du zwischendurch gefahren, wurde diese Fahrt nicht aufgezeichnet.',
  },
  'es': {
    'rpNotifRentIdleText': 'La moto lleva mucho tiempo parada, así que apagué el GPS para ahorrar batería. Cuando salgas, solo abre la app y la grabación se activará sola.',
    'rpRentGuardWoke': 'La moto estaba parada desde el {date}, así que mientras tanto apagué el GPS para ahorrar batería. Ya vuelve a estar encendido y, en cuanto arranques, grabo yo solo. Si saliste a rodar mientras tanto, esa ruta no se grabó.',
  },
  'fr': {
    'rpNotifRentIdleText': 'La moto est à l’arrêt depuis longtemps, j’ai donc coupé le GPS pour économiser la batterie. Quand tu repars, ouvre simplement l’appli et l’enregistrement se relance tout seul.',
    'rpRentGuardWoke': 'La moto était à l’arrêt depuis le {date}, j’avais donc coupé le GPS entre-temps pour économiser la batterie. Il est de nouveau allumé et j’enregistre tout seul dès que tu repars. Si tu as roulé entre-temps, ce trajet n’a pas été enregistré.',
  },
  'nl': {
    'rpNotifRentIdleText': 'De motor staat al lang stil, dus heb ik de gps uitgezet om je batterij te sparen. Als je vertrekt, open je gewoon de app en gaat de opname vanzelf weer aan.',
    'rpRentGuardWoke': 'De motor stond sinds {date} stil, dus had ik de gps intussen uitgezet om je batterij te sparen. Hij staat nu weer aan en zodra je wegrijdt, neem ik vanzelf op. Heb je intussen gereden, dan is die rit niet opgenomen.',
  },
  'pl': {
    'rpNotifRentIdleText': 'Motocykl długo stoi, więc wyłączyłem GPS, żeby oszczędzać baterię. Gdy ruszysz, po prostu otwórz aplikację, a zapis sam się włączy.',
    'rpRentGuardWoke': 'Motocykl stał od {date}, więc w międzyczasie wyłączyłem GPS, żeby oszczędzać baterię. Teraz znów działa i gdy ruszysz, nagrywam sam. Jeśli w międzyczasie jechałeś, ta jazda się nie nagrała.',
  },
  'uk': {
    'rpNotifRentIdleText': 'Мотоцикл довго стоїть, тож я вимкнув GPS, щоб зберегти батарею. Коли рушиш, просто відкрий застосунок — запис увімкнеться сам.',
    'rpRentGuardWoke': 'Мотоцикл стояв з {date}, тож я тим часом вимкнув GPS, щоб зберегти батарею. Тепер він знову увімкнений, і щойно рушиш, я записуватиму сам. Якщо ти тим часом їздив, ця поїздка не записалася.',
  },
};
