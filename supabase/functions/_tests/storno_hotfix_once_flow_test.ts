// ===== _tests/storno_hotfix_once_flow_test.ts =====
// HOTFIX storno 2026-10-29 — storno vratka nejvýš JEDNOU za storno (process-refund/cancel-once.ts),
// i bez DB triggeru (živé dnes): čekající Stripe vratka, opakované doručení charge.refunded po 30 min,
// pád process-refund po refunds.create, souběh volání Velínu a send-cancellation-email. Na main
// tyto scénáře PADAJÍ (vrátí se 3000 místo 1500). + regrese, které musí projít na main i po opravě.
// Spouští storno_hotfix_test.ts v podprocesu s import mapou storno-flow-map.json (viz trigger test).
// deno-lint-ignore-file no-explicit-any
import { BID, EMAIL, advance, bk, boot, call, cnKc, creditNotes, customerMails, dbNow, deliver, fresh, insert, refundedKc, rows, world } from './storno-harness.ts'
import { customerCancel, trigger, velinCancel, velinConfirm } from './storno-dispatch.ts'

const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/stripe@14').startsWith('file:') } catch { return false } })()
if (MAPPED) await boot()

function money(label: string, refunded: number, cn = refunded) {
  const r = refundedKc(), c = cnKc()
  if (r !== refunded || c !== cn) throw new Error(`${label}: vráceno ${r} (čekáno ${refunded}), dobropisy ${c} (čekáno ${cn}), stripe ${JSON.stringify(world().creates.map((x) => x.result))}`)
}
function mailsSay(label: string, amount: number | null, count?: number) {
  const ms = customerMails()
  if ((count != null && ms.length !== count) || !ms.length || ms.some((m) => m.amount !== amount)) throw new Error(`${label}: maily ${JSON.stringify(ms)}, čekáno ${amount}`)
}

Deno.test({ name: 'storno Velín 50 %, Stripe vratka „pending“ (nízký zůstatek): send-cancellation-email nevrací podruhé', ignore: !MAPPED, fn: async () => {
  fresh(10); world().refundStatus = () => 'pending'
  await velinCancel(1500); await deliver()
  money('pending', 1500); mailsSay('pending', 1500, 1)
} })

Deno.test({ name: 'storno + charge.refunded doručený znovu po 40 min: Velín 50 %, zákazník +4 d (motorka i výbava) → bez další vratky', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  const replay = async (label: string, exp: number) => {
    const ev = world().takeEvents(); await deliver(ev); advance(40); await deliver(ev)
    try { money(label, exp); mailsSay(label, exp, 1) } catch (e) { bad.push((e as Error).message) }
  }
  fresh(10); await velinCancel(1500); await replay('replay Velín 50 %', 1500)
  for (const gear of [false, true]) {
    fresh(4, { gear }); const c = await customerCancel('none'); await replay(`replay zákazník +4 d${gear ? ' gear' : ''}`, c.amt)
  }
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'storno Velín 50 %, o hodinu později ruční vratka 500 Kč v Stripe dashboardu → celkem 2000, ne 3000', ignore: !MAPPED, fn: async () => {
  fresh(10); await velinCancel(1500); await deliver()
  advance(60); await world().dashboardRefund('pi_orig', 50000); await deliver()
  money('dashboard +500', 2000, 1500)
} })

Deno.test({ name: 'storno Velín 50 %, process-refund spadne po refunds.create (před zápisem stavu) → jedna vratka, dobropis a mail 1500', ignore: !MAPPED, fn: async () => {
  fresh(10)
  let killed = false
  const db = (globalThis as any).__STORNO_DB
  db.beforeUpdate = (t: string, patch: any) => { if (!killed && t === 'bookings' && patch.stripe_refund_id) { killed = true; throw new Error('isolate killed') } }
  await velinCancel(1500); db.beforeUpdate = null; await deliver()
  money('pád po refunds.create', 1500)
  if (creditNotes().length !== 1) throw new Error(`dobropisů ${creditNotes().length}`)
  mailsSay('pád', 1500, 1)
} })

Deno.test({ name: 'souběh: process-refund z Velínu a send-cancellation-email (vypršel invoke v prohlížeči) → jedna vratka 1500', ignore: !MAPPED, fn: async () => {
  fresh(10)
  Object.assign(bk(), { status: 'cancelled', cancelled_at: new Date().toISOString(), payment_status: 'refund_pending', cancelled_by_source: 'velin', cancellation_reason: 'Storno (Velín)' })
  await insert('booking_cancellations', { booking_id: BID, refund_amount: 1500, refund_percent: 50, created_at: dbNow() })
  await Promise.all([
    call('process-refund', { booking_id: BID, reason: 'cancellation', amount: 1500 }, 'admin'),
    call('send-cancellation-email', { booking_id: BID, customer_email: EMAIL, cancellation_reason: 'Storno (Velín)', cancelled_by_source: 'velin', source: 'app', refund_amount: 1500, refund_percent: 50 }, 'admin'),
  ])
  await deliver()
  money('souběh', 1500); mailsSay('souběh', 1500, 1)
} })

// ── regrese: na main i po opravě stejně ──
Deno.test({ name: 'regrese bez triggeru: Velín 100/50/0 % a zákazník +10/+4/+1 d vrací přesně zvolené / dle pásma', ignore: !MAPPED, fn: async () => {
  for (const days of [10, 4]) for (const [choice, exp] of [['full', 3000], [1500, 1500], [0, 0]] as Array<[number | 'full', number]>) {
    fresh(days); await velinCancel(choice); await deliver()
    money(`Velín +${days} d ${choice}`, exp); mailsSay(`Velín +${days} d ${choice}`, exp || null, 1)
  }
  for (const [days, exp] of [[10, 3000], [4, 1500], [1, 0]]) {
    fresh(days); await customerCancel('none'); await deliver()
    money(`zákazník +${days} d`, exp); mailsSay(`zákazník +${days} d`, exp || null, 1)
  }
} })

Deno.test({ name: 'regrese: Velín storno rezervace „částečně vráceno“ (bez volby vratky) dál vrací dle storno tabulky — i s triggerem', ignore: !MAPPED, fn: async () => {
  for (const withTrigger of [false, true]) {
    fresh(10)
    await call('process-refund', { booking_id: BID, amount: 500, reason: 'edit_shortening' }); await deliver()
    bk().total_price = 2500
    await velinCancel('full', withTrigger ? 'concurrent' : 'none'); await deliver()
    money(`F trigger=${withTrigger}`, 3000); mailsSay('F', 2500, 1)
  }
} })

Deno.test({ name: 'regrese: charge.refunded zpracovaný uvnitř process-refund (před zápisem stavu) → 1500', ignore: !MAPPED, fn: async () => {
  fresh(10); world().onRefundCreated = async () => { world().onRefundCreated = null; await deliver() }
  await velinCancel(1500); await deliver()
  money('webhook uvnitř', 1500)
} })

Deno.test({ name: 'regrese: nezaplacená rezervace + trigger → jeden storno mail, žádné peníze (Velín, zákazník, hromadně)', ignore: !MAPPED, fn: async () => {
  fresh(10, { booking: { payment_status: 'unpaid' } }); await velinCancel('full', 'concurrent'); money('Velín nezaplaceno', 0); mailsSay('Velín nezaplaceno', null, 1)
  fresh(10, { booking: { payment_status: 'unpaid' } }); await customerCancel('triggerFirst'); money('zákazník nezaplaceno', 0)
  mailsSay('zákazník nezaplaceno (trigger první = jako dřív bez vratky)', null, 1)
  fresh(10, { booking: { payment_status: 'unpaid' } })
  Object.assign(bk(), { status: 'cancelled', cancelled_at: new Date().toISOString(), cancelled_by_source: 'admin', cancellation_reason: 'Hromadné storno' })
  await trigger(); money('hromadně nezaplaceno', 0); mailsSay('hromadně nezaplaceno', null, 1)
} })

Deno.test({ name: 'regrese: „Potvrdit vrácení“ obsluhy po stornu 50 % (další vratka 2000 → zbytek) se neblokuje', ignore: !MAPPED, fn: async () => {
  fresh(10); await velinCancel(1500); await deliver()
  const before = rows('debug_log').length
  await velinConfirm(2000); await deliver()
  money('potvrzení obsluhy', 3000)
  if (rows('debug_log').slice(before).some((d) => d.action === 'cancellation_refund_exists')) throw new Error('kontrola zablokovala obsluhu')
} })

