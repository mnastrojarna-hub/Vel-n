// ===== _tests/pp_webhook_charge_flow_test.ts =====
// verify:charges (2026-11-05) — webhook-receiver nad falešným Stripe + in-memory DB (import mapa
// storno-flow-map.json, spouští storno_hotfix_test.ts): potvrzení platby rezervace / objednávky zapíše
// dorovnání z metadat PŘED potvrzením (doklady = stržená částka), opakovaná událost nic nepřičte,
// platba v jiné měně než CZK rezervaci NEpotvrdí (jen záznam + mail obsluze).
// deno-lint-ignore-file no-explicit-any
import { BID, boot, deliver, fresh, opsMails, rows, webhookStatuses, world } from './storno-harness.ts'

const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/stripe@14').startsWith('file:') } catch { return false } })()
const db = () => (globalThis as any).__STORNO_DB
const bk = () => rows('bookings')[0]
const now = () => Math.floor(Date.now() / 1000)

function piEvent(id: string, haleru: number, md: Record<string, string>, currency = 'czk') {
  return { id: `evt_${id}_${Math.random().toString(36).slice(2, 8)}`, type: 'payment_intent.succeeded', created: now(),
    data: { object: { id, object: 'payment_intent', amount: haleru, amount_received: haleru, currency, status: 'succeeded', metadata: md, customer: 'cus_1', created: now(), latest_charge: 'ch_' + id.slice(3) } } }
}
function unpaid(total: number, extra: Record<string, unknown> = {}) {
  fresh(10, { booking: { payment_status: 'unpaid', status: 'pending', total_price: total, card_rounding: 0, stripe_payment_intent_id: 'pi_r', ...extra } })
  world().addPi('pi_r', 15, { booking_id: BID, type: 'booking', due: String(total), card_rounding: String(Math.round((15 - total) * 100) / 100) }, -60)
  let confirms = 0
  db().rpcs.confirm_payment = () => { confirms++; const b = bk(); const was = b.payment_status === 'paid'; b.payment_status = 'paid'; b.status = 'reserved'; return { data: { success: true, was_already_paid: was }, error: null } }
  for (const t of ['financial_events', 'debug_log', 'invoices']) db().rows(t)
  return { confirms: () => confirms }
}

Deno.test({ name: 'charges webhook: dorovnání 7 → 15 Kč do ceny před potvrzením; opakovaná událost nic nepřičte', ignore: !MAPPED, fn: async () => {
  await boot()
  const s = unpaid(7)
  const md = { booking_id: BID, type: 'booking', due: '7', card_rounding: '8' }
  await deliver([piEvent('pi_r', 1500, md)])
  if (webhookStatuses[0] !== 200) throw new Error(`status ${webhookStatuses[0]}`)
  if (Number(bk().total_price) !== 15 || Number(bk().card_rounding) !== 8) throw new Error(`cena ${bk().total_price} / dorovnání ${bk().card_rounding}`)
  if (bk().payment_status !== 'paid' || s.confirms() !== 1) throw new Error('nepotvrzeno')
  await deliver([piEvent('pi_r', 1500, md)], 2)
  if (Number(bk().total_price) !== 15 || Number(bk().card_rounding) !== 8) throw new Error(`po opakování cena ${bk().total_price} / ${bk().card_rounding}`)
  if (!rows('debug_log').some((d: any) => d.action === 'card_rounding_applied')) throw new Error('chybí záznam card_rounding_applied')
} })

Deno.test({ name: 'charges webhook: platba v EUR rezervaci nepotvrdí (cena i stav beze změny), 200 + mail obsluze', ignore: !MAPPED, fn: async () => {
  await boot()
  const s = unpaid(1000)
  await deliver([piEvent('pi_r', 1500, { booking_id: BID, type: 'booking' }, 'eur')])
  if (webhookStatuses[0] !== 200) throw new Error(`status ${webhookStatuses[0]}`)
  if (bk().payment_status !== 'unpaid' || s.confirms() !== 0 || Number(bk().total_price) !== 1000) throw new Error('potvrzeno v cizí měně')
  if (!rows('debug_log').some((d: any) => d.action === 'non_czk_payment_ignored')) throw new Error('chybí non_czk_payment_ignored')
  if (!opsMails.some((m) => /cizí měně/.test(m.subject))) throw new Error('chybí mail obsluze')
} })

Deno.test({ name: 'charges webhook: cena změněná mezi platbou a potvrzením (Velín) → mismatch jen do logu, platba se potvrdí', ignore: !MAPPED, fn: async () => {
  await boot()
  const s = unpaid(7); bk().total_price = 100
  await deliver([piEvent('pi_r', 1500, { booking_id: BID, type: 'booking', due: '7', card_rounding: '8' })])
  if (Number(bk().total_price) !== 100 || s.confirms() !== 1) throw new Error(`cena ${bk().total_price} potvrzení ${s.confirms()}`)
  if (!rows('debug_log').some((d: any) => d.action === 'card_rounding_mismatch')) throw new Error('chybí card_rounding_mismatch')
} })

// Oprava i2 (2026-11-05): 0 Kč rezervace přes Stripe Checkout setup (jen ověření karty) — cena se mohla po vzniku session
// změnit (přecenění ve Velínu / vlastní UPDATE zákazníka přes RLS) → nepotvrdit (dřív 'paid' s cenou > 0 a nic strženo).
function setupEvent() {
  return { id: `evt_setup_${Math.random().toString(36).slice(2, 8)}`, type: 'checkout.session.completed', created: now(),
    data: { object: { id: 'cs_setup_1', object: 'checkout.session', mode: 'setup', status: 'complete', payment_status: 'no_payment_required', currency: null, amount_total: 0,
      metadata: { action: 'verify_free_booking', booking_id: BID, type: 'booking' }, payment_intent: null, customer: null, client_reference_id: BID } } }
}
Deno.test({ name: 'charges webhook (i2): setup session 0 Kč rezervace — cena mezitím 500 → NEpotvrzeno (200, záznam, mail obsluze); cena 0 → potvrzeno', ignore: !MAPPED, fn: async () => {
  await boot()
  const s = unpaid(0); bk().total_price = 500
  await deliver([setupEvent()])
  if (webhookStatuses[0] !== 200) throw new Error(`status ${webhookStatuses[0]}`)
  if (bk().payment_status !== 'unpaid' || s.confirms() !== 0) throw new Error(`potvrzeno s cenou 500: ${bk().payment_status} / ${s.confirms()}`)
  if (!rows('debug_log').some((d: any) => d.action === 'free_verify_price_changed')) throw new Error('chybí free_verify_price_changed')
  if (!opsMails.some((m) => /cena se změnila/.test(m.subject))) throw new Error(`mail obsluze ${JSON.stringify(opsMails.map((m) => m.subject))}`)
  const s2 = unpaid(0)
  await deliver([setupEvent()])
  if (bk().payment_status !== 'paid' || s2.confirms() !== 1) throw new Error(`cena 0 nepotvrzena: ${bk().payment_status} / ${s2.confirms()}`)
} })
