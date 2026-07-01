import { useState, useEffect, useMemo } from 'react'
import { supabase } from '../../lib/supabase'
import { BarChart, Bar, PieChart, Pie, Cell, XAxis, YAxis, Tooltip, ResponsiveContainer, Legend } from 'recharts'
import TimePeriodSelector, { filterByPeriod, getTimePeriodLabel } from './TimePeriodSelector'
import { PAID_BOOKING_STATUSES } from '../../lib/revenueUtils'
import { computeDocVerification } from '../../lib/docVerification'

// ───────────────────────────────────────────────────────────────────────────
// App rezervační funnel — kde zákazníci v mobilní appce (booking_source='app')
// odpadávají. Obdoba webového funnelu, ale přizpůsobená datům z appky.
//
// DŮLEŽITÝ ROZDÍL OPROTI WEBU: appka zakládá řádek `bookings` až v KROKU PLATBY
// (payment_screen vloží pending+unpaid), zatímco web vytvoří řádek už po výběru
// stroje (krok 1). Appka proto NEumí změřit opuštění formuláře PŘED platbou
// (žádný řádek nevznikne) — tento funnel měří dokončení PLATBY u rezervací,
// které se do platebního kroku dostaly. Appka navíc nemá webové markery
// (created_device / checkout_started_at / stripe_checkout_url), takže není
// mezikrok „platební brána" — appka platí přes nativní Stripe PaymentSheet.
//
// VŠE se počítá z EXISTUJÍCÍCH sloupců (bez změny appky):
//   • `bookings` (booking_source='app', is_test=false): status, payment_status
//   • doklady = computeDocVerification (fotka NEBO Mindee OCR verified_at; dětská N)
//   • platforma (Android/iOS) = best-effort z `app_installations` dle poslední
//     známé platformy zákazníka (user_id → nejnovější last_seen_at)
//
// 3 vzájemně se vylučující koše (priorita shora):
//   paid             → Zaplaceno
//   pending_unpaid   → Rozpracováno, nezaplaceno (čeká / 10min okno platby)
//   cancelled_unpaid → Nezaplaceno → stornováno (auto-cancel 10 min nebo uživatel)
// ───────────────────────────────────────────────────────────────────────────

const VERIFICATION_TYPES = ['id_card', 'id_photo', 'passport', 'drivers_license', 'license_photo']

const STAGE_META = {
  cancelled_unpaid: { label: 'Nezaplaceno → stornováno', color: '#dc2626', short: 'Stornováno' },
  pending_unpaid:   { label: 'Rozpracováno — nezaplaceno (čeká / okno platby)', color: '#f59e0b', short: 'Rozpracováno' },
  paid:             { label: 'Zaplaceno', color: '#16a34a', short: 'Zaplaceno' },
}
const STAGE_ORDER = ['cancelled_unpaid', 'pending_unpaid', 'paid']

const PLATFORM_META = {
  android: { label: 'Android', color: '#74FB71' },
  ios:     { label: 'iOS', color: '#4285f4' },
  unknown: { label: 'Neznámé', color: '#9ca3af' },
}
const PLATFORM_ORDER = ['android', 'ios', 'unknown']

const cardStyle = { background: '#fff', borderRadius: 14, padding: 16, boxShadow: '0 1px 4px rgba(0,0,0,.06)' }

const platNorm = (p) => {
  const v = String(p || '').toLowerCase()
  return v === 'android' || v === 'ios' ? v : 'unknown'
}
const pct = (n, d) => (d > 0 ? (n / d) * 100 : 0)
const fmtPct = (n, d) => `${pct(n, d).toFixed(1)} %`

export default function AppRezervacniFunnel() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [raw, setRaw] = useState(null)
  const [period, setPeriod] = useState({ type: 'all' })

  useEffect(() => { loadData() }, [])

  async function loadData() {
    setLoading(true); setError(null)
    try {
      const [bRes, pRes, dRes, mRes, iRes] = await Promise.all([
        supabase.from('bookings')
          .select('id, user_id, moto_id, created_at, status, payment_status, is_test, booking_source')
          .eq('booking_source', 'app'),
        supabase.from('profiles')
          .select('id, license_number, id_number, license_verified_at, id_verified_at, passport_verified_at, license_expiry, license_group'),
        supabase.from('documents')
          .select('user_id, type')
          .in('type', VERIFICATION_TYPES),
        supabase.from('motorcycles').select('id, license_required'),
        supabase.from('app_installations').select('user_id, platform, last_seen_at'),
      ])
      if (bRes.error) throw bRes.error
      if (pRes.error) throw pRes.error
      setRaw({
        bookings: (bRes.data || []).filter(b => b.is_test !== true),
        profiles: pRes.data || [],
        documents: dRes.error ? [] : (dRes.data || []),
        motorcycles: mRes.error ? [] : (mRes.data || []),
        installations: iRes.error ? [] : (iRes.data || []),
      })
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  const model = useMemo(() => {
    if (!raw) return null
    const profileById = new Map(raw.profiles.map(p => [p.id, p]))
    const motoById = new Map(raw.motorcycles.map(m => [m.id, m]))
    const docsByUser = new Map()
    for (const d of raw.documents) {
      if (!d.user_id) continue
      if (!docsByUser.has(d.user_id)) docsByUser.set(d.user_id, [])
      docsByUser.get(d.user_id).push(d)
    }
    // user_id → platforma dle NEJNOVĚJŠÍ instalace (ISO last_seen_at lze porovnat lexikograficky)
    const platformByUser = new Map()
    const lastSeenByUser = new Map()
    for (const inst of raw.installations) {
      if (!inst.user_id) continue
      const seen = inst.last_seen_at || ''
      if (!lastSeenByUser.has(inst.user_id) || seen > lastSeenByUser.get(inst.user_id)) {
        lastSeenByUser.set(inst.user_id, seen)
        platformByUser.set(inst.user_id, platNorm(inst.platform))
      }
    }

    const filtered = filterByPeriod(raw.bookings, period, 'created_at')

    const classified = filtered.map(b => {
      const moto = motoById.get(b.moto_id)
      const dv = computeDocVerification(docsByUser.get(b.user_id) || [], profileById.get(b.user_id), moto?.license_required)
      const docsDone = dv.isChildMoto ? dv.hasIdentity : (dv.hasIdentity && dv.hasLicense)

      const paid = PAID_BOOKING_STATUSES.includes(b.payment_status)
      let stage
      if (paid) stage = 'paid'
      else if (b.status === 'cancelled') stage = 'cancelled_unpaid'
      else stage = 'pending_unpaid'

      const platform = platformByUser.get(b.user_id) || 'unknown'
      return { ...b, stage, platform, docsDone, paid }
    })

    const total = classified.length
    const byStage = Object.fromEntries(STAGE_ORDER.map(s => [s, 0]))
    const unfinishedByPlatform = Object.fromEntries(PLATFORM_ORDER.map(p => [p, 0]))
    const stagePlatform = {} // stage -> {platform -> count}
    let docsDoneCount = 0
    let paidWithoutDocs = 0

    for (const b of classified) {
      byStage[b.stage]++
      if (!stagePlatform[b.stage]) stagePlatform[b.stage] = Object.fromEntries(PLATFORM_ORDER.map(p => [p, 0]))
      stagePlatform[b.stage][b.platform]++
      if (b.docsDone) docsDoneCount++
      if (b.paid && !b.docsDone) paidWithoutDocs++
      if (!b.paid) unfinishedByPlatform[b.platform]++
    }

    const paid = byStage.paid
    const unfinished = total - paid

    return {
      total, byStage, paid, unfinished,
      docsDoneCount, paidWithoutDocs, unfinishedByPlatform, stagePlatform,
    }
  }, [raw, period])

  if (loading) return <div className="text-sm" style={{ color: '#888' }}>Načítám…</div>
  if (error) return <div className="text-sm" style={{ color: '#dc2626' }}>Chyba: {error}</div>
  if (!model) return null

  const { total } = model

  if (total === 0) {
    return (
      <div>
        <TimePeriodSelector value={period} onChange={setPeriod} />
        <div className="text-sm" style={{ ...cardStyle, color: '#888' }}>
          Žádné appkové rezervace v období „{getTimePeriodLabel(period)}".
        </div>
      </div>
    )
  }

  // ── Lineární funnel (monotonní): Vytvořeno v appce → Zaplaceno
  const funnelNodes = [
    { key: 'started', label: 'Rezervace vytvořena v appce (krok platby)', value: total, color: '#1a2e22' },
    { key: 'paid', label: 'Zaplaceno', value: model.paid, color: '#16a34a' },
  ]

  const kpis = [
    { label: 'Zahájeno (app, krok platby)', value: total, sub: getTimePeriodLabel(period) },
    { label: 'Nedokončeno celkem', value: model.unfinished, sub: fmtPct(model.unfinished, total) + ' ze zahájených' },
    { label: 'Zaplaceno (konverze)', value: model.paid, sub: fmtPct(model.paid, total) + ' ze zahájených' },
    { label: 'Stornováno nezaplacené', value: model.byStage.cancelled_unpaid, sub: fmtPct(model.byStage.cancelled_unpaid, total) + ' ze zahájených' },
  ]

  // ── Data pro grafy
  const bucketBarData = STAGE_ORDER.map(s => ({
    name: STAGE_META[s].short, count: model.byStage[s], fill: STAGE_META[s].color,
  }))
  const unfinishedPie = PLATFORM_ORDER
    .map(p => ({ name: PLATFORM_META[p].label, value: model.unfinishedByPlatform[p], color: PLATFORM_META[p].color }))
    .filter(x => x.value > 0)

  const androidUnf = model.unfinishedByPlatform.android
  const iosUnf = model.unfinishedByPlatform.ios

  return (
    <div>
      <TimePeriodSelector value={period} onChange={setPeriod} />

      {/* KPI */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        {kpis.map(k => (
          <div key={k.label} style={{ ...cardStyle, padding: '18px 16px' }}>
            <div className="text-2xl font-extrabold" style={{ color: '#166534' }}>{k.value}</div>
            <div className="text-xs mt-1 font-bold" style={{ color: '#1a2e22' }}>{k.label}</div>
            <div className="text-xs mt-0.5" style={{ color: '#888' }}>{k.sub}</div>
          </div>
        ))}
      </div>

      {/* Lineární funnel */}
      <div style={{ ...cardStyle, marginBottom: 24 }}>
        <div className="text-sm font-extrabold mb-3" style={{ color: '#1a2e22' }}>Trychtýř (postup k platbě)</div>
        <div className="flex flex-col gap-2">
          {funnelNodes.map((n, i) => {
            const widthPct = pct(n.value, total)
            const prev = i > 0 ? funnelNodes[i - 1].value : null
            const drop = prev != null ? prev - n.value : null
            return (
              <div key={n.key}>
                <div className="flex justify-between text-xs mb-1">
                  <span className="font-bold" style={{ color: '#1a2e22' }}>{n.label}</span>
                  <span style={{ color: '#888' }}>
                    {n.value} • {fmtPct(n.value, total)}
                    {drop != null && drop > 0 && <span style={{ color: '#dc2626' }}> (−{drop} odpadlo)</span>}
                  </span>
                </div>
                <div style={{ background: '#f1faf7', borderRadius: 8, height: 26, overflow: 'hidden' }}>
                  <div style={{ width: `${Math.max(widthPct, 1.5)}%`, height: '100%', background: n.color, borderRadius: 8, transition: 'width .3s' }} />
                </div>
              </div>
            )
          })}
        </div>
      </div>

      {/* 3 vzájemně se vylučující koše */}
      <div className="grid lg:grid-cols-2 gap-4 mb-6">
        <div style={cardStyle}>
          <div className="text-sm font-extrabold mb-3" style={{ color: '#1a2e22' }}>Rozdělení všech zahájených (3 stavy)</div>
          {/* segmentovaný pruh */}
          <div className="flex w-full mb-3" style={{ height: 28, borderRadius: 8, overflow: 'hidden' }}>
            {STAGE_ORDER.map(s => {
              const w = pct(model.byStage[s], total)
              if (w <= 0) return null
              return <div key={s} title={`${STAGE_META[s].label}: ${model.byStage[s]}`} style={{ width: `${w}%`, background: STAGE_META[s].color }} />
            })}
          </div>
          <div className="flex flex-col gap-2">
            {STAGE_ORDER.map(s => (
              <div key={s} className="flex items-center justify-between text-xs">
                <span className="flex items-center gap-2">
                  <span style={{ width: 12, height: 12, borderRadius: 3, background: STAGE_META[s].color, display: 'inline-block' }} />
                  <span style={{ color: '#1a2e22' }}>{STAGE_META[s].label}</span>
                </span>
                <span className="font-bold" style={{ color: '#1a2e22' }}>{model.byStage[s]} <span style={{ color: '#888', fontWeight: 400 }}>({fmtPct(model.byStage[s], total)})</span></span>
              </div>
            ))}
          </div>
        </div>

        <div style={cardStyle}>
          <div className="text-sm font-extrabold mb-3" style={{ color: '#1a2e22' }}>Počty podle stavu</div>
          <ResponsiveContainer width="100%" height={220}>
            <BarChart data={bucketBarData} margin={{ top: 4, right: 8, left: -16, bottom: 4 }}>
              <XAxis dataKey="name" tick={{ fontSize: 10 }} interval={0} />
              <YAxis tick={{ fontSize: 11 }} allowDecimals={false} />
              <Tooltip />
              <Bar dataKey="count" radius={[6, 6, 0, 0]} name="Rezervací">
                {bucketBarData.map((d, i) => <Cell key={i} fill={d.fill} />)}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* Platforma — nedokončené rezervace Android/iOS */}
      <div className="grid lg:grid-cols-2 gap-4 mb-6">
        <div style={cardStyle}>
          <div className="text-sm font-extrabold mb-1" style={{ color: '#1a2e22' }}>Nedokončené rezervace dle platformy</div>
          <div className="text-xs mb-3" style={{ color: '#888' }}>
            Poměr Android/iOS u nezaplacených: {androidUnf} : {iosUnf}
            {iosUnf > 0 && <span> ({(androidUnf / iosUnf).toFixed(2)}× více na Androidu)</span>}
          </div>
          {unfinishedPie.length > 0 ? (
            <ResponsiveContainer width="100%" height={220}>
              <PieChart>
                <Pie data={unfinishedPie} dataKey="value" nameKey="name" cx="50%" cy="50%" innerRadius={50} outerRadius={90} paddingAngle={2}>
                  {unfinishedPie.map((s, i) => <Cell key={i} fill={s.color} />)}
                </Pie>
                <Tooltip />
                <Legend layout="vertical" align="right" verticalAlign="middle" />
              </PieChart>
            </ResponsiveContainer>
          ) : <div className="text-sm" style={{ color: '#888' }}>Žádné nedokončené rezervace.</div>}
        </div>

        <div style={cardStyle}>
          <div className="text-sm font-extrabold mb-3" style={{ color: '#1a2e22' }}>Stav × platforma</div>
          <div className="overflow-x-auto">
            <table className="w-full text-xs" style={{ borderCollapse: 'collapse' }}>
              <thead>
                <tr style={{ color: '#888' }}>
                  <th className="text-left py-1 pr-2">Stav</th>
                  {PLATFORM_ORDER.map(p => <th key={p} className="text-right py-1 px-2">{PLATFORM_META[p].label}</th>)}
                  <th className="text-right py-1 pl-2">Σ</th>
                </tr>
              </thead>
              <tbody>
                {STAGE_ORDER.map(s => {
                  const row = model.stagePlatform[s] || {}
                  const sum = model.byStage[s]
                  return (
                    <tr key={s} style={{ borderTop: '1px solid #f0f0f0' }}>
                      <td className="py-1 pr-2" style={{ color: '#1a2e22' }}>
                        <span style={{ width: 10, height: 10, borderRadius: 2, background: STAGE_META[s].color, display: 'inline-block', marginRight: 6 }} />
                        {STAGE_META[s].short}
                      </td>
                      {PLATFORM_ORDER.map(p => <td key={p} className="text-right py-1 px-2" style={{ color: '#444' }}>{row[p] || 0}</td>)}
                      <td className="text-right py-1 pl-2 font-bold" style={{ color: '#1a2e22' }}>{sum}</td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        </div>
      </div>

      {/* Doklady — orthogonální pohled */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <div style={{ ...cardStyle, padding: '18px 16px' }}>
          <div className="text-2xl font-extrabold" style={{ color: '#166534' }}>{model.docsDoneCount}</div>
          <div className="text-xs mt-1 font-bold" style={{ color: '#1a2e22' }}>Doklady vyplněny</div>
          <div className="text-xs mt-0.5" style={{ color: '#888' }}>{fmtPct(model.docsDoneCount, total)} ze zahájených</div>
        </div>
        <div style={{ ...cardStyle, padding: '18px 16px' }}>
          <div className="text-2xl font-extrabold" style={{ color: '#dc2626' }}>{total - model.docsDoneCount}</div>
          <div className="text-xs mt-1 font-bold" style={{ color: '#1a2e22' }}>Doklady nevyplněny</div>
          <div className="text-xs mt-0.5" style={{ color: '#888' }}>{fmtPct(total - model.docsDoneCount, total)} ze zahájených</div>
        </div>
        <div style={{ ...cardStyle, padding: '18px 16px' }}>
          <div className="text-2xl font-extrabold" style={{ color: '#f59e0b' }}>{model.byStage.pending_unpaid}</div>
          <div className="text-xs mt-1 font-bold" style={{ color: '#1a2e22' }}>Rozpracováno, nezaplaceno</div>
          <div className="text-xs mt-0.5" style={{ color: '#888' }}>čeká / v okně platby (10 min)</div>
        </div>
        <div style={{ ...cardStyle, padding: '18px 16px' }}>
          <div className="text-2xl font-extrabold" style={{ color: model.paidWithoutDocs > 0 ? '#f59e0b' : '#166534' }}>{model.paidWithoutDocs}</div>
          <div className="text-xs mt-1 font-bold" style={{ color: '#1a2e22' }}>Zaplaceno bez dokladů</div>
          <div className="text-xs mt-0.5" style={{ color: '#888' }}>zaplatil, doklady chybí</div>
        </div>
      </div>

      <div className="text-xs leading-relaxed" style={{ color: '#aaa' }}>
        Zdroj: sloupce <code>bookings</code> (<code>status</code>, <code>payment_status</code>) pro <code>booking_source='app'</code>, vyjma testovacích.
        <strong> Pozor:</strong> appka zakládá rezervaci až v kroku platby (na rozdíl od webu, který ji vytvoří už po výběru stroje), takže „Zahájeno" = rezervace, které se dostaly do platebního kroku — opuštění formuláře PŘED platbou appka nezaznamenává (nevznikne řádek). Appka nemá platební bránu s odkazem (platí přes nativní Stripe PaymentSheet), proto trychtýř nemá mezikrok „brána".
        „Doklady vyplněny" = nahraná fotka NEBO Mindee OCR (<code>verified_at</code>) na profilu zákazníka (dětská motorka N bez ŘP); stav je na úrovni zákazníka. Platforma je best-effort dle poslední známé instalace zákazníka (<code>app_installations</code>) — nemusí přesně odpovídat platformě dané rezervace.
      </div>
    </div>
  )
}
