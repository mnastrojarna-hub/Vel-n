// Dvojjazyčný předávací protokol (audit EDGE-DOC-10): zákazník podepisuje na displeji kiosku /
// v appce ve svém jazyce, dokument byl dřív jen česky. Nově: cs → beze změny (jen česky);
// jiný jazyk → popisky „jazyk zákazníka / česky“ (čeština šedě, lang="cs") + věta, že závazné
// je české znění. Klíče HO_CS = přesné české texty dokumentu (html.ts).

import { parseDocLang } from '../_shared/doc-i18n.ts'
import { HO_A } from './i18n-a.ts'
import { HO_B } from './i18n-b.ts'

export const HO_CS: Record<string, string> = {
  title: 'Předávací protokol', heading: 'PŘEDÁVACÍ PROTOKOL', forBooking: 'k rezervaci č. {bn} ze dne {today}',
  binding: 'Dvojjazyčný protokol — závazné je české znění.',
  parties: 'Smluvní strany a vozidlo', lessor: 'Pronajímatel', renter: 'Nájemce', moto: 'Motocykl', vin: 'VIN', period: 'Období pronájmu',
  state: 'Stav při předání', agreedPickup: 'Sjednaný čas vyzvednutí', actualPickup: 'Skutečný čas převzetí',
  mileageKm: 'Stav km při předání', mileageMh: 'Stav motohodin při předání', mileageNote: 'Vyplněno automaticky ze stavu při posledním vrácení.',
  checks: 'Kontrola předání', chk_clean: 'Motocykl předán čistý a v provozuschopném stavu', chk_docs: 'Doklady k vozidlu (OTP, zelená karta) předány',
  chk_keys: 'Klíče a zabezpečení předány', chk_instructed: 'Nájemce poučen o obsluze a provozu', chk_gear: 'Ochranná výbava předána a vyzkoušena',
  gearTitle: 'Zapůjčená výbava', thItem: 'Položka', thSize: 'Velikost', thHanded: 'Předáno', extraMark: '(navíc)', noGear: 'Žádná zapůjčená výbava.',
  removedNote: '☐ = nepřevzato — položka byla z rezervace odebrána.',
  extraNote: '(navíc) = položka nebyla v rezervaci, nájemce si ji při převzetí vzal navíc.',
  motoEq: 'Výbava motorky', motoEqNote: 'Uložena v motorce — v kufru nebo v tankvaku. Nájemce ji přebírá spolu s motorkou a vrací ji s ní.',
  me_luggage: 'Kufr nebo tankvak (cestovní motorka kufr; sportovní, naked a supermoto tankvak)', me_phone_holder: 'Držák na telefon',
  me_phone_holder_key: 'Klíč k držáku mobilu', me_disc_lock: 'Kotoučový zámek', me_accident_form: 'Záznam o nehodě (formulář)', me_first_aid_kit: 'Lékárnička',
  me_reflective_vest: 'Reflexní vesta', me_green_card: 'Zelená karta', me_registration_certificate: 'Technický průkaz',
  extras: 'Doplňkové vybavení', ex_phone_holder: 'Držák na telefon', ex_usb_adapter: 'USB 12V přechodka', ex_disc_lock: 'Kotoučový zámek',
  ex_rain_suit: 'Set nepromokavé bundy a kalhot', ex_rain_boots: 'Nepromoky na nohy', ex_rain_gloves: 'Nepromoky na ruce', ex_tie_net: 'Upínací síťka',
  ex_tankbag_small: 'Tankvak malý', ex_tankbag_large: 'Tankvak velký', ex_reflective: 'Reflexní prvky', ex_back_protector: 'Páteřák', ex_chain_spray: 'Sprej na řetěz',
  damage: 'Poškození', damageAt: 'Poškození při předání', notes: 'Poznámky', signature: 'Podpis nájemce', signedAt: 'Podepsáno {where} {at}',
  whereKiosk: 'na displeji pobočky (zařízení {device})', whereApp: 'v aplikaci MotoGo24',
  footer: 'Tento protokol byl vyplněn a elektronicky podepsán nájemcem na samoobslužné pobočce {where} dne {at}. Případné nesrovnalosti nahlaste neprodleně přes aplikaci nebo e-mailem na info@motogo24.cz.',
  g_helmet: 'Helma', g_jacket: 'Bunda', g_pants: 'Kalhoty', g_boots: 'Boty', g_gloves: 'Rukavice', who_rider: 'řidič', who_passenger: 'spolujezdec',
}

const FOREIGN: Record<string, Record<string, string>> = { ...HO_A, ...HO_B }
export const PROTOCOL_LANGS = ['cs', ...Object.keys(FOREIGN)]

export function esc(s: unknown): string {
  return String(s == null ? '' : s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c] as string))
}

/** Šablona → HTML: text escapovaný, {proměnné} vloženy jako hotové HTML. */
export function fill(tpl: string, vars: Record<string, string> = {}): string {
  return esc(tpl).replace(/\{(\w+)\}/g, (m, k) => (k in vars ? vars[k] : m))
}

export interface Tr {
  lang: string
  bilingual: boolean
  /** Česky → jen čeština; jinak „cizí / česky“ (čeština šedě). `fn` dostane slovník jazyka. */
  both(fn: (d: Record<string, string>) => string, block?: boolean): string
  /** Krátký popisek / věta podle klíče. */
  t(key: string, block?: boolean): string
  /** Má slovník klíč? (položky, které nejsou v překladech, se vypíšou tak, jak přišly). */
  has(key: string): boolean
  /** Popisek výbavy z klíče a role (řidič/spolujezdec), dvojjazyčně. */
  gear(key: string, who: string): string
  /** Holý text klíče v jazyce zákazníka (nebo 'cs'), bez HTML. */
  plain(key: string, lang?: string): string
}

export function makeTr(langRaw: string): Tr {
  const fx = FOREIGN[langRaw]
  const lang = fx ? langRaw : 'cs'
  const pick = (d: Record<string, string>, k: string) => d[k] ?? HO_CS[k] ?? k
  const both = (fn: (d: Record<string, string>) => string, block = false) => {
    if (!fx) return fn(HO_CS)
    const cz = fn(HO_CS)
    return block
      ? `${fn(fx)}<br><span lang="cs" style="color:#666">${cz}</span>`
      : `${fn(fx)}<span lang="cs" style="color:#666"> / ${cz}</span>`
  }
  return {
    lang, bilingual: !!fx, both,
    t: (key, block = false) => both((d) => esc(pick(d, key)), block),
    has: (key) => key in HO_CS,
    gear: (key, who) => both((d) => esc(`${pick(d, 'g_' + key)} (${pick(d, 'who_' + who)})`)),
    plain: (key, l) => pick(l === 'cs' || !fx ? HO_CS : fx, key),
  }
}

/** Jazyk protokolu: jazyk obrazovky, na které zákazník podepsal (kiosk / appka posílají `lang` nebo
 *  `form.lang`), jinak jazyk zákazníka z DB (detect_customer_language), jinak cs. */
// deno-lint-ignore no-explicit-any
export async function resolveProtocolLang(admin: any, explicit: unknown, userId: unknown, bookingId: string): Promise<string> {
  const l = parseDocLang(explicit)
  if (l) return l
  try {
    const { data } = await admin.rpc('detect_customer_language', { p_user_id: userId || null, p_booking_id: bookingId, p_order_id: null })
    return parseDocLang(data) || 'cs'
  } catch (_) { return 'cs' }
}
