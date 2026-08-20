export const TABS = ['Detail', 'Kalendář motorky', 'Dokumenty', 'Platby', 'Reklamace']

export const ACTIONS = {
  pending: [
    { label: 'Potvrdit', status: 'reserved', green: true },
    { label: 'Zrušit', status: 'cancelled', danger: true },
  ],
  reserved: [
    { label: 'Zrušit', status: 'cancelled', danger: true },
  ],
  active: [
    { label: 'Přijmout zpět', status: 'completed', green: true },
  ],
  completed_sos_replacement: [
    { label: 'Reaktivovat', status: 'active', green: true },
  ],
  // Obnovení zrušené rezervace → Čeká na platbu (pending) + Nezaplaceno + restored_at
  // (marker: cron auto_cancel_expired_pending obnovené rezervace neruší). Tlačítko se
  // zobrazí jen když termín není v minulosti (filtr v BookingDetail); kolizi na motorce
  // kontroluje handleRestore těsně před uložením.
  cancelled: [
    { label: 'Obnovit', status: 'restored', green: true, restore: true },
  ],
}

export const CANCEL_REASONS = [
  { value: 'customer_app', label: 'Zrušeno zákazníkem v aplikaci' },
  { value: 'customer_web', label: 'Zrušeno zákazníkem na webu' },
  { value: 'velin', label: 'Zrušeno ve Velínu' },
  { value: 'admin', label: 'Zrušeno administrátorem (vlastní důvod)' },
  { value: 'unpaid_4h', label: 'Zrušeno pro nezaplacení po 4h' },
  { value: 'unpaid_auto', label: 'Automaticky zrušeno pro nezaplacení' },
]

export const CANCEL_SOURCE_LABELS = Object.fromEntries(CANCEL_REASONS.map(r => [r.value, r.label]))

export const STATUS_LABELS = {
  pending: 'Čeká na platbu', reserved: 'Nadcházející', active: 'Aktivní',
  completed: 'Dokončená', cancelled: 'Zrušená', upcoming: 'Nadcházející', completed_sos: 'Dokončeno SOS'
}

export function describeModification(fromStart, fromEnd, toStart, toEnd) {
  const fs = new Date(fromStart); fs.setHours(0,0,0,0)
  const fe = new Date(fromEnd); fe.setHours(0,0,0,0)
  const ts = new Date(toStart); ts.setHours(0,0,0,0)
  const te = new Date(toEnd); te.setHours(0,0,0,0)
  const startDelta = Math.round((ts - fs) / 86400000)
  const endDelta = Math.round((te - fe) / 86400000)
  const origDays = Math.max(1, Math.round((fe - fs) / 86400000) + 1)
  const newDays = Math.max(1, Math.round((te - ts) / 86400000) + 1)
  const durationDelta = newDays - origDays

  const parts = []
  if (startDelta < 0) parts.push(`začátek dříve o ${Math.abs(startDelta)} d`)
  else if (startDelta > 0) parts.push(`začátek později o ${startDelta} d`)
  if (endDelta > 0) parts.push(`konec později o ${endDelta} d`)
  else if (endDelta < 0) parts.push(`konec dříve o ${Math.abs(endDelta)} d`)

  let type, color, bg
  if (durationDelta > 0) { type = `prodlouženo o ${durationDelta} d`; color = '#2563eb'; bg = '#dbeafe' }
  else if (durationDelta < 0) { type = `zkráceno o ${Math.abs(durationDelta)} d`; color = '#dc2626'; bg = '#fee2e2' }
  else if (startDelta !== 0 || endDelta !== 0) { type = 'přesunuto'; color = '#92400e'; bg = '#fef3c7' }
  else { type = 'beze změny'; color = '#1a2e22'; bg = '#f1faf7' }

  const detail = parts.length > 0 ? parts.join(', ') : type
  return { type, detail, parts, durationDelta, startDelta, endDelta, origDays, newDays, color, bg }
}

export function fmtDT(iso) {
  if (!iso) return '—'
  return new Date(iso).toLocaleString('cs-CZ')
}

// Jednotné labely zdroje úpravy — sdílí detail rezervace i Dashboard.
export const MOD_SOURCE_LABELS = {
  web_customer: 'zákazník (web)', app_customer: 'zákazník (app)', app: 'zákazník (app)',
  customer: 'zákazník', ai_agent: 'AI agent', velin: 'Velín', admin: 'Velín',
  system: 'systém', stripe_webhook: 'doplatek (Stripe)',
}

const GEAR_CHANGE_LABELS = {
  helmet: 'Helma', jacket: 'Bunda', pants: 'Kalhoty', boots: 'Boty', gloves: 'Rukavice',
  passenger_helmet: 'Helma spolujezdce', passenger_jacket: 'Bunda spolujezdce',
  passenger_pants: 'Kalhoty spolujezdce', passenger_boots: 'Boty spolujezdce',
  passenger_gloves: 'Rukavice spolujezdce',
}

// DB hodnoty metod nejsou jednotné: pobočku značí 'store'/'pickup'/'branch'/
// 'rental'/'pickup_at_rental'/'return_to_rental'/NULL, adresu jen 'delivery'.
// Přejmenování synonyma (např. store → pickup z webové editace) NENÍ změna místa.
const _locKind = m => m === 'delivery' ? 'delivery' : 'branch'
const _locLbl = m => _locKind(m) === 'delivery' ? 'přistavení na adresu' : 'na pobočce'

const _histTime = t => t ? String(t).slice(0, 5) : null
const _histDate = d => d ? new Date(d).toLocaleDateString('cs-CZ') : '—'
const _isUuid = s => typeof s === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-/i.test(s)

// Popíše JEDEN záznam modification_history vč. změn času, motorky, místa a výbavy.
// Vrací { typeLabel, color, bg, changes: [text], sourceLabel, dateChanged }.
// Záznamy zapisují: RPC _apply_booking_changes_core, appka, Velín modaly a
// DB trigger track_booking_content_changes (auto:true) — klíče se liší podle
// zapisovatele, proto se každá dvojice from/to porovnává (core píše i nezměněné).
export function describeHistoryEntry(h) {
  const dm = describeModification(h.from_start, h.from_end, h.to_start, h.to_end)
  const dateChanged = dm.startDelta !== 0 || dm.endDelta !== 0
  const changes = []
  if (dateChanged) changes.push(`termín ${_histDate(h.from_start)} – ${_histDate(h.from_end)} → ${_histDate(h.to_start)} – ${_histDate(h.to_end)} (${dm.detail})`)

  const fpt = _histTime(h.from_pickup_time), tpt = _histTime(h.to_pickup_time)
  const pickupTimeChanged = tpt && fpt !== tpt
  if (pickupTimeChanged) changes.push(`čas vyzvednutí ${fpt || '—'} → ${tpt}`)
  const frt = _histTime(h.from_return_time), trt = _histTime(h.to_return_time)
  const returnTimeChanged = trt && frt !== trt
  if (returnTimeChanged) changes.push(`čas vrácení ${frt || '—'} → ${trt}`)

  const motoChanged = (h.from_moto && h.to_moto && String(h.from_moto) !== String(h.to_moto))
    || (h.from_moto_id && h.to_moto_id && h.from_moto_id !== h.to_moto_id) || h.moto_changed
  if (motoChanged) {
    if (h.from_moto && h.to_moto && !_isUuid(h.from_moto) && !_isUuid(h.to_moto)) changes.push(`motorka ${h.from_moto} → ${h.to_moto}`)
    else changes.push('výměna motorky')
  }

  if (h.to_pickup_method && _locKind(h.to_pickup_method) !== _locKind(h.from_pickup_method)) changes.push(`vyzvednutí: ${_locLbl(h.from_pickup_method)} → ${_locLbl(h.to_pickup_method)}`)
  if (h.to_pickup_address && h.to_pickup_address !== h.from_pickup_address) changes.push(`adresa přistavení: ${h.to_pickup_address}`)
  if (h.to_return_method && _locKind(h.to_return_method) !== _locKind(h.from_return_method)) changes.push(`vrácení: ${_locLbl(h.from_return_method)} → ${_locLbl(h.to_return_method)}`)
  if (h.to_return_address && h.to_return_address !== h.from_return_address) changes.push(`adresa vrácení: ${h.to_return_address}`)

  const gear = h.gear_changes && typeof h.gear_changes === 'object' ? h.gear_changes : null
  const gearChanged = gear && Object.keys(gear).length > 0
  if (gearChanged) {
    const parts = Object.entries(gear).map(([k, v]) =>
      `${GEAR_CHANGE_LABELS[k] || k} ${v?.from || '—'} → ${v?.to || 'odebráno'}`)
    changes.push(`výbava: ${parts.join(', ')}`)
  }

  const diff = Number(h.price_diff ?? h.net_diff ?? NaN)
  if (Number.isFinite(diff) && diff !== 0) changes.push(diff > 0 ? `doplatek +${Math.abs(diff).toLocaleString('cs-CZ')} Kč` : `vratka −${Math.abs(diff).toLocaleString('cs-CZ')} Kč`)

  let typeLabel, color, bg
  if (dateChanged) { typeLabel = dm.type; color = dm.color; bg = dm.bg }
  else if (motoChanged) { typeLabel = 'výměna motorky'; color = '#7c3aed'; bg = '#ede9fe' }
  else if (pickupTimeChanged || returnTimeChanged) { typeLabel = 'změna času'; color = '#d97706'; bg = '#fef3c7' }
  else if (gearChanged) { typeLabel = 'změna výbavy'; color = '#0891b2'; bg = '#cffafe' }
  else if (changes.length > 0) { typeLabel = 'změna místa'; color = '#0891b2'; bg = '#cffafe' }
  else { typeLabel = 'upraveno'; color = '#4a5a52'; bg = '#f1faf7' }
  if (changes.length === 0) changes.push('úprava rezervace')

  return { typeLabel, color, bg, changes, dateChanged, sourceLabel: MOD_SOURCE_LABELS[h.source] || h.source || '—' }
}

const PAYMENT_METHOD_LABELS = {
  card: { label: 'Platební karta', icon: '💳', tone: '#2563eb' },
  stripe: { label: 'Online (Stripe)', icon: '💳', tone: '#2563eb' },
  google_pay: { label: 'Google Pay', icon: '🟢', tone: '#16a34a' },
  apple_pay: { label: 'Apple Pay', icon: '🍎', tone: '#1a2e22' },
  klarna: { label: 'Klarna', icon: '💗', tone: '#db2777' },
  paypal: { label: 'PayPal', icon: '🅿️', tone: '#1e3a8a' },
  bank_transfer: { label: 'Bankovní převod', icon: '🏦', tone: '#1a8a18' },
  wire: { label: 'Bankovní převod', icon: '🏦', tone: '#1a8a18' },
  qr: { label: 'QR platba', icon: '🔳', tone: '#1a8a18' },
  cash: { label: 'Hotově', icon: '💵', tone: '#1a8a18' },
  crypto: { label: 'Kryptoměna', icon: '🪙', tone: '#d97706' },
  voucher: { label: 'Dárkový poukaz', icon: '🎁', tone: '#7c3aed' },
}

// Způsoby platby nabízené při ručním potvrzení platby ve Velínu (QR, převod, hotově…).
export const MANUAL_PAYMENT_METHODS = [
  { value: 'bank_transfer', label: 'Bankovní převod' },
  { value: 'qr', label: 'QR platba' },
  { value: 'cash', label: 'Hotově' },
  { value: 'crypto', label: 'Kryptoměna' },
  { value: 'card', label: 'Platební karta (na místě)' },
  { value: 'voucher', label: 'Dárkový poukaz' },
]

export function paymentMethodInfo(method) {
  if (!method) return { label: '—', icon: '', tone: '#0f1a14' }
  const key = String(method).toLowerCase().trim()
  return PAYMENT_METHOD_LABELS[key] || { label: method, icon: '💳', tone: '#0f1a14' }
}

// Jednotné odvození stavu platby pro celý Velín. Reflektuje realitu životního cyklu peněz:
//  - 'paid'           → Zaplaceno (peníze u nás)
//  - storno zaplacené rezervace, ale Stripe ještě nepotvrdil vrácení → Čeká na vrácení
//    (buď explicitní enum 'refund_pending', nebo odvozeně paid + status='cancelled')
//  - 'partial_refund' → Částečně vráceno (např. 50 % při zkrácení)
//  - 'refunded'       → Vráceno (Stripe potvrdil plné vrácení)
//  - jinak            → Nezaplaceno
// Klíče odpovídají hodnotám enumu payment_status (+ pseudo 'refund_pending' z odvození),
// takže je lze použít i pro filtry (PAYMENT_STATUS_FILTER_OPTIONS).
export function paymentStatusInfo(booking) {
  const ps = booking?.payment_status
  const st = booking?.status
  if (ps === 'refunded')
    return { key: 'refunded', label: 'Vráceno', icon: '↩️', color: '#475569', bg: '#e2e8f0' }
  if (ps === 'partial_refund')
    return { key: 'partial_refund', label: 'Částečně vráceno', icon: '↩️', color: '#c2410c', bg: '#ffedd5' }
  if (ps === 'refund_pending')
    return { key: 'refund_pending', label: 'Čeká na vrácení', icon: '⏳', color: '#b45309', bg: '#fef3c7' }
  // Odvozený mezistav: zaplacená rezervace byla stornována, ale refund ještě
  // neproběhl (Stripe nepotvrdil) → peníze jsou pořád u nás, čekáme na vrácení.
  if (ps === 'paid' && st === 'cancelled')
    return { key: 'refund_pending', label: 'Čeká na vrácení', icon: '⏳', color: '#b45309', bg: '#fef3c7' }
  if (ps === 'paid' && st !== 'pending')
    return { key: 'paid', label: 'Zaplaceno', icon: '✅', color: '#1a8a18', bg: '#dcfce7' }
  return { key: 'unpaid', label: 'Nezaplaceno', icon: '⚠️', color: '#dc2626', bg: '#fee2e2' }
}

// Volby filtru „Platba" v seznamu rezervací. Hodnoty = enum payment_status.
export const PAYMENT_STATUS_FILTER_OPTIONS = [
  { value: 'paid', label: 'Zaplaceno' },
  { value: 'refund_pending', label: 'Čeká na vrácení' },
  { value: 'partial_refund', label: 'Částečně vráceno' },
  { value: 'refunded', label: 'Vráceno' },
  { value: 'unpaid', label: 'Nezaplaceno' },
]

// Stripe dashboard link pro PaymentIntent (jen test/live; admin si v dashboardu vybere prostředí)
export function stripePaymentIntentUrl(piId) {
  if (!piId) return null
  return `https://dashboard.stripe.com/payments/${piId}`
}

// Stripe dashboard link pro Refund
export function stripeRefundUrl(refundId) {
  if (!refundId) return null
  return `https://dashboard.stripe.com/refunds/${refundId}`
}

// Krátký label karty: „Visa **** 4242". Bezpečné pro chybějící hodnoty.
export function cardLabel(brand, last4) {
  if (!brand && !last4) return null
  const b = brand ? String(brand).toUpperCase() : 'CARD'
  const l4 = last4 || '****'
  return `${b} **** ${l4}`
}

// Detekuje, zda byla skutečně objednána výbava spolujezdce.
// Sám fakt, že je v `bookings` vyplněna `passenger_*_size`, neznamená objednávku
// (může jít o pozůstatek/auto-vyplnění). Spolehlivý signál je položka v
// `booking_extras` obsahující slovo „spolujez" / „passenger" v názvu, nebo
// alespoň 2 vyplněné velikosti (= reálná sada).
export function hasPassengerGearOrdered(booking, bookingExtras) {
  const fromExtras = (bookingExtras || []).some(e => {
    const n = (e?.name || e?.extras_catalog?.name || '').toLowerCase()
    return n.includes('spolujez') || n.includes('passenger')
  })
  if (fromExtras) return true
  const sizes = ['passenger_helmet_size', 'passenger_jacket_size', 'passenger_pants_size', 'passenger_boots_size', 'passenger_gloves_size']
    .map(k => booking?.[k]).filter(Boolean)
  return sizes.length >= 2
}

export function calcPriceFromDayPrices(dayPrices, startDate, endDate) {
  if (!dayPrices || !startDate || !endDate) return null
  const dayMap = ['price_sun', 'price_mon', 'price_tue', 'price_wed', 'price_thu', 'price_fri', 'price_sat']
  let total = 0
  const s = new Date(startDate); s.setHours(0,0,0,0)
  const e = new Date(endDate); e.setHours(0,0,0,0)
  const d = new Date(s)
  while (d <= e) {
    const key = dayMap[d.getDay()]
    total += Number(dayPrices[key] || 0)
    d.setDate(d.getDate() + 1)
  }
  return total || null
}
