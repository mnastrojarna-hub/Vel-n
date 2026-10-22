// ===== webhook-receiver/customer-lang.ts =====
// Jazyk zákazníka pro maily/doklady spouštěné ze Stripe webhooku (audit W2, EDGE-DOC-03).
// Webhook ho předává volaným funkcím explicitně (`language`), aby nezávisely jen na
// vlastním dotazu přes RPC. Pořadí: bookings/shop_orders.language → RPC
// detect_customer_language → undefined (volaný si jazyk dohledá sám, jinak 'cs').
// Navazující rezervace (SOS náhrada `replacement_for_booking_id`, výměna motorky
// `continues_booking_id`) se zakládají s výchozím 'cs' — pokud je původní rezervace
// v jiném jazyce, převezme se (stejné pravidlo jako trigger _booking_inherit_language v M1).

export const CUSTOMER_LANGS = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'] as const
export type CustomerLang = typeof CUSTOMER_LANGS[number]

/** 'EN' / 'de-DE' / ' pl ' → 'en' / 'de' / 'pl'; nepodporovaný nebo prázdný → null. */
export function normalizeCustomerLang(v: unknown): CustomerLang | null {
  const s = String(v ?? '').trim().toLowerCase().slice(0, 2)
  return (CUSTOMER_LANGS as readonly string[]).includes(s) ? s as CustomerLang : null
}

/** Vlastní jazyk rezervace; když je výchozí 'cs' a nadřazená rezervace má jiný jazyk, vezme ten. */
export function pickBookingLanguage(own: unknown, parent?: unknown): CustomerLang | null {
  const o = normalizeCustomerLang(own)
  const p = normalizeCustomerLang(parent)
  if (o && o !== 'cs') return o
  if (p && p !== 'cs') return p
  return o ?? p
}

// Volající mají různě odvozené typy klienta (esm.sh) → záměrně volný typ.
// deno-lint-ignore no-explicit-any
type Db = any
// deno-lint-ignore no-explicit-any
type Row = Record<string, any> | null

async function detectViaRpc(supabase: Db, bookingId: string | null, orderId: string | null): Promise<CustomerLang | null> {
  try {
    const { data, error } = await supabase.rpc('detect_customer_language', {
      p_user_id: null, p_booking_id: bookingId, p_order_id: orderId,
    })
    return error ? null : normalizeCustomerLang(data)
  } catch { return null }
}

/** Jazyk zákazníka k rezervaci. Nikdy nehází; undefined = nechat na volané funkci. */
export async function resolveBookingLanguage(supabase: Db, bookingId: string | null | undefined): Promise<CustomerLang | undefined> {
  if (!bookingId) return undefined
  try {
    const { data } = await supabase.from('bookings')
      .select('language, replacement_for_booking_id, continues_booking_id')
      .eq('id', bookingId).maybeSingle()
    const bk = data as Row
    const own = normalizeCustomerLang(bk?.language)
    const parentId = bk?.continues_booking_id || bk?.replacement_for_booking_id
    let parentLang: unknown = null
    if (parentId && (own === null || own === 'cs')) { // jen u výchozí 'cs' má smysl číst původní rezervaci
      const { data: parent } = await supabase.from('bookings').select('language').eq('id', parentId).maybeSingle()
      parentLang = (parent as Row)?.language ?? null
    }
    const lang = pickBookingLanguage(bk?.language, parentLang) ?? await detectViaRpc(supabase, bookingId, null)
    return lang ?? undefined
  } catch { return undefined }
}

/** Jazyk zákazníka k e-shop objednávce (voucher). Nikdy nehází; undefined = nechat na volané funkci. */
export async function resolveOrderLanguage(supabase: Db, orderId: string | null | undefined): Promise<CustomerLang | undefined> {
  if (!orderId) return undefined
  try {
    const { data } = await supabase.from('shop_orders').select('language').eq('id', orderId).maybeSingle()
    const lang = normalizeCustomerLang((data as Row)?.language) ?? await detectViaRpc(supabase, null, orderId)
    return lang ?? undefined
  } catch { return undefined }
}
