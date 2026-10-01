// HTML předávacího protokolu (samoobslužná pobočka) — česky, jen podpis nájemce
// (MotoGo automaticky souhlasí). Používá index.ts; PDF vzniká přes render-pdf.

import type { AccessoryItem } from './gear.ts'

export function esc(s: unknown): string {
  return String(s == null ? '' : s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c] as string))
}
export function escMulti(s: unknown): string { return esc(s).replace(/\n/g, '<br>') }

export const HANDOVER_CHECKS = [
  { key: 'clean', label: 'Motocykl předán čistý a v provozuschopném stavu' },
  { key: 'docs', label: 'Doklady k vozidlu (OTP, zelená karta) předány' },
  { key: 'keys', label: 'Klíče a zabezpečení předány' },
  { key: 'instructed', label: 'Nájemce poučen o obsluze a provozu' },
  { key: 'gear', label: 'Ochranná výbava předána a vyzkoušena' },
]
const EXTRA_GEAR_CHECKS = [
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

/**
 * Výbava motorky (zadání majitele 2026-09-28): pevná skupina v KAŽDÉM protokolu
 * samoobslužné pobočky — leží v motorce (kufr / tankvak), kiosk i appka (zrcadlo)
 * ji ukazují předem zaškrtnutou a zákazník může odškrtnout, co chybí.
 * Klíče = kiosk `MOTO_GEAR`, appka `protocol_screen.dart _motoGear`.
 */
export const MOTO_EQUIPMENT = [
  { key: 'phone_holder_key', label: 'Klíč k držáku mobilu', qty: 1 },
  { key: 'disc_lock', label: 'Kotoučový zámek', qty: 1 },
  { key: 'accident_form', label: 'Záznam o nehodě (formulář)', qty: 1 },
  { key: 'first_aid_kit', label: 'Lékárnička', qty: 1 },
  { key: 'reflective_vest', label: 'Reflexní vesta', qty: 2 },
] as const
export const MOTO_EQUIPMENT_NOTE = 'Uložena v motorce — v kufru nebo v tankvaku. Nájemce ji přebírá spolu s motorkou a vrací ji s ní.'

/** Stav km/MH při předání vyplňuje systém, nájemce ho nezadává (zadání majitele 2026-09-29). */
export const MILEAGE_NOTE = 'Vyplněno automaticky ze stavu při posledním vrácení.'

export interface MotoEquipmentItem { key: string; label: string; qty: number; checked: boolean }

/**
 * `form.moto_equipment[]` z klienta ({key, checked}) → úplný seznam v pevném
 * pořadí. Položka bez hodnoty dostane `defaultChecked`; když klient pole
 * neposlal: `defaultChecked` true/false = doplnit vše (kiosk: starší build
 * jednotky = vše předáno), null = sekce v dokumentu nebude (starší build appky).
 */
export function normalizeMotoEquipment(raw: unknown, defaultChecked: boolean | null): MotoEquipmentItem[] | null {
  const byKey = new Map<string, boolean>()
  if (Array.isArray(raw)) {
    for (const it of raw.slice(0, 20)) {
      if (!it || typeof it !== 'object') continue
      const o = it as Record<string, unknown>
      if (typeof o.key === 'string' && typeof o.checked === 'boolean') byKey.set(o.key, o.checked)
    }
  } else if (defaultChecked === null) {
    return null
  }
  return MOTO_EQUIPMENT.map((m) => ({
    key: m.key, label: m.label, qty: m.qty,
    checked: byKey.has(m.key) ? (byKey.get(m.key) as boolean) : (defaultChecked ?? false),
  }))
}

/** Doplňkové vybavení, které je při poslané skupině „Výbava motorky" v ní (kotoučový
 *  zámek, reflexní prvky = vesty) — v seznamu doplňků se pak nevypisuje (bez zdvojení). */
const EXTRA_IN_MOTO_EQUIPMENT = new Set(['disc_lock', 'reflective'])

export interface Vars {
  booking_number: string; today: string; company_name: string; customer_name: string
  moto_model: string; moto_spz: string; moto_vin: string; rental_period: string
  /** Sjednaný čas vyzvednutí („d. m. rrrr HH:MM“); '' = bez času (stará samoobsluha 00:01). */
  pickup_time?: string
}

/** Kdo a kde podepsal: appka (JWT zákazníka) nebo displej pobočky (zařízení kiosku). */
export interface Signer { by: 'app' | 'kiosk'; deviceId?: string; signedAt: Date }

export function fmtDateTime(d: Date): string {
  try { return d.toLocaleString('cs-CZ', { timeZone: 'Europe/Prague' }) } catch { return d.toISOString() }
}

export function buildHtml(v: Vars, form: Record<string, unknown>, signature: string, signer: Signer): string {
  const checks = (form.checks || {}) as Record<string, boolean>
  const damage = (form.damage || {}) as { checked?: boolean; desc?: string }
  const accessories = (form.accessories || []) as AccessoryItem[]
  const mileage = form.mileage as string | undefined
  const mh = form.mileage_unit === 'mh' // motocykl evidovaný v motohodinách
  const notes = form.notes as string | undefined

  // Výbava motorky — kiosk i appka ji posílají (2026-09-28); starší build appky bez pole sekci nemá.
  const motoEq = Array.isArray(form.moto_equipment) ? form.moto_equipment as MotoEquipmentItem[] : []
  const checkList = HANDOVER_CHECKS.map((c) => `<div style="font-size:12px;margin:5px 0">${checks[c.key] ? '☑' : '☐'} ${esc(c.label)}</div>`).join('')
  const extraList = EXTRA_GEAR_CHECKS.filter((c) => !(motoEq.length && EXTRA_IN_MOTO_EQUIPMENT.has(c.key)))
    .map((c) => `<div style="font-size:12px;margin:5px 0">${checks[c.key] ? '☑' : '☐'} ${esc(c.label)}</div>`).join('')
  const accRows = accessories.map((a) => `<tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600">${esc(a.label)}</td><td style="padding:6px 8px;border:1px solid #ddd">${esc(a.size || '')}</td><td style="padding:6px 8px;border:1px solid #ddd;text-align:center;width:80px;font-size:14px">${a.checked ? '☑' : '☐'}</td></tr>`).join('')
  const accTable = accRows
    ? `<table style="width:100%;border-collapse:collapse;font-size:11px;margin:6px 0;border:1px solid #ddd"><tr><th style="padding:6px 8px;border:1px solid #ddd;background:#f0f7ff;text-align:left;font-size:10px;text-transform:uppercase">Položka</th><th style="padding:6px 8px;border:1px solid #ddd;background:#f0f7ff;text-align:left;font-size:10px;text-transform:uppercase">Velikost</th><th style="padding:6px 8px;border:1px solid #ddd;background:#f0f7ff;text-align:center;font-size:10px;text-transform:uppercase">Předáno</th></tr>${accRows}</table>`
    : '<p style="font-size:12px">Žádná zapůjčená výbava.</p>'
  const motoBlock = motoEq.length
    ? `<h3 style="font-size:13px;margin-top:14px">Výbava motorky</h3><p style="font-size:11px;color:#666;margin:2px 0 6px">${esc(MOTO_EQUIPMENT_NOTE)}</p>` +
      motoEq.map((m) => `<div style="font-size:12px;margin:5px 0">${m.checked ? '☑' : '☐'} ${m.qty > 1 ? `${m.qty}× ` : ''}${esc(m.label)}</div>`).join('')
    : ''
  const damageBlock = `<div style="font-size:12px;margin:5px 0">${damage.checked ? '☑' : '☐'} Poškození při předání</div>` +
    (damage.checked && damage.desc ? `<p style="font-size:12px;margin:4px 0 0;padding:8px 10px;background:#fef2f2;border:1px solid #fca5a5;border-radius:6px">${escMulti(damage.desc)}</p>` : '')

  const TD = 'padding:6px 8px;border:1px solid #ddd'
  const TDL = `${TD};background:#f8faf9;font-weight:600;width:220px`
  const row = (l: string, val: string) => `<tr><td style="${TDL}">${esc(l)}</td><td style="${TD}">${val ? escMulti(val) : '&nbsp;'}</td></tr>`
  const parties = `<h3 style="font-size:13px;margin-top:16px">Smluvní strany a vozidlo</h3><table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd">${row('Pronajímatel', v.company_name)}${row('Nájemce', v.customer_name)}${row('Motocykl', `${v.moto_model} (${v.moto_spz || ''})`)}${row('VIN', v.moto_vin)}${row('Období pronájmu', v.rental_period)}</table>`

  // Skutečný čas převzetí = okamžik podpisu. Sjednaný čas vyzvednutí (zvolený
  // zákazníkem, řídí slevu za vyzvednutí od 12:00 — zadání 2026-10-01 večer) je
  // jen informativní řádek; smlouva u samoobsluhy platí od 00:01, se slevou od 12:00.
  const signedAt = fmtDateTime(signer.signedAt)
  // Kde byl podpis pořízen — u kiosku s identifikací zařízení (audit).
  const where = signer.by === 'kiosk'
    ? `na displeji pobočky (zařízení ${esc(signer.deviceId || '?')})`
    : 'v aplikaci MotoGo24'
  const sigBlock = `<div style="margin-top:40px;display:flex;justify-content:center"><div style="text-align:center;width:60%"><div style="height:96px;border:1px solid #ccc;border-radius:8px;display:flex;align-items:center;justify-content:center;background:#fff;overflow:hidden"><img src="${signature}" alt="podpis" style="max-width:100%;max-height:92px"/></div><div style="border-top:1px solid #999;margin-top:6px;padding-top:6px;font-size:11px">Podpis nájemce — ${esc(v.customer_name)}</div><div style="font-size:10px;color:#666;margin-top:4px">Podepsáno ${where} ${esc(signedAt)}</div></div></div>`

  const foot = `<p style="font-size:11px;color:#666;margin-top:18px">Tento protokol byl vyplněn a elektronicky podepsán nájemcem na samoobslužné pobočce ${where} dne ${esc(signedAt)}. Případné nesrovnalosti nahlaste neprodleně přes aplikaci nebo e-mailem na info@motogo24.cz.</p></div></body></html>`

  return `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Předávací protokol</title></head><body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a"><div style="max-width:780px;margin:0 auto;padding:32px"><h1 style="text-align:center;font-size:19px;border-bottom:2px solid #2563eb;padding-bottom:12px">PŘEDÁVACÍ PROTOKOL</h1><p style="text-align:center;font-size:12px;color:#666">k rezervaci č. ${esc(v.booking_number)} ze dne ${esc(v.today)}</p>` +
    parties +
    `<h3 style="font-size:13px;margin-top:14px">Stav při předání</h3><table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd">${v.pickup_time ? row('Sjednaný čas vyzvednutí', v.pickup_time) : ''}${row('Skutečný čas převzetí', signedAt)}${row(mh ? 'Stav motohodin při předání' : 'Stav km při předání', mileage ? `${mileage} ${mh ? 'MH' : 'km'}` : '')}</table>` +
    (mileage ? `<p style="font-size:10px;color:#666;margin:4px 0 0">${esc(MILEAGE_NOTE)}</p>` : '') +
    `<h3 style="font-size:13px;margin-top:14px">Kontrola předání</h3>${checkList}` +
    `<h3 style="font-size:13px;margin-top:14px">Zapůjčená výbava</h3>${accTable}` +
    motoBlock +
    `<h3 style="font-size:13px;margin-top:14px">Doplňkové vybavení</h3>${extraList}` +
    `<h3 style="font-size:13px;margin-top:14px">Poškození</h3>${damageBlock}` +
    (notes ? `<h3 style="font-size:13px;margin-top:14px">Poznámky</h3><p style="font-size:12px">${escMulti(notes)}</p>` : '') +
    sigBlock + foot
}
