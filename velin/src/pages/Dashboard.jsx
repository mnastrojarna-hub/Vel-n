import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { debugAction, debugLog, debugError } from '../lib/debugLog'
import { useDebugMode } from '../hooks/useDebugMode'
import { isRevenueEntry, isTestInvoice, isVoidInvoice, summarizeInvoices, INVOICE_PAID_TYPES, INVOICE_RECEIVED_TYPES } from '../lib/revenueUtils'
import AiDashboardWidget from '../components/ai/AiDashboardWidget'
import Stat from '../components/ui/Stat'
import ExportBar from '../components/ui/ExportBar'
import BannerEditor from './DashboardBannerEditor'
import {
  WidgetCard, fmtKc, RevenueChartCard, BookingRowsCard, ModificationsCard, PaymentsCard,
  ShopOrdersCard, ServiceCard, StkCard, EmailsCard, DocsCard, VisitorsCard, AiConvCard,
  MessagesCard, SosCard,
} from './dashboard/DashboardWidgets'

const MONTHS = ['Led', 'Úno', 'Bře', 'Dub', 'Kvě', 'Čvn', 'Čvc', 'Srp', 'Zář', 'Říj', 'Lis', 'Pro']
const MONTHS_FULL = ['Leden', 'Únor', 'Březen', 'Duben', 'Květen', 'Červen', 'Červenec', 'Srpen', 'Září', 'Říjen', 'Listopad', 'Prosinec']

function Spinner() {
  return (
    <div className="flex items-center justify-center py-8">
      <div className="w-8 h-8 rounded-full animate-spin"
        style={{ border: '3px solid #d4e8e0', borderTopColor: '#74FB71' }} />
    </div>
  )
}

const val = (r, fb = []) => (r?.status === 'fulfilled' && !r.value?.error ? (r.value.data ?? fb) : fb)
const cnt = (r) => (r?.status === 'fulfilled' ? (r.value?.count ?? (r.value?.data || []).length) : 0)

export default function Dashboard() {
  const debugMode = useDebugMode()
  const nav = useNavigate()
  const [data, setData] = useState(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    debugLog('page.mount', 'Dashboard')
    fetchDashboardData()
    const interval = setInterval(fetchDashboardData, 120000)
    return () => clearInterval(interval)
  }, [])

  async function fetchDashboardData() {
    try {
      const now = new Date()
      const today = now.toISOString().split('T')[0]
      const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).toISOString().slice(0, 10)
      const weekAgo = new Date(Date.now() - 7 * 86400000).toISOString()

      const [motosR, bookCntR, unreadR, invStockR, eventsR, sosR, invoicesR, expenseR,
        newBookR, emailsR, shopR, msgsR, serviceR, visitorsR, aiR, modsR] =
        await debugAction('dashboard.fetchAll', 'Dashboard', () => Promise.allSettled([
          supabase.from('motorcycles').select('id, model, spz, status, stk_valid_until'),
          supabase.from('bookings').select('id, status').in('status', ['active', 'pending', 'reserved']),
          supabase.from('messages').select('id', { count: 'exact', head: true }).eq('direction', 'customer').is('read_at', null),
          supabase.from('inventory').select('id, stock, min_stock'),
          supabase.from('bookings').select('id, user_id, moto_id, start_date, end_date, status, total_price, created_via_ai')
            .or(`start_date.gte.${today},status.eq.active`)
            .in('status', ['active', 'reserved', 'pending'])
            .order('start_date', { ascending: true }).limit(5),
          supabase.from('sos_incidents').select('id, type, title, severity, status, created_at')
            .in('status', ['reported', 'acknowledged', 'in_progress']).order('created_at', { ascending: false }),
          // Bez server-side filtru na `issue_date` — faktury s `issue_date = NULL`
          // (měsíc se bere z fallbacku `created_at`) by jinak vypadly (`null >= x`
          // = false) a graf „Tržby dle měsíců" by za starší měsíce byl prázdný.
          // Bereme nejnovějších 1000 faktur a měsíc filtrujeme klientsky přes invMonth.
          supabase.from('invoices')
            .select('id, number, type, status, total, issue_date, created_at, booking_id, order_id, bookings:booking_id(is_test), profiles:customer_id(full_name, is_test_account)')
            .order('created_at', { ascending: false }).limit(1000),
          supabase.from('accounting_entries').select('type, amount, category, description').gte('date', monthStart),
          supabase.from('bookings').select('id, user_id, moto_id, start_date, end_date, status, total_price, created_at, created_via_ai')
            .order('created_at', { ascending: false }).limit(5),
          supabase.from('sent_emails').select('id, subject, recipient_email, template_slug, status, created_at')
            .order('created_at', { ascending: false }).limit(5),
          supabase.from('shop_orders').select('id, order_number, customer_name, total, status, payment_status, created_at')
            .order('created_at', { ascending: false }).limit(5),
          supabase.from('messages').select('id, content, created_at, read_at').eq('direction', 'customer')
            .order('created_at', { ascending: false }).limit(4),
          supabase.from('maintenance_log')
            .select('id, moto_id, service_type, status, service_date, scheduled_date, description, is_urgent')
            .is('completed_date', null).order('service_date', { ascending: true }).limit(5),
          supabase.rpc('get_visitor_stats', { p_from: weekAgo, p_to: now.toISOString(), p_host: null, p_granularity: 'day' }),
          supabase.from('ai_public_conversations').select('id, outcome').gte('started_at', weekAgo).limit(1000),
          supabase.from('bookings').select('id, user_id, moto_id, start_date, end_date, status, modification_history, updated_at')
            .neq('modification_history', '[]').order('updated_at', { ascending: false }).limit(5),
        ]))

      // ── Flotila, rezervace, sklad, STK ──
      const allMotos = val(motosR)
      const activeMotos = allMotos.filter(m => m.status === 'active').length
      const bookings = val(bookCntR)
      const activeBookings = bookings.filter(b => b.status === 'active' || b.status === 'reserved').length
      const pendingBookings = bookings.filter(b => b.status === 'pending').length
      const lowStock = val(invStockR).filter(i => i.stock <= (i.min_stock || 0)).length
      const utilization = activeMotos > 0 ? Math.min(Math.round((activeBookings / activeMotos) * 100), 100) : 0
      const in30days = new Date(Date.now() + 30 * 86400000).toISOString().slice(0, 10)
      const stkExpiring = allMotos.filter(m => m.stk_valid_until && m.stk_valid_until <= in30days)

      // ── Tržby z faktur (DP + KF + shop_final − dobropisy) — kanonický zdroj.
      // accounting_entries příjmy neplníme spolehlivě (trigger bug), proto faktury.
      const invoices = val(invoicesR)
      const paidInv = invoices.filter(i => !isVoidInvoice(i) && !isTestInvoice(i) && INVOICE_PAID_TYPES.includes(i.type))
      const invMonth = (i) => (i.issue_date || i.created_at || '').slice(0, 7)
      const monthKeys = []
      for (let m = 11; m >= 0; m--) {
        const d = new Date(now.getFullYear(), now.getMonth() - m, 1)
        monthKeys.push({
          key: `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`,
          label: MONTHS[d.getMonth()],
          full: `${MONTHS_FULL[d.getMonth()]} ${d.getFullYear()}`,
        })
      }
      const revenueByMonth = monthKeys.map(mk => paidInv.filter(i => invMonth(i) === mk.key).reduce((s, i) => s + (i.total || 0), 0))
      const monthRevenue = revenueByMonth[11]
      const lastMonthRevenue = revenueByMonth[10]

      // ── Finance: výdaje z účetních záznamů, neuhrazené zálohy z faktur ──
      const expense = val(expenseR).filter(e => !isRevenueEntry(e)).reduce((s, e) => s + Math.abs(e.amount || 0), 0)
      const { unpaid } = summarizeInvoices(invoices)

      // ── Poslední přijaté platby (rezervace = DP/KF, e-shop = shop_final) ──
      const payments = invoices
        .filter(i => !isVoidInvoice(i) && !isTestInvoice(i) && INVOICE_RECEIVED_TYPES.includes(i.type))
        .slice(0, 5).map(i => ({ ...i, customer_name: i.profiles?.full_name }))

      // ── Vystavené dokumenty (posledních 5 faktur všech typů) ──
      const docs = invoices.filter(i => !isTestInvoice(i)).slice(0, 5).map(i => ({ ...i, customer_name: i.profiles?.full_name }))

      // ── Události + nové rezervace + úpravy: doplň jména zákazníků a motorek ──
      const events = val(eventsR)
      const newBookings = val(newBookR)
      const modBookings = val(modsR)
        .map(b => ({ ...b, lastMod: (Array.isArray(b.modification_history) ? b.modification_history : []).slice(-1)[0] }))
        .filter(b => b.lastMod)
      const userIds = [...new Set([...events, ...newBookings, ...modBookings].map(b => b.user_id).filter(Boolean))]
      const profilesR = userIds.length > 0
        ? await debugAction('dashboard.enrichEvents', 'Dashboard', () => supabase.from('profiles').select('id, full_name').in('id', userIds))
        : { data: [] }
      const profileMap = Object.fromEntries((profilesR.data || []).map(p => [p.id, p.full_name]))
      const motoMap = Object.fromEntries(allMotos.map(m => [m.id, m.model]))
      const enrich = (b) => ({ ...b, customer_name: profileMap[b.user_id] || null, motorcycle_name: motoMap[b.moto_id] || null })

      // ── Servis ──
      const serviceLogs = val(serviceR).map(l => ({ ...l, motorcycle_name: motoMap[l.moto_id] || null }))
      const inServiceCount = allMotos.filter(m => m.status === 'maintenance').length

      // ── Návštěvnost + AI konverzace ──
      const vs = visitorsR.status === 'fulfilled' && !visitorsR.value?.error ? visitorsR.value.data : null
      const visitors = vs ? {
        views: Number(vs.total_views || 0),
        visitors: Number(vs.unique_visitors || 0),
        timeline: (vs.timeline || []).map(t => Number(t.views || 0)),
      } : null
      const aiConvs = val(aiR, null)
      const ai = aiConvs ? { total: aiConvs.length, bookings: aiConvs.filter(c => c.outcome === 'booking_created').length } : null

      const sosList = val(sosR)
      setData({
        activeMotos, totalMotos: allMotos.length, utilization, activeBookings, pendingBookings,
        monthRevenue, lastMonthRevenue,
        revenueChart: monthKeys.map((mk, i) => ({ label: mk.label, full: mk.full, value: revenueByMonth[i] })),
        finance: { revenue: monthRevenue, expense, profit: monthRevenue - expense, unpaid },
        unreadMessages: cnt(unreadR), lowStock, stkExpiring,
        sosList, sosCritical: sosList.filter(s => s.severity === 'critical' || s.severity === 'high').length,
        events: events.map(enrich), newBookings: newBookings.map(enrich), modifications: modBookings.map(enrich),
        payments, docs, emails: val(emailsR), shopOrders: val(shopR), messages: val(msgsR),
        serviceLogs, inServiceCount, visitors, ai,
      })
    } catch (err) {
      debugError('dashboard.fetchAll', 'Dashboard', err)
    } finally {
      setLoading(false)
    }
  }

  if (loading && !data) return <Spinner />
  if (!data) return null

  const fmtShort = (v) => v >= 1_000_000 ? `${(v / 1_000_000).toFixed(1)}M Kč` : v >= 1_000 ? `${Math.round(v / 1_000)}k Kč` : `${Math.round(v)} Kč`
  const clickable = (path, child) => <div onClick={() => nav(path)} className="cursor-pointer flex-1 flex" style={{ minWidth: 160 }}>{child}</div>

  return (
    <div>
      <div className="flex gap-3.5 mb-5 flex-wrap">
        {clickable('/flotila', <Stat icon="🏍️" label="Aktivní motorky" value={`${data.activeMotos}/${data.totalMotos}`} sub={`Ø využití ${data.utilization}%`} />)}
        {clickable('/finance', <Stat icon="💰" label="Tržby tento měsíc" value={fmtShort(data.monthRevenue)} color="#f59e0b" sub="z přijatých plateb" />)}
        {clickable('/finance', <Stat icon="🗓️" label="Tržby minulý měsíc" value={fmtShort(data.lastMonthRevenue)} color="#f59e0b" sub="z přijatých plateb" />)}
        {clickable('/rezervace', <Stat icon="📅" label="Akt. / Čekající" value={`${data.activeBookings} / ${data.pendingBookings}`} sub="rezervací" color="#3b82f6" />)}
        {clickable('/zpravy', <Stat icon="💬" label="Nepřečtené" value={data.unreadMessages} sub="zpráv" color="#8b5cf6" />)}
        {clickable('/sos', <Stat icon="🚨" label="Aktivní SOS" value={data.sosList.length} sub={data.sosCritical > 0 ? `${data.sosCritical} kritických!` : 'incidentů'} color={data.sosList.length > 0 ? '#dc2626' : '#1a8a18'} />)}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <RevenueChartCard data={data.revenueChart} nav={nav} />
        <BookingRowsCard icon="📅" title="Nejbližší události" bookings={data.events} nav={nav} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mt-4">
        <BookingRowsCard icon="🆕" title="Poslední vytvořené rezervace" bookings={data.newBookings} nav={nav} dateField="created_at" />
        <ModificationsCard mods={data.modifications} nav={nav} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mt-4">
        <PaymentsCard payments={data.payments} nav={nav} />
        <ShopOrdersCard orders={data.shopOrders} nav={nav} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mt-4">
        <WidgetCard icon="💰" title="Finance — měsíční přehled" onOpen={() => nav('/finance')}>
          <div className="grid grid-cols-2 gap-3">
            {[['Příjmy', data.finance.revenue, '#1a8a18', '#dcfce7'],
              ['Výdaje', data.finance.expense, '#dc2626', '#fee2e2'],
              ['Zisk', data.finance.profit, data.finance.profit >= 0 ? '#1a8a18' : '#dc2626', data.finance.profit >= 0 ? '#f0fdf4' : '#fef2f2'],
              ['Neuhrazené zálohy', data.finance.unpaid, '#b45309', '#fef3c7']].map(([label, v, color, bg]) => (
              <div key={label} className="rounded-lg" style={{ padding: '10px 14px', background: bg }}>
                <div className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>{label}</div>
                <div className="text-lg font-extrabold" style={{ color }}>{fmtKc(v)}</div>
              </div>
            ))}
          </div>
        </WidgetCard>
        <DocsCard docs={data.docs} nav={nav} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mt-4">
        <ServiceCard logs={data.serviceLogs} inServiceCount={data.inServiceCount} nav={nav} />
        <StkCard stkExpiring={data.stkExpiring} nav={nav} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mt-4">
        <EmailsCard emails={data.emails} nav={nav} />
        <MessagesCard messages={data.messages} unread={data.unreadMessages} nav={nav} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mt-4">
        <VisitorsCard visitors={data.visitors} nav={nav} />
        <AiConvCard ai={data.ai} nav={nav} />
      </div>

      <div className="mt-4">
        <SosCard sosList={data.sosList} sosCritical={data.sosCritical} nav={nav} />
      </div>

      {data.lowStock > 0 && (
        <div className="flex gap-2.5 mt-4 flex-wrap">
          <div onClick={() => nav('/sklady')} className="text-sm font-bold cursor-pointer"
            style={{ background: '#fef3c7', borderRadius: 50, padding: '8px 18px', color: '#92400e' }}>
            ⚠️ {data.lowStock} položek pod minimem
          </div>
        </div>
      )}

      <div className="mt-4"><AiDashboardWidget /></div>
      <div className="mt-4"><BannerEditor /></div>

      {debugMode && (
        <div className="mt-4 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
          <strong>DIAGNOSTIKA Dashboard</strong><br />
          <div>motorcycles: {data.totalMotos} (active: {data.activeMotos}, využití: {data.utilization}%)</div>
          <div>bookings (active/pending): {data.activeBookings}/{data.pendingBookings}</div>
          <div>tržby z faktur: tento měsíc={data.monthRevenue?.toLocaleString('cs-CZ')} Kč, minulý={data.lastMonthRevenue?.toLocaleString('cs-CZ')} Kč</div>
          <div>finance: výdaje={data.finance.expense?.toLocaleString('cs-CZ')} Kč, neuhrazené={data.finance.unpaid?.toLocaleString('cs-CZ')} Kč</div>
          <div>revenueChart: {data.revenueChart.filter(m => m.value > 0).length}/12 měsíců s daty</div>
          <div>payments: {data.payments.length}, docs: {data.docs.length}, emails: {data.emails.length}, shop: {data.shopOrders.length}</div>
          <div>service open: {data.serviceLogs.length} (v servisu: {data.inServiceCount}), STK 30d: {data.stkExpiring.length}</div>
          <div>visitors 7d: {data.visitors ? `${data.visitors.visitors} / ${data.visitors.views} views` : 'N/A'}, AI konverzace 7d: {data.ai ? data.ai.total : 'N/A'}</div>
          <div>messages: {data.messages.length} (unread: {data.unreadMessages}), SOS: {data.sosList.length}</div>
        </div>
      )}
      <ExportBar />
    </div>
  )
}
