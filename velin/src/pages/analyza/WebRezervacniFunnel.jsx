import { useState, useEffect, useMemo } from 'react'
import { supabase } from '../../lib/supabase'
import { BarChart, Bar, PieChart, Pie, Cell, XAxis, YAxis, Tooltip, ResponsiveContainer, Legend } from 'recharts'
import TimePeriodSelector, { filterByPeriod, getTimePeriodLabel } from './TimePeriodSelector'
import { PAID_BOOKING_STATUSES } from '../../lib/revenueUtils'
import { computeDocVerification } from '../../lib/docVerification'

// ───────────────────────────────────────────────────────────────────────────
// Web rezervační funnel — kde zákazníci na webu (motogo24.cz) odpadávají.
//
// VŠE se počítá z EXISTUJÍCÍCH sloupců `bookings` + `documents` + `profiles`,
// které web už dnes plní → žádná změna ani redeploy webu není potřeba.
//
// Klíčové markery (jen `booking_source='web'`, `is_test=false`):
//   • řádek vznikne po KROKU 1 (výběr stroje + termínu → create_web_booking)
//   • `created_device`   = zařízení v kroku 1
//   • `completed_device` = zařízení v kroku 2 (klik „Pokračovat k platbě")
//   • `checkout_started_at` / `stripe_checkout_url` = klik na platbu → Stripe brána (krok 3)
//   • `payment_status`   = unpaid → paid (zaplaceno)
//   • doklady = computeDocVerification (fotka NEBO Mindee OCR verified_at; dětská motorka N bez ŘP)
//
// 4 vzájemně se vylučující koše (priorita shora):
//   paid_docs_done  → Zaplaceno + doklady (dokončeno)
//   paid_no_docs    → Zaplaceno, čeká na doklady (krok 3 — legitimní mezistav)
//   gateway_unpaid  → Zvolil platbu / na bráně, nezaplaceno (krok 2)
//   step2_unpaid    → Krok 2 (přehled/platba) nedokončen, nezaplaceno
// ───────────────────────────────────────────────────────────────────────────

const VERIFICATION_TYPES = ['id_card', 'id_photo', 'passport', 'drivers_license', 'license_photo']

// NOVÝ FLOW (platba PŘED doklady): krok 2 = přehled + platba, krok 3 = doklady.
// „Zaplaceno, čeká na doklady" je LEGITIMNÍ krok, ne anomálie.
const STAGE_META = {
  step2_unpaid:    { label: 'Krok 2 (přehled/platba) nedokončen — nezaplaceno', color: '#dc2626', short: 'Nezaplaceno' },
  gateway_unpaid:  { label: 'Zvolil platbu / na bráně — nezaplaceno', color: '#f59e0b', short: 'Brána, nezaplaceno' },
  paid_no_docs:    { label: 'Zaplaceno — čeká na doklady (krok 3)', color: '#7c3aed', short: 'Zapl., čeká doklady' },
  paid_docs_done:  { label: 'Zaplaceno + doklady (dokončeno)', color: '#16a34a', short: 'Dokončeno' },
}
const STAGE_ORDER = ['step2_unpaid', 'gateway_unpaid', 'paid_no_docs', 'paid_docs_done']

const DEVICE_META = {
  pc:      { label: 'PC', color: '#4285f4' },
  mobile:  { label: 'Mobil', color: '#74FB71' },
  tablet:  { label: 'Tablet', color: '#f59e0b' },
  unknown: { label: 'Neznámé', color: '#9ca3af' },
}
const DEVICE_ORDER = ['pc', 'mobile', 'tablet', 'unknown']

const cardStyle = { background: '#fff', borderRadius: 14, padding: 16, boxShadow: '0 1px 4px rgba(0,0,0,.06)' }

const devNorm = (d) => {
  const v = String(d || '').toLowerCase()
  return v === 'pc' || v === 'mobile' || v === 'tablet' ? v : 'unknown'
}
const pct = (n, d) => (d > 0 ? (n / d) * 100 : 0)
const fmtPct = (n, d) => `${pct(n, d).toFixed(1)} %`

export default function WebRezervacniFunnel() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [raw, setRaw] = useState(null)
  const [period, setPeriod] = useState({ type: 'all' })

  useEffect(() => { loadData() }, [])

  async function loadData() {
    setLoading(true); setError(null)
    try {
      const [bRes, pRes, dRes, mRes] = await Promise.all([
        supabase.from('bookings')
          .select('id, user_id, moto_id, created_at, created_device, completed_device, status, payment_status, is_test, checkout_started_at, stripe_checkout_url, confirmed_at, booking_source, chosen_payment_method, pay_channel, docs_completed_at')
          .eq('booking_source', 'web'),
        supabase.from('profiles')
          .select('id, license_number, id_number, license_verified_at, id_verified_at, passport_verified_at, license_expiry, license_group'),
        supabase.from('documents')
          .select('user_id, type')
          .in('type', VERIFICATION_TYPES),
        supabase.from('motorcycles').select('id, license_required'),
      ])
      if (bRes.error) throw bRes.error
      if (pRes.error) throw pRes.error
      setRaw({
        bookings: (bRes.data || []).filter(b => b.is_test !== true),
        profiles: pRes.data || [],
        documents: dRes.error ? [] : (dRes.data || []),
        motorcycles: mRes.error ? [] : (mRes.data || []),
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

    const filtered = filterByPeriod(raw.bookings, period, 'created_at')

    const classified = filtered.map(b => {
      const moto = motoById.get(b.moto_id)
      const dv = computeDocVerification(docsByUser.get(b.user_id) || [], profileById.get(b.user_id), moto?.license_required)
      const docsDone = dv.isChildMoto ? dv.hasIdentity : (dv.hasIdentity && dv.hasLicense)

      const paid = PAID_BOOKING_STATUSES.includes(b.payment_status)
      // „zvolil platbu / na bráně" = Stripe checkout NEBO zvolená metoda (QR / karta)
      const reachedGateway = !!(b.checkout_started_at || b.stripe_checkout_url || b.pay_channel === 'qr' || b.chosen_payment_method)

      let stage
      if (paid && docsDone) stage = 'paid_docs_done'
      else if (paid) stage = 'paid_no_docs'
      else if (reachedGateway) stage = 'gateway_unpaid'
      else stage = 'step2_unpaid'

      // „Kde byl, když odpadl" — poslední známé zařízení (krok 2, jinak krok 1)
      const device = devNorm(b.completed_device || b.created_device)
      return { ...b, stage, device, docsDone, paid, reachedGateway }
    })

    const total = classified.length
    const byStage = Object.fromEntries(STAGE_ORDER.map(s => [s, 0]))
    const unfinishedByDevice = Object.fromEntries(DEVICE_ORDER.map(d => [d, 0]))
    const stageDevice = {} // stage -> {device -> count}
    let docsDoneCount = 0
    let paidWithoutDocs = 0

    for (const b of classified) {
      byStage[b.stage]++
      if (!stageDevice[b.stage]) stageDevice[b.stage] = Object.fromEntries(DEVICE_ORDER.map(d => [d, 0]))
      stageDevice[b.stage][b.device]++
      if (b.docsDone) docsDoneCount++
      if (b.paid && !b.docsDone) paidWithoutDocs++
      if (!b.paid) unfinishedByDevice[b.device]++
    }

    const paid = byStage.paid_docs_done + byStage.paid_no_docs
    const reachedGateway = paid + byStage.gateway_unpaid
    const unfinished = total - paid

    return {
      total, byStage, paid, reachedGateway, unfinished,
      docsDoneCount, paidWithoutDocs, unfinishedByDevice, stageDevice,
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
          Žádné webové rezervace v období „{getTimePeriodLabel(period)}".
        </div>
      </div>
    )
  }

  // ── Lineární funnel (monotonní): Zahájeno → Na platební bránu → Zaplaceno
  const funnelNodes = [
    { key: 'started', label: 'Zahájeno (krok 1)', value: total, color: '#1a2e22' },
    { key: 'gateway', label: 'Zvolil platbu / brána (krok 2)', value: model.reachedGateway, color: '#f59e0b' },
    { key: 'paid', label: 'Zaplaceno (krok 2 dokončen)', value: model.paid, color: '#7c3aed' },
    { key: 'done', label: 'Zaplaceno + doklady (krok 3 dokončen)', value: model.byStage.paid_docs_done, color: '#16a34a' },
  ]

  const kpis = [
    { label: 'Zahájeno (web, krok 1)', value: total, sub: getTimePeriodLabel(period) },
    { label: 'Nedokončeno celkem', value: model.unfinished, sub: fmtPct(model.unfinished, total) + ' ze zahájených' },
    { label: 'Zaplaceno (konverze)', value: model.paid, sub: fmtPct(model.paid, total) + ' ze zahájených' },
    { label: 'Konverze brána → platba', value: fmtPct(model.paid, model.reachedGateway), sub: `${model.paid} z ${model.reachedGateway} na bráně` },
  ]

  // ── Data pro grafy
  const bucketBarData = STAGE_ORDER.map(s => ({
    name: STAGE_META[s].short, count: model.byStage[s], fill: STAGE_META[s].color,
  }))
  const unfinishedPie = DEVICE_ORDER
    .map(d => ({ name: DEVICE_META[d].label, value: model.unfinishedByDevice[d], color: DEVICE_META[d].color }))
    .filter(x => x.value > 0)

  const mobileUnf = model.unfinishedByDevice.mobile
  const pcUnf = model.unfinishedByDevice.pc

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
        <div className="text-sm font-extrabold mb-3" style={{ color: '#1a2e22' }}>Trychtýř (postup ke kroku 3 a platbě)</div>
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

      {/* 4 vzájemně se vylučující koše */}
      <div className="grid lg:grid-cols-2 gap-4 mb-6">
        <div style={cardStyle}>
          <div className="text-sm font-extrabold mb-3" style={{ color: '#1a2e22' }}>Rozdělení všech zahájených (4 stavy)</div>
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

      {/* Zařízení — nedokončené rezervace mobil/pc */}
      <div className="grid lg:grid-cols-2 gap-4 mb-6">
        <div style={cardStyle}>
          <div className="text-sm font-extrabold mb-1" style={{ color: '#1a2e22' }}>Nedokončené rezervace dle zařízení</div>
          <div className="text-xs mb-3" style={{ color: '#888' }}>
            Poměr Mobil/PC u nezaplacených: {mobileUnf} : {pcUnf}
            {pcUnf > 0 && <span> ({(mobileUnf / pcUnf).toFixed(2)}× více na mobilu)</span>}
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
          <div className="text-sm font-extrabold mb-3" style={{ color: '#1a2e22' }}>Stav × zařízení</div>
          <div className="overflow-x-auto">
            <table className="w-full text-xs" style={{ borderCollapse: 'collapse' }}>
              <thead>
                <tr style={{ color: '#888' }}>
                  <th className="text-left py-1 pr-2">Stav</th>
                  {DEVICE_ORDER.map(d => <th key={d} className="text-right py-1 px-2">{DEVICE_META[d].label}</th>)}
                  <th className="text-right py-1 pl-2">Σ</th>
                </tr>
              </thead>
              <tbody>
                {STAGE_ORDER.map(s => {
                  const row = model.stageDevice[s] || {}
                  const sum = model.byStage[s]
                  return (
                    <tr key={s} style={{ borderTop: '1px solid #f0f0f0' }}>
                      <td className="py-1 pr-2" style={{ color: '#1a2e22' }}>
                        <span style={{ width: 10, height: 10, borderRadius: 2, background: STAGE_META[s].color, display: 'inline-block', marginRight: 6 }} />
                        {STAGE_META[s].short}
                      </td>
                      {DEVICE_ORDER.map(d => <td key={d} className="text-right py-1 px-2" style={{ color: '#444' }}>{row[d] || 0}</td>)}
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
          <div className="text-2xl font-extrabold" style={{ color: '#7c3aed' }}>{model.byStage.gateway_unpaid}</div>
          <div className="text-xs mt-1 font-bold" style={{ color: '#1a2e22' }}>Na bráně, nezaplaceno</div>
          <div className="text-xs mt-0.5" style={{ color: '#888' }}>existuje Stripe odkaz, unpaid</div>
        </div>
        <div style={{ ...cardStyle, padding: '18px 16px' }}>
          <div className="text-2xl font-extrabold" style={{ color: '#7c3aed' }}>{model.paidWithoutDocs}</div>
          <div className="text-xs mt-1 font-bold" style={{ color: '#1a2e22' }}>Zaplaceno — čeká na doklady</div>
          <div className="text-xs mt-0.5" style={{ color: '#888' }}>krok 3 (doklady po platbě)</div>
        </div>
      </div>

      <div className="text-xs leading-relaxed" style={{ color: '#aaa' }}>
        Zdroj: sloupce <code>bookings</code> (<code>created_device</code>, <code>completed_device</code>, <code>checkout_started_at</code>, <code>stripe_checkout_url</code>, <code>payment_status</code>), které web plní automaticky — bez nutnosti měnit web.
        Jen <code>booking_source='web'</code>, vyjma testovacích. „Doklady vyplněny" = nahraná fotka NEBO Mindee OCR (<code>verified_at</code>) na profilu zákazníka (dětská motorka N bez ŘP); stav je na úrovni zákazníka, takže u vracejícího se ověřeného zákazníka může být označen i u dříve nedokončené rezervace.
      </div>
    </div>
  )
}
