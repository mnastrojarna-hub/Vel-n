/// Samoobslužná pobočka — čas vyzvednutí (zadání majitele 2026-10-01 večer):
/// zákazník volí čas vyzvednutí (sleva 50 % na 1. den od 12:00), čas vrácení
/// ne; rezervaci se slevou kiosk vydá až od 12:00. Nápověda u výběru času,
/// poznámka v detailu / potvrzení, protokol před 12:00, stará hodnota 00:01.
/// `{datum}` = datum začátku (výdej od 12:00 Europe/Prague).
/// Merged into the global translations map.
const Map<String, Map<String, String>> translationsExt29SelfServiceTime = {
  'cs': {
    'ssPickupHint': 'Na samoobslužné pobočce volíte jen čas vyzvednutí — motorku vrátíte kdykoliv poslední den do 24:00. Při vyzvednutí od 12:00 (výpůjčka 2 a více dní) máte 1. den za polovinu a kiosk vám motorku vydá až od 12:00.',
    'ssLateGateNote': 'Sleva za vyzvednutí od 12:00: kiosk vám motorku vydá {datum} od 12:00. Chcete ji dřív? Upravte čas vyzvednutí — sleva zanikne a rozdíl doplatíte.',
    'ssLateGateCta': 'Upravit čas vyzvednutí',
    'ssPickupAnyTime': 'Kdykoliv během prvního dne',
    'ssProtocolBeforeRelease': 'Předávací protokol půjde podepsat {datum} od 12:00 (sleva za vyzvednutí od 12:00).',
    'activePickupTimeLocked': 'Motorka už byla vyzvednuta — čas vyzvednutí už nelze změnit.',
  },
  'en': {
    'ssPickupHint': 'At a self-service branch you only choose the pickup time — you can return the motorcycle any time on the last day until 24:00. With pickup from 12:00 (rental of 2 or more days) the 1st day is half price and the kiosk releases the motorcycle only from 12:00.',
    'ssLateGateNote': 'Discount for pickup from 12:00: the kiosk will release the motorcycle on {datum} from 12:00. Need it earlier? Change the pickup time — the discount will be removed and you will pay the difference.',
    'ssLateGateCta': 'Change pickup time',
    'ssPickupAnyTime': 'Any time during the first day',
    'ssProtocolBeforeRelease': 'The handover protocol can be signed on {datum} from 12:00 (discount for pickup from 12:00).',
    'activePickupTimeLocked': 'The motorcycle has already been picked up — the pickup time can no longer be changed.',
  },
  'de': {
    'ssPickupHint': 'In einer Selbstbedienungs-Filiale wählen Sie nur die Abholzeit — das Motorrad geben Sie am letzten Tag jederzeit bis 24:00 zurück. Bei Abholung ab 12:00 (Miete ab 2 Tagen) ist der 1. Tag zum halben Preis und der Kiosk gibt Ihnen das Motorrad erst ab 12:00 heraus.',
    'ssLateGateNote': 'Rabatt für Abholung ab 12:00: Der Kiosk gibt Ihnen das Motorrad am {datum} ab 12:00 heraus. Brauchen Sie es früher? Ändern Sie die Abholzeit — der Rabatt entfällt und Sie zahlen die Differenz nach.',
    'ssLateGateCta': 'Abholzeit ändern',
    'ssPickupAnyTime': 'Jederzeit am ersten Tag',
    'ssProtocolBeforeRelease': 'Das Übergabeprotokoll kann am {datum} ab 12:00 unterschrieben werden (Rabatt für Abholung ab 12:00).',
    'activePickupTimeLocked': 'Das Motorrad wurde bereits abgeholt — die Abholzeit kann nicht mehr geändert werden.',
  },
  'es': {
    'ssPickupHint': 'En una sucursal de autoservicio solo elige la hora de recogida — la moto la devuelve cuando quiera el último día hasta las 24:00. Con recogida desde las 12:00 (alquiler de 2 o más días) el 1.er día es a mitad de precio y el quiosco le entrega la moto solo a partir de las 12:00.',
    'ssLateGateNote': 'Descuento por recogida desde las 12:00: el quiosco le entregará la moto el {datum} a partir de las 12:00. ¿La necesita antes? Cambie la hora de recogida — el descuento desaparecerá y pagará la diferencia.',
    'ssLateGateCta': 'Cambiar la hora de recogida',
    'ssPickupAnyTime': 'En cualquier momento del primer día',
    'ssProtocolBeforeRelease': 'El protocolo de entrega se podrá firmar el {datum} a partir de las 12:00 (descuento por recogida desde las 12:00).',
    'activePickupTimeLocked': 'La moto ya ha sido recogida — la hora de recogida ya no se puede cambiar.',
  },
  'fr': {
    'ssPickupHint': 'Dans une agence en libre-service, vous choisissez seulement l’heure de retrait — vous rendez la moto quand vous voulez le dernier jour jusqu’à 24:00. Avec un retrait à partir de 12:00 (location de 2 jours ou plus), le 1er jour est à moitié prix et la borne ne vous remet la moto qu’à partir de 12:00.',
    'ssLateGateNote': 'Remise pour retrait à partir de 12:00 : la borne vous remettra la moto le {datum} à partir de 12:00. Vous en avez besoin plus tôt ? Modifiez l’heure de retrait — la remise sera supprimée et vous paierez la différence.',
    'ssLateGateCta': 'Modifier l’heure de retrait',
    'ssPickupAnyTime': 'À tout moment le premier jour',
    'ssProtocolBeforeRelease': 'Le protocole de remise pourra être signé le {datum} à partir de 12:00 (remise pour retrait à partir de 12:00).',
    'activePickupTimeLocked': 'La moto a déjà été retirée — l’heure de retrait ne peut plus être modifiée.',
  },
  'nl': {
    'ssPickupHint': 'Bij een selfservicevestiging kiest u alleen de ophaaltijd — de motor brengt u op de laatste dag op elk moment tot 24:00 terug. Bij ophalen vanaf 12:00 (huur van 2 of meer dagen) is de 1e dag voor de halve prijs en geeft de kiosk u de motor pas vanaf 12:00 mee.',
    'ssLateGateNote': 'Korting voor ophalen vanaf 12:00: de kiosk geeft u de motor op {datum} vanaf 12:00 mee. Heeft u hem eerder nodig? Wijzig de ophaaltijd — de korting vervalt en u betaalt het verschil bij.',
    'ssLateGateCta': 'Ophaaltijd wijzigen',
    'ssPickupAnyTime': 'Op elk moment tijdens de eerste dag',
    'ssProtocolBeforeRelease': 'Het overdrachtsprotocol kan op {datum} vanaf 12:00 worden ondertekend (korting voor ophalen vanaf 12:00).',
    'activePickupTimeLocked': 'De motor is al opgehaald — de ophaaltijd kan niet meer worden gewijzigd.',
  },
  'pl': {
    'ssPickupHint': 'W oddziale samoobsługowym wybierasz tylko godzinę odbioru — motocykl zwracasz w dowolnym momencie ostatniego dnia do 24:00. Przy odbiorze od 12:00 (wynajem na 2 lub więcej dni) 1. dzień jest za pół ceny, a kiosk wyda Ci motocykl dopiero od 12:00.',
    'ssLateGateNote': 'Zniżka za odbiór od 12:00: kiosk wyda Ci motocykl {datum} od 12:00. Potrzebujesz go wcześniej? Zmień godzinę odbioru — zniżka przepadnie, a różnicę dopłacisz.',
    'ssLateGateCta': 'Zmień godzinę odbioru',
    'ssPickupAnyTime': 'W dowolnym momencie pierwszego dnia',
    'ssProtocolBeforeRelease': 'Protokół zdawczo-odbiorczy będzie można podpisać {datum} od 12:00 (zniżka za odbiór od 12:00).',
    'activePickupTimeLocked': 'Motocykl został już odebrany — godziny odbioru nie można już zmienić.',
  },
  'uk': {
    'ssPickupHint': 'На філії самообслуговування ви обираєте лише час отримання — мотоцикл повернете будь-коли в останній день до 24:00. При отриманні з 12:00 (оренда від 2 днів) перший день коштує половину, а кіоск видасть вам мотоцикл лише з 12:00.',
    'ssLateGateNote': 'Знижка за отримання з 12:00: кіоск видасть вам мотоцикл {datum} з 12:00. Потрібен раніше? Змініть час отримання — знижка зникне, і ви доплатите різницю.',
    'ssLateGateCta': 'Змінити час отримання',
    'ssPickupAnyTime': 'Будь-коли протягом першого дня',
    'ssProtocolBeforeRelease': 'Протокол передачі можна буде підписати {datum} з 12:00 (знижка за отримання з 12:00).',
    'activePickupTimeLocked': 'Мотоцикл уже отримано — час отримання більше не можна змінити.',
  },
};
