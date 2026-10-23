// ===== _shared/agent-knowledge/gear-offer.ts =====
// Nástroj `get_gear_rental_offer` — VÝPŮJČKA VÝBAVY BEZ MOTORKY (2026-10-23).
// Sdílí veřejný agent (ai-public-agent → PUBLIC_TOOLS) i appka (ai-moto-agent →
// PUBLIC_READ_TOOLS, tím i agent zpráv ve Velínu). Vše ŽIVĚ z DB (service role):
// app_settings.gear_rental (enabled/max_days/max_ahead_days/app_visible), aktivní
// gear_rental_prices (štítky z translations v jazyce zákazníka), pobočky (active +
// is_open, příznak brány), u pobočky + termínu zavření (branch_is_closed), s kusy
// kalkulace SERVERU (quote_gear_booking, 20261023b; bez ní záloha _gear_rental_quote
// = cena/den) a volné kusy (get_gear_rental_availability). Ceny se v TS NEpočítají
// (jediná výjimka: záloha cena/den × dny, když nová RPC ještě není nasazená).

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { AGENT_LANGS, normLang, siteUrl } from './site-url.ts'
import { markGateBranches } from './branch-gate.ts'
import { ssSizeOk } from './gear-rental.ts'

type Row = Record<string, unknown>
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const ISO = /^\d{4}-\d{2}-\d{2}$/

export const GEAR_OFFER_TOOL = {
  name: 'get_gear_rental_offer',
  description: 'VÝPŮJČKA VÝBAVY BEZ MOTORKY (helma, bunda, kalhoty, rukavice, boty — kusy i komplety): živý ceník Kč/den z Velína, zda je služba zapnutá, max. délka a jak daleko dopředu, pobočky k vyzvednutí (typ, brána), velikosti (na samoobslužné pobočce jen `sizes_self_service`), `app_available` (true = lze objednat i v appce; false = zatím jen web, v appce bude brzy) a `order_url` = odkaz na objednávku na webu v jazyce zákazníka. S `branch_id` + `start_date` + `end_date` ověří, že je pobočka otevřená, a s `items` vrátí PŘESNOU kalkulaci serveru (`quote`) a volné kusy (`stock`, je-li zapnutá kontrola skladu). Volej VŽDY na dotazy o půjčení výbavy/oblečení BEZ motorky. Výbava K rezervaci motorky je jiná věc → `get_extras_catalog` (`gear_pricing`).',
  input_schema: {
    type: 'object' as const,
    properties: {
      branch_id: { type: 'string', description: 'UUID pobočky (z `branches` tohoto toolu nebo z get_branches) — volitelné.' },
      start_date: { type: 'string', description: 'První den výpůjčky YYYY-MM-DD — volitelné.' },
      end_date: { type: 'string', description: 'Poslední den výpůjčky (včetně) YYYY-MM-DD — volitelné.' },
      items: {
        type: 'array',
        description: 'Kusy [{key, size}] — key z `items[].key`, size z jeho `sizes` (boty = číslo). Komplet se započítá sám, když je levnější.',
        items: { type: 'object', properties: { key: { type: 'string' }, size: { type: 'string' } }, required: ['key'] },
      },
      voucher_code: { type: 'string', description: 'Dárkový poukaz (volitelné; promo kódy ani věrnostní sleva na výbavu neplatí).' },
      customer_language: { type: 'string', enum: [...AGENT_LANGS], description: 'Jazyk zákazníka — štítky kusů a odkaz.' },
    },
  },
}

function daysInclusive(a: string, b: string): number {
  return Math.round((Date.parse(b + 'T12:00:00Z') - Date.parse(a + 'T12:00:00Z')) / 86400000) + 1
}

function localized(r: Row, L: string): { label: string; description: string | null } {
  const t = ((r.translations as Record<string, Row> | null) || {})[L] || {}
  return {
    label: String((L !== 'cs' && t.label) || r.label || r.key),
    description: ((L !== 'cs' && t.description) || r.description || null) as string | null,
  }
}

/** Celé číslo z nastavení Velína s výchozí hodnotou a ořezem jako v SQL (prázdné / nečíselné = výchozí). */
function cfgInt(v: unknown, def: number, max: number): number {
  const n = v === null || v === undefined || v === '' ? NaN : Math.trunc(Number(v))
  return Number.isFinite(n) ? Math.min(Math.max(n, 1), max) : def
}

export async function getGearRentalOffer(sb: SupabaseClient, args: Row, lang = 'cs'): Promise<unknown> {
  const L = normLang(args.customer_language, normLang(lang))
  const [setRes, priceRes, brRes] = await Promise.all([
    sb.from('app_settings').select('value').eq('key', 'gear_rental').maybeSingle(),
    sb.from('gear_rental_prices').select('key, kind, label, description, includes, sizes, price_per_day, sort_order, translations')
      .eq('is_active', true).order('sort_order', { ascending: true }).order('key'),
    sb.from('branches').select('*').order('name'),
  ])
  const st = ((setRes.data as Row | null)?.value || {}) as Row
  if (st.enabled === false) {
    return { enabled: false, notice: 'Půjčení výbavy bez motorky je teď ve Velínu vypnuté — nenabízej ho; výbava jde jen k rezervaci motorky (get_extras_catalog → gear_pricing).' }
  }
  const prices = (priceRes.data || []) as Row[]
  if (priceRes.error || prices.length === 0) {
    return { enabled: true, error: 'price_list_unavailable', notice: 'Ceník výbavy se nepodařilo načíst — cenu NEUVÁDĚJ, pošli zákazníka na order_url (ceník je na stránce).', order_url: siteUrl(L, '/pujceni-obleceni') }
  }
  const branches = ((brRes.data || []) as Row[])
    .filter((b) => b.active !== false && b.is_open !== false)
    .map((b) => ({
      id: b.id, name: b.name, city: b.city ?? null, address: b.address ?? null, type: b.type ?? null,
      self_service: b.type === 'samoobslužná',
      pickup: b.type === 'samoobslužná'
        ? 'samoobsluha 24/7: kód šatny (+ kód schránky s klíčem od brány, má-li pobočka bránu), velikosti a podpis protokolu na displeji'
        : 'výbavu předá a převezme obsluha osobně v čase z rezervace',
    } as Row))
  await markGateBranches(sb, branches)

  const items = prices.filter((r) => r.kind === 'item').map((r) => {
    const sizes = (Array.isArray(r.sizes) ? r.sizes : []) as string[]
    return { key: r.key, ...localized(r, L), sizes, sizes_self_service: sizes.filter((s) => ssSizeOk(String(r.key), s)), price_per_day: Number(r.price_per_day) }
  })
  const sets = prices.filter((r) => r.kind === 'set').map((r) => ({ key: r.key, ...localized(r, L), includes: r.includes, price_per_day: Number(r.price_per_day) }))

  const out: Row = {
    enabled: true,
    // Efektivní limity = zrcadlo SQL _gear_rental_quote (COALESCE 30 / 400, oříznuto 1–366 / 1–800)
    max_days: cfgInt(st.max_days, 30, 366),
    max_ahead_days: cfgInt(st.max_ahead_days, 400, 800),
    app_available: st.app_visible === true,
    currency: 'CZK', price_unit: 'Kč za den (termín od–do včetně)',
    items, sets, branches,
    rules: 'Komplet se účtuje automaticky, když je levnější než součet jeho kusů. Na samoobslužné pobočce jen velikosti ze `sizes_self_service`. Doklady: jen doklad totožnosti (18+), ŘP ne. Věrnostní sleva ani promo kódy neplatí, dárkový poukaz ano.',
  }

  const bid = typeof args.branch_id === 'string' && UUID.test(args.branch_id) ? args.branch_id : null
  const s = typeof args.start_date === 'string' && ISO.test(args.start_date) ? args.start_date : null
  const e = typeof args.end_date === 'string' && ISO.test(args.end_date) ? args.end_date : (s || null)
  const q = new URLSearchParams()
  if (bid) q.set('pobocka', bid)
  if (s) q.set('start', s)
  if (e && s) q.set('end', e)
  out.order_url = siteUrl(L, '/pujceni-obleceni' + (q.toString() ? `?${q}` : ''))

  if (bid && !branches.some((b) => b.id === bid)) out.branch_error = 'bad_branch'
  if (bid && s && e) {
    if (e < s) return { ...out, quote: { error: 'bad_dates' } }
    out.days = daysInclusive(s, e)
    const { data: closed } = await sb.rpc('branch_is_closed', { p_branch_id: bid, p_start: s, p_end: e })
    if (closed === true) out.branch_closed = true
    const rawItems = Array.isArray(args.items) ? (args.items as Row[]) : []
    const pItems = rawItems.filter((i) => i && typeof i.key === 'string').slice(0, 12)
      .map((i) => ({ key: String(i.key), size: i.size == null ? null : String(i.size) }))
    const [quote, stock] = await Promise.all([
      pItems.length ? serverQuote(sb, bid, s, e, pItems, args.voucher_code, Number(out.days)) : Promise.resolve(null),
      sb.rpc('get_gear_rental_availability', { p_branch_id: bid, p_start: s, p_end: e }).then((r) => (r.error ? null : r.data), () => null),
    ])
    if (quote) out.quote = quote
    if (stock) out.stock = stock
  }
  return out
}

// Kalkulace serveru: quote_gear_booking (DB-A) — jinak záloha _gear_rental_quote (cena/den).
async function serverQuote(sb: SupabaseClient, bid: string, s: string, e: string, items: Row[], voucher: unknown, days: number): Promise<unknown> {
  const v = typeof voucher === 'string' && voucher.trim() ? voucher.trim() : null
  const r = await sb.rpc('quote_gear_booking', { p_branch_id: bid, p_start: s, p_end: e, p_items: items, p_voucher_code: v })
  if (!r.error) return r.data
  const f = await sb.rpc('_gear_rental_quote', { p_items: items })
  if (f.error) return { error: 'quote_unavailable' }
  const d = (f.data || {}) as Row
  if (d.error) return d
  const perDay = Number(d.per_day || 0)
  return { source: 'fallback', per_day: perDay, days, total: perDay * days, lines: d.lines, note: 'Orientační cena bez poukazu a bez kontroly skladu — přesnou částku ukáže objednávka na webu.' }
}
