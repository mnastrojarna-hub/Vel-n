// ─── MotoGo24 Fleet Calculation Constants ───────────────────────────
// Zdroj: kalkulace návratnosti MotoGo24

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

export function calcBikeEconomics(category, branchType, overrideUtilization = null) {
  const cat = (category || '').toLowerCase()
  const params = FLEET_CALC.categoryParams[cat]
  if (!params) return null
  const utilization = overrideUtilization
    ?? FLEET_CALC.branchUtilization[branchType]?.[cat]
    ?? 0.50
  const rentedDays = Math.round(365 * utilization)
  const annualRevenue = rentedDays * params.avgDailyRate
  const servicesCost = params.avgServicePerEvent * params.servicesPerYear
  const marketingCost = annualRevenue * FLEET_CALC.marketingPct
  const totalCosts = servicesCost + params.insuranceCleaningYear + marketingCost + FLEET_CALC.otherFixedPerBike
  const annualProfit = annualRevenue - totalCosts
  const purchasePriceWithMarkup = params.avgPurchasePrice * FLEET_CALC.purchasePriceMarkup
  const roi = purchasePriceWithMarkup > 0 ? annualProfit / purchasePriceWithMarkup : 0
  const paybackMonths = annualProfit > 0 ? (purchasePriceWithMarkup / annualProfit) * 12 : null
  return { category: cat, branchType, utilization, rentedDays, annualRevenue, servicesCost, marketingCost, totalCosts, annualProfit, purchasePriceWithMarkup, roi, paybackMonths }
}

export function calcFleetEconomics(fleet, branchType, realUtilizationMap = null) {
  let totalRevenue = 0, totalProfit = 0, totalInvestment = 0
  const breakdown = []
  for (const { cat, n } of fleet) {
    const realUtil = realUtilizationMap?.[cat] ?? null
    const bike = calcBikeEconomics(cat, branchType, realUtil)
    if (!bike) continue
    breakdown.push({ ...bike, count: n, totalRevenue: bike.annualRevenue * n, totalProfit: bike.annualProfit * n })
    totalRevenue += bike.annualRevenue * n
    totalProfit += bike.annualProfit * n
    totalInvestment += bike.purchasePriceWithMarkup * n
  }
  const totalSlots = fleet.reduce((s, f) => s + f.n, 0)
  const revenuePerSlot = totalSlots > 0 ? totalRevenue / totalSlots : 0
  return { totalRevenue, totalProfit, totalInvestment, revenuePerSlot, breakdown }
}
