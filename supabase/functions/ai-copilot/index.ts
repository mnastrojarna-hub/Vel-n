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

const SYSTEM_PROMPT = `Jsi AI asistent pro řízení půjčovny motorek MotoGo24 (Velín dashboard). Firma: Bc. Petra Semorádová, IČO: 21874263, Mezná 9.
Máš přístup k aktuálním datům z databáze které ti budou předány jako kontext.
Odpovídej stručně, prakticky a v češtině. Pomáháš s: analýzou tržeb, správou flotily, plánováním servisů, řešením SOS, statistikami zákazníků.`

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

    const [bookingsRes, revenueRes, maintenanceRes, sosRes] = await Promise.all([
      supabaseAdmin.from('bookings')
        .select('id', { count: 'exact', head: true })
        .in('status', ['active', 'reserved']),
      supabaseAdmin.from('bookings')
        .select('total_price')
        .eq('payment_status', 'paid')
        .gte('created_at', monthStart),
      supabaseAdmin.from('motorcycles')
        .select('id', { count: 'exact', head: true })
        .eq('status', 'maintenance'),
      supabaseAdmin.from('sos_incidents')
        .select('id', { count: 'exact', head: true })
        .not('status', 'in', '("resolved","closed")'),
    ])

    const activeBookings = bookingsRes.count || 0
    const revenue = (revenueRes.data || []).reduce((sum: number, b: { total_price: number | null }) => sum + (b.total_price || 0), 0)
    const maintenanceCount = maintenanceRes.count || 0
    const activeSos = sosRes.count || 0

    return `Aktuální stav: ${activeBookings} aktivních rezervací, tržby tento měsíc ${revenue.toLocaleString('cs-CZ')} Kč, ${maintenanceCount} motorek v servisu, ${activeSos} aktivních SOS incidentů.`
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

    // Verify JWT
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return jsonResponse({ error: 'Unauthorized' }, 401)
    }

    const supabaseAnon = createClient(SUPABASE_URL, Deno.env.get('SUPABASE_ANON_KEY') || '', {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: { user }, error: userErr } = await supabaseAnon.auth.getUser()
    if (userErr || !user) {
      console.error('ai-copilot: auth failed', userErr?.message)
      return jsonResponse({ error: 'Unauthorized' }, 401)
    }

    console.log('ai-copilot: authenticated user', user.id)

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

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
        max_tokens: 1024,
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
