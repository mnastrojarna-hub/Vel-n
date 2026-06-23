// Elektronická varianta předávacího protokolu a protokolu o poškození.
// Modal vyplní operátor/zákazník na tabletu (checkboxy + volný text + podpis perem),
// tento modul z toho sestaví finální podepsané HTML.

export const HANDOVER_CHECKS = [
  { key: 'clean', label: 'Motocykl předán čistý a v provozuschopném stavu' },
  { key: 'fuel_full', label: 'Nádrž plná pohonných hmot' },
  { key: 'docs', label: 'Doklady k vozidlu (OTP, zelená karta) předány' },
  { key: 'keys', label: 'Klíče a zabezpečení předány' },
  { key: 'instructed', label: 'Nájemce poučen o obsluze a provozu' },
  { key: 'gear', label: 'Ochranná výbava předána a vyzkoušena' },
]

// Doplňkové vybavení / příslušenství — operátor zaškrtne, co reálně předal.
export const EXTRA_GEAR_CHECKS = [
  { key: 'phone_holder', label: 'Držák na telefon' },
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

function esc(s) {
  return String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]))
}
function escMulti(s) { return esc(s).replace(/\n/g, '<br>') }

const TD = 'padding:6px 8px;border:1px solid #ddd'
const TDL = `${TD};background:#f8faf9;font-weight:600;width:220px`

function infoRow(label, value) {
  return `<tr><td style="${TDL}">${esc(label)}</td><td style="${TD}">${value ? escMulti(value) : '&nbsp;'}</td></tr>`
}

function sigBlock(signatures, customerName, includeOperator = true) {
  const box = (img, caption) => `<div style="text-align:center;width:46%"><div style="height:96px;border:1px solid #ccc;border-radius:8px;display:flex;align-items:center;justify-content:center;background:#fff;overflow:hidden">${img ? `<img src="${img}" alt="podpis" style="max-width:100%;max-height:92px"/>` : ''}</div><div style="border-top:1px solid #999;margin-top:6px;padding-top:6px;font-size:11px">${esc(caption)}</div></div>`
  // Předávací protokol podepisuje jen nájemce (zákazník) — podpis za MotoGo se neuvádí.
  if (!includeOperator) {
    return `<div style="margin-top:40px;display:flex;justify-content:center">${box(signatures.customer, 'Podpis nájemce — ' + customerName)}</div>`
  }
  return `<div style="margin-top:40px;display:flex;justify-content:space-between">${box(signatures.operator, 'Podpis pronajímatele')}${box(signatures.customer, 'Podpis nájemce — ' + customerName)}</div>`
}

export function buildElectronicProtocolHtml({ type, vars, form, signatures }) {
  const isDamage = type === 'damage_protocol'
  const v = vars || {}
  const sig = signatures || {}
  const signedAt = new Date().toLocaleString('cs-CZ')

  const head = (title, color) => `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>${esc(title)}</title></head><body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a"><div style="max-width:780px;margin:0 auto;padding:32px"><h1 style="text-align:center;font-size:19px;border-bottom:2px solid ${color};padding-bottom:12px">${esc(title)}</h1><p style="text-align:center;font-size:12px;color:#666">k rezervaci č. ${esc(v.booking_number)} ze dne ${esc(v.today)}</p>`

  const parties = `<h3 style="font-size:13px;margin-top:16px">Smluvní strany a vozidlo</h3><table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd">${infoRow('Pronajímatel', v.company_name)}${infoRow('Nájemce', v.customer_name)}${infoRow('Motocykl', `${v.moto_model} (${v.moto_spz || ''})`)}${infoRow('VIN', v.moto_vin)}${infoRow('Období pronájmu', v.rental_period)}</table>`

  const foot = `<p style="font-size:11px;color:#666;margin-top:18px">Tento protokol byl vyplněn a elektronicky podepsán perem na zařízení provozovatele dne ${esc(signedAt)}. Podpisy jsou nedílnou součástí tohoto dokumentu.</p></div></body></html>`

  if (!isDamage) {
    const accRows = (form.accessories || []).map(a => `<tr><td style="${TD};background:#f8faf9;font-weight:600">${esc(a.label)}</td><td style="${TD}">${esc(a.size)}</td><td style="${TD};text-align:center;width:80px;font-size:14px">${a.checked ? '☑' : '☐'}</td></tr>`).join('')
    const accTable = accRows
      ? `<table style="width:100%;border-collapse:collapse;font-size:11px;margin:6px 0;border:1px solid #ddd"><tr><th style="${TD};background:#f0f7ff;text-align:left;font-size:10px;text-transform:uppercase">Položka</th><th style="${TD};background:#f0f7ff;text-align:left;font-size:10px;text-transform:uppercase">Velikost</th><th style="${TD};background:#f0f7ff;text-align:center;font-size:10px;text-transform:uppercase">Předáno</th></tr>${accRows}</table>`
      : '<p style="font-size:12px">Žádné zapůjčené příslušenství.</p>'
    const checkList = HANDOVER_CHECKS.map(c => `<div style="font-size:12px;margin:5px 0">${form.checks?.[c.key] ? '☑' : '☐'} ${esc(c.label)}</div>`).join('')
    const extraList = EXTRA_GEAR_CHECKS.map(c => `<div style="font-size:12px;margin:5px 0">${form.checks?.[c.key] ? '☑' : '☐'} ${esc(c.label)}</div>`).join('')
    return head('PŘEDÁVACÍ PROTOKOL', '#2563eb') +
      parties +
      `<h3 style="font-size:13px;margin-top:14px">Stav při předání</h3><table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd">${infoRow('Stav km při předání', form.mileage ? `${form.mileage} km` : '')}</table>` +
      `<h3 style="font-size:13px;margin-top:14px">Kontrola předání</h3>${checkList}` +
      `<h3 style="font-size:13px;margin-top:14px">Příslušenství a výbava</h3>${accTable}` +
      `<h3 style="font-size:13px;margin-top:14px">Doplňkové vybavení</h3>${extraList}` +
      (form.notes ? `<h3 style="font-size:13px;margin-top:14px">Poznámky</h3><p style="font-size:12px">${escMulti(form.notes)}</p>` : '') +
      sigBlock(sig, v.customer_name, false) +
      foot
  }

  // damage_protocol
  const dmgRows = DAMAGE_CHECKS.map(c => {
    const d = form.checks?.[c.key] || {}
    return `<div style="font-size:12px;margin:5px 0">${d.checked ? '☑' : '☐'} ${esc(c.label)}${d.note ? ` — <span style="color:#444">${esc(d.note)}</span>` : ''}</div>`
  }).join('')
  return head('PROTOKOL O ZJIŠTĚNÉM POŠKOZENÍ PŘI VRÁCENÍ', '#dc2626') +
    parties +
    `<h3 style="font-size:13px;margin-top:14px">Stav motocyklu při vrácení</h3><table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd">${infoRow('Stav tachometru', form.mileage ? `${form.mileage} km` : '')}${infoRow('Celkový vizuální stav', form.visualState)}${infoRow('Datum a čas vrácení', `${v.today} ${v.today_time || ''}`)}</table>` +
    `<h3 style="font-size:13px;margin-top:14px">Zjištěná poškození</h3>${dmgRows}` +
    (form.damageDesc ? `<h3 style="font-size:13px;margin-top:14px">Podrobný popis poškození</h3><p style="font-size:12px">${escMulti(form.damageDesc)}</p>` : '') +
    (form.missingGear ? `<h3 style="font-size:13px;margin-top:14px">Chybějící / poškozené vybavení</h3><p style="font-size:12px">${escMulti(form.missingGear)}</p>` : '') +
    `<p style="font-size:11px;color:#666;margin-top:8px">Zapůjčené příslušenství dle rezervace: ${esc(v.accessories)}</p>` +
    sigBlock(sig, v.customer_name) +
    foot
}
