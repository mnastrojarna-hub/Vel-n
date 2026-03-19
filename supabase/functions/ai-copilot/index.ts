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

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}

// ---------------------------------------------------------------------------
// SYSTEM PROMPT
// ---------------------------------------------------------------------------

const SYSTEM_PROMPT = `Jsi AI Copilot pro Velín — superadmin dashboard půjčovny motorek MotoGo24.
Firma: Bc. Petra Semorádová, IČO: 21874263, Mezná 9, 393 01. Kontakt: +420 774 256 271, info@motogo24.cz

Máš k dispozici nástroje pro přístup ke kompletní databázi v reálném čase.
VŽDY si nejdřív sáhni pro data přes nástroj než odpovíš — nehádej, nevymýšlej čísla.
Můžeš volat více nástrojů najednou (parallel tool use).

Tvoje oblasti:
- Tržby a finance (měsíční přehledy, porovnání, fakturace)
- Flotila motorek (stavy, nájezdy, servisy, pobočky)
- Rezervace (aktivní, nadcházející, čekající, historie)
- SOS incidenty (aktivní, závažnost, náhrady)
- Pobočky (otevřené/zavřené, počty motorek, příslušenství)
- Zákazníci (profily, historie rezervací, dokumenty)
- E-shop a vouchery (objednávky, dárkové poukazy)
- Promo kódy (aktivní, využití)
- Fakturace (zálohové, konečné, proforma)
- Servis a údržba (blížící se servisy, servisní objednávky)
- Zprávy (konverzace se zákazníky, nepřečtené)
- Denní statistiky (tržby, rezervace, trendy)

Odpovídej v češtině, stručně, s konkrétními čísly z dat. Pokud data nemáš, řekni to upřímně.`

// ---------------------------------------------------------------------------
// TOOLS DEFINITION — 15 nástrojů pro Anthropic tool-use API
// ---------------------------------------------------------------------------

const TOOLS_DEFINITION = [
  {
    name: 'get_bookings_summary',
    description: 'Počty rezervací podle stavu + tržby za aktuální a minulý měsíc',
    input_schema: {
      type: 'object' as const,
      properties: {},
      required: [],
    },
  },
  {
    name: 'get_bookings_detail',
    description: 'Seznam rezervací s filtrem',
    input_schema: {
      type: 'object' as const,
      properties: {
        status: { type: 'string', description: 'Filtr dle stavu (pending, reserved, active, completed, cancelled)' },
        limit: { type: 'number', description: 'Max počet výsledků (default 20)' },
        date_from: { type: 'string', description: 'Od data (YYYY-MM-DD)' },
        date_to: { type: 'string', description: 'Do data (YYYY-MM-DD)' },
      },
      required: [],
    },
  },
  {
    name: 'get_fleet_overview',
    description: 'Všechny motorky se stavem, nájezdem, pobočkou',
    input_schema: {
      type: 'object' as const,
      properties: {
        status: { type: 'string', description: 'Filtr dle stavu (active, rented, maintenance, unavailable, retired)' },
        branch_id: { type: 'string', description: 'Filtr dle ID pobočky' },
      },
      required: [],
    },
  },
  {
    name: 'get_motorcycle_detail',
    description: 'Detail jedné motorky + její rezervace a servis',
    input_schema: {
      type: 'object' as const,
      properties: {
        motorcycle_id: { type: 'string', description: 'UUID motorky' },
        spz: { type: 'string', description: 'SPZ motorky' },
        model_search: { type: 'string', description: 'Hledání dle modelu' },
      },
      required: [],
    },
  },
  {
    name: 'get_sos_incidents',
    description: 'SOS incidenty s detaily',
    input_schema: {
      type: 'object' as const,
      properties: {
        status: { type: 'string', description: 'Filtr dle stavu (reported, acknowledged, in_progress, resolved, closed)' },
        limit: { type: 'number', description: 'Max počet výsledků (default 20)' },
      },
      required: [],
    },
  },
  {
    name: 'get_branches',
    description: 'Pobočky s počty motorek',
    input_schema: {
      type: 'object' as const,
      properties: {},
      required: [],
    },
  },
  {
    name: 'get_customers',
    description: 'Přehled zákazníků',
    input_schema: {
      type: 'object' as const,
      properties: {
        search: { type: 'string', description: 'Hledání dle jména nebo emailu' },
        limit: { type: 'number', description: 'Max počet výsledků (default 20)' },
      },
      required: [],
    },
  },
  {
    name: 'get_customer_detail',
    description: 'Kompletní profil zákazníka + rezervace + dokumenty',
    input_schema: {
      type: 'object' as const,
      properties: {
        customer_id: { type: 'string', description: 'UUID zákazníka' },
        email: { type: 'string', description: 'Email zákazníka' },
        name_search: { type: 'string', description: 'Hledání dle jména' },
      },
      required: [],
    },
  },
  {
    name: 'get_financial_overview',
    description: 'Tržby, faktury, platby, vouchery',
    input_schema: {
      type: 'object' as const,
      properties: {
        period: { type: 'string', description: 'Období: today, week, month, quarter' },
      },
      required: [],
    },
  },
  {
    name: 'get_invoices',
    description: 'Seznam faktur',
    input_schema: {
      type: 'object' as const,
      properties: {
        status: { type: 'string', description: 'Filtr dle stavu' },
        type: { type: 'string', description: 'Filtr dle typu (issued, received, final, proforma, shop_proforma, shop_final, advance, payment_receipt)' },
        limit: { type: 'number', description: 'Max počet výsledků (default 20)' },
      },
      required: [],
    },
  },
  {
    name: 'get_shop_orders',
    description: 'E-shop objednávky',
    input_schema: {
      type: 'object' as const,
      properties: {
        status: { type: 'string', description: 'Filtr dle stavu (new, confirmed, processing, shipped, delivered, cancelled, returned, refunded)' },
        limit: { type: 'number', description: 'Max počet výsledků (default 20)' },
      },
      required: [],
    },
  },
  {
    name: 'get_vouchers_and_promos',
    description: 'Aktivní vouchery a promo kódy',
    input_schema: {
      type: 'object' as const,
      properties: {
        active_only: { type: 'boolean', description: 'Pouze aktivní (default true)' },
      },
      required: [],
    },
  },
  {
    name: 'get_service_status',
    description: 'Blížící se servisy + aktivní servisní objednávky',
    input_schema: {
      type: 'object' as const,
      properties: {
        days_ahead: { type: 'number', description: 'Počet dní dopředu (default 30)' },
      },
      required: [],
    },
  },
  {
    name: 'get_messages_overview',
    description: 'Přehled zpráv se zákazníky',
    input_schema: {
      type: 'object' as const,
      properties: {
        unread_only: { type: 'boolean', description: 'Pouze nepřečtené' },
        limit: { type: 'number', description: 'Max počet výsledků (default 20)' },
      },
      required: [],
    },
  },
  {
    name: 'get_daily_stats',
    description: 'Denní statistiky za období',
    input_schema: {
      type: 'object' as const,
      properties: {
        days: { type: 'number', description: 'Počet dní zpět (default 7)' },
      },
      required: [],
    },
  },
]

// ---------------------------------------------------------------------------
// TOOL EXECUTOR — TODO: implementace v dalším kroku
// ---------------------------------------------------------------------------

// deno-lint-ignore no-explicit-any
async function executeTool(_name: string, _input: Record<string, unknown>, _supabaseAdmin: any): Promise<string> {
  // TODO: Implementace všech 15 nástrojů (příští krok)
  return JSON.stringify({ error: 'Tool not implemented yet' })
}

// ---------------------------------------------------------------------------
// SERVE HANDLER
// ---------------------------------------------------------------------------

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    // 1. Parse body
    const body = await req.json()
    const message = body?.message
    const conversation_id = body?.conversation_id
    const conversation_history = body?.conversation_history

    if (!message || typeof message !== 'string') {
      return jsonResponse({ error: 'Missing message' }, 400)
    }

    if (!ANTHROPIC_API_KEY) {
      return jsonResponse({ error: 'ANTHROPIC_API_KEY not configured' }, 500)
    }

    // 2. JWT auth
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

    // 3. Load conversation history z ai_conversations (CELÁ, ne jen 10)
    let conversationMessages: Array<{ role: string; content: string }> = []

    if (conversation_history && Array.isArray(conversation_history)) {
      // Prefer client-supplied history if provided
      conversationMessages = conversation_history
        .filter((m: { role: string }) => m.role === 'user' || m.role === 'assistant')
        .map((m: { role: string; content: string }) => ({ role: m.role, content: m.content }))
    } else if (conversation_id) {
      const { data: conv } = await supabaseAdmin
        .from('ai_conversations')
        .select('messages')
        .eq('id', conversation_id)
        .single()
      if (conv?.messages && Array.isArray(conv.messages)) {
        // Load ALL messages — no limit
        conversationMessages = conv.messages
          .filter((m: { role: string }) => m.role === 'user' || m.role === 'assistant')
          .map((m: { role: string; content: string }) => ({ role: m.role, content: m.content }))
      }
    }

    // Build messages array — ensure alternating roles
    const rawMessages = [
      ...conversationMessages,
      { role: 'user', content: message },
    ]

    // Merge consecutive same-role messages (Anthropic API requires alternating roles)
    const apiMessages: Array<{ role: string; content: string }> = []
    for (const m of rawMessages) {
      if (apiMessages.length > 0 && apiMessages[apiMessages.length - 1].role === m.role) {
        apiMessages[apiMessages.length - 1].content += '\n\n' + m.content
      } else {
        apiMessages.push({ ...m })
      }
    }

    // Ensure first message is from user
    if (apiMessages.length === 0 || apiMessages[0].role !== 'user') {
      apiMessages.unshift({ role: 'user', content: message })
    }

    console.log('ai-copilot: messages count:', apiMessages.length)

    // 4. TODO: Agentic loop — volání Anthropic API s tools, iterace dokud stop_reason !== 'end_turn'
    //    - Poslat request s SYSTEM_PROMPT, apiMessages, TOOLS_DEFINITION
    //    - Pokud stop_reason === 'tool_use', zavolat executeTool() pro každý tool_use block
    //    - Přidat assistant response + tool results do messages
    //    - Opakovat dokud AI neodpoví textem (stop_reason === 'end_turn')
    //    - Max iterací: 10 (safety limit)

    // 5. TODO: Uložit konverzaci do ai_conversations

    // Temporary response until agentic loop is implemented
    void executeTool // suppress unused warning
    void TOOLS_DEFINITION // suppress unused warning

    return jsonResponse({ response: 'AI Copilot v2 — tools coming next' })

  } catch (err) {
    console.error('ai-copilot error:', err)
    return jsonResponse({ error: (err as Error).message }, 500)
  }
})
