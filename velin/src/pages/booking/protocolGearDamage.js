// Protokol o poškození výpůjčky JEN výbavy (booking_kind 'gear', Velín) — varianta motorkového damage_protocol
// bez motocyklu a tachometru: kontroly poškození výbavy, stav při vrácení, popis, chybějící kusy, zapůjčené
// kusy s velikostmi, podpis nájemce i pronajímatele. Texty v 8 jazycích dvojjazyčně „jazyk zákazníka / česky“.
import { esc, escMulti, TD, infoRow, sigBlock } from './bookingDocElectronic'
import { makeGearTr } from './protocolGearOnly'

export const GEAR_DAMAGE_CHECKS = [
  { key: 'gd_helmet', label: 'Helma — prasklina, odřená skořepina, poškozené hledí' },
  { key: 'gd_clothes', label: 'Bunda / kalhoty — trhlina, propálení, poškozený zip' },
  { key: 'gd_gloves', label: 'Rukavice — trhlina, poškozený chránič' },
  { key: 'gd_boots', label: 'Boty — poškozená podrážka nebo zapínání' },
  { key: 'gd_dirty', label: 'Výbava silně znečištěná (nutné čištění)' },
  { key: 'gd_missing', label: 'Chybějící kus výbavy' },
]
const CS = {
  dHeading: 'PROTOKOL O POŠKOZENÍ — ZAPŮJČENÁ VÝBAVA', dState: 'Stav výbavy při vrácení', dFound: 'Zjištěná poškození výbavy',
  ...Object.fromEntries(GEAR_DAMAGE_CHECKS.map(c => [c.key, c.label])),
}
const K = ['dHeading', 'dState', 'dFound', ...GEAR_DAMAGE_CHECKS.map(c => c.key)]
const row = arr => Object.fromEntries(K.map((k, i) => [k, arr[i]]))
const FX = {
  en: row(['DAMAGE PROTOCOL — RENTED GEAR', 'Condition of the gear at return', 'Damage found on the gear', 'Helmet — crack, scratched shell, damaged visor', 'Jacket / trousers — tear, burn, damaged zip', 'Gloves — tear, damaged protector', 'Boots — damaged sole or fastening', 'Gear heavily soiled (cleaning needed)', 'Missing gear item']),
  de: row(['SCHADENSPROTOKOLL — GELIEHENE AUSRÜSTUNG', 'Zustand der Ausrüstung bei Rückgabe', 'Festgestellte Schäden an der Ausrüstung', 'Helm — Riss, verkratzte Schale, beschädigtes Visier', 'Jacke / Hose — Riss, Brandloch, defekter Reißverschluss', 'Handschuhe — Riss, beschädigter Protektor', 'Stiefel — beschädigte Sohle oder Verschluss', 'Ausrüstung stark verschmutzt (Reinigung nötig)', 'Fehlendes Ausrüstungsteil']),
  es: row(['PROTOCOLO DE DAÑOS — EQUIPAMIENTO ALQUILADO', 'Estado del equipamiento en la devolución', 'Daños detectados en el equipamiento', 'Casco — grieta, carcasa rayada, visera dañada', 'Chaqueta / pantalón — rotura, quemadura, cremallera dañada', 'Guantes — rotura, protección dañada', 'Botas — suela o cierre dañados', 'Equipamiento muy sucio (requiere limpieza)', 'Falta una pieza del equipamiento']),
  fr: row(['PROCÈS-VERBAL DE DOMMAGES — ÉQUIPEMENT LOUÉ', "État de l'équipement au retour", "Dommages constatés sur l'équipement", 'Casque — fissure, coque rayée, visière endommagée', 'Blouson / pantalon — déchirure, brûlure, fermeture éclair endommagée', 'Gants — déchirure, protection endommagée', 'Bottes — semelle ou fermeture endommagée', 'Équipement très sale (nettoyage nécessaire)', "Pièce d'équipement manquante"]),
  nl: row(['SCHADEPROTOCOL — GEHUURDE UITRUSTING', 'Staat van de uitrusting bij terugbrengen', 'Vastgestelde schade aan de uitrusting', 'Helm — barst, bekraste schaal, beschadigd vizier', 'Jas / broek — scheur, brandgat, kapotte rits', 'Handschoenen — scheur, beschadigde protector', 'Laarzen — beschadigde zool of sluiting', 'Uitrusting sterk vervuild (reiniging nodig)', 'Ontbrekend onderdeel van de uitrusting']),
  pl: row(['PROTOKÓŁ USZKODZEŃ — WYPOŻYCZONY SPRZĘT', 'Stan sprzętu przy zwrocie', 'Stwierdzone uszkodzenia sprzętu', 'Kask — pęknięcie, porysowana skorupa, uszkodzona szyba', 'Kurtka / spodnie — rozdarcie, przepalenie, uszkodzony zamek', 'Rękawice — rozdarcie, uszkodzony ochraniacz', 'Buty — uszkodzona podeszwa lub zapięcie', 'Sprzęt mocno zabrudzony (wymaga czyszczenia)', 'Brakujący element sprzętu']),
  uk: row(['ПРОТОКОЛ ПОШКОДЖЕНЬ — ОРЕНДОВАНЕ СПОРЯДЖЕННЯ', 'Стан спорядження під час повернення', 'Виявлені пошкодження спорядження', 'Шолом — тріщина, подряпана оболонка, пошкоджений візор', 'Куртка / штани — розрив, пропалення, пошкоджена блискавка', 'Рукавички — розрив, пошкоджений захист', 'Черевики — пошкоджена підошва або застібка', 'Спорядження сильно забруднене (потрібне чищення)', 'Відсутній предмет спорядження']),
}

/** HTML protokolu o poškození výbavy (form = stav modalu: checks {key:{checked,note}}, visualState, damageDesc, missingGear, accessories). */
export function buildGearDamageHtml({ vars, form, signatures, lang = 'cs', branch = null }) {
  const v = vars || {}
  const f = form || {}
  const T = makeGearTr(lang)
  const tr = T.base
  const fx = tr.bilingual ? FX[tr.lang] : null
  const d = (key, block = false) => (!fx ? esc(CS[key]) : block
    ? `${esc(fx[key] ?? CS[key])}<br><span lang="cs" style="color:#666">${esc(CS[key])}</span>`
    : `${esc(fx[key] ?? CS[key])}<span lang="cs" style="color:#666"> / ${esc(CS[key])}</span>`)
  const h3 = (html, top = 14) => `<h3 style="font-size:13px;margin-top:${top}px">${html}</h3>`
  const table = rows => `<table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd">${rows}</table>`
  const signedAt = new Date().toLocaleString('cs-CZ')
  const title = fx ? `${fx.dHeading} / ${CS.dHeading}` : CS.dHeading

  const head = `<!DOCTYPE html><html lang="${tr.lang}"><head><meta charset="utf-8"><title>${esc(title)}</title></head><body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a"><div style="max-width:780px;margin:0 auto;padding:32px"><h1 style="text-align:center;font-size:19px;border-bottom:2px solid #dc2626;padding-bottom:12px">${d('dHeading', true)}</h1><p style="text-align:center;font-size:12px;color:#666">${tr.fill('forBooking', { bn: esc(v.booking_number), today: esc(v.today) })}</p>` +
    (tr.bilingual ? `<p style="text-align:center;font-size:11px;color:#666;margin-top:-4px">${tr.t('binding')}</p>` : '')
  const branchVal = [branch?.name, [branch?.address, [branch?.zip, branch?.city].filter(Boolean).join(' ')].filter(Boolean).join(', ')].filter(Boolean).join(' — ')
  const identityRow = f.identityCodeRequired ? infoRow(T.g('gIdentity'), tr.plain(f.identityVerified ? 'verified' : 'notVerified')) : ''
  const parties = h3(T.g('gParties'), 16) + table(
    infoRow(tr.t('lessor'), v.company_name) + infoRow(tr.t('renter'), v.customer_name) +
    infoRow(T.g('gSubject'), T.gplain('gSubjectVal')) + infoRow(T.g('gBranch'), branchVal) +
    infoRow(tr.t('period'), v.rental_period) + identityRow)
  const state = h3(d('dState')) + table(infoRow(tr.t('visual'), f.visualState) + infoRow(tr.t('returnedAt'), `${v.today || ''} ${v.today_time || ''}`.trim()))
  const found = GEAR_DAMAGE_CHECKS.map(c => {
    const x = f.checks?.[c.key] || {}
    return `<div style="font-size:12px;margin:5px 0">${x.checked ? '☑' : '☐'} ${d(c.key)}${x.note ? ` — <span style="color:#444">${esc(x.note)}</span>` : ''}</div>`
  }).join('')
  const acc = (f.accessories || []).filter(a => a.size)
  const th = `${TD};background:#f0f7ff;font-size:10px;text-transform:uppercase`
  const accTable = acc.length
    ? `<table style="width:100%;border-collapse:collapse;font-size:11px;margin:6px 0;border:1px solid #ddd"><tr><th style="${th};text-align:left">${tr.t('thItem')}</th><th style="${th};text-align:left">${tr.t('thSize')}</th></tr>${acc.map(a => `<tr><td style="${TD};background:#f8faf9;font-weight:600">${a.type ? T.item(a.type, a.label) : esc(a.label)}</td><td style="${TD}">${esc(a.size)}</td></tr>`).join('')}</table>`
    : `<p style="font-size:12px">${tr.t('noAcc')}</p>`

  return head + parties + state +
    `${h3(d('dFound'))}${found}` +
    (f.damageDesc ? `${h3(tr.t('dmgDesc'))}<p style="font-size:12px">${escMulti(f.damageDesc)}</p>` : '') +
    (f.missingGear ? `${h3(tr.t('missingGear'))}<p style="font-size:12px">${escMulti(f.missingGear)}</p>` : '') +
    `${h3(T.g('gAccTitle'))}${accTable}` +
    sigBlock(tr, signatures || {}, v.customer_name) +
    `<p style="font-size:11px;color:#666;margin-top:18px">${tr.fill('footer', { at: esc(signedAt) }, true)}</p></div></body></html>`
}
