// Mock data for demo mode (when Supabase is unavailable)

export const MOTOS = [
  { id: 'bmw', model: 'BMW R 1200 GS Adventure', category: 'cestovní', status: 'active', branch: 'Mezná', mileage: 42350, spz: '5P2 3456', price_per_day: 4208, next_service: '2026-04-15', stk_valid_until: '2026-12-01', image_url: null },
  { id: 'jawa', model: 'Jawa RVM 500 Adventure', category: 'cestovní', status: 'active', branch: 'Mezná', mileage: 18200, spz: '3J1 2233', price_per_day: 1986, next_service: '2026-05-01', stk_valid_until: '2027-02-15', image_url: null },
  { id: 'benelli', model: 'Benelli TRK 702 X', category: 'cestovní', status: 'maintenance', branch: 'Mezná', mileage: 31400, spz: '2B4 7788', price_per_day: 2951, next_service: '2026-03-10', stk_valid_until: '2026-08-20', image_url: null },
  { id: 'cfmoto', model: 'CF MOTO 800 MT', category: 'cestovní', status: 'active', branch: 'Mezná', mileage: 15800, spz: '6C2 1199', price_per_day: 3941, next_service: '2026-06-20', stk_valid_until: '2027-01-10', image_url: null },
  { id: 'niken', model: 'Yamaha Niken GT', category: 'special', status: 'active', branch: 'Mezná', mileage: 28900, spz: '1Y3 5566', price_per_day: 3931, next_service: '2026-03-28', stk_valid_until: '2026-11-05', image_url: null },
  { id: 'ktm', model: 'KTM 1290 Super Adv.', category: 'adventure', status: 'active', branch: 'Brno', mileage: 52100, spz: '4K7 9900', price_per_day: 4500, next_service: '2026-04-05', stk_valid_until: '2026-10-15', image_url: null },
  { id: 'tiger', model: 'Triumph Tiger 1200', category: 'adventure', status: 'out_of_service', branch: 'Brno', mileage: 67200, spz: '7T8 4411', price_per_day: 4100, next_service: null, stk_valid_until: null, image_url: null },
  { id: 'versys', model: 'Kawasaki Versys 650', category: 'naked', status: 'active', branch: 'Brno', mileage: 22700, spz: '8K1 6677', price_per_day: 2200, next_service: '2026-05-15', stk_valid_until: '2027-03-01', image_url: null },
]

export const BOOKINGS = [
  { id: 'RES-2026-001', customer_name: 'Jan Novák', motorcycle_name: 'BMW R 1200 GS', start_date: '2026-03-01', end_date: '2026-03-04', status: 'active', total_price: 16832, paid: true, customer_email: 'jan@example.cz', customer_phone: '+420111222333' },
  { id: 'RES-2026-002', customer_name: 'Petra Dvořáková', motorcycle_name: 'CF MOTO 800 MT', start_date: '2026-03-02', end_date: '2026-03-05', status: 'active', total_price: 15764, paid: true, customer_email: 'petra@example.cz', customer_phone: '+420222333444' },
  { id: 'RES-2026-003', customer_name: 'Martin Šimek', motorcycle_name: 'KTM 1290 SA', start_date: '2026-03-05', end_date: '2026-03-08', status: 'pending', total_price: 18000, paid: false, customer_email: 'martin@example.cz', customer_phone: '+420333444555' },
  { id: 'RES-2026-004', customer_name: 'Eva Králová', motorcycle_name: 'Yamaha Niken GT', start_date: '2026-03-03', end_date: '2026-03-06', status: 'active', total_price: 15724, paid: true, customer_email: 'eva@example.cz', customer_phone: '+420444555666' },
  { id: 'RES-2026-005', customer_name: 'Tomáš Beneš', motorcycle_name: 'Kawasaki Versys', start_date: '2026-03-10', end_date: '2026-03-12', status: 'pending', total_price: 4400, paid: false, customer_email: 'tomas@example.cz', customer_phone: '+420555666777' },
]

export const MESSAGES = [
  { id: 1, sender_name: 'Jan Novák', channel: 'web', subject: 'Dotaz na prodloužení', created_at: '2026-03-04T14:32:00', read: false, body: 'Dobrý den, chtěl bych prodloužit pronájem o 2 dny.' },
  { id: 2, sender_name: 'Petra D.', channel: 'whatsapp', subject: 'Problém s helmetem', created_at: '2026-03-04T11:15:00', read: false, body: 'Dobrý den, helma má poškrábaný štít.' },
  { id: 3, sender_name: 'Martin Šimek', channel: 'email', subject: 'Potvrzení platby', created_at: '2026-03-03T19:00:00', read: true, body: 'Posílám potvrzení platby za rezervaci.' },
  { id: 4, sender_name: 'Autoservis Havel', channel: 'email', subject: 'Benelli TRK hotova', created_at: '2026-03-04T09:00:00', read: false, body: 'Benelli TRK 702 X je připravena k vyzvednutí.' },
  { id: 5, sender_name: 'Eva K.', channel: 'instagram', subject: 'Fotky z výletu', created_at: '2026-03-03T16:45:00', read: true, body: 'Posílám fotky z víkendového výletu na Niken.' },
]

export const INVENTORY = [
  { id: 1, name: 'Helma Shoei GT-Air II', sku: 'HLM-001', stock: 8, min_stock: 4, category: 'ochranné', unit_price: 12500 },
  { id: 2, name: 'Bunda Alpinestars Andes', sku: 'BUN-001', stock: 2, min_stock: 4, category: 'ochranné', unit_price: 8200 },
  { id: 3, name: 'Motorový olej Motul 10W-40', sku: 'OIL-001', stock: 24, min_stock: 10, category: 'spotřební', unit_price: 450 },
  { id: 4, name: 'Brzdové destičky univerzál', sku: 'BRK-001', stock: 6, min_stock: 8, category: 'spotřební', unit_price: 890 },
  { id: 5, name: 'Řetězová sada 520', sku: 'RET-001', stock: 3, min_stock: 4, category: 'spotřební', unit_price: 3200 },
  { id: 6, name: 'Pneumatiky Michelin Road 6', sku: 'PNE-001', stock: 4, min_stock: 4, category: 'spotřební', unit_price: 4800 },
]

export const CUSTOMERS = [
  { id: 1, name: 'Jan Novák', email: 'jan@example.cz', phone: '+420111222333', bookings_count: 5, total_spent: 84160, vip: true, created_at: '2025-06-15' },
  { id: 2, name: 'Petra Dvořáková', email: 'petra@example.cz', phone: '+420222333444', bookings_count: 3, total_spent: 47292, vip: false, created_at: '2025-09-20' },
  { id: 3, name: 'Martin Šimek', email: 'martin@example.cz', phone: '+420333444555', bookings_count: 1, total_spent: 18000, vip: false, created_at: '2026-01-10' },
  { id: 4, name: 'Eva Králová', email: 'eva@example.cz', phone: '+420444555666', bookings_count: 4, total_spent: 62896, vip: true, created_at: '2025-04-01' },
  { id: 5, name: 'Tomáš Beneš', email: 'tomas@example.cz', phone: '+420555666777', bookings_count: 2, total_spent: 8800, vip: false, created_at: '2025-11-05' },
]

export const DOCS = [
  { id: 1, type: 'VOP', name: 'Všeobecné obchodní podmínky v2.4', updated_at: '2026-02-15', status: 'active' },
  { id: 2, type: 'Smlouva', name: 'Šablona nájemní smlouvy', updated_at: '2026-01-20', status: 'active' },
  { id: 3, type: 'Faktura', name: 'Šablona faktury', updated_at: '2026-02-28', status: 'active' },
  { id: 4, type: 'Protokol', name: 'Předávací protokol motorky', updated_at: '2026-02-10', status: 'active' },
  { id: 5, type: 'GDPR', name: 'Souhlas se zpracováním údajů', updated_at: '2025-12-01', status: 'review' },
  { id: 6, type: 'Pojistka', name: 'Pojistné podmínky pronájmu', updated_at: '2026-01-05', status: 'active' },
]

export const REVENUE_MONTHLY = [82, 71, 145, 198, 267, 312, 345, 356, 289, 178, 95, 68]
export const COST_MONTHLY = [48, 42, 72, 89, 112, 134, 148, 152, 124, 88, 52, 38]

export const SOS_INCIDENTS = []

export const ACCOUNTING_ENTRIES = [
  { id: 1, type: 'revenue', description: 'Pronájem BMW R 1200 GS', amount: 16832, date: '2026-03-01' },
  { id: 2, type: 'revenue', description: 'Pronájem CF MOTO 800 MT', amount: 15764, date: '2026-03-02' },
  { id: 3, type: 'expense', description: 'Servis Benelli TRK', amount: -24200, date: '2026-03-05' },
  { id: 4, type: 'revenue', description: 'Pronájem Yamaha Niken GT', amount: 15724, date: '2026-03-03' },
]

export const SERVICE_LOG = [
  { id: 1, motorcycle_id: 'benelli', motorcycle_name: 'Benelli TRK 702 X', type: 'Velký servis', date: '2026-03-05', cost: 24200, status: 'in_progress', notes: 'Výměna brzdových destiček, olej, řetěz' },
  { id: 2, motorcycle_id: 'bmw', motorcycle_name: 'BMW R 1200 GS', type: 'Běžný servis', date: '2026-04-15', cost: 8500, status: 'planned', notes: 'Pravidelná údržba 50 000 km' },
]

export function isDemoMode() {
  return sessionStorage.getItem('motogo_demo') === '1'
}
