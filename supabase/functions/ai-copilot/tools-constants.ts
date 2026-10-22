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

// Sjednocená definice „realizované" rezervace (= obrat) dle velin/src/lib/revenueUtils.js:
// zaplaceno (vč. částečných refundů), není storno, není testovací.
export const PAID_BOOKING_STATUSES = ['paid', 'partial_refund', 'refund_pending', 'refunded']
// deno-lint-ignore no-explicit-any
export function isRealizedBooking(b: Record<string, any>): boolean {
  return !!b && b.status !== 'cancelled' && b.is_test !== true && PAID_BOOKING_STATUSES.includes(b.payment_status)
}

// Pobočka rezervace = bookings.branch_id (kde zákazník převzal; DB triggery 20261010b — do vyzvednutí jde
// s motorkou, pak zmrazená). U NULL (před doběhnutím migrace) záloha na AKTUÁLNÍ pobočku motorky.
// deno-lint-ignore no-explicit-any
export function bookingBranchOf(b: Record<string, any>, motoBranchMap: Record<string, any>): string | null {
  return b?.branch_id || motoBranchMap[b?.moto_id] || null
}
// .or() filtr „rezervace pobočky“ se zálohou přes motorky pobočky (moto_id IN) u NULL branch_id
export function branchBookingsOr(branchId: string, motoIds: string[]): string {
  const nil = '00000000-0000-0000-0000-000000000000'
  const bid = /^[0-9a-f-]{36}$/i.test(String(branchId)) ? branchId : nil   // vstup od AI → jen UUID do filtru
  const ids = motoIds.length ? motoIds.join(',') : nil
  return `branch_id.eq.${bid},and(branch_id.is.null,moto_id.in.(${ids}))`
}

/** Všechny řádky (PostgREST vrací max. 1000 na dotaz — dřív se analýzy tiše uřízly); makeQuery = () => builder s .order(). */
// deno-lint-ignore no-explicit-any
export async function fetchAllRows(makeQuery: () => any, pageSize = 1000): Promise<Record<string, any>[]> {
  // deno-lint-ignore no-explicit-any
  const out: Record<string, any>[] = []
  for (let from = 0; ; from += pageSize) {
    const { data, error } = await makeQuery().range(from, from + pageSize - 1)
    if (error) throw new Error(error.message)
    for (const r of data || []) out.push(r)
    if (!data || data.length < pageSize) return out
  }
}

// `bookings` = rezervace MOTOREK (analýzy flotily, kategorií, motorek); výpůjčky JEN VÝBAVY
// (booking_kind='gear', 2026-10-23) zvlášť v `gearBookings` — do moto analýz nepatří, do obratu ano.
export async function fetchAnalyticsRawData(sb: SB, months: number) {
  const since = new Date()
  since.setMonth(since.getMonth() - months)
  const [allBookings, mRes, lRes, profiles] = await Promise.all([
    fetchAllRows(() => sb.from('bookings').select('id, user_id, moto_id, branch_id, start_date, end_date, total_price, status, created_at, booking_source, rating, payment_status, is_test, booking_kind').gte('created_at', since.toISOString()).not('is_test', 'is', true).order('id')),
    sb.from('motorcycles').select('id, model, brand, category, branch_id, status, purchase_price, mileage, acquired_at, created_at, is_trailer'),
    sb.from('branches').select('id, name, city, type'),
    fetchAllRows(() => sb.from('profiles').select('id, full_name, email, city, license_group, riding_experience, created_at, is_test_account').not('is_test_account', 'is', true).order('id')),
  ])
  // deno-lint-ignore no-explicit-any
  type Row = Record<string, any>
  const bookings = allBookings.filter((b) => b.booking_kind !== 'gear')
  const gearBookings = allBookings.filter((b) => b.booking_kind === 'gear')
  return { bookings, gearBookings, motorcycles: (mRes.data || []) as Row[], branches: (lRes.data || []) as Row[], profiles }
}

export function diffDays(start: string, end: string): number {
  return Math.max(1, Math.round((new Date(end).getTime() - new Date(start).getTime()) / 86400000))
}
