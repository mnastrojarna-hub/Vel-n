import { useMemo, useState } from 'react'
import Card from '../ui/Card'
import { TASK_BY_ID } from './serviceCatalog'
import { SERVICE_LABEL_TO_ID } from './motoActionConstants'
import { SERVICE_TYPE_LABELS, LOG_TYPE_LABELS, fmtDate, fmtKm, fmtMoney, isLogCompleted } from '../../lib/serviceBook'

/**
 * Servisní kniha motorky: dlaždice „naposledy provedeno“ (klíčové úkony) + chronologie DOKONČENÝCH servisů
 * se zadáním, zprávou technika, úkony (✓ = provedeno), km, technikem, cenou a doklady.
 * Zdroj: maintenance_log (items s klíči z katalogu; starší záznamy párujeme podle štítku / aliasu).
 * Props: logs, unitLabel, invoicesByLog { logId: [maintenance_invoices] }, onEdit(log)
 */
const TRACKED = [
  ['oil_change', 'Olej'], ['oil_filter', 'Olejový filtr'], ['air_filter', 'Vzduch. filtr'], ['spark_plugs', 'Svíčky'],
  ['valve_clearance', 'Ventilové vůle'], ['brake_fluid', 'Brzdová kapalina'], ['brake_pads_front', 'Destičky P'], ['brake_pads_rear', 'Destičky Z'],
  ['tire_front', 'Pneu přední'], ['tire_rear', 'Pneu zadní'], ['chain_kit', 'Řetěz + rozety'], ['final_drive_oil', 'Olej kardan'],
  ['coolant_change', 'Chladicí kapalina'], ['fork_oil', 'Olej vidlice'], ['battery', 'Baterie'], ['full_service', 'Kompletní servis'],
]
const TYPE_KEYS = { oil_change: ['oil_change', 'oil_filter'], tire_change: ['tire_front', 'tire_rear'], full_service: ['full_service'], winter_service: ['full_service'] }

const logDate = l => (l.completed_date || l.service_date || l.created_at || '').slice(0, 10)
export function doneKeysOf(l) {
  const keys = new Set()
  for (const it of (Array.isArray(l.items) ? l.items : [])) {
    if (it?.done !== true) continue
    const k = it.key || SERVICE_LABEL_TO_ID[it.label]
    if (k) { keys.add(k); for (const imp of TASK_BY_ID[k]?.implies || []) keys.add(imp) }
  }
  for (const k of TYPE_KEYS[l.type] || []) keys.add(k)
  if (/v[yý]m[eě]n\w*\s+(motorov\w+\s+)?olej/iu.test(l.description || '')) keys.add('oil_change')
  return keys
}

export default function ServiceBookCard({ logs, unitLabel = 'km', invoicesByLog = {}, onEdit }) {
  const [showAll, setShowAll] = useState(false)
  const completed = useMemo(() => [...(logs || [])].filter(isLogCompleted).sort((a, b) => logDate(b).localeCompare(logDate(a))), [logs])
  const openCount = (logs || []).length - completed.length
  const last = useMemo(() => {
    const m = {}
    for (const l of completed) { for (const k of doneKeysOf(l)) if (!m[k]) m[k] = l }
    return m
  }, [completed])
  const shown = showAll ? completed : completed.slice(0, 12)

  return (
    <Card>
      <div className="flex items-center justify-between mb-1 flex-wrap gap-2">
        <h3 className="text-sm font-extrabold uppercase tracking-widest" style={{ color: '#1a2e22' }}>Servisní kniha</h3>
        <span className="text-xs" style={{ color: '#6b7280' }}>{completed.length} dokončených servisů{openCount > 0 ? ` · ${openCount} otevřených (výše)` : ''}</span>
      </div>
      <p className="text-xs mb-3" style={{ color: '#6b7280' }}>Co bylo provedeno, kdy, při kolika {unitLabel}, kdo to dělal a co zjistil. Počítají se odškrtnuté úkony dokončených servisů.</p>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-2 mb-4">
        {TRACKED.map(([k, title]) => {
          const l = last[k]
          return (
            <div key={k} className="p-2 rounded-lg" style={{ background: l ? '#f1faf7' : '#f8fafc', border: '1px solid #d4e8e0' }}>
              <div className="text-xs font-extrabold uppercase" style={{ color: '#1a2e22' }}>{title}</div>
              {l ? <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>{fmtDate(logDate(l))} <span style={{ color: '#1a8a18' }}>· {fmtKm(l.km_at_service, unitLabel)}</span></div>
                 : <div className="text-sm" style={{ color: '#9ca3af' }}>zatím nezapsáno</div>}
            </div>
          )
        })}
      </div>

      {completed.length === 0 ? (
        <p style={{ color: '#1a2e22', fontSize: 13 }}>Žádný dokončený servis — kniha se plní po dokončení servisu.</p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full border-collapse" style={{ fontSize: 13 }}>
            <thead>
              <tr style={{ background: '#f1faf7', borderBottom: '1px solid #d4e8e0' }}>
                {['Datum', unitLabel, 'Typ', 'Úkony · zadání · zpráva technika', 'Technik', 'Cena', ''].map((h, i) => (
                  <th key={i} className="text-left text-xs font-extrabold uppercase tracking-wide" style={{ padding: '8px 10px', color: '#1a2e22' }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {shown.map(l => {
                const items = Array.isArray(l.items) ? l.items.filter(i => i?.label) : []
                const inv = invoicesByLog[l.id] || []
                const cost = l.cost || l.invoiced_amount || null
                return (
                  <tr key={l.id} style={{ borderBottom: '1px solid #e5efe9', verticalAlign: 'top' }}>
                    <td style={{ padding: '8px 10px', whiteSpace: 'nowrap', fontWeight: 700, color: '#0f1a14' }}>{fmtDate(logDate(l))}{l.is_urgent && <div className="text-xs font-bold" style={{ color: '#dc2626' }}>URGENT</div>}</td>
                    <td style={{ padding: '8px 10px', whiteSpace: 'nowrap', color: '#1a2e22' }}>{fmtKm(l.km_at_service, '')}{l.km_auto && <span title="automaticky ze stavu tachometru" style={{ color: '#9ca3af', fontSize: 10 }}> auto</span>}</td>
                    <td style={{ padding: '8px 10px', whiteSpace: 'nowrap', color: '#1a2e22' }}>{LOG_TYPE_LABELS[l.type] || SERVICE_TYPE_LABELS[l.service_type] || 'Servis'}</td>
                    <td style={{ padding: '8px 10px', color: '#0f1a14', minWidth: 260 }}>
                      {items.length > 0 && (
                        <div className="flex flex-wrap gap-1 mb-1">
                          {items.map((i, idx) => (
                            <span key={idx} title={i.done === true ? 'Provedeno' : 'Neodškrtnuto — nepočítá se jako provedené'} className="text-xs font-bold" style={{ padding: '2px 7px', borderRadius: 7, background: i.done === true ? '#e8fde8' : '#f8fafc', border: `1px solid ${i.done === true ? '#b6dccb' : '#e5e7eb'}`, color: i.done === true ? '#0f1a14' : '#9ca3af' }}>
                              {i.done === true ? '✓ ' : ''}{i.custom ? '✎ ' : ''}{i.label}{i.note ? ` — ${i.note}` : ''}
                            </span>
                          ))}
                        </div>
                      )}
                      {l.description && <div className="text-xs" style={{ color: '#1a2e22', whiteSpace: 'pre-wrap' }}><b>Zadání:</b> {l.description}</div>}
                      {l.technician_report && <div className="text-xs mt-0.5 p-1 rounded" style={{ color: '#0f1a14', whiteSpace: 'pre-wrap', background: '#fffbeb' }}><b>Technik:</b> {l.technician_report}</div>}
                      {inv.length > 0 && <div className="text-xs mt-0.5" style={{ color: '#2563eb' }}>📎 {inv.map(r => `${r.invoice_number || r.file_name || 'doklad'} (${fmtMoney(r.amount)})`).join(', ')}</div>}
                      {items.length === 0 && !l.description && !l.technician_report && <span style={{ color: '#9ca3af' }}>—</span>}
                    </td>
                    <td style={{ padding: '8px 10px', whiteSpace: 'nowrap', color: '#1a2e22' }}>{l.performed_by || '—'}</td>
                    <td style={{ padding: '8px 10px', whiteSpace: 'nowrap', fontWeight: 700, color: '#0f1a14' }}>{fmtMoney(cost)}</td>
                    <td style={{ padding: '8px 6px' }}>{onEdit && <button onClick={() => onEdit(l)} className="text-xs font-bold cursor-pointer" style={{ background: 'none', border: 'none', color: '#2563eb' }} title="Upravit záznam">✎</button>}</td>
                  </tr>
                )
              })}
            </tbody>
          </table>
          {completed.length > shown.length && <button onClick={() => setShowAll(true)} className="text-xs font-bold cursor-pointer mt-2" style={{ background: 'none', border: 'none', color: '#2563eb' }}>Zobrazit všech {completed.length} záznamů</button>}
        </div>
      )}
    </Card>
  )
}
