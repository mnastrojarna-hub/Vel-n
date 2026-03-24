// Write tools: Bookings, Fleet, Customers, SOS
import type { SB } from './tools-constants.ts'

// deno-lint-ignore no-explicit-any
type R = Record<string, any>

export async function execWriteCore(name: string, input: R, sb: SB, dryRun: boolean): Promise<unknown> {
  switch (name) {
    // === BOOKING ===
    case 'update_booking_status': {
      const { booking_id, new_status, reason } = input
      const { data: booking } = await sb.from('bookings').select('id, status, payment_status, user_id, moto_id, total_price, start_date, end_date').eq('id', booking_id).single()
      if (!booking) return { error: 'Rezervace nenalezena' }
      const summary = `Změna stavu rezervace z "${booking.status}" na "${new_status}"${reason ? ` (důvod: ${reason})` : ''}`
      if (dryRun) return { status: 'preview', summary, current: booking }
      const update: R = { status: new_status }
      if (new_status === 'cancelled') { update.cancelled_at = new Date().toISOString(); update.cancellation_reason = reason || 'AI Copilot' }
      if (new_status === 'completed') update.returned_at = new Date().toISOString()
      if (new_status === 'active') update.picked_up_at = new Date().toISOString()
      const { error } = await sb.from('bookings').update(update).eq('id', booking_id)
      if (error) return { error: error.message }
      return { status: 'executed', summary, booking_id }
    }

    case 'update_booking_details': {
      const { booking_id, ...fields } = input
      const { data: booking } = await sb.from('bookings').select('id, notes, start_date, end_date').eq('id', booking_id).single()
      if (!booking) return { error: 'Rezervace nenalezena' }
      const changes = Object.keys(fields).filter(k => fields[k] !== undefined)
      const summary = `Úprava rezervace: ${changes.join(', ')}`
      if (dryRun) return { status: 'preview', summary, current: booking, changes: fields }
      const { error } = await sb.from('bookings').update(fields).eq('id', booking_id)
      if (error) return { error: error.message }
      return { status: 'executed', summary, booking_id }
    }

    case 'confirm_booking_payment': {
      const { booking_id, method } = input
      const { data: booking } = await sb.from('bookings').select('id, status, payment_status, total_price').eq('id', booking_id).single()
      if (!booking) return { error: 'Rezervace nenalezena' }
      const summary = `Potvrzení platby ${booking.total_price} Kč (${method || 'neznámá metoda'})`
      if (dryRun) return { status: 'preview', summary, current: booking }
      const { error } = await sb.rpc('confirm_payment', { p_booking_id: booking_id, p_method: method || 'cash' })
      if (error) return { error: error.message }
      return { status: 'executed', summary, booking_id }
    }

    // === FLEET ===
    case 'update_motorcycle': {
      const { motorcycle_id, ...fields } = input
      const { data: moto } = await sb.from('motorcycles').select('id, model, brand, spz, status, mileage, branch_id').eq('id', motorcycle_id).single()
      if (!moto) return { error: 'Motorka nenalezena' }
      const changes = Object.keys(fields).filter(k => fields[k] !== undefined)
      const summary = `Úprava motorky ${moto.model} (${moto.spz}): ${changes.join(', ')}`
      if (dryRun) return { status: 'preview', summary, current: moto, changes: fields }
      const { error } = await sb.from('motorcycles').update(fields).eq('id', motorcycle_id)
      if (error) return { error: error.message }
      return { status: 'executed', summary, motorcycle_id }
    }

    case 'update_motorcycle_pricing': {
      const { motorcycle_id, ...prices } = input
      const { data: moto } = await sb.from('motorcycles').select('id, model, spz, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun').eq('id', motorcycle_id).single()
      if (!moto) return { error: 'Motorka nenalezena' }
      const summary = `Úprava ceníku ${moto.model} (${moto.spz})`
      if (dryRun) return { status: 'preview', summary, current: moto, new_prices: prices }
      const { error } = await sb.from('motorcycles').update(prices).eq('id', motorcycle_id)
      if (error) return { error: error.message }
      return { status: 'executed', summary, motorcycle_id }
    }

    case 'update_branch': {
      const { branch_id, ...fields } = input
      const { data: branch } = await sb.from('branches').select('id, name, is_open, type').eq('id', branch_id).single()
      if (!branch) return { error: 'Pobočka nenalezena' }
      const changes = Object.keys(fields).filter(k => fields[k] !== undefined)
      const summary = `Úprava pobočky "${branch.name}": ${changes.join(', ')}`
      if (dryRun) return { status: 'preview', summary, current: branch, changes: fields }
      const { error } = await sb.from('branches').update(fields).eq('id', branch_id)
      if (error) return { error: error.message }
      return { status: 'executed', summary, branch_id }
    }

    case 'update_branch_accessories': {
      const { branch_id, type, size, quantity } = input
      const summary = `Nastavení příslušenství: ${type} ${size} = ${quantity} ks`
      if (dryRun) return { status: 'preview', summary, data: { branch_id, type, size, quantity } }
      const { error } = await sb.from('branch_accessories').upsert({ branch_id, type, size, quantity }, { onConflict: 'branch_id,type,size' })
      if (error) return { error: error.message }
      return { status: 'executed', summary }
    }

    // === CUSTOMER ===
    case 'update_customer': {
      const { customer_id, ...fields } = input
      const { data: profile } = await sb.from('profiles').select('id, full_name, email, phone, is_blocked').eq('id', customer_id).single()
      if (!profile) return { error: 'Zákazník nenalezen' }
      const changes = Object.keys(fields).filter(k => fields[k] !== undefined)
      const summary = `Úprava zákazníka "${profile.full_name}": ${changes.join(', ')}`
      if (dryRun) return { status: 'preview', summary, current: profile, changes: fields }
      if (fields.is_blocked === true) { fields.blocked_at = new Date().toISOString() }
      if (fields.is_blocked === false) { fields.blocked_at = null; fields.blocked_reason = null }
      const { error } = await sb.from('profiles').update(fields).eq('id', customer_id)
      if (error) return { error: error.message }
      return { status: 'executed', summary, customer_id }
    }

    case 'send_customer_message': {
      const { customer_id, content, channel } = input
      const { data: profile } = await sb.from('profiles').select('id, full_name, phone, email').eq('id', customer_id).single()
      if (!profile) return { error: 'Zákazník nenalezen' }
      const ch = channel || 'in_app'
      const summary = `Odeslání zprávy zákazníkovi "${profile.full_name}" přes ${ch}`
      if (dryRun) return { status: 'preview', summary, recipient: profile, channel: ch, content_preview: content.slice(0, 100) }
      const { error } = await sb.from('admin_messages').insert({ user_id: customer_id, type: 'info', content, created_at: new Date().toISOString() })
      if (error) return { error: error.message }
      return { status: 'executed', summary, customer_id }
    }

    // === SOS ===
    case 'update_sos_incident': {
      const { incident_id, ...fields } = input
      const { data: inc } = await sb.from('sos_incidents').select('id, title, status, severity').eq('id', incident_id).single()
      if (!inc) return { error: 'SOS incident nenalezen' }
      const changes = Object.keys(fields).filter(k => fields[k] !== undefined)
      const summary = `Úprava SOS "${inc.title}": ${changes.join(', ')}`
      if (dryRun) return { status: 'preview', summary, current: inc, changes: fields }
      if (fields.status === 'resolved') fields.resolved_at = new Date().toISOString()
      const { error } = await sb.from('sos_incidents').update(fields).eq('id', incident_id)
      if (error) return { error: error.message }
      return { status: 'executed', summary, incident_id }
    }

    default: return null
  }
}
