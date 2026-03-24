// Combined tool definitions: 31 read + 26 write tools
import { WRITE_TOOLS_DEFINITION } from './tools-def-write.ts'

const T = 'object' as const

const READ_TOOLS = [
  { name: 'get_bookings_summary', description: 'Počty rezervací podle stavu + tržby za aktuální a minulý měsíc', input_schema: { type: T, properties: {}, required: [] } },
  { name: 'get_bookings_detail', description: 'Seznam rezervací s filtrem', input_schema: { type: T, properties: { status: { type: 'string', description: 'Filtr dle stavu' }, limit: { type: 'number', description: 'Max počet (default 20)' }, date_from: { type: 'string', description: 'Od data (YYYY-MM-DD)' }, date_to: { type: 'string', description: 'Do data (YYYY-MM-DD)' } }, required: [] } },
  { name: 'get_fleet_overview', description: 'Všechny motorky se stavem, nájezdem, pobočkou', input_schema: { type: T, properties: { status: { type: 'string', description: 'Filtr dle stavu' }, branch_id: { type: 'string', description: 'Filtr dle ID pobočky' } }, required: [] } },
  { name: 'get_motorcycle_detail', description: 'Detail jedné motorky + její rezervace a servis', input_schema: { type: T, properties: { motorcycle_id: { type: 'string', description: 'UUID motorky' }, spz: { type: 'string', description: 'SPZ motorky' }, model_search: { type: 'string', description: 'Hledání dle modelu' } }, required: [] } },
  { name: 'get_sos_incidents', description: 'SOS incidenty s detaily', input_schema: { type: T, properties: { status: { type: 'string', description: 'Filtr dle stavu' }, limit: { type: 'number', description: 'Max počet (default 20)' } }, required: [] } },
  { name: 'get_branches', description: 'Pobočky s počty motorek', input_schema: { type: T, properties: {}, required: [] } },
  { name: 'get_customers', description: 'Přehled zákazníků', input_schema: { type: T, properties: { search: { type: 'string', description: 'Hledání dle jména/emailu' }, limit: { type: 'number', description: 'Max počet (default 20)' } }, required: [] } },
  { name: 'get_customer_detail', description: 'Kompletní profil zákazníka + rezervace + dokumenty', input_schema: { type: T, properties: { customer_id: { type: 'string', description: 'UUID zákazníka' }, email: { type: 'string', description: 'Email' }, name_search: { type: 'string', description: 'Hledání dle jména' } }, required: [] } },
  { name: 'get_financial_overview', description: 'Tržby, faktury, platby, vouchery', input_schema: { type: T, properties: { period: { type: 'string', description: 'Období: today/week/month/quarter' } }, required: [] } },
  { name: 'get_invoices', description: 'Seznam faktur', input_schema: { type: T, properties: { status: { type: 'string', description: 'Filtr dle stavu' }, type: { type: 'string', description: 'Filtr dle typu' }, limit: { type: 'number', description: 'Max počet (default 20)' } }, required: [] } },
  { name: 'get_shop_orders', description: 'E-shop objednávky', input_schema: { type: T, properties: { status: { type: 'string', description: 'Filtr dle stavu' }, limit: { type: 'number', description: 'Max počet (default 20)' } }, required: [] } },
  { name: 'get_vouchers_and_promos', description: 'Aktivní vouchery a promo kódy', input_schema: { type: T, properties: { active_only: { type: 'boolean', description: 'Pouze aktivní (default true)' } }, required: [] } },
  { name: 'get_service_status', description: 'Blížící se servisy + aktivní servisní objednávky', input_schema: { type: T, properties: { days_ahead: { type: 'number', description: 'Počet dní dopředu (default 30)' } }, required: [] } },
  { name: 'get_messages_overview', description: 'Přehled zpráv se zákazníky', input_schema: { type: T, properties: { unread_only: { type: 'boolean', description: 'Pouze nepřečtené' }, limit: { type: 'number', description: 'Max počet (default 20)' } }, required: [] } },
  { name: 'get_daily_stats', description: 'Denní statistiky za období', input_schema: { type: T, properties: { days: { type: 'number', description: 'Počet dní zpět (default 7)' } }, required: [] } },
  { name: 'get_inventory', description: 'Sklady — položky, zásoby, nízké stavy, dodavatelé', input_schema: { type: T, properties: { search: { type: 'string' }, low_stock_only: { type: 'boolean' }, category: { type: 'string' }, limit: { type: 'number' } }, required: [] } },
  { name: 'get_inventory_movements', description: 'Pohyby skladu', input_schema: { type: T, properties: { item_id: { type: 'string' }, type: { type: 'string' }, limit: { type: 'number' } }, required: [] } },
  { name: 'get_branch_detail', description: 'Kompletní detail pobočky', input_schema: { type: T, properties: { branch_id: { type: 'string', description: 'UUID pobočky' } }, required: ['branch_id'] } },
  { name: 'get_documents', description: 'Dokumenty — smlouvy, šablony, vygenerované, e-maily', input_schema: { type: T, properties: { type: { type: 'string' }, search: { type: 'string' }, limit: { type: 'number' } }, required: [] } },
  { name: 'get_reviews', description: 'Hodnocení zákazníků', input_schema: { type: T, properties: { moto_id: { type: 'string' }, min_rating: { type: 'number' }, limit: { type: 'number' } }, required: [] } },
  { name: 'get_cms_settings', description: 'CMS nastavení — feature flagy, proměnné, app_settings', input_schema: { type: T, properties: { section: { type: 'string' } }, required: [] } },
  { name: 'get_audit_log', description: 'Audit log — historie akcí adminů', input_schema: { type: T, properties: { admin_id: { type: 'string' }, action: { type: 'string' }, limit: { type: 'number' } }, required: [] } },
  { name: 'get_government_overview', description: 'Státní správa — STK termíny, pojistky celé flotily', input_schema: { type: T, properties: {}, required: [] } },
  { name: 'get_sos_detail', description: 'Detail SOS incidentu včetně timeline', input_schema: { type: T, properties: { incident_id: { type: 'string' } }, required: ['incident_id'] } },
  { name: 'get_pricing_overview', description: 'Ceník — denní ceny motorek', input_schema: { type: T, properties: { motorcycle_id: { type: 'string' } }, required: [] } },
  { name: 'analyze_branch_performance', description: 'Analýza výkonnosti poboček', input_schema: { type: T, properties: { period_months: { type: 'number' } }, required: [] } },
  { name: 'analyze_motorcycle_performance', description: 'Analýza výkonnosti motorek', input_schema: { type: T, properties: { period_months: { type: 'number' } }, required: [] } },
  { name: 'analyze_category_demand', description: 'Analýza poptávky dle kategorie', input_schema: { type: T, properties: { period_months: { type: 'number' } }, required: [] } },
  { name: 'analyze_optimal_fleet', description: 'Optimální složení flotily', input_schema: { type: T, properties: { branch_id: { type: 'string' }, period_months: { type: 'number' } }, required: ['branch_id'] } },
  { name: 'analyze_customers', description: 'Analýza zákazníků — segmentace', input_schema: { type: T, properties: { period_months: { type: 'number' } }, required: [] } },
  { name: 'forecast_predictions', description: 'Predikce tržeb a obsazenosti', input_schema: { type: T, properties: { months_ahead: { type: 'number' }, branch_id: { type: 'string' } }, required: [] } },
  // HR tools
  { name: 'get_employees', description: 'Seznam zaměstnanců s pozicemi a mzdami', input_schema: { type: T, properties: {}, required: [] } },
  { name: 'get_employee_detail', description: 'Detail zaměstnance — docházka, dovolená, směny, dokumenty, mzdy', input_schema: { type: T, properties: { employee_id: { type: 'string' } }, required: ['employee_id'] } },
  { name: 'get_attendance_overview', description: 'Přehled docházky za období', input_schema: { type: T, properties: { days: { type: 'number', description: 'Počet dní zpět (default 7)' } }, required: [] } },
  { name: 'get_pending_vacations', description: 'Nevyřízené žádosti o dovolenou', input_schema: { type: T, properties: {}, required: [] } },
  { name: 'get_shifts_overview', description: 'Přehled směn', input_schema: { type: T, properties: { days_ahead: { type: 'number' } }, required: [] } },
  { name: 'get_payrolls', description: 'Přehled výplatních pásek', input_schema: { type: T, properties: { limit: { type: 'number' } }, required: [] } },
  // Accounting tools
  { name: 'get_accounting_entries', description: 'Účetní záznamy', input_schema: { type: T, properties: { type: { type: 'string' }, limit: { type: 'number' } }, required: [] } },
  { name: 'get_cash_register', description: 'Pokladna — záznamy a zůstatek', input_schema: { type: T, properties: { limit: { type: 'number' } }, required: [] } },
  { name: 'get_long_term_assets', description: 'Dlouhodobý majetek — vozidla, stroje, odpisy', input_schema: { type: T, properties: {}, required: [] } },
  { name: 'get_short_term_assets', description: 'Krátkodobý majetek — materiál, zásoby, pohledávky', input_schema: { type: T, properties: {}, required: [] } },
  { name: 'get_depreciation', description: 'Odpisy dlouhodobého majetku za rok', input_schema: { type: T, properties: { year: { type: 'number' } }, required: [] } },
  { name: 'get_liabilities', description: 'Závazky — dodavatelé, daně, SP, ZP, mzdy', input_schema: { type: T, properties: { unpaid_only: { type: 'boolean' } }, required: [] } },
  { name: 'get_vat_returns', description: 'DPH přiznání — čtvrtletní přehledy', input_schema: { type: T, properties: {}, required: [] } },
  { name: 'get_tax_returns', description: 'Daňová přiznání', input_schema: { type: T, properties: {}, required: [] } },
  { name: 'get_tax_records', description: 'Daňové záznamy', input_schema: { type: T, properties: { limit: { type: 'number' } }, required: [] } },
  { name: 'get_flexi_reports', description: 'Výkazy z Abra Flexi — DPH, daně, rozvaha, výsledovka', input_schema: { type: T, properties: {}, required: [] } },
  // Extra tools
  { name: 'get_contracts', description: 'Smlouvy — nájemní, servisní, zaměstnanecké', input_schema: { type: T, properties: { status: { type: 'string' }, contract_type: { type: 'string' }, limit: { type: 'number' } }, required: [] } },
  { name: 'get_purchase_orders', description: 'Nákupní objednávky s položkami', input_schema: { type: T, properties: { status: { type: 'string' }, limit: { type: 'number' } }, required: [] } },
  { name: 'get_booking_extras', description: 'Příslušenství k rezervaci + katalog', input_schema: { type: T, properties: { booking_id: { type: 'string' } }, required: ['booking_id'] } },
  { name: 'get_booking_complaints', description: 'Reklamace zákazníků', input_schema: { type: T, properties: { status: { type: 'string' }, limit: { type: 'number' } }, required: [] } },
  { name: 'get_booking_cancellations', description: 'Storna rezervací s refundy', input_schema: { type: T, properties: { limit: { type: 'number' } }, required: [] } },
  { name: 'get_payment_methods', description: 'Uložené platební karty zákazníků', input_schema: { type: T, properties: { user_id: { type: 'string' } }, required: [] } },
  { name: 'get_service_parts', description: 'Díly potřebné pro servisní plány', input_schema: { type: T, properties: { schedule_id: { type: 'string' } }, required: [] } },
  { name: 'get_moto_locations', description: 'GPS pozice motorek', input_schema: { type: T, properties: {}, required: [] } },
  { name: 'get_auto_order_rules', description: 'Pravidla automatických objednávek', input_schema: { type: T, properties: {}, required: [] } },
  { name: 'get_notification_log', description: 'Log odeslaných notifikací', input_schema: { type: T, properties: { limit: { type: 'number' } }, required: [] } },
  { name: 'get_message_templates', description: 'Šablony SMS/email zpráv', input_schema: { type: T, properties: {}, required: [] } },
  { name: 'get_accessory_types', description: 'Typy příslušenství (dynamické)', input_schema: { type: T, properties: {}, required: [] } },
  { name: 'get_performance_stats', description: 'Výkonnostní statistiky motorek a poboček', input_schema: { type: T, properties: {}, required: [] } },
]

export const TOOLS_DEFINITION = [...READ_TOOLS, ...WRITE_TOOLS_DEFINITION]

// Filter tools by enabled list
export function filterToolsByEnabled(enabledTools?: string[]) {
  if (!enabledTools || enabledTools.length === 0) return TOOLS_DEFINITION
  return TOOLS_DEFINITION.filter(t => enabledTools.includes(t.name))
}
