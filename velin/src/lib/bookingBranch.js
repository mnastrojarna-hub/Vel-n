// Pobočka REZERVACE = kde zákazník motorku skutečně převzal (`bookings.branch_id`).
// Plní ji DB triggery (migrace 20261010b): do vyzvednutí následuje motorku, od vyzvednutí /
// storna / dokončení je zmrazená → pozdější přesun motorky už nepřestěhuje historii.
// Záloha na AKTUÁLNÍ pobočku motorky jen u řádků s NULL (krátce po nasazení, než doběhne migrace).
// Kde je potřeba AKTUÁLNÍ umístění motorky (kód brány, quick check-in, logistika výbavy,
// seznamy motorek), tento helper NEPOUŽÍVAT.

/** Embed pobočky rezervace do PostgREST selectu (explicitní FK, ať PostgREST nehádá cestu). */
export const BOOKING_BRANCH_EMBED = 'branch:branches!bookings_branch_id_fkey(id, name, type, address, zip, city)'

/** ID pobočky rezervace: bookings.branch_id, jinak pobočka motorky (embed nebo mapa moto_id → branch_id). */
export function effBranchId(b, motoBranchMap) {
  return b?.branch_id || b?.motorcycles?.branch_id || motoBranchMap?.[b?.moto_id] || null
}

/** Pobočka rezervace jako objekt: embed `branch`, jinak `motorcycles.branches`. */
export function effBranch(b) {
  return b?.branch || b?.motorcycles?.branches || null
}

/** Pro `.or()`: rezervace pobočky dle bookings.branch_id; u NULL záloha přes motorky pobočky (`motoIds`). */
export function branchOrFilter(branchId, motoIds) {
  const ids = motoIds?.length ? motoIds.join(',') : '00000000-0000-0000-0000-000000000000'
  return `branch_id.eq.${branchId},and(branch_id.is.null,moto_id.in.(${ids}))`
}
