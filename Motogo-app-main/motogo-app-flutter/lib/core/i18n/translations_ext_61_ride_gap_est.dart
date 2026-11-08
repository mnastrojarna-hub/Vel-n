/// Mezery v záznamu jízdy (bez GPS) — majitel 2026-11-08: „odhad šedá trasa
/// s popisem“. Mezera se kreslí šedě tečkovaně jako ODHAD trasy po silnici
/// (Mapy.com), nikdy rovnou spojnicí; popisek na mapě + vysvětlení pod
/// statistikami (starý i nový vzhled). + `pdLateRefund*`: platba prošla na
/// mezitím zrušenou rezervaci → vracíme (VerifyState.cancelledRefund).
/// Všech 8 jazyků (cs tyká), bez emoji.
const Map<String, Map<String, String>> translationsExt61RideGapEst = {
  'cs': {
    'pdLateRefundTitle': 'Rezervace byla mezitím zrušená',
    'pdLateRefundBody': 'Platba prošla, ale rezervace se mezitím zrušila (nebyla zaplacená včas). Peníze ti vrátíme na kartu – nemusíš nic dělat, vrácenou částku pak uvidíš v detailu rezervace. Novou rezervaci si můžeš vytvořit kdykoli.',
    'rideGapEstLabel': 'Odhad trasy · bez GPS',
    'rideGapEstNotice': 'Část trasy neznáme — telefon chvílemi neposílal polohu (slabý signál, vypnutá appka nebo poloha). Šedé tečkované úseky jsou jen odhad trasy po silnici: tudy jsi jet nemusel a do kilometrů se nepočítají. Pauzy a noci sem nepatří, ty jsou zvlášť.',
  },
  'en': {
    'pdLateRefundTitle': 'The booking was cancelled in the meantime',
    'pdLateRefundBody': 'The payment went through, but the booking was cancelled in the meantime (it wasn’t paid in time). We’ll refund the money to your card – you don’t need to do anything; you’ll then see the refunded amount in the booking details. You can make a new booking at any time.',
    'rideGapEstLabel': 'Estimated route · no GPS',
    'rideGapEstNotice': 'Part of the route is unknown — your phone stopped sending its location for a while (weak signal, app or location off). The grey dotted parts are only an estimated route by road: you may not have ridden there and they aren’t counted in the distance. Breaks and nights aren’t included here; they’re shown separately.',
  },
  'de': {
    'pdLateRefundTitle': 'Die Buchung wurde inzwischen storniert',
    'pdLateRefundBody': 'Die Zahlung ist durchgegangen, aber die Buchung wurde inzwischen storniert (sie wurde nicht rechtzeitig bezahlt). Wir erstatten dir das Geld auf die Karte – du musst nichts tun, den erstatteten Betrag siehst du dann in den Buchungsdetails. Eine neue Buchung kannst du jederzeit anlegen.',
    'rideGapEstLabel': 'Geschätzte Route · kein GPS',
    'rideGapEstNotice': 'Ein Teil der Strecke ist unbekannt — dein Handy hat zeitweise keinen Standort gesendet (schwaches Signal, App oder Standort aus). Die grau gepunkteten Abschnitte sind nur eine geschätzte Route über die Straße: Dort bist du nicht unbedingt gefahren, und sie zählen nicht zu den Kilometern. Pausen und Nächte gehören nicht dazu, die werden getrennt angezeigt.',
  },
  'es': {
    'pdLateRefundTitle': 'La reserva se canceló mientras tanto',
    'pdLateRefundBody': 'El pago se ha realizado, pero la reserva se canceló mientras tanto (no se pagó a tiempo). Te devolveremos el dinero a la tarjeta: no tienes que hacer nada; luego verás el importe reembolsado en el detalle de la reserva. Puedes hacer una nueva reserva cuando quieras.',
    'rideGapEstLabel': 'Ruta estimada · sin GPS',
    'rideGapEstNotice': 'No conocemos parte del recorrido: tu móvil dejó de enviar la ubicación un rato (señal débil, app o ubicación apagadas). Los tramos grises de puntos son solo una ruta estimada por carretera: puede que no pasaras por ahí y no cuentan en los kilómetros. Las pausas y las noches no entran aquí; se muestran aparte.',
  },
  'fr': {
    'pdLateRefundTitle': 'La réservation a été annulée entre-temps',
    'pdLateRefundBody': 'Le paiement est passé, mais la réservation a été annulée entre-temps (elle n’a pas été payée à temps). Nous te rembourserons sur ta carte – tu n’as rien à faire, tu verras ensuite le montant remboursé dans le détail de la réservation. Tu peux faire une nouvelle réservation à tout moment.',
    'rideGapEstLabel': 'Trajet estimé · sans GPS',
    'rideGapEstNotice': 'Une partie du trajet est inconnue — ton téléphone n’a pas envoyé sa position pendant un moment (signal faible, appli ou localisation coupée). Les pointillés gris ne sont qu’un trajet estimé par la route : tu n’es pas forcément passé par là, et ils ne comptent pas dans les kilomètres. Les pauses et les nuits n’en font pas partie ; elles sont affichées à part.',
  },
  'nl': {
    'pdLateRefundTitle': 'De reservering is intussen geannuleerd',
    'pdLateRefundBody': 'De betaling is gelukt, maar de reservering is intussen geannuleerd (ze is niet op tijd betaald). We betalen het geld terug op je kaart – je hoeft niets te doen, het terugbetaalde bedrag zie je daarna in de details van de reservering. Je kunt altijd een nieuwe reservering maken.',
    'rideGapEstLabel': 'Geschatte route · geen GPS',
    'rideGapEstNotice': 'Een deel van de route is onbekend – je telefoon stuurde een tijdje geen locatie (zwak signaal, app of locatie uit). De grijze stippellijnen zijn alleen een geschatte route over de weg: daar ben je niet per se gereden en ze tellen niet mee in de kilometers. Pauzes en nachten horen hier niet bij; die worden apart getoond.',
  },
  'pl': {
    'pdLateRefundTitle': 'Rezerwacja została w międzyczasie anulowana',
    'pdLateRefundBody': 'Płatność przeszła, ale rezerwacja została w międzyczasie anulowana (nie została opłacona na czas). Zwrócimy pieniądze na kartę – nie musisz nic robić, zwróconą kwotę zobaczysz potem w szczegółach rezerwacji. Nową rezerwację możesz założyć w każdej chwili.',
    'rideGapEstLabel': 'Szacowana trasa · brak GPS',
    'rideGapEstNotice': 'Części trasy nie znamy — telefon przez jakiś czas nie wysyłał lokalizacji (słaby sygnał, wyłączona aplikacja lub lokalizacja). Szare kropkowane odcinki to tylko szacowana trasa po drogach: wcale nie musiałeś tamtędy jechać i nie liczą się do kilometrów. Przerwy i noce się tu nie wliczają, są pokazane osobno.',
  },
  'uk': {
    'pdLateRefundTitle': 'Бронювання тим часом скасовано',
    'pdLateRefundBody': 'Оплата пройшла, але бронювання тим часом скасувалося (його не оплатили вчасно). Ми повернемо гроші на картку — тобі нічого не треба робити, повернену суму потім побачиш у деталях бронювання. Нове бронювання можна створити будь-коли.',
    'rideGapEstLabel': 'Орієнтовний маршрут · без GPS',
    'rideGapEstNotice': 'Частина маршруту невідома — телефон якийсь час не надсилав геопозицію (слабкий сигнал, вимкнений застосунок або геолокація). Сірі пунктирні відрізки — лише орієнтовний маршрут дорогами: ти міг там і не їхати, і вони не враховуються в кілометрах. Перерви й ночі сюди не входять, вони показані окремо.',
  },
};
