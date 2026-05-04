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

const PAYMENT_METHOD_LABELS = {
  card: { label: 'Platební karta', icon: '💳', tone: '#2563eb' },
  stripe: { label: 'Online (Stripe)', icon: '💳', tone: '#2563eb' },
  google_pay: { label: 'Google Pay', icon: '🟢', tone: '#16a34a' },
  apple_pay: { label: 'Apple Pay', icon: '🍎', tone: '#1a2e22' },
  klarna: { label: 'Klarna', icon: '💗', tone: '#db2777' },
  paypal: { label: 'PayPal', icon: '🅿️', tone: '#1e3a8a' },
  bank_transfer: { label: 'Bankovní převod', icon: '🏦', tone: '#1a8a18' },
  wire: { label: 'Bankovní převod', icon: '🏦', tone: '#1a8a18' },
  cash: { label: 'Hotově', icon: '💵', tone: '#1a8a18' },
  voucher: { label: 'Dárkový poukaz', icon: '🎁', tone: '#7c3aed' },
}

export function paymentMethodInfo(method) {
  if (!method) return { label: '—', icon: '', tone: '#0f1a14' }
  const key = String(method).toLowerCase().trim()
  return PAYMENT_METHOD_LABELS[key] || { label: method, icon: '💳', tone: '#0f1a14' }
}

// Stripe dashboard link pro PaymentIntent (jen test/live; admin si v dashboardu vybere prostředí)
export function stripePaymentIntentUrl(piId) {
  if (!piId) return null
  return `https://dashboard.stripe.com/payments/${piId}`
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
