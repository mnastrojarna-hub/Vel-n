// Read tools: Provoz+ — detail rezervace, logistika výbavy, finanční události, message log, kiosk + univerzální query_table
// Whitelist VŠECH provozních tabulek public schématu — univerzální fallback čtení.
// AI díky tomu NIKDY nemusí říct „k tomu nemám přístup".
const QUERYABLE_TABLES = [
  'profiles',
  'motorcycles',
  'bookings',
  'branches',
  'branch_accessories',
  'branch_door_codes',
  'admin_users',
  'booking_extras',
  'booking_cancellations',
  'booking_complaints',
  'booking_discounts',
  'extras_catalog',
  'moto_day_prices',
  'pricing_rules',
  'sos_incidents',
  'sos_timeline',
  'message_threads',
  'messages',
  'message_templates',
  'message_templates_sms',
  'admin_messages',
  'notification_log',
  'notification_rules',
  'push_tokens',
  'message_log',
  'broadcast_campaigns',
  'email_templates',
  'sent_emails',
  'invoices',
  'document_templates',
  'custom_documents',
  'generated_documents',
  'documents',
  'products',
  'shop_orders',
  'shop_order_items',
  'routes',
  'route_pois',
  'user_pois',
  'route_reviews',
  'poi_ratings',
  'points_of_interest',
  'user_saved_routes',
  'user_visited_places',
  'promo_codes',
  'promo_code_usage',
  'vouchers',
  'loyalty_levels',
  'loyalty_monthly_winners',
  'maintenance_log',
  'maintenance_schedules',
  'service_parts',
  'service_orders',
  'moto_locations',
  'accounting_entries',
  'financial_events',
  'document_number_counters',
  'cash_register',
  'tax_records',
  'daily_stats',
  'moto_performance',
  'branch_performance',
  'acc_employees',
  'acc_payrolls',
  'emp_attendance',
  'emp_vacations',
  'emp_shifts',
  'emp_documents',
  'acc_vat_returns',
  'acc_tax_returns',
  'acc_short_term_assets',
  'acc_long_term_assets',
  'acc_depreciation_entries',
  'acc_liabilities',
  'flexi_reports',
  'accounting_exceptions',
  'approval_queue',
  'flexi_sync_log',
  'delivery_notes',
  'contracts',
  'purchase_orders',
  'purchase_order_items',
  'auto_order_rules',
  'suppliers',
  'inventory',
  'inventory_movements',
  'gear_shortages',
  'stock_receipts',
  'accessory_types',
  'ai_conversations',
  'ai_customer_conversations',
  'ai_actions',
  'ai_logs',
  'automation_rules',
  'predictions',
  'api_keys',
  'ai_traffic_log',
  'ai_citations',
  'ai_public_conversations',
  'payment_methods',
  'app_settings',
  'cms_pages',
  'cms_variables',
  'faq_items',
  'feature_flags',
  'reviews',
  'admin_audit_log',
  'debug_log',
  'app_crash_reports',
  'app_debug_logs',
  'visitor_log',
  'app_installations',
  'branch_kiosk_config',
  'kiosk_devices',
  'branch_doors',
  'branch_service_codes',
  'kiosk_commands',
  'branch_door_events',
  'branch_cameras',
  'branch_power_status'
];
export async function execReadOpsPlus(name, input, sb) {
  const now = new Date();
  switch(name){
    // Univerzální čtení libovolné tabulky — fallback, když neexistuje specializovaný nástroj
    case 'query_table':
      {
        const table = input.table;
        if (!table || !QUERYABLE_TABLES.includes(table)) return {
          error: `Neznámá tabulka '${table}'. Povolené: ${QUERYABLE_TABLES.join(', ')}`
        };
        const limit = Math.min(input.limit || 20, 100);
        const columns = input.columns || '*';
        if (input.count_only) {
          let cq = sb.from(table).select('*', {
            count: 'exact',
            head: true
          });
          for (const f of input.filters || [])cq = applyFilter(cq, f);
          const { count, error } = await cq;
          return error ? {
            error: error.message
          } : {
            table,
            count
          };
        }
        let q = sb.from(table).select(columns);
        for (const f of input.filters || [])q = applyFilter(q, f);
        if (input.order_by) q = q.order(input.order_by, {
          ascending: input.ascending === true
        });
        q = q.limit(limit);
        const { data, error } = await q;
        if (error) return {
          error: error.message
        };
        return {
          table,
          rows: data || [],
          count: (data || []).length,
          limited_to: limit
        };
      }
    // Kompletní detail jedné rezervace — vše, co vidí Velín BookingDetail
    case 'get_booking_detail':
      {
        const id = input.booking_id;
        if (!id) return {
          error: 'booking_id je povinný'
        };
        const { data: b, error } = await sb.from('bookings').select('*').eq('id', id).single();
        if (error || !b) return {
          error: 'Rezervace nenalezena'
        };
        const [custR, motoR, discR, extrasR, invR, cancR, complR, codesR, sosR] = await Promise.all([
          b.user_id ? sb.from('profiles').select('id, full_name, email, phone, city, is_blocked, license_group, id_verified_at, license_verified_at, passport_verified_at').eq('id', b.user_id).single() : Promise.resolve({
            data: null
          }),
          b.moto_id ? sb.from('motorcycles').select('id, model, brand, spz, category, branch_id, status, box_number').eq('id', b.moto_id).single() : Promise.resolve({
            data: null
          }),
          sb.from('booking_discounts').select('*').eq('booking_id', id),
          sb.from('booking_extras').select('*').eq('booking_id', id),
          sb.from('invoices').select('id, number, type, total, status, issue_date, variable_symbol').eq('booking_id', id).order('issue_date'),
          sb.from('booking_cancellations').select('*').eq('booking_id', id),
          sb.from('booking_complaints').select('*').eq('booking_id', id),
          sb.from('branch_door_codes').select('code_type, door_code, is_active, valid_from, valid_until, sent_to_customer, withheld_reason').eq('booking_id', id),
          b.sos_incident_id ? sb.from('sos_incidents').select('id, type, severity, status, title').eq('id', b.sos_incident_id).single() : Promise.resolve({
            data: null
          })
        ]);
        return {
          booking: b,
          customer: custR.data,
          motorcycle: motoR.data,
          discounts: discR.data || [],
          extras: extrasR.data || [],
          invoices: invR.data || [],
          cancellation: (cancR.data || [])[0] || null,
          complaints: complR.data || [],
          door_codes: codesR.data || [],
          sos_incident: sosR.data,
          protocol: {
            started_at: b.handover_protocol_started_at,
            filled_at: b.handover_protocol_filled_at,
            autofilled: b.handover_protocol_autofilled
          },
          surcharge: b.mod_surcharge_due ? {
            due: b.mod_surcharge_due,
            vs: b.mod_surcharge_vs,
            requested_at: b.mod_surcharge_requested_at,
            paid_at: b.mod_surcharge_paid_at
          } : null
        };
      }
    // Logistika výbavy — deficity + naskladnění
    case 'get_gear_logistics':
      {
        const [shortR, recR] = await Promise.all([
          sb.from('gear_shortages').select('*').order('shortage_date').limit(200),
          sb.from('stock_receipts').select('*').order('created_at', {
            ascending: false
          }).limit(input.limit || 20)
        ]);
        const shorts = shortR.data || [];
        const open = shorts.filter((s)=>![
            'resolved',
            'dismissed'
          ].includes(s.status));
        return {
          open_shortages: open,
          open_count: open.length,
          by_status: shorts.reduce((m, s)=>{
            m[s.status] = (m[s.status] || 0) + 1;
            return m;
          }, {}),
          recent_stock_receipts: recR.data || [],
          receipts_missing_dl: (recR.data || []).filter((r)=>r.needs_dl).length
        };
      }
    // Finanční události (účetní pipeline) + výjimky + schvalovací fronta + Flexi sync
    case 'get_financial_events':
      {
        const limit = input.limit || 30;
        let q = sb.from('financial_events').select('*').order('created_at', {
          ascending: false
        }).limit(limit);
        if (input.status) q = q.eq('status', input.status);
        if (input.event_type) q = q.eq('event_type', input.event_type);
        const [evR, excR, apprR, syncR] = await Promise.all([
          q,
          sb.from('accounting_exceptions').select('*').is('resolved_at', null).limit(50),
          sb.from('approval_queue').select('*').eq('status', 'pending').limit(50),
          sb.from('flexi_sync_log').select('id, financial_event_id, direction, status, error_message, created_at').eq('status', 'error').order('created_at', {
            ascending: false
          }).limit(10)
        ]);
        const evs = evR.data || [];
        return {
          events: evs,
          by_status: evs.reduce((m, e)=>{
            m[e.status] = (m[e.status] || 0) + 1;
            return m;
          }, {}),
          unresolved_exceptions: excR.data || [],
          pending_approvals: apprR.data || [],
          recent_flexi_errors: syncR.data || []
        };
      }
    // Odeslaná komunikace — message_log (SMS/WhatsApp/email) + kampaně
    case 'get_message_log':
      {
        const limit = input.limit || 30;
        let q = sb.from('message_log').select('*').order('created_at', {
          ascending: false
        }).limit(limit);
        if (input.channel) q = q.eq('channel', input.channel);
        if (input.status) q = q.eq('status', input.status);
        const [logR, campR] = await Promise.all([
          q,
          sb.from('broadcast_campaigns').select('*').order('created_at', {
            ascending: false
          }).limit(10)
        ]);
        const logs = logR.data || [];
        return {
          messages: logs,
          by_channel: logs.reduce((m, l)=>{
            const c = l.channel || '?';
            m[c] = (m[c] || 0) + 1;
            return m;
          }, {}),
          failed: logs.filter((l)=>l.status === 'failed').length,
          campaigns: campR.data || []
        };
      }
    // Samoobslužné pobočky — kiosk zařízení, FV elektrárna, poslední otevření dveří
    case 'get_kiosk_status':
      {
        const [devR, pwrR, evR, cfgR] = await Promise.all([
          sb.from('kiosk_devices').select('id, branch_id, name, platform, app_version, last_seen_at, is_active'),
          sb.from('branch_power_status').select('*'),
          sb.from('branch_door_events').select('branch_id, kind, booking_id, success, code_masked, created_at').order('created_at', {
            ascending: false
          }).limit(input.limit || 20),
          sb.from('branch_kiosk_config').select('branch_id, is_active, door_open_seconds, power_poll_seconds')
        ]);
        const online = (d)=>d.last_seen_at && now.getTime() - new Date(d.last_seen_at).getTime() < 70000;
        return {
          devices: (devR.data || []).map((d)=>({
              ...d,
              online: online(d)
            })),
          online_count: (devR.data || []).filter(online).length,
          power_status: pwrR.data || [],
          recent_door_events: evR.data || [],
          kiosk_configs: cfgR.data || []
        };
      }
    default:
      return null;
  }
}
// deno-lint-ignore no-explicit-any
function applyFilter(q, f) {
  const { column, op, value } = f;
  if (!column) return q;
  switch(op){
    case 'neq':
      return q.neq(column, value);
    case 'gt':
      return q.gt(column, value);
    case 'gte':
      return q.gte(column, value);
    case 'lt':
      return q.lt(column, value);
    case 'lte':
      return q.lte(column, value);
    case 'like':
      return q.ilike(column, `%${value}%`);
    case 'is_null':
      return q.is(column, null);
    case 'not_null':
      return q.not(column, 'is', null);
    case 'in':
      return q.in(column, Array.isArray(value) ? value : String(value).split(','));
    default:
      return q.eq(column, value);
  }
}
