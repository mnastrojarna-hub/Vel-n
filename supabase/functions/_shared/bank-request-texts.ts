// ===== _shared/bank-request-texts.ts =====
// Texty výzvy k platbě QR / převodem pro DÁRKOVÝ POUKAZ (objednávku) a DOPLATEK úpravy rezervace z webu
// v 8 jazycích (cs, en, de, es, fr, nl, pl, uk) — stejný mechanismus jako qr-payment/texts.ts +
// fallback-texts.ts: proměnné do šablon `shop_qr_payment` / `booking_change_qr_payment` (send-email je
// přeloží do jazyka zákazníka) a texty záložního mailu (šablona chybí / je vypnutá / neodešla).
// Čeština vyká, ostatní jazyky tykají (jako ostatní zákaznické texty). Účet, IBAN, VS a částky tu nejsou.
import type { QrLang } from '../qr-payment/texts.ts'

export interface BankRequestTexts {
  /** předmět záložního mailu k objednávce (šablonový mail má předmět ze šablony) */
  orderSubject: (orderNumber: string) => string
  /** pokračování za „Jméno, děkujeme“: „ za objednávku <strong>X</strong>. Uhraďte…“ */
  orderIntro: (numHtml: string) => string
  /** {{deadline}} objednávky — `date` = poslední den lhůty v jazyce zákazníka */
  orderDeadline: (date: string) => string
  orderAfter: string
  /** {{deadline}} doplatku úpravy — `time` = čas konce lhůty (Praha) */
  changeDeadline: (time: string) => string
  /** věta za úvodem: úprava se provede až po připsání */
  changeNote: string
  changeAfter: string
  /** slovo „poukaz / objednávka“ do zprávy pro příjemce v QR (jen ASCII) */
  spdOrder: string
}

export const BANK_TEXTS: Record<QrLang, BankRequestTexts> = {
  cs: {
    orderSubject: (n) => 'Platební údaje k objednávce ' + n + ' — QR / bankovní převod',
    orderIntro: (b) => ' za objednávku ' + b + '. Uhraďte prosím částku bankovním převodem nebo naskenováním QR kódu v mobilní bankovní aplikaci.',
    orderDeadline: (d) => 'Platbu prosím proveďte do ' + d + ' (7 dní). Poukaz vystavíme a pošleme e-mailem hned po připsání platby.',
    orderAfter: 'Jakmile platbu připíšeme (obvykle do několika minut), pošleme vám e-mailem potvrzení s dokladem — u dárkového poukazu i samotný poukaz. Zálohovou fakturu najdete v příloze.',
    changeDeadline: (t) => 'Doplatek prosím uhraďte do ' + t + ' (lhůta 60 minut). Pokud se do té doby platba nepřipíše, úprava se neprovede a rezervace zůstane beze změny.',
    changeNote: 'Úpravu provedeme, jakmile platbu připíšeme — do té doby platí rezervace beze změny.',
    changeAfter: 'Po připsání platby vám úpravu potvrdíme e-mailem spolu s dokladem o platbě a aktualizovanou smlouvou. Kdyby úpravu mezitím nešlo provést (například termín obsadila jiná rezervace), doplatek vám vrátíme a rezervace zůstane beze změny.',
    spdOrder: 'objednavka',
  },
  en: {
    orderSubject: (n) => 'Payment details for order ' + n + ' — QR / bank transfer',
    orderIntro: (b) => ' for your order ' + b + '. Please pay the amount by bank transfer or by scanning the QR code in your mobile banking app.',
    orderDeadline: (d) => 'Please make the payment by ' + d + ' (7 days). We will issue the voucher and e-mail it to you as soon as the payment arrives.',
    orderAfter: 'As soon as the payment arrives (usually within a few minutes), we will e-mail you the confirmation with the receipt — and, for a gift voucher, the voucher itself. The advance invoice is attached.',
    changeDeadline: (t) => 'Please pay the additional amount by ' + t + ' (within 60 minutes). If the payment has not arrived by then, the change will not be made and your booking stays as it is.',
    changeNote: 'We will make the change as soon as the payment arrives — until then your booking stays unchanged.',
    changeAfter: 'Once the payment arrives, we will confirm the change by e-mail together with the payment receipt and the updated contract. If the change can no longer be made in the meantime (for example because the dates were taken by another booking), we will return the payment and your booking stays unchanged.',
    spdOrder: 'order',
  },
  de: {
    orderSubject: (n) => 'Zahlungsdaten zur Bestellung ' + n + ' — QR / Banküberweisung',
    orderIntro: (b) => ' für deine Bestellung ' + b + '. Bitte zahle den Betrag per Banküberweisung oder scanne den QR-Code in deiner Banking-App.',
    orderDeadline: (d) => 'Bitte zahle bis ' + d + ' (7 Tage). Den Gutschein stellen wir aus und schicken ihn dir per E-Mail, sobald die Zahlung eingegangen ist.',
    orderAfter: 'Sobald die Zahlung eingegangen ist (meist innerhalb weniger Minuten), schicken wir dir per E-Mail die Bestätigung mit dem Beleg — bei einem Geschenkgutschein auch den Gutschein selbst. Die Vorschussrechnung findest du im Anhang.',
    changeDeadline: (t) => 'Bitte zahle die Nachzahlung bis ' + t + ' (innerhalb von 60 Minuten). Geht die Zahlung bis dahin nicht ein, wird die Änderung nicht durchgeführt und die Reservierung bleibt unverändert.',
    changeNote: 'Wir führen die Änderung durch, sobald die Zahlung eingegangen ist — bis dahin gilt die Reservierung unverändert.',
    changeAfter: 'Sobald die Zahlung eingegangen ist, bestätigen wir dir die Änderung per E-Mail zusammen mit dem Zahlungsbeleg und dem aktualisierten Vertrag. Sollte die Änderung inzwischen nicht mehr möglich sein (zum Beispiel weil der Termin anderweitig belegt wurde), erstatten wir dir die Nachzahlung und die Reservierung bleibt unverändert.',
    spdOrder: 'Bestellung',
  },
  es: {
    orderSubject: (n) => 'Datos de pago del pedido ' + n + ' — QR / transferencia bancaria',
    orderIntro: (b) => ' por tu pedido ' + b + '. Paga el importe por transferencia bancaria o escaneando el código QR en la app de tu banco.',
    orderDeadline: (d) => 'Realiza el pago antes del ' + d + ' (7 días). Emitiremos el vale y te lo enviaremos por correo electrónico en cuanto recibamos el pago.',
    orderAfter: 'En cuanto recibamos el pago (normalmente en unos minutos), te enviaremos por correo electrónico la confirmación con el justificante y, si es un vale regalo, también el vale. La factura de anticipo va adjunta.',
    changeDeadline: (t) => 'Paga el suplemento antes de las ' + t + ' (en un plazo de 60 minutos). Si el pago no ha llegado para entonces, el cambio no se realizará y la reserva quedará como está.',
    changeNote: 'Haremos el cambio en cuanto recibamos el pago; hasta entonces la reserva sigue sin cambios.',
    changeAfter: 'Cuando recibamos el pago, te confirmaremos el cambio por correo electrónico junto con el justificante de pago y el contrato actualizado. Si entretanto el cambio ya no fuera posible (por ejemplo, porque otra reserva ocupó las fechas), te devolveremos el pago y la reserva quedará sin cambios.',
    spdOrder: 'pedido',
  },
  fr: {
    orderSubject: (n) => 'Coordonnées de paiement de la commande ' + n + ' — QR / virement bancaire',
    orderIntro: (b) => ' pour ta commande ' + b + '. Merci de régler le montant par virement bancaire ou en scannant le code QR dans ton application bancaire.',
    orderDeadline: (d) => 'Merci d’effectuer le paiement avant le ' + d + ' (7 jours). Nous émettrons le bon et te l’enverrons par e-mail dès réception du paiement.',
    orderAfter: 'Dès réception du paiement (généralement en quelques minutes), nous t’envoyons par e-mail la confirmation avec le justificatif — et, pour un bon cadeau, le bon lui-même. La facture d’acompte est en pièce jointe.',
    changeDeadline: (t) => 'Merci de régler le supplément avant ' + t + ' (dans les 60 minutes). Si le paiement n’est pas arrivé d’ici là, la modification ne sera pas effectuée et la réservation restera inchangée.',
    changeNote: 'Nous effectuerons la modification dès réception du paiement — d’ici là, la réservation reste inchangée.',
    changeAfter: 'Dès réception du paiement, nous te confirmerons la modification par e-mail avec le justificatif de paiement et le contrat mis à jour. Si la modification n’était plus possible entre-temps (par exemple parce que les dates ont été prises par une autre réservation), nous te rembourserons le supplément et la réservation restera inchangée.',
    spdOrder: 'commande',
  },
  nl: {
    orderSubject: (n) => 'Betaalgegevens voor bestelling ' + n + ' — QR / bankoverschrijving',
    orderIntro: (b) => ' voor je bestelling ' + b + '. Betaal het bedrag per bankoverschrijving of scan de QR-code in je bankapp.',
    orderDeadline: (d) => 'Betaal vóór ' + d + ' (7 dagen). We maken de cadeaubon aan en sturen hem per e-mail zodra de betaling binnen is.',
    orderAfter: 'Zodra de betaling binnen is (meestal binnen een paar minuten), sturen we je per e-mail de bevestiging met het betalingsbewijs — en bij een cadeaubon ook de bon zelf. De voorschotfactuur vind je in de bijlage.',
    changeDeadline: (t) => 'Betaal de bijbetaling vóór ' + t + ' (binnen 60 minuten). Is de betaling dan nog niet binnen, dan wordt de wijziging niet doorgevoerd en blijft de reservering ongewijzigd.',
    changeNote: 'We voeren de wijziging door zodra de betaling binnen is — tot die tijd blijft de reservering ongewijzigd.',
    changeAfter: 'Zodra de betaling binnen is, bevestigen we de wijziging per e-mail, samen met het betalingsbewijs en het bijgewerkte contract. Mocht de wijziging intussen niet meer mogelijk zijn (bijvoorbeeld omdat de periode door een andere reservering is bezet), dan storten we de bijbetaling terug en blijft de reservering ongewijzigd.',
    spdOrder: 'bestelling',
  },
  pl: {
    orderSubject: (n) => 'Dane do płatności za zamówienie ' + n + ' — QR / przelew bankowy',
    orderIntro: (b) => ' za zamówienie ' + b + '. Zapłać kwotę przelewem bankowym lub skanując kod QR w aplikacji bankowej.',
    orderDeadline: (d) => 'Prosimy o płatność do ' + d + ' (7 dni). Voucher wystawimy i wyślemy e-mailem zaraz po zaksięgowaniu płatności.',
    orderAfter: 'Gdy tylko płatność zostanie zaksięgowana (zwykle w ciągu kilku minut), wyślemy Ci e-mailem potwierdzenie z dokumentem — a w przypadku vouchera podarunkowego także sam voucher. Fakturę zaliczkową znajdziesz w załączniku.',
    changeDeadline: (t) => 'Dopłatę prosimy uregulować do ' + t + ' (w ciągu 60 minut). Jeśli płatność do tego czasu nie wpłynie, zmiana nie zostanie wprowadzona, a rezerwacja pozostanie bez zmian.',
    changeNote: 'Zmianę wprowadzimy, gdy tylko płatność zostanie zaksięgowana — do tego czasu rezerwacja pozostaje bez zmian.',
    changeAfter: 'Po zaksięgowaniu płatności potwierdzimy zmianę e-mailem wraz z potwierdzeniem płatności i zaktualizowaną umową. Gdyby zmiana w międzyczasie nie była już możliwa (na przykład termin zajęła inna rezerwacja), zwrócimy dopłatę, a rezerwacja pozostanie bez zmian.',
    spdOrder: 'zamowienie',
  },
  uk: {
    orderSubject: (n) => 'Платіжні дані до замовлення ' + n + ' — QR / банківський переказ',
    orderIntro: (b) => ' за замовлення ' + b + '. Сплати суму банківським переказом або відсканувавши QR-код у банківському застосунку.',
    orderDeadline: (d) => 'Будь ласка, здійсни платіж до ' + d + ' (7 днів). Ваучер ми оформимо й надішлемо електронною поштою одразу після надходження платежу.',
    orderAfter: 'Щойно платіж надійде (зазвичай за кілька хвилин), ми надішлемо тобі електронною поштою підтвердження з документом — а якщо це подарунковий ваучер, то й сам ваучер. Авансовий рахунок додано у вкладенні.',
    changeDeadline: (t) => 'Будь ласка, сплати доплату до ' + t + ' (протягом 60 хвилин). Якщо до того часу платіж не надійде, зміну не буде внесено, а бронювання залишиться без змін.',
    changeNote: 'Зміну ми внесемо, щойно надійде платіж, — до того часу бронювання залишається без змін.',
    changeAfter: 'Після надходження платежу ми підтвердимо зміну електронною поштою разом із квитанцією про оплату та оновленим договором. Якщо зміну тим часом уже не можна буде внести (наприклад, дати зайняло інше бронювання), ми повернемо доплату, а бронювання залишиться без змін.',
    spdOrder: 'zamovlennia',
  },
}

const LOCALE: Record<QrLang, string> = { cs: 'cs-CZ', en: 'en-GB', de: 'de-DE', es: 'es-ES', fr: 'fr-FR', nl: 'nl-NL', pl: 'pl-PL', uk: 'uk-UA' }

/** Konec lhůty v pražském čase a zvyklostech jazyka: „14:35“ (doplatek) / „8. 12. 2026“ (objednávka). */
export function deadlineLabel(lang: QrLang, iso: string, kind: 'time' | 'date'): string {
  const d = new Date(iso)
  if (!Number.isFinite(d.getTime())) return ''
  const opts: Intl.DateTimeFormatOptions = kind === 'time'
    ? { timeZone: 'Europe/Prague', hour: '2-digit', minute: '2-digit', hour12: false }
    : { timeZone: 'Europe/Prague', day: 'numeric', month: 'numeric', year: 'numeric' }
  try { return new Intl.DateTimeFormat(LOCALE[lang], opts).format(d) } catch { return d.toISOString().slice(0, kind === 'time' ? 16 : 10) }
}
