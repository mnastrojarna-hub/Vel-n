// =============================================================================
// Konkrétní důvod zadržení přístupových kódů v e-mailu (2026-10-10, review C11)
// =============================================================================
// `reason` = withheld_reason řádku branch_door_codes / výsledek
// check_booking_docs_status (_docs_gate_checklist → části spojené „; “).
// Části, které NAHRÁNÍM fotek nevyřešíte (věk pod 18, nedostatečná skupina ŘP,
// propadlý ŘP), jsou „blocker“ → blok ukáže kontakt (telefon) místo pouhé
// výzvy „Nahrát doklady“. Neznámé části = doklady (dosavadní chování); mimo cs
// se nepřekládají a vynechají se (český text do cizojazyčného mailu nedáváme).
import type { Lang } from './i18n.ts'

type ReasonKey = 'idBoth' | 'idBack' | 'idFront' | 'dlBoth' | 'dlBack' | 'dlFront'
  | 'dob' | 'under18' | 'expMissing' | 'expired' | 'grpMissing' | 'grpLow'
type ReasonTexts = Record<ReasonKey, string> & { label: string; title: string; alt: string; ctaCheck: string }

const PHONE = '<a href="tel:+420774256271" style="color:#9a3412;font-weight:700;white-space:nowrap">+420 774 256 271</a>'

// [vzor části důvodu z DB, klíč překladu, blocker]
const PARTS: Array<[RegExp, ReasonKey, boolean]> = [
  [/^Chybí OP \(líc a rub\) nebo pas$/, 'idBoth', false],
  [/^Chybí rub OP$/, 'idBack', false],
  [/^Chybí líc OP$/, 'idFront', false],
  [/^Chybí ŘP \(líc a rub\)$/, 'dlBoth', false],
  [/^Chybí rub ŘP$/, 'dlBack', false],
  [/^Chybí líc ŘP$/, 'dlFront', false],
  [/^Chybí datum narození$/, 'dob', false],
  [/^Zákazníkovi není 18 let$/, 'under18', true],
  [/^Chybí platnost ŘP$/, 'expMissing', false],
  [/^ŘP propadlý (.+)$/, 'expired', true],
  [/^Chybí skupina ŘP$/, 'grpMissing', false],
  [/^Skupina ŘP nestačí \(potřeba (.+)\)$/, 'grpLow', true],
]

// cs: DB text 1:1, jen tyto dvě části přeformulované pro zákazníka („ŘP propadlý“
// = platí jen do data PŘED koncem pronájmu, datum může být i budoucí).
const CS_TR: Partial<Record<ReasonKey, string>> = {
  under18: 'K začátku pronájmu vám ještě nebude 18 let',
  expired: 'ŘP platí jen do {x} (musí platit do konce pronájmu)',
}

const CS_EXTRA = { label: 'Důvod', title: 'Přístupové kódy zatím nemůžeme vydat', ctaCheck: 'Zkontrolovat doklady',
  alt: `Pokud to úpravou dokladů nevyřešíte, zavolejte nám na ${PHONE} — domluvíme řešení (např. jinou motorku nebo úpravu rezervace).` }

const T: Partial<Record<Lang, ReasonTexts>> = {
  en: { idBoth: 'ID card (front and back) or passport missing', idBack: 'back of the ID card missing', idFront: 'front of the ID card missing',
    dlBoth: 'driving licence (front and back) missing', dlBack: 'back of the driving licence missing', dlFront: 'front of the driving licence missing',
    dob: 'date of birth missing', under18: 'you are not yet 18', expMissing: 'driving licence expiry date missing',
    expired: 'driving licence valid only until {x} (it must be valid until the end of the rental)', grpMissing: 'driving licence category missing',
    grpLow: 'driving licence category not sufficient (required: {x})', label: 'Reason', title: 'We can\'t release the access codes yet', ctaCheck: 'Check documents',
    alt: `If you can't fix this by updating your documents, call us at ${PHONE} — we'll find a solution (e.g. a different motorcycle or a change to your booking).` },
  de: { idBoth: 'Personalausweis (Vorder- und Rückseite) oder Reisepass fehlt', idBack: 'Rückseite des Personalausweises fehlt', idFront: 'Vorderseite des Personalausweises fehlt',
    dlBoth: 'Führerschein (Vorder- und Rückseite) fehlt', dlBack: 'Rückseite des Führerscheins fehlt', dlFront: 'Vorderseite des Führerscheins fehlt',
    dob: 'Geburtsdatum fehlt', under18: 'Sie sind noch nicht 18 Jahre alt', expMissing: 'Gültigkeitsdatum des Führerscheins fehlt',
    expired: 'Führerschein nur bis {x} gültig (er muss bis zum Ende der Miete gültig sein)', grpMissing: 'Führerscheinklasse fehlt',
    grpLow: 'Führerscheinklasse reicht nicht aus (erforderlich: {x})', label: 'Grund', title: 'Die Zugangscodes können wir noch nicht freigeben', ctaCheck: 'Dokumente prüfen',
    alt: `Lässt sich das nicht durch Aktualisieren Ihrer Dokumente lösen, rufen Sie uns an: ${PHONE} — wir finden eine Lösung (z. B. ein anderes Motorrad oder eine Änderung der Buchung).` },
  nl: { idBoth: 'identiteitsbewijs (voor- en achterkant) of paspoort ontbreekt', idBack: 'achterkant van het identiteitsbewijs ontbreekt', idFront: 'voorkant van het identiteitsbewijs ontbreekt',
    dlBoth: 'rijbewijs (voor- en achterkant) ontbreekt', dlBack: 'achterkant van het rijbewijs ontbreekt', dlFront: 'voorkant van het rijbewijs ontbreekt',
    dob: 'geboortedatum ontbreekt', under18: 'je bent nog geen 18 jaar', expMissing: 'geldigheidsdatum van het rijbewijs ontbreekt',
    expired: 'rijbewijs alleen geldig tot {x} (het moet geldig zijn tot het einde van de huur)', grpMissing: 'rijbewijscategorie ontbreekt',
    grpLow: 'rijbewijscategorie volstaat niet (vereist: {x})', label: 'Reden', title: 'De toegangscodes kunnen nog niet worden vrijgegeven', ctaCheck: 'Documenten controleren',
    alt: `Lukt het niet om dit op te lossen door je documenten bij te werken? Bel ons op ${PHONE} — we zoeken een oplossing (bijv. een andere motor of een wijziging van de reservering).` },
  es: { idBoth: 'falta el documento de identidad (anverso y reverso) o el pasaporte', idBack: 'falta el reverso del documento de identidad', idFront: 'falta el anverso del documento de identidad',
    dlBoth: 'falta el permiso de conducir (anverso y reverso)', dlBack: 'falta el reverso del permiso de conducir', dlFront: 'falta el anverso del permiso de conducir',
    dob: 'falta la fecha de nacimiento', under18: 'todavía no tienes 18 años', expMissing: 'falta la fecha de validez del permiso de conducir',
    expired: 'el permiso de conducir solo es válido hasta el {x} (debe ser válido hasta el final del alquiler)', grpMissing: 'falta la categoría del permiso de conducir',
    grpLow: 'la categoría del permiso de conducir no es suficiente (se requiere: {x})', label: 'Motivo', title: 'Todavía no podemos emitir los códigos de acceso', ctaCheck: 'Revisar documentos',
    alt: `Si no puedes resolverlo actualizando tus documentos, llámanos al ${PHONE} y buscaremos una solución (p. ej., otra moto o un cambio en la reserva).` },
  fr: { idBoth: 'pièce d\'identité (recto et verso) ou passeport manquant', idBack: 'verso de la pièce d\'identité manquant', idFront: 'recto de la pièce d\'identité manquant',
    dlBoth: 'permis de conduire (recto et verso) manquant', dlBack: 'verso du permis de conduire manquant', dlFront: 'recto du permis de conduire manquant',
    dob: 'date de naissance manquante', under18: 'vous n\'avez pas encore 18 ans', expMissing: 'date de validité du permis de conduire manquante',
    expired: 'permis de conduire valable seulement jusqu\'au {x} (il doit être valable jusqu\'à la fin de la location)', grpMissing: 'catégorie du permis de conduire manquante',
    grpLow: 'catégorie du permis de conduire insuffisante (requise : {x})', label: 'Motif', title: 'Nous ne pouvons pas encore délivrer les codes d\'accès', ctaCheck: 'Vérifier les documents',
    alt: `Si vous ne pouvez pas régler cela en mettant à jour vos documents, appelez-nous au ${PHONE} — nous trouverons une solution (par ex. une autre moto ou une modification de la réservation).` },
  pl: { idBoth: 'brak dowodu osobistego (przód i tył) lub paszportu', idBack: 'brak tyłu dowodu osobistego', idFront: 'brak przodu dowodu osobistego',
    dlBoth: 'brak prawa jazdy (przód i tył)', dlBack: 'brak tyłu prawa jazdy', dlFront: 'brak przodu prawa jazdy',
    dob: 'brak daty urodzenia', under18: 'nie masz jeszcze 18 lat', expMissing: 'brak daty ważności prawa jazdy',
    expired: 'prawo jazdy ważne tylko do {x} (musi być ważne do końca wypożyczenia)', grpMissing: 'brak kategorii prawa jazdy',
    grpLow: 'kategoria prawa jazdy nie wystarcza (wymagana: {x})', label: 'Powód', title: 'Nie możemy jeszcze wydać kodów dostępu', ctaCheck: 'Sprawdź dokumenty',
    alt: `Jeśli nie rozwiążesz tego, aktualizując dokumenty, zadzwoń do nas: ${PHONE} — znajdziemy rozwiązanie (np. inny motocykl lub zmianę rezerwacji).` },
  uk: { idBoth: 'бракує документа, що посвідчує особу (лицьовий і зворотний бік), або паспорта', idBack: 'бракує зворотного боку документа, що посвідчує особу', idFront: 'бракує лицьового боку документа, що посвідчує особу',
    dlBoth: 'бракує посвідчення водія (лицьовий і зворотний бік)', dlBack: 'бракує зворотного боку посвідчення водія', dlFront: 'бракує лицьового боку посвідчення водія',
    dob: 'бракує дати народження', under18: 'вам ще не виповнилося 18 років', expMissing: 'бракує терміну дії посвідчення водія',
    expired: 'посвідчення водія дійсне лише до {x} (має бути дійсним до кінця оренди)', grpMissing: 'бракує категорії посвідчення водія',
    grpLow: 'категорія посвідчення водія недостатня (потрібна: {x})', label: 'Причина', title: 'Поки не можемо видати коди доступу', ctaCheck: 'Перевірити документи',
    alt: `Якщо це не вдасться вирішити оновленням документів, зателефонуйте нам: ${PHONE} — знайдемо рішення (наприклад, інший мотоцикл або зміну бронювання).` },
}

const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')

export interface DocsReasonInfo {
  /** Lokalizovaný důvod („Chybí rub OP; Skupina ŘP nestačí…“), HTML-escapovaný; '' = bez řádku. */
  line: string
  /** Je mezi důvody něco, co vyřeší nahrání / doplnění dokladů (nebo neznámý důvod). */
  docs: boolean
  /** Je mezi důvody věk / skupina ŘP / propadlý ŘP (nahráním fotek to nevyřešíte). */
  blocker: boolean
  label: string; title: string; alt: string; ctaCheck: string
}

export function docsReasonInfo(lang: Lang, reason: string | null | undefined): DocsReasonInfo {
  const tr = lang === 'cs' ? null : T[lang] || null
  const extra = tr || CS_EXTRA
  const out: string[] = []
  let docs = false, blocker = false
  for (const raw of String(reason || '').split(';').map(s => s.trim()).filter(Boolean)) {
    const hit = PARTS.find(([rx]) => rx.test(raw))
    if (!hit) { docs = true; if (!tr) out.push(esc(raw)); continue }
    const [rx, key, isBlocker] = hit
    if (isBlocker) blocker = true; else docs = true
    const txt = tr ? tr[key] : CS_TR[key]
    out.push(esc(txt ? txt.replace('{x}', raw.match(rx)?.[1] || '') : raw))
  }
  const line = out.join('; ')
  return {
    line: line ? line.charAt(0).toUpperCase() + line.slice(1) : '',
    docs, blocker,
    label: extra.label, title: extra.title, alt: extra.alt, ctaCheck: extra.ctaCheck,
  }
}
