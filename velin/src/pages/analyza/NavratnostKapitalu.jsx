// Návratnost kapitálu motorek — tržby za období vztažené k pořizovací ceně.
// Počítá se z TRŽEB (isRealizedBooking), ne ze zisku — provozní náklady se neodečítají;
// jde o hrubou návratnost vloženého kapitálu. Roční tempo přepočítává tržby období
// na 365 dní (stejná aproximace jako obsazenost ve VykonMotorek).

const fmtKc = n => `${Math.round(n).toLocaleString('cs-CZ')} Kč`

const Card = ({ label, value, sub, accent }) => (
  <div style={{ background: '#fff', borderRadius: 14, padding: 16, boxShadow: '0 1px 4px rgba(0,0,0,.06)', flex: '1 1 160px', minWidth: 160 }}>
    <div style={{ fontSize: 11, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.05em', color: '#888' }}>{label}</div>
    <div className="font-extrabold" style={{ fontSize: 22, color: accent || '#1a2e22', marginTop: 4 }}>{value}</div>
    {sub && <div style={{ fontSize: 11, color: '#888', marginTop: 2 }}>{sub}</div>}
  </div>
)

export default function NavratnostKapitalu({ motoStats, periodDays }) {
  const withPrice = motoStats.filter(m => Number(m.purchase_price) > 0)
  const missingPrice = motoStats.length - withPrice.length

  const rows = withPrice.map(m => {
    const pp = Number(m.purchase_price)
    const returnPct = (m.revenue / pp) * 100
    const annualRevenue = periodDays > 0 ? (m.revenue / periodDays) * 365 : 0
    const annualReturnPct = (annualRevenue / pp) * 100
    const remaining = Math.max(0, pp - m.revenue)
    const paybackMonths = remaining === 0 ? 0 : (annualRevenue > 0 ? remaining / (annualRevenue / 12) : null)
    return { ...m, pp, returnPct, annualReturnPct, remaining, paybackMonths }
  }).sort((a, b) => b.returnPct - a.returnPct)

  const totalCapital = rows.reduce((s, m) => s + m.pp, 0)
  const totalRevenue = rows.reduce((s, m) => s + m.revenue, 0)
  const overallPct = totalCapital > 0 ? (totalRevenue / totalCapital) * 100 : 0
  const paidOff = rows.filter(m => m.remaining === 0).length

  return (
    <div style={{ marginBottom: 24 }}>
      <div className="font-bold mb-3" style={{ color: '#1a2e22', fontSize: 16 }}>Návratnost kapitálu</div>

      {withPrice.length === 0 ? (
        <div className="p-6 text-center" style={{ background: '#fffbeb', borderRadius: 14, border: '1px solid #fde68a', color: '#854d0e', fontSize: 13 }}>
          Žádná motorka nemá vyplněnou pořizovací cenu — doplňte ji v detailu motorky (Flotila), pak se tu zobrazí návratnost kapitálu.
        </div>
      ) : (
        <>
          <div className="flex gap-3 flex-wrap mb-4">
            <Card label="Vložený kapitál" value={fmtKc(totalCapital)} sub={`${rows.length} motorek s cenou`} />
            <Card label="Tržby za období" value={fmtKc(totalRevenue)} />
            <Card label="Návratnost kapitálu" value={`${overallPct.toFixed(1)} %`} accent={overallPct >= 100 ? '#16a34a' : '#1a2e22'} sub="tržby / pořizovací cena" />
            <Card label="Splacené motorky" value={`${paidOff} / ${rows.length}`} sub="tržby ≥ pořizovací cena" />
          </div>

          <div style={{ background: '#fff', borderRadius: 14, padding: 16, overflowX: 'auto', boxShadow: '0 1px 4px rgba(0,0,0,.06)' }}>
            <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
              <thead>
                <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
                  {['Model', 'Značka', 'Pobočka', 'Pořizovací cena', 'Tržby', 'Návratnost', 'Roční tempo', 'Odhad splacení'].map(h => (
                    <th key={h} className="text-left font-bold py-2 px-3" style={{ color: '#1a2e22' }}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {rows.map((m, i) => (
                  <tr key={m.id} style={{ borderBottom: '1px solid #f3f4f6', background: i % 2 === 1 ? '#f9fdfb' : 'transparent' }}>
                    <td className="py-2 px-3 font-semibold">{m.model}</td>
                    <td className="py-2 px-3">{m.brand || '—'}</td>
                    <td className="py-2 px-3">{m.branchName}</td>
                    <td className="py-2 px-3">{fmtKc(m.pp)}</td>
                    <td className="py-2 px-3">{fmtKc(m.revenue)}</td>
                    <td className="py-2 px-3" style={{ minWidth: 140 }}>
                      <div className="flex items-center gap-2">
                        <div style={{ flex: 1, height: 8, borderRadius: 4, background: '#e5e7eb' }}>
                          <div style={{ width: `${Math.min(m.returnPct, 100)}%`, height: '100%', borderRadius: 4, background: m.returnPct >= 100 ? '#16a34a' : '#74FB71' }} />
                        </div>
                        <span style={{ fontSize: 11, minWidth: 44, fontWeight: 700, color: m.returnPct >= 100 ? '#16a34a' : '#1a2e22' }}>{m.returnPct.toFixed(1)}%</span>
                      </div>
                    </td>
                    <td className="py-2 px-3">{m.annualReturnPct.toFixed(1)} %/rok</td>
                    <td className="py-2 px-3">
                      {m.remaining === 0
                        ? <span style={{ color: '#16a34a', fontWeight: 700 }}>Splaceno</span>
                        : m.paybackMonths != null
                          ? `~${Math.ceil(m.paybackMonths)} měs.`
                          : '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            <div style={{ fontSize: 11, color: '#888', marginTop: 10 }}>
              Návratnost = tržby z realizovaných rezervací za vybrané období / pořizovací cena (hrubá, bez odečtu nákladů).
              Odhad splacení vychází z ročního tempa tržeb za vybrané období.
              {missingPrice > 0 && <> U {missingPrice} {missingPrice === 1 ? 'motorky' : 'motorek'} chybí pořizovací cena — nejsou zahrnuty.</>}
            </div>
          </div>
        </>
      )}
    </div>
  )
}
