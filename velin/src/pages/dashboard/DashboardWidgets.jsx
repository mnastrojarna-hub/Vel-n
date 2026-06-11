import Card from '../../components/ui/Card'
import Badge from '../../components/ui/Badge'
import MiniChart from '../../components/ui/MiniChart'
import { getDisplayStatus } from '../../components/ui/StatusBadge'
import { ResponsiveContainer, BarChart, Bar, XAxis, YAxis, Tooltip, CartesianGrid } from 'recharts'

export const STATUS_MAP = {
  active: { label: 'Aktivní', color: '#1a8a18', bg: '#dcfce7' },
  upcoming: { label: 'Nadcházející', color: '#7c3aed', bg: '#ede9fe' },
  pending: { label: 'Čekající', color: '#92400e', bg: '#fef3c7' },
  reserved: { label: 'Nadcházející', color: '#7c3aed', bg: '#ede9fe' },
  completed: { label: 'Dokončena', color: '#3b82f6', bg: '#dbeafe' },
  cancelled: { label: 'Zrušeno', color: '#dc2626', bg: '#fee2e2' },
}

const INVOICE_TYPE_LABELS = {
  advance: 'ZF', proforma: 'ZF', payment_receipt: 'DP', final: 'KF',
  shop_proforma: 'Shop ZF', shop_final: 'Shop KF', credit_note: 'DB', received: 'Přijatá',
}
const SHOP_STATUS_LABELS = {
  new: 'Nová', confirmed: 'Potvrzena', processing: 'Zpracovává se', shipped: 'Odeslána',
  delivered: 'Doručena', cancelled: 'Zrušena', returned: 'Vrácena', refunded: 'Refundována',
}
const SERVICE_STATUS = {
  pending: { label: 'Naplánován', color: '#92400e', bg: '#fef3c7' },
  in_service: { label: 'Probíhá', color: '#1d4ed8', bg: '#dbeafe' },
  completed: { label: 'Dokončen', color: '#1a8a18', bg: '#dcfce7' },
}
const EMAIL_STATUS_COLORS = { sent: '#1a8a18', queued: '#b45309', failed: '#dc2626', bounced: '#dc2626' }

export const fmtKc = (v) => `${Math.round(Number(v) || 0).toLocaleString('cs-CZ')} Kč`
const fmtD = (d) => d ? new Date(d).toLocaleDateString('cs-CZ') : '—'
const fmtDT = (d) => d ? new Date(d).toLocaleString('cs-CZ', { day: 'numeric', month: 'numeric', hour: '2-digit', minute: '2-digit' }) : '—'

export function WidgetCard({ icon, title, onOpen, children }) {
  return (
    <Card>
      <div className="flex items-center justify-between mb-2.5">
        <div className="text-[13px] font-extrabold" style={{ color: '#0f1a14' }}>{icon} {title}</div>
        {onOpen && (
          <button onClick={onOpen} className="text-[11px] font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ background: 'none', border: 'none', color: '#1a8a18' }}>
            Zobrazit →
          </button>
        )}
      </div>
      {children}
    </Card>
  )
}

export function Row({ onClick, title, sub, right, badge }) {
  return (
    <div onClick={onClick}
      className={`flex items-center mb-1.5 ${onClick ? 'cursor-pointer hover:brightness-95 transition-all' : ''}`}
      style={{ padding: '8px 10px', background: '#f1faf7', borderRadius: 12, fontSize: 12 }}>
      <div className="flex-1 min-w-0">
        <div className="font-bold truncate" style={{ color: '#0f1a14' }}>{title}</div>
        {sub && <div className="text-sm truncate" style={{ color: '#1a2e22' }}>{sub}</div>}
      </div>
      <div className="text-right ml-2 shrink-0">
        {right && <div className="font-extrabold" style={{ color: '#3dba3a' }}>{right}</div>}
        {badge}
      </div>
    </div>
  )
}

export function Empty({ children }) {
  return <div className="text-sm font-medium py-3 text-center" style={{ color: '#1a2e22' }}>{children}</div>
}

export function BookingRowsCard({ icon, title, bookings, nav, dateField }) {
  return (
    <WidgetCard icon={icon} title={title} onOpen={() => nav('/rezervace')}>
      {bookings.length === 0 ? <Empty>Žádné rezervace</Empty> : bookings.map(b => (
        <Row key={b.id} onClick={() => nav(`/rezervace/${b.id}`)}
          title={<>{b.customer_name || 'Zákazník'}{b.created_via_ai ? ' 🤖' : ''}</>}
          sub={`${b.motorcycle_name || 'Motorka'} · ${fmtD(b.start_date)} – ${fmtD(b.end_date)}${dateField === 'created_at' ? ` · vytvořeno ${fmtDT(b.created_at)}` : ''}`}
          right={b.total_price ? fmtKc(b.total_price) : null}
          badge={STATUS_MAP[getDisplayStatus(b)] && <Badge {...STATUS_MAP[getDisplayStatus(b)]} />}
        />
      ))}
    </WidgetCard>
  )
}

export function RevenueChartCard({ data, nav }) {
  const fmtAxis = (v) => v >= 1_000_000 ? `${(v / 1_000_000).toLocaleString('cs-CZ')}M` : v >= 1000 ? `${Math.round(v / 1000)}k` : v
  return (
    <WidgetCard icon="📈" title="Tržby dle měsíců (z přijatých plateb)" onOpen={() => nav('/finance')}>
      {data.some(d => d.value > 0) ? (
        <ResponsiveContainer width="100%" height={200}>
          <BarChart data={data} margin={{ top: 8, right: 4, left: 0, bottom: 0 }}>
            <CartesianGrid strokeDasharray="3 3" stroke="#e0ede7" vertical={false} />
            <XAxis dataKey="label" tick={{ fontSize: 10, fontWeight: 700, fill: '#1a2e22' }} axisLine={false} tickLine={false} interval={0} />
            <YAxis tickFormatter={fmtAxis} tick={{ fontSize: 10, fontWeight: 700, fill: '#1a2e22' }} axisLine={false} tickLine={false} width={44} />
            <Tooltip cursor={{ fill: '#f1faf7' }}
              formatter={(v) => [`${Number(v).toLocaleString('cs-CZ')} Kč`, 'Tržby']}
              labelFormatter={(l, p) => p?.[0]?.payload?.full || l}
              contentStyle={{ borderRadius: 12, border: '1px solid #d4e8e0', fontSize: 12, fontWeight: 700 }} />
            <Bar dataKey="value" fill="#3dba3a" radius={[6, 6, 0, 0]} maxBarSize={30} />
          </BarChart>
        </ResponsiveContainer>
      ) : <Empty>Zatím žádné přijaté platby za posledních 12 měsíců</Empty>}
    </WidgetCard>
  )
}

const MOD_SOURCE_LABELS = {
  web_customer: 'zákazník (web)', app: 'zákazník (app)', ai_agent: 'AI agent',
  velin: 'Velín', admin: 'Velín', stripe_webhook: 'doplatek (Stripe)',
}

export function ModificationsCard({ mods, nav }) {
  return (
    <WidgetCard icon="✏️" title="Poslední úpravy rezervací" onOpen={() => nav('/rezervace')}>
      {mods.length === 0 ? <Empty>Žádné úpravy rezervací</Empty> : mods.map(m => {
        const e = m.lastMod
        const dateChange = e.to_start && (e.to_start !== e.from_start || e.to_end !== e.from_end)
        const what = e.free_move ? `posun zdarma → ${fmtD(e.to_start)} – ${fmtD(e.to_end)}`
          : dateChange ? `termín ${fmtD(e.from_start)} – ${fmtD(e.from_end)} → ${fmtD(e.to_start)} – ${fmtD(e.to_end)}`
          : 'úprava rezervace'
        const diff = Number(e.price_diff ?? e.gross_diff)
        return (
          <Row key={m.id} onClick={() => nav(`/rezervace/${m.id}`)}
            title={`${m.customer_name || 'Zákazník'} · ${m.motorcycle_name || 'Motorka'}`}
            sub={`${fmtDT(e.at)} · ${what}`}
            right={Number.isFinite(diff) && diff !== 0 ? `${diff > 0 ? '+' : '−'}${fmtKc(Math.abs(diff))}` : null}
            badge={<Badge label={MOD_SOURCE_LABELS[e.source] || e.source || '—'} color="#7c3aed" bg="#ede9fe" />}
          />
        )
      })}
    </WidgetCard>
  )
}

export function PaymentsCard({ payments, nav }) {
  return (
    <WidgetCard icon="💳" title="Poslední přijaté platby" onOpen={() => nav('/finance')}>
      {payments.length === 0 ? <Empty>Žádné přijaté platby</Empty> : payments.map(p => (
        <Row key={p.id} onClick={() => nav(p.booking_id ? `/rezervace/${p.booking_id}` : '/e-shop')}
          title={p.customer_name || (p.order_id ? 'E-shop objednávka' : 'Zákazník')}
          sub={`${p.number || '—'} · ${fmtD(p.issue_date || p.created_at)}`}
          right={fmtKc(p.total)}
          badge={<Badge label={p.order_id ? 'E-shop' : 'Rezervace'} color={p.order_id ? '#7c3aed' : '#0891b2'} bg={p.order_id ? '#ede9fe' : '#cffafe'} />}
        />
      ))}
    </WidgetCard>
  )
}

export function ShopOrdersCard({ orders, nav }) {
  return (
    <WidgetCard icon="🛒" title="E-shop — poslední nákupy" onOpen={() => nav('/e-shop')}>
      {orders.length === 0 ? <Empty>Žádné objednávky</Empty> : orders.map(o => (
        <Row key={o.id} onClick={() => nav('/e-shop')}
          title={o.customer_name || 'Zákazník'}
          sub={`${o.order_number || '—'} · ${fmtDT(o.created_at)}`}
          right={fmtKc(o.total)}
          badge={<Badge label={`${SHOP_STATUS_LABELS[o.status] || o.status}${o.payment_status === 'paid' ? ' · zaplaceno' : ''}`}
            color={o.payment_status === 'paid' ? '#1a8a18' : '#92400e'} bg={o.payment_status === 'paid' ? '#dcfce7' : '#fef3c7'} />}
        />
      ))}
    </WidgetCard>
  )
}

export function ServiceCard({ logs, inServiceCount, nav }) {
  return (
    <WidgetCard icon="🔧" title={`Servis — stav a průběh (${inServiceCount} motorek v servisu)`} onOpen={() => nav('/servis')}>
      {logs.length === 0 ? <Empty>Žádný otevřený servis</Empty> : logs.map(l => {
        const st = SERVICE_STATUS[l.status] || { label: l.status || '—', color: '#6b7280', bg: '#f3f4f6' }
        return (
          <Row key={l.id} onClick={() => nav('/servis')}
            title={<>{l.is_urgent ? '🚨 ' : ''}{l.motorcycle_name || 'Motorka'}</>}
            sub={`${l.description || l.service_type || 'Servis'} · ${fmtD(l.service_date)}${l.scheduled_date && l.scheduled_date !== l.service_date ? ` – ${fmtD(l.scheduled_date)}` : ''}`}
            badge={<Badge label={st.label} color={st.color} bg={st.bg} />}
          />
        )
      })}
    </WidgetCard>
  )
}

export function StkCard({ stkExpiring, nav }) {
  return (
    <WidgetCard icon="🏛️" title="Blížící se STK" onOpen={() => nav('/servis')}>
      {stkExpiring.length > 0 ? stkExpiring.slice(0, 4).map(m => {
        const days = Math.ceil((new Date(m.stk_valid_until) - new Date()) / 86400000)
        return (
          <div key={m.id} onClick={() => nav(`/flotila/${m.id}`)} className="flex items-center text-sm mb-1 cursor-pointer hover:brightness-95"
            style={{ padding: '6px 10px', background: days < 0 ? '#fee2e2' : '#fef3c7', borderRadius: 8 }}>
            <span className="font-bold" style={{ color: '#0f1a14' }}>{m.model}</span>
            <span className="ml-2 font-mono text-sm" style={{ color: '#1a2e22' }}>{m.spz}</span>
            <span className="ml-auto font-bold" style={{ color: days < 0 ? '#dc2626' : '#b45309' }}>
              {days < 0 ? `${Math.abs(days)} dní po` : `za ${days} dní`}
            </span>
          </div>
        )
      }) : <div className="text-sm font-medium" style={{ color: '#1a8a18' }}>✅ Žádné STK nevyprší v nejbližších 30 dnech</div>}
    </WidgetCard>
  )
}

export function EmailsCard({ emails, nav }) {
  return (
    <WidgetCard icon="📧" title="Odeslané e-maily" onOpen={() => nav('/dokumenty')}>
      {emails.length === 0 ? <Empty>Žádné odeslané e-maily</Empty> : emails.map(e => (
        <Row key={e.id} onClick={() => nav('/dokumenty')}
          title={e.subject || e.template_slug || '—'}
          sub={`${e.recipient_email || '—'} · ${fmtDT(e.created_at)}`}
          badge={<span className="text-sm font-extrabold" style={{ color: EMAIL_STATUS_COLORS[e.status] || '#6b7280' }}>{e.status}</span>}
        />
      ))}
    </WidgetCard>
  )
}

export function DocsCard({ docs, nav }) {
  return (
    <WidgetCard icon="📄" title="Vystavené dokumenty" onOpen={() => nav('/dokumenty')}>
      {docs.length === 0 ? <Empty>Žádné dokumenty</Empty> : docs.map(d => (
        <Row key={d.id} onClick={() => nav(d.booking_id ? `/rezervace/${d.booking_id}` : '/dokumenty')}
          title={`${d.number || '—'} · ${d.customer_name || 'Zákazník'}`}
          sub={fmtD(d.issue_date || d.created_at)}
          right={fmtKc(d.total)}
          badge={<Badge label={INVOICE_TYPE_LABELS[d.type] || d.type} color="#0891b2" bg="#cffafe" />}
        />
      ))}
    </WidgetCard>
  )
}

export function VisitorsCard({ visitors, nav }) {
  return (
    <WidgetCard icon="🌍" title="Návštěvnost webu (7 dní)" onOpen={() => nav('/analyza')}>
      {!visitors ? <Empty>Návštěvnost zatím není aktivní</Empty> : (
        <>
          <div className="flex gap-5 mb-2">
            <div><span className="text-xl font-black" style={{ color: '#1a8a18' }}>{visitors.visitors.toLocaleString('cs-CZ')}</span>
              <span className="text-sm font-medium ml-1.5" style={{ color: '#1a2e22' }}>návštěvníků</span></div>
            <div><span className="text-xl font-black" style={{ color: '#3b82f6' }}>{visitors.views.toLocaleString('cs-CZ')}</span>
              <span className="text-sm font-medium ml-1.5" style={{ color: '#1a2e22' }}>zobrazení</span></div>
          </div>
          {visitors.timeline.length > 1 && <MiniChart data={visitors.timeline} color="#3b82f6" height={42} />}
        </>
      )}
    </WidgetCard>
  )
}

export function AiConvCard({ ai, nav }) {
  return (
    <WidgetCard icon="🤖" title="AI konverzace na webu (7 dní)" onOpen={() => nav('/analyza')}>
      {!ai ? <Empty>Žádná data</Empty> : (
        <div className="flex gap-5">
          <div><span className="text-xl font-black" style={{ color: '#7c3aed' }}>{ai.total}</span>
            <span className="text-sm font-medium ml-1.5" style={{ color: '#1a2e22' }}>konverzací</span></div>
          <div><span className="text-xl font-black" style={{ color: '#1a8a18' }}>{ai.bookings}</span>
            <span className="text-sm font-medium ml-1.5" style={{ color: '#1a2e22' }}>vedlo k rezervaci</span></div>
        </div>
      )}
    </WidgetCard>
  )
}

export function MessagesCard({ messages, unread, nav }) {
  return (
    <WidgetCard icon="💬" title={`Aktuální zprávy${unread > 0 ? ` (${unread} nepřečtených)` : ''}`} onOpen={() => nav('/zpravy')}>
      {messages.length === 0 ? <Empty>Žádné zprávy od zákazníků</Empty> : messages.map(m => (
        <Row key={m.id} onClick={() => nav('/zpravy')}
          title={(m.content || '').slice(0, 70) || '—'}
          sub={fmtDT(m.created_at)}
          badge={!m.read_at && <Badge label="Nové" color="#7c3aed" bg="#ede9fe" />}
        />
      ))}
    </WidgetCard>
  )
}

export function SosCard({ sosList, sosCritical, nav }) {
  return (
    <WidgetCard icon="🚨" title="SOS incidenty" onOpen={() => nav('/sos')}>
      {sosList.length === 0 ? (
        <div className="text-sm font-medium" style={{ color: '#1a8a18' }}>Žádné aktivní incidenty</div>
      ) : (
        <>
          {sosCritical > 0 && (
            <div className="text-sm font-extrabold uppercase tracking-wide mb-1.5 animate-pulse" style={{ color: '#dc2626' }}>
              {sosCritical} kritických!
            </div>
          )}
          {sosList.slice(0, 4).map(s => (
            <Row key={s.id} onClick={() => nav('/sos')}
              title={s.title || s.type || 'Incident'}
              sub={fmtDT(s.created_at)}
              badge={<Badge label={s.severity || '—'} color={['critical', 'high'].includes(s.severity) ? '#dc2626' : '#b45309'}
                bg={['critical', 'high'].includes(s.severity) ? '#fee2e2' : '#fef3c7'} />}
            />
          ))}
        </>
      )}
    </WidgetCard>
  )
}
