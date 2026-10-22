// ===== Potvrzení půjčení výbavy bez motorky (gear_rentals, 2026-10-22) =====
// DB trigger trg_send_shop_order_confirmed_email posílá po zaplacení typ
// 'shop_order_confirmed'. Když k objednávce existuje řádek gear_rentals,
// index.ts přepne renderType na 'gear_rental_confirmed' a tělo/předmět jde
// odsud (termín, pobočka, výbava s velikostmi, jak vyzvednout). DB šablona se
// slugem (web_)gear_rental_confirmed ve Velínu by měla přednost. Přílohy (DP)
// a logovaný slug zůstávají dle shop_order_confirmed.
import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { helloPhrase, signOff, type Lang } from './i18n.ts'

type Vars = Record<string, string>
type Line = { key: string; kind: string; label: string; sizes?: Record<string, string | null>; price_per_day?: number }

const LOCALE: Record<Lang, string> = { cs: 'cs-CZ', en: 'en-GB', de: 'de-DE', nl: 'nl-NL', es: 'es-ES', fr: 'fr-FR', pl: 'pl-PL', uk: 'uk-UA' }
const esc = (s: unknown) => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!))
const fmtD = (iso: string, lang: Lang) => {
  try { return new Date(iso + 'T12:00:00Z').toLocaleDateString(LOCALE[lang], { day: 'numeric', month: 'numeric', year: 'numeric', timeZone: 'UTC' }) } catch { return iso }
}
const kc = (n: number) => `${Math.round(n).toLocaleString('cs-CZ')} Kč`

type T = {
  subj: string; intro: string; order: string; term: string; branch: string; time: string; total: string; gear: string;
  perDay: string; days: (n: number) => string; staffed: string; self: string; ret: string; change: string; attached: string; note: string; bye: string
}
const TX: Record<Lang, T> = {
  cs: { subj: 'Půjčení výbavy č. {n} je potvrzené — MOTO GO 24', intro: 'děkujeme, vaše půjčení výbavy je zaplacené a potvrzené.',
    order: 'Číslo objednávky:', term: 'Termín:', branch: 'Pobočka:', time: 'Čas vyzvednutí:', total: 'Celkem zaplaceno:', gear: 'Výbava:',
    perDay: '/den', days: n => n === 1 ? '1 den' : n < 5 ? `${n} dny` : `${n} dní`,
    staffed: 'Výbavu si vyzvednete osobně na pobočce v první den výpůjčky. Kdybyste potřebovali čas vyzvednutí upřesnit, ozvěte se nám.',
    self: 'Pobočka Velké Němčice je samoobslužná: před vyzvednutím se vám ozveme a pošleme kód k šatně s vaší výbavou.',
    ret: 'Výbavu vraťte nejpozději poslední den výpůjčky na stejnou pobočku.',
    change: 'Potřebujete změnit termín nebo velikost? Stačí odpovědět na tento e-mail nebo zavolat na +420 774 256 271.',
    attached: 'V příloze najdete <strong>doklad o přijaté platbě</strong>.', note: 'Vaše poznámka:', bye: 'S pozdravem,' },
  en: { subj: 'Gear rental #{n} confirmed — MOTO GO 24', intro: 'thank you, your gear rental is paid and confirmed.',
    order: 'Order number:', term: 'Dates:', branch: 'Branch:', time: 'Pick-up time:', total: 'Total paid:', gear: 'Gear:',
    perDay: '/day', days: n => n === 1 ? '1 day' : `${n} days`,
    staffed: 'Pick up your gear in person at the branch on the first day of the rental. If you need to adjust the pick-up time, just let us know.',
    self: 'Velké Němčice is a self-service branch: before pick-up we will contact you and send you the code to the locker room with your gear.',
    ret: 'Please return the gear to the same branch by the last day of the rental.',
    change: 'Need to change the dates or a size? Simply reply to this email or call +420 774 256 271.',
    attached: 'Attached you\'ll find the <strong>payment receipt</strong>.', note: 'Your note:', bye: 'Best regards,' },
  de: { subj: 'Ausrüstungsverleih Nr. {n} bestätigt — MOTO GO 24', intro: 'vielen Dank, Ihr Ausrüstungsverleih ist bezahlt und bestätigt.',
    order: 'Bestellnummer:', term: 'Zeitraum:', branch: 'Filiale:', time: 'Abholzeit:', total: 'Bezahlt:', gear: 'Ausrüstung:',
    perDay: '/Tag', days: n => n === 1 ? '1 Tag' : `${n} Tage`,
    staffed: 'Sie holen die Ausrüstung am ersten Miettag persönlich in der Filiale ab. Wenn Sie die Abholzeit anpassen möchten, melden Sie sich einfach.',
    self: 'Velké Němčice ist eine Selbstbedienungsfiliale: Vor der Abholung melden wir uns und senden Ihnen den Code für den Umkleideraum mit Ihrer Ausrüstung.',
    ret: 'Bitte geben Sie die Ausrüstung spätestens am letzten Miettag in derselben Filiale zurück.',
    change: 'Möchten Sie Zeitraum oder Größe ändern? Antworten Sie einfach auf diese E-Mail oder rufen Sie +420 774 256 271 an.',
    attached: 'Im Anhang finden Sie den <strong>Zahlungsbeleg</strong>.', note: 'Ihre Anmerkung:', bye: 'Mit freundlichen Grüßen,' },
  nl: { subj: 'Uitrustingshuur nr. {n} bevestigd — MOTO GO 24', intro: 'bedankt, je uitrustingshuur is betaald en bevestigd.',
    order: 'Bestelnummer:', term: 'Periode:', branch: 'Vestiging:', time: 'Ophaaltijd:', total: 'Totaal betaald:', gear: 'Uitrusting:',
    perDay: '/dag', days: n => n === 1 ? '1 dag' : `${n} dagen`,
    staffed: 'Je haalt de uitrusting op de eerste huurdag persoonlijk op bij de vestiging. Wil je de ophaaltijd aanpassen, laat het ons dan weten.',
    self: 'Velké Němčice is een selfservicevestiging: vóór het ophalen nemen we contact met je op en sturen we je de code van de kleedruimte met je uitrusting.',
    ret: 'Breng de uitrusting uiterlijk op de laatste huurdag terug naar dezelfde vestiging.',
    change: 'Wil je de periode of een maat wijzigen? Beantwoord deze e-mail of bel +420 774 256 271.',
    attached: 'In de bijlage vind je het <strong>betalingsbewijs</strong>.', note: 'Jouw opmerking:', bye: 'Met vriendelijke groet,' },
  es: { subj: 'Alquiler de equipo nº {n} confirmado — MOTO GO 24', intro: 'gracias, tu alquiler de equipo está pagado y confirmado.',
    order: 'Nº de pedido:', term: 'Fechas:', branch: 'Sucursal:', time: 'Hora de recogida:', total: 'Total pagado:', gear: 'Equipo:',
    perDay: '/día', days: n => n === 1 ? '1 día' : `${n} días`,
    staffed: 'Recoges el equipo en persona en la sucursal el primer día del alquiler. Si necesitas ajustar la hora de recogida, avísanos.',
    self: 'Velké Němčice es una sucursal de autoservicio: antes de la recogida te contactaremos y te enviaremos el código del vestuario con tu equipo.',
    ret: 'Devuelve el equipo en la misma sucursal como muy tarde el último día del alquiler.',
    change: '¿Necesitas cambiar las fechas o una talla? Responde a este correo o llama al +420 774 256 271.',
    attached: 'Adjuntamos el <strong>recibo de pago</strong>.', note: 'Tu nota:', bye: 'Saludos cordiales,' },
  fr: { subj: 'Location d\'équipement n° {n} confirmée — MOTO GO 24', intro: 'merci, votre location d\'équipement est payée et confirmée.',
    order: 'Numéro de commande :', term: 'Dates :', branch: 'Agence :', time: 'Heure de retrait :', total: 'Total payé :', gear: 'Équipement :',
    perDay: '/jour', days: n => n === 1 ? '1 jour' : `${n} jours`,
    staffed: 'Vous retirez l\'équipement en personne à l\'agence le premier jour de la location. Pour ajuster l\'heure de retrait, contactez-nous.',
    self: 'Velké Němčice est une agence en libre-service : avant le retrait, nous vous contacterons et vous enverrons le code du vestiaire avec votre équipement.',
    ret: 'Merci de rendre l\'équipement à la même agence au plus tard le dernier jour de la location.',
    change: 'Besoin de changer les dates ou une taille ? Répondez à cet e-mail ou appelez le +420 774 256 271.',
    attached: 'Vous trouverez en pièce jointe le <strong>reçu de paiement</strong>.', note: 'Votre remarque :', bye: 'Cordialement,' },
  pl: { subj: 'Wypożyczenie wyposażenia nr {n} potwierdzone — MOTO GO 24', intro: 'dziękujemy, wypożyczenie wyposażenia jest opłacone i potwierdzone.',
    order: 'Numer zamówienia:', term: 'Termin:', branch: 'Oddział:', time: 'Godzina odbioru:', total: 'Zapłacono:', gear: 'Wyposażenie:',
    perDay: '/dzień', days: n => n === 1 ? '1 dzień' : `${n} dni`,
    staffed: 'Wyposażenie odbierzesz osobiście w oddziale pierwszego dnia wypożyczenia. Jeśli chcesz zmienić godzinę odbioru, daj nam znać.',
    self: 'Velké Němčice to oddział samoobsługowy: przed odbiorem skontaktujemy się z Tobą i wyślemy kod do szatni z Twoim wyposażeniem.',
    ret: 'Wyposażenie zwróć najpóźniej ostatniego dnia wypożyczenia w tym samym oddziale.',
    change: 'Chcesz zmienić termin lub rozmiar? Odpowiedz na tego e-maila albo zadzwoń: +420 774 256 271.',
    attached: 'W załączniku znajdziesz <strong>potwierdzenie wpłaty</strong>.', note: 'Twoja uwaga:', bye: 'Pozdrawiamy,' },
  uk: { subj: 'Оренду спорядження № {n} підтверджено — MOTO GO 24', intro: 'дякуємо, оренду спорядження оплачено й підтверджено.',
    order: 'Номер замовлення:', term: 'Термін:', branch: 'Філія:', time: 'Час отримання:', total: 'Сплачено:', gear: 'Спорядження:',
    perDay: '/день', days: n => n === 1 ? '1 день' : n < 5 ? `${n} дні` : `${n} днів`,
    staffed: 'Спорядження ви отримаєте особисто у філії в перший день оренди. Якщо потрібно змінити час отримання, напишіть нам.',
    self: 'Філія Velké Němčice працює в режимі самообслуговування: перед отриманням ми зв\'яжемося з вами й надішлемо код до гардеробу з вашим спорядженням.',
    ret: 'Поверніть спорядження до тієї ж філії не пізніше останнього дня оренди.',
    change: 'Потрібно змінити термін або розмір? Просто відповідайте на цей лист або телефонуйте: +420 774 256 271.',
    attached: 'У вкладенні — <strong>підтвердження оплати</strong>.', note: 'Ваша примітка:', bye: 'З повагою,' },
}

function linesHtml(lines: Line[], labels: Record<string, Record<string, string>>, lang: Lang, t: T): string {
  const lb = (k: string, fb: string) => labels[k]?.[lang] || labels[k]?.cs || fb
  return '<ul style="margin:6px 0 0;padding-left:18px">' + lines.map(l => {
    const sizes = Object.entries(l.sizes || {}).filter(([, v]) => v)
      .map(([k, v]) => l.kind === 'set' ? `${lb(k, k).toLowerCase()} ${v}` : String(v)).join(', ')
    return `<li style="margin:2px 0"><strong>${esc(lb(l.key, l.label))}</strong>${sizes ? ` — ${esc(sizes)}` : ''}` +
      (l.price_per_day != null ? ` <span style="color:#6b7280">(${kc(Number(l.price_per_day))}${t.perDay})</span>` : '') + '</li>'
  }).join('') + '</ul>'
}

/** Proměnné pro šablonu — null, když objednávka není půjčení výbavy. */
export async function loadGearRentalVars(supabase: SupabaseClient, orderId: string, lang: Lang): Promise<Vars | null> {
  const { data: g } = await supabase.from('gear_rentals')
    .select('branch_id, start_date, end_date, days, pickup_time, lines, note').eq('order_id', orderId).maybeSingle()
  if (!g) return null
  const { data: b } = await supabase.from('branches').select('name, address, city, type').eq('id', g.branch_id).maybeSingle()
  const { data: pr } = await supabase.from('gear_rental_prices').select('key, label, translations')
  const labels: Record<string, Record<string, string>> = {}
  for (const p of (pr || []) as { key: string; label: string; translations?: Record<string, { label?: string }> }[]) {
    labels[p.key] = { cs: p.label }
    for (const [l, v] of Object.entries(p.translations || {})) if (v?.label) labels[p.key][l] = v.label
  }
  const lines = (Array.isArray(g.lines) ? g.lines : []) as Line[]
  const brName = String(b?.name || '').replace(/^MotoGo24\s*/i, '')
  return {
    gear_lang: lang,
    gear_start: String(g.start_date), gear_end: String(g.end_date), gear_days: String(g.days || 1),
    gear_pickup_time: g.pickup_time ? String(g.pickup_time).slice(0, 5) : '',
    gear_branch: [b?.name, [b?.address, b?.city].filter(Boolean).join(', ')].filter(Boolean).join(', ') || brName,
    gear_self: b?.type === 'samoobslužná' ? '1' : '',
    gear_note: g.note ? String(g.note) : '',
    gear_lines_json: JSON.stringify(lines), gear_labels_json: JSON.stringify(labels),
  }
}

/** Předmět + tělo v jazyce `lang` (vars z loadGearRentalVars + order_number, total_price, customer_name). */
export function renderGearRentalEmail(lang: Lang, v: Vars): { subject: string; body: string } {
  const t = TX[lang] || TX.cs
  const days = Number(v.gear_days) || 1
  let lines: Line[] = []; let labels: Record<string, Record<string, string>> = {}
  try { lines = JSON.parse(v.gear_lines_json || '[]'); labels = JSON.parse(v.gear_labels_json || '{}') } catch { /* prázdné */ }
  const row = (k: string, val: string) => `<tr><td style="padding:6px 12px 6px 0;color:#6b7280;vertical-align:top">${k}</td><td style="padding:6px 0;font-weight:700;color:#0f1a14">${val}</td></tr>`
  const body = `<p>${esc(helloPhrase(lang))}</p>
<p>${t.intro}</p>
<table style="width:100%;border-collapse:collapse;margin:16px 0;font-size:13px">
${row(t.order, esc(v.order_number))}
${row(t.term, `${esc(fmtD(v.gear_start, lang))} – ${esc(fmtD(v.gear_end, lang))} (${esc(t.days(days))})`)}
${row(t.branch, esc(v.gear_branch))}
${v.gear_pickup_time && !v.gear_self ? row(t.time, esc(v.gear_pickup_time)) : ''}
${row(t.total, esc(v.total_price))}
</table>
<p style="margin:0"><strong>${t.gear}</strong></p>
${linesHtml(lines, labels, lang, t)}
${v.gear_note ? `<p style="margin-top:12px;color:#374151"><em>${t.note}</em> ${esc(v.gear_note)}</p>` : ''}
<p style="margin-top:16px">${v.gear_self ? t.self : t.staffed}</p>
<p>${t.ret}</p>
<p>${t.change}</p>
<p>${t.attached}</p>
<p>${t.bye}<br>${signOff(lang)}</p>`
  return { subject: t.subj.replace('{n}', v.order_number || ''), body }
}
