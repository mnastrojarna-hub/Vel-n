// ===== _tests/storno_hotfix_trigger_flow_test.ts =====
// HOTFIX storno 2026-10-29 — DB trigger trg_notify_booking_cancelled_email (send-cancellation-email
// BEZ e-mailu a BEZ vratky v těle) už nikdy nerozhoduje o penězích. Na main tyto testy PADAJÍ
// (Velín 50 % → 100 %, „bez vratky“ → vratka, hromadné storno → vratka, zákazník po posunu → 100 %…).
// Spouští storno_hotfix_test.ts v podprocesu s import mapou, nebo přímo:
//   deno test -A --no-check --import-map=supabase/functions/_tests/storno-flow-map.json supabase/functions/_tests/storno_hotfix_trigger_flow_test.ts
// STORNO_FN_DIR=<strom>/supabase/functions = tytéž testy proti jinému stromu (důkaz pádu na main).
// deno-lint-ignore-file no-explicit-any
import { boot, cnKc, customerMails, deliver, fresh, later, refundedKc, tier, bk } from './storno-harness.ts'
import { bulkCancel, customerCancel, portalFullRefund, rpcCancel, trigger, velinCancel, type CustMode, type TriggerMode } from './storno-dispatch.ts'

const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/stripe@14').startsWith('file:') } catch { return false } })()
if (MAPPED) await boot()

/** Peníze, dobropisy a JEDEN storno mail zákazníkovi s částkou, která se skutečně vrátila. */
function check(label: string, exp: { refunded: number; cn?: number; mails?: number }, bad: string[]) {
  const ms = customerMails(), r = refundedKc(), cn = cnKc(), wantCn = exp.cn ?? exp.refunded, wantMails = exp.mails ?? 1
  const mailOk = ms.length === wantMails && ms.every((m) => (wantCn > 0 ? m.amount === wantCn : m.amount === null))
  if (r !== exp.refunded || cn !== wantCn || !mailOk) {
    bad.push(`${label}: vráceno ${r} (čekáno ${exp.refunded}), dobropisy ${cn} (čekáno ${wantCn}), maily ${JSON.stringify(ms)}`)
  }
}
const done = (bad: string[]) => { if (bad.length) throw new Error(`${bad.length} scénářů špatně:\n` + bad.join('\n')) }
const MODES: TriggerMode[] = ['before', 'mid', 'concurrent', 'after']

Deno.test({ name: 'storno Velín + trigger: volba admina (100 / 50 / 0 %) platí v každém pořadí, motorka +10 d a +4 d', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const days of [10, 4]) for (const [lab, choice, exp] of [['100%', 'full', 3000], ['50%', 1500, 1500], ['0%', 0, 0]] as Array<[string, number | 'full', number]>) {
    for (const mode of MODES) {
      fresh(days); await velinCancel(choice, mode); await deliver()
      check(`moto +${days} d ${lab} trigger ${mode}`, { refunded: exp }, bad)
    }
  }
  done(bad)
} })

Deno.test({ name: 'storno Velín + trigger: výpůjčka výbavy (booking_kind=gear) stejně jako motorka', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const days of [10, 4]) for (const [lab, choice, exp] of [['50%', 1500, 1500], ['0%', 0, 0], ['100%', 'full', 3000]] as Array<[string, number | 'full', number]>) {
    for (const mode of ['before', 'concurrent'] as TriggerMode[]) {
      fresh(days, { gear: true }); await velinCancel(choice, mode); await deliver()
      check(`gear +${days} d ${lab} trigger ${mode}`, { refunded: exp }, bad)
    }
  }
  done(bad)
} })

Deno.test({ name: 'storno zákazník (cancel_booking_tracked) + trigger: vratka dle RPC (strop po posunu, LEAST časů) právě jednou', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  const nowH = Number(new Intl.DateTimeFormat('en-GB', { timeZone: 'Europe/Prague', hour: '2-digit', hourCycle: 'h23' }).format(new Date()))
  const cases: Array<[string, () => void, number]> = [
    ['+10 d', () => fresh(10), 100], ['+4 d', () => fresh(4), 100], ['+1 d', () => fresh(1), 100],
    ['+10 d posunutá (strop 50 %)', () => fresh(10), 50],
    ['+7 d čas vyzvednutí posunut později', () => fresh(7, { booking: { refund_pickup_time: '00:30:00', pickup_time: `${String(Math.min(23, nowH + 1)).padStart(2, '0')}:30:00` } }), 100],
    ['gear +4 d', () => fresh(4, { gear: true }), 100], ['gear +10 d posunutá (strop 50 %)', () => fresh(10, { gear: true }), 50],
  ]
  for (const [lab, mk, cap] of cases) for (const mode of ['rpcFirst', 'triggerFirst', 'concurrent'] as CustMode[]) {
    mk(); const c = await customerCancel(mode, cap); await deliver()
    check(`zákazník ${lab} (RPC ${c.pct} % = ${c.amt}) ${mode}`, { refunded: c.amt }, bad)
  }
  done(bad)
} })

Deno.test({ name: 'storno zákazník + trigger na hranici 168 h: platí pásmo RPC v okamžiku storna (ne o 0,6 s později)', ignore: !MAPPED, fn: async () => {
  fresh(8)
  const delta = (tier.refundTierRef(bk().start_date, '09:00') - Date.now()) - 168 * 3600_000
  const c = await later(delta - 400, () => Promise.resolve(rpcCancel()))
  await later(delta + 200, () => trigger()); await later(delta + 250, () => c.R()); await deliver()
  const bad: string[] = []
  check(`hranice 168 h (RPC ${c.pct} %)`, { refunded: 3000 }, bad)
  done(bad)
} })

Deno.test({ name: 'hromadné storno / AI copilot + trigger: zaplacená rezervace → žádná vratka, žádný mail', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const days of [10, 4]) { fresh(days); await bulkCancel(true); await deliver(); check(`hromadně +${days} d`, { refunded: 0, mails: 0 }, bad) }
  done(bad)
} })

Deno.test({ name: 'storno Velín + trigger, platba QR: dobropis jen dle volby admina', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const choice of [0, 1500]) {
    fresh(10, { booking: { payment_method: 'qr', pay_channel: 'qr', stripe_payment_intent_id: null } })
    await velinCancel(choice, 'concurrent'); await deliver()
    check(`QR ${choice}`, { refunded: 0, cn: choice }, bad)
  }
  done(bad)
} })

Deno.test({ name: 'plná vratka v Stripe dashboardu (živá rezervace +4 d) + trigger: storno mail uvádí skutečných 3000 Kč (100 %)', ignore: !MAPPED, fn: async () => {
  fresh(4); await portalFullRefund(true); await deliver()
  const bad: string[] = []
  check('Stripe portál', { refunded: 3000 }, bad)
  if (customerMails()[0]?.pct !== 100) bad.push(`mail uvádí ${customerMails()[0]?.pct} %`)
  done(bad)
} })
