// ===== _tests/operator_refund_flow_test.ts =====
// Změna provozovatele (2026-11): dobropis nese vystavitele OPRAVOVANÉHO dokladu — skutečný handler
// process-refund nad falešným Stripe + in-memory DB (storno-harness):
//   • dobropis ke starému dokladu (issuer_snapshot dřívějšího provozovatele) = dřívější provozovatel,
//     i když company_info už říká nového a i při dorenderování chybějícího souboru,
//   • dobropis k novému dokladu = nový provozovatel (vč. zápisu v rejstříku),
//   • snapshot na řádku dobropisu (jak ho plní DB trigger) má přednost,
//   • nový kód + stará DB (žádný snapshot, company_info starý) = dosavadní provozovatel, bez pádu.
// Spuštění: deno test --allow-all --no-check --import-map=supabase/functions/_tests/storno-flow-map.json supabase/functions/_tests/operator_refund_flow_test.ts
// Bez import mapy se přeskočí — spouští je operator_flow_runner_test.ts v podprocesu.
// deno-lint-ignore-file no-explicit-any
import { BID, EMAIL, boot, call, creditNotes, fresh, mails, refundedKc, rows } from './storno-harness.ts'
import { velinCancel } from './storno-dispatch.ts'
import { NEW_INFO, OLD_INFO, OLD_SNAPSHOT } from './operator-fixtures.ts'

const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/stripe@14').endsWith('storno-stubs.ts') } catch { return false } })()
if (MAPPED) await boot()

function ok(c: unknown, msg = '') { if (!c) throw new Error(`assert failed ${msg}`) }
const files = (): Map<string, Blob> => (globalThis as any).__STORNO_DB.files
async function cnHtml() {
  const cns = creditNotes()
  if (cns.length !== 1) throw new Error(`čekán 1 dobropis, je ${cns.length}`)
  const cn = cns[0]
  const blob = files().get(String(cn.pdf_path))
  if (!blob) throw new Error(`soubor dobropisu ${cn.pdf_path} není ve storage: ${[...files().keys()]}`)
  return { cn, html: await blob.text() }
}
const setup = (o: { info?: Record<string, unknown>; dpSnapshot?: unknown }) => {
  fresh(10)
  if (o.info) rows('app_settings').push({ key: 'company_info', value: o.info })
  if (o.dpSnapshot !== undefined) rows('invoices')[0].issuer_snapshot = o.dpSnapshot
}
const OLD = ['>Jan Novák<', 'Dlouhá 1, 110 00 Praha', 'IČO: 12345678']
const NEW = ['>MotoGo24 s.r.o.<', 'Mezná 9, 393 01 Mezná', 'IČO: 29909864', 'C 36876, Krajský soud v Českých Budějovicích']
const all = (h: string, marks: string[], label: string) => { for (const m of marks) ok(h.includes(m), `${label}: chybí „${m}“`) }
const none = (h: string, marks: string[], label: string) => { for (const m of marks) ok(!h.includes(m), `${label}: nesmí obsahovat „${m}“`) }

Deno.test({ name: 'provozovatel · dobropis ke STARÉMU dokladu nese dřívějšího vystavitele (company_info už nový) — i po dorenderování souboru', ignore: !MAPPED, fn: async () => {
  setup({ info: NEW_INFO, dpSnapshot: OLD_SNAPSHOT })
  await velinCancel('full')
  ok(refundedKc() === 3000, `vráceno ${refundedKc()}`)
  const a = await cnHtml()
  ok(a.cn.original_invoice_id === rows('invoices')[0].id, 'dobropis odkazuje na původní DP')
  all(a.html, OLD, 'dobropis'); none(a.html, [...NEW, '29909864', 's.r.o.'], 'dobropis')
  // soubor zmizel → další volání (už vráceno) ho dorenderuje — pořád s původním vystavitelem
  files().delete(String(a.cn.pdf_path))
  await call('process-refund', { booking_id: BID, reason: 'cancellation' }, 'admin')
  const b = await cnHtml()
  all(b.html, OLD, 'dorenderovaný dobropis'); none(b.html, NEW, 'dorenderovaný dobropis')
} })

Deno.test({ name: 'provozovatel · dobropis k NOVÉMU dokladu nese nového provozovatele (název, sídlo, IČO, zápis v rejstříku)', ignore: !MAPPED, fn: async () => {
  setup({ info: NEW_INFO, dpSnapshot: NEW_INFO })
  await velinCancel('full')
  const a = await cnHtml()
  all(a.html, NEW, 'dobropis'); none(a.html, OLD, 'dobropis')
  // patička storno e-mailu (send-cancellation-email) = provozovatel z company_info
  const mail = mails.find((m) => m.to === EMAIL)
  ok(mail, 'storno e-mail zákazníkovi odešel')
  all(mail!.html, ['>MotoGo24 s.r.o.</div>', '>Mezná 9, 393 01 Mezná</div>', '>IČO: 29909864</div>', '>C 36876, Krajský soud v Českých Budějovicích</div>'], 'patička e-mailu')
} })

Deno.test({ name: 'provozovatel · dobropis: snapshot na řádku dobropisu (DB trigger — zděděný z původního dokladu) má přednost před company_info', ignore: !MAPPED, fn: async () => {
  setup({ info: NEW_INFO, dpSnapshot: OLD_SNAPSHOT })
  // simulace triggeru invoices_stamp_issuer: dobropis zdědí vystavitele dokladu z original_invoice_id, jinak company_info
  const db = (globalThis as any).__STORNO_DB
  const prev = db.beforeInsert
  db.beforeInsert = (t: string, r: any) => {
    if (t === 'invoices' && r.issuer_snapshot == null) {
      const orig = r.type === 'credit_note' && r.original_invoice_id ? rows('invoices').find((x) => x.id === r.original_invoice_id) : null
      r.issuer_snapshot = orig?.issuer_snapshot || NEW_INFO
    }
    return prev?.(t, r)
  }
  await velinCancel(1500)
  const a = await cnHtml()
  ok(JSON.stringify(a.cn.issuer_snapshot) === JSON.stringify(OLD_SNAPSHOT), 'trigger: dobropis zdědil vystavitele původního dokladu')
  all(a.html, OLD, 'dobropis'); none(a.html, NEW, 'dobropis')
} })

Deno.test({ name: 'provozovatel · dobropis: NOVÝ KÓD + STARÁ DB (žádný snapshot, company_info starý) → dosavadní provozovatel; bez nastavení výchozí', ignore: !MAPPED, fn: async () => {
  setup({ info: OLD_INFO })
  await velinCancel('full')
  const a = await cnHtml()
  all(a.html, OLD, 'stará DB'); none(a.html, [...NEW, '36876'], 'stará DB')
  const mail = mails.find((m) => m.to === EMAIL)
  ok(mail && mail.html.includes('>Jan Novák</div>') && mail.html.includes('>IČO: 12345678</div>') && !mail.html.includes('s.r.o.') && !mail.html.includes('36876'), 'patička e-mailu ve staré DB = dosavadní provozovatel')
  setup({})
  await velinCancel('full')
  const b = await cnHtml()
  all(b.html, NEW, 'bez nastavení'); none(b.html, OLD, 'bez nastavení')
} })
