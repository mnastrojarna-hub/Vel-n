/// SOS náhradní motorka (fix:shared r4): seznam nabízí jen motorky volné do
/// konce pronájmu; když server přesto odmítne („není do konce pronájmu
/// volná“ — mezitím ji někdo vzal), zákazník dostane důvod a vrátí se do
/// seznamu místo slepého „Zkusit znovu“. Oba stromy appky, tyká se.
const Map<String, Map<String, String>> translationsExt64SosReplace = {
  'cs': {
    'sosReplaceTakenTitle': 'Tahle motorka už není volná',
    'sosReplaceTakenBody': 'Vybraná motorka není do konce tvého pronájmu volná — mezitím si ji někdo zarezervoval nebo míří do servisu. Vyber prosím jinou, nabídku jsme právě obnovili.',
    'sosReplacePickOther': 'Vybrat jinou',
  },
  'en': {
    'sosReplaceTakenTitle': 'This bike is no longer free',
    'sosReplaceTakenBody': 'The bike you picked is not free until the end of your rental — someone booked it in the meantime or it is due for service. Please pick another one, the list has just been refreshed.',
    'sosReplacePickOther': 'Pick another',
  },
  'de': {
    'sosReplaceTakenTitle': 'Dieses Motorrad ist nicht mehr frei',
    'sosReplaceTakenBody': 'Das gewählte Motorrad ist bis zum Ende deiner Miete nicht frei — jemand hat es inzwischen gebucht oder es muss in den Service. Wähle bitte ein anderes, die Liste wurde gerade aktualisiert.',
    'sosReplacePickOther': 'Anderes wählen',
  },
  'es': {
    'sosReplaceTakenTitle': 'Esta moto ya no está libre',
    'sosReplaceTakenBody': 'La moto que elegiste no está libre hasta el final de tu alquiler: alguien la reservó mientras tanto o tiene que pasar por el taller. Elige otra, por favor; acabamos de actualizar la lista.',
    'sosReplacePickOther': 'Elegir otra',
  },
  'fr': {
    'sosReplaceTakenTitle': 'Cette moto n\'est plus libre',
    'sosReplaceTakenBody': 'La moto choisie n\'est pas libre jusqu\'à la fin de ta location : quelqu\'un l\'a réservée entre-temps ou elle part en entretien. Choisis-en une autre, la liste vient d\'être actualisée.',
    'sosReplacePickOther': 'En choisir une autre',
  },
  'nl': {
    'sosReplaceTakenTitle': 'Deze motor is niet meer vrij',
    'sosReplaceTakenBody': 'De gekozen motor is niet vrij tot het einde van je huur — iemand heeft hem intussen geboekt of hij moet naar de service. Kies een andere, de lijst is net ververst.',
    'sosReplacePickOther': 'Andere kiezen',
  },
  'pl': {
    'sosReplaceTakenTitle': 'Ten motocykl nie jest już wolny',
    'sosReplaceTakenBody': 'Wybrany motocykl nie jest wolny do końca twojego wynajmu — ktoś go w międzyczasie zarezerwował albo jedzie do serwisu. Wybierz proszę inny, lista została właśnie odświeżona.',
    'sosReplacePickOther': 'Wybierz inny',
  },
  'uk': {
    'sosReplaceTakenTitle': 'Цей мотоцикл уже не вільний',
    'sosReplaceTakenBody': 'Обраний мотоцикл не вільний до кінця твоєї оренди — хтось тим часом його забронював або він їде на сервіс. Обери, будь ласка, інший, список щойно оновлено.',
    'sosReplacePickOther': 'Обрати інший',
  },
};
