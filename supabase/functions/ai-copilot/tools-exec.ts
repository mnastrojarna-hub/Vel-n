import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ---------------------------------------------------------------------------
// FLEET CALC CONSTANTS
// ---------------------------------------------------------------------------

const FLEET_CALC = {
  purchasePriceMarkup: 1.20,
  marketingPct: 0.15,
  otherFixedPerBike: 3000,
  categoryParams: {
    adventure:  { avgDailyRate: 2100, avgServicePerEvent: 25000, servicesPerYear: 2, insuranceCleaningYear: 13000, avgPurchasePrice: 200000 },
    touring:    { avgDailyRate: 2000, avgServicePerEvent: 20000, servicesPerYear: 2, insuranceCleaningYear: 13000, avgPurchasePrice: 220000 },
    naked:      { avgDailyRate: 1600, avgServicePerEvent: 20000, servicesPerYear: 3, insuranceCleaningYear: 13000, avgPurchasePrice: 165000 },
    sport:      { avgDailyRate: 1700, avgServicePerEvent: 20000, servicesPerYear: 3, insuranceCleaningYear: 13000, avgPurchasePrice: 175000 },
    retro:      { avgDailyRate: 1400, avgServicePerEvent: 10000, servicesPerYear: 3, insuranceCleaningYear: 13000, avgPurchasePrice: 110000 },
    A2:         { avgDailyRate: 1100, avgServicePerEvent: 10000, servicesPerYear: 2, insuranceCleaningYear: 7000,  avgPurchasePrice: 50000 },
    detske:     { avgDailyRate: 800,  avgServicePerEvent: 8000,  servicesPerYear: 2, insuranceCleaningYear: 5000,  avgPurchasePrice: 30000 },
    enduro:     { avgDailyRate: 1800, avgServicePerEvent: 15000, servicesPerYear: 3, insuranceCleaningYear: 13000, avgPurchasePrice: 180000 },
    cestovni:   { avgDailyRate: 2000, avgServicePerEvent: 20000, servicesPerYear: 2, insuranceCleaningYear: 13000, avgPurchasePrice: 220000 },
    chopper:    { avgDailyRate: 1500, avgServicePerEvent: 18000, servicesPerYear: 2, insuranceCleaningYear: 13000, avgPurchasePrice: 190000 },
  } as Record<string, { avgDailyRate: number; avgServicePerEvent: number; servicesPerYear: number; insuranceCleaningYear: number; avgPurchasePrice: number }>,
  branchUtilization: {
    'turistická':       { adventure: 0.82, touring: 0.76, naked: 0.45, sport: 0.40, retro: 0.55, A2: 0.35, enduro: 0.70, cestovni: 0.76, chopper: 0.50, detske: 0.30 },
    'horská':           { adventure: 0.78, touring: 0.60, naked: 0.35, sport: 0.30, retro: 0.30, A2: 0.25, enduro: 0.80, cestovni: 0.60, chopper: 0.25, detske: 0.20 },
    'rekreační voda':   { adventure: 0.72, touring: 0.68, naked: 0.55, sport: 0.38, retro: 0.65, A2: 0.40, enduro: 0.50, cestovni: 0.68, chopper: 0.55, detske: 0.35 },
    'centrum':          { adventure: 0.40, touring: 0.50, naked: 0.72, sport: 0.55, retro: 0.60, A2: 0.68, enduro: 0.25, cestovni: 0.50, chopper: 0.50, detske: 0.45 },
    'předměstí':        { adventure: 0.48, touring: 0.52, naked: 0.68, sport: 0.52, retro: 0.55, A2: 0.65, enduro: 0.30, cestovni: 0.52, chopper: 0.45, detske: 0.40 },
    'letiště':          { adventure: 0.55, touring: 0.65, naked: 0.60, sport: 0.45, retro: 0.50, A2: 0.50, enduro: 0.30, cestovni: 0.65, chopper: 0.45, detske: 0.25 },
  } as Record<string, Record<string, number>>,
}

// ---------------------------------------------------------------------------
// ANALYTICS HELPERS
// ---------------------------------------------------------------------------

async function fetchAnalyticsRawData(sb: ReturnType<typeof createClient>, months: number) {
  const since = new Date()
  since.setMonth(since.getMonth() - months)
  const [bRes, mRes, lRes, pRes] = await Promise.all([
    sb.from('bookings').select('id, user_id, moto_id, start_date, end_date, total_price, status, created_at, booking_source, rating, payment_status').gte('created_at', since.toISOString()),
    sb.from('motorcycles').select('id, model, brand, category, branch_id, status, purchase_price, mileage'),
    sb.from('branches').select('id, name, city, type'),
    sb.from('profiles').select('id, full_name, email, city, license_group, riding_experience, created_at'),
  ])
  return { bookings: bRes.data || [], motorcycles: mRes.data || [], branches: lRes.data || [], profiles: pRes.data || [] }
}

function diffDays(start: string, end: string): number {
  return Math.max(1, Math.round((new Date(end).getTime() - new Date(start).getTime()) / 86400000))
}

// ---------------------------------------------------------------------------
// TOOL EXECUTOR — 25 provozních + 6 analytických nástrojů
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
      // 26. analyze_branch_performance
      // =====================================================================
      case 'analyze_branch_performance': {
        const periodMonths = (toolInput.period_months as number) || 6
        const raw = await fetchAnalyticsRawData(supabaseAdmin, periodMonths)
        const periodDays = periodMonths * 30

        // Current month bookings for trend
        const nowDate = new Date()
        const curMonthStart = new Date(nowDate.getFullYear(), nowDate.getMonth(), 1).toISOString()
        const prevMStart = new Date(nowDate.getFullYear(), nowDate.getMonth() - 1, 1).toISOString()

        const completedBookings = raw.bookings.filter((b: Record<string, unknown>) =>
          b.status === 'completed' && b.payment_status === 'paid'
        )

        // Map moto_id → branch_id
        const motoBranchMap: Record<string, string> = {}
        for (const m of raw.motorcycles) motoBranchMap[(m as Record<string, unknown>).id as string] = (m as Record<string, unknown>).branch_id as string

        // Moto → category
        const motoCategoryMap: Record<string, string> = {}
        for (const m of raw.motorcycles) motoCategoryMap[(m as Record<string, unknown>).id as string] = ((m as Record<string, unknown>).category as string) || 'unknown'

        const branchStats = raw.branches.map((branch: Record<string, unknown>) => {
          const branchMotoIds = raw.motorcycles
            .filter((m: Record<string, unknown>) => m.branch_id === branch.id)
            .map((m: Record<string, unknown>) => m.id as string)
          const motoCount = branchMotoIds.length

          const branchBookings = completedBookings.filter((b: Record<string, unknown>) =>
            branchMotoIds.includes(b.moto_id as string)
          )

          const revenue = branchBookings.reduce((s: number, b: Record<string, unknown>) => s + ((b.total_price as number) || 0), 0)
          const totalRentedDays = branchBookings.reduce((s: number, b: Record<string, unknown>) =>
            s + diffDays(b.start_date as string, b.end_date as string), 0)
          const utilizationPct = motoCount > 0 ? Math.round(totalRentedDays / (motoCount * periodDays) * 1000) / 10 : 0
          const revenuePerMoto = motoCount > 0 ? Math.round(revenue / motoCount) : 0

          // Profit per moto estimate using FLEET_CALC
          const categories = branchMotoIds.map(id => motoCategoryMap[id] || 'naked')
          const avgServiceCost = categories.reduce((s, cat) => {
            const p = FLEET_CALC.categoryParams[cat] || FLEET_CALC.categoryParams['naked']
            return s + p.avgServicePerEvent * p.servicesPerYear + p.insuranceCleaningYear
          }, 0) / Math.max(1, categories.length)
          const marketingCost = revenue * FLEET_CALC.marketingPct
          const profitPerMoto = motoCount > 0 ? Math.round((revenue - avgServiceCost * motoCount - marketingCost - FLEET_CALC.otherFixedPerBike * motoCount) / motoCount) : 0

          // Trend: current month vs previous month
          const curMonthRev = branchBookings
            .filter((b: Record<string, unknown>) => (b.created_at as string) >= curMonthStart)
            .reduce((s: number, b: Record<string, unknown>) => s + ((b.total_price as number) || 0), 0)
          const prevMonthRev = branchBookings
            .filter((b: Record<string, unknown>) => (b.created_at as string) >= prevMStart && (b.created_at as string) < curMonthStart)
            .reduce((s: number, b: Record<string, unknown>) => s + ((b.total_price as number) || 0), 0)
          const changePct = prevMonthRev > 0 ? (curMonthRev / prevMonthRev - 1) * 100 : 0
          const trend = changePct > 10 ? 'Rostoucí' : changePct < -5 ? 'Klesající' : 'Stagnující'

          return {
            id: branch.id, name: branch.name, city: branch.city, type: branch.type,
            motorcycle_count: motoCount, reservations: branchBookings.length,
            revenue, revenue_per_moto: revenuePerMoto, utilization_pct: utilizationPct,
            rented_days: totalRentedDays, profit_per_moto: profitPerMoto,
            trend, trend_change_pct: Math.round(changePct * 10) / 10,
          }
        })

        const totalRevenue = branchStats.reduce((s: number, b: Record<string, unknown>) => s + (b.revenue as number), 0)
        const totalReservations = branchStats.reduce((s: number, b: Record<string, unknown>) => s + (b.reservations as number), 0)
        const avgUtil = branchStats.length > 0
          ? Math.round(branchStats.reduce((s: number, b: Record<string, unknown>) => s + (b.utilization_pct as number), 0) / branchStats.length * 10) / 10
          : 0

        result = {
          branches: branchStats,
          totals: { revenue: totalRevenue, reservations: totalReservations, avg_utilization: avgUtil },
          period_months: periodMonths,
        }
        break
      }

      // =====================================================================
      // 27. analyze_motorcycle_performance
      // =====================================================================
      case 'analyze_motorcycle_performance': {
        const periodMonths = (toolInput.period_months as number) || 6
        const raw = await fetchAnalyticsRawData(supabaseAdmin, periodMonths)
        const periodDays = periodMonths * 30

        const completedBookings = raw.bookings.filter((b: Record<string, unknown>) =>
          b.status === 'completed' && b.payment_status === 'paid'
        )

        const motoStats = raw.motorcycles.map((moto: Record<string, unknown>) => {
          const motoBookings = completedBookings.filter((b: Record<string, unknown>) => b.moto_id === moto.id)
          const revenue = motoBookings.reduce((s: number, b: Record<string, unknown>) => s + ((b.total_price as number) || 0), 0)
          const rentedDays = motoBookings.reduce((s: number, b: Record<string, unknown>) =>
            s + diffDays(b.start_date as string, b.end_date as string), 0)
          const utilizationPct = Math.round(rentedDays / periodDays * 1000) / 10
          const avgDailyRate = rentedDays > 0 ? Math.round(revenue / rentedDays) : 0

          return {
            id: moto.id, model: moto.model, brand: moto.brand, category: moto.category,
            status: moto.status, mileage: moto.mileage, purchase_price: moto.purchase_price,
            reservations: motoBookings.length, revenue, rented_days: rentedDays,
            utilization_pct: utilizationPct, avg_daily_rate: avgDailyRate,
          }
        }).sort((a: Record<string, unknown>, b: Record<string, unknown>) => (b.revenue as number) - (a.revenue as number))

        // Brand aggregation
        const brandMap: Record<string, { revenue: number; count: number; utilSum: number }> = {}
        for (const ms of motoStats) {
          const brand = (ms.brand as string) || 'Unknown'
          if (!brandMap[brand]) brandMap[brand] = { revenue: 0, count: 0, utilSum: 0 }
          brandMap[brand].revenue += ms.revenue as number
          brandMap[brand].count++
          brandMap[brand].utilSum += ms.utilization_pct as number
        }
        const maxRevPerMoto = Math.max(...Object.values(brandMap).map(b => b.count > 0 ? b.revenue / b.count : 0), 1)
        const brandStats = Object.entries(brandMap).map(([brand, data]) => {
          const avgUtil = data.count > 0 ? Math.round(data.utilSum / data.count * 10) / 10 : 0
          const revPerMoto = data.count > 0 ? Math.round(data.revenue / data.count) : 0
          const perfScore = Math.round(((revPerMoto / maxRevPerMoto) + (avgUtil / 100)) / 2 * 100) / 100
          return { brand, motorcycle_count: data.count, total_revenue: data.revenue, revenue_per_moto: revPerMoto, avg_utilization: avgUtil, performance_score: perfScore }
        }).sort((a, b) => b.performance_score - a.performance_score)

        result = { motorcycles: motoStats, brand_stats: brandStats, period_months: periodMonths }
        break
      }

      // =====================================================================
      // 28. analyze_category_demand
      // =====================================================================
      case 'analyze_category_demand': {
        const periodMonths = (toolInput.period_months as number) || 6
        const raw = await fetchAnalyticsRawData(supabaseAdmin, periodMonths)
        const periodDays = periodMonths * 30

        const motoCategoryMap: Record<string, string> = {}
        for (const m of raw.motorcycles) motoCategoryMap[(m as Record<string, unknown>).id as string] = ((m as Record<string, unknown>).category as string) || 'unknown'

        const completedBookings = raw.bookings.filter((b: Record<string, unknown>) =>
          b.status === 'completed' && b.payment_status === 'paid'
        )

        // Count motos per category
        const catMotoCount: Record<string, number> = {}
        for (const m of raw.motorcycles) {
          const cat = ((m as Record<string, unknown>).category as string) || 'unknown'
          catMotoCount[cat] = (catMotoCount[cat] || 0) + 1
        }

        const catStats: Record<string, { reservations: number; revenue: number; rentedDays: number }> = {}
        for (const b of completedBookings) {
          const cat = motoCategoryMap[(b as Record<string, unknown>).moto_id as string] || 'unknown'
          if (!catStats[cat]) catStats[cat] = { reservations: 0, revenue: 0, rentedDays: 0 }
          catStats[cat].reservations++
          catStats[cat].revenue += ((b as Record<string, unknown>).total_price as number) || 0
          catStats[cat].rentedDays += diffDays((b as Record<string, unknown>).start_date as string, (b as Record<string, unknown>).end_date as string)
        }

        const categories = Object.entries(catStats).map(([category, data]) => {
          const motoCount = catMotoCount[category] || 1
          const utilizationPct = Math.round(data.rentedDays / (motoCount * periodDays) * 1000) / 10
          return {
            category, motorcycle_count: catMotoCount[category] || 0,
            reservation_count: data.reservations, total_revenue: data.revenue,
            revenue_per_moto: Math.round(data.revenue / motoCount),
            avg_utilization: utilizationPct, rented_days: data.rentedDays,
          }
        }).sort((a, b) => b.avg_utilization - a.avg_utilization)

        result = { categories, period_months: periodMonths }
        break
      }

      // =====================================================================
      // 29. analyze_optimal_fleet
      // =====================================================================
      case 'analyze_optimal_fleet': {
        const branchId = toolInput.branch_id as string
        if (!branchId) {
          result = { error: 'branch_id je povinný parametr' }
          break
        }

        const periodMonths = (toolInput.period_months as number) || 6
        const raw = await fetchAnalyticsRawData(supabaseAdmin, periodMonths)
        const periodDays = periodMonths * 30

        const branch = raw.branches.find((b: Record<string, unknown>) => b.id === branchId) as Record<string, unknown> | undefined
        if (!branch) {
          result = { error: 'Pobočka nenalezena' }
          break
        }

        const branchMotos = raw.motorcycles.filter((m: Record<string, unknown>) => m.branch_id === branchId)
        const branchMotoIds = branchMotos.map((m: Record<string, unknown>) => m.id as string)
        const motoCategoryMap: Record<string, string> = {}
        for (const m of branchMotos) motoCategoryMap[(m as Record<string, unknown>).id as string] = ((m as Record<string, unknown>).category as string) || 'unknown'

        const completedBookings = raw.bookings.filter((b: Record<string, unknown>) =>
          b.status === 'completed' && b.payment_status === 'paid' && branchMotoIds.includes(b.moto_id as string)
        )

        // Current fleet by category
        const currentFleet: Record<string, { count: number; revenue: number; rentedDays: number }> = {}
        for (const m of branchMotos) {
          const cat = ((m as Record<string, unknown>).category as string) || 'unknown'
          if (!currentFleet[cat]) currentFleet[cat] = { count: 0, revenue: 0, rentedDays: 0 }
          currentFleet[cat].count++
        }
        for (const b of completedBookings) {
          const cat = motoCategoryMap[(b as Record<string, unknown>).moto_id as string] || 'unknown'
          if (currentFleet[cat]) {
            currentFleet[cat].revenue += ((b as Record<string, unknown>).total_price as number) || 0
            currentFleet[cat].rentedDays += diffDays((b as Record<string, unknown>).start_date as string, (b as Record<string, unknown>).end_date as string)
          }
        }

        const current = Object.entries(currentFleet).map(([cat, data]) => {
          const utilPct = data.count > 0 ? Math.round(data.rentedDays / (data.count * periodDays) * 1000) / 10 : 0
          const revPerSlot = data.count > 0 ? Math.round(data.revenue / data.count) : 0
          return { category: cat, count: data.count, revenue: data.revenue, utilization_pct: utilPct, revenue_per_slot: revPerSlot }
        })

        // Score each category: revenuePerSlot * (utilPct / 100)
        const branchType = (branch.type as string) || 'turistická'
        const branchUtilData = FLEET_CALC.branchUtilization[branchType] || FLEET_CALC.branchUtilization['turistická']

        const catScores: Array<{ category: string; score: number; expectedRevPerSlot: number; utilPct: number }> = []
        for (const [cat, params] of Object.entries(FLEET_CALC.categoryParams)) {
          const utilFromData = branchUtilData[cat] || 0.3
          // Use real data if available, otherwise use FLEET_CALC estimates
          const existing = currentFleet[cat]
          const realUtil = existing && existing.count > 0
            ? existing.rentedDays / (existing.count * periodDays)
            : utilFromData
          const utilPct = Math.round(realUtil * 1000) / 10
          const expectedRevPerSlot = Math.round(params.avgDailyRate * periodDays * realUtil)
          const score = expectedRevPerSlot * realUtil
          if (utilPct > 40) {
            catScores.push({ category: cat, score, expectedRevPerSlot, utilPct })
          }
        }
        catScores.sort((a, b) => b.score - a.score)

        // Distribute 8 slots proportionally
        const totalScore = catScores.reduce((s, c) => s + c.score, 0)
        const totalSlots = 8
        let assigned = 0
        const recommended = catScores.map(c => {
          const raw = totalScore > 0 ? (c.score / totalScore) * totalSlots : 0
          const slots = Math.max(1, Math.round(raw))
          assigned += slots
          return { category: c.category, slots, expected_revenue_per_slot: c.expectedRevPerSlot, utilization_pct: c.utilPct }
        })
        // Adjust to exactly 8
        while (assigned > totalSlots && recommended.length > 0) {
          const minIdx = recommended.reduce((mi, r, i) => r.slots > 1 && r.expected_revenue_per_slot < (recommended[mi]?.expected_revenue_per_slot || Infinity) ? i : mi, 0)
          recommended[minIdx].slots--
          assigned--
        }
        while (assigned < totalSlots && recommended.length > 0) {
          const maxIdx = recommended.reduce((mi, r, i) => r.expected_revenue_per_slot > (recommended[mi]?.expected_revenue_per_slot || 0) ? i : mi, 0)
          recommended[maxIdx].slots++
          assigned++
        }

        const currentRevPerSlot = branchMotos.length > 0
          ? Math.round(completedBookings.reduce((s: number, b: Record<string, unknown>) => s + ((b.total_price as number) || 0), 0) / branchMotos.length)
          : 0
        const optimizedRevPerSlot = recommended.length > 0
          ? Math.round(recommended.reduce((s, r) => s + r.expected_revenue_per_slot * r.slots, 0) / totalSlots)
          : 0
        const improvementPct = currentRevPerSlot > 0 ? Math.round((optimizedRevPerSlot / currentRevPerSlot - 1) * 1000) / 10 : 0

        result = {
          branch: { id: branch.id, name: branch.name, type: branchType },
          current, recommended,
          potential: { current_rev_per_slot: currentRevPerSlot, optimized_rev_per_slot: optimizedRevPerSlot, improvement_pct: improvementPct },
          period_months: periodMonths,
        }
        break
      }

      // =====================================================================
      // 30. analyze_customers
      // =====================================================================
      case 'analyze_customers': {
        const periodMonths = (toolInput.period_months as number) || 12
        const raw = await fetchAnalyticsRawData(supabaseAdmin, periodMonths)

        const motoCategoryMap: Record<string, string> = {}
        for (const m of raw.motorcycles) motoCategoryMap[(m as Record<string, unknown>).id as string] = ((m as Record<string, unknown>).category as string) || 'unknown'

        const completedBookings = raw.bookings.filter((b: Record<string, unknown>) =>
          b.status === 'completed' && b.payment_status === 'paid'
        )

        // Per-customer stats
        const customerStats: Record<string, { revenue: number; reservations: number; categories: Record<string, number>; sources: Record<string, number> }> = {}
        for (const b of completedBookings) {
          const uid = (b as Record<string, unknown>).user_id as string
          if (!uid) continue
          if (!customerStats[uid]) customerStats[uid] = { revenue: 0, reservations: 0, categories: {}, sources: {} }
          customerStats[uid].revenue += ((b as Record<string, unknown>).total_price as number) || 0
          customerStats[uid].reservations++
          const cat = motoCategoryMap[(b as Record<string, unknown>).moto_id as string] || 'unknown'
          customerStats[uid].categories[cat] = (customerStats[uid].categories[cat] || 0) + 1
          const src = ((b as Record<string, unknown>).booking_source as string) || 'app'
          customerStats[uid].sources[src] = (customerStats[uid].sources[src] || 0) + 1
        }

        // Segmentation
        const profileMap: Record<string, Record<string, unknown>> = {}
        for (const p of raw.profiles) profileMap[(p as Record<string, unknown>).id as string] = p as Record<string, unknown>

        let vip = 0, regular = 0, occasional = 0, inactive = 0
        const topCustomers: Array<Record<string, unknown>> = []

        for (const p of raw.profiles) {
          const uid = (p as Record<string, unknown>).id as string
          const stats = customerStats[uid]
          if (!stats || stats.reservations === 0) { inactive++; continue }
          if (stats.revenue >= 20000 || stats.reservations >= 5) vip++
          else if (stats.reservations >= 2) regular++
          else occasional++

          topCustomers.push({
            id: uid, name: (p as Record<string, unknown>).full_name, email: (p as Record<string, unknown>).email,
            city: (p as Record<string, unknown>).city,
            revenue: stats.revenue, reservations: stats.reservations,
            segment: stats.revenue >= 20000 || stats.reservations >= 5 ? 'VIP' : stats.reservations >= 2 ? 'Regular' : 'Occasional',
          })
        }
        topCustomers.sort((a, b) => (b.revenue as number) - (a.revenue as number))

        // Category preference
        const catPref: Record<string, number> = {}
        for (const stats of Object.values(customerStats)) {
          for (const [cat, cnt] of Object.entries(stats.categories)) {
            catPref[cat] = (catPref[cat] || 0) + cnt
          }
        }
        const categoryPreference = Object.entries(catPref)
          .map(([category, count]) => ({ category, booking_count: count }))
          .sort((a, b) => b.booking_count - a.booking_count)

        // Booking source
        const srcStats: Record<string, number> = {}
        for (const stats of Object.values(customerStats)) {
          for (const [src, cnt] of Object.entries(stats.sources)) {
            srcStats[src] = (srcStats[src] || 0) + cnt
          }
        }
        const bookingSources = Object.entries(srcStats).map(([source, count]) => ({ source, count }))

        // City distribution (top 10)
        const cityStats: Record<string, number> = {}
        for (const p of raw.profiles) {
          const city = ((p as Record<string, unknown>).city as string) || 'Neznámé'
          cityStats[city] = (cityStats[city] || 0) + 1
        }
        const cityDistribution = Object.entries(cityStats)
          .map(([city, count]) => ({ city, count }))
          .sort((a, b) => b.count - a.count)
          .slice(0, 10)

        // License groups
        const licenseStats: Record<string, number> = {}
        for (const p of raw.profiles) {
          const groups = (p as Record<string, unknown>).license_group as string[] | null
          if (groups && Array.isArray(groups)) {
            for (const g of groups) licenseStats[g] = (licenseStats[g] || 0) + 1
          }
        }

        const totalRevenue = Object.values(customerStats).reduce((s, c) => s + c.revenue, 0)
        const totalCustomers = raw.profiles.length

        result = {
          segments: { vip, regular, occasional, inactive, total: totalCustomers },
          top_customers: topCustomers.slice(0, 20),
          category_preference: categoryPreference,
          booking_sources: bookingSources,
          city_distribution: cityDistribution,
          license_groups: licenseStats,
          kpis: {
            total_customers: totalCustomers,
            active_customers: totalCustomers - inactive,
            total_revenue: totalRevenue,
            avg_revenue_per_customer: totalCustomers - inactive > 0 ? Math.round(totalRevenue / (totalCustomers - inactive)) : 0,
            avg_bookings_per_customer: totalCustomers - inactive > 0 ? Math.round(completedBookings.length / (totalCustomers - inactive) * 10) / 10 : 0,
          },
          period_months: periodMonths,
        }
        break
      }

      // =====================================================================
      // 31. forecast_predictions
      // =====================================================================
      case 'forecast_predictions': {
        const monthsAhead = (toolInput.months_ahead as number) || 3
        const branchId = toolInput.branch_id as string | undefined

        // Fetch ALL completed bookings (full history, not just period)
        let bQuery = supabaseAdmin.from('bookings')
          .select('id, moto_id, total_price, start_date, end_date, status, payment_status, created_at')
          .eq('status', 'completed')
          .eq('payment_status', 'paid')
          .order('created_at', { ascending: true })

        if (branchId) {
          const { data: branchMotos } = await supabaseAdmin.from('motorcycles').select('id').eq('branch_id', branchId)
          const motoIds = (branchMotos || []).map((m: Record<string, unknown>) => m.id as string)
          if (motoIds.length > 0) {
            bQuery = bQuery.in('moto_id', motoIds)
          } else {
            result = { error: 'Pobočka nemá žádné motorky' }
            break
          }
        }

        const { data: allBookings } = await bQuery
        if (!allBookings || allBookings.length === 0) {
          result = { error: 'Nedostatek dat pro predikci', available_months: 0 }
          break
        }

        // Group by month
        const monthlyData: Record<string, { revenue: number; bookingCount: number }> = {}
        for (const b of allBookings) {
          const month = ((b as Record<string, unknown>).created_at as string).slice(0, 7) // YYYY-MM
          if (!monthlyData[month]) monthlyData[month] = { revenue: 0, bookingCount: 0 }
          monthlyData[month].revenue += ((b as Record<string, unknown>).total_price as number) || 0
          monthlyData[month].bookingCount++
        }

        const sortedMonths = Object.keys(monthlyData).sort()
        if (sortedMonths.length < 3) {
          result = { error: 'Nedostatek dat pro predikci (min 3 měsíce)', available_months: sortedMonths.length }
          break
        }

        const historical = sortedMonths.map(m => ({
          month: m,
          revenue: Math.round(monthlyData[m].revenue),
          booking_count: monthlyData[m].bookingCount,
        }))

        // Seasonal coefficients: for each calendar month (1-12), avg share of total annual revenue
        const calMonthRevenue: Record<number, number[]> = {}
        for (const m of sortedMonths) {
          const calMonth = parseInt(m.split('-')[1])
          if (!calMonthRevenue[calMonth]) calMonthRevenue[calMonth] = []
          calMonthRevenue[calMonth].push(monthlyData[m].revenue)
        }
        const avgMonthlyRev = sortedMonths.reduce((s, m) => s + monthlyData[m].revenue, 0) / sortedMonths.length
        const seasonalCoeffs: Record<number, number> = {}
        for (let cm = 1; cm <= 12; cm++) {
          const revs = calMonthRevenue[cm]
          if (revs && revs.length > 0) {
            const avg = revs.reduce((s, v) => s + v, 0) / revs.length
            seasonalCoeffs[cm] = avgMonthlyRev > 0 ? avg / avgMonthlyRev : 1
          } else {
            seasonalCoeffs[cm] = 1
          }
        }

        // Linear trend: slope
        const firstRev = monthlyData[sortedMonths[0]].revenue
        const lastRev = monthlyData[sortedMonths[sortedMonths.length - 1]].revenue
        const slope = (lastRev - firstRev) / Math.max(1, sortedMonths.length - 1)

        // Generate predictions
        const predictions: Array<{ month: string; predicted_revenue: number; predicted_bookings: number; confidence: string; seasonal_factor: number }> = []
        const nowDate = new Date()
        const avgBookingsPerRevenue = historical.reduce((s, h) => s + h.booking_count, 0) / Math.max(1, historical.reduce((s, h) => s + h.revenue, 0))

        for (let i = 1; i <= monthsAhead; i++) {
          const futureDate = new Date(nowDate.getFullYear(), nowDate.getMonth() + i, 1)
          const futureMonth = `${futureDate.getFullYear()}-${String(futureDate.getMonth() + 1).padStart(2, '0')}`
          const calMonth = futureDate.getMonth() + 1
          const offset = sortedMonths.length + i - 1
          const baseline = lastRev + slope * i
          const seasonalFactor = seasonalCoeffs[calMonth] || 1
          const predictedRevenue = Math.max(0, Math.round(baseline * seasonalFactor))
          const predictedBookings = Math.round(predictedRevenue * avgBookingsPerRevenue)
          const confidence = sortedMonths.length > 6 ? 'high' : sortedMonths.length >= 3 ? 'medium' : 'low'

          predictions.push({
            month: futureMonth, predicted_revenue: predictedRevenue,
            predicted_bookings: predictedBookings, confidence,
            seasonal_factor: Math.round(seasonalFactor * 100) / 100,
          })
        }

        // Find peak and low months
        let peakMonth = 1, lowMonth = 1, peakVal = 0, lowVal = Infinity
        for (let cm = 1; cm <= 12; cm++) {
          if (seasonalCoeffs[cm] > peakVal) { peakVal = seasonalCoeffs[cm]; peakMonth = cm }
          if (seasonalCoeffs[cm] < lowVal) { lowVal = seasonalCoeffs[cm]; lowMonth = cm }
        }

        result = {
          historical,
          predictions,
          trend: {
            monthly_growth: Math.round(slope),
            peak_month: peakMonth,
            low_month: lowMonth,
          },
          data_quality: {
            months_available: sortedMonths.length,
            confidence_level: sortedMonths.length > 6 ? 'high' : sortedMonths.length >= 3 ? 'medium' : 'low',
          },
        }
        break
      }

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
// Export
export { executeTool }
