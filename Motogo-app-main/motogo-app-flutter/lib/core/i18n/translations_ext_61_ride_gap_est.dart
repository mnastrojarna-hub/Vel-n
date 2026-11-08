/// Mezery v záznamu jízdy (bez GPS) — majitel 2026-11-08: „odhad šedá trasa
/// s popisem“. Mezera se kreslí šedě tečkovaně jako ODHAD trasy po silnici
/// (Mapy.com), nikdy rovnou spojnicí; popisek na mapě + vysvětlení pod
/// statistikami (starý i nový vzhled). Klíče JEN s prefixem `rideGapEst`;
/// všech 8 jazyků (cs tyká), bez emoji.
const Map<String, Map<String, String>> translationsExt61RideGapEst = {
  'cs': {
    'rideGapEstLabel': 'Odhad trasy · bez GPS',
    'rideGapEstNotice': 'Část trasy neznáme — telefon chvílemi neposílal polohu (slabý signál, vypnutá appka nebo poloha). Šedé tečkované úseky jsou jen odhad trasy po silnici: tudy jsi jet nemusel a do kilometrů se nepočítají. Pauzy a noci sem nepatří, ty jsou zvlášť.',
  },
  'en': {
    'rideGapEstLabel': 'Estimated route · no GPS',
    'rideGapEstNotice': 'Part of the route is unknown — your phone stopped sending its location for a while (weak signal, app or location off). The grey dotted parts are only an estimated route by road: you may not have ridden there and they aren’t counted in the distance. Breaks and nights aren’t included here; they’re shown separately.',
  },
  'de': {
    'rideGapEstLabel': 'Geschätzte Route · kein GPS',
    'rideGapEstNotice': 'Ein Teil der Strecke ist unbekannt — dein Handy hat zeitweise keinen Standort gesendet (schwaches Signal, App oder Standort aus). Die grau gepunkteten Abschnitte sind nur eine geschätzte Route über die Straße: Dort bist du nicht unbedingt gefahren, und sie zählen nicht zu den Kilometern. Pausen und Nächte gehören nicht dazu, die werden getrennt angezeigt.',
  },
  'es': {
    'rideGapEstLabel': 'Ruta estimada · sin GPS',
    'rideGapEstNotice': 'No conocemos parte del recorrido: tu móvil dejó de enviar la ubicación un rato (señal débil, app o ubicación apagadas). Los tramos grises de puntos son solo una ruta estimada por carretera: puede que no pasaras por ahí y no cuentan en los kilómetros. Las pausas y las noches no entran aquí; se muestran aparte.',
  },
  'fr': {
    'rideGapEstLabel': 'Trajet estimé · sans GPS',
    'rideGapEstNotice': 'Une partie du trajet est inconnue — ton téléphone n’a pas envoyé sa position pendant un moment (signal faible, appli ou localisation coupée). Les pointillés gris ne sont qu’un trajet estimé par la route : tu n’es pas forcément passé par là, et ils ne comptent pas dans les kilomètres. Les pauses et les nuits n’en font pas partie ; elles sont affichées à part.',
  },
  'nl': {
    'rideGapEstLabel': 'Geschatte route · geen GPS',
    'rideGapEstNotice': 'Een deel van de route is onbekend – je telefoon stuurde een tijdje geen locatie (zwak signaal, app of locatie uit). De grijze stippellijnen zijn alleen een geschatte route over de weg: daar ben je niet per se gereden en ze tellen niet mee in de kilometers. Pauzes en nachten horen hier niet bij; die worden apart getoond.',
  },
  'pl': {
    'rideGapEstLabel': 'Szacowana trasa · brak GPS',
    'rideGapEstNotice': 'Części trasy nie znamy — telefon przez jakiś czas nie wysyłał lokalizacji (słaby sygnał, wyłączona aplikacja lub lokalizacja). Szare kropkowane odcinki to tylko szacowana trasa po drogach: wcale nie musiałeś tamtędy jechać i nie liczą się do kilometrów. Przerwy i noce się tu nie wliczają, są pokazane osobno.',
  },
  'uk': {
    'rideGapEstLabel': 'Орієнтовний маршрут · без GPS',
    'rideGapEstNotice': 'Частина маршруту невідома — телефон якийсь час не надсилав геопозицію (слабкий сигнал, вимкнений застосунок або геолокація). Сірі пунктирні відрізки — лише орієнтовний маршрут дорогами: ти міг там і не їхати, і вони не враховуються в кілометрах. Перерви й ночі сюди не входять, вони показані окремо.',
  },
};
