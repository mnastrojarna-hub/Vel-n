import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') || ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const FROM_EMAIL = Deno.env.get('FROM_EMAIL') || 'noreply@motogo24.cz'

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

interface OrderItem {
  name: string
  sku?: string
  quantity: number
  unit_price?: number
}

interface OrderEmailRequest {
  supplier_email: string
  supplier_name: string
  items: OrderItem[]
  notes?: string
  order_id?: string
  order_number?: string
}

function buildOrderHtml(req: OrderEmailRequest): string {
  const itemRows = req.items.map(it => {
    const total = (it.quantity || 0) * (it.unit_price || 0)
    return `<tr>
      <td style="padding:8px 12px;border-bottom:1px solid #e5e7eb">${it.name}${it.sku ? ` <span style="color:#6b7280">(${it.sku})</span>` : ''}</td>
      <td style="padding:8px 12px;border-bottom:1px solid #e5e7eb;text-align:center">${it.quantity}</td>
      ${it.unit_price ? `<td style="padding:8px 12px;border-bottom:1px solid #e5e7eb;text-align:right">${Number(it.unit_price).toLocaleString('cs-CZ')} Kč</td>` : ''}
      ${it.unit_price ? `<td style="padding:8px 12px;border-bottom:1px solid #e5e7eb;text-align:right;font-weight:bold">${total.toLocaleString('cs-CZ')} Kč</td>` : ''}
    </tr>`
  }).join('')

  const grandTotal = req.items.reduce((s, it) => s + (it.quantity || 0) * (it.unit_price || 0), 0)
  const hasPrice = req.items.some(it => it.unit_price)

  return `<!DOCTYPE html><html lang="cs"><head><meta charset="UTF-8"></head>
<body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#f4f7f5;padding:32px">
  <div style="max-width:600px;margin:0 auto;background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,.08)">
    <div style="background:#1a2e22;padding:28px 32px;text-align:center">
      <h1 style="margin:0;color:#74FB71;font-size:22px;font-weight:900">MOTO GO 24</h1>
      <p style="color:#a7f3d0;font-size:13px;margin:8px 0 0 0">Objednávka materiálu</p>
    </div>
    <div style="padding:32px">
      <p style="color:#374151;font-size:14px;line-height:1.7">Dobrý den,</p>
      <p style="color:#374151;font-size:14px;line-height:1.7">rádi bychom objednali následující položky${req.order_number ? ` (č. obj. <strong>${req.order_number}</strong>)` : ''}:</p>

      <table style="width:100%;border-collapse:collapse;margin:20px 0;font-size:13px">
        <thead>
          <tr style="background:#f9fafb">
            <th style="padding:8px 12px;text-align:left;border-bottom:2px solid #d1d5db">Položka</th>
            <th style="padding:8px 12px;text-align:center;border-bottom:2px solid #d1d5db">Množství</th>
            ${hasPrice ? '<th style="padding:8px 12px;text-align:right;border-bottom:2px solid #d1d5db">Cena/ks</th>' : ''}
            ${hasPrice ? '<th style="padding:8px 12px;text-align:right;border-bottom:2px solid #d1d5db">Celkem</th>' : ''}
          </tr>
        </thead>
        <tbody>${itemRows}</tbody>
        ${hasPrice ? `<tfoot><tr style="background:#f0fdf4">
          <td colspan="3" style="padding:8px 12px;text-align:right;font-weight:bold">Celkem:</td>
          <td style="padding:8px 12px;text-align:right;font-weight:bold;color:#1a8a18">${grandTotal.toLocaleString('cs-CZ')} Kč</td>
        </tr></tfoot>` : ''}
      </table>

      ${req.notes ? `<p style="color:#374151;font-size:14px;line-height:1.7"><strong>Poznámka:</strong> ${req.notes}</p>` : ''}

      <p style="color:#374151;font-size:14px;line-height:1.7;margin-top:24px">Prosíme o potvrzení objednávky a předpokládaný termín dodání.</p>
      <p style="color:#374151;font-size:14px;line-height:1.7">Děkujeme,<br><strong>MotoGo24</strong></p>
    </div>
    <div style="background:#f9fafb;padding:16px 32px;text-align:center;border-top:1px solid #e5e7eb">
      <p style="color:#9ca3af;font-size:11px;margin:0">Bc. Petra Semorádová · IČO: 21874263 · info@motogo24.cz · +420 774 256 271</p>
    </div>
  </div>
</body></html>`
}

async function sendWithRetry(payload: Record<string, unknown>, retries = 3): Promise<Response> {
  for (let attempt = 1; attempt <= retries; attempt++) {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    })
    if (res.ok) return res
    if (attempt < retries) await new Promise(r => setTimeout(r, attempt * 2000))
  }
  throw new Error('Resend: all retries failed')
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })

  try {
    const body: OrderEmailRequest = await req.json()
    const { supplier_email, supplier_name, items, notes, order_id, order_number } = body

    if (!supplier_email || !items?.length) {
      return json({ error: 'Missing supplier_email or items' }, 400)
    }

    const html = buildOrderHtml(body)
    const subject = `Objednávka${order_number ? ` ${order_number}` : ''} — MotoGo24`

    await sendWithRetry({
      from: FROM_EMAIL,
      to: [supplier_email],
      subject,
      html,
    })

    // Log to DB
    const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    // Update purchase order status to 'sent' if order_id provided
    if (order_id) {
      await sb.from('purchase_orders').update({
        status: 'sent',
        sent_at: new Date().toISOString(),
      }).eq('id', order_id)
    }

    // Log the sent email
    await sb.from('debug_log').insert({
      source: 'send-order-email',
      action: 'order_email_sent',
      component: 'edge_function',
      status: 'ok',
      request_data: { supplier_email, supplier_name, order_number, item_count: items.length },
    })

    return json({ success: true, message: `Order email sent to ${supplier_email}` })
  } catch (e) {
    // Log failure
    try {
      const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)
      await sb.from('debug_log').insert({
        source: 'send-order-email',
        action: 'order_email_failed',
        component: 'edge_function',
        status: 'error',
        error_message: e.message,
      })
    } catch {}
    return json({ error: e.message }, 500)
  }
})
