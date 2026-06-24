export function getClientTemplate(slug, dbTemplates) {
  if (dbTemplates && dbTemplates[slug]) return dbTemplates[slug]
  if (slug === 'rental_contract') {
    return `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Smlouva o pronajmu</title></head><body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a"><div style="max-width:780px;margin:0 auto;padding:32px"><h1 style="text-align:center;font-size:20px;border-bottom:2px solid #1a8a18;padding-bottom:12px">SMLOUVA O PRONAJMU MOTOCYKLU</h1><p style="text-align:center;font-size:12px;color:#666">c. {{booking_number}} ze dne {{today}}</p><p>Pronajimatel: Bc. Petra Semoradova, ICO: 21874263</p><p>Najemce: {{customer_name}}, {{customer_address}}</p><p>Motocykl: {{moto_model}} ({{moto_spz}}), VIN: {{moto_vin}}</p><p>Obdobi: {{start_date}} — {{end_date}} ({{days}} dni)</p><p>Celkem: {{total_price}} Kč</p><p style="color:#b45309;font-size:11px;margin-top:24px">Toto je zalozni sablona. Plne texty smluv najdete v Dokumenty - Smluvni texty.</p></div></body></html>`
  }
  if (slug === 'handover_protocol') {
    return `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Predavaci protokol</title></head><body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a"><div style="max-width:780px;margin:0 auto;padding:32px"><h1 style="text-align:center;font-size:20px;border-bottom:2px solid #2563eb;padding-bottom:12px">PREDAVACI PROTOKOL</h1><p style="text-align:center;font-size:12px;color:#666">k rezervaci c. {{booking_number}} ze dne {{today}}</p><p>Najemce: {{customer_name}}</p><p>Motocykl: {{moto_model}} ({{moto_spz}}), VIN: {{moto_vin}}</p><p>Stav km: {{mileage}}</p><h3 style="font-size:13px;margin-top:16px">Prislusenstvi a vybava</h3>{{accessories_block}}<p style="color:#b45309;font-size:11px;margin-top:24px">Toto je zalozni sablona. Plne texty najdete v Dokumenty - Smluvni texty.</p></div></body></html>`
  }
  if (slug === 'vop') {
    return `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Vseobecne obchodni podminky</title></head><body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a"><div style="max-width:780px;margin:0 auto;padding:32px"><h1 style="text-align:center;font-size:20px;border-bottom:2px solid #1a8a18;padding-bottom:12px">VSEOBECNE OBCHODNI PODMINKY</h1><p style="text-align:center;font-size:12px;color:#666">{{company_name}} | ICO: {{company_ico}} | {{company_address}}</p><p style="text-align:center;font-size:12px;color:#666">Platne od {{today}} k rezervaci c. {{booking_number}}</p><h3 style="font-size:13px;margin-top:24px">1. Uvodni ustanoveni</h3><p style="font-size:12px">Tyto vseobecne obchodni podminky upravuji prava a povinnosti smluvnich stran pri pronajmu motocyklu provozovanem spolecnosti {{company_name}}, ICO: {{company_ico}}, se sidlem {{company_address}}.</p><h3 style="font-size:13px">2. Predmet pronajmu</h3><p style="font-size:12px">Predmetem pronajmu je motocykl specifikovany v najemni smlouve.</p><h3 style="font-size:13px">3. Podminky pronajmu</h3><p style="font-size:12px">Najemce musi byt drzitelem platneho ridicskeho prukazu prislusne skupiny. Minimalni vek najemce je 21 let.</p><h3 style="font-size:13px">4. Cena a platebni podminky</h3><p style="font-size:12px">Cena pronajmu se ridi aktualnim cenikem. Platba je splatna pred prevzetim motocyklu.</p><h3 style="font-size:13px">5. Odpovednost za skody</h3><p style="font-size:12px">Najemce odpovida za veskere skody vznikle na motocyklu po dobu pronajmu.</p><h3 style="font-size:13px">6. Storno podminky</h3><p style="font-size:12px">Bezplatne storno je mozne do 48 hodin pred zacatkem pronajmu.</p><p style="color:#b45309;font-size:11px;margin-top:24px">Toto je zalozni sablona. Plne texty VOP najdete v Dokumenty - Smluvni texty.</p></div></body></html>`
  }
  if (slug === 'damage_protocol') {
    return `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Protokol o zjistenem poskozeni</title></head><body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a"><div style="max-width:780px;margin:0 auto;padding:32px"><h1 style="text-align:center;font-size:18px;border-bottom:2px solid #dc2626;padding-bottom:12px">PROTOKOL O ZJISTENEM POSKOZENI PRI VRACENI</h1><p style="text-align:center;font-size:12px;color:#666">k rezervaci c. {{booking_number}} ze dne {{today}}</p><h3 style="font-size:13px;margin-top:16px">1. Identifikace smlouvy a stran</h3><table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd"><tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600;width:220px">Cislo smlouvy</td><td style="padding:6px 8px;border:1px solid #ddd">{{booking_number}}</td></tr><tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600">Pronajimatel</td><td style="padding:6px 8px;border:1px solid #ddd">{{company_name}}</td></tr><tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600">Najemce</td><td style="padding:6px 8px;border:1px solid #ddd">{{customer_name}}</td></tr></table><h3 style="font-size:13px;margin-top:14px">2. Identifikace vozidla</h3><table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd"><tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600;width:220px">Znacka a model</td><td style="padding:6px 8px;border:1px solid #ddd">{{moto_model}}</td></tr><tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600">VIN</td><td style="padding:6px 8px;border:1px solid #ddd">{{moto_vin}}</td></tr><tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600">SPZ</td><td style="padding:6px 8px;border:1px solid #ddd">{{moto_spz}}</td></tr></table><h3 style="font-size:13px;margin-top:14px">3. Stav motocyklu pri vraceni</h3><table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd"><tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600;width:220px">Stav tachometru</td><td style="padding:6px 8px;border:1px solid #ddd">&nbsp; km</td></tr><tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600">Celkovy vizualni stav</td><td style="padding:14px 8px;border:1px solid #ddd"></td></tr></table><h3 style="font-size:13px;margin-top:14px">4. Zjistena poskozeni / chybejici prislusenstvi</h3><table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd"><tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600;width:220px;vertical-align:top">Popis poskozeni motocyklu</td><td style="padding:24px 8px;border:1px solid #ddd"></td></tr><tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600;vertical-align:top">Chybejici / poskozene vybaveni</td><td style="padding:18px 8px;border:1px solid #ddd"></td></tr></table><p style="font-size:11px;color:#666;margin-top:6px">Zapujcene prislusenstvi dle rezervace: {{accessories}}</p><p style="font-size:12px;margin-top:12px">Prislusna fotodokumentace je prilozena k protokolu a je jeho nedilnou soucasti.</p><table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd;margin-top:8px"><tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600;width:220px">Datum a cas vraceni</td><td style="padding:6px 8px;border:1px solid #ddd">{{today}} {{today_time}}</td></tr><tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600">Vystavil/a</td><td style="padding:6px 8px;border:1px solid #ddd">{{company_name}}</td></tr></table><div style="margin-top:48px;display:flex;justify-content:space-between"><div style="text-align:center;width:45%"><div style="border-top:1px solid #999;padding-top:8px;font-size:11px">Podpis pronajimatele</div></div><div style="text-align:center;width:45%"><div style="border-top:1px solid #999;padding-top:8px;font-size:11px">Podpis najemce — {{customer_name}}</div></div></div><p style="color:#b45309;font-size:11px;margin-top:24px">Toto je zalozni sablona. Plne texty najdete v Dokumenty - Smluvni texty.</p></div></body></html>`
  }
  if (slug === 'gdpr') {
    return `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Souhlas se zpracovanim osobnich udaju</title></head><body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a"><div style="max-width:780px;margin:0 auto;padding:32px"><h1 style="text-align:center;font-size:18px;border-bottom:2px solid #1a8a18;padding-bottom:12px">INFORMACE A SOUHLAS SE ZPRACOVANIM OSOBNICH UDAJU (GDPR)</h1><p style="text-align:center;font-size:12px;color:#666">{{company_name}} | ICO: {{company_ico}} | {{company_address}} | ze dne {{today}}</p><h3 style="font-size:13px;margin-top:16px">1. Spravce osobnich udaju</h3><p style="font-size:12px">Spravcem osobnich udaju je {{company_name}}, ICO: {{company_ico}}, se sidlem {{company_address}}, kontakt: info@motogo24.cz, +420 774 256 271.</p><h3 style="font-size:13px">2. Subjekt udaju</h3><p style="font-size:12px">Jmeno a prijmeni: <strong>{{customer_name}}</strong><br>Adresa: {{customer_address}}<br>E-mail: {{customer_email}}</p><h3 style="font-size:13px">3. Rozsah a ucel zpracovani</h3><p style="font-size:12px">Spravce zpracovava identifikacni a kontaktni udaje, udaje z dokladu totoznosti a ridicskeho prukazu a udaje o rezervaci za ucelem uzavreni a plneni najemni smlouvy, vedeni evidence, fakturace a plneni pravnich povinnosti.</p><h3 style="font-size:13px">4. Pravni zaklad a doba uchovani</h3><p style="font-size:12px">Zpracovani je nezbytne pro plneni smlouvy a plneni pravnich povinnosti spravce (zejm. ucetni a danove predpisy). Udaje jsou uchovavany po dobu trvani smluvniho vztahu a nasledne po dobu stanovenou pravnimi predpisy.</p><h3 style="font-size:13px">5. Prava subjektu udaju</h3><p style="font-size:12px">Subjekt udaju ma pravo na pristup k udajum, jejich opravu, vymaz, omezeni zpracovani, prenositelnost, vzneseni namitky a pravo podat stiznost u Uradu pro ochranu osobnich udaju.</p><h3 style="font-size:13px">6. Souhlas</h3><p style="font-size:12px">Svym podpisem potvrzuji, ze jsem byl/a informovan/a o zpracovani osobnich udaju v rozsahu uvedenem vyse.</p><div style="margin-top:48px;display:flex;justify-content:space-between"><div style="text-align:center;width:45%"><div style="border-top:1px solid #999;padding-top:8px;font-size:11px">Za spravce — {{company_name}}</div></div><div style="text-align:center;width:45%"><div style="border-top:1px solid #999;padding-top:8px;font-size:11px">{{customer_name}}</div></div></div><p style="color:#b45309;font-size:11px;margin-top:24px">Toto je zalozni sablona. Plne texty najdete v Dokumenty - Smluvni texty.</p></div></body></html>`
  }
  return null
}

// Sestaví seznam zapůjčeného příslušenství (velikosti) z reálné rezervace.
// - vždy řádky pro řidiče podle vyplněných `*_size`
// - pokud má spolujezdec aspoň jednu velikost → druhá sada řádků "(spolujezdec)"
//   (klidně chybí boty / jen 2 velikosti — vypíše se jen objednané)
// - u dětských motorek (`motorcycles.license_required === 'N'`) přidá "(dětská velikost)"
export function buildAccessoriesBlock(booking, moto) {
  const isChild = String(moto?.license_required || '').toUpperCase() === 'N'
  const childSuffix = isChild ? ' (dětská velikost)' : ''
  const items = [
    { key: 'helmet', label: 'Helma' },
    { key: 'jacket', label: 'Bunda / vesta' },
    { key: 'pants', label: 'Kalhoty' },
    { key: 'boots', label: 'Boty' },
    { key: 'gloves', label: 'Rukavice' },
  ]
  const td = 'padding:6px 8px;border:1px solid #ddd;text-align:left'
  const rows = []
  const textParts = []
  const addRow = (label, size) => {
    rows.push(`<tr><td style="${td};background:#f8faf9;font-weight:600">${label}${childSuffix}</td><td style="${td}">${size}</td><td style="${td};text-align:center;width:60px">☐</td></tr>`)
    textParts.push(`${label} ${size}`)
  }
  let hasRider = false
  for (const it of items) { const s = booking?.[`${it.key}_size`]; if (s) { addRow(`${it.label} (řidič)`, String(s)); hasRider = true } }
  let hasPassenger = false
  for (const it of items) { const s = booking?.[`passenger_${it.key}_size`]; if (s) { addRow(`${it.label} (spolujezdec)`, String(s)); hasPassenger = true } }
  if (!hasRider && !hasPassenger) return { html: '<p style="font-size:12px">Žádné zapůjčené příslušenství.</p>', text: 'Žádné' }
  const th = 'padding:6px 8px;border:1px solid #ddd;text-align:left;background:#f0f7ff;font-weight:700;font-size:10px;text-transform:uppercase'
  const html = `<table style="width:100%;border-collapse:collapse;font-size:11px;margin:6px 0;border:1px solid #ddd"><tr><th style="${th}">Položka</th><th style="${th}">Velikost</th><th style="${th}">Předáno</th></tr>${rows.join('')}</table>`
  return { html, text: textParts.join(', ') }
}

// Strukturovaný seznam zapůjčeného příslušenství pro elektronický protokol
// (checkboxy „předáno"). Stejná pravidla jako buildAccessoriesBlock.
export function listAccessoryItems(booking, moto) {
  const isChild = String(moto?.license_required || '').toUpperCase() === 'N'
  const suffix = isChild ? ' (dětská velikost)' : ''
  const defs = [
    { key: 'helmet', label: 'Helma' },
    { key: 'jacket', label: 'Bunda / vesta' },
    { key: 'pants', label: 'Kalhoty' },
    { key: 'boots', label: 'Boty' },
    { key: 'gloves', label: 'Rukavice' },
  ]
  const out = []
  for (const d of defs) { const s = booking?.[`${d.key}_size`]; if (s) out.push({ label: `${d.label} (řidič)${suffix}`, size: String(s) }) }
  for (const d of defs) { const s = booking?.[`passenger_${d.key}_size`]; if (s) out.push({ label: `${d.label} (spolujezdec)${suffix}`, size: String(s) }) }
  return out
}

export function buildDocVars(booking, customer, bookingId) {
  const moto = booking.motorcycles || {}
  const accessories = buildAccessoriesBlock(booking, moto)
  const days = Math.max(1, Math.ceil((new Date(booking.end_date) - new Date(booking.start_date)) / 86400000))
  const fmtDate = (d) => d ? new Date(d).toLocaleDateString('cs-CZ') : '\u2014'
  const fmtPrice = (n) => (n || 0).toLocaleString('cs-CZ', { minimumFractionDigits: 2 })
  return {
    customer_name: customer.full_name || '\u2014', customer_email: customer.email || '',
    customer_phone: customer.phone || '', customer_address: [customer.street, customer.city, customer.zip, customer.country].filter(Boolean).join(', ') || '',
    customer_ico: customer.ico || '', customer_dic: customer.dic || '',
    customer_license: customer.license_number || '', customer_license_expiry: fmtDate(customer.license_expiry),
    customer_id_number: '',
    moto_model: moto.model || '\u2014', moto_spz: moto.spz || '', moto_vin: moto.vin || '', moto_year: String(moto.year || ''),
    start_date: fmtDate(booking.start_date), end_date: fmtDate(booking.end_date),
    days: String(days), total_price: fmtPrice(booking.total_price || 0),
    daily_rate: fmtPrice(Math.round((booking.total_price || 0) / days)),
    booking_id: bookingId.slice(-8).toUpperCase(), booking_number: bookingId.slice(-8).toUpperCase(),
    today: fmtDate(new Date().toISOString()),
    start_time: booking.pickup_time || '', end_time: '24:00',
    rental_period: `${fmtDate(booking.start_date)} \u2014 ${fmtDate(booking.end_date)} (${days} dni)`,
    total_price_words: '',
    pickup_location: booking.pickup_address || 'Mezna 9, 393 01 Mezna',
    return_location: booking.return_address || 'Mezna 9, 393 01 Mezna',
    mileage: String(booking.mileage_start || ''),
    technical_state: '',
    accessories_block: accessories.html,
    accessories: accessories.text,
    today_time: new Date().toLocaleTimeString('cs-CZ', { hour: '2-digit', minute: '2-digit' }),
    company_name: 'Bc. Petra Semoradova', company_address: 'Mezna 9, 393 01 Mezna',
    company_ico: '21874263', company_dic: '',
  }
}

export function fillTemplate(html, vars) {
  for (const [key, val] of Object.entries(vars)) {
    html = html.replace(new RegExp(`\\{\\{${key}\\}\\}`, 'g'), val)
  }
  return html
}

export function rebuildFromFilledData(doc) {
  if (!doc.filled_data) return null
  // Elektronicky podepsaný protokol nese kompletní finální HTML (vč. podpisů) →
  // vrať ho přímo, ať náhled i stažení ukazují přesně podepsaný dokument.
  if (doc.filled_data._signed_html) return doc.filled_data._signed_html
  const v = doc.filled_data
  return `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Dokument</title></head><body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a"><div style="max-width:780px;margin:0 auto;padding:32px"><h2>${v.company_name || 'MotoGo24'}</h2><p>Zakaznik: ${v.customer_name || '\u2014'}</p><p>Motocykl: ${v.moto_model || '\u2014'} (${v.moto_spz || ''})</p><p>Obdobi: ${v.start_date || '\u2014'} — ${v.end_date || '\u2014'} (${v.days || '\u2014'} dni)</p><p>Cena: ${v.total_price || '\u2014'} Kč</p></div></body></html>`
}
