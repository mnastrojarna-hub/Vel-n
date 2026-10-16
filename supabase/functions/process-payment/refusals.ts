// ===== process-payment/refusals.ts =====
// D4/D5 (2026-10-16): každé odmítnutí má stabilní strojový `code` (appka/web ho
// překládají) a český `error` BEZ kontaktů, který přesně říká, co se stalo, zda
// se něco strhlo a co udělat (appka ≤ 4.1.3 neznámý kód zobrazí doslova).
// CORS 1:1 se stripe-customer.ts (bez importu Stripe klienta — modul jde testovat samostatně).
export { declineMessageCs } from './declines.ts'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

export function respond(status: number, payload: Record<string, unknown>): Response {
  return new Response(JSON.stringify(payload), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })
}

/** Klíče s částkou (Kč) — formátují se česky; ostatní ({voucher_code}…) se vkládají doslova. */
const AMOUNT_KEYS = new Set(['due', 'server_total', 'expected', 'amount', 'charge', 'min', 'rounding'])

/** {success:false, code, error, …extra}; `error` = text z CS (s dosazením {klíčů} z extra), nebo `text`. */
export function refuse(status: number, code: string, extra: Record<string, unknown> = {}, text?: string): Response {
  const tpl = text ?? CS[code] ?? CS.server_error
  const error = tpl.replace(/\{(\w+)\}/g, (_m, k) => (AMOUNT_KEYS.has(k) ? fmtKc(extra[k]) : String(extra[k] ?? '')))
  return respond(status, { success: false, code, error, ...extra })
}

const fmtKc = (v: unknown) => {
  const n = Number(v)
  if (v == null || v === '' || !Number.isFinite(n)) return String(v ?? '')
  return (Math.round(n * 100) / 100).toLocaleString('cs-CZ', { maximumFractionDigits: 2 })
}

const NOTHING = 'Nic jsme nestrhli.'
const NEW_BOOKING = 'Vytvoř si prosím novou rezervaci.'

export const CS: Record<string, string> = {
  invalid_type: 'Neznámý typ platby – aktualizuj prosím aplikaci MotoGo24. Nic jsme nestrhli.',
  missing_booking_id: 'Chybí rezervace k zaplacení – otevři ji v Rezervacích a zaplať odtud. Nic jsme nestrhli.',
  missing_order_id: 'Chybí objednávka k zaplacení – vrať se do košíku a odešli ji znovu. Nic jsme nestrhli.',
  invalid_amount: 'Částka k zaplacení chybí – otevři platbu znovu. Nic jsme nestrhli.',
  auth_required: 'Přihlášení chybí nebo vypršelo – přihlas se prosím znovu a platbu zopakuj. Nic jsme nestrhli.',
  auth_required_edit: 'Přihlášení chybí nebo vypršelo – přihlas se prosím znovu a úpravu zopakuj. Nic jsme nestrhli.',
  forbidden: 'Tuhle rezervaci nejde zaplatit z účtu, na kterém jsi přihlášen(a). Přihlas se účtem, kterým jsi ji vytvořil(a). Nic jsme nestrhli.',
  forbidden_edit: 'Tuhle rezervaci nejde upravit z účtu, na kterém jsi přihlášen(a). Přihlas se účtem, kterým jsi ji vytvořil(a). Nic jsme nestrhli.',
  forbidden_shop: 'Tuhle objednávku nejde zaplatit z účtu, na kterém jsi přihlášen(a). Přihlas se účtem, kterým jsi ji vytvořil(a). Nic jsme nestrhli.',
  booking_not_found: 'Rezervaci jsme nenašli – načti prosím Rezervace znovu. Nic jsme nestrhli.',
  order_not_found: 'Objednávku jsme nenašli – vrať se prosím do košíku a odešli ji znovu. Nic jsme nestrhli.',
  wrong_status_shop: 'Tuhle objednávku už zaplatit nejde (je zrušená nebo vyřízená). Vytvoř si prosím novou objednávku. Nic jsme nestrhli.',
  not_sos_replacement: 'Tahle rezervace není náhradou ze SOS, proto ji takhle zaplatit nejde. Otevři ji prosím v Rezervacích. Nic jsme nestrhli.',
  validation_unavailable: 'Rezervaci se teď nepodařilo ověřit. Nic jsme nestrhli – zkus to prosím za chvíli znovu.',
  already_paid: 'Rezervace je už zaplacená – nic dalšího platit nemusíš. Najdeš ji v Rezervacích.',
  already_paid_shop: 'Objednávka je už zaplacená – nic dalšího platit nemusíš.',
  no_payment_needed: 'Objednávka nevyžaduje platbu – je potvrzená.',
  booking_cancelled: 'Rezervace byla zrušená (nebyla zaplacená do 30 minut, nebo ji někdo zrušil), takže ji teď zaplatit nejde. ' + NOTHING +
    ' Obnov ji v Rezervacích tlačítkem „Obnovit rezervaci" a zaplať znovu. Když obnovení nejde (motorka je mezitím obsazená, poukaz byl použitý jinde nebo už jsi ji obnovil(a) třikrát), ' + NEW_BOOKING.charAt(0).toLowerCase() + NEW_BOOKING.slice(1),
  // konkrétní důvod, proč nešlo obnovení (pojistka obnovení v DB, SQL 20261016p2)
  booking_cancelled_staff: 'Rezervaci zrušila naše obsluha, proto ji obnovit ani zaplatit nejde. ' + NOTHING + ' ' + NEW_BOOKING,
  booking_cancelled_date: 'Rezervace je zrušená a její začátek už nastal, proto ji obnovit ani zaplatit nejde. ' + NOTHING + ' Vytvoř si prosím novou rezervaci s jiným termínem.',
  booking_cancelled_limit: 'Rezervaci jsi obnovil(a) už třikrát – další obnovení nejde, aby motorka nezůstávala blokovaná. ' + NOTHING + ' ' + NEW_BOOKING,
  booking_cancelled_voucher: 'Rezervace je zrušená a poukaz {voucher_code} z ní mezitím vypršel nebo byl použitý jinde, proto ji obnovit nejde. ' + NOTHING + ' Vytvoř si prosím novou rezervaci – bez poukazu, nebo s jiným.',
  booking_cancelled_promo: 'Rezervace je zrušená a slevový kód {voucher_code} už neplatí (vypršel nebo je vyčerpaný), proto ji obnovit nejde. ' + NOTHING + ' ' + NEW_BOOKING,
  booking_cancelled_price: 'Rezervace je zrušená a ceník se od jejího vytvoření změnil, proto ji za původní cenu obnovit nejde. ' + NOTHING + ' Vytvoř si prosím novou rezervaci – cenu spočítáme podle aktuálního ceníku.',
  booking_cancelled_other: 'Rezervace je zrušená a v tomhle stavu ji obnovit ani zaplatit nejde. ' + NOTHING + ' ' + NEW_BOOKING,
  voucher_unavailable: 'Poukaz {voucher_code} mezitím vypršel nebo byl použitý jinde, takže rezervaci s ním zaplatit nejde. Nic jsme nestrhli. Vytvoř si prosím rezervaci znovu – bez poukazu, nebo s jiným.',
  below_minimum: 'Zbývá zaplatit {due} Kč, ale kartou jde zaplatit nejméně 15 Kč. Tahle verze aplikace drobnou částku neumí dorovnat – aktualizuj prosím aplikaci MotoGo24 a zkus to znovu. Nic jsme nestrhli.',
  below_minimum_app: 'Kartou jde zaplatit nejméně 15 Kč – zbývá {due} Kč. Zaplať 15 Kč, rozdíl uvidíš na dokladu jako dorovnání. Nic jsme nestrhli.',
  below_minimum_web: 'Kartou jde zaplatit nejméně 15 Kč – zbývá {due} Kč. Uprav prosím rezervaci nebo objednávku, nebo ji dokonči v aplikaci MotoGo24, která drobnou částku dorovná. Nic jsme nestrhli.',
  below_minimum_generic: 'Kartou jde zaplatit nejméně 15 Kč. Nic jsme nestrhli – aktualizuj prosím aplikaci MotoGo24 a zkus to znovu.',
  below_minimum_operator: 'Minimální částka platby kartou je 15 Kč – zadej prosím alespoň 15 Kč.',
  // odpuštění do 1 Kč jen u ceny, kterou server ověří (jinak se platí kartou 15 Kč)
  waiver_unverified: 'Zbývá {due} Kč. Tuhle částku teď nejde odpustit, protože ji server nedokázal ověřit – kartou jde zaplatit nejméně 15 Kč. Zaplať 15 Kč, rozdíl uvidíš na dokladu jako dorovnání. Nic jsme nestrhli.',
  rounding_unavailable: 'Tuhle platbu teď nejde dokončit – na serveru právě probíhá aktualizace. Nic jsme nestrhli – zkus to prosím později.',
  rounding_unavailable_waiver: 'Částku do 1 Kč teď nejde odpustit – na serveru právě probíhá aktualizace. Nic se nezměnilo a nic jsme nestrhli – zkus to prosím později.',
  change_too_large: 'Tahle úprava je na jednu platbu moc rozsáhlá. Nic jsme nestrhli – rozděl ji prosím na dvě menší (např. nejdřív termín, potom místo).',
  amount_mismatch: 'Cena rezervace je teď {server_total} Kč. Otevři prosím platbu znovu z Rezervací – nic jsme nestrhli.',
  amount_mismatch_edit: 'Cena úpravy se mezitím změnila na {expected} Kč. Načti prosím rezervaci znovu a úpravu zopakuj – nic jsme nestrhli.',
  amount_mismatch_shop: 'Cena objednávky se přepočítala na {server_total} Kč. Vrať se prosím do košíku a objednávku odešli znovu – nic jsme nestrhli.',
  free_mismatch: 'Sleva nepokrývá celou cenu (zbývá {server_total} Kč). Vrať se prosím k rezervaci a zaplať zbytek – nic jsme nestrhli.',
  free_unverified: 'Slevu se nepodařilo ověřit na celou cenu, takže rezervaci zdarma potvrdit nejde. Nic jsme nestrhli – vrať se k rezervaci a zkontroluj slevový kód.',
  // cena rezervace neodpovídá ceníku a platným slevám (např. kód / poukaz mezitím přestal platit) —
  // jinou částku nenabízíme: zaplaceno by se lišilo od ceny na dokladech
  price_outdated: 'Cena rezervace už neodpovídá aktuálnímu ceníku nebo slevám (slevový kód nebo poukaz mezitím mohl přestat platit). Nic jsme nestrhli. Vytvoř si prosím rezervaci znovu – cenu spočítáme podle aktuálního stavu.',
  previous_change_applied: 'Předchozí zaplacená úprava se právě dopsala do rezervace. Načti ji prosím znovu a novou úpravu zopakuj – nic jsme nestrhli.',
  free_confirm_failed: 'Rezervaci se nepodařilo potvrdit kvůli chybě na serveru. Nic jsme nestrhli – zkus to prosím za minutu znovu.',
  payment_in_progress: 'Platba za tohle už proběhla nebo se právě ověřuje. Neplať prosím znovu – výsledek uvidíš za pár minut v Rezervacích.',
  payment_uncertain: 'Platební brána neodpověděla včas, takže zatím nevíme, jestli platba prošla. Neplať prosím znovu – ověřujeme to a výsledek uvidíš za pár minut v Rezervacích.',
  duplicate_request: 'Stejná platba se právě zpracovává. Nic dalšího neplať – za pár vteřin uvidíš výsledek v Rezervacích.',
  stripe_unavailable: 'Platební brána teď neodpovídá. Nic jsme nestrhli – zkus to prosím za minutu znovu.',
  server_error: 'Platbu teď nejde dokončit kvůli chybě na našem serveru. Nic jsme nestrhli – zkus to prosím za minutu znovu.',
  change_not_applicable: 'Rezervace je mezitím v jiném stavu, než appka ukazuje. Nic jsme nestrhli – načti rezervaci znovu a úpravu zopakuj.',
  // kódy dry-runu výměny motorky (split_booking_moto_swap)
  not_found: 'Rezervaci jsme nenašli – načti prosím Rezervace znovu. Nic jsme nestrhli.',
  not_paid: 'Motorku jde vyměnit jen u zaplacené rezervace. Nic jsme nestrhli – nejdřív rezervaci zaplať.',
  invalid_new_moto: 'Vybranou motorku teď nejde do výměny použít (nebo ji v rezervaci už máš). Nic jsme nestrhli – vyber jinou motorku.',
  swap_date_out_of_range: 'Den výměny musí být v termínu rezervace a nejdřív dnes. Nic jsme nestrhli – vyber jiný den výměny.',
  already_split: 'U této rezervace už výměna motorky proběhla. Nic jsme nestrhli – načti rezervaci znovu.',
  license_insufficient: 'Na vybranou motorku nemáš potřebné řidičské oprávnění. Nic jsme nestrhli – vyber motorku pro svou skupinu ŘP.',
  new_moto_unavailable: 'Vybraná motorka je ve zbytku termínu už obsazená. Nic jsme nestrhli – vyber jinou motorku nebo jiný den výměny.',
  // complete_extension
  not_extension: 'Tahle platba nepatří k úpravě rezervace.',
  payment_not_paid: 'Platba úpravy neproběhla – nic jsme nestrhli. Otevři rezervaci a zkus to znovu.',
  payment_processing: 'Banka platbu ještě zpracovává. Úpravu dokončíme hned, jak ji potvrdí – nemusíš nic dělat.',
  payment_unconfirmed: 'Platba ještě čeká na ověření u banky (3D Secure). Jakmile ho dokončíš, úpravu zapíšeme sami – nic dalšího neplať.',
  apply_failed: 'Doplatek je zaplacený a úpravu teď zapisujeme. Dokončí se sama během pár minut – neplať prosím znovu.',
  change_failed: 'Zaplacenou úpravu nešlo zapsat, protože se rezervace mezitím změnila. Doplatek ti automaticky vracíme na kartu.',
  change_failed_staff: 'Zaplacenou úpravu nešlo zapsat automaticky. Obsluha ji zkontroluje a doplatek případně vrátí do 2 pracovních dnů – nemusíš nic dělat.',
  // odpověď majitele 2026-10-16: nová rezervace má přednost před zaplacenou výměnou
  change_failed_taken: 'Motorka je mezitím obsazená – během tvé platby si ji zarezervoval někdo jiný a nová rezervace má přednost, takže výměnu nešlo zapsat. Tvoje původní rezervace platí beze změny a doplatek ti automaticky vracíme na kartu. Můžeš si vybrat jinou motorku, nebo si nechat tu současnou.',
  change_failed_taken_staff: 'Motorka je mezitím obsazená – během tvé platby si ji zarezervoval někdo jiný a nová rezervace má přednost, takže výměnu nešlo zapsat. Tvoje původní rezervace platí beze změny. Doplatek ti vrátí obsluha do 2 pracovních dnů – nemusíš nic dělat.',
  stale_payment: 'Tuhle starší platbu už nejde automaticky zapsat do rezervace. Obsluha ji zkontroluje a doplatek případně vrátí do 2 pracovních dnů – nemusíš nic dělat ani platit znovu.',
  stale_payment_refunded: 'Z téhle platby už jsme peníze vrátili, proto ji do rezervace nezapisujeme. Nemusíš nic dělat.',
  payment_not_found: 'Platbu jsme nenašli – otevři prosím rezervaci znovu.',
}

/** Kódy z dry-runu, které mají vlastní text (zbytek → change_not_applicable). */
export const SWAP_DRY_CODES = ['not_found', 'not_paid', 'invalid_new_moto', 'swap_date_out_of_range', 'already_split',
  'license_insufficient', 'new_moto_unavailable']

/** Důvod odmítnutého obnovení (debug_log customer_restore_refused) → klíč textu. */
export function cancelledReasonKey(reason: string | null | undefined): string {
  switch (reason) {
    case 'cancelled_by_staff': return 'booking_cancelled_staff'
    case 'date_passed': return 'booking_cancelled_date'
    case 'restore_limit': return 'booking_cancelled_limit'
    case 'voucher_unavailable': return 'booking_cancelled_voucher'
    case 'promo_unavailable': return 'booking_cancelled_promo'
    case 'price_changed': return 'booking_cancelled_price'
    case 'not_restorable': case 'forbidden': return 'booking_cancelled_other'
    default: return 'booking_cancelled'
  }
}
