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
