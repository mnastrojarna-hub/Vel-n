// HTML předávacího protokolu výpůjčky JEN výbavy (booking_kind = 'gear', 2026-10-23) — obdoba html.ts
// bez motocyklu: předmět nájmu „Motorkářská výbava (bez motocyklu)“, pobočka, ověření nájemce kódem
// šatny (kiosk) / přihlášením (appka), bez km/VIN, bez kontrol a výbavy motorky; kontroly
// gear_condition / gear_fit / gear_return, tabulka kusů (bez „řidič“), poškození výbavy.
// Jazyk jako html.ts: cs = jen česky, jinak dvojjazyčně se závazným českým zněním (texty gr_* v i18n-gear.ts).

import type { AccessoryItem } from './gear.ts'
import { escMulti, fmtDateTime, type Signer, type Vars } from './html.ts'
import { esc, fill, makeTr } from './i18n.ts'

export const GEAR_CHECKS = ['gear_condition', 'gear_fit', 'gear_return'] as const

export interface GearDocCtx {
  /** „MotoGo24 Velké Němčice, Adresa, Město“ — pobočka rezervace (bookings.branch_id). */
  branch: string
}

export function buildGearHtml(v: Vars, form: Record<string, unknown>, signature: string, signer: Signer, lang: string, ctx: GearDocCtx): string {
  const tr = makeTr(lang)
  const checks = (form.checks || {}) as Record<string, boolean>
  const damage = (form.damage || {}) as { checked?: boolean; desc?: string }
  const accessories = (form.accessories || []) as AccessoryItem[]
  const notes = form.notes as string | undefined
  const H3 = (key: string, top = 14) => `<h3 style="font-size:13px;margin-top:${top}px">${tr.t(key)}</h3>`

  const checkList = GEAR_CHECKS.map((k) => `<div style="font-size:12px;margin:5px 0">${checks[k] ? '☑' : '☐'} ${tr.t('gr_chk_' + k)}</div>`).join('')
  // Kus s klíčem → jen název kusu (výpůjčka nemá spolujezdce); bez vazby tak, jak přišel.
  const accLabel = (a: AccessoryItem) => a.key ? tr.t('g_' + a.key) : esc(a.label)
  const TDc = 'padding:6px 8px;border:1px solid #ddd'
  const accRows = accessories.map((a) => `<tr><td style="${TDc};background:#f8faf9;font-weight:600">${accLabel(a)}${a.extra ? ` <span style="font-weight:400;color:#666">${tr.t('extraMark')}</span>` : ''}</td><td style="${TDc}">${esc(a.size || '')}</td><td style="${TDc};text-align:center;width:80px;font-size:14px">${a.checked ? '☑' : '☐'}</td></tr>`).join('')
  const TH = 'padding:6px 8px;border:1px solid #ddd;background:#f0f7ff;text-align:left;font-size:10px;text-transform:uppercase'
  const accTable = accRows
    ? `<table style="width:100%;border-collapse:collapse;font-size:11px;margin:6px 0;border:1px solid #ddd"><tr><th style="${TH}">${tr.t('thItem')}</th><th style="${TH}">${tr.t('thSize')}</th><th style="${TH.replace('text-align:left', 'text-align:center')}">${tr.t('thHanded')}</th></tr>${accRows}</table>`
    : `<p style="font-size:12px">${tr.t('noGear')}</p>`
  const accNote = (accessories.some((a) => a.removed) ? `<p style="font-size:10px;color:#666;margin:2px 0 0">${tr.t('removedNote', true)}</p>` : '') +
    (accessories.some((a) => a.extra) ? `<p style="font-size:10px;color:#666;margin:2px 0 0">${tr.t('extraNote', true)}</p>` : '')
  const damageBlock = `<div style="font-size:12px;margin:5px 0">${damage.checked ? '☑' : '☐'} ${tr.t('gr_damageAt')}</div>` +
    (damage.checked && damage.desc ? `<p style="font-size:12px;margin:4px 0 0;padding:8px 10px;background:#fef2f2;border:1px solid #fca5a5;border-radius:6px">${escMulti(damage.desc)}</p>` : '')

  const TD = 'padding:6px 8px;border:1px solid #ddd'
  const TDL = `${TD};background:#f8faf9;font-weight:600;width:220px`
  const row = (labelHtml: string, valHtml: string) => `<tr><td style="${TDL}">${labelHtml}</td><td style="${TD}">${valHtml || '&nbsp;'}</td></tr>`
  const identity = tr.t(signer.by === 'kiosk' ? 'gr_identity_kiosk' : 'gr_identity_app')
  const parties = `${H3('gr_parties', 16)}<table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd">` +
    row(tr.t('lessor'), escMulti(v.company_name)) + row(tr.t('renter'), escMulti(v.customer_name)) +
    row(tr.t('gr_subject'), tr.t('gr_subject_val')) + row(tr.t('gr_branch'), escMulti(ctx.branch)) +
    row(tr.t('period'), escMulti(v.rental_period)) + row(tr.t('gr_identity'), identity) + `</table>`

  const signedAt = fmtDateTime(signer.signedAt)
  const whereOf = (d: Record<string, string>) => signer.by === 'kiosk'
    ? fill(d.whereKiosk, { device: esc(signer.deviceId || '?') })
    : fill(d.whereApp)
  const sigBlock = `<div style="margin-top:40px;display:flex;justify-content:center"><div style="text-align:center;width:60%"><div style="height:96px;border:1px solid #ccc;border-radius:8px;display:flex;align-items:center;justify-content:center;background:#fff;overflow:hidden"><img src="${signature}" alt="podpis" style="max-width:100%;max-height:92px"/></div><div style="border-top:1px solid #999;margin-top:6px;padding-top:6px;font-size:11px">${tr.t('signature')} — ${esc(v.customer_name)}</div><div style="font-size:10px;color:#666;margin-top:4px">${tr.both((d) => fill(d.signedAt, { where: whereOf(d), at: esc(signedAt) }))}</div></div></div>`
  const foot = `<p style="font-size:11px;color:#666;margin-top:18px">${tr.both((d) => fill(d.footer, { where: whereOf(d), at: esc(signedAt) }), true)}</p></div></body></html>`
  const title = tr.bilingual ? `${tr.plain('gr_title')} / ${tr.plain('gr_title', 'cs')}` : tr.plain('gr_title')
  const sub = tr.both((d) => fill(d.forBooking, { bn: esc(v.booking_number), today: esc(v.today) }))

  return `<!DOCTYPE html><html lang="${tr.lang}"><head><meta charset="utf-8"><title>${esc(title)}</title></head><body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a"><div style="max-width:780px;margin:0 auto;padding:32px"><h1 style="text-align:center;font-size:19px;border-bottom:2px solid #2563eb;padding-bottom:12px">${tr.t('gr_heading')}</h1><p style="text-align:center;font-size:12px;color:#666">${sub}</p>` +
    (tr.bilingual ? `<p style="text-align:center;font-size:11px;color:#92400e;margin:4px 0 0">${tr.t('binding')}</p>` : '') +
    parties +
    `${H3('state')}<table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd">${v.pickup_time ? row(tr.t('agreedPickup'), escMulti(v.pickup_time)) : ''}${row(tr.t('actualPickup'), escMulti(signedAt))}</table>` +
    `${H3('checks')}${checkList}` +
    `${H3('gearTitle')}${accTable}${accNote}` +
    `${H3('damage')}${damageBlock}` +
    (notes ? `${H3('notes')}<p style="font-size:12px">${escMulti(notes)}</p>` : '') +
    sigBlock + foot
}
