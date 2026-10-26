// Analytics tools 26-31: Branch/Moto/Category performance, Optimal fleet, Customers, Forecast
import { FLEET_CALC, fetchAnalyticsRawData, diffDays, isRealizedBooking, PAID_BOOKING_STATUSES, bookingBranchOf, branchBookingsOr, fetchAllRows } from './tools-constants.ts';
import { branchFleetStats, profitPerMotoYear, MIN_EXPOSURE_DAYS } from './tools-branch-fleet.ts';
// Výkon poboček: JEDNO přiřazení — rezervace/obrat = pobočka rezervace (bookings.branch_id, u NULL pobočka
// motorky); flotila/obsazenost/zisk = moto-dny motorek, které na pobočce v okně reálně stály
// (tools-branch-fleet.ts = port velin/src/lib/branchFleet.js). Ne aktuální flotila pobočky.
const FLEET_NOTE = 'Pobočka rezervace = kde zákazník převzal (bookings.branch_id). Flotila, obsazenost, obrat/motorku a zisk/motorku z moto-dnů: motorka se počítá pobočce jen za dny, kdy tam reálně stála (přesun dnes = až od dneška; přesuny před 30. 9. 2026 nejsou zalogované → do té doby poslední známá pobočka). motorcycle_count = aktuální počet; avg_fleet = průměr v období. Méně než ' + MIN_EXPOSURE_DAYS + ' moto-dní → per-motorku null.';
export async function execAnalytics(name, input, sb) {
  switch(name){
    case 'analyze_branch_performance':
      {
        const pm = input.period_months || 6;
        const raw = await fetchAnalyticsRawData(sb, pm);
        const fleet = await branchFleetStats(sb, pm, raw.motorcycles);
        const nd = new Date();
        const cms = new Date(nd.getFullYear(), nd.getMonth(), 1).toISOString();
        const pms = new Date(nd.getFullYear(), nd.getMonth() - 1, 1).toISOString();
        const completed = raw.bookings.filter((b)=>isRealizedBooking(b));
        const mbm = {}, mById = {};
        for (const m of raw.motorcycles){
          mbm[m.id] = m.branch_id;
          mById[m.id] = m;
        }
        const stats = raw.branches.map((branch)=>{
          const mc = raw.motorcycles.filter((m)=>m.branch_id === branch.id && !m.is_trailer).length;
          const bb = completed.filter((b)=>bookingBranchOf(b, mbm) === branch.id);
          const rev = bb.reduce((s, b)=>s + (Number(b.total_price) || 0), 0);
          const st = fleet.byBranch[branch.id];
          const md = st?.motoDays || 0, rd = st?.rentedDays || 0;
          const avgFleet = fleet.days > 0 ? md / fleet.days : 0;
          const ok = md >= MIN_EXPOSURE_DAYS && avgFleet > 0;
          const ppy = profitPerMotoYear(st, mById);
          const curRev = bb.filter((b)=>b.created_at >= cms).reduce((s, b)=>s + (Number(b.total_price) || 0), 0);
          const prevRev = bb.filter((b)=>b.created_at >= pms && b.created_at < cms).reduce((s, b)=>s + (Number(b.total_price) || 0), 0);
          const chg = prevRev > 0 ? (curRev / prevRev - 1) * 100 : 0;
          // Výpůjčky JEN VÝBAVY na pobočce (bookings.branch_id) — mimo moto metriky, obrat zvlášť
          const gb = raw.gearBookings.filter((b)=>isRealizedBooking(b) && b.branch_id === branch.id);
          const gearRental = {
            reservations: gb.length,
            revenue: gb.reduce((s, b)=>s + (Number(b.total_price) || 0), 0)
          };
          return {
            id: branch.id,
            name: branch.name,
            city: branch.city,
            type: branch.type,
            gear_rental: gearRental,
            motorcycle_count: mc,
            avg_fleet: Math.round(avgFleet * 10) / 10,
            moto_days: md,
            reservations: bb.length,
            revenue: rev,
            revenue_per_moto: ok ? Math.round(rev / avgFleet) : null,
            utilization_pct: md > 0 ? Math.round(rd / md * 1000) / 10 : 0,
            rented_days: rd,
            profit_per_moto: ppy != null ? Math.round(ppy) : null,
            trend: chg > 10 ? 'Rostoucí' : chg < -5 ? 'Klesající' : 'Stagnující',
            trend_change_pct: Math.round(chg * 10) / 10
          };
        });
        const totalRev = stats.reduce((s, b)=>s + b.revenue, 0);
        const totalRes = stats.reduce((s, b)=>s + b.reservations, 0);
        const tmd = stats.reduce((s, b)=>s + b.moto_days, 0), trd = stats.reduce((s, b)=>s + b.rented_days, 0);
        const avgUtil = tmd > 0 ? Math.round(trd / tmd * 1000) / 10 : 0;
        const gearRev = stats.reduce((s, b)=>s + b.gear_rental.revenue, 0);
        const gearRes = stats.reduce((s, b)=>s + b.gear_rental.reservations, 0);
        return {
          branches: stats,
          totals: {
            revenue: totalRev,
            reservations: totalRes,
            avg_utilization: avgUtil,
            gear_rental_revenue: gearRev,
            gear_rental_reservations: gearRes
          },
          period_months: pm,
          method: FLEET_NOTE,
          note: 'revenue/reservations/utilization = rezervace MOTOREK; výpůjčky jen výbavy (bez motorky) jsou zvlášť v gear_rental (obrat celkem = revenue + gear_rental_revenue).'
        };
      }
    case 'analyze_motorcycle_performance':
      {
        const pm = input.period_months || 6;
        const raw = await fetchAnalyticsRawData(sb, pm);
        const pd = pm * 30;
        const completed = raw.bookings.filter((b)=>isRealizedBooking(b));
        const ms = raw.motorcycles.map((moto)=>{
          const mb = completed.filter((b)=>b.moto_id === moto.id);
          const rev = mb.reduce((s, b)=>s + (b.total_price || 0), 0);
          const rd = mb.reduce((s, b)=>s + diffDays(b.start_date, b.end_date), 0);
          return {
            id: moto.id,
            model: moto.model,
            brand: moto.brand,
            category: moto.category,
            status: moto.status,
            mileage: moto.mileage,
            purchase_price: moto.purchase_price,
            reservations: mb.length,
            revenue: rev,
            rented_days: rd,
            utilization_pct: Math.round(rd / pd * 1000) / 10,
            avg_daily_rate: rd > 0 ? Math.round(rev / rd) : 0
          };
        }).sort((a, b)=>b.revenue - a.revenue);
        const bm = {};
        for (const m of ms){
          const br = m.brand || 'Unknown';
          if (!bm[br]) bm[br] = {
            revenue: 0,
            count: 0,
            utilSum: 0
          };
          bm[br].revenue += m.revenue;
          bm[br].count++;
          bm[br].utilSum += m.utilization_pct;
        }
        const maxRPM = Math.max(...Object.values(bm).map((b)=>b.count > 0 ? b.revenue / b.count : 0), 1);
        const bs = Object.entries(bm).map(([brand, d])=>{
          const au = d.count > 0 ? Math.round(d.utilSum / d.count * 10) / 10 : 0;
          const rpm = d.count > 0 ? Math.round(d.revenue / d.count) : 0;
          return {
            brand,
            motorcycle_count: d.count,
            total_revenue: d.revenue,
            revenue_per_moto: rpm,
            avg_utilization: au,
            performance_score: Math.round((rpm / maxRPM + au / 100) / 2 * 100) / 100
          };
        }).sort((a, b)=>b.performance_score - a.performance_score);
        return {
          motorcycles: ms,
          brand_stats: bs,
          period_months: pm
        };
      }
    case 'analyze_category_demand':
      {
        const pm = input.period_months || 6;
        const raw = await fetchAnalyticsRawData(sb, pm);
        const pd = pm * 30;
        const mcm = {};
        for (const m of raw.motorcycles)mcm[m.id] = m.category || 'unknown';
        const completed = raw.bookings.filter((b)=>isRealizedBooking(b));
        const cmc = {};
        for (const m of raw.motorcycles){
          const c = m.category || 'unknown';
          cmc[c] = (cmc[c] || 0) + 1;
        }
        const cs = {};
        for (const b of completed){
          const c = mcm[b.moto_id] || 'unknown';
          if (!cs[c]) cs[c] = {
            res: 0,
            rev: 0,
            rd: 0
          };
          cs[c].res++;
          cs[c].rev += b.total_price || 0;
          cs[c].rd += diffDays(b.start_date, b.end_date);
        }
        const cats = Object.entries(cs).map(([cat, d])=>{
          const mc = cmc[cat] || 1;
          return {
            category: cat,
            motorcycle_count: cmc[cat] || 0,
            reservation_count: d.res,
            total_revenue: d.rev,
            revenue_per_moto: Math.round(d.rev / mc),
            avg_utilization: Math.round(d.rd / (mc * pd) * 1000) / 10,
            rented_days: d.rd
          };
        }).sort((a, b)=>b.avg_utilization - a.avg_utilization);
        return {
          categories: cats,
          period_months: pm
        };
      }
    case 'analyze_optimal_fleet':
      {
        const branchId = input.branch_id;
        if (!branchId) return {
          error: 'branch_id je povinný parametr'
        };
        const pm = input.period_months || 6;
        const raw = await fetchAnalyticsRawData(sb, pm);
        const branch = raw.branches.find((b)=>b.id === branchId);
        if (!branch) return {
          error: 'Pobočka nenalezena'
        };
        const fleet = await branchFleetStats(sb, pm, raw.motorcycles);
        const pd = fleet.days;
        const st = fleet.byBranch[branchId];
        const bMotos = raw.motorcycles.filter((m)=>m.branch_id === branchId && !m.is_trailer);
        // Rezervace = pobočka rezervace; sloty/obsazenost = moto-dny kategorie na pobočce; count = AKTUÁLNÍ počet kusů
        const mbm = {}, mcm = {};
        for (const m of raw.motorcycles){
          mbm[m.id] = m.branch_id;
          mcm[m.id] = m.category || 'unknown';
        }
        const completed = raw.bookings.filter((b)=>isRealizedBooking(b) && bookingBranchOf(b, mbm) === branchId);
        const cf = {};
        const cfe = (c)=>cf[c] ||= {
            count: 0,
            rev: 0,
            md: st?.cats[c]?.motoDays || 0,
            rd: st?.cats[c]?.rentedDays || 0
          };
        for (const m of bMotos)cfe(m.category || 'unknown').count++;
        for (const c of Object.keys(st?.cats || {}))cfe(c);
        for (const b of completed)cfe(mcm[b.moto_id] || 'unknown').rev += Number(b.total_price) || 0;
        const minSlots = pd > 0 ? Math.min(MIN_EXPOSURE_DAYS, pd) / pd : 0;
        const perSlot = (rev, md)=>pd > 0 && (md > 0 || rev > 0) ? Math.round(rev / Math.max(md / pd, minSlots)) : 0;
        const current = Object.entries(cf).map(([cat, d])=>({
            category: cat,
            count: d.count,
            avg_fleet: pd > 0 ? Math.round(d.md / pd * 10) / 10 : 0,
            revenue: d.rev,
            utilization_pct: d.md > 0 ? Math.round(d.rd / d.md * 1000) / 10 : 0,
            revenue_per_slot: perSlot(d.rev, d.md)
          }));
        const bt = branch.type || 'turistická';
        const bud = FLEET_CALC.branchUtilization[bt] || FLEET_CALC.branchUtilization['turistická'];
        const scores = [];
        for (const [cat, params] of Object.entries(FLEET_CALC.categoryParams)){
          const uf = bud[cat] || 0.3;
          const ex = cf[cat];
          const ru = ex && ex.md >= MIN_EXPOSURE_DAYS ? ex.rd / ex.md : uf;
          const up = Math.round(ru * 1000) / 10;
          const erps = Math.round(params.avgDailyRate * pd * ru);
          if (up > 40) scores.push({
            category: cat,
            score: erps * ru,
            erps,
            up
          });
        }
        scores.sort((a, b)=>b.score - a.score);
        const ts = scores.reduce((s, c)=>s + c.score, 0);
        let assigned = 0;
        const rec = scores.map((c)=>{
          const slots = Math.max(1, Math.round(ts > 0 ? c.score / ts * 8 : 0));
          assigned += slots;
          return {
            category: c.category,
            slots,
            expected_revenue_per_slot: c.erps,
            utilization_pct: c.up
          };
        });
        while(assigned > 8 && rec.length > 0){
          const mi = rec.reduce((mi, r, i)=>r.slots > 1 && r.expected_revenue_per_slot < (rec[mi]?.expected_revenue_per_slot || Infinity) ? i : mi, 0);
          rec[mi].slots--;
          assigned--;
        }
        while(assigned < 8 && rec.length > 0){
          const mi = rec.reduce((mi, r, i)=>r.expected_revenue_per_slot > (rec[mi]?.expected_revenue_per_slot || 0) ? i : mi, 0);
          rec[mi].slots++;
          assigned++;
        }
        const crps = perSlot(completed.reduce((s, b)=>s + (Number(b.total_price) || 0), 0), st?.motoDays || 0);
        const orps = rec.length > 0 ? Math.round(rec.reduce((s, r)=>s + r.expected_revenue_per_slot * r.slots, 0) / 8) : 0;
        return {
          branch: {
            id: branch.id,
            name: branch.name,
            type: bt
          },
          current,
          recommended: rec,
          potential: {
            current_rev_per_slot: crps,
            optimized_rev_per_slot: orps,
            improvement_pct: crps > 0 ? Math.round((orps / crps - 1) * 1000) / 10 : 0
          },
          period_months: pm,
          method: FLEET_NOTE
        };
      }
    case 'analyze_customers':
      {
        const pm = input.period_months || 12;
        const raw = await fetchAnalyticsRawData(sb, pm);
        const mcm = {};
        for (const m of raw.motorcycles)mcm[m.id] = m.category || 'unknown';
        // Zákaznické metriky zahrnují i výpůjčky JEN VÝBAVY (kategorie 'gear_only')
        const completed = [
          ...raw.bookings,
          ...raw.gearBookings
        ].filter((b)=>isRealizedBooking(b));
        const cs = {};
        for (const b of completed){
          const uid = b.user_id;
          if (!uid) continue;
          if (!cs[uid]) cs[uid] = {
            rev: 0,
            res: 0,
            cats: {},
            srcs: {}
          };
          cs[uid].rev += b.total_price || 0;
          cs[uid].res++;
          const c = b.booking_kind === 'gear' ? 'gear_only' : mcm[b.moto_id] || 'unknown';
          cs[uid].cats[c] = (cs[uid].cats[c] || 0) + 1;
          const src = b.booking_source || 'app';
          cs[uid].srcs[src] = (cs[uid].srcs[src] || 0) + 1;
        }
        let vip = 0, regular = 0, occasional = 0, inactive = 0;
        const top = [];
        for (const p of raw.profiles){
          const s = cs[p.id];
          if (!s || s.res === 0) {
            inactive++;
            continue;
          }
          ;
          if (s.rev >= 20000 || s.res >= 5) vip++;
          else if (s.res >= 2) regular++;
          else occasional++;
          top.push({
            id: p.id,
            name: p.full_name,
            email: p.email,
            city: p.city,
            revenue: s.rev,
            reservations: s.res,
            segment: s.rev >= 20000 || s.res >= 5 ? 'VIP' : s.res >= 2 ? 'Regular' : 'Occasional'
          });
        }
        top.sort((a, b)=>b.revenue - a.revenue);
        const cp = {}, srcS = {}, cityS = {}, licS = {};
        for (const s of Object.values(cs)){
          for (const [c, n] of Object.entries(s.cats))cp[c] = (cp[c] || 0) + n;
          for (const [src, n] of Object.entries(s.srcs))srcS[src] = (srcS[src] || 0) + n;
        }
        for (const p of raw.profiles){
          const city = p.city || 'Neznámé';
          cityS[city] = (cityS[city] || 0) + 1;
          if (Array.isArray(p.license_group)) for (const g of p.license_group)licS[g] = (licS[g] || 0) + 1;
        }
        const totalRev = Object.values(cs).reduce((s, c)=>s + c.rev, 0);
        const tc = raw.profiles.length, ac = tc - inactive;
        return {
          segments: {
            vip,
            regular,
            occasional,
            inactive,
            total: tc
          },
          top_customers: top.slice(0, 20),
          category_preference: Object.entries(cp).map(([c, n])=>({
              category: c,
              booking_count: n
            })).sort((a, b)=>b.booking_count - a.booking_count),
          booking_sources: Object.entries(srcS).map(([s, c])=>({
              source: s,
              count: c
            })),
          city_distribution: Object.entries(cityS).map(([c, n])=>({
              city: c,
              count: n
            })).sort((a, b)=>b.count - a.count).slice(0, 10),
          license_groups: licS,
          kpis: {
            total_customers: tc,
            active_customers: ac,
            total_revenue: totalRev,
            avg_revenue_per_customer: ac > 0 ? Math.round(totalRev / ac) : 0,
            avg_bookings_per_customer: ac > 0 ? Math.round(completed.length / ac * 10) / 10 : 0
          },
          period_months: pm
        };
      }
    case 'forecast_predictions':
      {
        const ma = input.months_ahead || 3;
        const branchId = input.branch_id;
        // Pobočka rezervace = bookings.branch_id (kde převzal), u NULL záloha přes AKTUÁLNÍ motorky pobočky
        let bOr = null;
        if (branchId) {
          const { data: bm } = await sb.from('motorcycles').select('id').eq('branch_id', branchId);
          const mids = (bm || []).map((m)=>m.id);
          bOr = branchBookingsOr(branchId, mids);
        }
        const allB = await fetchAllRows(()=>{
          let q = sb.from('bookings').select('id, moto_id, branch_id, total_price, start_date, end_date, status, payment_status, created_at').neq('status', 'cancelled').in('payment_status', PAID_BOOKING_STATUSES).not('is_test', 'is', true);
          if (bOr) q = q.or(bOr);
          return q.order('created_at', {
            ascending: true
          }).order('id');
        });
        if (!allB || allB.length === 0) return {
          error: 'Nedostatek dat pro predikci',
          available_months: 0
        };
        const md = {};
        for (const b of allB){
          const m = b.created_at.slice(0, 7);
          if (!md[m]) md[m] = {
            rev: 0,
            cnt: 0
          };
          md[m].rev += b.total_price || 0;
          md[m].cnt++;
        }
        const sm = Object.keys(md).sort();
        if (sm.length < 3) return {
          error: 'Nedostatek dat pro predikci (min 3 měsíce)',
          available_months: sm.length
        };
        const hist = sm.map((m)=>({
            month: m,
            revenue: Math.round(md[m].rev),
            booking_count: md[m].cnt
          }));
        const cmr = {};
        for (const m of sm){
          const cm = parseInt(m.split('-')[1]);
          if (!cmr[cm]) cmr[cm] = [];
          cmr[cm].push(md[m].rev);
        }
        const avgMR = sm.reduce((s, m)=>s + md[m].rev, 0) / sm.length;
        const sc = {};
        for(let cm = 1; cm <= 12; cm++){
          const r = cmr[cm];
          sc[cm] = r && r.length > 0 ? r.reduce((s, v)=>s + v, 0) / r.length / (avgMR || 1) : 1;
        }
        const slope = (md[sm[sm.length - 1]].rev - md[sm[0]].rev) / Math.max(1, sm.length - 1);
        const lastRev = md[sm[sm.length - 1]].rev;
        const avgBPR = hist.reduce((s, h)=>s + h.booking_count, 0) / Math.max(1, hist.reduce((s, h)=>s + h.revenue, 0));
        const nd = new Date();
        const preds = [];
        for(let i = 1; i <= ma; i++){
          const fd = new Date(nd.getFullYear(), nd.getMonth() + i, 1);
          const fm = `${fd.getFullYear()}-${String(fd.getMonth() + 1).padStart(2, '0')}`;
          const cm = fd.getMonth() + 1, sf = sc[cm] || 1;
          const pr = Math.max(0, Math.round((lastRev + slope * i) * sf));
          preds.push({
            month: fm,
            predicted_revenue: pr,
            predicted_bookings: Math.round(pr * avgBPR),
            confidence: sm.length > 6 ? 'high' : sm.length >= 3 ? 'medium' : 'low',
            seasonal_factor: Math.round(sf * 100) / 100
          });
        }
        let peakM = 1, lowM = 1, peakV = 0, lowV = Infinity;
        for(let cm = 1; cm <= 12; cm++){
          if (sc[cm] > peakV) {
            peakV = sc[cm];
            peakM = cm;
          }
          ;
          if (sc[cm] < lowV) {
            lowV = sc[cm];
            lowM = cm;
          }
        }
        return {
          historical: hist,
          predictions: preds,
          trend: {
            monthly_growth: Math.round(slope),
            peak_month: peakM,
            low_month: lowM
          },
          data_quality: {
            months_available: sm.length,
            confidence_level: sm.length > 6 ? 'high' : sm.length >= 3 ? 'medium' : 'low'
          }
        };
      }
    default:
      return null;
  }
}
