// ─── MotoGo24 Fleet Calculation Constants ───────────────────────────
export const FLEET_CALC = {
  purchasePriceMarkup: 1.20,
  marketingPct: 0.15,
  otherFixedPerBike: 3000,
  categoryParams: {
    adventure:  { avgDailyRate: 2100, avgServicePerEvent: 25000, servicesPerYear: 2, insuranceCleaningYear: 13000, avgPurchasePrice: 200000 },
    touring:    { avgDailyRate: 2000, avgServicePerEvent: 20000, servicesPerYear: 2, insuranceCleaningYear: 13000, avgPurchasePrice: 220000 },
    naked:      { avgDailyRate: 1600, avgServicePerEvent: 20000, servicesPerYear: 3, insuranceCleaningYear: 13000, avgPurchasePrice: 165000 },
    sport:      { avgDailyRate: 1700, avgServicePerEvent: 20000, servicesPerYear: 3, insuranceCleaningYear: 13000, avgPurchasePrice: 175000 },
    sportovni:  { avgDailyRate: 1700, avgServicePerEvent: 20000, servicesPerYear: 3, insuranceCleaningYear: 13000, avgPurchasePrice: 175000 },
    retro:      { avgDailyRate: 1400, avgServicePerEvent: 10000, servicesPerYear: 3, insuranceCleaningYear: 13000, avgPurchasePrice: 110000 },
    A2:         { avgDailyRate: 1100, avgServicePerEvent: 10000, servicesPerYear: 2, insuranceCleaningYear: 7000,  avgPurchasePrice: 50000 },
    detske:     { avgDailyRate: 800,  avgServicePerEvent: 8000,  servicesPerYear: 2, insuranceCleaningYear: 5000,  avgPurchasePrice: 30000 },
    enduro:     { avgDailyRate: 1800, avgServicePerEvent: 15000, servicesPerYear: 3, insuranceCleaningYear: 13000, avgPurchasePrice: 180000 },
    cestovni:   { avgDailyRate: 2000, avgServicePerEvent: 20000, servicesPerYear: 2, insuranceCleaningYear: 13000, avgPurchasePrice: 220000 },
    chopper:    { avgDailyRate: 1500, avgServicePerEvent: 18000, servicesPerYear: 2, insuranceCleaningYear: 13000, avgPurchasePrice: 190000 },
  },
  branchUtilization: {
    turistická:        { adventure: 0.82, touring: 0.76, naked: 0.45, sport: 0.40, retro: 0.55, A2: 0.35, enduro: 0.70, cestovni: 0.76, sportovni: 0.40, chopper: 0.50, detske: 0.30 },
    horská:            { adventure: 0.78, touring: 0.60, naked: 0.35, sport: 0.30, retro: 0.30, A2: 0.25, enduro: 0.80, cestovni: 0.60, sportovni: 0.30, chopper: 0.25, detske: 0.20 },
    'rekreační voda':  { adventure: 0.72, touring: 0.68, naked: 0.55, sport: 0.38, retro: 0.65, A2: 0.40, enduro: 0.50, cestovni: 0.68, sportovni: 0.38, chopper: 0.55, detske: 0.35 },
    centrum:           { adventure: 0.40, touring: 0.50, naked: 0.72, sport: 0.55, retro: 0.60, A2: 0.68, enduro: 0.25, cestovni: 0.50, sportovni: 0.55, chopper: 0.50, detske: 0.45 },
    'předměstí':       { adventure: 0.48, touring: 0.52, naked: 0.68, sport: 0.52, retro: 0.55, A2: 0.65, enduro: 0.30, cestovni: 0.52, sportovni: 0.52, chopper: 0.45, detske: 0.40 },
    'letiště':         { adventure: 0.55, touring: 0.65, naked: 0.60, sport: 0.45, retro: 0.50, A2: 0.50, enduro: 0.30, cestovni: 0.65, sportovni: 0.45, chopper: 0.45, detske: 0.25 },
  },
  defaultFleet: {
    turistická:        [{ cat: 'adventure', n: 4 }, { cat: 'touring', n: 2 }, { cat: 'naked', n: 1 }, { cat: 'sport', n: 1 }],
    horská:            [{ cat: 'adventure', n: 4 }, { cat: 'enduro', n: 2 }, { cat: 'touring', n: 1 }, { cat: 'sport', n: 1 }],
    'rekreační voda':  [{ cat: 'adventure', n: 3 }, { cat: 'touring', n: 2 }, { cat: 'naked', n: 2 }, { cat: 'retro', n: 1 }],
    centrum:           [{ cat: 'naked', n: 3 }, { cat: 'A2', n: 2 }, { cat: 'sport', n: 2 }, { cat: 'touring', n: 1 }],
    'předměstí':       [{ cat: 'naked', n: 3 }, { cat: 'A2', n: 2 }, { cat: 'sport', n: 2 }, { cat: 'adventure', n: 1 }],
    'letiště':         [{ cat: 'touring', n: 3 }, { cat: 'adventure', n: 2 }, { cat: 'naked', n: 2 }, { cat: 'sport', n: 1 }],
  },
}

// Real data — ekonomika jedné motorky z DB bookings
export function calcBikeEconomicsReal(moto, motoBookings) {
  if (!motoBookings || motoBookings.length === 0) return null
  let totalRentedDays = 0, totalRevenue = 0
  for (const bk of motoBookings) {
    const days = Math.max(1, Math.round((new Date(bk.end_date) - new Date(bk.start_date)) / 86400000))
    totalRentedDays += days
    totalRevenue += Number(bk.total_price) > 0 ? Number(bk.total_price) : 0
  }
  const utilization = Math.min(totalRentedDays / 365, 1)
  const cat = (moto.category || 'naked').toLowerCase()
  const params = FLEET_CALC.categoryParams[cat] ?? FLEET_CALC.categoryParams['naked']
  const servicesCost = params.avgServicePerEvent * params.servicesPerYear
  const marketingCost = totalRevenue * FLEET_CALC.marketingPct
  const totalCosts = servicesCost + params.insuranceCleaningYear + marketingCost + FLEET_CALC.otherFixedPerBike
  const annualProfit = totalRevenue - totalCosts
  const pp = ((Number(moto.purchase_price) || 0) > 0 ? Number(moto.purchase_price) : params.avgPurchasePrice) * FLEET_CALC.purchasePriceMarkup
  const roi = pp > 0 ? annualProfit / pp : 0
  const paybackMonths = annualProfit > 0 ? (pp / annualProfit) * 12 : null
  return { source: 'real', category: cat, utilization, rentedDays: totalRentedDays, annualRevenue: totalRevenue, totalCosts, annualProfit, purchasePrice: pp, roi, paybackMonths, count: 1 }
}

// Benchmark — ekonomika z konstant (žádná real data)
export function calcBikeEconomicsBenchmark(category, branchType, realUtilOverride = null) {
  const cat = (category || 'naked').toLowerCase()
  const params = FLEET_CALC.categoryParams[cat] ?? FLEET_CALC.categoryParams['naked']
  const utilization = realUtilOverride ?? FLEET_CALC.branchUtilization[branchType]?.[cat] ?? 0.50
  const rentedDays = Math.round(365 * utilization)
  const annualRevenue = rentedDays * params.avgDailyRate
  const servicesCost = params.avgServicePerEvent * params.servicesPerYear
  const marketingCost = annualRevenue * FLEET_CALC.marketingPct
  const totalCosts = servicesCost + params.insuranceCleaningYear + marketingCost + FLEET_CALC.otherFixedPerBike
  const annualProfit = annualRevenue - totalCosts
  const pp = params.avgPurchasePrice * FLEET_CALC.purchasePriceMarkup
  const roi = pp > 0 ? annualProfit / pp : 0
  const paybackMonths = annualProfit > 0 ? (pp / annualProfit) * 12 : null
  return { source: realUtilOverride != null ? 'derived' : 'benchmark', category: cat, utilization, rentedDays, annualRevenue, totalCosts, annualProfit, purchasePrice: pp, roi, paybackMonths, count: 1 }
}

// Ekonomika celé pobočky/lokality
// locMotos = motorky z DB, completedBookings = bookings status=completed
// fleetDef = [{ cat, n }] pro novou doporučenou lokaci (null = real pobočka)
// realUtilByType = { branchType: { cat: utilization } } z real dat jiných poboček
export function calcLocationEconomics(locMotos, completedBookings, branchType, fleetDef = null, realUtilByType = null) {
  const results = []
  let hasRealData = false

  if (!fleetDef && locMotos.length > 0) {
    // REAL pobočka — použij skutečné bookings
    for (const moto of locMotos) {
      const mb = completedBookings.filter(b => b.moto_id === moto.id)
      if (mb.length > 0) {
        const r = calcBikeEconomicsReal(moto, mb)
        if (r) { results.push(r); hasRealData = true }
      }
    }
  }

  if (!hasRealData) {
    // BENCHMARK / DERIVED — nová lokace nebo pobočka bez dat
    const bt = branchType || 'turistická'
    const fleet = fleetDef || locMotos.map(m => ({ cat: (m.category || 'naked').toLowerCase(), n: 1 }))
    const fleetMap = {}
    for (const f of fleet) { const c = (f.cat || 'naked').toLowerCase(); fleetMap[c] = (fleetMap[c] || 0) + (f.n || 1) }
    const realUtilForType = realUtilByType?.[bt]
    const hasDerivation = realUtilForType && Object.keys(realUtilForType).length > 0
    for (const [cat, count] of Object.entries(fleetMap)) {
      const override = hasDerivation ? (realUtilForType[cat] ?? null) : null
      const r = calcBikeEconomicsBenchmark(cat, bt, override)
      if (r) results.push({ ...r, count, source: override != null ? 'derived' : 'benchmark' })
    }
  }

  const totalRevenue = results.reduce((s, b) => s + b.annualRevenue * (b.count || 1), 0)
  const totalProfit = results.reduce((s, b) => s + b.annualProfit * (b.count || 1), 0)
  const totalInvestment = results.reduce((s, b) => s + b.purchasePrice * (b.count || 1), 0)
  const totalSlots = results.reduce((s, b) => s + (b.count || 1), 0)
  const revenuePerSlot = totalSlots > 0 ? totalRevenue / totalSlots : 0
  const paybackMonths = totalProfit > 0 ? (totalInvestment / totalProfit) * 12 : null
  const avgUtilization = totalSlots > 0 ? results.reduce((s, b) => s + b.utilization * (b.count || 1), 0) / totalSlots : 0
  const dataSource = hasRealData ? 'real' : (results.some(r => r.source === 'derived') ? 'derived' : 'benchmark')
  return { dataSource, hasRealData, totalRevenue, totalProfit, totalInvestment, revenuePerSlot, paybackMonths, avgUtilization, breakdown: results }
}
