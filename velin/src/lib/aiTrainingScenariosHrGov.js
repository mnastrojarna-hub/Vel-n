// Training Part 2b — HR, Analytics, Government (real cross-checks)
import * as API from './aiTrainingHelpers'
import { supabase } from './supabase'

// === HR AGENT — zákonnost směn, pokrytí, nemoc, dovolená, přesčasy ===
export async function trainHrAgent(onStep) {
  const results = []

  // 1. Fetch zaměstnanci — ověř že existují a mají kompletní data
  onStep?.({ agent: 'hr', action: 'Kontrola zaměstnanců', i: 0, total: 12 })
  const { data: emps, error } = await supabase.from('acc_employees')
    .select('id, name, hourly_rate, position, active, phone, email')
    .eq('active', true).limit(20)
  results.push({ agent: 'hr', action: 'fetch_employees', ok: !error, count: emps?.length || 0 })
  // Kontrola kompletnosti profilu zaměstnanců
  for (const emp of (emps || []).slice(0, 5)) {
    const complete = !!(emp.name && emp.hourly_rate > 0 && emp.phone)
    results.push({ agent: 'hr', action: 'verify_employee_profile', ok: complete, name: emp.name, missingRate: !emp.hourly_rate, missingPhone: !emp.phone })
  }

  // 2. Směny — ověř 11h odpočinek mezi směnami
  onStep?.({ agent: 'hr', action: 'Kontrola směn — odpočinek', i: 1, total: 12 })
  const { data: shifts } = await supabase.from('emp_shifts')
    .select('id, employee_id, shift_date, start_time, end_time')
    .order('shift_date', { ascending: false }).limit(20)
  results.push({ agent: 'hr', action: 'fetch_shifts', ok: true, count: shifts?.length || 0 })
  // Kontrola mezer mezi směnami (11h odpočinek)
  if (shifts?.length >= 2) {
    const byEmployee = {}
    shifts.forEach(s => { (byEmployee[s.employee_id] = byEmployee[s.employee_id] || []).push(s) })
    for (const [empId, empShifts] of Object.entries(byEmployee)) {
      const sorted = empShifts.sort((a, b) => a.shift_date?.localeCompare(b.shift_date))
      for (let i = 1; i < sorted.length; i++) {
        const prev = sorted[i - 1], curr = sorted[i]
        if (prev.shift_date === curr.shift_date) continue // same day, skip
        // Simplistic check: consecutive days = could violate 11h rest
        const d1 = new Date(prev.shift_date), d2 = new Date(curr.shift_date)
        const dayDiff = (d2 - d1) / 86400000
        if (dayDiff === 1) {
          results.push({ agent: 'hr', action: 'check_11h_rest', ok: true, empId, detail: `${prev.shift_date}→${curr.shift_date}: po sobě jdoucí dny — ověřit časy` })
        }
      }
    }
  }

  // 3. Docházka — ověř že existují záznamy
  onStep?.({ agent: 'hr', action: 'Kontrola docházky', i: 3, total: 12 })
  const { data: att, error: ae } = await supabase.from('emp_attendance')
    .select('id, employee_id, date, check_in, check_out')
    .order('date', { ascending: false }).limit(20)
  results.push({ agent: 'hr', action: 'fetch_attendance', ok: !ae, count: att?.length || 0 })
  // Detekce chybějících check-out
  const missingCheckout = (att || []).filter(a => a.check_in && !a.check_out)
  if (missingCheckout.length) {
    results.push({ agent: 'hr', action: 'alert_missing_checkout', ok: false, count: missingCheckout.length })
  }

  // 4. Dovolené — kontrola schválení a pokrytí
  onStep?.({ agent: 'hr', action: 'Kontrola dovolených', i: 5, total: 12 })
  const { data: vac } = await supabase.from('emp_vacations')
    .select('id, employee_id, start_date, end_date, status, type')
    .order('start_date', { ascending: false }).limit(20)
  results.push({ agent: 'hr', action: 'fetch_vacations', ok: true, count: vac?.length || 0 })
  const pendingVac = (vac || []).filter(v => v.status === 'pending')
  if (pendingVac.length) {
    results.push({ agent: 'hr', action: 'alert_pending_vacations', ok: true, count: pendingVac.length })
  }

  // 5. Cross-check: zaměstnanec na dovolené ale má přiřazené směny
  onStep?.({ agent: 'hr', action: 'Cross-check dovolená vs směny', i: 7, total: 12 })
  for (const v of (vac || []).filter(v => v.status === 'approved').slice(0, 3)) {
    const { data: conflictShifts } = await supabase.from('emp_shifts')
      .select('id').eq('employee_id', v.employee_id)
      .gte('shift_date', v.start_date).lte('shift_date', v.end_date)
    if (conflictShifts?.length) {
      results.push({ agent: 'hr', action: 'inconsistency_vacation_vs_shift', ok: false, empId: v.employee_id, conflictCount: conflictShifts.length })
    } else {
      results.push({ agent: 'hr', action: 'vacation_shift_ok', ok: true, empId: v.employee_id })
    }
  }

  // 6. Přesčasy — kontrola > 40h/týden (zjednodušeně počet směn/týden)
  onStep?.({ agent: 'hr', action: 'Kontrola přesčasů', i: 9, total: 12 })
  if (emps?.length && shifts?.length) {
    const thisWeekShifts = shifts.filter(s => {
      const d = new Date(s.shift_date)
      const now = new Date()
      return (now - d) / 86400000 < 7
    })
    const byEmp = {}
    thisWeekShifts.forEach(s => { byEmp[s.employee_id] = (byEmp[s.employee_id] || 0) + 1 })
    for (const [empId, count] of Object.entries(byEmp)) {
      if (count > 5) results.push({ agent: 'hr', action: 'alert_overtime', ok: false, empId, shiftsThisWeek: count })
      else results.push({ agent: 'hr', action: 'check_overtime_ok', ok: true, empId, shiftsThisWeek: count })
    }
  }

  // 7. Dokumenty zaměstnanců
  onStep?.({ agent: 'hr', action: 'Kontrola dokumentů', i: 11, total: 12 })
  const { data: empDocs } = await supabase.from('emp_documents').select('id, employee_id, type').limit(20)
  results.push({ agent: 'hr', action: 'fetch_employee_docs', ok: true, count: empDocs?.length || 0 })

  return results
}

// === ANALYTICS AGENT — trendy, anomálie, obsazenost, segmentace ===
export async function trainAnalyticsAgent(onStep) {
  const results = []
  const motos = await API.fetchAvailableMotos()
  results.push({ agent: 'analytics', action: 'fetch_fleet', ok: motos.ok, count: motos.data?.length || 0 })

  // 1. Booking statistiky — aktivní vs completed vs cancelled
  onStep?.({ agent: 'analytics', action: 'Booking statistiky', i: 0, total: 12 })
  for (const status of ['reserved', 'active', 'completed', 'cancelled']) {
    const { count } = await supabase.from('bookings').select('id', { count: 'exact', head: true }).eq('status', status)
    results.push({ agent: 'analytics', action: `count_bookings_${status}`, ok: true, count: count || 0 })
  }

  // 2. Zákaznická segmentace — aktivní vs neaktivní
  onStep?.({ agent: 'analytics', action: 'Zákaznická segmentace', i: 2, total: 12 })
  const { count: totalCustomers } = await supabase.from('profiles').select('id', { count: 'exact', head: true })
  const { count: blockedCustomers } = await supabase.from('profiles').select('id', { count: 'exact', head: true }).eq('is_blocked', true)
  results.push({ agent: 'analytics', action: 'customer_segmentation', ok: true, total: totalCustomers || 0, blocked: blockedCustomers || 0 })

  // 3. SOS analýza — per typ
  onStep?.({ agent: 'analytics', action: 'SOS analýza per typ', i: 4, total: 12 })
  const { data: sosAll } = await supabase.from('sos_incidents').select('type, status').limit(100)
  const sosByType = {}
  ;(sosAll || []).forEach(s => { sosByType[s.type] = (sosByType[s.type] || 0) + 1 })
  results.push({ agent: 'analytics', action: 'sos_by_type', ok: true, distribution: sosByType })

  // 4. Cenová analýza — porovnání cen mezi motorkami
  onStep?.({ agent: 'analytics', action: 'Cenová analýza', i: 5, total: 12 })
  const prices = []
  for (let i = 0; i < Math.min(5, motos.data?.length || 0); i++) {
    const moto = motos.data[i]
    const p = await API.calcBookingPrice(moto.id, API.futureDate(1), API.futureDate(4))
    if (p.ok) prices.push({ model: moto.model, price3d: p.price })
  }
  const avgPrice = prices.length ? prices.reduce((s, p) => s + p.price3d, 0) / prices.length : 0
  results.push({ agent: 'analytics', action: 'price_analysis', ok: true, avgPrice3d: Math.round(avgPrice), motos: prices.length })

  // 5. Pobočky — obsazenost
  onStep?.({ agent: 'analytics', action: 'Pobočky obsazenost', i: 7, total: 12 })
  const { data: branches } = await supabase.from('branches').select('id, name, city, is_open').limit(10)
  for (const br of (branches || [])) {
    const { count: motoCount } = await supabase.from('motorcycles').select('id', { count: 'exact', head: true }).eq('branch_id', br.id).eq('status', 'active')
    const { count: bookingCount } = await supabase.from('bookings').select('id', { count: 'exact', head: true })
      .eq('status', 'active')
    results.push({ agent: 'analytics', action: 'branch_occupancy', ok: true, branch: br.name, motos: motoCount || 0, activeBookings: bookingCount || 0 })
  }

  // 6. Detekce anomálií — motorky bez ceny, zákazníci bez bookingu
  onStep?.({ agent: 'analytics', action: 'Detekce anomálií', i: 9, total: 12 })
  const { data: noPriceMotos } = await supabase.from('motorcycles')
    .select('id, model').eq('status', 'active').is('price_weekday', null).limit(5)
  if (noPriceMotos?.length) {
    results.push({ agent: 'analytics', action: 'anomaly_no_price', ok: false, count: noPriceMotos.length })
  }

  // 7. Hodnocení analýza
  onStep?.({ agent: 'analytics', action: 'Hodnocení zákazníků', i: 11, total: 12 })
  const { data: ratings } = await supabase.from('bookings').select('rating').not('rating', 'is', null).limit(100)
  if (ratings?.length) {
    const avg = ratings.reduce((s, r) => s + r.rating, 0) / ratings.length
    results.push({ agent: 'analytics', action: 'rating_analysis', ok: true, avgRating: Math.round(avg * 10) / 10, count: ratings.length })
  } else {
    results.push({ agent: 'analytics', action: 'rating_analysis', ok: true, avgRating: 0, count: 0 })
  }

  return results
}

// === GOVERNMENT AGENT — STK, pojistky, daňové termíny ===
export async function trainGovernmentAgent(onStep) {
  const results = []
  const motos = await API.fetchAvailableMotos()
  if (!motos.ok) return [{ ok: false, error: 'Žádné motorky' }]

  // 1. STK kontrola — detailní (dny do expirace)
  for (let i = 0; i < Math.min(5, motos.data.length); i++) {
    const moto = motos.data[i]
    onStep?.({ agent: 'government', action: `STK ${moto.model}`, i, total: 10 })
    const { data: detail } = await supabase.from('motorcycles')
      .select('id, model, stk_valid_until, status, spz, vin').eq('id', moto.id).single()
    if (detail?.stk_valid_until) {
      const daysLeft = Math.floor((new Date(detail.stk_valid_until) - new Date()) / 86400000)
      const severity = daysLeft < 0 ? 'expired' : daysLeft < 14 ? 'critical' : daysLeft < 30 ? 'warning' : 'ok'
      results.push({ agent: 'government', action: 'check_stk', ok: severity === 'ok', severity, daysLeft, moto: detail.model, spz: detail.spz })
      if (severity !== 'ok') results.push({ agent: 'government', action: `alert_stk_${severity}`, ok: false, moto: detail.model, daysLeft })
    } else {
      results.push({ agent: 'government', action: 'alert_stk_missing', ok: false, moto: detail?.model })
    }
  }

  // 2. Cross-check: motorka s expirovanou STK ale status active
  onStep?.({ agent: 'government', action: 'Cross-check STK vs status', i: 5, total: 10 })
  const { data: expiredStk } = await supabase.from('motorcycles')
    .select('id, model, stk_valid_until, status')
    .eq('status', 'active').lt('stk_valid_until', new Date().toISOString()).limit(5)
  if (expiredStk?.length) {
    results.push({ agent: 'government', action: 'inconsistency_expired_stk_active', ok: false, count: expiredStk.length, motos: expiredStk.map(m => m.model) })
  } else {
    results.push({ agent: 'government', action: 'stk_status_consistent', ok: true })
  }

  // 3. VIN kontrola — ověř že všechny motorky mají VIN
  onStep?.({ agent: 'government', action: 'VIN kontrola', i: 7, total: 10 })
  const { data: noVin } = await supabase.from('motorcycles')
    .select('id, model').is('vin', null).eq('status', 'active').limit(10)
  results.push({ agent: 'government', action: 'check_vin_completeness', ok: !(noVin?.length), missingCount: noVin?.length || 0 })

  // 4. SPZ kontrola
  onStep?.({ agent: 'government', action: 'SPZ kontrola', i: 8, total: 10 })
  const { data: noSpz } = await supabase.from('motorcycles')
    .select('id, model').is('spz', null).eq('status', 'active').limit(10)
  results.push({ agent: 'government', action: 'check_spz_completeness', ok: !(noSpz?.length), missingCount: noSpz?.length || 0 })

  // 5. Souhrn compliance
  onStep?.({ agent: 'government', action: 'Compliance report', i: 9, total: 10 })
  results.push({ agent: 'government', action: 'compliance_summary', ok: true })

  return results
}
