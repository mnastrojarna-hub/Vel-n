/// Rental-length validation messages (min/max rental days enforced from
/// motorcycles.min_rental_days / max_rental_days, like the web). `{n}` = day
/// count. Merged into the global translations map.
const Map<String, Map<String, String>> translationsExt5Validation = {
  'cs': {
    'validationMinDays': 'Minimální délka pronájmu této motorky je {n} dní.',
    'validationMaxDays': 'Maximální délka pronájmu této motorky je {n} dní.',
    'validationPastPickup': 'Čas vyzvednutí už uplynul. Rezervaci nelze vytvořit zpětně – vyberte čas v budoucnosti.',
    'validationStaffedLeadTime': 'Na obslužné pobočce je vyzvednutí možné nejdříve za 1 hodinu od teď. Vyberte pozdější čas.',
    'validationDeliveryLeadTime': 'Přistavení je možné nejdříve za 6 hodin od teď. Vyberte pozdější čas nebo jiný den.',
  },
  'en': {
    'validationMinDays': 'The minimum rental length for this motorcycle is {n} days.',
    'validationMaxDays': 'The maximum rental length for this motorcycle is {n} days.',
    'validationPastPickup': 'The pickup time has already passed. You cannot book retroactively – choose a time in the future.',
    'validationStaffedLeadTime': 'At a staffed branch, pickup is available no sooner than 1 hour from now. Choose a later time.',
    'validationDeliveryLeadTime': 'Delivery is available no sooner than 6 hours from now. Choose a later time or another day.',
  },
  'de': {
    'validationMinDays': 'Die Mindestmietdauer für dieses Motorrad beträgt {n} Tage.',
    'validationMaxDays': 'Die maximale Mietdauer für dieses Motorrad beträgt {n} Tage.',
    'validationPastPickup': 'Die Abholzeit ist bereits vergangen. Eine rückwirkende Buchung ist nicht möglich – wählen Sie eine Zeit in der Zukunft.',
    'validationStaffedLeadTime': 'In einer besetzten Filiale ist die Abholung frühestens in 1 Stunde ab jetzt möglich. Wählen Sie eine spätere Zeit.',
    'validationDeliveryLeadTime': 'Die Lieferung ist frühestens in 6 Stunden ab jetzt möglich. Wählen Sie eine spätere Zeit oder einen anderen Tag.',
  },
  'es': {
    'validationMinDays': 'La duración mínima de alquiler de esta moto es de {n} días.',
    'validationMaxDays': 'La duración máxima de alquiler de esta moto es de {n} días.',
    'validationPastPickup': 'La hora de recogida ya ha pasado. No se puede reservar de forma retroactiva: elige una hora futura.',
    'validationStaffedLeadTime': 'En una sucursal atendida, la recogida está disponible como mínimo 1 hora a partir de ahora. Elige una hora posterior.',
    'validationDeliveryLeadTime': 'La entrega está disponible como mínimo 6 horas a partir de ahora. Elige una hora posterior u otro día.',
  },
  'fr': {
    'validationMinDays': 'La durée minimale de location de cette moto est de {n} jours.',
    'validationMaxDays': 'La durée maximale de location de cette moto est de {n} jours.',
    'validationPastPickup': 'L\'heure de prise en charge est déjà passée. Impossible de réserver rétroactivement – choisissez une heure future.',
    'validationStaffedLeadTime': 'Dans une agence avec personnel, la prise en charge est possible au plus tôt dans 1 heure. Choisissez une heure ultérieure.',
    'validationDeliveryLeadTime': 'La livraison est possible au plus tôt dans 6 heures. Choisissez une heure ultérieure ou un autre jour.',
  },
  'nl': {
    'validationMinDays': 'De minimale huurduur voor deze motor is {n} dagen.',
    'validationMaxDays': 'De maximale huurduur voor deze motor is {n} dagen.',
    'validationPastPickup': 'Het ophaaltijdstip is al verstreken. Achteraf reserveren kan niet – kies een tijdstip in de toekomst.',
    'validationStaffedLeadTime': 'Bij een bemande vestiging is ophalen op zijn vroegst over 1 uur vanaf nu mogelijk. Kies een later tijdstip.',
    'validationDeliveryLeadTime': 'Bezorging is op zijn vroegst over 6 uur vanaf nu mogelijk. Kies een later tijdstip of een andere dag.',
  },
  'pl': {
    'validationMinDays': 'Minimalny czas wynajmu tego motocykla to {n} dni.',
    'validationMaxDays': 'Maksymalny czas wynajmu tego motocykla to {n} dni.',
    'validationPastPickup': 'Godzina odbioru już minęła. Nie można rezerwować wstecz – wybierz godzinę w przyszłości.',
    'validationStaffedLeadTime': 'W oddziale z obsługą odbiór jest możliwy najwcześniej za 1 godzinę od teraz. Wybierz późniejszą godzinę.',
    'validationDeliveryLeadTime': 'Dostawa jest możliwa najwcześniej za 6 godzin od teraz. Wybierz późniejszą godzinę lub inny dzień.',
  },
};
