// Flotila pobočky V ČASE („moto-dny“) — port velin/src/lib/branchFleet.js (držet shodné!).
// Den pronájmu → pobočka REZERVACE; jinak zalogované přesuny (admin_audit_log 'motorcycle_migrated',
// moto_odometer_readings 'transfer') a dnes aktuální pobočka motorky. Mezi body se stejnou pobočkou = ta
// pobočka; při neshodě (nezalogovaný přesun) předchozí pobočka, od MOVES_LOGGED_SINCE už ta další (od té doby
// je každý přesun na pobočku zalogovaný přes RPC admin_move_motorcycle(s)). Přesun dnes = nečinné dny
// na nové pobočce až od dneška. Vozíky se nepočítají, vyřazená motorka jen do posledního záznamu.
import { FLEET_CALC, isRealizedBooking, bookingBranchOf, fetchAllRows } from './tools-constants.ts';
const DAY = 86400000;
export const MOVES_LOGGED_SINCE = '2026-09-30';
export const MIN_EXPOSURE_DAYS = 30;
const PRAGUE = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Europe/Prague',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit'
});
/** Kalendářní den v Praze jako celé číslo ('YYYY-MM-DD' = ten den). */ export function dayNum(x) {
  if (x == null || x === '') return null;
  const s = typeof x === 'string' && x.length <= 10 ? x : (()=>{
    const d = x instanceof Date ? x : new Date(String(x));
    return isNaN(d.getTime()) ? null : PRAGUE.format(d);
  })();
  if (!s) return null;
  const [y, m, d] = s.split('-').map(Number);
  return Math.round(Date.UTC(y, m - 1, d) / DAY);
}
export async function loadMotoMoves(sb) {
  try {
    const [audit, odo] = await Promise.all([
      fetchAllRows(()=>sb.from('admin_audit_log').select('entity_id, created_at, old_data, new_data').eq('action', 'motorcycle_migrated').order('created_at').order('id')),
      fetchAllRows(()=>sb.from('moto_odometer_readings').select('moto_id, recorded_at, branch_id, to_branch_id').eq('kind', 'transfer').order('recorded_at').order('id'))
    ]);
    const seen = new Set(), out = [];
    const add = (moto_id, at, from, to)=>{
      const k = `${moto_id}|${dayNum(at)}|${from}|${to}`;
      if (!moto_id || !at || from === to || seen.has(k)) return;
      seen.add(k);
      out.push({
        moto_id,
        at,
        from: from || null,
        to: to || null
      });
    };
    for (const a of audit)if (a.new_data && 'branch_id' in a.new_data) add(a.entity_id, a.created_at, a.old_data?.branch_id ?? null, a.new_data.branch_id);
    for (const r of odo)add(r.moto_id, r.recorded_at, r.branch_id, r.to_branch_id);
    return out;
  } catch (_) {
    return [];
  }
}
function isAnchor(b) {
  return !!b && b.is_test !== true && b.status !== 'cancelled' && (b.status !== 'pending' || isRealizedBooking(b));
}
const upper = (keys, x)=>{
  let lo = 0, hi = keys.length;
  while(lo < hi){
    const m = lo + hi >> 1;
    if (keys[m] <= x) lo = m + 1;
    else hi = m;
  }
  return lo;
};
export function buildFleetTimeline(o) {
  const today = o.today ?? dayNum(new Date());
  const mbm = Object.fromEntries(o.motorcycles.map((m)=>[
      m.id,
      m.branch_id
    ]));
  const logDay = dayNum(MOVES_LOGGED_SINCE);
  const byMoto = {};
  const ev = (id)=>byMoto[id] ||= {
      a: [],
      m: []
    };
  for (const b of o.bookings){
    if (!isAnchor(b)) continue;
    const s = dayNum(b.start_date), e0 = dayNum(b.end_date);
    if (s == null) continue;
    const e = Math.max(s, e0 ?? s), rented = isRealizedBooking(b);
    if (b.moto_id) ev(b.moto_id).a.push({
      s,
      e,
      loc: bookingBranchOf(b, mbm),
      rented,
      price: rented ? Number(b.total_price) || 0 : 0
    });
    if (b.trailer_moto_id) ev(b.trailer_moto_id).a.push({
      s,
      e,
      loc: b.branch_id || mbm[b.trailer_moto_id] || null,
      rented: false,
      price: 0
    });
  }
  for (const mv of o.moves)if (mv.moto_id in mbm) ev(mv.moto_id).m.push({
    d: dayNum(mv.at),
    from: mv.from,
    to: mv.to
  });
  const out = [];
  for (const moto of o.motorcycles){
    if (moto.is_trailer) continue;
    const E = byMoto[moto.id] || {
      a: [],
      m: []
    };
    const A = E.a.slice().sort((x, y)=>x.s - y.s), M = E.m.filter((x)=>x.d != null).sort((x, y)=>x.d - y.d);
    const firsts = [
      ...A.map((x)=>x.s),
      ...M.map((x)=>x.d)
    ], lasts = [
      ...A.map((x)=>x.e),
      ...M.map((x)=>x.d)
    ];
    const acq = dayNum(moto.acquired_at) ?? dayNum(moto.created_at);
    let pStart = Math.min(acq ?? Infinity, ...firsts);
    if (!isFinite(pStart)) pStart = o.fromDay;
    const pEnd = moto.status === 'retired' ? lasts.length ? Math.max(...lasts) : -Infinity : Infinity;
    const a = Math.max(o.fromDay, pStart), z = Math.min(o.toDay, pEnd);
    if (!(a <= z)) continue;
    const n = z - a + 1, loc = new Array(n).fill(undefined), rented = new Uint8Array(n), revByBranch = {};
    for (const x of A){
      const len = x.e - x.s + 1;
      for(let d = Math.max(x.s, a); d <= Math.min(x.e, z); d++){
        loc[d - a] = x.loc;
        if (x.rented) {
          rented[d - a] = 1;
          if (x.loc) revByBranch[x.loc] = (revByBranch[x.loc] || 0) + x.price / len;
        }
      }
    }
    const ends = A.slice().sort((x, y)=>x.e - y.e), endK = ends.map((x)=>x.e), startK = A.map((x)=>x.s), moveK = M.map((x)=>x.d);
    const cur = moto.branch_id || null;
    for(let i = 0; i < n; i++){
      if (loc[i] !== undefined) continue;
      const d = a + i;
      let prev = null, next = null;
      const pe = upper(endK, d - 1) - 1;
      if (pe >= 0) prev = {
        at: endK[pe],
        loc: ends[pe].loc,
        r: 0
      };
      const pm = upper(moveK, d) - 1;
      if (pm >= 0 && (!prev || M[pm].d >= prev.at)) prev = {
        at: M[pm].d,
        loc: M[pm].to,
        r: 2
      };
      if (today <= d && (!prev || today > prev.at || today === prev.at && prev.r < 1)) prev = {
        at: today,
        loc: cur,
        r: 1
      };
      const ns = upper(startK, d);
      if (ns < A.length) next = {
        at: A[ns].s,
        loc: A[ns].loc
      };
      const nm = upper(moveK, d);
      if (nm < M.length && (!next || M[nm].d <= next.at)) next = {
        at: M[nm].d,
        loc: M[nm].from
      };
      if (today > d && (!next || today < next.at)) next = {
        at: today,
        loc: cur
      };
      loc[i] = !prev ? next?.loc ?? cur : !next ? prev.loc : prev.loc === next.loc ? prev.loc : d >= logDay ? next.loc : prev.loc;
    }
    out.push({
      moto,
      start: a,
      loc,
      rented,
      revByBranch
    });
  }
  return {
    fromDay: o.fromDay,
    toDay: o.toDay,
    motos: out
  };
}
export function summarizeByBranch(tl, catOf = (m)=>String(m.category || 'unknown')) {
  const out = {};
  const get = (b)=>out[b] ||= {
      motoDays: 0,
      rentedDays: 0,
      revenue: 0,
      perMoto: {},
      cats: {}
    };
  const cget = (s, c)=>s.cats[c] ||= {
      motoDays: 0,
      rentedDays: 0,
      revenue: 0
    };
  for (const t of tl.motos){
    const cat = catOf(t.moto);
    for(let i = 0; i < t.loc.length; i++){
      const b = t.loc[i];
      if (!b) continue;
      const s = get(b), c = cget(s, cat);
      s.motoDays++;
      c.motoDays++;
      s.perMoto[t.moto.id] = (s.perMoto[t.moto.id] || 0) + 1;
      if (t.rented[i]) {
        s.rentedDays++;
        c.rentedDays++;
      }
    }
    for (const [b, v] of Object.entries(t.revByBranch)){
      const s = get(b);
      s.revenue += v;
      cget(s, cat).revenue += v;
    }
  }
  return out;
}
/** Fixní roční náklady motorky (servis + pojištění/čištění + ostatní) — jako Velín calcBikeEconomicsIdle. */ export function fixedAnnualCost(moto) {
  const p = FLEET_CALC.categoryParams[String(moto?.category || 'naked').toLowerCase()] || FLEET_CALC.categoryParams['naked'];
  return p.avgServicePerEvent * p.servicesPerYear + p.insuranceCleaningYear + FLEET_CALC.otherFixedPerBike;
}
/** Roční projekce zisku na motorku: (tržba v okně × (1 − marketing) − fixní náklady poměrně dle dnů) × 365 / moto-dny. */ export function profitPerMotoYear(stat, motosById) {
  if (!stat || stat.motoDays < MIN_EXPOSURE_DAYS) return null;
  let fixed = 0;
  for (const [id, days] of Object.entries(stat.perMoto))fixed += fixedAnnualCost(motosById[id]) * days / 365;
  return (stat.revenue * (1 - FLEET_CALC.marketingPct) - fixed) * 365 / stat.motoDays;
}
/** Okno posledních `months` měsíců končící dnes + souhrn po pobočkách (rezervace jako kotvy = všechny, ne jen v okně). */ export async function branchFleetStats(sb, months, motorcycles) {
  const since = new Date();
  since.setMonth(since.getMonth() - months);
  const today = dayNum(new Date()), fromDay = dayNum(since);
  const [anchors, moves] = await Promise.all([
    fetchAllRows(()=>sb.from('bookings').select('id, moto_id, trailer_moto_id, branch_id, start_date, end_date, total_price, status, payment_status, is_test').not('is_test', 'is', true).neq('status', 'cancelled').order('id')),
    loadMotoMoves(sb)
  ]);
  const tl = buildFleetTimeline({
    motorcycles,
    bookings: anchors,
    moves,
    fromDay,
    toDay: today,
    today
  });
  return {
    days: today - fromDay + 1,
    byBranch: summarizeByBranch(tl)
  };
}
