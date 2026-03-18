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

async function fetchDbContext(supabaseAdmin: ReturnType<typeof createClient>): Promise<string> {
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
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    const { message, conversation_id } = await req.json()

    if (!message || typeof message !== 'string') {
      return new Response(JSON.stringify({ error: 'Missing message' }), {
        status: 400, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    // Verify JWT
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    const supabaseAnon = createClient(SUPABASE_URL, Deno.env.get('SUPABASE_ANON_KEY') || '', {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: { user }, error: userErr } = await supabaseAnon.auth.getUser()
    if (userErr || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    // Load DB context
    const dbContext = await fetchDbContext(supabaseAdmin)

    // Load conversation history if exists
    let conversationMessages: Array<{ role: string; content: string }> = []
    if (conversation_id) {
      const { data: conv } = await supabaseAdmin
        .from('ai_conversations')
        .select('messages')
        .eq('id', conversation_id)
        .single()
      if (conv?.messages && Array.isArray(conv.messages)) {
        conversationMessages = conv.messages
          .filter((m: { role: string }) => m.role === 'user' || m.role === 'assistant')
          .map((m: { role: string; content: string }) => ({ role: m.role, content: m.content }))
      }
    }

    // Build messages for Claude
    const apiMessages = [
      { role: 'user', content: dbContext },
      ...conversationMessages,
      { role: 'user', content: message },
    ]

    if (!ANTHROPIC_API_KEY) {
      return new Response(JSON.stringify({ error: 'ANTHROPIC_API_KEY not configured' }), {
        status: 500, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

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
        system: SYSTEM_PROMPT,
        messages: apiMessages,
      }),
    })

    if (!response.ok) {
      const errText = await response.text()
      console.error('Anthropic API error:', response.status, errText)
      return new Response(JSON.stringify({ error: 'AI service error', details: errText }), {
        status: 502, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    const aiResult = await response.json()
    const aiText = aiResult.content?.[0]?.text || 'Odpověď nedostupná.'

    return new Response(JSON.stringify({ response: aiText }), {
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })

  } catch (err) {
    console.error('ai-copilot error:', err)
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 500, headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }
})
