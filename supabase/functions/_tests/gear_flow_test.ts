// ===== _tests/gear_flow_test.ts =====
// EDGE-B (2026-10-23) flow testy CELÝCH handlerů (submit-handover-protocol, generate-invoice)
// pro výpůjčku JEN výbavy + motorkovou regresi. Potřebují import mapu (serve zachytí handler,
// supabase-js = LooseDb):
//   deno test --allow-all --no-check --import-map=supabase/functions/_tests/gear-flow-map.json supabase/functions/_tests/gear_flow_test.ts
// Bez import mapy (běžné `deno test _tests/`) se přeskočí (ignore).
import { LooseDb, stubFetch } from './gear-fake.ts'

function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
function ok(c: unknown, msg = '') { if (!c) throw new Error(`assert failed ${msg}`) }
type Row = Record<string, unknown>
type Handler = (req: Request) => Response | Promise<Response>

const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/@supabase/supabase-js@2').startsWith('file:') } catch { return false } })()
const SVC = 'svc-test-key'
// env jen při běhu s import mapou (samostatně) — ve společném běhu by ovlivnil ostatní testovací soubory
if (MAPPED) {
  Deno.env.set('SUPABASE_URL', 'https://fake.supabase.test')
  Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', SVC)
}
const g = globalThis as unknown as { __gearHandlers?: Handler[]; __gearFakeDb?: unknown }
const handlers: Record<string, Handler> = {}
async function handlerOf(path: string): Promise<Handler> {
  if (handlers[path]) return handlers[path]
  const before = (g.__gearHandlers || []).length
  await import(path)
  const h = (g.__gearHandlers || [])[before]
  if (!h) throw new Error(`handler ${path} se nezaregistroval`)
  return (handlers[path] = h)
}

const BID = '11111111-2222-3333-4444-555566667777'
const DEV = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
const TOKEN = 'ffffffff-1111-2222-3333-444444444444'
const SIG = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='
const PRICES = [
  { key: 'helmet', kind: 'item', label: 'Helma', sizes: ['XS', 'S', 'M', 'L', 'XL', '2XL', '3XL'], is_active: true },
  { key: 'jacket', kind: 'item', label: 'Bunda', sizes: ['S', 'M', 'L', 'XL', '2XL', '3XL', '4XL', '5XL', '6XL'], is_active: true },
]
function protocolDb(o: { kind?: 'gear' | 'moto'; branchType?: string; codeType?: string; codeBranch?: string; helmet?: string | null } = {}) {
  const kind = o.kind ?? 'gear'
  const db = new LooseDb({
    bookings: [{ id: BID, booking_kind: kind, status: 'reserved', user_id: 'u1', branch_id: 'br-vn', moto_id: kind === 'gear' ? null : 'm1',
      start_date: '2026-11-10T00:00:00+00:00', end_date: '2026-11-12T00:00:00+00:00', pickup_time: '12:00:00', return_time: null,
      handover_protocol_filled_at: null, helmet_size: o.helmet === undefined ? 'M' : o.helmet, jacket_size: 'L', modification_history: [],
      gear_lines: kind === 'gear' ? [{ key: 'helmet', kind: 'item', label: 'Helma', includes: ['helmet'], sizes: { helmet: 'M' }, price_per_day: 200 },
        { key: 'jacket', kind: 'item', label: 'Bunda', includes: ['jacket'], sizes: { jacket: 'L' }, price_per_day: 200 }] : null,
      gear_per_day: kind === 'gear' ? 400 : null,
      motorcycles: kind === 'gear' ? null : { model: 'BMW R 1250 GS', spz: '1AB 2345', vin: 'VIN123', mileage: 10000, tracking_unit: 'km', branch_id: 'br-vn', license_required: 'A', branches: { type: 'samoobslužná' } } }],
    branches: [{ id: 'br-vn', type: o.branchType ?? 'samoobslužná', name: 'MotoGo24 Velké Němčice', address: 'Hlavní 1', city: 'Velké Němčice' }],
    branch_door_codes: [{ id: 'c1', booking_id: BID, code_type: o.codeType ?? (kind === 'gear' ? 'accessories' : 'motorcycle'), branch_id: o.codeBranch ?? 'br-vn', sent_to_customer: true, is_active: true }],
    profiles: [{ id: 'u1', full_name: 'Jana Nováková', email: 'jana@example.com' }],
    gear_rental_prices: PRICES, accessory_types: [], generated_documents: [], debug_log: [],
  })
  db.rpcs.kiosk_device_branch = (a) => ({ data: a.p_device_id === DEV ? 'br-vn' : null, error: null })
  db.rpcs._kiosk_release_at = () => ({ data: null, error: null })
  db.rpcs.detect_customer_language = () => ({ data: 'cs', error: null })
  db.rpcs._handover_pickup_km = () => ({ data: 10500, error: null })
  return db
}
async function sign(db: LooseDb, form: Row, mailStatus: Record<string, number> = {}) {
  g.__gearFakeDb = db
  const h = await handlerOf('../submit-handover-protocol/index.ts')
  const f = stubFetch((url, body) => {
    if (url.endsWith('/render-pdf')) return new Response('no pdf', { status: 500 })
    const st = mailStatus[String(body?.template_slug)] ?? 200
    return new Response(JSON.stringify({ success: st === 200 }), { status: st })
  })
  try {
    const res = await h(new Request('http://x/submit', { method: 'POST', body: JSON.stringify({ booking_id: BID, mode: 'kiosk', device_id: DEV,
      device_token: TOKEN, signature: SIG, signed_at: new Date().toISOString(), lang: 'cs', form }) }))
    return { status: res.status, json: await res.json(), mails: f.calls.filter((c) => c.url.endsWith('/send-email')), db }
  } finally { f.restore() }
}
const GEAR_FORM = { accessories: [{ field: 'helmet_size', key: 'helmet', who: 'rider', size: 'L', checked: true }, { field: 'jacket_size', key: 'jacket', who: 'rider', size: 'L', checked: true }] }

Deno.test({ name: 'flow protokol gear (kiosk): kód šatny, pobočka z rezervace, dokument bez motorky, velikost i do gear_lines, gear e-mail', ignore: !MAPPED, fn: async () => {
  const r = await sign(protocolDb(), GEAR_FORM)
  eq([r.status, r.json.success, r.json.already_filled], [200, true, false], JSON.stringify(r.json))
  const b = r.db.rows('bookings')[0]
  ok(b.handover_protocol_filled_at, 'claim')
  eq(b.helmet_size, 'L'); eq((b.gear_lines as Row[])[0].sizes, { helmet: 'L' })
  eq(r.db.callsOf('rpc', '_handover_pickup_km').length, 0, 'bez km')
  const doc = r.db.rows('generated_documents')[0]
  const fd = doc.filled_data as Row
  eq([fd._gear_only, fd._doc_type, fd._mileage], [true, 'handover_protocol', null])
  const html = String(fd._signed_html)
  ok(html.includes('ZAPŮJČENÁ VÝBAVA') && html.includes('MotoGo24 Velké Němčice') && !html.includes('VIN') && !html.includes('Stav km'), 'gear dokument')
  eq(r.mails.map((m) => m.body?.template_slug), ['handover_protocol_gear_sent'])
  const tv = r.mails[0].body?.template_vars as Row
  ok(String(tv.gear_items_block).includes('Helma: <strong>L</strong>') && tv.branch_name === 'MotoGo24 Velké Němčice' && tv.gear_days === '3 dny')
  eq(r.json.email_sent, true)
} })

Deno.test({ name: 'flow protokol gear: chybí gear šablona (404) → handover_protocol_sent', ignore: !MAPPED, fn: async () => {
  const r = await sign(protocolDb(), GEAR_FORM, { handover_protocol_gear_sent: 404 })
  eq(r.mails.map((m) => m.body?.template_slug), ['handover_protocol_gear_sent', 'handover_protocol_sent'])
  eq(r.json.email_sent, true)
} })

Deno.test({ name: 'flow protokol gear: identita jen kódem šatny téže pobočky; obslužná pobočka = not_self_service', ignore: !MAPPED, fn: async () => {
  eq((await sign(protocolDb({ codeType: 'motorcycle' }), GEAR_FORM)).status, 403, 'gear s kódem motorky')
  eq((await sign(protocolDb({ codeBranch: 'br-other' }), GEAR_FORM)).status, 403, 'kód jiné pobočky')
  const st = await sign(protocolDb({ branchType: 'obslužná' }), GEAR_FORM)
  eq([st.status, st.json.error], [400, 'not_self_service'])
  eq((await sign(protocolDb({ kind: 'moto', codeType: 'accessories' }), {})).status, 403, 'motorka s kódem šatny (beze změny)')
} })

Deno.test({ name: 'flow protokol gear: výpadek DB při čtení pobočky = 500 (kiosk podpis zopakuje), nic se nezapíše', ignore: !MAPPED, fn: async () => {
  const db = protocolDb()
  db.failSelect = (t) => t === 'branches' ? { code: '57014', message: 'timeout' } : null
  const r = await sign(db, GEAR_FORM)
  eq(r.status, 500)
  eq([db.rows('bookings')[0].handover_protocol_filled_at, db.rows('generated_documents').length], [null, 0])
} })

Deno.test({ name: 'flow protokol gear: odebrání posledního kusu se nezapíše (rezervace beze změny)', ignore: !MAPPED, fn: async () => {
  const db = protocolDb({ helmet: null })
  const r = await sign(db, { accessories: [{ field: 'jacket_size', key: 'jacket', who: 'rider', size: 'L', checked: false }] })
  eq(r.status, 200)
  eq(db.rows('bookings')[0].jacket_size, 'L')
  ok(!String((db.rows('generated_documents')[0].filled_data as Row)._signed_html).includes('odebrána'), 'bez poznámky o odebrání')
} })

Deno.test({ name: 'flow protokol MOTO regrese: kód motorky, km z RPC, motorkový dokument a šablona', ignore: !MAPPED, fn: async () => {
  const r = await sign(protocolDb({ kind: 'moto' }), {})
  eq([r.status, r.json.success], [200, true], JSON.stringify(r.json))
  eq(r.db.callsOf('rpc', '_handover_pickup_km').length, 1)
  const fd = r.db.rows('generated_documents')[0].filled_data as Row
  eq([fd._gear_only, fd._mileage], [undefined, 10500])
  ok(String(fd._signed_html).includes('BMW R 1250 GS') && String(fd._signed_html).includes('VIN123'))
  eq(r.db.rows('bookings')[0].mileage_start, 10500)
  eq(r.mails.map((m) => m.body?.template_slug), ['handover_protocol_sent'])
  eq((r.mails[0].body?.template_vars as Row).moto, 'BMW R 1250 GS (1AB 2345)')
} })

// ── generate-invoice (ZF) ────────────────────────────────────────────────────
function invoiceDb(kind: 'gear' | 'moto') {
  const db = new LooseDb({
    bookings: [{ id: BID, booking_kind: kind, user_id: 'u1', moto_id: kind === 'gear' ? null : 'm1', total_price: kind === 'gear' ? 2170 : 3000,
      discount_amount: kind === 'gear' ? 500 : 0, delivery_fee: 0, card_rounding: 0, start_date: '2026-11-10T00:00:00+00:00', end_date: '2026-11-12T00:00:00+00:00',
      gear_per_day: kind === 'gear' ? 890 : null, stripe_payment_intent_id: 'pi_1',
      gear_lines: kind === 'gear' ? [{ key: 'set_rider', kind: 'set', label: 'Komplet bez bot', includes: ['helmet', 'jacket', 'pants', 'gloves'],
        sizes: { helmet: 'M', jacket: 'L', pants: 'L', gloves: 'M' }, price_per_day: 490 }, { key: 'boots', kind: 'item', label: 'Boty', includes: ['boots'], sizes: { boots: '43' }, price_per_day: 400 }] : null,
      motorcycles: kind === 'gear' ? null : { model: 'BMW R 1250 GS', spz: '1AB 2345', price_mon: 1000, price_tue: 1000, price_wed: 1000, price_thu: 1000, price_fri: 1000, price_sat: 1000, price_sun: 1000 },
      profiles: { id: 'u1', full_name: 'Jana Nováková', email: 'jana@example.com' } }],
    booking_extras: [], booking_discounts: kind === 'gear' ? [{ booking_id: BID, kind: 'voucher', code: 'DAREK500', amount: 500 }] : [],
    invoices: [], payment_methods: [], app_settings: [], debug_log: [],
  })
  db.rpcs.next_document_number = () => ({ data: 'ZF-2026-0042', error: null })
  db.rpcs.detect_customer_language = () => ({ data: 'cs', error: null })
  return db
}
async function invoice(kind: 'gear' | 'moto') {
  const db = invoiceDb(kind)
  g.__gearFakeDb = db
  const h = await handlerOf('../generate-invoice/index.ts')
  const res = await h(new Request('http://x/gi', { method: 'POST', headers: { Authorization: `Bearer ${SVC}` },
    body: JSON.stringify({ type: 'proforma', booking_id: BID, send_email: false }) }))
  return { status: res.status, json: await res.json(), inv: db.rows('invoices')[0], db }
}

Deno.test({ name: 'flow ZF gear: řádky výbavy × dny, poukaz, bez motorky; součet = cena', ignore: !MAPPED, fn: async () => {
  const r = await invoice('gear')
  eq([r.status, r.json.success], [200, true], JSON.stringify(r.json))
  const items = r.inv.items as Array<{ description: string; qty: number; unit_price: number }>
  eq(items.map((i) => [i.description.split(' — ')[0], i.qty, i.unit_price]), [
    ['Půjčení výbavy: Komplet bez bot (helma M, bunda L, kalhoty L, rukavice M)', 3, 490],
    ['Půjčení výbavy: Boty (43)', 3, 400],
    ['Voucher (DAREK500)', 1, -500],
  ])
  eq(r.inv.total, 2170)
  ok(!items.some((i) => /motork|Pronájem/i.test(i.description)))
} })

Deno.test({ name: 'flow ZF MOTO regrese: řádek pronájmu motorky beze změny', ignore: !MAPPED, fn: async () => {
  const r = await invoice('moto')
  const items = r.inv.items as Array<{ description: string; qty: number; unit_price: number }>
  eq(items.map((i) => [i.description, i.qty, i.unit_price]), [['Pronájem BMW R 1250 GS (1AB 2345) — 10. 11. 2026 – 12. 11. 2026', 2, 1500]])
  eq(r.inv.total, 3000)
} })
