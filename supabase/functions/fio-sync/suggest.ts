// ===== fio-sync/suggest.ts =====
// NÁVRHY SPÁROVÁNÍ pro platbu bez / se špatným variabilním symbolem (zadání majitele 2026-11-27):
// taková platba se NIKDY nepotvrdí sama. Velínu se nabídnou čekající platby s PŘESNĚ stejnou částkou
// (žádné „přibližně“), seřazené podle podobnosti: jméno plátce × jméno zákazníka, zpráva pro příjemce
// (číslo rezervace / objednávky, e-mail, jméno, VS), překlep ve VS, účet, ze kterého zákazník už platil.
// Každý návrh nese důvody česky; obsluha potvrdí jedním kliknutím (akce `pair`), nic se nepotvrzuje samo.
// Čisté funkce (rankCandidates…) jsou bez DB — testy v _tests/fio_suggest_test.ts.
import { fmtAmount, isMissing, type Row, type Sb, short, vsDigits } from './util.ts'

export type Candidate = {
  target_type: 'booking' | 'surcharge' | 'order' | 'request'
  target_id: string
  kind: 'booking' | 'gear' | 'surcharge' | 'booking_change' | 'voucher' | 'shop_order'
  label: string; number: string
  booking_id: string | null; order_id: string | null; request_id: string | null
  amount: number; vs: string | null
  customer_name: string | null; customer_email: string | null
  state: 'waiting' | 'expired' | 'cancelled'
  created_at: string | null; expires_at: string | null
  /** interní (do odpovědi nejde): zákazník pro shodu podle účtu plátce */
  user_id?: string | null
}
export type Ranked = Candidate & { score: number; confidence: 'high' | 'medium' | 'low'; reasons: string[] }
export type Movement = { fio_id: number; amount: number; vs: string | null; counter_name: string | null; counter_account: string | null; counter_bank?: string | null; message: string | null; tx_date?: string | null }

const TITLES = new Set(['ing', 'mgr', 'bc', 'mudr', 'judr', 'phd', 'phdr', 'rndr', 'dr', 'mba', 'csc', 'dis', 'pan', 'pani', 'sro', 'as', 'spol'])
/** Bez diakritiky, malými písmeny, jen písmena a číslice. */
export const norm = (s: unknown) => String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim()
const tokens = (s: unknown) => norm(s).split(' ').filter((t) => t.length >= 2 && !TITLES.has(t))
const cents = (n: unknown) => Math.round((Number(n) || 0) * 100)
const kc = (n: number) => fmtAmount(n).replace('.', ',').replace(/\B(?=(\d{3})+(?!\d))/g, ' ') + ' Kč'

/** Shoda jmen: 'full' = všechna slova jména zákazníka (aspoň 2) jsou ve jménu plátce (pořadí nerozhoduje),
 *  'partial' = shoduje se aspoň jedno slovo o 3+ znacích (typicky příjmení). */
export function nameMatch(payer: unknown, customer: unknown): { kind: 'full' | 'partial' | null; hit: string[] } {
  const a = tokens(payer), b = tokens(customer)
  if (!a.length || !b.length) return { kind: null, hit: [] }
  const hit = b.filter((t) => a.includes(t))
  if (hit.length >= 2 && hit.length === b.length) return { kind: 'full', hit }
  if (hit.length >= 2 && hit.length === a.length) return { kind: 'full', hit }
  const strong = hit.filter((t) => t.length >= 3)
  return strong.length ? { kind: 'partial', hit: strong } : { kind: null, hit: [] }
}

/** Překlep ve VS: jedna jiná číslice, dvě sousední prohozené, jedna chybí / přebývá. */
export function vsNear(a: string, b: string): boolean {
  if (!a || !b || a === b) return false
  if (a.length === b.length) {
    const diff: number[] = []
    for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) diff.push(i)
    if (diff.length === 1) return true
    return diff.length === 2 && diff[1] === diff[0] + 1 && a[diff[0]] === b[diff[1]] && a[diff[1]] === b[diff[0]]
  }
  const [s, l] = a.length < b.length ? [a, b] : [b, a]
  if (l.length - s.length !== 1) return false
  for (let i = 0; i < l.length; i++) if (l.slice(0, i) + l.slice(i + 1) === s) return true
  return false
}

/** Seřazené návrhy pro pohyb `m`. `paidFrom` = zákazníci (user_id), kteří už z účtu plátce platili. */
export function rankCandidates(m: Movement, all: Candidate[], paidFrom: Set<string> = new Set(), limit = 8): Ranked[] {
  const msg = norm(m.message)
  const msgRaw = String(m.message || '').toLowerCase()
  const mvs = vsDigits(m.vs)
  const out: Ranked[] = []
  for (const c of all) {
    if (cents(c.amount) !== cents(m.amount)) continue // jen PŘESNĚ stejná částka
    let score = 10
    const reasons = [`Stejná částka ${kc(c.amount)}`]
    const nm = nameMatch(m.counter_name, c.customer_name)
    if (nm.kind === 'full') { score += 50; reasons.push(`Jméno plátce „${m.counter_name}“ odpovídá zákazníkovi ${c.customer_name}`) }
    else if (nm.kind === 'partial') { score += 30; reasons.push(`Jméno plátce „${m.counter_name}“ se částečně shoduje se zákazníkem ${c.customer_name} (${nm.hit.join(', ')})`) }
    else if (msg && nameMatch(m.message, c.customer_name).kind === 'full') { score += 25; reasons.push(`Zpráva pro příjemce obsahuje jméno zákazníka ${c.customer_name}`) }
    const num = norm(c.number).replace(/ /g, '')
    if (num.length >= 6 && msg.replace(/ /g, '').includes(num)) { score += 50; reasons.push(`Zpráva pro příjemce obsahuje číslo ${c.number}`) }
    const mail = String(c.customer_email || '').toLowerCase()
    if (mail.length >= 6 && msgRaw.includes(mail)) { score += 45; reasons.push('Zpráva pro příjemce obsahuje e-mail zákazníka') }
    const cvs = vsDigits(c.vs)
    if (cvs) {
      if (mvs && mvs === cvs) { score += 60; reasons.push(`Stejný variabilní symbol ${cvs}`) }
      else if (mvs && vsNear(mvs, cvs)) { score += 40; reasons.push(`Variabilní symbol se liší jen překlepem (${mvs} × ${cvs})`) }
      else if (cvs.length >= 6 && msgRaw.replace(/\D/g, '').includes(cvs)) { score += 40; reasons.push(`Zpráva pro příjemce obsahuje variabilní symbol ${cvs}`) }
    }
    if (c.user_id && paidFrom.has(c.user_id)) { score += 35; reasons.push('Z tohoto účtu už zákazník dříve platil') }
    if (c.state === 'cancelled') reasons.push('Pozor: rezervace byla mezitím automaticky zrušena (po spárování se obnoví, je-li termín volný)')
    if (c.state === 'expired') reasons.push('Pozor: lhůta k zaplacení už uplynula')
    score = Math.min(100, score)
    const { user_id: _u, ...pub } = c
    out.push({ ...pub, score, confidence: score >= 60 ? 'high' : score >= 30 ? 'medium' : 'low', reasons })
  }
  out.sort((x, y) => y.score - x.score || (x.state === 'waiting' ? 0 : 1) - (y.state === 'waiting' ? 0 : 1) || String(y.created_at || '').localeCompare(String(x.created_at || '')))
  return out.slice(0, Math.max(1, limit))
}

// ── Načtení čekajících plateb (service klient) ───────────────────────────────

const prof = (r: Row) => (Array.isArray(r.profiles) ? r.profiles[0] : r.profiles) as { full_name?: string; email?: string } | null
const iso = (ms: number) => new Date(ms).toISOString()
const rowsOf = async (q: PromiseLike<{ data: unknown; error: { code?: string; message?: string } | null }>): Promise<Row[]> => {
  const { data, error } = await q
  if (error) { if (isMissing(error)) return []; throw new Error(error.message || 'db_error') }
  return (data as Row[] | null) || []
}

/** Vše, na co se čeká. `wide` (návrhy): navíc nedávno automaticky zrušené QR rezervace, prošlé / zrušené
 *  požadavky úprav a nezaplacené objednávky bez požadavku (převod podle zálohové faktury). */
export async function loadWaiting(sb: Sb, o: { wide: boolean; now?: number }): Promise<Candidate[]> {
  const now = o.now ?? Date.now()
  const out: Candidate[] = []
  const bk = (b: Row, state: Candidate['state']): Candidate => {
    const gear = !b.moto_id && b.booking_kind === 'gear'
    const from = Date.parse(String(b.qr_requested_at || b.created_at || '')) || null
    return { target_type: 'booking', target_id: String(b.id), kind: gear ? 'gear' : 'booking',
      label: (gear ? 'Výpůjčka výbavy #' : 'Rezervace #') + short(String(b.id)), number: short(String(b.id)),
      booking_id: String(b.id), order_id: null, request_id: null, amount: Number(b.total_price) || 0, vs: (b.payment_vs as string) || null,
      customer_name: prof(b)?.full_name || null, customer_email: prof(b)?.email || null, state,
      created_at: (b.created_at as string) || null, expires_at: from ? iso(from + 4 * 3600_000) : null, user_id: (b.user_id as string) || null }
  }
  // 1) nezaplacené rezervace / výpůjčky výbavy čekající na převod
  for (const b of await rowsOf(sb.from('bookings').select('*, profiles(full_name, email)').eq('status', 'pending').eq('payment_status', 'unpaid').not('payment_vs', 'is', null).limit(300))) {
    if (b.payment_vs) out.push(bk(b, 'waiting'))
  }
  if (o.wide) {
    for (const b of await rowsOf(sb.from('bookings').select('*, profiles(full_name, email)').eq('status', 'cancelled').eq('payment_status', 'unpaid')
      .eq('cancelled_by_source', 'auto').not('payment_vs', 'is', null).gte('cancelled_at', iso(now - 14 * 86400_000)).limit(200))) {
      if (b.payment_vs) out.push(bk(b, 'cancelled'))
    }
  }
  // 2) doplatky úprav zadané ve Velínu
  for (const b of await rowsOf(sb.from('bookings').select('id, status, user_id, mod_surcharge_due, mod_surcharge_vs, created_at, profiles(full_name, email)').gt('mod_surcharge_due', 0).limit(200))) {
    if (!(Number(b.mod_surcharge_due) > 0) || b.status === 'cancelled') continue
    out.push({ target_type: 'surcharge', target_id: String(b.id), kind: 'surcharge', label: 'Doplatek rezervace #' + short(String(b.id)), number: short(String(b.id)),
      booking_id: String(b.id), order_id: null, request_id: null, amount: Number(b.mod_surcharge_due), vs: (b.mod_surcharge_vs as string) || null,
      customer_name: prof(b)?.full_name || null, customer_email: prof(b)?.email || null, state: 'waiting', created_at: null, expires_at: null, user_id: (b.user_id as string) || null })
  }
  // 3) požadavky na platbu (poukaz / objednávka, doplatek úpravy z webu)
  const reqs = (await rowsOf(sb.from('bank_payment_requests').select('*').in('status', o.wide ? ['pending', 'expired', 'cancelled'] : ['pending', 'expired'])
    .gte('created_at', iso(now - 60 * 86400_000)).limit(500)))
    .filter((r) => r.status === 'pending' || (r.kind === 'shop_order' && r.status === 'expired') ||
      (o.wide && r.kind === 'booking_change' && Date.parse(String(r.expires_at || '')) > now - 3 * 86400_000))
  const withReq = new Set<string>()
  for (const r of reqs) {
    const lapsed = r.status !== 'pending' || Date.parse(String(r.expires_at || '')) <= now
    const state: Candidate['state'] = r.status === 'cancelled' ? 'cancelled' : lapsed ? 'expired' : 'waiting'
    if (r.kind === 'booking_change') {
      const b = (await rowsOf(sb.from('bookings').select('id, user_id, profiles(full_name, email)').eq('id', r.booking_id).limit(1)))[0]
      out.push({ target_type: 'request', target_id: String(r.id), kind: 'booking_change', label: 'Úprava rezervace #' + short(String(r.booking_id)), number: short(String(r.booking_id)),
        booking_id: String(r.booking_id), order_id: null, request_id: String(r.id), amount: Number(r.amount) || 0, vs: String(r.vs || '') || null,
        customer_name: b ? prof(b)?.full_name || null : null, customer_email: b ? prof(b)?.email || null : null, state,
        created_at: (r.created_at as string) || null, expires_at: (r.expires_at as string) || null, user_id: (b?.user_id as string) || null })
    } else if (r.order_id) {
      const ord = (await rowsOf(sb.from('shop_orders').select('*').eq('id', r.order_id).limit(1)))[0]
      if (!ord || ord.payment_status !== 'pending' || ['cancelled', 'refunded', 'returned'].includes(String(ord.status))) continue
      withReq.add(String(r.order_id))
      out.push(orderCand(ord, r, state))
    }
  }
  // 4) nezaplacené objednávky bez požadavku (zákazník platí převodem podle zálohové faktury) — jen pro návrhy
  if (o.wide) {
    const orders = (await rowsOf(sb.from('shop_orders').select('*').eq('payment_status', 'pending').eq('status', 'new').gte('created_at', iso(now - 60 * 86400_000)).limit(300)))
      .filter((x) => !withReq.has(String(x.id)) && x.payment_status === 'pending' && Number(x.total) > 0)
    if (orders.length) {
      const inv = await rowsOf(sb.from('invoices').select('order_id, variable_symbol, type, status').in('order_id', orders.map((x) => x.id)).in('type', ['shop_proforma', 'proforma', 'advance']).limit(600))
      const vsOf = new Map<string, string>()
      for (const i of inv) if (i.status !== 'cancelled' && i.order_id && i.variable_symbol && !vsOf.has(String(i.order_id))) vsOf.set(String(i.order_id), String(i.variable_symbol))
      for (const ord of orders) out.push(orderCand(ord, null, 'waiting', vsOf.get(String(ord.id)) || null))
    }
  }
  return out
}

function orderCand(ord: Row, r: Row | null, state: Candidate['state'], vs: string | null = null): Candidate {
  const voucher = /poukaz|voucher/i.test(String(ord.notes || ''))
  const number = String(ord.order_number || short(String(ord.id)))
  return { target_type: 'order', target_id: String(ord.id), kind: voucher ? 'voucher' : 'shop_order', label: (voucher ? 'Dárkový poukaz ' : 'Objednávka ') + number, number,
    booking_id: null, order_id: String(ord.id), request_id: r ? String(r.id) : null, amount: Number(r?.amount ?? ord.total) || 0, vs: r ? String(r.vs || '') || null : vs,
    customer_name: (ord.customer_name as string) || null, customer_email: (ord.customer_email as string) || null, state,
    created_at: ((r?.created_at ?? ord.created_at) as string) || null, expires_at: (r?.expires_at as string) || null, user_id: (ord.customer_id as string) || null }
}

/** Zákazníci, kteří už z účtu plátce platili (dřívější spárované pohyby se stejným protiúčtem). */
export async function payersOfAccount(sb: Sb, m: Movement): Promise<Set<string>> {
  const set = new Set<string>()
  if (!m.counter_account) return set
  try {
    const prev = await rowsOf(sb.from('fio_transactions').select('fio_id, booking_id, counter_bank').eq('counter_account', m.counter_account)
      .not('booking_id', 'is', null).neq('fio_id', m.fio_id).limit(50))
    const ids = [...new Set(prev.filter((r) => r.booking_id && (!m.counter_bank || !r.counter_bank || r.counter_bank === m.counter_bank)).map((r) => String(r.booking_id)))]
    if (!ids.length) return set
    for (const b of await rowsOf(sb.from('bookings').select('id, user_id').in('id', ids).limit(50))) if (b.user_id) set.add(String(b.user_id))
  } catch { /* návrh se obejde bez historie účtu */ }
  return set
}

export async function suggestFor(sb: Sb, fioId: number, limit = 8, now?: number): Promise<Row> {
  const { data: tx, error } = await sb.from('fio_transactions')
    .select('fio_id, tx_date, amount, currency, vs, counter_account, counter_bank, counter_name, message, status').eq('fio_id', fioId).maybeSingle()
  if (error) return { success: false, error: 'db_error' }
  if (!tx) return { success: false, error: 'not_found' }
  const m = tx as unknown as Movement
  if (!(Number(m.amount) > 0)) return { success: true, movement: tx, candidates: [] }
  const all = await loadWaiting(sb, { wide: true, now })
  return { success: true, movement: tx, candidates: rankCandidates(m, all, await payersOfAccount(sb, m), limit) }
}
