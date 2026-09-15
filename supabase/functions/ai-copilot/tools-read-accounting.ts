// Read tools: Accounting — assets, liabilities, depreciation, VAT, tax, cash register, flexi
export async function execReadAccounting(name, input, sb) {
  switch(name){
    case 'get_accounting_entries':
      {
        const limit = input.limit || 30;
        let q = sb.from('accounting_entries').select('*').order('created_at', {
          ascending: false
        }).limit(limit);
        if (input.type) q = q.eq('type', input.type);
        const { data } = await q;
        const total = (data || []).reduce((s, e)=>s + (e.amount || 0), 0);
        return {
          entries: data || [],
          count: (data || []).length,
          total
        };
      }
    case 'get_cash_register':
      {
        const limit = input.limit || 30;
        const [{ data }, allR] = await Promise.all([
          sb.from('cash_register').select('*').order('date', {
            ascending: false
          }).limit(limit),
          sb.from('cash_register').select('type, amount')
        ]);
        const balance = (allR.data || []).reduce((s, e)=>s + (e.type === 'expense' ? -(e.amount || 0) : e.amount || 0), 0);
        return {
          entries: data || [],
          count: (data || []).length,
          balance_note: 'zůstatek = příjmy − výdaje za celou historii',
          balance
        };
      }
    case 'get_long_term_assets':
      {
        const { data } = await sb.from('acc_long_term_assets').select('*, motorcycles(model, spz)').order('name');
        const totalValue = (data || []).reduce((s, a)=>s + (a.purchase_price || 0), 0);
        const totalResidual = (data || []).reduce((s, a)=>s + (a.residual_value || 0), 0);
        return {
          assets: data || [],
          count: (data || []).length,
          total_purchase_value: totalValue,
          total_residual_value: totalResidual
        };
      }
    case 'get_short_term_assets':
      {
        const { data } = await sb.from('acc_short_term_assets').select('*').order('name');
        const total = (data || []).reduce((s, a)=>s + (a.amount || 0), 0);
        return {
          assets: data || [],
          count: (data || []).length,
          total
        };
      }
    case 'get_depreciation':
      {
        const year = input.year || new Date().getFullYear();
        const { data } = await sb.from('acc_depreciation_entries').select('*, acc_long_term_assets(name)').eq('year', year).order('created_at');
        const totalDepreciation = (data || []).reduce((s, d)=>s + (d.annual_amount || d.annual_depreciation || 0), 0);
        return {
          entries: data || [],
          count: (data || []).length,
          year,
          total_depreciation: totalDepreciation
        };
      }
    case 'get_liabilities':
      {
        let q = sb.from('acc_liabilities').select('*').order('due_date');
        if (input.unpaid_only) q = q.neq('status', 'paid');
        const { data } = await q;
        const remaining = (l)=>(l.amount || 0) - (l.paid_amount || 0);
        const total = (data || []).reduce((s, l)=>s + (l.amount || 0), 0);
        const today = new Date().toISOString().slice(0, 10);
        const overdue = (data || []).filter((l)=>l.status !== 'paid' && remaining(l) > 0 && l.due_date && l.due_date < today);
        return {
          liabilities: data || [],
          count: (data || []).length,
          total,
          total_unpaid_remaining: (data || []).filter((l)=>l.status !== 'paid').reduce((s, l)=>s + remaining(l), 0),
          overdue_count: overdue.length,
          overdue_total: overdue.reduce((s, l)=>s + remaining(l), 0)
        };
      }
    case 'get_vat_returns':
      {
        const { data } = await sb.from('acc_vat_returns').select('*').order('period', {
          ascending: false
        }).limit(8);
        return {
          returns: data || [],
          count: (data || []).length
        };
      }
    case 'get_tax_returns':
      {
        const { data } = await sb.from('acc_tax_returns').select('*').order('year', {
          ascending: false
        }).limit(5);
        return {
          returns: data || [],
          count: (data || []).length
        };
      }
    case 'get_tax_records':
      {
        const limit = input.limit || 30;
        const { data } = await sb.from('tax_records').select('*').order('created_at', {
          ascending: false
        }).limit(limit);
        return {
          records: data || [],
          count: (data || []).length
        };
      }
    case 'get_flexi_reports':
      {
        const { data } = await sb.from('flexi_reports').select('*').order('created_at', {
          ascending: false
        }).limit(20);
        const byStatus = {};
        for (const r of data || []){
          const s = r.status;
          byStatus[s] = (byStatus[s] || 0) + 1;
        }
        return {
          reports: data || [],
          count: (data || []).length,
          by_status: byStatus
        };
      }
    default:
      return null;
  }
}
