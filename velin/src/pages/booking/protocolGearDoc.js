// HTML elektronického předávacího protokolu výpůjčky JEN výbavy (Velín, obslužná i samoobslužná pobočka) —
// varianta buildElectronicProtocolHtml bez motocyklu: předmět nájmu = výbava, pobočka, identita = kód šatny,
// kontroly výbavy (GEAR_HANDOVER_CHECKS), tabulka kusů s velikostmi, poškození výbavy, podpis nájemce.
import { esc, escMulti, TD, infoRow, sigBlock } from './bookingDocElectronic'
import { makeGearTr, GEAR_HANDOVER_CHECKS } from './protocolGearOnly'

export function buildGearProtocolHtml({ vars, form, signatures, lang = 'cs', branch = null }) {
  const v = vars || {}
  const f = form || {}
  const sig = signatures || {}
  const signedAt = new Date().toLocaleString('cs-CZ')
  const T = makeGearTr(lang)
  const tr = T.base
  const h3 = (html, top = 14) => `<h3 style="font-size:13px;margin-top:${top}px">${html}</h3>`
  const table = rows => `<table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd">${rows}</table>`

  const head = `<!DOCTYPE html><html lang="${tr.lang}"><head><meta charset="utf-8"><title>${esc(T.gplain('gHeading'))}</title></head><body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a"><div style="max-width:780px;margin:0 auto;padding:32px"><h1 style="text-align:center;font-size:19px;border-bottom:2px solid #0e7490;padding-bottom:12px">${T.g('gHeading', true)}</h1><p style="text-align:center;font-size:12px;color:#666">${tr.fill('forBooking', { bn: esc(v.booking_number), today: esc(v.today) })}</p>` +
    (tr.bilingual ? `<p style="text-align:center;font-size:11px;color:#666;margin-top:-4px">${tr.t('binding')}</p>` : '')

  const branchVal = [branch?.name, [branch?.address, [branch?.zip, branch?.city].filter(Boolean).join(' ')].filter(Boolean).join(', ')].filter(Boolean).join(' — ')
  const identityRow = f.identityCodeRequired ? infoRow(T.g('gIdentity'), tr.plain(f.identityVerified ? 'verified' : 'notVerified')) : ''
  const parties = h3(T.g('gParties'), 16) + table(
    infoRow(tr.t('lessor'), v.company_name) + infoRow(tr.t('renter'), v.customer_name) +
    infoRow(T.g('gSubject'), T.gplain('gSubjectVal')) + infoRow(T.g('gBranch'), branchVal) +
    infoRow(tr.t('period'), v.rental_period) + identityRow)

  const state = h3(tr.t('state')) + table(infoRow(T.g('gPickedAt'), signedAt))
  const checkList = GEAR_HANDOVER_CHECKS.map(c => `<div style="font-size:12px;margin:5px 0">${f.checks?.[c.key] ? '☑' : '☐'} ${T.g('chk_' + c.key)}</div>`).join('')

  const acc = f.accessories || []
  const th = `${TD};background:#f0f7ff;font-size:10px;text-transform:uppercase`
  const accRows = acc.map(a => `<tr><td style="${TD};background:#f8faf9;font-weight:600">${a.type ? T.item(a.type, a.label) : esc(a.label)}</td><td style="${TD}">${esc(a.size)}</td><td style="${TD};text-align:center;width:80px;font-size:14px">${a.checked ? '☑' : '☐'}</td></tr>`).join('')
  const accTable = accRows
    ? `<table style="width:100%;border-collapse:collapse;font-size:11px;margin:6px 0;border:1px solid #ddd"><tr><th style="${th};text-align:left">${tr.t('thItem')}</th><th style="${th};text-align:left">${tr.t('thSize')}</th><th style="${th};text-align:center">${tr.t('thHanded')}</th></tr>${accRows}</table>` +
      (acc.some(a => !a.checked) ? `<p style="font-size:10px;color:#666;margin:2px 0 0">${tr.t('removedNote')}</p>` : '')
    : `<p style="font-size:12px">${tr.t('noAcc')}</p>`

  const dmg = f.damage || {}
  const damageBlock = `<div style="font-size:12px;margin:5px 0">${dmg.checked ? '☑' : '☐'} ${T.g('gDamageAt')}</div>` +
    (dmg.checked && dmg.desc ? `<p style="font-size:12px;margin:4px 0 0;padding:8px 10px;background:#fef2f2;border:1px solid #fca5a5;border-radius:6px">${escMulti(dmg.desc)}</p>` : '')

  return head + parties + state +
    `${h3(tr.t('checks'))}${checkList}` +
    `${h3(T.g('gAccTitle'))}${accTable}` +
    `${h3(tr.t('damage'))}${damageBlock}` +
    (f.notes ? `${h3(tr.t('notes'))}<p style="font-size:12px">${escMulti(f.notes)}</p>` : '') +
    sigBlock(tr, sig, v.customer_name, false) +
    `<p style="font-size:11px;color:#666;margin-top:18px">${tr.fill('footer', { at: esc(signedAt) }, true)}</p></div></body></html>`
}
