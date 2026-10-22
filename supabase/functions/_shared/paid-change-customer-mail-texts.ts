// ===== _shared/paid-change-customer-mail-texts.ts =====
// Texty e-mailu zákazníkovi o nezapsané zaplacené změně (8 jazyků) — logika v paid-change-customer-mail.ts.
// Vykání (cs), bez kontaktů (D5).
export type Lang = 'cs' | 'en' | 'de' | 'nl' | 'es' | 'fr' | 'pl' | 'uk'
export const LANGS: Lang[] = ['cs', 'en', 'de', 'nl', 'es', 'fr', 'pl', 'uk']
export type T = { subjTaken: string; subjFailed: string; hello: string; taken: string; failed: string; unchanged: string
  auto: string; staff: string; nextTaken: string; nextFailed: string; cta: string; sign: string }

// {num} = číslo rezervace, {amount} = doplatek
export const TX: Record<Lang, T> = {
  cs: { subjTaken: 'Rezervace #{num}: motorka je mezitím obsazená – doplatek vracíme', subjFailed: 'Rezervace #{num}: změnu nešlo zapsat – doplatek vracíme',
    hello: 'Dobrý den,', taken: 'motorka je pro požadovanou změnu mezitím obsazená – během vaší platby si ji zarezervoval někdo jiný a nová rezervace má přednost. Změnu proto nešlo zapsat.',
    failed: 'zaplacenou změnu vaší rezervace nešlo zapsat, protože se rezervace mezitím změnila.', unchanged: 'Vaše rezervace č. {num} platí beze změny.',
    auto: 'Doplatek {amount} vám automaticky vracíme na kartu – peníze bývají zpět do 5–10 pracovních dnů.', staff: 'Doplatek {amount} vám vrátí naše obsluha do 2 pracovních dnů – nemusíte nic dělat.',
    nextTaken: 'V úpravě rezervace můžete zvolit jinou motorku nebo jiný termín, nebo nechat rezervaci tak, jak je – pak nemusíte dělat nic.', nextFailed: 'Úpravu můžete zkusit znovu v úpravě rezervace.',
    cta: 'Upravit rezervaci', sign: 'Tým MotoGo24' },
  en: { subjTaken: 'Booking #{num}: the motorcycle has been booked meanwhile – we are refunding the surcharge', subjFailed: 'Booking #{num}: the change could not be saved – we are refunding the surcharge',
    hello: 'Hello,', taken: 'the motorcycle needed for your change has been booked by someone else while you were paying, and the new booking takes priority. That is why the change could not be saved.',
    failed: 'the paid change to your booking could not be saved because the booking changed in the meantime.', unchanged: 'Your booking #{num} stays unchanged.',
    auto: 'We are automatically refunding the surcharge of {amount} to your card – the money usually arrives within 5–10 business days.', staff: 'Our staff will refund the surcharge of {amount} within 2 business days – you do not need to do anything.',
    nextTaken: 'You can choose another motorcycle or other dates in the booking editor, or keep your booking as it is – then there is nothing to do.', nextFailed: 'You can try the change again in the booking editor.',
    cta: 'Edit booking', sign: 'MOTO GO 24 Team' },
  de: { subjTaken: 'Buchung #{num}: Das Motorrad ist inzwischen belegt – wir erstatten die Zuzahlung', subjFailed: 'Buchung #{num}: Die Änderung konnte nicht gespeichert werden – wir erstatten die Zuzahlung',
    hello: 'Guten Tag,', taken: 'das Motorrad für Ihre Änderung wurde während Ihrer Zahlung von jemand anderem gebucht, und die neue Buchung hat Vorrang. Die Änderung konnte daher nicht gespeichert werden.',
    failed: 'die bezahlte Änderung Ihrer Buchung konnte nicht gespeichert werden, weil sich die Buchung inzwischen geändert hat.', unchanged: 'Ihre Buchung Nr. {num} bleibt unverändert.',
    auto: 'Die Zuzahlung von {amount} erstatten wir automatisch auf Ihre Karte – das Geld ist meist innerhalb von 5–10 Werktagen zurück.', staff: 'Die Zuzahlung von {amount} erstattet Ihnen unser Team innerhalb von 2 Werktagen – Sie müssen nichts tun.',
    nextTaken: 'In der Buchungsbearbeitung können Sie ein anderes Motorrad oder einen anderen Termin wählen oder die Buchung so lassen – dann müssen Sie nichts tun.', nextFailed: 'Sie können die Änderung in der Buchungsbearbeitung erneut versuchen.',
    cta: 'Buchung bearbeiten', sign: 'Ihr MOTO GO 24 Team' },
  nl: { subjTaken: 'Boeking #{num}: de motor is intussen bezet – we betalen de bijbetaling terug', subjFailed: 'Boeking #{num}: de wijziging kon niet worden opgeslagen – we betalen de bijbetaling terug',
    hello: 'Goedendag,', taken: 'de motor voor je wijziging is tijdens je betaling door iemand anders geboekt en de nieuwe boeking heeft voorrang. Daarom kon de wijziging niet worden opgeslagen.',
    failed: 'de betaalde wijziging van je boeking kon niet worden opgeslagen, omdat de boeking intussen is gewijzigd.', unchanged: 'Je boeking nr. {num} blijft ongewijzigd.',
    auto: 'De bijbetaling van {amount} betalen we automatisch terug op je kaart – het geld staat er meestal binnen 5–10 werkdagen.', staff: 'Ons team betaalt de bijbetaling van {amount} binnen 2 werkdagen terug – je hoeft niets te doen.',
    nextTaken: 'Bij het aanpassen van je boeking kun je een andere motor of andere data kiezen, of de boeking laten zoals ze is – dan hoef je niets te doen.', nextFailed: 'Je kunt de wijziging opnieuw proberen bij het aanpassen van je boeking.',
    cta: 'Boeking aanpassen', sign: 'MOTO GO 24 Team' },
  es: { subjTaken: 'Reserva n.º {num}: la moto ya está ocupada – te devolvemos el suplemento', subjFailed: 'Reserva n.º {num}: no se pudo guardar el cambio – te devolvemos el suplemento',
    hello: 'Hola,', taken: 'la moto necesaria para tu cambio la ha reservado otra persona mientras pagabas y la nueva reserva tiene prioridad. Por eso no se pudo guardar el cambio.',
    failed: 'no se pudo guardar el cambio pagado de tu reserva porque la reserva cambió entretanto.', unchanged: 'Tu reserva n.º {num} sigue sin cambios.',
    auto: 'Te devolvemos automáticamente el suplemento de {amount} a tu tarjeta – el dinero suele llegar en 5–10 días hábiles.', staff: 'Nuestro equipo te devolverá el suplemento de {amount} en 2 días hábiles – no tienes que hacer nada.',
    nextTaken: 'En la edición de la reserva puedes elegir otra moto u otras fechas, o dejar la reserva como está – en ese caso no tienes que hacer nada.', nextFailed: 'Puedes volver a intentar el cambio en la edición de la reserva.',
    cta: 'Editar reserva', sign: 'Equipo MOTO GO 24' },
  fr: { subjTaken: 'Réservation n° {num} : la moto est entre-temps réservée – nous remboursons le supplément', subjFailed: 'Réservation n° {num} : la modification n’a pas pu être enregistrée – nous remboursons le supplément',
    hello: 'Bonjour,', taken: 'la moto nécessaire à votre modification a été réservée par quelqu’un d’autre pendant votre paiement, et la nouvelle réservation est prioritaire. La modification n’a donc pas pu être enregistrée.',
    failed: 'la modification payée de votre réservation n’a pas pu être enregistrée, car la réservation a changé entre-temps.', unchanged: 'Votre réservation n° {num} reste inchangée.',
    auto: 'Nous vous remboursons automatiquement le supplément de {amount} sur votre carte – l’argent revient généralement sous 5 à 10 jours ouvrés.', staff: 'Notre équipe vous remboursera le supplément de {amount} sous 2 jours ouvrés – vous n’avez rien à faire.',
    nextTaken: 'Dans la modification de la réservation, vous pouvez choisir une autre moto ou d’autres dates, ou laisser la réservation telle quelle – vous n’avez alors rien à faire.', nextFailed: 'Vous pouvez réessayer la modification dans l’édition de la réservation.',
    cta: 'Modifier la réservation', sign: 'Équipe MOTO GO 24' },
  pl: { subjTaken: 'Rezerwacja nr {num}: motocykl jest już zajęty – zwracamy dopłatę', subjFailed: 'Rezerwacja nr {num}: nie udało się zapisać zmiany – zwracamy dopłatę',
    hello: 'Dzień dobry,', taken: 'motocykl potrzebny do Twojej zmiany został w trakcie płatności zarezerwowany przez kogoś innego, a nowa rezerwacja ma pierwszeństwo. Dlatego zmiany nie udało się zapisać.',
    failed: 'opłaconej zmiany Twojej rezerwacji nie udało się zapisać, ponieważ rezerwacja w międzyczasie się zmieniła.', unchanged: 'Twoja rezerwacja nr {num} pozostaje bez zmian.',
    auto: 'Dopłatę {amount} automatycznie zwracamy na Twoją kartę – pieniądze zwykle wracają w ciągu 5–10 dni roboczych.', staff: 'Dopłatę {amount} zwróci nasza obsługa w ciągu 2 dni roboczych – nie musisz nic robić.',
    nextTaken: 'W edycji rezerwacji możesz wybrać inny motocykl lub inny termin albo zostawić rezerwację bez zmian – wtedy nie musisz nic robić.', nextFailed: 'Zmianę możesz spróbować ponownie w edycji rezerwacji.',
    cta: 'Edytuj rezerwację', sign: 'Zespół MOTO GO 24' },
  uk: { subjTaken: 'Бронювання № {num}: мотоцикл тим часом зайнятий – повертаємо доплату', subjFailed: 'Бронювання № {num}: зміну не вдалося зберегти – повертаємо доплату',
    hello: 'Доброго дня,', taken: 'мотоцикл, потрібний для вашої зміни, під час вашої оплати забронював хтось інший, і нове бронювання має пріоритет. Тому зміну не вдалося зберегти.',
    failed: 'оплачену зміну вашого бронювання не вдалося зберегти, бо бронювання тим часом змінилося.', unchanged: 'Ваше бронювання № {num} залишається без змін.',
    auto: 'Доплату {amount} ми автоматично повертаємо на вашу картку – гроші зазвичай надходять протягом 5–10 робочих днів.', staff: 'Доплату {amount} поверне наша команда протягом 2 робочих днів – вам нічого не потрібно робити.',
    nextTaken: 'У редагуванні бронювання можна вибрати інший мотоцикл чи інші дати або залишити бронювання як є – тоді нічого робити не потрібно.', nextFailed: 'Зміну можна спробувати ще раз у редагуванні бронювання.',
    cta: 'Редагувати бронювання', sign: 'Команда MOTO GO 24' },
}
