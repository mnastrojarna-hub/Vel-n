// ===== process-payment/due-verify.ts =====
// D1 (oprava 2026-10-16): zbytek rezervace do 15 Kč se odpouští (≤ 1 Kč) nebo
// dorovnává na 15 Kč JEN, když ho server umí ověřit. bookings.total_price zapisuje
// klient (RLS bookings_user_update / insert) — bez kontroly by šlo poslat rezervaci
// na 5 dní s cenou 0,40 Kč a potvrdit ji bez karty.
// Ověření je velkorysé (spodní mez ceny): pronájem dle ceníku dní motorky
// (_moto_dayprice_sum) minus NEJVĚTŠÍ slevy, které server dokáže doložit:
//  • poukazy (booking_discounts / voucher_id / discount_code) — hodnota z tabulky
//    vouchers, jen aktivní nebo uplatněné pro tuto rezervaci a platné,
//  • slevové kódy (booking_discounts / promo_code_id) — z promo_codes (procento
//    počítané z ceny vč. výbavy a dopravy), jen aktivní,
//  • věrnostní sleva (max. 20 % — strop pravidla) a sleva za vyzvednutí od 12:00
//    (_late_pickup_discount) v uložené výši, nejvýš do pravidla.
// Výbava a doprava se do spodní meze NEpočítají (jen by ji zvyšovaly).
// Zbytek (cena − slevy) vyšší než uložená cena o víc než 1 Kč = cena neodpovídá.

// deno-lint-ignore no-explicit-any
type Sb = any

const day = (v: unknown) => String(v || '').slice(0, 10)
const num = (v: unknown) => (Number.isFinite(Number(v)) ? Number(v) : 0)

/** Spodní mez ceny rezervace, kterou server doloží (Kč), nebo null = ověření teď neproběhlo. */
export async function verifiedBookingFloor(sb: Sb, b: Record<string, unknown>): Promise<number | null> {
  try {
    if (!b.moto_id || !b.start_date || !b.end_date) return 0
    const { data: rent, error: rErr } = await sb.rpc('_moto_dayprice_sum', {
      p_moto_id: b.moto_id, p_start: day(b.start_date), p_end: day(b.end_date),
    })
    if (rErr || rent == null || !Number.isFinite(Number(rent))) return null
    const rental = Number(rent)
    const gross = rental + Math.max(num(b.extras_price), 0) + Math.max(num(b.delivery_fee), 0)
    const today = new Date().toISOString().slice(0, 10)

    // Poukazy
    const vIds = new Set<string>()
    const vCodes = new Set<string>()
    const promoIds = new Set<string>()
    const { data: bd, error: bdErr } = await sb.from('booking_discounts')
      .select('kind, voucher_id, promo_code_id, code').eq('booking_id', b.id)
    if (bdErr) return null
    for (const r of (bd || []) as Array<Record<string, unknown>>) {
      if (r.kind === 'voucher' && r.voucher_id) vIds.add(String(r.voucher_id))
      if (r.kind === 'promo_code' && r.promo_code_id) promoIds.add(String(r.promo_code_id))
    }
    if (b.voucher_id) vIds.add(String(b.voucher_id))
    if (b.promo_code_id) promoIds.add(String(b.promo_code_id))
    for (const c of String(b.discount_code || '').split(',')) if (c.trim()) { vCodes.add(c.trim()); vCodes.add(c.trim().toUpperCase()) }
    let vouchers = 0
    const seen = new Set<string>()
    const addVoucher = (v: Record<string, unknown>) => {
      if (seen.has(String(v.id))) return
      seen.add(String(v.id))
      const valid = !v.valid_until || day(v.valid_until) >= today
      const mine = v.status === 'active' || (v.status === 'redeemed' && v.booking_id === b.id)
      if (valid && mine) vouchers += Math.max(num(v.amount), 0)
    }
    if (vIds.size) {
      const { data, error } = await sb.from('vouchers').select('id, amount, status, booking_id, valid_until').in('id', [...vIds])
      if (error) return null
      for (const v of (data || []) as Array<Record<string, unknown>>) addVoucher(v)
    }
    if (vCodes.size) {
      const { data, error } = await sb.from('vouchers').select('id, code, amount, status, booking_id, valid_until').in('code', [...vCodes])
      if (error) return null
      for (const v of (data || []) as Array<Record<string, unknown>>) addVoucher(v)
    }

    // Slevové kódy (id z booking_discounts / promo_code_id, legacy i podle discount_code)
    let promos = 0
    const pSeen = new Set<string>()
    const addPromos = (rows: Array<Record<string, unknown>>) => {
      for (const p of rows) {
        if (pSeen.has(String(p.id)) || p.active === false) continue
        pSeen.add(String(p.id))
        promos += p.type === 'percent' ? gross * Math.min(Math.max(num(p.value), 0), 100) / 100 : Math.max(num(p.value), 0)
      }
    }
    if (promoIds.size) {
      const { data, error } = await sb.from('promo_codes').select('id, type, value, active').in('id', [...promoIds])
      if (error) return null
      addPromos((data || []) as Array<Record<string, unknown>>)
    }
    if (vCodes.size) {
      const { data, error } = await sb.from('promo_codes').select('id, type, value, active').in('code', [...vCodes])
      if (error) return null
      addPromos((data || []) as Array<Record<string, unknown>>)
    }

    // Věrnost (strop pravidla 20 %) + sleva za vyzvednutí od 12:00 (strop dle pravidla)
    const loyalty = Math.min(Math.max(num(b.loyalty_discount_amount), 0), Math.round(gross * 0.2))
    let late = Math.max(num(b.late_pickup_discount_amount), 0)
    if (late > 0) {
      const { data: lmax, error: lErr } = await sb.rpc('_late_pickup_discount', {
        p_moto_id: b.moto_id, p_start: String(b.start_date), p_end: String(b.end_date),
        p_pickup_time: b.pickup_time == null ? null : String(b.pickup_time),
      })
      if (lErr || lmax == null) return null
      late = Math.min(late, Math.max(num(lmax), 0))
    }
    return Math.max(0, Math.round((rental - vouchers - promos - loyalty - late) * 100) / 100)
  } catch { return null }
}
