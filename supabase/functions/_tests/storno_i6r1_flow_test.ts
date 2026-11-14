// ===== _tests/storno_i6r1_flow_test.ts =====
// Oprava fix:i6r1 (2026-11-07) po verify:refunds / verify:charges i6 — celé handlery nad falešným Stripe + DB
// (storno-harness.ts). Na stromu před opravou (9886c117) testy PADAJÍ (STORNO_FN_DIR=<strom před opravou>), kromě kontroly N1b:
//  W1  selhaná vratka 1. zkrácení + pozdější LEGITIMNÍ zkrácení o stejnou částku → rezervace se znovu otevře, „Chybí vrátit“
//      (failed-refund.ts: nahrazuje jen vratka označená mg_retry_of — retry-of.ts); W1b totéž z více plateb, 1. selhala dřív
//      → druhé zkrácení se celé vrátí (jiná cena = nová úprava, žádný odečet, mg_retry_of 'none'), W1c opakování po jiné úpravě
//      je označené (mg_retry_of) a stará událost „failed“ rezervaci neotevře,
//  W2b dřívější zkrácení 500 + storno 500 selže → Velín „Potvrdit vrácení na 500 Kč“ vratku opravdu provede (přeskočí jen
//      kvůli dobropisu TOHOTO storna), mail přiloží dobropis storna,
//  W3  karta + převod, kartová vratka selže → „Vratka odeslána“ z otevřené stránky nezapíše 'refunded' (manualRefundSentLive);
//      W3b zastaralý 'refunded' (starší Velín) → „Potvrdit vrácení“ chyba, žádný mail o vrácení (refunded-check.ts),
//  W6  zkrácení z více plateb, selže hlavní vratka (zbytek odešel) → mail „vraťte jen chybějících … NEopakujte“; opakování téhož
//      volání vrátí jen chybějící část (retry-of.ts) a stará událost „failed“ pak rezervaci znovu neotevře,
//  N1  chyba přenosu confirm_payment u zrušené (cron) rezervace → webhook 500, žádný mail „rezervováno“; N1b RPC commitla → jako dřív,
//  T1  souběžné doručení téže nevysvětlené platby → právě jeden mail obsluze (claim_email_send); T1b mail neodešel → 500
//      a znovu doručená událost ho pošle; T1c bez RPC → první záznam vyhrává (jeden mail).
// Spouští storno_hotfix_test.ts (podproces s import mapou storno-flow-map.json).
// deno-lint-ignore-file no-explicit-any
import { BID, FN, advance, bk, boot, call, cnKc, creditNotes, customerMails, deliver, fresh, mails, opsMails, rows, webhookStatuses, world } from './storno-harness.ts'
import { velinCancel, velinConfirm } from './storno-dispatch.ts'

const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/stripe@14').startsWith('file:') } catch { return false } })()
if (MAPPED) await boot()
const velin: any = MAPPED ? await import(new URL('../../velin/src/pages/booking/manualRefundState.js', FN).href) : {}
const g = globalThis as any
const db = () => g.__STORNO_DB

// send-booking-email (mail zákazníkovi po potvrzení platby) zachytit; send-email (mail obsluze) volitelně nechat selhat
const bookingMails: any[] = []
let failOpsMail = 0
const prevFetch = g.fetch
g.fetch = (input: any, init?: any) => {
  const url = typeof input === 'string' ? input : input.url
  if (url.includes('/functions/v1/send-booking-email')) { try { bookingMails.push(JSON.parse(String(init?.body || '{}'))) } catch { /* */ } }
  if (url.includes('/functions/v1/send-email') && failOpsMail > 0) { failOpsMail--; return Promise.resolve(new Response('{"error":"resend down"}', { status: 502 })) }
  return prevFetch(input, init)
}

const pr = (amount?: number, as: 'service' | 'admin' | 'customer' = 'admin', reason = 'cancellation') =>
  call('process-refund', { booking_id: BID, reason, ...(amount ? { amount } : {}) }, as)
const ev = (type: string, r: any, id: string) => deliver([{ id, type, created: Math.floor(Date.now() / 1000), data: { object: JSON.parse(JSON.stringify(r)) } }])
const fail = (r: any, id = 'evt_cru_' + r.id) => { r.status = 'failed'; return ev('charge.refund.updated', r, id) }
const liveKc = () => world().refunds.filter((r: any) => r.status === 'succeeded' || r.status === 'pending').reduce((s: number, r: any) => s + r.amount, 0) / 100
const text = (h: string) => h.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ')
const failMails = () => opsMails.filter((m) => /SELHALA/.test(m.subject))
const priceList = () => { db().rpcs._moto_dayprice_sum = () => ({ data: 2000, error: null }) }
const piEvent = (pi: string) => {
  const o: any = world().intents.get(pi)!
  return { id: 'evt_' + pi + '_' + Math.random().toString(36).slice(2, 7), type: 'payment_intent.succeeded', created: Math.floor(Date.now() / 1000),
    data: { object: { id: pi, object: 'payment_intent', currency: 'czk', amount: o.amount, amount_received: o.amount_received, status: 'succeeded',
      metadata: o.metadata, customer: null, created: o.created, latest_charge: o.latest_charge } } }
}

Deno.test({ name: 'i6r1 W1: selhaná vratka 1. zkrácení + pozdější legitimní zkrácení o stejnou částku → znovu otevřena, „Chybí vrátit 500 Kč“', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const [lab, as, reason] of [['appka 4.1.3', 'customer', 'edit_shortening'], ['web / RPC', 'service', 'shortening']] as Array<[string, 'customer' | 'service', string]>) {
    fresh(10); priceList(); world().refundStatus = () => 'pending'
    bk().total_price = 2500
    await pr(500, as, reason); await deliver() // 1. zkrácení o den (pending)
    world().refundStatus = () => 'succeeded'
    advance(24 * 60)
    bk().total_price = 2000
    await pr(500, as, reason); await deliver() // 2. zkrácení o DALŠÍ den — nová vratka, ne opakování
    opsMails.length = 0
    await fail(world().refunds[0])
    const m = failMails()[0]
    if (bk().payment_status !== 'refund_pending') bad.push(`${lab}: stav ${bk().payment_status}`)
    if (!m || !/Chybí vrátit <strong>500 Kč/.test(m.html) || /nahradila novější vratka/.test(m.html)) bad.push(`${lab}: mail ${m ? text(m.html).slice(-240) : '—'}`)
    if (liveKc() !== 500 || cnKc() !== 500) bad.push(`${lab}: vráceno ${liveKc()} Kč, dobropisy ${cnKc()} Kč`)
  }
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i6r1 W1b: více plateb, 1. zkrácení (hlavní) selže dřív, pak legitimní 2. zkrácení o stejnou částku → vrátí se celé (bez odečtu)', ignore: !MAPPED, fn: async () => {
  fresh(10, { extra: [{ id: 'pi_ext1', czk: 500 }] }) // 3000 + uložený doplatek 500
  let n = 0
  world().refundStatus = () => (++n === 1 ? 'pending' : 'succeeded')
  bk().total_price = 2000
  await pr(1500, 'service', 'shortening'); await deliver() // hlavní 500 (pi_ext1, pending) + zbytek 1000 (pi_orig)
  world().refundStatus = () => 'succeeded'
  await fail(world().refunds.find((r: any) => r.metadata.mg_part !== 'remainder')) // hlavní selže, obsluha dostane mail
  advance(24 * 60)
  bk().total_price = 500
  await pr(1500, 'service', 'shortening'); await deliver() // DALŠÍ zkrácení o 1500 (jiná cena)
  const newest = world().refunds.filter((r: any) => r.metadata.mg_part !== 'remainder').at(-1)
  if (liveKc() !== 2500 || newest?.metadata?.mg_retry_of !== 'none') {
    throw new Error(`vráceno ${liveKc()} Kč (čekáno 1000 + 1500), mg_retry_of ${newest?.metadata?.mg_retry_of}`)
  }
} })

Deno.test({ name: 'i6r1 W1c: opakování selhané vratky po jiné úpravě je označené opakování → stará událost „failed“ neotevírá', ignore: !MAPPED, fn: async () => {
  fresh(10); world().refundStatus = () => 'pending'
  bk().total_price = 2500
  await pr(500, 'service', 'shortening'); await deliver()
  world().refundStatus = () => 'succeeded'
  advance(2); bk().total_price = 2200
  await pr(300, 'service', 'moto_swap'); await deliver()
  await fail(world().refunds[0])
  advance(5)
  await pr(500, 'service', 'shortening'); await deliver() // opakování dle mailu
  const retry = world().refunds.at(-1)
  const after = bk().payment_status
  await fail(world().refunds[0], 'evt_ru_again')
  if (retry?.metadata?.mg_retry_of !== world().refunds[0].id || bk().payment_status !== after || after === 'refund_pending' || liveKc() !== 800) {
    throw new Error(`mg_retry_of ${retry?.metadata?.mg_retry_of}, stav ${after} → ${bk().payment_status}, vráceno ${liveKc()} Kč`)
  }
} })

Deno.test({ name: 'i6r1 W2b: dřívější zkrácení 500 + storno 500 selže → „Potvrdit vrácení na 500 Kč“ dle mailu opravdu vrátí, dobropis storna v mailu', ignore: !MAPPED, fn: async () => {
  fresh(10); priceList()
  bk().total_price = 2500
  await pr(500, 'service', 'shortening'); await deliver() // zkrácení: vratka 500 + dobropis 500
  const shortCn = creditNotes()[0]?.number
  advance(24 * 60)
  world().refundStatus = () => 'pending'
  await velinCancel(500); await deliver() // storno s vratkou 500 (pending)
  world().refundStatus = () => 'succeeded'
  opsMails.length = 0
  await fail(world().refunds[1])
  const m = failMails()[0]
  const pre = { cn: cnKc(), st: bk().payment_status, mail: m ? text(m.html) : '—' }
  advance(10)
  const nMail = mails.length
  await velinConfirm(500); await deliver()
  const cm = mails.slice(nMail).filter((x) => /zakaznik/.test(x.to)).at(-1)
  const bad: string[] = []
  if (!/Potvrdit vrácení[^.]*na 500 Kč/.test(pre.mail) || pre.cn !== 500 || pre.st !== 'refund_pending') bad.push(`předpoklad: dobropisy ${pre.cn}, stav ${pre.st}`)
  if (liveKc() !== 1000) bad.push(`vráceno ${liveKc()} Kč (čekáno 1000) — Velín vratku přeskočil kvůli dobropisu zkrácení`)
  if (cnKc() !== liveKc()) bad.push(`dobropisy ${cnKc()} Kč ≠ vráceno ${liveKc()} Kč`)
  if (bk().payment_status !== 'partial_refund') bad.push(`stav ${bk().payment_status}`)
  const att = cm?.attachments || []
  if (!att.some((a) => /^Dobropis-/.test(a)) || att.some((a) => a.includes(String(shortCn)))) bad.push(`mail zákazníkovi přikládá dobropis zkrácení ${shortCn}: ${JSON.stringify(cm?.attachments)}`)
  if (bad.length) throw new Error(bad.join('\n'))
} })

/** karta 3000 + převod 500, plné storno; kartová vratka selže → stav k vrácení, dobropis karty zrušen */
async function cardBankFailed() {
  fresh(10, { booking: { total_price: 3500, mod_surcharge_vs: '2026002', mod_surcharge_paid_at: new Date().toISOString() } })
  rows('invoices').push({ id: crypto.randomUUID(), booking_id: BID, type: 'payment_receipt', status: 'issued', total: 500, number: 'DP-2026-1501', issue_date: '2026-10-02', created_at: new Date().toISOString() })
  rows('fio_transactions').push({ fio_id: 8, booking_id: BID, amount: 500, vs: '2026002', counter_account: '111', counter_bank: '0100' })
  world().refundStatus = () => 'pending'
  await velinCancel('full'); await deliver()
  world().refundStatus = () => 'succeeded'
  const page = { bk: { ...bk() }, cns: creditNotes().map((c: any) => ({ ...c })) } // detail rezervace otevřený PŘED selháním
  await fail(world().refunds[0])
  return page
}

Deno.test({ name: 'i6r1 W3: karta + převod, kartová vratka selže → „Vratka odeslána“ z otevřené stránky nezapíše vráceno; „Potvrdit vrácení“ pak vrátí kartou', ignore: !MAPPED, fn: async () => {
  const page = await cardBankFailed()
  const afterFail = { cn: cnKc(), st: bk().payment_status }
  if (typeof velin.manualRefundSentLive !== 'function') throw new Error('manualRefundSentLive chybí (Velín čte dobropisy ze stránky)')
  const st = await velin.manualRefundSentLive(db(), page.bk)
  advance(10)
  const nMail = customerMails().length
  await velinConfirm(3500); await deliver() // P2: celková vratka storna 3500 (karta 3000 + převod 500 už v dobropisu)
  const cm = customerMails().slice(nMail).at(-1)
  const bad: string[] = []
  if (afterFail.cn !== 500 || afterFail.st !== 'refund_pending') bad.push(`po selhání karty dobropisy ${afterFail.cn} Kč, stav ${afterFail.st} (předpoklad)`)
  if (st === 'refunded') bad.push('„Vratka odeslána“ zapsala refunded, ačkoli kartových 3000 Kč neodešlo')
  if (liveKc() !== 3000) bad.push(`„Potvrdit vrácení“ pak vrátilo kartou ${liveKc()} Kč (čekáno 3000)`)
  if (liveKc() < 3000 && (cm?.amount ?? 0) >= 3000) bad.push(`mail zákazníkovi tvrdí ${cm?.amount} Kč`)
  // CAS: stav se mezitím změnil → výjimka, nic se nezapíše
  bk().payment_status = 'refund_pending'
  const d = db(); const of = d.from.bind(d); let once = false
  d.from = (t: string) => { const q = of(t); if (t === 'invoices' && !once) { once = true; bk().payment_status = 'partial_refund' } return q }
  let threw = false
  try { await velin.manualRefundSentLive(d, page.bk) } catch { threw = true } finally { d.from = of }
  if (!threw || bk().payment_status !== 'partial_refund') bad.push(`compare-and-set: výjimka ${threw}, stav ${bk().payment_status}`)
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i6r1 W3b: zastaralé „Vráceno“ (starší Velín) po selhané kartové vratce → „Potvrdit vrácení“ chyba, žádný mail o vrácení', ignore: !MAPPED, fn: async () => {
  await cardBankFailed()
  bk().payment_status = 'refunded' // starší Velín: „Vratka odeslána“ ze seznamu dobropisů z doby před selháním
  advance(10)
  const nMail = customerMails().length
  const r = await velinConfirm(3000)
  const res = await pr(3000, 'admin')
  if (!r.failed || res?.code !== 'refunded_status_mismatch' || customerMails().length !== nMail || liveKc() !== 0) {
    throw new Error(`Velín ${JSON.stringify(r)}, odpověď ${JSON.stringify(res)}, nových mailů ${customerMails().length - nMail}, vráceno ${liveKc()} Kč`)
  }
  // kontrola: skutečně vrácené storno (3000 kartou + 500 převodem) ve stavu 'refunded' → „už vráceno“ jako dřív
  fresh(10); await velinCancel('full'); await deliver(); advance(10)
  const ok = await pr(3000, 'admin')
  if (ok?.already_refunded !== true) throw new Error(`plně vrácené storno: ${JSON.stringify(ok)}`)
} })

Deno.test({ name: 'i6r1 W6: zkrácení z více plateb, selže HLAVNÍ vratka → mail „vraťte jen chybějících“, opakování vrátí jen chybějící část', ignore: !MAPPED, fn: async () => {
  fresh(10, { extra: [{ id: 'pi_ext1', czk: 500 }] }) // 3000 + uložený doplatek 500 = 3500
  let n = 0
  world().refundStatus = () => (++n === 1 ? 'pending' : 'succeeded')
  bk().total_price = 2000
  await pr(1500, 'service', 'shortening'); await deliver() // hlavní 500 (pi_ext1) + zbytek 1000 (pi_orig)
  world().refundStatus = () => 'succeeded'
  opsMails.length = 0
  const main = world().refunds.find((r: any) => r.metadata.mg_part !== 'remainder')
  await fail(main)
  const m = failMails()[0]
  const pre = { cn: cnKc(), mail: m ? text(m.html) : '—' }
  advance(30)
  const res = await pr(1500, 'service', 'shortening'); await deliver() // služba / obsluha zopakuje totéž zkrácení
  const retry = world().refunds.filter((r: any) => r.metadata.mg_part !== 'remainder').at(-1)
  const afterRetry = bk().payment_status
  await fail(main, 'evt_ru_stale') // stará událost „failed“ po úspěšném opakování
  const bad: string[] = []
  if (pre.cn !== 1000 || !/Chybí vrátit 500 Kč[^.]*vraťte jen chybějících 500 Kč[^.]*NEopakujte/.test(pre.mail)) bad.push(`předpoklad: dobropisy ${pre.cn} Kč, mail ${pre.mail.slice(-300)}`)
  if (liveKc() !== 1500) bad.push(`vráceno ${liveKc()} Kč, dlužno 1500 Kč`)
  if (cnKc() !== liveKc()) bad.push(`dobropisy ${cnKc()} Kč ≠ vráceno ${liveKc()} Kč`)
  if (retry?.metadata?.mg_retry_of !== main.id || Number(res?.amount_refunded) !== 1500) bad.push(`opakování: mg_retry_of ${retry?.metadata?.mg_retry_of}, odpověď ${res?.amount_refunded}`)
  if (bk().payment_status !== afterRetry || afterRetry === 'refund_pending') bad.push(`stará událost: ${afterRetry} → ${bk().payment_status}`)
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i6r1 N1: chyba přenosu confirm_payment u zrušené nezaplacené rezervace → 500 (Stripe doručí znovu), žádný mail „rezervováno“', ignore: !MAPPED, fn: async () => {
  fresh(10, { booking: { status: 'cancelled', payment_status: 'unpaid', cancelled_at: new Date(Date.now() - 60_000).toISOString(), cancelled_by_source: 'cron' } })
  db().rpcs.confirm_payment = () => ({ data: null, error: { message: 'upstream request timeout' } })
  bookingMails.length = 0
  await deliver([piEvent('pi_orig')])
  const reserved = bookingMails.filter((m) => m.type === 'booking_reserved' || m.type === 'invoice_payment_receipt')
  if (reserved.length || webhookStatuses.at(-1) !== 500 || bk().status !== 'cancelled') {
    throw new Error(`rezervace ${bk().status}/${bk().payment_status}, maily ${reserved.map((m) => m.type)}, webhook ${webhookStatuses.at(-1)}`)
  }
} })

Deno.test({ name: 'i6r1 N1b (kontrola): confirm_payment commitla, pak chyba přenosu → potvrzeno jako dřív (200, mail)', ignore: !MAPPED, fn: async () => {
  fresh(10, { booking: { status: 'pending', payment_status: 'unpaid' } })
  db().rpcs.confirm_payment = () => { Object.assign(bk(), { status: 'reserved', payment_status: 'paid' }); return { data: null, error: { message: 'connection reset' } } }
  bookingMails.length = 0
  await deliver([piEvent('pi_orig')])
  const reserved = bookingMails.filter((m) => m.type === 'booking_reserved')
  if (reserved.length !== 1 || webhookStatuses.at(-1) !== 200 || bk().payment_status !== 'paid') {
    throw new Error(`rezervace ${bk().status}/${bk().payment_status}, maily ${bookingMails.map((m) => m.type)}, webhook ${webhookStatuses.at(-1)}`)
  }
  // nezaplacená živá rezervace a RPC nedoběhla → záložní zápis jako dřív
  fresh(10, { booking: { status: 'pending', payment_status: 'unpaid' } })
  db().rpcs.confirm_payment = () => ({ data: null, error: { message: 'timeout' } })
  await deliver([piEvent('pi_orig')])
  if (bk().payment_status !== 'paid' || webhookStatuses.at(-1) !== 200) throw new Error(`záložní zápis: ${bk().status}/${bk().payment_status}, webhook ${webhookStatuses.at(-1)}`)
} })

const reviewSetup = () => {
  fresh(10, { booking: { status: 'cancelled', payment_status: 'refunded', cancelled_at: new Date().toISOString() } })
  world().addPi('pi_x', 3000, { booking_id: BID, type: 'booking' }, -120) // zaplaceno před stornem, rezervace ji neeviduje
  opsMails.length = 0
}
const reviewMails = () => opsMails.filter((m) => /pi_x/.test(m.html) && /zkontrolujte/i.test(m.subject))

Deno.test({ name: 'i6r1 T1: dvě souběžná doručení téže nevysvětlené platby → právě jeden mail obsluze', ignore: !MAPPED, fn: async () => {
  reviewSetup()
  await Promise.all([deliver([piEvent('pi_x')]), deliver([piEvent('pi_x')])])
  await deliver([piEvent('pi_x')]) // pozdější znovu doručení
  if (reviewMails().length !== 1) throw new Error(`mailů ${reviewMails().length}, záznamů ${rows('debug_log').filter((d: any) => d.action === 'cancelled_payment_review').length}`)
} })

Deno.test({ name: 'i6r1 T1b: mail obsluze neodešel → webhook 500 a znovu doručená událost ho pošle (jednou)', ignore: !MAPPED, fn: async () => {
  reviewSetup()
  failOpsMail = 1
  await deliver([piEvent('pi_x')])
  const first = { st: webhookStatuses.at(-1), n: reviewMails().length }
  await deliver([piEvent('pi_x')]); await deliver([piEvent('pi_x')])
  failOpsMail = 0
  if (first.st !== 500 || first.n !== 0 || reviewMails().length !== 1) throw new Error(`1. doručení ${first.st} (${first.n} mailů), celkem ${reviewMails().length} mailů`)
} })

Deno.test({ name: 'i6r1 T1c: bez claim_email_send (RPC chybí) → první záznam vyhrává, souběh pošle jeden mail', ignore: !MAPPED, fn: async () => {
  reviewSetup()
  delete db().rpcs.claim_email_send
  await Promise.all([deliver([piEvent('pi_x')]), deliver([piEvent('pi_x')])])
  if (reviewMails().length !== 1) throw new Error(`mailů ${reviewMails().length}`)
} })
