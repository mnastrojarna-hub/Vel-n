// Kategorie, které jsou VŽDY příjmy (i když type = 'expense')
export const REVENUE_CATEGORIES = ['pronájem', 'pronajem', 'rezervace', 'booking', 'rental']

// Popisy, které indikují příjem
export const REVENUE_DESCRIPTIONS = ['platba za rezervaci', 'platba za pronájem', 'příjem z pronájmu']

/**
 * Klasifikuje účetní záznam jako 'revenue', 'expense' nebo 'unknown'.
 */
export function classifyEntry(entry) {
  const cat = (entry.category || '').toLowerCase()
  const desc = (entry.description || '').toLowerCase()
  if (entry.type === 'revenue') return 'revenue'
  if (REVENUE_CATEGORIES.some(rc => cat.includes(rc)) ||
      REVENUE_DESCRIPTIONS.some(rd => desc.includes(rd))) {
    return 'revenue'
  }
  return entry.type || 'expense'
}

/**
 * Vrací true pokud je záznam příjmový.
 */
export function isRevenueEntry(entry) {
  return classifyEntry(entry) === 'revenue'
}

// ── Realizované rezervace (obrat z rezervací) ─────────────────────────────────
//
// Sjednocená definice „obratu" z rezervací pro celou Analýzu (zákazníci,
// pobočky, motorky, lokace, kategorie) i Návštěvnost. Do obratu se počítá KAŽDÁ
// rezervace, kterou zákazník reálně ZAPLATIL a není stornovaná ani testovací —
// tedy i nadcházející (`reserved`) a probíhající (`active`), ne pouze
// `completed`. Dosud analytika počítala výhradně `status='completed'`, takže
// během sezóny (většina zaplacených rezervací je teprve reserved/active)
// systematicky podhodnocovala obrat a čísla „neseděla".
//
// `total_price` nese po úpravě/vratce už čistou částku (Varianta B přepisuje
// total absolutně + přepočítá slevu), takže součet odpovídá reálné tržbě.
export const PAID_BOOKING_STATUSES = ['paid', 'partial_refund', 'refund_pending', 'refunded']

/** Rezervace, u které peníze reálně dorazily a počítá se do obratu. */
export function isRealizedBooking(b) {
  return !!b
    && b.status !== 'cancelled'
    && b.is_test !== true
    && PAID_BOOKING_STATUSES.includes(b.payment_status)
}

/** Obrat jedné rezervace (0 pokud není realizovaná). */
export function bookingRevenue(b) {
  return isRealizedBooking(b) ? (Number(b.total_price) || 0) : 0
}

// ── Souhrn faktur (sdílená logika pro Dokumenty i Finance) ────────────────────
//
// Datový model (viz generate-invoice / invoiceUtils):
//  • Doklady se generují se `status: 'issued'` — status se NEMĚNÍ na 'paid'
//    (kromě ručního „Označit zaplaceno"). Proto se „Zaplaceno" NESMÍ počítat
//    podle statusu, ale podle TYPU dokladu.
//  • KF (final) i shop_final odečítají DP samostatným záporným řádkem,
//    takže DP + KF = skutečná tržba bez dvojího počítání.
//  • Dobropis (credit_note) má záporný `total` → přičtením se refund odečte.

// Doklady o reálně přijaté platbě (peníze dorazily)
export const INVOICE_RECEIVED_TYPES = ['payment_receipt', 'final', 'shop_final']
// Do „Zaplaceno" se přidají i dobropisy (záporné → odečtou refundy)
export const INVOICE_PAID_TYPES = [...INVOICE_RECEIVED_TYPES, 'credit_note']
// Zálohové faktury = pouze výzvy k platbě
export const INVOICE_PROFORMA_TYPES = ['advance', 'proforma', 'shop_proforma']

/**
 * Testovací doklad (z testovací rezervace / účtu). Vyžaduje, aby byl řádek
 * z `invoices` načten s joiny `bookings:booking_id(is_test)` a
 * `profiles:customer_id(is_test_account)`.
 */
export function isTestInvoice(i) {
  return i?.bookings?.is_test === true || i?.profiles?.is_test_account === true
}

/** Stornovaný / refundovaný doklad — do tržeb se nezapočítává. */
export function isVoidInvoice(i) {
  return i?.status === 'cancelled' || i?.status === 'refunded'
}

/**
 * Sečte tržby z faktur (DP + KF + shop_final − dobropisy) BEZ dvojího započítání
 * e-shop / voucher plateb.
 *
 * U e-shop/voucher objednávky se generuje jak `payment_receipt` (DP, na 100 %
 * ceny), tak `shop_final` (Shop KF). `shop_final` MÁ částku DP odečíst záporným
 * řádkem → správně vyjde 0. Jenže `shop_final` často vzniká DŘÍV než DP (DB
 * trigger `generate_shop_final_on_ship` + `confirmShopPayment` generují KF hned,
 * DP se doplní až přílohou `voucher_purchased` mailu), takže `shop_final` zůstane
 * na plné částce a stejná platba se do tržeb započítá 2× (poukaz „počítaný 2×").
 *
 * Řešení: pro objednávku (`order_id`), která má nestornovaný DP, `shop_final` do
 * tržeb NEpřičítáme — platbu reprezentuje DP. Když DP chybí, `shop_final` se
 * počítá (žádný podhodnocený obrat). Vyžaduje, aby řádky faktur nesly `order_id`;
 * bez něj se chová jako prostý součet (bezpečný fallback).
 */
export function sumInvoiceRevenue(invoices) {
  const rows = (invoices || [])
    .filter(i => !isVoidInvoice(i) && !isTestInvoice(i) && INVOICE_PAID_TYPES.includes(i.type))
  const ordersWithReceipt = new Set(
    rows.filter(i => i.type === 'payment_receipt' && i.order_id).map(i => i.order_id)
  )
  return rows.reduce((s, i) => {
    if (i.type === 'shop_final' && i.order_id && ordersWithReceipt.has(i.order_id)) return s
    return s + (i.total || 0)
  }, 0)
}

/**
 * Spočítá souhrn faktur: Zaplaceno / Nezaplaceno / Celkem / Stornováno.
 *
 * Vstup: pole řádků z `invoices` načtené min. se sloupci
 *   `type, status, total, booking_id, order_id`
 * a (pro vyřazení testovacích) s joiny
 *   `bookings:booking_id(is_test), profiles:customer_id(is_test_account)`.
 *
 *  • paid     = DP + KF + shop_final − dobropisy (mimo stornované/testovací)
 *  • unpaid   = zálohové faktury BEZ odpovídajícího DP/KF (= nikdo neuhradil),
 *               mimo ručně zaplacené, stornované, refundované a testovací
 */
export function summarizeInvoices(invoices) {
  const nonTest = (invoices || []).filter(i => !isTestInvoice(i))

  // Zaplaceno = DP + KF + shop_final − dobropisy, bez dvojího počítání e-shop plateb.
  const paid = sumInvoiceRevenue(invoices)

  // Rezervace/objednávky, u kterých už platba reálně dorazila (existuje DP/KF)
  const received = nonTest.filter(i => !isVoidInvoice(i) && INVOICE_RECEIVED_TYPES.includes(i.type))
  const paidBookings = new Set(received.filter(i => i.booking_id).map(i => i.booking_id))
  const paidOrders = new Set(received.filter(i => i.order_id).map(i => i.order_id))

  const unpaidInvoices = nonTest
    .filter(i => INVOICE_PROFORMA_TYPES.includes(i.type) && !isVoidInvoice(i) && i.status !== 'paid')
    .filter(i => !(i.booking_id && paidBookings.has(i.booking_id)) && !(i.order_id && paidOrders.has(i.order_id)))
  const unpaid = unpaidInvoices.reduce((s, i) => s + (i.total || 0), 0)

  return {
    total: nonTest.length,
    paid,
    unpaid,
    unpaidCount: unpaidInvoices.length,
    cancelled: nonTest.filter(i => i.status === 'cancelled').length,
  }
}
