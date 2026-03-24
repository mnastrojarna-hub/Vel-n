// Write tools: Finance, Service, HR, E-shop, CMS, Tester
import type { SB } from './tools-constants.ts'

// deno-lint-ignore no-explicit-any
type R = Record<string, any>

export async function execWriteOps(name: string, input: R, sb: SB, dryRun: boolean): Promise<unknown> {
  switch (name) {
    // === FINANCE ===
    case 'update_invoice_status': {
      const { invoice_id, status, paid_date } = input
      const { data: inv } = await sb.from('invoices').select('id, number, status, total').eq('id', invoice_id).single()
      if (!inv) return { error: 'Faktura nenalezena' }
      const summary = `Změna stavu faktury ${inv.number}: "${inv.status}" → "${status}"`
      if (dryRun) return { status: 'preview', summary, current: inv }
      const upd: R = { status }
      if (paid_date) upd.paid_date = paid_date
      const { error } = await sb.from('invoices').update(upd).eq('id', invoice_id)
      if (error) return { error: error.message }
      return { status: 'executed', summary }
    }

    case 'create_accounting_entry': {
      const { type, amount, description, category } = input
      const summary = `Vytvoření účetního záznamu: ${type} ${amount} Kč — ${description || 'bez popisu'}`
      if (dryRun) return { status: 'preview', summary, data: input }
      const { error } = await sb.from('accounting_entries').insert({ type, amount, description, category, created_at: new Date().toISOString() })
      if (error) return { error: error.message }
      return { status: 'executed', summary }
    }

    case 'match_delivery_note': {
      const { delivery_note_id, invoice_id, confidence } = input
      const summary = `Párování dodacího listu s fakturou (confidence: ${confidence || 'manual'})`
      if (dryRun) return { status: 'preview', summary, data: input }
      const now = new Date().toISOString()
      const [r1, r2] = await Promise.all([
        sb.from('delivery_notes').update({ matched_invoice_id: invoice_id, match_method: 'ai', match_confidence: confidence || 1, matched_at: now }).eq('id', delivery_note_id),
        sb.from('invoices').update({ matched_delivery_note_id: delivery_note_id }).eq('id', invoice_id),
      ])
      if (r1.error) return { error: r1.error.message }
      if (r2.error) return { error: r2.error.message }
      return { status: 'executed', summary }
    }

    // === SERVICE ===
    case 'create_service_order': {
      const { moto_id, description, status: st } = input
      const { data: moto } = await sb.from('motorcycles').select('id, model, spz').eq('id', moto_id).single()
      if (!moto) return { error: 'Motorka nenalezena' }
      const summary = `Vytvoření servisní objednávky pro ${moto.model} (${moto.spz})`
      if (dryRun) return { status: 'preview', summary, motorcycle: moto }
      const { data, error } = await sb.from('service_orders').insert({ moto_id, description, status: st || 'pending', created_at: new Date().toISOString() }).select().single()
      if (error) return { error: error.message }
      return { status: 'executed', summary, order_id: data?.id }
    }

    case 'update_service_order': {
      const { order_id, status: st, notes } = input
      const { data: order } = await sb.from('service_orders').select('id, status, moto_id').eq('id', order_id).single()
      if (!order) return { error: 'Servisní objednávka nenalezena' }
      const summary = `Změna stavu servisní objednávky: "${order.status}" → "${st || order.status}"`
      if (dryRun) return { status: 'preview', summary, current: order }
      const upd: R = {}
      if (st) upd.status = st
      if (notes) upd.notes = notes
      const { error } = await sb.from('service_orders').update(upd).eq('id', order_id)
      if (error) return { error: error.message }
      return { status: 'executed', summary }
    }

    case 'create_maintenance_log': {
      const { moto_id, service_type, description, cost, technician_id, labor_hours } = input
      const { data: moto } = await sb.from('motorcycles').select('id, model, spz, mileage').eq('id', moto_id).single()
      if (!moto) return { error: 'Motorka nenalezena' }
      const summary = `Zápis servisu ${service_type} pro ${moto.model} (${moto.spz})${cost ? ` — ${cost} Kč` : ''}`
      if (dryRun) return { status: 'preview', summary, motorcycle: moto }
      const { error } = await sb.from('maintenance_log').insert({
        moto_id, service_type, description, cost: cost || 0, technician_id,
        labor_hours: labor_hours || 0, km_at_service: moto.mileage,
        service_date: new Date().toISOString().slice(0, 10),
      })
      if (error) return { error: error.message }
      return { status: 'executed', summary }
    }

    // === HR ===
    case 'create_attendance': {
      const { employee_id, date, check_in, check_out, status: st } = input
      const summary = `Zápis docházky: ${date} — ${st}`
      if (dryRun) return { status: 'preview', summary, data: input }
      const { error } = await sb.from('emp_attendance').upsert({ employee_id, date, check_in, check_out, status: st }, { onConflict: 'employee_id,date' })
      if (error) return { error: error.message }
      return { status: 'executed', summary }
    }

    case 'manage_vacation': {
      const { employee_id, start_date, end_date, type: vType, status: vStatus, action } = input
      if (action === 'create') {
        const summary = `Vytvoření žádosti o dovolenou: ${start_date} — ${end_date} (${vType || 'vacation'})`
        if (dryRun) return { status: 'preview', summary, data: input }
        const days = start_date && end_date ? Math.ceil((new Date(end_date).getTime() - new Date(start_date).getTime()) / 86400000) + 1 : 1
        const { error } = await sb.from('emp_vacations').insert({ employee_id, start_date, end_date, days, type: vType || 'vacation', status: 'pending' })
        if (error) return { error: error.message }
        return { status: 'executed', summary }
      }
      return { error: `Nepodporovaná akce: ${action}` }
    }

    case 'manage_shifts': {
      const { employee_id, date, shift_type, branch_id } = input
      const summary = `Plánování směny: ${date} — ${shift_type}`
      if (dryRun) return { status: 'preview', summary, data: input }
      const { error } = await sb.from('emp_shifts').upsert({ employee_id, date, shift_type, branch_id }, { onConflict: 'employee_id,date' })
      if (error) return { error: error.message }
      return { status: 'executed', summary }
    }

    // === ESHOP ===
    case 'update_shop_order': {
      const { order_id, status: st, notes } = input
      const { data: order } = await sb.from('shop_orders').select('id, order_number, status').eq('id', order_id).single()
      if (!order) return { error: 'Objednávka nenalezena' }
      const summary = `Změna stavu objednávky ${order.order_number}: "${order.status}" → "${st}"`
      if (dryRun) return { status: 'preview', summary, current: order }
      const upd: R = { status: st }
      if (notes) upd.notes = notes
      const { error } = await sb.from('shop_orders').update(upd).eq('id', order_id)
      if (error) return { error: error.message }
      return { status: 'executed', summary }
    }

    case 'update_product': {
      const { product_id, ...fields } = input
      const { data: prod } = await sb.from('products').select('id, name, price, stock_quantity').eq('id', product_id).single()
      if (!prod) return { error: 'Produkt nenalezen' }
      const changes = Object.keys(fields).filter(k => fields[k] !== undefined)
      const summary = `Úprava produktu "${prod.name}": ${changes.join(', ')}`
      if (dryRun) return { status: 'preview', summary, current: prod, changes: fields }
      const { error } = await sb.from('products').update(fields).eq('id', product_id)
      if (error) return { error: error.message }
      return { status: 'executed', summary }
    }

    case 'create_promo_code': {
      const { code, type: pType, discount_value, max_uses, valid_to } = input
      const summary = `Vytvoření promo kódu "${code}": ${pType} ${discount_value}${pType === 'percent' ? '%' : ' Kč'}`
      if (dryRun) return { status: 'preview', summary, data: input }
      const { error } = await sb.from('promo_codes').insert({ code, type: pType, discount_value, max_uses: max_uses || 100, valid_to, is_active: true })
      if (error) return { error: error.message }
      return { status: 'executed', summary }
    }

    // === CMS ===
    case 'update_app_setting': {
      const { key, value } = input
      const summary = `Změna nastavení "${key}"`
      if (dryRun) return { status: 'preview', summary, key, new_value: value }
      let parsedValue
      try { parsedValue = JSON.parse(value) } catch { parsedValue = value }
      const { error } = await sb.from('app_settings').update({ value: parsedValue }).eq('key', key)
      if (error) return { error: error.message }
      return { status: 'executed', summary }
    }

    case 'update_feature_flag': {
      const { flag_name, enabled } = input
      const summary = `Feature flag "${flag_name}": ${enabled ? 'ZAPNUTO' : 'VYPNUTO'}`
      if (dryRun) return { status: 'preview', summary }
      const { error } = await sb.from('feature_flags').update({ enabled }).eq('name', flag_name)
      if (error) return { error: error.message }
      return { status: 'executed', summary }
    }

    // === TESTER ===
    case 'generate_test_report': {
      const { scope, depth } = input
      const summary = `Testovací report: ${scope} (${depth || 'standard'})`
      // Tester always runs (no dryRun needed - read-only analysis)
      const checks: R[] = []
      if (scope === 'all' || scope === 'bookings') {
        const { count: orphaned } = await sb.from('bookings').select('id', { count: 'exact', head: true }).is('user_id', null)
        const { count: noMoto } = await sb.from('bookings').select('id', { count: 'exact', head: true }).is('moto_id', null)
        checks.push({ area: 'bookings', orphaned_bookings: orphaned || 0, no_moto_bookings: noMoto || 0 })
      }
      if (scope === 'all' || scope === 'fleet') {
        const { count: noPrice } = await sb.from('motorcycles').select('id', { count: 'exact', head: true }).is('price_weekday', null)
        const { count: noBranch } = await sb.from('motorcycles').select('id', { count: 'exact', head: true }).is('branch_id', null)
        checks.push({ area: 'fleet', no_price: noPrice || 0, no_branch: noBranch || 0 })
      }
      if (scope === 'all' || scope === 'finance') {
        const { count: unpaid } = await sb.from('invoices').select('id', { count: 'exact', head: true }).eq('status', 'unpaid')
        checks.push({ area: 'finance', unpaid_invoices: unpaid || 0 })
      }
      return { status: 'executed', summary, checks }
    }

    case 'check_data_integrity': {
      const { table } = input
      const issues: R[] = []
      if (table === 'all' || table === 'bookings') {
        const { data: dups } = await sb.from('bookings').select('id, user_id, moto_id, start_date, end_date, status').in('status', ['active', 'reserved']).order('moto_id')
        const seen: R = {}
        for (const b of (dups || [])) { const k = `${b.moto_id}_${b.start_date}`; if (seen[k]) issues.push({ type: 'overlap', table: 'bookings', ids: [seen[k], b.id] }); seen[k] = b.id }
      }
      if (table === 'all' || table === 'profiles') {
        const { count: noName } = await sb.from('profiles').select('id', { count: 'exact', head: true }).is('full_name', null)
        if ((noName || 0) > 0) issues.push({ type: 'missing_data', table: 'profiles', field: 'full_name', count: noName })
      }
      return { status: 'executed', summary: `Kontrola integrity: ${table}`, issues, issues_count: issues.length }
    }

    default: return null
  }
}
