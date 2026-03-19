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
// TOOLS DEFINITION — 25 nástrojů pro Anthropic tool-use API
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
  {
    name: 'get_inventory',
    description: 'Sklady — položky, zásoby, nízké stavy, dodavatelé',
    input_schema: {
      type: 'object' as const,
      properties: {
        search: { type: 'string', description: 'Hledání dle názvu nebo SKU' },
        low_stock_only: { type: 'boolean', description: 'Pouze položky s nízkým stavem' },
        category: { type: 'string', description: 'Filtr dle kategorie' },
        limit: { type: 'number', description: 'Max počet výsledků (default 50)' },
      },
      required: [],
    },
  },
  {
    name: 'get_inventory_movements',
    description: 'Pohyby skladu — příjmy, výdeje, korekce pro konkrétní položku nebo celkově',
    input_schema: {
      type: 'object' as const,
      properties: {
        item_id: { type: 'string', description: 'UUID skladové položky' },
        type: { type: 'string', description: 'Typ pohybu (receipt/issue/correction)' },
        limit: { type: 'number', description: 'Max počet výsledků (default 30)' },
      },
      required: [],
    },
  },
  {
    name: 'get_branch_detail',
    description: 'Kompletní detail pobočky: motorky s kojemi (box_number), příslušenství (helmy/boty/rukavice s velikostmi), aktivní přístupové kódy, aktivní rezervace na pobočce',
    input_schema: {
      type: 'object' as const,
      properties: {
        branch_id: { type: 'string', description: 'UUID pobočky' },
      },
      required: ['branch_id'],
    },
  },
  {
    name: 'get_documents',
    description: 'Dokumenty — smlouvy, šablony, vygenerované dokumenty, odeslané e-maily',
    input_schema: {
      type: 'object' as const,
      properties: {
        type: { type: 'string', description: 'Typ: contracts, templates, generated, emails' },
        search: { type: 'string', description: 'Hledání v dokumentech' },
        limit: { type: 'number', description: 'Max počet výsledků (default 20)' },
      },
      required: [],
    },
  },
  {
    name: 'get_reviews',
    description: 'Hodnocení zákazníků — recenze motorek a služeb',
    input_schema: {
      type: 'object' as const,
      properties: {
        moto_id: { type: 'string', description: 'UUID motorky pro filtraci' },
        min_rating: { type: 'number', description: 'Minimální hodnocení (1-5)' },
        limit: { type: 'number', description: 'Max počet výsledků (default 20)' },
      },
      required: [],
    },
  },
  {
    name: 'get_cms_settings',
    description: 'CMS nastavení — feature flagy, proměnné, app_settings',
    input_schema: {
      type: 'object' as const,
      properties: {
        section: { type: 'string', description: 'Sekce: flags, variables, settings' },
      },
      required: [],
    },
  },
  {
    name: 'get_audit_log',
    description: 'Audit log — historie akcí adminů (kdo, co, kdy)',
    input_schema: {
      type: 'object' as const,
      properties: {
        admin_id: { type: 'string', description: 'UUID admina' },
        action: { type: 'string', description: 'Filtr dle akce' },
        limit: { type: 'number', description: 'Max počet výsledků (default 30)' },
      },
      required: [],
    },
  },
  {
    name: 'get_government_overview',
    description: 'Státní správa — STK termíny, pojistky, přehled pro celou flotilu',
    input_schema: {
      type: 'object' as const,
      properties: {},
      required: [],
    },
  },
  {
    name: 'get_sos_detail',
    description: 'Detail SOS incidentu včetně timeline a workflow',
    input_schema: {
      type: 'object' as const,
      properties: {
        incident_id: { type: 'string', description: 'UUID SOS incidentu' },
      },
      required: ['incident_id'],
    },
  },
  {
    name: 'get_pricing_overview',
    description: 'Ceník — denní ceny motorek po dnech v týdnu, speciální ceny',
    input_schema: {
      type: 'object' as const,
      properties: {
        motorcycle_id: { type: 'string', description: 'UUID motorky (volitelné — bez něj vrátí ceník všech)' },
      },
      required: [],
    },
  },
]

// ---------------------------------------------------------------------------
// TOOL EXECUTOR — 25 provozních nástrojů
// ---------------------------------------------------------------------------

async function executeTool(
  toolName: string,
  toolInput: Record<string, unknown>,
  supabaseAdmin: ReturnType<typeof createClient>
): Promise<unknown> {
  const now = new Date()
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).toISOString()
  const prevMonthStart = new Date(now.getFullYear(), now.getMonth() - 1, 1).toISOString()
  const startTime = Date.now()

  try {
    let result: unknown

    switch (toolName) {

      // =====================================================================
      // 1. get_bookings_summary
      // =====================================================================
      case 'get_bookings_summary': {
        const [activeR, reservedR, pendingR, completedR, cancelledR, revThisR, revPrevR] = await Promise.all([
          supabaseAdmin.from('bookings').select('id', { count: 'exact', head: true }).eq('status', 'active'),
          supabaseAdmin.from('bookings').select('id', { count: 'exact', head: true }).eq('status', 'reserved'),
          supabaseAdmin.from('bookings').select('id', { count: 'exact', head: true }).eq('status', 'pending'),
          supabaseAdmin.from('bookings').select('id', { count: 'exact', head: true }).eq('status', 'completed').gte('updated_at', monthStart),
          supabaseAdmin.from('bookings').select('id', { count: 'exact', head: true }).eq('status', 'cancelled').gte('updated_at', monthStart),
          supabaseAdmin.from('bookings').select('total_price').eq('payment_status', 'paid').gte('created_at', monthStart),
          supabaseAdmin.from('bookings').select('total_price').eq('payment_status', 'paid').gte('created_at', prevMonthStart).lt('created_at', monthStart),
        ])

        const revThis = (revThisR.data || []).reduce((s: number, b: { total_price: number | null }) => s + (b.total_price || 0), 0)
        const revPrev = (revPrevR.data || []).reduce((s: number, b: { total_price: number | null }) => s + (b.total_price || 0), 0)

        result = {
          active: activeR.count || 0,
          reserved: reservedR.count || 0,
          pending: pendingR.count || 0,
          completed_this_month: completedR.count || 0,
          cancelled_this_month: cancelledR.count || 0,
          revenue_this_month: revThis,
          revenue_prev_month: revPrev,
          revenue_change_pct: revPrev > 0 ? Math.round((revThis / revPrev - 1) * 1000) / 10 : null,
        }
        break
      }

      // =====================================================================
      // 2. get_bookings_detail
      // =====================================================================
      case 'get_bookings_detail': {
        const limit = (toolInput.limit as number) || 20
        let query = supabaseAdmin.from('bookings')
          .select('id, user_id, moto_id, start_date, end_date, status, payment_status, total_price, pickup_method, return_method, booking_source, notes, created_at, pickup_time, promo_code, discount_amount, extras_price, deposit')
          .order('start_date', { ascending: false })
          .limit(limit)

        if (toolInput.status) query = query.eq('status', toolInput.status as string)
        if (toolInput.date_from) query = query.gte('start_date', toolInput.date_from as string)
        if (toolInput.date_to) query = query.lte('start_date', toolInput.date_to as string)

        const { data: bookings } = await query

        if (!bookings || bookings.length === 0) {
          result = { bookings: [], count: 0 }
          break
        }

        // Fetch motorcycle info
        const motoIds = [...new Set(bookings.map((b: Record<string, unknown>) => b.moto_id).filter(Boolean))]
        const { data: motos } = motoIds.length > 0
          ? await supabaseAdmin.from('motorcycles').select('id, model, brand, spz').in('id', motoIds)
          : { data: [] }
        const motoMap: Record<string, Record<string, unknown>> = {}
        for (const m of (motos || [])) motoMap[m.id] = m

        // Fetch customer names
        const userIds = [...new Set(bookings.map((b: Record<string, unknown>) => b.user_id).filter(Boolean))]
        const { data: profiles } = userIds.length > 0
          ? await supabaseAdmin.from('profiles').select('id, full_name, email, phone').in('id', userIds)
          : { data: [] }
        const profileMap: Record<string, Record<string, unknown>> = {}
        for (const p of (profiles || [])) profileMap[p.id] = p

        const enriched = bookings.map((b: Record<string, unknown>) => ({
          ...b,
          motorcycle: motoMap[b.moto_id as string] || null,
          customer: profileMap[b.user_id as string] || null,
        }))

        result = { bookings: enriched, count: enriched.length }
        break
      }

      // =====================================================================
      // 3. get_fleet_overview
      // =====================================================================
      case 'get_fleet_overview': {
        let query = supabaseAdmin.from('motorcycles')
          .select('id, model, brand, spz, vin, status, branch_id, mileage, category, year, next_service_date, price_weekday, price_weekend, image_url, color, deposit_amount, engine_cc, power_kw')

        if (toolInput.status) query = query.eq('status', toolInput.status as string)
        if (toolInput.branch_id) query = query.eq('branch_id', toolInput.branch_id as string)

        const { data: motos } = await query

        // Fetch branches for names
        const { data: branches } = await supabaseAdmin.from('branches').select('id, name, branch_code')
        const branchMap: Record<string, Record<string, unknown>> = {}
        for (const b of (branches || [])) branchMap[b.id] = b

        const byStatus: Record<string, number> = {}
        for (const m of (motos || [])) {
          const s = (m as Record<string, unknown>).status as string
          byStatus[s] = (byStatus[s] || 0) + 1
        }

        const enriched = (motos || []).map((m: Record<string, unknown>) => ({
          ...m,
          branch: branchMap[m.branch_id as string] || null,
        }))

        result = { total: enriched.length, by_status: byStatus, motorcycles: enriched }
        break
      }

      // =====================================================================
      // 4. get_motorcycle_detail
      // =====================================================================
      case 'get_motorcycle_detail': {
        let moto: Record<string, unknown> | null = null

        if (toolInput.motorcycle_id) {
          const { data } = await supabaseAdmin.from('motorcycles').select('*').eq('id', toolInput.motorcycle_id as string).single()
          moto = data
        } else if (toolInput.spz) {
          const { data } = await supabaseAdmin.from('motorcycles').select('*').ilike('spz', `%${toolInput.spz}%`).limit(1).single()
          moto = data
        } else if (toolInput.model_search) {
          const search = `%${toolInput.model_search}%`
          const { data } = await supabaseAdmin.from('motorcycles').select('*').or(`model.ilike.${search},brand.ilike.${search}`).limit(1)
          moto = data?.[0] || null
        }

        if (!moto) {
          result = { error: 'Motorka nenalezena' }
          break
        }

        const [bookingsR, serviceR] = await Promise.all([
          supabaseAdmin.from('bookings').select('id, start_date, end_date, status, payment_status, total_price, user_id').eq('moto_id', moto.id).order('start_date', { ascending: false }).limit(10),
          supabaseAdmin.from('service_orders').select('*').eq('moto_id', moto.id).order('created_at', { ascending: false }),
        ])

        result = {
          motorcycle: moto,
          recent_bookings: bookingsR.data || [],
          service_orders: serviceR.data || [],
        }
        break
      }

      // =====================================================================
      // 5. get_sos_incidents
      // =====================================================================
      case 'get_sos_incidents': {
        const limit = (toolInput.limit as number) || 20
        let query = supabaseAdmin.from('sos_incidents')
          .select('id, type, severity, status, title, description, created_at, moto_id, booking_id, user_id, address, customer_decision, replacement_status, customer_fault, damage_severity, resolved_at')
          .order('created_at', { ascending: false })
          .limit(limit)

        if (toolInput.status) query = query.eq('status', toolInput.status as string)

        const { data } = await query
        result = { incidents: data || [], count: (data || []).length }
        break
      }

      // =====================================================================
      // 6. get_branches
      // =====================================================================
      case 'get_branches': {
        const [branchesR, motosR] = await Promise.all([
          supabaseAdmin.from('branches').select('id, name, branch_code, is_open, type, created_at'),
          supabaseAdmin.from('motorcycles').select('id, branch_id, status'),
        ])

        const motos = motosR.data || []
        const branches = (branchesR.data || []).map((b: Record<string, unknown>) => {
          const branchMotos = motos.filter((m: Record<string, unknown>) => m.branch_id === b.id)
          return {
            ...b,
            total_motos: branchMotos.length,
            active_motos: branchMotos.filter((m: Record<string, unknown>) => m.status === 'active').length,
            rented_motos: branchMotos.filter((m: Record<string, unknown>) => m.status === 'rented').length,
            maintenance_motos: branchMotos.filter((m: Record<string, unknown>) => m.status === 'maintenance').length,
          }
        })

        result = { branches, count: branches.length }
        break
      }

      // =====================================================================
      // 7. get_customers
      // =====================================================================
      case 'get_customers': {
        const limit = (toolInput.limit as number) || 20
        const search = toolInput.search as string | undefined

        // Get total count
        const { count: totalCount } = await supabaseAdmin.from('profiles').select('id', { count: 'exact', head: true })

        let query = supabaseAdmin.from('profiles')
          .select('id, full_name, email, phone, city, created_at, reliability_score, preferred_branch')
          .order('created_at', { ascending: false })
          .limit(limit)

        if (search) {
          query = query.or(`full_name.ilike.%${search}%,email.ilike.%${search}%`)
        }

        const { data } = await query
        result = { total_count: totalCount || 0, customers: data || [] }
        break
      }

      // =====================================================================
      // 8. get_customer_detail
      // =====================================================================
      case 'get_customer_detail': {
        let profile: Record<string, unknown> | null = null

        if (toolInput.customer_id) {
          const { data } = await supabaseAdmin.from('profiles').select('*').eq('id', toolInput.customer_id as string).single()
          profile = data
        } else if (toolInput.email) {
          const { data } = await supabaseAdmin.from('profiles').select('*').eq('email', toolInput.email as string).single()
          profile = data
        } else if (toolInput.name_search) {
          const { data } = await supabaseAdmin.from('profiles').select('*').ilike('full_name', `%${toolInput.name_search}%`).limit(1)
          profile = data?.[0] || null
        }

        if (!profile) {
          result = { error: 'Zákazník nenalezen' }
          break
        }

        const [bookingsR, documentsR, reviewsR] = await Promise.all([
          supabaseAdmin.from('bookings').select('id, start_date, end_date, status, payment_status, total_price, moto_id').eq('user_id', profile.id).order('start_date', { ascending: false }).limit(20),
          supabaseAdmin.from('documents').select('id, type, created_at').eq('user_id', profile.id).order('created_at', { ascending: false }),
          supabaseAdmin.from('reviews').select('id, rating, created_at').eq('user_id', profile.id),
        ])

        result = {
          profile,
          bookings: bookingsR.data || [],
          documents: documentsR.data || [],
          reviews: reviewsR.data || [],
          bookings_count: (bookingsR.data || []).length,
        }
        break
      }

      // =====================================================================
      // 9. get_financial_overview
      // =====================================================================
      case 'get_financial_overview': {
        const period = (toolInput.period as string) || 'month'
        let dateFrom: string

        if (period === 'today') {
          dateFrom = now.toISOString().slice(0, 10)
        } else if (period === 'week') {
          dateFrom = new Date(now.getTime() - 7 * 86400000).toISOString()
        } else if (period === 'quarter') {
          const qMonth = Math.floor(now.getMonth() / 3) * 3
          dateFrom = new Date(now.getFullYear(), qMonth, 1).toISOString()
        } else {
          dateFrom = monthStart
        }

        const [revenueR, invoicesR, shopR, vouchersR] = await Promise.all([
          supabaseAdmin.from('bookings').select('total_price').eq('payment_status', 'paid').gte('created_at', dateFrom),
          supabaseAdmin.from('invoices').select('id, total, status').gte('issued_at', dateFrom),
          supabaseAdmin.from('shop_orders').select('id, total_amount, payment_status').gte('created_at', dateFrom),
          supabaseAdmin.from('vouchers').select('amount').eq('status', 'active'),
        ])

        const revenue = (revenueR.data || []).reduce((s: number, b: { total_price: number | null }) => s + (b.total_price || 0), 0)
        const invoiceTotal = (invoicesR.data || []).reduce((s: number, i: { total: number | null }) => s + (i.total || 0), 0)
        const shopTotal = (shopR.data || []).reduce((s: number, o: { total_amount: number | null }) => s + (o.total_amount || 0), 0)
        const voucherValue = (vouchersR.data || []).reduce((s: number, v: { amount: number | null }) => s + (v.amount || 0), 0)

        result = {
          period,
          revenue,
          invoice_count: (invoicesR.data || []).length,
          invoice_total: invoiceTotal,
          shop_orders_count: (shopR.data || []).length,
          shop_total: shopTotal,
          voucher_value: voucherValue,
        }
        break
      }

      // =====================================================================
      // 10. get_invoices
      // =====================================================================
      case 'get_invoices': {
        const limit = (toolInput.limit as number) || 20
        let query = supabaseAdmin.from('invoices')
          .select('id, number, type, customer_id, booking_id, order_id, total, status, issued_at, due_date, paid_date, source, variable_symbol')
          .order('issued_at', { ascending: false })
          .limit(limit)

        if (toolInput.status) query = query.eq('status', toolInput.status as string)
        if (toolInput.type) query = query.eq('type', toolInput.type as string)

        const { data } = await query
        result = { invoices: data || [], count: (data || []).length }
        break
      }

      // =====================================================================
      // 11. get_shop_orders
      // =====================================================================
      case 'get_shop_orders': {
        const limit = (toolInput.limit as number) || 20
        let query = supabaseAdmin.from('shop_orders')
          .select('id, order_number, customer_id, status, payment_status, payment_method, total_amount, shipping_method, created_at, confirmed_at')
          .order('created_at', { ascending: false })
          .limit(limit)

        if (toolInput.status) query = query.eq('status', toolInput.status as string)

        const { data } = await query
        result = { orders: data || [], count: (data || []).length }
        break
      }

      // =====================================================================
      // 12. get_vouchers_and_promos
      // =====================================================================
      case 'get_vouchers_and_promos': {
        const activeOnly = toolInput.active_only !== false // default true

        let vQuery = supabaseAdmin.from('vouchers')
          .select('id, code, amount, status, valid_from, valid_until, buyer_name, buyer_email, category, redeemed_at')
        if (activeOnly) vQuery = vQuery.eq('status', 'active')

        let pQuery = supabaseAdmin.from('promo_codes')
          .select('id, code, type, discount_value, is_active, used_count, max_uses, valid_to')
        if (activeOnly) pQuery = pQuery.eq('is_active', true)

        const [vouchersR, promosR] = await Promise.all([vQuery, pQuery])

        const vouchers = vouchersR.data || []
        const totalVoucherValue = vouchers.reduce((s: number, v: { amount: number | null }) => s + (v.amount || 0), 0)

        result = {
          vouchers,
          promo_codes: promosR.data || [],
          total_voucher_value: totalVoucherValue,
        }
        break
      }

      // =====================================================================
      // 13. get_service_status
      // =====================================================================
      case 'get_service_status': {
        const daysAhead = (toolInput.days_ahead as number) || 30
        const futureDate = new Date(now.getTime() + daysAhead * 86400000).toISOString().slice(0, 10)

        const [upcomingR, ordersR] = await Promise.all([
          supabaseAdmin.from('motorcycles')
            .select('id, model, brand, spz, mileage, next_service_date, last_service_date')
            .not('next_service_date', 'is', null)
            .lte('next_service_date', futureDate)
            .order('next_service_date', { ascending: true }),
          supabaseAdmin.from('service_orders')
            .select('id, moto_id, status, created_at')
            .in('status', ['pending', 'in_service']),
        ])

        result = {
          upcoming_services: upcomingR.data || [],
          active_orders: ordersR.data || [],
        }
        break
      }

      // =====================================================================
      // 14. get_messages_overview
      // =====================================================================
      case 'get_messages_overview': {
        const limit = (toolInput.limit as number) || 20

        let query = supabaseAdmin.from('message_threads')
          .select('id, customer_id, channel, status, assigned_admin, created_at, updated_at')
          .order('updated_at', { ascending: false })
          .limit(limit)

        if (toolInput.unread_only) {
          query = query.eq('status', 'open')
        }

        const { data } = await query
        result = { threads: data || [], count: (data || []).length }
        break
      }

      // =====================================================================
      // 15. get_daily_stats
      // =====================================================================
      case 'get_daily_stats': {
        const days = (toolInput.days as number) || 7
        const since = new Date(now.getTime() - days * 86400000).toISOString().slice(0, 10)

        const { data } = await supabaseAdmin.from('daily_stats')
          .select('*')
          .gte('date', since)
          .order('date', { ascending: false })
          .limit(days)

        result = { stats: data || [], days }
        break
      }

      // =====================================================================
      // 16. get_inventory
      // =====================================================================
      case 'get_inventory': {
        try {
          const limit = (toolInput.limit as number) || 50
          let query = supabaseAdmin.from('inventory')
            .select('id, name, sku, category, stock, min_stock, unit_price, supplier_id')
            .order('name', { ascending: true })
            .limit(limit)

          if (toolInput.search) {
            const s = toolInput.search as string
            query = query.or(`name.ilike.%${s}%,sku.ilike.%${s}%`)
          }
          if (toolInput.category) query = query.eq('category', toolInput.category as string)

          const { data: items, error: invErr } = await query
          if (invErr) throw invErr

          // Fetch suppliers for names
          const supplierIds = [...new Set((items || []).map((i: Record<string, unknown>) => i.supplier_id).filter(Boolean))]
          const { data: suppliers } = supplierIds.length > 0
            ? await supabaseAdmin.from('suppliers').select('id, name').in('id', supplierIds)
            : { data: [] }
          const supplierMap: Record<string, string> = {}
          for (const s of (suppliers || [])) supplierMap[s.id] = s.name

          let enriched = (items || []).map((i: Record<string, unknown>) => ({
            ...i,
            supplier_name: supplierMap[i.supplier_id as string] || null,
          }))

          if (toolInput.low_stock_only) {
            enriched = enriched.filter((i: Record<string, unknown>) => (i.stock as number) <= (i.min_stock as number))
          }

          const lowStockCount = (items || []).filter((i: Record<string, unknown>) => (i.stock as number) <= (i.min_stock as number)).length

          result = { total: enriched.length, low_stock_count: lowStockCount, items: enriched }
        } catch {
          result = { error: 'Table not available', data: [] }
        }
        break
      }

      // =====================================================================
      // 17. get_inventory_movements
      // =====================================================================
      case 'get_inventory_movements': {
        try {
          const limit = (toolInput.limit as number) || 30
          let query = supabaseAdmin.from('inventory_movements')
            .select('*')
            .order('created_at', { ascending: false })
            .limit(limit)

          if (toolInput.item_id) query = query.eq('item_id', toolInput.item_id as string)
          if (toolInput.type) query = query.eq('type', toolInput.type as string)

          const { data, error: mvErr } = await query
          if (mvErr) throw mvErr

          result = { movements: data || [], count: (data || []).length }
        } catch {
          result = { error: 'Table not available', data: [] }
        }
        break
      }

      // =====================================================================
      // 18. get_branch_detail
      // =====================================================================
      case 'get_branch_detail': {
        try {
          const branchId = toolInput.branch_id as string
          if (!branchId) {
            result = { error: 'branch_id je povinný parametr' }
            break
          }

          const [branchR, motosR, accessoriesR, codesR, bookingsR] = await Promise.all([
            supabaseAdmin.from('branches').select('*').eq('id', branchId).single(),
            supabaseAdmin.from('motorcycles').select('id, model, brand, spz, status, mileage, image_url, category, year').eq('branch_id', branchId),
            supabaseAdmin.from('branch_accessories').select('*').eq('branch_id', branchId),
            supabaseAdmin.from('branch_door_codes').select('*').eq('branch_id', branchId).eq('is_active', true),
            supabaseAdmin.from('bookings')
              .select('id, user_id, moto_id, start_date, end_date, status, total_price, payment_status')
              .in('status', ['active', 'reserved']),
          ])

          if (!branchR.data) {
            result = { error: 'Pobočka nenalezena' }
            break
          }

          // Filter bookings to this branch's motorcycles
          const branchMotoIds = (motosR.data || []).map((m: Record<string, unknown>) => m.id)
          const branchBookings = (bookingsR.data || []).filter((b: Record<string, unknown>) =>
            branchMotoIds.includes(b.moto_id)
          )

          // Fetch customer names for active bookings
          const userIds = [...new Set(branchBookings.map((b: Record<string, unknown>) => b.user_id).filter(Boolean))]
          const { data: profiles } = userIds.length > 0
            ? await supabaseAdmin.from('profiles').select('id, full_name, email, phone').in('id', userIds)
            : { data: [] }
          const profileMap: Record<string, Record<string, unknown>> = {}
          for (const p of (profiles || [])) profileMap[p.id] = p

          const enrichedBookings = branchBookings.map((b: Record<string, unknown>) => ({
            ...b,
            customer: profileMap[b.user_id as string] || null,
          }))

          result = {
            branch: branchR.data,
            motorcycles: motosR.data || [],
            accessories: accessoriesR.data || [],
            door_codes: codesR.data || [],
            active_bookings: enrichedBookings,
          }
        } catch {
          result = { error: 'Table not available', data: [] }
        }
        break
      }

      // =====================================================================
      // 19. get_documents
      // =====================================================================
      case 'get_documents': {
        try {
          const limit = (toolInput.limit as number) || 20
          const docType = toolInput.type as string | undefined

          if (docType === 'contracts') {
            const { data } = await supabaseAdmin.from('documents')
              .select('id, type, user_id, created_at')
              .order('created_at', { ascending: false })
              .limit(limit)
            result = { documents: data || [], total_count: (data || []).length }
          } else if (docType === 'templates') {
            const { data } = await supabaseAdmin.from('document_templates')
              .select('id, type, name, active, version, updated_at')
              .order('name', { ascending: true })
            result = { documents: data || [], total_count: (data || []).length }
          } else if (docType === 'generated') {
            const { data } = await supabaseAdmin.from('generated_documents')
              .select('*')
              .order('created_at', { ascending: false })
              .limit(limit)
            result = { documents: data || [], total_count: (data || []).length }
          } else if (docType === 'emails') {
            const { data } = await supabaseAdmin.from('sent_emails')
              .select('*')
              .order('created_at', { ascending: false })
              .limit(limit)
            result = { documents: data || [], total_count: (data || []).length }
          } else {
            // No type — return counts + last 5 from each
            const [contractsR, templatesR, generatedR, emailsR] = await Promise.all([
              supabaseAdmin.from('documents').select('id, type, created_at').order('created_at', { ascending: false }).limit(5),
              supabaseAdmin.from('document_templates').select('id, type, name, active').order('name', { ascending: true }),
              supabaseAdmin.from('generated_documents').select('id, created_at').order('created_at', { ascending: false }).limit(5),
              supabaseAdmin.from('sent_emails').select('id, created_at').order('created_at', { ascending: false }).limit(5),
            ])
            result = {
              contracts: { recent: contractsR.data || [], count: (contractsR.data || []).length },
              templates: { items: templatesR.data || [], count: (templatesR.data || []).length },
              generated: { recent: generatedR.data || [], count: (generatedR.data || []).length },
              emails: { recent: emailsR.data || [], count: (emailsR.data || []).length },
            }
          }
        } catch {
          result = { error: 'Table not available', data: [] }
        }
        break
      }

      // =====================================================================
      // 20. get_reviews
      // =====================================================================
      case 'get_reviews': {
        try {
          const limit = (toolInput.limit as number) || 20
          let query = supabaseAdmin.from('reviews')
            .select('id, user_id, rating, created_at')
            .order('created_at', { ascending: false })
            .limit(limit)

          if (toolInput.moto_id) query = query.eq('moto_id', toolInput.moto_id as string)
          if (toolInput.min_rating) query = query.gte('rating', toolInput.min_rating as number)

          const { data: reviews, error: revErr } = await query
          if (revErr) throw revErr

          // Fetch profiles for names
          const userIds = [...new Set((reviews || []).map((r: Record<string, unknown>) => r.user_id).filter(Boolean))]
          const { data: profiles } = userIds.length > 0
            ? await supabaseAdmin.from('profiles').select('id, full_name').in('id', userIds)
            : { data: [] }
          const profileMap: Record<string, string> = {}
          for (const p of (profiles || [])) profileMap[p.id] = p.full_name

          const enriched = (reviews || []).map((r: Record<string, unknown>) => ({
            ...r,
            customer_name: profileMap[r.user_id as string] || null,
          }))

          const ratings = (reviews || []).map((r: Record<string, unknown>) => r.rating as number).filter(Boolean)
          const avgRating = ratings.length > 0 ? Math.round(ratings.reduce((s, v) => s + v, 0) / ratings.length * 10) / 10 : null

          result = { avg_rating: avgRating, total_count: (reviews || []).length, reviews: enriched }
        } catch {
          result = { error: 'Table not available', data: [] }
        }
        break
      }

      // =====================================================================
      // 21. get_cms_settings
      // =====================================================================
      case 'get_cms_settings': {
        try {
          const section = toolInput.section as string | undefined

          if (section === 'flags') {
            const { data } = await supabaseAdmin.from('feature_flags').select('*').order('name', { ascending: true })
            result = { feature_flags: data || [] }
          } else if (section === 'variables') {
            const { data } = await supabaseAdmin.from('cms_variables').select('*').order('key', { ascending: true })
            result = { variables: data || [] }
          } else if (section === 'settings') {
            const { data } = await supabaseAdmin.from('app_settings').select('*').order('key', { ascending: true })
            result = { app_settings: data || [] }
          } else {
            const [flagsR, varsR, settingsR] = await Promise.all([
              supabaseAdmin.from('feature_flags').select('*').order('name', { ascending: true }),
              supabaseAdmin.from('cms_variables').select('*').order('key', { ascending: true }),
              supabaseAdmin.from('app_settings').select('*').order('key', { ascending: true }),
            ])
            result = {
              feature_flags: flagsR.data || [],
              variables: varsR.data || [],
              app_settings: settingsR.data || [],
            }
          }
        } catch {
          result = { error: 'Table not available', data: [] }
        }
        break
      }

      // =====================================================================
      // 22. get_audit_log
      // =====================================================================
      case 'get_audit_log': {
        try {
          const limit = (toolInput.limit as number) || 30
          let query = supabaseAdmin.from('admin_audit_log')
            .select('id, admin_id, action, details, ip_address, created_at')
            .order('created_at', { ascending: false })
            .limit(limit)

          if (toolInput.admin_id) query = query.eq('admin_id', toolInput.admin_id as string)
          if (toolInput.action) query = query.ilike('action', `%${toolInput.action}%`)

          const { data: logs, error: auditErr } = await query
          if (auditErr) throw auditErr

          // Fetch admin emails
          const adminIds = [...new Set((logs || []).map((l: Record<string, unknown>) => l.admin_id).filter(Boolean))]
          const { data: admins } = adminIds.length > 0
            ? await supabaseAdmin.from('admin_users').select('id, email, name').in('id', adminIds)
            : { data: [] }
          const adminMap: Record<string, Record<string, unknown>> = {}
          for (const a of (admins || [])) adminMap[a.id] = a

          const enriched = (logs || []).map((l: Record<string, unknown>) => ({
            ...l,
            admin: adminMap[l.admin_id as string] || null,
          }))

          result = { logs: enriched, count: enriched.length }
        } catch {
          result = { error: 'Table not available', data: [] }
        }
        break
      }

      // =====================================================================
      // 23. get_government_overview
      // =====================================================================
      case 'get_government_overview': {
        try {
          const { data: motos, error: govErr } = await supabaseAdmin.from('motorcycles')
            .select('id, model, brand, spz, stk_valid_until, insurance_price, status')

          if (govErr) throw govErr

          const today = now.toISOString().slice(0, 10)
          const d30 = new Date(now.getTime() + 30 * 86400000).toISOString().slice(0, 10)
          const d60 = new Date(now.getTime() + 60 * 86400000).toISOString().slice(0, 10)
          const d90 = new Date(now.getTime() + 90 * 86400000).toISOString().slice(0, 10)

          let expired = 0, within30 = 0, within60 = 0, within90 = 0, ok = 0, noStk = 0
          for (const m of (motos || [])) {
            const stk = (m as Record<string, unknown>).stk_valid_until as string | null
            if (!stk) { noStk++; continue }
            if (stk < today) expired++
            else if (stk <= d30) within30++
            else if (stk <= d60) within60++
            else if (stk <= d90) within90++
            else ok++
          }

          const totalInsurance = (motos || []).reduce((s: number, m: Record<string, unknown>) => s + ((m.insurance_price as number) || 0), 0)

          result = {
            motorcycles: motos || [],
            stk_summary: { expired, within_30d: within30, within_60d: within60, within_90d: within90, ok, no_stk: noStk },
            total_insurance_cost: totalInsurance,
          }
        } catch {
          result = { error: 'Table not available', data: [] }
        }
        break
      }

      // =====================================================================
      // 24. get_sos_detail
      // =====================================================================
      case 'get_sos_detail': {
        try {
          const incidentId = toolInput.incident_id as string
          if (!incidentId) {
            result = { error: 'incident_id je povinný parametr' }
            break
          }

          const { data: incident, error: sosErr } = await supabaseAdmin.from('sos_incidents')
            .select('*')
            .eq('id', incidentId)
            .single()

          if (sosErr || !incident) {
            result = { error: 'SOS incident nenalezen' }
            break
          }

          const { data: timeline } = await supabaseAdmin.from('sos_timeline')
            .select('*')
            .eq('incident_id', incidentId)
            .order('created_at', { ascending: true })

          // Fetch related booking, motorcycle, customer
          const [bookingR, motoR, profileR] = await Promise.all([
            incident.booking_id
              ? supabaseAdmin.from('bookings').select('id, start_date, end_date, status, total_price, payment_status').eq('id', incident.booking_id).single()
              : Promise.resolve({ data: null }),
            incident.moto_id
              ? supabaseAdmin.from('motorcycles').select('id, model, brand, spz, status').eq('id', incident.moto_id).single()
              : Promise.resolve({ data: null }),
            incident.user_id
              ? supabaseAdmin.from('profiles').select('id, full_name, email, phone').eq('id', incident.user_id).single()
              : Promise.resolve({ data: null }),
          ])

          result = {
            incident,
            timeline: timeline || [],
            booking: bookingR.data || null,
            motorcycle: motoR.data || null,
            customer: profileR.data || null,
          }
        } catch {
          result = { error: 'Table not available', data: [] }
        }
        break
      }

      // =====================================================================
      // 25. get_pricing_overview
      // =====================================================================
      case 'get_pricing_overview': {
        try {
          let motosQuery = supabaseAdmin.from('motorcycles')
            .select('id, model, brand, spz, price_weekday, price_weekend, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun, category, status')

          if (toolInput.motorcycle_id) {
            motosQuery = motosQuery.eq('id', toolInput.motorcycle_id as string)
          }

          const { data: motos, error: priceErr } = await motosQuery
          if (priceErr) throw priceErr

          // Also fetch moto_day_prices if they exist
          const motoIds = (motos || []).map((m: Record<string, unknown>) => m.id)
          const { data: dayPrices } = motoIds.length > 0
            ? await supabaseAdmin.from('moto_day_prices').select('*').in('moto_id', motoIds)
            : { data: [] }

          const dayPriceMap: Record<string, unknown[]> = {}
          for (const dp of (dayPrices || [])) {
            const mid = (dp as Record<string, unknown>).moto_id as string
            if (!dayPriceMap[mid]) dayPriceMap[mid] = []
            dayPriceMap[mid].push(dp)
          }

          const enriched = (motos || []).map((m: Record<string, unknown>) => ({
            id: m.id,
            model: m.model,
            brand: m.brand,
            spz: m.spz,
            category: m.category,
            status: m.status,
            prices_by_day: {
              mon: m.price_mon, tue: m.price_tue, wed: m.price_wed, thu: m.price_thu,
              fri: m.price_fri, sat: m.price_sat, sun: m.price_sun,
            },
            price_weekday: m.price_weekday,
            price_weekend: m.price_weekend,
            day_prices_table: dayPriceMap[m.id as string] || [],
          }))

          result = { motorcycles: enriched }
        } catch {
          result = { error: 'Table not available', data: [] }
        }
        break
      }

      // =====================================================================
      // Analytické nástroje 26+ — TODO: implementace v dalším kroku
      // =====================================================================
      case 'analyze_branch_performance':
      case 'analyze_motorcycle_performance':
      case 'analyze_category_demand':
      case 'analyze_optimal_fleet':
      case 'analyze_customers':
        // TODO: implementace analytických nástrojů v dalším kroku
        result = { error: 'Analytický nástroj zatím není implementován. Použijte provozní nástroje.' }
        break

      default:
        result = { error: `Unknown tool: ${toolName}` }
    }

    console.log(`ai-copilot tool: ${toolName} (${Date.now() - startTime}ms)`)
    return result
  } catch (err) {
    console.error(`ai-copilot tool error: ${toolName}`, err)
    return { error: `Tool ${toolName} failed: ${(err as Error).message}` }
  }
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
