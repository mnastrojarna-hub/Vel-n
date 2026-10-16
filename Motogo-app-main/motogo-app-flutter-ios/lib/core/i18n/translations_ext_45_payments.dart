/// Platby D1 — oprava po kontrole (2026-10-16): zbytek do 1 Kč, který server
/// nedokázal ověřit k odpuštění (`below_minimum` + `waiver_unverified`: SOS
/// náhrada, platba s objednávkou, úprava místa / doplňků / slevy) — platí se
/// 15 Kč s dorovnáním. Žádné kontakty (D5). 8 jazyků, tyká se.
/// D3 (oprava 2026-10-16): obnovení zrušené rezervace odmítnuté, protože ceník se
/// mezitím změnil (`price_changed`, SQL 20261016p2) → nová rezervace za aktuální cenu.
const Map<String, Map<String, String>> translationsExt45Payments = {
  'cs': {
    'pdWaiverUnverifiedBody': 'K zaplacení zbývá {amount}. Částky do 1 Kč neúčtujeme jen tehdy, když je dokážeme ověřit – u téhle platby to teď nejde, proto ji nemůžeme odpustit. Kartou jde zaplatit nejméně 15 Kč: zaplať 15 Kč, rozdíl {rounding} uvidíš na dokladu jako dorovnání. Zatím jsme nic nestrhli.',
    'pdRestorePriceChanged': 'Ceník se od vytvoření rezervace změnil, proto ji za původní cenu obnovit nejde. Nic jsme nestrhli. Vytvoř si prosím novou rezervaci – cenu spočítáme podle aktuálního ceníku.',
  },
  'en': {
    'pdWaiverUnverifiedBody': 'There is {amount} left to pay. We only waive amounts up to 1 CZK when we can verify them – for this payment that isn’t possible right now, so we can’t waive it. Cards can only be charged at least 15 CZK: pay 15 CZK – you’ll see the difference of {rounding} on the receipt as a top-up. Nothing has been charged yet.',
    'pdRestorePriceChanged': 'Prices have changed since this booking was created, so it can’t be restored at the original price. Nothing has been charged. Please create a new booking – we’ll calculate the price from the current price list.',
  },
  'de': {
    'pdWaiverUnverifiedBody': 'Es sind noch {amount} offen. Beträge bis 1 CZK erlassen wir nur, wenn wir sie prüfen können – bei dieser Zahlung geht das gerade nicht, deshalb können wir den Betrag nicht erlassen. Mit Karte kann man mindestens 15 CZK zahlen: Zahl 15 CZK – die Differenz von {rounding} siehst du auf dem Beleg als Aufrundung. Bisher wurde nichts abgebucht.',
    'pdRestorePriceChanged': 'Die Preise haben sich seit dem Anlegen der Buchung geändert, deshalb lässt sie sich nicht zum ursprünglichen Preis wiederherstellen. Es wurde nichts abgebucht. Leg bitte eine neue Buchung an – den Preis berechnen wir nach der aktuellen Preisliste.',
  },
  'es': {
    'pdWaiverUnverifiedBody': 'Quedan {amount} por pagar. Solo perdonamos importes de hasta 1 CZK cuando podemos verificarlos; en este pago ahora no es posible, así que no podemos perdonarlo. Con tarjeta se puede pagar como mínimo 15 CZK: paga 15 CZK y la diferencia de {rounding} aparecerá en el justificante como redondeo. Todavía no hemos cobrado nada.',
    'pdRestorePriceChanged': 'Los precios han cambiado desde que se creó la reserva, por eso no se puede restaurar al precio original. No hemos cobrado nada. Crea una reserva nueva: calcularemos el precio según la tarifa actual.',
  },
  'fr': {
    'pdWaiverUnverifiedBody': 'Il reste {amount} à payer. Nous n’offrons les montants jusqu’à 1 CZK que lorsque nous pouvons les vérifier – pour ce paiement, ce n’est pas possible pour l’instant, nous ne pouvons donc pas l’offrir. Une carte ne peut être débitée que d’au moins 15 CZK : paie 15 CZK – la différence de {rounding} figurera sur le justificatif comme complément. Rien n’a encore été débité.',
    'pdRestorePriceChanged': 'Les tarifs ont changé depuis la création de la réservation, elle ne peut donc pas être restaurée au prix d’origine. Rien n’a été débité. Crée une nouvelle réservation – nous calculerons le prix selon les tarifs actuels.',
  },
  'nl': {
    'pdWaiverUnverifiedBody': 'Er staat nog {amount} open. Bedragen tot 1 CZK schelden we alleen kwijt als we ze kunnen controleren – bij deze betaling kan dat nu niet, dus we kunnen het niet kwijtschelden. Met een kaart kun je minimaal 15 CZK betalen: betaal 15 CZK – het verschil van {rounding} zie je op het betaalbewijs als aanvulling. Er is nog niets afgeschreven.',
    'pdRestorePriceChanged': 'De prijzen zijn veranderd sinds de boeking is gemaakt, daarom kan ze niet tegen de oorspronkelijke prijs worden hersteld. Er is niets afgeschreven. Maak een nieuwe boeking – we berekenen de prijs volgens de actuele prijslijst.',
  },
  'pl': {
    'pdWaiverUnverifiedBody': 'Do zapłaty zostało {amount}. Kwoty do 1 CZK umarzamy tylko wtedy, gdy możemy je zweryfikować – przy tej płatności teraz się nie da, więc nie możemy jej umorzyć. Kartą można zapłacić co najmniej 15 CZK: zapłać 15 CZK – różnicę {rounding} zobaczysz na dowodzie jako wyrównanie. Na razie nic nie pobraliśmy.',
    'pdRestorePriceChanged': 'Cennik zmienił się od utworzenia rezerwacji, dlatego nie da się jej przywrócić w pierwotnej cenie. Nic nie pobraliśmy. Utwórz nową rezerwację – cenę obliczymy według aktualnego cennika.',
  },
  'uk': {
    'pdWaiverUnverifiedBody': 'До сплати лишилося {amount}. Суми до 1 CZK ми прощаємо лише тоді, коли можемо їх перевірити, — для цього платежу зараз це неможливо, тож простити його ми не можемо. Карткою можна заплатити щонайменше 15 CZK: заплати 15 CZK — різницю {rounding} побачиш у квитанції як доплату до мінімуму. Поки що ми нічого не списали.',
    'pdRestorePriceChanged': 'Ціни змінилися відтоді, як було створено бронювання, тому відновити його за початковою ціною не можна. Ми нічого не списали. Створи нове бронювання — ціну розрахуємо за актуальним прайсом.',
  },
};
