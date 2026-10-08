// Re-export helperů servisní knížky + načtení faktur po záznamech (mapa logId → řádky).
export * from './serviceBook'
import { fetchServiceInvoices } from './serviceInvoices'

export async function fetchServiceInvoicesMap(logIds) {
  const rows = await fetchServiceInvoices(logIds)
  const map = {}
  for (const r of rows) { (map[r.maintenance_log_id] ||= []).push(r) }
  return map
}
