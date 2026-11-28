// ===== process-payment/voucher-order.ts =====
// Založení objednávky DÁRKOVÉHO POUKAZU z webu (shop_orders + shop_order_items) — JEDNO místo pro platbu
// kartou (handleWebShopCheckout) i převodem / QR (bank-shop.ts): stejné sloupce, stejné položky, liší se
// jen `payment_method` ('stripe' | 'bank_transfer'). Tělo je 1:1 původní blok z payment-flows.ts.
import { resolveSiteLang } from './stripe-customer.ts'

// deno-lint-ignore no-explicit-any
type Sb = any

export type VoucherOrderInput = {
  orderId: string; paymentMethod: 'stripe' | 'bank_transfer'
  customerName: string; customerEmail: string; customerPhone: string
  shippingAddress: string; billingAddress: string; customerCompany: string; customerIco: string; customerDic: string
  amountCzk: number; voucherAmount: number; isPrint: boolean; printFee: number; discount: number
  quote: Record<string, unknown> | null; locale: string | null | undefined
}

/** Vloží objednávku a položky. Chyba vložení objednávky → { error } (+ záznam do debug_log jako dřív). */
export async function insertVoucherOrder(supabaseAdmin: Sb, v: VoucherOrderInput): Promise<{ error: string | null }> {
  // payment_status musí matchovat CHECK constraint shop_orders → pending/paid/refunded/failed.
  // Dříve zde bylo 'unpaid' (legacy z bookings.payment_status enum), což CHECK porušuje a INSERT
  // tiše selhal — voucher se pak nikdy nevytvořil a po Stripe platbě nedorazil mail.
  const { error: insertOrderError } = await supabaseAdmin.from('shop_orders').insert({
    id: v.orderId,
    customer_name: v.customerName,
    customer_email: v.customerEmail,
    customer_phone: v.customerPhone,
    shipping_address: v.shippingAddress || null,
    billing_address: v.billingAddress || null,
    customer_company: v.customerCompany || null,
    customer_ico: v.customerIco || null,
    customer_dic: v.customerDic || null,
    status: 'new',
    payment_status: 'pending',
    payment_method: v.paymentMethod,
    total: v.amountCzk,
    subtotal: v.voucherAmount,
    // POZN: printFee NEDÁVÁME do shipping_cost — jinak generate-invoice
    // ho zobrazí 2× (jako "Doprava" + jako shop_order_item "Tisk a poštovné").
    // Položka "Tisk a poštovné" je v shop_order_items níže (isPrint branch).
    shipping_cost: 0,
    discount: v.discount,
    ...(v.quote ? { promo_code_id: v.quote.promo_code_id ?? null, discount_codes: v.quote.discount_codes ?? null } : {}),
    notes: v.isPrint ? 'Fyzický poukaz (tisk + poštovné)' : 'Elektronický poukaz',
    // i18n: jazyk zákazníka z webu (cs/en/de/nl/es/fr/pl) → voucher_purchased mail
    // i SMS dorazí přeložené (detect_customer_language čte shop_orders.language).
    language: resolveSiteLang(v.locale),
  })
  if (insertOrderError) {
    console.error('[WebShopCheckout] shop_orders insert failed:', insertOrderError.message)
    try {
      await supabaseAdmin.from('debug_log').insert({
        source: 'process-payment',
        action: 'web_shop_order_insert_failed',
        component: 'voucher_checkout',
        status: 'error',
        error_message: insertOrderError.message,
        request_data: { order_id: v.orderId, customer_email: v.customerEmail, voucher_amount: v.voucherAmount, is_print: v.isPrint },
      })
    } catch { /* ignore */ }
    return { error: insertOrderError.message }
  }

  // Hlavní položka: dárkový poukaz
  const orderItems: Record<string, unknown>[] = [{
    order_id: v.orderId,
    product_name: 'Dárkový poukaz',
    quantity: 1,
    unit_price: v.voucherAmount,
    total_price: v.voucherAmount,
  }]

  // Fyzický tisk + poštovné (název BEZ "poukaz" aby trigger negeneroval voucher)
  if (v.isPrint) {
    orderItems.push({
      order_id: v.orderId,
      product_name: 'Tisk a poštovné',
      quantity: 1,
      unit_price: v.printFee,
      total_price: v.printFee,
    })
  }

  await supabaseAdmin.from('shop_order_items').insert(orderItems)
  return { error: null }
}
