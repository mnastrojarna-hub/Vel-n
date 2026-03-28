export function getClientTemplate(slug, dbTemplates) {
  if (dbTemplates && dbTemplates[slug]) return dbTemplates[slug]
  if (slug === 'rental_contract') {
    return `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Smlouva o pronajmu</title></head><body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a"><div style="max-width:780px;margin:0 auto;padding:32px"><h1 style="text-align:center;font-size:20px;border-bottom:2px solid #1a8a18;padding-bottom:12px">SMLOUVA O PRONAJMU MOTOCYKLU</h1><p style="text-align:center;font-size:12px;color:#666">c. {{booking_number}} ze dne {{today}}</p><p>Pronajimatel: Bc. Petra Semoradova, ICO: 21874263</p><p>Najemce: {{customer_name}}, {{customer_address}}</p><p>Motocykl: {{moto_model}} ({{moto_spz}}), VIN: {{moto_vin}}</p><p>Obdobi: {{start_date}} — {{end_date}} ({{days}} dni)</p><p>Celkem: {{total_price}} Kc</p><p style="color:#b45309;font-size:11px;margin-top:24px">Toto je zalozni sablona. Plne texty smluv najdete v Dokumenty - Smluvni texty.</p></div></body></html>`
  }
  if (slug === 'handover_protocol') {
    return `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Predavaci protokol</title></head><body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a"><div style="max-width:780px;margin:0 auto;padding:32px"><h1 style="text-align:center;font-size:20px;border-bottom:2px solid #2563eb;padding-bottom:12px">PREDAVACI PROTOKOL</h1><p style="text-align:center;font-size:12px;color:#666">k rezervaci c. {{booking_number}} ze dne {{today}}</p><p>Najemce: {{customer_name}}</p><p>Motocykl: {{moto_model}} ({{moto_spz}}), VIN: {{moto_vin}}</p><p style="color:#b45309;font-size:11px;margin-top:24px">Toto je zalozni sablona. Plne texty najdete v Dokumenty - Smluvni texty.</p></div></body></html>`
  }
  if (slug === 'vop') {
    return `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Vseobecne obchodni podminky</title></head><body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a"><div style="max-width:780px;margin:0 auto;padding:32px"><h1 style="text-align:center;font-size:20px;border-bottom:2px solid #1a8a18;padding-bottom:12px">VSEOBECNE OBCHODNI PODMINKY</h1><p style="text-align:center;font-size:12px;color:#666">{{company_name}} | ICO: {{company_ico}} | {{company_address}}</p><p style="text-align:center;font-size:12px;color:#666">Platne od {{today}} k rezervaci c. {{booking_number}}</p><h3 style="font-size:13px;margin-top:24px">1. Uvodni ustanoveni</h3><p style="font-size:12px">Tyto vseobecne obchodni podminky upravuji prava a povinnosti smluvnich stran pri pronajmu motocyklu provozovanem spolecnosti {{company_name}}, ICO: {{company_ico}}, se sidlem {{company_address}}.</p><h3 style="font-size:13px">2. Predmet pronajmu</h3><p style="font-size:12px">Predmetem pronajmu je motocykl specifikovany v najemni smlouve.</p><h3 style="font-size:13px">3. Podminky pronajmu</h3><p style="font-size:12px">Najemce musi byt drzitelem platneho ridicskeho prukazu prislusne skupiny. Minimalni vek najemce je 21 let.</p><h3 style="font-size:13px">4. Cena a platebni podminky</h3><p style="font-size:12px">Cena pronajmu se ridi aktualnim cenikem. Platba je splatna pred prevzetim motocyklu.</p><h3 style="font-size:13px">5. Odpovednost za skody</h3><p style="font-size:12px">Najemce odpovida za veskere skody vznikle na motocyklu po dobu pronajmu.</p><h3 style="font-size:13px">6. Storno podminky</h3><p style="font-size:12px">Bezplatne storno je mozne do 48 hodin pred zacatkem pronajmu.</p><p style="color:#b45309;font-size:11px;margin-top:24px">Toto je zalozni sablona. Plne texty VOP najdete v Dokumenty - Smluvni texty.</p></div></body></html>`
  }
  return null
}

export function buildDocVars(booking, customer, bookingId) {
  const moto = booking.motorcycles || {}
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
    fuel_state: '', technical_state: '',
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
  const v = doc.filled_data
  return `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Dokument</title></head><body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a"><div style="max-width:780px;margin:0 auto;padding:32px"><h2>${v.company_name || 'MotoGo24'}</h2><p>Zakaznik: ${v.customer_name || '\u2014'}</p><p>Motocykl: ${v.moto_model || '\u2014'} (${v.moto_spz || ''})</p><p>Obdobi: ${v.start_date || '\u2014'} — ${v.end_date || '\u2014'} (${v.days || '\u2014'} dni)</p><p>Cena: ${v.total_price || '\u2014'} Kc</p></div></body></html>`
}
