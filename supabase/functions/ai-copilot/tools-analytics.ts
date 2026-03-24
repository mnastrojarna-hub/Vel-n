// Analytics tools 26-31: Branch/Moto/Category performance, Optimal fleet, Customers, Forecast
import type { SB } from './tools-constants.ts'
import { FLEET_CALC, fetchAnalyticsRawData, diffDays } from './tools-constants.ts'

// deno-lint-ignore no-explicit-any
type R = Record<string, any>

export async function execAnalytics(name: string, input: R, sb: SB): Promise<unknown> {
  switch (name) {
    case 'analyze_branch_performance': {
      const pm = (input.period_months as number) || 6
      const raw = await fetchAnalyticsRawData(sb, pm)
      const pd = pm * 30, nd = new Date()
      const cms = new Date(nd.getFullYear(), nd.getMonth(), 1).toISOString()
      const pms = new Date(nd.getFullYear(), nd.getMonth() - 1, 1).toISOString()
      const completed = raw.bookings.filter((b: R) => b.status === 'completed' && b.payment_status === 'paid')
      const mbm: R = {}, mcm: R = {}
      for (const m of raw.motorcycles) { mbm[m.id] = m.branch_id; mcm[m.id] = m.category || 'unknown' }
      const stats = raw.branches.map((branch: R) => {
        const bmids = raw.motorcycles.filter((m: R) => m.branch_id === branch.id).map((m: R) => m.id)
        const mc = bmids.length
        const bb = completed.filter((b: R) => bmids.includes(b.moto_id))
        const rev = bb.reduce((s: number, b: R) => s + (b.total_price || 0), 0)
        const rd = bb.reduce((s: number, b: R) => s + diffDays(b.start_date, b.end_date), 0)
        const util = mc > 0 ? Math.round(rd / (mc * pd) * 1000) / 10 : 0
        const cats = bmids.map((id: string) => mcm[id] || 'naked')
        const avgSvc = cats.reduce((s: number, cat: string) => { const p = FLEET_CALC.categoryParams[cat] || FLEET_CALC.categoryParams['naked']; return s + p.avgServicePerEvent * p.servicesPerYear + p.insuranceCleaningYear }, 0) / Math.max(1, cats.length)
        const profit = mc > 0 ? Math.round((rev - avgSvc * mc - rev * FLEET_CALC.marketingPct - FLEET_CALC.otherFixedPerBike * mc) / mc) : 0
        const curRev = bb.filter((b: R) => b.created_at >= cms).reduce((s: number, b: R) => s + (b.total_price || 0), 0)
        const prevRev = bb.filter((b: R) => b.created_at >= pms && b.created_at < cms).reduce((s: number, b: R) => s + (b.total_price || 0), 0)
        const chg = prevRev > 0 ? (curRev / prevRev - 1) * 100 : 0
        return { id: branch.id, name: branch.name, city: branch.city, type: branch.type, motorcycle_count: mc, reservations: bb.length, revenue: rev, revenue_per_moto: mc > 0 ? Math.round(rev / mc) : 0, utilization_pct: util, rented_days: rd, profit_per_moto: profit, trend: chg > 10 ? 'Rostoucí' : chg < -5 ? 'Klesající' : 'Stagnující', trend_change_pct: Math.round(chg * 10) / 10 }
      })
      const totalRev = stats.reduce((s: number, b: R) => s + b.revenue, 0)
      const totalRes = stats.reduce((s: number, b: R) => s + b.reservations, 0)
      const avgUtil = stats.length > 0 ? Math.round(stats.reduce((s: number, b: R) => s + b.utilization_pct, 0) / stats.length * 10) / 10 : 0
      return { branches: stats, totals: { revenue: totalRev, reservations: totalRes, avg_utilization: avgUtil }, period_months: pm }
    }

    case 'analyze_motorcycle_performance': {
      const pm = (input.period_months as number) || 6
      const raw = await fetchAnalyticsRawData(sb, pm)
      const pd = pm * 30
      const completed = raw.bookings.filter((b: R) => b.status === 'completed' && b.payment_status === 'paid')
      const ms = raw.motorcycles.map((moto: R) => {
        const mb = completed.filter((b: R) => b.moto_id === moto.id)
        const rev = mb.reduce((s: number, b: R) => s + (b.total_price || 0), 0)
        const rd = mb.reduce((s: number, b: R) => s + diffDays(b.start_date, b.end_date), 0)
        return { id: moto.id, model: moto.model, brand: moto.brand, category: moto.category, status: moto.status, mileage: moto.mileage, purchase_price: moto.purchase_price, reservations: mb.length, revenue: rev, rented_days: rd, utilization_pct: Math.round(rd / pd * 1000) / 10, avg_daily_rate: rd > 0 ? Math.round(rev / rd) : 0 }
      }).sort((a: R, b: R) => b.revenue - a.revenue)
      const bm: R = {}
      for (const m of ms) { const br = m.brand || 'Unknown'; if (!bm[br]) bm[br] = { revenue: 0, count: 0, utilSum: 0 }; bm[br].revenue += m.revenue; bm[br].count++; bm[br].utilSum += m.utilization_pct }
      const maxRPM = Math.max(...Object.values(bm).map((b: R) => b.count > 0 ? b.revenue / b.count : 0), 1)
      const bs = Object.entries(bm).map(([brand, d]: [string, R]) => {
        const au = d.count > 0 ? Math.round(d.utilSum / d.count * 10) / 10 : 0
        const rpm = d.count > 0 ? Math.round(d.revenue / d.count) : 0
        return { brand, motorcycle_count: d.count, total_revenue: d.revenue, revenue_per_moto: rpm, avg_utilization: au, performance_score: Math.round(((rpm / maxRPM) + (au / 100)) / 2 * 100) / 100 }
      }).sort((a, b) => b.performance_score - a.performance_score)
      return { motorcycles: ms, brand_stats: bs, period_months: pm }
    }

    case 'analyze_category_demand': {
      const pm = (input.period_months as number) || 6
      const raw = await fetchAnalyticsRawData(sb, pm)
      const pd = pm * 30
      const mcm: R = {}; for (const m of raw.motorcycles) mcm[m.id] = m.category || 'unknown'
      const completed = raw.bookings.filter((b: R) => b.status === 'completed' && b.payment_status === 'paid')
      const cmc: R = {}; for (const m of raw.motorcycles) { const c = m.category || 'unknown'; cmc[c] = (cmc[c] || 0) + 1 }
      const cs: R = {}
      for (const b of completed) { const c = mcm[b.moto_id] || 'unknown'; if (!cs[c]) cs[c] = { res: 0, rev: 0, rd: 0 }; cs[c].res++; cs[c].rev += b.total_price || 0; cs[c].rd += diffDays(b.start_date, b.end_date) }
      const cats = Object.entries(cs).map(([cat, d]: [string, R]) => {
        const mc = cmc[cat] || 1
        return { category: cat, motorcycle_count: cmc[cat] || 0, reservation_count: d.res, total_revenue: d.rev, revenue_per_moto: Math.round(d.rev / mc), avg_utilization: Math.round(d.rd / (mc * pd) * 1000) / 10, rented_days: d.rd }
      }).sort((a, b) => b.avg_utilization - a.avg_utilization)
      return { categories: cats, period_months: pm }
    }

    case 'analyze_optimal_fleet': {
      const branchId = input.branch_id as string
      if (!branchId) return { error: 'branch_id je povinný parametr' }
      const pm = (input.period_months as number) || 6
      const raw = await fetchAnalyticsRawData(sb, pm)
      const pd = pm * 30
      const branch = raw.branches.find((b: R) => b.id === branchId)
      if (!branch) return { error: 'Pobočka nenalezena' }
      const bMotos = raw.motorcycles.filter((m: R) => m.branch_id === branchId)
      const bmIds = bMotos.map((m: R) => m.id)
      const mcm: R = {}; for (const m of bMotos) mcm[m.id] = m.category || 'unknown'
      const completed = raw.bookings.filter((b: R) => b.status === 'completed' && b.payment_status === 'paid' && bmIds.includes(b.moto_id))
      const cf: R = {}
      for (const m of bMotos) { const c = m.category || 'unknown'; if (!cf[c]) cf[c] = { count: 0, rev: 0, rd: 0 }; cf[c].count++ }
      for (const b of completed) { const c = mcm[b.moto_id] || 'unknown'; if (cf[c]) { cf[c].rev += b.total_price || 0; cf[c].rd += diffDays(b.start_date, b.end_date) } }
      const current = Object.entries(cf).map(([cat, d]: [string, R]) => ({ category: cat, count: d.count, revenue: d.rev, utilization_pct: d.count > 0 ? Math.round(d.rd / (d.count * pd) * 1000) / 10 : 0, revenue_per_slot: d.count > 0 ? Math.round(d.rev / d.count) : 0 }))
      const bt = (branch.type as string) || 'turistická'
      const bud = FLEET_CALC.branchUtilization[bt] || FLEET_CALC.branchUtilization['turistická']
      const scores: Array<{ category: string; score: number; erps: number; up: number }> = []
      for (const [cat, params] of Object.entries(FLEET_CALC.categoryParams)) {
        const uf = bud[cat] || 0.3
        const ex = cf[cat]; const ru = ex && ex.count > 0 ? ex.rd / (ex.count * pd) : uf
        const up = Math.round(ru * 1000) / 10; const erps = Math.round(params.avgDailyRate * pd * ru)
        if (up > 40) scores.push({ category: cat, score: erps * ru, erps, up })
      }
      scores.sort((a, b) => b.score - a.score)
      const ts = scores.reduce((s, c) => s + c.score, 0)
      let assigned = 0
      const rec = scores.map(c => { const slots = Math.max(1, Math.round(ts > 0 ? (c.score / ts) * 8 : 0)); assigned += slots; return { category: c.category, slots, expected_revenue_per_slot: c.erps, utilization_pct: c.up } })
      while (assigned > 8 && rec.length > 0) { const mi = rec.reduce((mi, r, i) => r.slots > 1 && r.expected_revenue_per_slot < (rec[mi]?.expected_revenue_per_slot || Infinity) ? i : mi, 0); rec[mi].slots--; assigned-- }
      while (assigned < 8 && rec.length > 0) { const mi = rec.reduce((mi, r, i) => r.expected_revenue_per_slot > (rec[mi]?.expected_revenue_per_slot || 0) ? i : mi, 0); rec[mi].slots++; assigned++ }
      const crps = bMotos.length > 0 ? Math.round(completed.reduce((s: number, b: R) => s + (b.total_price || 0), 0) / bMotos.length) : 0
      const orps = rec.length > 0 ? Math.round(rec.reduce((s, r) => s + r.expected_revenue_per_slot * r.slots, 0) / 8) : 0
      return { branch: { id: branch.id, name: branch.name, type: bt }, current, recommended: rec, potential: { current_rev_per_slot: crps, optimized_rev_per_slot: orps, improvement_pct: crps > 0 ? Math.round((orps / crps - 1) * 1000) / 10 : 0 }, period_months: pm }
    }

    case 'analyze_customers': {
      const pm = (input.period_months as number) || 12
      const raw = await fetchAnalyticsRawData(sb, pm)
      const mcm: R = {}; for (const m of raw.motorcycles) mcm[m.id] = m.category || 'unknown'
      const completed = raw.bookings.filter((b: R) => b.status === 'completed' && b.payment_status === 'paid')
      const cs: R = {}
      for (const b of completed) { const uid = b.user_id; if (!uid) continue; if (!cs[uid]) cs[uid] = { rev: 0, res: 0, cats: {} as R, srcs: {} as R }; cs[uid].rev += b.total_price || 0; cs[uid].res++; const c = mcm[b.moto_id] || 'unknown'; cs[uid].cats[c] = (cs[uid].cats[c] || 0) + 1; const src = b.booking_source || 'app'; cs[uid].srcs[src] = (cs[uid].srcs[src] || 0) + 1 }
      let vip = 0, regular = 0, occasional = 0, inactive = 0
      const top: R[] = []
      for (const p of raw.profiles) { const s = cs[p.id]; if (!s || s.res === 0) { inactive++; continue }; if (s.rev >= 20000 || s.res >= 5) vip++; else if (s.res >= 2) regular++; else occasional++; top.push({ id: p.id, name: p.full_name, email: p.email, city: p.city, revenue: s.rev, reservations: s.res, segment: s.rev >= 20000 || s.res >= 5 ? 'VIP' : s.res >= 2 ? 'Regular' : 'Occasional' }) }
      top.sort((a, b) => b.revenue - a.revenue)
      const cp: R = {}, srcS: R = {}, cityS: R = {}, licS: R = {}
      for (const s of Object.values(cs) as R[]) { for (const [c, n] of Object.entries(s.cats)) cp[c] = (cp[c] || 0) + (n as number); for (const [src, n] of Object.entries(s.srcs)) srcS[src] = (srcS[src] || 0) + (n as number) }
      for (const p of raw.profiles) { const city = p.city || 'Neznámé'; cityS[city] = (cityS[city] || 0) + 1; if (Array.isArray(p.license_group)) for (const g of p.license_group) licS[g] = (licS[g] || 0) + 1 }
      const totalRev = Object.values(cs).reduce((s: number, c: R) => s + c.rev, 0)
      const tc = raw.profiles.length, ac = tc - inactive
      return { segments: { vip, regular, occasional, inactive, total: tc }, top_customers: top.slice(0, 20), category_preference: Object.entries(cp).map(([c, n]) => ({ category: c, booking_count: n })).sort((a: R, b: R) => b.booking_count - a.booking_count), booking_sources: Object.entries(srcS).map(([s, c]) => ({ source: s, count: c })), city_distribution: Object.entries(cityS).map(([c, n]) => ({ city: c, count: n })).sort((a: R, b: R) => b.count - a.count).slice(0, 10), license_groups: licS, kpis: { total_customers: tc, active_customers: ac, total_revenue: totalRev, avg_revenue_per_customer: ac > 0 ? Math.round(totalRev / ac) : 0, avg_bookings_per_customer: ac > 0 ? Math.round(completed.length / ac * 10) / 10 : 0 }, period_months: pm }
    }

    case 'forecast_predictions': {
      const ma = (input.months_ahead as number) || 3
      const branchId = input.branch_id as string | undefined
      let bQ = sb.from('bookings').select('id, moto_id, total_price, start_date, end_date, status, payment_status, created_at').eq('status', 'completed').eq('payment_status', 'paid').order('created_at', { ascending: true })
      if (branchId) { const { data: bm } = await sb.from('motorcycles').select('id').eq('branch_id', branchId); const mids = (bm || []).map((m: R) => m.id); if (mids.length > 0) bQ = bQ.in('moto_id', mids); else return { error: 'Pobočka nemá žádné motorky' } }
      const { data: allB } = await bQ
      if (!allB || allB.length === 0) return { error: 'Nedostatek dat pro predikci', available_months: 0 }
      const md: R = {}; for (const b of allB) { const m = b.created_at.slice(0, 7); if (!md[m]) md[m] = { rev: 0, cnt: 0 }; md[m].rev += b.total_price || 0; md[m].cnt++ }
      const sm = Object.keys(md).sort()
      if (sm.length < 3) return { error: 'Nedostatek dat pro predikci (min 3 měsíce)', available_months: sm.length }
      const hist = sm.map(m => ({ month: m, revenue: Math.round(md[m].rev), booking_count: md[m].cnt }))
      const cmr: R = {}; for (const m of sm) { const cm = parseInt(m.split('-')[1]); if (!cmr[cm]) cmr[cm] = []; cmr[cm].push(md[m].rev) }
      const avgMR = sm.reduce((s: number, m: string) => s + md[m].rev, 0) / sm.length
      const sc: R = {}; for (let cm = 1; cm <= 12; cm++) { const r = cmr[cm]; sc[cm] = r && r.length > 0 ? r.reduce((s: number, v: number) => s + v, 0) / r.length / (avgMR || 1) : 1 }
      const slope = (md[sm[sm.length - 1]].rev - md[sm[0]].rev) / Math.max(1, sm.length - 1)
      const lastRev = md[sm[sm.length - 1]].rev
      const avgBPR = hist.reduce((s, h) => s + h.booking_count, 0) / Math.max(1, hist.reduce((s, h) => s + h.revenue, 0))
      const nd = new Date()
      const preds = []
      for (let i = 1; i <= ma; i++) {
        const fd = new Date(nd.getFullYear(), nd.getMonth() + i, 1)
        const fm = `${fd.getFullYear()}-${String(fd.getMonth() + 1).padStart(2, '0')}`
        const cm = fd.getMonth() + 1, sf = sc[cm] || 1
        const pr = Math.max(0, Math.round((lastRev + slope * i) * sf))
        preds.push({ month: fm, predicted_revenue: pr, predicted_bookings: Math.round(pr * avgBPR), confidence: sm.length > 6 ? 'high' : sm.length >= 3 ? 'medium' : 'low', seasonal_factor: Math.round(sf * 100) / 100 })
      }
      let peakM = 1, lowM = 1, peakV = 0, lowV = Infinity
      for (let cm = 1; cm <= 12; cm++) { if (sc[cm] > peakV) { peakV = sc[cm]; peakM = cm }; if (sc[cm] < lowV) { lowV = sc[cm]; lowM = cm } }
      return { historical: hist, predictions: preds, trend: { monthly_growth: Math.round(slope), peak_month: peakM, low_month: lowM }, data_quality: { months_available: sm.length, confidence_level: sm.length > 6 ? 'high' : sm.length >= 3 ? 'medium' : 'low' } }
    }

    default: return null
  }
}
