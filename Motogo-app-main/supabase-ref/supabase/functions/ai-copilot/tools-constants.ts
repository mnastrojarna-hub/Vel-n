// Shared constants and helpers for AI Copilot tools
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

export type SB = ReturnType<typeof createClient>

export const FLEET_CALC = {
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

export async function fetchAnalyticsRawData(sb: SB, months: number) {
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

export function diffDays(start: string, end: string): number {
  return Math.max(1, Math.round((new Date(end).getTime() - new Date(start).getTime()) / 86400000))
}
