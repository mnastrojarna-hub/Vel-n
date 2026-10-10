import { useMemo, useState } from 'react'
import Card from '../ui/Card'
import { TASK_BY_ID, SERVICE_GROUPS } from './serviceCatalog'
import { SERVICE_LABEL_TO_ID } from './motoActionConstants'
import { SERVICE_TYPE_LABELS, LOG_TYPE_LABELS, fmtDate, fmtKm, fmtMoney, isLogCompleted, effectiveCost } from '../../lib/serviceBook'

/**
 * Servisní kniha motorky: chronologie DOKONČENÝCH servisů se zadáním, zprávou technika, úkony (✓ = provedeno),
 * km, technikem, cenou a doklady. Filtry: text, úkon (jen záznamy, kde byl proveden), rok.
 * Zdroj: maintenance_log (items s klíči z katalogu; starší záznamy párujeme podle štítku / aliasu).
 * Props: logs, unitLabel, invoicesByLog { logId: [maintenance_invoices] }, onEdit(log), canEdit(log) — běžný účet neupravuje cizí dokončené servisy
 */
const TYPE_KEYS = { oil_change: ['oil_change', 'oil_filter'], tire_change: ['tire_front', 'tire_rear'], full_service: ['full_service'], winter_service: ['full_service'] }
const logDate = l => (l.completed_date || l.service_date || l.created_at || '').slice(0, 10)
// Zrcadlo DB `_service_done_task_keys`: provedené = odškrtnuté + implies (tranzitivně); legacy `type` / popis
// „výměna oleje“ jen u záznamů bez checklistu (popis je zadání, ne provedení).
export function doneKeysOf(l) {
  const items = Array.isArray(l.items) ? l.items : []
  const keys = new Set()
  const add = (k) => { if (!k || keys.has(k)) return; keys.add(k); for (const imp of TASK_BY_ID[k]?.implies || []) add(imp) }
  for (const it of items) { if (it?.done === true) add(it.key || SERVICE_LABEL_TO_ID[it.label]) }
  const hasChecklist = items.some(it => it?.key || (it && 'done' in it))
  if (!hasChecklist) {
    for (const k of TYPE_KEYS[l.type] || []) add(k)
    const d = l.description || ''
    if (/v[yý]m[eě]n\w*\s+(motorov\w+\s+)?olej/iu.test(d) && !/olej\w*\s+(v|ve|do)\s+(kardan|rozvodov|vidlic|p[rř]evodov|tlumi[cč])/iu.test(d) && !/(nen[ií]\s|zda\s|jestli\s|zkontrol|kontrol)/iu.test(d)) add('oil_change')
  }
  return keys
}
const sel = { padding: '5px 8px', background: '#f1faf7', border: '1px solid #d4e8e0', fontSize: 13, borderRadius: 50 }

export default function ServiceBookCard({ logs, unitLabel = 'km', invoicesByLog = {}, onEdit, canEdit }) {
  const [q, setQ] = useState('')
  const [task, setTask] = useState('')
  const [year, setYear] = useState('')
  const [showAll, setShowAll] = useState(false)
  const completed = useMemo(() => [...(logs || [])].filter(isLogCompleted).sort((a, b) => logDate(b).localeCompare(logDate(a))).map(l => ({ ...l, _keys: doneKeysOf(l) })), [logs])
  const openCount = (logs || []).length - completed.length
  const usedKeys = useMemo(() => { const s = new Set(); completed.forEach(l => l._keys.forEach(k => s.add(k))); return s }, [completed])
  const years = useMemo(() => [...new Set(completed.map(l => logDate(l).slice(0, 4)).filter(Boolean))].sort().reverse(), [completed])
  const norm = s => (s || '').toLowerCase()
  const filtered = completed.filter(l => (!task || l._keys.has(task)) && (!year || logDate(l).startsWith(year)) &&
    (!q || norm(l.description).includes(norm(q)) || norm(l.technician_report).includes(norm(q)) || norm(l.performed_by).includes(norm(q)) || (l.items || []).some(i => norm(i?.label).includes(norm(q)) || norm(i?.note).includes(norm(q)))))
  const shown = showAll || task || year || q ? filtered : filtered.slice(0, 12)
  const totalCost = filtered.reduce((s, l) => s + effectiveCost(l), 0)

  return (
    <Card>
      <div className="flex items-center justify-between mb-1 flex-wrap gap-2">
        <h3 className="text-sm font-extrabold uppercase tracking-widest" style={{ color: '#1a2e22' }}>Servisní kniha — historie</h3>
        <span className="text-xs" style={{ color: '#6b7280' }}>{filtered.length}{filtered.length !== completed.length ? ` z ${completed.length}` : ''} dokončených servisů · náklady {fmtMoney(totalCost)}{openCount > 0 ? ` · ${openCount} otevřených (výše)` : ''}</span>
      </div>
      <div className="flex items-center gap-2 flex-wrap mb-3">
        <input value={q} onChange={e => setQ(e.target.value)} placeholder="Hledat v zadání, zprávě, úkonech, technikovi…" className="text-sm outline-none" style={{ ...sel, width: 280, maxWidth: '100%' }} />
        <select value={task} onChange={e => setTask(e.target.value)} className="text-sm outline-none" style={sel}>
          <option value="">Všechny úkony</option>
          {SERVICE_GROUPS.map(g => { const its = g.items.filter(i => usedKeys.has(i.id)); return its.length ? <optgroup key={g.key} label={g.label}>{its.map(i => <option key={i.id} value={i.id}>{i.label}</option>)}</optgroup> : null })}
        </select>
        <select value={year} onChange={e => setYear(e.target.value)} className="text-sm outline-none" style={sel}>
          <option value="">Všechny roky</option>{years.map(y => <option key={y} value={y}>{y}</option>)}
        </select>
        {(q || task || year) && <button onClick={() => { setQ(''); setTask(''); setYear('') }} className="text-xs font-bold cursor-pointer" style={{ background: 'none', border: 'none', color: '#dc2626' }}>zrušit filtry</button>}
      </div>

      {completed.length === 0 ? <p style={{ color: '#1a2e22', fontSize: 13 }}>Žádný dokončený servis — kniha se plní po dokončení servisu.</p>
      : filtered.length === 0 ? <p style={{ color: '#6b7280', fontSize: 13 }}>Žádný záznam neodpovídá filtru.</p> : (
        <div className="overflow-x-auto mg-stack-wrap">
          <table className="w-full border-collapse mg-stack" style={{ fontSize: 13 }}>
            <thead><tr style={{ background: '#f1faf7', borderBottom: '1px solid #d4e8e0' }}>
              {['Datum', unitLabel, 'Typ', 'Úkony · zadání · zpráva technika', 'Technik', 'Cena', ''].map((h, i) => <th key={i} className="text-left text-xs font-extrabold uppercase tracking-wide" style={{ padding: '8px 10px', color: '#1a2e22' }}>{h}</th>)}
            </tr></thead>
            <tbody>
              {shown.map(l => {
                const items = Array.isArray(l.items) ? l.items.filter(i => i?.label) : []
                const inv = invoicesByLog[l.id] || []
                return (
                  <tr key={l.id} style={{ borderBottom: '1px solid #e5efe9', verticalAlign: 'top' }}>
                    <td style={{ padding: '8px 10px', whiteSpace: 'nowrap', fontWeight: 700, color: '#0f1a14' }}>{fmtDate(logDate(l))}{l.is_urgent && <div className="text-xs font-bold" style={{ color: '#dc2626' }}>URGENT</div>}</td>
                    <td style={{ padding: '8px 10px', whiteSpace: 'nowrap', color: '#1a2e22' }}>{fmtKm(l.km_at_service, '')}{l.km_auto && <span title="automaticky ze stavu tachometru" style={{ color: '#9ca3af', fontSize: 10 }}> auto</span>}</td>
                    <td style={{ padding: '8px 10px', whiteSpace: 'nowrap', color: '#1a2e22' }}>{LOG_TYPE_LABELS[l.type] || SERVICE_TYPE_LABELS[l.service_type] || 'Servis'}</td>
                    <td className="mg-stack-full" style={{ padding: '8px 10px', color: '#0f1a14', minWidth: 260 }}>
                      {items.length > 0 && <div className="flex flex-wrap gap-1 mb-1">{items.map((i, idx) => (
                        <span key={idx} title={i.done === true ? 'Provedeno' : 'Neodškrtnuto — nepočítá se jako provedené'} className="text-xs font-bold" style={{ padding: '2px 7px', borderRadius: 7, background: i.done === true ? (task && (i.key || SERVICE_LABEL_TO_ID[i.label]) === task ? '#74FB71' : '#e8fde8') : '#f8fafc', border: `1px solid ${i.done === true ? '#b6dccb' : '#e5e7eb'}`, color: i.done === true ? '#0f1a14' : '#9ca3af' }}>
                          {i.done === true ? '✓ ' : ''}{i.custom ? '✎ ' : ''}{i.label}{i.added_by ? ' (navíc)' : ''}{i.done_legacy ? ' (historicky)' : ''}{i.note ? ` — ${i.note}` : ''}
                        </span>))}</div>}
                      {l.description && <div className="text-xs" style={{ color: '#1a2e22', whiteSpace: 'pre-wrap' }}><b>Zadání:</b> {l.description}</div>}
                      {l.technician_report && <div className="text-xs mt-0.5 p-1 rounded" style={{ color: '#0f1a14', whiteSpace: 'pre-wrap', background: '#fffbeb' }}><b>Technik:</b> {l.technician_report}</div>}
                      {inv.length > 0 && <div className="text-xs mt-0.5" style={{ color: '#2563eb' }}>📎 {inv.map(r => `${r.invoice_number || r.file_name || 'doklad'} (${fmtMoney(r.amount)})`).join(', ')}</div>}
                      {items.length === 0 && !l.description && !l.technician_report && <span style={{ color: '#9ca3af' }}>—</span>}
                    </td>
                    <td style={{ padding: '8px 10px', whiteSpace: 'nowrap', color: '#1a2e22' }}>{l.performed_by || '—'}</td>
                    <td style={{ padding: '8px 10px', whiteSpace: 'nowrap', fontWeight: 700, color: '#0f1a14' }}>{fmtMoney(effectiveCost(l))}{Number(l.invoiced_amount) > 0 && Number(l.cost) > 0 && Number(l.cost) !== Number(l.invoiced_amount) ? <div className="text-xs font-normal" style={{ color: '#9ca3af' }}>odhad {fmtMoney(l.cost)}</div> : null}</td>
                    <td style={{ padding: '8px 6px' }}>{onEdit && (!canEdit || canEdit(l)) && <button onClick={() => onEdit(l)} className="text-xs font-bold cursor-pointer max-md:text-sm max-md:rounded-btn max-md:px-4 max-md:py-2 max-md:!bg-[#dbeafe]" style={{ background: 'none', border: 'none', color: '#2563eb' }} title="Upravit záznam">✎<span className="md:hidden"> Upravit</span></button>}</td>
                  </tr>
                )
              })}
            </tbody>
          </table>
          {filtered.length > shown.length && <button onClick={() => setShowAll(true)} className="text-xs font-bold cursor-pointer mt-2" style={{ background: 'none', border: 'none', color: '#2563eb' }}>Zobrazit všech {filtered.length} záznamů</button>}
        </div>
      )}
    </Card>
  )
}
