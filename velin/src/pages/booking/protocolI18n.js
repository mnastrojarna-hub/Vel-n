// Dvojjazyčný elektronický protokol z Velína (audit W3) — zrcadlo edge submit-handover-protocol/i18n.ts:
// jazyk rezervace cs → beze změny (jen česky); jiný jazyk → popisky „jazyk zákazníka / česky“ (čeština šedě,
// lang="cs") + věta, že závazné je české znění. Data (jméno, motorka, poznámky operátora…) se nepřekládají.
import { PROTO_A } from './protocolI18nA'
import { PROTO_B } from './protocolI18nB'

// Česká znění = přesné texty dokumentu (bookingDocElectronic.js); položky kontrol/doplňků/poškození nese builder
// z polí HANDOVER_CHECKS / EXTRA_GEAR_CHECKS / DAMAGE_CHECKS (stejné texty jako checkboxy v modalu).
export const PROTO_CS = {
  heading: 'PŘEDÁVACÍ PROTOKOL', dmgHeading: 'PROTOKOL O ZJIŠTĚNÉM POŠKOZENÍ PŘI VRÁCENÍ',
  forBooking: 'k rezervaci č. {bn} ze dne {today}', binding: 'Dvojjazyčný protokol — závazné je české znění.',
  parties: 'Smluvní strany a vozidlo', lessor: 'Pronajímatel', renter: 'Nájemce', moto: 'Motocykl', vin: 'VIN', period: 'Období pronájmu',
  identity: 'Ověření identity (kód k motorce)', verified: 'Ověřeno ✓', notVerified: 'Neověřeno',
  state: 'Stav při předání', mileageKm: 'Stav km při předání', checks: 'Kontrola předání',
  accTitle: 'Příslušenství a výbava', thItem: 'Položka', thSize: 'Velikost', thHanded: 'Předáno',
  removedNote: '☐ = nepřevzato — položka byla z rezervace odebrána.', noAcc: 'Žádné zapůjčené příslušenství.',
  extras: 'Doplňkové vybavení', damage: 'Poškození', damageAt: 'Poškození při předání', notes: 'Poznámky',
  sigRenter: 'Podpis nájemce', sigLessor: 'Podpis pronajímatele',
  footer: 'Tento protokol byl vyplněn a elektronicky podepsán perem na zařízení provozovatele dne {at}. Podpisy jsou nedílnou součástí tohoto dokumentu.',
  dmgState: 'Stav motocyklu při vrácení', odometer: 'Stav tachometru', visual: 'Celkový vizuální stav', returnedAt: 'Datum a čas vrácení',
  dmgFound: 'Zjištěná poškození', dmgDesc: 'Podrobný popis poškození', missingGear: 'Chybějící / poškozené vybavení',
  accByBooking: 'Zapůjčené příslušenství dle rezervace',
  // přípony popisku výbavy (bookingDocTemplates.listAccessoryItems, ProtocolGearEditor, ElectronicProtocolModal)
  child: '(dětská velikost)', added: 'přidáno při předání',
}

const FOREIGN = { ...PROTO_A, ...PROTO_B }
export const PROTOCOL_LANGS = ['cs', ...Object.keys(FOREIGN)]

/** Jazyk dokumentu z `bookings.language` (= detect_customer_language: rezervace má přednost); neznámý → cs. */
export function protocolLang(raw) {
  const s = String(raw ?? '').trim().toLowerCase().slice(0, 2)
  return FOREIGN[s] ? s : 'cs'
}

export function esc(s) {
  return String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]))
}
/** Šablona → HTML: text escapovaný, {proměnné} vloženy jako hotové HTML. */
function fillTpl(tpl, vars) {
  return esc(tpl).replace(/\{(\w+)\}/g, (m, k) => (k in vars ? vars[k] : m))
}

export function makeProtocolTr(langRaw) {
  const fx = FOREIGN[langRaw] || null
  const both = (fxHtml, czHtml, block) => {
    if (!fx) return czHtml
    return block ? `${fxHtml}<br><span lang="cs" style="color:#666">${czHtml}</span>` : `${fxHtml}<span lang="cs" style="color:#666"> / ${czHtml}</span>`
  }
  return {
    lang: fx ? langRaw : 'cs',
    bilingual: !!fx,
    /** Popisek dle klíče; `cz` = české znění (výchozí PROTO_CS[key]); `block` = čeština na novém řádku. */
    t: (key, cz = PROTO_CS[key], block = false) => both(esc(fx?.[key] ?? cz), esc(cz), block),
    /** Věta se {proměnnými} (hodnoty už jako HTML). */
    fill: (key, vars, block = false) => both(fillTpl(fx?.[key] ?? PROTO_CS[key], vars), fillTpl(PROTO_CS[key], vars), block),
    /** Holý text (bez HTML) — <title>. */
    plain: (key) => (fx ? `${fx[key] ?? PROTO_CS[key]} / ${PROTO_CS[key]}` : PROTO_CS[key]),
    /** Položka výbavy {label, type, field, added}: typ + role (+ dětská velikost, přidáno) ze slovníku; vlastní popis
     *  operátora (bez typu) zůstává, jak byl zadán. Česky vždy původní `label`. */
    acc: (a) => {
      const label = String(a?.label ?? '')
      if (!fx) return esc(label)
      const addedCz = ' — ' + PROTO_CS.added
      const base = a.added && label.endsWith(addedCz) ? label.slice(0, -addedCz.length) : label
      let f
      if (a.type && fx['g_' + a.type]) {
        const who = String(a.field || '').startsWith('passenger_') ? 'who_passenger' : 'who_rider'
        f = `${fx['g_' + a.type]} (${fx[who]})${base.includes(PROTO_CS.child) ? ' ' + fx.child : ''}`
      } else if (a.added && base !== label) {
        f = base
      } else {
        return esc(label)
      }
      return both(esc(a.added ? `${f} — ${fx.added}` : f), esc(label), false)
    },
  }
}
