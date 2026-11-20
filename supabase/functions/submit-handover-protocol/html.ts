// HTML předávacího protokolu (samoobslužná pobočka) — jen podpis nájemce (MotoGo automaticky
// souhlasí). Používá index.ts; PDF vzniká přes render-pdf. Jazyk (audit EDGE-DOC-10): cs = jen česky
// (beze změny), jiný jazyk zákazníka = dvojjazyčně „jazyk zákazníka / česky“, závazné české znění
// (texty i18n.ts, i18n-a.ts, i18n-b.ts; české popisky níže zůstávají zdrojem pro HO_CS).
import { esc, fill, makeTr } from './i18n.ts';
export { esc };
export function escMulti(s) {
  return esc(s).replace(/\n/g, '<br>');
}
export const HANDOVER_CHECKS = [
  {
    key: 'clean',
    label: 'Motocykl předán čistý a v provozuschopném stavu'
  },
  {
    key: 'docs',
    label: 'Doklady k vozidlu (OTP, zelená karta) předány'
  },
  {
    key: 'keys',
    label: 'Klíče a zabezpečení předány'
  },
  {
    key: 'instructed',
    label: 'Nájemce poučen o obsluze a provozu'
  },
  {
    key: 'gear',
    label: 'Ochranná výbava předána a vyzkoušena'
  }
];
const EXTRA_GEAR_CHECKS = [
  {
    key: 'phone_holder',
    label: 'Držák na telefon'
  },
  {
    key: 'usb_adapter',
    label: 'USB 12V přechodka'
  },
  {
    key: 'disc_lock',
    label: 'Kotoučový zámek'
  },
  {
    key: 'rain_suit',
    label: 'Set nepromokavé bundy a kalhot'
  },
  {
    key: 'rain_boots',
    label: 'Nepromoky na nohy'
  },
  {
    key: 'rain_gloves',
    label: 'Nepromoky na ruce'
  },
  {
    key: 'tie_net',
    label: 'Upínací síťka'
  },
  {
    key: 'tankbag_small',
    label: 'Tankvak malý'
  },
  {
    key: 'tankbag_large',
    label: 'Tankvak velký'
  },
  {
    key: 'reflective',
    label: 'Reflexní prvky'
  },
  {
    key: 'back_protector',
    label: 'Páteřák'
  },
  {
    key: 'chain_spray',
    label: 'Sprej na řetěz'
  }
];
/**
 * Výbava motorky (zadání majitele 2026-09-28): pevná skupina v KAŽDÉM protokolu
 * samoobslužné pobočky — leží v motorce (kufr / tankvak), kiosk (a starší buildy
 * appky) ji ukazuje předem zaškrtnutou a zákazník může odškrtnout, co chybí.
 * Klíče = kiosk `MOTO_GEAR` (formulář v appce zrušen 2026-10-10; starší buildy
 * posílají stejné klíče z `protocol_screen.dart _motoGear`).
 */ export const MOTO_EQUIPMENT = [
  // 2026-10-10 (zadání majitele): každá motorka má kufr (cestovní) nebo tankvak (sportovní, naked, supermoto).
  {
    key: 'luggage',
    label: 'Kufr nebo tankvak (cestovní motorka kufr; sportovní, naked a supermoto tankvak)',
    qty: 1
  },
  // 2026-10-10 (zadání majitele): držák na telefon — k němu patří klíč na dalším řádku.
  {
    key: 'phone_holder',
    label: 'Držák na telefon',
    qty: 1
  },
  {
    key: 'phone_holder_key',
    label: 'Klíč k držáku mobilu',
    qty: 1
  },
  {
    key: 'disc_lock',
    label: 'Kotoučový zámek',
    qty: 1
  },
  {
    key: 'accident_form',
    label: 'Záznam o nehodě (formulář)',
    qty: 1
  },
  {
    key: 'first_aid_kit',
    label: 'Lékárnička',
    qty: 1
  },
  {
    key: 'reflective_vest',
    label: 'Reflexní vesta',
    qty: 2
  },
  // 2026-10-10 (zadání majitele): doklady k motorce — kiosk je ukazuje informativně jako ostatní výbavu.
  {
    key: 'green_card',
    label: 'Zelená karta',
    qty: 1
  },
  {
    key: 'registration_certificate',
    label: 'Technický průkaz',
    qty: 1
  }
];
export const MOTO_EQUIPMENT_NOTE = 'Uložena v motorce — v kufru nebo v tankvaku. Nájemce ji přebírá spolu s motorkou a vrací ji s ní.';
/** Stav km/MH při předání vyplňuje systém, nájemce ho nezadává (zadání majitele 2026-09-29). */ export const MILEAGE_NOTE = 'Vyplněno automaticky ze stavu při posledním vrácení.';
/**
 * `form.moto_equipment[]` z klienta ({key, checked}) → úplný seznam v pevném
 * pořadí. Položka bez hodnoty dostane `defaultChecked`; když klient pole
 * neposlal: `defaultChecked` true/false = doplnit vše (kiosk: starší build
 * jednotky = vše předáno), null = sekce v dokumentu nebude (starší build appky).
 */ export function normalizeMotoEquipment(raw, defaultChecked) {
  const byKey = new Map();
  if (Array.isArray(raw)) {
    for (const it of raw.slice(0, 20)){
      if (!it || typeof it !== 'object') continue;
      const o = it;
      if (typeof o.key === 'string' && typeof o.checked === 'boolean') byKey.set(o.key, o.checked);
    }
  } else if (defaultChecked === null) {
    return null;
  }
  return MOTO_EQUIPMENT.map((m)=>({
      key: m.key,
      label: m.label,
      qty: m.qty,
      checked: byKey.has(m.key) ? byKey.get(m.key) : defaultChecked ?? false
    }));
}
/** Doplňkové vybavení, které je při poslané skupině „Výbava motorky" v ní (kotoučový
 *  zámek, reflexní prvky = vesty, od 2026-10-10 i držák na telefon) — v seznamu doplňků
 *  se pak nevypisuje (bez zdvojení). */ const EXTRA_IN_MOTO_EQUIPMENT = new Set([
  'disc_lock',
  'reflective',
  'phone_holder'
]);
export function fmtDateTime(d) {
  try {
    return d.toLocaleString('cs-CZ', {
      timeZone: 'Europe/Prague'
    });
  } catch  {
    return d.toISOString();
  }
}
export function buildHtml(v, form, signature, signer, lang = 'cs') {
  const tr = makeTr(lang);
  const checks = form.checks || {};
  const damage = form.damage || {};
  const accessories = form.accessories || [];
  const mileage = form.mileage;
  const mh = form.mileage_unit === 'mh' // motocykl evidovaný v motohodinách
  ;
  const notes = form.notes;
  const H3 = (key, top = 14)=>`<h3 style="font-size:13px;margin-top:${top}px">${tr.t(key)}</h3>`;
  // Výbava motorky — kiosk i appka ji posílají (2026-09-28); starší build appky bez pole sekci nemá.
  const motoEq = Array.isArray(form.moto_equipment) ? form.moto_equipment : [];
  const checkList = HANDOVER_CHECKS.map((c)=>`<div style="font-size:12px;margin:5px 0">${checks[c.key] ? '☑' : '☐'} ${tr.t('chk_' + c.key)}</div>`).join('');
  // Samoobsluha (kiosk / appka posílají výbavu motorky) doplňkové vybavení NENABÍZÍ (zadání majitele 2026-10-10) —
  // vypíše se jen to, co starší build appky přesto zaškrtl; nic zaškrtnutého = sekce v dokumentu není.
  const extraList = EXTRA_GEAR_CHECKS.filter((c)=>!(motoEq.length && (EXTRA_IN_MOTO_EQUIPMENT.has(c.key) || !checks[c.key]))).map((c)=>`<div style="font-size:12px;margin:5px 0">${checks[c.key] ? '☑' : '☐'} ${tr.t('ex_' + c.key)}</div>`).join('');
  // Položka s klíčem a rolí → popisek ve slovníku (dvojjazyčně); bez vazby (starší appka) tak, jak přišla.
  const accLabel = (a)=>tr.bilingual && a.key && a.who ? tr.gear(a.key, a.who) : esc(a.label);
  const accRows = accessories.map((a)=>`<tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600">${accLabel(a)}${a.extra ? ` <span style="font-weight:400;color:#666">${tr.t('extraMark')}</span>` : ''}</td><td style="padding:6px 8px;border:1px solid #ddd">${esc(a.size || '')}</td><td style="padding:6px 8px;border:1px solid #ddd;text-align:center;width:80px;font-size:14px">${a.checked ? '☑' : '☐'}</td></tr>`).join('');
  const TH = 'padding:6px 8px;border:1px solid #ddd;background:#f0f7ff;text-align:left;font-size:10px;text-transform:uppercase';
  const accTable = accRows ? `<table style="width:100%;border-collapse:collapse;font-size:11px;margin:6px 0;border:1px solid #ddd"><tr><th style="${TH}">${tr.t('thItem')}</th><th style="${TH}">${tr.t('thSize')}</th><th style="${TH.replace('text-align:left', 'text-align:center')}">${tr.t('thHanded')}</th></tr>${accRows}</table>` : `<p style="font-size:12px">${tr.t('noGear')}</p>`;
  // Nepřevzatá položka, kterou edge z rezervace odebrala (gear.ts `removed`) — poznámka jen tehdy.
  const accNote = (accessories.some((a)=>a.removed) ? `<p style="font-size:10px;color:#666;margin:2px 0 0">${tr.t('removedNote', true)}</p>` : '') + // Převzato navíc (gear.ts `extra`): v rezervaci nebyla, nájemce si ji při převzetí vzal (2026-10-05).
  (accessories.some((a)=>a.extra) ? `<p style="font-size:10px;color:#666;margin:2px 0 0">${tr.t('extraNote', true)}</p>` : '');
  const motoBlock = motoEq.length ? `${H3('motoEq')}<p style="font-size:11px;color:#666;margin:2px 0 6px">${tr.t('motoEqNote', true)}</p>` + motoEq.map((m)=>`<div style="font-size:12px;margin:5px 0">${m.checked ? '☑' : '☐'} ${m.qty > 1 ? `${m.qty}× ` : ''}${tr.has('me_' + m.key) ? tr.t('me_' + m.key) : esc(m.label)}</div>`).join('') : '';
  const damageBlock = `<div style="font-size:12px;margin:5px 0">${damage.checked ? '☑' : '☐'} ${tr.t('damageAt')}</div>` + (damage.checked && damage.desc ? `<p style="font-size:12px;margin:4px 0 0;padding:8px 10px;background:#fef2f2;border:1px solid #fca5a5;border-radius:6px">${escMulti(damage.desc)}</p>` : '');
  const TD = 'padding:6px 8px;border:1px solid #ddd';
  const TDL = `${TD};background:#f8faf9;font-weight:600;width:220px`;
  const row = (labelHtml, val)=>`<tr><td style="${TDL}">${labelHtml}</td><td style="${TD}">${val ? escMulti(val) : '&nbsp;'}</td></tr>`;
  const parties = `${H3('parties', 16)}<table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd">${row(tr.t('lessor'), v.company_name)}${row(tr.t('renter'), v.customer_name)}${row(tr.t('moto'), `${v.moto_model} (${v.moto_spz || ''})`)}${row(tr.t('vin'), v.moto_vin)}${row(tr.t('period'), v.rental_period)}</table>`;
  // Skutečný čas převzetí = okamžik podpisu. Sjednaný čas vyzvednutí (zvolený
  // zákazníkem, řídí slevu za vyzvednutí od 12:00 — zadání 2026-10-01 večer) je
  // jen informativní řádek; smlouva u samoobsluhy platí od 00:01, se slevou od 12:00.
  const signedAt = fmtDateTime(signer.signedAt);
  // Kde byl podpis pořízen — u kiosku s identifikací zařízení (audit).
  const whereOf = (d)=>signer.by === 'kiosk' ? fill(d.whereKiosk, {
      device: esc(signer.deviceId || '?')
    }) : fill(d.whereApp);
  const sigBlock = `<div style="margin-top:40px;display:flex;justify-content:center"><div style="text-align:center;width:60%"><div style="height:96px;border:1px solid #ccc;border-radius:8px;display:flex;align-items:center;justify-content:center;background:#fff;overflow:hidden"><img src="${signature}" alt="podpis" style="max-width:100%;max-height:92px"/></div><div style="border-top:1px solid #999;margin-top:6px;padding-top:6px;font-size:11px">${tr.t('signature')} — ${esc(v.customer_name)}</div><div style="font-size:10px;color:#666;margin-top:4px">${tr.both((d)=>fill(d.signedAt, {
      where: whereOf(d),
      at: esc(signedAt)
    }))}</div></div></div>`;
  const foot = `<p style="font-size:11px;color:#666;margin-top:18px">${tr.both((d)=>fill(d.footer, {
      where: whereOf(d),
      at: esc(signedAt)
    }), true)}</p></div></body></html>`;
  const title = tr.bilingual ? `${tr.plain('title')} / ${tr.plain('title', 'cs')}` : tr.plain('title');
  const sub = tr.both((d)=>fill(d.forBooking, {
      bn: esc(v.booking_number),
      today: esc(v.today)
    }));
  return `<!DOCTYPE html><html lang="${tr.lang}"><head><meta charset="utf-8"><title>${esc(title)}</title></head><body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a"><div style="max-width:780px;margin:0 auto;padding:32px"><h1 style="text-align:center;font-size:19px;border-bottom:2px solid #2563eb;padding-bottom:12px">${tr.t('heading')}</h1><p style="text-align:center;font-size:12px;color:#666">${sub}</p>` + (tr.bilingual ? `<p style="text-align:center;font-size:11px;color:#92400e;margin:4px 0 0">${tr.t('binding')}</p>` : '') + parties + `${H3('state')}<table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd">${v.pickup_time ? row(tr.t('agreedPickup'), v.pickup_time) : ''}${row(tr.t('actualPickup'), signedAt)}${row(tr.t(mh ? 'mileageMh' : 'mileageKm'), mileage ? `${mileage} ${mh ? 'MH' : 'km'}` : '')}</table>` + (mileage ? `<p style="font-size:10px;color:#666;margin:4px 0 0">${tr.t('mileageNote', true)}</p>` : '') + `${H3('checks')}${checkList}` + `${H3('gearTitle')}${accTable}${accNote}` + motoBlock + (extraList || !motoEq.length ? `${H3('extras')}${extraList}` : '') + `${H3('damage')}${damageBlock}` + (notes ? `${H3('notes')}<p style="font-size:12px">${escMulti(notes)}</p>` : '') + sigBlock + foot;
}
