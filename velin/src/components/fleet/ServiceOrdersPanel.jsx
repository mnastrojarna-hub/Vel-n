import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Card from '../ui/Card'

/* ═══ SERVISNÍ ZAKÁZKY — pending/in_service objednávky s možností dokončit ═══ */
export default function ServiceOrdersPanel({ motoId, logAudit }) {
  const [orders, setOrders] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => { load() }, [motoId])

  async function load() {
    setLoading(true)
    const { data } = await supabase.from('service_orders')
      .select('id, type, status, notes, km, created_at, maintenance_log_id')
      .eq('moto_id', motoId)
      .in('status', ['pending', 'in_service'])
      .order('created_at', { ascending: false })
    setOrders(data || [])
    setLoading(false)
  }

  async function completeOrder(order) {
    const now = new Date().toISOString()
    await supabase.from('service_orders')
      .update({ status: 'completed', completed_at: now })
      .eq('id', order.id)
    // Also complete linked maintenance_log if exists
    if (order.maintenance_log_id) {
      await supabase.from('maintenance_log')
        .update({ status: 'completed', completed_date: now.slice(0, 10) })
        .eq('id', order.maintenance_log_id)
    }
    await logAudit?.('service_order_completed', { order_id: order.id, moto_id: motoId })
    await load()
  }

  async function cancelOrder(order) {
    await supabase.from('service_orders')
      .update({ status: 'cancelled' })
      .eq('id', order.id)
    await logAudit?.('service_order_cancelled', { order_id: order.id, moto_id: motoId })
    await load()
  }

  if (loading) return null
  if (!orders.length) return null

  const fmtDate = d => d ? new Date(d).toLocaleDateString('cs-CZ') : '—'
  const daysSince = d => d ? Math.floor((Date.now() - new Date(d).getTime()) / 86400000) : 0

  return (
    <Card>
      <h3 className="text-sm font-extrabold uppercase tracking-widest mb-3" style={{ color: '#1a2e22' }}>
        Otevřené servisní zakázky ({orders.length})
      </h3>
      <div className="space-y-2">
        {orders.map(o => {
          const days = daysSince(o.created_at)
          const isOld = days > 7
          return (
            <div key={o.id} className="flex items-center gap-3 p-3 rounded-lg"
              style={{ background: isOld ? '#fef2f2' : '#fef3c7', border: `1px solid ${isOld ? '#fca5a5' : '#fde68a'}` }}>
              <div className="flex-1">
                <span className="font-bold text-sm" style={{ color: '#0f1a14' }}>{o.type || 'Servis'}</span>
                <span className="text-xs ml-2" style={{ color: '#6b7280' }}>
                  {fmtDate(o.created_at)} ({days} {days === 1 ? 'den' : days < 5 ? 'dny' : 'dní'})
                </span>
                {o.km > 0 && <span className="text-xs ml-2" style={{ color: '#6b7280' }}>{o.km.toLocaleString('cs-CZ')} km</span>}
                <span className="text-xs font-bold ml-2" style={{
                  padding: '1px 6px', borderRadius: 4,
                  background: o.status === 'in_service' ? '#dbeafe' : '#fef3c7',
                  color: o.status === 'in_service' ? '#1e40af' : '#b45309',
                }}>
                  {{ pending: 'Čeká', in_service: 'V servisu' }[o.status] || o.status}
                </span>
                {isOld && <span className="text-xs font-bold ml-2" style={{ color: '#dc2626' }}>Otevřeno &gt;7 dní!</span>}
              </div>
              <button onClick={() => completeOrder(o)}
                className="rounded-btn text-xs font-extrabold uppercase cursor-pointer"
                style={{ padding: '4px 12px', background: '#74FB71', color: '#1a2e22', border: 'none' }}>
                Dokončit
              </button>
              <button onClick={() => cancelOrder(o)}
                className="text-xs font-bold cursor-pointer"
                style={{ color: '#dc2626', background: 'none', border: 'none' }}>
                Zrušit
              </button>
            </div>
          )
        })}
      </div>
    </Card>
  )
}
