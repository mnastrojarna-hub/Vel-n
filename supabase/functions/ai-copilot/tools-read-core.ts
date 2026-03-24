// Read tools 1-8: Bookings, Fleet, SOS, Branches, Customers
import type { SB } from './tools-constants.ts'

// deno-lint-ignore no-explicit-any
type R = Record<string, any>

export async function execReadCore(name: string, input: R, sb: SB): Promise<unknown> {
  const now = new Date()
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).toISOString()
  const prevMonthStart = new Date(now.getFullYear(), now.getMonth() - 1, 1).toISOString()

  switch (name) {
    case 'get_bookings_summary': {
      const [activeR, reservedR, pendingR, completedR, cancelledR, revThisR, revPrevR] = await Promise.all([
        sb.from('bookings').select('id', { count: 'exact', head: true }).eq('status', 'active'),
        sb.from('bookings').select('id', { count: 'exact', head: true }).eq('status', 'reserved'),
        sb.from('bookings').select('id', { count: 'exact', head: true }).eq('status', 'pending'),
        sb.from('bookings').select('id', { count: 'exact', head: true }).eq('status', 'completed').gte('updated_at', monthStart),
        sb.from('bookings').select('id', { count: 'exact', head: true }).eq('status', 'cancelled').gte('updated_at', monthStart),
        sb.from('bookings').select('total_price').eq('payment_status', 'paid').gte('created_at', monthStart),
        sb.from('bookings').select('total_price').eq('payment_status', 'paid').gte('created_at', prevMonthStart).lt('created_at', monthStart),
      ])
      const revThis = (revThisR.data || []).reduce((s: number, b: R) => s + (b.total_price || 0), 0)
      const revPrev = (revPrevR.data || []).reduce((s: number, b: R) => s + (b.total_price || 0), 0)
      return {
        active: activeR.count || 0, reserved: reservedR.count || 0, pending: pendingR.count || 0,
        completed_this_month: completedR.count || 0, cancelled_this_month: cancelledR.count || 0,
        revenue_this_month: revThis, revenue_prev_month: revPrev,
        revenue_change_pct: revPrev > 0 ? Math.round((revThis / revPrev - 1) * 1000) / 10 : null,
      }
    }

    case 'get_bookings_detail': {
      const limit = (input.limit as number) || 20
      let q = sb.from('bookings')
        .select('id, user_id, moto_id, start_date, end_date, status, payment_status, total_price, pickup_method, return_method, booking_source, notes, created_at, pickup_time, promo_code, discount_amount, extras_price, deposit')
        .order('start_date', { ascending: false }).limit(limit)
      if (input.status) q = q.eq('status', input.status)
      if (input.date_from) q = q.gte('start_date', input.date_from)
      if (input.date_to) q = q.lte('start_date', input.date_to)
      const { data: bookings } = await q
      if (!bookings || bookings.length === 0) return { bookings: [], count: 0 }
      const motoIds = [...new Set(bookings.map((b: R) => b.moto_id).filter(Boolean))]
      const userIds = [...new Set(bookings.map((b: R) => b.user_id).filter(Boolean))]
      const [{ data: motos }, { data: profiles }] = await Promise.all([
        motoIds.length > 0 ? sb.from('motorcycles').select('id, model, brand, spz').in('id', motoIds) : { data: [] },
        userIds.length > 0 ? sb.from('profiles').select('id, full_name, email, phone').in('id', userIds) : { data: [] },
      ])
      const mm: R = {}; for (const m of (motos || [])) mm[m.id] = m
      const pm: R = {}; for (const p of (profiles || [])) pm[p.id] = p
      const enriched = bookings.map((b: R) => ({ ...b, motorcycle: mm[b.moto_id] || null, customer: pm[b.user_id] || null }))
      return { bookings: enriched, count: enriched.length }
    }

    case 'get_fleet_overview': {
      let q = sb.from('motorcycles').select('id, model, brand, spz, vin, status, branch_id, mileage, category, year, next_service_date, price_weekday, price_weekend, image_url, color, deposit_amount, engine_cc, power_kw')
      if (input.status) q = q.eq('status', input.status)
      if (input.branch_id) q = q.eq('branch_id', input.branch_id)
      const { data: motos } = await q
      const { data: branches } = await sb.from('branches').select('id, name, branch_code')
      const bm: R = {}; for (const b of (branches || [])) bm[b.id] = b
      const byStatus: R = {}
      for (const m of (motos || [])) { const s = m.status; byStatus[s] = (byStatus[s] || 0) + 1 }
      return { total: (motos || []).length, by_status: byStatus, motorcycles: (motos || []).map((m: R) => ({ ...m, branch: bm[m.branch_id] || null })) }
    }

    case 'get_motorcycle_detail': {
      let moto: R | null = null
      if (input.motorcycle_id) { const { data } = await sb.from('motorcycles').select('*').eq('id', input.motorcycle_id).single(); moto = data }
      else if (input.spz) { const { data } = await sb.from('motorcycles').select('*').ilike('spz', `%${input.spz}%`).limit(1).single(); moto = data }
      else if (input.model_search) { const s = `%${input.model_search}%`; const { data } = await sb.from('motorcycles').select('*').or(`model.ilike.${s},brand.ilike.${s}`).limit(1); moto = data?.[0] || null }
      if (!moto) return { error: 'Motorka nenalezena' }
      const [bookingsR, serviceR] = await Promise.all([
        sb.from('bookings').select('id, start_date, end_date, status, payment_status, total_price, user_id').eq('moto_id', moto.id).order('start_date', { ascending: false }).limit(10),
        sb.from('service_orders').select('*').eq('moto_id', moto.id).order('created_at', { ascending: false }),
      ])
      return { motorcycle: moto, recent_bookings: bookingsR.data || [], service_orders: serviceR.data || [] }
    }

    case 'get_sos_incidents': {
      const limit = (input.limit as number) || 20
      let q = sb.from('sos_incidents').select('id, type, severity, status, title, description, created_at, moto_id, booking_id, user_id, address, customer_decision, replacement_status, customer_fault, damage_severity, resolved_at').order('created_at', { ascending: false }).limit(limit)
      if (input.status) q = q.eq('status', input.status)
      const { data } = await q
      return { incidents: data || [], count: (data || []).length }
    }

    case 'get_branches': {
      const [branchesR, motosR] = await Promise.all([
        sb.from('branches').select('id, name, branch_code, is_open, type, created_at'),
        sb.from('motorcycles').select('id, branch_id, status'),
      ])
      const motos = motosR.data || []
      const branches = (branchesR.data || []).map((b: R) => {
        const bm = motos.filter((m: R) => m.branch_id === b.id)
        return { ...b, total_motos: bm.length, active_motos: bm.filter((m: R) => m.status === 'active').length, unavailable_motos: bm.filter((m: R) => m.status === 'unavailable').length, maintenance_motos: bm.filter((m: R) => m.status === 'maintenance').length }
      })
      return { branches, count: branches.length }
    }

    case 'get_customers': {
      const limit = (input.limit as number) || 20
      const { count } = await sb.from('profiles').select('id', { count: 'exact', head: true })
      let q = sb.from('profiles').select('id, full_name, email, phone, city, created_at, reliability_score, preferred_branch').order('created_at', { ascending: false }).limit(limit)
      if (input.search) q = q.or(`full_name.ilike.%${input.search}%,email.ilike.%${input.search}%`)
      const { data } = await q
      return { total_count: count || 0, customers: data || [] }
    }

    case 'get_customer_detail': {
      let profile: R | null = null
      if (input.customer_id) { const { data } = await sb.from('profiles').select('*').eq('id', input.customer_id).single(); profile = data }
      else if (input.email) { const { data } = await sb.from('profiles').select('*').eq('email', input.email).single(); profile = data }
      else if (input.name_search) { const { data } = await sb.from('profiles').select('*').ilike('full_name', `%${input.name_search}%`).limit(1); profile = data?.[0] || null }
      if (!profile) return { error: 'Zákazník nenalezen' }
      const [bookingsR, documentsR, reviewsR] = await Promise.all([
        sb.from('bookings').select('id, start_date, end_date, status, payment_status, total_price, moto_id').eq('user_id', profile.id).order('start_date', { ascending: false }).limit(20),
        sb.from('documents').select('id, type, created_at').eq('user_id', profile.id).order('created_at', { ascending: false }),
        sb.from('reviews').select('id, rating, created_at').eq('user_id', profile.id),
      ])
      return { profile, bookings: bookingsR.data || [], documents: documentsR.data || [], reviews: reviewsR.data || [], bookings_count: (bookingsR.data || []).length }
    }

    default: return null
  }
}
