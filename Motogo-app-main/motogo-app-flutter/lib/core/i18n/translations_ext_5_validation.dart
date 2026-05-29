/// Rental-length validation messages (min/max rental days enforced from
/// motorcycles.min_rental_days / max_rental_days, like the web). `{n}` = day
/// count. Merged into the global translations map.
const Map<String, Map<String, String>> translationsExt5Validation = {
  'cs': {
    'validationMinDays': 'Minimální délka pronájmu této motorky je {n} dní.',
    'validationMaxDays': 'Maximální délka pronájmu této motorky je {n} dní.',
    'validationPastPickup': 'Čas vyzvednutí už uplynul. Rezervaci nelze vytvořit zpětně – vyberte čas v budoucnosti.',
    'validationDeliveryLeadTime': 'Přistavení je možné nejdříve za 6 hodin od teď. Vyberte pozdější čas nebo jiný den.',
  },
  'en': {
    'validationMinDays': 'The minimum rental length for this motorcycle is {n} days.',
    'validationMaxDays': 'The maximum rental length for this motorcycle is {n} days.',
    'validationPastPickup': 'The pickup time has already passed. You cannot book retroactively – choose a time in the future.',
    'validationDeliveryLeadTime': 'Delivery is available no sooner than 6 hours from now. Choose a later time or another day.',
  },
  'de': {
    'validationMinDays': 'Die Mindestmietdauer für dieses Motorrad beträgt {n} Tage.',
    'validationMaxDays': 'Die maximale Mietdauer für dieses Motorrad beträgt {n} Tage.',
    'validationPastPickup': 'Die Abholzeit ist bereits vergangen. Eine rückwirkende Buchung ist nicht möglich – wählen Sie eine Zeit in der Zukunft.',
    'validationDeliveryLeadTime': 'Die Lieferung ist frühestens in 6 Stunden ab jetzt möglich. Wählen Sie eine spätere Zeit oder einen anderen Tag.',
  },
  'es': {
    'validationMinDays': 'La duración mínima de alquiler de esta moto es de {n} días.',
    'validationMaxDays': 'La duración máxima de alquiler de esta moto es de {n} días.',
    'validationPastPickup': 'La hora de recogida ya ha pasado. No se puede reservar de forma retroactiva: elige una hora futura.',
    'validationDeliveryLeadTime': 'La entrega está disponible como mínimo 6 horas a partir de ahora. Elige una hora posterior u otro día.',
  },
  'fr': {
    'validationMinDays': 'La durée minimale de location de cette moto est de {n} jours.',
    'validationMaxDays': 'La durée maximale de location de cette moto est de {n} jours.',
    'validationPastPickup': 'L\'heure de prise en charge est déjà passée. Impossible de réserver rétroactivement – choisissez une heure future.',
    'validationDeliveryLeadTime': 'La livraison est possible au plus tôt dans 6 heures. Choisissez une heure ultérieure ou un autre jour.',
  },
  'nl': {
    'validationMinDays': 'De minimale huurduur voor deze motor is {n} dagen.',
    'validationMaxDays': 'De maximale huurduur voor deze motor is {n} dagen.',
    'validationPastPickup': 'Het ophaaltijdstip is al verstreken. Achteraf reserveren kan niet – kies een tijdstip in de toekomst.',
    'validationDeliveryLeadTime': 'Bezorging is op zijn vroegst over 6 uur vanaf nu mogelijk. Kies een later tijdstip of een andere dag.',
  },
  'pl': {
    'validationMinDays': 'Minimalny czas wynajmu tego motocykla to {n} dni.',
    'validationMaxDays': 'Maksymalny czas wynajmu tego motocykla to {n} dni.',
    'validationPastPickup': 'Godzina odbioru już minęła. Nie można rezerwować wstecz – wybierz godzinę w przyszłości.',
    'validationDeliveryLeadTime': 'Dostawa jest możliwa najwcześniej za 6 godzin od teraz. Wybierz późniejszą godzinę lub inny dzień.',
  },
};
