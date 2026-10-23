// In-app zprávy (messages, vlákno „Rezervace“) při změně stavu výpůjčky JEN výbavy z Velína — v jazyce
// zákazníka (bookings.language; 8 jazyků, tykání jako gear e-maily), vždy s číslem rezervace, bez motorky,
// SOS a jízdy. Jen záložní text: e-maily jdou ze šablon Velínu gear_* (DESIGN §1.10); slug message_templates
// pro tyto zprávy DESIGN nedefinuje. Názvy kusů = popisky předávacího protokolu (protocolI18nA/B g_*).
import { PROTO_A } from './protocolI18nA'
import { PROTO_B } from './protocolI18nB'
import { GEAR_LABELS, gearItems } from '../../lib/bookingKind'

const LANGS = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk']
const LOCALE = { cs: 'cs-CZ', en: 'en-GB', de: 'de-DE', es: 'es-ES', fr: 'fr-FR', nl: 'nl-NL', pl: 'pl-PL', uk: 'uk-UA' }
const ITEM_FX = { ...PROTO_A, ...PROTO_B }

const T = {
  cs: {
    reserved: (n, w, d) => `Tvoje výpůjčka výbavy ${n}${w} na ${d} je potvrzená. Smlouvu a doklady najdeš v sekci Dokumenty.`,
    active: (n, w, d, e) => `Výbava k výpůjčce ${n} je předaná. Šťastnou cestu! Vrátit ji máš do ${e} na stejnou pobočku.`,
    completed: n => `Výpůjčka výbavy ${n} je dokončená — díky za vrácení výbavy. Konečnou fakturu najdeš v sekci Dokumenty.`,
  },
  en: {
    reserved: (n, w, d) => `Your gear rental ${n}${w} for ${d} is confirmed. You'll find the contract and documents in the Documents section.`,
    active: (n, w, d, e) => `The gear for rental ${n} has been handed over. Have a great ride! Please return it by ${e} to the same branch.`,
    completed: n => `Gear rental ${n} is completed — thanks for returning the gear. You'll find the final invoice in the Documents section.`,
  },
  de: {
    reserved: (n, w, d) => `Deine Ausrüstungsmiete ${n}${w} für ${d} ist bestätigt. Vertrag und Belege findest du im Bereich Dokumente.`,
    active: (n, w, d, e) => `Die Ausrüstung zur Miete ${n} wurde übergeben. Gute Fahrt! Bitte gib sie bis ${e} in derselben Filiale zurück.`,
    completed: n => `Die Ausrüstungsmiete ${n} ist abgeschlossen — danke für die Rückgabe. Die Schlussrechnung findest du im Bereich Dokumente.`,
  },
  es: {
    reserved: (n, w, d) => `Tu alquiler de equipamiento ${n}${w} para ${d} está confirmado. Encontrarás el contrato y los documentos en la sección Documentos.`,
    active: (n, w, d, e) => `El equipamiento del alquiler ${n} ya está entregado. ¡Buen viaje! Devuélvelo a más tardar el ${e} en la misma sucursal.`,
    completed: n => `El alquiler de equipamiento ${n} ha finalizado — gracias por devolverlo. Encontrarás la factura final en la sección Documentos.`,
  },
  fr: {
    reserved: (n, w, d) => `Ta location d'équipement ${n}${w} pour ${d} est confirmée. Tu trouveras le contrat et les documents dans la rubrique Documents.`,
    active: (n, w, d, e) => `L'équipement de la location ${n} t'a été remis. Bonne route ! Rends-le au plus tard le ${e} dans la même agence.`,
    completed: n => `La location d'équipement ${n} est terminée — merci d'avoir rendu l'équipement. Tu trouveras la facture finale dans la rubrique Documents.`,
  },
  nl: {
    reserved: (n, w, d) => `Je huur van uitrusting ${n}${w} voor ${d} is bevestigd. Het contract en de documenten vind je onder Documenten.`,
    active: (n, w, d, e) => `De uitrusting van huur ${n} is overgedragen. Goede rit! Breng ze uiterlijk ${e} terug naar dezelfde vestiging.`,
    completed: n => `De huur van uitrusting ${n} is afgerond — bedankt voor het terugbrengen. De eindfactuur vind je onder Documenten.`,
  },
  pl: {
    reserved: (n, w, d) => `Twoje wypożyczenie sprzętu ${n}${w} na ${d} jest potwierdzone. Umowę i dokumenty znajdziesz w sekcji Dokumenty.`,
    active: (n, w, d, e) => `Sprzęt z wypożyczenia ${n} został wydany. Szerokiej drogi! Zwróć go do ${e} w tym samym oddziale.`,
    completed: n => `Wypożyczenie sprzętu ${n} jest zakończone — dziękujemy za zwrot sprzętu. Fakturę końcową znajdziesz w sekcji Dokumenty.`,
  },
  uk: {
    reserved: (n, w, d) => `Твою оренду спорядження ${n}${w} на ${d} підтверджено. Договір і документи знайдеш у розділі «Документи».`,
    active: (n, w, d, e) => `Спорядження за орендою ${n} видано. Щасливої дороги! Поверни його до ${e} у ту саму філію.`,
    completed: n => `Оренду спорядження ${n} завершено — дякуємо за повернення спорядження. Остаточний рахунок знайдеш у розділі «Документи».`,
  },
}

export function gearMsgLang(raw) {
  const l = String(raw || '').toLowerCase().slice(0, 2)
  return LANGS.includes(l) ? l : 'cs'
}

const fmtDay = (d, l) => (d ? new Date(d).toLocaleDateString(LOCALE[l], { timeZone: 'Europe/Prague' }) : '')

/** Text in-app zprávy pro stav (reserved | active | completed) nebo null. */
export function gearStatusMessage(status, b) {
  const l = gearMsgLang(b?.language)
  const tpl = T[l][status]
  if (!tpl) return null
  const items = gearItems(b).map(i => `${l === 'cs' ? GEAR_LABELS[i.key] : (ITEM_FX[l]?.['g_' + i.key] || GEAR_LABELS[i.key])} ${i.size}`).join(', ')
  const no = `#${String(b?.id || '').slice(-8).toUpperCase()}`
  const s = fmtDay(b?.start_date, l), e = fmtDay(b?.end_date, l)
  return tpl(no, items ? ` (${items})` : '', `${s} – ${e}`, e)
}
