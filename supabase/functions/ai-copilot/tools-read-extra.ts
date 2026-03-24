// Read tools: Contracts, POs, Booking extras, Complaints, Payment methods, Service parts, Locations
import type { SB } from './tools-constants.ts'

// deno-lint-ignore no-explicit-any
type R = Record<string, any>

export async function execReadExtra(name: string, input: R, sb: SB): Promise<unknown> {
  switch (name) {
    case 'get_contracts': {
      const limit = (input.limit as number) || 20
      let q = sb.from('contracts').select('*, acc_employees(name)').order('created_at', { ascending: false }).limit(limit)
      if (input.status) q = q.eq('status', input.status)
      if (input.contract_type) q = q.eq('contract_type', input.contract_type)
      const { data } = await q
      return { contracts: data || [], count: (data || []).length }
    }

    case 'get_purchase_orders': {
      const limit = (input.limit as number) || 20
      let q = sb.from('purchase_orders').select('*, purchase_order_items(*)').order('created_at', { ascending: false }).limit(limit)
      if (input.status) q = q.eq('status', input.status)
      const { data } = await q
      return { orders: data || [], count: (data || []).length }
    }

    case 'get_booking_extras': {
      const bookingId = input.booking_id as string
      if (!bookingId) return { error: 'booking_id je povinný' }
      const [extrasR, catalogR] = await Promise.all([
        sb.from('booking_extras').select('*, extras_catalog(name, price)').eq('booking_id', bookingId),
        sb.from('extras_catalog').select('*').order('name'),
      ])
      return { extras: extrasR.data || [], catalog: catalogR.data || [] }
    }

    case 'get_booking_complaints': {
      const limit = (input.limit as number) || 20
      let q = sb.from('booking_complaints').select('*, profiles(full_name, email)').order('created_at', { ascending: false }).limit(limit)
      if (input.status) q = q.eq('status', input.status)
      const { data } = await q
      return { complaints: data || [], count: (data || []).length }
    }

    case 'get_booking_cancellations': {
      const limit = (input.limit as number) || 20
      const { data } = await sb.from('booking_cancellations').select('*').order('created_at', { ascending: false }).limit(limit)
      const totalRefund = (data || []).reduce((s: number, c: R) => s + (c.refund_amount || 0), 0)
      return { cancellations: data || [], count: (data || []).length, total_refunded: totalRefund }
    }

    case 'get_payment_methods': {
      const userId = input.user_id as string
      let q = sb.from('payment_methods').select('*')
      if (userId) q = q.eq('user_id', userId)
      q = q.order('created_at', { ascending: false }).limit(50)
      const { data } = await q
      return { methods: data || [], count: (data || []).length }
    }

    case 'get_service_parts': {
      const scheduleId = input.schedule_id as string
      let q = sb.from('service_parts').select('*, inventory(name, sku, stock, min_stock), maintenance_schedules(schedule_type, motorcycle_id)')
      if (scheduleId) q = q.eq('schedule_id', scheduleId)
      const { data } = await q
      return { parts: data || [], count: (data || []).length }
    }

    case 'get_moto_locations': {
      const { data } = await sb.from('moto_locations').select('*, motorcycles(model, spz)').order('updated_at', { ascending: false }).limit(50)
      return { locations: data || [], count: (data || []).length }
    }

    case 'get_auto_order_rules': {
      const { data } = await sb.from('auto_order_rules').select('*, inventory(name, sku)').order('created_at', { ascending: false })
      return { rules: data || [], count: (data || []).length }
    }

    case 'get_notification_log': {
      const limit = (input.limit as number) || 30
      const { data } = await sb.from('notification_log').select('*').order('created_at', { ascending: false }).limit(limit)
      return { notifications: data || [], count: (data || []).length }
    }

    case 'get_message_templates': {
      const [smsR, emailR] = await Promise.all([
        sb.from('message_templates_sms').select('*').order('slug'),
        sb.from('email_templates').select('*').order('slug'),
      ])
      return { sms_templates: smsR.data || [], email_templates: emailR.data || [] }
    }

    case 'get_accessory_types': {
      const { data } = await sb.from('accessory_types').select('*').order('sort_order')
      return { types: data || [], count: (data || []).length }
    }

    case 'get_performance_stats': {
      const [motoR, branchR] = await Promise.all([
        sb.from('moto_performance').select('*').order('updated_at', { ascending: false }).limit(30),
        sb.from('branch_performance').select('*').order('updated_at', { ascending: false }).limit(10),
      ])
      return { moto_performance: motoR.data || [], branch_performance: branchR.data || [] }
    }

    default: return null
  }
}
