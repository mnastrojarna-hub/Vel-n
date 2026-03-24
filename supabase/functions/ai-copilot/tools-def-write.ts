// Write tool definitions for AI Copilot — requires confirmation before execution

const T = 'object' as const
const S = { type: 'string' as const }
const N = { type: 'number' as const }
const B = { type: 'boolean' as const }

export const WRITE_TOOLS_DEFINITION = [
  // === BOOKING AGENT ===
  { name: 'update_booking_status', description: 'Změna stavu rezervace (pending/reserved/active/completed/cancelled)', input_schema: { type: T, properties: { booking_id: { ...S, description: 'UUID rezervace' }, new_status: { ...S, description: 'Nový stav' }, reason: { ...S, description: 'Důvod změny' } }, required: ['booking_id', 'new_status'] } },
  { name: 'update_booking_details', description: 'Úprava detailů rezervace (poznámky, termíny, extras)', input_schema: { type: T, properties: { booking_id: { ...S, description: 'UUID' }, notes: S, start_date: S, end_date: S, extras_price: N, deposit: N }, required: ['booking_id'] } },
  { name: 'confirm_booking_payment', description: 'Potvrzení platby rezervace', input_schema: { type: T, properties: { booking_id: { ...S, description: 'UUID' }, method: { ...S, description: 'Platební metoda (card/cash/transfer)' } }, required: ['booking_id'] } },

  // === FLEET AGENT ===
  { name: 'update_motorcycle', description: 'Úprava motorky (stav, nájezd, pobočka, údaje)', input_schema: { type: T, properties: { motorcycle_id: { ...S, description: 'UUID' }, status: S, mileage: N, branch_id: S, unavailable_reason: S, notes: S }, required: ['motorcycle_id'] } },
  { name: 'update_motorcycle_pricing', description: 'Úprava ceníku motorky dle dnů', input_schema: { type: T, properties: { motorcycle_id: { ...S, description: 'UUID' }, price_mon: N, price_tue: N, price_wed: N, price_thu: N, price_fri: N, price_sat: N, price_sun: N }, required: ['motorcycle_id'] } },
  { name: 'update_branch', description: 'Úprava pobočky (název, otevřeno/zavřeno, typ)', input_schema: { type: T, properties: { branch_id: { ...S, description: 'UUID' }, name: S, is_open: B, type: S }, required: ['branch_id'] } },
  { name: 'update_branch_accessories', description: 'Úprava příslušenství na pobočce', input_schema: { type: T, properties: { branch_id: { ...S, description: 'UUID' }, type: { ...S, description: 'Typ příslušenství' }, size: S, quantity: N }, required: ['branch_id', 'type', 'size', 'quantity'] } },

  // === CUSTOMER AGENT ===
  { name: 'update_customer', description: 'Úprava profilu zákazníka', input_schema: { type: T, properties: { customer_id: { ...S, description: 'UUID' }, full_name: S, phone: S, city: S, is_blocked: B, blocked_reason: S }, required: ['customer_id'] } },
  { name: 'send_customer_message', description: 'Odeslání zprávy zákazníkovi', input_schema: { type: T, properties: { customer_id: { ...S, description: 'UUID' }, content: { ...S, description: 'Text zprávy' }, channel: { ...S, description: 'Kanál: sms/email/whatsapp/in_app' } }, required: ['customer_id', 'content'] } },

  // === FINANCE AGENT ===
  { name: 'update_invoice_status', description: 'Změna stavu faktury', input_schema: { type: T, properties: { invoice_id: { ...S, description: 'UUID' }, status: { ...S, description: 'Nový stav' }, paid_date: S }, required: ['invoice_id', 'status'] } },
  { name: 'create_accounting_entry', description: 'Vytvoření účetního záznamu', input_schema: { type: T, properties: { type: { ...S, description: 'Typ záznamu' }, amount: N, description: S, category: S }, required: ['type', 'amount'] } },
  { name: 'match_delivery_note', description: 'Párování dodacího listu s fakturou', input_schema: { type: T, properties: { delivery_note_id: S, invoice_id: S, confidence: N }, required: ['delivery_note_id', 'invoice_id'] } },

  // === SERVICE AGENT ===
  { name: 'create_service_order', description: 'Vytvoření servisní objednávky', input_schema: { type: T, properties: { moto_id: { ...S, description: 'UUID motorky' }, description: S, status: S }, required: ['moto_id'] } },
  { name: 'update_service_order', description: 'Úprava servisní objednávky', input_schema: { type: T, properties: { order_id: S, status: S, notes: S }, required: ['order_id'] } },
  { name: 'create_maintenance_log', description: 'Zápis do servisního logu', input_schema: { type: T, properties: { moto_id: S, service_type: S, description: S, cost: N, technician_id: S, labor_hours: N }, required: ['moto_id', 'service_type'] } },

  // === HR AGENT ===
  { name: 'create_attendance', description: 'Zápis docházky zaměstnance', input_schema: { type: T, properties: { employee_id: S, date: S, check_in: S, check_out: S, status: { ...S, description: 'present/absent/sick/vacation/home_office' } }, required: ['employee_id', 'date', 'status'] } },
  { name: 'manage_vacation', description: 'Správa dovolené', input_schema: { type: T, properties: { employee_id: S, start_date: S, end_date: S, type: { ...S, description: 'vacation/sick/personal/unpaid' }, status: { ...S, description: 'pending/approved/rejected' }, action: { ...S, description: 'create/approve/reject' } }, required: ['employee_id', 'action'] } },
  { name: 'manage_shifts', description: 'Plánování směn', input_schema: { type: T, properties: { employee_id: S, date: S, shift_type: { ...S, description: 'morning/afternoon/night/full_day/free' }, branch_id: S }, required: ['employee_id', 'date', 'shift_type'] } },

  // === ESHOP AGENT ===
  { name: 'update_shop_order', description: 'Změna stavu e-shop objednávky', input_schema: { type: T, properties: { order_id: S, status: S, notes: S }, required: ['order_id', 'status'] } },
  { name: 'update_product', description: 'Úprava produktu v e-shopu', input_schema: { type: T, properties: { product_id: S, name: S, price: N, stock_quantity: N, is_active: B }, required: ['product_id'] } },
  { name: 'create_promo_code', description: 'Vytvoření slevového kódu', input_schema: { type: T, properties: { code: S, type: { ...S, description: 'percent/fixed' }, discount_value: N, max_uses: N, valid_to: S }, required: ['code', 'type', 'discount_value'] } },

  // === CMS AGENT ===
  { name: 'update_app_setting', description: 'Změna nastavení aplikace', input_schema: { type: T, properties: { key: S, value: { ...S, description: 'JSON string hodnoty' } }, required: ['key', 'value'] } },
  { name: 'update_feature_flag', description: 'Zapnutí/vypnutí feature flagu', input_schema: { type: T, properties: { flag_name: S, enabled: B }, required: ['flag_name', 'enabled'] } },

  // === SOS AGENT ===
  { name: 'update_sos_incident', description: 'Úprava SOS incidentu', input_schema: { type: T, properties: { incident_id: S, status: S, admin_notes: S, assigned_to: S, resolution: S }, required: ['incident_id'] } },

  // === TESTER AGENT ===
  { name: 'generate_test_report', description: 'Vygenerování testovacího reportu', input_schema: { type: T, properties: { scope: { ...S, description: 'Oblast: bookings/fleet/finance/eshop/sos/all' }, depth: { ...S, description: 'quick/standard/deep' } }, required: ['scope'] } },
  { name: 'check_data_integrity', description: 'Kontrola integrity dat', input_schema: { type: T, properties: { table: { ...S, description: 'Název tabulky nebo all' } }, required: ['table'] } },

  // === PROCUREMENT ===
  { name: 'create_purchase_order', description: 'Vytvoření nákupní objednávky', input_schema: { type: T, properties: { supplier_id: S, items: { type: 'array' as const, description: 'Položky [{item_id, quantity, unit_price}]' }, notes: S }, required: [] } },
  { name: 'create_inventory_movement', description: 'Pohyb na skladě (příjem/výdej/korekce)', input_schema: { type: T, properties: { item_id: { ...S, description: 'UUID skladové položky' }, type: { ...S, description: 'receipt/issue/correction' }, quantity: N, notes: S }, required: ['item_id', 'type', 'quantity'] } },

  // === ORCHESTRATOR ===
  { name: 'generate_daily_briefing', description: 'Denní briefing pro ředitele — KPIs, alerty, priority', input_schema: { type: T, properties: {}, required: [] } },
  { name: 'check_agent_health', description: 'Kontrola zdraví všech AI agentů — stav domén', input_schema: { type: T, properties: {}, required: [] } },
  { name: 'get_priority_queue', description: 'Fronta priorit — co vyžaduje okamžitou pozornost', input_schema: { type: T, properties: {}, required: [] } },

  // === TESTER — FLOW TESTY ===
  { name: 'test_booking_flow', description: 'Test integrity booking flow — lifecycle, platby, konzistence', input_schema: { type: T, properties: {}, required: [] } },
  { name: 'test_payment_flow', description: 'Test platebního flow — platby vs faktury vs stavy', input_schema: { type: T, properties: {}, required: [] } },
  { name: 'test_sos_flow', description: 'Test SOS flow — response time, timeline, řešení', input_schema: { type: T, properties: {}, required: [] } },
  { name: 'run_full_system_test', description: 'Kompletní systémový test — DB, integrita, pricing, bezpečnost', input_schema: { type: T, properties: { depth: { ...S, description: 'quick/standard/deep' } }, required: [] } },
]

// Tool risk levels for confirmation dialog
export const TOOL_RISK: Record<string, string> = {
  update_booking_status: 'medium', update_booking_details: 'low', confirm_booking_payment: 'high',
  update_motorcycle: 'medium', update_motorcycle_pricing: 'medium', update_branch: 'low', update_branch_accessories: 'low',
  update_customer: 'medium', send_customer_message: 'high',
  update_invoice_status: 'medium', create_accounting_entry: 'medium', match_delivery_note: 'low',
  create_service_order: 'low', update_service_order: 'low', create_maintenance_log: 'low',
  create_attendance: 'low', manage_vacation: 'medium', manage_shifts: 'low',
  update_shop_order: 'medium', update_product: 'low', create_promo_code: 'medium',
  update_app_setting: 'high', update_feature_flag: 'high',
  update_sos_incident: 'medium',
  generate_test_report: 'low', check_data_integrity: 'low', create_purchase_order: 'medium', create_inventory_movement: 'medium',
  generate_daily_briefing: 'low', check_agent_health: 'low', get_priority_queue: 'low',
  test_booking_flow: 'low', test_payment_flow: 'low', test_sos_flow: 'low', run_full_system_test: 'low',
}
