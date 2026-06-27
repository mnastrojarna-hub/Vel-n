/**
 * MotoGo24 Velín — Analýza / Návštěvnost (reální lidé)
 *
 * Reálná lidská návštěvnost webu motogo24.* (na rozdíl od AI traffic tabu,
 * který sleduje crawlery / REST API / MCP / widget). Data se logují
 * server-side z `motogo-web-php/visitor_traffic.php` do tabulky `visitor_log`
 * (cookieless, hashovaná IP — GDPR friendly, model á la Plausible). Boti se
 * filtrují, takže tu jsou jen skuteční návštěvníci.
 *
 * Granularita: Dny / Týdny / Měsíce / Roky (+ vlastní rozsah). Filtr dle
 * jednotlivých domén (.cz / .com / .es / .pl / .at / ...). Rozpad zdrojů
 * návštěv (přímý vstup / vyhledávače / sociální sítě / odkazy) + z jakých
 * stránek přišli (referrer domény i konkrétní URL).
 *
 * Server-side agregace přes RPC `get_visitor_stats` — nestahuje raw řádky
 * (PostgREST max-rows 1000), vrací jeden JSON s agregáty.
 */
import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { isRealizedBooking } from '../../lib/revenueUtils'
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, LineChart, Line, PieChart, Pie, Cell, Legend, CartesianGrid } from 'recharts'

const GRANULARITIES = [
  { id: 'day',   label: 'Dny',    days: 30 },
  { id: 'week',  label: 'Týdny',  days: 7 * 12 },
  { id: 'month', label: 'Měsíce', days: 365 },
  { id: 'year',  label: 'Roky',   days: 365 * 5 },
]

const REF_TYPE_LABELS = {
  direct: 'Přímý vstup', search: 'Vyhledávače', social: 'Sociální sítě', referral: 'Odkazy', internal: 'Interní',
}
const REF_TYPE_COLORS = {
  direct: '#74FB71', search: '#4285f4', social: '#f97316', referral: '#d4a017', internal: '#9ca3af',
}
const DEVICE_LABELS = { desktop: 'Počítač', mobile: 'Mobil', tablet: 'Tablet', unknown: 'Neznámé' }
const DEVICE_COLORS = { desktop: '#74FB71', mobile: '#4285f4', tablet: '#d4a017', unknown: '#9ca3af' }

const MONTHS_SHORT = ['led', 'úno', 'bře', 'dub', 'kvě', 'čvn', 'čvc', 'srp', 'zář', 'říj', 'lis', 'pro']

function formatBucket(iso, gran) {
  const d = new Date(iso)
  if (isNaN(d)) return iso
  if (gran === 'year') return String(d.getFullYear())
  if (gran === 'month') return `${MONTHS_SHORT[d.getMonth()]} ${String(d.getFullYear()).slice(2)}`
  // day / week
  return `${d.getDate()}.${d.getMonth() + 1}.`
}

function pct(part, total) {
  if (!total) return 0
  return Math.round((part / total) * 100)
}

export default function Navstevnost() {
  const [gran, setGran] = useState('day')
  const [custom, setCustom] = useState({ from: '', to: '' })
  const [host, setHost] = useState(null)        // null = všechny domény
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [needsSetup, setNeedsSetup] = useState(false)
  const [allStats, setAllStats] = useState(null) // host = null (pro chipy domén + KPI když "vše")
  const [stats, setStats] = useState(null)       // aplikovaný host filtr
  const [biz, setBiz] = useState(null)           // reální zákazníci: rezervace + tržby za stejné období

  useEffect(() => { loadData() }, [gran, custom, host])
  useEffect(() => { loadBiz() }, [gran, custom])

  // Byznys výsledek za stejné období — propojuje návštěvnost s reálným dopadem
  // (rezervace + tržby). visitor_log je cookieless, takže per-návštěvníka spojit
  // s rezervací nelze; tady agregujeme rezervace dle zdroje (web/app) a počítáme
  // orientační konverzi vůči unikátním návštěvníkům.
  async function loadBiz() {
    try {
      const { from, to } = range()
      const { data, error: e } = await supabase
        .from('bookings')
        .select('total_price, payment_status, status, booking_source, created_at, is_test')
        .gte('created_at', from).lte('created_at', to)
      if (e) { setBiz(null); return }
      const acc = { web: { count: 0, paid: 0, revenue: 0 }, app: { count: 0, paid: 0, revenue: 0 } }
      for (const b of (data || [])) {
        if (b.is_test === true) continue
        const src = b.booking_source === 'web' ? 'web' : 'app'
        acc[src].count++
        if (isRealizedBooking(b)) {
          acc[src].paid++
          acc[src].revenue += Number(b.total_price || 0)
        }
      }
      setBiz(acc)
    } catch { setBiz(null) }
  }

  function range() {
    if (custom.from && custom.to) {
      return { from: new Date(custom.from).toISOString(), to: new Date(custom.to + 'T23:59:59').toISOString() }
    }
    const g = GRANULARITIES.find(x => x.id === gran)
    return { from: new Date(Date.now() - g.days * 24 * 3600 * 1000).toISOString(), to: new Date().toISOString() }
  }

  const isMissing = (e) => e && (e.code === 'PGRST205' || e.code === 'PGRST202' || e.code === '42P01' || e.code === '42883' || (e.message || '').includes('schema cache') || (e.message || '').includes('does not exist'))

  async function loadData() {
    setLoading(true); setError(null); setNeedsSetup(false)
    // Watchdog: kdyby RPC „viselo" (síť/RLS), neukazuj nekonečný spinner,
    // ale po 20 s vypiš chybu — uživatel ví, co se děje, a může zkusit znovu.
    const withTimeout = (p, ms = 20000) => Promise.race([
      p,
      new Promise((_, rej) => setTimeout(() => rej(new Error('Načítání trvalo příliš dlouho (timeout). Zkuste to prosím znovu.')), ms)),
    ])
    try {
      const { from, to } = range()
      // A: vždy všechny domény (chipy + baseline)
      const a = await withTimeout(supabase.rpc('get_visitor_stats', { p_from: from, p_to: to, p_host: null, p_granularity: gran }))
      if (a.error) {
        if (isMissing(a.error)) { setNeedsSetup(true); setAllStats(null); setStats(null); return }
        throw a.error
      }
      setAllStats(a.data || null)
      if (host) {
        const b = await withTimeout(supabase.rpc('get_visitor_stats', { p_from: from, p_to: to, p_host: host, p_granularity: gran }))
        if (b.error && !isMissing(b.error)) throw b.error
        setStats(b.error ? null : (b.data || null))
      } else {
        setStats(a.data || null)
      }
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  const byHost = useMemo(() => allStats?.by_host || {}, [allStats])
  const hostList = useMemo(() => Object.entries(byHost).sort((a, b) => Number(b[1]) - Number(a[1])), [byHost])

  const total = Number(stats?.total_views || 0)
  const visitors = Number(stats?.unique_visitors || 0)
  const byType = stats?.by_referrer_type || {}
  const typeTotal = Object.values(byType).reduce((s, v) => s + Number(v), 0)

  const timeline = useMemo(() => (stats?.timeline || []).map(r => ({
    label: formatBucket(r.bucket, gran), views: Number(r.views || 0), visitors: Number(r.visitors || 0),
  })), [stats, gran])

  const typePie = Object.entries(byType)
    .filter(([k]) => k !== 'internal')
    .map(([k, v]) => ({ name: REF_TYPE_LABELS[k] || k, value: Number(v), color: REF_TYPE_COLORS[k] || '#888' }))

  const devicePie = Object.entries(stats?.by_device || {})
    .map(([k, v]) => ({ name: DEVICE_LABELS[k] || k, value: Number(v), color: DEVICE_COLORS[k] || '#888' }))

  const refDomains = (stats?.by_referrer_domain || []).map(r => ({ name: r.name, count: Number(r.count) }))
  const topPaths = (stats?.top_paths || []).map(r => ({ path: r.path, count: Number(r.count) }))
  const topReferrers = (stats?.top_referrers || []).map(r => ({ referrer: r.referrer, count: Number(r.count) }))
  const countries = (stats?.by_country || []).map(r => ({ name: r.name, count: Number(r.count) }))

  if (loading) return <div className="flex items-center justify-center py-20"><div className="animate-spin rounded-full h-8 w-8 border-t-2" style={{ borderColor: '#74FB71' }} /></div>
  if (error) return <div className="p-4 text-center" style={{ color: '#dc2626' }}>Chyba načítání: {error}</div>

  if (needsSetup) {
    return (
      <div style={{ background: '#fff', borderRadius: 14, padding: 24, border: '1px solid #e3e8e5', textAlign: 'center' }}>
        <h2 className="text-xl font-extrabold mb-2" style={{ color: '#1a2e22' }}>Návštěvnost zatím není aktivní</h2>
        <p style={{ color: '#888', fontSize: 13, maxWidth: 620, margin: '0 auto' }}>
          Sledování reálné lidské návštěvnosti vyžaduje tabulku <code>visitor_log</code> + RPC <code>get_visitor_stats</code> v Supabase.
          Po spuštění připravené SQL migrace se sem začnou sypat data z webu (cookieless, hashovaná IP — GDPR friendly).
        </p>
      </div>
    )
  }

  return (
    <div>
      {/* Header + granularita */}
      <div className="flex items-center justify-between mb-4 flex-wrap gap-3">
        <div>
          <h2 className="text-xl font-extrabold" style={{ color: '#1a2e22' }}>Návštěvnost</h2>
          <p className="text-xs" style={{ color: '#888' }}>
            Reální návštěvníci webu motogo24.* — odkud přišli, na jaké domény a stránky. Boti odfiltrováni, bez cookies.
          </p>
        </div>
        <div className="flex gap-2 flex-wrap">
          {GRANULARITIES.map(g => (
            <button key={g.id} onClick={() => { setCustom({ from: '', to: '' }); setGran(g.id) }}
              className="rounded-btn text-xs font-bold cursor-pointer"
              style={{ padding: '6px 14px', background: (!custom.from && gran === g.id) ? '#74FB71' : '#f1faf7', color: '#1a2e22', border: 'none' }}>
              {g.label}
            </button>
          ))}
        </div>
      </div>

      {/* Vlastní rozsah */}
      <div className="flex items-center gap-2 mb-4 flex-wrap" style={{ background: '#fff', borderRadius: 12, padding: '8px 14px', border: '1px solid #e3e8e5' }}>
        <span className="text-xs font-bold uppercase" style={{ color: '#888', letterSpacing: 1 }}>Vlastní rozsah:</span>
        <input type="date" value={custom.from} onChange={e => setCustom(c => ({ ...c, from: e.target.value }))}
          style={{ padding: '5px 9px', borderRadius: 8, border: '1px solid #d4e8e0', fontSize: 12, color: '#1a2e22' }} />
        <span className="text-xs" style={{ color: '#888' }}>—</span>
        <input type="date" value={custom.to} onChange={e => setCustom(c => ({ ...c, to: e.target.value }))}
          style={{ padding: '5px 9px', borderRadius: 8, border: '1px solid #d4e8e0', fontSize: 12, color: '#1a2e22' }} />
        {(custom.from || custom.to) && (
          <button onClick={() => setCustom({ from: '', to: '' })}
            style={{ background: 'none', border: 'none', color: '#dc2626', cursor: 'pointer', fontSize: 11, fontWeight: 700 }}>
            Zrušit
          </button>
        )}
        <span className="text-[11px]" style={{ color: '#bbb' }}>(graf se kreslí po {GRANULARITIES.find(g => g.id === gran)?.label.toLowerCase()})</span>
      </div>

      {/* Filtr domén */}
      <div className="flex items-center gap-2 mb-5 flex-wrap" style={{ background: '#fff', borderRadius: 12, padding: '10px 14px', border: '1px solid #e3e8e5' }}>
        <span className="text-xs font-bold uppercase" style={{ color: '#888', letterSpacing: 1 }}>Doména:</span>
        <button onClick={() => setHost(null)}
          className="rounded-btn text-xs font-bold cursor-pointer"
          style={{ padding: '6px 14px', background: host === null ? '#74FB71' : '#f1faf7', color: '#1a2e22', border: 'none' }}>
          Všechny
        </button>
        {hostList.map(([h, c]) => (
          <button key={h} onClick={() => setHost(h)}
            className="rounded-btn text-xs font-bold cursor-pointer"
            style={{ padding: '6px 14px', background: host === h ? '#74FB71' : '#f1faf7', color: '#1a2e22', border: 'none' }}>
            {h} <span style={{ color: host === h ? '#1a2e22' : '#999', fontWeight: 500 }}>({Number(c).toLocaleString('cs-CZ')})</span>
          </button>
        ))}
        {hostList.length === 0 && <span style={{ color: '#bbb', fontSize: 12 }}>Zatím žádná data</span>}
      </div>

      {/* Upřesnění období — KPI jsou SOUČET za celý zvolený rozsah, ne za dnešek */}
      {(() => {
        const r = range()
        const fromD = new Date(r.from).toLocaleDateString('cs-CZ')
        const toD = new Date(r.to).toLocaleDateString('cs-CZ')
        const granLabel = (GRANULARITIES.find(g => g.id === gran)?.label || '').toLowerCase()
        return (
          <p className="text-xs mb-2" style={{ color: '#888' }}>
            Souhrn za období <b>{fromD} – {toD}</b>{(!custom.from && !custom.to) ? ` (posledních ${GRANULARITIES.find(g => g.id === gran)?.days || ''} dní, graf po ${granLabel})` : ''} — čísla níže jsou součtem za celý rozsah, ne za dnešek.
          </p>
        )
      })()}

      {/* KPI tiles */}
      <div className="grid grid-cols-2 md:grid-cols-5 gap-3 mb-5">
        <KpiTile label="Zobrazení stránek" value={total.toLocaleString('cs-CZ')} hint={host || 'všechny domény'} color="#74FB71" />
        <KpiTile label="Návštěvníci" value={visitors.toLocaleString('cs-CZ')} hint="unikátní (denně)" color="#166534" />
        <KpiTile label="Přímý vstup" value={pct(Number(byType.direct || 0), typeTotal) + ' %'} hint={`${Number(byType.direct || 0).toLocaleString('cs-CZ')} návštěv`} color="#74FB71" />
        <KpiTile label="Z vyhledávačů" value={pct(Number(byType.search || 0), typeTotal) + ' %'} hint="Google, Seznam…" color="#4285f4" />
        <KpiTile label="Ze sociálních sítí" value={pct(Number(byType.social || 0), typeTotal) + ' %'} hint="FB, IG…" color="#f97316" />
      </div>

      {/* Byznys výsledek — reální zákazníci + tržby za stejné období */}
      {biz && (
        <div style={{ background: '#fff', borderRadius: 14, padding: 16, border: '1px solid #e3e8e5', marginBottom: 20 }}>
          <h3 className="font-extrabold text-sm" style={{ color: '#1a2e22' }}>Byznys výsledek za období (reální zákazníci)</h3>
          <p className="text-xs mb-3" style={{ color: '#888' }}>
            Rezervace a tržby ze stejného období jako návštěvnost výše. Konverze je orientační (návštěvnost je
            cookieless, nelze spojit konkrétního návštěvníka s rezervací) — počítá zaplacené web rezervace vůči unikátním návštěvníkům.
          </p>
          <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
            <KpiTile label="Rezervací (web)" value={biz.web.count.toLocaleString('cs-CZ')} hint={`z toho ${biz.web.paid} zaplacených`} color="#74FB71" />
            <KpiTile label="Tržby web" value={Math.round(biz.web.revenue).toLocaleString('cs-CZ') + ' Kč'} hint="zaplacené web rezervace" color="#166534" />
            <KpiTile label="Konverze web" value={(visitors > 0 ? (biz.web.paid / visitors * 100).toFixed(2) : '0') + ' %'} hint="zaplacené web / návštěvníci" color="#4285f4" />
            <KpiTile label="Rezervací (app)" value={biz.app.count.toLocaleString('cs-CZ')} hint={`z toho ${biz.app.paid} zaplacených`} color="#f97316" />
            <KpiTile label="Tržby app" value={Math.round(biz.app.revenue).toLocaleString('cs-CZ') + ' Kč'} hint="zaplacené app rezervace" color="#d4a017" />
          </div>
        </div>
      )}

      {/* Timeline */}
      <div style={{ background: '#fff', borderRadius: 14, padding: 16, border: '1px solid #e3e8e5', marginBottom: 20 }}>
        <h3 className="font-extrabold text-sm mb-3" style={{ color: '#1a2e22' }}>Návštěvnost v čase</h3>
        {timeline.length === 0 ? <NoData /> : (
          <ResponsiveContainer width="100%" height={260}>
            <LineChart data={timeline}>
              <CartesianGrid strokeDasharray="3 3" stroke="#f1f1f1" />
              <XAxis dataKey="label" fontSize={10} />
              <YAxis fontSize={10} allowDecimals={false} />
              <Tooltip />
              <Legend />
              <Line type="monotone" dataKey="views" name="Zobrazení" stroke="#74FB71" strokeWidth={2} dot={false} />
              <Line type="monotone" dataKey="visitors" name="Návštěvníci" stroke="#4285f4" strokeWidth={2} dot={false} />
            </LineChart>
          </ResponsiveContainer>
        )}
      </div>

      {/* Domény (bar) + zdroj návštěv (pie) */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-5">
        <div style={{ background: '#fff', borderRadius: 14, padding: 16, border: '1px solid #e3e8e5' }}>
          <h3 className="font-extrabold text-sm mb-3" style={{ color: '#1a2e22' }}>Návštěvnost dle domén</h3>
          {hostList.length === 0 ? <NoData /> : (
            <ResponsiveContainer width="100%" height={240}>
              <BarChart data={hostList.map(([h, c]) => ({ host: h, count: Number(c) }))} layout="vertical" margin={{ left: 20 }}>
                <XAxis type="number" fontSize={10} allowDecimals={false} />
                <YAxis type="category" dataKey="host" fontSize={10} width={110} />
                <Tooltip />
                <Bar dataKey="count" fill="#74FB71" radius={[0, 6, 6, 0]} />
              </BarChart>
            </ResponsiveContainer>
          )}
        </div>
        <div style={{ background: '#fff', borderRadius: 14, padding: 16, border: '1px solid #e3e8e5' }}>
          <h3 className="font-extrabold text-sm mb-3" style={{ color: '#1a2e22' }}>Zdroj návštěv</h3>
          {typePie.length === 0 ? <NoData /> : (
            <ResponsiveContainer width="100%" height={240}>
              <PieChart>
                <Pie data={typePie} dataKey="value" nameKey="name" outerRadius={85} label>
                  {typePie.map((d, i) => <Cell key={i} fill={d.color} />)}
                </Pie>
                <Legend />
                <Tooltip />
              </PieChart>
            </ResponsiveContainer>
          )}
        </div>
      </div>

      {/* Odkud přišli (referrer domény) + Top stránky */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-5">
        <ListCard title="Odkud přišli (domény)" hint="Referrer domény mimo náš web" rows={refDomains.map(r => [r.name, r.count])} />
        <ListCard title="Nejnavštěvovanější stránky" rows={topPaths.map(r => [r.path, r.count])} mono />
      </div>

      {/* Top referrery (URL) + zařízení / země */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-5">
        <ListCard title="Konkrétní odkazující URL" hint="Přesné stránky, ze kterých přišli" rows={topReferrers.map(r => [r.referrer, r.count])} mono link />
        <div style={{ background: '#fff', borderRadius: 14, padding: 16, border: '1px solid #e3e8e5' }}>
          <h3 className="font-extrabold text-sm mb-3" style={{ color: '#1a2e22' }}>Zařízení</h3>
          {devicePie.length === 0 ? <NoData /> : (
            <ResponsiveContainer width="100%" height={200}>
              <PieChart>
                <Pie data={devicePie} dataKey="value" nameKey="name" outerRadius={70} label>
                  {devicePie.map((d, i) => <Cell key={i} fill={d.color} />)}
                </Pie>
                <Legend />
                <Tooltip />
              </PieChart>
            </ResponsiveContainer>
          )}
          {countries.length > 0 && (
            <div className="mt-2">
              <h4 className="font-bold text-xs mb-1" style={{ color: '#1a2e22' }}>Země</h4>
              <div className="flex flex-wrap gap-2">
                {countries.slice(0, 12).map(c => (
                  <span key={c.name} style={{ background: '#f1faf7', borderRadius: 8, padding: '3px 8px', fontSize: 11, color: '#1a2e22' }}>
                    {c.name} <b>{c.count.toLocaleString('cs-CZ')}</b>
                  </span>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

function KpiTile({ label, value, hint, color = '#1a2e22' }) {
  return (
    <div style={{ background: '#fff', borderRadius: 14, padding: 14, border: '1px solid #e3e8e5' }}>
      <div style={{ color: '#888', fontSize: 10, fontWeight: 700, textTransform: 'uppercase' }}>{label}</div>
      <div style={{ color, fontSize: 22, fontWeight: 800, margin: '4px 0' }}>{value}</div>
      <div style={{ color: '#bbb', fontSize: 10 }}>{hint}</div>
    </div>
  )
}

function ListCard({ title, hint, rows, mono, link }) {
  return (
    <div style={{ background: '#fff', borderRadius: 14, padding: 16, border: '1px solid #e3e8e5' }}>
      <h3 className="font-extrabold text-sm" style={{ color: '#1a2e22' }}>{title}</h3>
      {hint && <p style={{ color: '#888', fontSize: 11, marginBottom: 6 }}>{hint}</p>}
      {(!rows || rows.length === 0) ? <NoData /> : (
        <table className="w-full text-xs mt-2">
          <tbody>
            {rows.map(([label, count], i) => (
              <tr key={i} style={{ borderBottom: '1px solid #f5f5f5' }}>
                <td className="p-2" style={{ maxWidth: 360, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={label}>
                  {mono
                    ? (link && /^https?:\/\//i.test(label)
                        ? <a href={label} target="_blank" rel="noopener noreferrer" style={{ color: '#1a8c1a' }}><code style={{ background: '#f1faf7', padding: '2px 6px', borderRadius: 4 }}>{label}</code></a>
                        : <code style={{ background: '#f1faf7', padding: '2px 6px', borderRadius: 4 }}>{label || '—'}</code>)
                    : (label || '—')}
                </td>
                <td className="p-2 text-right font-bold" style={{ color: '#1a2e22', whiteSpace: 'nowrap' }}>{Number(count).toLocaleString('cs-CZ')}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  )
}

function NoData() {
  return <p style={{ color: '#888', fontSize: 12, textAlign: 'center', padding: '40px 0' }}>Žádná data v tomto období</p>
}
