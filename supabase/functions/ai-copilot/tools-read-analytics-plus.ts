// Read tools: Analýza+ — návštěvnost webu, funnely, AI konverzace, aplikace, km, servisní plán, loyalty, trasy
import type { SB } from './tools-constants.ts'
import { PAID_BOOKING_STATUSES } from './tools-constants.ts'

// deno-lint-ignore no-explicit-any
type R = Record<string, any>

export async function execReadAnalyticsPlus(name: string, input: R, sb: SB, sbUser?: SB): Promise<unknown> {
  // RPC s is_admin() guardem volej přes JWT přihlášeného admina (service role má auth.uid()=NULL)
  const rpc = sbUser || sb
  const now = new Date()

  switch (name) {
    // Reálná lidská návštěvnost webu (visitor_log přes RPC get_visitor_stats — server-side agregace)
    case 'get_web_traffic': {
      const days = (input.days as number) || 30
      const from = new Date(now.getTime() - days * 86400000).toISOString()
      const { data, error } = await rpc.rpc('get_visitor_stats', { p_from: from, p_to: now.toISOString(), p_host: (input.host as string) || null, p_granularity: (input.granularity as string) || 'day' })
      if (error) return { error: `get_visitor_stats: ${error.message}` }
      return { period_days: days, stats: data }
    }

    // Web rezervační funnel (bookings source=web, is_test=false) — kde zákazníci odpadávají
    case 'get_web_funnel': {
      const days = (input.days as number) || 30
      const from = new Date(now.getTime() - days * 86400000).toISOString()
      const { data: rows } = await sb.from('bookings')
        .select('id, status, payment_status, created_at, checkout_started_at, docs_completed_at, created_device, completed_device, chosen_payment_method, pay_channel, form_fill_seconds, payment_fill_seconds, abandoned_email_sent_at, total_price, created_via_ai')
        .eq('booking_source', 'web').eq('is_test', false).gte('created_at', from)
      const all = rows || []
      const paid = all.filter((b: R) => PAID_BOOKING_STATUSES.includes(b.payment_status) && b.status !== 'cancelled')
      const gateway = all.filter((b: R) => !PAID_BOOKING_STATUSES.includes(b.payment_status) && b.checkout_started_at)
      const cnt = (arr: R[], key: string) => { const m: R = {}; for (const b of arr) { const v = b[key] || 'unknown'; m[v] = (m[v] || 0) + 1 } return m }
      const avg = (arr: number[]) => arr.length ? Math.round(arr.reduce((s, v) => s + v, 0) / arr.length) : null
      return {
        period_days: days, created: all.length, paid: paid.length,
        conversion_created_to_paid_pct: all.length ? Math.round(paid.length / all.length * 1000) / 10 : null,
        gateway_but_unpaid: gateway.length, cancelled: all.filter((b: R) => b.status === 'cancelled').length,
        abandoned_emails_sent: all.filter((b: R) => b.abandoned_email_sent_at).length,
        docs_completed: all.filter((b: R) => b.docs_completed_at).length,
        created_via_ai: all.filter((b: R) => b.created_via_ai).length,
        devices_step1: cnt(all, 'created_device'), devices_step2: cnt(all, 'completed_device'),
        chosen_payment_method: cnt(all, 'chosen_payment_method'), qr_channel: all.filter((b: R) => b.pay_channel === 'qr').length,
        avg_form_fill_seconds: avg(all.map((b: R) => b.form_fill_seconds).filter(Boolean)),
        avg_payment_fill_seconds: avg(all.map((b: R) => b.payment_fill_seconds).filter(Boolean)),
        paid_revenue: paid.reduce((s: number, b: R) => s + (b.total_price || 0), 0),
      }
    }

    // AI konverzace: web widget (ai_public_conversations), appka (ai_customer_conversations), AI traffic + citace
    case 'get_ai_agents_analytics': {
      const days = (input.days as number) || 30
      const from = new Date(now.getTime() - days * 86400000).toISOString()
      const limit = (input.limit as number) || 10
      const [pubR, custR, trafR, citR, aiBookR] = await Promise.all([
        sb.from('ai_public_conversations').select('id, session_id, lang, message_count, outcome, booking_id, started_at, last_activity_at').gte('started_at', from).order('started_at', { ascending: false }).limit(200),
        sb.from('ai_customer_conversations').select('id, user_id, title, booking_id, created_at, updated_at').gte('created_at', from).order('created_at', { ascending: false }).limit(limit),
        sb.from('ai_traffic_log').select('source, outcome').gte('ts', from),
        sb.from('ai_citations').select('ai_platform, query, observed_at').order('observed_at', { ascending: false }).limit(limit),
        sb.from('bookings').select('id', { count: 'exact', head: true }).eq('created_via_ai', true).gte('created_at', from),
      ])
      const pub = pubR.data || []
      const byOutcome: R = {}; for (const c of pub) { const o = c.outcome || 'view'; byOutcome[o] = (byOutcome[o] || 0) + 1 }
      const bySource: R = {}; for (const t of (trafR.data || [])) { const s = t.source || 'unknown'; bySource[s] = (bySource[s] || 0) + 1 }
      return {
        period_days: days,
        web_widget: { conversations: pub.length, by_outcome: byOutcome, with_booking: pub.filter((c: R) => c.booking_id).length, recent: pub.slice(0, limit) },
        app_agent: { conversations: (custR.data || []).length, recent: custR.data || [] },
        ai_traffic: { events: (trafR.data || []).length, by_source: bySource },
        ai_citations_recent: citR.data || [],
        bookings_created_via_ai: aiBookR.count || 0,
      }
    }

    // Mobilní aplikace — instalace, DAU/WAU/MAU, pády + KDO z registrovaných zákazníků appku reálně má
    case 'get_app_stats': {
      const [statsR, instR, crashR, profR, bookR] = await Promise.all([
        rpc.rpc('get_app_install_stats'),
        sb.from('app_installations').select('device_id, user_id, platform, push_enabled, last_seen_at'),
        sb.from('app_crash_reports').select('id, app_version, platform, screen, error_type, severity, created_at').order('created_at', { ascending: false }).limit(10),
        sb.from('profiles').select('id, registration_source, is_test_account').limit(10000),
        sb.from('bookings').select('user_id, booking_source, status').eq('is_test', false).limit(10000),
      ])
      const inst = instR.data || []
      const since = (d: number) => new Date(now.getTime() - d * 86400000).toISOString()
      const active = (d: number) => inst.filter((i: R) => i.last_seen_at >= since(d)).length
      const byPlatform: R = {}; for (const i of inst) { const p = (i.platform || 'unknown').toLowerCase(); byPlatform[p] = (byPlatform[p] || 0) + 1 }
      const realProfiles = (profR.data || []).filter((p: R) => !p.is_test_account)
      const usersWithInstall = new Set(inst.map((i: R) => i.user_id).filter(Boolean))
      const books = bookR.data || []
      const appBookUsers = new Set(books.filter((b: R) => b.booking_source === 'app' && b.status !== 'cancelled').map((b: R) => b.user_id).filter(Boolean))
      const webBookUsers = new Set(books.filter((b: R) => b.booking_source === 'web' && b.status !== 'cancelled').map((b: R) => b.user_id).filter(Boolean))
      const anyBookUsers = new Set(books.map((b: R) => b.user_id).filter(Boolean))
      const cancelledOnlyUsers = new Set([...anyBookUsers].filter(u => !appBookUsers.has(u) && !webBookUsers.has(u)))
      // POZOR: registration_source='auth_trigger' je technický placeholder — jako 'app' počítej JEN explicitní 'app'
      const regApp = realProfiles.filter((p: R) => p.registration_source === 'app').length
      const hasApp = realProfiles.filter((p: R) => usersWithInstall.has(p.id) || appBookUsers.has(p.id) || p.registration_source === 'app').length
      const seg = {
        no_booking_at_all: realProfiles.filter((p: R) => !anyBookUsers.has(p.id)).length,
        only_cancelled_bookings: realProfiles.filter((p: R) => cancelledOnlyUsers.has(p.id)).length,
        with_app_booking: realProfiles.filter((p: R) => appBookUsers.has(p.id)).length,
        with_web_booking_only: realProfiles.filter((p: R) => webBookUsers.has(p.id) && !appBookUsers.has(p.id)).length,
      }
      return {
        install_stats_rpc: statsR.error ? { error: statsR.error.message } : statsR.data,
        installations_total: inst.length, by_platform: byPlatform,
        push_enabled: inst.filter((i: R) => i.push_enabled).length,
        dau: active(1), wau: active(7), mau: active(30),
        customers_with_app: {
          real_customers_total: realProfiles.length,
          with_app_any_signal: hasApp,
          with_app_pct: realProfiles.length ? Math.round(hasApp / realProfiles.length * 1000) / 10 : null,
          via_active_installation: usersWithInstall.size,
          via_app_booking: appBookUsers.size,
          registered_via_app_explicit: regApp,
          note: 'appku má = aktivní instalace (app_installations) NEBO nestornovaná app rezervace NEBO registration_source=app. Placeholder auth_trigger NENÍ zdroj — ignoruj ho. Web rezervace appku nedokazují.',
        },
        customer_booking_segments: { ...seg, note: 'segmenty přes reálné (netestovací) zákazníky × nestornované rezervace dle booking_source' },
        recent_crashes: crashR.data || [],
      }
    }

    // Km analytika (RPC z předávacích protokolů)
    case 'get_km_analytics': {
      const [motoR, custR] = await Promise.all([rpc.rpc('analytics_moto_km'), rpc.rpc('analytics_customer_km')])
      if (motoR.error) return { error: `analytics_moto_km: ${motoR.error.message}` }
      const topCust = (custR.data || []).sort((a: R, b: R) => (b.total_km || 0) - (a.total_km || 0)).slice(0, 15)
      return { per_motorcycle: motoR.data || [], top_customers_by_km: topCust, note: 'km z předávacích protokolů (mileage_start segmenty), jen uzavřené segmenty' }
    }

    // Servisní plán per motorka × typ servisu (olej/pneu/komplet)
    case 'get_service_plan': {
      const { data, error } = await rpc.rpc('analytics_service_plan', { p_default_daily_km: (input.default_daily_km as number) || 50 })
      if (error) return { error: `analytics_service_plan: ${error.message}` }
      const rows = data || []
      return { due_soon: rows.filter((r: R) => r.due_soon && !r.overdue), overdue: rows.filter((r: R) => r.overdue), all_count: rows.length, all: rows }
    }

    // Věrnostní program — úrovně, měsíční výherci, využití app slev
    case 'get_loyalty_overview': {
      const [lvlR, winR, useR] = await Promise.all([
        sb.from('loyalty_levels').select('*').order('level'),
        sb.from('loyalty_monthly_winners').select('*').order('month', { ascending: false }).limit(12),
        sb.from('bookings').select('loyalty_level, loyalty_percent, loyalty_discount_amount').gt('loyalty_discount_amount', 0).eq('is_test', false),
      ])
      const used = useR.data || []
      return {
        levels: lvlR.data || [], monthly_winners: winR.data || [],
        app_discount_usage: { bookings_with_loyalty_discount: used.length, total_discount_czk: used.reduce((s: number, b: R) => s + (b.loyalty_discount_amount || 0), 0) },
        rules: 'Sleva 1–20 % dle ranku, JEN pro rezervace z aplikace (booking_source=app). Rank roste s počtem app rezervací (loyalty_levels.min_booking_order).',
      }
    }

    // Trasy a komunitní obsah — trasy, recenze, návrhy ke schválení
    case 'get_routes_overview': {
      const [routesR, pendR, revR, upoiR] = await Promise.all([
        sb.from('routes').select('id, name, branch_id, route_type, distance_km, duration_min, difficulty, is_active, status').limit(1000),
        sb.from('routes').select('id, name, submitted_note, created_at').eq('status', 'pending').limit(50),
        sb.from('route_reviews').select('route_id, rating, status, created_at').limit(1000),
        sb.from('user_pois').select('id, name, status, created_at').eq('status', 'pending').limit(50),
      ])
      const routes = routesR.data || []
      const revs = (revR.data || []).filter((r: R) => r.status === 'approved')
      const avgRating = revs.length ? Math.round(revs.reduce((s: number, r: R) => s + (r.rating || 0), 0) / revs.length * 10) / 10 : null
      return {
        routes_total: routes.length, routes_active: routes.filter((r: R) => r.is_active).length,
        pending_route_suggestions: pendR.data || [], pending_user_pois: upoiR.data || [],
        reviews: { approved_count: revs.length, avg_rating: avgRating },
        by_difficulty: routes.reduce((m: R, r: R) => { const d = r.difficulty || '?'; m[d] = (m[d] || 0) + 1; return m }, {}),
      }
    }

    default: return null
  }
}
