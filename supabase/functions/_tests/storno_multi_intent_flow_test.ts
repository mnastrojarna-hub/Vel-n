// ===== _tests/storno_multi_intent_flow_test.ts =====
// Sloučení HOTFIXU storna 2026-10-29 (vratka nejvýš jednou za storno) s vratkou z VÍCE PLATEB rezervace
// (dev f1–f3: mainSource / staffFullBalanceHaleru / refundRemainder), 2026-11-05. Rezervace 3000 Kč
// + zaplacené doplatky úprav (115 / 200 Kč; process-payment ukládá poslední doplatek do
// stripe_payment_intent_id): storno vrací hlavní vratkou z uložené platby + zbytkem z ostatních plateb,
// nebo z jiné platby než z uložené (nikdy nezaplacený doplatek → retarget). Právě jednou přes všechny
// platby: zámek, kontrola „už vráceno" nad vratkami všech plateb, dovrácení zbytku po pádu, pojistný mail
// webhooku s částkou celého storna. Spouští storno_hotfix_test.ts v podprocesu s import mapou.
// deno-lint-ignore-file no-explicit-any
import { BID, EMAIL, advance, bk, boot, call, cnKc, creditNotes, customerMails, deliver, fresh, refundedKc, rows, world, type ExtraPi } from './storno-harness.ts'
import { customerCancel, rpcCancel, trigger, velinCancel, velinConfirm, type CustMode, type TriggerMode } from './storno-dispatch.ts'

const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/stripe@14').startsWith('file:') } catch { return false } })()
if (MAPPED) await boot()

const TWO: ExtraPi[] = [{ id: 'pi_ext1', czk: 115 }] // 3115 Kč, uložená platba pi_ext1
const THREE: ExtraPi[] = [{ id: 'pi_ext1', czk: 115 }, { id: 'pi_ext2', czk: 200 }] // 3315 Kč, uložená platba pi_ext2
const SETS: Array<[string, ExtraPi[], number]> = [['2 platby', TWO, 3115], ['3 platby', THREE, 3315]]
const half = (total: number) => Math.round(total / 2)

function money(label: string, refunded: number, cn = refunded) {
  const r = refundedKc(), c = cnKc()
  if (r !== refunded || c !== cn) throw new Error(`${label}: vráceno ${r} (čekáno ${refunded}), dobropisy ${c} (čekáno ${cn}), stripe ${JSON.stringify(world().creates.map((x) => x.result))}`)
}
function mailsSay(label: string, amount: number | null, count?: number) {
  const ms = customerMails()
  if ((count != null && ms.length !== count) || !ms.length || ms.some((m) => m.amount !== amount)) throw new Error(`${label}: maily ${JSON.stringify(ms)}, čekáno ${amount}`)
}
/** vráceno z každé platby (Kč) */
const perPi = () => Object.fromEntries([...world().intents.keys()].map((id) => [id, (world().intents.get(id)!.amount_received - world().left(id)) / 100]))
const pr = (amount?: number, as: 'service' | 'admin' = 'admin') => call('process-refund', { booking_id: BID, reason: 'cancellation', ...(amount ? { amount } : {}) }, as)
const sce = (amount: number) => call('send-cancellation-email', { booking_id: BID, customer_email: EMAIL, cancellation_reason: 'Storno (Velín)',
  cancelled_by_source: 'velin', source: 'app', refund_amount: amount, refund_percent: Math.round(amount / 30) }, 'admin')
/** zabije process-refund hned po N-té vratce (pád mezi hlavní vratkou a zbytkem) */
function killAfterRefund(n: number) {
  let k = 0; world().onRefundCreated = async () => { if (++k === n) { world().onRefundCreated = null; throw new Error('isolate killed') } }
}
const done = (bad: string[]) => { if (bad.length) throw new Error(`${bad.length} scénářů špatně:\n` + bad.join('\n')) }

Deno.test({ name: 'více plateb: Velín 100 / 50 / 0 % (2 i 3 platby, i s triggerem) → přesně zvolená částka z více plateb, dobropis a 1 mail', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const [lab, extra, total] of SETS) for (const [choice, exp] of [['full', total], [half(total), half(total)], [0, 0]] as Array<[number | 'full', number]>) {
    for (const mode of ['none', 'mid', 'concurrent', 'after'] as TriggerMode[]) {
      fresh(10, { extra }); await velinCancel(choice, mode); await deliver()
      try { money(`${lab} Velín ${choice} trigger ${mode}`, exp); mailsSay(`${lab} Velín ${choice} trigger ${mode}`, exp || null, 1) } catch (e) { bad.push((e as Error).message) }
    }
  }
  // 50 % ze dvou plateb = celý doplatek z uložené platby + zbytek z původní platby
  fresh(10, { extra: TWO }); await velinCancel(1558); await deliver()
  const p = perPi(); if (p.pi_ext1 !== 115 || p.pi_orig !== 1443) bad.push(`rozdělení 50 %: ${JSON.stringify(p)}`)
  if (bk().payment_status !== 'partial_refund') bad.push(`stav po 50 %: ${bk().payment_status}`)
  fresh(10, { extra: THREE }); await velinCancel('full'); await deliver()
  if (bk().payment_status !== 'refunded' || creditNotes().length !== 1) bad.push(`stav po 100 %: ${bk().payment_status}, dobropisů ${creditNotes().length}`)
  done(bad)
} })

Deno.test({ name: 'více plateb: zákazník (cancel_booking_tracked) +10 / +4 / +1 d × trigger v každém pořadí → dle pásma právě jednou', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const [lab, extra] of SETS) for (const days of [10, 4, 1]) for (const mode of ['rpcFirst', 'triggerFirst', 'concurrent'] as CustMode[]) {
    fresh(days, { extra }); const c = await customerCancel(mode); await deliver()
    try { money(`${lab} zákazník +${days} d ${mode} (RPC ${c.pct} %)`, c.amt); mailsSay(`${lab} zákazník +${days} d ${mode}`, c.amt || null, 1) } catch (e) { bad.push((e as Error).message) }
  }
  done(bad)
} })

Deno.test({ name: 'více plateb: charge.refunded obou plateb doručený znovu po 40 min (Velín 50 %, zákazník +4 d) → bez další vratky i mailu', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const [lab, extra, total] of SETS) {
    fresh(10, { extra }); await velinCancel(half(total)); const ev = world().takeEvents(); await deliver(ev); advance(40); await deliver(ev, 2)
    try { money(`${lab} replay Velín 50 %`, half(total)); mailsSay(`${lab} replay Velín 50 %`, half(total), 1) } catch (e) { bad.push((e as Error).message) }
    fresh(4, { extra }); const c = await customerCancel('concurrent'); const ev2 = world().takeEvents(); await deliver(ev2); advance(40); await deliver(ev2, 2)
    try { money(`${lab} replay zákazník +4 d`, c.amt); mailsSay(`${lab} replay zákazník +4 d`, c.amt, 1) } catch (e) { bad.push((e as Error).message) }
  }
  done(bad)
} })

Deno.test({ name: 'více plateb: pád process-refund mezi hlavní vratkou a zbytkem → další volání (send-cancellation-email / trigger) dovrátí přesně do cíle, nikdy víc', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const [lab, extra, total] of SETS) for (const [choice, exp] of [[half(total), half(total)], ['full', total]] as Array<[number | 'full', number]>) {
    fresh(10, { extra }); killAfterRefund(1)
    await velinCancel(choice, 'concurrent') // admin volání spadne po hlavní vratce; mail Velínu (service) storno dovrátí
    await deliver(); advance(5); await pr(choice === 'full' ? undefined : choice, 'service'); await deliver()
    try {
      money(`${lab} pád po hlavní vratce, Velín ${choice}`, exp); mailsSay(`${lab} pád, Velín ${choice}`, exp, 1)
      if (creditNotes().length !== 1) bad.push(`${lab} pád ${choice}: dobropisů ${creditNotes().length}`)
      const want = choice === 'full' ? 'refunded' : 'partial_refund'
      if (bk().payment_status !== want) bad.push(`${lab} pád ${choice}: stav ${bk().payment_status} (čekáno ${want})`)
    } catch (e) { bad.push((e as Error).message) }
  }
  // 3 platby, pád po druhé vratce (hlavní + první zbytek): dovrátí jen třetí část
  fresh(10, { extra: THREE }); killAfterRefund(2); await velinCancel('full', 'after'); await deliver()
  try { money('3 platby pád po 2. vratce', 3315); mailsSay('3 platby pád po 2. vratce', 3315, 1) } catch (e) { bad.push((e as Error).message) }
  done(bad)
} })

Deno.test({ name: 'více plateb: pád po hlavní vratce u zákazníka (stav paid) a webhook dřív než retry → recovery dovrátí zbytek, mail uvádí celé storno', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const [lab, extra, total] of SETS) {
    fresh(4, { extra }); const c = rpcCancel(); killAfterRefund(1)
    await pr(c.amt, 'service').catch(() => null) // jediné volání z RPC spadlo po hlavní vratce
    const before = refundedKc()
    await deliver() // charge.refunded uložené platby: stav partial_refund, recovery dovrátí, pojistný mail
    await c.R() // retry z RPC: claim mailu drží webhook → nic
    await deliver()
    try {
      if (before >= c.amt) bad.push(`${lab}: pád se nenasimuloval (${before})`)
      money(`${lab} pád zákazník + webhook`, c.amt); mailsSay(`${lab} pád zákazník + webhook`, c.amt, 1)
      if (c.amt < total && bk().payment_status !== 'partial_refund') bad.push(`${lab}: stav ${bk().payment_status}`)
      if (creditNotes().length !== 1) bad.push(`${lab}: dobropisů ${creditNotes().length}`)
    } catch (e) { bad.push((e as Error).message) }
  }
  done(bad)
} })

Deno.test({ name: 'více plateb: pojistný storno mail webhooku (předběhne mail z RPC) uvádí celé storno, ne jen vratku uložené platby', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const [lab, extra] of SETS) {
    fresh(4, { extra }); const c = rpcCancel(); await pr(c.amt, 'service'); await deliver(); await c.R()
    try { money(`${lab} mail webhooku`, c.amt); mailsSay(`${lab} mail webhooku`, c.amt, 1) } catch (e) { bad.push((e as Error).message) }
    if (!rows('debug_log').some((d) => d.action === 'idempotent_skip_claim')) bad.push(`${lab}: mail z RPC se neměl poslat (claim webhooku)`)
  }
  done(bad)
} })

Deno.test({ name: 'více plateb: uložený doplatek NIKDY nezaplacený (opuštěný pokus) → storno z původní platby a druhé volání ze serveru nevrací podruhé', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const [choice, exp] of [[1500, 1500], ['full', 3000]] as Array<[number | 'full', number]>) {
    fresh(10, { extra: TWO, booking: { total_price: 3000, modification_history: [] } })
    Object.assign(world().intents.get('pi_ext1')!, { status: 'requires_payment_method', amount_received: 0 })
    await velinCancel(choice, 'concurrent'); await deliver(); advance(5); await pr(choice === 'full' ? undefined : choice, 'service'); await deliver()
    try { money(`retarget Velín ${choice}`, exp); mailsSay(`retarget Velín ${choice}`, exp, 1) } catch (e) { bad.push((e as Error).message) }
    if (perPi().pi_orig !== exp) bad.push(`retarget ${choice}: vráceno z plateb ${JSON.stringify(perPi())}`)
  }
  done(bad)
} })

Deno.test({ name: 'více plateb: obsluha — dvojité odeslání storna 50 % (souběžně i po sobě) jedna vratka; „Potvrdit vrácení“ 100 % po 50 % dorovná zbytek', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  const velinUpd = () => Object.assign(bk(), { status: 'cancelled', cancelled_at: new Date().toISOString(), payment_status: 'refund_pending', cancelled_by_source: 'velin', cancellation_reason: 'Storno (Velín)' })
  fresh(10, { extra: TWO }); velinUpd(); await Promise.all([pr(1558), pr(1558)]); await sce(1558); await deliver()
  try { money('souběžné 50 %', 1558); mailsSay('souběžné 50 %', 1558, 1) } catch (e) { bad.push((e as Error).message) }
  fresh(10, { extra: TWO }); velinUpd(); await pr(1558); await pr(1558); await sce(1558); await deliver()
  try { money('po sobě 50 % (hlavní vratka 115 ≠ 1558 — cíl v metadatech)', 1558) } catch (e) { bad.push((e as Error).message) }
  fresh(10, { extra: TWO }); world().refundStatus = () => 'pending'; velinUpd(); await pr(1558); await sce(1558); await deliver()
  try { money('vratky „pending“', 1558); mailsSay('vratky „pending“', 1558, 1) } catch (e) { bad.push((e as Error).message) }
  for (const [lab, extra, total] of SETS) {
    fresh(10, { extra }); await velinCancel(half(total)); await deliver(); advance(40); await velinConfirm(total); await deliver()
    try { money(`${lab} dorovnání na 100 %`, total) } catch (e) { bad.push((e as Error).message) }
    if (bk().payment_status !== 'refunded' || customerMails().at(-1)?.amount !== total) bad.push(`${lab} dorovnání: stav ${bk().payment_status}, maily ${JSON.stringify(customerMails())}`)
  }
  done(bad)
} })

Deno.test({ name: 'více plateb: po stornu 50 % ruční vratka 500 Kč v dashboardu a replay → jen +500; storno 0 % + trigger znovu → nic', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  fresh(10, { extra: TWO }); await velinCancel(1558); const ev = world().takeEvents(); await deliver(ev)
  advance(60); await world().dashboardRefund('pi_orig', 50000); await deliver(); await deliver(ev)
  // i3 (2026-11-07): externí vratka PŮVODNÍ (neuložené) platby se dohledá podle metadat (dřív ignorována) → pojistný storno
  // mail jako u jedné platby (vratka po stornu, skip_refund), částka = vráceno k rezervaci celkem přes všechny platby
  try {
    money('dashboard +500', 2058, 1558)
    const ms = customerMails()
    if (ms.length !== 2 || ms[0].amount !== 1558 || ms[1].amount !== 2058) throw new Error(`dashboard +500: maily ${JSON.stringify(ms)}, čekáno 1558, 2058`)
  } catch (e) { bad.push((e as Error).message) }
  fresh(10, { extra: THREE }); await velinCancel(0, 'concurrent'); await deliver(); advance(40); await trigger(); await deliver()
  try { money('Velín 0 %', 0); mailsSay('Velín 0 %', null, 1) } catch (e) { bad.push((e as Error).message) }
  done(bad)
} })

Deno.test({ name: 'více plateb: vrácení doplatku (přesně zbytek uložené platby) rezervaci neuzavře — pozdější storno 50 % / 100 % vrátí z původní platby', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const [choice, exp] of [[1500, 1500], ['full', 3000]] as Array<[number | 'full', number]>) {
    fresh(10, { extra: TWO })
    await call('process-refund', { booking_id: BID, amount: 115, reason: 'booking_modified' }); await deliver() // revert úpravy (DB trigger, service)
    if (bk().payment_status !== 'partial_refund') bad.push(`po vrácení doplatku stav ${bk().payment_status} (čekáno partial_refund)`)
    bk().total_price = 3000; bk().payment_status = 'paid' // úprava vrácena: cena zpět, Velín vidí zaplaceno
    await velinCancel(choice, 'concurrent'); await deliver()
    try { money(`po vrácení doplatku Velín ${choice}`, 115 + exp); mailsSay(`po vrácení doplatku Velín ${choice}`, exp, 1) } catch (e) { bad.push((e as Error).message) }
  }
  done(bad)
} })
