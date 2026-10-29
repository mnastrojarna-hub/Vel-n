// ===== _tests/gear_email_fallback_flow_test.ts =====
// CELÉ edge funkce (fake-postgrest.ts) — pojistky po review EDGE-A: gear fallback pro de zákazníka
// (anglický text i proměnné, odkazy de, blok kódů jen jednou), storno fallback de + dovětek o vratce
// převodem v tykání a ve stejném jazyce, send-email loguje náhradní protokol pod vyžádaným slugem.
// Každý testový soubor běží ve vlastním isolate (globální fetch/listen se nesdílí, env ano).
import { installFakeNet, callFn, restoreFakeEnv } from './fake-postgrest.ts'

const net = installFakeNet()
const fn = (name: string) => import(new URL(`../${name}/index.ts`, import.meta.url).href)
await fn('send-booking-email') // servers[0]
await fn('send-cancellation-email') // servers[1]
await fn('send-email') // servers[2]

type Row = Record<string, unknown>
function ok(c: unknown, msg: string) { if (!c) throw new Error(msg) }
function eq(a: unknown, b: unknown, msg = '') { const A = JSON.stringify(a), B = JSON.stringify(b); if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`) }
const T = { sanitizeOps: false, sanitizeResources: false }
const BID = '5b0c8f2e-1111-4222-8333-0000a1b2c3d4', VN = '22222222-2222-2222-2222-222222222222'
const LINES = [
  { key: 'set_rider', kind: 'set', label: 'Komplet bez bot', sizes: { helmet: 'M', jacket: 'L', pants: 'L', gloves: 'M' }, price_per_day: 490 },
  { key: 'boots', kind: 'item', label: 'Boty', sizes: { boots: '43' }, price_per_day: 400 },
]
function fixtures(lang: string, templates: Row[] = []) {
  net.reset({
    bookings: [{ id: BID, booking_kind: 'gear', status: 'reserved', payment_status: 'paid', user_id: 'u1', start_date: '2026-06-15T00:00:00+00:00',
      end_date: '2026-06-17T00:00:00+00:00', pickup_time: '09:00:00', return_time: null, total_price: 2670, gear_lines: LINES, branch_id: VN,
      helmet_size: 'M', jacket_size: 'L', pants_size: 'L', gloves_size: 'M', boots_size: '43', language: lang, booking_source: 'web' }],
    branch_door_codes: [{ booking_id: BID, code_type: 'accessories', door_code: '4821', sent_to_customer: true, withheld_reason: null, is_active: true }],
    branches: [{ id: VN, name: 'Velké Němčice', address: 'Hlavní 1', city: 'Velké Němčice', type: 'samoobslužná' }],
    gear_rental_prices: [
      { key: 'set_rider', label: 'Komplet bez bot', translations: { de: { label: 'Komplett ohne Stiefel' }, en: { label: 'Full set without boots' } } },
      { key: 'boots', label: 'Boty', translations: { de: { label: 'Stiefel' }, en: { label: 'Boots' } } },
    ],
    profiles: [{ id: 'u1', full_name: 'Jana Nováková', email: 'jana@example.com' }],
    email_templates: [
      { slug: 'booking_reserved', name: 'x', subject: 'MOTO', body_html: '<p>MOTO TEMPLATE</p>', active: true, attachments: [] },
      { slug: 'booking_cancelled', name: 'x', subject: 'MOTO', body_html: '<p>MOTO CANCEL</p>', active: true, attachments: [] },
      ...templates,
    ],
    invoices: [], message_log: [], sent_emails: [], debug_log: [], app_settings: [],
  })
  net.rpcs.detect_customer_language = () => lang
  net.rpcs._branch_gate_code = (a) => a.p_branch_id === VN ? '0937' : null
  net.rpcs._branch_locker_door_no = () => 8
}
// Hlavička layoutu v jazyce zákazníka („MOTORRADVERLEIH“) je značka, ne text o motorce rezervace.
const moto = /MOTO TEMPLATE|MOTO CANCEL|Kód motorky|Motorrad-Code|motocykl|motorcycle code|your motorcycle/i
const count = (h: string, s: string) => h.split(s).length - 1

Deno.test({ name: 'send-booking-email gear fallback (de): anglický text + proměnné, odkazy de, kódy jednou, admin česky', ...T, fn: async () => {
  fixtures('de')
  const r = await callFn(0, { type: 'booking_reserved', booking_id: BID, customer_email: 'jana@example.com', customer_name: 'Jana', source: 'app' })
  eq(r.status, 200)
  const [cust, admin] = net.mails()
  const h = String(cust.html)
  ok(h.includes('3 days') && h.includes('Full set without boots') && h.includes('15/06/2026'), 'en vars')
  ok(!/Tage|Komplett|Umkleideraum|Stiefel/.test(h), 'no German variables')
  eq(count(h, '4821'), 1, 'codes block once')
  ok(h.includes('Locker room code (door no. 8)') && h.includes('0937') && !moto.test(h), 'gear codes, no moto')
  ok(h.includes('upravit-rezervaci?lang=de'), 'manage link in customer language')
  ok(String(cust.subject).startsWith('Gear rental #A1B2C3D4 confirmed') && !String(cust.subject).includes('0937'), 'subject')
  const a = String(admin.html)
  ok(a.includes('3 dny') && a.includes('Kód šatny (dveře č. 8)') && !a.includes('3 days'), 'admin copy cs')
  eq(net.rows('message_log')[0]?.template_slug, 'booking_reserved', 'logged slug = type')
} })

Deno.test({ name: 'send-cancellation-email gear fallback (de) + vratka převodem: angličtina, tykání, dobropis', ...T, fn: async () => {
  fixtures('de')
  net.rows('invoices').push({ id: 'cn1', booking_id: BID, type: 'credit_note', status: 'issued', number: 'DB-1', pdf_path: 'credit/db1.pdf' })
  net.files['documents/credit/db1.pdf'] = '%PDF-1.4 fake'
  await callFn(1, { booking_id: BID, customer_email: 'jana@example.com', customer_name: 'Jana', refund_amount: 1335, refund_percent: 50,
    skip_refund: true, manual_refund: true, source: 'web' })
  const [cust, admin] = net.mails()
  const h = String(cust.html)
  ok(h.includes('Reason: Not specified.') && h.includes('3 days') && h.includes('CZK</strong> (50 %)'), 'en fallback with en vars')
  ok(h.includes('We will return the amount by bank transfer to your account within 14 days'), 'en tykání manual note')
  ok(!/Nicht angegeben|Tage|Der Betrag|Ihr Konto|váš bankovní/.test(h) && !moto.test(h), 'no German / formal / moto text')
  eq(((cust.attachments as Row[]) || []).map((x) => x.filename), ['Dobropis-DB-1.pdf'], 'credit note attached')
  ok(String(admin.html).includes('Neuvedeno') && String(admin.html).includes('3 dny'), 'admin cs')
  eq(net.rows('debug_log').filter((r) => r.action === 'email_template_fallback').length, 1)
  fixtures('cs')
  net.rows('invoices').push({ id: 'cn2', booking_id: BID, type: 'credit_note', status: 'issued', number: 'DB-2', pdf_path: 'credit/db2.pdf' })
  net.files['documents/credit/db2.pdf'] = '%PDF-1.4 fake'
  await callFn(1, { booking_id: BID, customer_email: 'jana@example.com', refund_amount: 100, refund_percent: 50, skip_refund: true, manual_refund: true, source: 'app' })
  const c = String(net.mails()[0].html)
  ok(c.includes('Částku ti vrátíme převodem na tvůj bankovní účet do 14 dnů') && !c.includes('váš bankovní účet'), 'cs tykání note')
} })

Deno.test({ name: 'send-email: náhradní šablona protokolu se loguje pod vyžádaným slugem; constructor → 404', ...T, fn: async () => {
  fixtures('cs', [{ slug: 'handover_protocol_sent', name: 'p', subject: 'Protokol', body_html: '<p>Protokol {{x}}</p>', active: true }])
  const r = await callFn(2, { to: 'jana@example.com', template_slug: 'handover_protocol_gear_sent', template_vars: { x: 'OK' }, booking_id: BID, language: 'cs' })
  eq([r.status, r.json.success], [200, true])
  eq(net.rows('message_log')[0]?.template_slug, 'handover_protocol_gear_sent', 'message_log slug')
  eq(net.rows('sent_emails')[0]?.template_slug, 'handover_protocol_gear_sent', 'sent_emails slug')
  await callFn(2, { to: 'jana@example.com', template_slug: 'handover_protocol_sent', template_vars: { x: 'M' }, language: 'cs' })
  eq(net.rows('sent_emails')[1]?.template_slug, 'handover_protocol_sent', 'moto protocol unchanged')
  eq((await callFn(2, { to: 'a@b.cz', template_slug: 'constructor', language: 'cs' })).status, 404)
} })

Deno.test({ name: 'úklid: env + fetch + servery', ...T, fn: () => restoreFakeEnv() })
