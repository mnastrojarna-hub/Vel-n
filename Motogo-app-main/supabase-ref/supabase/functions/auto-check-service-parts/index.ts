import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

  try {
    // 1. Run the RPC that checks inventory and creates draft purchase orders
    const { data: rpcResult, error: rpcErr } = await sb.rpc('auto_check_service_parts')
    if (rpcErr) throw rpcErr

    const createdOrders = rpcResult?.created_orders || 0
    if (createdOrders === 0) {
      await sb.from('debug_log').insert({
        source: 'auto-check-service-parts',
        action: 'check_completed',
        component: 'edge_function',
        status: 'ok',
        request_data: { created_orders: 0, message: 'No parts need ordering' },
      })
      return json({ success: true, created_orders: 0, emails_sent: 0 })
    }

    // 2. Find all draft orders created in last 5 minutes (the ones we just created)
    const fiveMinAgo = new Date(Date.now() - 5 * 60 * 1000).toISOString()
    const { data: newOrders } = await sb
      .from('purchase_orders')
      .select('id, order_number, notes, supplier_id, suppliers(name, contact_email)')
      .eq('status', 'draft')
      .gte('created_at', fiveMinAgo)

    let emailsSent = 0

    // 3. For each new order, load items and send email
    for (const order of (newOrders || [])) {
      const supplierEmail = (order.suppliers as any)?.contact_email
      if (!supplierEmail) continue

      const { data: items } = await sb
        .from('purchase_order_items')
        .select('quantity, unit_price, inventory(name, sku)')
        .eq('order_id', order.id)

      const emailItems = (items || []).map((it: any) => ({
        name: it.inventory?.name || 'Neznámá položka',
        sku: it.inventory?.sku || '',
        quantity: it.quantity,
        unit_price: it.unit_price,
      }))

      if (!emailItems.length) continue

      // Send email via the existing send-order-email function
      const { error: emailErr } = await sb.functions.invoke('send-order-email', {
        body: {
          supplier_email: supplierEmail,
          supplier_name: (order.suppliers as any)?.name || 'Dodavatel',
          items: emailItems,
          notes: order.notes || '',
          order_id: order.id,
          order_number: order.order_number || undefined,
        },
      })

      if (emailErr) {
        await sb.from('debug_log').insert({
          source: 'auto-check-service-parts',
          action: 'email_failed',
          component: 'edge_function',
          status: 'error',
          error_message: emailErr.message,
          request_data: { order_id: order.id },
        })
      } else {
        emailsSent++
      }
    }

    await sb.from('debug_log').insert({
      source: 'auto-check-service-parts',
      action: 'auto_order_completed',
      component: 'edge_function',
      status: 'ok',
      request_data: { created_orders: createdOrders, emails_sent: emailsSent },
    })

    return json({ success: true, created_orders: createdOrders, emails_sent: emailsSent })
  } catch (e) {
    try {
      await sb.from('debug_log').insert({
        source: 'auto-check-service-parts',
        action: 'auto_order_failed',
        component: 'edge_function',
        status: 'error',
        error_message: (e as Error).message,
      })
    } catch {}
    return json({ error: (e as Error).message }, 500)
  }
})
