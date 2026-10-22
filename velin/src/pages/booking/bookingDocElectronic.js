// Elektronická varianta předávacího protokolu a protokolu o poškození.
// Modal vyplní operátor/zákazník na tabletu (checkboxy + volný text + podpis perem),
// tento modul z toho sestaví finální podepsané HTML. Jazyk rezervace ≠ cs → dvojjazyčně
// „jazyk zákazníka / česky“ se závazným českým zněním (protocolI18n.js, zrcadlo edge
// submit-handover-protocol); cs → beze změny.
import { makeProtocolTr, protocolLang } from './protocolI18n'

export const HANDOVER_CHECKS = [
  { key: 'clean', label: 'Motocykl předán čistý a v provozuschopném stavu' },
  { key: 'docs', label: 'Doklady k vozidlu (OTP, zelená karta) předány' },
  { key: 'keys', label: 'Klíče a zabezpečení předány' },
  { key: 'instructed', label: 'Nájemce poučen o obsluze a provozu' },
  { key: 'gear', label: 'Ochranná výbava předána a vyzkoušena' },
]

// Doplňkové vybavení / příslušenství — operátor zaškrtne, co reálně předal.
export const EXTRA_GEAR_CHECKS = [
  { key: 'phone_holder', label: 'Držák na telefon' },
  { key: 'usb_adapter', label: 'USB 12V přechodka' },
  { key: 'disc_lock', label: 'Kotoučový zámek' },
  { key: 'rain_suit', label: 'Set nepromokavé bundy a kalhot' },
  { key: 'rain_boots', label: 'Nepromoky na nohy' },
  { key: 'rain_gloves', label: 'Nepromoky na ruce' },
  { key: 'tie_net', label: 'Upínací síťka' },
  { key: 'tankbag_small', label: 'Tankvak malý' },
  { key: 'tankbag_large', label: 'Tankvak velký' },
  { key: 'reflective', label: 'Reflexní prvky' },
  { key: 'back_protector', label: 'Páteřák' },
  { key: 'chain_spray', label: 'Sprej na řetěz' },
]

export const DAMAGE_CHECKS = [
  { key: 'bodywork', label: 'Kapotáž / karoserie' },
  { key: 'tank', label: 'Nádrž / boční kryty' },
  { key: 'tires', label: 'Pneumatiky / disky' },
  { key: 'brakes', label: 'Brzdy' },
  { key: 'lights', label: 'Světla / blinkry' },
  { key: 'mirrors', label: 'Zrcátka' },
  { key: 'levers', label: 'Páčky / řídítka' },
  { key: 'exhaust', label: 'Výfuk' },
  { key: 'seat', label: 'Sedlo' },
  { key: 'gear', label: 'Zapůjčená výbava (helma, oblečení)' },
]

export function esc(s) {
  return String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]))
}
export function escMulti(s) { return esc(s).replace(/\n/g, '<br>') }

// sdílené s protocolGearDoc.js (protokol výpůjčky jen výbavy)
export const TD = 'padding:6px 8px;border:1px solid #ddd'
export const TDL = `${TD};background:#f8faf9;font-weight:600;width:220px`

// labelHtml = hotové HTML popisku (tr.t → u češtiny esc(text), tj. totéž co dřív esc(label))
export function infoRow(labelHtml, value) {
  return `<tr><td style="${TDL}">${labelHtml}</td><td style="${TD}">${value ? escMulti(value) : '&nbsp;'}</td></tr>`
}

export function sigBlock(tr, signatures, customerName, includeOperator = true) {
  const box = (img, captionHtml) => `<div style="text-align:center;width:46%"><div style="height:96px;border:1px solid #ccc;border-radius:8px;display:flex;align-items:center;justify-content:center;background:#fff;overflow:hidden">${img ? `<img src="${img}" alt="podpis" style="max-width:100%;max-height:92px"/>` : ''}</div><div style="border-top:1px solid #999;margin-top:6px;padding-top:6px;font-size:11px">${captionHtml}</div></div>`
  const renter = tr.t('sigRenter') + ' — ' + esc(customerName)
  // Předávací protokol podepisuje jen nájemce (zákazník) — podpis za MotoGo se neuvádí.
  if (!includeOperator) {
    return `<div style="margin-top:40px;display:flex;justify-content:center">${box(signatures.customer, renter)}</div>`
  }
  return `<div style="margin-top:40px;display:flex;justify-content:space-between">${box(signatures.operator, tr.t('sigLessor'))}${box(signatures.customer, renter)}</div>`
}

export function buildElectronicProtocolHtml({ type, vars, form, signatures, lang = 'cs' }) {
  const isDamage = type === 'damage_protocol'
  const v = vars || {}
  const sig = signatures || {}
  const signedAt = new Date().toLocaleString('cs-CZ')
  const tr = makeProtocolTr(protocolLang(lang))
  const h3 = (key, top = 14) => `<h3 style="font-size:13px;margin-top:${top}px">${tr.t(key)}</h3>`

  const head = (key, color) => `<!DOCTYPE html><html lang="${tr.lang}"><head><meta charset="utf-8"><title>${esc(tr.plain(key))}</title></head><body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a"><div style="max-width:780px;margin:0 auto;padding:32px"><h1 style="text-align:center;font-size:19px;border-bottom:2px solid ${color};padding-bottom:12px">${tr.t(key, undefined, true)}</h1><p style="text-align:center;font-size:12px;color:#666">${tr.fill('forBooking', { bn: esc(v.booking_number), today: esc(v.today) })}</p>` +
    (tr.bilingual ? `<p style="text-align:center;font-size:11px;color:#666;margin-top:-4px">${tr.t('binding')}</p>` : '')

  const identityRow = form.identityCodeRequired
    ? infoRow(tr.t('identity'), tr.plain(form.identityVerified ? 'verified' : 'notVerified'))
    : ''
  const parties = `${h3('parties', 16)}<table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd">${infoRow(tr.t('lessor'), v.company_name)}${infoRow(tr.t('renter'), v.customer_name)}${infoRow(tr.t('moto'), `${v.moto_model} (${v.moto_spz || ''})`)}${infoRow(tr.t('vin'), v.moto_vin)}${infoRow(tr.t('period'), v.rental_period)}${identityRow}</table>`

  const foot = `<p style="font-size:11px;color:#666;margin-top:18px">${tr.fill('footer', { at: esc(signedAt) }, true)}</p></div></body></html>`

  if (!isDamage) {
    const accRows = (form.accessories || []).map(a => `<tr><td style="${TD};background:#f8faf9;font-weight:600">${tr.acc(a)}</td><td style="${TD}">${esc(a.size)}</td><td style="${TD};text-align:center;width:80px;font-size:14px">${a.checked ? '☑' : '☐'}</td></tr>`).join('')
    // Poznámka pod tabulkou jen když je něco nepřevzato (☐ = položka při podpisu z rezervace odebrána)
    const accNote = (form.accessories || []).some(a => !a.checked)
      ? `<p style="font-size:10px;color:#666;margin:2px 0 0">${tr.t('removedNote')}</p>`
      : ''
    const accTable = accRows
      ? `<table style="width:100%;border-collapse:collapse;font-size:11px;margin:6px 0;border:1px solid #ddd"><tr><th style="${TD};background:#f0f7ff;text-align:left;font-size:10px;text-transform:uppercase">${tr.t('thItem')}</th><th style="${TD};background:#f0f7ff;text-align:left;font-size:10px;text-transform:uppercase">${tr.t('thSize')}</th><th style="${TD};background:#f0f7ff;text-align:center;font-size:10px;text-transform:uppercase">${tr.t('thHanded')}</th></tr>${accRows}</table>${accNote}`
      : `<p style="font-size:12px">${tr.t('noAcc')}</p>`
    const checkList = HANDOVER_CHECKS.map(c => `<div style="font-size:12px;margin:5px 0">${form.checks?.[c.key] ? '☑' : '☐'} ${tr.t('chk_' + c.key, c.label)}</div>`).join('')
    const extraList = EXTRA_GEAR_CHECKS.map(c => `<div style="font-size:12px;margin:5px 0">${form.checks?.[c.key] ? '☑' : '☐'} ${tr.t('ex_' + c.key, c.label)}</div>`).join('')
    const dmg = form.damage || {}
    const damageBlock = `<div style="font-size:12px;margin:5px 0">${dmg.checked ? '☑' : '☐'} ${tr.t('damageAt')}</div>` +
      (dmg.checked && dmg.desc ? `<p style="font-size:12px;margin:4px 0 0;padding:8px 10px;background:#fef2f2;border:1px solid #fca5a5;border-radius:6px">${escMulti(dmg.desc)}</p>` : '')
    return head('heading', '#2563eb') +
      parties +
      `${h3('state')}<table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd">${infoRow(tr.t('mileageKm'), form.mileage ? `${form.mileage} km` : '')}</table>` +
      `${h3('checks')}${checkList}` +
      `${h3('accTitle')}${accTable}` +
      `${h3('extras')}${extraList}` +
      `${h3('damage')}${damageBlock}` +
      (form.notes ? `${h3('notes')}<p style="font-size:12px">${escMulti(form.notes)}</p>` : '') +
      sigBlock(tr, sig, v.customer_name, false) +
      foot
  }

  // damage_protocol
  const dmgRows = DAMAGE_CHECKS.map(c => {
    const d = form.checks?.[c.key] || {}
    return `<div style="font-size:12px;margin:5px 0">${d.checked ? '☑' : '☐'} ${tr.t('dmg_' + c.key, c.label)}${d.note ? ` — <span style="color:#444">${esc(d.note)}</span>` : ''}</div>`
  }).join('')
  return head('dmgHeading', '#dc2626') +
    parties +
    `${h3('dmgState')}<table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd">${infoRow(tr.t('odometer'), form.mileage ? `${form.mileage} km` : '')}${infoRow(tr.t('visual'), form.visualState)}${infoRow(tr.t('returnedAt'), `${v.today} ${v.today_time || ''}`)}</table>` +
    `${h3('dmgFound')}${dmgRows}` +
    (form.damageDesc ? `${h3('dmgDesc')}<p style="font-size:12px">${escMulti(form.damageDesc)}</p>` : '') +
    (form.missingGear ? `${h3('missingGear')}<p style="font-size:12px">${escMulti(form.missingGear)}</p>` : '') +
    `<p style="font-size:11px;color:#666;margin-top:8px">${tr.t('accByBooking')}: ${esc(v.accessories)}</p>` +
    sigBlock(tr, sig, v.customer_name) +
    foot
}
