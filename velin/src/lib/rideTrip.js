// Cesty (víc jízd, které appka zákazníka ukazuje jako JEDNU cestu) — stejné
// seskupení jako appka (`rideTripKey` v ride_trip.dart):
//   `trip_id` vyplněné → sloučil je jezdec (klíč cesty; `trip_id` = vlastní id
//   znamená „výslovně samostatná"), jinak jízdy téže výpůjčky (`booking_id` —
//   i starší, rozdělené přes noc), jinak samostatná jízda.
// Velín cesty jen ukazuje; slučovat / rozdělovat může jen zákazník v appce.

import { rideDays, pragueDay, normStages } from './rideStats'

/** Klíč skupiny (s uživatelem — Velín čte jízdy všech zákazníků). */
export function rideTripKey(r) {
  const k = r.trip_id ? `t:${r.trip_id}` : (r.booking_id ? `b:${r.booking_id}` : `r:${r.id}`)
  return `${r.user_id || ''}|${k}`
}

/** Mapa klíč → cesta `{ key, rides (od nejstarší), explicit, rental, name }` (jen skupiny ≥ 2). */
export function groupRideTrips(rides) {
  const groups = new Map()
  for (const r of rides || []) {
    const k = rideTripKey(r)
    if (!groups.has(k)) groups.set(k, [])
    groups.get(k).push(r)
  }
  const out = new Map()
  for (const [key, list] of groups) {
    if (list.length < 2) continue
    const members = [...list].sort((a, b) => new Date(a.started_at) - new Date(b.started_at))
    const explicit = key.includes('|t:')
    const booking = members[0].booking_id
    const rental = !explicit || (!!booking && members.every(m => m.booking_id === booking))
    const named = members.find(m => (m.trip_name || '').trim())
    const moto = members.map(m => m.moto_name).find(Boolean)
    out.set(key, {
      key, rides: members, explicit, rental,
      name: named ? named.trip_name.trim()
        : (rental ? `Výpůjčka${moto ? ` ${moto}` : ''}` : `Cesta ${tripDates(members)}`),
    })
  }
  return out
}

/** Cesta, do které jízda patří (null = samostatná). */
export function tripOfRide(trips, ride) {
  return ride ? (trips.get(rideTripKey(ride)) || null) : null
}

/** „12. 10.–18. 10. 2026" — rozsah dat cesty. */
export function tripDates(rides) {
  const f = new Date(rides[0]?.started_at)
  const l = rides[rides.length - 1]
  const t = new Date(l?.ended_at || l?.last_fix_at || l?.started_at)
  if (!Number.isFinite(f.getTime()) || !Number.isFinite(t.getTime())) return ''
  const dm = (d) => `${d.getDate()}. ${d.getMonth() + 1}.`
  if (f.toDateString() === t.toDateString()) return `${dm(f)} ${f.getFullYear()}`
  if (f.getFullYear() !== t.getFullYear()) return `${dm(f)} ${f.getFullYear()}–${dm(t)} ${t.getFullYear()}`
  return `${dm(f)}–${dm(t)} ${t.getFullYear()}`
}

/** Souhrn cesty z uložených čísel jednotlivých jízd (nikdy z prořídlé stopy).
 *  Pauzy se nesčítají — sloučené jízdy můžou být měsíce od sebe. */
export function tripTotals(trip) {
  let km = 0, moving = 0
  const days = new Set()
  for (const r of trip.rides) {
    km += Number(r.distance_km || 0)
    moving += Number(r.moving_sec || 0)
    const st = normStages(r.stages)
    if (st.length) {
      st.forEach(s => { if (s.mv >= 300) { days.add(pragueDay(s.from)); days.add(pragueDay(s.to)) } })
    } else if (Number(r.moving_sec || 0) >= 300) {
      // Bez etap: kalendářní dny jízdy (rideDays) — rozepsané na data.
      const n = rideDays(r)
      const t0 = new Date(r.started_at).getTime()
      for (let i = 0; i < n; i++) days.add(pragueDay(new Date(t0 + i * 86400000).toISOString()))
    }
  }
  return { km, moving, days: Math.max(1, days.size), count: trip.rides.length }
}
