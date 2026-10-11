// qr-payment — texty ZÁLOŽNÍHO mailu (raw_html, když šablona booking_qr_payment[_surcharge]
// chybí / je vypnutá / send-email selže) v 8 jazycích. Čeština 1:1 s původním kódem.
// Cizí jazyky tykají (du/tu/tú/je/ty/ти) jako ostatní nové zákaznické texty.

import type { QrLang } from './texts.ts'

export interface QrFallbackTexts {
  title: string
  surchargeTitle: string
  /** pokračování za thanks(jméno): „ za rezervaci <strong>#X</strong>. Uhraďte…“ */
  intro: (bnHtml: string) => string
  /** pokračování za surchargeLead(jméno): „ <strong>#X</strong> se váže doplatek. Uhraďte ho…“ */
  surchargeIntro: (bnHtml: string) => string
  qrAlt: string
  amount: string; account: string; bank: string; vs: string
  deadline: string
  after: string
  card: string
  surchargeAfter: string
}

export const QR_FALLBACK: Record<QrLang, QrFallbackTexts> = {
  cs: {
    title: 'Platební údaje — QR / bankovní převod',
    surchargeTitle: 'Doplatek za úpravu rezervace — QR / bankovní převod',
    intro: (b) => ' za rezervaci ' + b + '. Uhraďte prosím částku bankovním převodem nebo naskenováním QR kódu v mobilní bankovní aplikaci.',
    surchargeIntro: (b) => ' ' + b + ' se váže doplatek. Uhraďte ho prosím bankovním převodem nebo naskenováním QR kódu v mobilní bankovní aplikaci.',
    qrAlt: 'QR Platba',
    amount: 'Částka', account: 'Číslo účtu', bank: 'Banka', vs: 'Variabilní symbol',
    deadline: '⏱ Platbu prosím proveďte do 4 hodin. Pokud se do té doby nepřipíše, rezervace se automaticky zruší a termín se uvolní.',
    after: 'Po připsání platby vám rezervaci potvrdíme a pošleme potvrzení s přístupovými údaji. Zálohovou fakturu najdete v příloze.',
    card: 'Platíte-li raději kartou (okamžité potvrzení), můžete rezervaci dokončit online platbou v rezervačním formuláři.',
    surchargeAfter: 'Po připsání platby vám úpravu rezervace potvrdíme e-mailem spolu s dokladem o platbě a aktualizovanou smlouvou.',
  },
  en: {
    title: 'Payment details — QR / bank transfer',
    surchargeTitle: 'Additional payment for your booking change — QR / bank transfer',
    intro: (b) => ' for your booking ' + b + '. Please pay the amount by bank transfer or by scanning the QR code in your mobile banking app.',
    surchargeIntro: (b) => ' ' + b + ' comes with an additional payment. Please pay it by bank transfer or by scanning the QR code in your mobile banking app.',
    qrAlt: 'QR payment',
    amount: 'Amount', account: 'Account number', bank: 'Bank', vs: 'Variable symbol',
    deadline: '⏱ Please make the payment within 4 hours. If it has not arrived by then, the booking will be cancelled automatically and the dates released.',
    after: 'Once the payment arrives, we will confirm your booking and send you a confirmation with the access details. The advance invoice is attached.',
    card: 'If you prefer to pay by card (instant confirmation), you can complete the booking with an online payment in the booking form.',
    surchargeAfter: 'Once the payment arrives, we will confirm the booking change by e-mail together with the payment receipt and the updated contract.',
  },
  de: {
    title: 'Zahlungsdaten — QR / Banküberweisung',
    surchargeTitle: 'Nachzahlung für die Reservierungsänderung — QR / Banküberweisung',
    intro: (b) => ' für deine Reservierung ' + b + '. Bitte überweise den Betrag per Banküberweisung oder scanne den QR-Code in deiner Banking-App.',
    surchargeIntro: (b) => ' ' + b + ' ist eine Nachzahlung verbunden. Bitte überweise sie per Banküberweisung oder scanne den QR-Code in deiner Banking-App.',
    qrAlt: 'QR-Zahlung',
    amount: 'Betrag', account: 'Kontonummer', bank: 'Bank', vs: 'Variabler Symbol',
    deadline: '⏱ Bitte zahle innerhalb von 4 Stunden. Ist die Zahlung bis dahin nicht eingegangen, wird die Reservierung automatisch storniert und der Termin wieder freigegeben.',
    after: 'Sobald die Zahlung eingegangen ist, bestätigen wir deine Reservierung und schicken dir die Bestätigung mit den Zugangsdaten. Die Vorschussrechnung findest du im Anhang.',
    card: 'Wenn du lieber mit Karte zahlst (sofortige Bestätigung), kannst du die Reservierung mit einer Online-Zahlung im Reservierungsformular abschließen.',
    surchargeAfter: 'Sobald die Zahlung eingegangen ist, bestätigen wir dir die Änderung per E-Mail zusammen mit dem Zahlungsbeleg und dem aktualisierten Vertrag.',
  },
  es: {
    title: 'Datos de pago — QR / transferencia bancaria',
    surchargeTitle: 'Pago adicional por la modificación de la reserva — QR / transferencia bancaria',
    intro: (b) => ' por tu reserva ' + b + '. Paga el importe por transferencia bancaria o escaneando el código QR en la app de tu banco.',
    surchargeIntro: (b) => ' ' + b + ' conlleva un pago adicional. Págalo por transferencia bancaria o escaneando el código QR en la app de tu banco.',
    qrAlt: 'Pago QR',
    amount: 'Importe', account: 'Número de cuenta', bank: 'Banco', vs: 'Símbolo variable',
    deadline: '⏱ Realiza el pago en un plazo de 4 horas. Si para entonces no se ha recibido, la reserva se cancelará automáticamente y las fechas quedarán libres.',
    after: 'Cuando recibamos el pago, confirmaremos tu reserva y te enviaremos la confirmación con los datos de acceso. Encontrarás la factura de anticipo en el adjunto.',
    card: 'Si prefieres pagar con tarjeta (confirmación inmediata), puedes completar la reserva con un pago online en el formulario de reserva.',
    surchargeAfter: 'Cuando recibamos el pago, te confirmaremos la modificación por e-mail junto con el justificante de pago y el contrato actualizado.',
  },
  fr: {
    title: 'Coordonnées de paiement — QR / virement bancaire',
    surchargeTitle: 'Supplément pour la modification de la réservation — QR / virement bancaire',
    intro: (b) => ' pour ta réservation ' + b + '. Règle le montant par virement bancaire ou en scannant le code QR dans ton application bancaire.',
    surchargeIntro: (b) => ' ' + b + ' entraîne un supplément. Règle-le par virement bancaire ou en scannant le code QR dans ton application bancaire.',
    qrAlt: 'Paiement QR',
    amount: 'Montant', account: 'Numéro de compte', bank: 'Banque', vs: 'Symbole variable',
    deadline: '⏱ Effectue le paiement dans les 4 heures. S’il n’est pas crédité d’ici là, la réservation sera annulée automatiquement et les dates seront libérées.',
    after: 'Dès réception du paiement, nous confirmerons ta réservation et t’enverrons la confirmation avec les informations d’accès. La facture d’acompte est en pièce jointe.',
    card: 'Si tu préfères payer par carte (confirmation immédiate), tu peux finaliser la réservation par un paiement en ligne dans le formulaire de réservation.',
    surchargeAfter: 'Dès réception du paiement, nous te confirmerons la modification par e-mail avec le justificatif de paiement et le contrat mis à jour.',
  },
  nl: {
    title: 'Betaalgegevens — QR / bankoverschrijving',
    surchargeTitle: 'Bijbetaling voor de wijziging van de reservering — QR / bankoverschrijving',
    intro: (b) => ' voor je reservering ' + b + '. Maak het bedrag over per bankoverschrijving of scan de QR-code in je bankapp.',
    surchargeIntro: (b) => ' ' + b + ' is een bijbetaling verbonden. Maak die over per bankoverschrijving of scan de QR-code in je bankapp.',
    qrAlt: 'QR-betaling',
    amount: 'Bedrag', account: 'Rekeningnummer', bank: 'Bank', vs: 'Variabel symbool',
    deadline: '⏱ Betaal binnen 4 uur. Is de betaling dan nog niet binnen, dan wordt de reservering automatisch geannuleerd en komt de periode weer vrij.',
    after: 'Zodra de betaling binnen is, bevestigen we je reservering en sturen we je de bevestiging met de toegangsgegevens. De voorschotfactuur vind je in de bijlage.',
    card: 'Betaal je liever met een kaart (directe bevestiging), dan kun je de reservering afronden met een online betaling in het reserveringsformulier.',
    surchargeAfter: 'Zodra de betaling binnen is, bevestigen we de wijziging per e-mail, samen met het betalingsbewijs en het bijgewerkte contract.',
  },
  pl: {
    title: 'Dane do płatności — QR / przelew bankowy',
    surchargeTitle: 'Dopłata za zmianę rezerwacji — QR / przelew bankowy',
    intro: (b) => ' za rezerwację ' + b + '. Opłać kwotę przelewem bankowym lub zeskanuj kod QR w aplikacji swojego banku.',
    surchargeIntro: (b) => ' ' + b + ' wiąże się dopłata. Opłać ją przelewem bankowym lub zeskanuj kod QR w aplikacji swojego banku.',
    qrAlt: 'Płatność QR',
    amount: 'Kwota', account: 'Numer konta', bank: 'Bank', vs: 'Symbol zmienny',
    deadline: '⏱ Dokonaj płatności w ciągu 4 godzin. Jeśli do tego czasu nie wpłynie, rezerwacja zostanie automatycznie anulowana, a termin zwolniony.',
    after: 'Po zaksięgowaniu płatności potwierdzimy rezerwację i wyślemy potwierdzenie z danymi dostępowymi. Fakturę zaliczkową znajdziesz w załączniku.',
    card: 'Jeśli wolisz zapłacić kartą (natychmiastowe potwierdzenie), możesz dokończyć rezerwację płatnością online w formularzu rezerwacji.',
    surchargeAfter: 'Po zaksięgowaniu płatności potwierdzimy zmianę rezerwacji e-mailem wraz z potwierdzeniem płatności i zaktualizowaną umową.',
  },
  uk: {
    title: 'Платіжні дані — QR / банківський переказ',
    surchargeTitle: 'Доплата за зміну бронювання — QR / банківський переказ',
    intro: (b) => ' за бронювання ' + b + '. Сплати суму банківським переказом або відскануй QR-код у мобільному банківському застосунку.',
    surchargeIntro: (b) => ' ' + b + ' повʼязана доплата. Сплати її банківським переказом або відскануй QR-код у мобільному банківському застосунку.',
    qrAlt: 'QR-платіж',
    amount: 'Сума', account: 'Номер рахунку', bank: 'Банк', vs: 'Варіабельний символ',
    deadline: '⏱ Здійсни оплату протягом 4 годин. Якщо до того часу кошти не надійдуть, бронювання автоматично скасується, а дати звільняться.',
    after: 'Після надходження оплати ми підтвердимо бронювання й надішлемо підтвердження з даними доступу. Рахунок на передоплату знайдеш у вкладенні.',
    card: 'Якщо зручніше оплатити карткою (миттєве підтвердження), заверши бронювання онлайн-оплатою у формі бронювання.',
    surchargeAfter: 'Після надходження оплати ми підтвердимо зміну бронювання електронною поштою разом із підтвердженням оплати та оновленим договором.',
  },
}
