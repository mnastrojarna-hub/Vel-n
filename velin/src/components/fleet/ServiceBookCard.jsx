import { useMemo } from 'react'
import Card from '../ui/Card'
import { TYPE_LABELS } from '../../pages/service/serviceScheduleUtils'

/**
 * Servisní kniha motorky (zadání majitele): u každé motorky přehledně, jaký servis
 * byl proveden, kdy a při kolika km — souhrn „naposledy provedeno“ pro klíčové
 * úkony + chronologický zápis DOKONČENÝCH servisů. Čistě z `maintenance_log`
 * (service_date/completed_date, km_at_service, type, service_type, items jsonb
 * vč. vlastních úkonů „Jiné“, description, performed_by, cost). Otevřené /
 * naplánované záznamy zůstávají v „Historie servisu“ níže.
 */

const SERVICE_TYPE_LABELS = { regular: 'Pravidelný servis', extraordinary: 'Mimořádný servis', repair: 'Oprava', inspection: 'Inspekce' }

// Klíčové úkony, u kterých se hlídá „naposledy provedeno“. `labels` = štítky
// z checklistu (motoActionConstants), `types` = maintenance_log.type, `desc` = záchyt z popisu.
const TRACKED = [
  { key: 'oil', title: 'Výměna oleje', labels: ['Výměna oleje'], types: ['oil_change'], desc: /v[yý]m[eě]n\w*\s+(motorov\w+\s+)?olej/i },
  { key: 'oil_filter', title: 'Olejový filtr', labels: ['Výměna olejového filtru'] },
  { key: 'air_filter', title: 'Vzduchový filtr', labels: ['Výměna vzduchového filtru'] },
  { key: 'spark', title: 'Svíčky', labels: ['Výměna svíček'] },
  { key: 'brake_fluid', title: 'Brzdová kapalina', labels: ['Výměna brzdové kapaliny'], desc: /brzdov\w+\s+kapalin/i },
  { key: 'brake_pads', title: 'Brzdové destičky', labels: ['Brzdové destičky přední', 'Brzdové destičky zadní'], types: ['brake_check'] },
  { key: 'tire_front', title: 'Přední pneumatika', labels: ['Výměna přední pneumatiky'] },
  { key: 'tire_rear', title: 'Zadní pneumatika', labels: ['Výměna zadní pneumatiky'], types: ['tire_change'] },
  { key: 'chain', title: 'Řetěz + rozety', labels: ['Výměna řetězu + rozet'] },
  { key: 'coolant', title: 'Chladicí kapalina', labels: ['Kontrola / výměna chladicí kapaliny'] },
  { key: 'valves', title: 'Seřízení ventilů', labels: ['Seřízení ventilů'] },
  { key: 'battery', title: 'Baterie', labels: ['Kontrola / výměna baterie'] },
  { key: 'full', title: 'Kompletní servis', types: ['full_service', 'winter_service'] },
  { key: 'stk', title: 'STK', labels: ['Příprava na STK'], types: ['stk', 'inspection'] },
]

const isCompleted = l => l.status === 'completed' || !!l.completed_date
const logDate = l => (l.completed_date || l.service_date || l.created_at || '').slice(0, 10)
const fmtDate = d => d ? new Date(d).toLocaleDateString('cs-CZ') : '—'
const fmtKm = (km, unit) => km ? `${Number(km).toLocaleString('cs-CZ')} ${unit}` : '—'

/** Úkon z items se počítá jako provedený, když je odškrtnutý, nebo když technik neodškrtával nic (zápis bez checklistu). */
function itemDone(item, log) {
  if (item.done === true) return true
  return !(log.items || []).some(i => i?.done === true)
}

function findLast(track, logs) {
  for (const l of logs) { // logs seřazené od nejnovějšího
    if (!isCompleted(l)) continue
    const items = Array.isArray(l.items) ? l.items : []
    const byItem = track.labels?.length && items.some(i => track.labels.includes(i?.label) && itemDone(i, l))
    const byType = track.types?.length && track.types.includes(l.type)
    const byDesc = track.desc && track.desc.test(l.description || '')
    if (byItem || byType || byDesc) return l
  }
  return null
}

export default function ServiceBookCard({ logs, unitLabel = 'km' }) {
  const { completed, openCount } = useMemo(() => {
    const sorted = [...(logs || [])].sort((a, b) => logDate(b).localeCompare(logDate(a)))
    return { completed: sorted.filter(isCompleted), openCount: sorted.length - sorted.filter(isCompleted).length }
  }, [logs])

  const summary = useMemo(() => TRACKED.map(t => ({ ...t, last: findLast(t, completed) })), [completed])

  return (
    <Card>
      <h3 className="text-sm font-extrabold uppercase tracking-widest mb-1" style={{ color: '#1a2e22' }}>Servisní kniha</h3>
      <p className="text-xs mb-3" style={{ color: '#6b7280' }}>Co bylo provedeno, kdy a při kolika {unitLabel}. Zapisuje se z dokončených servisních záznamů (vč. úkonů „Jiné“).</p>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-2 mb-4">
        {summary.map(t => (
          <div key={t.key} className="p-2 rounded-lg" style={{ background: t.last ? '#f1faf7' : '#f8fafc', border: '1px solid #d4e8e0' }}>
            <div className="text-xs font-extrabold uppercase" style={{ color: '#1a2e22' }}>{t.title}</div>
            {t.last ? (
              <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>{fmtDate(logDate(t.last))} <span style={{ color: '#1a8a18' }}>· {fmtKm(t.last.km_at_service, unitLabel)}</span></div>
            ) : (
              <div className="text-sm" style={{ color: '#9ca3af' }}>zatím nezapsáno</div>
            )}
          </div>
        ))}
      </div>

      {completed.length === 0 ? (
        <p style={{ color: '#1a2e22', fontSize: 13 }}>Žádný dokončený servis — servisní kniha se plní po ukončení servisu.</p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full border-collapse" style={{ fontSize: 13 }}>
            <thead>
              <tr style={{ background: '#f1faf7', borderBottom: '1px solid #d4e8e0' }}>
                {['Datum', unitLabel, 'Typ', 'Provedené úkony', 'Technik', 'Cena'].map(h => (
                  <th key={h} className="text-left text-xs font-extrabold uppercase tracking-wide" style={{ padding: '8px 10px', color: '#1a2e22' }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {completed.map(l => {
                const items = Array.isArray(l.items) ? l.items.filter(i => i?.label) : []
                const typeLabel = TYPE_LABELS[l.type] || SERVICE_TYPE_LABELS[l.service_type] || l.type || 'Servis'
                return (
                  <tr key={l.id} style={{ borderBottom: '1px solid #e5efe9', verticalAlign: 'top' }}>
                    <td style={{ padding: '8px 10px', whiteSpace: 'nowrap', fontWeight: 700, color: '#0f1a14' }}>{fmtDate(logDate(l))}</td>
                    <td style={{ padding: '8px 10px', whiteSpace: 'nowrap', color: '#1a2e22' }}>{fmtKm(l.km_at_service, '')}</td>
                    <td style={{ padding: '8px 10px', whiteSpace: 'nowrap', color: '#1a2e22' }}>{typeLabel}</td>
                    <td style={{ padding: '8px 10px', color: '#0f1a14' }}>
                      {items.length > 0 && (
                        <div className="flex flex-wrap gap-1 mb-1">
                          {items.map((i, idx) => (
                            <span key={idx} title={i.custom ? 'Vlastní úkon (Jiné)' : undefined} className="text-xs font-bold" style={{ padding: '2px 7px', borderRadius: 7, background: i.custom ? '#fff7ed' : '#e8fde8', border: `1px solid ${i.custom ? '#fdba74' : '#b6dccb'}`, color: '#0f1a14', textDecoration: i.done === false && items.some(x => x.done === true) ? 'line-through' : 'none' }}>
                              {i.custom ? '✎ ' : ''}{i.label}{i.note ? ` — ${i.note}` : ''}
                            </span>
                          ))}
                        </div>
                      )}
                      {l.description && <div className="text-xs" style={{ color: '#1a2e22', whiteSpace: 'pre-wrap' }}>{l.description}</div>}
                      {items.length === 0 && !l.description && <span style={{ color: '#9ca3af' }}>—</span>}
                    </td>
                    <td style={{ padding: '8px 10px', whiteSpace: 'nowrap', color: '#1a2e22' }}>{l.performed_by || '—'}</td>
                    <td style={{ padding: '8px 10px', whiteSpace: 'nowrap', fontWeight: 700, color: '#0f1a14' }}>{l.cost ? `${Number(l.cost).toLocaleString('cs-CZ')} Kč` : '—'}</td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}
      {openCount > 0 && <p className="text-xs mt-2" style={{ color: '#b45309' }}>+ {openCount} otevřený/naplánovaný záznam — po dokončení se zapíše do servisní knihy (viz Historie servisu).</p>}
    </Card>
  )
}
