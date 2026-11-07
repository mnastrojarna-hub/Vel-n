/// Rezervace bez dvojího vyplňování (majitel 2026-10-22: „neměl by nikdy
/// zákazník nic vyplňovat dvakrát“): rychlá volba adresy (z profilu / stejná
/// jako druhá strana předání), předvyplněné velikosti spolujezdce a bot
/// z minulé rezervace, vlastní dárkové poukazy jedním klepnutím.
/// Klíče `bk*` sdílí oba stromy appky. Tyká se ve všech jazycích.
const Map<String, Map<String, String>> translationsExt46BookingPrefill = {
  'cs': {
    'bkAddrMine': 'Moje adresa z profilu',
    'bkAddrSamePickup': 'Stejná jako u přistavení',
    'bkAddrSameReturn': 'Stejná jako u odvozu',
    'bkSizesFromLast': 'Velikosti jsme předvyplnili podle minulé rezervace – zkontroluj je a potvrď.',
    'bkSizeLastTag': 'naposledy',
    'bkMyVouchers': 'Tvoje dárkové poukazy',
    'bkVoucherUseA11y': 'Použít poukaz {code} v hodnotě {amount}',
  },
  'en': {
    'bkAddrMine': 'My address from my profile',
    'bkAddrSamePickup': 'Same as the delivery address',
    'bkAddrSameReturn': 'Same as the collection address',
    'bkSizesFromLast': 'We’ve prefilled the sizes from your last booking – check them and confirm.',
    'bkSizeLastTag': 'last time',
    'bkMyVouchers': 'Your gift vouchers',
    'bkVoucherUseA11y': 'Use voucher {code} worth {amount}',
  },
  'de': {
    'bkAddrMine': 'Meine Adresse aus dem Profil',
    'bkAddrSamePickup': 'Wie bei der Lieferung',
    'bkAddrSameReturn': 'Wie bei der Abholung',
    'bkSizesFromLast': 'Wir haben die Größen aus deiner letzten Buchung vorausgefüllt – prüf sie und bestätige.',
    'bkSizeLastTag': 'zuletzt',
    'bkMyVouchers': 'Deine Geschenkgutscheine',
    'bkVoucherUseA11y': 'Gutschein {code} im Wert von {amount} einlösen',
  },
  'es': {
    'bkAddrMine': 'Mi dirección del perfil',
    'bkAddrSamePickup': 'La misma que para la entrega',
    'bkAddrSameReturn': 'La misma que para la recogida',
    'bkSizesFromLast': 'Hemos rellenado las tallas de tu última reserva: revísalas y confirma.',
    'bkSizeLastTag': 'la última vez',
    'bkMyVouchers': 'Tus vales regalo',
    'bkVoucherUseA11y': 'Usar el vale {code} por valor de {amount}',
  },
  'fr': {
    'bkAddrMine': 'Mon adresse du profil',
    'bkAddrSamePickup': 'Identique à la livraison',
    'bkAddrSameReturn': 'Identique à la récupération',
    'bkSizesFromLast': 'Nous avons prérempli les tailles de ta dernière réservation – vérifie-les et confirme.',
    'bkSizeLastTag': 'la dernière fois',
    'bkMyVouchers': 'Tes bons cadeaux',
    'bkVoucherUseA11y': 'Utiliser le bon {code} d’une valeur de {amount}',
  },
  'nl': {
    'bkAddrMine': 'Mijn adres uit mijn profiel',
    'bkAddrSamePickup': 'Hetzelfde als bij de bezorging',
    'bkAddrSameReturn': 'Hetzelfde als bij het ophalen',
    'bkSizesFromLast': 'We hebben de maten van je vorige boeking al ingevuld – controleer ze en bevestig.',
    'bkSizeLastTag': 'vorige keer',
    'bkMyVouchers': 'Je cadeauvouchers',
    'bkVoucherUseA11y': 'Voucher {code} ter waarde van {amount} gebruiken',
  },
  'pl': {
    'bkAddrMine': 'Mój adres z profilu',
    'bkAddrSamePickup': 'Taki sam jak przy dostawie',
    'bkAddrSameReturn': 'Taki sam jak przy odbiorze',
    'bkSizesFromLast': 'Uzupełniliśmy rozmiary z twojej ostatniej rezerwacji – sprawdź je i potwierdź.',
    'bkSizeLastTag': 'ostatnio',
    'bkMyVouchers': 'Twoje vouchery prezentowe',
    'bkVoucherUseA11y': 'Użyj vouchera {code} o wartości {amount}',
  },
  'uk': {
    'bkAddrMine': 'Моя адреса з профілю',
    'bkAddrSamePickup': 'Така сама, як для доставки',
    'bkAddrSameReturn': 'Така сама, як для забору',
    'bkSizesFromLast': 'Ми заповнили розміри з твого останнього бронювання — перевір їх і підтверди.',
    'bkSizeLastTag': 'минулого разу',
    'bkMyVouchers': 'Твої подарункові ваучери',
    'bkVoucherUseA11y': 'Використати ваучер {code} на суму {amount}',
  },
};
