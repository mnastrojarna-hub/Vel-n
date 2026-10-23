// ===== _tests/gear_email_flow_test.ts =====
// CELÉ edge funkce send-booking-email / send-cancellation-email / send-email (serve() na
// náhodném portu, Supabase + Resend v paměti — fake-postgrest.ts): gear rezervace jde z gear
// šablony (web_ → základní), přílohy z gear šablony, Smlouva = gear_rental_contract, admin kopie
// česky, bez šablony gear fallback + debug_log; motorková rezervace beze změny.
import { installFakeNet, callFn, restoreFakeEnv } from './fake-postgrest.ts'

const net = installFakeNet()
// Import mimo statickou analýzu → deno test netypuje celé funkce (send-email / send-cancellation-email
// mají starší typové chyby supabase-js generik, které běh neovlivňují); pořadí = servers[i].
const fn = (name: string) => import(new URL(`../${name}/index.ts`, import.meta.url).href)
await fn('send-booking-email') // servers[0]
await fn('send-cancellation-email') // servers[1]
await fn('send-email') // servers[2]

type Row = Record<string, unknown>
function ok(c: unknown, msg: string) { if (!c) throw new Error(msg) }
function eq(a: unknown, b: unknown, msg = '') { const A = JSON.stringify(a), B = JSON.stringify(b); if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`) }
const T = { sanitizeOps: false, sanitizeResources: false }
const BID = '5b0c8f2e-1111-4222-8333-0000a1b2c3d4', MID = '7d0c8f2e-1111-4222-8333-0000deadbeef', VN = '22222222-2222-2222-2222-222222222222'
const LINES = [
  { key: 'set_rider', kind: 'set', label: 'Komplet bez bot', sizes: { helmet: 'M', jacket: 'L', pants: 'L', gloves: 'M' }, price_per_day: 490 },
  { key: 'boots', kind: 'item', label: 'Boty', sizes: { boots: '43' }, price_per_day: 400 },
]
const tpl = (slug: string, body: string, attachments: string[], subject = 'Předmět {{booking_number}} {{customer_name}}') =>
  ({ slug, name: slug, subject, body_html: body, active: true, attachments, subject_translations: {}, body_translations: {} })
const GEAR_BODY = '<p>Ahoj {{customer_name}}</p><p>{{gear_period}} ({{gear_days}}) — {{branch_name}}, {{branch_address}}</p>{{gear_items_block}}{{door_codes_block}}<p>{{total_price}} Kč</p><a href="{{docs_url}}">D</a><a href="{{manage_url}}">M</a>'

function fixtures(o: { templates?: Row[]; lang?: string; kind?: 'gear' | 'moto'; codes?: Row[] } = {}) {
  net.reset({
    bookings: [
      { id: BID, booking_kind: 'gear', status: 'reserved', payment_status: 'paid', user_id: 'u1', start_date: '2026-06-15T00:00:00+00:00',
        end_date: '2026-06-17T00:00:00+00:00', pickup_time: '09:00:00', return_time: null, total_price: 2670, gear_lines: LINES, branch_id: VN,
        helmet_size: 'M', jacket_size: 'L', pants_size: 'L', gloves_size: 'M', boots_size: '43', language: o.lang || 'cs', booking_source: 'web' },
      { id: MID, booking_kind: 'moto', moto_id: 'm1', status: 'reserved', payment_status: 'paid', user_id: 'u1', start_date: '2026-06-15T00:00:00+00:00',
        end_date: '2026-06-17T00:00:00+00:00', total_price: 5000, branch_id: 'br-mz', language: 'cs', booking_source: 'web' },
    ],
    branch_door_codes: o.codes ?? [{ booking_id: BID, code_type: 'accessories', door_code: '4821', sent_to_customer: true, withheld_reason: null, is_active: true }],
    branches: [{ id: VN, name: 'Velké Němčice', address: 'Hlavní 1', city: 'Velké Němčice', type: 'samoobslužná' }],
    gear_rental_prices: [
      { key: 'set_rider', label: 'Komplet bez bot', translations: { de: { label: 'Komplett ohne Stiefel' }, en: { label: 'Full set without boots' } } },
      { key: 'helmet', label: 'Helma', translations: { de: { label: 'Helm' }, en: { label: 'Helmet' } } },
      { key: 'jacket', label: 'Bunda', translations: { de: { label: 'Jacke' } } }, { key: 'boots', label: 'Boty', translations: { de: { label: 'Stiefel' } } },
    ],
    profiles: [{ id: 'u1', full_name: 'Jana Nováková', email: 'jana@example.com' }],
    email_templates: [
      tpl('web_booking_reserved', '<p>MOTO TEMPLATE {{motorcycle}}</p>', ['ZF']), tpl('booking_reserved', '<p>MOTO TEMPLATE</p>', ['ZF']),
      tpl('booking_cancelled', '<p>MOTO CANCEL</p>', ['Dobropis']), tpl('handover_protocol_sent', '<p>Protokol {{x}}</p>', []),
      ...(o.templates || []),
    ],
    invoices: [], message_log: [], sent_emails: [], debug_log: [], app_settings: [],
  })
  net.rpcs.detect_customer_language = () => o.lang || 'cs'
  net.rpcs._branch_gate_code = (a) => a.p_branch_id === VN ? '0937' : null
  net.rpcs._branch_locker_door_no = () => 8
}
const tplSlugs = () => net.restSelects('email_templates').map((c) => (c.query!.get('slug') || '').replace(/^eq\./, ''))
// generate-document se při neúspěchu zkouší 2× (generateDocAttachment) → unikátní slugy v pořadí
const docCalls = () => [...new Set(net.calls.filter((c) => c.kind === 'fn' && c.name === 'generate-document').map((c) => (c.body as Row).template_slug))]
const debug = (action: string) => net.rows('debug_log').filter((r) => r.action === action)
const moto = /MOTO TEMPLATE|MOTO CANCEL|Kód motorky|Motorrad-Code|Motorcycle code|motocykl/i

Deno.test({ name: 'send-booking-email gear (de, web): gear šablona, přílohy Smlouva=výbava + VOP, admin kopie česky', ...T, fn: async () => {
  fixtures({ lang: 'de', templates: [tpl('gear_booking_reserved', GEAR_BODY, ['Smlouva', 'VOP'])] })
  const r = await callFn(0, { type: 'booking_reserved', booking_id: BID, customer_email: 'jana@example.com', customer_name: 'Jana', motorcycle: '', start_date: '2026-06-15', total_price: 2670, source: 'web' })
  eq(r.status, 200, 'status')
  const [cust, admin] = net.mails()
  const h = String(cust.html)
  ok(h.includes('15.6.2026 – 17.6.2026') && h.includes('3 Tage') && h.includes('Komplett ohne Stiefel') && h.includes('Helm M, Jacke L'), 'de vars')
  ok(h.includes('Code für den Umkleideraum (Tür Nr. 8)') && h.includes('4821') && h.includes('0937'), 'locker + gate')
  ok(h.includes(`pujceni-obleceni?resume=${BID}&amp;docs=1&amp;lang=de`) || h.includes(`pujceni-obleceni?resume=${BID}&docs=1&lang=de`), 'docs_url')
  ok(!moto.test(h), 'no motorcycle template/text')
  eq(cust.subject, 'Předmět A1B2C3D4 Jana', 'subject plain')
  eq(tplSlugs().filter((s) => !s.includes('gear')), [], 'motorkové šablony se nehledají')
  eq(docCalls(), ['gear_rental_contract', 'vop'], 'Smlouva → smlouva o nájmu výbavy')
  eq(admin.to, 'info@motogo24.cz')
  ok(String(admin.subject).startsWith('[Kopie — zákazník DE] Předmět A1B2C3D4'), 'admin subject')
  const a = String(admin.html)
  ok(a.includes('3 dny') && a.includes('Kód šatny (dveře č. 8)') && a.includes('helma M, bunda L') && !a.includes('3 Tage'), 'admin copy in cs')
  eq(net.rows('message_log')[0]?.template_slug, 'web_booking_reserved', 'logged slug = type')
} })

Deno.test({ name: 'send-booking-email gear bez šablony: gear fallback (nikdy motorka) + debug_log + výchozí přílohy', ...T, fn: async () => {
  fixtures()
  await callFn(0, { type: 'door_codes', booking_id: BID, customer_email: 'jana@example.com', source: 'app' })
  const [cust, admin] = net.mails()
  ok(String(cust.subject).startsWith('Přístupové kódy — výpůjčka výbavy č. A1B2C3D4'), 'fallback subject')
  const h = String(cust.html)
  ok(h.includes('Kód šatny (dveře č. 8)') && h.includes('Postup na pobočce Velké Němčice') && !moto.test(h), 'fallback body')
  eq(debug('email_template_fallback').map((r) => (r.request_data as Row).slug), ['gear_door_codes'])
  eq(String(admin.subject), `[Kopie] ${cust.subject}`, 'cs admin copy')
  fixtures()
  await callFn(0, { type: 'booking_reserved', booking_id: BID, customer_email: 'jana@example.com', source: 'web' })
  eq(docCalls(), ['gear_rental_contract', 'vop'], 'default Smlouva + VOP')
  ok(!moto.test(String(net.mails()[0].html)), 'reserved fallback without moto')
} })

Deno.test({ name: 'send-booking-email gear: doklad o platbě (ZF+DP z gear šablony), bez vydaného kódu bez bloku kódů', ...T, fn: async () => {
  fixtures({ codes: [], templates: [tpl('gear_invoice_payment_receipt', GEAR_BODY, ['ZF', 'DP'])] })
  await callFn(0, { type: 'invoice_payment_receipt', booking_id: BID, customer_email: 'jana@example.com', source: 'web', docs_url: 'https://www.motogo24.cz/rezervace?resume=x' })
  const inv = net.calls.filter((c) => c.kind === 'fn' && c.name === 'generate-invoice').map((c) => (c.body as Row).type)
  eq(inv, ['advance', 'payment_receipt'], 'ZF + DP')
  const h = String(net.mails()[0].html)
  ok(h.includes(`/pujceni-obleceni?resume=${BID}&docs=1`) && !h.includes('/rezervace?resume'), 'gear docs link wins')
  ok(!h.includes('Kód šatny') && !h.includes('Nahrát doklady') && !moto.test(h), 'no codes, no moto docs block')
} })

Deno.test({ name: 'send-booking-email motorka: beze změny (motorková šablona, přílohy, slug)', ...T, fn: async () => {
  fixtures({ codes: [] })
  await callFn(0, { type: 'booking_reserved', booking_id: MID, customer_email: 'jan@example.com', motorcycle: 'Honda', source: 'web' })
  ok(String(net.mails()[0].html).includes('MOTO TEMPLATE Honda'), 'moto template')
  eq(tplSlugs()[0], 'web_booking_reserved')
  eq(net.restSelects('gear_rental_prices').length, 0, 'no gear lookups')
  eq(net.calls.filter((c) => c.kind === 'fn' && c.name === 'generate-invoice').map((c) => (c.body as Row).type), ['advance'])
  eq(debug('email_template_fallback').length, 0)
} })

Deno.test({ name: 'send-cancellation-email gear (en): gear šablona, důvod + vratka, admin kopie česky, slug booking_cancelled', ...T, fn: async () => {
  fixtures({ lang: 'en', templates: [tpl('gear_booking_cancelled', GEAR_BODY + '<p>{{cancellation_reason}} {{refund_amount}} Kč {{refund_percent}} %</p>', ['Dobropis'])] })
  net.rows('bookings')[0].payment_status = 'unpaid'
  await callFn(1, { booking_id: BID, customer_email: 'jana@example.com', customer_name: 'Jana', cancellation_reason: 'Stornováno zákazníkem', refund_amount: 1335, refund_percent: 50, source: 'web' })
  const [cust, admin] = net.mails()
  const h = String(cust.html)
  ok(h.includes('Cancelled by the customer') && h.includes(`${(1335).toLocaleString('cs-CZ')} Kč 50 %`) && h.includes('Full set without boots') && !moto.test(h), 'en gear cancel')
  ok(String(admin.html).includes('Stornováno zákazníkem') && String(admin.html).includes('Komplet bez bot'), 'admin cs')
  eq(tplSlugs().filter((s) => !s.includes('gear')), [], 'no moto template lookup')
  eq(net.rows('sent_emails')[0]?.template_slug, 'booking_cancelled')
  fixtures({ lang: 'cs' })
  net.rows('bookings')[0].payment_status = 'unpaid'
  await callFn(1, { booking_id: BID, customer_email: 'jana@example.com', source: 'app' })
  ok(String(net.mails()[0].subject).includes('Výpůjčka výbavy č. A1B2C3D4 je stornovaná') && !moto.test(String(net.mails()[0].html)), 'fallback')
  eq(debug('email_template_fallback').length, 1)
  fixtures()
  net.rows('bookings')[1].payment_status = 'unpaid'
  await callFn(1, { booking_id: MID, customer_email: 'jan@example.com', source: 'app' })
  ok(String(net.mails()[0].html).includes('MOTO CANCEL'), 'moto cancel unchanged')
} })

Deno.test({ name: 'send-email: handover_protocol_gear_sent bez šablony → handover_protocol_sent (+ debug_log); bez obou 404', ...T, fn: async () => {
  fixtures()
  const r = await callFn(2, { to: 'jana@example.com', template_slug: 'handover_protocol_gear_sent', template_vars: { x: 'OK' }, booking_id: BID, language: 'cs' })
  eq([r.status, r.json.success], [200, true])
  ok(String(net.mails()[0].html).includes('Protokol OK'), 'fallback template used')
  eq(debug('email_template_fallback').map((d) => (d.request_data as Row).used), ['handover_protocol_sent'])
  net.tables.email_templates = []
  eq((await callFn(2, { to: 'a@b.cz', template_slug: 'handover_protocol_gear_sent', language: 'cs' })).status, 404)
  eq((await callFn(2, { to: 'a@b.cz', template_slug: 'jina_sablona', language: 'cs' })).status, 404)
} })

// Úklid: env procesu (sdílené s dalšími testovými soubory) + servery funkcí.
Deno.test({ name: 'úklid: env + servery', ...T, fn: () => restoreFakeEnv() })
