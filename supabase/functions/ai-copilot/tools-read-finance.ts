// Read tools 9-18: Finance, Invoices, Shop, Vouchers, Service, Messages, Stats, Inventory, Branch Detail
import { PAID_BOOKING_STATUSES } from './tools-constants.ts';
export async function execReadFinance(name, input, sb) {
  const now = new Date();
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).toISOString();
  switch(name){
    case 'get_financial_overview':
      {
        const period = input.period || 'month';
        let dateFrom;
        if (period === 'today') dateFrom = now.toISOString().slice(0, 10);
        else if (period === 'week') dateFrom = new Date(now.getTime() - 7 * 86400000).toISOString();
        else if (period === 'quarter') {
          const qm = Math.floor(now.getMonth() / 3) * 3;
          dateFrom = new Date(now.getFullYear(), qm, 1).toISOString();
        } else dateFrom = monthStart;
        const [revenueR, invoicesR, shopR, vouchersR, expR] = await Promise.all([
          sb.from('bookings').select('total_price, status, payment_status, is_test').in('payment_status', PAID_BOOKING_STATUSES).neq('status', 'cancelled').eq('is_test', false).gte('created_at', dateFrom),
          sb.from('invoices').select('id, total, status, type').gte('issue_date', dateFrom.slice(0, 10)),
          sb.from('shop_orders').select('id, total, payment_status').gte('created_at', dateFrom),
          sb.from('vouchers').select('amount').eq('status', 'active'),
          sb.from('accounting_entries').select('amount, type, category').eq('type', 'expense').gte('date', dateFrom.slice(0, 10))
        ]);
        const revenue = (revenueR.data || []).reduce((s, b)=>s + (b.total_price || 0), 0);
        const invoiceTotal = (invoicesR.data || []).reduce((s, i)=>s + (i.total || 0), 0);
        const shopTotal = (shopR.data || []).filter((o)=>o.payment_status === 'paid').reduce((s, o)=>s + (o.total || 0), 0);
        const voucherValue = (vouchersR.data || []).reduce((s, v)=>s + (v.amount || 0), 0);
        const expenses = (expR.data || []).reduce((s, e)=>s + (e.amount || 0), 0);
        return {
          period,
          revenue_bookings: revenue,
          revenue_note: 'Obrat = zaplacené, nestornované, netestovací rezervace (vč. partial_refund/refund_pending) dle vzniku v období',
          invoice_count: (invoicesR.data || []).length,
          invoice_total: invoiceTotal,
          shop_orders_paid_total: shopTotal,
          shop_orders_count: (shopR.data || []).length,
          active_voucher_value: voucherValue,
          expenses_accounting: expenses
        };
      }
    case 'get_invoices':
      {
        const limit = input.limit || 20;
        let q = sb.from('invoices').select('id, number, type, customer_id, booking_id, order_id, subtotal, tax_amount, total, status, issue_date, due_date, paid_date, source, variable_symbol').order('issue_date', {
          ascending: false
        }).limit(limit);
        if (input.status) q = q.eq('status', input.status);
        if (input.type) q = q.eq('type', input.type);
        const { data } = await q;
        return {
          invoices: data || [],
          count: (data || []).length
        };
      }
    case 'get_shop_orders':
      {
        const limit = input.limit || 20;
        let q = sb.from('shop_orders').select('id, order_number, customer_id, customer_name, customer_email, status, payment_status, payment_method, subtotal, shipping_cost, discount, total, shipping_method, tracking_number, created_at, confirmed_at').order('created_at', {
          ascending: false
        }).limit(limit);
        if (input.status) q = q.eq('status', input.status);
        const { data } = await q;
        return {
          orders: data || [],
          count: (data || []).length
        };
      }
    case 'get_vouchers_and_promos':
      {
        const activeOnly = input.active_only !== false;
        let vQ = sb.from('vouchers').select('id, code, amount, status, valid_from, valid_until, buyer_name, buyer_email, category, source, redeemed_at, booking_id, slevomat_apply_status, slevomat_applied_at');
        if (activeOnly) vQ = vQ.eq('status', 'active');
        let pQ = sb.from('promo_codes').select('id, code, type, value, active, source, used_count, max_uses, valid_from, valid_to, min_order_amount');
        if (activeOnly) pQ = pQ.eq('active', true);
        const [vR, pR] = await Promise.all([
          vQ,
          pQ
        ]);
        const vouchers = vR.data || [];
        return {
          vouchers,
          promo_codes: pR.data || [],
          total_voucher_value: vouchers.reduce((s, v)=>s + (v.amount || 0), 0)
        };
      }
    case 'get_service_status':
      {
        const daysAhead = input.days_ahead || 30;
        const futureDate = new Date(now.getTime() + daysAhead * 86400000).toISOString().slice(0, 10);
        const [upR, ordR] = await Promise.all([
          sb.from('motorcycles').select('id, model, brand, spz, mileage, next_service_date, last_service_date').not('next_service_date', 'is', null).lte('next_service_date', futureDate).order('next_service_date', {
            ascending: true
          }),
          sb.from('service_orders').select('id, moto_id, status, created_at').in('status', [
            'pending',
            'in_service'
          ])
        ]);
        return {
          upcoming_services: upR.data || [],
          active_orders: ordR.data || []
        };
      }
    case 'get_messages_overview':
      {
        const limit = input.limit || 20;
        let q = sb.from('message_threads').select('id, customer_id, channel, status, assigned_admin, created_at, updated_at').order('updated_at', {
          ascending: false
        }).limit(limit);
        if (input.unread_only) q = q.eq('status', 'open');
        const { data } = await q;
        return {
          threads: data || [],
          count: (data || []).length
        };
      }
    case 'get_daily_stats':
      {
        const days = input.days || 7;
        const since = new Date(now.getTime() - days * 86400000).toISOString().slice(0, 10);
        const { data } = await sb.from('daily_stats').select('*').gte('date', since).order('date', {
          ascending: false
        }).limit(days);
        return {
          stats: data || [],
          days
        };
      }
    case 'get_inventory':
      {
        try {
          const limit = input.limit || 50;
          let q = sb.from('inventory').select('id, name, sku, category, stock, min_stock, unit_price, supplier_id').order('name', {
            ascending: true
          }).limit(limit);
          if (input.search) {
            const s = input.search;
            q = q.or(`name.ilike.%${s}%,sku.ilike.%${s}%`);
          }
          if (input.category) q = q.eq('category', input.category);
          const { data: items, error: err } = await q;
          if (err) throw err;
          const sids = [
            ...new Set((items || []).map((i)=>i.supplier_id).filter(Boolean))
          ];
          const { data: suppliers } = sids.length > 0 ? await sb.from('suppliers').select('id, name').in('id', sids) : {
            data: []
          };
          const sm = {};
          for (const s of suppliers || [])sm[s.id] = s.name;
          let enriched = (items || []).map((i)=>({
              ...i,
              supplier_name: sm[i.supplier_id] || null
            }));
          if (input.low_stock_only) enriched = enriched.filter((i)=>i.stock <= i.min_stock);
          const lowCount = (items || []).filter((i)=>i.stock <= i.min_stock).length;
          return {
            total: enriched.length,
            low_stock_count: lowCount,
            items: enriched
          };
        } catch  {
          return {
            error: 'Table not available',
            data: []
          };
        }
      }
    case 'get_inventory_movements':
      {
        try {
          const limit = input.limit || 30;
          let q = sb.from('inventory_movements').select('*').order('created_at', {
            ascending: false
          }).limit(limit);
          if (input.item_id) q = q.eq('item_id', input.item_id);
          if (input.type) q = q.eq('type', input.type);
          const { data, error: err } = await q;
          if (err) throw err;
          return {
            movements: data || [],
            count: (data || []).length
          };
        } catch  {
          return {
            error: 'Table not available',
            data: []
          };
        }
      }
    case 'get_branch_detail':
      {
        try {
          const branchId = input.branch_id;
          if (!branchId) return {
            error: 'branch_id je povinný parametr'
          };
          const [branchR, motosR, accR, codesR, bookR] = await Promise.all([
            sb.from('branches').select('*').eq('id', branchId).single(),
            sb.from('motorcycles').select('id, model, brand, spz, status, mileage, image_url, category, year').eq('branch_id', branchId),
            sb.from('branch_accessories').select('*').eq('branch_id', branchId),
            sb.from('branch_door_codes').select('*').eq('branch_id', branchId).eq('is_active', true),
            sb.from('bookings').select('id, user_id, moto_id, start_date, end_date, status, total_price, payment_status').in('status', [
              'active',
              'reserved'
            ])
          ]);
          if (!branchR.data) return {
            error: 'Pobočka nenalezena'
          };
          const bmIds = (motosR.data || []).map((m)=>m.id);
          const bb = (bookR.data || []).filter((b)=>bmIds.includes(b.moto_id));
          const uids = [
            ...new Set(bb.map((b)=>b.user_id).filter(Boolean))
          ];
          const { data: profiles } = uids.length > 0 ? await sb.from('profiles').select('id, full_name, email, phone').in('id', uids) : {
            data: []
          };
          const pm = {};
          for (const p of profiles || [])pm[p.id] = p;
          return {
            branch: branchR.data,
            motorcycles: motosR.data || [],
            accessories: accR.data || [],
            door_codes: codesR.data || [],
            active_bookings: bb.map((b)=>({
                ...b,
                customer: pm[b.user_id] || null
              }))
          };
        } catch  {
          return {
            error: 'Table not available',
            data: []
          };
        }
      }
    default:
      return null;
  }
}
