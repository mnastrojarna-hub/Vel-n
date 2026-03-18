import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') || ''

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const SYSTEM_PROMPT = `Jsi AI asistent pro řízení půjčovny motorek MotoGo24 (Velín = superadmin dashboard).
Firma: Bc. Petra Semorádová, IČO: 21874263, Mezná 9, 393 01.
Kontakt: +420 774 256 271, info@motogo24.cz, https://motogo24.cz

Máš přístup ke KOMPLETNÍM aktuálním datům z databáze — rezervace, tržby, flotila motorek, SOS incidenty, pobočky, zákazníci, e-shop objednávky, vouchery, promo kódy, servisní plány, faktury a denní statistiky. Data ti budou předána jako kontext.

Tvoje schopnosti:
- Analýza tržeb a porovnání s minulým měsícem
- Kompletní přehled flotily (stav motorek, nájezd, blížící se servisy)
- Správa a přehled poboček (otevřené/zavřené, počet motorek)
- Přehled SOS incidentů (aktivní, závažnost, stav náhrad)
- Statistiky zákazníků (počet, noví zákazníci)
- E-shop objednávky a vouchery
- Promo kódy a jejich využití
- Fakturace a platební přehled
- Servisní plány a údržba
- Denní statistiky a trendy

Odpovídej stručně, prakticky a v češtině. Používej čísla a konkrétní data z kontextu. Pokud se ptají na něco co v datech nemáš, řekni to upřímně.`

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}

async function fetchDbContext(supabaseAdmin: ReturnType<typeof createClient>): Promise<string> {
  try {
    const now = new Date()
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).toISOString()
    const prevMonthStart = new Date(now.getFullYear(), now.getMonth() - 1, 1).toISOString()
    const weekAgo = new Date(now.getTime() - 7 * 86400000).toISOString()
    const today = now.toISOString().slice(0, 10)

    const [
      bookingsActiveRes,
      bookingsReservedRes,
      bookingsPendingRes,
      bookingsCompletedMonthRes,
      bookingsCancelledMonthRes,
      revenueThisMonthRes,
      revenuePrevMonthRes,
      motosRes,
      sosActiveRes,
      sosAllMonthRes,
      branchesRes,
      profilesCountRes,
      profilesRecentRes,
      shopOrdersRes,
      vouchersActiveRes,
      maintenanceUpcomingRes,
      serviceOrdersRes,
      invoicesRecentRes,
      promoCodesRes,
      dailyStatsRes,
      bookingsDetailRes,
      sosDetailRes,
    ] = await Promise.all([
      // Booking counts by status
      supabaseAdmin.from('bookings').select('id', { count: 'exact', head: true }).eq('status', 'active'),
      supabaseAdmin.from('bookings').select('id', { count: 'exact', head: true }).eq('status', 'reserved'),
      supabaseAdmin.from('bookings').select('id', { count: 'exact', head: true }).eq('status', 'pending'),
      supabaseAdmin.from('bookings').select('id', { count: 'exact', head: true }).eq('status', 'completed').gte('updated_at', monthStart),
      supabaseAdmin.from('bookings').select('id', { count: 'exact', head: true }).eq('status', 'cancelled').gte('updated_at', monthStart),
      // Revenue this month & previous
      supabaseAdmin.from('bookings').select('total_price').eq('payment_status', 'paid').gte('created_at', monthStart),
      supabaseAdmin.from('bookings').select('total_price').eq('payment_status', 'paid').gte('created_at', prevMonthStart).lt('created_at', monthStart),
      // Fleet — all motorcycles
      supabaseAdmin.from('motorcycles').select('id, model, spz, status, branch_id, mileage, next_service_date, category, brand'),
      // SOS
      supabaseAdmin.from('sos_incidents').select('id, type, severity, status, title, created_at, moto_id').not('status', 'in', '("resolved","closed")'),
      supabaseAdmin.from('sos_incidents').select('id', { count: 'exact', head: true }).gte('created_at', monthStart),
      // Branches
      supabaseAdmin.from('branches').select('id, name, branch_code, is_open, type'),
      // Customers
      supabaseAdmin.from('profiles').select('id', { count: 'exact', head: true }),
      supabaseAdmin.from('profiles').select('id, full_name, email, created_at').order('created_at', { ascending: false }).limit(5),
      // Shop orders
      supabaseAdmin.from('shop_orders').select('id, order_number, status, payment_status, total_amount, created_at').order('created_at', { ascending: false }).limit(10),
      // Vouchers
      supabaseAdmin.from('vouchers').select('id, code, amount, status, valid_until').eq('status', 'active'),
      // Maintenance
      supabaseAdmin.from('motorcycles').select('id, model, spz, next_service_date, mileage').not('next_service_date', 'is', null).order('next_service_date', { ascending: true }).limit(10),
      // Service orders
      supabaseAdmin.from('service_orders').select('id, moto_id, status, created_at').in('status', ['pending', 'in_service']),
      // Recent invoices
      supabaseAdmin.from('invoices').select('id, number, type, total, status, issued_at').order('issued_at', { ascending: false }).limit(10),
      // Promo codes
      supabaseAdmin.from('promo_codes').select('id, code, type, discount_value, is_active, used_count, max_uses, valid_to').eq('is_active', true),
      // Daily stats (last 7 days)
      supabaseAdmin.from('daily_stats').select('*').gte('date', weekAgo).order('date', { ascending: false }).limit(7),
      // Active bookings detail
      supabaseAdmin.from('bookings').select('id, start_date, end_date, total_price, payment_status, moto_id, user_id, status, pickup_method, return_method, booking_source').in('status', ['active', 'reserved', 'pending']).order('start_date', { ascending: true }).limit(30),
      // SOS detail for active
      supabaseAdmin.from('sos_incidents').select('id, type, severity, status, title, description, created_at, moto_id, booking_id, address, customer_decision, replacement_status').not('status', 'in', '("resolved","closed")'),
    ])

    const revenueThisMonth = (revenueThisMonthRes.data || []).reduce((s: number, b: { total_price: number | null }) => s + (b.total_price || 0), 0)
    const revenuePrevMonth = (revenuePrevMonthRes.data || []).reduce((s: number, b: { total_price: number | null }) => s + (b.total_price || 0), 0)

    const motos = motosRes.data || []
    const motosByStatus: Record<string, number> = {}
    motos.forEach((m: { status: string }) => { motosByStatus[m.status] = (motosByStatus[m.status] || 0) + 1 })

    const parts: string[] = []

    // 1. Bookings summary
    parts.push(`== REZERVACE ==
Aktivní: ${bookingsActiveRes.count || 0}, Nadcházející (reserved): ${bookingsReservedRes.count || 0}, Čekající (pending): ${bookingsPendingRes.count || 0}
Dokončeno tento měsíc: ${bookingsCompletedMonthRes.count || 0}, Stornováno tento měsíc: ${bookingsCancelledMonthRes.count || 0}`)

    // Booking details
    const bkgs = bookingsDetailRes.data || []
    if (bkgs.length > 0) {
      parts.push('Aktuální rezervace (detail):')
      bkgs.forEach((b: Record<string, unknown>) => {
        parts.push(`  - ${(b.status as string).toUpperCase()} | ${b.start_date}→${b.end_date} | ${b.total_price} Kč | platba: ${b.payment_status} | moto: ${(b.moto_id as string)?.slice(-6) || '?'} | zdroj: ${b.booking_source || 'app'}`)
      })
    }

    // 2. Revenue
    parts.push(`\n== TRŽBY ==
Tento měsíc: ${revenueThisMonth.toLocaleString('cs-CZ')} Kč
Minulý měsíc: ${revenuePrevMonth.toLocaleString('cs-CZ')} Kč
Změna: ${revenuePrevMonth > 0 ? ((revenueThisMonth / revenuePrevMonth - 1) * 100).toFixed(1) + '%' : 'N/A'}`)

    // 3. Fleet
    parts.push(`\n== FLOTILA (${motos.length} motorek) ==
Stavy: ${Object.entries(motosByStatus).map(([s, c]) => `${s}: ${c}`).join(', ')}`)
    motos.forEach((m: Record<string, unknown>) => {
      const svc = m.next_service_date ? ` | příští servis: ${m.next_service_date}` : ''
      parts.push(`  - ${m.brand || ''} ${m.model} (${m.spz}) — ${m.status} | ${m.mileage || '?'} km${svc}`)
    })

    // 4. SOS
    const sosActive = sosDetailRes.data || []
    parts.push(`\n== SOS INCIDENTY ==
Aktivních: ${sosActive.length}, Celkem tento měsíc: ${sosAllMonthRes.count || 0}`)
    sosActive.forEach((s: Record<string, unknown>) => {
      parts.push(`  - [${s.severity}] ${s.type}: ${s.title || s.description || 'bez popisu'} | status: ${s.status} | ${s.address || 'bez adresy'} | náhrada: ${s.replacement_status || 'N/A'}`)
    })

    // 5. Branches
    const branches = branchesRes.data || []
    parts.push(`\n== POBOČKY (${branches.length}) ==`)
    branches.forEach((b: Record<string, unknown>) => {
      const motosAtBranch = motos.filter((m: Record<string, unknown>) => m.branch_id === b.id).length
      parts.push(`  - ${b.name} (${b.branch_code}) — ${b.is_open ? 'OTEVŘENÁ' : 'ZAVŘENÁ'} | typ: ${b.type || '?'} | motorek: ${motosAtBranch}`)
    })

    // 6. Customers
    parts.push(`\n== ZÁKAZNÍCI ==
Celkem: ${profilesCountRes.count || 0}
Poslední registrace:`)
    ;(profilesRecentRes.data || []).forEach((p: Record<string, unknown>) => {
      parts.push(`  - ${p.full_name || p.email} (${new Date(p.created_at as string).toLocaleDateString('cs-CZ')})`)
    })

    // 7. E-shop orders
    const orders = shopOrdersRes.data || []
    if (orders.length > 0) {
      parts.push(`\n== E-SHOP OBJEDNÁVKY (posledních ${orders.length}) ==`)
      orders.forEach((o: Record<string, unknown>) => {
        parts.push(`  - ${o.order_number} | ${o.status} | ${o.payment_status} | ${o.total_amount} Kč | ${new Date(o.created_at as string).toLocaleDateString('cs-CZ')}`)
      })
    }

    // 8. Vouchers
    const vouchers = vouchersActiveRes.data || []
    parts.push(`\n== VOUCHERY ==
Aktivních: ${vouchers.length}`)
    if (vouchers.length > 0) {
      const totalValue = vouchers.reduce((s: number, v: { amount: number | null }) => s + (v.amount || 0), 0)
      parts.push(`Celková hodnota aktivních: ${totalValue.toLocaleString('cs-CZ')} Kč`)
      vouchers.forEach((v: Record<string, unknown>) => {
        parts.push(`  - ${v.code}: ${v.amount} Kč | platný do: ${v.valid_until || '?'}`)
      })
    }

    // 9. Maintenance / Service
    const upcomingSvc = (maintenanceUpcomingRes.data || []).filter((m: Record<string, unknown>) => (m.next_service_date as string) <= new Date(now.getTime() + 30 * 86400000).toISOString().slice(0, 10))
    const svcOrders = serviceOrdersRes.data || []
    parts.push(`\n== SERVIS ==
Motorky s blížícím se servisem (do 30 dní): ${upcomingSvc.length}`)
    upcomingSvc.forEach((m: Record<string, unknown>) => {
      parts.push(`  - ${m.model} (${m.spz}) — servis: ${m.next_service_date} | km: ${m.mileage || '?'}`)
    })
    if (svcOrders.length > 0) {
      parts.push(`Aktivní servisní objednávky: ${svcOrders.length}`)
    }

    // 10. Invoices
    const invoices = invoicesRecentRes.data || []
    if (invoices.length > 0) {
      parts.push(`\n== FAKTURY (posledních ${invoices.length}) ==`)
      invoices.forEach((inv: Record<string, unknown>) => {
        parts.push(`  - ${inv.number} | ${inv.type} | ${inv.total} Kč | ${inv.status} | ${inv.issued_at ? new Date(inv.issued_at as string).toLocaleDateString('cs-CZ') : ''}`)
      })
    }

    // 11. Promo codes
    const promos = promoCodesRes.data || []
    if (promos.length > 0) {
      parts.push(`\n== PROMO KÓDY (aktivní: ${promos.length}) ==`)
      promos.forEach((p: Record<string, unknown>) => {
        parts.push(`  - ${p.code}: ${p.type === 'percent' ? p.discount_value + '%' : p.discount_value + ' Kč'} | použito: ${p.used_count}/${p.max_uses || '∞'} | do: ${p.valid_to || 'neomezeno'}`)
      })
    }

    // 12. Daily stats
    const stats = dailyStatsRes.data || []
    if (stats.length > 0) {
      parts.push(`\n== DENNÍ STATISTIKY (posledních ${stats.length} dní) ==`)
      stats.forEach((s: Record<string, unknown>) => {
        parts.push(`  - ${s.date}: tržby ${s.revenue || 0} Kč | rezervací: ${s.bookings_count || 0} | nových zákazníků: ${s.new_customers || 0}`)
      })
    }

    return parts.join('\n')
  } catch (e) {
    console.error('fetchDbContext error:', e)
    return 'Kontext databáze nedostupný.'
  }
}

// Merge consecutive same-role messages (Anthropic API requires alternating roles)
function mergeConsecutiveMessages(msgs: Array<{ role: string; content: string }>) {
  const merged: Array<{ role: string; content: string }> = []
  for (const m of msgs) {
    if (merged.length > 0 && merged[merged.length - 1].role === m.role) {
      merged[merged.length - 1].content += '\n\n' + m.content
    } else {
      merged.push({ ...m })
    }
  }
  return merged
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    console.log('ai-copilot: request received')

    if (!ANTHROPIC_API_KEY) {
      console.error('ai-copilot: ANTHROPIC_API_KEY not configured')
      return jsonResponse({ error: 'ANTHROPIC_API_KEY not configured' }, 500)
    }

    const body = await req.json()
    const message = body?.message
    const conversation_id = body?.conversation_id

    if (!message || typeof message !== 'string') {
      return jsonResponse({ error: 'Missing message' }, 400)
    }

    // Verify JWT using service role client (avoids SUPABASE_ANON_KEY dependency)
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return jsonResponse({ error: 'Unauthorized: missing auth header' }, 401)
    }

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: userErr } = await supabaseAdmin.auth.getUser(token)
    if (userErr || !user) {
      console.error('ai-copilot: auth failed', userErr?.message)
      return jsonResponse({ error: 'Unauthorized: ' + (userErr?.message || 'invalid token') }, 401)
    }

    console.log('ai-copilot: authenticated user', user.id)

    // Load DB context
    const dbContext = await fetchDbContext(supabaseAdmin)
    console.log('ai-copilot: db context loaded')

    // Load conversation history if exists
    let conversationMessages: Array<{ role: string; content: string }> = []
    if (conversation_id) {
      const { data: conv } = await supabaseAdmin
        .from('ai_conversations')
        .select('messages')
        .eq('id', conversation_id)
        .single()
      if (conv?.messages && Array.isArray(conv.messages)) {
        // Take only last 10 messages to avoid token limits
        const recent = conv.messages.slice(-10)
        conversationMessages = recent
          .filter((m: { role: string }) => m.role === 'user' || m.role === 'assistant')
          .map((m: { role: string; content: string }) => ({ role: m.role, content: m.content }))
      }
    }

    // Build messages — put DB context into system prompt instead of user message
    const systemWithContext = SYSTEM_PROMPT + '\n\n' + dbContext

    // Ensure alternating roles
    const rawMessages = [
      ...conversationMessages,
      { role: 'user', content: message },
    ]
    const apiMessages = mergeConsecutiveMessages(rawMessages)

    // Ensure first message is from user
    if (apiMessages.length === 0 || apiMessages[0].role !== 'user') {
      apiMessages.unshift({ role: 'user', content: message })
    }

    console.log('ai-copilot: calling Anthropic API, messages:', apiMessages.length)

    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        model: 'claude-sonnet-4-20250514',
        max_tokens: 2048,
        system: systemWithContext,
        messages: apiMessages,
      }),
    })

    if (!response.ok) {
      const errText = await response.text()
      console.error('Anthropic API error:', response.status, errText)
      return jsonResponse({ error: 'AI service error', status: response.status, details: errText }, 502)
    }

    const aiResult = await response.json()
    const aiText = aiResult.content?.[0]?.text || 'Odpověď nedostupná.'

    console.log('ai-copilot: success, response length:', aiText.length)

    return jsonResponse({ response: aiText })

  } catch (err) {
    console.error('ai-copilot error:', (err as Error).message, (err as Error).stack)
    return jsonResponse({ error: (err as Error).message }, 500)
  }
})
