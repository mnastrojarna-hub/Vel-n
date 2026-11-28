// ===== qr-payment/gear-texts.ts =====
// Výpůjčka JEN výbavy placená QR / převodem (booking_kind = 'gear'): e-mail mluví o „výpůjčce výbavy“,
// ne o „rezervaci motorky“. Šablona `booking_qr_payment_gear` (SQL 20261130e; Velín → E-mailové šablony,
// send-email ji přeloží) — když chybí nebo je vypnutá, odejde běžná `booking_qr_payment` jako dosud.
// Tady: předmět a texty ZÁLOŽNÍHO mailu (raw_html) v 8 jazycích; čeština vyká, ostatní tykají.
// Použije se jen u gear rezervace a jen s nasazeným SQL 20261130c (qr-payment to pozná podle expires_at
// v odpovědi set_booking_qr_payment) — bez něj se nic nemění.
import { QR_TEXTS, invoiceSuffix, type QrLang } from './texts.ts'
import { QR_FALLBACK } from './fallback-texts.ts'
import { fmtAmount, row } from './fallback-html.ts'

export const GEAR_QR_TEMPLATE = 'booking_qr_payment_gear'

export const GEAR_QR: Record<QrLang, { subject: (bn: string) => string; intro: (bnHtml: string) => string; deadline: string; after: string }> = {
  cs: {
    subject: (bn) => 'Platební údaje k výpůjčce výbavy #' + bn + ' — QR / bankovní převod',
    intro: (b) => ' za objednávku výpůjčky výbavy ' + b + '. Uhraďte prosím částku bankovním převodem nebo naskenováním QR kódu v mobilní bankovní aplikaci.',
    deadline: '⏱ Platbu prosím proveďte do 4 hodin. Pokud se do té doby nepřipíše, výpůjčka se automaticky zruší a výbava se uvolní.',
    after: 'Po připsání platby vám výpůjčku potvrdíme e-mailem (obvykle do několika minut). Zálohovou fakturu najdete v příloze.',
  },
  en: {
    subject: (bn) => 'Payment details for gear rental #' + bn + ' — QR / bank transfer',
    intro: (b) => ' for your gear rental order ' + b + '. Please pay the amount by bank transfer or by scanning the QR code in your mobile banking app.',
    deadline: '⏱ Please make the payment within 4 hours. If it has not arrived by then, the rental will be cancelled automatically and the gear released.',
    after: 'Once the payment arrives, we will confirm your rental by e-mail (usually within a few minutes). The advance invoice is attached.',
  },
  de: {
    subject: (bn) => 'Zahlungsdaten zur Ausrüstungsmiete #' + bn + ' — QR / Banküberweisung',
    intro: (b) => ' für deine Ausrüstungsmiete ' + b + '. Bitte zahle den Betrag per Banküberweisung oder scanne den QR-Code in deiner Banking-App.',
    deadline: '⏱ Bitte zahle innerhalb von 4 Stunden. Ist die Zahlung bis dahin nicht eingegangen, wird die Miete automatisch storniert und die Ausrüstung wieder freigegeben.',
    after: 'Sobald die Zahlung eingegangen ist, bestätigen wir dir die Miete per E-Mail (meist innerhalb weniger Minuten). Die Vorschussrechnung findest du im Anhang.',
  },
  es: {
    subject: (bn) => 'Datos de pago del alquiler de equipamiento #' + bn + ' — QR / transferencia bancaria',
    intro: (b) => ' por tu alquiler de equipamiento ' + b + '. Paga el importe por transferencia bancaria o escaneando el código QR en la app de tu banco.',
    deadline: '⏱ Realiza el pago en un plazo de 4 horas. Si para entonces no ha llegado, el alquiler se cancelará automáticamente y el equipamiento quedará libre.',
    after: 'Cuando recibamos el pago, te confirmaremos el alquiler por correo electrónico (normalmente en unos minutos). La factura de anticipo va adjunta.',
  },
  fr: {
    subject: (bn) => 'Coordonnées de paiement de la location d’équipement #' + bn + ' — QR / virement bancaire',
    intro: (b) => ' pour ta location d’équipement ' + b + '. Merci de régler le montant par virement bancaire ou en scannant le code QR dans ton application bancaire.',
    deadline: '⏱ Merci d’effectuer le paiement dans les 4 heures. S’il n’est pas arrivé d’ici là, la location sera annulée automatiquement et l’équipement libéré.',
    after: 'Dès réception du paiement, nous te confirmerons la location par e-mail (généralement en quelques minutes). La facture d’acompte est en pièce jointe.',
  },
  nl: {
    subject: (bn) => 'Betaalgegevens voor huur van uitrusting #' + bn + ' — QR / bankoverschrijving',
    intro: (b) => ' voor je huur van uitrusting ' + b + '. Betaal het bedrag per bankoverschrijving of scan de QR-code in je bankapp.',
    deadline: '⏱ Betaal binnen 4 uur. Is de betaling dan nog niet binnen, dan wordt de huur automatisch geannuleerd en komt de uitrusting weer vrij.',
    after: 'Zodra de betaling binnen is, bevestigen we de huur per e-mail (meestal binnen een paar minuten). De voorschotfactuur vind je in de bijlage.',
  },
  pl: {
    subject: (bn) => 'Dane do płatności za wypożyczenie odzieży #' + bn + ' — QR / przelew bankowy',
    intro: (b) => ' za zamówienie wypożyczenia odzieży ' + b + '. Zapłać kwotę przelewem bankowym lub skanując kod QR w aplikacji bankowej.',
    deadline: '⏱ Prosimy o płatność w ciągu 4 godzin. Jeśli do tego czasu nie wpłynie, wypożyczenie zostanie automatycznie anulowane, a odzież zwolniona.',
    after: 'Po zaksięgowaniu płatności potwierdzimy wypożyczenie e-mailem (zwykle w ciągu kilku minut). Fakturę zaliczkową znajdziesz w załączniku.',
  },
  uk: {
    subject: (bn) => 'Платіжні дані до оренди спорядження #' + bn + ' — QR / банківський переказ',
    intro: (b) => ' за замовлення оренди спорядження ' + b + '. Сплати суму банківським переказом або відсканувавши QR-код у банківському застосунку.',
    deadline: '⏱ Будь ласка, здійсни платіж протягом 4 годин. Якщо до того часу він не надійде, оренду буде автоматично скасовано, а спорядження звільнено.',
    after: 'Після надходження платежу ми підтвердимо оренду електронною поштою (зазвичай за кілька хвилин). Авансовий рахунок додано у вкладенні.',
  },
}

/** Záložní HTML mailu pro výpůjčku výbavy — stejný vzhled jako customerEmailHtml (fallback-html.ts). */
export function gearEmailHtml(p: { custName: string; amount: number; account: string; iban: string; bank: string; vs: string; qrUrl: string;
  bookingNumber: string; invoiceNumber: string | null }, lang: QrLang = 'cs'): string {
  const f = QR_FALLBACK[lang], g = GEAR_QR[lang]
  return `
  <h2 style="margin:0 0 6px;font-size:20px;color:#0f1a14">${f.title}</h2>
  <p style="margin:0 0 16px;color:#374151;font-size:14px">${QR_TEXTS[lang].thanks(p.custName)}${g.intro(`<strong>#${p.bookingNumber}</strong>`)}</p>
  <div style="text-align:center;margin:0 0 16px"><img src="${p.qrUrl}" alt="${f.qrAlt}" style="width:240px;height:240px;border:1px solid #e5e7eb;border-radius:12px"></div>
  <table style="width:100%;border-collapse:collapse;margin:0 0 14px">
    ${row(f.amount, fmtAmount(p.amount) + ' Kč', true)}
    ${row(f.account, p.account)}
    ${row('IBAN', p.iban.replace(/(.{4})/g, '$1 ').trim())}
    ${row(f.bank, p.bank)}
    ${row(f.vs, p.vs)}
  </table>
  <p style="margin:0 0 10px;padding:12px 14px;background:#fef2f2;border-radius:10px;color:#b91c1c;font-weight:700;font-size:14px">${g.deadline}</p>
  <p style="margin:0;color:#374151;font-size:13px">${g.after}${invoiceSuffix(lang, p.invoiceNumber)}</p>
  `
}
