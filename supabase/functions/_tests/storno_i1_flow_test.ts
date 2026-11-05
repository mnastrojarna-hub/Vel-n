// ===== _tests/storno_i1_flow_test.ts =====
// Oprava i1 (2026-11-05) po adversariální verifikaci sloučení hotfixu storna s vratkou z více plateb:
//  A1 dovrácení staré hlavní vratky, jejíž zbytek už obsluha vrátila vědomě (3 cesty) → nikdy podruhé,
//  A2 zámek po zabitém isolatu (všechna volání do 60 s) → mail obsluze, webhook 503 → po vypršení zámku dovráceno,
//  A3/A4/A21 Stripe search padá → vratka obsluhy/služby selže NAPEVNO (nic z doplatku, žádné 'refunded'), retry projde,
//  A5 search padne jen u zbytku → partial_refund (ne refunded), další volání služby dovrátí přesně,
//  A7 zkrácení + storno do 15 min na stejnou částku → storno vratka proběhne (dedup čerstvého dobropisu jen mimo storno),
//  A8 souběžný dispatch téže vratky zákazníka s unikátním indexem dobropisů → jeden dobropis, bez mailu „nevystavil“,
//  webhook: payment_intent.succeeded bez metadat u částečně vrácené rezervace ji nepřepne na 'paid'.
// Na verzi před opravou i1 tyto testy PADAJÍ. Spouští storno_hotfix_test.ts v podprocesu s import mapou.
// deno-lint-ignore-file no-explicit-any
import { BID, EMAIL, advance, bk, boot, call, cnKc, creditNotes, customerMails, deliver, fresh, mails, opsMails, refundedKc, rows,
  setUniqueCnIndex, webhookStatuses, world, type ExtraPi } from './storno-harness.ts'
import { velinCancel, velinConfirm } from './storno-dispatch.ts'

const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/stripe@14').startsWith('file:') } catch { return false } })()
if (MAPPED) await boot()

const TWO: ExtraPi[] = [{ id: 'pi_ext1', czk: 115 }] // 3115 Kč, uložená platba pi_ext1
const SB = 'https://fake.supabase.test'

function money(label: string, refunded: number, cn = refunded) {
  const r = refundedKc(), c = cnKc()
  if (r !== refunded || c !== cn) throw new Error(`${label}: vráceno ${r} (čekáno ${refunded}), dobropisy ${c} (čekáno ${cn}), stripe ${JSON.stringify(world().creates.map((x) => x.result))}`)
}
const pr = (amount?: number, as: 'service' | 'admin' = 'admin', reason = 'cancellation') =>
  call('process-refund', { booking_id: BID, reason, ...(amount ? { amount } : {}) }, as)
const sce = (amount: number) => call('send-cancellation-email', { booking_id: BID, customer_email: EMAIL, cancellation_reason: 'Storno (Velín)',
  cancelled_by_source: 'velin', source: 'app', refund_amount: amount, refund_percent: Math.round(amount / 31.15) }, 'admin')
const velinUpd = () => Object.assign(bk(), { status: 'cancelled', cancelled_at: new Date().toISOString(), payment_status: 'refund_pending',
  cancelled_by_source: 'velin', cancellation_reason: 'Storno (Velín)' })
const dl = (action: string) => rows('debug_log').filter((d) => d.action === action)
/** zbytek z pi_orig selže jednou (přechodná chyba Stripe) */
function failNextOrig() { world().onBeforeCreate = (p) => { if (p.payment_intent === 'pi_orig') { world().onBeforeCreate = null; throw new Error('Stripe: transient') } } }

Deno.test({ name: 'i1 A1: obsluha vrátí chybějící zbytek sama → retry / webhook replay / služba už NIKDY nedovrací znovu', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const via of ['cancellation_retry', 'webhook_replay', 'service'] as const) {
    fresh(10, { extra: TWO }); failNextOrig()
    await velinCancel(1558) // hlavní 115 z pi_ext1 (mg_target 1558), zbytek 1443 selže → partial_refund + mail obsluze
    const ev = world().takeEvents(); await deliver(ev)
    if (refundedKc() !== 115 || bk().payment_status !== 'partial_refund') { bad.push(`${via}: po pádu zbytku vráceno ${refundedKc()}, stav ${bk().payment_status}`); continue }
    advance(5)
    const adm = await pr(1443) // obsluha vědomě vrátí chybějících 1443 (nová hlavní vratka z pi_orig)
    if (!adm?.success || refundedKc() !== 1558) { bad.push(`${via}: ruční dorovnání ${JSON.stringify(adm)}, vráceno ${refundedKc()}`); continue }
    await deliver()
    if (via === 'cancellation_retry') await pr(1558, 'service', 'cancellation_retry')
    else if (via === 'webhook_replay') { advance(40); await deliver(ev, 2) }
    else await pr(1558, 'service')
    try { money(`A1 ${via}`, 1558) } catch (e) { bad.push((e as Error).message) }
    if (bk().payment_status !== 'partial_refund') bad.push(`${via}: stav ${bk().payment_status}`)
  }
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i1 A2: zámek po zabitém isolatu + všechna volání do 60 s → mail obsluze, webhook 503, po vypršení zámku dovráceno', ignore: !MAPPED, fn: async () => {
  fresh(10, { extra: TWO }); velinUpd()
  // zabitý process-refund z Velínu hned po hlavní vratce (115 z pi_ext1, cíl 1558): stav ani dobropis, zámek zůstal
  await world().api().refunds.create({ payment_intent: 'pi_ext1', amount: 11500, reason: 'requested_by_customer', metadata: {
    mg_source: 'process-refund', mg_reason: 'cancellation', mg_booking_id: BID, mg_order_id: '', mg_target: '155800',
    mg_cancel_at: bk().cancelled_at, mg_cancel_total: '155800' } }, { idempotencyKey: `refund:${BID}:11500:11500` })
  const ev = world().takeEvents()
  rows('email_send_locks').push({ booking_id: BID, template_slug: 'refund_cancellation', locked_at: Date.now() })
  const orig = Date.now; let off = 0; Date.now = () => orig() + off
  try { const p = sce(1558); setTimeout(() => { off = 9000 }, 300); await p } finally { Date.now = orig }
  if (refundedKc() !== 115) throw new Error(`ve zbytku zámku se nesmí vracet: ${refundedKc()}`)
  if (!dl('cancellation_remainder_deferred').length) throw new Error('chybí debug_log cancellation_remainder_deferred')
  const ops = opsMails.filter((m) => /Storno #.*zbytek zkontrolujte/.test(m.subject))
  if (ops.length !== 1) throw new Error(`mail obsluze: ${JSON.stringify(opsMails.map((m) => m.subject))}`)
  const cm = mails.filter((m) => m.to === EMAIL)
  if (cm.length !== 1 || !/dokončuje obsluha/.test(cm[0].html) || /byl zpracován a vrácen/.test(cm[0].html)) throw new Error(`mail zákazníkovi: ${cm.map((m) => m.html.slice(0, 400))}`)
  await deliver(ev) // charge.refunded uložené platby do 60 s: recovery 503 → webhook 500 (Stripe doručí znovu)
  if (webhookStatuses.at(-1) !== 500) throw new Error(`webhook měl vrátit 500 (retry), vrátil ${webhookStatuses.at(-1)}`)
  if (refundedKc() !== 115) throw new Error(`webhook ve zbytku zámku nesmí vracet: ${refundedKc()}`)
  advance(5); await deliver(ev) // Stripe doručí znovu po vypršení zámku → recovery dovrátí 1443
  if (webhookStatuses.at(-1) !== 200) throw new Error(`webhook po zámku: ${webhookStatuses.at(-1)}`)
  money('A2 po vypršení zámku', 1558)
  if (bk().payment_status !== 'partial_refund' || creditNotes().length !== 1) throw new Error(`stav ${bk().payment_status}, dobropisů ${creditNotes().length}`)
  if (mails.filter((m) => m.to === EMAIL).length !== 1) throw new Error('druhý storno mail')
} })

Deno.test({ name: 'i1 A4/A3: Stripe search padá → plné storno obsluhy selže napevno (nic z doplatku, žádné refunded), po obnovení projde', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  // A4: 3000 + 115, Velín 100 %
  fresh(10, { extra: TWO }); world().failSearch = new Error('rate_limit: search')
  await velinCancel('full'); await deliver()
  if (refundedKc() !== 0) bad.push(`A4: vráceno ${refundedKc()} (čekáno 0)`)
  if (bk().payment_status !== 'refund_pending') bad.push(`A4: stav ${bk().payment_status}`)
  if (!dl('other_payments_unavailable').length) bad.push('A4: chybí debug_log other_payments_unavailable')
  if (!opsMails.some((m) => /platby ve Stripe nejdou načíst/.test(m.subject))) bad.push(`A4: mail obsluze ${JSON.stringify(opsMails.map((m) => m.subject))}`)
  const cm = mails.filter((m) => m.to === EMAIL)
  if (cm.length !== 1 || !/dokončuje obsluha/.test(cm[0].html)) bad.push(`A4: mail zákazníkovi ${cm.map((m) => m.html.slice(0, 300))}`)
  world().failSearch = null; await pr(undefined, 'service'); await deliver()
  if (refundedKc() !== 3115 || bk().payment_status !== 'refunded') bad.push(`A4 retry: vráceno ${refundedKc()}, stav ${bk().payment_status}`)
  // A3: uložený doplatek už dřív vrácený (revert úpravy), cena zpět 3000, search padá
  fresh(10, { extra: TWO })
  await call('process-refund', { booking_id: BID, amount: 115, reason: 'booking_modified' }); await deliver()
  bk().total_price = 3000; bk().payment_status = 'paid'
  world().failSearch = new Error('rate_limit: search'); opsMails.length = 0
  await velinCancel('full'); await deliver()
  if (refundedKc() !== 115) bad.push(`A3: vráceno ${refundedKc()} (čekáno 115)`)
  if (bk().payment_status === 'refunded') bad.push('A3: stav refunded bez vrácení')
  world().failSearch = null; await pr(undefined, 'service'); await deliver()
  if (refundedKc() !== 3115 || bk().payment_status !== 'refunded') bad.push(`A3 retry: vráceno ${refundedKc()}, stav ${bk().payment_status}`)
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i1 A21: „Potvrdit vrácení“ 100 % po 50 % při výpadku search → chyba ve Velíně (bez mailu), po obnovení dorovná', ignore: !MAPPED, fn: async () => {
  fresh(10, { extra: TWO }); await velinCancel(1558); await deliver(); advance(40)
  world().failSearch = new Error('rate_limit: search')
  const r = await velinConfirm(3115)
  if (!r.failed) throw new Error('Velín měl dostat chybu')
  if (refundedKc() !== 1558 || bk().payment_status !== 'partial_refund') throw new Error(`vráceno ${refundedKc()}, stav ${bk().payment_status}`)
  if (customerMails().length !== 1) throw new Error('mail po selhání')
  world().failSearch = null
  const r2 = await velinConfirm(3115); await deliver()
  if (r2.failed) throw new Error('retry měl projít')
  money('A21 retry', 3115)
  if (bk().payment_status !== 'refunded') throw new Error(`stav ${bk().payment_status}`)
} })

Deno.test({ name: 'i1 A5: search padne jen u zbytku Velín 50 % → partial_refund + mail obsluze; další volání služby dovrátí přesně 1558', ignore: !MAPPED, fn: async () => {
  fresh(10, { extra: TWO })
  world().onRefundCreated = async () => { world().onRefundCreated = null; world().failSearch = new Error('rate_limit: search') }
  await velinCancel(1558); await deliver()
  if (refundedKc() !== 115) throw new Error(`vráceno ${refundedKc()} (čekáno 115)`)
  if (bk().payment_status !== 'partial_refund') throw new Error(`stav ${bk().payment_status} (čekáno partial_refund)`)
  if (!opsMails.some((m) => /nevrátila celá/.test(m.subject))) throw new Error(`mail obsluze ${JSON.stringify(opsMails.map((m) => m.subject))}`)
  world().failSearch = null; advance(5)
  await pr(1558, 'service'); await deliver()
  money('A5 dovrácení', 1558)
  if (bk().payment_status !== 'partial_refund') throw new Error(`stav po dovrácení ${bk().payment_status}`)
} })

Deno.test({ name: 'i1 A7: zkrácení (vratka 1500) a do 15 min storno Velínem → storno vrátí dalších 1500 (dobropisy 3000)', ignore: !MAPPED, fn: async () => {
  fresh(10)
  await call('process-refund', { booking_id: BID, amount: 1500, reason: 'edit_shortening' }); await deliver()
  bk().total_price = 1500
  if (bk().payment_status !== 'partial_refund') throw new Error(`po zkrácení ${bk().payment_status}`)
  await velinCancel('full'); await deliver() // Velín: není 'paid' → bez částky; mail si pásmo spočítá (100 % z 1500)
  money('A7', 3000)
  const cm = customerMails()
  if (cm.length !== 1 || cm[0].amount !== 1500) throw new Error(`maily ${JSON.stringify(cm)}`)
} })

Deno.test({ name: 'i1 A8: souběžný dispatch téže zákaznické vratky + unikátní index dobropisů → jeden dobropis, bez mailu „nevystavil“', ignore: !MAPPED, fn: async () => {
  fresh(10); setUniqueCnIndex(true)
  const [a, b] = await Promise.all([
    call('process-refund', { booking_id: BID, amount: 500, reason: 'edit_shortening' }),
    call('process-refund', { booking_id: BID, amount: 500, reason: 'edit_shortening' }),
  ])
  money('A8 souběh', 500)
  if (creditNotes().length !== 1) throw new Error(`dobropisů ${creditNotes().length}`)
  if (!a?.success || !b?.success || !a.credit_note_id || a.credit_note_id !== b.credit_note_id) throw new Error(`odpovědi ${JSON.stringify([a, b])}`)
  if (opsMails.some((m) => /nevystavil/.test(m.subject))) throw new Error('mail „Dobropis se nevystavil“')
  if (rows('accounting_entries').length !== 1) throw new Error(`účetních záznamů ${rows('accounting_entries').length}`)
  setUniqueCnIndex(false)
} })

Deno.test({ name: 'i1 webhook: payment_intent.succeeded bez metadat u částečně vrácené rezervace (uložený doplatek) ji nepřepne na paid', ignore: !MAPPED, fn: async () => {
  fresh(10, { extra: TWO }); bk().payment_status = 'partial_refund'
  const ev = { id: 'evt_pi_1', type: 'payment_intent.succeeded', created: Math.floor(Date.now() / 1000),
    data: { object: { id: 'pi_ext1', object: 'payment_intent', amount: 11500, amount_received: 11500, currency: 'czk', status: 'succeeded', metadata: {}, customer: 'cus_1', created: Math.floor(Date.now() / 1000) } } }
  await deliver([ev])
  if (bk().payment_status !== 'partial_refund') throw new Error(`stav ${bk().payment_status}`)
  if (!dl('pi_fallback_skipped_not_unpaid').length) throw new Error('chybí debug_log pi_fallback_skipped_not_unpaid')
  if (mails.some((m) => m.to === EMAIL)) throw new Error('mail zákazníkovi')
  void SB
} })
