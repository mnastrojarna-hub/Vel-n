// Read tools: Accounting — assets, liabilities, depreciation, VAT, tax, cash register, flexi
import type { SB } from './tools-constants.ts'

// deno-lint-ignore no-explicit-any
type R = Record<string, any>

export async function execReadAccounting(name: string, input: R, sb: SB): Promise<unknown> {
  switch (name) {
    case 'get_accounting_entries': {
      const limit = (input.limit as number) || 30
      let q = sb.from('accounting_entries').select('*').order('created_at', { ascending: false }).limit(limit)
      if (input.type) q = q.eq('type', input.type)
      const { data } = await q
      const total = (data || []).reduce((s: number, e: R) => s + (e.amount || 0), 0)
      return { entries: data || [], count: (data || []).length, total }
    }

    case 'get_cash_register': {
      const limit = (input.limit as number) || 30
      const { data } = await sb.from('cash_register').select('*').order('created_at', { ascending: false }).limit(limit)
      const balance = (data || []).reduce((s: number, e: R) => s + (e.amount || 0), 0)
      return { entries: data || [], count: (data || []).length, balance }
    }

    case 'get_long_term_assets': {
      const { data } = await sb.from('acc_long_term_assets').select('*, motorcycles(model, spz)').order('name')
      const totalValue = (data || []).reduce((s: number, a: R) => s + (a.purchase_price || 0), 0)
      const totalResidual = (data || []).reduce((s: number, a: R) => s + (a.residual_value || 0), 0)
      return { assets: data || [], count: (data || []).length, total_purchase_value: totalValue, total_residual_value: totalResidual }
    }

    case 'get_short_term_assets': {
      const { data } = await sb.from('acc_short_term_assets').select('*').order('name')
      const total = (data || []).reduce((s: number, a: R) => s + (a.amount || 0), 0)
      return { assets: data || [], count: (data || []).length, total }
    }

    case 'get_depreciation': {
      const year = (input.year as number) || new Date().getFullYear()
      const { data } = await sb.from('acc_depreciation_entries').select('*, acc_long_term_assets(name)').eq('year', year).order('created_at')
      const totalDepreciation = (data || []).reduce((s: number, d: R) => s + (d.annual_depreciation || 0), 0)
      return { entries: data || [], count: (data || []).length, year, total_depreciation: totalDepreciation }
    }

    case 'get_liabilities': {
      let q = sb.from('acc_liabilities').select('*').order('due_date')
      if (input.unpaid_only) q = q.eq('is_paid', false)
      const { data } = await q
      const total = (data || []).reduce((s: number, l: R) => s + (l.amount || 0), 0)
      const overdue = (data || []).filter((l: R) => !l.is_paid && l.due_date && l.due_date < new Date().toISOString().slice(0, 10))
      return { liabilities: data || [], count: (data || []).length, total, overdue_count: overdue.length, overdue_total: overdue.reduce((s: number, l: R) => s + (l.amount || 0), 0) }
    }

    case 'get_vat_returns': {
      const { data } = await sb.from('acc_vat_returns').select('*').order('period', { ascending: false }).limit(8)
      return { returns: data || [], count: (data || []).length }
    }

    case 'get_tax_returns': {
      const { data } = await sb.from('acc_tax_returns').select('*').order('year', { ascending: false }).limit(5)
      return { returns: data || [], count: (data || []).length }
    }

    case 'get_tax_records': {
      const limit = (input.limit as number) || 30
      const { data } = await sb.from('tax_records').select('*').order('created_at', { ascending: false }).limit(limit)
      return { records: data || [], count: (data || []).length }
    }

    case 'get_flexi_reports': {
      const { data } = await sb.from('flexi_reports').select('*').order('created_at', { ascending: false }).limit(20)
      const byStatus: R = {}
      for (const r of (data || [])) { const s = r.status; byStatus[s] = (byStatus[s] || 0) + 1 }
      return { reports: data || [], count: (data || []).length, by_status: byStatus }
    }

    default: return null
  }
}
