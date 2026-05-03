// =============================================================================
// i18n modul pro customer comms emaily (send-booking-email, send-cancellation-email, ...)
// =============================================================================
// Pokrývá 7 jazyků: cs, en, de, nl, es, fr, pl
//
// Použití:
//   import { renderEmail, type Lang } from '../_shared/i18n.ts'
//   const { subject, body } = renderEmail('booking_reserved', 'en', vars)
//
// Detekce jazyka v edge fn:
//   - payload.language (přímo poslán)
//   - NEBO RPC detect_customer_language(user_id, booking_id, order_id) → 'cs' default
//
// Velin admin kopie do info@motogo24.cz se vždy renderuje s 'cs' (Etapa 5.2c).
//
// DB override:
//   email_templates.subject_translations + body_translations (jsonb {"en": "..."})
//   pokud existuje pro daný (slug, lang), použije se DB, jinak hardcoded fallback níže.
// =============================================================================

export type Lang = 'cs' | 'en' | 'de' | 'nl' | 'es' | 'fr' | 'pl'
export const SUPPORTED_LANGS: Lang[] = ['cs', 'en', 'de', 'nl', 'es', 'fr', 'pl']
export const DEFAULT_LANG: Lang = 'cs'

export function normalizeLang(lang: string | null | undefined): Lang {
  if (!lang) return DEFAULT_LANG
  const l = lang.toLowerCase().trim().slice(0, 2)
  return (SUPPORTED_LANGS as string[]).includes(l) ? (l as Lang) : DEFAULT_LANG
}

// Vars: substituce v subject + body, formát {{key}}
export type Vars = Record<string, string>

export function substitute(template: string, vars: Vars): string {
  if (!template) return ''
  let out = template
  for (const [k, v] of Object.entries(vars)) {
    out = out.replaceAll(`{{${k}}}`, v ?? '')
  }
  return out.replace(/\{\{[^}]+\}\}/g, '')
}

// =============================================================================
// SHARED HTML SNIPPETS (per-language) — používané ve více šablonách
// =============================================================================

// "Tým MotoGo24" / "MOTO GO 24 Team" / atd. — signature
const SIGN: Record<Lang, string> = {
  cs: 'Tým MotoGo24',
  en: 'MOTO GO 24 Team',
  de: 'Ihr MOTO GO 24 Team',
  nl: 'MOTO GO 24 Team',
  es: 'Equipo MOTO GO 24',
  fr: 'Équipe MOTO GO 24',
  pl: 'Zespół MOTO GO 24',
}
const HELLO: Record<Lang, string> = {
  cs: 'Dobrý den,',
  en: 'Hello,',
  de: 'Guten Tag,',
  nl: 'Goedendag,',
  es: 'Hola,',
  fr: 'Bonjour,',
  pl: 'Dzień dobry,',
}

// =============================================================================
// PER-TEMPLATE PER-LANG SUBJECTS
// =============================================================================

type SubjectFn = (v: Vars) => string

const SUBJECTS: Record<string, Record<Lang, SubjectFn>> = {
  booking_reserved: {
    cs: v => `Vaše rezervace č. ${v.booking_number} motocyklu u MotoGo24 je potvrzena`,
    en: v => `Your motorcycle booking #${v.booking_number} at MOTO GO 24 is confirmed`,
    de: v => `Ihre Motorradbuchung Nr. ${v.booking_number} bei MOTO GO 24 ist bestätigt`,
    nl: v => `Je motorboeking nr. ${v.booking_number} bij MOTO GO 24 is bevestigd`,
    es: v => `Tu reserva de moto nº ${v.booking_number} en MOTO GO 24 está confirmada`,
    fr: v => `Votre réservation moto n° ${v.booking_number} chez MOTO GO 24 est confirmée`,
    pl: v => `Twoja rezerwacja motocykla nr ${v.booking_number} w MOTO GO 24 została potwierdzona`,
  },
  booking_completed: {
    cs: () => 'Děkujeme za využití služeb MotoGo24',
    en: () => 'Thank you for choosing MOTO GO 24',
    de: () => 'Vielen Dank, dass Sie MOTO GO 24 gewählt haben',
    nl: () => 'Bedankt voor je keuze voor MOTO GO 24',
    es: () => 'Gracias por elegir MOTO GO 24',
    fr: () => 'Merci d\'avoir choisi MOTO GO 24',
    pl: () => 'Dziękujemy za wybór MOTO GO 24',
  },
  booking_modified: {
    cs: v => {
      const pd = Number((v.price_difference || '0').toString().replace(/\s/g, '').replace(',', '.')) || 0
      if (pd > 0) return `Úprava rezervace č. ${v.booking_number} — doplatek ${v.price_difference} Kč — MOTO GO 24`
      if (pd < 0) return `Úprava rezervace č. ${v.booking_number} — vrácení platby — MOTO GO 24`
      return `Změna rezervace č. ${v.booking_number} — MOTO GO 24`
    },
    en: v => {
      const pd = Number((v.price_difference || '0').toString().replace(/\s/g, '').replace(',', '.')) || 0
      if (pd > 0) return `Booking #${v.booking_number} updated — additional payment ${v.price_difference} CZK — MOTO GO 24`
      if (pd < 0) return `Booking #${v.booking_number} updated — refund issued — MOTO GO 24`
      return `Booking #${v.booking_number} changed — MOTO GO 24`
    },
    de: v => {
      const pd = Number((v.price_difference || '0').toString().replace(/\s/g, '').replace(',', '.')) || 0
      if (pd > 0) return `Buchung Nr. ${v.booking_number} geändert — Nachzahlung ${v.price_difference} CZK — MOTO GO 24`
      if (pd < 0) return `Buchung Nr. ${v.booking_number} geändert — Rückerstattung — MOTO GO 24`
      return `Buchung Nr. ${v.booking_number} aktualisiert — MOTO GO 24`
    },
    nl: v => {
      const pd = Number((v.price_difference || '0').toString().replace(/\s/g, '').replace(',', '.')) || 0
      if (pd > 0) return `Boeking nr. ${v.booking_number} aangepast — bijbetaling ${v.price_difference} CZK — MOTO GO 24`
      if (pd < 0) return `Boeking nr. ${v.booking_number} aangepast — terugbetaling — MOTO GO 24`
      return `Boeking nr. ${v.booking_number} gewijzigd — MOTO GO 24`
    },
    es: v => {
      const pd = Number((v.price_difference || '0').toString().replace(/\s/g, '').replace(',', '.')) || 0
      if (pd > 0) return `Reserva nº ${v.booking_number} modificada — pago adicional ${v.price_difference} CZK — MOTO GO 24`
      if (pd < 0) return `Reserva nº ${v.booking_number} modificada — reembolso emitido — MOTO GO 24`
      return `Reserva nº ${v.booking_number} cambiada — MOTO GO 24`
    },
    fr: v => {
      const pd = Number((v.price_difference || '0').toString().replace(/\s/g, '').replace(',', '.')) || 0
      if (pd > 0) return `Réservation n° ${v.booking_number} modifiée — supplément ${v.price_difference} CZK — MOTO GO 24`
      if (pd < 0) return `Réservation n° ${v.booking_number} modifiée — remboursement émis — MOTO GO 24`
      return `Réservation n° ${v.booking_number} modifiée — MOTO GO 24`
    },
    pl: v => {
      const pd = Number((v.price_difference || '0').toString().replace(/\s/g, '').replace(',', '.')) || 0
      if (pd > 0) return `Rezerwacja nr ${v.booking_number} zmieniona — dopłata ${v.price_difference} CZK — MOTO GO 24`
      if (pd < 0) return `Rezerwacja nr ${v.booking_number} zmieniona — zwrot — MOTO GO 24`
      return `Rezerwacja nr ${v.booking_number} zmieniona — MOTO GO 24`
    },
  },
  booking_cancelled: {
    cs: v => `Vaše rezervace č. ${v.booking_number} motocyklu u MotoGo24 byla úspěšně stornována`,
    en: v => `Your motorcycle booking #${v.booking_number} at MOTO GO 24 has been cancelled`,
    de: v => `Ihre Motorradbuchung Nr. ${v.booking_number} bei MOTO GO 24 wurde storniert`,
    nl: v => `Je motorboeking nr. ${v.booking_number} bij MOTO GO 24 is geannuleerd`,
    es: v => `Tu reserva de moto nº ${v.booking_number} en MOTO GO 24 ha sido cancelada`,
    fr: v => `Votre réservation moto n° ${v.booking_number} chez MOTO GO 24 a été annulée`,
    pl: v => `Twoja rezerwacja motocykla nr ${v.booking_number} w MOTO GO 24 została anulowana`,
  },
  booking_abandoned: {
    cs: v => `Dokončete svou rezervaci č. ${v.booking_number} motocyklu u MotoGo24`,
    en: v => `Finish your motorcycle booking #${v.booking_number} at MOTO GO 24`,
    de: v => `Schließen Sie Ihre Motorradbuchung Nr. ${v.booking_number} bei MOTO GO 24 ab`,
    nl: v => `Maak je motorboeking nr. ${v.booking_number} bij MOTO GO 24 af`,
    es: v => `Finaliza tu reserva de moto nº ${v.booking_number} en MOTO GO 24`,
    fr: v => `Finalisez votre réservation moto n° ${v.booking_number} chez MOTO GO 24`,
    pl: v => `Dokończ swoją rezerwację motocykla nr ${v.booking_number} w MOTO GO 24`,
  },
  booking_abandoned_full: {
    cs: v => `Dokončete rezervaci č. ${v.booking_number} — chybí platba a doklady`,
    en: v => `Finish booking #${v.booking_number} — payment & documents pending`,
    de: v => `Buchung Nr. ${v.booking_number} abschließen — Zahlung & Dokumente fehlen`,
    nl: v => `Boeking nr. ${v.booking_number} afmaken — betaling & documenten ontbreken`,
    es: v => `Finaliza la reserva nº ${v.booking_number} — falta pago y documentos`,
    fr: v => `Terminez la réservation n° ${v.booking_number} — paiement et documents manquants`,
    pl: v => `Dokończ rezerwację nr ${v.booking_number} — brak płatności i dokumentów`,
  },
  booking_missing_docs: {
    cs: v => `Nahrajte doklady k rezervaci č. ${v.booking_number} — MotoGo24`,
    en: v => `Upload documents for booking #${v.booking_number} — MOTO GO 24`,
    de: v => `Dokumente zur Buchung Nr. ${v.booking_number} hochladen — MOTO GO 24`,
    nl: v => `Upload documenten voor boeking nr. ${v.booking_number} — MOTO GO 24`,
    es: v => `Sube los documentos para la reserva nº ${v.booking_number} — MOTO GO 24`,
    fr: v => `Téléchargez vos documents pour la réservation n° ${v.booking_number} — MOTO GO 24`,
    pl: v => `Prześlij dokumenty do rezerwacji nr ${v.booking_number} — MOTO GO 24`,
  },
  voucher_purchased: {
    cs: () => 'Váš dárkový poukaz od MotoGo24',
    en: () => 'Your gift voucher from MOTO GO 24',
    de: () => 'Ihr Geschenkgutschein von MOTO GO 24',
    nl: () => 'Je cadeaubon van MOTO GO 24',
    es: () => 'Tu cheque regalo de MOTO GO 24',
    fr: () => 'Votre bon cadeau MOTO GO 24',
    pl: () => 'Twój voucher prezentowy od MOTO GO 24',
  },
  sos_incident: {
    cs: () => 'SOS — MotoGo24 je na cestě',
    en: () => 'SOS — MOTO GO 24 is on the way',
    de: () => 'SOS — MOTO GO 24 ist unterwegs',
    nl: () => 'SOS — MOTO GO 24 is onderweg',
    es: () => 'SOS — MOTO GO 24 está en camino',
    fr: () => 'SOS — MOTO GO 24 arrive',
    pl: () => 'SOS — MOTO GO 24 już jedzie',
  },
  door_codes: {
    cs: v => `Přístupové kódy k pobočce — rezervace č. ${v.booking_number}`,
    en: v => `Branch access codes — booking #${v.booking_number}`,
    de: v => `Filial-Zugangscodes — Buchung Nr. ${v.booking_number}`,
    nl: v => `Toegangscodes filiaal — boeking nr. ${v.booking_number}`,
    es: v => `Códigos de acceso de sucursal — reserva nº ${v.booking_number}`,
    fr: v => `Codes d'accès succursale — réservation n° ${v.booking_number}`,
    pl: v => `Kody dostępu do oddziału — rezerwacja nr ${v.booking_number}`,
  },
  shop_order_confirmed: {
    cs: v => `Objednávka č. ${v.order_number} přijata — MOTO GO 24`,
    en: v => `Order #${v.order_number} received — MOTO GO 24`,
    de: v => `Bestellung Nr. ${v.order_number} eingegangen — MOTO GO 24`,
    nl: v => `Bestelling nr. ${v.order_number} ontvangen — MOTO GO 24`,
    es: v => `Pedido nº ${v.order_number} recibido — MOTO GO 24`,
    fr: v => `Commande n° ${v.order_number} reçue — MOTO GO 24`,
    pl: v => `Zamówienie nr ${v.order_number} przyjęte — MOTO GO 24`,
  },
  shop_order_shipped: {
    cs: v => `Objednávka č. ${v.order_number} odeslána — MOTO GO 24`,
    en: v => `Order #${v.order_number} shipped — MOTO GO 24`,
    de: v => `Bestellung Nr. ${v.order_number} versandt — MOTO GO 24`,
    nl: v => `Bestelling nr. ${v.order_number} verzonden — MOTO GO 24`,
    es: v => `Pedido nº ${v.order_number} enviado — MOTO GO 24`,
    fr: v => `Commande n° ${v.order_number} expédiée — MOTO GO 24`,
    pl: v => `Zamówienie nr ${v.order_number} wysłane — MOTO GO 24`,
  },
}

// =============================================================================
// PER-TEMPLATE PER-LANG BODY HTML
// =============================================================================
// Helpery pro tabulku diff v booking_modified (per-jazyk popisky sloupců)

const DIFF_LABELS: Record<Lang, { uda: string; old: string; new: string; moto: string; from: string; to: string; pickup: string; ret: string; total: string }> = {
  cs: { uda: 'Údaj',     old: 'Původní',   new: 'Nové',     moto: 'Motorka',     from: 'Začátek',  to: 'Konec',  pickup: 'Místo převzetí', ret: 'Místo vrácení',   total: 'Celková cena' },
  en: { uda: 'Field',    old: 'Original',  new: 'New',      moto: 'Motorcycle',  from: 'Start',    to: 'End',    pickup: 'Pickup',         ret: 'Return',           total: 'Total price'  },
  de: { uda: 'Feld',     old: 'Original',  new: 'Neu',      moto: 'Motorrad',    from: 'Beginn',   to: 'Ende',   pickup: 'Abholort',       ret: 'Rückgabeort',      total: 'Gesamtpreis'  },
  nl: { uda: 'Veld',     old: 'Origineel', new: 'Nieuw',    moto: 'Motorfiets',  from: 'Begin',    to: 'Einde',  pickup: 'Ophaalpunt',     ret: 'Retourpunt',       total: 'Totaalprijs'  },
  es: { uda: 'Campo',    old: 'Original',  new: 'Nuevo',    moto: 'Motocicleta', from: 'Inicio',   to: 'Fin',    pickup: 'Recogida',       ret: 'Devolución',       total: 'Precio total' },
  fr: { uda: 'Champ',    old: 'Original',  new: 'Nouveau',  moto: 'Moto',        from: 'Début',    to: 'Fin',    pickup: 'Retrait',        ret: 'Retour',           total: 'Prix total'   },
  pl: { uda: 'Pole',     old: 'Pierwotne', new: 'Nowe',     moto: 'Motocykl',    from: 'Początek', to: 'Koniec', pickup: 'Odbiór',         ret: 'Zwrot',            total: 'Cena całkowita' },
}

function renderDiffRow(label: string, oldVal: string, newVal: string): string {
  if (!oldVal && !newVal) return ''
  const changed = !!oldVal && !!newVal && oldVal !== newVal
  return `<tr>
    <td style="padding:8px 12px;border-bottom:1px solid #e5e7eb;color:#6b7280;font-size:12px">${label}</td>
    <td style="padding:8px 12px;border-bottom:1px solid #e5e7eb;color:${changed ? '#9ca3af' : '#0f1a14'};${changed ? 'text-decoration:line-through' : ''};font-size:13px">${oldVal || '—'}</td>
    <td style="padding:8px 12px;border-bottom:1px solid #e5e7eb;color:${changed ? '#16a34a' : '#0f1a14'};font-weight:${changed ? '700' : '400'};font-size:13px">${newVal || '—'}</td>
  </tr>`
}

const BODIES: Record<string, Record<Lang, (v: Vars) => string>> = {
  // -------- booking_reserved --------
  booking_reserved: {
    cs: v => `<p>${HELLO.cs}</p>
<p>děkujeme za vaši důvěru a za rezervaci č. <strong>${v.booking_number}</strong> motocyklu u MotoGo24.</p>
<p>Vaše rezervace byla úspěšně přijata a uhrazena.</p>
<p>Kompletní přehled rezervovaných služeb a výbavy naleznete v přiložené Nájemní smlouvě a zálohové faktuře.</p>
${v.door_codes_block || ''}
<h3 style="color:#1a2e22;font-size:15px;margin-top:24px">Informace k převzetí motocyklu</h3>
<p>Prosíme, pro bezproblémové převzetí si připravte:</p>
<ul><li>platný doklad totožnosti (který jste uvedli v rezervačním formuláři),</li><li>platný řidičský průkaz.</li></ul>
<p>Na místě společně provedeme kontrolu dokladů, předání motocyklu i případné zapůjčené výbavy a podepíšeme Předávací protokol.</p>
<p>${SIGN.cs}</p>`,
    en: v => `<p>${HELLO.en}</p>
<p>thank you for your trust and your booking <strong>#${v.booking_number}</strong> at MOTO GO 24.</p>
<p>Your booking has been successfully received and paid.</p>
<p>You'll find the full overview of booked services and gear in the attached Rental Agreement and Proforma Invoice.</p>
${v.door_codes_block || ''}
<h3 style="color:#1a2e22;font-size:15px;margin-top:24px">Pickup information</h3>
<p>For a smooth pickup, please bring:</p>
<ul><li>a valid ID document (the one you provided in the booking form),</li><li>a valid driver's license.</li></ul>
<p>On site we'll verify the documents, hand over the motorcycle and any rented gear, and sign the Handover Protocol.</p>
<p>${SIGN.en}</p>`,
    de: v => `<p>${HELLO.de}</p>
<p>vielen Dank für Ihr Vertrauen und Ihre Buchung Nr. <strong>${v.booking_number}</strong> bei MOTO GO 24.</p>
<p>Ihre Buchung wurde erfolgreich angenommen und bezahlt.</p>
<p>Eine vollständige Übersicht der gebuchten Leistungen und Ausrüstung finden Sie im beigefügten Mietvertrag und in der Vorausrechnung.</p>
${v.door_codes_block || ''}
<h3 style="color:#1a2e22;font-size:15px;margin-top:24px">Informationen zur Abholung</h3>
<p>Bitte bringen Sie für eine reibungslose Übergabe mit:</p>
<ul><li>einen gültigen Personalausweis (den Sie im Buchungsformular angegeben haben),</li><li>einen gültigen Führerschein.</li></ul>
<p>Vor Ort prüfen wir die Dokumente, übergeben das Motorrad und die ggf. gemietete Ausrüstung und unterschreiben das Übergabeprotokoll.</p>
<p>${SIGN.de}</p>`,
    nl: v => `<p>${HELLO.nl}</p>
<p>bedankt voor je vertrouwen en je boeking nr. <strong>${v.booking_number}</strong> bij MOTO GO 24.</p>
<p>Je boeking is succesvol ontvangen en betaald.</p>
<p>Een volledig overzicht van geboekte diensten en uitrusting vind je in de bijgevoegde Huurovereenkomst en proforma factuur.</p>
${v.door_codes_block || ''}
<h3 style="color:#1a2e22;font-size:15px;margin-top:24px">Ophalen — informatie</h3>
<p>Voor een soepele overdracht graag meenemen:</p>
<ul><li>een geldig identiteitsbewijs (dat je in het boekingsformulier hebt opgegeven),</li><li>een geldig rijbewijs.</li></ul>
<p>Ter plaatse controleren we de documenten, geven we de motor en eventueel gehuurde uitrusting over en tekenen we het Overdrachtsprotocol.</p>
<p>${SIGN.nl}</p>`,
    es: v => `<p>${HELLO.es}</p>
<p>gracias por tu confianza y por tu reserva nº <strong>${v.booking_number}</strong> en MOTO GO 24.</p>
<p>Tu reserva ha sido recibida y pagada con éxito.</p>
<p>Encontrarás el resumen completo de los servicios y el equipo reservados en el Contrato de Alquiler y la factura proforma adjuntos.</p>
${v.door_codes_block || ''}
<h3 style="color:#1a2e22;font-size:15px;margin-top:24px">Información de recogida</h3>
<p>Para una recogida sin problemas, trae por favor:</p>
<ul><li>un documento de identidad válido (el que indicaste en el formulario),</li><li>un permiso de conducir válido.</li></ul>
<p>En el lugar verificaremos los documentos, te entregaremos la moto y el equipo alquilado, y firmaremos el Acta de Entrega.</p>
<p>${SIGN.es}</p>`,
    fr: v => `<p>${HELLO.fr}</p>
<p>merci de votre confiance et de votre réservation n° <strong>${v.booking_number}</strong> chez MOTO GO 24.</p>
<p>Votre réservation a bien été reçue et payée.</p>
<p>Vous trouverez l'aperçu complet des services et de l'équipement réservés dans le Contrat de location et la facture proforma joints.</p>
${v.door_codes_block || ''}
<h3 style="color:#1a2e22;font-size:15px;margin-top:24px">Informations de retrait</h3>
<p>Pour un retrait sans souci, veuillez apporter :</p>
<ul><li>une pièce d'identité valide (celle indiquée dans le formulaire),</li><li>un permis de conduire valide.</li></ul>
<p>Sur place, nous vérifierons les documents, vous remettrons la moto et l'équipement loué, et signerons le procès-verbal de remise.</p>
<p>${SIGN.fr}</p>`,
    pl: v => `<p>${HELLO.pl}</p>
<p>dziękujemy za zaufanie i rezerwację nr <strong>${v.booking_number}</strong> w MOTO GO 24.</p>
<p>Twoja rezerwacja została pomyślnie przyjęta i opłacona.</p>
<p>Pełny wykaz zarezerwowanych usług i wyposażenia znajdziesz w załączonej Umowie najmu oraz fakturze proforma.</p>
${v.door_codes_block || ''}
<h3 style="color:#1a2e22;font-size:15px;margin-top:24px">Informacje dotyczące odbioru</h3>
<p>Aby odbiór przebiegł sprawnie, prosimy o:</p>
<ul><li>ważny dokument tożsamości (wskazany w formularzu rezerwacji),</li><li>ważne prawo jazdy.</li></ul>
<p>Na miejscu sprawdzimy dokumenty, przekażemy motocykl i wynajęte wyposażenie oraz podpiszemy protokół zdawczo-odbiorczy.</p>
<p>${SIGN.pl}</p>`,
  },

  // -------- booking_completed (poděkování + slevový kód) --------
  booking_completed: {
    cs: v => `<p>${HELLO.cs}</p>
<p>děkujeme, že jste využili služeb MotoGo24.</p>
<p>Protože je pro nás zpětná vazba velmi důležitá, budeme rádi, pokud nám zanecháte recenzi na <a href="${v.google_review_url || '#'}" style="color:#2563eb">Googlu</a> nebo na <a href="${v.facebook_review_url || '#'}" style="color:#2563eb">Facebooku</a>.</p>
${v.discount_code ? `<div style="background:#dcfce7;border-radius:12px;padding:16px;margin:20px 0;border:1px solid #86efac"><p style="margin:0;font-size:14px;color:#166534">Jako malé poděkování za poskytnutou důvěru přikládáme slevový kód <strong>200 Kč</strong> na vaši příští rezervaci: <strong style="font-family:monospace;font-size:16px;letter-spacing:2px">${v.discount_code}</strong></p></div>` : ''}
<p>V příloze naleznete konečnou fakturu za vaši rezervaci.</p>
<p>Těšíme se na vás při dalším dobrodružství!</p>
<p>S pozdravem,<br>${SIGN.cs}</p>`,
    en: v => `<p>${HELLO.en}</p>
<p>thank you for choosing MOTO GO 24.</p>
<p>Your feedback matters a lot to us — please leave a review on <a href="${v.google_review_url || '#'}" style="color:#2563eb">Google</a> or <a href="${v.facebook_review_url || '#'}" style="color:#2563eb">Facebook</a>.</p>
${v.discount_code ? `<div style="background:#dcfce7;border-radius:12px;padding:16px;margin:20px 0;border:1px solid #86efac"><p style="margin:0;font-size:14px;color:#166534">As a thank-you, we're including a <strong>200 CZK discount code</strong> for your next booking: <strong style="font-family:monospace;font-size:16px;letter-spacing:2px">${v.discount_code}</strong></p></div>` : ''}
<p>You'll find the final invoice for your booking attached.</p>
<p>We look forward to your next adventure with us!</p>
<p>Best regards,<br>${SIGN.en}</p>`,
    de: v => `<p>${HELLO.de}</p>
<p>vielen Dank, dass Sie MOTO GO 24 gewählt haben.</p>
<p>Ihr Feedback ist uns sehr wichtig — bitte hinterlassen Sie eine Bewertung auf <a href="${v.google_review_url || '#'}" style="color:#2563eb">Google</a> oder <a href="${v.facebook_review_url || '#'}" style="color:#2563eb">Facebook</a>.</p>
${v.discount_code ? `<div style="background:#dcfce7;border-radius:12px;padding:16px;margin:20px 0;border:1px solid #86efac"><p style="margin:0;font-size:14px;color:#166534">Als Dankeschön legen wir Ihnen einen <strong>Rabattcode von 200 CZK</strong> für Ihre nächste Buchung bei: <strong style="font-family:monospace;font-size:16px;letter-spacing:2px">${v.discount_code}</strong></p></div>` : ''}
<p>Im Anhang finden Sie die Endrechnung zu Ihrer Buchung.</p>
<p>Wir freuen uns auf Ihr nächstes Abenteuer mit uns!</p>
<p>Mit freundlichen Grüßen,<br>${SIGN.de}</p>`,
    nl: v => `<p>${HELLO.nl}</p>
<p>bedankt dat je voor MOTO GO 24 hebt gekozen.</p>
<p>Jouw feedback is belangrijk — laat een review achter op <a href="${v.google_review_url || '#'}" style="color:#2563eb">Google</a> of <a href="${v.facebook_review_url || '#'}" style="color:#2563eb">Facebook</a>.</p>
${v.discount_code ? `<div style="background:#dcfce7;border-radius:12px;padding:16px;margin:20px 0;border:1px solid #86efac"><p style="margin:0;font-size:14px;color:#166534">Als bedankje sluiten we een <strong>kortingscode van 200 CZK</strong> bij voor je volgende boeking: <strong style="font-family:monospace;font-size:16px;letter-spacing:2px">${v.discount_code}</strong></p></div>` : ''}
<p>De eindfactuur voor je boeking vind je in de bijlage.</p>
<p>Tot je volgende avontuur met ons!</p>
<p>Met vriendelijke groet,<br>${SIGN.nl}</p>`,
    es: v => `<p>${HELLO.es}</p>
<p>gracias por elegir MOTO GO 24.</p>
<p>Tu opinión es muy importante para nosotros — por favor déjanos una reseña en <a href="${v.google_review_url || '#'}" style="color:#2563eb">Google</a> o <a href="${v.facebook_review_url || '#'}" style="color:#2563eb">Facebook</a>.</p>
${v.discount_code ? `<div style="background:#dcfce7;border-radius:12px;padding:16px;margin:20px 0;border:1px solid #86efac"><p style="margin:0;font-size:14px;color:#166534">Como agradecimiento, te regalamos un <strong>código de descuento de 200 CZK</strong> para tu próxima reserva: <strong style="font-family:monospace;font-size:16px;letter-spacing:2px">${v.discount_code}</strong></p></div>` : ''}
<p>Adjuntamos la factura final de tu reserva.</p>
<p>¡Esperamos tu próxima aventura con nosotros!</p>
<p>Saludos cordiales,<br>${SIGN.es}</p>`,
    fr: v => `<p>${HELLO.fr}</p>
<p>merci d'avoir choisi MOTO GO 24.</p>
<p>Votre avis compte beaucoup — laissez-nous un avis sur <a href="${v.google_review_url || '#'}" style="color:#2563eb">Google</a> ou <a href="${v.facebook_review_url || '#'}" style="color:#2563eb">Facebook</a>.</p>
${v.discount_code ? `<div style="background:#dcfce7;border-radius:12px;padding:16px;margin:20px 0;border:1px solid #86efac"><p style="margin:0;font-size:14px;color:#166534">En remerciement, nous joignons un <strong>code de réduction de 200 CZK</strong> pour votre prochaine réservation : <strong style="font-family:monospace;font-size:16px;letter-spacing:2px">${v.discount_code}</strong></p></div>` : ''}
<p>Vous trouverez la facture finale de votre réservation en pièce jointe.</p>
<p>Nous nous réjouissons de votre prochaine aventure avec nous !</p>
<p>Cordialement,<br>${SIGN.fr}</p>`,
    pl: v => `<p>${HELLO.pl}</p>
<p>dziękujemy za wybór MOTO GO 24.</p>
<p>Twoja opinia jest dla nas bardzo ważna — zostaw recenzję na <a href="${v.google_review_url || '#'}" style="color:#2563eb">Google</a> lub <a href="${v.facebook_review_url || '#'}" style="color:#2563eb">Facebooku</a>.</p>
${v.discount_code ? `<div style="background:#dcfce7;border-radius:12px;padding:16px;margin:20px 0;border:1px solid #86efac"><p style="margin:0;font-size:14px;color:#166534">W ramach podziękowania dołączamy <strong>kod rabatowy 200 CZK</strong> na Twoją kolejną rezerwację: <strong style="font-family:monospace;font-size:16px;letter-spacing:2px">${v.discount_code}</strong></p></div>` : ''}
<p>W załączeniu znajdziesz fakturę końcową za Twoją rezerwację.</p>
<p>Czekamy na kolejną przygodę razem!</p>
<p>Pozdrawiamy,<br>${SIGN.pl}</p>`,
  },

  // -------- booking_modified (s diff tabulkou per-jazyk) --------
  booking_modified: {
    cs: v => renderModifiedBody('cs', v),
    en: v => renderModifiedBody('en', v),
    de: v => renderModifiedBody('de', v),
    nl: v => renderModifiedBody('nl', v),
    es: v => renderModifiedBody('es', v),
    fr: v => renderModifiedBody('fr', v),
    pl: v => renderModifiedBody('pl', v),
  },

  // -------- booking_abandoned (web nedokončená rezervace, jen platba chybí) --------
  booking_abandoned: {
    cs: v => `<p>${HELLO.cs}</p>
<p>velice vám děkujeme za váš zájem o naši motopůjčovnu.</p>
<p>Vypadá to, že jste nedokončili svou rezervaci č. <strong>${v.booking_number}</strong> motocyklu.</p>
<p>Pro snadné dokončení rezervace stačí kliknout na následující odkaz:</p>
${v.resume_link ? `<div style="text-align:center;margin:24px 0"><a href="${v.resume_link}" style="background:#74FB71;color:#1a2e22;padding:14px 28px;border-radius:25px;text-decoration:none;font-weight:800;font-size:15px;display:inline-block">Dokončit rezervaci</a></div>` : ''}
<p style="color:#dc2626;font-weight:700;font-style:italic">Pozor: odkaz je platný pouze 4 hodiny. Po uplynutí této doby se motocykl uvolní pro další zákazníky.</p>
<p>Děkujeme a těšíme se na vás.</p>
<p>${SIGN.cs}</p>`,
    en: v => `<p>${HELLO.en}</p>
<p>thank you for your interest in our motorcycle rental.</p>
<p>It looks like you didn't complete your booking <strong>#${v.booking_number}</strong>.</p>
<p>To finish, just click the link below:</p>
${v.resume_link ? `<div style="text-align:center;margin:24px 0"><a href="${v.resume_link}" style="background:#74FB71;color:#1a2e22;padding:14px 28px;border-radius:25px;text-decoration:none;font-weight:800;font-size:15px;display:inline-block">Finish booking</a></div>` : ''}
<p style="color:#dc2626;font-weight:700;font-style:italic">Heads up: the link is valid for 4 hours. After that, the motorcycle is released to other customers.</p>
<p>We look forward to seeing you.</p>
<p>${SIGN.en}</p>`,
    de: v => `<p>${HELLO.de}</p>
<p>vielen Dank für Ihr Interesse an unserer Motorradvermietung.</p>
<p>Es sieht aus, als hätten Sie Ihre Buchung Nr. <strong>${v.booking_number}</strong> nicht abgeschlossen.</p>
<p>Klicken Sie einfach auf den folgenden Link, um sie abzuschließen:</p>
${v.resume_link ? `<div style="text-align:center;margin:24px 0"><a href="${v.resume_link}" style="background:#74FB71;color:#1a2e22;padding:14px 28px;border-radius:25px;text-decoration:none;font-weight:800;font-size:15px;display:inline-block">Buchung abschließen</a></div>` : ''}
<p style="color:#dc2626;font-weight:700;font-style:italic">Achtung: Der Link ist nur 4 Stunden gültig. Danach wird das Motorrad für andere Kunden freigegeben.</p>
<p>Wir freuen uns auf Sie.</p>
<p>${SIGN.de}</p>`,
    nl: v => `<p>${HELLO.nl}</p>
<p>bedankt voor je interesse in onze motorverhuur.</p>
<p>Het lijkt erop dat je je boeking nr. <strong>${v.booking_number}</strong> niet hebt afgerond.</p>
<p>Klik op de link hieronder om af te ronden:</p>
${v.resume_link ? `<div style="text-align:center;margin:24px 0"><a href="${v.resume_link}" style="background:#74FB71;color:#1a2e22;padding:14px 28px;border-radius:25px;text-decoration:none;font-weight:800;font-size:15px;display:inline-block">Boeking afronden</a></div>` : ''}
<p style="color:#dc2626;font-weight:700;font-style:italic">Let op: de link is 4 uur geldig. Daarna wordt de motor vrijgegeven voor andere klanten.</p>
<p>Tot ziens.</p>
<p>${SIGN.nl}</p>`,
    es: v => `<p>${HELLO.es}</p>
<p>gracias por tu interés en nuestro alquiler de motos.</p>
<p>Parece que no completaste tu reserva nº <strong>${v.booking_number}</strong>.</p>
<p>Para terminarla basta con hacer clic en el siguiente enlace:</p>
${v.resume_link ? `<div style="text-align:center;margin:24px 0"><a href="${v.resume_link}" style="background:#74FB71;color:#1a2e22;padding:14px 28px;border-radius:25px;text-decoration:none;font-weight:800;font-size:15px;display:inline-block">Finalizar reserva</a></div>` : ''}
<p style="color:#dc2626;font-weight:700;font-style:italic">Atención: el enlace es válido durante 4 horas. Después la moto se libera para otros clientes.</p>
<p>¡Te esperamos!</p>
<p>${SIGN.es}</p>`,
    fr: v => `<p>${HELLO.fr}</p>
<p>merci pour votre intérêt pour notre location de motos.</p>
<p>Il semble que vous n'ayez pas finalisé votre réservation n° <strong>${v.booking_number}</strong>.</p>
<p>Pour la finaliser, cliquez simplement sur le lien ci-dessous :</p>
${v.resume_link ? `<div style="text-align:center;margin:24px 0"><a href="${v.resume_link}" style="background:#74FB71;color:#1a2e22;padding:14px 28px;border-radius:25px;text-decoration:none;font-weight:800;font-size:15px;display:inline-block">Finaliser la réservation</a></div>` : ''}
<p style="color:#dc2626;font-weight:700;font-style:italic">Attention : le lien est valable 4 heures. Passé ce délai, la moto est libérée pour d'autres clients.</p>
<p>À très bientôt.</p>
<p>${SIGN.fr}</p>`,
    pl: v => `<p>${HELLO.pl}</p>
<p>dziękujemy za zainteresowanie naszą wypożyczalnią motocykli.</p>
<p>Wygląda na to, że nie dokończyłeś rezerwacji nr <strong>${v.booking_number}</strong>.</p>
<p>Aby ją sfinalizować, kliknij w poniższy link:</p>
${v.resume_link ? `<div style="text-align:center;margin:24px 0"><a href="${v.resume_link}" style="background:#74FB71;color:#1a2e22;padding:14px 28px;border-radius:25px;text-decoration:none;font-weight:800;font-size:15px;display:inline-block">Dokończ rezerwację</a></div>` : ''}
<p style="color:#dc2626;font-weight:700;font-style:italic">Uwaga: link jest ważny 4 godziny. Po tym czasie motocykl wraca do dostępnej puli.</p>
<p>Czekamy na Ciebie.</p>
<p>${SIGN.pl}</p>`,
  },

  // -------- booking_abandoned_full (chybí platba i doklady) --------
  booking_abandoned_full: {
    cs: v => renderAbandonedFullBody('cs', v),
    en: v => renderAbandonedFullBody('en', v),
    de: v => renderAbandonedFullBody('de', v),
    nl: v => renderAbandonedFullBody('nl', v),
    es: v => renderAbandonedFullBody('es', v),
    fr: v => renderAbandonedFullBody('fr', v),
    pl: v => renderAbandonedFullBody('pl', v),
  },

  // -------- booking_missing_docs (paid, chybí doklady) --------
  booking_missing_docs: {
    cs: v => renderMissingDocsBody('cs', v),
    en: v => renderMissingDocsBody('en', v),
    de: v => renderMissingDocsBody('de', v),
    nl: v => renderMissingDocsBody('nl', v),
    es: v => renderMissingDocsBody('es', v),
    fr: v => renderMissingDocsBody('fr', v),
    pl: v => renderMissingDocsBody('pl', v),
  },

  // -------- voucher_purchased (dárkový poukaz) --------
  voucher_purchased: {
    cs: v => renderVoucherBody('cs', v),
    en: v => renderVoucherBody('en', v),
    de: v => renderVoucherBody('de', v),
    nl: v => renderVoucherBody('nl', v),
    es: v => renderVoucherBody('es', v),
    fr: v => renderVoucherBody('fr', v),
    pl: v => renderVoucherBody('pl', v),
  },

  // -------- sos_incident (SOS hlášení) --------
  sos_incident: {
    cs: v => `<p>${HELLO.cs}</p>
<p>přijali jsme vaše SOS hlášení k rezervaci č. <strong>${v.booking_number}</strong>.</p>
<p><strong>Omlouváme se za nepříjemnosti a jsme na cestě.</strong></p>
<p>Náš tým se vám ozve v nejbližších minutách. Pokud potřebujete okamžitou pomoc, volejte na <a href="tel:+420774256271" style="color:#2563eb;font-weight:700">+420 774 256 271</a>.</p>
<p>${SIGN.cs}</p>`,
    en: v => `<p>${HELLO.en}</p>
<p>we have received your SOS report for booking <strong>#${v.booking_number}</strong>.</p>
<p><strong>We're sorry for the trouble and we're on our way.</strong></p>
<p>Our team will contact you within minutes. If you need immediate help, call <a href="tel:+420774256271" style="color:#2563eb;font-weight:700">+420 774 256 271</a>.</p>
<p>${SIGN.en}</p>`,
    de: v => `<p>${HELLO.de}</p>
<p>wir haben Ihre SOS-Meldung zur Buchung Nr. <strong>${v.booking_number}</strong> erhalten.</p>
<p><strong>Wir entschuldigen uns für die Unannehmlichkeiten und sind unterwegs.</strong></p>
<p>Unser Team meldet sich in Kürze. Brauchen Sie sofortige Hilfe, rufen Sie <a href="tel:+420774256271" style="color:#2563eb;font-weight:700">+420 774 256 271</a> an.</p>
<p>${SIGN.de}</p>`,
    nl: v => `<p>${HELLO.nl}</p>
<p>we hebben je SOS-melding voor boeking nr. <strong>${v.booking_number}</strong> ontvangen.</p>
<p><strong>Onze excuses voor het ongemak — we zijn onderweg.</strong></p>
<p>Ons team neemt binnen enkele minuten contact op. Onmiddellijke hulp nodig? Bel <a href="tel:+420774256271" style="color:#2563eb;font-weight:700">+420 774 256 271</a>.</p>
<p>${SIGN.nl}</p>`,
    es: v => `<p>${HELLO.es}</p>
<p>hemos recibido tu aviso SOS para la reserva nº <strong>${v.booking_number}</strong>.</p>
<p><strong>Lamentamos las molestias y vamos en camino.</strong></p>
<p>Nuestro equipo te contactará en breve. Si necesitas ayuda inmediata, llama al <a href="tel:+420774256271" style="color:#2563eb;font-weight:700">+420 774 256 271</a>.</p>
<p>${SIGN.es}</p>`,
    fr: v => `<p>${HELLO.fr}</p>
<p>nous avons reçu votre signalement SOS pour la réservation n° <strong>${v.booking_number}</strong>.</p>
<p><strong>Nous nous excusons pour la gêne et arrivons.</strong></p>
<p>Notre équipe vous contactera sous peu. Si vous avez besoin d'aide immédiate, appelez le <a href="tel:+420774256271" style="color:#2563eb;font-weight:700">+420 774 256 271</a>.</p>
<p>${SIGN.fr}</p>`,
    pl: v => `<p>${HELLO.pl}</p>
<p>odebraliśmy Twoje zgłoszenie SOS do rezerwacji nr <strong>${v.booking_number}</strong>.</p>
<p><strong>Przepraszamy za niedogodności — już jedziemy.</strong></p>
<p>Nasz zespół skontaktuje się w ciągu kilku minut. Jeśli potrzebujesz natychmiastowej pomocy, zadzwoń pod <a href="tel:+420774256271" style="color:#2563eb;font-weight:700">+420 774 256 271</a>.</p>
<p>${SIGN.pl}</p>`,
  },

  // -------- door_codes (přístupové kódy) --------
  door_codes: {
    cs: v => `<p>${HELLO.cs}</p>
<p>k vaší rezervaci č. <strong>${v.booking_number}</strong> jsou nyní k dispozici přístupové kódy k pobočce.</p>
${v.door_codes_block || `<p style="color:#dc2626">Kódy se zobrazí po ověření dokladů.</p>`}
<p>Kódy najdete také v appce MotoGo24 v detailu rezervace a v sekci Zprávy.</p>
<p>Těšíme se na vás.</p>
<p>${SIGN.cs}</p>`,
    en: v => `<p>${HELLO.en}</p>
<p>access codes for booking <strong>#${v.booking_number}</strong> are now available.</p>
${v.door_codes_block || `<p style="color:#dc2626">Codes will be released after document verification.</p>`}
<p>You'll also find them in the MOTO GO 24 app under booking details and in Messages.</p>
<p>See you soon.</p>
<p>${SIGN.en}</p>`,
    de: v => `<p>${HELLO.de}</p>
<p>für Ihre Buchung Nr. <strong>${v.booking_number}</strong> sind nun die Zugangscodes zur Filiale verfügbar.</p>
${v.door_codes_block || `<p style="color:#dc2626">Die Codes werden nach Dokumentenprüfung freigegeben.</p>`}
<p>Sie finden sie auch in der MOTO GO 24 App in den Buchungsdetails und in Nachrichten.</p>
<p>Wir freuen uns auf Sie.</p>
<p>${SIGN.de}</p>`,
    nl: v => `<p>${HELLO.nl}</p>
<p>de toegangscodes voor boeking nr. <strong>${v.booking_number}</strong> zijn nu beschikbaar.</p>
${v.door_codes_block || `<p style="color:#dc2626">Codes worden vrijgegeven na controle van de documenten.</p>`}
<p>Je vindt ze ook in de MOTO GO 24 app onder boekingsdetails en in Berichten.</p>
<p>Tot snel.</p>
<p>${SIGN.nl}</p>`,
    es: v => `<p>${HELLO.es}</p>
<p>los códigos de acceso para la reserva nº <strong>${v.booking_number}</strong> ya están disponibles.</p>
${v.door_codes_block || `<p style="color:#dc2626">Los códigos se emitirán tras verificar los documentos.</p>`}
<p>También los encontrarás en la app MOTO GO 24 en el detalle de la reserva y en Mensajes.</p>
<p>¡Hasta pronto!</p>
<p>${SIGN.es}</p>`,
    fr: v => `<p>${HELLO.fr}</p>
<p>les codes d'accès pour la réservation n° <strong>${v.booking_number}</strong> sont désormais disponibles.</p>
${v.door_codes_block || `<p style="color:#dc2626">Les codes seront diffusés après vérification des documents.</p>`}
<p>Vous les retrouvez aussi dans l'app MOTO GO 24, dans les détails de la réservation et dans Messages.</p>
<p>À bientôt.</p>
<p>${SIGN.fr}</p>`,
    pl: v => `<p>${HELLO.pl}</p>
<p>kody dostępu do rezerwacji nr <strong>${v.booking_number}</strong> są już gotowe.</p>
${v.door_codes_block || `<p style="color:#dc2626">Kody zostaną udostępnione po weryfikacji dokumentów.</p>`}
<p>Znajdziesz je też w aplikacji MOTO GO 24 w szczegółach rezerwacji i w Wiadomościach.</p>
<p>Do zobaczenia.</p>
<p>${SIGN.pl}</p>`,
  },

  // -------- shop_order_confirmed (e-shop platba přijata) --------
  shop_order_confirmed: {
    cs: v => renderShopConfirmedBody('cs', v),
    en: v => renderShopConfirmedBody('en', v),
    de: v => renderShopConfirmedBody('de', v),
    nl: v => renderShopConfirmedBody('nl', v),
    es: v => renderShopConfirmedBody('es', v),
    fr: v => renderShopConfirmedBody('fr', v),
    pl: v => renderShopConfirmedBody('pl', v),
  },

  // -------- shop_order_shipped (e-shop odesláno + KF) --------
  shop_order_shipped: {
    cs: v => renderShopShippedBody('cs', v),
    en: v => renderShopShippedBody('en', v),
    de: v => renderShopShippedBody('de', v),
    nl: v => renderShopShippedBody('nl', v),
    es: v => renderShopShippedBody('es', v),
    fr: v => renderShopShippedBody('fr', v),
    pl: v => renderShopShippedBody('pl', v),
  },

  // -------- booking_cancelled (storno) --------
  booking_cancelled: {
    cs: v => `<p>${HELLO.cs}</p>
<p>vaše rezervace č. <strong>${v.booking_number}</strong> motocyklu byla úspěšně stornována.</p>
${v.refund_amount && Number(v.refund_amount) > 0 ? `<p>Refund <strong>${v.refund_amount} Kč</strong> (${v.refund_percent || 0} %) byl zpracován a vrácen na původní platební kartu — peníze obvykle dorazí do 5–7 pracovních dnů. V příloze najdete dobropis.</p>` : '<p>Dle storno podmínek nárok na vrácení částky bohužel nevzniká.</p>'}
<p>${v.cancellation_reason ? `<strong>Důvod:</strong> ${v.cancellation_reason}</p><p>` : ''}Pokud je to omyl nebo si rezervaci chcete obnovit, kontaktujte nás na <a href="mailto:info@motogo24.cz" style="color:#2563eb">info@motogo24.cz</a>.</p>
<p>Děkujeme za pochopení.</p>
<p>${SIGN.cs}</p>`,
    en: v => `<p>${HELLO.en}</p>
<p>your booking <strong>#${v.booking_number}</strong> has been cancelled.</p>
${v.refund_amount && Number(v.refund_amount) > 0 ? `<p>A refund of <strong>${v.refund_amount} CZK</strong> (${v.refund_percent || 0} %) has been processed back to your original payment card — funds typically arrive within 5–7 business days. The credit note is attached.</p>` : '<p>According to our cancellation policy, no refund is due.</p>'}
<p>${v.cancellation_reason ? `<strong>Reason:</strong> ${v.cancellation_reason}</p><p>` : ''}If this was a mistake or you wish to restore your booking, contact us at <a href="mailto:info@motogo24.cz" style="color:#2563eb">info@motogo24.cz</a>.</p>
<p>Thank you for understanding.</p>
<p>${SIGN.en}</p>`,
    de: v => `<p>${HELLO.de}</p>
<p>Ihre Buchung Nr. <strong>${v.booking_number}</strong> wurde storniert.</p>
${v.refund_amount && Number(v.refund_amount) > 0 ? `<p>Eine Rückerstattung von <strong>${v.refund_amount} CZK</strong> (${v.refund_percent || 0} %) wurde auf Ihre ursprüngliche Zahlungskarte veranlasst — der Betrag erscheint in der Regel innerhalb von 5–7 Werktagen. Die Gutschrift finden Sie im Anhang.</p>` : '<p>Gemäß unseren Stornobedingungen besteht kein Anspruch auf Rückerstattung.</p>'}
<p>${v.cancellation_reason ? `<strong>Grund:</strong> ${v.cancellation_reason}</p><p>` : ''}War das ein Versehen oder möchten Sie die Buchung wiederherstellen, kontaktieren Sie uns unter <a href="mailto:info@motogo24.cz" style="color:#2563eb">info@motogo24.cz</a>.</p>
<p>Danke für Ihr Verständnis.</p>
<p>${SIGN.de}</p>`,
    nl: v => `<p>${HELLO.nl}</p>
<p>je boeking nr. <strong>${v.booking_number}</strong> is geannuleerd.</p>
${v.refund_amount && Number(v.refund_amount) > 0 ? `<p>Een terugbetaling van <strong>${v.refund_amount} CZK</strong> (${v.refund_percent || 0} %) is teruggeboekt op je oorspronkelijke betaalkaart — het bedrag verschijnt doorgaans binnen 5–7 werkdagen. De creditnota vind je in de bijlage.</p>` : '<p>Volgens ons annuleringsbeleid is geen terugbetaling van toepassing.</p>'}
<p>${v.cancellation_reason ? `<strong>Reden:</strong> ${v.cancellation_reason}</p><p>` : ''}Was dit een vergissing of wil je je boeking herstellen, neem contact op via <a href="mailto:info@motogo24.cz" style="color:#2563eb">info@motogo24.cz</a>.</p>
<p>Bedankt voor je begrip.</p>
<p>${SIGN.nl}</p>`,
    es: v => `<p>${HELLO.es}</p>
<p>tu reserva nº <strong>${v.booking_number}</strong> ha sido cancelada.</p>
${v.refund_amount && Number(v.refund_amount) > 0 ? `<p>Se ha procesado un reembolso de <strong>${v.refund_amount} CZK</strong> (${v.refund_percent || 0} %) a tu tarjeta original — el importe suele llegar en 5–7 días hábiles. La nota de crédito está adjunta.</p>` : '<p>Según nuestra política de cancelación, no procede reembolso.</p>'}
<p>${v.cancellation_reason ? `<strong>Motivo:</strong> ${v.cancellation_reason}</p><p>` : ''}Si fue un error o deseas restaurar tu reserva, contáctanos en <a href="mailto:info@motogo24.cz" style="color:#2563eb">info@motogo24.cz</a>.</p>
<p>Gracias por tu comprensión.</p>
<p>${SIGN.es}</p>`,
    fr: v => `<p>${HELLO.fr}</p>
<p>votre réservation n° <strong>${v.booking_number}</strong> a été annulée.</p>
${v.refund_amount && Number(v.refund_amount) > 0 ? `<p>Un remboursement de <strong>${v.refund_amount} CZK</strong> (${v.refund_percent || 0} %) a été émis sur votre carte d'origine — la somme arrive généralement sous 5 à 7 jours ouvrés. L'avoir est joint.</p>` : '<p>Selon nos conditions d\'annulation, aucun remboursement n\'est applicable.</p>'}
<p>${v.cancellation_reason ? `<strong>Motif :</strong> ${v.cancellation_reason}</p><p>` : ''}En cas d'erreur ou si vous souhaitez rétablir la réservation, contactez-nous à <a href="mailto:info@motogo24.cz" style="color:#2563eb">info@motogo24.cz</a>.</p>
<p>Merci pour votre compréhension.</p>
<p>${SIGN.fr}</p>`,
    pl: v => `<p>${HELLO.pl}</p>
<p>Twoja rezerwacja nr <strong>${v.booking_number}</strong> została anulowana.</p>
${v.refund_amount && Number(v.refund_amount) > 0 ? `<p>Zwrot w wysokości <strong>${v.refund_amount} CZK</strong> (${v.refund_percent || 0} %) został przekazany na pierwotną kartę płatniczą — środki zwykle pojawiają się w ciągu 5–7 dni roboczych. Notę kredytową znajdziesz w załączniku.</p>` : '<p>Zgodnie z polityką anulowania nie przysługuje zwrot.</p>'}
<p>${v.cancellation_reason ? `<strong>Powód:</strong> ${v.cancellation_reason}</p><p>` : ''}Jeśli to pomyłka lub chcesz przywrócić rezerwację, napisz na <a href="mailto:info@motogo24.cz" style="color:#2563eb">info@motogo24.cz</a>.</p>
<p>Dziękujemy za zrozumienie.</p>
<p>${SIGN.pl}</p>`,
  },
}

// =============================================================================
// HELPER body renderers — víc-jazyčné šablony s složitější strukturou
// =============================================================================

function renderAbandonedFullBody(lang: Lang, v: Vars): string {
  // State A: chybí platba i doklady. Dva CTA: pay_url + docs_url.
  const T: Record<Lang, { intro: string; needs: string[]; backText: string; warn: string; payCta: string; docsCta: string }> = {
    cs: { intro: `vidíme, že jste rozjeli rezervaci č. <strong>${v.booking_number}</strong> motocyklu <strong>${v.motorcycle}</strong> na <strong>${v.start_date} – ${v.end_date}</strong>, ale ještě jste ji nedokončili. Chybí dvě věci:`,
          needs: ['<strong>Zaplatit</strong> přes zabezpečenou Stripe bránu', '<strong>Nahrát doklady</strong> (občanka/pas + řidičák) — sken přes mobil díky Mindee OCR zabere 30 vteřin'],
          backText: 'Vraťte se prosím do rezervace a obojí dořešte — všechna vyplněná data jsou uložená.',
          warn: 'Bez platby a dokladů systém přístupový kód k motorce nevydá. Termín můžeme držet jen omezenou dobu.',
          payCta: 'Pokračovat k platbě', docsCta: 'Nahrát doklady' },
    en: { intro: `we noticed you started booking <strong>#${v.booking_number}</strong> for <strong>${v.motorcycle}</strong> on <strong>${v.start_date} – ${v.end_date}</strong> but haven't finished it. Two things are missing:`,
          needs: ['<strong>Pay</strong> via secure Stripe', '<strong>Upload documents</strong> (ID + driver\'s license) — Mindee OCR scan via mobile takes 30 seconds'],
          backText: 'Please return to your booking and finish — all entered data is saved.',
          warn: 'Without payment and documents the system won\'t issue access codes. We can only hold the slot for a limited time.',
          payCta: 'Continue to payment', docsCta: 'Upload documents' },
    de: { intro: `wir sehen, dass Sie die Buchung Nr. <strong>${v.booking_number}</strong> für <strong>${v.motorcycle}</strong> vom <strong>${v.start_date} – ${v.end_date}</strong> begonnen, aber nicht abgeschlossen haben. Es fehlen zwei Dinge:`,
          needs: ['<strong>Zahlung</strong> über das sichere Stripe-Gateway', '<strong>Dokumente hochladen</strong> (Ausweis + Führerschein) — Mindee-OCR-Scan per Handy in 30 Sekunden'],
          backText: 'Bitte kehren Sie zur Buchung zurück und erledigen Sie beides — alle Daten sind gespeichert.',
          warn: 'Ohne Zahlung und Dokumente gibt das System keinen Zugangscode aus. Wir können den Termin nur begrenzt halten.',
          payCta: 'Zur Zahlung', docsCta: 'Dokumente hochladen' },
    nl: { intro: `we zien dat je boeking nr. <strong>${v.booking_number}</strong> voor <strong>${v.motorcycle}</strong> op <strong>${v.start_date} – ${v.end_date}</strong> bent begonnen maar niet hebt afgerond. Er ontbreken twee dingen:`,
          needs: ['<strong>Betalen</strong> via beveiligde Stripe', '<strong>Documenten uploaden</strong> (ID + rijbewijs) — Mindee OCR-scan via mobiel duurt 30 seconden'],
          backText: 'Ga terug naar je boeking en handel beide af — alle ingevulde gegevens zijn bewaard.',
          warn: 'Zonder betaling en documenten geeft het systeem geen toegangscode af. We kunnen het tijdslot beperkt vasthouden.',
          payCta: 'Doorgaan naar betaling', docsCta: 'Documenten uploaden' },
    es: { intro: `vemos que comenzaste la reserva nº <strong>${v.booking_number}</strong> para <strong>${v.motorcycle}</strong> del <strong>${v.start_date} al ${v.end_date}</strong>, pero aún no la has finalizado. Faltan dos cosas:`,
          needs: ['<strong>Pagar</strong> a través de la pasarela segura Stripe', '<strong>Subir documentos</strong> (DNI/pasaporte + permiso de conducir) — escaneo Mindee OCR desde el móvil en 30 segundos'],
          backText: 'Vuelve a tu reserva y resuelve ambas cosas — todos los datos están guardados.',
          warn: 'Sin pago ni documentos el sistema no emite el código de acceso. Solo podemos mantener la franja un tiempo limitado.',
          payCta: 'Continuar al pago', docsCta: 'Subir documentos' },
    fr: { intro: `nous avons vu que vous avez commencé la réservation n° <strong>${v.booking_number}</strong> pour <strong>${v.motorcycle}</strong> du <strong>${v.start_date} au ${v.end_date}</strong> sans la terminer. Il manque deux choses :`,
          needs: ['<strong>Payer</strong> via la passerelle sécurisée Stripe', '<strong>Télécharger les documents</strong> (CNI/passeport + permis) — scan Mindee OCR depuis le mobile en 30 secondes'],
          backText: 'Revenez à votre réservation et terminez les deux étapes — toutes les données sont sauvegardées.',
          warn: 'Sans paiement ni documents, le système ne délivre pas de code d\'accès. Nous ne pouvons réserver le créneau que pour un temps limité.',
          payCta: 'Continuer le paiement', docsCta: 'Télécharger les documents' },
    pl: { intro: `widzimy, że rozpocząłeś rezerwację nr <strong>${v.booking_number}</strong> motocykla <strong>${v.motorcycle}</strong> na <strong>${v.start_date} – ${v.end_date}</strong>, ale jej nie dokończyłeś. Brakuje dwóch rzeczy:`,
          needs: ['<strong>Zapłacić</strong> przez bezpieczną bramkę Stripe', '<strong>Przesłać dokumenty</strong> (dowód + prawo jazdy) — skan Mindee OCR z telefonu trwa 30 sekund'],
          backText: 'Wróć do rezerwacji i dokończ obie rzeczy — wszystkie dane są zapisane.',
          warn: 'Bez płatności i dokumentów system nie wyda kodu dostępu. Termin możemy utrzymać tylko przez ograniczony czas.',
          payCta: 'Przejdź do płatności', docsCta: 'Prześlij dokumenty' },
  }
  const t = T[lang]
  return `<p>${HELLO[lang]}</p>
<p>${t.intro}</p>
<ol>${t.needs.map(n => `<li>${n}</li>`).join('')}</ol>
<p>${t.backText}</p>
<div style="text-align:center;margin:24px 0">
  ${v.pay_url ? `<a href="${v.pay_url}" style="display:inline-block;background:#74FB71;color:#1a2e22;padding:14px 22px;border-radius:25px;text-decoration:none;font-weight:800;font-size:14px;margin:4px">${t.payCta}</a>` : ''}
  ${v.docs_url ? `<a href="${v.docs_url}" style="display:inline-block;background:#1a2e22;color:#74FB71;padding:14px 22px;border-radius:25px;text-decoration:none;font-weight:800;font-size:14px;margin:4px">${t.docsCta}</a>` : ''}
</div>
<p style="color:#dc2626;font-weight:700;font-style:italic">${t.warn}</p>
<p>${SIGN[lang]}</p>`
}

function renderMissingDocsBody(lang: Lang, v: Vars): string {
  // State C: paid + chybí doklady. Jen docs CTA.
  const T: Record<Lang, { paid: string; ask: string; cta: string; warn: string }> = {
    cs: { paid: `vaše rezervace č. <strong>${v.booking_number}</strong> motocyklu <strong>${v.motorcycle}</strong> na <strong>${v.start_date} – ${v.end_date}</strong> je zaplacená — děkujeme!`,
          ask: 'Aby vám dorazil <strong>přístupový kód k motorce</strong>, ještě potřebujeme naskenovat doklady (občanku/pas + řidičák). Sken přes mobil díky Mindee OCR zabere 30 vteřin.',
          cta: 'Nahrát doklady', warn: 'Bez nahraných dokladů systém kódy nevydá — a platit za něco, co si nemůžete vyzvednout, by byla škoda.' },
    en: { paid: `your booking <strong>#${v.booking_number}</strong> for <strong>${v.motorcycle}</strong> on <strong>${v.start_date} – ${v.end_date}</strong> is paid — thank you!`,
          ask: 'For us to release the <strong>access code</strong>, we still need a scan of your documents (ID/passport + driver\'s license). The Mindee OCR scan takes 30 seconds on mobile.',
          cta: 'Upload documents', warn: 'Without uploaded documents the system won\'t release codes — and paying for something you can\'t pick up would be a shame.' },
    de: { paid: `Ihre Buchung Nr. <strong>${v.booking_number}</strong> für <strong>${v.motorcycle}</strong> vom <strong>${v.start_date} – ${v.end_date}</strong> ist bezahlt — danke!`,
          ask: 'Damit wir den <strong>Zugangscode zum Motorrad</strong> freigeben können, benötigen wir noch einen Scan Ihrer Dokumente (Ausweis/Pass + Führerschein). Der Mindee-OCR-Scan dauert per Handy 30 Sekunden.',
          cta: 'Dokumente hochladen', warn: 'Ohne hochgeladene Dokumente gibt das System keine Codes frei — und für etwas zu zahlen, das Sie nicht abholen können, wäre schade.' },
    nl: { paid: `je boeking nr. <strong>${v.booking_number}</strong> voor <strong>${v.motorcycle}</strong> van <strong>${v.start_date} – ${v.end_date}</strong> is betaald — bedankt!`,
          ask: 'Om de <strong>toegangscode voor de motor</strong> vrij te geven hebben we nog een scan van je documenten nodig (ID/paspoort + rijbewijs). De Mindee OCR-scan duurt 30 seconden op mobiel.',
          cta: 'Documenten uploaden', warn: 'Zonder geüploade documenten geeft het systeem geen codes vrij — en betalen voor iets dat je niet kunt ophalen zou zonde zijn.' },
    es: { paid: `tu reserva nº <strong>${v.booking_number}</strong> de <strong>${v.motorcycle}</strong> del <strong>${v.start_date} al ${v.end_date}</strong> está pagada — ¡gracias!`,
          ask: 'Para liberar el <strong>código de acceso a la moto</strong> aún necesitamos un escaneo de tus documentos (DNI/pasaporte + permiso). El escaneo Mindee OCR desde el móvil tarda 30 segundos.',
          cta: 'Subir documentos', warn: 'Sin documentos subidos el sistema no libera los códigos — y pagar por algo que no puedes recoger sería una pena.' },
    fr: { paid: `votre réservation n° <strong>${v.booking_number}</strong> pour <strong>${v.motorcycle}</strong> du <strong>${v.start_date} au ${v.end_date}</strong> est payée — merci !`,
          ask: 'Pour libérer le <strong>code d\'accès à la moto</strong>, nous avons encore besoin d\'un scan de vos documents (CNI/passeport + permis). Le scan Mindee OCR depuis le mobile prend 30 secondes.',
          cta: 'Télécharger les documents', warn: 'Sans documents téléchargés, le système ne libère pas les codes — et payer pour quelque chose que vous ne pouvez pas récupérer, ce serait dommage.' },
    pl: { paid: `Twoja rezerwacja nr <strong>${v.booking_number}</strong> motocykla <strong>${v.motorcycle}</strong> na <strong>${v.start_date} – ${v.end_date}</strong> jest opłacona — dziękujemy!`,
          ask: 'Aby zwolnić <strong>kod dostępu do motocykla</strong>, potrzebujemy jeszcze skanu dokumentów (dowód/paszport + prawo jazdy). Skan Mindee OCR z telefonu zajmie 30 sekund.',
          cta: 'Prześlij dokumenty', warn: 'Bez przesłanych dokumentów system nie zwolni kodów — szkoda płacić za coś, czego nie można odebrać.' },
  }
  const t = T[lang]
  return `<p>${HELLO[lang]}</p>
<p>${t.paid}</p>
<p>${t.ask}</p>
${v.docs_url ? `<div style="text-align:center;margin:24px 0"><a href="${v.docs_url}" style="display:inline-block;background:#74FB71;color:#1a2e22;padding:14px 28px;border-radius:25px;text-decoration:none;font-weight:800;font-size:15px">${t.cta}</a></div>` : ''}
<p>${t.warn}</p>
<p>${SIGN[lang]}</p>`
}

function renderVoucherBody(lang: Lang, v: Vars): string {
  const T: Record<Lang, { intro: string; received: string; attached: string[]; printed: string; usageH: string; usage: string[]; close: string }> = {
    cs: { intro: 'děkujeme, že jste si pro svůj dárek vybrali právě MotoGo24.',
          received: `Vaši objednávku č. <strong>${v.order_number}</strong> jsme úspěšně přijali a platba byla zpracována.`,
          attached: ['dárkový poukaz,', 'doklad o přijetí platby za nákup dárkového poukazu.'],
          printed: 'Pokud jste si objednali tištěnou verzi poukazu, právě ji pro Vás připravujeme. V nejbližších dnech ji můžete očekávat ve své poštovní schránce.',
          usageH: 'Informace k uplatnění dárkového poukazu',
          usage: ['Dárkový poukaz má platnost 3 roky od data vystavení a je možné jej uplatnit na zapůjčení motocyklu dle vlastního výběru. Obdarovaný si jednoduše rezervuje termín jízdy předem podle aktuální dostupnosti motorek prostřednictvím formuláře na webových stránkách <a href="https://motogo24.cz" style="color:#2563eb">motogo24.cz</a>.',
                  'Při rezervaci zadá do kolonky Slevový kód jedinečný kód uvedený na dárkovém poukazu. Jeho hodnota se automaticky odečte z ceny zapůjčení již během rezervace. Pokud je výsledná částka vyšší než hodnota poukazu, rozdíl lze pohodlně uhradit online prostřednictvím platební brány.',
                  'Dárkové poukazy je možné kombinovat a uplatnit více kódů současně. Dárkový poukaz je nutné vyčerpat jednorázově v rámci jedné rezervace.',
                  'Doporučujeme rezervovat termín s dostatečným předstihem, zejména v hlavní sezóně.'],
          close: 'Děkujeme za důvěru a přejeme mnoho radosti z darovaného zážitku.' },
    en: { intro: 'thank you for choosing MOTO GO 24 for your gift.',
          received: `We have successfully received your order <strong>#${v.order_number}</strong> and the payment has been processed.`,
          attached: ['the gift voucher,', 'the receipt for the voucher purchase.'],
          printed: 'If you ordered a printed voucher, we\'re preparing it now. You can expect it in your mailbox within the next few days.',
          usageH: 'How to redeem the voucher',
          usage: ['The gift voucher is valid for 3 years from issue date and can be used for any motorcycle rental of your choice. The recipient simply books a date in advance based on current motorcycle availability via the form at <a href="https://motogo24.cz" style="color:#2563eb">motogo24.cz</a>.',
                  'During booking, enter the unique code from the voucher in the Discount Code field. The value is automatically deducted from the rental price during booking. If the total exceeds the voucher value, the difference can be paid online via the payment gateway.',
                  'Vouchers can be combined and multiple codes redeemed simultaneously. A voucher must be used in full within a single booking.',
                  'We recommend booking well in advance, especially during peak season.'],
          close: 'Thank you for your trust — we wish the recipient a great experience!' },
    de: { intro: 'vielen Dank, dass Sie für Ihr Geschenk MOTO GO 24 gewählt haben.',
          received: `Wir haben Ihre Bestellung Nr. <strong>${v.order_number}</strong> erhalten und die Zahlung wurde verarbeitet.`,
          attached: ['den Geschenkgutschein,', 'die Quittung für den Gutscheinkauf.'],
          printed: 'Falls Sie einen gedruckten Gutschein bestellt haben, bereiten wir ihn vor. Sie können ihn in den nächsten Tagen in Ihrem Briefkasten erwarten.',
          usageH: 'Einlösung des Gutscheins',
          usage: ['Der Geschenkgutschein ist 3 Jahre ab Ausstellungsdatum gültig und kann für eine Motorradmiete Ihrer Wahl verwendet werden. Der Beschenkte bucht einen Termin im Voraus über das Formular auf <a href="https://motogo24.cz" style="color:#2563eb">motogo24.cz</a>.',
                  'Bei der Buchung den einmaligen Code aus dem Gutschein im Feld Rabattcode eingeben. Der Wert wird automatisch vom Mietpreis abgezogen. Übersteigt der Endbetrag den Gutscheinwert, kann die Differenz online über das Zahlungsportal bezahlt werden.',
                  'Gutscheine können kombiniert und mehrere Codes gleichzeitig eingelöst werden. Ein Gutschein muss innerhalb einer Buchung vollständig aufgebraucht werden.',
                  'Wir empfehlen, den Termin rechtzeitig zu buchen, besonders in der Hochsaison.'],
          close: 'Danke für Ihr Vertrauen und viel Freude mit dem geschenkten Erlebnis.' },
    nl: { intro: 'bedankt dat je voor je cadeau MOTO GO 24 hebt gekozen.',
          received: `We hebben je bestelling nr. <strong>${v.order_number}</strong> ontvangen en de betaling is verwerkt.`,
          attached: ['de cadeaubon,', 'de kwitantie voor de aankoop.'],
          printed: 'Als je een gedrukte bon hebt besteld bereiden we hem voor. Verwacht hem binnenkort in je brievenbus.',
          usageH: 'Hoe de bon te gebruiken',
          usage: ['De cadeaubon is 3 jaar geldig vanaf uitgiftedatum en kan worden gebruikt voor elke motorhuur naar keuze. De ontvanger boekt eenvoudig een datum vooraf via het formulier op <a href="https://motogo24.cz" style="color:#2563eb">motogo24.cz</a>.',
                  'Voer bij het boeken de unieke code uit de bon in het veld Kortingscode in. De waarde wordt automatisch van de huurprijs afgetrokken. Bij een hoger totaal wordt het verschil online betaald.',
                  'Bonnen kunnen worden gecombineerd en meerdere codes tegelijk worden ingewisseld. Een bon moet binnen één boeking volledig worden besteed.',
                  'We adviseren om vroeg te boeken, vooral in het hoogseizoen.'],
          close: 'Bedankt voor je vertrouwen — veel plezier met het cadeau!' },
    es: { intro: 'gracias por elegir MOTO GO 24 para tu regalo.',
          received: `Hemos recibido tu pedido nº <strong>${v.order_number}</strong> y el pago se ha procesado.`,
          attached: ['el cheque regalo,', 'el recibo de la compra del cheque.'],
          printed: 'Si pediste el cheque impreso lo estamos preparando. Llegará a tu buzón en los próximos días.',
          usageH: 'Cómo canjear el cheque',
          usage: ['El cheque regalo es válido durante 3 años desde su emisión y puede usarse para alquilar cualquier motocicleta. El destinatario reserva una fecha por adelantado mediante el formulario en <a href="https://motogo24.cz" style="color:#2563eb">motogo24.cz</a>.',
                  'Al reservar, introduce el código único del cheque en el campo Código de descuento. El valor se descuenta automáticamente. Si el total supera el valor del cheque, la diferencia se paga online.',
                  'Los cheques se pueden combinar y canjear varios códigos a la vez. Un cheque debe utilizarse íntegramente en una única reserva.',
                  'Recomendamos reservar con antelación, sobre todo en temporada alta.'],
          close: '¡Gracias por tu confianza y mucha suerte con la experiencia regalada!' },
    fr: { intro: 'merci d\'avoir choisi MOTO GO 24 pour votre cadeau.',
          received: `Nous avons bien reçu votre commande n° <strong>${v.order_number}</strong> et le paiement est confirmé.`,
          attached: ['le bon cadeau,', 'le reçu de l\'achat.'],
          printed: 'Si vous avez commandé une version imprimée, nous la préparons. Vous la recevrez dans votre boîte aux lettres sous quelques jours.',
          usageH: 'Comment utiliser le bon',
          usage: ['Le bon cadeau est valable 3 ans à compter de la date d\'émission et peut être utilisé pour la location d\'une moto au choix. Le bénéficiaire réserve une date à l\'avance via le formulaire sur <a href="https://motogo24.cz" style="color:#2563eb">motogo24.cz</a>.',
                  'Lors de la réservation, saisissez le code unique du bon dans le champ Code de réduction. La valeur est automatiquement déduite. Si le total dépasse la valeur du bon, le complément est réglé en ligne.',
                  'Les bons peuvent être combinés et plusieurs codes utilisés simultanément. Un bon doit être utilisé entièrement dans une seule réservation.',
                  'Nous recommandons de réserver à l\'avance, surtout en haute saison.'],
          close: 'Merci de votre confiance et profitez bien de l\'expérience offerte !' },
    pl: { intro: 'dziękujemy, że na prezent wybrałeś MOTO GO 24.',
          received: `Otrzymaliśmy zamówienie nr <strong>${v.order_number}</strong>, a płatność została zaksięgowana.`,
          attached: ['voucher prezentowy,', 'potwierdzenie zakupu vouchera.'],
          printed: 'Jeśli zamówiłeś wersję drukowaną, przygotowujemy ją. Spodziewaj się jej w skrzynce w najbliższych dniach.',
          usageH: 'Jak wykorzystać voucher',
          usage: ['Voucher jest ważny 3 lata od daty wystawienia i można go wykorzystać na wynajem dowolnego motocykla. Obdarowany rezerwuje termin z wyprzedzeniem przez formularz na <a href="https://motogo24.cz" style="color:#2563eb">motogo24.cz</a>.',
                  'Podczas rezerwacji wpisz unikalny kod z vouchera w polu Kod rabatowy. Wartość zostanie automatycznie odjęta od ceny. Jeśli kwota przewyższa wartość vouchera, różnicę można dopłacić online.',
                  'Vouchery można łączyć i jednocześnie wymieniać kilka kodów. Voucher trzeba wykorzystać w całości w ramach jednej rezerwacji.',
                  'Polecamy rezerwować z wyprzedzeniem, zwłaszcza w wysokim sezonie.'],
          close: 'Dziękujemy za zaufanie i życzymy obdarowanemu wspaniałych wrażeń!' },
  }
  const t = T[lang]
  return `<p>${HELLO[lang]}</p>
<p>${t.intro}</p>
<p>${t.received}</p>
<p>V příloze tohoto e-mailu najdete:</p>
<ul>${t.attached.map(a => `<li>${a}</li>`).join('')}</ul>
<p>${t.printed}</p>
<h3 style="color:#1a2e22;font-size:15px;margin-top:24px">${t.usageH}</h3>
${t.usage.map(p => `<p>${p}</p>`).join('')}
<p>${t.close}</p>
<p>${SIGN[lang]}</p>`
}

function renderShopConfirmedBody(lang: Lang, v: Vars): string {
  const T: Record<Lang, { intro: string; orderNum: string; total: string; ship: string; attached: string; followup: string; help: string; closing: string }> = {
    cs: { intro: 'děkujeme za vaši objednávku v e-shopu MotoGo24. Vaši platbu jsme úspěšně přijali.',
          orderNum: 'Číslo objednávky:', total: 'Celková cena:', ship: 'Doprava:',
          attached: 'V příloze najdete <strong>doklad o přijaté platbě</strong>.',
          followup: 'Jakmile vaši objednávku připravíme a předáme přepravci, pošleme vám e-mail s tracking číslem a finální fakturou.',
          help: 'Pokud máte jakýkoliv dotaz, jsme vám k dispozici.', closing: 'S pozdravem,' },
    en: { intro: 'thank you for your order at MOTO GO 24 e-shop. We have received your payment.',
          orderNum: 'Order number:', total: 'Total:', ship: 'Shipping:',
          attached: 'Attached you\'ll find the <strong>payment receipt</strong>.',
          followup: 'Once we ship your order, we\'ll send you an email with tracking number and the final invoice.',
          help: 'If you have any questions, we\'re here to help.', closing: 'Best regards,' },
    de: { intro: 'vielen Dank für Ihre Bestellung im MOTO GO 24 Shop. Ihre Zahlung ist eingegangen.',
          orderNum: 'Bestellnummer:', total: 'Gesamtpreis:', ship: 'Versand:',
          attached: 'Im Anhang finden Sie den <strong>Zahlungsbeleg</strong>.',
          followup: 'Sobald wir Ihre Bestellung versenden, erhalten Sie eine E-Mail mit Sendungsnummer und Endrechnung.',
          help: 'Bei Fragen sind wir für Sie da.', closing: 'Mit freundlichen Grüßen,' },
    nl: { intro: 'bedankt voor je bestelling bij MOTO GO 24. Je betaling is ontvangen.',
          orderNum: 'Bestelnummer:', total: 'Totaal:', ship: 'Verzending:',
          attached: 'In de bijlage vind je het <strong>betalingsbewijs</strong>.',
          followup: 'Zodra we je bestelling verzenden, ontvang je een e-mail met track & trace en de eindfactuur.',
          help: 'Heb je vragen? We helpen je graag.', closing: 'Met vriendelijke groet,' },
    es: { intro: 'gracias por tu pedido en la tienda MOTO GO 24. Hemos recibido tu pago.',
          orderNum: 'Nº de pedido:', total: 'Total:', ship: 'Envío:',
          attached: 'Adjuntamos el <strong>recibo de pago</strong>.',
          followup: 'Cuando enviemos tu pedido, te mandaremos un email con número de seguimiento y la factura final.',
          help: 'Si tienes preguntas, estamos para ayudarte.', closing: 'Saludos cordiales,' },
    fr: { intro: 'merci pour votre commande dans la boutique MOTO GO 24. Votre paiement est bien reçu.',
          orderNum: 'Numéro de commande :', total: 'Total :', ship: 'Livraison :',
          attached: 'Vous trouverez en pièce jointe le <strong>reçu de paiement</strong>.',
          followup: 'Dès l\'expédition, nous vous enverrons un e-mail avec le numéro de suivi et la facture finale.',
          help: 'Pour toute question, nous restons à votre disposition.', closing: 'Cordialement,' },
    pl: { intro: 'dziękujemy za zamówienie w sklepie MOTO GO 24. Twoja płatność została przyjęta.',
          orderNum: 'Numer zamówienia:', total: 'Suma:', ship: 'Dostawa:',
          attached: 'W załączniku znajdziesz <strong>potwierdzenie wpłaty</strong>.',
          followup: 'Po wysyłce otrzymasz e-mail z numerem przesyłki i fakturą końcową.',
          help: 'W razie pytań jesteśmy do dyspozycji.', closing: 'Pozdrawiamy,' },
  }
  const t = T[lang]
  return `<p>${HELLO[lang]}</p>
<p>${t.intro}</p>
<table style="width:100%;border-collapse:collapse;margin:16px 0;font-size:13px">
  <tr><td style="padding:6px 0;color:#6b7280">${t.orderNum}</td><td style="padding:6px 0;font-weight:700;color:#0f1a14">${v.order_number}</td></tr>
  <tr><td style="padding:6px 0;color:#6b7280">${t.total}</td><td style="padding:6px 0;font-weight:700;color:#0f1a14">${v.total_price}</td></tr>
  ${v.shipping_cost ? `<tr><td style="padding:6px 0;color:#6b7280">${t.ship}</td><td style="padding:6px 0;color:#0f1a14">${v.shipping_cost}</td></tr>` : ''}
</table>
<p>${t.attached}</p>
<p>${t.followup}</p>
<p>${t.help}</p>
<p>${t.closing}<br>${SIGN[lang]}</p>`
}

function renderShopShippedBody(lang: Lang, v: Vars): string {
  const T: Record<Lang, { intro: string; trackNum: string; trackUrl: string; attached: string; thanks: string; closing: string }> = {
    cs: { intro: `vaše objednávka č. <strong>${v.order_number}</strong> byla odeslána a brzy dorazí k vám.`,
          trackNum: 'Číslo zásilky:', trackUrl: 'Sledování:',
          attached: 'V příloze najdete <strong>konečnou fakturu</strong> za tuto objednávku.',
          thanks: 'Děkujeme za nákup u MOTO GO 24 a věříme, že budete s nákupem spokojeni.', closing: 'S pozdravem,' },
    en: { intro: `your order <strong>#${v.order_number}</strong> has been shipped and will reach you soon.`,
          trackNum: 'Tracking number:', trackUrl: 'Track at:',
          attached: 'Attached you\'ll find the <strong>final invoice</strong> for this order.',
          thanks: 'Thank you for shopping at MOTO GO 24 — we hope you\'ll love your purchase.', closing: 'Best regards,' },
    de: { intro: `Ihre Bestellung Nr. <strong>${v.order_number}</strong> wurde versandt und erreicht Sie bald.`,
          trackNum: 'Sendungsnummer:', trackUrl: 'Verfolgen unter:',
          attached: 'Im Anhang finden Sie die <strong>Endrechnung</strong> zu dieser Bestellung.',
          thanks: 'Danke für Ihren Einkauf bei MOTO GO 24 — wir hoffen, Sie sind zufrieden.', closing: 'Mit freundlichen Grüßen,' },
    nl: { intro: `je bestelling nr. <strong>${v.order_number}</strong> is verzonden en komt binnenkort aan.`,
          trackNum: 'Trackingnummer:', trackUrl: 'Volgen op:',
          attached: 'In de bijlage vind je de <strong>eindfactuur</strong> voor deze bestelling.',
          thanks: 'Bedankt voor je aankoop bij MOTO GO 24 — we hopen dat je tevreden bent.', closing: 'Met vriendelijke groet,' },
    es: { intro: `tu pedido nº <strong>${v.order_number}</strong> ha sido enviado y llegará pronto.`,
          trackNum: 'Nº de seguimiento:', trackUrl: 'Sigue en:',
          attached: 'Adjuntamos la <strong>factura final</strong> de este pedido.',
          thanks: '¡Gracias por comprar en MOTO GO 24 — esperamos que disfrutes tu compra!', closing: 'Saludos cordiales,' },
    fr: { intro: `votre commande n° <strong>${v.order_number}</strong> a été expédiée et vous parviendra sous peu.`,
          trackNum: 'Numéro de suivi :', trackUrl: 'Suivi sur :',
          attached: 'Vous trouverez en pièce jointe la <strong>facture finale</strong> de cette commande.',
          thanks: 'Merci pour votre achat chez MOTO GO 24 — nous espérons qu\'il vous plaira.', closing: 'Cordialement,' },
    pl: { intro: `Twoje zamówienie nr <strong>${v.order_number}</strong> zostało wysłane i wkrótce dotrze.`,
          trackNum: 'Numer przesyłki:', trackUrl: 'Śledzenie:',
          attached: 'W załączniku znajdziesz <strong>fakturę końcową</strong> do tego zamówienia.',
          thanks: 'Dziękujemy za zakupy w MOTO GO 24 — mamy nadzieję, że będziesz zadowolony.', closing: 'Pozdrawiamy,' },
  }
  const t = T[lang]
  return `<p>${HELLO[lang]}</p>
<p>${t.intro}</p>
${v.tracking_number ? `<table style="width:100%;border-collapse:collapse;margin:16px 0;font-size:13px">
  <tr><td style="padding:6px 0;color:#6b7280">${t.trackNum}</td><td style="padding:6px 0;font-weight:700;color:#0f1a14;font-family:monospace">${v.tracking_number}</td></tr>
  ${v.tracking_url ? `<tr><td style="padding:6px 0;color:#6b7280">${t.trackUrl}</td><td style="padding:6px 0"><a href="${v.tracking_url}" style="color:#2563eb">${v.tracking_url}</a></td></tr>` : ''}
</table>` : ''}
<p>${t.attached}</p>
<p>${t.thanks}</p>
<p>${t.closing}<br>${SIGN[lang]}</p>`
}

function renderModifiedBody(lang: Lang, v: Vars): string {
  const L = DIFF_LABELS[lang]
  const pickupOrig = [v.original_pickup_method, v.original_pickup_address].filter(Boolean).join(' — ')
  const pickupNew  = [v.pickup_method, v.pickup_address].filter(Boolean).join(' — ')
  const returnOrig = [v.original_return_method, v.original_return_address].filter(Boolean).join(' — ')
  const returnNew  = [v.return_method, v.return_address].filter(Boolean).join(' — ')

  const pd = Number((v.price_difference || '0').toString().replace(/\s/g, '').replace(',', '.')) || 0

  const intros: Record<Lang, string> = {
    cs: `vaše rezervace č. <strong>${v.booking_number}</strong> byla upravena. Níže najdete kompletní přehled změn — původní hodnoty jsou přeškrtnuté, nové zvýrazněné zeleně.`,
    en: `your booking <strong>#${v.booking_number}</strong> has been updated. Below is the full overview of changes — original values are struck through, new ones are highlighted green.`,
    de: `Ihre Buchung Nr. <strong>${v.booking_number}</strong> wurde geändert. Unten finden Sie die vollständige Übersicht der Änderungen — Originalwerte sind durchgestrichen, neue grün hervorgehoben.`,
    nl: `je boeking nr. <strong>${v.booking_number}</strong> is bijgewerkt. Hieronder zie je het volledige overzicht — originele waarden zijn doorgestreept, nieuwe groen gemarkeerd.`,
    es: `tu reserva nº <strong>${v.booking_number}</strong> ha sido actualizada. A continuación el resumen completo de los cambios — los valores originales aparecen tachados y los nuevos resaltados en verde.`,
    fr: `votre réservation n° <strong>${v.booking_number}</strong> a été modifiée. Ci-dessous le récapitulatif complet — les valeurs originales sont barrées, les nouvelles surlignées en vert.`,
    pl: `Twoja rezerwacja nr <strong>${v.booking_number}</strong> została zmieniona. Poniżej pełne podsumowanie zmian — pierwotne wartości są przekreślone, nowe wyróżnione na zielono.`,
  }
  const priceMsgs: Record<Lang, { plus: string; minus: string }> = {
    cs: { plus: `K úpravě se vztahuje <strong>doplatek ${v.price_difference}</strong>. Po platbě dorazí daňový doklad.`,                  minus: `K úpravě se vztahuje <strong>vrácení ${v.price_difference}</strong> formou dobropisu, který najdete v příloze. Refund jde zpět na původní platební kartu.` },
    en: { plus: `An additional payment of <strong>${v.price_difference}</strong> applies. The tax document will follow after payment.`,    minus: `A refund of <strong>${v.price_difference}</strong> applies as a credit note (attached). The amount returns to your original card.` },
    de: { plus: `Es fällt eine Nachzahlung von <strong>${v.price_difference}</strong> an. Der Beleg folgt nach Zahlungseingang.`,           minus: `Eine Rückerstattung von <strong>${v.price_difference}</strong> wird als Gutschrift (Anhang) erstattet — Betrag geht zurück auf Ihre ursprüngliche Karte.` },
    nl: { plus: `Er volgt een bijbetaling van <strong>${v.price_difference}</strong>. Het belastingdocument komt na betaling.`,             minus: `Een terugbetaling van <strong>${v.price_difference}</strong> wordt verwerkt als creditnota (bijlage) — bedrag terug op je oorspronkelijke kaart.` },
    es: { plus: `Se aplica un pago adicional de <strong>${v.price_difference}</strong>. El comprobante llegará tras el pago.`,             minus: `Se aplica un reembolso de <strong>${v.price_difference}</strong> mediante nota de crédito (adjunta) — el importe vuelve a tu tarjeta original.` },
    fr: { plus: `Un supplément de <strong>${v.price_difference}</strong> s'applique. Le justificatif suivra après paiement.`,              minus: `Un remboursement de <strong>${v.price_difference}</strong> est émis sous forme d'avoir (joint) — la somme retourne sur votre carte d'origine.` },
    pl: { plus: `Wymagana jest dopłata <strong>${v.price_difference}</strong>. Dokument podatkowy nadejdzie po płatności.`,                 minus: `Zwrot <strong>${v.price_difference}</strong> w formie noty kredytowej (załącznik) — środki wracają na pierwotną kartę.` },
  }
  const attachInfo: Record<Lang, string> = {
    cs: `V příloze najdete <strong>aktualizovanou nájemní smlouvu, VOP</strong> a všechny <strong>nové daňové doklady</strong> (zálohová faktura, doklad o platbě, případně dobropis).`,
    en: `Attached you'll find the <strong>updated rental agreement, terms</strong> and all <strong>new tax documents</strong> (proforma invoice, payment receipt, or credit note as applicable).`,
    de: `Im Anhang finden Sie den <strong>aktualisierten Mietvertrag, AGB</strong> und alle <strong>neuen Steuerbelege</strong> (Vorausrechnung, Zahlungsbeleg bzw. Gutschrift).`,
    nl: `In de bijlage vind je de <strong>bijgewerkte huurovereenkomst, voorwaarden</strong> en alle <strong>nieuwe belastingdocumenten</strong> (proforma factuur, betalingsbewijs of creditnota).`,
    es: `Adjuntamos el <strong>contrato de alquiler actualizado, condiciones</strong> y todos los <strong>nuevos documentos fiscales</strong> (factura proforma, recibo de pago o nota de crédito).`,
    fr: `Vous trouverez en pièce jointe le <strong>contrat de location mis à jour, CGV</strong> et tous les <strong>nouveaux justificatifs</strong> (facture proforma, reçu, ou avoir).`,
    pl: `W załączniku znajdziesz <strong>zaktualizowaną umowę najmu, regulamin</strong> i wszystkie <strong>nowe dokumenty podatkowe</strong> (faktura proforma, dowód wpłaty lub nota kredytowa).`,
  }
  const verify: Record<Lang, string> = {
    cs: `Pokud změnu neiniciovali jste vy a jde o nesrovnalost, ihned nás kontaktujte na`,
    en: `If you didn't initiate this change and it looks suspicious, contact us immediately at`,
    de: `Falls Sie diese Änderung nicht selbst veranlasst haben und sie verdächtig wirkt, kontaktieren Sie uns sofort unter`,
    nl: `Heb je deze wijziging niet zelf aangevraagd en lijkt het verdacht, neem dan direct contact op via`,
    es: `Si no iniciaste este cambio y parece sospechoso, contáctanos de inmediato en`,
    fr: `Si vous n'êtes pas à l'origine de ce changement et qu'il semble suspect, contactez-nous immédiatement à`,
    pl: `Jeśli to nie Ty zainicjowałeś tę zmianę i wygląda podejrzanie, skontaktuj się z nami natychmiast pod`,
  }
  const closing: Record<Lang, string> = {
    cs: 'S pozdravem,', en: 'Best regards,', de: 'Mit freundlichen Grüßen,',
    nl: 'Met vriendelijke groet,', es: 'Saludos cordiales,', fr: 'Cordialement,', pl: 'Pozdrawiamy,',
  }

  let priceMessage = ''
  if (pd > 0) priceMessage = `<p>${priceMsgs[lang].plus}</p>`
  else if (pd < 0) priceMessage = `<p>${priceMsgs[lang].minus}</p>`

  return `<p>${HELLO[lang]}</p>
<p>${intros[lang]}</p>
<table style="width:100%;border-collapse:collapse;margin:16px 0;border:1px solid #e5e7eb">
  <thead>
    <tr style="background:#f9fafb">
      <th style="padding:10px 12px;text-align:left;font-size:11px;color:#6b7280;letter-spacing:.5px;text-transform:uppercase">${L.uda}</th>
      <th style="padding:10px 12px;text-align:left;font-size:11px;color:#6b7280;letter-spacing:.5px;text-transform:uppercase">${L.old}</th>
      <th style="padding:10px 12px;text-align:left;font-size:11px;color:#6b7280;letter-spacing:.5px;text-transform:uppercase">${L.new}</th>
    </tr>
  </thead>
  <tbody>
    ${renderDiffRow(L.moto,   v.original_motorcycle,    v.motorcycle)}
    ${renderDiffRow(L.from,   v.original_start_date,    v.start_date)}
    ${renderDiffRow(L.to,     v.original_end_date,      v.end_date)}
    ${renderDiffRow(L.pickup, pickupOrig,               pickupNew)}
    ${renderDiffRow(L.ret,    returnOrig,               returnNew)}
    ${renderDiffRow(L.total,  v.original_total_price,   v.total_price)}
  </tbody>
</table>
${priceMessage}
<p>${attachInfo[lang]}</p>
<p>${verify[lang]} <a href="mailto:info@motogo24.cz" style="color:#2563eb">info@motogo24.cz</a>.</p>
<p>${closing[lang]}<br>${SIGN[lang]}</p>`
}

// =============================================================================
// PUBLIC API
// =============================================================================

/** Render subject + body for a given (slug, lang). Falls back to 'cs' if lang missing. */
export function renderEmail(
  slug: string,
  lang: Lang,
  vars: Vars
): { subject: string; body: string } | null {
  const subjFns = SUBJECTS[slug]
  const bodyFns = BODIES[slug]
  if (!subjFns || !bodyFns) return null
  const subjectFn = subjFns[lang] || subjFns.cs
  const bodyFn = bodyFns[lang] || bodyFns.cs
  return { subject: subjectFn(vars), body: bodyFn(vars) }
}

/** Per-lang sign-off (for help card / footer in wrapInBrandedLayout). */
export function signOff(lang: Lang): string { return SIGN[lang] || SIGN.cs }
export function helloPhrase(lang: Lang): string { return HELLO[lang] || HELLO.cs }

/** Per-lang labels for the help card "Have a question?" + CTA. */
export function helpCardLabels(lang: Lang): { title: string; body: string; cta: string } {
  const map: Record<Lang, { title: string; body: string; cta: string }> = {
    cs: { title: 'Máte dotaz?',           body: 'Pokud budete mít jakýkoliv dotaz, jsme vám k dispozici.',     cta: 'info@motogo24.cz' },
    en: { title: 'Have a question?',      body: 'If you have any questions, we\'re here to help.',              cta: 'info@motogo24.cz' },
    de: { title: 'Haben Sie eine Frage?', body: 'Bei Fragen sind wir gerne für Sie da.',                         cta: 'info@motogo24.cz' },
    nl: { title: 'Heb je een vraag?',     body: 'Heb je vragen? We helpen je graag.',                            cta: 'info@motogo24.cz' },
    es: { title: '¿Tienes preguntas?',    body: 'Si tienes alguna pregunta, estamos para ayudarte.',             cta: 'info@motogo24.cz' },
    fr: { title: 'Une question ?',        body: 'Pour toute question, nous sommes à votre disposition.',         cta: 'info@motogo24.cz' },
    pl: { title: 'Masz pytanie?',         body: 'W razie pytań jesteśmy do dyspozycji.',                         cta: 'info@motogo24.cz' },
  }
  return map[lang] || map.cs
}
