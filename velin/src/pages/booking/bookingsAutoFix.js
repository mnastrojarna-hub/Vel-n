import { supabase } from '../../lib/supabase'
import { generateFinalInvoice } from '../../lib/invoiceUtils'

function localIso(d) {
  const y = d.getFullYear(), m = String(d.getMonth() + 1).padStart(2, '0'), day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

export async function autoCancelStale() {
  try {
    const tenMinAgo = new Date(Date.now() - 10 * 60 * 1000).toISOString()
    const { data: stale } = await supabase
      .from('bookings').select('id')
      .eq('status', 'pending').eq('payment_status', 'unpaid')
      .lt('created_at', tenMinAgo)
    if (stale && stale.length > 0) {
      await supabase.from('bookings')
        .update({ status: 'cancelled', cancellation_reason: 'Automaticky zrušeno — nezaplaceno do 10 minut' })
        .in('id', stale.map(b => b.id))
    }
  } catch (e) { console.error('[AutoCancel]', e) }
}

export async function autoActivateReserved() {
  try {
    const today = localIso(new Date())
    const { data: ready } = await supabase.from('bookings').select('id')
      .eq('status', 'reserved').eq('payment_status', 'paid')
      .lte('start_date', today)
    if (ready && ready.length > 0) {
      await supabase.from('bookings')
        .update({ status: 'active', picked_up_at: new Date().toISOString() })
        .in('id', ready.map(b => b.id))
      console.log('[AutoActivate]', ready.length, 'bookings activated')
    }
  } catch (e) { console.error('[AutoActivate]', e) }
}

export async function autoFixPendingPaid() {
  try {
    const today = localIso(new Date())
    const { data: stuck } = await supabase.from('bookings').select('id, start_date')
      .eq('status', 'pending').eq('payment_status', 'paid')
    if (stuck && stuck.length > 0) {
      for (const b of stuck) {
        const startLocal = b.start_date ? b.start_date.slice(0, 10) : ''
        if (startLocal <= today) {
          await supabase.from('bookings').update({ status: 'active', picked_up_at: new Date().toISOString() }).eq('id', b.id)
        } else {
          await supabase.from('bookings').update({ status: 'reserved', confirmed_at: new Date().toISOString() }).eq('id', b.id)
        }
      }
      console.log('[AutoFixPendingPaid]', stuck.length, 'bookings fixed')
    }
  } catch (e) { console.error('[AutoFixPendingPaid]', e) }
}

export async function autoGenerateKF() {
  try {
    const today = localIso(new Date())
    const { data: expired } = await supabase.from('bookings').select('id, status, end_date')
      .in('status', ['active', 'reserved', 'completed']).eq('payment_status', 'paid')
      .lt('end_date', today)
    if (!expired || expired.length === 0) return
    for (const b of expired) {
      const { data: kf } = await supabase.from('invoices').select('id')
        .eq('booking_id', b.id).eq('type', 'final').limit(1)
      if (kf && kf.length > 0) continue
      try { await generateFinalInvoice(b.id) } catch (e) { console.error('[AutoKF]', b.id, e.message) }
    }
  } catch (e) { console.error('[AutoKF]', e) }
}
